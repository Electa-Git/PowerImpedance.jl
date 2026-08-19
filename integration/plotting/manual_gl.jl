# Instantiate and run from the repository root:
# julia --project=integration/plotting -e 'using Pkg; Pkg.instantiate()'
# julia --project=integration/plotting integration/plotting/manual_gl.jl

using Test
using PowerImpedance
using GLMakie

const NB = PowerImpedance.NetworkBuilder
const ARTIFACT_DIRECTORY = abspath(get(
    ENV,
    "POWERIMPEDANCE_GL_ARTIFACTS",
    joinpath(@__DIR__, "manual-gl-artifacts")
))
mkpath(ARTIFACT_DIRECTORY)

set_backend!(:gl)

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

network = NB.define(elements, connections)
problem = PowerImpedanceProblem(
    network;
    nodes = [:source, :remote],
    frequency_range = (1.0, 5.0e3, 500)
)
result = compute(problem, NodalImpedance())

diagonal = only(Makie.plot(
    result;
    backend = :gl,
    display_plot = true,
    export_theme = :publication,
    open_export = true,
    title = "Two-node resonant network — driving-point impedances"
))

all_entries = only(Makie.plot(
    result;
    entries = :all,
    grouping = :panels,
    backend = :gl,
    display_plot = true,
    export_theme = :publication,
    open_export = true,
    title = "Two-node resonant network — complete impedance matrix",
    figure_size = (1100, 780)
))

using CairoMakie
set_backend!(:gl)

@testset "Manual GL harmonic-impedance gallery" begin
    @test diagonal isa UIPlot
    @test all_entries isa UIPlot
    @test diagonal.context.window !== nothing
    @test all_entries.context.window !== nothing
    @test length(diagonal.panels) == 1
    @test length(all_entries.panels) == 4
    @test Set(keys(diagonal.controls)) == Set((:reset, :export_svg, :xlog, :legend))
    @test !haskey(all_entries.controls, :legend)

    Makie.resize!(diagonal.figure, 760, 430)
    Makie.resize!(all_entries.figure, 1250, 820)
    diagonal.controls[:xlog].active[] = false
    diagonal.controls[:xlog].active[] = true
    diagonal.controls[:reset].clicks[] += 1

    legend = diagonal.controls[:legend]
    entry = first(last(first(legend.entrygroups[])))
    Makie.toggle_visibility!(entry)
    Makie.toggle_visibility!(entry)

    ui_components = Base.get_extension(
        PowerImpedance, :PowerImpedanceMakieExt
    ).UIComponents
    publication_theme = ui_components._theme(
        export_mode = true,
        export_theme = :publication
    )
    latex_theme = Makie.theme_latexfonts()
    for font in (:regular, :italic, :bold, :bolditalic)
        @test publication_theme[:fonts][font][] == latex_theme[:fonts][font][]
    end

    diagonal.controls[:export_svg].clicks[] += 1
    @test occursin("opened it with the system application", diagonal.context.status[])

    overlay_svg = joinpath(ARTIFACT_DIRECTORY, "harmonic_impedance_overlay.svg")
    panels_svg = joinpath(ARTIFACT_DIRECTORY, "harmonic_impedance_panels.svg")
    ispath(overlay_svg) || export_svg(
        diagonal; path = overlay_svg, theme = :publication, open_file = false
    )
    ispath(panels_svg) || export_svg(
        all_entries; path = panels_svg, theme = :publication, open_file = false
    )
    @test isfile(overlay_svg)
    @test isfile(panels_svg)
    @test PowerImpedance.PlotBuilder.BackendHandler.current_backend_symbol() === :gl
end

println("Manual plotting artifacts: $ARTIFACT_DIRECTORY")
println("The save callback opened a publication-theme SVG in the system viewer.")
println("Inspect the SVG and both GL windows. Resize them, toggle legend entries and x scale, then close both windows.")

while any(plot -> Makie.events(plot.figure).window_open[], (diagonal, all_entries))
    sleep(0.25)
end
