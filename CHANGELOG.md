# Changelog

## Unreleased

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
