module NetworkBuilder

export pin, ⟷, ↔

const P = parentmodule(@__MODULE__)

struct Pin
	element::Symbol
	name::Symbol
end

struct Connection
	endpoints::Vector{Any}
end

mutable struct BuilderState
	elements::NamedTuple
	connections::Tuple
	options::NamedTuple
	network::P.Network
	powerflow::Any
end

pin(element::Symbol, name) = Pin(element, Symbol(name))

function connection_endpoints(connection::Connection)
	return connection.endpoints
end

function connection_endpoints(endpoint::Union{Pin, Symbol})
	return Any[endpoint]
end

function connection_endpoints(endpoint::AbstractString)
	return Any[Symbol(endpoint)]
end

function ⟷(left, right)
	return Connection(vcat(connection_endpoints(left), connection_endpoints(right)))
end

↔(left, right) = left ⟷ right

function define(elements::NamedTuple, connections::Tuple; options = (;))
	network = build_network(elements, connections, options)
	return BuilderState(elements, connections, options, network, nothing)
end

function update!(
	builder::BuilderState;
	elements = builder.elements,
	connections = builder.connections,
	options = builder.options,
	powerflow = nothing,
)
	builder.elements = elements
	builder.connections = connections
	builder.options = options
	builder.network = build_network(elements, connections, options)
	builder.powerflow = nothing

	if powerflow !== nothing
		set_point!(builder; powerflow)
	end

	return (network = builder.network, powerflow = builder.powerflow)
end

function solve(builder::BuilderState)
	powerflow = solve_powerflow(builder.network, builder.options)

	if powerflow !== nothing
		apply_powerflow_setpoints!(builder.network, powerflow)
		powerflow = cache_active_setpoint_values(builder.network, powerflow)
	end

	builder.powerflow = powerflow
	return (network = builder.network, powerflow = builder.powerflow)
end


function set_point!(builder::BuilderState; powerflow = builder.powerflow)
	builder.powerflow = powerflow

	if powerflow !== nothing
		restore_active_setpoint_values!(builder.network, powerflow)
	end

	return (network = builder.network, powerflow = builder.powerflow)
end

function cache_active_setpoint_values(network::P.Network, powerflow::NamedTuple)
	return merge(powerflow, (; active_setpoint_values = active_setpoint_values(network)))
end

function active_setpoint_values(network::P.Network)
	values = Dict{Symbol, Any}()

	for (name, element) in pairs(network.elements)
		if P.is_converter(element) || P.is_generator(element)
			values[name] = deepcopy(element.element_value)
		end
	end

	return values
end

function restore_active_setpoint_values!(network::P.Network, powerflow::NamedTuple)
	hasproperty(powerflow, :active_setpoint_values) ||
		throw(
			ArgumentError(
				"Cached power flow does not contain active setpoint values. " *
				"Run NetworkBuilder.solve(builder) first and reuse the returned powerflow.",
			),
		)

	for (name, element) in pairs(network.elements)
		if (P.is_converter(element) || P.is_generator(element)) &&
		   !haskey(powerflow.active_setpoint_values, name)
			throw(
				ArgumentError("Cached power flow has no active setpoint value for :$name."),
			)
		end
	end

	for (name, cached_value) in pairs(powerflow.active_setpoint_values)
		haskey(network.elements, name) ||
			throw(
				ArgumentError(
					"Cached power flow references missing active element :$name.",
				),
			)

		element = network.elements[name]

		(P.is_converter(element) || P.is_generator(element)) ||
			throw(
				ArgumentError("Cached power flow expected :$name to be an active element."),
			)

		typeof(element.element_value) === typeof(cached_value) ||
			throw(
				ArgumentError(
					"Cached active setpoint value for :$name has type $(typeof(cached_value)), " *
					"but the rebuilt element has type $(typeof(element.element_value)).",
				),
			)

		element.element_value = deepcopy(cached_value)
	end

	sync_parent_powerflow_globals!(powerflow)
	return network
end

function sync_parent_powerflow_globals!(powerflow::NamedTuple)
	set_parent_global!(:result, powerflow.result)
	set_parent_global!(:data, powerflow.data)
	set_parent_global!(:nodes2bus, powerflow.nodes2bus)
	set_parent_global!(:elem2comp, powerflow.elem2comp)
	return powerflow
end

