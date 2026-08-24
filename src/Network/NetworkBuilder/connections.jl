"Typed row stored by [`NetworkTopology`](@ref)."
const TopologyConnection = @NamedTuple{
    node::Symbol,
    bus::Int,
    element::Symbol,
    side::Int,
    terminal::Int,
    domain::Int
}

"Required fields of one user-supplied topology row."
const _TOPOLOGY_ROW_FIELDS = (:node, :element, :side, :terminal)

"Describe one externally connected side of an element."
struct _PortDescription
    side::Int
    terminals::Int
    domain::Int
end

function _two_port_description(element::P.Element, domain::Int)
    return (
        _PortDescription(1, P.nip(element), domain),
        _PortDescription(2, P.nop(element), domain)
    )
end

function _single_port_description(element::P.Element, domain::Int)
    (_PortDescription(1, P.nip(element), domain),)
end

function _converter_port_description(element::P.Element)
    (
        _PortDescription(1, P.nip(element), 2),
        _PortDescription(2, P.nop(element), 1)
    )
end

function _port_descriptions(element::P.Element{<:P.Source})
    _single_port_description(element, P.pmtype(element) == "gen" ? 1 : 2)
end

function _port_descriptions(element::P.Element{<:P.Impedance})
    _two_port_description(element, P.is_three_phase(element) ? 1 : 0)
end

_port_descriptions(element::P.Element{<:P.Transformer}) = _two_port_description(element, 1)

function _port_descriptions(element::P.Element{<:P.Transmission_line})
    _two_port_description(element, P.is_three_phase(element) ? 1 : 0)
end

function _port_descriptions(element::P.Element{<:P.AbstractConverter})
    _converter_port_description(element)
end

_port_descriptions(element::P.Element{<:P.Converter}) = _converter_port_description(element)

function _port_descriptions(element::P.Element{<:P.SynchronousMachine})
    _single_port_description(element, 1)
end

function _port_descriptions(element::P.Element{<:P.InductionMachine})
    _single_port_description(element, 1)
end

function _port_descriptions(element::P.Element)
    throw(
        ArgumentError(
        "no NetworkBuilder port description is defined for " *
        "$(typeof(element.element_model))",
    ),
    )
end

function _port_description(element::P.Element, side::Int)
    ports = _port_descriptions(element)
    index = findfirst(port -> port.side == side, ports)
    index === nothing && throw(
        ArgumentError(
        "element $(typeof(element.element_model)) has no externally connected side $side",
    ),
    )
    return ports[index]
end

function _validate_topology_row(row)
    row isa NamedTuple || throw(
        ArgumentError(
        "each connection must be a named tuple with fields " *
        "(node, element, side, terminal); received $(typeof(row))",
    ),
    )
    Set(propertynames(row)) == Set(_TOPOLOGY_ROW_FIELDS) || throw(
        ArgumentError(
        "connection fields must be exactly " *
        "(node, element, side, terminal); received $(propertynames(row))",
    ),
    )
    row.node isa Symbol || throw(ArgumentError("connection node must be a Symbol"))
    row.element isa Symbol || throw(ArgumentError("connection element must be a Symbol"))
    row.side isa Integer || throw(ArgumentError("connection side must be an integer"))
    row.terminal isa Integer ||
        throw(ArgumentError("connection terminal must be an integer"))
    row.side > 0 || throw(ArgumentError("connection side must be positive"))
    row.terminal > 0 || throw(ArgumentError("connection terminal must be positive"))
    return (
        node = row.node,
        element = row.element,
        side = Int(row.side),
        terminal = Int(row.terminal)
    )
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

function _resolved_topology_domains(elements::NamedTuple, rows)
    sets = _DisjointSet{Tuple{Symbol, Int}}()
    node_sides = Dict{Symbol, Vector{Tuple{Symbol, Int}}}()
    element_sides = Dict{Symbol, Vector{Tuple{Symbol, Int}}}()

    for row in rows
        side = (row.element, row.side)
        _find!(sets, side)
        push!(get!(node_sides, row.node, Tuple{Symbol, Int}[]), side)
        push!(get!(element_sides, row.element, Tuple{Symbol, Int}[]), side)
    end

    for sides in values(node_sides)
        first_side = first(sides)
        for side in Iterators.drop(sides, 1)
            _union!(sets, first_side, side)
        end
    end

    # A one-conductor impedance or line has no intrinsic AC/DC marker. Its two
    # physical sides must nevertheless belong to one electrical domain.
    for (element_name, sides) in element_sides
        ports = _port_descriptions(elements[element_name])
        all(iszero(port.domain) for port in ports) || continue
        first_side = first(sides)
        for side in Iterators.drop(sides, 1)
            _union!(sets, first_side, side)
        end
    end

    fixed_domains = Dict{Tuple{Symbol, Int}, Set{Int}}()
    root_nodes = Dict{Tuple{Symbol, Int}, Set{Symbol}}()
    for row in rows
        root = _find!(sets, (row.element, row.side))
        iszero(row.domain) || push!(get!(fixed_domains, root, Set{Int}()), row.domain)
        push!(get!(root_nodes, root, Set{Symbol}()), row.node)
    end

    root_domain = Dict{Tuple{Symbol, Int}, Int}()
    for (root, nodes) in root_nodes
        domains = get(fixed_domains, root, Set{Int}())
        length(domains) <= 1 || throw(
            ArgumentError(
            "topology containing node :$(first(sort!(collect(nodes)))) " *
            "mixes electrical domains 1 and 2",
        ),
        )
        # An otherwise unclassified one-conductor passive network retains the
        # established DC interpretation used by the power-flow conversion.
        root_domain[root] = isempty(domains) ? 2 : only(domains)
    end

    return [merge(row, (; domain = root_domain[_find!(sets, (row.element, row.side))]))
            for row in rows]
