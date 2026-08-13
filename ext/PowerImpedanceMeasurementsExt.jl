module PowerImpedanceMeasurementsExt

using PowerImpedanceACDC
using Measurements
import Random

const NB = PowerImpedanceACDC.NetworkBuilder

NB._is_measurement(::Measurements.Measurement) = true
NB._measurement_nominal(value::Measurements.Measurement) = Measurements.value(value)
NB._measurement_error(value::Measurements.Measurement) = Measurements.uncertainty(value)
function NB._make_measurement(mean::Real, standard_deviation::Real)
    Measurements.measurement(mean, standard_deviation)
end

function NB._sample_measurement(rng, value::Measurements.Measurement, distribution::Symbol)
    nominal = Measurements.value(value)
    sigma = Measurements.uncertainty(value)
    return iszero(sigma) ? float(nominal) :
           rand(rng, NB._distribution(distribution, nominal, sigma))
end

_primitive_sort_key(key) = (key[3], key[1], key[2])

function _measurement_primitive_keys(value_collections...)
    primitive_keys = Set{Any}()
    for values in value_collections
        for value in values, component in (real(value), imag(value))

            component isa Measurements.Measurement || continue
            union!(primitive_keys, keys(Measurements.uncertainty_components(component)))
        end
    end
    return sort!(collect(primitive_keys); by = _primitive_sort_key)
end

function _sample_measurement_component(component, draws)
    component isa Measurements.Measurement || return Float64(component)
    sampled = Float64(Measurements.value(component))
    for (key, draw) in draws
        sampled += key[2] * Measurements.derivative(component, key) * draw
    end
    return sampled
end

function _sample_measurement_array(values::AbstractArray, draws)
    sampled = Array{ComplexF64}(undef, size(values))
    for index in eachindex(values)
        value = values[index]
        sampled[index] = complex(
            _sample_measurement_component(real(value), draws),
            _sample_measurement_component(imag(value), draws)
        )
    end
    return all(value -> value isa Real, values) ? real.(sampled) : sampled
end

function _sample_measurement_arrays(rng, values::Tuple, distribution)
    primitive_keys = _measurement_primitive_keys(values...)
    standardized = NB._distribution(distribution, 0.0, 1.0)
    draws = Dict(key => rand(rng, standardized) for key in primitive_keys)
    return map(value -> _sample_measurement_array(value, draws), values)
end

function _sample_measurement_array(rng, values::AbstractArray, distribution)
    only(_sample_measurement_arrays(rng, (values,), distribution))
end

function NB._sample_value(rng, values::AbstractArray, distribution)
    (NB._has_measurement(values) && all(value -> value isa Number, values)) || return map(
        value -> NB._sample_value(rng, value, distribution), values
    )
    return _sample_measurement_array(rng, values, distribution)
end

const _UncertainResponseNumber = Union{
    Measurements.Measurement,
    Complex{M} where {M <: Measurements.Measurement}
}

function _surrogate_response(
        response,
        frequencies;
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples,
        nodes,
        kind
)
    return NB.sampled_frequency_response(
        response,
        frequencies;
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples,
        nodes,
        kind
    )
end

function PowerImpedanceACDC.nyquistplot(
        response::AbstractArray{T, 3},
        frequencies;
        trials::Union{Nothing, Int} = nothing,
        distribution::Symbol = :normal,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false,
        nodes = Symbol[],
        kwargs...
) where {T <: _UncertainResponseNumber}
    surrogate = _surrogate_response(
        response,
        frequencies;
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples,
        nodes,
        kind = :external
    )
    return PowerImpedanceACDC.nyquistplot(
        surrogate;
        return_samples,
        kwargs...
    )
end

for analysis in (:bodeplot, :passivity, :stabilitymargin, :unstable_frequency)
    @eval function PowerImpedanceACDC.$analysis(
            response::AbstractArray{T, 3},
            frequencies,
            args...;
            trials::Union{Nothing, Int} = nothing,
            distribution::Symbol = :normal,
            seed = nothing,
            confidence::Real = 0.95,
            tolerance::Real = 0.02,
            return_samples::Bool = false,
            nodes = Symbol[],
            kwargs...
    ) where {T <: _UncertainResponseNumber}
        surrogate = _surrogate_response(
            response,
            frequencies;
            trials,
            distribution,
            seed,
            confidence,
            tolerance,
            return_samples,
            nodes,
            kind = :external
        )
        return PowerImpedanceACDC.$analysis(
            surrogate,
            nothing,
            args...;
            return_samples,
            kwargs...
        )
    end
end

function PowerImpedanceACDC.EVD(
        response::AbstractArray{T, 3},
        frequencies,
        fmin,
        fmax,
        determinant::Bool = false;
        trials::Union{Nothing, Int} = nothing,
        distribution::Symbol = :normal,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false,
        nodes = Symbol[],
        kwargs...
) where {T <: _UncertainResponseNumber}
    surrogate = _surrogate_response(
        response,
        frequencies;
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples,
        nodes,
        kind = :external
    )
    return PowerImpedanceACDC.EVD(
        surrogate,
        nothing,
        fmin,
        fmax,
        determinant;
        return_samples,
        kwargs...
    )
