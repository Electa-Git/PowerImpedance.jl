# A converged primal point belongs to one network and one mapped topology.
mutable struct _PowerFlowStart
    topology::Any
    primal::Dict{String, Float64}
end

_PowerFlowStart() = _PowerFlowStart(nothing, Dict{String, Float64}())

"""
$(TYPEDEF)

Store one materialized NetworkBuilder system with numeric component models,
topology, and numerical options.

Construct systems with [`define`](@ref).

$(TYPEDFIELDS)
"""
mutable struct NetworkState
    "Materialized component models indexed by name."
    elements::NamedTuple
    "Net-component incidence relation."
    topology::NetworkTopology
    "Numerical and power-flow options."
    options::NamedTuple
    "Converged primal point for repeated solves of this mapped topology."
    powerflow_start::_PowerFlowStart
end

NetworkState(elements::NamedTuple, topology::NetworkTopology, options::NamedTuple) =
    NetworkState(elements, topology, options, _PowerFlowStart())

function data_init!(data, global_dict)
    data["source_type"] = "matpower"
    data["name"] = "network"
    data["source_version"] = "0.0.0"
    data["per_unit"] = true
    # Monopolar (1) or bipolar and symmetrically grounded monopolar (2)
    data["dcpol"] = P.dcpol
    data["baseMVA"] = global_dict["S"] / 1e6
    data["bus"] = Dict{String, Any}()
    data["im"] = Dict{String, Any}()
    data["busdc"] = Dict{String, Any}()
    data["shunt"] = Dict{String, Any}()     # empty
    data["dcline"] = Dict{String, Any}()    # empty
    data["storage"] = Dict{String, Any}()   # empty
    data["switch"] = Dict{String, Any}()    # empty
    data["load"] = Dict{String, Any}()      # empty
    data["branch"] = Dict{String, Any}()
    data["branchdc"] = Dict{String, Any}()
    data["gen"] = Dict{String, Any}()
	data["im"] = Dict{String, Any}()
    data["sssc"] = Dict{String, Any}()  # empty (avoid warning from PMACDC)
    data["convdc"] = Dict{String, Any}()
    data["pst"] = Dict{String, Any}() ## Empty (Phase shifting transformer)
    data["gendc"] = Dict{String, Any}()
    return data
end

function canonicalize_converter_voltages!(result)
    for converter in values(get(result["solution"], "convdc", Dict()))
        if get(converter, "vmconv", 0.0) < 0
            converter["vmconv"] = -converter["vmconv"]
            angle = rem2pi(converter["vaconv"] + π, RoundNearest)
            converter["vaconv"] = angle == -Float64(π) ? Float64(π) : angle
        end
    end
    return result
end

function accept_feasible_power_flow!(result, model)
    result["termination_status"] == P.MOI.LOCALLY_SOLVED && return true
    P.JuMP.has_values(model) || return false
    residual = maximum(values(P.primal_feasibility_report(model; atol = 0.0)); init = 0.0)
    tolerance = P.JuMP.get_optimizer_attribute(model, "constr_viol_tol")
    if isfinite(residual) && residual <= tolerance
        result["primal_feasible"] = true
        @warn ("Accepting power-flow point with termination status " *
            "$(result["termination_status"]) and maximum primal constraint violation " *
            "$residual (constr_viol_tol = $tolerance).")
        return true
    end
    return false
end

function _prepare_power_flow_start!(start::_PowerFlowStart, data, mapping)
    # Component identities and endpoints identify the topology used for a warm start.
    # Numerical targets may change. The converged point supplies initial values for the
    # rebuilt constraints.
    fields = ("index", "status", "gen_bus", "load_bus", "shunt_bus",
        "storage_bus", "f_bus", "t_bus", "busac_i", "busdc_i", "fbusdc", "tbusdc")
    topology = (mapping, Dict(group => Dict(id => Dict(key => component[key]
        for key in fields if haskey(component, key)) for (id, component) in data[group])
        for group in ("bus", "busdc", "gen", "gendc", "branch", "branchdc", "convdc",
            "load", "shunt", "storage") if haskey(data, group)))
    if !isequal(start.topology, topology)
        empty!(start.primal)
        start.topology = deepcopy(topology)
    end
    return start
end

