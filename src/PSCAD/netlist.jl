"""
$(TYPEDEF)

Identify one nongrounded topology bus independently of its power-flow index.

$(TYPEDFIELDS)
"""
struct BusKey
    "Electrical domain: 1 for AC, 2 for DC."
    domain::Int
    "Bus index assigned by NetworkTopology."
    index::Int
end

"""
$(TYPEDEF)

Store a bus and its optional solved voltage. AC bases are phase RMS \\[kV\\];
DC bases are pole-to-ground \\[kV\\]. With a solved power flow and input data,
`pf_index` selects the base from the PowerModels bus record. All bus bases
must agree. Without a solution, use the declared network base.

$(TYPEDFIELDS)
"""
struct Bus
    "Domain and topology index."
    key::BusKey
    "Unique PSCAD identifier."
    name::String
    "Distinct network nets in first-seen order."
    nets::Vector{Symbol}
    "Representation: `:ac3_dq`, `:ac3_abc`, or `:dc`."
    kind::Symbol
    "AC phase RMS or DC pole-to-ground voltage base \\[kV\\]."
    base_kV::Float64
    "Solved voltage magnitude \\[dimensionless\\], when available."
    vm_pu::Union{Nothing, Float64}
    "Solved AC voltage angle \\[rad\\], when available."
    va_rad::Union{Nothing, Float64}
    "Power-flow bus index, independent of the topology index."
    pf_index::Union{Nothing, Int}

    function Bus(key, name, nets, kind, base_kV, vm_pu, va_rad, pf_index)
        kind in (:ac3_dq, :ac3_abc, :dc) || throw(ArgumentError("invalid bus kind: $kind"))
        return new(key, name, nets, kind, base_kV, vm_pu, va_rad, pf_index)
    end
end

"""
$(TYPEDEF)

Store connected pins on one element side in physical terminal order.
Omit unconnected pins. A fully grounded side has `bus = nothing`.

$(TYPEDFIELDS)
"""
struct Terminal
    "Element designator."
    element::Symbol
    "Element side number."
    side::Int
    "Local terminal numbers, in increasing order."
    terminals::Vector{Int}
    "Network nets corresponding to the local terminals."
    nets::Vector{Symbol}
    "Nongrounded topology bus, when present."
    bus::Union{Nothing, BusKey}
    "Whether every connected terminal is grounded."
    grounded::Bool
end

"""
$(TYPEDEF)

Store an element, its physical model, connections and operating setpoint.
Setpoint powers use \\[MW, MVAr\\], angles \\[rad\\], AC voltages phase peak
\\[kV\\], and DC source and converter voltages pole-to-pole \\[kV\\].
Construction leaves the element unchanged.

$(TYPEDFIELDS)
"""
struct NetlistElement{M}
    "Network element designator."
    name::Symbol
    "Unique PSCAD identifier."
    pscad::String
    "Original materialized element."
    element::PowerImpedance.Element{M}
    "Original component model."
    model::M
    "Connected element sides in physical order."
    terminals::Vector{Terminal}
    "Topology role refined by power-flow component type when available."
    role::Symbol
    "Effective operating setpoint in the units described above."
    setpoint::PowerImpedance.Setpoint
end

"""
$(TYPEDEF)

Store a supplied power-flow solution without changing the network.
With no solved result, dictionaries are empty and `slack_bus`/`bases` are
`nothing`.

$(TYPEDFIELDS)
"""
struct OperatingPointRecord
    "Bus states `(vm_pu, va_rad)` in \\[dimensionless\\] and \\[rad\\], indexed by `BusKey`."
    bus_states::Dict{BusKey, NamedTuple}
    "Solved component powers \\[MW, MVAr\\], synchronous-machine terminal voltage/angle \\[kV, rad\\] and induction-machine speed \\[pu\\], keyed by designator."
    branch_flows::Dict{Symbol, NamedTuple}
    "Effective element Setpoints \\[MW, MVAr, rad, kV\\], keyed by designator."
    setpoints::Dict{Symbol, PowerImpedance.Setpoint}
    "AC bus of the first AC source, when a solved result exists."
    slack_bus::Union{Nothing, BusKey}
    "Power-flow bases `(S_MVA = 1000.0, V_kV, dcpol = 2)` in \\[MVA, kV\\], or `nothing`."
    bases::Union{Nothing, NamedTuple}
