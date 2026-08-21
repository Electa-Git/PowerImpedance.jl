using Test

const LOAD_ORDER = Symbol(get(ENV, "POWERIMPEDANCE_PLOTTING_LOAD_ORDER", "power_first"))
if LOAD_ORDER === :makie_first
    using CairoMakie
    using PowerImpedance
elseif LOAD_ORDER === :power_first
    using PowerImpedance
    using CairoMakie
else
    error("POWERIMPEDANCE_PLOTTING_LOAD_ORDER must be power_first or makie_first")
end

const TRACKED_UI_PLOTS = UIPlot[]

function track_ui_plots(plots::Vector{<:UIPlot})
    append!(TRACKED_UI_PLOTS, plots)
    return plots
end

function close_tracked_ui_plots!()
    foreach(close, Iterators.reverse(TRACKED_UI_PLOTS))
    empty!(TRACKED_UI_PLOTS)
    Makie.current_figure!(nothing)
    return nothing
end

atexit(close_tracked_ui_plots!)

function cairo_stability_responses()
    impedance = cairo_frequency_response()
    loop_gain = FrequencyResponseResult(
        LoopGain(),
        :loopgain,
        0.1 .* impedance.response,
        impedance.frequencies,
        impedance.nodes,
        impedance.network_model,
        (;),
    )
    admittance = FrequencyResponseResult(
        NodeAdmittance(),
        :node_admittance,
        impedance.response,
        impedance.frequencies,
        impedance.nodes,
        impedance.network_model,
        (;),
    )
    return loop_gain, admittance
end

function cairo_frequency_response()
    frequency = 10.0 .^ range(0, 4; length = 80)
    response = Array{ComplexF64}(undef, 2, 2, length(frequency))
    for (index, value) in enumerate(frequency)
        response[:, :, index] .= [2 + im * value / 30 0.25 + im * value / 300
                                  0.25 + im * value / 300 4 + im * value / 50]
    end
    return FrequencyResponseResult(
        NodalImpedance(),
        :nodal_impedance,
        response,
        2π .* frequency,
        [:source, :remote],
        nothing,
        nothing
    )
end

function cairo_legend_response(node_count::Int = 12)
    frequency = 10.0 .^ range(0, 4; length = 40)
    response = zeros(ComplexF64, node_count, node_count, length(frequency))
    for node in 1:node_count
        response[node, node, :] .= node .* (1 .+ im .* frequency ./ 100)
    end
    return FrequencyResponseResult(
        NodalImpedance(),
        :nodal_impedance,
        response,
        2π .* frequency,
        [Symbol("node_$node") for node in 1:node_count],
        nothing,
        nothing
    )
end

function cairo_square_response(node_count::Int)
    frequency = 10.0 .^ range(0, 4; length = 40)
    response = Array{ComplexF64}(
        undef, node_count, node_count, length(frequency)
    )
    for row in 1:node_count, column in 1:node_count

        response[row, column, :] .= (row + column / 10) .*
                                    (1 .+ im .* frequency ./ (80 + 10row + column))
    end
    return FrequencyResponseResult(
        NodalImpedance(),
        :nodal_impedance,
        response,
        2π .* frequency,
        [Symbol("node_$node") for node in 1:node_count],
        nothing,
        nothing
    )
end

function computed_frequency_response()
    elements = (
        branch = impedance(z = s -> 0.35 + s * 3.0e-3, pins = 1),
        source_shunt = impedance(z = s -> 1 / (s * 30.0e-6), pins = 1),
        remote_shunt = impedance(z = s -> 1 / (s * 45.0e-6), pins = 1)
    )
    connections = (
        (node = :source, element = :branch, side = 1, terminal = 1),
        (node = :remote, element = :branch, side = 2, terminal = 1),
        (node = :source, element = :source_shunt, side = 1, terminal = 1),
        (node = :gnd, element = :source_shunt, side = 2, terminal = 1),
        (node = :remote, element = :remote_shunt, side = 1, terminal = 1),
        (node = :gnd, element = :remote_shunt, side = 2, terminal = 1)
    )
    network = PowerImpedance.NetworkBuilder.define(elements, connections)
    return compute(
        PowerImpedanceProblem(
            network;
            nodes = [:source, :remote],
            frequency_range = (1.0, 5.0e3, 40)
        ),
        NodalImpedance()
    )
