include("gs_components.jl")
include("gs_passives.jl")
include("gs_machines.jl")
include("gs_controls.jl")
include("gs_converters.jl")

# Empty active-element selections can infer `Vector{Union{}}`. Normalize that
# empty vector at the parametric boundary.
function NetworkModel(
        admittances::AdmittanceLookup{T},
        ::Vector{Union{}},
        passive_elements::Vector{Int64},
        grounded_nodes::Vector{Int},
        retained_nodes::Vector{Int},
        indices::NetworkLookup
) where {T <: Number}
    return NetworkModel(
        admittances,
        Int64[],
        passive_elements,
        grounded_nodes,
        retained_nodes,
        indices
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

"""
    define(elements, connections; options=(;))

Compose element Gridspaces into a declarative system Gridspace.

# Arguments

- `elements`: Named tuple whose values are qualified NetworkBuilder shadow
  constructor results.
- `connections`: Fixed tuple or vector of named topology rows.
- `options`: Ordinary or explicitly gridded builder options.

# Returns

- A `Gridspace{NetworkState}` whose deterministic cases follow Cartesian-product
  order.

# Notes

Raw arrays and other containers remain atomic constructor arguments. Only an
explicit [`Grid`](@ref), uncertainty grid, or nested Gridspace introduces an
axis. Connections are fixed by this overload; stochastic topology changes are
rejected by downstream response studies.
"""
function define(
        elements::NamedTuple{Names, Types},
        connections::Union{Tuple, AbstractVector};
        options = (;)
) where {Names, Types <: Tuple{Vararg{Gridspace}}}
    element_space = _namedtuple_gridspace(elements)
    option_space = _namedtuple_gridspace(options)
    target = _BuilderMaterializer(connections)
    return Gridspace{NetworkState}(target, (element_space, option_space), (
        :elements, :options))
end

# Gridspace impedance studies may reuse an active-device linearization only
# while the complete operating-point context remains unchanged. These private
# dispatch types keep that optimization outside the unchanged scalar API.
struct _OperatingPointContext
    elements::Dict{Symbol, Any}
    topology::Any
    options::Any
end

struct _CachedAdmittance{F}
    response::F
end

struct _LinearizationCache{C, P, A}
    context::C
    powerflow::P
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
    Union{AbstractString, Symbol, Char, Nothing, Missing, Type, Module} &&
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

function _operating_point_context(builder::NetworkState)
    elements = Dict{Symbol, Any}(
        name => deepcopy(element)
    for (name, element) in pairs(builder.elements)
    if !P.is_passive(element)
    )
    return _OperatingPointContext(
        elements,
        deepcopy(collect(builder.topology.connections)),
        deepcopy(builder.options)
    )
end

function _same_operating_point(left::_OperatingPointContext, right::_OperatingPointContext)
    return _same_study_value(left.elements, right.elements) &&
           _same_study_value(left.topology, right.topology) &&
           _same_study_value(left.options, right.options)
end

_linearization_decision(::NetworkState, ::Nothing) = _RefreshLinearization()
function _linearization_decision(builder::NetworkState, cache::_LinearizationCache)
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

function _active_admittance_cache(network::NetworkModel, builder::NetworkState)
    cached = Dict{Symbol, Any}()
    for (name, element) in pairs(builder.elements)
        (P.is_active(element) && !P.is_source(element)) || continue
        index = network.indices.elements[name]
        cached[name] = _CachedAdmittance(network.element_admittances.Y![index])
    end
    return cached
end

function _linearize(builder::NetworkState, ::_RefreshLinearization)
    context = _operating_point_context(builder)
    powerflow = islinear(builder.elements) ? nothing :
                P.compute(PowerFlowProblem(builder), ACDCPowerFlow())
    result = P.compute(
        LinearizationProblem(builder, powerflow),
        AdmittanceLinearization()
    )
    network = result.network_model
    cache = _LinearizationCache(
        context,
        powerflow,
        _active_admittance_cache(network, builder)
    )
    return network, cache
end

function _linearize(builder::NetworkState, decision::_ReuseLinearization)
    powerflow = decision.cache.powerflow
    builder.operating_point = powerflow === nothing ? P.OperatingPoint() :
                              powerflow.operating_point
    network = NetworkModel(builder, decision.cache.admittances)
    return network, decision.cache
end

mutable struct _ParametricImpedanceRunner{K}
    cache::Any
    keywords::K
end

function _stack_impedance_samples(samples::AbstractVector)
    isempty(samples) && throw(ArgumentError("at least one impedance sample is required"))
    reference = first(samples)
    reference isa AbstractArray || throw(ArgumentError(
        "impedance samples must be arrays; received $(typeof(reference))",
    ))
    sample_dimensions = size(reference)
    all(sample isa AbstractArray && size(sample) == sample_dimensions
    for sample in samples) ||
        throw(DimensionMismatch("impedance sample types or dimensions differ"))
    stacked = similar(reference, (sample_dimensions..., length(samples)))
    trial_dimension = ndims(stacked)
    for (trial_index, sample) in enumerate(samples)
        selectdim(stacked, trial_dimension, trial_index) .= sample
    end
    return stacked
end

function (runner::_ParametricImpedanceRunner)(builder::NetworkState)
    decision = _linearization_decision(builder, runner.cache)
    network, runner.cache = _linearize(builder, decision)
    keywords = runner.keywords
    result = P.compute(
        P.PowerImpedanceProblem(
            network;
            nodes = keywords.nets,
            eliminated_elements = get(keywords, :elim_elements, Symbol[]),
            frequency_range = get(
                keywords,
                :freq_range,
                (0.001, 10_000.0, 2_000)
            )
        ),
        P.NodalImpedance()
    )
    return result.response, result.frequencies
end

"""
    solve(gridspace::Gridspace{NetworkState}; trials=nothing,
          distribution=:normal, seed=nothing, confidence=0.95,
          tolerance=0.02, return_samples=false)

Solve every deterministic case and numeric uncertainty trial in a builder
Gridspace.

# Arguments

- `gridspace`: Declarative systems to materialize and solve.
- `trials`: Positive Monte Carlo count, or `nothing` for DKW sizing.
- `distribution`: Primitive sampling law, `:normal` or `:uniform`.
- `seed`: Local master seed, or `nothing` to generate one without changing the
  global random-number generator.
- `confidence`: DKW simultaneous confidence when `trials=nothing`.
- `tolerance`: DKW empirical-CDF tolerance when `trials=nothing`.
- `return_samples`: Retain each numeric power-flow result when `true`.

# Returns

- A [`ParametricSolve`](@ref) containing one [`SolveCase`](@ref) per
  deterministic Gridspace case.

# Notes

`:normal` samples `Normal(nominal, standard_deviation)`. `:uniform` samples
`nominal ± √3 standard_deviation`, which has the same variance. Every sampled
builder contains ordinary numeric values before reaching the scalar solver.
Separate Gridspace axes remain independent. Zero-uncertainty cases execute one
physical solve while retaining the requested logical trial count.

# Errors

Throws an error for invalid Monte Carlo controls or a failed case/trial. Trial
errors report coordinates, case index, trial index, and seed.
"""
function solve(
        gridspace::Gridspace{NetworkState};
        trials::Union{Nothing, Int} = nothing,
        distribution::Symbol = :normal,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false
)
    _validate_study_keywords(trials, distribution, confidence, tolerance)
    plans = _gridspace_plans(deepcopy(gridspace))
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

"""
    determine_impedance(gridspace::Gridspace{NetworkState}; trials=nothing,
                        distribution=:normal, seed=nothing, confidence=0.95,
                        tolerance=0.02, return_samples=false, kwargs...)

Evaluate impedance for every deterministic case and numeric uncertainty trial
in a builder Gridspace.

# Arguments

- `gridspace`: Declarative systems to materialize and evaluate.
- `trials`: Positive Monte Carlo count, or `nothing` for DKW sizing.
- `distribution`: Primitive sampling law, `:normal` or `:uniform`.
- `seed`: Local master seed, or `nothing` to generate one without changing the
  global random-number generator.
- `confidence`: DKW simultaneous confidence when `trials=nothing`.
- `tolerance`: DKW empirical-CDF tolerance when `trials=nothing`.
- `return_samples`: Retain the numeric tensor with layout
  `rows × columns × frequencies × trials` when `true`.
- `kwargs`: Scalar impedance arguments, including `nets`, `elim_elements`, and
  `freq_range`, whose frequencies are specified in hertz.

# Returns

- A [`ParametricImpedance`](@ref) containing one [`ImpedanceCase`](@ref) per
  deterministic Gridspace case. Complex response statistics are stored
  separately under `case.statistics.real` and `case.statistics.imag`.

# Notes

`:normal` samples `Normal(nominal, standard_deviation)`. `:uniform` samples
`nominal ± √3 standard_deviation`, which has the same variance. Passive-only
changes rebuild passive admittances while reusing the active operating point.
Changes to active elements, sources, connections, or builder options repeat
power flow, nonlinear equilibrium, and linearization.

When samples are omitted, private frozen provenance records the builder plan,
distribution, and seed so downstream stability tools can replay the same
numeric trials. The uncertainty source of such cases is `:monte_carlo`.

# Errors

Throws an error for invalid Monte Carlo controls, inconsistent trial response
dimensions or frequencies, or a failed case/trial. Trial errors report
coordinates, case index, trial index, and seed.
"""
function determine_impedance(
        gridspace::Gridspace{NetworkState};
        trials::Union{Nothing, Int} = nothing,
        distribution::Symbol = :normal,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false,
        kwargs...
)
    _validate_study_keywords(trials, distribution, confidence, tolerance)
    plans = _gridspace_plans(deepcopy(gridspace))
    any(plan -> plan.uncertain, plans) && !_measurement_extension_loaded() &&
        throw(ArgumentError("uncertain studies require Measurements.jl; load it with `using Measurements`"))
    master_seed = _master_seed(seed)
    cases = ImpedanceCase[]

    impedance_keywords = (; kwargs...)
    run = _ParametricImpedanceRunner(nothing, impedance_keywords)
    study_id = master_seed ⊻ 0xe7037ed1a0b428db
    for (case_index, plan) in enumerate(plans)
        case_seed = _case_seed(master_seed, case_index)
        rng = Random.Xoshiro(case_seed)
        if !plan.uncertain
            impedance, frequencies = run(plan.sample(rng, distribution))
            output = (impedance = impedance, frequencies = frequencies)
            push!(cases,
                ImpedanceCase(
                    plan.coordinates, 1, case_seed, distribution, output, impedance,
                    frequencies, nothing, nothing,
                    _ImpedanceReplay(
                        plan, impedance_keywords, case_seed, distribution, 1, true,
                        study_id
                    )
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
        retained = return_samples ? _stack_impedance_samples(impedance_samples) : nothing
        push!(cases,
            ImpedanceCase(
                plan.coordinates, requested_trials, case_seed, distribution, output,
                averaged, frequencies, statistics, retained,
                _ImpedanceReplay(
                    plan,
                    impedance_keywords,
                    case_seed,
                    distribution,
                    requested_trials,
                    plan.zero_uncertainty,
                    study_id
                )
            ))
    end
    return ParametricImpedance(cases)
end
