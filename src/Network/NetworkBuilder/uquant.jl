import Statistics

"""One deterministic or uncertainty-aware impedance-study result."""
struct ImpedanceCase <: P.AbstractResult
    coordinates::Vector{Pair{Tuple, Any}}
    trials::Int
    seed::Union{Nothing, UInt64}
    distribution::Symbol
    output::Any
    impedance::Any
    frequencies::Any
    statistics::Any
    samples::Any
    _provenance::Any
end

function ImpedanceCase(
        coordinates,
        trials,
        seed,
        distribution,
        output,
        impedance,
        frequencies,
        statistics,
        samples
)
    ImpedanceCase(
        coordinates,
        trials,
        seed,
        distribution,
        output,
        impedance,
        frequencies,
        statistics,
        samples,
        nothing
    )
end

"""Ordered collection of [`ImpedanceCase`](@ref) values."""
struct ParametricImpedance <: P.AbstractResult
    cases::Vector{ImpedanceCase}
end

"""One deterministic or uncertainty-aware power-flow result."""
struct SolveCase <: P.AbstractResult
    coordinates::Vector{Pair{Tuple, Any}}
    trials::Int
    seed::Union{Nothing, UInt64}
    distribution::Symbol
    output::Any
    powerflow::Any
    network::Any
    statistics::Any
    samples::Any
end

"""Ordered collection of [`SolveCase`](@ref) values."""
struct ParametricSolve <: P.AbstractResult
    cases::Vector{SolveCase}
end

"""
    FrequencyResponseCase

Represent one deterministic or uncertainty-aware matrix frequency response.

The canonical response layout is `n × n × nf`. Retained Monte Carlo samples use
`n × n × nf × ntrials`. Frequencies are angular frequencies \\[rad/s\\].

`uncertainty_source` is `:deterministic` for an ordinary response,
`:monte_carlo` for a physically evaluated Gridspace study,
`:empirical_samples` for supplied whole-trial data, or
`:measurements_surrogate` for synthetic trials reconstructed from the
first-order moment and covariance model encoded by Measurements values.

Keep the complete case when passing a response downstream. Extracting only
`response` discards retained samples and private replay provenance.
"""
struct FrequencyResponseCase <: P.AbstractResult
    "Gridspace coordinates that identify the deterministic case."
    coordinates::Vector{Pair{Tuple, Any}}
    "Number of Monte Carlo trials represented by the case."
    trials::Int
    "Derived local random seed, or `nothing` for externally supplied samples."
    seed::Union{Nothing, UInt64}
    "Sampling distribution identifier."
    distribution::Symbol
    "Response kind, such as `:node_admittance`, `:edge_admittance`, or `:loopgain`."
    kind::Symbol
    "Named result payload containing the response, frequencies, and node order."
    output::Any
    "Deterministic response or entrywise mean-and-standard-deviation response."
    response::Any
    "Strictly increasing angular-frequency vector \\[rad/s\\]."
    frequencies::Vector{Float64}
    "Ordered node names corresponding to the matrix rows and columns."
    nodes::Vector{Symbol}
    "Entrywise trial statistics, or `nothing` for a deterministic case."
    statistics::Any
    "Optional numeric sample tensor with layout `n × n × nf × ntrials`."
    samples::Any
    "Uncertainty origin: `:deterministic`, `:monte_carlo`, `:empirical_samples`, or `:measurements_surrogate`."
    uncertainty_source::Symbol
    "Private frozen information used to replay exact trials."
    _provenance::Any
end

"""
    ParametricFrequencyResponse

Store ordered matrix-valued frequency-response cases from one study.

The collection supports `length`, iteration, integer indexing, and `only`.
"""
struct ParametricFrequencyResponse <: P.AbstractResult
    "Common response kind."
    kind::Symbol
    "Ordered deterministic cases."
    cases::Vector{FrequencyResponseCase}
    "Private identity used to prove shared trial provenance."
    _study_id::UInt64
end

"""
    ParametricNodeSchema

Store one ordered node list per deterministic Gridspace case.

Passing this object as `nodelist` to `make_y_edge` preserves case order and the
sampling identity established by `make_y_node`.
"""
struct ParametricNodeSchema
    "Ordered node names for every deterministic case."
    nodes::Vector{Vector{Symbol}}
    "Gridspace coordinates associated with each node list."
    coordinates::Vector{Vector{Pair{Tuple, Any}}}
    "Private shared-study identity."
    _study_id::UInt64
    "Private frozen study specification used for paired evaluation."
    _study::Any
