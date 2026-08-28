@testset "GraphMakie diagram PlotBuilder recipe" begin
    network = diagram_hybrid_network()
    layout_calls = Ref(0)
    counting_layout = graph -> begin
        layout_calls[] += 1
        return [Makie.Point2f(index, isodd(index) ? 0 : 1)
                for index in 1:Graphs.nv(graph)]
    end

    render = PowerImpedance.PlotBuilder.make_render(
        NetworkDiagramDefinition,
        network;
        graph_layout = counting_layout,
        title = "Hybrid network diagram",
        figure_size = (920, 560),
        open_export = false
    )
    @test layout_calls[] == 1
    @test render.definition === NetworkDiagramDefinition
    page = only(render.figures)
    @test page.size == (920, 560)
    @test page.layout.name == :network_diagram
    @test length(only(page.layout.grids).columns) == 1
    @test !page.legend.enabled
    @test page.controls.reset
    @test page.controls.export_svg
    view_definition = only(page.views)
    @test view_definition.xaxis.allowed_scales == (:linear,)
    @test view_definition.yaxis.allowed_scales == (:linear,)
    @test only(view_definition.series).kind == :network_diagram

    handles = PowerImpedance.PlotBuilder.build(
        render;
        backend = :cairo,
        display = false,
        controls = true
    )
    handle = only(handles)
    try
        @test handle isa UIPlot
        @test Set(keys(handle.controls)) == Set((:reset, :export_svg))
        @test Set(keys(handle.artifacts)) == Set((:network_diagram,))
        @test !any(content -> content isa Makie.Legend, handle.figure.content)

        diagram_view = handle.artifacts[:network_diagram]
        @test diagram_view isa DiagramExtension.NetworkDiagram
        @test diagram_view.figure === handle.figure
        @test diagram_view.axis === only(handle.panels).axis
        @test diagram_view.positions == only(view_definition.series).zdata.positions
        @test haskey(
            diagram_view.axis.interactions,
            :powerimpedance_diagram_select
        )

        component = DiagramExtension.ComponentKey(:converter)
        positions_before = copy(diagram_view.positions)
        graph_before = diagram_view.model.graph
        DiagramExtension.select!(diagram_view, component)
        @test diagram_view.selected[] == component
        @test diagram_view.details[].role == :converter
        @test length(diagram_view.highlight[]) == 1
        @test diagram_view.positions == positions_before
        @test diagram_view.model.graph === graph_before
        @test layout_calls[] == 1

        axis = diagram_view.axis
        initial_limits = axis.finallimits[]
        Makie.xlims!(axis, -1, 1)
        handle.controls[:reset].clicks[] += 1
        Makie.update_state_before_display!(handle.figure)
        reset_limits = axis.finallimits[]
        @test reset_limits.origin ≈ initial_limits.origin
        @test reset_limits.widths ≈ initial_limits.widths
        @test handle.context.status[] == "Axis limits reset"
        @test layout_calls[] == 1

        Makie.resize!(handle.figure, 760, 430)
        Makie.update_state_before_display!(handle.figure)
        compact_box = axis.layoutobservables.computedbbox[]
        @test compact_box.origin[1] + compact_box.widths[1] > 0.95 * 760

        Makie.resize!(handle.figure, 1200, 600)
        Makie.update_state_before_display!(handle.figure)
        wide_box = axis.layoutobservables.computedbbox[]
        @test wide_box.widths[1] > compact_box.widths[1] + 400
        @test wide_box.origin[1] + wide_box.widths[1] > 0.95 * 1200

        output = joinpath(mktempdir(), "network-plotbuilder.svg")
        @test export_svg(handle; path = output, open_file = false) == output
        @test isfile(output)
        @test filesize(output) > 100
        @test occursin("<svg", read(output, String))
        @test layout_calls[] == 1
    finally
        foreach(close, handles)
    end

    portrait_render = PowerImpedance.PlotBuilder.make_render(
        NetworkDiagramDefinition,
        network;
        graph_layout = graph -> [Makie.Point2f(isodd(index), index)
                                 for index in 1:Graphs.nv(graph)],
        figure_size = :auto,
        open_export = false
    )
    portrait_size = only(portrait_render.figures).size
    @test portrait_size[1] < portrait_size[2]
    @test portrait_size[1] >= 480
    @test portrait_size[2] >= 420

    powerflow = diagram_powerflow_fixture(network)
    data_before = deepcopy(powerflow.data)
    result_before = deepcopy(powerflow.result)
    enriched_handles = PowerImpedance.plot(
        network,
        powerflow;
        backend = :cairo,
        display_plot = false,
        interactive = false,
        open_export = false
    )
    try
        enriched = only(enriched_handles).artifacts[:network_diagram]
        component = only(item
        for item in enriched.model.components
        if item.key.element == :ac_line)
        @test component.input === powerflow.data["branch"]["1"]
        @test component.solution === powerflow.result["solution"]["branch"]["1"]
        @test powerflow.data == data_before
        @test powerflow.result == result_before
    finally
        foreach(close, enriched_handles)
    end
end
