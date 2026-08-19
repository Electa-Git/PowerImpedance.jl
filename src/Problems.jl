export OperatingPoint, PowerFlowResult, LinearizationResult
export PowerImpedanceProblem, StabilityProblem
export NodalImpedance, NodeAdmittance, EdgeAdmittance, LoopGain
export GeneralizedNyquist, BodeAnalysis, PassivityAnalysis, SmallGainAnalysis
export EigenvalueAnalysis, FrequencyResponseResult, StabilityResult
export ParametricProblem, UQuantProblem, Combinatorial, MonteCarlo

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

Store one PowerModelsACDC power-flow calculation and the operating point
derived from it.

$(TYPEDFIELDS)
"""
struct PowerFlowResult{R, D, N, E, G} <: AbstractResult
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
    fields = (
        :result,
        :data,
        :nodes2bus,
        :elem2comp,
        :operating_point,
        :diagnostics,
        :active_setpoint_values
    )
    return fields
end

"""
$(TYPEDEF)

Store a linearized network and the operating point used to construct it.

$(TYPEDFIELDS)
"""
struct LinearizationResult{M, G} <: AbstractResult
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
struct PowerImpedanceProblem{N, K, E, F} <: ProblemDefinition
    "Materialized network state or linearized network model."
    network::N
    "Ordered retained node names."
    nodes::K
    "Elements excluded from the response calculation."
    eliminated_elements::E
    "Minimum frequency, maximum frequency, and point count in hertz."
    frequency_range::F
end

"""
    PowerImpedanceProblem(network; nodes=Symbol[], eliminated_elements=Symbol[],
                          frequency_range=(0.001, 10_000.0, 2_000))

Construct a network frequency-response problem.
"""
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

Specify a small-signal analysis of a calculated frequency response.

$(TYPEDFIELDS)
"""
struct StabilityProblem{R, K} <: ProblemDefinition
    "Frequency-response result or numeric response."
    response::R
    "Analysis options forwarded to the scalar stability method."
    options::K
end

"""
    StabilityProblem(response; options=(;))

Construct a downstream small-signal analysis problem from a calculated
frequency response and analysis options.
"""
StabilityProblem(response; options = (;)) = StabilityProblem(response, options)

"Calculate nodal impedance with the validated network reduction method."
struct NodalImpedance <: AbstractFormulation end

"Calculate the admittance contributed by active elements."
struct NodeAdmittance <: AbstractFormulation end

"Calculate the admittance contributed by passive elements."
struct EdgeAdmittance <: AbstractFormulation end

"Calculate the matrix loop gain from node and edge admittances."
struct LoopGain <: AbstractFormulation end

"Apply the generalized Nyquist analysis."
struct GeneralizedNyquist <: AbstractFormulation end

"Apply the Bode magnitude-and-phase analysis."
struct BodeAnalysis <: AbstractFormulation end

"Apply the passivity analysis."
struct PassivityAnalysis <: AbstractFormulation end

"Apply the small-gain analysis."
struct SmallGainAnalysis <: AbstractFormulation end

"Apply the eigenvalue-decomposition analysis."
struct EigenvalueAnalysis <: AbstractFormulation end

"""
$(TYPEDEF)

Store one scalar matrix frequency response.

$(TYPEDFIELDS)
"""
struct FrequencyResponseResult{R, F, N, M, G} <: AbstractResult
    "Response identifier."
    kind::Symbol
    "Numeric response with dimensions `n × n × nf`."
    response::R
    "Angular frequencies \\[rad/s\\]."
    frequencies::F
    "Ordered response nodes."
    nodes::N
    "Linearized network used for the calculation."
    network_model::M
    "Calculation diagnostics."
    diagnostics::G
end

"""
$(TYPEDEF)

Store one scalar small-signal analysis.

$(TYPEDFIELDS)
"""
struct StabilityResult{O, P, G} <: AbstractResult
    "Analysis identifier."
    analysis::Symbol
    "Calculated analysis quantities."
    output::O
    "Constructed plot object or plot collection."
    plots::P
    "Analysis diagnostics."
    diagnostics::G
end

"""
$(TYPEDEF)

Specify deterministic evaluation of a parameter space.

$(TYPEDFIELDS)
"""
struct ParametricProblem{S, F, O} <: ProblemDefinition
    "Parameter space containing the materialized network cases."
    space::S
    "Scalar formulation applied to each case."
    formulation::F
    "Keyword options passed to the calculation."
    options::O
end

"""
    ParametricProblem(space, formulation)

Construct a deterministic parameter-enumeration problem with no additional
calculation options.
"""
ParametricProblem(space, formulation) = ParametricProblem(space, formulation, (;))

"""
$(TYPEDEF)

Specify uncertainty propagation through a parameter space.

$(TYPEDFIELDS)
"""
struct UQuantProblem{S, F, O} <: ProblemDefinition
    "Parameter space containing deterministic and uncertain network cases."
    space::S
    "Scalar formulation applied to each numeric trial."
    formulation::F
    "Keyword options passed to the calculation."
    options::O
end

"""
    UQuantProblem(space, formulation)

Construct an uncertainty-quantification problem with no additional calculation
options.
"""
UQuantProblem(space, formulation) = UQuantProblem(space, formulation, (;))

"Enumerate every deterministic parameter combination."
struct Combinatorial <: AbstractFormulation end

"""
$(TYPEDEF)

Specify a Monte Carlo calculation over an uncertain Gridspace.

$(TYPEDFIELDS)
"""
struct MonteCarlo{S} <: AbstractFormulation
    "Requested trial count, or `nothing` for DKW sizing."
    trials::Union{Nothing, Int}
    "Primitive sampling distribution."
    distribution::Symbol
    "Master random seed."
    seed::S
    "Simultaneous confidence level."
    confidence::Float64
    "DKW tolerance."
    tolerance::Float64
    "Whether to retain numeric trial samples."
    return_samples::Bool
end

"""
    MonteCarlo(; trials=nothing, distribution=:normal, seed=nothing,
                 confidence=0.95, tolerance=0.02, return_samples=false)

Specify sampling, DKW sizing, reproducibility, and sample-retention options for
an uncertainty calculation.
"""
function MonteCarlo(;
        trials = nothing,
        distribution::Symbol = :normal,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false
)
    return MonteCarlo(
        isnothing(trials) ? nothing : Int(trials),
        distribution,
        seed,
        Float64(confidence),
        Float64(tolerance),
        return_samples
    )
end
