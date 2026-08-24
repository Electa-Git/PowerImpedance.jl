module PowerImpedanceMakieExt

using DocStringExtensions: TYPEDSIGNATURES
using Makie
using PowerImpedance

const PlotBuilder = PowerImpedance.PlotBuilder
const BackendHandler = PlotBuilder.BackendHandler

function current_backend_symbol()
    name = nameof(Makie.current_backend())
    name === :CairoMakie && return :cairo
    name === :GLMakie && return :gl
    name === :WGLMakie && return :wgl
    return :unknown
end

renderfig(figure) = display(figure)

include(joinpath(@__DIR__, "..", "src", "PlotBuilder", "UIComponents.jl"))
using .UIComponents

import PowerImpedance: plot

function _scale_symbol(value)
    value isa Symbol && return value
    value === Makie.identity && return :linear
    value === Makie.log10 && return :log10
    throw(ArgumentError("xscale must be :linear, :log10, Makie.identity, or Makie.log10"))
end

"""
    PowerImpedance.plot(result::FrequencyResponseResult; kwargs...)

Render the harmonic nodal-impedance magnitude contained in `result` using
the active Makie backend. Frequencies are displayed in Hz and impedance
magnitudes in dBΩ.
"""
const _CompletedFrequencyResponseResult = Union{
    PowerImpedance.FrequencyResponseResult,
    PowerImpedance.AbstractParametricResult{<:PowerImpedance.FrequencyResponseResult},
    PowerImpedance.AbstractUncertaintyResult{<:PowerImpedance.FrequencyResponseResult},
}

_response_kind(result::PowerImpedance.FrequencyResponseResult) = result.kind
function _response_kind(result::PowerImpedance.AbstractParametricResult)
    isempty(result.values) && throw(ArgumentError("the result contains no completed responses"))
    return first(result.values).kind
end
function _response_kind(result::PowerImpedance.AbstractUncertaintyResult)
    values = PowerImpedance._frequency_response_values(result)
    isempty(values) && throw(ArgumentError("the result contains no completed responses"))
    return first(values).kind
end

function _completed_bode(result::PowerImpedance.FrequencyResponseResult)
    return PowerImpedance.compute(
        PowerImpedance.StabilityProblem(result),
        PowerImpedance.BodeAnalysis(),
    )
end
function _completed_bode(
    result::PowerImpedance.AbstractParametricResult{<:PowerImpedance.FrequencyResponseResult},
)
    values = [_completed_bode(value) for value in result.values]
    return PowerImpedance.ParametricResult(
        result.formulation,
        values,
        result.space,
        merge(result.details, (; source_checkpoint=result)),
    )
end
function _completed_bode(
    result::PowerImpedance.LinearErrorResult{<:PowerImpedance.FrequencyResponseResult},
)
    values = [_completed_bode(value) for value in result.values]
    return PowerImpedance.LinearErrorResult(
        result.formulation,
        values,
        result.space,
        merge(result.details, (; source_checkpoint=result)),
    )
end
function _completed_bode(
    result::PowerImpedance.MonteCarloResult{<:PowerImpedance.FrequencyResponseResult},
)
    method = result.formulation
    return PowerImpedance.compute(
        PowerImpedance.StabilityProblem(result),
        PowerImpedance.MonteCarlo(
            PowerImpedance.BodeAnalysis();
            backend=method.backend,
            distribution=method.distribution,
            seed=method.seed,
            confidence=method.confidence,
            tolerance=method.tolerance,
            return_samples=method.return_samples,
            failure_policy=method.failure_policy,
        ),
    )
end

function plot(
        result::_CompletedFrequencyResponseResult;
        backend = nothing,
        display_plot::Bool = true,
        controls::Bool = true,
        xscale = :log10,
        kwargs...
)
    if _response_kind(result) === :nodal_impedance
        render = PlotBuilder.make_render(
            PowerImpedance.HarmonicImpedancePlotDefinition,
            result;
            xscale = _scale_symbol(xscale),
            kwargs...
        )
        return UIComponents.build(render; backend, display = display_plot, controls)
    end
    completed = _completed_bode(result)
    return plot(
        completed;
        backend,
        display_plot,
        controls,
        xscale=_scale_symbol(xscale),
        kwargs...,
    )
end

function _stability_definition(analysis::Symbol)
    analysis === :nyquist && return PowerImpedance.NyquistPlotDefinition
    analysis === :bode && return PowerImpedance.BodePlotDefinition
    analysis === :passivity && return PowerImpedance.PassivityPlotDefinition
    analysis === :small_gain && return PowerImpedance.SmallGainPlotDefinition
    analysis === :eigenvalue && return PowerImpedance.EigenvaluePlotDefinition
    analysis === :unstable_frequency && return PowerImpedance.UnstableFrequencyPlotDefinition
    throw(ArgumentError("no plot definition is registered for analysis :$analysis"))
end

_stability_analysis(result::PowerImpedance.StabilityResult) = result.analysis
function _stability_analysis(result::PowerImpedance.AbstractParametricResult)
    isempty(result.values) && throw(ArgumentError("the result contains no completed values"))
    return first(result.values).analysis
end
function _stability_analysis(result::PowerImpedance.AbstractUncertaintyResult)
    grouped = result.details.plot_data.values
    isempty(grouped) && throw(ArgumentError("the result contains no completed plot data"))
    return first(first(grouped)).analysis
end

function plot(
    result::Union{
        PowerImpedance.StabilityResult,
        PowerImpedance.AbstractParametricResult{<:PowerImpedance.StabilityResult},
        PowerImpedance.AbstractUncertaintyResult{<:PowerImpedance.StabilityResult},
    };
    backend=nothing,
    display_plot::Bool=true,
    controls::Bool=true,
    plots=nothing,
    kwargs...,
)
    definition = _stability_definition(_stability_analysis(result))
    render = PlotBuilder.make_render(definition, result; kwargs...)
    if plots !== nothing
        definition === PowerImpedance.BodePlotDefinition || throw(ArgumentError(
            "existing UIPlot targets are supported only by Bode plotting",
        ))
        targets = plots isa PlotBuilder.UIPlot ? [plots] : plots
        targets isa AbstractVector{<:PlotBuilder.UIPlot} || throw(ArgumentError(
            "plots must be a UIPlot or a vector of UIPlot handles",
        ))
        updated = UIComponents.overlay!(targets, render)
        return plots isa PlotBuilder.UIPlot ? only(updated) : updated
    end
    return UIComponents.build(render; backend, display=display_plot, controls)
end

"""
$(TYPEDSIGNATURES)

Render a harmonic nodal-impedance result through PowerImpedance's
declarative Makie recipe.
"""
function Makie.plot(result::_CompletedFrequencyResponseResult; kwargs...)
    return plot(result; kwargs...)
end


function Makie.plot(
    result::Union{
        PowerImpedance.StabilityResult,
        PowerImpedance.AbstractParametricResult{<:PowerImpedance.StabilityResult},
        PowerImpedance.AbstractUncertaintyResult{<:PowerImpedance.StabilityResult},
    };
    kwargs...,
)
    return plot(result; kwargs...)
end

end
