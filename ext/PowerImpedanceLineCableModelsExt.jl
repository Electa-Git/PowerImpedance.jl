module PowerImpedanceLineCableModelsExt

using LineCableModels
using Measurements
using PowerImpedanceACDC
import Random

const LCM = LineCableModels
const P = PowerImpedanceACDC
const NB = PowerImpedanceACDC.NetworkBuilder

abstract type _LineParametersTransmissionLine <: P.Transmission_line end

struct _LineParametersOverheadLine{L <: LCM.LineParameters} <:
       _LineParametersTransmissionLine
    parameters::L
    length::Float64
    extrapolation::Symbol
end

struct _LineParametersCable{L <: LCM.LineParameters} <:
       _LineParametersTransmissionLine
    parameters::L
    length::Float64
    extrapolation::Symbol
end

struct _LineParametersElementMaterializer{F}
    constructor::F
end

function (target::_LineParametersElementMaterializer)(
        parameters,
        length,
        transformation,
        connection,
        extrapolation
)
    return target.constructor(
        parameters;
        length,
        transformation,
        connection,
        extrapolation
    )
end

function _validate_numeric_component(value, label)
    nominal = NB._measurement_nominal(value)
    error = NB._measurement_error(value)
    isfinite(nominal) || throw(ArgumentError("$label contains a non-finite nominal value"))
    isfinite(error) || throw(ArgumentError("$label contains a non-finite uncertainty"))
    error >= zero(error) || throw(ArgumentError("$label contains a negative uncertainty"))
    return nothing
end

function _validate_parameter_values(values, label)
    for value in values
        _validate_numeric_component(real(value), label)
        _validate_numeric_component(imag(value), label)
    end
    return nothing
end

function _validate_line_parameters(parameters::LCM.LineParameters)
    LCM.domain(parameters) === LCM.PhaseDomain || throw(ArgumentError(
        "PowerImpedanceACDC requires phase-domain LineParameters; " *
        "inverse-transform modal parameters before constructing the line",
    ))

    size(parameters.Z) == size(parameters.Y) || throw(DimensionMismatch(
        "LineParameters Z and Y must have identical n×n×nf dimensions",
    ))
    ndims(parameters.Z) == 3 || throw(DimensionMismatch(
        "LineParameters Z and Y must be three-dimensional n×n×nf arrays",
    ))
    order = size(parameters.Z, 1)
    size(parameters.Z, 2) == order || throw(DimensionMismatch(
        "LineParameters Z and Y matrices must be square",
    ))
    order in 1:3 || throw(ArgumentError(
        "unsupported LineParameters order $order; PowerImpedanceACDC supports one, two, or three phase conductors",
    ))
    size(parameters.Z, 3) == length(parameters.f) || throw(DimensionMismatch(
        "the LineParameters frequency count must match the third Z/Y dimension",
    ))

    length(parameters.f) >= 2 || throw(ArgumentError(
        "LineParameters must contain at least two frequency samples",
    ))
    any(NB._has_measurement, parameters.f) && throw(ArgumentError(
        "uncertain LineParameters frequencies are unsupported; use a deterministic, ordered frequency grid",
    ))
    all(frequency -> isfinite(frequency) && frequency > 0, parameters.f) ||
        throw(ArgumentError(
            "LineParameters frequencies must be finite and strictly positive",
        ))
    all(index -> parameters.f[index] < parameters.f[index + 1],
        firstindex(parameters.f):(lastindex(parameters.f) - 1)) ||
        throw(ArgumentError(
            "LineParameters frequencies must be strictly increasing without duplicates",
        ))

    _validate_parameter_values(parameters.Z, "LineParameters.Z")
    _validate_parameter_values(parameters.Y, "LineParameters.Y")
    return order
end

function _validate_configuration(order::Integer, transformation)
    transformation isa Bool || throw(ArgumentError("transformation must be true or false"))
    if order == 1
        transformation && throw(ArgumentError(
            "one-conductor LineParameters require transformation=false",
        ))
    elseif order == 2
        transformation || throw(ArgumentError(
            "two-conductor LineParameters require transformation=true for the native DC differential representation",
        ))
    end
    return nothing
end

