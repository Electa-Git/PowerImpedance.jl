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

Store connected terminals on one named port in physical order.
Omit unconnected terminals. A fully grounded port has `bus = nothing`.

$(TYPEDFIELDS)
"""
struct Terminal
    "Element designator."
    element::Symbol
    "Electrical port name."
    port::Symbol
    "Local terminal labels, in physical order."
    terminals::Vector{Symbol}
    "Network nets corresponding to the local terminals."
    nets::Vector{Symbol}
    "Nongrounded topology bus, when present."
    bus::Union{Nothing, BusKey}
    "Whether every connected terminal is grounded."
    grounded::Bool
end

"""
$(TYPEDEF)

Store a component model, its ports, connections and solved terminal values.
Powers flowing into the component use \\[MW, MVAr\\], angles \\[rad\\], AC voltages
phase peak \\[kV\\], and DC source and converter voltages pole-to-pole \\[kV\\].
Retain the supplied model.

$(TYPEDFIELDS)
"""
struct NetlistElement{M}
    "Network element designator."
    name::Symbol
    "Unique PSCAD identifier."
    pscad::String
    "Original component model."
    model::M
    "Electrical port descriptions in declaration order."
    ports::NamedTuple
    "Connected ports in physical order."
    terminals::Vector{Terminal}
    "Topology role refined by power-flow component type when available."
    role::Symbol
    "Solved per-port terminal values, or `nothing` when unavailable."
    values::Union{Nothing, NamedTuple}
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
    "Solved per-port values \\[MW, MVAr, rad, kV\\], keyed by designator."
    values::Dict{Symbol, NamedTuple}
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

function _check_supported_elements(models)
    for (name, model) in pairs(models)
        model isa Union{PowerImpedance.Blackbox_line, PowerImpedance.Blackbox_MMC} &&
            throw(ArgumentError("PSCAD does not support element :$name ($(typeof(model)))"))
    end
    return nothing
end

function _bus_kind(key, nets)
    key.domain == 1 && length(nets) == 2 && return :ac3_dq
    key.domain == 1 && length(nets) == 3 && return :ac3_abc
    key.domain == 2 && length(nets) == 1 && return :dc
    throw(ArgumentError("unsupported PSCAD bus nets $(repr(nets)) in domain $(key.domain)"))
end

function _pf_bus_indices(topology, pf::PowerImpedance.PowerFlowResult)
    Set(topology.connections.net) == Set(keys(pf.nodes2bus)) ||
        throw(ArgumentError("power-flow result does not belong to the supplied network: node mappings differ"))
    indices = Dict{BusKey, Int}()
    for row in topology.connections
        expected = row.bus == 0 ? (:ground, 0) :
                   (row.domain == 1 ? :ac : :dc, row.bus)
        mapping = pf.nodes2bus[row.net]
        mapping == expected ||
            throw(ArgumentError("power-flow result does not belong to the supplied " *
                                "network: node :$(row.net) maps to $mapping, " *
                                "expected $expected"))
        row.bus == 0 || (indices[BusKey(row.domain, row.bus)] = mapping[2])
    end
    return indices
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
        indices = indices, values = pf.operating_point.values)
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

function _branch_flow(model, pmtype, solution, input, pf, terminals, values)
    if pmtype == "shunt"
        # PowerModels shunts have no separate solved component entry. Their
        # input admittance and solved bus voltage determine terminal power.
        voltage = pf.result["solution"]["bus"][string(input["shunt_bus"])]["vm"]
        p = Float64(input["gs"] * voltage^2 * 1000)
        q = Float64(-input["bs"] * voltage^2 * 1000)
        port = only(filter(t -> !t.grounded, terminals)).port
        return port == :side1 ? (pf = p, qf = q) : (pt = p, qt = q)
    end
    solution === nothing && return nothing
    fields = pmtype == "branch" ? (:pf, :qf, :pt, :qt) :
             pmtype == "branchdc" ? (:pf, :pt) :
             pmtype == "convdc" ? (:pgrid, :qgrid, :pdc) :
             pmtype == "gen" ? (:pg, :qg) :
             pmtype == "gendc" ? (:pgdc,) : ()
    isempty(fields) && return nothing
    return NamedTuple{fields}(Tuple(Float64(solution[string(field)]) * 1000.0
    for field in fields))
end

function _branch_flow(model::PowerImpedance.InductionMachine,
        pmtype, solution, input, pf, terminals, values)
    solution === nothing && return nothing
    # Induction-machine pg/qg are powers absorbed at its AC terminal.
    states = NamedTuple{PowerImpedance.statenames(model)}(
        Tuple(PowerImpedance.steady_state(model, values)))
    return (pf = values.ac.p, qf = values.ac.q, speed_pu = states.ω_r)
end

function _branch_flow(model::PowerImpedance.SynchronousMachine,
        pmtype, solution, input, pf, terminals, values)
    solution === nothing && return nothing
    # The machine's public bus lies beyond rt/lt. The power-flow generator
    # record refers to the intermediate machine terminal bus.
    terminal_index = string(input["gen_bus"])
    terminal_bus = pf.result["solution"]["bus"][terminal_index]
    terminal_base = Float64(pf.data["bus"][terminal_index]["base_kv"])
    branch = pf.result["solution"]["branch"][string(input["index"])]
    return (pg = Float64(solution["pg"]) * 1000,
        qg = Float64(solution["qg"]) * 1000,
        pf = -Float64(branch["pt"]) * 1000,
        qf = -Float64(branch["qt"]) * 1000,
        terminal_voltage_kV = Float64(terminal_bus["vm"]) * terminal_base,
        terminal_angle_rad = Float64(terminal_bus["va"]))
end

function _branch_flow(model::Union{PowerImpedance.TLC, PowerImpedance.MMC},
        pmtype, solution, input, pf, terminals, values)
    solution === nothing && return nothing
    # convdc defines pgrid and qgrid as power absorbed from the AC bus. The
    # external ammeter points toward the bus. The DC port absorbs pdc.
    return (pgrid = Float64(solution["pgrid"]) * 1000,
        qgrid = Float64(solution["qgrid"]) * 1000,
        pdc = values.dc.p, pf = values.dc.p, pt = -values.ac.p, qt = -values.ac.q)
end

function _netlist(elements, topology, voltage_base, frequency, supplied_pf)
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
        row.net in bus_nets[key] || push!(bus_nets[key], row.net)
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
    port_values = Dict{Symbol, NamedTuple}()
    slack_bus = nothing
    for (name, model) in pairs(elements)
        ports = PowerImpedance.electricalconnections(model)
        element_rows = filter(row -> row.component == name, rows)
        terminals = Terminal[]
        for (port, description) in pairs(ports)
            port_rows = filter(row -> row.port == port, element_rows)
            isempty(port_rows) && continue
            labels = first(port_rows).frame == :dq ?
                     PowerImpedance.terminals(PowerImpedance.ACDQ) : description.terminals
            port_rows = sort!(collect(port_rows);
                by = row -> findfirst(==(row.terminal), labels))
            nets = Symbol[row.net for row in port_rows]
            grounded = all(PowerImpedance.isgroundnet, nets)
            any(PowerImpedance.isgroundnet, nets) && !grounded && throw(ArgumentError(
                "element :$name port :$port mixes grounded and nongrounded nets " *
                repr(nets)))
            bus = grounded ? nothing : BusKey(first(port_rows).domain, first(port_rows).bus)
            !grounded && bus.index == 0 && throw(ArgumentError(
                "element :$name port :$port has nongrounded nets on a grounded bus"))
            push!(terminals, Terminal(name, port,
                Symbol[row.terminal for row in port_rows], nets, bus, grounded))
            if length(ports) == 1
                push!(terminals, Terminal(name, port, collect(labels),
                    fill(:gnd, length(labels)), nothing, true))
            end
        end
        pmtype, input, solution = _powerflow_component(pf, name)
        connected = filter(terminal -> terminal.bus !== nothing, terminals)
        grounded_ports = [terminal.port for terminal in terminals if terminal.grounded]
        role = PowerImpedance.NetworkBuilder.refined_role(
            PowerImpedance.NetworkBuilder.topology_role(model, connected, grounded_ports),
            model, pmtype, input)
        values = pf === nothing ? nothing : get(pf.values, name, nothing)
        push!(netlist_elements, NetlistElement(name, pscad_name(name; used), model,
            ports, terminals, role, values))
        if pf !== nothing
            values === nothing || (port_values[name] = values)
            flow = _branch_flow(model, pmtype, solution, input, pf, terminals, values)
            flow === nothing || (flows[name] = flow)
            if slack_bus === nothing && PowerImpedance.is_source(model)
                ac_terminal = findfirst(terminal -> terminal.bus.domain == 1, connected)
                ac_terminal === nothing || (slack_bus = connected[ac_terminal].bus)
            end
        end
    end
    bases = pf === nothing ? nothing : (S_MVA = 1000.0, V_kV = voltage_base, dcpol = 2)
    point = OperatingPointRecord(bus_states, flows, port_values, slack_bus, bases)
    return Netlist(buses, netlist_elements, point, voltage_base, frequency)
end

"""
$(TYPEDSIGNATURES)

Construct a PSCAD netlist from component models and named topology ports.
Read solved terminal values from the supplied power-flow result.

# Arguments

- `state`: Materialized builder network.
- `pf`: `PowerFlowResult`, or `nothing` for an unsolved netlist.

# Returns

- A `Netlist` preserving physical terminal order, with implicit `:gnd` terminals
  for one-port devices. The network frame is 50 \\[Hz\\]. With a solution and
  input data, `pf_index` selects each bus base from its PowerModels record.
  Require a common base for the netlist and operating point. Otherwise use
  `state.options.voltageBase` \\[kV\\], defaulting to
  `NetworkBuilder.DEFAULT_VOLTAGE_BASE`.

# Notes

Construction preserves model inputs, topology and the supplied power-flow data.
An induction-machine equilibrium can update its model cache. A solved voltage
base can differ from the declared network base.
"""
function netlist(state::PowerImpedance.NetworkBuilder.NetworkState,
        pf::Union{Nothing, PowerImpedance.PowerFlowResult})
    voltage_base = Float64(get(state.options, :voltageBase,
        PowerImpedance.NetworkBuilder.DEFAULT_VOLTAGE_BASE))
    return _netlist(state.elements, state.topology, voltage_base, 50.0, pf)
end