end

function _joint_surrogate_responses(
        first_response,
        second_response,
        frequencies;
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples,
        nodes
)
    NB._validate_study_keywords(trials, distribution, confidence, tolerance)
    validated_frequencies = NB._validate_frequencies(frequencies)
    size(first_response) == size(second_response) || throw(DimensionMismatch(
        "the two uncertain responses must have identical dimensions",
    ))
    requested_trials = something(
        trials,
        NB._dkw_trials(
            2 * (length(first_response) + length(second_response)),
            confidence,
            tolerance
        )
    )
    master_seed = NB._master_seed(seed)
    rng = Random.Xoshiro(master_seed)
    first_samples = Vector{Array{ComplexF64, 3}}(undef, requested_trials)
    second_samples = similar(first_samples)
    zero_uncertainty = NB._zero_measurement(first_response) &&
                       NB._zero_measurement(second_response)
    sampled_first, sampled_second = _sample_measurement_arrays(
        rng,
        (first_response, second_response),
        distribution
    )
    first_samples[1] = NB._response_tensor(sampled_first, validated_frequencies)
    second_samples[1] = NB._response_tensor(sampled_second, validated_frequencies)
    for trial_index in 2:requested_trials
        if zero_uncertainty
            first_samples[trial_index] = copy(first_samples[1])
            second_samples[trial_index] = copy(second_samples[1])
        else
            sampled_first, sampled_second = _sample_measurement_arrays(
                rng,
                (first_response, second_response),
                distribution
            )
            first_samples[trial_index] = NB._response_tensor(
                sampled_first, validated_frequencies
            )
            second_samples[trial_index] = NB._response_tensor(
                sampled_second, validated_frequencies
            )
        end
    end
    first_stacked = NB._stack_impedance_samples(first_samples)
    second_stacked = NB._stack_impedance_samples(second_samples)
    first_result = NB.sampled_frequency_response(
        first_stacked,
        validated_frequencies;
        nodes
    )
    second_result = NB.sampled_frequency_response(
        second_stacked,
        validated_frequencies;
        nodes
    )
    shared_id = master_seed ⊻ 0xdb4f0b9175ae2165
    function mark_surrogate(result, stacked)
        case = only(result)
        replay = NB._EmpiricalResponseReplay(
            stacked,
            collect(1:requested_trials),
            shared_id
        )
        marked = NB.FrequencyResponseCase(
            case.coordinates,
            case.trials,
            master_seed,
            distribution,
            case.kind,
            case.output,
            case.response,
            case.frequencies,
            case.nodes,
            case.statistics,
            return_samples ? stacked : nothing,
            :measurements_surrogate,
            replay
        )
        return NB.ParametricFrequencyResponse(:external, [marked], shared_id)
    end
    return mark_surrogate(first_result, first_stacked),
    mark_surrogate(second_result, second_stacked)
end

function _measurement_small_gain(
        first_response,
        second_response,
        frequencies,
        title;
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples,
        nodes,
        kwargs...
)
    @warn "Sampling standalone Measurements responses uses their encoded moment/covariance model; it cannot recover empirical trials discarded by earlier aggregation."
    first_surrogate, second_surrogate = _joint_surrogate_responses(
        first_response,
        second_response,
        frequencies;
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples,
        nodes
    )
    return PowerImpedanceACDC.small_gain(
        first_surrogate,
        second_surrogate,
        nothing,
        title;
        pairing = :auto,
        return_samples,
        kwargs...
    )
end

for (First, Second) in (
    (:(T <: _UncertainResponseNumber), :(S <: _UncertainResponseNumber)),
    (:(T <: _UncertainResponseNumber), :(S <: Number)),
    (:(T <: Number), :(S <: _UncertainResponseNumber))
)
    @eval function PowerImpedanceACDC.small_gain(
            first_response::AbstractArray{T, 3},
            second_response::AbstractArray{S, 3},
            frequencies,
            title::String = "Small gain theorem evaluation via SVD";
            trials::Union{Nothing, Int} = nothing,
            distribution::Symbol = :normal,
            seed = nothing,
            confidence::Real = 0.95,
            tolerance::Real = 0.02,
            return_samples::Bool = false,
            nodes = Symbol[],
            kwargs...
    ) where {$First, $Second}
        return _measurement_small_gain(
            first_response,
            second_response,
            frequencies,
            title;
            trials,
            distribution,
            seed,
            confidence,
            tolerance,
            return_samples,
            nodes,
            kwargs...
        )
    end
end

struct _MeasurementResponseReplay{A}
    response::A
    frequencies::Vector{Float64}
    distribution::Symbol
    seed::UInt64
    trials::Int
end

function NB._replay_response(replay::_MeasurementResponseReplay)
    rng = Random.Xoshiro(replay.seed)
    if NB._zero_measurement(replay.response)
        first_sample = NB._response_tensor(
            NB._sample_value(rng, replay.response, replay.distribution),
            replay.frequencies
        )
        return NB._repeat_samples(first_sample, replay.trials)
    end
    return [NB._response_tensor(
                NB._sample_value(rng, replay.response, replay.distribution),
                replay.frequencies
            )
            for _ in 1:replay.trials]
