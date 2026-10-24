# Changelog

## Unreleased

### Added

- `ZToolScan` runs Z-tool frequency sweeps from Julia through the configured
  PSCAD application. `ZToolResult` and `read_ztool_admittance` give admittance
  matrices in siemens from AC, DC and mixed scans.

- PSCAD exports include induction machines with load torque control and terminal power and speed comparisons.
- `ZToolProbe` adds Z-tool AC and DC scans in series at an element terminal or
  as an open shunt at a bus. Exports with probes include the checked v0.1.52
  library and workspace, and runs load the library before the project.
- `overhead_line(; transposition = :ideal)` models an ideally transposed
  three-phase line by averaging the series impedance and potential coefficients
  over the three phase positions. PSCAD exports set `Transp = 1` for these lines.
- Add `DCVoltageSupportLag` for MMC/TLC active-power control and map legacy
  `vdc_droop`, changing results for those formerly ignored legacy controls;
  existing constructions retain their results. Power-flow reference and slope
  use `vDCbase`, intentionally differing from the historical mapper away from
  nominal voltage. With a 672 kV operating voltage, the 640 kV base, gain 5,
  500 MVA rating and 1.05 pu reference give 672 rather than 705.6 kV and the slope is 3.90625
  rather than 3.720238095 MW/kV. PSCAD export is not yet supported.
- Export passive AC/DC networks, overhead lines, cables, transformers,
  synchronous machines with AVR/governor, TLC grid-following controls and MMC
  grid-following/grid-forming controls, energy controls and compensated
  modulation to PSCAD 5 projects (`export_pscad`, requires `using PythonCall`).
  Run projects remotely (`PSCADModel`, `PSCADRun`, `RemoteConfig`,
  `read_pscad_output`) and compare their steady state with the power flow
  (`compare_operating_point`).

### Changed

- The IEEE 39-bus example is a NetworkBuilder tutorial with a modular STATCOM
  and an impedance-based stability check at Bus 9. The documentation runs it.
- PSCAD operating-point comparison reports `settling` and checks the change
  between window halves against `settling_fraction` times each row's tolerance.
  The default fraction is `0.1`.
- Tighten default PSCAD overhead-line and cable frequency-dependent fit targets
  `YMaxE`/`AMaxE` from 0.2% to 0.02%, still overridable through `line_options`;
  exported projects containing AC/DC lines or cables change.

- **Breaking:** Read transformer `V₁ᵒ`/`V₂ᵒ` power-flow ratings in volts per
  phase (previously kV per phase).
- Tighten default Classic and NetworkBuilder power-flow settings to `tol=1e-6`,
  `constr_viol_tol=1e-5` and `max_iter=300`; accept returned points within the
  configured primal feasibility tolerance with a warning regardless of solver
  status, without relaxation. Comparable power-flow raw bus magnitudes/angles
  change by up to 8.72589e-05 pu/1080 degrees and converter/generator P/Q by up
  to 0.437079 MW/1.329107 MVAr, excluding the artificial extreme diagnostic.
- **Breaking:** Interpret `dc_source` `Setpoint.Vdc` and legacy `V` as
  pole-to-pole DC voltage in kV, consistently with converters. Pass the
  pole-to-pole voltage; callers that halved it must stop halving.

### Removed

- Remove the unused legacy converter files and `make_y_edge_old`.
- **Breaking:** remove the converter keyword adapter. `mmc(Grid; ...)` and
  `tlc(Grid; ...)` accept the modular constructor keywords only.
- Remove the error messages for retired NetworkBuilder names.

### Fixed

- Network models now build for networks with no passive elements.
- Fix network admittance of circuits with a synchronous machine by applying its admittance base.
- Power flow for induction machines uses torque on the network power base
  and includes transformer resistance and inductance in the stator impedance.
- Overhead-line and cable parameters use CODATA 2018 vacuum permittivity,
  8.8541878128e-12 F/m. Capacitances increase by about 0.0473 %.
- Correct the B and D block order in multiconductor line/cable ABCD matrices,
  including imported Z/Y blackbox lines, to restore reciprocal terminal
  admittances and section composition for untransposed geometries. Use concrete
  complex matrices for blackbox evaluation on Julia 1.10.
- Pre-charge source-free DC networks with a Vdc-controlling converter through
  temporary ideal sources behind breakers, released at 0.2 s.
- Round fractional residual PSCAD modulation delays to the nearest integration
  step, with half-step ties upward and a warning when rounding changes the delay.
- Set PSCAD sheets to size 5 and reject coordinates outside the sheet or
  component relocation on load. Count output rows after file sizes stabilize; row counting runs without a timeout.

- Correct the Wedepohl–Wilcox cable earth-return logarithmic constant to
  `exp(γ_E) ≈ 1.781072418` in both self and mutual terms. For earth relative
  permeability 1, this removes excess reactance of approximately
  `1.41592 f μΩ/m` (70.7961 μΩ/m at 50 Hz) from each earth coefficient;
  the correction vanishes at DC. Evaluate each cable's self earth-return term
  at its own burial depth instead of reusing the first cable's depth;
  common-depth cable groups retain bit-identical results from the constant fix.
- Start repeated power-flow solves from the converged point and seed converter
  current from apparent power, eliminating drift in repeated solves of the TLC
  DC-voltage-control case.
- Correct inferred transformer voltage levels for unrated transformers.
- Set PSCAD transformer winding ratings from the solved primary voltage.
- Correct the Δ-triplen energy-balancing frame direction, changing compensated-MMC admittances slightly and damping the previously unstable 150 Hz mode.
- Normalize stored converter voltages and retry failed converter steady-state initialization with a trust-region solve, preserving successful results.
- Derive synchronous-machine torque and effective AVR references from the power
  flow and initialize states from its phasors, changing machine equilibria,
  linearizations, admittances and PSCAD machine control parameters to reproduce
  terminal P/Q/voltage; power-flow and other component results retain their values.
- Restore legacy MMC Σ controls and MMC/TLC reference fallback, local VAC/DC
  and power filters, and supported droop equations, changing legacy-keyword
  equilibria and admittances (and power-flow inputs when a previously ignored
  reference supplies a missing setpoint); existing modular constructions retain
  their numerical results.
- Resolve the module name of the Classic power-flow fallback model, replacing an undefined-name
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