function _initialize_power_flow!(model, start::_PowerFlowStart)
    variables = P.JuMP.all_variables(model)
    if length(variables) == length(start.primal) &&
       all(variable -> haskey(start.primal, P.JuMP.name(variable)), variables)
        for variable in variables
            P.JuMP.set_start_value(variable, start.primal[P.JuMP.name(variable)])
        end
    else
        empty!(start.primal)
    end
    return nothing
end

function _store_power_flow_start!(start::_PowerFlowStart, model)
    # Store converged primal points. Residual-acceptance and penalty-relaxation results
    # leave the saved point unchanged.
    if P.JuMP.termination_status(model) == P.MOI.LOCALLY_SOLVED
        empty!(start.primal)
        for variable in P.JuMP.all_variables(model)
            start.primal[P.JuMP.name(variable)] = P.JuMP.value(variable)
        end
    end
    return nothing
end

# Function to slightly shift the setpoints of the active elements to nudge the solver
# towards a solution. "delta" = percentage change
function update_actives_setpoints!(data, delta)

	# Slightly shift the reactive power setpoints for the converters, if any
	if haskey(data, "convdc")
		# TODO handle Vac control after its implementation.
		for conv_index in keys(data["convdc"])

			data["convdc"][conv_index]["Q_g"] != 0.0 ?
			data["convdc"][conv_index]["Q_g"] *= (1+delta) :
			data["convdc"][conv_index]["Q_g"] += delta# This will impact Q, QV-droop control
		end
	end
	# Slightly shift the Vm setpoints for the synchronous machines, if any
	for gen_index in keys(data["gen"])
		bus_gen = data["gen"][gen_index]["gen_bus"]
		if data["bus"][string(bus_gen)]["bus_type"] == 2 # PV-bus
			# This will slightly shift the Voltage reference for the SG
			data["gen"][gen_index]["vg"] *= (1+delta)
		end
	end


end

function Base.convert(bs::NetworkState, ::Type{P.PMACDC})
    _validate_powerflow_domains(bs)
    data = Dict{String, Any}()
    global_dict = P.PowerModelsACDC._get_pu_bases(1000,
        option_value(bs.options, :voltageBase, DEFAULT_VOLTAGE_BASE))
    data_init!(data, global_dict)
    global_dict["omega"] = 2*π*50
    convert!(data, bs.topology, P.PMACDC, global_dict)
    elempitopm = Dict{Symbol, @NamedTuple{pmtype::String, compkey::Int}}()

    records = map(collect(pairs(bs.elements))) do (name, model)
        _element_call(name) do
            rows = filter(row -> row.component == name, bs.topology.connections)
            ports = _powerflow_ports(model, rows)
            pmtype = P.pmtype(model, rows)
            (; name, model, ports, pmtype)
        end
    end
    _infer_transformer_voltage_levels!(global_dict, records)
    for record in records
        (; name, model, ports, pmtype) = record
        compkey = length(data[pmtype]) + 1
        elempitopm[name] = (; pmtype, compkey)
        key = (; name, index = compkey, pmtype)
        _element_call(name) do
            P.convert!(data, model, P.PMACDC, key, ports, global_dict)
        end
    end
    ensure_slack_bus!(data)
    P.PowerModelsACDC.process_additional_data!(data)
    return data, global_dict, elempitopm
end

function _powerflow_ports(model, rows)
    names = keys(P.electricalconnections(model))
    buses = map(names) do port
        ids = unique(row.bus for row in rows if row.port == port)
        length(ids) == 1 ||
            throw(ArgumentError("port :$port must connect to one power-flow bus"))
        only(ids)
    end
    return NamedTuple{names}(buses)
end

function _validate_powerflow_domains(network::NetworkState)
    for (name, model) in pairs(network.elements)
        _element_call(name) do
            ports = P.electricalconnections(model)
            for row in network.topology.connections
                row.component == name || continue
                _domain_number(ports[row.port].domain) == row.domain && continue
                throw(ArgumentError(
                    "one-conductor passive element was inferred as AC from its " *
                    "topology. This representation is supported by frequency-domain " *
                    "calculations but has no AC PowerModels conversion; use a " *
                    "transformed three-phase element for power flow"))
            end
        end
    end
    return nothing
end

findvalue(componentdata, id) = componentdata[id]

