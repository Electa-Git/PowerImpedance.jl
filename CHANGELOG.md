# Changelog

## Unreleased

## [0.4.0] - 2026-10-28

### Added

- Add a legend for the glyphs in standalone and PlotBuilder network diagrams.
- Declare electrical ports with `Port`, `ACDQ`, `ACABC`, `DC_CM` and
  `electricalconnections`, and connect them with `NetworkBuilder.Bus` and `Net`.
- Declare configurable inputs with `Input` and `inputs`, read configured values
  with `inputvalues`, and configure copies with `withinputs` and `component`.
- Expose component bases with `BaseValues` and `bases`, and stored operating
  limits with `limits`.
- Add `ACPortValues` and `DCPortValues` for per-port operating values, and
  `linearize` and `steady_state` for state-space component models.
- Export passive AC/DC networks, overhead lines, cables, transformers,
  synchronous machines with AVR/governor, induction machines with load torque
  control, TLC grid-following controls and MMC controls for grid-following and
  grid-forming operation, energy controls and compensated modulation to PSCAD 5 projects
  (`export_pscad`, requires `using PythonCall`). Run projects remotely with
  `PSCADModel`, `PSCADRun`, `RemoteConfig` and `read_pscad_output`, and compare
  steady state, machine terminal power and speed with `compare_operating_point`.
- Add `ZToolProbe` for AC/DC scans in series at a component port or as an open
  shunt at a bus. Exports include the checked v0.1.52 library and workspace, and
  runs load the library before the project. `ZToolScan` runs frequency sweeps
  through the configured PSCAD application. `ZToolResult` and
  `read_ztool_admittance` return admittance matrices in siemens from AC, DC and
  mixed scans.
- Add `overhead_line(; transposition = :ideal)` for an ideally transposed
  three-phase line, averaging series impedance and potential coefficients over
  the phase positions. PSCAD exports set `Transp = 1` for these lines.
- Add `DCVoltageSupportLag` for MMC/TLC active-power control. Power-flow reference
  and slope use `vDCbase`. With a 672 kV operating voltage, 640 kV base, gain 5,
  500 MVA rating and 1.05 pu reference, the target is 672 kV and the slope is
  3.90625 MW/kV. The former mapping used 705.6 kV and 3.720238095 MW/kV away from
  nominal voltage. PSCAD export is not yet supported.
- Add a getting-started example for a synchronous machine connected to an infinite bus.
  It calculates the operating point, the machine-bus impedance and the generalized
  Nyquist response.

### Changed

- **Breaking:** `linearize(model, values)` returns a `StateSpaceLinearization`
  with equilibrium `state` and continuous-time `system`. Remove `LinearizationCache`
  and the `cache` fields from MMC, TLC, synchronous-machine and induction-machine models.
  `steady_state(model, values)` computes the equilibrium on each call.
- **Breaking:** component constructors return models directly.
  `NetworkState.elements` stores the models under their NamedTuple names.
- **Breaking:** passives use `conductors` for conductor count, including the
  `Transformer` field. `ac_source` always has three conductors. `dc_source` has one.
- **Breaking:** ports use `side1`/`side2` for two-port passives, `ac` for AC
  devices, `dc` for DC sources, and `(ac, dc)` for converters. Terminal labels
  are symbols. AC coordinates follow the bus: `ACABC` ports on an `ACDQ` bus
  are transformed to dq. A three-phase `:ΔY` transformer requires an `ACDQ` bus.
- **Breaking:** configure references and power-flow setpoints with `component` or
  `withinputs`. Control references and converter or machine setpoints are per unit
  on the model's `BaseValues`. Source inputs use physical units.
- **Breaking:** move base keywords from `ElectricalMMC`, `ElectricalTLC`,
  `ElectricalSM` and `ElectricalIM` to `mmc`, `tlc`, `synchronousmachine` and
  `inductionmachine`. Keep their names, units and defaults. Return the model's
  `bases` field from `bases(model)`. Replace electrical base fields `Sbase`,
  `vAC_base`/`vACbase`, `vDC_base`/`vDCbase`, `ωbase`, `S_base` and `ωn` with
  `bases(model).S`, `.v_ac`, `.v_dc` and `.omega`. Read derived electrical values
  `Lₑ`, `Rₑ`, `zAC_base`, `lAC_base`, `baseConv1`, `baseConv2`, `baseConv3`,
  `zACbase`, `lACbase`, `iACbase` and `iDCbase` from `perunit(elec, bases)`.
  Store MMC arm fields `Lₐᵣₘ`, `Rₐᵣₘ`, `Cₐᵣₘ` in H, Ω and F, and TLC `Lᵣ`,
  `Rᵣ` in H and Ω. Move the machines' line-to-line RMS voltage bases `Vᵃᶜ_base` and
  `Vac_base` from their electrical sub-models to the models.
