export OperatingPoint, PowerFlowResult, LinearizationResult
export PowerImpedanceProblem, StabilityProblem
export NodalImpedance, NodeAdmittance, EdgeAdmittance, LoopGain
export GeneralizedNyquist, BodeAnalysis, PassivityAnalysis, SmallGainAnalysis
export EigenvalueAnalysis, UnstableFrequencyAnalysis
export FrequencyResponseResult, StabilityResult

const _FORMULATION_BACKENDS = IdDict{Any, DataType}()

function _register_backend!(formulation::Type, backend::Type)
    _FORMULATION_BACKENDS[formulation] = backend
    return backend
end

_default_backend(formulation::Type) = get(_FORMULATION_BACKENDS, formulation, PIACDC)

"""
$(TYPEDEF)

Store the steady-state quantities required to linearize active elements.

$(TYPEDFIELDS)
"""
struct OperatingPoint
    "Calculated steady-state values indexed by element name."
    setpoints::Dict{Symbol, Setpoint}
end

OperatingPoint() = OperatingPoint(Dict{Symbol, Setpoint}())
Base.getindex(point::OperatingPoint, element::Symbol) = point.setpoints[element]
function Base.get(point::OperatingPoint, element::Symbol, default)
    get(point.setpoints, element, default)
end
Base.keys(point::OperatingPoint) = keys(point.setpoints)
Base.isempty(point::OperatingPoint) = isempty(point.setpoints)

"""
$(TYPEDEF)

Store one PowerModelsACDC power-flow calculation and its operating point.

$(TYPEDFIELDS)
"""
struct PowerFlowResult{F, R, D, N, E, G} <: AbstractProblemResult
    "Resolved power-flow formulation."
    formulation::F

    "PowerModelsACDC solution and termination information."
    result::R

    "PowerModelsACDC input data used by the calculation."
    data::D

    "Mapping from PowerImpedance nodes to power-flow buses."
    nodes2bus::N

    "Mapping from PowerImpedance elements to power-flow components."
    elem2comp::E

    "Steady-state quantities used for active-element linearization."
    operating_point::OperatingPoint

    "Convergence status and solver diagnostics."
    diagnostics::G
end

function Base.getproperty(result::PowerFlowResult, field::Symbol)
    field === :active_setpoint_values && return getfield(result, :operating_point).setpoints
    return getfield(result, field)
end

function Base.propertynames(::PowerFlowResult, private::Bool = false)
    return (
        :formulation,
        :result,
        :data,
        :nodes2bus,
        :elem2comp,
        :operating_point,
        :diagnostics,
        :active_setpoint_values
    )
end

"""
$(TYPEDEF)

Store a linearized network and the operating point used to construct it.

$(TYPEDFIELDS)
"""
struct LinearizationResult{F, M, G} <: AbstractProblemResult
    "Resolved linearization formulation."
    formulation::F

    "Linearized frequency-domain network model."
    network_model::M

    "Steady-state point about which active elements were linearized."
    operating_point::OperatingPoint

    "Linearization diagnostics."
    diagnostics::G
end

"""
$(TYPEDEF)

Specify a network frequency-response calculation.

$(TYPEDFIELDS)
"""
struct PowerImpedanceProblem{N, K, E, F} <: AbstractProblemDefinition
    "Materialized network state or linearized network model."
    network::N

    "Ordered retained node names."
    nodes::K

    "Elements excluded from the response calculation."
    eliminated_elements::E

    "Minimum frequency, maximum frequency, and point count in hertz."
    frequency_range::F
end

function PowerImpedanceProblem(
        network;
        nodes = Symbol[],
        eliminated_elements = Symbol[],
        frequency_range = (0.001, 10_000.0, 2_000)
)
    return PowerImpedanceProblem(
        network,
        Symbol.(collect(nodes)),
        Symbol.(collect(eliminated_elements)),
        frequency_range
    )
end

"""
$(TYPEDEF)

Specify a small-signal analysis of completed frequency-response results.

$(TYPEDFIELDS)
"""
struct StabilityProblem{R} <: AbstractProblemDefinition
    "One frequency-response result or an explicit pair for small-gain analysis."
    response::R
end

abstract type AbstractPowerImpedanceFormulation{B} <: AbstractFormulation end

