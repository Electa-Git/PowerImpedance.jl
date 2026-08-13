import Statistics

"""One deterministic or uncertainty-aware impedance-study result."""
struct ImpedanceCase
    coordinates::Vector{Pair{Tuple,Any}}
    trials::Int
    seed::Union{Nothing,UInt64}
    distribution::Symbol
    output::Any
    impedance::Any
    frequencies::Any
    statistics::Any
    samples::Any
end

"""Ordered collection of [`ImpedanceCase`](@ref) values."""
struct ParametricImpedance
    cases::Vector{ImpedanceCase}
end

"""One deterministic or uncertainty-aware power-flow result."""
struct SolveCase
    coordinates::Vector{Pair{Tuple,Any}}
    trials::Int
    seed::Union{Nothing,UInt64}
    distribution::Symbol
    output::Any
    powerflow::Any
    network::Any
    statistics::Any
    samples::Any
end


"""Ordered collection of [`SolveCase`](@ref) values."""
struct ParametricSolve
    cases::Vector{SolveCase}
end

for Collection in (:ParametricImpedance, :ParametricSolve)
    @eval begin
        Base.length(result::$Collection) = length(result.cases)
        Base.size(result::$Collection) = (length(result),)
        Base.getindex(result::$Collection, index::Integer) = result.cases[index]
        Base.iterate(result::$Collection, state...) = iterate(result.cases, state...)
        Base.IteratorSize(::Type{<:$Collection}) = Base.HasShape{1}()
    end
end

struct _ValuePlan{F}
    sample::F
    coordinates::Vector{Pair{Tuple,Any}}
    uncertain::Bool
    zero_uncertainty::Bool
end

_measurement_extension_loaded() =
    Base.get_extension(P, :PowerImpedanceMeasurementsExt) !== nothing
_is_measurement(::Any) = false
_measurement_nominal(value) = value
_measurement_error(::Any) = 0.0
_make_measurement(args...) = throw(ArgumentError(
    "uncertainty aggregation requires Measurements.jl; load it with `using Measurements`",
))
_sample_measurement(rng, value, distribution) = throw(ArgumentError(
    "sampling Measurements values requires Measurements.jl; load it with `using Measurements`",
))

function _has_measurement(value)
    _is_measurement(value) && return true
    value isa Complex && return _has_measurement(real(value)) || _has_measurement(imag(value))
    value isa NamedTuple && return any(_has_measurement, values(value))
    value isa Tuple && return any(_has_measurement, value)
    value isa AbstractArray && return any(_has_measurement, value)
    return false
end

function _zero_measurement(value)
    _is_measurement(value) && return iszero(_measurement_error(value))
    value isa Complex && return _zero_measurement(real(value)) && _zero_measurement(imag(value))
    value isa NamedTuple && return all(_zero_measurement, values(value))
    value isa Tuple && return all(_zero_measurement, value)
    value isa AbstractArray && return all(_zero_measurement, value)
    return true
end

function _sample_value(rng, value, distribution)
    _is_measurement(value) && return _sample_measurement(rng, value, distribution)
    value isa Complex && return complex(
        _sample_value(rng, real(value), distribution),
        _sample_value(rng, imag(value), distribution),
    )
    value isa NamedTuple && return map(item -> _sample_value(rng, item, distribution), value)
    value isa Tuple && return map(item -> _sample_value(rng, item, distribution), value)
    value isa AbstractArray && return map(item -> _sample_value(rng, item, distribution), value)
    return value
end

function _measurement_description(value)
    if _is_measurement(value)
        return (
            kind = :measurement,
            nominal = _measurement_nominal(value),
            error = _measurement_error(value),
        )
    end
    if value isa Complex
        return (
            kind = :complex_measurement,
            nominal = complex(
                _measurement_nominal(real(value)), _measurement_nominal(imag(value)),
            ),
            error = (
                real = _measurement_error(real(value)),
                imag = _measurement_error(imag(value)),
            ),
        )
    end
    return (kind = :measurement_container, nominal = value, error = nothing)
end