end

"""
    StabilityCase

Represent one deterministic or uncertainty-aware small-signal analysis.

The `uncertainty_source` field retains the source classification of the input
response: `:deterministic`, `:monte_carlo`, `:empirical_samples`, or
`:measurements_surrogate`. Tool-specific continuous outputs use the standard
statistics `mean`, `std`, `min`, `q05`, `median`, `q95`, `max`, and `n`;
categorical and variable-length outcomes use probabilities and pooled event
summaries instead.
"""
struct StabilityCase <: P.AbstractResult
    "Gridspace coordinates that identify the deterministic case."
    coordinates::Vector{Pair{Tuple, Any}}
    "Number of numeric trials analyzed."
    trials::Int
    "Derived local random seed, when applicable."
    seed::Union{Nothing, UInt64}
    "Sampling distribution identifier."
    distribution::Symbol
    "Analysis identifier, such as `:nyquist`, `:bode`, or `:evd`."
    analysis::Symbol
    "Tool-specific aggregated result."
    output::Any
    "Tool-specific trial statistics."
    statistics::Any
    "Optional exact trial-level analysis records."
    samples::Any
    "Constructed plot object or plot collection."
    plots::Any
    "Uncertainty origin: `:deterministic`, `:monte_carlo`, `:empirical_samples`, or `:measurements_surrogate`."
    uncertainty_source::Symbol
end

"""
    ParametricStability

Store ordered results from one parametric small-signal analysis.

The collection supports `length`, iteration, integer indexing, and `only`.
"""
struct ParametricStability <: P.AbstractResult
    "Common analysis identifier."
    analysis::Symbol
    "Ordered deterministic cases."
    cases::Vector{StabilityCase}
end

for Collection in (
    :ParametricImpedance,
    :ParametricSolve,
    :ParametricFrequencyResponse,
    :ParametricStability
)
    @eval begin
        Base.length(result::$Collection) = length(result.cases)
        Base.size(result::$Collection) = (length(result),)
        Base.getindex(result::$Collection, index::Integer) = result.cases[index]
        Base.iterate(result::$Collection, state...) = iterate(result.cases, state...)
        Base.IteratorSize(::Type{<:$Collection}) = Base.HasShape{1}()
    end
end

Base.length(schema::ParametricNodeSchema) = length(schema.nodes)
Base.size(schema::ParametricNodeSchema) = (length(schema),)
Base.getindex(schema::ParametricNodeSchema, index::Integer) = schema.nodes[index]
Base.iterate(schema::ParametricNodeSchema, state...) = iterate(schema.nodes, state...)
Base.IteratorSize(::Type{<:ParametricNodeSchema}) = Base.HasShape{1}()

struct _ValuePlan{F}
    sample::F
    coordinates::Vector{Pair{Tuple, Any}}
    uncertain::Bool
    zero_uncertainty::Bool
end

function _measurement_extension_loaded()
    Base.get_extension(P, :PowerImpedanceMeasurementsExt) !== nothing
end
_is_measurement(::Any) = false
_measurement_nominal(value) = value
_measurement_error(::Any) = 0.0
function _make_measurement(args...)
    throw(ArgumentError(
        "uncertainty aggregation requires Measurements.jl; load it with `using Measurements`",
    ))
end
function _sample_measurement(rng, value, distribution)
    throw(ArgumentError(
        "sampling Measurements values requires Measurements.jl; load it with `using Measurements`",
    ))
end

function _has_measurement(value)
    _is_measurement(value) && return true
    value isa Complex &&
        return _has_measurement(real(value)) || _has_measurement(imag(value))
    value isa NamedTuple && return any(_has_measurement, values(value))
    value isa Tuple && return any(_has_measurement, value)
    value isa AbstractArray && return any(_has_measurement, value)
    return false
end

function _zero_measurement(value)
    _is_measurement(value) && return iszero(_measurement_error(value))
    value isa Complex &&
        return _zero_measurement(real(value)) && _zero_measurement(imag(value))
    value isa NamedTuple && return all(_zero_measurement, values(value))
    value isa Tuple && return all(_zero_measurement, value)
    value isa AbstractArray && return all(_zero_measurement, value)
    return true
