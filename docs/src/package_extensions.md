# Package extensions

PowerImpedanceACDC keeps optional uncertainty packages outside its base
dependency set. Loading an optional package activates the corresponding Julia
package extension without replacing the ordinary component constructors or
scalar solvers.

Two extensions are currently provided:

| Extension | Activated by | Purpose |
|:--|:--|:--|
| `PowerImpedanceMeasurementsExt` | `Measurements` | Measurements-valued axes, converter-safe Monte Carlo studies, covariance-aware response surrogates, and small-signal analysis |
| `PowerImpedanceLineCableModelsExt` | `LineCableModels` and `Measurements` | Native and `NetworkBuilder` lines constructed directly from phase-domain `LineParameters` |

The extensions are load-order independent. A typical session starts with:

```julia
using PowerImpedanceACDC
using Measurements
using LineCableModels
using PowerImpedanceACDC.NetworkBuilder: AbsoluteError, Grid, define, pin,
    sampled_frequency_response, solve, ⟷
```

`Measurements` and `LineCableModels` must be installed in the active Julia
environment. LineCableModels currently requires Julia 1.12. Loading
LineCableModels is unnecessary for studies that only use ordinary
PowerImpedanceACDC component parameters.

The clean workflow depends on what information must be retained:

| Study | Recommended path |
|:--|:--|
| Deterministic component sensitivity | Put explicit alternatives in `Grid`, build once with `define`, and call `solve` or `determine_impedance` |
| Uncertain converter, source, or passive parameters | Use `Measurement` values or uncertain `Grid` axes and let one Gridspace Monte Carlo run sample the complete builder |
| Deterministic line model calculated by LCM | Pass the resulting `LineParameters` directly to `overhead_line` or `cable` |
| LCM line uncertainty represented by joint first-order moments | Pass a covariance-preserving `LineParameters` to `overhead_line(Grid, lp; ...)` or `cable(Grid, lp; ...)` |
| Exact empirical LCM joint distribution | Retain complete LCM trial tensors, evaluate each complete physical trial through PowerImpedanceACDC, and wrap the resulting response tensor with `sampled_frequency_response` |

See [Parametric and uncertainty studies](gridspace.md) for the basic Gridspace
construction rules.

## Measurements and Gridspace

### Enabling the extension

Loading Measurements activates uncertain-grid iteration, sampling of
`Measurement` values, and aggregation of numeric solver outputs:

```julia
using PowerImpedanceACDC
using Measurements
using PowerImpedanceACDC.NetworkBuilder: AbsoluteError, Grid, define, pin,
    sampled_frequency_response, solve, ⟷
```

Keyword-only component calls remain scalar constructors. Passing `Grid` as the
first positional argument selects the additive lazy constructor through Julia
dispatch:

```julia
scalar_element = impedance(z = 10.0, pins = 1)
element_space = impedance(Grid; z = 10.0, pins = 1)

materialized_element = only(element_space)
```

### Parameter entry points

`Grid` is the only marker that expands a value into an axis. A raw vector,
matrix, range, or configuration object remains one atomic constructor argument.

```julia
# Three deterministic alternatives.
length_axis = Grid([50e3, 75e3, 100e3])

# A 5 percent relative standard deviation around one nominal value.
relative_axis = Grid(100.0, 5.0)

# An absolute standard deviation of 0.5 in the parameter's physical unit.
absolute_axis = Grid(10.0, AbsoluteError(0.5))

# Measurements.jl values can also be placed directly in component fields.
measured_value = 10.0 ± 0.5
```

The complete public construction path is:

1. `Grid(values)` introduces deterministic alternatives.
2. `Grid(nominals, relative_errors)` introduces relative standard
   deviations in percent.
3. `Grid(nominals, AbsoluteError(errors))` introduces absolute standard
   deviations.
4. `component(Grid; kwargs...)` creates `Gridspace` objects; the qualified
   `NetworkBuilder.component(; kwargs...)` spelling remains compatible.