end

"""
$(TYPEDEF)

Represent a materialized network for later PSCAD emission, preserving physical
terminal order and the supplied operating point.

$(TYPEDFIELDS)
"""
struct Netlist
    "Nongrounded buses in first-seen topology order."
    buses::Vector{Bus}
    "Elements in network declaration order."
    elements::Vector{NetlistElement}
    "Supplied solved operating point, or an empty record."
    operating_point::OperatingPointRecord
    "Common AC phase RMS / DC pole-to-ground voltage base \\[kV\\]."
    voltageBase::Float64
    "Global network frequency \\[Hz\\]."
    frequency::Float64
end

function _check_supported_elements(elements)
    for (name, element) in pairs(elements)
        model = element.element_model
        model isa Union{PowerImpedance.Blackbox_line, PowerImpedance.Blackbox_MMC} &&
            throw(ArgumentError("PSCAD does not support element :$name ($(typeof(model)))"))
    end
    return nothing
end

# Topology inference also runs without the plotting extension, so its
# projection and refinement rules are implemented here.
function _topology_role(element, connected_buses, grounded_sides)
    model = element.element_model
    PowerImpedance.is_converter(element) && return :converter
    PowerImpedance.is_source(element) && return :source
    (PowerImpedance.is_generator(element) ||
     PowerImpedance.is_inductionmachine(element)) && return :machine
    model isa PowerImpedance.Transformer && return :transformer
    if model isa PowerImpedance.Impedance
        isempty(grounded_sides) || return :shunt
        return all(connection -> connection.bus.domain == 2, connected_buses) ?
               :dc_branch : :ac_branch
    end
    if model isa PowerImpedance.Transmission_line
        return all(connection -> connection.bus.domain == 2, connected_buses) ?
               :dc_branch : :ac_branch
    end
    return :generic
end

function _refined_role(role::Symbol, element, pmtype, input)
    pmtype === nothing && return role
    pmtype == "convdc" && return :converter
    pmtype == "branchdc" && return :dc_branch
    if pmtype == "branch"
        value = get(input, "transformer", false)
        transformer = value isa Bool ? value : value isa Number && !iszero(value)
        return transformer ? :transformer : :ac_branch
    end
    pmtype == "load" && return :load
    pmtype == "shunt" && return :shunt
    pmtype == "im" && return :machine
    if pmtype in ("gen", "gendc")
        return PowerImpedance.is_source(element) ? :source : :machine
    end
    return role
end

function _bus_kind(key, nets)
    key.domain == 1 && length(nets) == 2 && return :ac3_dq
    key.domain == 1 && length(nets) == 3 && return :ac3_abc
    key.domain == 2 && length(nets) == 1 && return :dc
    throw(ArgumentError("unsupported PSCAD bus nets $(repr(nets)) in domain $(key.domain)"))
end

function _pf_bus_indices(topology, pf::Tuple)
    nodes2bus = pf[3]
    indices = Dict{BusKey, Int}()
    for row in topology.connections
        row.bus == 0 && continue
        key = BusKey(row.domain, row.bus)
        side_rows = filter(r -> r.element == row.element && r.side == row.side,
            topology.connections)
        mapping = get(nodes2bus, Set(r.node for r in side_rows), nothing)
        expected = row.domain == 1 ? "bus" : "busdc"
        mapping !== nothing && mapping[1] == expected ||
            throw(ArgumentError("power-flow mapping is missing or has the wrong domain for element :$(row.element) side $(row.side)"))
        index = Int(mapping[2])
        get(indices, key, index) == index ||
            throw(ArgumentError("power-flow mappings disagree on bus nets $(repr(unique(side_rows.node)))"))
        indices[key] = index
    end
    return indices
end

function _pf_bus_indices(topology, pf::PowerImpedance.PowerFlowResult)
    Set(topology.connections.node) == Set(keys(pf.nodes2bus)) ||
        throw(ArgumentError("power-flow result does not belong to the supplied network: node mappings differ"))
    indices = Dict{BusKey, Int}()
    for row in topology.connections
        expected = row.bus == 0 ? (:ground, 0) :
                   (row.domain == 1 ? :ac : :dc, row.bus)
        mapping = pf.nodes2bus[row.node]
        mapping == expected ||
            throw(ArgumentError("power-flow result does not belong to the supplied network: node :$(row.node) maps to $mapping, expected $expected"))
        row.bus == 0 || (indices[BusKey(row.domain, row.bus)] = mapping[2])
    end
    return indices
