# Gridspace and Measurements Extension

## Summary

Implement an additive parametric and uncertainty-aware layer under `NetworkBuilder` without changing existing component implementations, constructor methods, or scalar return contracts.

The feature will:

- Introduce `Grid` and `Gridspace` Cartesian parameterization.
- Mirror every supported component constructor as `NetworkBuilder.<same_name>` through new `gs_*.jl` files.
- Convert scalar inputs to singleton deterministic grids while treating raw arrays and vectors as atomic values.
- Run uncertain nonlinear studies through Monte Carlo using ordinary numeric samples, ensuring Measurements values never reach JuMP or component kernels.
- Aggregate impedance and power-flow outputs back into Measurements values.
- Retain every existing test and add complete deterministic, parametric, and uncertainty acceptance coverage.

## Public API and Contracts

`NetworkBuilder` will retain its existing exports and additionally export:

```julia
AbsoluteError
AbsoluteGrid
DeterministicGrid
Grid
Gridspace
RelativeGrid
@gridspace
@relax

ImpedanceCase
ParametricImpedance
SolveCase
ParametricSolve
```

Component shadows will deliberately remain qualified:

```julia
NetworkBuilder.impedance(...)
NetworkBuilder.mmc(...)
NetworkBuilder.tlc(...)
```

They will not be exported because their names conflict with the unchanged parent API.

Key contracts:

- `NetworkBuilder.foo(; scalar_arguments...)` returns a singleton `Gridspace`.
- `only(NetworkBuilder.foo(...))` is equivalent field-for-field to the original `PowerImpedanceACDC.foo(...)`.
- Raw vectors, matrices, ranges, file paths, and other containers are atomic singleton values inside shadow constructors.
- Only an explicit `Grid(...)`, uncertainty grid, or nested `Gridspace` introduces alternatives.
- Existing scalar `solve`, `convert`, and `determine_impedance` methods and return values remain unchanged.
- Gridspace methods return rich case collections:
  - `ParametricImpedance` contains ordered `ImpedanceCase` objects.
  - `ParametricSolve` contains ordered `SolveCase` objects.
  - Both support `length`, iteration, indexing, and `only`.
- Every case records ordered parameter coordinates, trial count, seed, distribution, output, statistics, and optional samples.
- Deterministic impedance cases retain the existing impedance tensor and frequency vector.
- Uncertain impedance tensors contain `Complex{Measurement{Float64}}` values with unchanged matrix-by-matrix-by-frequency dimensions.
- Deterministic solve cases retain the ordinary power-flow result and built network.
- Uncertain solve cases aggregate every numeric leaf under the power-flow solution into Measurements values and set the averaged network to `nothing`.

## Sequential Implementation Checkpoints

### 1. Establish and protect the baseline

- Instantiate the current project and run the unchanged test suite before implementation.
- Record any pre-existing failure separately from feature failures.
- Preserve the existing dirty documentation work and supplied gridspace stubs.
- Verify at each checkpoint that existing component source files and parent constructor method tables have not changed.
- If passing existing tests would require modifying a forbidden original component implementation, stop and report the conflict instead of silently refactoring it.