end

function _sample_value(rng, value, distribution)
    _is_measurement(value) && return _sample_measurement(rng, value, distribution)
    value isa Complex && return complex(
        _sample_value(rng, real(value), distribution),
        _sample_value(rng, imag(value), distribution)
    )
    value isa NamedTuple &&
        return map(item -> _sample_value(rng, item, distribution), value)
    value isa Tuple && return map(item -> _sample_value(rng, item, distribution), value)
    value isa AbstractArray &&
        return map(item -> _sample_value(rng, item, distribution), value)
    return value
end

function _measurement_description(value)
    if _is_measurement(value)
        return (
            kind = :measurement,
            nominal = _measurement_nominal(value),
            error = _measurement_error(value)
        )
    end
    if value isa Complex
        return (
            kind = :complex_measurement,
            nominal = complex(
                _measurement_nominal(real(value)), _measurement_nominal(imag(value))
            ),
            error = (
                real = _measurement_error(real(value)),
                imag = _measurement_error(imag(value))
            )
        )
    end
    return (kind = :measurement_container, nominal = value, error = nothing)
end

function _axis_plans(axis::DeterministicGrid, path::Tuple)
    varied = length(axis) > 1
    return map(enumerate(axis.vals)) do (_, value)
        uncertain = _has_measurement(value)
        coordinates = Pair{Tuple, Any}[]
        if varied || uncertain
            metadata = uncertain ? _measurement_description(value) :
                       (kind = :deterministic, value = value)
            push!(coordinates, path => metadata)
        end
        sample = (rng, distribution) -> _sample_value(rng, value, distribution)
        _ValuePlan(sample, coordinates, uncertain, !uncertain || _zero_measurement(value))
    end
end

function _axis_plans(axis::RelativeGrid, path::Tuple)
    return [_ValuePlan(
                (rng, distribution) -> begin
                    sigma = abs(nominal) * error / 100
                    iszero(sigma) ? float(nominal) :
                    rand(rng, _distribution(distribution, nominal, sigma))
                end,
                Pair{Tuple, Any}[
                    path => (kind = :relative, nominal = nominal, error = error),
                ],
                true,
                iszero(error)
            ) for (nominal, error) in Iterators.product(axis.vals, axis.rel_err)]
end

function _axis_plans(axis::AbsoluteGrid, path::Tuple)
    return [_ValuePlan(
                (rng, distribution) -> iszero(error) ? float(nominal) :
                                       rand(rng, _distribution(distribution, nominal, error)),
                Pair{Tuple, Any}[
                    path => (kind = :absolute, nominal = nominal, error = error),
                ],
                true,
                iszero(error)
            ) for (nominal, error) in Iterators.product(axis.vals, axis.abs_err)]
end

function _axis_path(g::Gridspace, path::Tuple, index::Int)
    isempty(g.names) && return (path..., index)
    return (path..., g.names[index])
end

function _gridspace_plans(g::Gridspace, path::Tuple = ())
    axis_plans = ntuple(
        index -> begin
            axis = g.grids[index]
            axis_path = _axis_path(g, path, index)
            axis isa Gridspace ? _gridspace_plans(axis, axis_path) :
            _axis_plans(axis, axis_path)
        end,
        length(g.grids))

    combinations = Iterators.product(axis_plans...)
    plans = _ValuePlan[]
    for combination in combinations
        coordinates = Pair{Tuple, Any}[]
        foreach(plan -> append!(coordinates, plan.coordinates), combination)
        uncertain = any(plan -> plan.uncertain, combination)
        zero_uncertainty = all(plan -> plan.zero_uncertainty, combination)
        sample = let g = g, combination = combination
            (rng, distribution) -> begin
                values = map(plan -> plan.sample(rng, distribution), combination)
                _materialize(g, values)
            end
        end
        push!(plans, _ValuePlan(sample, coordinates, uncertain, zero_uncertainty))
    end
    return plans
end

function _validate_study_keywords(trials, distribution, confidence, tolerance)
    trials === nothing || trials > 0 || throw(ArgumentError("trials must be positive"))
    distribution in (:normal, :uniform) || throw(ArgumentError(
        "unsupported distribution :$distribution; expected :normal or :uniform",
    ))
    0 < confidence < 1 || throw(ArgumentError("confidence must be between zero and one"))
    tolerance > 0 || throw(ArgumentError("tolerance must be positive"))
    return nothing
