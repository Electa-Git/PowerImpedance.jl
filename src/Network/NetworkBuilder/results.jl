"""
$(TYPEDEF)

Specify an AC/DC power-flow calculation for one materialized network.

$(TYPEDFIELDS)
"""
struct PowerFlowProblem{N <: NetworkState} <: P.AbstractProblemDefinition
    "Materialized network whose operating point is required."
    network::N
end

"Select the validated PowerModelsACDC power-flow formulation."
struct ACDCPowerFlow{B} <: P.AbstractFormulation
    backend::Type{B}
end

ACDCPowerFlow(; backend::Type{B}=P.PMACDC) where {B} = ACDCPowerFlow{B}(backend)

"""
$(TYPEDEF)

Specify admittance linearization of one materialized network.

$(TYPEDFIELDS)
"""
struct LinearizationProblem{N <: NetworkState, F} <: P.AbstractProblemDefinition
    "Materialized network to linearize."
    network::N
    "Previously calculated power-flow result, or `nothing`."
    powerflow::F
end

LinearizationProblem(network::NetworkState) = LinearizationProblem(network, nothing)

"Select frequency-domain admittance linearization."
struct AdmittanceLinearization{B} <: P.AbstractFormulation
    backend::Type{B}
end

AdmittanceLinearization(; backend::Type{B}=P.PIACDC) where {B} =
    AdmittanceLinearization{B}(backend)

function islinear(elements)
    for (name, model) in pairs(elements)
        linear = _element_call(name) do
            P.islinear(model)
        end
        linear || return false
    end
    return true
end

function _node_bus_mapping(topology::NetworkTopology)
    mapping = Dict{Symbol, Tuple{Symbol, Int}}()
    for row in topology.connections
        bus_type = row.bus == 0 ? :ground : row.domain == 1 ? :ac : :dc
        mapping[row.net] = (bus_type, row.bus)
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
    values = transform(
        result["solution"],
        global_dict,
        network,
        P.PMACDC,
        P.PIACDC,
        element_mapping
    )
    return P.OperatingPoint(values)
end

function P.compute(
        problem::PowerFlowProblem,
        formulation::ACDCPowerFlow{P.PMACDC};
        options::NamedTuple = (;)
)
    network = _assert_numeric_powerflow_network(problem.network)
    data, global_dict, element_mapping = convert(network, P.PMACDC)
    _prepare_power_flow_start!(network.powerflow_start, data,
        (element_mapping, collect(network.topology.connections)))
    result = solve_acdcpf(
        data,
        P._PM.ACPPowerModel,
        powerflow_optimizer(network.options),
        is_bounded_options(network.options),
        network.powerflow_start;
        setting = powerflow_setting(network.options)
    )
    point = _operating_point(result, global_dict, network, element_mapping)
    @info "Terminal operating values: $(point.values)"
    return P.PowerFlowResult(
        formulation,
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

function P.compute(
        problem::LinearizationProblem,
        formulation::AdmittanceLinearization{P.PIACDC};
        options::NamedTuple = (;)
)
    network = problem.network
    powerflow = problem.powerflow
    point = if powerflow isa P.PowerFlowResult
        convert(P.OperatingPoint, powerflow)
    elseif islinear(network.elements)
        P.OperatingPoint()
    else
        P.compute(PowerFlowProblem(network), ACDCPowerFlow()).operating_point
    end
    model = NetworkModel(network, point)
    return P.LinearizationResult(
        formulation,
        model,
        point,
        (
            powerflow_required = !islinear(network.elements),
            active_elements = length(model.active_elements),
            passive_elements = length(model.passive_elements)
        )
    )
end

"""
$(TYPEDSIGNATURES)

Return physical port values from a PowerModelsACDC solution.
Powers are positive into the component: `ac.p = 916` for a motor drawing 916 MW.
A converter taking 603 MW from DC and delivering 600 MW to AC has `dc.p = 603`
and `ac.p = -600`. Sources delivering power have negative port powers.
"""
function transform(output, global_dict, bs::NetworkState,
        ::Type{P.PMACDC}, ::Type{P.PIACDC}, elempitopm)
    values = Dict{Symbol, NamedTuple}()
    for (name, model) in pairs(bs.elements)
        P.is_passive(model) && continue
        values[name] = _element_call(name) do
            pmcomptype, pmkey = elempitopm[name]
            elemresult = output[pmcomptype][string(pmkey)]
            rows = filter(row -> row.component == name, bs.topology.connections)
            ports = _powerflow_ports(model, rows)
            descriptions = P.electricalconnections(model)
            busvalues = map(keys(ports)) do port
                group = P.isac(descriptions[port].domain) ? "bus" : "busdc"
                output[group][string(ports[port])]
            end
            busresult = NamedTuple{keys(ports)}(busvalues)
            P.transform(elemresult, busresult, global_dict, model, P.PMACDC, P.PIACDC)
        end
    end
    return values
end
