# Parametric and uncertainty studies

`PowerImpedanceACDC.NetworkBuilder` provides an additive parameter layer. The
ordinary package constructors and scalar solver return values are unchanged.
Qualified shadow constructors, such as `NetworkBuilder.impedance`, return a
lazy `Gridspace`; use `only` to materialize a singleton specification.

```julia
using PowerImpedanceACDC
const NB = PowerImpedanceACDC.NetworkBuilder

spec = NB.impedance(z = 5.0, pins = 1)
element = only(spec)
```

## Deterministic Cartesian axes

Only an explicit `Grid` introduces alternatives. Raw vectors, matrices,
ranges, paths, and arbitrary objects passed to a shadow constructor remain one
atomic value.

```julia
sweep = NB.impedance(z = NB.Grid([1.0, 2.0, 5.0]), pins = 1)
length(sweep) # 3

matrix_spec = NB.impedance(z = [1.0 0.0; 0.0 2.0], pins = 2)
length(matrix_spec) # 1
```

Nested Gridspaces compose recursively. Cartesian order follows Julia's
`Iterators.product`: the first axis changes fastest. `NetworkBuilder.define`
lifts a named tuple of component Gridspaces into a `Gridspace{BuilderState}`.
Connections remain fixed; component parameters and explicitly gridded options
may vary.

## Uncertainty axes

Load Measurements.jl to activate uncertain iteration and output aggregation.
Relative errors are percentages of nominal magnitude. `AbsoluteError` uses the
same physical unit as the nominal value.

```julia
using Measurements

relative = NB.Grid(10.0, 5.0)                  # 5 percent standard deviation
absolute = NB.Grid(10.0, NB.AbsoluteError(0.5))
measured = NB.impedance(z = 10.0 ± 0.5, pins = 1)
```

Uncertain `solve` and `determine_impedance` studies enumerate deterministic
cases first, then run independent Monte Carlo trials using ordinary numeric
samples. Measurements values therefore never enter JuMP, component
constructors, or admittance kernels. Supported distributions are `:normal`
and `:uniform`; the uniform interval is chosen to have the requested standard
deviation.

`solve` executes the unchanged scalar power-flow pipeline for every sampled
builder. `determine_impedance` also starts with that scalar pipeline, then uses
private dispatch to decide whether the next builder has the same operating-point
context. If only passive component parameters changed, it rebuilds those
admittances and reuses the active-device linearization. A change to any active
component, source, connection, or builder option invalidates the cache and
repeats power flow, nonlinear equilibrium, and linearization. This is one Monte
Carlo pass; converter uncertainty does not require a nested sampling loop.

```julia
result = NB.determine_impedance(
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
