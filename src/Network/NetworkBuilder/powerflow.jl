
function Base.convert(bs::NetworkState, ::Type{P.PMACDC})
    _validate_powerflow_domains(bs)

    #PMACDC data + interface
    data = Dict{String, Any}()
    global_dict = P.PowerModelsACDC._get_pu_bases(1000, option_value(bs.options, :voltageBase, 320)) # 3-PH MVA, LL-RMS, Original setting was 100,320
    P.data_init!(data, global_dict)

    global_dict["omega"] = 2*π*50

    ## Adding buses 

    convert!(data, bs.topology, P.PMACDC, global_dict)

    # 2. Fill up the data dictionary with corresponding PM index and bus connections 

    elempitopm = Dict{Symbol, @NamedTuple{pmtype::String, compkey::Int}}() #Maps PM component to element symbol for later use in transformation of results

    for (elemid, stored_element) in pairs(bs.elements) #NamedTuple
        element = _element_for_powerflow(stored_element, elemid, bs.topology)
        # Get sorted connectoins (first AC, then DC)
        connections = sortedcomponentconnections(bs.topology, elemid)
        busidtable = Table(domain = connections.domain, bus = connections.bus)
        sortedbusses = Table(unique(busidtable)).bus #unique(connections.bus) #Take unique busidss (elecdomain+bus integer) and then only provide it with bus information

        # Get the PM component key and update LUT
        pmtype = P.pmtype(element)
        compkey = length(data[pmtype]) + 1
        elempitopm[elemid] = (; pmtype, compkey)

        P.convert!(data, element, P.PMACDC, compkey, sortedbusses, global_dict)
    end

    ensure_slack_bus!(data)
    P.PowerModelsACDC.process_additional_data!(data)

    return data, global_dict, elempitopm
end

function _validate_powerflow_domains(network::NetworkState)
    for (name, element) in pairs(network.elements)
        ports = _port_descriptions(element)
        all(iszero(port.domain) for port in ports) || continue
        rows = filter(row -> row.element == name, network.topology.connections)
        any(row -> row.domain == 1, rows) || continue
        throw(
            ArgumentError(
            "one-conductor passive element :$name was inferred as AC from its " *
            "topology. This representation is supported by frequency-domain " *
            "calculations but has no AC PowerModels conversion; use a " *
            "transformed three-phase element for power flow",
        ),
        )
    end
    return nothing
end

function _element_for_powerflow(
        element::P.Element,
        name::Symbol,
        topology::NetworkTopology
)
    result = deepcopy(element)
    result.symbol = name
    for row in filter(connection -> connection.element == name, topology.connections)
        result.pins[pin_name(row.side, row.terminal)] = row.node
    end
    return result
end

findvalue(componentdata, id) = componentdata[id]

function convert!(data, connections::NetworkTopology, ::Type{P.PMACDC}, global_dict)

    # pm2pi = Dict{Tuple{String, Int}, Int}() # Maps PM bus index to PI bus index for later use in transformation of results
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

function solve_powerflow(network::P.Network, options::NamedTuple)
    if P.is_linear(network)
        @info "Network only consists of linear elements. Skipping power flow."
        return nothing
    end

    global_dict = P.PowerModelsACDC._get_pu_bases(1000, network.voltageBase[1])
    global_dict["omega"] = 2π * 50

    data = P.data_init!(Dict{String, Any}(), global_dict)
    nodes2bus = Dict()
    bus2nodes = Dict()
    elem2comp = Dict()
    comp2elem = Dict()

    ground_nodes = [k for k in keys(network.nets) if startswith(string(k), "gnd")]
    push!(nodes2bus, ground_nodes => "gnd")
    push!(bus2nodes, "gnd" => ground_nodes)

    for element in values(network.elements)
        P.convert!(
            data,
            element,
            P.PMACDC,
            nodes2bus,
            bus2nodes,
            elem2comp,
            comp2elem,
            global_dict
        )
    end

    ensure_slack_bus!(data)
    P.PowerModelsACDC.process_additional_data!(data)

    result = solve_acdcpf(
        data,
        P._PM.ACPPowerModel,
        powerflow_optimizer(options),
        is_bounded_options(options);
        setting = powerflow_setting(options)
    )

    powerflow = (result = result, data = data, nodes2bus = nodes2bus, elem2comp = elem2comp)
    # set_parent_global!(:result, result)
    # set_parent_global!(:data, data)
    # set_parent_global!(:nodes2bus, nodes2bus)
    # set_parent_global!(:elem2comp, elem2comp)
    return powerflow
end

function ensure_slack_bus!(data)
    if 3 in [data["bus"][index]["bus_type"] for index in keys(data["bus"])]
        return data
    end

    @warn "WARNING: No slack bus present. The first PV bus with generator will be set as reference"
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
    P.JuMP.optimize!(pm.model)
    result = P._IM.build_result(pm, P.JuMP.solve_time(pm.model))
    @info result["termination_status"]
    if result["termination_status"] == P.JuMP.MOI.LOCALLY_SOLVED
        @info "Power flow converged succesfully."
    else
        converged_feasible = false
        has_violations = !isempty(P.JuMP.primal_feasibility_report(pm.model; atol = 1e-4))
        if has_violations
            @warn "Violations reported. Entering power flow with increments of setpoints to find a solution."
            for r in 1:5
                P.update_actives_setpoints!(data, -0.0001)
                pm = P._PM.instantiate_model(
                    data,
                    model_type,
                    build_method;
                    ref_extensions = ref_ext,
                    kwargs...
                )
                P.JuMP.set_optimizer(pm.model, optimizer)
                P.JuMP.optimize!(pm.model)
                result = P._IM.build_result(pm, P.JuMP.solve_time(pm.model))
                if result["termination_status"] == P.JuMP.MOI.LOCALLY_SOLVED
                    @info "Power flow converged succesfully after $r increment change."
                    converged_feasible = true
                    break
                elseif isempty(P.JuMP.primal_feasibility_report(pm.model; atol = 1e-4))
                    @info "Power flow converged succesfully after $r increment change. Point is feasible."
                    converged_feasible = true
                    break
                end
            end
            if !converged_feasible
                @warn "Last resort: Relaxing constraints to find a solution and see which constraints are violated."
                result = solve_acdcpf_relax(
                    data, model_type, optimizer, variables; kwargs...)
            end
        else
            @info "Power flow converged succesfully. Point is feasible"
        end
    end

    return result
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

    return result
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
    ((data["busdc"])[busstr])["bus_type"] = 1 # bus type - depends on components 1 is default P
end
