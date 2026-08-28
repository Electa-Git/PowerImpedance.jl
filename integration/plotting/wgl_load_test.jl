using Test
using PowerImpedance
using WGLMakie
using GraphMakie
using Graphs

include("diagram_fixture.jl")

@testset "WGLMakie extension load" begin
    @test Base.get_extension(PowerImpedance, :PowerImpedanceMakieExt) !== nothing
    @test Base.get_extension(PowerImpedance, :PowerImpedanceWGLMakieExt) !== nothing
    @test Base.get_extension(PowerImpedance, :PowerImpedanceGraphMakieExt) !== nothing
    @test PowerImpedance.PlotBuilder.BackendHandler.backend_available(:wgl)
    @test set_backend!(:wgl) === :wgl
    @test PowerImpedance.PlotBuilder.BackendHandler.current_backend_symbol() === :wgl

    network = diagram_hybrid_network()
    view = diagram(network, diagram_powerflow_fixture(network))
    @test view.figure isa Makie.Figure
    @test view.selected isa Makie.Observable
    @test view.details isa Makie.Observable
    @test haskey(view.axis.interactions, :powerimpedance_diagram_select)

    handles = PowerImpedance.plot(
        network,
        diagram_powerflow_fixture(network);
        backend = :wgl,
        display_plot = false,
        open_export = false
    )
    ui = only(handles)
    @test ui isa UIPlot
    @test Set(keys(ui.controls)) == Set((:reset, :export_svg))
    @test Set(keys(ui.artifacts)) == Set((:network_diagram,))
    @test ui.artifacts[:network_diagram].figure === ui.figure
    @test haskey(
        ui.artifacts[:network_diagram].axis.interactions,
        :powerimpedance_diagram_select
    )
    Makie.resize!(ui.figure, 880, 520)
    Makie.update_state_before_display!(ui.figure)
    @test only(ui.panels).axis.layoutobservables.computedbbox[].widths[1] > 800
    close(ui)
end
