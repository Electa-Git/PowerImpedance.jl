const PBTest = PowerImpedance.PlotBuilder

struct TestDeclarativePlot <: PBTest.AbstractPlotSpec end
PBTest.dispatch_on(::Type{TestDeclarativePlot}) = Vector{Float64}
PBTest.input_kwargs(::Type{TestDeclarativePlot}) = (:grouping,)
PBTest.input_defaults(::Type{TestDeclarativePlot}, object) = (; grouping = :overlay)
function PBTest.group_facets(
        ::Type{TestDeclarativePlot}, mode::Val, recipe::PBTest.PlotRecipe, page
)
    (:values,)
end
function PBTest.series_data(
        ::Type{TestDeclarativePlot}, ::Val{:x}, recipe::PBTest.PlotRecipe, key
)
    eachindex(recipe.object)
end
function PBTest.series_data(
        ::Type{TestDeclarativePlot}, ::Val{:y}, recipe::PBTest.PlotRecipe, key
)
    recipe.object
end
PBTest.legend_label(
    ::Type{TestDeclarativePlot}, recipe::PBTest.PlotRecipe, key
) = "values"

@testset "Grammar relocation" begin
    @test ProblemDefinition isa DataType
    @test AbstractFormulation isa DataType
    @test AbstractResult isa DataType
    @test isdefined(PowerImpedance, :compute)
    grammar_source = read(joinpath(pkgdir(PowerImpedance), "src", "Grammar.jl"), String)
    problems_source = read(joinpath(pkgdir(PowerImpedance), "src", "Problems.jl"), String)
    @test occursin("abstract type ProblemDefinition end", grammar_source)
    @test !occursin("abstract type ProblemDefinition end", problems_source)
end

@testset "UnitHandler" begin
    UH = PowerImpedance.UnitHandler
    ohms_per_km = UH.units(:base, :ohm; per = (:kilo, :meter))
    @test UH.get_label(ohms_per_km) == "Ω/km"
    @test UH.get_exp(ohms_per_km) == -3
    @test UH.scale_factor(UH.units(:base, :ohm; per = (:base, :meter)), ohms_per_km) ==
          1.0e3
    @test UH.get_label(UH.QuantityTag{:frequency}()) == "Frequency"
    @test UH.get_label(UH.default_unit(UH.QuantityTag{:angular_frequency}())) == "rad/s"
    @test UH.get_label(UH.display_unit(UH.QuantityTag{:impedance_db}())) == "dBΩ"
    @test UH.nominal(2.0) == 2.0
    @test iszero(UH.standard_uncertainty(2.0))
    @test UH.format_value(2.125; digits = 2) == "2.12"
    @test_throws ArgumentError UH.Unit(name = :ohm, prefix = :unsupported)
end

@testset "PlotBuilder grammar" begin
    PB = PowerImpedance.PlotBuilder
    @test PB.FixedTrack(12).value == 12
    @test PB.RelativeTrack().weight == 1
    @test PB.ContentTrack() isa PB.AbstractTrackSize
    @test_throws ArgumentError PB.FixedTrack(-1)
    @test_throws ArgumentError PB.RelativeTrack(0)

    layout = PB.layout_preset(Val(:grid), 4)
    @test PB.validate(layout) === layout
    @test length(layout.grids) == 2
    @test first(layout.grids).columns[1] isa PB.RelativeTrack
    @test first(layout.grids).columns[2] isa PB.ContentTrack
    @test Set(getfield.(layout.slots, :name)) ==
          Set((:toolbar, :canvas, :status, :legend, :colorbars))

    render = PB.make_render(TestDeclarativePlot, [1.0, 2.0])
    @test render isa PB.RenderSpec{TestDeclarativePlot}
    @test only(render.figures).views[1].series[1].ydata == [1.0, 2.0]
    @test_throws ArgumentError PB.make_render(TestDeclarativePlot, [1.0]; bad = true)
    @test_throws ArgumentError PB.make_render(TestDeclarativePlot, 1.0)
end

function _plot_test_result(; kind = :nodal_impedance, values = nothing,
        frequencies = 2π .* [10.0, 100.0, 1_000.0], nodes = [:left, :right])
    response = values === nothing ? Array{ComplexF64}(undef, 2, 2, 3) : values
    if values === nothing
        response[1, 1, :] .= [1, 10, 100]
        response[1, 2, :] .= [2, 20, 200]
        response[2, 1, :] .= [3, 30, 300]
        response[2, 2, :] .= [4, 40, 400]
    end
    return FrequencyResponseResult(kind, response, frequencies, nodes, nothing, nothing)
end

