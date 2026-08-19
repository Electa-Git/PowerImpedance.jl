# PlotBuilder guide

PowerImpedance separates scientific plot descriptions from graphics backends.
`PlotBuilder.make_render` converts a typed result into axes, series, layouts,
controls, legends, and export settings without loading Plots.jl or Makie.
An optional Makie backend converts that description into one [`UIPlot`](@ref)
per page.

The implemented scientific recipe plots the magnitude of a scalar
[`FrequencyResponseResult`](@ref) whose response kind is
`:nodal_impedance`. Stored angular frequencies in rad/s are converted to Hz.
Each selected matrix entry is displayed as

```math
\lvert Z\rvert_{\mathrm{dB}\Omega}
=20\log_{10}\left(\frac{\lvert Z\rvert}{1\;\Omega}\right).
```

## Optional backends

Install the renderer needed by the current environment:

```julia
pkg> add CairoMakie
pkg> add GLMakie
pkg> add WGLMakie
```

CairoMakie produces static output, GLMakie supplies desktop interaction, and
WGLMakie supplies browser-based interaction. Makie and all three backends are
weak dependencies; none is loaded by `using PowerImpedance`.

```julia
using PowerImpedance
using CairoMakie

result = compute(problem, NodalImpedance())
handles = Makie.plot(result; display_plot = false)
handle = only(handles)
```

When `backend` is omitted, the active Makie backend is used. An explicitly
loaded backend can be selected with `backend=:cairo`, `:gl`, or `:wgl`, or by
calling [`set_backend!`](@ref).

## Harmonic-impedance selections

Driving-point entries are overlaid by default:

```julia
Makie.plot(result; entries = :diagonal)
```

The complete matrix can be placed in panels:

```julia
Makie.plot(
    result;
    entries = :all,
    grouping = :panels,
    figure_size = (1100, 780),
)
```

Ordered transfer selections accept integer indices or node names:

```julia
Makie.plot(
    result;
    entries = (:source => :remote, :remote => :source),
    grouping = :pages,
    xscale = :linear,
    title = "Selected transfer impedances",
)
```

`grouping` accepts `:overlay`, `:panels`, and `:pages`. `xscale` accepts
`:log10` and `:linear`. `layout` accepts a built-in layout symbol or a complete
[`PowerImpedance.PlotBuilder.LayoutSpec`](@ref). `export_theme` accepts `:default` and
`:publication`; the latter uses Makie's LaTeX-font theme for native SVG output.
`figure_size=:auto`, the default, increases a faceted page with its row and
column count. A `(width, height)` tuple fixes the page size explicitly.

## Interaction and SVG export

GLMakie and WGLMakie figures provide reset, x-scale, legend-visibility, and
SVG controls. Axis limits are recomputed from visible series. The responsive
legend truncates entries when its allocated space is too small and restores
them after resizing.

[`export_svg`](@ref) exports the current axis scales, limits, and series
visibility through CairoMakie. Exported pages use a white background and
complete legends. Existing paths are never overwritten.

```julia
using CairoMakie

export_svg(
    handle;
    path = "harmonic_impedance.svg",
    theme = :publication,
    open_file = false,
)
```

When `path` is omitted, PlotBuilder creates a collision-free timestamped name.
The toolbar save callback opens the exported SVG with the operating-system
viewer by default. `open_export=false` or `open_file=false` disables that action.

## Backend-neutral descriptions

The render description can be inspected or tested without a graphics package:

```julia
render = PowerImpedance.PlotBuilder.make_render(
    HarmonicImpedancePlotSpec,
    result;
    entries = :all,
    grouping = :panels,
)

page = only(render.figures)
page.views
```

Caller-defined recipes subtype `PlotBuilder.AbstractPlotSpec` and specialize
the grammar accessors associated with accepted inputs, axes, series, grouping,
layouts, controls, and export settings. The common `make_render` sequence
validates and materializes those declarations.

## Plots.jl and Makie qualification

Plots.jl is also optional. Loading it activates the existing Nyquist, Bode,
passivity, small-gain, EVD, and parametric plotting implementations:

```julia
using PowerImpedance
import Plots

result = nyquistplot(loopgain, omega)
combined = Plots.plot(result...)
```

`PowerImpedance.plot` is intentionally not exported. With one graphics library
loaded, its own exported `plot` may be used normally. Loading Plots.jl and a
Makie backend with `using` can produce Julia's ordinary exported-name conflict;
use `Plots.plot`, `Makie.plot`, or `PowerImpedance.plot` explicitly.

## Result accessors

The harmonic-impedance recipe obtains its inputs through:

- [`response_kind`](@ref);
- [`response_values`](@ref);
- [`angular_frequencies`](@ref);
- [`response_nodes`](@ref).

These accessors expose the response semantics without duplicating the fields of
[`FrequencyResponseResult`](@ref).

## Manual GL gallery

The repository includes a two-node resonant-network gallery for visual and
interaction checks. Its isolated environment contains GLMakie and CairoMakie:

```bash
julia --project=integration/plotting -e 'using Pkg; Pkg.instantiate()'
julia --project=integration/plotting integration/plotting/manual_gl.jl
```

The script opens the diagonal overlay and the complete matrix in panels. It
checks resizing, reset, logarithmic x-scale selection, legend visibility, and
Cairo SVG export. The save callback exports with the publication theme and
opens the SVG in the system viewer for comparison with the GL windows. The
terminal prints the artifact directory and remains attached until both GL
windows are closed.
