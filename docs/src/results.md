```@meta
CurrentModule = PowerImpedance
```

# Impedance and stability analysis

Start from a defined network. When nonlinear models need an operating point,
solve and linearize the network first. Then calculate a frequency response,
inspect its result, and choose a stability analysis or plot.

## Calculate a frequency response

`PowerImpedanceProblem` selects the network nodes, optional eliminated
elements, and frequency range. The range is `(minimum, maximum, count)` in Hz.
Use `NodalImpedance` for a driving-point or transfer impedance, `NodeAdmittance`
for nodal admittance, `EdgeAdmittance` for branch admittance, or `LoopGain` for
the generalized loop-gain response.

```julia
problem = PowerImpedanceProblem(
    linearized.network_model;
    nodes = [:pccd, :pccq],
    frequency_range = (1.0, 1000.0, 300),
)

impedance = compute(problem, NodalImpedance())
loop_gain = compute(problem, LoopGain())
```

The [Getting started tutorial](examples/Getting_started_SMIB.md) calculates
and plots both responses for a machine connected to an infinite bus.

## Inspect and analyze results

Frequency-response calculations return `FrequencyResponseResult`. Its
`formulation`, `kind`, `response`, `frequencies`, and `nodes` describe the
calculation and ordered numerical output. `response` is a three-dimensional
tensor indexed by output node, input node, and frequency. Frequencies are
stored as angular frequencies in rad/s.

Wrap a completed result in `StabilityProblem` to run a stability analysis:

```julia
nyquist = compute(StabilityProblem(loop_gain), GeneralizedNyquist())
bode = compute(StabilityProblem(loop_gain), BodeAnalysis())
passive = compute(StabilityProblem(node_admittance), PassivityAnalysis())
modes = compute(
    StabilityProblem(node_admittance),
    EigenvalueAnalysis(fmin = 1.0, fmax = 1000.0),
)
```

`SmallGainAnalysis` takes an explicit pair of completed responses.
`StabilityResult` stores the selected analysis and its numerical output. Use
the returned values to identify the response features that matter for the
study. A plot does not replace interpretation of the selected nodes,
formulation, and model assumptions.

## Plot completed results

Load a Makie backend after the calculations, then pass the completed result to
`PowerImpedance.plot`:

```julia
using CairoMakie

impedance_plot = only(PowerImpedance.plot(impedance; display_plot = false))
nyquist_plot = only(PowerImpedance.plot(nyquist; display_plot = false))
impedance_plot.figure
nyquist_plot.figure
```

Other result types select their plot definition from the result metadata. The
plotting layer supports display and SVG export. See the
[Package extensions](package_extensions.md) guide for Makie backend setup. The
[PlotBuilder guide](developers/plotbuilder.md) documents custom plot
definitions.

## Parametric and composite results

Gridspace calculations keep results aligned with their configurations.
`ParametricResult`, `LinearErrorResult`, and `MonteCarloResult` store the
configuration and execution metadata for those workflows. Use the dedicated
[Gridspace guide](gridspace.md) to choose and run a study. Consult the
[API reference](reference.md) for complete result fields and signatures.