end

function _powerflow_parts(topology, elements, pf::Tuple)
    length(pf) == 4 || throw(ArgumentError("classic power flow must be a four-tuple"))
    result, data, nodes2bus, elem2comp = pf
    return (; result, data, elem2comp, indices = _pf_bus_indices(topology, pf),
        setpoints = Dict{Symbol, PowerImpedance.Setpoint}())
end

function _powerflow_parts(topology, elements, pf::PowerImpedance.PowerFlowResult)
    indices = _pf_bus_indices(topology, pf)
    if pf.data === nothing
        isempty(pf.elem2comp) ||
            throw(ArgumentError("power-flow result has component mappings but no input data"))
    else
        Set(keys(pf.elem2comp)) == Set(keys(elements)) ||
            throw(ArgumentError("power-flow result does not belong to the supplied network: element mappings differ"))
    end
    pf.result === nothing && return nothing
    return (result = pf.result, data = pf.data, elem2comp = pf.elem2comp,
        indices = indices, setpoints = pf.operating_point.setpoints)
end

_powerflow_parts(topology, elements, ::Nothing) = nothing

function _powerflow_component(pf, name)
    pf === nothing && return (nothing, nothing, nothing)
    mapping = get(pf.elem2comp, name, nothing)
    mapping === nothing && return (nothing, nothing, nothing)
    pmtype, index = mapping
    pmtype = String(pmtype)
    input = pf.data[pmtype][string(index)]
    solution = get(get(pf.result["solution"], pmtype, Dict()), string(index), nothing)
    return pmtype, input, solution
end

function _branch_flow(pmtype, solution, input, pf, terminals)
    if pmtype == "shunt"
        # PowerModels shunts have no separate solved component entry. Their
        # input admittance and solved bus voltage determine terminal power.
        voltage = pf.result["solution"]["bus"][string(input["shunt_bus"])]["vm"]
        p = Float64(input["gs"] * voltage^2 * 1000)
        q = Float64(-input["bs"] * voltage^2 * 1000)
        side = only(filter(t -> !t.grounded, terminals)).side
        return side == 1 ? (pf = p, qf = q) : (pt = p, qt = q)
    end
    solution === nothing && return nothing
    if pmtype == "im"
        # Induction-machine pg/qg are powers absorbed at its AC terminal.
        return (pf = Float64(solution["pg"]) * 1000,
            qf = Float64(solution["qg"]) * 1000)
    end
    fields = pmtype == "branch" ? (:pf, :qf, :pt, :qt) :
             pmtype == "branchdc" ? (:pf, :pt) :
             pmtype == "convdc" ? (:pgrid, :qgrid, :pdc) :
             pmtype == "gen" ? (:pg, :qg) :
             pmtype == "gendc" ? (:pgdc,) : ()
    isempty(fields) && return nothing
    return NamedTuple{fields}(Tuple(Float64(solution[string(field)]) * 1000.0
    for field in fields))
end