end

"""
$(TYPEDEF)

Store the node incidence relation used by NetworkBuilder calculations.

Each stored row identifies a node, its power-flow bus, an element side and
terminal, and the electrical domain. Construct a topology through
[`define`](@ref) or `NetworkTopology(elements, connections)`.

$(TYPEDFIELDS)
"""
struct NetworkTopology
    "Typed node–element incidence rows."
    connections::Table{TopologyConnection,
        1,
        NamedTuple{
            (:node, :bus, :element, :side, :terminal, :domain),
            Tuple{Vector{Symbol}, Vector{Int}, Vector{Symbol},
                Vector{Int}, Vector{Int}, Vector{Int}}
        }}
end

"""
    NetworkTopology(elements, connections)

Construct the topology of a materialized network from named connection rows.

# Arguments

- `elements`: Named tuple of ordinary PowerImpedance elements.
- `connections`: Tuple or vector of named tuples with the fields `node`,
  `element`, `side`, and `terminal`.

# Returns

- A `NetworkTopology` with typed rows and deterministic bus numbering.

# Errors

- Throws `ArgumentError` for malformed rows, missing elements, invalid ports,
  duplicate terminal assignments, or nodes that mix AC and DC terminals.
"""
function NetworkTopology(elements::NamedTuple, connections::Union{Tuple, AbstractVector})
    rows = NamedTuple[]
    terminal_nodes = Dict{Tuple{Symbol, Int, Int}, Symbol}()

    for supplied in connections
        row = _validate_topology_row(supplied)
        haskey(elements, row.element) || throw(
            ArgumentError("connection references missing element :$(row.element)"),
        )
        element = elements[row.element]
        element isa P.Element || throw(
            ArgumentError("NetworkBuilder element :$(row.element) must be an Element"),
        )
        element.connection || continue

        port = _port_description(element, row.side)
        row.terminal <= port.terminals || throw(
            ArgumentError(
            "element :$(row.element) side $(row.side) has $(port.terminals) " *
            "terminal(s); received terminal $(row.terminal)",
        ),
        )
        terminal_key = (row.element, row.side, row.terminal)
        if haskey(terminal_nodes, terminal_key)
            throw(
                ArgumentError(
                "element :$(row.element) side $(row.side) terminal " *
                "$(row.terminal) is assigned more than once",
            ),
            )
        end
        terminal_nodes[terminal_key] = row.node

        push!(rows, merge(row, (; domain = port.domain)))
    end
    rows = _resolved_topology_domains(elements, rows)

    side_sets = Dict(
        1 => _DisjointSet{Tuple{Symbol, Int}}(),
        2 => _DisjointSet{Tuple{Symbol, Int}}()
    )
    node_sides = Dict{Tuple{Int, Symbol}, Vector{Tuple{Symbol, Int}}}()
    for row in rows
        side_key = (row.element, row.side)
        _find!(side_sets[row.domain], side_key)
        push!(get!(node_sides, (row.domain, row.node), Tuple{Symbol, Int}[]), side_key)
    end

    for ((domain, _), sides) in node_sides
        isempty(sides) && continue
        first_side = first(sides)
        for side in Iterators.drop(sides, 1)
            _union!(side_sets[domain], first_side, side)
        end
    end

    ground_roots = Set{Tuple{Int, Tuple{Symbol, Int}}}()
    for row in rows
        P.isgroundnet(row.node) || continue
        root = _find!(side_sets[row.domain], (row.element, row.side))
        push!(ground_roots, (row.domain, root))
    end

    bus_by_root = Dict{Tuple{Int, Tuple{Symbol, Int}}, Int}()
    next_bus = Dict(1 => 1, 2 => 1)
    stored = Table(
        node = Symbol[],
        bus = Int[],
        element = Symbol[],
        side = Int[],
        terminal = Int[],
        domain = Int[]
    )
    for row in rows
        root = _find!(side_sets[row.domain], (row.element, row.side))
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
        push!(stored, (; row.node, bus, row.element, row.side, row.terminal, row.domain))
    end
    return NetworkTopology(stored)
end

"Return all nongrounded AC topology rows."
function acconnections(topology::NetworkTopology)
    return filter(row -> row.domain == 1 && row.bus != 0, topology.connections)
end

"Return all nongrounded DC topology rows."
function dcconnections(topology::NetworkTopology)
    return filter(row -> row.domain == 2 && row.bus != 0, topology.connections)
end

"Return the topology rows of one element in electrical and terminal order."
function sortedcomponentconnections(
        topology::NetworkTopology,
        component::Symbol;
        kwargs...
)
    return sortedcomponentconnections(topology.connections, component; kwargs...)
end

function sortedcomponentconnections(
        connections::Table,
        component::Symbol;
        withground::Bool = false,
        acfirst::Bool = true
)
    selected = filter(row -> row.element == component, connections)
    withground || filter!(row -> row.bus != 0, selected)
    order(row) = acfirst ? (row.domain, row.side, row.terminal) :
                 (row.side, row.terminal)
    sort!(selected; by = order)
    return selected
end

"Return the Classic network pin name associated with a side and terminal."
pin_name(side::Int, terminal::Int) = Symbol("$(side).$(terminal)")

"Convert one topology row to the Classic network pin representation."
connection_to_classic_pin(row) = (row.element, pin_name(row.side, row.terminal))