5. `define(elements, connections; options)` composes them into a
   `Gridspace{BuilderState}`.
6. `solve` and `determine_impedance` execute the deterministic cases and
   any trials belonging to each case.

Multiple grid axes form a Cartesian product. For example,
`Grid([10.0, 20.0], [5.0, 10.0])` describes four uncertain cases: every
nominal value paired with every relative standard deviation. Use separate
studies when the values are intended to be paired rather than crossed.

### Deterministic sensitivity analysis

The network is declared once. The affected constructor fields show explicitly
which quantities vary:

```julia
elements = (
    branch = impedance(Grid;
        z = Grid([8.0, 10.0, 12.0]),
        pins = 1,
    ),
    shunt = impedance(Grid; z = 20.0, pins = 1),
)

connections = (
    pin(:branch, 1, 1) ⟷ pin(:shunt, 1, 1) ⟷ :bus,
    pin(:branch, 2, 1) ⟷ pin(:shunt, 2, 1) ⟷ :gnd,
)

builders = define(elements, connections)

sensitivity = determine_impedance(
    builders;
    nets = [:bus],
    freq_range = (1.0, 1e3, 100),
)
```

This is deterministic enumeration, not Monte Carlo. Each result case has one
trial, and its `coordinates` identify the value used on the varied field.

### Uncertainty quantification

Uncertainty is declared on the affected fields and sampled before ordinary
elements are materialized:

```julia
uncertain_elements = merge(
    elements,
    (branch = impedance(Grid; z = 10.0 ± 0.5, pins = 1),),
)

uncertain_builders = define(uncertain_elements, connections)

uq = determine_impedance(
    uncertain_builders;
    nets = [:bus],
    freq_range = (1.0, 1e3, 100),
    trials = 1000,
    distribution = :normal,
    seed = 2026,
    return_samples = true,
)
```

Supported primitive laws are:

- `distribution=:normal`: `Normal(nominal, standard_deviation)`;
- `distribution=:uniform`: a uniform interval
  `nominal ± √3 standard_deviation`, which has the requested variance.

If `trials` is omitted, the number of trials is selected from the output
cardinality, `confidence`, and `tolerance` using the Dvoretzky–Kiefer–Wolfowitz
bound. Set `trials` explicitly when comparing studies at a fixed computational
budget. A fixed `seed` makes each deterministic case reproducible without
changing Julia's global random-number generator.

Ordinary Gridspace axes are independent. Measurements placed in ordinary
component fields are sampled leaf by leaf; shared Measurements tags across
different ordinary fields are not a general correlation interface. Put
correlated primitives behind one purpose-built object with specialized
sampling dispatch, as the LineParameters extension does.

### Power flow and nonlinear components

`solve(builder_space; ...)` runs the unchanged scalar solve pipeline for
every physical sample. Each sampled converter or other nonlinear component
therefore reaches the power-flow and nonlinear-equilibrium solvers as an
ordinary numeric object.

`determine_impedance(builder_space; ...)` performs the same safe sampling in
one Monte Carlo loop. It caches an active-device linearization only while the
operating-point context is unchanged:

- changing only passive parameters rebuilds the passive admittances and reuses
  the active-device operating point;
- changing a converter, another active element, a source, topology, or builder
  option invalidates the cache and repeats power flow, nonlinear equilibrium,
  and linearization.

Consequently, uncertain converters do not require an outer Monte Carlo wrapper
around `determine_impedance`. Their samples belong in the same builder
Gridspace as the passive uncertainties. Power-flow values and steady-state
setpoints are reused only for samples whose operating-point context has not
changed.

### Results and retained samples

`determine_impedance` returns a `ParametricImpedance`, an ordered collection
of `ImpedanceCase` values. `solve` similarly returns a `ParametricSolve` of
`SolveCase` values. Both collections support iteration, integer indexing,
`length`, and `only`.