function convert!(data, connections::NetworkTopology, ::Type{P.PMACDC}, global_dict)

    # pm2pi = Dict{Tuple{String, Int}, Int}() # Maps PM bus index to PI bus index for later
    # use in transformation of results
    # pi2pm = Dict{Int, Tuple{String, Int}}()

    # Split up for improved speed inside for loop (same function)
    acconn = acconnections(connections)
    acbusses = unique(acconn.bus) # Their index is busid
    dcconn = dcconnections(connections)
    dcbusses = unique(dcconn.bus)

    # AC-bus generation
    for (i, bus) in enumerate(acbusses)
        # pm2pi[("bus", i)] = bus
        addbus!(data, bus, global_dict, Val(:AC))
    end

    # DC-bus generation
    for (i, bus) in enumerate(dcbusses)
        # pm2pi[("busdc", i)] = bus
        addbus!(data, bus, global_dict, Val(:DC))
    end

    # return pm2pi
end

function ensure_slack_bus!(data)
    if 3 in [data["bus"][index]["bus_type"] for index in keys(data["bus"])]
        return data
    end

    @warn ("WARNING: No slack bus present. The first PV bus with generator " *
        "will be set as reference")
    for gen_index in keys(data["gen"])
        bus_gen = data["gen"][gen_index]["gen_bus"]
        if data["bus"][string(bus_gen)]["bus_type"] == 2
            P.set_bus_type(data["bus"][string(bus_gen)], 3)
            return data
        end
        error("No PV bus with generator found. Update your problem!")
    end

    return data
end

function solve_acdcpf(
        data::Dict{String, Any},
        model_type::Type,
        optimizer,
        variables::NamedTuple,
        start::_PowerFlowStart = _PowerFlowStart();
        kwargs...
)
    ref_ext = [
        P._PMACDC.add_ref_dcgrid!,
        P._PMACDC.ref_add_pst!,
        P._PMACDC.ref_add_sssc!,
        P._PMACDC.ref_add_flex_load!,
        P._PMACDC.ref_add_gendc!,
        P._PMACDC.ref_add_im!
    ]
    build_method = pm -> build_acdcpf(pm, variables)
    pm = P._PM.instantiate_model(
        data,
        model_type,
        build_method;
        ref_extensions = ref_ext,
        kwargs...
    )

    P.JuMP.set_optimizer(pm.model, optimizer)
    _initialize_power_flow!(pm.model, start)
    P.JuMP.optimize!(pm.model)
    _store_power_flow_start!(start, pm.model)
    result = P._IM.build_result(pm, P.JuMP.solve_time(pm.model))
    @info result["termination_status"]
    if accept_feasible_power_flow!(result, pm.model)
        @info "Power flow converged successfully."
    else
        converged_feasible = false
        has_violations = !isempty(P.JuMP.primal_feasibility_report(pm.model; atol = 1e-4))
        if has_violations
            @warn ("Violations reported. Entering power flow with increments of " *
                "setpoints to find a solution.")
            for r in 1:5
                update_actives_setpoints!(data, -0.0001)
                pm = P._PM.instantiate_model(
                    data,
                    model_type,
                    build_method;
                    ref_extensions = ref_ext,
                    kwargs...
                )
                P.JuMP.set_optimizer(pm.model, optimizer)
                P.JuMP.optimize!(pm.model)
                _store_power_flow_start!(start, pm.model)
                result = P._IM.build_result(pm, P.JuMP.solve_time(pm.model))
                if accept_feasible_power_flow!(result, pm.model)
                    @info "Power flow converged successfully after $r increment change."
                    converged_feasible = true
                    break
                elseif isempty(P.JuMP.primal_feasibility_report(pm.model; atol = 1e-4))
                    @info ("Power flow converged successfully after $r increment " *
                        "change. Point is feasible.")
                    converged_feasible = true
                    break
                end
            end
            if !converged_feasible
                @warn ("Last resort: Relaxing constraints to find a solution and " *
                    "see which constraints are violated.")
                result = solve_acdcpf_relax(
                    data, model_type, optimizer, variables; kwargs...)
            end
        else
            @info "Power flow converged successfully. Point is feasible"
        end
    end

    return canonicalize_converter_voltages!(result)
end