- **Breaking:** `Source` is immutable and stores physical `v`, `theta`, `p`, `q`,
  conductor count, domain, limits and its ideal ABCD matrix. Set the source limits
  with `component(source; limits = x)`. `ac_source` has no `limits` keyword.
- **Breaking:** the scan-based MMC accepts `ac_control`, `dc_control`, `powerflow`
  in physical MW, MVAr, AC phase-peak kV and DC pole-to-pole kV, and `limits`.
  Controller objects are unsupported. Its scan uses solved terminal values.
- **Breaking:** evaluate scan-based MMC admittance with `eval_parameters(model, values, s)`
  from solved `(ac, dc)` port values. Remove the `Blackbox_MMC.cache` field and
  `update!(::Blackbox_MMC, ...)`.
- **Breaking:** `OperatingPoint.values` stores values by component and port,
  accessed as `op[:c1].ac.p`. Port powers and signed currents are positive into
  the component, with `Y = I_in / V`. Source, synchronous-machine and converter
  AC powers negate the former values. Induction-machine AC and converter DC
  powers retain their signs. Converter `powerflow.p_dc` is positive into its DC port.
- **Breaking:** topology uses `Bus` and `Net`. Stored rows have `net`, `bus`,
  `component`, `port`, `terminal`, `domain` and `frame`. `define(...; exclude)`
  omits named components and rejects unreferenced included components.
- **Breaking:** `solve(state)` returns a `PowerFlowResult`. An explicit
  `PowerFlowProblem` always solves, including networks with only sources and passives.
- **Breaking:** `export_pscad` accepts a `NetworkState` and an optional
  `PowerFlowResult` through `powerflow`. Without one, power flow is solved
  for every network. Export uses solved bus voltages and transformer ratings.
- **Breaking:** PSCAD current probes use `I_<element>_<port>`, such as `I_c1_ac`,
  and measure current into the component at each port. Voltage names remain
  `V_<bus>`. `ZToolProbe` selects a named `port`.
- **Breaking:** network-diagram terminal details use `port`. Component details
  use `grounded_ports` and per-port operating values.
- **Breaking:** rename the `AVRSM` field `vref_SG` to `v_ref`.
- **Breaking:** transformer `V₁ᵒ`/`V₂ᵒ` power-flow ratings use volts per phase,
  formerly kV per phase.
- **Breaking:** `dc_source` voltage is pole to pole in kV, consistently with
  converters. Callers that halved it before must pass the full voltage.
- The IEEE 39-bus example is a NetworkBuilder tutorial with a modular STATCOM
  and an impedance-based stability check at Bus 9. The documentation runs it.
- PSCAD operating-point comparison reports `settling` and checks the change
  between window halves against `settling_fraction` times each row's tolerance.
  The default fraction is `0.1`.
- Tighten PSCAD overhead-line and cable frequency-dependent fit targets
  `YMaxE`/`AMaxE` from 0.2% to 0.02%, overridable through `line_options`.
- Tighten power-flow defaults to `tol=1e-6`, `constr_viol_tol=1e-5` and
  `max_iter=300`. Accept returned points within the configured primal feasibility
  tolerance with a warning regardless of solver status, with the configured tolerances.
  Comparable raw bus magnitudes and angles change by up to 8.72589e-05 pu and
  1080 degrees. Converter and generator P/Q change by up to 0.437079 MW and
  1.329107 MVAr,
  excluding the artificial extreme diagnostic.

### Removed

- Remove the classic network API: `Network`, `@network`, `add!`, `connect!`,
  `disconnect!`, `composite_element`, `power_flow`, and classic solvers
  `make_abcd`, `make_y`, `make_z`, `determine_impedance`, `make_y_matrix`,
  `make_y_edge`, `make_y_node` and `check_stability`. NetworkBuilder solvers
  and `check_stability(::NetworkState, ...)` remain available.
- Remove `Element`, `Setpoint`, `SetpointPU` and their methods. Remove
  `PowerFlowResult.active_setpoint_values`. Use `result.operating_point.values`.
- Remove the constructor keywords `pins`, `transformation`, `connection` and
  `setpoint`, and the old topology rows and keyword grammar.
- Remove source fields `V`, `P`, `Q`, `P_min`, `P_max`, `Q_min`, `Q_max` and `pins`.
- Remove `export_pscad(::Network)`, classic PSCAD netlists and numeric probe sides.
- Remove old controller types `Controller`, `PI_control`, `VSE_old`, `CCQSEM`
  and `FFVI`, and the scan-based MMC options `:vdc_droop` and `:vac_supp`,
  which always threw an error.
- Remove unused legacy converter files, `controller_old.jl`, `make_y_edge_old`
  and the converter keyword adapter. `mmc(Grid; ...)` and `tlc(Grid; ...)`
  accept modular constructor keywords only.
- Remove error messages for retired NetworkBuilder names and the manual's
  classic-interface and old network-performance pages.

### Fixed

- Use each component's solved operating point when components share a scan-based MMC
  model. Before this change, both components used the operating point written last.
