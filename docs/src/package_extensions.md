# Package extensions

Optional packages activate focused interoperability or rendering methods. Core
calculations do not load a graphics package.

| Extension | Activated by | Purpose |
|:--|:--|:--|
| `PowerImpedanceMeasurementsExt` | `Measurements` | Direct uncertainty materialization, covariance-preserving first-order results, and numeric trial sampling |
| `PowerImpedanceMakieExt` | `Makie` | PlotBuilder rendering and `plot` methods |
| `PowerImpedanceGraphMakieExt` | `Makie`, `GraphMakie`, `Graphs`, and `NetworkLayout` | Reusable topology and solved-state network diagrams |
| `PowerImpedanceCairoMakieExt` | `Makie` and `CairoMakie` | Static rendering and SVG export |
| `PowerImpedanceGLMakieExt` | `Makie` and `GLMakie` | Interactive desktop rendering |
| `PowerImpedanceWGLMakieExt` | `Makie` and `WGLMakie` | Interactive browser rendering |

The extensions are load-order independent.

## Measurements

```julia
using PowerImpedance
using Measurements
```

Shared Measurement primitives are drawn once per numeric trial, so Gridspace
Monte Carlo preserves covariance within supported containers.
`LinearError` reconstructs Measurements only after its numeric base and
perturbation responses complete.

PowerModels never receives Measurements values. A power-flow study with
Measurements-valued components runs a local Monte Carlo sequence of numeric
network realizations. The
aggregate reconstructs Measurements for solved AC and DC bus fields only.

## LineCableModels

LineCableModels interoperability is temporarily dormant while
LineCableModels.jl awaits registration. The extension source and dedicated tests
are retained for restoration once it can again be declared as a weak dependency.

## Makie backends

Load CairoMakie, GLMakie, or WGLMakie after computing a result:

```julia
using CairoMakie

handles = Makie.plot(result; display_plot = false)
```

See the [PlotBuilder guide](developers/plotbuilder.md) for definitions,
controls, existing Bode targets, and SVG export.