function build_acdcpf(pm::P._PM.AbstractPowerModel, variables::NamedTuple)
    P._PM.variable_bus_voltage(
        pm,
        bounded = variable_bounded(variables, :bus_voltage, false)
    )
    P._PM.variable_gen_power(pm, bounded = variable_bounded(variables, :gen_power, false))
    P._PM.variable_branch_power(
        pm,
        bounded = variable_bounded(variables, :branch_power, false)
    )
    P._PM.variable_storage_power(
        pm,
        bounded = variable_bounded(variables, :storage_power, false)
    )

    if typeof(pm) <: P._PM.SOCBFPowerModel
        P._PM.variable_branch_current(
            pm,
            bounded = variable_bounded(variables, :branch_current, false)
        )
    end

    P._PMACDC.variable_active_dcbranch_flow(
        pm,
        bounded = variable_bounded(variables, :active_dcbranch_flow, false)
    )
    P._PMACDC.variable_dcbranch_current(
        pm,
        bounded = variable_bounded(variables, :dcbranch_current, false)
    )
    P._PMACDC.variable_dc_converter(
        pm,
        bounded = variable_bounded(variables, :dc_converter, false)
    )
    P._initialize_converter_current!(pm)
    P._PMACDC.variable_dcgrid_voltage_magnitude(
        pm,
        bounded = variable_bounded(variables, :dcgrid_voltage_magnitude, false)
    )
    P._PMACDC.variable_dcgenerator_power(
        pm;
        bounded = variable_bounded(variables, :dcgenerator_power, false)
    )
    P._PMACDC.variable_flexible_demand(
        pm,
        bounded = variable_bounded(variables, :flexible_demand, false)
    )
    P._PMACDC.variable_pst(pm, bounded = variable_bounded(variables, :pst, false))
    P._PMACDC.variable_sssc(pm, bounded = variable_bounded(variables, :sssc, false))
    P._PMACDC.variable_im(pm, bounded = variable_bounded(variables, :im, false))

    P._PM.constraint_model_voltage(pm)
    P._PMACDC.constraint_voltage_dc(pm)

    for (i, bus) in P._PM.ref(pm, :ref_buses)
        @assert bus["bus_type"] == 3
        P._PM.constraint_theta_ref(pm, i)
        P._PM.constraint_voltage_magnitude_setpoint(pm, i)
    end

    for (i, bus) in P._PM.ref(pm, :bus)
        P._PMACDC.constraint_power_balance_ac(pm, i)
        if length(P._PM.ref(pm, :bus_gens, i)) > 0 && !(i in P._PM.ids(pm, :ref_buses))
            for j in P._PM.ref(pm, :bus_gens, i)
                P._PM.constraint_gen_setpoint_active(pm, j)
                if bus["bus_type"] == 2
                    P._PM.constraint_voltage_magnitude_setpoint(pm, i)
                elseif bus["bus_type"] == 1
                    P._PM.constraint_gen_setpoint_active(pm, j)
                end
            end
        end
    end

    for i in P._PM.ids(pm, :branch)
        if typeof(pm) <: P._PM.SOCBFPowerModel
            P._PM.constraint_power_losses(pm, i)
            P._PM.constraint_voltage_magnitude_difference(pm, i)
            P._PM.constraint_branch_current(pm, i)
        else
            P._PM.constraint_ohms_yt_from(pm, i)
            P._PM.constraint_ohms_yt_to(pm, i)
        end
    end

    for i in P._PM.ids(pm, :flex_load)
        P._PMACDC.constraint_total_flexible_demand(pm, i)
    end

    for i in P._PM.ids(pm, :fixed_load)
        P._PMACDC.constraint_total_fixed_demand(pm, i)
    end

    for i in P._PM.ids(pm, :busdc)
        P._PMACDC.constraint_power_balance_dc(pm, i)
    end

    for i in P._PM.ids(pm, :branchdc)
        P._PMACDC.constraint_ohms_dc_branch(pm, i)
    end

    for i in P._PM.ids(pm, :im)
        P._PMACDC.constraint_im_stator(pm, i)
        P._PMACDC.constraint_im_rotor_inductance(pm, i)
        P._PMACDC.constraint_im_magnetisation(pm, i)
        P._PMACDC.constraint_im_slip(pm, i)
    end

    if !isempty(P._PM.ids(pm, :gendc))
        for i in P._PM.ids(pm, :gendc)
            P._PMACDC.constraint_dcgenerator_voltage_and_power(pm, i)
        end
    end

    for (c, conv) in P._PM.ref(pm, :convdc)
        P._PMACDC.constraint_conv_transformer(pm, c)
        P._PMACDC.constraint_conv_reactor(pm, c)
        P._PMACDC.constraint_conv_filter(pm, c)
        if conv["type_dc"] == 2
            P._PMACDC.constraint_dc_voltage_magnitude_setpoint(pm, c)
        elseif conv["type_dc"] == 3 || conv["type_dc"] == 4
            if typeof(pm) <: P._PM.AbstractACPModel || typeof(pm) <: P._PM.AbstractACRModel
                P._PMACDC.constraint_dc_droop_control(pm, c)
            else
                P._PMACDC.Memento.warn(
                    P._PM._LOGGER,
                    join([
                        "Droop only defined for ACP and ACR formulations, converter ",
                        c,
                        " will be treated as type 2"
                    ])
                )
                P._PMACDC.constraint_dc_voltage_magnitude_setpoint(pm, c)
            end
        else
            P._PMACDC.constraint_active_conv_setpoint(pm, c)
        end
        if conv["type_ac"] == 2
            if haskey(conv, "acq_droop") && conv["acq_droop"] == 1
                P._PMACDC.constraint_ac_voltage_droop_control(pm, c)
            else
                P._PM.constraint_voltage_magnitude_setpoint(pm, conv["busac_i"])
            end
        else
            P._PMACDC.constraint_reactive_conv_setpoint(pm, c)
        end
        P._PMACDC.constraint_converter_losses(pm, c)
        P._PMACDC.constraint_converter_current(pm, c)
    end
