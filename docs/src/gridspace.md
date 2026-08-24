```@meta
CurrentModule = PowerImpedance
```

# Parametric and uncertainty studies

`PowerImpedance.Grammar` defines the Gridspace API, composite formulations, and
composite results. The package root and `NetworkBuilder` re-export the same
objects.

## Construct a space

Only an explicit `Grid` introduces alternatives. Arrays passed as ordinary
component arguments stay atomic.

```julia
using PowerImpedance
using PowerImpedance.NetworkBuilder: define

elements = (
    branch = impedance(
        Grid;
        z = Grid([1.0, 2.0]),
        pins = 1,
    ),
)
connections = (
    (node = :bus, element = :branch, side = 1, terminal = 1),
    (node = :gnd, element = :branch, side = 2, terminal = 1),
)
networks = define(elements, connections)
```

Gridspaces support `combine=:product` and `combine=:zip`. Zip composition
broadcasts singleton axes. Reusing one Grid object couples its selections;
`key=:name` couples distinct Grid objects by name. Nested spaces retain their
structure and `configuration_manifest` preserves parameter order.

## Deterministic evaluation

Lift the network space to a space of owned problems, then select the scalar
formulation with `Combinatorial`:

```julia
problems = PowerImpedanceProblem(
    networks;
    nodes = [:bus],
    frequency_range = (1.0, 1e3, 200),
)

result = compute(
    ParametricProblem(problems),
    Combinatorial(NodalImpedance()),
)
```

`ParametricResult.values` and `ParametricResult.space` are aligned. Failed
configurations are recorded under `details.failures` when
`failure_policy=:record` is selected.

## First-order propagation

`LinearError` is available for validated frequency-response paths. Component
parameters are materialized as numeric base and perturbation networks before
any PowerModels call. Measurements values are reconstructed only after the
numeric frequency responses are complete.

```julia
using Measurements

uncertain = Grid(10.0, 5.0)
result = compute(
    ParametricProblem(uncertain_problems),
    LinearError(NodalImpedance()),
)
```

The return value is a `LinearErrorResult{<:FrequencyResponseResult}`. Shared
Grid keys share one latent variable, including when the coupled parameters
have different nominal values or standard uncertainties.

## Monte Carlo evaluation

`MonteCarlo` samples one complete numeric realization per trial:

```julia
result = compute(
    ParametricProblem(uncertain_problems),
    MonteCarlo(
        NodalImpedance();
        trials = 1000,
        distribution = :normal,
        seed = 2026,
        return_samples = false,
    ),
)
```

Normal and variance-equivalent uniform sampling are supported. Plot trajectories
remain available under `details.plot_data` even when raw problem
and response samples are omitted. Set `return_samples=true` to retain the raw
values used by `EmpiricalSamples`.

Power flow uses the same local Monte Carlo boundary. Every PowerModels solve
receives a plain numeric network realization. When Measurements is loaded, the
aggregate reconstructs Measurements only for solved AC and DC bus fields under
`stats.groups[*].bus_measurements`. It never passes a nominal surrogate of the
network to the solver.

## Completed checkpoints

Use `preprocess` to create the next owned problem from a completed response:

```julia
bode_problems = preprocess(result, BodeAnalysis())
bode = compute(bode_problems, MonteCarlo(BodeAnalysis(); seed = 2026))
```

No implicit averaging, flattening, or passthrough conversion is provided.
`primitives` exposes only explicit projections such as `LineParametersInput`,
`EmpiricalSamples`, and `MeasurementsSurrogate`.
