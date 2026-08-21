"""
    PowerImpedance.Grammar

Define the package-local problem, formulation, result, and parameter-space
language used by PowerImpedance calculations.
"""
module Grammar

using DocStringExtensions: TYPEDEF, TYPEDFIELDS

import ..PowerImpedance: PIACDC

export AbstractProblemDefinition, AbstractFormulation, AbstractResolutionResult
export AbstractParametricResult, AbstractUncertaintyResult
export compute, primitives, preprocess
export AbstractGrid, AbstractUncertainGrid, Grid, DeterministicGrid
export RelativeGrid, AbsoluteGrid, AbsoluteError, UncertainValue
export Gridspace, Configuration, configurations, materialize
export has_uncertainty, configuration_manifest, nominal, standard_uncertainty
export @gridspace, @relax
export ParametricProblem, Combinatorial, LinearError, MonteCarlo
export ParametricResult, LinearErrorResult, MonteCarloResult
export LineParametersInput, EmpiricalSamples, MeasurementsSurrogate

"Abstract supertype for calculation problem definitions."
abstract type AbstractProblemDefinition end

"Abstract supertype for numerical formulations."
abstract type AbstractFormulation end

"Abstract supertype for completed calculation results."
abstract type AbstractResolutionResult end

"Abstract supertype for deterministic parameter-study results containing `T`."
abstract type AbstractParametricResult{T} end

"Abstract supertype for uncertainty-study results containing `T`."
abstract type AbstractUncertaintyResult{T} end

"Calculate `problem` with `formulation`."
function compute end

"Project a completed external checkpoint into an explicit accepted input."
function primitives end

"Prepare a completed PowerImpedance checkpoint for a subsequent formulation."
function preprocess end

include("Network/NetworkBuilder/gridspace/grid.jl")
include("Network/NetworkBuilder/gridspace/gridspace.jl")
include("Network/NetworkBuilder/gridspace/macros.jl")

"""
$(TYPEDEF)

Specify evaluation of a PowerImpedance-owned parameter space.

$(TYPEDFIELDS)
"""
struct ParametricProblem{S,O} <: AbstractProblemDefinition
    "Space whose configurations materialize owned problems."
    space::S

    "Options merged into each scalar calculation."
    options::O
end

ParametricProblem(space, options::NamedTuple=(;)) =
    ParametricProblem{typeof(space),typeof(options)}(space, options)

function _failure_policy(value::Symbol)
    value in (:error, :record) || throw(ArgumentError(
        "failure_policy must be :error or :record; got :$value",
    ))
    return value
end

"""
$(TYPEDEF)

Enumerate every deterministic configuration and apply `inner`.

$(TYPEDFIELDS)
"""
struct Combinatorial{F,B} <: AbstractFormulation
    "Scalar formulation applied to each materialized problem."
    inner::F

    "Resolved higher-order execution backend."
    backend::Type{B}

    "Behavior when a configuration fails."
    failure_policy::Symbol
end


function Combinatorial(
    inner::F;
    backend::Type{B}=PIACDC,
    failure_policy::Symbol=:error,
) where {F,B}
    return Combinatorial{F,B}(inner, backend, _failure_policy(failure_policy))
end

"""
$(TYPEDEF)

Propagate first-order uncertainty through `inner` without random sampling.

$(TYPEDFIELDS)
"""
struct LinearError{F,B} <: AbstractFormulation
    "Scalar formulation evaluated with uncertainty-aware numeric values."
    inner::F

    "Resolved higher-order execution backend."
    backend::Type{B}

    "Behavior when a configuration fails."
    failure_policy::Symbol
end


function LinearError(
    inner::F;
    backend::Type{B}=PIACDC,
    failure_policy::Symbol=:error,
) where {F,B}
    return LinearError{F,B}(inner, backend, _failure_policy(failure_policy))
end

"""
$(TYPEDEF)

Specify Monte Carlo evaluation of uncertain configurations.

$(TYPEDFIELDS)
"""
struct MonteCarlo{F,B,S} <: AbstractFormulation
    "Scalar formulation applied to every numeric trial."
    inner::F

    "Resolved higher-order execution backend."
    backend::Type{B}

    "Requested trial count, or `nothing` for DKW sizing."
    trials::Union{Nothing,Int}

    "Primitive sampling distribution."
    distribution::Symbol

    "Master random seed."
    seed::S

    "Simultaneous confidence level."
    confidence::Float64

    "DKW tolerance."
    tolerance::Float64

    "Whether raw numeric trial samples are retained."
    return_samples::Bool

    "Behavior when a configuration or trial fails."
    failure_policy::Symbol
end


function MonteCarlo(
    inner::F;
    backend::Type{B}=PIACDC,
    trials=nothing,
    distribution::Symbol=:normal,
    seed=nothing,
    confidence::Real=0.95,
    tolerance::Real=0.02,
    return_samples::Bool=false,
    failure_policy::Symbol=:error,
) where {F,B}
    distribution in (:normal, :uniform) || throw(ArgumentError(
        "distribution must be :normal or :uniform; got :$distribution",
    ))
    trial_count = isnothing(trials) ? nothing : Int(trials)
    trial_count === nothing || trial_count > 0 || throw(ArgumentError(
        "trials must be positive",
    ))
    0 < confidence < 1 || throw(ArgumentError("confidence must lie in (0, 1)"))
    tolerance > 0 || throw(ArgumentError("tolerance must be positive"))
    return MonteCarlo{F,B,typeof(seed)}(
        inner,
        backend,
        trial_count,
        distribution,
        seed,
        Float64(confidence),
        Float64(tolerance),
        return_samples,
        _failure_policy(failure_policy),
    )