end

function solve_acdcpf_relax(
        data::Dict{String, Any},
        model_type::Type,
        optimizer,
        variables::NamedTuple;
        kwargs...
)
    ref_ext = [
        P._PMACDC.add_ref_dcgrid!,
        P._PMACDC.ref_add_pst!,
        P._PMACDC.ref_add_sssc!,
        P._PMACDC.ref_add_flex_load!,
        P._PMACDC.ref_add_gendc!,
        P._PMACDC.ref_add_im!
    ]
    build_method = pm -> build_acdcpf(pm, variables)
    pm = P._PM.instantiate_model(
        data,
        model_type,
        build_method;
        ref_extensions = ref_ext,
        kwargs...
    )
    P.JuMP.set_optimizer(pm.model, optimizer)

    map = P.JuMP.relax_with_penalty!(pm.model; default = 2.0)
    P.JuMP.optimize!(pm.model)
    result = P._IM.build_result(pm, P.JuMP.solve_time(pm.model))

    for (con, penalty) in map
        violation = P.JuMP.value(penalty)
        if abs(violation) > 1e-6
            @warn "ATTENTION! Constraint `$(P.JuMP.name(con))` is violated by $violation"
            # error("Power flow constraints are violated.")
        end
    end

    return canonicalize_converter_voltages!(result)
end

function addbus!(data, bus, global_dict, ::Val{:AC})
    busstr = string(bus)
    V = 1.0
    bustype = 1 # Default PQ bus, can be updated later if generator or shunt is connected

    (data["bus"])[busstr] = Dict{String, Any}()
    ((data["bus"])[busstr])["source_id"] = Any["bus", bus]
    ((data["bus"])[busstr])["index"] = bus
    ((data["bus"])[busstr])["bus_i"] = bus
    ((data["bus"])[busstr])["zone"] = 1
    ((data["bus"])[busstr])["area"] = 1
    ((data["bus"])[busstr])["vmin"] = 0.9*V
    ((data["bus"])[busstr])["vmax"] = 1.1*V
    ((data["bus"])[busstr])["vm"] = V
    ((data["bus"])[busstr])["va"] = 0
    ((data["bus"])[busstr])["base_kv"] = global_dict["V"] / 1e3
    ((data["bus"])[busstr])["bus_type"] = bustype
end

