```@meta
CurrentModule = PowerImpedance
```

# Impedance and stability analysis

Power-flow, frequency-response, and stability calculations return numerical result objects.
Plotting uses those completed results.

## Primitive calculations

```julia
problem = PowerImpedanceProblem(
    network;
    nodes = [:bus],
    eliminated_elements = Symbol[],
    frequency_range = (1.0, 5e3, 400),
)

impedance = compute(problem, NodalImpedance())
node_admittance = compute(problem, NodeAdmittance())
edge_admittance = compute(problem, EdgeAdmittance())
loop_gain = compute(problem, LoopGain())
```

Each call returns a `FrequencyResponseResult` with the formulation, response
kind, `n × n × nf` tensor, angular frequencies, ordered nodes, network model,
and diagnostics. Constructing a problem from an existing `NetworkModel` skips
power flow and linearization.

Power-flow and linearization checkpoints are explicit:

```julia
power_flow = compute(PowerFlowProblem(network), ACDCPowerFlow())
linearized = compute(
    LinearizationProblem(network, power_flow),
    AdmittanceLinearization(),
)
```

`power_flow` is a `PowerFlowResult`. Its `operating_point` holds per-port values
such as `point[:c1].ac.p` and `point[:c1].dc.v`. Port powers are positive into
the component. `solve(state)` returns the same result type. Explicit power-flow
requests always solve, including networks of only sources and passives.
Linearization alone can skip power flow for an entirely linear network.

The state retains converged power-flow starting values for repeated solves.
Calculated operating points remain in the result objects.

## Stability calculations

Wrap a completed frequency response in `StabilityProblem`:

```julia
nyquist = compute(StabilityProblem(loop_gain), GeneralizedNyquist())
bode = compute(StabilityProblem(loop_gain), BodeAnalysis())
passive = compute(StabilityProblem(node_admittance), PassivityAnalysis())
modes = compute(
    StabilityProblem(node_admittance),
    EigenvalueAnalysis(fmin = 1.0, fmax = 5e3, determinant = true),
)
detected = compute(
    StabilityProblem(loop_gain),
    UnstableFrequencyAnalysis(),
)
```

Small-gain analysis accepts an explicit pair of completed responses:

```julia
gain = compute(
    StabilityProblem((first_response, second_response)),
    SmallGainAnalysis(),
)
```

Every call returns `StabilityResult(formulation, analysis, output,
diagnostics)`. The `output` field contains the complete numerical payload used
by its plot definition.

## Plot completed results

Load one Makie backend after the calculations finish:

```julia
using CairoMakie

handles = PowerImpedance.plot(nyquist; display_plot = false)
```

`PowerImpedance.plot` and `Makie.plot` select the definition from
`FrequencyResponseResult.kind` or `StabilityResult.analysis`. The compatibility
functions `nyquistplot`, `bodeplot`, `passivity`, `small_gain`, `EVD`,
`unstable_frequency`, and `check_stability` also complete the required
calculation before invoking PlotBuilder. See the [PlotBuilder guide](developers/plotbuilder.md).

## Composite results

`ParametricResult`, `LinearErrorResult`, and `MonteCarloResult` retain aligned
configuration data and execution metadata. Stability plotting consumes their
completed values or retained `details.plot_data` trajectories.