function _validate_line_options(length, connection, extrapolation)
    length isa Real || throw(ArgumentError("length must be a real value in metres"))
    isfinite(length) || throw(ArgumentError("length must be finite"))
    length > zero(length) || throw(ArgumentError("length must be positive"))
    connection isa Bool || throw(ArgumentError("connection must be true or false"))
    extrapolation in (:error, :linear) || throw(ArgumentError(
        "unsupported extrapolation :$extrapolation; expected :error or :linear",
    ))
    return nothing
end

function _uncertain_native_error(kind::Symbol)
    constructor = kind === :overhead_line ? "overhead_line" : "cable"
    return ArgumentError(
        "uncertain LineParameters and line lengths must be sampled before line evaluation; " *
        "use `PowerImpedanceACDC.NetworkBuilder.$constructor(parameters; ...)`",
    )
end

function _line_element(
        ::Type{Model},
        kind::Symbol,
        parameters::LCM.LineParameters;
        length,
        transformation = false,
        connection = true,
        extrapolation = :error
) where {Model <: _LineParametersTransmissionLine}
    order = _validate_line_parameters(parameters)
    _validate_configuration(order, transformation)
    (NB._has_measurement(parameters) || NB._has_measurement(length)) &&
        throw(_uncertain_native_error(kind))
    _validate_line_options(length, connection, extrapolation)

    model = Model(parameters, Float64(length), extrapolation)
    return P.Element(
        input_pins = order,
        output_pins = order,
        element_value = model,
        transformation = transformation,
        connection = connection
    )
end

function P.overhead_line(
        parameters::LCM.LineParameters;
        length,
        transformation = false,
        connection = true,
        extrapolation = :error
)
    return _line_element(
        _LineParametersOverheadLine,
        :overhead_line,
        parameters;
        length,
        transformation,
        connection,
        extrapolation
    )
end

function P.cable(
        parameters::LCM.LineParameters;
        length,
        transformation = false,
        connection = true,
        extrapolation = :error
)
    return _line_element(
        _LineParametersCable,
        :cable,
        parameters;
        length,
        transformation,
        connection,
        extrapolation
    )
end

function _line_parameters_gridspace(
        constructor,
        parameters::LCM.LineParameters;
        length,
        transformation = false,
        connection = true,
        extrapolation = :error
)
    order = _validate_line_parameters(parameters)
    transformation isa Bool && _validate_configuration(order, transformation)
    target = _LineParametersElementMaterializer(constructor)
    axes = map(NB._axis, (
        parameters,
        length,
        transformation,
        connection,
        extrapolation
    ))
    names = (
        :line_parameters,
        :length,
        :transformation,
        :connection,
        :extrapolation
    )
    return NB.Gridspace{P.Element}(target, axes, names)
end

function NB.overhead_line(
        parameters::LCM.LineParameters;
        length,
        transformation = false,
        connection = true,
        extrapolation = :error
)
    return _line_parameters_gridspace(
        P.overhead_line,
        parameters;
        length,
        transformation,
        connection,
        extrapolation
    )
end

function NB.cable(
        parameters::LCM.LineParameters;
        length,
        transformation = false,
        connection = true,
        extrapolation = :error
)
    return _line_parameters_gridspace(
        P.cable,
        parameters;
        length,
        transformation,
        connection,
        extrapolation
    )
end

function _frequency_range_error(model, requested_frequency)
    first_frequency = first(model.parameters.f)
    last_frequency = last(model.parameters.f)
    return DomainError(
        requested_frequency,
        "requested frequency is outside the LineParameters range " *
        "[$first_frequency, $last_frequency] Hz. Include every frequency used by " *
        "the study (50 Hz for power flow, |f ± 50 Hz| for dq scans, and near " *
        "0 Hz for DC conversion), or pass extrapolation=:linear"
    )
end

