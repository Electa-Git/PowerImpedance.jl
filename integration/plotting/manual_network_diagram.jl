# Instantiate and run from the repository root:
# julia --project=integration/plotting -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
# julia --project=integration/plotting integration/plotting/manual_network_diagram.jl

using PowerImpedance
using PowerImpedance.NetworkBuilder: define
using GraphMakie
using GLMakie
using CairoMakie

# Reuse the authoritative IEEE39 NetworkBuilder fixture without maintaining a
# second copy of the system. Including the example defines the fixture loader;
# its full soil-resistivity study runs only when that file is the entry point.
include(joinpath(pkgdir(PowerImpedance), "examples", "IEEE39bus_Gridspace.jl"))

network = define(
    ieee39bus_elements(),
    ieee39bus_connections();
    options = IEEE39_BUILDER_OPTIONS
)

# CairoMakie is loaded for the toolbar's SVG export path. Reactivate GLMakie
# for the live, resizable inspection window.
set_backend!(:gl)
handles = PowerImpedance.plot(
    network;
    backend = :gl,
    display_plot = true,
    title = "IEEE39 network diagram",
    export_theme = :publication,
    open_export = true
)
view = only(handles)
diagram_view = view.artifacts[:network_diagram]

println("IEEE39 diagram vertices: ", length(diagram_view.model.vertex_keys))
println("IEEE39 diagram incidences: ", length(diagram_view.model.incidences))
println("Controls: ", collect(keys(view.controls)))
println("Resize and pan/zoom the window, select buses and components, reset the view, and export SVG from the toolbar.")

while Makie.events(view.figure).window_open[]
    sleep(0.25)
end
