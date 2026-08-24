@testset "Stability PlotBuilder definitions" begin
    frequencies = 2pi .* [1.0, 3.0, 10.0, 30.0]
    response = reshape(ComplexF64[
        0.2 + 0.1im,
        0.3 + 0.2im,
        0.4 + 0.1im,
        0.2 - 0.1im,
    ], 1, 1, :)
    loop = FrequencyResponseResult(
        LoopGain(),
        :loopgain,
        response,
        frequencies,
        [:port],
        nothing,
        (;),
    )
    admittance = FrequencyResponseResult(
        NodeAdmittance(),
        :node_admittance,
        response,
        frequencies,
        [:port],
        nothing,
        (;),
    )

    completed = Dict(
        NyquistPlotDefinition => compute(StabilityProblem(loop), GeneralizedNyquist()),
        BodePlotDefinition => compute(StabilityProblem(loop), BodeAnalysis()),
        PassivityPlotDefinition => compute(StabilityProblem(admittance), PassivityAnalysis()),
        SmallGainPlotDefinition => compute(
            StabilityProblem((admittance, admittance)),
            SmallGainAnalysis(),
        ),
        EigenvaluePlotDefinition => compute(
            StabilityProblem(admittance),
            EigenvalueAnalysis(fmin=1.0, fmax=30.0, determinant=true),
        ),
        UnstableFrequencyPlotDefinition => compute(
            StabilityProblem(loop),
            UnstableFrequencyAnalysis(order_maxima=1),
        ),
    )

    for (definition, result) in completed
        render = PlotBuilder.make_render(definition, result)
        @test render isa PlotBuilder.RenderDefinition{definition}
        @test !isempty(render.figures)
        @test all(page -> !isempty(page.views), render.figures)
        @test all(view -> !isempty(view.series), Iterators.flatten(
            getproperty.(render.figures, :views),
        ))
    end

    nyquist = PlotBuilder.make_render(
        NyquistPlotDefinition,
        completed[NyquistPlotDefinition],
    )
    nyquist_kinds = getfield.(only(nyquist.figures).views[1].series, :kind)
    @test :vline in nyquist_kinds
    @test :band in nyquist_kinds
    @test :scatter in nyquist_kinds

    bode = PlotBuilder.make_render(BodePlotDefinition, completed[BodePlotDefinition])
    @test length(bode.figures) == 1
    @test length(only(bode.figures).views) == 2
    @test all(view -> view.xaxis.scale === :log10, only(bode.figures).views)

    passivity_render = PlotBuilder.make_render(
        PassivityPlotDefinition,
        completed[PassivityPlotDefinition],
    )
    @test :hline in getfield.(only(passivity_render.figures).views[1].series, :kind)

    eigenvalue = PlotBuilder.make_render(
        EigenvaluePlotDefinition,
        completed[EigenvaluePlotDefinition];
        determinant=true,
    )
    @test length(eigenvalue.figures) == 2
    @test all(axis -> axis.scale === :log10,
        (last(eigenvalue.figures).views[1].xaxis, last(eigenvalue.figures).views[1].yaxis))

    trials = [completed[BodePlotDefinition], completed[BodePlotDefinition]]
    aggregate = MonteCarloResult{StabilityResult}(
        MonteCarlo(BodeAnalysis(); trials=2, seed=7),
        (n=2, groups=Any[]),
        [(trial=1,), (trial=2,)],
        (
            plot_data=(values=[trials],),
            failures=(items=Any[],),
        ),
    )
    aggregate_render = PlotBuilder.make_render(BodePlotDefinition, aggregate)
    @test all(view -> :band in getfield.(view.series, :kind),
        only(aggregate_render.figures).views)
end

@testset "PlotBuilder Definition nomenclature" begin
    definitions = (
        :AbstractPlotDefinition,
        :GridDefinition,
        :SlotDefinition,
        :LayoutDefinition,
        :PlacementDefinition,
        :ControlDefinition,
        :LegendDefinition,
        :ColorbarDefinition,
        :StatusDefinition,
        :ExportDefinition,
        :AxisDefinition,
        :SeriesDefinition,
        :ViewDefinition,
        :PageDefinition,
        :RenderDefinition,
        :layout_definition,
        :control_definition,
        :legend_definition,
        :colorbar_definitions,
        :status_definition,
        :export_definition,
    )
    @test all(name -> isdefined(PlotBuilder, name), definitions)
    @test fieldnames(PlotBuilder.RenderDefinition) == (:definition, :figures)
    @test :export_definition in fieldnames(PlotBuilder.PageDefinition)
end
