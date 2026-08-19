# Changelog

## Unreleased

- Add backend-independent `UnitHandler` and declarative `PlotBuilder` modules,
  with optional CairoMakie, GLMakie, WGLMakie, and Plots.jl extensions.
- Add a harmonic nodal-impedance recipe with driving-point, transfer,
  overlay, panel, and page selections; interactive controls; and native SVG
  export from the current figure state.
- Move the common problem/formulation/result declarations to `Grammar.jl`
  without changing their root-module identities.
- Replace NetworkBuilder pin chains with explicit `(node, element, side,
  terminal)` topology rows and component-specific AC/DC port descriptions.
- Rename the materialized and linearized NetworkBuilder structures to
  `NetworkState`, `NetworkTopology`, `AdmittanceLookup`, `NetworkLookup`, and
  `NetworkModel`, with hard-error migration shims for the retired type names.
- Add the public problem/formulation/result calculation interface for power
  impedance, nodal and edge admittance, loop gain, and downstream stability
  analysis.
- Use one typed `PowerFlowResult → OperatingPoint → LinearizationResult`
  sequence for scalar and Gridspace calculations, retaining passive-only
  operating-point and active-admittance reuse.
- Add the Literate Connection DSL tutorial and require explicit import of the
  supported Classic `@network` macro.
- Rename the package and primary module to `PowerImpedance`, retaining the
  UUID, a `PowerImpedanceACDC` module alias, and an entry point for manifests
  that already resolve the former package name.
- Add deterministic Cartesian `Grid` and `Gridspace` parameterization under `NetworkBuilder`.
- Add qualified shadow constructors for supported elements and nested configurations.
- Add Measurements.jl extension-driven Monte Carlo solve and impedance studies.
- Add optional LineCableModels.jl `LineParameters` line constructors with
  covariance-aware Gridspace sampling.
- Add ordered parametric result collections, statistics, optional samples, and seeded studies.
- Extend Gridspace through nodal-admittance construction, exact per-trial
  loop-gain composition, and fused small-signal stability analysis.
- Add uncertainty-aware Nyquist, Bode, small-gain, passivity, EVD, stability
  margin, unstable-frequency, and active-device partition analyses.
- Add exact external whole-trial response adapters, frozen replay provenance,
  explicit aligned/independent pairing, and covariance-aware standalone
  Measurements response surrogates.
