# Package extensions

Optional packages activate focused interoperability or rendering methods. Core
calculations do not load a graphics package.

| Extension | Activated by | Purpose |
|:--|:--|:--|
| `PowerImpedanceMeasurementsExt` | `Measurements` | Direct uncertainty materialization, covariance-preserving first-order results, and numeric trial sampling |
| `PowerImpedanceLineCableModelsExt` | `LineCableModels` | Deterministic phase-domain `LineParameters` interoperability |
| `PowerImpedanceLineCableModelsMeasurementsExt` | `LineCableModels` and `Measurements` | Joint sampling of Measurements-valued line parameters |
| `PowerImpedanceMakieExt` | `Makie` | PlotBuilder rendering and `plot` methods |
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

Deterministic `LineParameters` can be passed directly to `overhead_line` or
`cable`:

```julia
using LineCableModels
using PowerImpedance

line = cable(parameters; length = 25e3)
```

The deterministic extension validates the phase domain, conductor count,
frequency order, transformation, and extrapolation policy. It also provides the
explicit `LineParametersInput` projection.

Loading Measurements as well activates joint sampling of Measurements-valued
`Z` and `Y` arrays. One trial preserves their shared primitive identities and
constructs a plain numeric `LineParameters` object before line evaluation.

## Makie backends

Load CairoMakie, GLMakie, or WGLMakie after computing a result:

```julia
using CairoMakie

handles = Makie.plot(result; display_plot = false)
```

See the [PlotBuilder guide](developers/plotbuilder.md) for definitions,
controls, existing Bode targets, and SVG export.
