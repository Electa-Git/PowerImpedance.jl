# Changelog

## Unreleased

### Added

- PSCAD integration (work in progress): remote PSCAD execution of existing projects
  (`PSCADModel`, `PSCADRun`, `RemoteConfig`, `read_pscad_output`), export of passive AC
  networks to PSCAD projects (`export_pscad`, requires `using PythonCall`), and comparison
  of the simulated steady state with the power flow (`compare_operating_point`).

### Changed

- **Breaking:** Interpret `dc_source` `Setpoint.Vdc` and legacy `V` as
  pole-to-pole DC voltage in kV, consistently with converters. Pass the
  pole-to-pole voltage; callers that halved it must stop halving.

### Fixed

- Qualify the Classic power-flow fallback model, replacing an undefined-name
  error with the relaxed solve while preserving converged results.
- Store solved modular MMC and TLC reactive-power setpoints in the input
  convention, correcting the Q sign read by subsequent power-flow solves while
  preserving first-solve converter states, linearizations and admittances.
- Constrain modular MMC and TLC AC-voltage-control equilibria to the solved
  reactive power, changing VAC steady states and dependent admittances.
- Scale modular MMC VAC and Q-V control references onto the measured side of
  the converter transformer, changing their control equations and admittances
  for non-unit turns ratios.
- Use AC voltage control and Q-V droop in the power flow for grid-following
  MMCs, changing their solved voltages, reactive powers and dependent
  linearizations. The TLC power-flow mapping remains unchanged.
- Correct terminal scaling in both network paths, changing cross-admittances
  of modular MMCs with a converter transformer.
- Preserve TLC electrical current seeds and accept zero-voltage initialization.
- Classify untransformed six-pin elements as three-phase, so abc sources,
  impedances and lines enter the power flow as AC components.
- Use one default voltage base (`NetworkBuilder.DEFAULT_VOLTAGE_BASE`, 320 kV)
  for NetworkBuilder power flows and their materialized networks.
- Accept explicit overhead-line conductor positions, as documented.
- Use the per-pole resistance `z/2` for one-terminal DC impedances in the
  power flow, consistent with the differential frequency-domain model.
- Correct the `:ΔY` transformer to Dyn11 with a line-to-line voltage ratio,
  the complete per-phase Y-equivalent T-model, and a 30° secondary lead in
  frequency-domain and power-flow calculations. Reject untransformed
  three-phase use because zero-sequence isolation has no phase-domain ABCD.
- Use the exact pi conversion of the transformer T-model in the power flow,
  with the magnetizing branch placed on the primary side as modelled.

## [0.3.1] - 2026-09-22

- Add GraphMakie network-diagram plotting with new recipes, examples, and integration coverage.
- Update dependencies and CI, including PowerModelsACDC 0.10.1, Hungarian assignment, and dormant LineCableModels support.

## [0.3.0] - 2026-08-25

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