function build_network(elements::NamedTuple, connections::Tuple, options::NamedTuple)
	network = P.Network()
	network.voltageBase[1] = option_value(options, :voltageBase, network.voltageBase[1])

	for (name, element) in pairs(elements)
		element isa P.Element ||
			throw(ArgumentError("NetworkBuilder element :$name must be an Element."))
		P.add!(network, name, element)
	end

	for connection in connections
		connection isa Connection ||
			throw(ArgumentError("NetworkBuilder connections must be created with ⟷ or ↔."))

		endpoints = network_endpoints(network, elements, connection)
		isempty(endpoints) && continue

		P.connect!(network, endpoints...)
	end

	P.check_lumped_elements(network)
	P.connect!(network)
	return network
end

function network_endpoints(
	network::P.Network,
	elements::NamedTuple,
	connection::Connection,
)
	endpoints = Any[]

	for endpoint in connection.endpoints
		resolved = network_endpoint(network, elements, endpoint)
		resolved === nothing || push!(endpoints, resolved)
	end

	return Tuple(endpoints)
end

function network_endpoint(
	network::P.Network,
	elements::NamedTuple,
	endpoint::Pin,
)
	hasproperty(elements, endpoint.element) ||
		throw(ArgumentError("Unknown element :$(endpoint.element) in connection endpoint."))

	if !haskey(network.elements, endpoint.element)
		element = getproperty(elements, endpoint.element)

		element.connection == false && return nothing

		throw(
			ArgumentError(
				"Element :$(endpoint.element) was declared but was not added to the network.",
			),
		)
	end

	haskey(network.elements[endpoint.element].pins, endpoint.name) ||
		throw(
			ArgumentError("Unknown pin $(endpoint.name) on element :$(endpoint.element)."),
		)

	return (endpoint.element, endpoint.name)
end

function network_endpoint(::P.Network, ::NamedTuple, endpoint::Symbol)
	return endpoint
end

function option_value(options::NamedTuple, name::Symbol, default)
	return hasproperty(options, name) ? getproperty(options, name) : default
end

function set_parent_global!(name::Symbol, value)
	Core.eval(P, Expr(:(=), name, value))
	return value
end

function solve_powerflow(network::P.Network, options::NamedTuple)
	set_parent_global!(:ang_min, deg2rad(360))
	set_parent_global!(:ang_max, deg2rad(-360))

	if P.is_linear(network)
		println("Network only consists of linear elements. Skipping power flow.")
		return nothing
	end

	global_dict = P.PowerModelsACDC.get_pu_bases(1000, network.voltageBase[1])
	global_dict["omega"] = 2π * 50

	data = P.data_init(Dict{String, Any}(), global_dict)
	nodes2bus = Dict()
	bus2nodes = Dict()
	elem2comp = Dict()
	comp2elem = Dict()

	ground_nodes = [k for k in keys(network.nets) if startswith(string(k), "gnd")]
	push!(nodes2bus, ground_nodes => "gnd")
	push!(bus2nodes, "gnd" => ground_nodes)

	for element in values(network.elements)
		P.make_powerflow!(
			data,
			nodes2bus,
			bus2nodes,
			elem2comp,
			comp2elem,
			element,
			global_dict,
		)
	end

	ensure_slack_bus!(data)
	P.PowerModelsACDC.process_additional_data!(data)

	result = solve_acdcpf(
		data,
		P._PM.ACPPowerModel,
		powerflow_optimizer(options),
		variable_options(options);
		setting = powerflow_setting(options),
	)

	powerflow = (result = result, data = data, nodes2bus = nodes2bus, elem2comp = elem2comp)
	set_parent_global!(:result, result)
	set_parent_global!(:data, data)
	set_parent_global!(:nodes2bus, nodes2bus)
	set_parent_global!(:elem2comp, elem2comp)
	return powerflow
end

function ensure_slack_bus!(data)
	if 3 in [data["bus"][index]["bus_type"] for index in keys(data["bus"])]
		return data
	end

	println(
		"WARNING: No slack bus present. The first PV bus with generator will be set as reference",
	)
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

function powerflow_options(options::NamedTuple)
	return option_value(options, :power_flow, (;))
end

function variable_options(options::NamedTuple)
	return option_value(powerflow_options(options), :variables, (;))
end

function variable_bounded(variables::NamedTuple, name::Symbol, default::Bool)
	return option_value(variables, name, default)
end

function powerflow_optimizer(options::NamedTuple)
	attributes = Dict{String, Any}(
		"tol" => 1e2,
		"dual_inf_tol" => 1e-1,
		"constr_viol_tol" => 1e-3,
		"compl_inf_tol" => 1e3,
		"print_level" => 5,
		"max_iter" => 100,
		"grad_f_constant" => "yes",
		"recalc_y" => "yes",
		"bound_relax_factor" => 1e-8,
		"expect_infeasible_problem" => "yes",
	)

	user_attributes = option_value(powerflow_options(options), :optimizer, (;))
	for (name, value) in pairs(user_attributes)
		attributes[string(name)] = value
	end

	return P.JuMP.optimizer_with_attributes(P.Ipopt.Optimizer, attributes...)
