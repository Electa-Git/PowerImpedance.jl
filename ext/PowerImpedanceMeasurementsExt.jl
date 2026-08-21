module PowerImpedanceMeasurementsExt

using Measurements
using PowerImpedance
import Random

const P = PowerImpedance
const NB = P.NetworkBuilder

P.UnitHandler.nominal(value::Measurements.Measurement) = Measurements.value(value)
P.UnitHandler.standard_uncertainty(value::Measurements.Measurement) =
    Measurements.uncertainty(value)

P.Grammar._direct_uncertainty_latent() = Measurements.measurement(0.0, 1.0)
P.Grammar._direct_uncertain(value::P.UncertainValue, latent) =
    value.nominal + value.sigma * latent
P.Grammar._external_has_uncertainty(::Measurements.Measurement) = true
P.Grammar._external_has_uncertainty(values::AbstractArray) = NB._has_measurement(values)
P.Grammar._external_sample(rng, value::Measurements.Measurement, distribution) =
    NB._sample_value(rng, value, distribution)
P.Grammar._external_sample(rng, values::AbstractArray, distribution) =
    NB._sample_value(rng, values, distribution)

NB._is_measurement(::Measurements.Measurement) = true
NB._measurement_nominal(value::Measurements.Measurement) = Measurements.value(value)
NB._measurement_error(value::Measurements.Measurement) = Measurements.uncertainty(value)
NB._make_measurement(mean::Real, standard_deviation::Real) =
    Measurements.measurement(mean, standard_deviation)

function NB._sample_measurement(
    rng,
    value::Measurements.Measurement,
    distribution::Symbol,
)
    nominal = Measurements.value(value)
    sigma = Measurements.uncertainty(value)
    iszero(sigma) && return float(nominal)
    distribution === :normal && return nominal + sigma * randn(rng)
    distribution === :uniform && return nominal + sqrt(3) * sigma * (2rand(rng) - 1)
    throw(ArgumentError("distribution must be :normal or :uniform"))
end

_primitive_sort_key(key) = (key[3], key[1], key[2])

function _primitive_keys(value_collections...)
    primitive_keys = Set{Any}()
    for values in value_collections, value in values
        for component in (real(value), imag(value))
            component isa Measurements.Measurement || continue
            union!(primitive_keys, keys(Measurements.uncertainty_components(component)))
        end
    end
    return sort!(collect(primitive_keys); by=_primitive_sort_key)
end

function _sample_component(component, draws)
    component isa Measurements.Measurement || return Float64(component)
    sampled = Float64(Measurements.value(component))
    for (key, draw) in draws
        sampled += key[2] * Measurements.derivative(component, key) * draw
    end
    return sampled
end

function _sample_array(values, draws)
    sampled = Array{ComplexF64}(undef, size(values))
    for index in eachindex(values)
        value = values[index]
        sampled[index] = complex(
            _sample_component(real(value), draws),
            _sample_component(imag(value), draws),
        )
    end
    return all(value -> value isa Real, values) ? real.(sampled) : sampled
end

function NB._sample_value(rng, values::AbstractArray, distribution)
    NB._has_measurement(values) || return map(
        value -> NB._sample_value(rng, value, distribution),
        values,
    )
    primitive_keys = _primitive_keys(values)
    distribution in (:normal, :uniform) || throw(ArgumentError(
        "distribution must be :normal or :uniform",
    ))
    draw = distribution === :normal ? () -> randn(rng) :
        () -> sqrt(3) * (2rand(rng) - 1)
    draws = Dict(key => draw() for key in primitive_keys)
    return _sample_array(values, draws)
end

function _uncertain_bindings!(bindings, configuration::P.Configuration)
    for value in configuration.values
        if value isa P.Grammar.ResolvedGridValue && value.value isa P.UncertainValue
            get!(bindings, value.key, true)
        elseif value isa P.Configuration
            _uncertain_bindings!(bindings, value)
        end
    end
    return bindings
end

function _materialize_numeric(configuration, latent_overrides)
    resolver = value -> value.value isa P.UncertainValue ?
        value.value.nominal + value.value.sigma * get(latent_overrides, value.key, 0.0) :
        value.value
    return P.Grammar._materialize_resolved(configuration, resolver, Dict{Any,Any}())
end

function _linearized_measurement_response(base, derivatives, variables)
    first_value = begin
        nominal = base[begin]
        real_value = Measurements.measurement(real(nominal), 0.0)
        imaginary_value = Measurements.measurement(imag(nominal), 0.0)
        for (derivative, variable) in zip(derivatives, variables)
            delta = variable.measurement - variable.nominal
            real_value += real(derivative[begin]) * delta
            imaginary_value += imag(derivative[begin]) * delta
        end
        complex(real_value, imaginary_value)
    end
    response = Array{typeof(first_value)}(undef, size(base))
    for index in eachindex(base)
        real_value = Measurements.measurement(real(base[index]), 0.0)
        imaginary_value = Measurements.measurement(imag(base[index]), 0.0)
        for (derivative, variable) in zip(derivatives, variables)
            delta = variable.measurement - variable.nominal
            real_value += real(derivative[index]) * delta
            imaginary_value += imag(derivative[index]) * delta
        end
        response[index] = complex(real_value, imaginary_value)
    end
    return response
end

function P._linear_error_configuration(
    configuration::P.Configuration,
    formulation::P.AbstractPowerImpedanceFormulation,
    options::NamedTuple,
)
    bindings = _uncertain_bindings!(Dict{Any,Any}(), configuration)
    isempty(bindings) && throw(ArgumentError(
        "LinearError requires at least one uncertain Grid axis",
    ))
    base_problem = _materialize_numeric(configuration, Dict{Any,Any}())
    base = P.compute(base_problem, formulation; options)
    derivatives = Any[]
    variables = Any[]
    for key in keys(bindings)
        step = cbrt(eps(Float64))
        plus = P.compute(
            _materialize_numeric(configuration, Dict(key => step)),
            formulation;
            options,
        )
        minus = P.compute(
            _materialize_numeric(configuration, Dict(key => -step)),
            formulation;
            options,
        )
        push!(derivatives, (plus.response .- minus.response) ./ (2step))
        push!(variables, (
            nominal=0.0,
            measurement=Measurements.measurement(0.0, 1.0),
        ))
    end
    response = _linearized_measurement_response(base.response, derivatives, variables)
    return P.FrequencyResponseResult(
        formulation,
        base.kind,
        response,
        base.frequencies,
        base.nodes,
        base.network_model,
        merge(base.diagnostics, (
            propagation=:linear_error,
            latent_count=length(variables),
        )),
    )
end

function P.primitives(
    result::P.FrequencyResponseResult,
    ::P.MeasurementsSurrogate;
    options::NamedTuple=(;),
)
    NB._has_measurement(result.response) || throw(ArgumentError(
        "MeasurementsSurrogate requires a Measurements-valued response",
    ))
    return (
        response=result.response,
        frequencies=result.frequencies,
        nodes=result.nodes,
        kind=result.kind,
    )
end

function P.primitives(
    result::P.MonteCarloResult{<:P.FrequencyResponseResult},
    ::P.EmpiricalSamples;
    options::NamedTuple=(;),
)
    result.details.samples === nothing && throw(ArgumentError(
        "EmpiricalSamples requires return_samples=true",
    ))
    return result.details.samples
end

end