Audit:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using Pkg; Pkg.test()'
git diff --check
git diff -- src/Network
```

The final command may show only additive `NetworkBuilder` wiring and new `gs_*.jl`, `parametric.jl`, `uquant.jl`, and gridspace files.

### 2. Complete the Grid and Gridspace core

Finish the supplied files under `NetworkBuilder/gridspace/` and wire them into `NetworkBuilder.jl`.

Implement:

- Scalar, tuple, range, vector, array, complex, symbolic, string, and arbitrary-object deterministic grids.
- Stable iteration, `length`, `size`, `eltype`, `IteratorSize`, indexing where meaningful, and RNG-aware `rand`.
- `RelativeGrid`, `AbsoluteGrid`, and `AbsoluteError` validation and sampling.
- Relative errors interpreted as percentages of the nominal magnitude.
- Normal and uniform distributions; uniform bounds use the standard-deviation-equivalent interval.
- Recursive `Gridspace` Cartesian materialization without prematurely constructing typed component objects.
- Stable case ordering matching Julia’s Cartesian-product iteration.
- `recast` support required by `@relax`.
- Macro handling for defaults, parametric structs, supertypes, nested declarations, and stacked macro use.
- Clear extension-required errors when uncertain iteration is attempted without Measurements loaded.

Audit tests:

- Singleton scalar and arbitrary-object grids.
- Atomic versus explicitly expanded collections.
- Heterogeneous and complex deterministic values.
- Nested Gridspace length and iteration order.
- Cardinality and empty-axis behavior.
- Seeded sampling reproducibility.
- Macro expansion and construction tests.
- A custom “Pokémon-like” type proving that deterministic grids impose no numeric restriction.

### 3. Build the complete qualified shadow constructor layer

Create `gs_*.jl` counterparts alongside the existing Network hierarchy and include them only through `NetworkBuilder/parametric.jl`.

The mirrored inventory will cover:

- Sources, impedances, transformers, cables, overhead lines, and black-box elements.
- Induction and synchronous machines.
- MMC and TLC electrical, control, synchronization, modulation, measurement, delay, setpoint, and limit objects.
- All concrete nested configuration constructors used by the public element constructors.
- Modular and checked-in legacy MMC/TLC calling conventions.

Implementation rules:

- Preserve exact constructor names and keyword spelling.
- Normalize every argument to a `Grid`; preserve existing grids and gridspaces.
- Use private keyword-materializer targets so that object construction happens only after a concrete Cartesian case or Monte Carlo sample has been selected.
- Copy or refine logic only inside `gs_*.jl`; do not replace or edit the original implementation.
- Provide an explicit, tested manifest mapping each public concrete constructor to its `NetworkBuilder` shadow or to a documented exclusion such as an abstract type or computational function.

MMC/TLC routing:

- Modular keyword families route to the current modular parent constructors.
- Legacy keyword families route to copied NetworkBuilder adapters.
- Mixed incompatible keyword families throw an actionable error listing the conflicting keywords.
- The TLC legacy adapter will be ported from the existing legacy adapter.
- Legacy MMC behavior will initially be ported conservatively into a private NetworkBuilder-compatible implementation, including required predicates and conversion hooks, unless exact construction through the modular model can be demonstrated by parity tests.

Audit tests for every mirrored constructor:

- Scalar arguments produce a one-case Gridspace.
- The one materialized value matches the corresponding parent object field-for-field.
- Varying one field changes only that field.
- Raw matrices and vectors remain atomic.
- Nested configurations produce the expected Cartesian cardinality.
- Modular and legacy converter signatures have independent parity tests.

### 4. Lift BuilderState into Gridspace

Add orchestration in `parametric.jl` without modifying the existing `BuilderState`, `define`, `update!`, or scalar `solve` implementations.

Implement:

- A more-specific `define` route for named tuples whose element values are Gridspaces.
- Recursive named-tuple materializers that construct ordinary elements before calling the existing scalar `define`.
- A `Gridspace{BuilderState}` whose materialized cases are ordinary scalar `BuilderState` instances.
- Ordered coordinate paths such as `(:elements, :c1, :elec, :L_arm)`.
- Coordinates only for varied or uncertain axes, including uncertainty kind, nominal value, and error.
- Fixed connection topology per BuilderState Gridspace.
- Explicitly gridded physical options may vary; connections themselves are not a parametric axis in this feature.

Add:

```julia
solve(::Gridspace{BuilderState}; ...)
determine_impedance(::Gridspace{BuilderState}; ...)
```

Each deterministic case must delegate to the existing scalar pipeline. Nonlinear cases must therefore continue through the existing operating-point calculation and JuMP solve with ordinary numeric values.

Audit:

- A singleton BuilderState matches scalar `define`, `solve`, conversion, and impedance results.
- Multi-axis BuilderState length, ordering, and coordinate metadata are exact.
- One representative linear and one nonlinear deterministic grid study execute through the existing pipeline.

### 5. Implement the Measurements extension and Monte Carlo boundary

Create the package extension at:

```text
ext/PowerImpedanceMeasurementsExt.jl
```

Correct and supersede the misplaced supplied placeholder only after the real extension exists.

Update package metadata with:

- Measurements as a weak dependency and extension trigger.
- Measurements compatibility version 2.
- Distributions as a direct dependency.
- Random and Statistics as declared standard-library dependencies.
- Measurements in the test target.

The core `uquant.jl` will contain generic planning, statistics, result types, and orchestration without statically referring to Measurements types. The extension will provide:

- Measurement detection and nominal/error extraction.
- Iteration and `eltype` for relative and absolute uncertainty grids.
- Sampling of Measurement leaves into ordinary numbers.
- Reassembly of means and standard deviations into Measurements values.

Monte Carlo behavior:

- First enumerate deterministic Cartesian cases.
- Within each resulting uncertain case, sample all uncertain axes independently.
- Materialize an ordinary BuilderState for each trial.
- Run the complete scalar conversion, power flow, frequency scan, and impedance pipeline.
- Never pass a Measurement into JuMP, PowerModelsACDC, component constructors with concrete numeric fields, or admittance kernels.
- Fail on the first unsuccessful trial and report coordinate path, case index, trial index, and seed.
- Validate identical frequency vectors, tensor dimensions, and power-flow solution schemas across trials.

Supported keywords:

```julia
trials::Union{Nothing,Int} = nothing
distribution::Symbol = :normal
seed = nothing
confidence::Real = 0.95
tolerance::Real = 0.02
return_samples::Bool = false
```

When `trials` is omitted, compute:

```math
n =
\left\lceil
\frac{\log\!\left(2M/(1-c)\right)}
     {2\varepsilon^2}