end

function _dkw_trials(output_entries::Integer, confidence::Real, tolerance::Real)
    output_entries > 0 || return 1
    return ceil(Int, log(2 * output_entries / (1 - confidence)) / (2 * tolerance^2))
end

_master_seed(seed::Nothing) = rand(Random.RandomDevice(), UInt64)
_master_seed(seed::Integer) = UInt64(seed)
function _case_seed(master::UInt64, case_index::Integer)
    master ⊻ (UInt64(case_index) * 0x9e3779b97f4a7c15)
end

function _trial_error(error, plan::_ValuePlan, case_index, trial_index, seed)
    paths = isempty(plan.coordinates) ? "<none>" : join(first.(plan.coordinates), ", ")
    message = sprint(showerror, error)
    return ErrorException(
        "parametric study failed at case $case_index, trial $trial_index, seed $seed, " *
        "coordinate path(s) $paths: $message",
    )
end

_numeric_leaf_count(value::Number) = 1
_numeric_leaf_count(value::NamedTuple) = sum(_numeric_leaf_count, values(value); init = 0)
_numeric_leaf_count(value::Tuple) = sum(_numeric_leaf_count, value; init = 0)
_numeric_leaf_count(value::AbstractArray) = sum(_numeric_leaf_count, value; init = 0)
_numeric_leaf_count(value::AbstractDict) = sum(_numeric_leaf_count, values(value); init = 0)
function _numeric_leaf_count(value::P.OperatingPoint)
    return sum(values(value.setpoints); init = 0) do setpoint
        count(field -> getfield(setpoint, field) isa Number, fieldnames(P.Setpoint))
    end
end
function _numeric_leaf_count(value::P.PowerFlowResult)
    return _numeric_leaf_count(value.result) + _numeric_leaf_count(value.data) +
           _numeric_leaf_count(value.operating_point)
end
_numeric_leaf_count(::Any) = 0

function _scalar_statistics(values::AbstractVector{<:Real})
    sorted = sort(collect(values))
    standard_deviation = if length(values) == 1 || all(isequal(first(values)), values)
        zero(float(first(values)))
    else
        Statistics.std(values; corrected = true)
    end
    return (
        mean = Statistics.mean(values),
        std = standard_deviation,
        min = first(sorted),
        q05 = Statistics.quantile(sorted, 0.05),
        median = Statistics.median(sorted),
        q95 = Statistics.quantile(sorted, 0.95),
        max = last(sorted),
        n = length(values)
    )
end

function _aggregate_numbers(values::AbstractVector{<:Real})
    statistics = _scalar_statistics(values)
    return _make_measurement(statistics.mean, statistics.std), statistics
end

function _aggregate_numbers(values::AbstractVector{<:Complex})
    real_result, real_statistics = _aggregate_numbers(real.(values))
    imag_result, imag_statistics = _aggregate_numbers(imag.(values))
    return complex(real_result, imag_result),
    (real = real_statistics, imag = imag_statistics)
end

function _aggregate_numbers(values::AbstractVector)
    all(value -> value isa Real, values) && return _aggregate_numbers(Real[values...])
    all(value -> value isa Complex, values) && return _aggregate_numbers(Complex[values...])
    throw(ArgumentError("cannot aggregate heterogeneous numeric trial values"))
end

