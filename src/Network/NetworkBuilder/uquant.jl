function _measurement_extension_loaded()
    return Base.get_extension(P, :PowerImpedanceMeasurementsExt) !== nothing
end

_is_measurement(::Any) = false
_measurement_nominal(value) = value
_measurement_error(::Any) = 0.0

function _contains_measurement(value)
    _is_measurement(value) && return true
    if value isa Complex
        return _contains_measurement(real(value)) || _contains_measurement(imag(value))
    end
    value isa NamedTuple && return any(_contains_measurement, values(value))
    value isa Tuple && return any(_contains_measurement, value)
    value isa AbstractArray && return any(_contains_measurement, value)
    if value isa AbstractDict
        return any(_contains_measurement, keys(value)) ||
            any(_contains_measurement, values(value))
    end
    value isa Union{Function,Type,Module,Symbol,AbstractString,Nothing,Missing} &&
        return false
    isstructtype(typeof(value)) || return false
    return any(
        index -> isdefined(value, index) && _contains_measurement(getfield(value, index)),
        1:fieldcount(typeof(value)),
    )
end

function _assert_numeric_powerflow_network(network::NetworkState)
    _contains_measurement(network.elements) && throw(ArgumentError(
        "PowerModels cannot consume Measurements-valued components; run the " *
        "owned Gridspace through MonteCarlo(ACDCPowerFlow()) so each local " *
        "power-flow trial receives one numeric realization",
    ))
    return network
end

function _make_measurement(args...)
    throw(ArgumentError(
        "uncertainty aggregation requires Measurements.jl",
    ))
end

function _sample_measurement(rng, value, distribution)
    throw(ArgumentError(
        "sampling Measurements values requires Measurements.jl",
    ))
end

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
