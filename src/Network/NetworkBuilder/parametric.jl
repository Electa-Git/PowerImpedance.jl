include("gs_components.jl")
include("gs_passives.jl")
include("gs_machines.jl")
include("gs_controls.jl")
include("gs_converters.jl")

# The legacy constructor infers `Vector{Union{}}` for a network without active
# elements. Keep the original implementation intact while accepting that empty
# vector at the additive parametric boundary.
function LinearizedAdmittanceNetwork(
        admittances::LinearizedAdmittanceCollection{T},
        ::Vector{Union{}},
        passives::Vector{Int64},
        groundednets::Vector{Int},
        activenets::Vector{Int},
        interface::LinearizedInterface
) where {T <: Number}
    return LinearizedAdmittanceNetwork(
        admittances, Int64[], passives, groundednets, activenets, interface
    )
end

struct _NamedTupleMaterializer{Names} end
(::_NamedTupleMaterializer{Names})(values...) where {Names} = NamedTuple{Names}(values)

function _namedtuple_gridspace(values::NamedTuple{Names}) where {Names}
    axes = map(_axis, Base.values(values))
    return Gridspace{NamedTuple}(_NamedTupleMaterializer{Names}(), axes, Names)
end

struct _BuilderMaterializer{Connections}
    connections::Connections
end

function (target::_BuilderMaterializer)(elements, options)
    return define(elements, target.connections; options)
end

function define(
        elements::NamedTuple{Names, Types},
        connections::Tuple{Vararg{ConnectionDef}};
        options = (;)
) where {Names, Types <: Tuple{Vararg{Gridspace}}}
    element_space = _namedtuple_gridspace(elements)
    option_space = _namedtuple_gridspace(options)
    target = _BuilderMaterializer(connections)
    return Gridspace{BuilderState}(target, (element_space, option_space), (
        :elements, :options))
end

# Gridspace impedance studies may reuse an active-device linearization only
# while the complete operating-point context remains unchanged. These private
# dispatch types keep that optimization outside the unchanged scalar API.
struct _OperatingPointContext
    elements::Dict{Symbol, Any}
    connections::Any
    options::Any
end

struct _CachedAdmittance{F}
    response::F
end

struct _LinearizationCache{C, A}
    context::C
    admittances::A
end

abstract type _LinearizationDecision end
struct _RefreshLinearization <: _LinearizationDecision end
struct _ReuseLinearization{C} <: _LinearizationDecision
    cache::C
end

function _same_study_value(left::P.Element, right::P.Element)
    typeof(left) === typeof(right) || return false
    return _same_study_value(left.pins, right.pins) &&
           left.input_pins == right.input_pins &&
           left.output_pins == right.output_pins &&
           _same_study_value(left.element_model, right.element_model) &&
           left.transformation == right.transformation &&
           left.connection == right.connection &&
           _same_study_value(left.setpoint, right.setpoint) &&
           _same_study_value(left.limits, right.limits)
end

function _same_study_value(left, right)
    typeof(left) === typeof(right) || return false
    left === right && return true
    left isa Number && return isequal(left, right)
    left isa
    Union{AbstractString, Symbol, Char, Nothing, Missing, Type, Module, Function} &&
        return isequal(left, right)
    if left isa NamedTuple
        keys(left) == keys(right) || return false
        return all(_same_study_value(left[key], right[key]) for key in keys(left))
    elseif left isa Tuple
        length(left) == length(right) || return false
        return all(_same_study_value(a, b) for (a, b) in zip(left, right))
    elseif left isa AbstractArray
        axes(left) == axes(right) || return false
        return all(_same_study_value(left[index], right[index])
        for index in eachindex(left))
    elseif left isa AbstractDict
        Set(keys(left)) == Set(keys(right)) || return false
        return all(_same_study_value(left[key], right[key]) for key in keys(left))
    elseif left isa AbstractSet
        return left == right
    elseif isstructtype(typeof(left))
        return all(
            _same_study_value(getfield(left, index), getfield(right, index))
        for index in 1:fieldcount(typeof(left))
        )
    end
    return isequal(left, right)
end

function _operating_point_context(builder::BuilderState)
    elements = Dict{Symbol, Any}(
        name => deepcopy(element)
    for (name, element) in pairs(builder.elements)
    if !P.is_passive(element)
    )
    return _OperatingPointContext(
        elements,
        deepcopy(collect(builder.connections.registry)),
        deepcopy(builder.options)
    )
end

function _same_operating_point(left::_OperatingPointContext, right::_OperatingPointContext)
    return _same_study_value(left.elements, right.elements) &&
           _same_study_value(left.connections, right.connections) &&
           _same_study_value(left.options, right.options)
end

_linearization_decision(::BuilderState, ::Nothing) = _RefreshLinearization()
function _linearization_decision(builder::BuilderState, cache::_LinearizationCache)
    context = _operating_point_context(builder)
    return _same_operating_point(context, cache.context) ?
           _ReuseLinearization(cache) : _RefreshLinearization()
end

function build(element::P.Element, cached::_CachedAdmittance)
    P.is_active(element) || throw(ArgumentError(
        "cached admittances can only be applied to active elements",
    ))
    return cached.response
end

function _active_admittance_cache(network::LinearizedAdmittanceNetwork, builder::BuilderState)
    cached = Dict{Symbol, Any}()
    for (name, element) in pairs(builder.elements)
        (P.is_active(element) && !P.is_source(element)) || continue
        index = network.interface.elem[name]
        cached[name] = _CachedAdmittance(network.admittances.Y![index])
    end
    return cached