- Build network models for networks with no passive elements.
- Apply the synchronous-machine admittance base in network admittance assembly.
- Use induction-machine torque on the network power base and include transformer
  resistance and inductance in the stator impedance for power flow.
- Use CODATA 2018 vacuum permittivity, 8.8541878128e-12 F/m, for overhead lines
  and cables. Capacitances increase by about 0.0473%.
- Correct B and D block order in multiconductor line and cable ABCD matrices,
  including imported Z/Y lines, restoring reciprocal terminal admittances and
  section composition for untransposed geometries. Use concrete complex matrices
  for imported-line evaluation on Julia 1.10.
- Pre-charge source-free DC networks with a Vdc-controlling converter through
  temporary ideal sources behind breakers, released at 0.2 s.
- Round fractional residual PSCAD modulation delays to the nearest integration
  step, with half-step ties upward and a warning when the delay changes.
- Set PSCAD sheets to size 5 and reject coordinates outside the sheet or component
  relocation on load. Count output rows after file sizes stabilize, without a timeout.
- Correct the Wedepohl-Wilcox cable earth-return logarithmic constant to
  `exp(γ_E) ≈ 1.781072418` in self and mutual terms. For earth relative
  permeability 1, this removes excess reactance of approximately
  `1.41592 f μΩ/m` (70.7961 μΩ/m at 50 Hz) from each earth coefficient. The
  correction vanishes at DC. Evaluate self earth return at each cable's own
  burial depth. Common-depth groups retain bit-identical results from the constant fix.
- Start repeated power-flow solves from the converged point and set the converter
  current's initial value from apparent power, eliminating drift in the
  TLC DC-voltage-control case.
- Correct inferred voltage levels for unrated transformers and set PSCAD winding
  ratings from the solved primary voltage.
- Correct the Δ-triplen energy-balancing frame direction, changing compensated-MMC
  admittances slightly and damping the previously unstable 150 Hz mode.
- Normalize stored converter voltages and retry failed steady-state initialization
  with a trust-region solve, preserving successful results.
- Derive synchronous-machine torque and effective AVR references from power flow
  and initialize states from its phasors. Machine equilibria, linearizations,
  admittances and PSCAD control parameters reproduce terminal P/Q/voltage.
  Power-flow and other component results retain their values.
- Apply MMC Σ controls, converter reference fallback, local VAC/DC and power
  filters, and supported droop equations. The removed keyword adapter previously
  omitted these controls or references, changing its equilibria, admittances and
  power-flow inputs when a reference supplied a missing target. Existing modular
  constructions retain their numerical results.
- Resolve the power-flow fallback model's module name, replacing an undefined-name
  error with the relaxed solve while preserving converged results.
- Correct the modular MMC/TLC reactive-power convention in repeated power-flow
  solves, preserving first-solve converter states, linearizations and admittances.
- Constrain modular MMC/TLC AC-voltage-control equilibria to solved reactive
  power, changing VAC steady states and dependent admittances.
- Scale modular MMC VAC and Q-V references to the measured side of its transformer,
  changing control equations and admittances for non-unit turns ratios.
- Use AC voltage control and Q-V droop in grid-following MMC power flow,
  changing voltages, reactive powers and dependent linearizations. The TLC
  power-flow mapping remains unchanged.
- Correct terminal scaling in network calculations, changing cross-admittances
  of modular MMCs with a converter transformer.
- Preserve TLC electrical current initial values and accept zero-voltage initialization.
- Classify six-terminal three-phase models as AC for power flow, including abc
  sources, impedances and lines.
- Use one default voltage base (`NetworkBuilder.DEFAULT_VOLTAGE_BASE`, 320 kV)
  for power flow and materialized networks.
- Accept explicit overhead-line conductor positions, as documented.
- Use per-pole resistance `z/2` for differential DC impedances in power flow,
  consistently with the differential frequency-domain model.
- Correct `:ΔY` to Dyn11 with a line-to-line voltage ratio, the complete per-phase
  Y-equivalent T-model and a 30° secondary lead in frequency-domain and power-flow
  calculations. Reject three-phase abc use because zero-sequence isolation has
  no phase-domain ABCD representation.
- Use the exact pi conversion of the transformer T-model in power flow, with
  the magnetizing branch on the primary side.

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
- Remove the former plotting backend and the compatibility methods for packages.
- Add a harmonic nodal-impedance definition with driving-point and transfer
  entries. It supports overlay, panel, and page selections, interactive
  controls, and SVG export from the current figure state.
- Replace NetworkBuilder pin chains with explicit `(node, element, side,
  terminal)` topology rows and component-specific AC/DC port descriptions.
- Rename the materialized and linearized NetworkBuilder structures to
  `NetworkState`, `NetworkTopology`, `AdmittanceLookup`, `NetworkLookup`, and
  `NetworkModel`, with hard-error migration shims for the retired type names.
- Add the public calculation interface with problems, formulations and results for power
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
