"""
$(TYPEDEF)

Connect named component ports to an AC or DC bus.

$(TYPEDFIELDS)
"""
struct Bus
    "Bus name. AC nets append their terminal labels to this name."
    name::Symbol
    "Component and port pairs in declaration order."
    ports::Vector{Tuple{Symbol, Symbol}}
    "Declared electrical domain, or `nothing` to infer it from the ports."
    domain::Union{Nothing, P.AbstractDomain}
end

"""
$(TYPEDSIGNATURES)

Construct a bus that expands into one net per electrical coordinate.

# Arguments

- `name`: Bus name. Names starting with `gnd` connect to ground.
- `ports`: Ordered `(component, port)` pairs.
- `domain`: `ACDQ`, `ACABC`, `DC_CM`, or `nothing` (default). An inferred AC bus
  uses dq coordinates when any attached port declares `ACDQ`. Otherwise it uses abc.

# Returns

- A `Bus` declaration for [`define`](@ref). AC nets append `d`, `q` or `a`, `b`, `c`
  to `name`. A DC net retains `name`.

# Errors

- Throws `ArgumentError` during topology construction for mixed AC/DC ports or
  an `ACDQ` port on an explicitly declared `ACABC` bus.

# Examples

```julia
Bus(:Bus7; ports = ((:grid, :ac), (:line, :side1)), domain = ACDQ)
```
"""
Bus(name::Symbol; ports, domain = nothing) = Bus(name, collect(ports), domain)

"""
$(TYPEDEF)

Connect individual component terminals to one named net.

$(TYPEDFIELDS)
"""
struct Net
    "Net name. Names starting with `gnd` connect to ground."
    name::Symbol
    "Component, port and terminal triples in declaration order."
    terminals::Vector{Tuple{Symbol, Symbol, Symbol}}
    "Declared electrical domain, or `nothing` to infer it from the ports."
    domain::Union{Nothing, P.AbstractDomain}
end

"""
$(TYPEDSIGNATURES)

Construct a net joining individual terminals in their declared coordinates.

# Arguments

- `name`: Net name. Names starting with `gnd` connect to ground.
- `terminals`: Ordered `(component, port, terminal)` triples.
- `domain`: `ACDQ`, `ACABC`, `DC_CM`, or `nothing` (default).

# Returns

- A `Net` declaration for [`define`](@ref).

# Errors

- Throws `ArgumentError` during topology construction for incompatible domains or
  terminal labels. An `ACABC` port uses `a`, `b`, `c` labels on a `Net`.

# Examples

```julia
Net(:DC1; terminals = ((:grid, :dc, :dc), (:line, :side1, :dc)))
```
"""
Net(name::Symbol; terminals, domain = nothing) = Net(name, collect(terminals), domain)

"""Typed row stored by [`NetworkTopology`](@ref)."""
const TopologyConnection = @NamedTuple{
    net::Symbol,
    bus::Int,
    component::Symbol,
    port::Symbol,
    terminal::Symbol,
    domain::Int,
    frame::Symbol
}

_domain_number(domain::P.AbstractDomain) = P.isac(domain) ? 1 : 2
_frame(::P.ACDQDomain) = :dq
_frame(::P.ACABCDomain) = :abc
_frame(::P.DCDomain) = :dc

function _element_call(f, name::Symbol)
    try
        return f()
    catch error
        error isa InterruptException && rethrow()
        throw(ArgumentError("element :$name: $(sprint(showerror, error))"))
    end
end

function _port(elements, name, port)
    haskey(elements, name) ||
        throw(ArgumentError("topology references missing element :$name"))
    ports = _element_call(name) do
        P.electricalconnections(elements[name])
    end
    haskey(ports, port) ||
        throw(ArgumentError("element :$name has no port :$port"))
    return ports[port]
end

function _connection_domain(name, ports, declared)
    domains = unique(_domain_number(port.domain) for port in ports)
    length(domains) == 1 ||
        throw(ArgumentError("bus or net :$name mixes AC and DC ports"))
    if declared !== nothing
        only(domains) == _domain_number(declared) ||
            throw(ArgumentError("bus or net :$name has an incompatible domain"))
        if declared === P.ACABC && any(port -> port.domain === P.ACDQ, ports)
            throw(ArgumentError("bus or net :$name attaches an ACDQ port to ACABC"))
        end
        return declared
    end
    only(domains) == 2 && return P.DC_CM
    return any(port -> port.domain === P.ACDQ, ports) ? P.ACDQ : P.ACABC
end

function _expand!(rows, elements, bus::Bus, excluded)
    attached = filter(pair -> first(pair) ∉ excluded, bus.ports)
    isempty(attached) && return rows
    ports = [_port(elements, name, port) for (name, port) in attached]
    domain = _connection_domain(bus.name, ports, bus.domain)
    labels = P.terminals(domain)
    for terminal in labels
        net = P.isdc(domain) ? bus.name : Symbol(bus.name, terminal)
        for (name, port) in attached
            push!(rows, (; net, component = name, port, terminal,
                domain = _domain_number(domain), frame = _frame(domain)))
        end
    end
    return rows
