# PowerImpedance.jl

PowerImpedance is a Julia package for frequency-domain analysis of modern
AC, DC, and hybrid power systems. It provides impedance and admittance
characterization, AC/DC power-flow initialization, and fast small-signal
stability assessment using analytical models validated against PSCAD EMT
simulations with the Z-tool [[1]](#reference-1), [[2]](#reference-2). The
analytical component models have been validated over the frequency range from
0.1 Hz to 5 kHz.

## Supported components

### Analytical models

- Modular multilevel converters (MMCs)
  - Grid-following (GFL) control
  - Grid-forming (GFM) control
  - Multiple modulation schemes
- Two-level converters with multiple control strategies
- Overhead transmission lines
- Underground cables
- Synchronous generators
- Induction machines
- Transformers
- Lumped impedances
- Ideal AC and DC voltage sources

### Black-box models

Frequency-response data can be imported for:

- Passive components
- VSC-based AC/DC converters

## Features

### Impedance characterization

- Driving-point and transfer impedance or admittance characterization of
  individual components and aggregated systems
- Nodal and edge admittance construction

### Loop-gain-based stability assessment

- Stability assessment using the Generalized Nyquist Criterion (GNC) for
  standalone-stable multiple-input multiple-output (MIMO) systems
- Oscillation-mode identification using the Phase-Shift Criterion (PSC)
- Bode plots, stability margins, and unstable-frequency scans

### Nodal-impedance-based stability assessment

- Eigenvalue decomposition of nodal impedance matrices
- Stability assessment and oscillation-mode identification using the Positive
  Mode Damping (PMD) criterion
- Stability assessment and oscillation-mode identification using PSC
- Bus participation-factor analysis

### Additional analysis tools

- Passivity assessment
- Small-gain analysis

### Optional declarative plotting

The backend-independent `PlotBuilder` describes axes, series, layouts,
controls, legends, and SVG settings without loading a graphics package.
Optional CairoMakie, GLMakie, and WGLMakie extensions render harmonic nodal
impedance magnitude in dBΩ against frequency in Hz. Plots.jl is also optional
and continues to render the existing stability-analysis figures. See the
[PlotBuilder guide](docs/src/developers/plotbuilder.md).

### Parametric and uncertainty studies

Gridspace extends the ordinary component constructors to deterministic
parameter sweeps and uncertainty quantification while preserving the scalar
API. Importing `Grid` from `PowerImpedance.NetworkBuilder` and passing it as
the first positional argument selects the lazy NetworkBuilder form. Selected
component parameters can then receive `Grid(...)` values without qualifying
every constructor through the `NetworkBuilder` namespace.

The same parametric study implementation covers impedance, nodal admittance, loop gain, and
small-signal stability analysis. It preserves numeric Monte Carlo trials,
repeats power flow and linearization when active devices or topology change,
and reuses the active operating point for passive-only variations. Parametric
overloads are available for Nyquist, Bode, small-gain, passivity, EVD,
stability-margin, and unstable-frequency analysis. See the
[Gridspace guide](docs/src/gridspace.md).

Optional package extensions provide covariance-aware `Measurements` sampling
and direct construction of overhead lines and cables from phase-domain
`LineParameters` objects produced by
[LineCableModels.jl](https://github.com/Electa-Git/LineCableModels.jl). Exact
external Monte Carlo response tensors can be adapted with
`NetworkBuilder.sampled_frequency_response` while preserving cross-entry and
cross-frequency trial dependence. See
[Package extensions](docs/src/package_extensions.md).

### Explicit network topology and calculations

`NetworkBuilder.define` accepts one named row per connected element terminal:

```julia
using PowerImpedance
using PowerImpedance.NetworkBuilder: define

elements = (branch = impedance(z = 2.0, pins = 1),)
connections = (
    (node = :bus, element = :branch, side = 1, terminal = 1),
    (node = :gnd, element = :branch, side = 2, terminal = 1),
)
network = define(elements, connections)
```

`NetworkTopology` derives AC/DC domains and bus indices from component port
definitions while preserving input-row and first-occurrence node order. The
public problem/formulation interface evaluates nodal impedance, node and edge
admittance, loop gain, and downstream stability analyses from either a
`NetworkState` or an already linearized `NetworkModel`. See
[Network construction](docs/src/network.md) and the executable
[Connection DSL tutorial](examples/Connection_DSL.jl).

The Classic network DSL remains available with
`import PowerImpedance: @network`; the macro is no longer imported by
`using PowerImpedance`.

## Example

The figure below shows the admittance characteristics of a point-to-point HVDC
link consisting of two MMCs. The analytical results are validated against
PSCAD EMT simulations. A step-by-step implementation is available in the
`examples` folder.

![Validation against PSCAD](docs/src/pictures/P2P_validation.png)

## Installation

Install the latest release using the Julia package manager:

```julia
pkg> add PowerImpedance
```

Then load the package:

```julia
using PowerImpedance
```

### Compatibility with the former name

The package and its primary module were formerly named `PowerImpedanceACDC`.
The package UUID is unchanged, and `PowerImpedance` exports the former module
name as an alias, so qualified references remain valid after changing the
import:

```julia
using PowerImpedance

PowerImpedanceACDC.determine_impedance === PowerImpedance.determine_impedance
```

An existing manifest that already resolves `PowerImpedanceACDC` to this UUID
can also use the retained compatibility entry point. Fresh environments should
install and import `PowerImpedance`; Julia package metadata cannot assign two
package names to one UUID.

The Measurements extension activates when `Measurements` is loaded. Direct
`LineParameters` interoperability activates when both
[LineCableModels.jl](https://github.com/Electa-Git/LineCableModels.jl) and
`Measurements` are loaded.

## Citation

If you use PowerImpedance in your research, please cite:

```bibtex
@misc{PowerImpedance25,
  author = {{Etch}},
  title  = {{PowerImpedance}: Impedance-Based Stability Analysis},
  month  = mar,
  year   = {2025}
}
```

Complete BibTeX metadata for the software and its supporting publications is
available in [`CITATION.bib`](CITATION.bib).

## Contributors

- **Aleksandra Lekic**
  - Initial implementation
  - MMCs
  - Overhead lines
  - Cables
  - Transformers

- **Özgür Can Sakinci**
  - MMCs
  - Two-level converters
  - Synchronous generators
  - Time-delay models
  - Initial bipolar implementation

- **Thomas Roose**
  - Generalized Nyquist analysis
  - Eigenvalue decomposition
  - Bus participation factors

- **Francisco J. Cifuentes Garcia**
  - Passivity analysis
  - Small-gain analysis
  - Oscillation-mode identification
  - Phase-Shift Criterion implementation
  - MMC models
  - Two-level converter models
  - Synchronous machine models

- **Jan Kircheis**
  - MMC models
  - Component validation
  - Multinodal stability analysis
  - Black-box model implementation
  - Transformers

- **Robbe Vander Eeckt**
  - Component validation
  - Two-level converters
  - Power-flow implementation
  - Induction machines
  - Code development

- **Amr Saad**
  - Component validation

- **Amauri Martins**
  - Passive components
  - NetworkBuilder
  - Testing
  - Continuous integration
  - Parametric studies
  - Uncertainty quantification
  - Extension modules for Measurements and [LineCableModels.jl](https://github.com/Electa-Git/LineCableModels.jl)

- **Luis Müller**
  - Bipolar implementation
  - Code development

- **Paulin Eliat-Eliat**
  - MMC models
  - Code development

## Development

For local Conventional Commit warnings, enable the tracked advisory hook with:

```bash
git config core.hooksPath .githooks
```

The hook never blocks a commit.

## References

<a id="reference-1"></a>
**[1]** F. J. Cifuentes Garcia, T. Roose, Ö. C. Sakinci, D. Lee, L. Dewangan,
E. Avdiaj, and J. Beerten, “Automated Frequency-Domain Small-Signal Stability
Analysis of Electrical Energy Hubs,” *2024 IEEE PES Innovative Smart Grid
Technologies Europe (ISGT EUROPE)*, pp. 1–6, 2024.
[doi:10.1109/ISGTEUROPE62998.2024.10863484](https://doi.org/10.1109/ISGTEUROPE62998.2024.10863484)

<a id="reference-2"></a>
**[2]** F. J. Cifuentes Garcia and J. Beerten, “Z-Tool: Frequency-domain
characterization of EMT models for small-signal stability analysis,” *Electric
Power Systems Research*, vol. 252, art. 112405, 2026.
[doi:10.1016/j.epsr.2025.112405](https://doi.org/10.1016/j.epsr.2025.112405)

## Acknowledgements

This work is supported by the Etch Competence Hub of EnergyVille, financed by the Flemish Government.

<p align = "left">
  <p><br><img src="docs/src/assets/img/ETCH_LOGO_RGB_COLOR.svg" width="150" alt="Etch logo"></p>
  <p><img src="docs/src/assets/img/ENERGYVILLE-LOGO.svg" width="150" alt="EV logo"></p>
  <p><img src="docs/src/assets/img/kul_logo.svg" width="150" alt="KUL logo"></p>
</p>