for Formulation in (:NodalImpedance, :NodeAdmittance, :EdgeAdmittance, :LoopGain)
    @eval begin
        struct $Formulation{B} <: AbstractPowerImpedanceFormulation{B}
            backend::Type{B}
        end

        function $Formulation(; backend::Type{B} = _default_backend($Formulation)) where {B}
            return $Formulation{B}(backend)
        end

        _register_backend!($Formulation, PIACDC)
    end
end

"""
$(TYPEDEF)

Apply generalized Nyquist analysis to a loop-gain response.

`order_maxima` is the neighborhood order used to identify oscillatory peaks.
"""
struct GeneralizedNyquist{B} <: AbstractPowerImpedanceFormulation{B}
    backend::Type{B}
    order_maxima::Int
end

function GeneralizedNyquist(;
        backend::Type{B} = _default_backend(GeneralizedNyquist),
        order_maxima::Integer = 5
) where {B}
    order_maxima > 0 || throw(ArgumentError("order_maxima must be positive"))
    return GeneralizedNyquist{B}(backend, Int(order_maxima))
end
_register_backend!(GeneralizedNyquist, PIACDC)

for Formulation in (:BodeAnalysis, :PassivityAnalysis, :SmallGainAnalysis)
    @eval begin
        struct $Formulation{B} <: AbstractPowerImpedanceFormulation{B}
            backend::Type{B}
        end

        function $Formulation(; backend::Type{B} = _default_backend($Formulation)) where {B}
            return $Formulation{B}(backend)
        end

        _register_backend!($Formulation, PIACDC)
    end
end

"""
$(TYPEDEF)

Apply eigenvalue analysis between `fmin` and `fmax` in hertz.

$(TYPEDFIELDS)
"""
struct EigenvalueAnalysis{B} <: AbstractPowerImpedanceFormulation{B}
    "Resolved calculation backend."
    backend::Type{B}

    "Lower assessment frequency \\[Hz\\]."
    fmin::Float64

    "Upper assessment frequency \\[Hz\\]."
    fmax::Float64

    "Whether to calculate the inverse-determinant index."
    determinant::Bool
end

function EigenvalueAnalysis(;
        backend::Type{B} = _default_backend(EigenvalueAnalysis),
        fmin::Real = 0.001,
        fmax::Real = 10_000.0,
        determinant::Bool = false
) where {B}
    0 < fmin < fmax || throw(ArgumentError("require 0 < fmin < fmax"))
    return EigenvalueAnalysis{B}(backend, Float64(fmin), Float64(fmax), determinant)
end
_register_backend!(EigenvalueAnalysis, PIACDC)

"""
$(TYPEDEF)

Detect oscillatory frequencies from complementary-sensitivity peaks.

`order_maxima` is the neighborhood order used to select candidate peaks.
"""
struct UnstableFrequencyAnalysis{B} <: AbstractPowerImpedanceFormulation{B}
    backend::Type{B}
    order_maxima::Int
end

function UnstableFrequencyAnalysis(;
        backend::Type{B} = _default_backend(UnstableFrequencyAnalysis),
        order_maxima::Integer = 5
) where {B}
    order_maxima > 0 || throw(ArgumentError("order_maxima must be positive"))
    return UnstableFrequencyAnalysis{B}(backend, Int(order_maxima))
end
_register_backend!(UnstableFrequencyAnalysis, PIACDC)

"""
$(TYPEDEF)

Store one scalar matrix frequency response.

$(TYPEDFIELDS)
"""
struct FrequencyResponseResult{F, R, W, N, M, G} <: AbstractProblemResult
    "Resolved response formulation."
    formulation::F

    "Response identifier."
    kind::Symbol

    "Numeric response with dimensions `n x n x nf`."
    response::R

    "Angular frequencies \\[rad/s\\]."
    frequencies::W

    "Ordered response nodes."
    nodes::N

    "Linearized network used by the calculation."
    network_model::M

    "Calculation diagnostics."
    diagnostics::G
end

"""
$(TYPEDEF)

Store one completed small-signal analysis without graphics objects.

$(TYPEDFIELDS)
"""
struct StabilityResult{F, O, G} <: AbstractProblemResult
    "Resolved stability formulation."
    formulation::F

    "Analysis identifier."
    analysis::Symbol

    "Calculated analysis quantities."
    output::O

    "Calculation diagnostics."
    diagnostics::G
end