function _netlist(elements, topology, voltage_base, frequency, supplied_pf,
        ground_terminals = Dict{Symbol, Terminal}())
    _check_supported_elements(elements)
    pf = _powerflow_parts(topology, elements, supplied_pf)
    rows = topology.connections
    bus_order = BusKey[]
    bus_nets = Dict{BusKey, Vector{Symbol}}()
    for row in rows
        row.bus == 0 && continue
        key = BusKey(row.domain, row.bus)
        if !haskey(bus_nets, key)
            bus_nets[key] = Symbol[]
            push!(bus_order, key)
        end
        row.node in bus_nets[key] || push!(bus_nets[key], row.node)
    end

    used = _NameReservations()
    buses = Bus[]
    bus_states = Dict{BusKey, NamedTuple}()
    for (index, key) in enumerate(bus_order)
        nets = bus_nets[key]
        kind = _bus_kind(key, nets)
        proposed = bus_name(nets)
        name = pscad_name(proposed === nothing ? "BUS$index" : proposed; used)
        pf_index = pf === nothing ? nothing : pf.indices[key]
        base_kV, vm, va = if pf === nothing
            voltage_base, nothing, nothing
        else
            table = key.domain == 1 ? "bus" : "busdc"
            base_field = key.domain == 1 ? "base_kv" : "basekVdc"
            base = pf.data === nothing ? voltage_base :
                   Float64(pf.data[table][string(pf_index)][base_field])
            solution = pf.result["solution"][table][string(pf_index)]
            base, Float64(solution["vm"]),
            key.domain == 1 ? Float64(solution["va"]) : nothing
        end
        if index == 1
            voltage_base = base_kV
        else
            base_kV == voltage_base ||
                throw(ArgumentError("power-flow voltage bases disagree: bus $name uses $base_kV kV, expected $voltage_base kV"))
        end
        push!(buses, Bus(key, name, nets, kind, base_kV, vm, va, pf_index))
        pf === nothing || (bus_states[key] = (vm_pu = vm, va_rad = va))
    end

    netlist_elements = NetlistElement[]
    flows = Dict{Symbol, NamedTuple}()
    setpoints = Dict{Symbol, PowerImpedance.Setpoint}()
    slack_bus = nothing
    for (name, element) in pairs(elements)
        element_rows = filter(row -> row.element == name, rows)
        terminals = Terminal[]
        for side in sort!(unique(element_rows.side))
            side_rows = sort!(collect(filter(row -> row.side == side, element_rows)); by = row -> row.terminal)
            nets = Symbol[row.node for row in side_rows]
            grounded = all(PowerImpedance.isgroundnet, nets)
            any(PowerImpedance.isgroundnet, nets) && !grounded &&
                throw(ArgumentError("element :$name side $side mixes grounded and nongrounded nets $(repr(nets))"))
            bus = grounded ? nothing : BusKey(first(side_rows).domain, first(side_rows).bus)
            !grounded && bus.index == 0 &&
                throw(ArgumentError("element :$name side $side has nongrounded nets on a grounded topology bus"))
            push!(terminals, Terminal(
                name, side, Int[row.terminal for row in side_rows], nets, bus, grounded))
        end
        if PowerImpedance.issingleport(element) && !isempty(element_rows)
            ground = get(ground_terminals, name) do
                count = PowerImpedance.nop(element)
                Terminal(name, 2, collect(1:count), fill(:gnd, count), nothing, true)
            end
            isempty(ground.terminals) || push!(terminals, ground)
        end
        sort!(terminals; by = terminal -> terminal.side)
        pmtype, input, solution = _powerflow_component(pf, name)
        connected = filter(terminal -> terminal.bus !== nothing, terminals)
        grounded_sides = [terminal.side for terminal in terminals if terminal.grounded]
        role = _refined_role(_topology_role(element, connected, grounded_sides), element, pmtype, input)
        setpoint = pf === nothing ? element.setpoint :
                   get(pf.setpoints, name, element.setpoint)
        push!(netlist_elements,
            NetlistElement(name, pscad_name(name; used), element,
                element.element_model, terminals, role, setpoint))
        if pf !== nothing
            setpoints[name] = setpoint
            flow = _branch_flow(pmtype, solution, input, pf, terminals)
            if element.element_model isa PowerImpedance.InductionMachine && flow !== nothing
                states = NamedTuple{PowerImpedance.statenames(element.element_model)}(
                    Tuple(PowerImpedance._steady_state(element, setpoint)))
                flow = merge(flow, (speed_pu = states.ω_r,))
            end
            if element.element_model isa PowerImpedance.SynchronousMachine &&
               flow !== nothing
                # The machine's public bus lies beyond rt/lt. The power-flow generator
                # record refers to the intermediate machine terminal bus.
                terminal_index = string(input["gen_bus"])
                terminal_bus = pf.result["solution"]["bus"][terminal_index]
                terminal_base = Float64(pf.data["bus"][terminal_index]["base_kv"])
                branch = pf.result["solution"]["branch"][string(input["index"])]
                flow = merge(flow,
                    (pf = -Float64(branch["pt"]) * 1000,
                        qf = -Float64(branch["qt"]) * 1000,
                        terminal_voltage_kV = Float64(terminal_bus["vm"]) * terminal_base,
                        terminal_angle_rad = Float64(terminal_bus["va"])))
            end
            if element.element_model isa Union{PowerImpedance.TLC, PowerImpedance.MMC} &&
               flow !== nothing
                # convdc defines pgrid and qgrid as power absorbed from the AC bus. The
                # external ammeter points toward the bus. DC side 1 absorbs pdc.
                flow = merge(flow, (; pf = flow.pdc, pt = -flow.pgrid, qt = -flow.qgrid))
            end
            flow === nothing || (flows[name] = flow)
            if slack_bus === nothing && PowerImpedance.is_source(element)
                ac_terminal = findfirst(terminal -> terminal.bus.domain == 1, connected)
                ac_terminal === nothing || (slack_bus = connected[ac_terminal].bus)
            end
        end
    end
    bases = pf === nothing ? nothing : (S_MVA = 1000.0, V_kV = voltage_base, dcpol = 2)
    point = OperatingPointRecord(bus_states, flows, setpoints, slack_bus, bases)
    return Netlist(buses, netlist_elements, point, voltage_base, frequency)
