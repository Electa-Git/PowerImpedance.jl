# PowerImpedanceACDC

PowerImpedanceACDC is a Julia package for frequency-domain analysis of modern power systems. It provides tools for impedance/admittance characterization and fast small-signal stability assessment based on analytical models validated against PSCAD EMT simulations using the Z-tool [citations]. All implemented models have been validated in the frequency range from 0.1 Hz to 5 kHz.

## Supported Components

### Analytical Models
- Modular Multilevel Converters (MMCs)
  - Grid-Following (GFL) control
  - Grid-Forming (GFM) control
  - Various modulation schemes
- Two-level converters with multiple control strategies
- Overhead lines and underground cables
- Synchronous generators
- Induction machines
- Transformers
- Lumped impedances
- Ideal voltage sources

### Black-Box Models
Frequency-response data can be imported for:
- Passive components
- VSC-based AC/DC converters

## Features

### Impedance Identification
- Impedance and admittance characterization

### Loop-Gain-Based Stability Assessment
- Generalized Nyquist Criterion (GNC) for standalone-stable MIMO systems
- Oscillation mode identification using the Phase-Shift Criterion (PSC)

### Nodal-Impedance-Based Stability Assessment
- Eigenvalue decomposition of nodal impedance matrices
- Positive Mode Damping (PMD)-based stability assessment and mode identification
- Phase-Shift Criterion (PSC)-based stability assessment and mode identification
- Bus participation factor analysis

### Additional Analysis Tools
- Passivity assessment
- Small-gain analysis

### Parametric and uncertainty studies

Qualified `NetworkBuilder` shadow constructors support deterministic Cartesian
sweeps and Measurements.jl-based Monte Carlo studies while preserving the
ordinary scalar API. See the [Gridspace guide](docs/src/gridspace.md).

## Example

The figure below shows the admittance characteristics of a point-to-point HVDC link composed of two MMCs. The analytical results are validated against PSCAD simulations. This example, together with a detailed explanation, is available in the `examples` folder.

docs/src/pictures/P2P_validation.png

## Installation

Install the latest release using the Julia package manager:

```julia
] add PowerImpedanceACDC
```

For local Conventional Commit warnings, enable the tracked advisory hook with
`git config core.hooksPath .githooks`. The hook never blocks a commit.
