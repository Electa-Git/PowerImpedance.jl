# Parametric and uncertainty studies

`PowerImpedance.NetworkBuilder` provides an additive parameter layer. The
ordinary package constructors and scalar solver return values are unchanged.
Pass the selectively imported `Grid` function as the first positional argument
to select a lazy constructor, such as `impedance(Grid; ...)`; use `only` to
materialize a singleton specification. Ordinary `impedance(; ...)` remains
scalar. Qualified `NetworkBuilder.impedance(; ...)` shadows remain available
for compatibility, but tutorials do not need a module alias. Grid axes,
connections, study definitions, result types, and the external-response
adapter are safe selective imports; downstream solvers remain ordinary
top-level PowerImpedance functions.

```julia
using PowerImpedance
using PowerImpedance.NetworkBuilder: AbsoluteError, Grid, define,
    sampled_frequency_response

spec = impedance(Grid; z = 5.0, pins = 1)
element = only(spec)
```

## Deterministic Cartesian axes

Only an explicit `Grid` introduces alternatives. Raw vectors, matrices,
ranges, paths, and arbitrary objects passed to a lazy constructor remain one
atomic value. Julia does not dispatch on keyword argument types, so the first
positional `Grid` is the explicit, uniform selector for every component and
configuration constructor.

```julia
sweep = impedance(Grid; z = Grid([1.0, 2.0, 5.0]), pins = 1)
length(sweep) # 3

matrix_spec = impedance(Grid; z = [1.0 0.0; 0.0 2.0], pins = 2)
length(matrix_spec) # 1
```

Nested Gridspaces compose recursively. Cartesian order follows Julia's
`Iterators.product`: the first axis changes fastest. `define`
lifts a named tuple of component Gridspaces into a `Gridspace{NetworkState}`.
Connections remain fixed; component parameters and explicitly gridded options
may vary.

## Explicit study problems

`ParametricProblem` and `UQuantProblem` expose the same calculations through
the common `compute` entry point:

```julia
parameter_problem = ParametricProblem(
    builder_space,
    NodalImpedance(),
    (nets = [:bus], freq_range = (1.0, 1e3, 100)),
)
parameter_result = compute(parameter_problem, Combinatorial())

uq_problem = UQuantProblem(
    uncertain_builder_space,
    LoopGain(),
    (nodelist = [:bus_d, :bus_q], freq_range = (1.0, 1e3, 100)),
)
uq_result = compute(
    uq_problem,
    MonteCarlo(
        trials = 1000,
        distribution = :normal,
        seed = 2026,
        return_samples = true,
    ),
)
```

`Combinatorial` accepts deterministic Gridspace axes and preserves their
Cartesian order. `MonteCarlo` accepts `:normal` and variance-equivalent
`:uniform` primitive draws, fixed local seeds, explicit or DKW-selected trial
counts, and optional retained samples. Each materialized case or numeric trial
uses the same scalar calculation method as the corresponding direct call.

## Uncertainty axes

Load Measurements.jl to activate uncertain iteration and output aggregation.
Relative errors are percentages of nominal magnitude. `AbsoluteError` uses the
same physical unit as the nominal value.

```julia
using Measurements

relative = Grid(10.0, 5.0)                  # 5 percent standard deviation
absolute = Grid(10.0, AbsoluteError(0.5))
measured = impedance(Grid; z = 10.0 ± 0.5, pins = 1)
```

Uncertain `solve` and `determine_impedance` studies enumerate deterministic
cases first, then run independent Monte Carlo trials using ordinary numeric
samples. Measurements values therefore never enter JuMP, component
constructors, or admittance kernels. Supported distributions are `:normal`
and `:uniform`; the uniform interval is chosen to have the requested standard
deviation.

`solve` executes the unchanged scalar power-flow sequence for every sampled
builder. `determine_impedance` also starts with that scalar sequence, then uses
private dispatch to decide whether the next builder has the same operating-point
context. If only passive component parameters changed, it rebuilds those
admittances and reuses the active-device linearization. A change to any active
component, source, connection, or builder option invalidates the cache and
repeats power flow, nonlinear equilibrium, and linearization. This is one Monte
Carlo pass; converter uncertainty does not require a nested sampling loop.

```julia
result = determine_impedance(
    builder_grid;
    nets = [:bus],
    freq_range = (1.0, 1e3, 100),
    trials = 1000,
    distribution = :normal,
    seed = 42,
    return_samples = false,
)
case = only(result)
case.impedance
case.statistics
```

If `trials` is omitted, the study uses the documented Dvoretzky–Kiefer–Wolfowitz
bound from the output cardinality, confidence, and tolerance. When `seed` is
omitted a local master seed is generated without changing Julia's global RNG.
Each deterministic case receives its own reproducible derived seed.

Statistics include mean, sample standard deviation, minimum, 5th percentile,
median, 95th percentile, maximum, and sample count. Complex impedance stores
real and imaginary statistics separately. With `return_samples=true`,
impedance samples have dimensions `(rows, columns, frequencies, trials)`.

Ordinary Gridspace axes are independent. Represent complex uncertainty on
ordinary component fields through uncertain real and imaginary parts; no radial
complex-error convention is used. The LineCableModels interoperability described
on the [Package extensions](package_extensions.md) page additionally preserves
covariance encoded inside one `LineParameters` object. It does not correlate
that object with separate Gridspace axes.

## Result collections

`ParametricImpedance` contains ordered `ImpedanceCase` objects and
`ParametricSolve` contains ordered `SolveCase` objects. Both collections support
`length`, iteration, indexing, and `only`. Every case records coordinates,
trial count, derived seed, distribution, output, statistics, and optional
samples. An uncertain solve aggregates numeric leaves under the power-flow
solution and sets `network` to `nothing`.

