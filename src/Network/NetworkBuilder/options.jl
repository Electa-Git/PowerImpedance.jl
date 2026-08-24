#### Options are passed to the NetworkState through hierarchical NamedTuples.
#### The following functions are used to extract the options from the NamedTuples.
"""
Retrieve the value of a specific option, returning a default value if the option is not set.
"""
function option_value(options::NamedTuple, name::Symbol, default)
	return hasproperty(options, name) ? getproperty(options, name) : default
end



####### Power flow options ###########

function powerflow_options(options::NamedTuple)
	return option_value(options, :power_flow, (;))
end

function is_bounded_options(options::NamedTuple)
	return option_value(powerflow_options(options), :is_bounded, (;))
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
		"print_level" => P.Logging.min_enabled_level(P.current_logger()) <= P.Logging.Debug ? 5 : 0,
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