end

function _expand!(rows, elements, net::Net, excluded)
    attached = filter(triple -> first(triple) ∉ excluded, net.terminals)
    isempty(attached) && return rows
    ports = [_port(elements, name, port) for (name, port, _) in attached]
    domain = _connection_domain(net.name, ports, net.domain)
    for ((name, port, terminal), description) in zip(attached, ports)
        terminal in description.terminals || throw(ArgumentError(
            "net :$(net.name): element :$name port :$port has no terminal :$terminal"))
        terminal in P.terminals(domain) || throw(ArgumentError(
            "net :$(net.name): terminal :$terminal does not use $(_frame(domain))"))
        push!(rows, (; net = net.name, component = name, port, terminal,
            domain = _domain_number(domain), frame = _frame(domain)))
    end
    return rows
end

mutable struct _DisjointSet{T}
    parent::Dict{T, T}
end

_DisjointSet{T}() where {T} = _DisjointSet(Dict{T, T}())

function _find!(sets::_DisjointSet{T}, item::T) where {T}
    parent = get!(sets.parent, item, item)
    if parent != item
        sets.parent[item] = _find!(sets, parent)
    end
    return sets.parent[item]
end

function _union!(sets::_DisjointSet{T}, left::T, right::T) where {T}
    left_root = _find!(sets, left)
    right_root = _find!(sets, right)
    left_root == right_root || (sets.parent[right_root] = left_root)
    return nothing
end

"""
$(TYPEDEF)

Store rows for net incidence and the order of admittance rows for each component.

Each row identifies a net, its power-flow bus, a named component port and terminal,
its electrical domain (1 AC, 2 DC), and its coordinate frame (`:dq`, `:abc`, `:dc`).
Construct a topology through [`define`](@ref) or `NetworkTopology(elements, topology)`.

$(TYPEDFIELDS)
"""
struct NetworkTopology
    "Typed net-component incidence rows."
    connections::@Table{net::Symbol, bus::Int, component::Symbol, port::Symbol,
        terminal::Symbol, domain::Int, frame::Symbol}
    "Component admittance row labels in the topology's coordinates."
    admittance_orders::Dict{Symbol, Vector{Tuple{Symbol, Symbol}}}
end

"""
$(TYPEDSIGNATURES)

Expand bus and net declarations with deterministic bus numbering per domain.

# Arguments

- `elements`: Named tuple of component models.
- `connections`: Tuple or vector of `Bus` and `Net` declarations.
- `exclude`: Component names to omit. Default: `()`.

# Returns

- A `NetworkTopology`. A port touching a ground net belongs to bus 0.
  Other buses are numbered by their first row, separately for AC and DC.

# Errors

- Throws `ArgumentError` for missing elements or ports, duplicate terminal assignments,
  incompatible electrical domains, or different AC frames within a component.
"""
function NetworkTopology(elements::NamedTuple, connections::Union{Tuple, AbstractVector};
        exclude = ())
    excluded = _excluded_names(elements, exclude)
    rows = NamedTuple[]
    for supplied in connections
        _expand!(rows, elements, supplied, excluded)
    end
    rows = _resolved_topology_domains(rows)
    assigned = Set{Tuple{Symbol, Symbol, Symbol}}()
    frames = Dict{Symbol, Symbol}()
    for row in rows
        key = (row.component, row.port, row.terminal)
        key ∈ assigned && throw(ArgumentError(
            "element :$(row.component) port :$(row.port) terminal :$(row.terminal) " *
            "is assigned more than once"))
        push!(assigned, key)
        row.domain == 1 || continue
        frame = get!(frames, row.component, row.frame)
        frame == row.frame || throw(ArgumentError(
            "element :$(row.component) uses both $frame and $(row.frame) AC frames"))
    end

    port_sets = Dict(1 => _DisjointSet{Tuple{Symbol, Symbol}}(),
        2 => _DisjointSet{Tuple{Symbol, Symbol}}())
    net_ports = Dict{Tuple{Int, Symbol}, Vector{Tuple{Symbol, Symbol}}}()
    for row in rows
        key = (row.component, row.port)
        _find!(port_sets[row.domain], key)
        push!(get!(net_ports, (row.domain, row.net), Tuple{Symbol, Symbol}[]), key)
    end
    for ((domain, _), ports) in net_ports
        for port in Iterators.drop(ports, 1)
            _union!(port_sets[domain], first(ports), port)
        end
    end
    ground_roots = Set{Tuple{Int, Tuple{Symbol, Symbol}}}()
    for row in rows
        P.isgroundnet(row.net) || continue
        root = _find!(port_sets[row.domain], (row.component, row.port))
        push!(ground_roots, (row.domain, root))
    end

    bus_by_root = Dict{Tuple{Int, Tuple{Symbol, Symbol}}, Int}()
    next_bus = Dict(1 => 1, 2 => 1)
    stored = Table(TopologyConnection[])
    for row in rows
        root = _find!(port_sets[row.domain], (row.component, row.port))
        root_key = (row.domain, root)
        bus = if root_key in ground_roots
            0
        else
            get!(bus_by_root, root_key) do
                assigned = next_bus[row.domain]
                next_bus[row.domain] = assigned + 1
                assigned
            end
        end
        push!(stored, (; row.net, bus, row.component, row.port, row.terminal,
            row.domain, row.frame))
    end
    orders = Dict{Symbol, Vector{Tuple{Symbol, Symbol}}}()
    for name in unique(stored.component)
        model = elements[name]
        orders[name] = _element_call(name) do
            frame = get(frames, name, :dc)
            _check_frame(model, frame)
            _frame_order(model, frame)
        end
    end
    return NetworkTopology(stored, orders)