```julia
case = only(uq)

case.coordinates   # varied paths and their deterministic/uncertain metadata
case.trials        # actual trial count
case.seed          # case-specific derived seed
case.distribution  # :normal or :uniform
case.output        # (impedance=..., frequencies=...)
case.impedance     # mean ± sample standard deviation
case.frequencies
case.statistics
case.samples       # retained only when return_samples=true
```

For impedance studies, `case.statistics.real` and
`case.statistics.imag` have the same dimensions as `case.impedance`. Each leaf
contains `mean`, `std`, `min`, `q05`, `median`, `q95`, `max`, and `n`. Retained
impedance samples have dimensions
`(rows, columns, frequencies, trials)`.
For a deterministic case, `statistics` and `samples` are `nothing`.

A `SolveCase` provides `powerflow`, `network`, `statistics`, and `samples` in
place of the impedance-specific fields; `output` bundles `powerflow` and
`network`. Its retained samples are a vector of the per-trial power-flow result
trees. For an uncertain solve, `network` is `nothing` because there is no single
physical network representing every trial; deterministic cases retain their
network.

### Standalone uncertain frequency responses

Loading Measurements also adds direct uncertainty-aware stability entry points
for three-dimensional matrix responses whose entries contain `Measurement`
values:

```julia
result = nyquistplot(
    uncertain_loopgain,
    omega;
    trials = 1000,
    distribution = :normal,
    seed = 2026,
)
```

Shared Measurements primitive tags are collected across the complete response.
Each primitive is drawn once per trial, and signed derivatives reconstruct all
real and imaginary entries at all frequencies from the same draw. The same
joint reconstruction is used across both operands of a standalone uncertain
`small_gain` call. Normal sampling uses standard-normal primitive draws;
uniform sampling uses variance-equivalent draws on `[-√3, √3]`.

These overloads are explicitly labeled `:measurements_surrogate`. They preserve
the encoded first-order means, variances, and signed covariance, but they do
not recover a nonlinear empirical distribution whose complete trials were
discarded during earlier aggregation. The call emits a warning for that
reason. Prefer complete Gridspace results or exact empirical response slices
when they are available.

Exact external response data uses a different entry point:

```julia
response = sampled_frequency_response(
    samples,
    omega;
    nodes = [:bus_d, :bus_q],
    trial_ids = 1:size(samples, 4),
)
```

`samples` must have dimensions `(nodes, nodes, frequencies, trials)`. One trial
slice is one indivisible realization. The resulting uncertainty source is
`:empirical_samples`, and every stability tool consumes those exact slices.
A callback overload accepts `(rng, trial_index)` and returns one ordinary
numeric response, which is useful when trial responses are generated lazily.

## LineCableModels `LineParameters`

### Enabling the extension

The line extension activates after PowerImpedanceACDC, LineCableModels, and
Measurements have all been loaded, in any order:

```julia
using PowerImpedanceACDC
using LineCableModels
using Measurements
using PowerImpedanceACDC.NetworkBuilder: Grid, define,
    sampled_frequency_response
```

The integration boundary is deliberately narrow. LineCableModels constructs
and solves `CableDesign`, `LineCableSystem`, and `EarthModel` problems;
PowerImpedanceACDC consumes the resulting `LineParameters`. LCM solvers are not
executed inside Gridspace.

### Native and lazy entry points

The extension adds these positional overloads:

```julia
overhead_line(lp::LineParameters;
    length,
    transformation = false,
    connection = true,
    extrapolation = :error,
)

cable(lp::LineParameters;
    length,
    transformation = false,
    connection = true,
    extrapolation = :error,
)

overhead_line(Grid, lp::LineParameters;
    length,
    transformation = false,
    connection = true,
    extrapolation = :error,
)

cable(Grid, lp::LineParameters;
    length,
    transformation = false,
    connection = true,
    extrapolation = :error,
)
```