end

"""
    NetworkBuilder.sampled_frequency_response(
        response::AbstractArray{<:Number, 3}, frequencies;
        trials=nothing, distribution=:normal, seed=nothing,
        confidence=0.95, tolerance=0.02, return_samples=false,
        nodes=Symbol[], coordinates=[], kind=:external,
    )

Construct replayable numeric response trials from the first-order moment and
covariance model encoded by a Measurements-valued frequency response.

# Arguments

- `response`: Square matrix response with layout
  `nodes × nodes × frequencies`; real and imaginary entries may contain
  Measurements values.
- `frequencies`: Finite, positive, strictly increasing angular frequencies
  \\[rad/s\\].
- `trials`: Positive synthetic-trial count, or `nothing` for DKW sizing.
- `distribution`: Latent primitive law, `:normal` or `:uniform`.
- `seed`: Local master seed used for exact replay.
- `confidence`: DKW simultaneous confidence when `trials=nothing`.
- `tolerance`: DKW empirical-CDF tolerance when `trials=nothing`.
- `return_samples`: Retain the numeric
  `nodes × nodes × frequencies × trials` tensor when `true`.
- `nodes`: Ordered response-node names.
- `coordinates`: Optional deterministic-case coordinates.
- `kind`: Response classification used by downstream composition.

# Returns

- A singleton `NetworkBuilder.ParametricFrequencyResponse` whose case has
  `uncertainty_source == :measurements_surrogate`.

# Notes

Every shared Measurements primitive is drawn once per trial. Signed derivatives
then reconstruct all matrix entries, real and imaginary components, and
frequencies jointly. `:normal` uses standard-normal latent draws;
`:uniform` uses `Uniform(-√3, √3)`, preserving the encoded covariance in
expectation.

This is a moment-and-covariance surrogate. It cannot recover skewness, tails,
higher-order dependence, or complete empirical trials discarded before this
call. When physical trial slices remain available, use the four-dimensional
`sampled_frequency_response(samples, frequencies; ...)` overload, which labels
the result `:empirical_samples`.

# Errors

Throws an error for a deterministic numeric response, invalid Monte Carlo
controls, invalid frequencies, or incompatible matrix dimensions.
"""
function NB.sampled_frequency_response(
        response::AbstractArray{<:Number, 3},
        frequencies;
        trials::Union{Nothing, Int} = nothing,
        distribution::Symbol = :normal,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false,
        nodes = Symbol[],
        coordinates = Pair{Tuple, Any}[],
        kind::Symbol = :external
)
    NB._has_measurement(response) || throw(ArgumentError(
        "a three-dimensional numeric response is deterministic; pass it directly " *
        "to the analysis function or provide a four-dimensional trial array",
    ))
    NB._validate_study_keywords(trials, distribution, confidence, tolerance)
    @warn "Sampling a standalone Measurements response uses its encoded moment/covariance model; it cannot recover empirical trials discarded by earlier aggregation."
    validated_frequencies = NB._validate_frequencies(frequencies)
    requested_trials = something(
        trials,
        NB._dkw_trials(2 * length(response), confidence, tolerance)
    )
    master_seed = NB._master_seed(seed)
    replay = _MeasurementResponseReplay(
        deepcopy(response),
        validated_frequencies,
        distribution,
        master_seed,
        requested_trials
    )
    samples = NB._replay_response(replay)
    stacked = NB._stack_impedance_samples(samples)
    empirical = NB.sampled_frequency_response(
        stacked,
        validated_frequencies;
        nodes,
        coordinates,
        kind
    )
    case = only(empirical)
    replacement = NB.FrequencyResponseCase(
        case.coordinates,
        case.trials,
        master_seed,
        distribution,
        case.kind,
        case.output,
        case.response,
        case.frequencies,
        case.nodes,
        case.statistics,
        return_samples ? stacked : nothing,
        :measurements_surrogate,
        replay
    )
    return NB.ParametricFrequencyResponse(
        kind,
        [replacement],
        empirical._study_id
    )
end

function Base.iterate(grid::NB.RelativeGrid, state = nothing)
    iterator = Iterators.product(grid.vals, grid.rel_err)
    item = state === nothing ? iterate(iterator) : iterate(iterator, state)
    item === nothing && return nothing
    ((nominal, error), next_state) = item
    value = Measurements.measurement(nominal, abs(nominal) * error / 100)
    return value, next_state
end

function Base.iterate(grid::NB.AbsoluteGrid, state = nothing)
    iterator = Iterators.product(grid.vals, grid.abs_err)
    item = state === nothing ? iterate(iterator) : iterate(iterator, state)
    item === nothing && return nothing
    ((nominal, error), next_state) = item
    return Measurements.measurement(nominal, error), next_state
end

Base.eltype(::Type{<:NB.RelativeGrid}) = Measurements.Measurement{Float64}
Base.eltype(::Type{<:NB.AbsoluteGrid}) = Measurements.Measurement{Float64}

end
