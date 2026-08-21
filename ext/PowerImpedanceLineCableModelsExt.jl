module PowerImpedanceLineCableModelsExt

using LineCableModels
using DocStringExtensions: TYPEDSIGNATURES

const LCM = LineCableModels
using PowerImpedance
const P = PowerImpedance

const NB = P.NetworkBuilder

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
        "PowerImpedance requires phase-domain LineParameters; " *
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
        "unsupported LineParameters order $order; PowerImpedance supports one, two, or three phase conductors",
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
        "use `PowerImpedance.$constructor(Grid, parameters; ...)`",
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

"""
$(TYPEDSIGNATURES)

Construct a native overhead-line `Element` from deterministic, phase-domain
line parameters. `Z` [Ω/m] and `Y` [S/m] are scaled by the positive `length`
[m] and interpolated entrywise over the tabulated frequencies [Hz]. Use
`overhead_line` with the positional `Grid` marker when the parameters or constructor
arguments are uncertain or parametric.
"""
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

"""
$(TYPEDSIGNATURES)

Construct a native cable `Element` from deterministic, phase-domain line
parameters. `Z` [Ω/m] and `Y` [S/m] are scaled by the positive `length` [m]
and interpolated entrywise over the tabulated frequencies [Hz]. Use
`cable` with the positional `Grid` marker when the parameters or constructor arguments
are uncertain or parametric.
"""
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
    inputs = (
        line_parameters=parameters,
        length=length,
        transformation=transformation,
        connection=connection,
        extrapolation=extrapolation,
    )
    return NB._lift_gridspace(P.Element, target, inputs, Val(:product))
end

"""
$(TYPEDSIGNATURES)

Construct a lazy overhead-line `Gridspace` from phase-domain, per-metre line
parameters through the package's explicit positional `Grid` marker.

# Arguments

- `Grid`: the `PowerImpedance.Grid` constructor, used here
  as a positional dispatch marker.
- `parameters`: phase-domain `LineParameters` with `Z` in [Ω/m], `Y` in [S/m],
  and deterministic frequencies in [Hz].
- `length`: positive line length [m], or an explicit Gridspace axis.
- `transformation`: `false` for one conductor, `true` for two conductors, and
  either value for three conductors.
- `connection`: whether the resulting element participates in the network.
- `extrapolation`: `:error` or `:linear` outside the tabulated frequencies.

# Returns

- A lazy `Gridspace` that samples uncertain line parameters and constructor
  fields into ordinary numeric values before line evaluation.

# Notes

The keyword-only `overhead_line(parameters; ...)` method remains the scalar
constructor.
"""
function P.overhead_line(
        ::typeof(NB.Grid),
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

"""
$(TYPEDSIGNATURES)

Construct a lazy cable `Gridspace` from phase-domain line parameters. `Z` and
`Y` are interpreted as per-metre matrices in [Ω/m] and [S/m], `length` is in
[m], and frequencies are in [Hz]. The positional `Grid` marker selects the
lazy constructor. The scalar [`cable`](@ref) method remains the deterministic
native overload.

Uncertainty is sampled jointly within `parameters` before line evaluation.
`extrapolation` accepts `:error` or `:linear`.
"""
function P.cable(
        ::typeof(NB.Grid),
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

function P.primitives(
    parameters::LCM.LineParameters,
    ::P.LineParametersInput;
    options::NamedTuple=(;),
)
    return (
        domain=LCM.domain(parameters),
        series_impedance=parameters.Z,
        shunt_admittance=parameters.Y,
        frequencies=parameters.f,
    )
end

end
