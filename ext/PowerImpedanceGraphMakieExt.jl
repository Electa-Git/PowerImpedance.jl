module PowerImpedanceGraphMakieExt

import GraphMakie
import Graphs
import Makie
import NetworkLayout
import PowerImpedance
import DocStringExtensions: TYPEDSIGNATURES
import PowerImpedance: PowerFlowResult, diagram, plot

const NetworkBuilder = PowerImpedance.NetworkBuilder
const PlotBuilder = PowerImpedance.PlotBuilder

include("PowerImpedanceGraphMakieExt/projection.jl")
include("PowerImpedanceGraphMakieExt/render.jl")
include("PowerImpedanceGraphMakieExt/plotbuilder.jl")

function diagram(
        network::NetworkBuilder.NetworkState;
        layout = NetworkLayout.Stress(; seed = 1),
        positions = nothing,
        interactive::Bool = true,
        style::NamedTuple = (;)
)
    return _render_diagram(
        project_diagram(network);
        layout,
        positions,
        interactive,
        style
    )
end

function diagram(
        network::NetworkBuilder.NetworkState,
        powerflow::PowerFlowResult;
        layout = NetworkLayout.Stress(; seed = 1),
        positions = nothing,
        interactive::Bool = true,
        style::NamedTuple = (;)
)
    return _render_diagram(
        project_diagram(network, powerflow);
        layout,
        positions,
        interactive,
        style
    )
end

end
