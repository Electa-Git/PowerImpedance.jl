# Changelog

## Unreleased

## [0.3.0] - 2026-08-24

- Rename the registered package successor from `PowerImpedanceACDC` to
  `PowerImpedance` with a new package UUID.
- Define the computational grammar, Gridspace code, composite formulations, and
  result abstractions in `PowerImpedance.Grammar`.
- Add `Combinatorial`, `LinearError`, and `MonteCarlo` execution for owned
  problem spaces. `LinearError` now returns `LinearErrorResult` and preserves
  covariance through shared standardized latent variables.
- Run uncertain power-flow studies as local Monte Carlo calculations over
  numeric network realizations. Measurements are reconstructed only for the
  solved bus quantities after all PowerModels calls have completed.
- Add backend-independent `UnitHandler` and declarative `PlotBuilder` modules.
  CairoMakie, GLMakie, and WGLMakie provide the rendering extensions.
- Rename the PlotBuilder data model from `*Spec` to `*Definition` and add
  completed-result recipes for harmonic impedance, Nyquist, Bode, passivity,
  small gain, eigenvalue, and unstable-frequency plots.
- Remove graphics objects from calculation result payloads. Stability analyses
  retain the completed numerical trajectories and summaries required by the
  plotting recipes.
- Remove the former plotting backend and package compatibility entry points.
- Add a harmonic nodal-impedance definition with driving-point and transfer
  entries. It supports overlay, panel, and page selections, interactive
  controls, and SVG export from the current figure state.
- Replace NetworkBuilder pin chains with explicit `(node, element, side,
  terminal)` topology rows and component-specific AC/DC port descriptions.
- Rename the materialized and linearized NetworkBuilder structures to
  `NetworkState`, `NetworkTopology`, `AdmittanceLookup`, `NetworkLookup`, and
  `NetworkModel`, with hard-error migration shims for the retired type names.
- Add the public problem/formulation/result calculation interface for power
  impedance, nodal and edge admittance, loop gain, and downstream stability
  analysis.
- Use one typed `PowerFlowResult → OperatingPoint → LinearizationResult`
  sequence for scalar and Gridspace calculations. Each materialized network
  receives its own required power-flow solution, and explicit preprocessing
  pairs completed checkpoints with their source configurations.
- Add the Literate Connection DSL tutorial and require explicit import of the
  supported Classic `@network` macro.
- Add deterministic Cartesian `Grid` and `Gridspace` parameterization under
  `PowerImpedance.Grammar`.
- Add explicit `constructor(Grid; kwargs...)` methods for supported elements
  and nested configurations without a duplicate NetworkBuilder constructor family.
- Add optional LineCableModels.jl `LineParameters` line constructors with
  covariance-aware Gridspace sampling.
- Retain ordered configurations, statistics, optional raw samples, plotting
  trajectories, replay data, and failure records in composite result details.