end

_check_frame(model, frame) = nothing

function _check_frame(model::P.Transformer, frame)
    if model.conductors == 3 && model.organization == :ΔY && frame != :dq
        throw(ArgumentError(
            "three-phase :ΔY transformer requires dq coordinates; " *
            "connect it to an ACDQ bus (domain = ACDQ on the Bus, " *
            "or an ACDQ port on that bus)"))
    end
    return nothing
end

function _frame_order(model, frame)
    ports = P.electricalconnections(model)
    order = Tuple{Symbol, Symbol}[]
    for (port, terminal) in P.admittance_order(model)
        if frame == :dq && ports[port].domain === P.ACABC
            terminal == first(ports[port].terminals) || continue
            append!(order, ((port, :d), (port, :q)))
        else
            push!(order, (port, terminal))
        end
    end
    return order
end

"""Return all nongrounded AC topology rows."""
acconnections(topology::NetworkTopology) =
    filter(row -> row.domain == 1 && row.bus != 0, topology.connections)

"""Return all nongrounded DC topology rows."""
dcconnections(topology::NetworkTopology) =
    filter(row -> row.domain == 2 && row.bus != 0, topology.connections)

"""Return one component's rows in its admittance order, optionally sorting AC first."""
function sortedcomponentconnections(topology::NetworkTopology, component::Symbol; kwargs...)
    return sortedcomponentconnections(topology.connections, component;
        admittance_order = get(topology.admittance_orders, component,
            Tuple{Symbol, Symbol}[]), kwargs...)
end

function sortedcomponentconnections(connections::Table, component::Symbol;
        admittance_order, withground::Bool = false, acfirst::Bool = false)
    selected = filter(row -> row.component == component, connections)
    withground || filter!(row -> row.bus != 0, selected)
    rank(row) = something(findfirst(==((row.port, row.terminal)), admittance_order))
    order(row) = acfirst ? (row.domain, rank(row)) : (rank(row),)
    sort!(selected; by = order)
    return selected
end

function _resolved_topology_domains(rows)
    sets = _DisjointSet{Tuple{Symbol, Symbol}}()
    net_ports = Dict{Symbol, Vector{Tuple{Symbol, Symbol}}}()
    for row in rows
        key = (row.component, row.port)
        _find!(sets, key)
        push!(get!(net_ports, row.net, Tuple{Symbol, Symbol}[]), key)
    end
    for ports in values(net_ports)
        for port in Iterators.drop(ports, 1)
            _union!(sets, first(ports), port)
        end
    end
    domains = Dict{Tuple{Symbol, Symbol}, Set{Int}}()
    frames = Dict{Tuple{Symbol, Symbol}, Set{Symbol}}()
    for row in rows
        root = _find!(sets, (row.component, row.port))
        iszero(row.domain) && continue
        push!(get!(domains, root, Set{Int}()), row.domain)
        push!(get!(frames, root, Set{Symbol}()), row.frame)
    end
    return map(rows) do row
        root = _find!(sets, (row.component, row.port))
        fixed = get(domains, root, Set{Int}())
        length(fixed) <= 1 || throw(ArgumentError(
            "topology containing net :$(row.net) mixes AC and DC ports"))
        fixed_frames = get(frames, root, Set{Symbol}())
        length(fixed_frames) <= 1 || throw(ArgumentError(
            "topology containing net :$(row.net) mixes AC frames"))
        # An otherwise unclassified one-conductor passive network retains the
        # established DC interpretation used by the power-flow conversion.
        domain = isempty(fixed) ? 2 : only(fixed)
        frame = isempty(fixed_frames) ? :dc : only(fixed_frames)
        merge(row, (; domain, frame))
    end
end

function _excluded_names(elements, exclude)
    for name in exclude
        haskey(elements, name) ||
            throw(ArgumentError("excluded element :$name is missing"))
    end
    return Tuple(name for name in keys(elements)
        if name ∈ exclude)
end