function _axis_plans(axis::DeterministicGrid, path::Tuple)
    varied = length(axis) > 1
    return map(enumerate(axis.vals)) do (_, value)
        uncertain = _has_measurement(value)
        coordinates = Pair{Tuple,Any}[]
        if varied || uncertain
            metadata = uncertain ? _measurement_description(value) : (kind = :deterministic, value = value)
            push!(coordinates, path => metadata)
        end
        sample = (rng, distribution) -> _sample_value(rng, value, distribution)
        _ValuePlan(sample, coordinates, uncertain, !uncertain || _zero_measurement(value))
    end
end

function _axis_plans(axis::RelativeGrid, path::Tuple)
    return [
        _ValuePlan(
            (rng, distribution) -> begin
                sigma = abs(nominal) * error / 100
                iszero(sigma) ? float(nominal) : rand(rng, _distribution(distribution, nominal, sigma))
            end,
            Pair{Tuple,Any}[
                path => (kind = :relative, nominal = nominal, error = error),
            ],
            true,
            iszero(error),
        ) for (nominal, error) in Iterators.product(axis.vals, axis.rel_err)
    ]
end

function _axis_plans(axis::AbsoluteGrid, path::Tuple)
    return [
        _ValuePlan(
            (rng, distribution) -> iszero(error) ? float(nominal) :
                rand(rng, _distribution(distribution, nominal, error)),
            Pair{Tuple,Any}[
                path => (kind = :absolute, nominal = nominal, error = error),
            ],
            true,
            iszero(error),
        ) for (nominal, error) in Iterators.product(axis.vals, axis.abs_err)
    ]
end

function _axis_path(g::Gridspace, path::Tuple, index::Int)
    isempty(g.names) && return (path..., index)
    return (path..., g.names[index])
end

function _gridspace_plans(g::Gridspace, path::Tuple = ())
    axis_plans = ntuple(index -> begin
        axis = g.grids[index]
        axis_path = _axis_path(g, path, index)
        axis isa Gridspace ? _gridspace_plans(axis, axis_path) : _axis_plans(axis, axis_path)
    end, length(g.grids))

    combinations = Iterators.product(axis_plans...)
    plans = _ValuePlan[]
    for combination in combinations
        coordinates = Pair{Tuple,Any}[]
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
_case_seed(master::UInt64, case_index::Integer) =
    master ⊻ (UInt64(case_index) * 0x9e3779b97f4a7c15)

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
        n = length(values),
    )
end

function _aggregate_numbers(values::AbstractVector{<:Real})
    statistics = _scalar_statistics(values)
    return _make_measurement(statistics.mean, statistics.std), statistics
end

function _aggregate_numbers(values::AbstractVector{<:Complex})
    real_result, real_statistics = _aggregate_numbers(real.(values))
    imag_result, imag_statistics = _aggregate_numbers(imag.(values))
    return complex(real_result, imag_result), (real = real_statistics, imag = imag_statistics)
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
    elseif first_value isa NamedTuple
        keys(first_value) == keys(last(values)) || throw(ArgumentError("power-flow schemas differ across trials"))
        pairs = map(keys(first_value)) do key
            _aggregate_tree([getproperty(value, key) for value in values])
        end
        return map(first, pairs), map(last, pairs)
    elseif first_value isa AbstractDict
        expected = Set(keys(first_value))
        all(value -> Set(keys(value)) == expected, values) ||
            throw(ArgumentError("power-flow schemas differ across trials"))
        output = Dict{keytype(first_value),Any}()
        statistics = Dict{keytype(first_value),Any}()
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
            output[index], statistics[index] = _aggregate_tree([value[index] for value in values])
        end
        return output, statistics
    elseif first_value isa Tuple
        all(value -> length(value) == length(first_value), values) ||
            throw(ArgumentError("tuple schemas differ across trials"))
        pairs = ntuple(index -> _aggregate_tree([value[index] for value in values]), length(first_value))
        return map(first, pairs), map(last, pairs)
    end
    all(==(first_value), values) || throw(ArgumentError("nonnumeric outputs differ across trials"))
    return first_value, nothing
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