## Small-signal frequency responses

The same Gridspace logic extends through nodal admittance construction and
stability analysis. Frequency ranges are specified in hertz; returned `omega`
vectors are angular frequencies in radians per second. The canonical response
layout is `(rows, columns, frequencies)`, and retained numeric samples add a
fourth trial dimension.

The explicit staged API makes the physical partition visible:

```julia
Ynode, node_schema, omega = make_y_node(
    builder_space;
    freq_range = (1.0, 1e3, 400),
    trials = 1000,
    seed = 2026,
)

Yedge, _, _ = make_y_edge(
    builder_space;
    nodelist = node_schema,
    freq_range = (1.0, 1e3, 400),
)

loopgain = inv.(Yedge) .* Ynode
result = nyquistplot(loopgain, omega; zoom = "yes", SM = "GM")
```

`node_schema` stores one ordered node list per deterministic case. Passing it
to `make_y_edge` also inherits the case order, trial count, seed, distribution,
and study identity. The specialized broadcast expression performs one matrix
inverse and matrix product at each frequency and numeric trial. It never
inverts an aggregated mean±standard-deviation matrix.

The fused path performs the node and edge calculations from the same sampled
`NetworkState` and one active-device linearization per trial:

```julia
loopgain, node_schema, omega = make_loopgain(
    builder_space;
    freq_range = (1.0, 1e3, 400),
    trials = 1000,
    seed = 2026,
)

result = nyquistplot(
    builder_space;
    freq_range = (1.0, 1e3, 400),
    trials = 1000,
    seed = 2026,
    zoom = "yes",
    SM = "GM",
)
```

`make_y_node`, `make_y_edge`, and `make_loopgain` return a
`ParametricFrequencyResponse`, a `ParametricNodeSchema`, and the common angular
frequency vector. A response contains ordered `FrequencyResponseCase` values.
Every case records:

- deterministic coordinates, trials, seed, and distribution;
- response kind, ordered nodes, and angular frequencies;
- the deterministic response or aggregated mean±standard deviation;
- standard real/imaginary statistics;
- optional `(n, n, nf, ntrials)` samples;
- a truthful `uncertainty_source`; and
- private frozen provenance for exact replay when samples were not retained.

The possible uncertainty sources are `:deterministic`, `:monte_carlo`,
`:empirical_samples`, and `:measurements_surrogate`. Extracting only an
aggregated `case.response` discards empirical trial dependence. Pass the
complete result collection to later tools so retained samples or frozen replay
provenance remain available.

## Response composition and pairing

Explicit response composition accepts deterministic inputs or uncertain
collections:

```julia
loopgain = make_loopgain(Yedge, Ynode; pairing = :auto)
```

`pairing=:auto` aligns trials only when shared provenance proves that trial
indices describe the same physical samples. Otherwise select a policy:

- `pairing=:aligned` declares that equal trial indices are jointly sampled;
- `pairing=:independent` draws independent left and right trial indices using
  the supplied `seed` and optional `trials` count.

Unrelated deterministic case collections form a Cartesian product. Shared
studies align by deterministic coordinates. Ambiguous uncertain composition is
an error rather than silently imposing a dependence model.

## Exact external Monte Carlo responses

Use `sampled_frequency_response` when another solver or case-study runner has
already produced complete numeric response trials:

```julia
external = sampled_frequency_response(
    samples,
    omega;
    nodes = [:bus_d, :bus_q],
    trial_ids = 1:size(samples, 4),
)
```

Here `samples` has dimensions `(n, n, nf, ntrials)`. One fourth-dimension slice
must contain the whole response from one physical trial—every matrix entry and
every frequency uses the same trial index. A callback form is also available:

```julia
external = sampled_frequency_response(
    (rng, trial_index) -> calculate_one_numeric_response(rng, trial_index),
    omega;
    trials = 1000,
    seed = 2026,
    nodes = [:bus_d, :bus_q],
)
```

Both forms preserve cross-entry and cross-frequency empirical dependence. They
are the clean terminal boundary for exact Monte Carlo data produced outside
PowerImpedance.

## Stability result collections

Parametric overloads are available for `nyquistplot`, `bodeplot`, `small_gain`,
`passivity`, `EVD`, `stabilitymargin`, and `unstable_frequency`. Each returns a
`ParametricStability` containing ordered `StabilityCase` values. A case exposes
`analysis`, tool-specific `output`, `statistics`, optional trial `samples`, and
constructed `plots`. Plots are constructed and displayed by default;
`display_plot=false` suppresses display without discarding plot objects.

For example:

```julia
nyquist = nyquistplot(loopgain; return_samples = true)
case = only(nyquist)

case.output.assessment_probabilities
case.output.encirclements
case.output.margins
case.output.unstable_frequencies
case.statistics.eigenloci
case.samples.metrics
case.plots.nyquist
```

Nyquist and EVD match eigenvalue trajectories within every trial and then
match complete trial loci to a nominal trajectory. Bode phase is unwrapped
within each trial before branch alignment and aggregation. Small-gain binary
inputs obey the explicit pairing policy above. Passivity, margins, and unstable
frequencies are evaluated on numeric trials, never on aggregated matrices.

`check_stability(builder_space, :converter; direction=:ac)` resolves the
selected converter terminals through the network topology, partitions the
device from the remaining network, constructs `Zrest * inv(Zdevice)` per
trial, and runs the common Nyquist analysis. Missing, passive, source,
disconnected, singular, or dimensionally inconsistent selections are rejected
with case and trial diagnostics.