function _frequency_bracket(model, requested_frequency::Real)
    frequencies = model.parameters.f
    target = abs(requested_frequency)
    isfinite(target) || throw(ArgumentError("the requested frequency must be finite"))
    index = searchsortedfirst(frequencies, target)

    if index <= lastindex(frequencies) && frequencies[index] == target
        return index, index, 0.0
    elseif index == firstindex(frequencies)
        model.extrapolation === :error &&
            throw(_frequency_range_error(model, requested_frequency))
        lower, upper = firstindex(frequencies), firstindex(frequencies) + 1
    elseif index > lastindex(frequencies)
        model.extrapolation === :error &&
            throw(_frequency_range_error(model, requested_frequency))
        lower, upper = lastindex(frequencies) - 1, lastindex(frequencies)
    else
        lower, upper = index - 1, index
    end

    fraction = (target - frequencies[lower]) /
               (frequencies[upper] - frequencies[lower])
    return lower, upper, fraction
end

function _interpolate_parameter(values, lower, upper, fraction)
    low = ComplexF64.(values[:, :, lower])
    lower == upper && return low
    high = ComplexF64.(values[:, :, upper])
    return (1 - fraction) .* low .+ fraction .* high
end

function _line_parameters_at(model::_LineParametersTransmissionLine, frequency::Real)
    lower, upper, fraction = _frequency_bracket(model, frequency)
    parameters = model.parameters
    Z = _interpolate_parameter(parameters.Z, lower, upper, fraction)
    Y = _interpolate_parameter(parameters.Y, lower, upper, fraction)
    if frequency < 0
        Z = conj.(Z)
        Y = conj.(Y)
    end
    return Z, Y
end

function P.eval_parameters(model::_LineParametersTransmissionLine, s::Complex)
    frequency = imag(s) / (2pi)
    return _line_parameters_at(model, frequency)
end

function P.eval_abcd(model::_LineParametersTransmissionLine, s::Complex)
    Z, Y = P.eval_parameters(model, s)
    propagation = sqrt(Matrix{ComplexF64}(Z * Y))
    characteristic_admittance = Z \ propagation
    wave_cosh = cosh(propagation * model.length)
    wave_sinh = sinh(propagation * model.length)
    order = size(Z, 1)
    abcd = Matrix{ComplexF64}(undef, 2order, 2order)
    abcd[1:order, 1:order] = wave_cosh
    abcd[1:order, (order + 1):end] = characteristic_admittance \ wave_sinh
    abcd[(order + 1):end, 1:order] = characteristic_admittance * wave_sinh
    abcd[(order + 1):end, (order + 1):end] = wave_cosh
    return abcd
end

function NB._has_measurement(parameters::LCM.LineParameters)
    NB._has_measurement(parameters.Z) ||
        NB._has_measurement(parameters.Y) ||
        NB._has_measurement(parameters.f)
end

function NB._zero_measurement(parameters::LCM.LineParameters)
    NB._zero_measurement(parameters.Z) &&
        NB._zero_measurement(parameters.Y) &&
        NB._zero_measurement(parameters.f)
end

_primitive_sort_key(key) = (key[3], key[1], key[2])

function _primitive_keys(parameters::LCM.LineParameters)
    keys = Set{Any}()
    for values in (parameters.Z, parameters.Y), value in values

        for component in (real(value), imag(value))
            NB._is_measurement(component) || continue
            union!(keys, Measurements.uncertainty_components(component) |> Base.keys)
        end
    end
    return sort!(collect(keys); by = _primitive_sort_key)
end

function _sample_component(component, draws)
    NB._is_measurement(component) || return Float64(component)
    sampled = Float64(Measurements.value(component))
    contributions = Measurements.uncertainty_components(component)
    for key in sort!(collect(keys(contributions)); by = _primitive_sort_key)
        coefficient = key[2] * Measurements.derivative(component, key)
        sampled += coefficient * draws[key]
    end
    return sampled
end

function _sample_parameter_array(values, draws)
    sampled = Array{ComplexF64}(undef, size(values))
    for index in eachindex(values)
        value = values[index]
        sampled[index] = complex(
            _sample_component(real(value), draws),
            _sample_component(imag(value), draws)
        )
    end
    return sampled
end

struct _LineParametersSamplingPlan
    domain::DataType
    dimensions::Tuple{Vararg{Int}}
    frequencies::Vector{Float64}
    primitive_keys::Vector{Any}
    Z_nominal::Vector{ComplexF64}
    Y_nominal::Vector{ComplexF64}
    Z_coefficients::Matrix{ComplexF64}
    Y_coefficients::Matrix{ComplexF64}
    Y_storage::Any
    frequency_storage::Any