@testset "Harmonic impedance plot recipe" begin
    PB = PowerImpedance.PlotBuilder
    result = _plot_test_result()
    @test response_kind(result) === :nodal_impedance
    @test response_values(result) === result.response
    @test angular_frequencies(result) === result.frequencies
    @test response_nodes(result) === result.nodes

    render = PB.make_render(HarmonicImpedancePlotSpec, result)
    page = only(render.figures)
    @test length(page.views) == 1
    @test length(only(page.views).series) == 2
    @test only(page.views).xaxis.label == "Frequency [Hz]"
    @test only(page.views).yaxis.label == "Impedance magnitude [dBΩ]"
    @test only(page.views).xaxis.scale === :log10
    @test only(page.views).xaxis.allowed_scales == (:linear, :log10)
    @test only(page.views).series[1].xdata ≈ [10.0, 100.0, 1_000.0]
    @test only(page.views).series[1].ydata ≈ [0.0, 20.0, 40.0]
    @test getfield.(only(page.views).series, :label) ==
          ["Z[left, left]", "Z[right, right]"]

    complex_frequency_result = _plot_test_result(
        frequencies = ComplexF64.(2π .* [10.0, 100.0, 1_000.0])
    )
    complex_frequency_render = PB.make_render(
        HarmonicImpedancePlotSpec, complex_frequency_result
    )
    @test only(only(complex_frequency_render.figures).views).series[1].xdata ≈
          [10.0, 100.0, 1_000.0]

    panels = PB.make_render(
        HarmonicImpedancePlotSpec,
        result;
        entries = (:right => :left, 1 => 2),
        grouping = :panels,
        xscale = :linear,
        figure_size = (700, 500)
    )
    @test length(only(panels.figures).views) == 2
    @test only(panels.figures).size == (700, 500)
    @test getfield.(only(panels.figures).views, :title) ==
          ["Z[right, left]", "Z[left, right]"]
    @test all(view -> view.xaxis.scale === :linear, only(panels.figures).views)

    pages = PB.make_render(
        HarmonicImpedancePlotSpec, result; entries = :all, grouping = :pages
    )
    @test length(pages.figures) == 4
    @test all(page -> length(page.views) == 1, pages.figures)
    @test all(page -> page.size == (900, 560), pages.figures)

    automatic_panels = PB.make_render(
        HarmonicImpedancePlotSpec, result; entries = :all, grouping = :panels
    )
    @test only(automatic_panels.figures).size == (900, 640)

    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec, _plot_test_result(kind = :node_admittance)
    )
    @test_throws DimensionMismatch PB.make_render(
        HarmonicImpedancePlotSpec,
        _plot_test_result(values = ones(ComplexF64, 2, 3, 3))
    )
    @test_throws DimensionMismatch PB.make_render(
        HarmonicImpedancePlotSpec,
        _plot_test_result(values = ones(ComplexF64, 2, 2, 2))
    )
    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec,
        _plot_test_result(frequencies = 2π .* [10.0, 10.0, 100.0])
    )
    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec,
        _plot_test_result(frequencies = ComplexF64[2π * 10, 2π * 100 + im, 2π * 1_000])
    )
    @test_throws DomainError PB.make_render(
        HarmonicImpedancePlotSpec,
        _plot_test_result(values = zeros(ComplexF64, 2, 2, 3))
    )
    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec, result; entries = (:left => :left, 1 => 1)
    )
    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec, result; entries = :missing => :left
    )
    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec, result; entries = 3 => 1
    )
    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec, result; grouping = :invalid
    )
    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec, result; xscale = :ln
    )
    @test_throws ArgumentError PB.make_render(
        HarmonicImpedancePlotSpec, result; figure_size = :small
    )
end

@testset "Computed harmonic impedance plot recipe" begin
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
    result = compute(
        PowerImpedanceProblem(
            network;
            nodes = [:source, :remote],
            frequency_range = (1.0, 5.0e3, 15)
        ),
        NodalImpedance()
    )

    @test eltype(angular_frequencies(result)) === ComplexF64
    render = PowerImpedance.PlotBuilder.make_render(HarmonicImpedancePlotSpec, result)
    @test length(only(render.figures).views) == 1
    @test length(only(only(render.figures).views).series) == 2
    @test only(only(render.figures).views).series[1].xdata[begin] ≈ 1.0
    @test only(only(render.figures).views).series[1].xdata[end] ≈ 5.0e3
end

@testset "Plots extension" begin
    @test Base.get_extension(PowerImpedance, :PowerImpedancePlotsExt) !== nothing
    @test PowerImpedance.plot(1:2, [1.0, 2.0]) isa Plots.Plot
end