end

legend_labels(legend) = [entry.label[] for entry in last(first(legend.entrygroups[]))]
function visibility_state(handle)
    return Bool[plot_object.visible[] for panel in handle.panels
                for plot_object in panel.plots]
end

@testset "CairoMakie declarative plotting ($LOAD_ORDER)" begin
    @test Base.get_extension(PowerImpedance, :PowerImpedanceMakieExt) !== nothing
    @test Base.get_extension(PowerImpedance, :PowerImpedanceCairoMakieExt) !== nothing
    @test PowerImpedance.PlotBuilder.BackendHandler.current_backend_symbol() === :cairo
    @test set_backend!(:cairo) === :cairo

    result = cairo_frequency_response()
    plots = track_ui_plots(Makie.plot(
        result;
        backend = :cairo,
        display_plot = false,
        open_export = false,
        export_theme = :publication
    ))
    @test plots isa Vector{UIPlot}
    @test length(plots) == 1
    handle = only(plots)
    @test handle.context.backend === :cairo
    @test handle.figure.scene.backgroundcolor[] == Makie.to_color(:grey90)
    @test Set(keys(handle.controls)) == Set((:reset, :export_svg, :xlog, :legend))
    @test occursin("\\ue5d5", sprint(show, handle.controls[:reset].label[]))
    @test occursin("\\ue161", sprint(show, handle.controls[:export_svg].label[]))

    computed_result = computed_frequency_response()
    @test eltype(angular_frequencies(computed_result)) === ComplexF64
    computed_plot = only(track_ui_plots(Makie.plot(
        computed_result;
        backend = :cairo,
        display_plot = false,
        open_export = false
    )))
    @test computed_plot isa UIPlot
    @test length(computed_plot.panels) == 1
    @test length(only(computed_plot.panels).plots) == 2

    ui_components = Base.get_extension(
        PowerImpedance, :PowerImpedanceMakieExt
    ).UIComponents
    default_theme = ui_components._theme(export_mode = true, export_theme = :default)
    publication_theme = ui_components._theme(
        export_mode = true, export_theme = :publication
    )
    @test !haskey(default_theme[:fonts], :regular)
    @test haskey(publication_theme[:fonts], :regular)
    @test haskey(publication_theme[:fonts], :italic)
    @test publication_theme[:Axis][:titlesize][] == 15
    latex_theme = Makie.theme_latexfonts()
    for font in (:regular, :italic, :bold, :bolditalic)
        @test publication_theme[:fonts][font][] == latex_theme[:fonts][font][]
    end

    handle.controls[:xlog].active[] = false
    @test all(panel -> panel.axis.xscale[] === Makie.identity, handle.panels)
    handle.controls[:xlog].active[] = true
    @test all(panel -> panel.axis.xscale[] === Makie.log10, handle.panels)
    handle.controls[:reset].clicks[] += 1
    @test handle.context.status[] == "Axis limits reset"

    legend = handle.controls[:legend]
    entry = first(last(first(legend.entrygroups[])))
    Makie.toggle_visibility!(entry)

    Makie.resize!(handle.figure, 760, 430)
    Makie.update_state_before_display!(handle.figure)
    legend_box = legend.layoutobservables.computedbbox[]
    panel_box = only(handle.panels).axis.layoutobservables.computedbbox[]
    @test legend_box.origin[1] + legend_box.widths[1] <= 760
    @test panel_box.origin[1] + panel_box.widths[1] < legend_box.origin[1]

    contrast_response = cairo_frequency_response()
    contrast_response.response[1, 1, :] .= 1.0e6
    contrast_response.response[2, 2, :] .= 1.0
    contrast = only(track_ui_plots(Makie.plot(
        contrast_response;
        display_plot = false,
        open_export = false
    )))
    contrast_axis = only(contrast.panels).axis
    initial_limits = contrast_axis.finallimits[]
    initial_maximum = initial_limits.origin[2] + initial_limits.widths[2]
    contrast_entry = first(last(first(contrast.controls[:legend].entrygroups[])))
    Makie.toggle_visibility!(contrast_entry)
    Makie.update_state_before_display!(contrast.figure)
    hidden_limits = contrast_axis.finallimits[]
    hidden_maximum = hidden_limits.origin[2] + hidden_limits.widths[2]
    @test hidden_maximum < initial_maximum - 50
    @test contrast.context.status[] == "Axis limits fitted to visible series"
    Makie.toggle_visibility!(contrast_entry)
    @test any(
        plot_object -> !plot_object.visible[],
        Iterators.flatten(panel.plots for panel in handle.panels)
    )
    Makie.toggle_visibility!(entry)

    temporary = mktempdir()
    svg = joinpath(temporary, "publication.svg")
    @test export_svg(handle; path = svg, theme = :publication, open_file = false) == svg
    @test isfile(svg)
    @test filesize(svg) > 100
    svg_text = read(svg, String)
    @test occursin("<svg", svg_text)
    @test occursin("glyph", svg_text)
    @test occursin("rgb(100%, 100%, 100%)", svg_text)
    default_svg = joinpath(temporary, "default.svg")
    @test export_svg(handle; path = default_svg, theme = :default, open_file = false) ==
          default_svg
    @test read(default_svg) != read(svg)
    @test_throws ArgumentError export_svg(
        handle; path = svg, theme = :publication, open_file = false
    )
    @test PowerImpedance.PlotBuilder.BackendHandler.current_backend_symbol() === :cairo

    cd(temporary) do
        first_svg = export_svg(handle; open_file = false)
        second_svg = export_svg(handle; open_file = false)
        @test first_svg != second_svg
        @test isfile(first_svg)
        @test isfile(second_svg)
        @test occursin(
            r"^harmonic_nodal_impedance_\d{8}_\d{6}(?:_\d+)?\.svg$",
            basename(first_svg)
        )
    end

    compact = only(track_ui_plots(Makie.plot(
        cairo_legend_response();
        display_plot = false,
        open_export = false,
        figure_size = (650, 320)
    )))
    compact_legend = compact.controls[:legend]
    compact_panel = only(compact.panels)
    complete_labels = [compact_panel.group_labels[group]
                       for group in compact_panel.group_order
                       if haskey(compact_panel.group_labels, group)]
    compact_labels = legend_labels(compact_legend)
    @test last(compact_labels) == "(...)"
    @test length(compact_labels) < length(complete_labels)
    Makie.toggle_visibility!(first(last(first(compact_legend.entrygroups[]))))
    hidden_state = visibility_state(compact)
    Makie.resize!(compact.figure, 650, 900)
    Makie.update_state_before_display!(compact.figure)
    @test legend_labels(compact_legend) == complete_labels
    @test visibility_state(compact) == hidden_state
    Makie.resize!(compact.figure, 650, 320)
    Makie.update_state_before_display!(compact.figure)
    @test last(legend_labels(compact_legend)) == "(...)"
    @test visibility_state(compact) == hidden_state

    panels = track_ui_plots(PowerImpedance.plot(
        result;
        entries = :all,
        grouping = :panels,
        backend = :cairo,
        display_plot = false,
        controls = false,
        open_export = false
    ))
    panel_plot = only(panels)
    @test length(panel_plot.panels) == 4
    @test isempty(panel_plot.controls)
    Makie.update_state_before_display!(panel_plot.figure)
    panel_boxes = [panel.axis.layoutobservables.computedbbox[]
                   for panel in panel_plot.panels]
    right_edge = maximum(box.origin[1] + box.widths[1] for box in panel_boxes)
    @test right_edge > 0.85panel_plot.page.size[1]
    @test maximum(box.widths[1] for box in panel_boxes) -
          minimum(box.widths[1] for box in panel_boxes) < 1
    @test maximum(box.widths[2] for box in panel_boxes) -
          minimum(box.widths[2] for box in panel_boxes) < 1

    nine_panels = only(track_ui_plots(PowerImpedance.plot(
        cairo_square_response(3);
        entries = :all,
        grouping = :panels,
        backend = :cairo,
        display_plot = false,
        open_export = false
    )))
    @test nine_panels.page.size == (1140, 910)
    @test length(nine_panels.panels) == 9
    @test !haskey(nine_panels.controls, :legend)
    Makie.update_state_before_display!(nine_panels.figure)
    nine_boxes = [panel.axis.layoutobservables.computedbbox[]
                  for panel in nine_panels.panels]
    @test length(unique(round(box.origin[1]; digits = 2) for box in nine_boxes)) == 3
    @test length(unique(round(box.origin[2]; digits = 2) for box in nine_boxes)) == 3
    @test maximum(box.widths[1] for box in nine_boxes) -
          minimum(box.widths[1] for box in nine_boxes) < 1
    @test maximum(box.widths[2] for box in nine_boxes) -
          minimum(box.widths[2] for box in nine_boxes) < 1