The native overloads return an ordinary `Element` and accept deterministic
`LineParameters`. The positional-`Grid` overloads return `Gridspace{Element}`
and must be used when `lp.Z`, `lp.Y`, or `length` is uncertain, or when another
line argument is an explicit Gridspace axis. The older qualified
`NetworkBuilder.overhead_line(lp; ...)` and `NetworkBuilder.cable(lp; ...)`
spellings remain supported.

`length` is required and is measured in metres. LCM `Z` and `Y` are interpreted
as per-metre matrices in Ω/m and S/m. A `LineParameters` object does not carry
metadata indicating that values were previously multiplied by physical line
length, so outputs calculated with `per_length=false` cannot be consumed
safely.

### Deterministic LCM calculation

LCM returns the workspace and the line-parameter result separately:

```julia
workspace, lp = LineCableModels.compute!(problem, formulation)

line = cable(
    lp;
    length = 100e3,
    transformation = true,
)
```

Use positional `Grid` dispatch to compose that result declaratively with a
length sensitivity axis:

```julia
line_space = cable(Grid,
    lp;
    length = Grid([50e3, 75e3, 100e3]),
    transformation = true,
)
```

The `LineParameters` object itself remains atomic. The explicit `Grid` on
`length` is the axis in this example.

### Accurate Monte Carlo in LCM

When uncertainty originates in cable geometry, material properties, placement,
or earth data, the most faithful place to propagate it is LCM. LCM then
recomputes the electromagnetic line model for each sampled physical design:

```julia
using LineCableModels.UQ

lcm_mc = LineCableModels.UQ.mc(
    system_spec,
    formulation;
    trials = 2000,
    distribution = :normal,
    seed = 2026,
    return_samples = true,
    return_pdf = true,
    per_length = true,
)
```

The important inputs are:

| Input | Meaning |
|:--|:--|
| `system_spec` | LCM system-builder specification containing uncertain physical primitives and the frequency vector |
| `formulation` | EMT formulation used to calculate `Z(f)` and `Y(f)` |
| `trials` | Number of full LCM physical realizations; omit to use LCM's DKW sizing |
| `distribution` | Primitive law, `:normal` or variance-equivalent `:uniform` |
| `seed` | Reproducible LCM run seed |
| `trial_sampler` | Optional callback for shared or otherwise correlated primitive draws within one trial |
| `return_samples` | Retain complete empirical R/L/C/G trial tensors |
| `return_pdf` | Retain entrywise histogram PDFs |
| `per_length` | Must be `true` for subsequent PowerImpedanceACDC use |

Use `trial_sampler` when several LCM inputs depend on the same uncertain
physical quantity. Draw that primitive once for a trial and rebuild every
dependent input from that draw. Independently sampling those dependent inputs
would alter the intended physical covariance before the line calculation even
runs.

The resulting `LineParametersMC` contains:

| Field | Contents |
|:--|:--|
| `f` | Deterministic frequency vector |
| `stats.R`, `.L`, `.C`, `.G` | Entrywise statistics indexed by conductor, conductor, and frequency |
| `pdf.R`, `.L`, `.C`, `.G` | Optional entrywise marginal PDFs |
| `samples.R`, `.L`, `.C`, `.G` | Optional arrays with dimensions `(i, j, frequency, trial)` |
| `measurements` | A `LineParameters` summary whose `Z` and `Y` entries contain Measurements values |

The optional PDFs are marginal distributions. They describe each scalar entry
but do not record which values occurred together in a physical trial. They must
not be sampled independently to manufacture a coupled `Z(f),Y(f)` realization.

### Coupling LCM uncertainty into PowerImpedanceACDC

The clean moment-and-covariance path is to pass the Measurements-valued summary
directly to the lazy constructor:

```julia
uncertain_line = cable(Grid,
    lcm_mc.measurements;
    length = 100e3,
    transformation = true,
)

elements = (
    line = uncertain_line,
    # converters, sources, and other elements are declared here as Gridspaces
)

builders = define(elements, connections; options = builder_options)

result = determine_impedance(
    builders;
    nets = [:observed_bus],
    elim_elements = [:converter],
    freq_range = (10.0, 5e3, 400),
    trials = 1000,
    distribution = :normal,
    seed = 2026,
    return_samples = true,
)
```