end

"""
$(TYPEDEF)

Store deterministic primitive results and their resolved configurations.

$(TYPEDFIELDS)
"""
struct ParametricResult{T,F,V<:AbstractVector{T},S,D} <: AbstractParametricResult{T}
    "Higher-order formulation used for the study."
    formulation::F

    "Primitive results aligned with `space`."
    values::V

    "Resolved successful configuration manifests."
    space::S

    "Named execution metadata."
    details::D
end


"""
$(TYPEDEF)

Store primitive results calculated by direct first-order propagation.

$(TYPEDFIELDS)
"""
struct LinearErrorResult{T,F,V<:AbstractVector{T},S,D} <: AbstractUncertaintyResult{T}
    "`LinearError` formulation used for the study."
    formulation::F

    "Uncertainty-aware primitive results aligned with `space`."
    values::V

    "Resolved successful configuration manifests."
    space::S

    "Named propagation metadata."
    details::D
end


"""
$(TYPEDEF)

Store Monte Carlo statistics and their resolved trial configurations.

$(TYPEDFIELDS)
"""
struct MonteCarloResult{T,F,Sv,S,D} <: AbstractUncertaintyResult{T}
    "`MonteCarlo` formulation used for the study."
    formulation::F

    "Statistics aligned with configuration groups."
    stats::Sv

    "Resolved successful trial manifests."
    space::S

    "Named sampling, replay, and failure metadata."
    details::D
end


function MonteCarloResult{T}(formulation, stats, space, details=(;)) where {T}
    return MonteCarloResult{T,typeof(formulation),typeof(stats),typeof(space),typeof(details)}(
        formulation,
        stats,
        space,
        details,
    )
end

"Select deterministic line parameters from a completed donor checkpoint."
struct LineParametersInput{B} <: AbstractFormulation
    backend::Type{B}
end
LineParametersInput(; backend::Type{B}=PIACDC) where {B} =
    LineParametersInput{B}(backend)

"Select retained whole-trial values from a completed donor checkpoint."
struct EmpiricalSamples{B} <: AbstractFormulation
    backend::Type{B}
end
EmpiricalSamples(; backend::Type{B}=PIACDC) where {B} = EmpiricalSamples{B}(backend)

"Construct an explicit Measurements moment surrogate from a donor checkpoint."
struct MeasurementsSurrogate{B} <: AbstractFormulation
    backend::Type{B}
end
MeasurementsSurrogate(; backend::Type{B}=PIACDC) where {B} =
    MeasurementsSurrogate{B}(backend)

function primitives(result, projection::AbstractFormulation; options::NamedTuple=(;))
    throw(ArgumentError(
        "no primitives projection from $(typeof(result)) with $(typeof(projection)); " *
        "define PowerImpedance.Grammar.primitives for this checkpoint and projection",
    ))
end

function preprocess(result, formulation::AbstractFormulation; options::NamedTuple=(;))
    throw(ArgumentError(
        "no preprocessing path from $(typeof(result)) to $(typeof(formulation)); " *
        "define PowerImpedance.Grammar.preprocess before starting the next calculation",
    ))
end

end


using .Grammar: AbstractProblemDefinition, AbstractFormulation
using .Grammar: AbstractResolutionResult, AbstractParametricResult
using .Grammar: AbstractUncertaintyResult
import .Grammar: compute, primitives, preprocess
using .Grammar: AbstractGrid, AbstractUncertainGrid, Grid, DeterministicGrid
using .Grammar: RelativeGrid, AbsoluteGrid, AbsoluteError, UncertainValue
using .Grammar: Gridspace, Configuration, configurations, materialize
using .Grammar: has_uncertainty, configuration_manifest, nominal, standard_uncertainty
using .Grammar: @gridspace, @relax
using .Grammar: ParametricProblem, Combinatorial, LinearError, MonteCarlo
using .Grammar: ParametricResult, LinearErrorResult, MonteCarloResult
using .Grammar: LineParametersInput, EmpiricalSamples, MeasurementsSurrogate

export Grammar
export AbstractProblemDefinition, AbstractFormulation, AbstractResolutionResult
export AbstractParametricResult, AbstractUncertaintyResult
export compute, primitives, preprocess
export AbstractGrid, AbstractUncertainGrid, Grid, DeterministicGrid
export RelativeGrid, AbsoluteGrid, AbsoluteError, UncertainValue
export Gridspace, Configuration, configurations, materialize
export has_uncertainty, configuration_manifest, nominal, standard_uncertainty
export @gridspace, @relax
export ParametricProblem, Combinatorial, LinearError, MonteCarlo
export ParametricResult, LinearErrorResult, MonteCarloResult
export LineParametersInput, EmpiricalSamples, MeasurementsSurrogate
