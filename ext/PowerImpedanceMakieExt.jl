module PowerImpedanceMakieExt

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
function plot(
        result::PowerImpedance.FrequencyResponseResult;
        backend = nothing,
        display_plot::Bool = true,
        controls::Bool = true,
        xscale = :log10,
        kwargs...
)
    render = PlotBuilder.make_render(
        PowerImpedance.HarmonicImpedancePlotSpec,
        result;
        xscale = _scale_symbol(xscale),
        kwargs...
    )
    return UIComponents.build(render; backend, display = display_plot, controls)
end

"""
    Makie.plot(result::FrequencyResponseResult; kwargs...)

Render a harmonic nodal-impedance result through PowerImpedance's
declarative Makie recipe.
"""
function Makie.plot(result::PowerImpedance.FrequencyResponseResult; kwargs...)
    return plot(result; kwargs...)
end

end