end

function powerflow_setting(options::NamedTuple)
	setting = option_value(powerflow_options(options), :setting, nothing)
	return setting === nothing ?
		   Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => false) :
		   setting
end

function build_acdcpf(pm::P._PM.AbstractPowerModel, variables::NamedTuple)
	P._PM.variable_bus_voltage(
		pm,
		bounded = variable_bounded(variables, :bus_voltage, true),
	)
	P._PM.variable_gen_power(pm, bounded = variable_bounded(variables, :gen_power, false))
	P._PM.variable_branch_power(
		pm,
		bounded = variable_bounded(variables, :branch_power, false),
	)
	P._PM.variable_storage_power(
		pm,
		bounded = variable_bounded(variables, :storage_power, false),
	)

	if typeof(pm) <: P._PM.SOCBFPowerModel
		P._PM.variable_branch_current(
			pm,
			bounded = variable_bounded(variables, :branch_current, false),
		)
	end

	P._PMACDC.variable_active_dcbranch_flow(
		pm,
		bounded = variable_bounded(variables, :active_dcbranch_flow, false),
	)
	P._PMACDC.variable_dcbranch_current(
		pm,
		bounded = variable_bounded(variables, :dcbranch_current, false),
	)
	P._PMACDC.variable_dc_converter(
		pm,
		bounded = variable_bounded(variables, :dc_converter, false),
	)
	P._PMACDC.variable_dcgrid_voltage_magnitude(
		pm,
		bounded = variable_bounded(variables, :dcgrid_voltage_magnitude, false),
	)
	P._PMACDC.variable_dcgenerator_power(
		pm;
		bounded = variable_bounded(variables, :dcgenerator_power, false),
	)
	P._PMACDC.variable_flexible_demand(
		pm,
		bounded = variable_bounded(variables, :flexible_demand, false),
	)
	P._PMACDC.variable_pst(pm, bounded = variable_bounded(variables, :pst, false))
	P._PMACDC.variable_sssc(pm, bounded = variable_bounded(variables, :sssc, false))

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
				P._PM.Memento.warn(
					P._PM._LOGGER,
					join([
						"Droop only defined for ACP and ACR formulations, converter ",
						c,
						" will be treated as type 2",
					]),
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

function solve_acdcpf(
	data::Dict{String, Any},
	model_type::Type,
	optimizer,
	variables::NamedTuple;
	kwargs...,
)
	ref_ext = [
		P._PMACDC.add_ref_dcgrid!,
		P._PMACDC.ref_add_pst!,
		P._PMACDC.ref_add_sssc!,
		P._PMACDC.ref_add_flex_load!,
		P._PMACDC.ref_add_gendc!,
	]
	build_method = pm -> build_acdcpf(pm, variables)
	pm = P._PM.instantiate_model(
		data,
		model_type,
		build_method;
		ref_extensions = ref_ext,
		kwargs...,
	)

	P.JuMP.set_optimizer(pm.model, optimizer)
	P.JuMP.optimize!(pm.model)
	result = P._IM.build_result(pm, P.JuMP.solve_time(pm.model))
	println(result["termination_status"])
	if result["termination_status"] == P.JuMP.MOI.LOCALLY_SOLVED
		println("Power flow converged succesfully.")
	else
		converged_feasible = false
		has_violations = !isempty(P.JuMP.primal_feasibility_report(pm.model; atol = 1e-4))
		if has_violations
			println(
				"Violations reported. Entering power flow with increments of setpoints to find a solution.",
			)
			for r ∈ 1:5
				P.update_actives_setpoints!(data, -0.0001)
				pm = P._PM.instantiate_model(
					data,
					model_type,
					build_method;
					ref_extensions = ref_ext,
					kwargs...,
				)
				P.JuMP.set_optimizer(pm.model, optimizer)
				P.JuMP.optimize!(pm.model)
				result = P._IM.build_result(pm, P.JuMP.solve_time(pm.model))
				if result["termination_status"] == P.JuMP.MOI.LOCALLY_SOLVED
					println("Power flow converged succesfully after $r increment change.")
					converged_feasible = true
					break
				elseif isempty(P.JuMP.primal_feasibility_report(pm.model; atol = 1e-4))
					println(
						"Power flow converged succesfully after $r increment change. Point is feasible.",
					)
					converged_feasible = true
					break
				end
			end
			if !converged_feasible
				println(
					"Last resort: Relaxing constraints to find a solution and see which constraints are violated.",
				)
				result =
					solve_acdcpf_relax(data, model_type, optimizer, variables; kwargs...)
			end
		else
			println("Power flow converged succesfully. Point is feasible")
		end
	end

	return result
end

function solve_acdcpf_relax(
	data::Dict{String, Any},
	model_type::Type,
	optimizer,
	variables::NamedTuple;
	kwargs...,
)
	ref_ext = [
		P._PMACDC.add_ref_dcgrid!,
		P._PMACDC.ref_add_pst!,
		P._PMACDC.ref_add_sssc!,
		P._PMACDC.ref_add_flex_load!,
		P._PMACDC.ref_add_gendc!,
		P._PMACDC.ref_add_im!,
	]
	build_method = pm -> build_acdcpf(pm, variables)
	pm = P._PM.instantiate_model(
		data,
		model_type,
		build_method;
		ref_extensions = ref_ext,
		kwargs...,
	)
	P.JuMP.set_optimizer(pm.model, optimizer)

	map = P.JuMP.relax_with_penalty!(pm.model; default = 2.0)
	P.JuMP.optimize!(pm.model)
	result = P._IM.build_result(pm, P.JuMP.solve_time(pm.model))

	for (con, penalty) in map
		violation = P.JuMP.value(penalty)
		if abs(violation) > 1e-6
			println("ATTENTION! Constraint `$(P.JuMP.name(con))` is violated by $violation")
			error("Power flow constraints are violated.")
		end
	end

	return result
end

function apply_powerflow_setpoints!(network::P.Network, powerflow::NamedTuple)
	result = powerflow.result
	data = powerflow.data
	nodes2bus = powerflow.nodes2bus
	elem2comp = powerflow.elem2comp
	global_dict = P.PowerModelsACDC.get_pu_bases(1000, network.voltageBase[1])
	global_dict["omega"] = 2π * 50

	for element in values(network.elements)
		if !(P.is_converter(element) || P.is_generator(element))
			continue
		end

		haskey(elem2comp, element.symbol) ||
			throw(
				ArgumentError(
					"Cached power flow has no component mapping for :$(element.symbol).",
				),
			)

		comp_type, key = elem2comp[element.symbol]
		elem_dict = result["solution"][comp_type][string(key)]

		if P.is_converter(element)
			dc_node = P.make_node(element, 1)
			ac_node = P.make_node(element, 2)

			haskey(nodes2bus, dc_node) ||
				throw(
					ArgumentError(
						"Cached power flow has no DC bus mapping for :$(element.symbol).",
					),
				)
			haskey(nodes2bus, ac_node) ||
				throw(
					ArgumentError(
						"Cached power flow has no AC bus mapping for :$(element.symbol).",
					),
				)

			_, dc_bus = nodes2bus[dc_node]
			_, ac_bus = nodes2bus[ac_node]

			Pdc = elem_dict["pdc"] * global_dict["S"] / 1e6
			Vm =
				(result["solution"]["bus"][string(ac_bus)]["vm"] * global_dict["V"] / 1e3) *
				sqrt(2)
			θ = result["solution"]["bus"][string(ac_bus)]["va"]
			Vdc =
				result["solution"]["busdc"][string(dc_bus)]["vm"] *
				(data["dcpol"] * global_dict["V"] / 1e3)
			Pac = -elem_dict["pgrid"] * global_dict["S"] / 1e6
			Qac = elem_dict["qgrid"] * global_dict["S"] / 1e6

			P.update!(element.element_value, Vm, θ, Pac, Qac, Vdc, Pdc)
		elseif P.is_generator(element)
			ac_node = non_ground_node(element, nodes2bus)

			haskey(nodes2bus, ac_node) ||
				throw(
					ArgumentError(
						"Cached power flow has no AC bus mapping for :$(element.symbol).",
					),
				)

			_, ac_bus = nodes2bus[ac_node]

			Pgen = elem_dict["pg"] * global_dict["S"] / 1e6
			Qgen = elem_dict["qg"] * global_dict["S"] / 1e6
			Vm =
				(result["solution"]["bus"][string(ac_bus)]["vm"] * global_dict["V"] / 1e3) *
				sqrt(2)
			θ = result["solution"]["bus"][string(ac_bus)]["va"]

			P.update!(element.element_value, Pgen, Qgen, Vm, θ)
		end
	end

	sync_parent_powerflow_globals!(powerflow)
	return network
end

function non_ground_node(element::P.Element, nodes2bus)
	ground_nodes = Set{Symbol}()
	for (node, bus) in nodes2bus
		if bus == "gnd"
			append!(ground_nodes, node)
		end
	end

	return Set(node for node in values(element.pins) if !(node in ground_nodes))
end

end