end

const _LINE_PARAMETERS_SAMPLING_PLANS = IdDict{Any, _LineParametersSamplingPlan}()
const _LINE_PARAMETERS_SAMPLING_PLAN_LOCK = ReentrantLock()

function _complex_nominal(value)
    return complex(
        Float64(NB._measurement_nominal(real(value))),
        Float64(NB._measurement_nominal(imag(value)))
    )
end

function _complex_coefficient(value, key)
    real_coefficient = NB._is_measurement(real(value)) ?
        key[2] * Measurements.derivative(real(value), key) : 0.0
    imag_coefficient = NB._is_measurement(imag(value)) ?
        key[2] * Measurements.derivative(imag(value), key) : 0.0
    return complex(Float64(real_coefficient), Float64(imag_coefficient))
end

function _coefficient_matrix(values, primitive_keys)
    coefficients = Matrix{ComplexF64}(
        undef, length(values), length(primitive_keys))
    for (column, key) in enumerate(primitive_keys), index in eachindex(values)
        coefficients[index, column] = _complex_coefficient(values[index], key)
    end
    return coefficients
end

function _build_sampling_plan(parameters::LCM.LineParameters)
    primitive_keys = Any[_primitive_keys(parameters)...]
    Z_values = parameters.Z.values
    Y_values = parameters.Y.values
    return _LineParametersSamplingPlan(
        LCM.domain(parameters),
        size(Z_values),
        Float64.(parameters.f),
        primitive_keys,
        _complex_nominal.(vec(Z_values)),
        _complex_nominal.(vec(Y_values)),
        _coefficient_matrix(Z_values, primitive_keys),
        _coefficient_matrix(Y_values, primitive_keys),
        Y_values,
        parameters.f
    )
end

function _sampling_plan(parameters::LCM.LineParameters)
    Z_storage = parameters.Z.values
    Y_storage = parameters.Y.values
    frequency_storage = parameters.f
    return lock(_LINE_PARAMETERS_SAMPLING_PLAN_LOCK) do
        cached = get(_LINE_PARAMETERS_SAMPLING_PLANS, Z_storage, nothing)
        if cached !== nothing && cached.Y_storage === Y_storage &&
                cached.frequency_storage === frequency_storage
            return cached
        end
        plan = _build_sampling_plan(parameters)
        _LINE_PARAMETERS_SAMPLING_PLANS[Z_storage] = plan
        return plan
    end
end

function _sample_plan(rng, plan::_LineParametersSamplingPlan, distribution)
    standardized = NB._distribution(distribution, 0.0, 1.0)
    draws = Float64[Random.rand(rng, standardized)
        for _ in plan.primitive_keys]
    Z_values = plan.Z_nominal + plan.Z_coefficients * draws
    Y_values = plan.Y_nominal + plan.Y_coefficients * draws
    Z = copy(reshape(Z_values, plan.dimensions))
    Y = copy(reshape(Y_values, plan.dimensions))
    return LCM.LineParameters(plan.domain, Z, Y, plan.frequencies)
end

function NB._sample_value(
        rng,
        parameters::LCM.LineParameters,
        distribution
)
    any(NB._has_measurement, parameters.f) && throw(ArgumentError(
        "uncertain LineParameters frequencies are unsupported; use a deterministic, ordered frequency grid",
    ))
    return _sample_plan(rng, _sampling_plan(parameters), distribution)
end

function NB._measurement_description(parameters::LCM.LineParameters)
    measured_components = 0
    for values in (parameters.Z, parameters.Y), value in values

        measured_components += NB._is_measurement(real(value))
        measured_components += NB._is_measurement(imag(value))
    end
    return (
        kind = :line_parameters,
        domain = LCM.domain(parameters),
        order = size(parameters.Z, 1),
        frequencies = (
            first = first(parameters.f),
            last = last(parameters.f),
            count = length(parameters.f)
        ),
        measured_components,
        primitive_uncertainties = length(_primitive_keys(parameters)),
        units = (Z = :ohm_per_m, Y = :siemens_per_m)
    )
end

end