end

@testset "CairoMakie completed stability plotting" begin
    loop_gain, admittance = cairo_stability_responses()
    completed = (
        compute(StabilityProblem(loop_gain), GeneralizedNyquist()),
        compute(StabilityProblem(loop_gain), BodeAnalysis()),
        compute(StabilityProblem(admittance), PassivityAnalysis()),
        compute(StabilityProblem((admittance, admittance)), SmallGainAnalysis()),
        compute(
            StabilityProblem(admittance),
            EigenvalueAnalysis(fmin=1.0, fmax=1.0e4, determinant=true),
        ),
        compute(StabilityProblem(loop_gain), UnstableFrequencyAnalysis()),
    )

    for result in completed
        handles = track_ui_plots(PowerImpedance.plot(
            result;
            backend=:cairo,
            display_plot=false,
            controls=false,
            open_export=false,
        ))
        @test handles isa Vector{UIPlot}
        @test !isempty(handles)
        @test all(handle -> !isempty(handle.panels), handles)
    end

    bode_result = completed[2]
    targets = track_ui_plots(PowerImpedance.plot(
        bode_result;
        backend=:cairo,
        display_plot=false,
        controls=false,
        open_export=false,
    ))
    initial_series = sum(
        length(panel.plots) for target in targets for panel in target.panels
    )
    updated = bodeplot(
        loop_gain;
        plots=targets,
        display_plot=false,
        open_export=false,
    )
    @test updated === targets
    @test sum(
        length(panel.plots) for target in targets for panel in target.panels
    ) > initial_series

    siso = FrequencyResponseResult(
        LoopGain(),
        :loopgain,
        loop_gain.response[1:1, 1:1, :],
        loop_gain.frequencies,
        loop_gain.nodes[1:1],
        loop_gain.network_model,
        (;),
    )
    siso_bode = compute(StabilityProblem(siso), BodeAnalysis())
    target = only(track_ui_plots(PowerImpedance.plot(
        siso_bode;
        backend=:cairo,
        display_plot=false,
        controls=false,
        open_export=false,
    )))
    @test bodeplot(
        siso;
        plots=target,
        display_plot=false,
        open_export=false,
    ) === target
end

@testset "CairoMakie UIPlot lifecycle" begin
    handles = copy(TRACKED_UI_PLOTS)
    @test !isempty(handles)
    close_tracked_ui_plots!()
    @test all(isempty(handle.context.observers) for handle in handles)
    @test all(isempty(handle.figure.content) for handle in handles)
    @test all(isempty(handle.figure.scene.plots) for handle in handles)
    @test Makie.current_figure() === nothing
end

GC.gc(true)
yield()
GC.gc(true)
