module PowerImpedanceLineCableModelsMeasurementsExt

using LineCableModels
using Measurements
using PowerImpedance
import Random

const LCM = LineCableModels
const P = PowerImpedance
const NB = P.NetworkBuilder

_primitive_sort_key(key) = (key[3], key[1], key[2])

function _primitive_keys(parameters::LCM.LineParameters)
    keys = Set{Any}()
    for values in (parameters.Z, parameters.Y), value in values
        for component in (real(value), imag(value))
            component isa Measurements.Measurement || continue
            union!(keys, Base.keys(Measurements.uncertainty_components(component)))
        end
    end
    return sort!(collect(keys); by=_primitive_sort_key)
end

function _sample_component(component, draws)
    component isa Measurements.Measurement || return Float64(component)
    sampled = Float64(Measurements.value(component))
    for key in sort!(
        collect(keys(Measurements.uncertainty_components(component)));
        by=_primitive_sort_key,
    )
        sampled += key[2] * Measurements.derivative(component, key) * draws[key]
    end
    return sampled
end

function _sample_parameter_array(values, draws)
    sampled = Array{ComplexF64}(undef, size(values))
    for index in eachindex(values)
        value = values[index]
        sampled[index] = complex(
            _sample_component(real(value), draws),
            _sample_component(imag(value), draws),
        )
    end
    return sampled
end

function NB._sample_value(rng, parameters::LCM.LineParameters, distribution)
    any(NB._has_measurement, parameters.f) && throw(ArgumentError(
        "uncertain LineParameters frequencies are unsupported",
    ))
    primitive_keys = _primitive_keys(parameters)
    distribution in (:normal, :uniform) || throw(ArgumentError(
        "distribution must be :normal or :uniform",
    ))
    draw = distribution === :normal ? () -> randn(rng) :
        () -> sqrt(3) * (2rand(rng) - 1)
    draws = Dict(key => draw() for key in primitive_keys)
    return LCM.LineParameters(
        LCM.domain(parameters),
        _sample_parameter_array(parameters.Z, draws),
        _sample_parameter_array(parameters.Y, draws),
        Float64.(parameters.f),
    )
end

P.Grammar._external_has_uncertainty(parameters::LCM.LineParameters) =
    NB._has_measurement(parameters)
P.Grammar._external_sample(rng, parameters::LCM.LineParameters, distribution) =
    NB._sample_value(rng, parameters, distribution)

end