Before line evaluation, the extension samples the shared primitive tags in the
complete `LineParameters` once per PowerImpedanceACDC trial and reconstructs
ordinary dense numeric `Z` and `Y` arrays. The same primitive draw is therefore
used across matrix entries, real and imaginary components, `Z` and `Y`, and all
frequencies.

This guarantee depends on `lcm_mc.measurements` actually encoding the joint
covariance. An LCM aggregator which creates a fresh independent
`measurement(mean, std)` for every scalar retains only marginal standard
deviations. A covariance-preserving aggregator must construct all scalar
Measurements from shared latent primitives derived from the complete trial
tensors. The PowerImpedanceACDC extension preserves covariance that is present;
it cannot recover covariance that LCM has already discarded.

With shared tags present, `distribution=:normal` uses standard-normal latent
draws. `distribution=:uniform` uses independent `Uniform(-√3, √3)` latent
draws. Both reproduce the encoded first-order means, variances, and signed
covariances in expectation. They remain moment-based surrogate distributions:
a nonlinear or heavy-tailed empirical LCM distribution is not reconstructed
from moments alone.

For exact empirical propagation, one physical trial means one common trial
index across every R/L/C/G entry and every frequency:

```julia
R_t = lcm_mc.samples.R[:, :, :, trial]
L_t = lcm_mc.samples.L[:, :, :, trial]
G_t = lcm_mc.samples.G[:, :, :, trial]
C_t = lcm_mc.samples.C[:, :, :, trial]
```

Those four arrays jointly define one numeric `LineParameters`. A separate
trial index for each entry, or independent sampling from the marginal PDFs,
does not. Direct `LineParametersMC` dispatch is intentionally not part of the
current extension. The clean exact path is:

1. select one common LCM trial index across `R`, `L`, `C`, `G`, and frequency;
2. construct the numeric phase-domain, per-metre `LineParameters` for that
   trial;
3. build and evaluate the complete PowerImpedanceACDC system for that trial;
4. store the resulting numeric impedance, admittance, or loop-gain response as
   one fourth-dimension response slice; and
5. call `sampled_frequency_response(samples, omega; nodes, trial_ids)`.

This separates responsibilities cleanly: LCM samples physical line designs,
PowerImpedanceACDC evaluates complete systems, and the response adapter carries
the exact joint trials into Nyquist, Bode, passivity, small-gain, margin, and EVD
analysis. Use `.measurements` instead when a covariance-preserving first-order
surrogate is sufficient and a second Monte Carlo stage inside
PowerImpedanceACDC is desired.

### Supported line representations

The extension validates the LCM result before constructing a line:

| Property | Requirement |
|:--|:--|
| Domain | `PhaseDomain`; transform modal results back to phase coordinates first |
| Order 1 | `transformation=false` |
| Order 2 | `transformation=true` for the native DC differential representation |
| Order 3 | `transformation=false` or `true`; `true` applies the dq transformation |
| Matrices | Dense or diagonal square `Z` and `Y` with identical dimensions; mutual terms are retained |
| Frequencies | At least two finite, positive, strictly increasing deterministic samples |
| Length | Finite, positive, and expressed in metres |
| Extrapolation | `:error` by default; `:linear` enables endpoint linear extrapolation |

Each complex `Z` and `Y` entry is interpolated linearly in frequency using its
real and imaginary parts. Negative frequencies use conjugate symmetry. With
strict range checking, the LCM frequency table must cover every frequency used
by the downstream calculation, including:

- 50 Hz for AC power flow;
- `|f ± 50 Hz|` sidebands for dq impedance scans;
- frequencies near zero when a DC conversion requires them.

Extrapolation is an explicit modelling decision, not a replacement for a
frequency table designed for the intended PowerImpedanceACDC study.
