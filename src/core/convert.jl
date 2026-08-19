"""
$(TYPEDEF)

Specify an AC/DC power-flow calculation for one materialized network.

$(TYPEDFIELDS)
"""
struct PowerFlowProblem{N <: NetworkState} <: P.ProblemDefinition
    "Materialized network whose operating point is required."
    network::N
end

"Select the validated PowerModelsACDC power-flow formulation."
struct ACDCPowerFlow <: P.AbstractFormulation end

"""
$(TYPEDEF)

Specify admittance linearization of one materialized network.

$(TYPEDFIELDS)
"""
struct LinearizationProblem{N <: NetworkState, F} <: P.ProblemDefinition
    "Materialized network to linearize."
    network::N
    "Previously calculated power-flow result, or `nothing`."
    powerflow::F
end

LinearizationProblem(network::NetworkState) = LinearizationProblem(network, nothing)

"Select frequency-domain admittance linearization."
struct AdmittanceLinearization <: P.AbstractFormulation end

"""
    convert(network::NetworkState, NetworkModel)

Calculate the operating point required by active elements and construct the
frequency-domain network model. Linear networks skip power flow.
"""
function Base.convert(network::NetworkState, ::Type{NetworkModel})
    result = P.compute(LinearizationProblem(network), AdmittanceLinearization())
    return result.network_model
end

function islinear(elements)
    for elem in values(elements)
        if !P.islinear(elem)
            return false
        end
    end
    return true
end

function _node_bus_mapping(topology::NetworkTopology)
    mapping = Dict{Symbol, Tuple{Symbol, Int}}()
    for row in topology.connections
        bus_type = row.bus == 0 ? :ground : row.domain == 1 ? :ac : :dc
        mapping[row.node] = (bus_type, row.bus)
    end
    return mapping
end

function _powerflow_diagnostics(result, global_dict)
    return (
        termination_status = get(result, "termination_status", missing),
        objective = get(result, "objective", missing),
        solve_time = get(result, "solve_time", missing),
        global_bases = global_dict
    )
end

function _operating_point(
        result,
        global_dict,
        network::NetworkState,
        element_mapping
)
    setpoints = transform(
        result["solution"],
        global_dict,
        network,
        P.PMACDC,
        P.PIACDC,
        element_mapping
    )
    return P.OperatingPoint(Dict{Symbol, P.Setpoint}(pairs(setpoints)))
end

function P.compute(problem::PowerFlowProblem, ::ACDCPowerFlow)
    network = problem.network
    if islinear(network.elements)
        point = P.OperatingPoint()
        network.operating_point = point
        return P.PowerFlowResult(
            nothing,
            nothing,
            _node_bus_mapping(network.topology),
            Dict{Symbol, Any}(),
            point,
            (termination_status = :not_required,)
        )
    end

    data, global_dict, element_mapping = convert(network, P.PMACDC)
    result = solve_acdcpf(
        data,
        P._PM.ACPPowerModel,
        powerflow_optimizer(network.options),
        is_bounded_options(network.options);
        setting = powerflow_setting(network.options)
    )
    point = _operating_point(result, global_dict, network, element_mapping)
    network.operating_point = point
    @info "Setpoints of nonlinear devices: $(point.setpoints)"
    return P.PowerFlowResult(
        result,
        data,
        _node_bus_mapping(network.topology),
        element_mapping,
        point,
        _powerflow_diagnostics(result, global_dict)
    )
end

"Return the operating point already calculated by a power-flow result."
function Base.convert(::Type{P.OperatingPoint}, powerflow::P.PowerFlowResult)
    powerflow.operating_point
end

nonlinearsetpoints(powerflow::P.PowerFlowResult) = convert(P.OperatingPoint, powerflow)

function P.compute(problem::LinearizationProblem, ::AdmittanceLinearization)
    network = problem.network
    powerflow = problem.powerflow
    point = if powerflow isa P.PowerFlowResult
        nonlinearsetpoints(powerflow)
    elseif network.operating_point !== nothing
        network.operating_point
    elseif islinear(network.elements)
        P.OperatingPoint()
    else
        nonlinearsetpoints(P.compute(PowerFlowProblem(network), ACDCPowerFlow()))
    end
    network.operating_point = point
    model = NetworkModel(network, point)
    return P.LinearizationResult(
        model,
        point,
        (
            powerflow_required = !islinear(network.elements),
            active_elements = length(model.active_elements),
            passive_elements = length(model.passive_elements)
        )
    )
end

# Transforms output(output payload) from PMACDC to PIACDC
function transform(output, global_dict, bs::NetworkState,
        ::Type{P.PMACDC}, ::Type{P.PIACDC}, elempitopm)
    sp = (;)
    for (key, elem) in pairs(bs.elements)

        #1. Skip passive devices
        if P.is_passive(elem) || P.is_source(elem)
            continue # Skips iteration
        end

        pmcomptype, pmkey = elempitopm[key]
        elemresult = output[pmcomptype][string(pmkey)]
        busresult = transform(output, bs.topology, P.PMACDC, P.PIACDC, key) #Sorted from AC to DC (easier extension for nonshunt active elements)

        sp = merge(sp, (;
            key =>
            P.transform(elemresult, busresult, global_dict, elem, P.PMACDC, P.PIACDC),))
    end

    return sp
end

function transform(output, connections, ::Type{P.PMACDC}, ::Type{P.PIACDC}, key)
    elemconnections = sortedcomponentconnections(connections, key) #Sorted from AC to DC and with terminal
    busids = unique(Table(bus = elemconnections.bus, domain = elemconnections.domain))
    # Bus identifiers are unique only together with their electrical domain.
    busresults = [output[string(busid.domain == 1 ? "bus" : "busdc")][string(busid.bus)]
                  for busid in busids]
    # busresults_nt = NamedTuple{busids_symbol}(busresults)

    return busresults
end