function addbus!(data, bus, global_dict, ::Val{:DC})
    busstr = string(bus)

    (data["busdc"])[busstr] = Dict{String, Any}()
    ((data["busdc"])[busstr])["busdc_i"] = bus
    ((data["busdc"])[busstr])["source_id"] = Any["busdc", bus]
    ((data["busdc"])[busstr])["grid"] = 1
    ((data["busdc"])[busstr])["index"] = bus
    ((data["busdc"])[busstr])["Cdc"] = 0
    ((data["busdc"])[busstr])["Vdc"] = 1
    ((data["busdc"])[busstr])["Vdcmax"] = 1.1
    ((data["busdc"])[busstr])["Vdcmin"] = 0.9
    ((data["busdc"])[busstr])["Pdc"] = 0
    ((data["busdc"])[busstr])["basekVdc"] = global_dict["V"] / 1e3
    # bus type - depends on components 1 is default P
    ((data["busdc"])[busstr])["bus_type"] = 1
end


function _voltage_links!(edges, sources, transformers, model::P.AbstractElementModel,
        name, ports, pmtype)
    return nothing
end

function _voltage_links!(edges, sources, transformers, model::P.Source,
        name, ports, pmtype)
    haskey(ports, :ac) && push!(sources, ports.ac => P.inputvalues(model).v)
    return nothing
end

function _voltage_links!(edges, sources, transformers,
        model::Union{P.Impedance, P.Transmission_line}, name, ports, pmtype)
    pmtype == "branch" && ports.side1 != ports.side2 || return nothing
    push!(get!(edges, ports.side1, Tuple{Any, Float64, Bool}[]),
        (ports.side2, 1.0, true))
    push!(get!(edges, ports.side2, Tuple{Any, Float64, Bool}[]),
        (ports.side1, 1.0, false))
    return nothing
end

function _voltage_links!(edges, sources, transformers, model::P.Transformer,
        name, ports, pmtype)
    primary, secondary = ports.side1, ports.side2
    push!(transformers, (name, primary, secondary))
    primary != secondary || return nothing
    ratio = model.V₁ᵒ == model.V₂ᵒ == 0 ? model.n : model.V₁ᵒ / model.V₂ᵒ
    push!(get!(edges, primary, Tuple{Any, Float64, Bool}[]), (secondary, ratio, true))
    push!(get!(edges, secondary, Tuple{Any, Float64, Bool}[]), (primary, ratio, false))
    return nothing
end

function _infer_transformer_voltage_levels!(global_dict, records)
    sources = Pair{Int, Float64}[]
    transformers = Tuple{Symbol, Int, Int}[]
    edges = Dict{Any, Vector{Tuple{Any, Float64, Bool}}}()
    for record in records
        _element_call(record.name) do
            _voltage_links!(edges, sources, transformers, record.model,
                record.name, record.ports, record.pmtype)
        end
    end
    isempty(transformers) && return nothing
    voltage_base = global_dict["V"] / 1e3
    levels = Dict{Any, Float64}()
    queue = Any[]

    function assign_level!(bus, level)
        if !haskey(levels, bus)
            levels[bus] = level
            push!(queue, bus)
        elseif abs(level - levels[bus]) > 0.01 * levels[bus]
            @warn "Conflicting transformer voltage levels at bus $bus: " *
                "$(levels[bus]) kV and $level kV; retaining the first level."
        end
    end

    for (bus, voltage_peak) in sources
        if !ismissing(voltage_peak) && isfinite(voltage_peak) && voltage_peak > 0
            voltage = voltage_peak / sqrt(2)
            if !(0.9 * voltage_base <= voltage <= 1.1 * voltage_base)
                assign_level!(bus, voltage)
            end
        end
    end

    index = 1
    function propagate!()
        while index <= length(queue)
            bus = queue[index]
            for (other, ratio, forward) in get(edges, bus, Tuple{Any, Float64, Bool}[])
                level = forward ? levels[bus] / ratio : levels[bus] * ratio
                assign_level!(other, level)
            end
            index += 1
        end
    end
    propagate!()
    for (_, primary, _) in transformers
        if !haskey(levels, primary)
            assign_level!(primary, voltage_base)
            propagate!()
        end
    end

    global_dict["transformer_voltage_levels"] = Dict(
        name => (get(levels, primary, voltage_base), get(levels, secondary, voltage_base))
        for (name, primary, secondary) in transformers)
    global_dict["transformer_voltage_bounded_buses"] = Set{Int}()
    return nothing
end
