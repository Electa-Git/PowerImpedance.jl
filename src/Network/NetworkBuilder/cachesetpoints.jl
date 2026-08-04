
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

	# TODO: this should be changed to a linearized representation in next step
	for (name, element) in pairs(network.elements)
		if P.is_converter(element) || P.is_generator(element)
			values[name] = deepcopy(element)
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

		typeof(element) === typeof(cached_value) ||
			throw(
				ArgumentError(
					"Cached active setpoint value for :$name has type $(typeof(cached_value)), " *
					"but the rebuilt element has type $(typeof(element)).",
				),
			)

		element = deepcopy(cached_value)
	end

	# sync_parent_powerflow_globals!(powerflow)
	return network
end




function apply_powerflow_setpoints!(network::P.Network, powerflow::NamedTuple)
	result = powerflow.result
	data = powerflow.data
	nodes2bus = powerflow.nodes2bus
	elem2comp = powerflow.elem2comp
	global_dict = P.PowerModelsACDC._get_pu_bases(1000, network.voltageBase[1])
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

			setpoint = P.Setpoint(Pac = Pac, Qac = Qac, θac = θ, Vac = Vm, Vdc = Vdc, Pdc = Pdc)

			if element.element_model isa P.AbstractStateSpace
				P.update!(element, setpoint)
			else
				P.update!(element.element_model, Vm, θ, Pac, Qac, Vdc, Pdc)
			end
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

			setpoint = P.Setpoint(Pac=Pgen, Qac=Qgen, θac=θ, Vac=Vm)

			P.update!(element, setpoint)
		end
	end

	# sync_parent_powerflow_globals!(powerflow)
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