end

function _linearize(builder::BuilderState, ::_RefreshLinearization)
    context = _operating_point_context(builder)
    network = convert(builder, LinearizedAdmittanceNetwork)
    cache = _LinearizationCache(context, _active_admittance_cache(network, builder))
    return network, cache
end

function _linearize(builder::BuilderState, decision::_ReuseLinearization)
    network = LinearizedAdmittanceNetwork(builder, decision.cache.admittances)
    return network, decision.cache
end

mutable struct _ParametricImpedanceRunner{K}
    cache::Any
    keywords::K
end

function (runner::_ParametricImpedanceRunner)(builder::BuilderState)
    decision = _linearization_decision(builder, runner.cache)
    network, runner.cache = _linearize(builder, decision)
    return determine_impedance(network; runner.keywords...)
end

function solve(
        gridspace::Gridspace{BuilderState};
        trials::Union{Nothing, Int} = nothing,
        distribution::Symbol = :normal,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false
)
    _validate_study_keywords(trials, distribution, confidence, tolerance)
    plans = _gridspace_plans(gridspace)
    any(plan -> plan.uncertain, plans) && !_measurement_extension_loaded() &&
        throw(ArgumentError("uncertain studies require Measurements.jl; load it with `using Measurements`"))
    master_seed = _master_seed(seed)
    cases = SolveCase[]

    for (case_index, plan) in enumerate(plans)
        case_seed = _case_seed(master_seed, case_index)
        rng = Random.Xoshiro(case_seed)
        if !plan.uncertain
            builder = plan.sample(rng, distribution)
            output = solve(builder)
            push!(cases,
                SolveCase(
                    plan.coordinates, 1, case_seed, distribution, output, output.powerflow,
                    output.network, nothing, nothing
                ))
            continue
        end

        first_output = try
            solve(plan.sample(rng, distribution))
        catch error
            throw(_trial_error(error, plan, case_index, 1, case_seed))
        end
        requested_trials = something(
            trials,
            _dkw_trials(max(_numeric_leaf_count(first_output.powerflow), 1), confidence, tolerance)
        )
        outputs = if plan.zero_uncertainty
            _repeat_samples(first_output, requested_trials)
        else
            values = Any[first_output]
            for trial_index in 2:requested_trials
                try
                    push!(values, solve(plan.sample(rng, distribution)))
                catch error
                    throw(_trial_error(error, plan, case_index, trial_index, case_seed))
                end
            end
            values
        end
        powerflows = [output.powerflow for output in outputs]
        averaged_powerflow, statistics = _aggregate_tree(powerflows)
        output = (powerflow = averaged_powerflow, network = nothing)
        retained = return_samples ? powerflows : nothing
        push!(cases,
            SolveCase(
                plan.coordinates, requested_trials, case_seed, distribution, output,
                averaged_powerflow, nothing, statistics, retained
            ))
    end
    return ParametricSolve(cases)
end

function determine_impedance(
        gridspace::Gridspace{BuilderState};
        trials::Union{Nothing, Int} = nothing,
        distribution::Symbol = :normal,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false,
        kwargs...
)
    _validate_study_keywords(trials, distribution, confidence, tolerance)
    plans = _gridspace_plans(gridspace)
    any(plan -> plan.uncertain, plans) && !_measurement_extension_loaded() &&
        throw(ArgumentError("uncertain studies require Measurements.jl; load it with `using Measurements`"))
    master_seed = _master_seed(seed)
    cases = ImpedanceCase[]

    run = _ParametricImpedanceRunner(nothing, (; kwargs...))
    for (case_index, plan) in enumerate(plans)
        case_seed = _case_seed(master_seed, case_index)
        rng = Random.Xoshiro(case_seed)
        if !plan.uncertain
            impedance, frequencies = run(plan.sample(rng, distribution))
            output = (impedance = impedance, frequencies = frequencies)
            push!(cases,
                ImpedanceCase(
                    plan.coordinates, 1, case_seed, distribution, output, impedance,
                    frequencies, nothing, nothing
                ))
            continue
        end

        first_impedance, frequencies = try
            run(plan.sample(rng, distribution))
        catch error
            throw(_trial_error(error, plan, case_index, 1, case_seed))
        end
        entries = 2 * length(first_impedance)
        requested_trials = something(trials, _dkw_trials(entries, confidence, tolerance))
        impedance_samples = if plan.zero_uncertainty
            _repeat_samples(first_impedance, requested_trials)
        else
            values = Any[first_impedance]
            for trial_index in 2:requested_trials
                impedance, trial_frequencies = try
                    run(plan.sample(rng, distribution))
                catch error
                    throw(_trial_error(error, plan, case_index, trial_index, case_seed))
                end
                trial_frequencies == frequencies || throw(_trial_error(
                    ArgumentError("frequency vectors differ across trials"),
                    plan, case_index, trial_index, case_seed
                ))
                size(impedance) == size(first_impedance) || throw(_trial_error(
                    ArgumentError("impedance tensor dimensions differ across trials"),
                    plan, case_index, trial_index, case_seed
                ))
                push!(values, impedance)
            end
            values
        end
        averaged, statistics = _aggregate_impedance(impedance_samples)
        output = (impedance = averaged, frequencies = frequencies)
        retained = return_samples ? cat(impedance_samples...; dims = 4) : nothing
        push!(cases,
            ImpedanceCase(
                plan.coordinates, requested_trials, case_seed, distribution, output,
                averaged, frequencies, statistics, retained
            ))
    end
    return ParametricImpedance(cases)
end