function _aggregate_tree(values::AbstractVector)
    first_value = first(values)
    if first_value isa Number && all(value -> value isa Number, values)
        return _aggregate_numbers(values)
    elseif first_value isa P.PowerFlowResult
        all(value -> value isa P.PowerFlowResult, values) || throw(
            ArgumentError("power-flow result types differ across trials"),
        )
        result, result_statistics = _aggregate_tree([value.result for value in values])
        data, data_statistics = _aggregate_tree([value.data for value in values])
        nodes2bus, node_statistics = _aggregate_tree(
            [value.nodes2bus for value in values],
        )
        elem2comp, element_statistics = _aggregate_tree(
            [value.elem2comp for value in values],
        )
        operating_point, operating_statistics = _aggregate_operating_points(
            [value.operating_point for value in values],
        )
        diagnostics, diagnostic_statistics = _aggregate_tree(
            [value.diagnostics for value in values],
        )
        output = P.PowerFlowResult(
            result,
            data,
            nodes2bus,
            elem2comp,
            operating_point,
            diagnostics
        )
        statistics = (
            result = result_statistics,
            data = data_statistics,
            nodes2bus = node_statistics,
            elem2comp = element_statistics,
            operating_point = operating_statistics,
            diagnostics = diagnostic_statistics
        )
        return output, statistics
    elseif first_value isa NamedTuple
        keys(first_value) == keys(last(values)) ||
            throw(ArgumentError("power-flow schemas differ across trials"))
        names = keys(first_value)
        pairs = map(names) do key
            _aggregate_tree([getproperty(value, key) for value in values])
        end
        return NamedTuple{names}(map(first, pairs)), NamedTuple{names}(map(last, pairs))
    elseif first_value isa AbstractDict
        expected = Set(keys(first_value))
        all(value -> Set(keys(value)) == expected, values) ||
            throw(ArgumentError("power-flow schemas differ across trials"))
        output = Dict{keytype(first_value), Any}()
        statistics = Dict{keytype(first_value), Any}()
        for key in keys(first_value)
            output[key], statistics[key] = _aggregate_tree([value[key] for value in values])
        end
        return output, statistics
    elseif first_value isa AbstractArray
        all(value -> axes(value) == axes(first_value), values) ||
            throw(ArgumentError("array dimensions differ across trials"))
        output = similar(first_value, Any)
        statistics = similar(first_value, Any)
        for index in eachindex(first_value)
            output[index], statistics[index] = _aggregate_tree([value[index]
                                                                for value in values])
        end
        return output, statistics
    elseif first_value isa Tuple
        all(value -> length(value) == length(first_value), values) ||
            throw(ArgumentError("tuple schemas differ across trials"))
        pairs = ntuple(index -> _aggregate_tree([value[index] for value in values]), length(first_value))
        return map(first, pairs), map(last, pairs)
    end
    all(==(first_value), values) ||
        throw(ArgumentError("nonnumeric outputs differ across trials"))
    return first_value, nothing
end

function _aggregate_operating_points(points::AbstractVector{<:P.OperatingPoint})
    names = Set(keys(first(points).setpoints))
    all(point -> Set(keys(point.setpoints)) == names, points) || throw(
        ArgumentError("operating-point element sets differ across trials"),
    )
    output = Dict{Symbol, P.Setpoint}()
    statistics = Dict{Symbol, Any}()
    for name in keys(first(points).setpoints)
        setpoints = [point.setpoints[name] for point in points]
        fields = fieldnames(P.Setpoint)
        mean_values = Any[]
        field_statistics = Any[]
        for field in fields
            values = [getfield(setpoint, field) for setpoint in setpoints]
            if all(ismissing, values)
                push!(mean_values, missing)
                push!(field_statistics, nothing)
            elseif all(value -> value isa Real, values)
                stats = _scalar_statistics(Real[values...])
                push!(mean_values, Float64(stats.mean))
                push!(field_statistics, stats)
            else
                throw(ArgumentError(
                    "operating-point field :$field differs in missing-value status across trials",
                ))
            end
        end
        output[name] = P.Setpoint(; NamedTuple{fields}(Tuple(mean_values))...)
        statistics[name] = NamedTuple{fields}(Tuple(field_statistics))
    end
    return P.OperatingPoint(output), statistics
end

function _aggregate_impedance(samples::Vector)
    first_sample = first(samples)
    all(sample -> size(sample) == size(first_sample), samples) ||
        throw(ArgumentError("impedance tensor dimensions differ across trials"))
    first_values = [sample[firstindex(first_sample)] for sample in samples]
    first_output, first_statistics = _aggregate_numbers(first_values)
    output = Array{typeof(first_output)}(undef, size(first_sample))
    real_statistics = Array{Any}(undef, size(first_sample))
    imag_statistics = Array{Any}(undef, size(first_sample))
    for index in eachindex(first_sample)
        if index == firstindex(first_sample)
            output[index], statistics = first_output, first_statistics
        else
            values = [sample[index] for sample in samples]
            output[index], statistics = _aggregate_numbers(values)
        end
        real_statistics[index] = statistics.real
        imag_statistics[index] = statistics.imag
    end
    return output, (real = real_statistics, imag = imag_statistics)
end

function _repeat_samples(sample, trials::Int)
    return [deepcopy(sample) for _ in 1:trials]
end