\right\rceil
```

where \(M\) is twice the number of complex output entries, \(c\) is confidence, and \(\varepsilon\) is tolerance.

Aggregation:

- Compute mean, sample standard deviation, minimum, 5th percentile, median, 95th percentile, maximum, and sample count.
- Store real and imaginary impedance statistics separately.
- Reassemble real and imaginary parts as independent Measurements.
- Default to statistics only.
- With `return_samples=true`, retain impedance samples as `(rows, columns, frequencies, trials)` and solve samples as trial-indexed solution trees.
- Generate and record a local master seed when none is supplied; never mutate the global RNG.
- Derive deterministic per-case seeds from the master seed.
- Detect zero-uncertainty studies and execute the solver once while logically producing the requested trial count and zero variance. This keeps the mandatory 1,000-trial zero-error network acceptance tests tractable.

### 6. Add end-to-end acceptance coverage

Keep the unchanged legacy suite as a blocking test run and add a mirrored constructor matrix plus feature tests.

Required acceptance scenarios:

- Every scalar shadow constructor produces a one-unit `DeterministicGrid` for each argument and a singleton Gridspace for the object.
- Complete constructor coverage is enforced by the explicit manifest.
- Deterministic sweeps produce the Cartesian number of cases in stable order.
- A simple nonzero-uncertainty linear network physically executes 1,000 trials and validates expected mean and standard deviation within statistical tolerance.
- Normal and uniform sampling are covered.
- A fixed seed reproduces results exactly.
- Mixed deterministic and uncertain axes enumerate outer deterministic cases and perform independent Monte Carlo within each.
- DKW trial calculation, statistics, optional sample dimensions, and failure diagnostics are tested.
- Loading Measurements before or after PowerImpedanceACDC activates the extension.
- Without Measurements loaded, deterministic Gridspace behavior works and uncertainty use produces an extension hint.
- Every mirrored component/configuration test is repeated with zero-standard-deviation Measurements and `trials=1000`; results equal the deterministic case and output uncertainty is zero.
- Gridspaced IEEE39bus and P2P_HVDC_ALT fixtures cover the full topology and nonlinear path using a reduced frequency count.
- Their zero-uncertainty results match deterministic results, including impedance shape, frequencies, power-flow solution leaves, and nominal values.
- Scalar legacy tests continue to pass unchanged.

Blocking verification:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=. test/runtests.jl
julia --project=. test/run_extension_tests.jl
git diff --check
```

### 7. Add documentation and advisory quality tooling

- Document Grid, Gridspace, qualified shadows, Cartesian sweeps, result objects, Monte Carlo behavior, reproducibility, and unsupported correlation.
- Include a Literate end-to-end example covering deterministic and uncertain impedance studies.
- Add the new API types and macros to Documenter.
- Record the feature under an `Unreleased` changelog entry.
- Add `.JuliaFormatter.toml` with `style = "sciml"`.
- Add TestItems/TestItemRunner integration while retaining the ordinary test entry point.
- Add Aqua and formatting checks as advisory jobs or explicitly excluded advisory test items; they must not fail the functional pipeline yet.
- Add a tracked `.githooks/commit-msg` hook that recognizes Conventional Commit subjects, warns on violations, and always exits successfully. Document enabling it with `git config core.hooksPath .githooks`.
- Build documentation and run advisory checks, recording warnings separately from blocking acceptance failures.

## Assumptions and Explicit Limits

- Uncertainty axes are statistically independent; covariance and correlated Measurements are explicitly unsupported in this feature.
- Deterministic complex numbers are fully supported.
- Complex uncertainty is expressed through independent uncertain real and imaginary components, such as `Complex{Measurement}`; no radial complex-error interpretation is introduced.
- Relative errors are percentages; absolute errors use the physical unit of the nominal value.
- The default uncertainty distribution is normal; uniform is the only additional initial distribution.
- Feature acceptance tests explicitly request `trials=1000`; adaptive DKW sizing is tested separately.
- Full-network feature tests use the complete example topologies with a reduced frequency grid, while existing scalar tests retain their current ranges.
- Mechanical QA checks remain informative and nonblocking. Functional, parity, extension, and existing regression tests are blocking.