end

"""
$(TYPEDSIGNATURES)

Construct a PSCAD netlist from a classic network and supplied power-flow data.
Use NetworkBuilder topology inference for connected pins. Store the grounded
side 2 of one-port devices as a ground terminal, excluding it from bus inference.

# Arguments

- `net`: Connected classic network.
- `pf`: `(result, data, nodes2bus, elem2comp)` power-flow tuple, or `nothing`.

# Returns

- A `Netlist` with physical terminal order and the supplied operating point.
  With a solution, use the common voltage base in its bus input records.
  Otherwise use `net.voltageBase[1]` \\[kV\\]. The network frame is 50 \\[Hz\\].

# Notes

Construction preserves network setpoints and does not solve power flow.
"""
function netlist(net::PowerImpedance.Network, pf::Union{Nothing, Tuple})
    elements = NamedTuple{Tuple(keys(net.elements))}(Tuple(values(net.elements)))
    _check_supported_elements(elements)
    rows = NamedTuple[]
    grounds = Dict{Symbol, Terminal}()
    for (name, element) in pairs(elements)
        ground_pins = Tuple{Int, Symbol}[]
        for side in 1:2,
            terminal in 1:(side == 1 ? PowerImpedance.nip(element) :
                           PowerImpedance.nop(element))

            node = get(element.pins, Symbol("$side.$terminal"), Symbol())
            node == Symbol() && continue
            if side == 2 && PowerImpedance.issingleport(element)
                PowerImpedance.isgroundnet(node) ||
                    throw(ArgumentError("single-port element :$name has a nongrounded legacy side 2 net :$node"))
                push!(ground_pins, (terminal, node))
            else
                push!(rows, (; node, element = name, side, terminal))
            end
        end
        if !isempty(ground_pins)
            grounds[name] = Terminal(
                name, 2, first.(ground_pins), last.(ground_pins), nothing, true)
        end
    end
    topology = PowerImpedance.NetworkBuilder.NetworkTopology(elements, rows)
    return _netlist(elements, topology, net.voltageBase[1], 50.0, pf, grounds)
end

"""
$(TYPEDSIGNATURES)

Construct a PSCAD netlist from a NetworkBuilder topology and supplied solution.
Use the solution's operating setpoints because `NetworkBuilder.solve` updates
its returned classic network separately from `state.elements`.

# Arguments

- `state`: Materialized builder network.
- `pf`: `PowerFlowResult`, or `nothing` to use the declared setpoints.
- `elements`: Elements in declaration order, including solved states when
  available. Default: `state.elements`.

# Returns

- A `Netlist` preserving physical terminal order, with implicit `:gnd` terminals
  for one-port devices. The network frame is 50 \\[Hz\\]. With a solution and
  input data, `pf_index` selects each bus base from its PowerModels record.
  Require a common base for the netlist and operating point. Otherwise use
  `state.options.voltageBase` \\[kV\\], defaulting to
  `NetworkBuilder.DEFAULT_VOLTAGE_BASE`.

# Notes

Construction leaves `state` and `pf` unchanged. A solved voltage base can differ
from the declared network base.
"""
function netlist(state::PowerImpedance.NetworkBuilder.NetworkState,
        pf::Union{Nothing, PowerImpedance.PowerFlowResult}, elements = state.elements)
    voltage_base = Float64(get(state.options, :voltageBase,
        PowerImpedance.NetworkBuilder.DEFAULT_VOLTAGE_BASE))
    return _netlist(elements, state.topology, voltage_base, 50.0, pf)
end
