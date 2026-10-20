# Julia–PSCAD validation suite

This manual suite checks exported circuits against Julia operating points, frequency responses,
time-domain responses and instability growth. It covers passive elements, converters, synchronous
and induction machines, and coupled circuits. The scripts are private test utilities. Native measurements need
a configured Windows PSCAD station; preparation and local analysis do not contact it. The
[abbreviations](../../../../docs/src/pscad.md#Abbreviations) are defined in the export guide.

Passing an exported-project check establishes its written structure. Passing an operating-point
check establishes the measured equilibrium. Frequency-response and time-domain checks test their
declared inputs, windows and model realization. A finite frequency grid does not exclude
unresolved inter-bin resonances.

## Requirements and execution

Use Julia >=1.10 and the environment in this directory. Instantiate it with the same Julia version
used for execution. Remove its ignored Manifest before changing Julia versions, then instantiate
again from the repository root:

```sh
julia --project=test/manual/pscad/validation -e 'using Pkg; Pkg.develop(Pkg.PackageSpec(path=pwd())); Pkg.instantiate()'
```

The Windows station needs PSCAD 5.1.0, its licence and compiler, a logged-on desktop session, and
the dependencies described in the [export
guide](../../../../docs/src/pscad.md#prepare-the-windows-station). Set
`POWERIMPEDANCE_PSCAD_CONFIG` to its configuration file. Select a key from the catalogue and
assign it to the shell variable `fixture`. These commands prepare locally, inspect the written
XML, then run that fixture:

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/prepare.jl "$fixture"
julia --project=test/manual/pscad/validation test/manual/pscad/validation/check_projects.jl "$fixture"
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl "$fixture" --timeout=5400
```

`--timeout` is a finite positive workflow budget in seconds, shared across all selected fixtures.
Multiple keys can follow `run_station.jl`. Completed native runs resume only when project, inputs,
runner, outputs and solver identity match. An interrupted simulation restarts; completed axes
remain reusable. Analysis runs again after reuse. Measurements of passive elements, single devices
and coupled circuits must build with fewer than 100 live nodes. Complete-system builds use fewer than 200 live nodes and one subsystem.

Preparation solves power flow and computes passive dissipativity or active-network stability.
The screen result is recorded with the fixture and reported. Preparation writes baseline, driven,
half-amplitude and half-step projects with references, solved points and manifests. Changed physical projects/references are rejected rather than replacing retained native
data. Coupled-circuit preparation checks relevant harness sources against HEAD before writing
and rejects existing fixture directories. Use a committed implementation with the corresponding
stored-data preparation procedure.

For local checks without native execution:

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/runtests.jl
julia --project=test/manual/pscad/validation test/manual/pscad/validation/check_projects.jl "$fixture"
julia --project=test/manual/pscad/validation test/manual/pscad/validation/reanalyse.jl "$fixture"
```

`runtests.jl` runs the harness's own tests; they are not part of the package's `Pkg.test()`.
`reanalyse.jl` reads retained OUT/INF and saved-project metadata. Its `--refresh-reference` option
archives the previous Julia reference and analysis, regenerates power flow/admittance, and
verifies unchanged project hashes. It does not run PSCAD. Retained measurements keep their
producing probe signs.

## Z-tool component sweeps

`ztool_sweeps.jl` measures component admittances with Z-tool 0.1.52 and compares them with Julia in siemens.
Machines use an AC series probe at the device terminal.
Converters use AC and DC series probes and a topology file for the full DC, d, q matrix.
Passive two-ports use probes at both ends. The IEEE9 case measures the Bus5 admittance with an open shunt probe.
The comparison uses the device-facing sides and rotates measured AC coordinates into the fixed nominal frame.

The measurement copy opens an adjacent ideal source feed at the first integration step after `Tdecoupling`.
The strict time comparator uses the same snapshot time that Z-tool assigns to that parameter.
AC switching opens all three phases. DC switching opens both poles.
The DC breakers use 10 MΩ off resistances to the original pole voltages as a weak common-mode reference.
Their zero closed resistance leaves the startup circuit unchanged.

The manifest lists these sources and excludes their network-facing probe results from comparison.
Sources behind an impedance stay connected.
A scan block replaces the ordinary terminal meter in the measurement copy.
The manifest records that readout change. The ordinary export is unchanged.

The sweep uses sixteen rounded logarithmic tones from 1 Hz to 1 kHz on a 1 Hz base, with two simulations per axis.
Integration and sample steps come from the case specification.
Snapshot and FFT settling times use its comparison windows and any explicit decay-time margin.
The grid-forming MMC cases use solved initialization for slow control states, whose decay time is about 1590 s.

The perturbation is at most 0.0001 pu per tone.
The saved reference limits the predicted combined current departure to 0.004 pu.
Julia stability predictions do not prevent execution. The manifest records each result or execution error.

Each case keeps its own `data/<case>/ztool/` directory, manifest, file hashes, original project, measurement copy, Julia reference and measured files.
Offline reanalysis reads those saved files and checks their hashes.
Per-frequency relative Frobenius errors and their maximum use a 2 % limit for passives and 5 % for machines and converters.
The comparison also applies the suite's entry, phase and normalized-error rules.
The AC line, cable and IEEE9 sweep references use the native dq projection.
Their results do not replace the existing phase-domain comparisons.

Set `POWERIMPEDANCE_PSCAD_CONFIG` for station execution. The runner's Python needs `ztoolacdc==0.1.52`.
These commands prepare the pilots locally, run them on the station and reanalyse stored outputs:

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/ztool_sweeps.jl prepare induction_machine mmc_gfm_lec_compensated
julia --project=test/manual/pscad/validation test/manual/pscad/validation/ztool_sweeps.jl run induction_machine mmc_gfm_lec_compensated --timeout=14400
julia --project=test/manual/pscad/validation test/manual/pscad/validation/ztool_sweeps.jl reanalyse induction_machine mmc_gfm_lec_compensated
```

Replace the case ids with `components` to select every passive and single-device case.
The `estimates` action prints run counts, simulated durations and approximate station times for those cases.
The estimates scale the measured induction-machine rate with integration step and node count, with a factor-two range.
They do not predict scientific acceptance.
The [PSCAD comparator](https://www.pscad.com/webhelp-v502-ol/Master_Library_Models/CSMF/Interpolation_Compatibility/1comparator.htm) changes its output when time exceeds its threshold.

### Stored sweep results

The sweeps use sixteen tones from 1 Hz to 1 kHz.
The table gives maximum relative Frobenius errors in percent and passing counts for those measurements.
Every entry and phase check contributes to the passing count.

Zero-delay MMCs use the suite's recorded one-step reference for the verdict.
Both comparison tables keep the continuous-model errors visible.
Positive-delay converters and machines use their native reference.
`n/a` marks cases that keep their native reference.

| Case | Continuous, % | One step, % | Passing / 16 | Outcome |
|---|---:|---:|---:|---|
| `passive_ac_rlc` | 0.003194 | n/a | 16/16 | Pass |
| `passive_dc_rlc` | 0.002868 | n/a | 16/16 | Pass |
| `ac_ohl_untransposed` | 2.562 | n/a | 0/16 | dq approximation |
| `ac_cable_coaxial` | 11.01 | n/a | 0/16 | dq approximation |
| `dc_cable_ohl` | 0.3031 | n/a | 16/16 | Pass |
| `transformer_yy` | 0.0156 | n/a | 16/16 | Pass |
| `transformer_dyn11` | 0.01546 | n/a | 16/16 | Pass |
| `ieee9_bus_impedance` | 9.333 | n/a | 15/16 | dq approximation |
| `tlc_pq_freq_support` | 1.096 | n/a | 16/16 | Pass |
| `tlc_pf_q` | 1.096 | n/a | 16/16 | Pass |
| `tlc_p_qv` | 1.095 | n/a | 13/16 | time-step limited |
| `tlc_p_vac` | 1.084 | n/a | 15/16 | time-step limited |
| `tlc_vdc_q` | 0.2593 | n/a | 16/16 | Pass |
| `tlc_pq_weak_grid` | 1.096 | n/a | 16/16 | Pass |
| `mmc_pq` | 1.054 | 0.3013 | 16/16 | Pass |
| `mmc_pf_q` | 1.052 | 0.3034 | 16/16 | Pass |
| `mmc_p_qv` | 1.047 | 0.2956 | 16/16 | Pass |
| `mmc_p_vac` | 1.025 | 0.4827 | 16/16 | Pass |
| `mmc_vdc_q` | 0.6815 | 0.3019 | 16/16 | Pass |
| `mmc_pq_weak_grid` | 1.064 | 0.3051 | 16/16 | Pass |
| `mmc_gfm_vsm` | 0.3615 | n/a | 15/16 | model difference near 150 Hz |
| `mmc_gfm_lec_compensated` | 0.1005 | n/a | 16/16 | Pass |
| `mmc_pq_no_energy_control` | 0.7303 | n/a | 15/16 | model difference near 150 Hz |
| `synchronous_machine` | 2.923 | n/a | 16/16 | Pass |
| `mmc_gfm_weak_grid` | n/a | n/a | n/a | Diverged |
| `induction_machine` | 1.885 | n/a | 16/16 | Pass |

Eighteen cases pass, two are time-step limited, and two show a model difference near 150 Hz.
The counts also include three informational dq results and one divergence.
Cases with repeats keep their manifests and comparison tables under `ztool/repeats/`.
The case manifest hashes those files, and reanalysis reads their results and the recorded classification.

The weak-grid MMC reproduces the instability that Julia predicts near +101 ± j360 s⁻¹.
All sixteen measured matrices contain nonfinite entries.
Reanalysis records `diverged`, keeps the files and continues with the other cases.
A missing result receives `no_result` and keeps its diagnostic.

The untransposed cases report `dq approximation`, as in the suite.
Stored phase-domain baselines give negative-sequence current ratios of 6.60 % for the overhead line and 5.36 % for the cable.
The Bus5 voltage ratio is 0.173 %.
These sequences produce 100 Hz images in the nominal 50 Hz dq frame.
Z-tool kept frequency matrices without time traces.

The IEEE9 phase-admittance projection agrees with the sweep to 0.038 %.
Changing projection order leaves 2.52 % and 11.0 % errors for the overhead line and cable.
The stored matrices do not separate image coupling, fitting and frame effects in those two cases.
Their phase-domain suite comparisons keep their existing results.

`tlc_p_qv` is time-step limited.
Longer settling and a 0.5 Hz base leave the 1 Hz error in entry (1,2) at 0.0155 pu.
Halving the integration step from 2.5 to 1.25 us reduces that error to 0.0078 pu.
The entries at 2–3 Hz pass at half step.
The one-step timing of the DC-power calculation causes the error.

`tlc_p_vac` is time-step limited.
Longer settling and a 0.5 Hz base leave the 1 Hz error in entry (1,2) at 0.0127 pu.
Halving the integration step from 2.5 to 1.25 us reduces that error to 0.0064 pu.
The entries at 2–3 Hz pass at half step.
The one-step timing of the DC-power calculation causes the error.

`mmc_gfm_vsm` shows a model difference near 150 Hz.
Dense single-frequency sweeps find entry (3,1) failures at 140–158 Hz.
Entries (3,2) and (1,3) also fail at 150 Hz.
Halving the step changes the 150 Hz error in entry (3,1) from 0.0383 to 0.0376 pu.
The difference in DC-AC coupling is independent of step and settling and centres on 150 Hz, three times the fundamental.

`mmc_pq_no_energy_control` shows a model difference near 150 Hz.
Dense single-frequency sweeps find entry (3,1) failures at 140–158 Hz.
Entries (3,2) and (1,3) also fail at 150 Hz.
Halving the step changes the 150 Hz error in entry (3,1) from 0.0891 to 0.0879 pu.
The difference in DC-AC coupling is independent of step and settling and centres on 150 Hz, three times the fundamental.

`prepare_ztool(...; scan = ZToolScan(...))` writes a separate measurement directory for a repeat.
An explicit frequency list and snapshot time tie the source opening to that sweep.

## Measurement procedure

### Injection and baseline subtraction

Passive two-ports use independent terminal-voltage drives to recover Y. The network impedance
scans use shunt-current injection and recover Z directly from `V=Z*I`; they do not invert a
measured Y. Converter and machine scans inject nominal-frame d/q shunt currents and measure both
the actual terminal-voltage matrix and inward device-current matrix. Recover Y from the full
voltage matrix; a single coupled voltage axis cannot identify a Y column independently.

Each injection has an identical zero-amplitude baseline, including modules, signal paths and
summing junctions. Subtract baseline samples before the DFT. Probe orientation comes from the
saved project's metadata: negate outward terminal current for Y; retain outward source current as
network injection for Z. Passive branch direction is side 1 inward and side 2 outward. Older cable
projects can have both probes inward and require their recorded metadata.

Coherent rectangular windows use `(2/N)*sum(x(t)*cis(-2*pi*f*t))` for peak phasors. No fitted time
shift or window taper is applied to these frequency-response measurements. AC phasors are kV/kA,
so their ratio is S or ohm without extra factors of three or `sqrt(2)`. Departures use
baseline-subtracted samples in the declared windows, with means retained; whole-run turn-on maxima
remain diagnostic.

The passive grid contains 24 tones:
`[1,2,3,4,6,7,10,13,18,24,32,42,50,56,75,100,133,178,237,316,422,562,750,1000] Hz`. Balanced dq
omits 50 Hz, which would create an abc DC sideband. Phase-domain scans retain it because their
tones are physical phase frequencies. Most active scans use this 23-tone grid. Schroeder
cosine phases are `-pi*k*(k-1)/N` in absolute time. Passive tone onset is 0.5 s; active onset is 2
s. Per-tone amplitudes and bases are stored before measurement.

### Sampling and coherent windows

New preparation requires an odd integer `sample_step/time_step`, whole samples and tone/frame
periods in each window, and recorder Nyquist above four times the highest measured abc frequency.
Balanced dq includes the `f+50 Hz` sideband. Ratio 25 is used by the current MMC measurements at
both integration steps. Retained passive/TLC/machine records can use older ratios; their producing
settings remain attached to the data and are not silently rewritten. Re-preparing such an
even-ratio record fails the current sampling check; reuse its verified completed data or define an
odd-ratio experiment before collecting new data.

A finer integration run uses its own baseline and recorder interval. One selected axis repeats at
half amplitude. A matching baseline and that axis repeat at half integration step on the
worst-error frequency and 1000 Hz; when the worst is 1000 Hz, the pair is 750/1000 Hz. Adaptive
windows contain whole common periods. Selection is saved before execution and reused on retry.

### Julia references and the interface step

Balanced elements use native dq/differential-DC references. Two-port references call
`eval_abcd(element.element_model,j2*pi*f)` and `abcd_to_y`. The phase-domain references for asymmetric lines/cables and IEEE9
include zero sequence and the physical conductor order.
IEEE9 preserves each component and terminal-to-bus incidence, clamps ideal-source buses and
imposes floating YY-neutral KCL. The full 6x6 transfer comes from six independent drives; Bus1 and
Bus5 local 3x3 blocks are scored separately. Bus1's ideal-source Z=0 tests clamping.

The informational `transformation_dq` projection evaluates phase ABCD at `s +/- j*omega0`.
Untransposed circuits retain couplings and ±2ω0 sidebands that a fixed dq LTI model omits. This
projection cannot change phase-domain comparison status. Dyn11 uses one global 50 Hz frame at both
ports; its native Y already contains the vector-group rotation. A local secondary frame would
transform both rows and columns with `T=diag(I,R)`.

Zero-delay converters use a one-step (discrete) model with exact `exp(-s*h)` **inside modulation
feedback**, including native carrier corrections. It does not rotate terminal Y after solving.
Coupled references assemble the full circuit with exported grid/passive values and eliminate the
same internal nodes. Positive-delay models and the machine retain their native references. Errors
against the continuous model remain visible even when the one-step (discrete) model passes.

For current drive at step h, the predicted column is `P_h = gamma_h * diag(Ibase/Vbase,
Ibase/Vbase, 1, 1) * [v_h; i_h]`, where `v_h = (Y_h + inv(Zgrid)) \ e_axis`, `i_h = Y_h * v_h`,
and `gamma_h = exp(s*h)/cos(2π*50*h)`. Exported DC resistances supply load reduction; weak-grid
cases retain their actual grid R/L. A DC-clamped AC subblock cannot replace a
converter-plus-DC-load reference.

### KCL and readout timing

Baseline-subtracted inward device plus grid currents, divided by recorded drive on its driven
axis, must reproduce `gamma_h` within 1e-6 relative. Coupled scans include every device, grid and
shunt branch at each port, coordinate, tone and window in main, amplitude and half-step records.
Undriven coordinates use the full transported dq vector: `exp(s*h)*[cos(w0*h) sin(w0*h);
-sin(w0*h) cos(w0*h)]*Idrive`. A scalar timing factor on an undriven coordinate leaves a spurious
`w0*h` residual. Timing cancels in Y; direct Z includes injection-readout transport. No measured
column is shifted to make this check pass.

For zero-delay devices, the residual step-size check subtracts the predicted known step effect
only in the numerator:

```text
dR = (M_half - P_half) - (M_h - P_h)
frobenius_change = norm(dR) / max(norm(M_h), 0.1)
entry_change = maximum(abs.(dR) ./ max.(abs.(M_h), 0.02))
passed = frobenius_change <= 0.01 && entry_change <= 0.01
```

Main and half-step reproduction each also meet the 1 % column-change rule. Raw step changes and
residual-normalized diagnostics remain recorded. The selected denominator is the measured main
response, not its small unexplained residual. The Y comparison with the one-step (discrete) model,
KCL, amplitude and window checks must pass independently.

Coupled circuits select the step-size rule for each block. A zero-delay converter uses the
residual step-size check and must meet both reproduction checks. Machines and converters with
positive delays use the raw step change. Aggregate and direct-Z blocks use the residual check
when the circuit reference reproduces both measured columns within 1 %; otherwise they use the
raw step change. Each block records `step_reference` and `step_reference_reason`. Reproduction
errors remain diagnostic when the raw rule applies.

## Checks and tolerances

The suite reports operating-point, frequency-response, time-domain response and instability-growth
checks. The comparison terms have these meanings:

- The **continuous model** is Julia's model without the additional EMT interface
  step. Configured converter delays remain part of that model.
- The **one-step (discrete) model** adds exact one-step transport inside the
  modulation feedback of each zero-delay converter, with its carrier correction.
  Other devices and configured positive delays retain their native equations.
- A **repeat** is a separate run with half the injection amplitude or half the
  integration step, using the corresponding baseline and coherent windows.
- The **raw step change** is the measured response difference between integration
  steps, normalized by the main response and the stated floors.
- The **residual step-size check** compares that change after subtracting the
  change predicted by the one-step (discrete) model. It also requires the
  independent response-reproduction and KCL/readout checks.

A result passes only when its model comparison and independent measurement checks pass. Normalized
Frobenius error divides matrix-error norm by reference norm with its floor. Entry and phase checks
apply separately; a passing matrix norm cannot cancel a failing entry. Both norm and entry changes
must meet the step-size limit; the catalogue reports the maximum-entry change.

| Check | Limit or required condition |
|---|---|
| Operating point | `compare_operating_point` limits voltage error to 1 %, relative AC angle error to 1 degree and current error to 2 %. Device P/Q error divided by MVA rating is ≤0.01; speed error is ≤1e-3 pu |
| Passive frequency response | Complex error ≤2 %; phase ≤2 degrees for reference entries ≥0.02 pu |
| Active/coupled frequency response | Complex error ≤5 %; phase ≤3 degrees for reference entries ≥0.02 pu |
| Error floors | 0.02 pu per entry; 0.1 for Frobenius norms |
| Input-matrix conditioning | ≤100 |
| Baseline drift | ≤1e-3; phase-domain checks include window means and the 50 Hz phasor |
| Adjacent-window change | ≤1 % in required norm/entry checks |
| Drive amplitude | Error ≤1 % |
| Clamped voltage departure | ≤1e-6 pu, when applicable |
| Settled input/output departure | ≤0.01 pu |
| Half-amplitude repeat | Change ≤2 %, with the same floors |
| Half-step repeat | Raw step change ≤1 % for the continuous model; residual step-size check ≤1 % and reproduction ≤1 % for the one-step (discrete) model |
| KCL/readout | Driven timing discrepancy ≤1e-6 relative; undriven residual on the declared drive scale |
| Resolved resonance | Both peaks/dips bracketed, both half-power crossings, ≥5 in-band samples and ≥6 intervals across width; centre error ≤max(1 % of Julia centre, one local interval), width error ≤10 % |
| Lumped active-network stability screen | Records the closed right-half-plane count on the 6001-point 0.01 Hz–100 kHz contour at Re(s)=1e-6/s and all finite descriptor roots; reports whether the count is zero and Re(λ)<-1e-7/s. |
| Time-domain waveform | Per signal RMS error ≤5 %, peak error ≤10 %, scalar gain error ≤5 %; half-amplitude RMS/peak/gain changes ≤2 % |
| Ringdown mode | Frequency error ≤2 %, relative damping-ratio ζ error ≤10 %; report decay α separately |
| Instability growth | Frequency error must be ≤2 %, growth error ≤`max(0.10*abs(Re(λ)),0.5/s)` and departure ≤0.01 pu in the fixed fit interval. |
| Ringdown extraction | Converged interior fit, relative residual ≤0.10, relative standard errors ≤2 % frequency and ≤10 % ζ |
| Frequency-to-time inversion | Double/quadruple padded predictions agree within 1e-4 relative norm |
| Native measurement build | passive elements, single devices and coupled circuits: fewer than 100 live nodes. Complete systems: fewer than 200, one subsystem |

The lumped descriptor retains every device and passive storage state and checks its Schur response
against native admittances. Complete-network stability can include a stabilized open-subsystem
integrator or right-half-plane pole. Converter-only poles are insufficient. Distributed cables
require native finite-contour/root checks; these do not enumerate their infinite spectrum.

The resonance rule applies only inside either resolved half-power band. Elsewhere ordinary
complex/magnitude/phase rules apply. Point errors stay recorded inside the band. Unresolved curves
retain the ordinary rule.

## Fixture catalogue

The entries report maximum normalized Frobenius errors and maximum-entry step changes as
percentages or dimensionless ratios, next to their limits. Displayed values use two or three
digits of precision. Each fixture's manifest gives exact settings and results. Corrected probe-orientation
results take precedence over retained uncorrected analysis. A passing comparison with the one-step
(discrete) model does not imply a pass with the continuous model. Native data are not distributed
with the package.

### Passive elements and network

All passive main runs use 2 us integration, 10 us recording and 1 us half-step repeats. Voltage
bases are solved phase-peak kV; current bases are `2000/(3*Vbase)` kA on 1000 MVA total. DC uses
pole-to-pole kV and `1000/Vbase` kA.

#### AC RLC, RL two-source circuit (`passive_ac_rlc`)

The two-source RL circuit tests dq coupling and loss through its 2x2 admittance matrix. The run
lasts 3 s, with windows [1,2) and [2,3) s.

The frequency-response check passes against the continuous model: the maximum error is 0.00131 %
(limit 2 %). The operating-point check, half-amplitude repeat and raw step change also pass. The
balanced circuit does not test asymmetric phase couplings.

#### DC two-terminal RLC (`passive_dc_rlc`)

The two-terminal DC RLC circuit tests charging, pole bases and current directions through its
differential 2x2 admittance matrix. The run lasts 3 s, with windows [1,2) and [2,3) s.

The frequency-response check passes against the continuous model: the maximum error is 0.00131 %
(limit 2 %). The operating-point check, half-amplitude repeat and raw step change also pass. The
retained uncorrected current signs fail the comparison; analysis must use the corrected saved
probe signs.

#### AC overhead line, untransposed phases (`ac_ohl_untransposed`)

The untransposed overhead line tests earth return and propagation through its abc 6x6 admittance
matrix. The run lasts 7 s, with windows [5,6) and [6,7) s.

The frequency-response check passes against the continuous model: the maximum error is 0.034 %
(limit 2 %). The operating-point check, half-amplitude repeat and raw step change also pass. Early
windows contain decaying DC offsets. The dq approximation is informational.

#### AC coaxial cable, eliminated internal conductors (`ac_cable_coaxial`)

The coaxial cable tests sheath elimination and earth return through its abc 6x6 admittance matrix.
The run lasts 22 s, with windows [20,21) and [21,22) s.

The frequency-response check passes against the continuous model: the maximum error is 0.843 %
(limit 2 %). The operating-point check, half-amplitude repeat and raw step change also pass. The
side-2 current sign follows the producing project. Earth return uses exp(γ_E) and each cable’s own
depth; fitting error is a separate contribution.

#### DC cable and overhead line in series (`dc_cable_ohl`)

The series cable/overhead-line circuit tests mixed-media propagation and DC loss through its
differential 2x2 admittance matrix. The run lasts 8 s, with windows [6,7) and [7,8) s.

The frequency-response check passes against the continuous model: the maximum error is 0.303 %
(limit 2 %). The operating-point check, half-amplitude repeat and raw step change also pass. The
cable fit has a 260 s pole. Agreement in the measured band does not constrain its true-DC
extrapolation.

#### YY transformer, loaded secondary (`transformer_yy`)

The loaded YY transformer tests voltage ratio and winding loss through its dq 4x4 admittance
matrix. The run lasts 3 s, with windows [1,2) and [2,3) s.

The frequency-response check passes against the continuous model: the maximum error is 0.0118 %
(limit 2 %). The operating-point check, half-amplitude repeat and raw step change also pass. A
phase reference must retain floating winding neutrals and near-ideal terms. Meter placement can
affect the native solution.

#### Dyn11 transformer, loaded secondary (`transformer_dyn11`)

The loaded Dyn11 transformer tests the 30 degree secondary lead and winding loss through its dq
4x4 admittance matrix. The run lasts 3 s, with windows [1,2) and [2,3) s.

The frequency-response check passes against the continuous model: the maximum error is 0.0122 %
(limit 2 %). The operating-point check, half-amplitude repeat and raw step change also pass. The
reference already includes the vector-group rotation; a secondary-frame change must transform
voltage and current together.

#### IEEE9, local bus impedance (`ieee9_bus_impedance`)

The IEEE9 circuit tests network reduction and resonance through separate abc 3x3 local impedance
matrices at Bus1 and Bus5. Its coarse run lasts 3 s, with windows [1,2) and [2,3) s. The
operating-point check, half-amplitude repeat and raw step change pass.

The continuous model fails the ordinary point comparison: the coarse maximum error is 3.35 % and
the refined maximum is 3.88 % (limit 2 %). A separate 312–322 Hz scan uses 0.25 Hz spacing, [2,6)
and [6,10) s windows, 64 us recording and 2/1 us integration.

The Julia and PSCAD resonance centres are 316.94 and 316.87 Hz. Their difference is 0.022 % (limit
1 % or one local interval), and the widths 3.296 and 3.294 Hz differ by 0.072 % (limit 10 %). All
126 in-band rows pass the centre/width rule. Outside that band, shoulder errors of 2.0–2.6 % still
fail the 2 % limit; seven entry rows also fail at 237, 562 and 1000 Hz. Resonance agreement does
not override those point failures.

### Single devices against a Thevenin grid

All AC grids have X/R=10 at 50 Hz. Stiff-grid SCR is 8 at rated external voltage; weak-grid SCR is
2.5. The ideal source lies behind series R/L. TLC rating is 100 MVA, 220 kV LL RMS and 640 kV DC;
stiff-grid R/L are 6.02 ohm/0.192 H. Weak-grid R/L are 19.3 ohm/0.613 H. TLC P/Q PI is 0.04/40,
Vdc PI 5/5, P-f support K=5 with cutoff 2 rad/s, Q-V K=20 with cutoff 100 rad/s, VAC PI 0/100 with
`NoFilter`, and modulation delay 200 us Padé 3/3.

Grid-following MMC rating is 1000 MVA, 333/380 kV converter/external LL RMS, 800 kV DC, ratio
333/380, 400 submodules per arm, 50 mH/1.07 ohm arms and 10 mF submodule capacitance. Stiff-grid
R/L are 1.80 ohm/0.0572 H; weak-grid R/L are 5.75 ohm/0.183 H. P/Q PI is 0.1/31.4159, Vdc PI 5/15,
TEC 1.386/29.70, ZSCC/CCSC 0.1048/48.1914, PLL 0.28/12.5664 and OCC 0.7691/522.7654. The standard
MMC modulation has zero delay. Support/VAC blocks use the gains above.

Each entry states main/half integration steps, main recorder interval, main windows and per-tone
current amplitude. Half-amplitude is exactly one half; new half-step recorder intervals preserve
ratio 25 at their own step. The original TLC frequency-support circuit already includes the P-f
lag, so its separate P-f entry deliberately repeats that physics. Retained operating-point and
half-amplitude checks pass for the completed single-device entries; a failing frequency-response
check still prevents an overall pass.

#### TLC, P/Q and frequency support, stiff grid (`tlc_pq_freq_support`)

The TLC connects a direct ideal DC source to the stiff AC grid with a 70 MW/5 MVAr request. It
tests P/Q control, PLL/OCC, measurement filters and delayed modulation. The run uses 2.5 us
integration, a 1.25 us half-step repeat and 20 us recording. It lasts 10 s, with windows [8,9) and
[9,10) s and 5.00e-5 pu current per tone.

The frequency-response check fails against the continuous model; the maximum norm error is 1.07 %
(limit 5 %). The raw step change passes at 0.882 % (limit 1 %). At 2.5 us, the continuous model
fails its point comparison despite a passing matrix norm; entry and phase checks remain
independent.

The finer variant uses the same key with suffix `-1p25us`, 1.25/0.625 us integration and unchanged
recording, windows and amplitude. Its continuous model comparison passes at 0.534 % (limit 5 %),
and its raw step change passes at 0.441 % (limit 1 %). The operating-point check and
half-amplitude repeat also pass.

#### TLC, P-f/Q, stiff grid (`tlc_pf_q`)

The TLC uses the same physical controls and 70 MW/5 MVAr request as the preceding circuit. It
tests explicit selection of P-f support. The run uses 2.5 us integration, a 1.25 us half-step
repeat and 20 us recording. It lasts 10 s, with windows [8,9) and [9,10) s and 5.00e-5 pu current
per tone.

The frequency-response check fails against the continuous model; the maximum norm error is 1.07 %
(limit 5 %). The raw step change passes at 0.882 % (limit 1 %). Its passing operating point and
raw step change do not override the failed point comparison.

#### TLC, P/Q-V, stiff grid (`tlc_p_qv`)

The TLC supplies 70 MW with Q-V support and P control without frequency support; solved Q is -1.37
MVAr. It tests the voltage-support lag. The run uses 2.5 us integration, a 1.25 us half-step
repeat and 20 us recording. It lasts 10 s, with windows [8,9) and [9,10) s and 5.00e-5 pu current
per tone.

The frequency-response check passes against the continuous model; the maximum norm error is 1.07 %
(limit 5 %). The raw step change passes at 0.896 % (limit 1 %). The DC source clamps voltage, so
this circuit does not test DC-load feedback.

#### TLC, P/VAC, stiff grid (`tlc_p_vac`)

The TLC supplies 70 MW while its VAC loop holds terminal voltage at 1.00 pu; solved Q is -3.91
MVAr. It tests VAC initialization from solved Q. The run uses 2.5 us integration, a 1.25 us
half-step repeat and 20 us recording. It lasts 10 s, with windows [8,9) and [9,10) s and 5.00e-5
pu current per tone.

The frequency-response check passes against the continuous model; the maximum norm error is 1.05 %
(limit 5 %). The raw step change passes at 0.901 % (limit 1 %). The VAC loop uses NoFilter;
controller-local VAC filters remain unsupported by export.

#### TLC, Vdc/Q, resistive DC load (`tlc_vdc_q`)

The TLC supplies a 5.85 kohm differential DC load, implemented as two 2.93 kohm pole-to-ground legs,
and absorbs 70.0 MW from AC. It tests Vdc control with DC-load feedback. The run uses 0.625 us
integration, a 0.3125 us half-step repeat and 20 us recording. It lasts 10 s, with windows [8,9)
and [9,10) s and 5.00e-5 pu current per tone.

The frequency-response check passes against the continuous model; the maximum norm error is 0.888
% (limit 5 %). The raw step change passes at 0.578 % (limit 1 %). DC voltage is free after
pre-charge releases at 0.2 s. The reference must include the resistor rather than clamp the
converter’s DC port.

At 2.5 us, the 1000 Hz q-d magnitude error is 7.27 % (limit 5 %), while the matrix error is 3.28 %
(limit 5 %). At 1.25 us, the half-step repeat changes 0.532 % in norm and 1.11 % per entry (limit
1 %), so it fails. The 0.625/0.3125 us result above passes.

#### TLC, P/Q, weak grid (`tlc_pq_weak_grid`)

The TLC uses the 70 MW/5 MVAr request against an AC grid with SCR 2.5. It tests the same controls
against the weaker grid impedance. The run uses 2.5 us integration, a 1.25 us half-step repeat and
20 us recording. It lasts 10 s, with windows [8,9) and [9,10) s and 5.00e-5 pu current per tone.

The frequency-response check passes against the continuous model; the maximum norm error is 1.07 %
(limit 5 %). The raw step change passes at 0.864 % (limit 1 %). Reference calculations must retain
that weak-grid impedance.

#### Grid-following MMC, P/Q, stiff grid (`mmc_pq`)

The MMC supplies 600 MW/200 MVAr with an ideal 800 kV DC clamp. It tests TEC, ZSCC and CCSC with
zero configured modulation delay. The run uses 2.5 us integration, a 1.25 us half-step repeat and
62.5 us recording. It lasts 32 s, with windows [16,24) and [24,32) s and 5.44e-4 pu current per
tone.

The frequency-response check passes against the one-step (discrete) model with maximum error 0.113
% (limit 5 %). The continuous model fails the point comparison; its maximum norm error is 5.69 %
(limit 5 %). The raw step change fails, but the residual step-size check passes at 0.080 % (limit 1
%). One-second windows fail near 42 Hz; the stored eight-second windows pass the independent
window check.

#### Grid-following MMC, P-f/Q, stiff grid (`mmc_pf_q`)

The MMC supplies 600 MW/200 MVAr with P-f support gain 5 and cutoff 2 rad/s. It tests slow
frequency-support dynamics with zero configured modulation delay. The run uses 2.5 us integration,
a 1.25 us half-step repeat and 62.5 us recording. It lasts 32 s, with windows [16,24) and [24,32)
s and 5.44e-4 pu current per tone.

The frequency-response check passes against the one-step (discrete) model with maximum error 0.117
% (limit 5 %). The continuous model fails the point comparison; its maximum norm error is 5.69 %
(limit 5 %). The raw step change fails, but the residual step-size check passes at 0.0742 % (limit
1 %). Pole-based settling estimates cannot replace measured adjacent-window changes.

#### Grid-following MMC, P/Q-V, stiff grid (`mmc_p_qv`)

The MMC supplies 600 MW with Q-V support; solved Q is 30.7 MVAr. It tests converter-side
voltage-reference scaling through the transformer. The run uses 2.5 us integration, a 1.25 us
half-step repeat and 62.5 us recording. It lasts 32 s, with windows [16,24) and [24,32) s and
5.36e-4 pu current per tone.

The frequency-response check passes against the one-step (discrete) model with maximum error 0.195
% (limit 5 %). The continuous model fails the point comparison; its maximum norm error is 5.75 %
(limit 5 %). The raw step change fails, but the residual step-size check passes at 0.0603 % (limit
1 %). The continuous model retains a failed point comparison even when the one-step (discrete)
model passes.

#### Grid-following MMC, P/VAC, stiff grid (`mmc_p_vac`)

The MMC supplies 600 MW while regulating terminal voltage at 1.00 pu; solved Q is -37.3 MVAr. It
tests VAC control through the transformer. The run uses 2.5 us integration, a 1.25 us half-step
repeat and 62.5 us recording. It lasts 32 s, with windows [16,24) and [24,32) s and 5.58e-4 pu
current per tone.

The frequency-response check passes against the one-step (discrete) model with maximum error 0.156
% (limit 5 %). The continuous model fails the point comparison; its maximum norm error is 5.62 %
(limit 5 %). The raw step change fails, but the residual step-size check passes at 0.150 % (limit 1
%). The VAC equilibrium must use solved Q; the requested Q alone does not determine its integral
state.

#### Grid-following MMC, Vdc/Q, resistive DC load (`mmc_vdc_q`)

The MMC supplies a 600 MW DC load with differential resistance 1.07 kohm, implemented as two 533 ohm
legs. It absorbs 603 MW from AC and tests DC control without a permanent voltage source. The run
uses 1.25 us integration, a 0.625 us half-step repeat and 31.25 us recording. It lasts 24 s, with
windows [8,16) and [16,24) s and 5.25e-4 pu current per tone.

The frequency-response check passes against the one-step (discrete) model with maximum error 0.12
% (limit 5 %). The continuous model fails the point comparison; its maximum norm error is 3.15 %
(limit 5 %). The raw step change fails, but the residual step-size check passes at 0.0361 % (limit
1 %). Pre-charge releases at 0.2 s. The one-step (discrete) model must include both exported pole
resistances.

#### Grid-following MMC, P/Q, weak grid (`mmc_pq_weak_grid`)

The MMC supplies 600 MW/200 MVAr against an AC grid with SCR 2.5. It tests weak-grid conditioning
and the one-step (discrete) model. The run uses 2.5 us integration, a 1.25 us half-step repeat and
62.5 us recording. It lasts 24 s, with windows [8,16) and [16,24) s and 1.51e-4 pu current per
tone.

The frequency-response check passes against the one-step (discrete) model with maximum error 0.112
% (limit 5 %). The continuous model fails the point comparison; its maximum norm error is 5.69 %
(limit 5 %). The raw step change fails, but the residual step-size check passes at 0.133 % (limit
1 %). The residual step-size check uses the measured response as its denominator; dividing by the
small unexplained residual overstates the change.

#### Grid-forming MMC, VSM and CCVI (`mmc_gfm_vsm`)

The 1060 MVA MMC connects 320/400 kV AC and 640 kV DC circuits at 742 MW/0 MVAr. Its VSM and CCVI,
with TEC/ZSCC/CCSC and 200 us Padé 5/5 modulation, test grid-forming synchronization. The run uses
2.5 us integration, a 1.25 us half-step repeat and 62.5 us recording. It lasts 10 s, with windows
[8,9) and [9,10) s and 8.53e-4 pu current per tone.

The frequency-response check passes against the continuous model; the maximum norm error is 0.393
% (limit 5 %). The raw step change passes at 0.787 % (limit 1 %). The slow OCC poles have a decay
time of about 1590 s. These records rely on solved initialization and do not establish generic
startup settling.

#### Grid-forming MMC, leg-energy control and compensated modulation (`mmc_gfm_lec_compensated`)

The same 1060 MVA plant uses VSM/CCVI, Sigma/Delta-energy PI gains 0.5544/5.94 and CCC. It tests
the corrected triplen frame and physical per-arm capacitor division. The run uses 1 us
integration, a 0.5 us half-step repeat and 25 us recording. It lasts 10 s, with windows [8,9) and
[9,10) s and 8.55e-4 pu current per tone.

The frequency-response check passes against the continuous model; the maximum norm error is 0.116
% (limit 5 %). The raw step change passes at 0.314 % (limit 1 %). The 10 us case diverges, while
the measured 1 us case remains settled. Physical arm division retains harmonics absent from
Julia’s truncated harmonic solve.

#### MMC, P/Q with disabled total-energy and zero-sequence control (`mmc_pq_no_energy_control`)

The 1000 MVA MMC uses 333/380 kV AC, 640 kV DC and 30 mH arms at 100 MW/100 MVAr. It tests
disabled TEC/ZSCC while CCSC remains enabled. The run uses 2.5 us integration, a 1.25 us half-step
repeat and 62.5 us recording. It lasts 10 s, with windows [8,9) and [9,10) s and 7.06e-4 pu
current per tone.

The frequency-response check passes against the continuous model; the maximum norm error is 0.395
% (limit 5 %). The raw step change passes at 0.788 % (limit 1 %). Its clamped DC circuit does not
establish stability of the complete P2P link.

#### Synchronous machine, AVR, governor and steam turbine (`synchronous_machine`)

The 1000 MVA/380 kV machine supplies 900 MW with its native rt/lt branch, AVR, governor and steam
turbine. It tests machine admittance in SI units and slow electromechanical dynamics. The run uses
1.25 us integration, a 0.625 us half-step repeat and 20 us recording. It lasts 66 s, with windows
[62,64) and [64,66) s and 5.00e-5 pu current per tone.

The frequency-response check passes against the continuous model; the maximum norm error is 1.49 %
(limit 5 %). The raw step change passes at 0.895 % (limit 1 %). The slowest mode has a decay time
of 5.06 s. At 2.5 us, the raw step change was 1.81 % (limit 1 %); the finer stored result passes.

#### Induction machine with constant load torque (`induction_machine`)

The circuit is `PSCADFixtures.im_network()`: a 1000 MVA/220 kV induction machine behind a
0.01 ohm resistor and a 220 kV ideal source. The load torque is constant at 0.9 pu and the
inertia constant is 4 s. Element names are `DUT`, `Grid` and `G3`. The models and connections match
the reference circuit. Julia gives 916.166 MW, 881.241 MVAr and speed 0.987551129 pu.

The measurement tests stator-current, rotor-flux and speed dynamics through the full 2x2 terminal
admittance. It uses inward machine current and measured terminal voltage in fixed nominal 50 Hz
dq coordinates, with `d=cos(theta)` and `q=sin(theta)`. `NetworkBuilder.get_y` supplies the SI
reference at the solved machine setpoint. Phase-peak bases are 179.629 kV and 3.71135 kA.
Their ratio gives the admittance base `1000/220^2 = 0.0206612 S`. A kA/kV ratio is S.

The 29-tone grid adds 0.5, 1.5, 48, 49, 51 and 52 Hz to the usual active grid. It spans the
mechanical response and samples the 49.95 Hz stator-current mode. The grid excludes 50 Hz. The
complete-circuit slowest decay is 6.67984 per second, with a 0.149704 s time constant.

Tone onset is 2 s, with coherent windows [6,8) and [8,10) s in a 10 s run. The first window starts 26.7
decay times after tone onset. The pole estimate sizes the run. Measured drift and window checks
test validity.

Integration is 1 us, with a 0.5 us half-step repeat. Recorder intervals are 25 us and 12.5 us,
respectively. Both steps use an odd ratio of 25 and coherent two-second windows.

Per-tone shunt current is 0.01 pu, or 37.1135 A. The 0.01 ohm grid gives a small terminal voltage
response. The native response bounds the combined voltage and machine-current departures by
5.99e-5 pu and 4.54e-4 pu. Half amplitude is 0.005 pu.

The suite checks baseline subtraction, both drive axes, window agreement, half amplitude, half
step and baseline-subtracted KCL. Preparation records the stability screen. A failed screen
still permits preparation and execution.

Four main-step runs and two half-step runs need about 80 million integration steps. The
workflow budget is 1800 s:

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl induction_machine --timeout=1800
```

The independent Z-tool comparison is an offline diagnostic. The data span 80 frequencies from
1 to 499.5 Hz. The global relative Frobenius error is 0.0329212%. The largest per-frequency
matrix error is 0.487774%, at 499.5 Hz. The largest absolute entry difference is 2.70111e-4 S.

The data use the same dq order and SI units, without a further rotation or scale factor. Set
`im_data` to the author's `IM_Ztool_1us#Y_AC#-1#.txt` file to reproduce the comparison:

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/validation/crosscheck_induction_machine.jl "$im_data" /tmp/im_validation_crosscheck
```

The frequency-response check passes against the continuous model. The maximum norm error is
1.88 % (limit 5 %), at 1000 Hz. The dimensionless half-step change passes at 3.2e-5 (limit 1 %).
The half-amplitude change passes at 4.5e-7 (limit 2 %). Baseline drift is 8.4e-11. KCL passes.

#### Grid-forming MMC, weak grid (`mmc_gfm_weak_grid`)

Julia's complete-network roots for the 1060 MVA VSM/CCVI circuit at SCR 2.5 are
+101 ± j360 s⁻¹. The circuit was not run in PSCAD. The screen result is recorded with the fixture and
reported during preparation.

### Coupled circuits

Individual device Y retains each device's original phase-peak bases. Aggregate Y and direct Z use
the declared circuit base. Every measurand has independent comparison, window, amplitude, step and
KCL checks. A passing aggregate cannot cancel an individual-device failure. The recorded matrices
include full cross blocks.

Unless stated otherwise, main runs use 2.5/1.25 us integration, ratio 25, 32 s duration and
[16,24), [24,32) s windows. Local scans retain these windows, both drives, their own baseline and
amplitude/half-step repeats. Reported maxima below are taken across each group's required
measurands.

#### Two TLCs, P-f/Q and P/Q-V, shared bus (`two_tlc_shared_bus`)

The TLCs share an AC bus behind a 6.02 ohm/0.192 H grid and retain separate 640 kV DC clamps.
Their aggregate base is 200 MVA/220 kV, and each device keeps its 100 MVA base. The circuit tests
individual/aggregate admittance and direct impedance with both 200 us delays. The coarse scan
injects 4.51e-4 pu current per tone.

The coarse frequency-response comparisons pass against the continuous model, with maximum error
1.53 % (limit 5 %). The half-amplitude repeat and raw step change pass.

Both DC voltages are clamped, so this circuit does not test DC-side coupling.

#### Two grid-following MMCs, P/Q and P/Q-V, shared bus (`two_mmc_shared_bus`)

The MMCs share an AC bus behind a 1.80 ohm/0.0572 H grid and retain separate 800 kV DC clamps. The
grid has SCR 4 on the combined 2000 MVA/380 kV base. The circuit tests interaction between two
zero-delay converters. The coarse scan injects 2.56e-4 pu current per tone.

The coarse frequency-response comparisons pass against the one-step (discrete) model, with maximum
error 0.193 % (limit 5 %). The half-amplitude repeat and residual step-size check pass.

The continuous model fails individual/aggregate admittance comparisons, although its
direct-impedance comparison passes.

#### Grid-forming and grid-following MMC, shared bus (`mmc_gfm_gfl_shared_bus`)

The MMCs share a bus behind a 0.872 ohm/0.0278 H grid and retain separate 640/800 kV DC clamps.
The 2060 MVA/380 kV circuit tests mixed synchronization and model delays. The coarse scan injects
6.92e-4 pu current per tone.

The coarse frequency-response comparisons pass against the one-step (discrete) model, with maximum
error 0.316 % (limit 5 %). The half-amplitude repeat and residual step-size check pass.

The GFM retains its 1060 MVA/400 kV nameplate and 200 us delay; only the zero-delay GFL receives
the extra interface step. The continuous model fails the GFL admittance comparison. Slow GFM
filters rely on solved initialization.

#### MMC behind a lumped pi line (`mmc_pi_line`)

The MMC connects to the remote end of a pi line with series R=2 ohm, L=20 mH and C=2 uF to ground
at each end. An SCR-8 grid supplies the near end on a 1000 MVA/380 kV base. The circuit tests
remote device admittance, aggregate line/device admittance and direct near-port impedance. The
coarse scan injects 7.12e-4 pu current per tone.

The coarse frequency-response comparisons pass against the one-step (discrete) model, with maximum
error 0.123 % (limit 5 %). The half-amplitude repeat and residual step-size check pass.

The local frequency-response comparisons pass against the one-step (discrete) model, with maximum
error 0.122 % (limit 5 %). The half-amplitude repeat and residual step-size check pass.

Remote terminal voltage/current checks remain independent. The local scan uses 43 tones from 357
to 378 Hz at 0.5 Hz spacing and 2.44e-5 pu per tone. The one-step (discrete) model gives a local-Z
centre of 366.9 Hz and width 5.73 Hz; the continuous model gives 367.2 Hz and 4.83 Hz.

#### TLC behind a step-up transformer and line (`tlc_transformer_line`)

The TLC connects to the grid through a step-up transformer and a line. This circuit is intended to
test converter interaction with the transformer and line.

The recorded transformer magnetising-flux decay time is about 21 s, with a proposed run duration
of 390 s. The circuit was not run in PSCAD.

#### Synchronous machine and MMC, shared bus (`machine_mmc_shared_bus`)

The machine and MMC share a bus supplied by an SCR-8 grid on a 2000 MVA/380 kV aggregate base.
Each device keeps its 1000 MVA base. The circuit tests individual/aggregate admittance and direct
impedance during machine/converter interaction. The coarse scan injects 6.71e-4 pu current per
tone.

The coarse frequency-response comparisons pass against the one-step (discrete) model, with maximum
error 1.51 % (limit 5 %). The run uses 1.25/0.625 us integration, recorder ratio 25, 80 s duration
and [64,72), [72,80) s windows. Re-analysis of the retained native runs gives these step-size
results; both norm and entry changes must be at most 1 %.

| Block | Applied rule | Norm change | Entry change | Result |
|---|---|---|---|---|
| Machine C1 | Raw step change; no zero-delay modulation | 0.342 % | 1.117 % | Fail |
| MMC C2 | Residual step-size check; zero-delay modulation | 0.133 % | 0.377 % | Pass |
| Aggregate Y | Raw step change; main reference reproduction exceeds 1 % | 0.342 % | 1.34 % | Fail |
| Direct Z | Residual step-size check; both reference reproductions pass | 0.133 % | 0.377 % | Pass |

The half-amplitude repeats pass. The fixture fails the step-size limit, with valid measured
columns. The recorded integration steps are 1.25/0.625 us. The standalone machine passed at 0.90 %. A finer repeat would require 80 s runs at 0.3125 us.
The re-analysis record and per-block columns are under `data/machine_mmc_shared_bus/`. Native evidence is retained
separately.

#### Two MMCs coupled by a distributed DC cable (`two_mmc_dc_cable`)

Vdc/Q and P/Q MMCs connect through a 25 km DC cable and independent SCR-8 AC grids. Each port uses
a 1000 MVA/380 kV base. The circuit tests the full 4x4 AC admittance/impedance matrices and two
2x4 drive-to-DC voltage/current transfers. The coarse scan injects 5.45e-4 pu current per tone.

The coarse frequency-response comparisons pass against the one-step (discrete) model, with maximum
error 0.829 % (limit 5 %). The half-amplitude repeat and residual step-size check pass. The run
uses 1.25/0.625 us integration and recorder ratio 25. Both DC buses release pre-charge at 0.2 s
and retain two 10 Mohm pole references each. Native finite contours through 1 MHz locate a
rightmost root at -3.00/s but do not enumerate the distributed infinite spectrum. Sub-floor cross
entries receive absolute-floor checks only.

#### MMC with a damped series-RC shunt (`mmc_rc_shunt`)

The P/Q MMC retains its SCR-8 grid and DC clamp, with a series R=2 ohm/C=5 uF shunt per phase. The
1000 MVA/380 kV circuit tests device/aggregate admittance and direct impedance at two resonances.
The coarse scan injects 4.74e-4 pu current per tone.

The coarse frequency-response comparisons pass against the one-step (discrete) model, with maximum
error 0.118 % (limit 5 %). The half-amplitude repeat and residual step-size check pass.

The local frequency-response comparisons pass against the one-step (discrete) model, with maximum
error 0.192 % (limit 5 %). The half-amplitude repeat and residual step-size check pass.

The local scan uses 39 tones at 232–260.5 Hz and 334–361 Hz, spaced by 1.5 Hz, at 5.91e-5 pu per
tone. Both disjoint bands pass the resonance rule. Local half-step filenames need the compact
frequency digest described below.

### Complete systems

The redesigned P2P passes its operating-point comparison. The P2P with AC grids fails only
its c2 arm-capacitor voltage sums, with 1.1–1.3 % error against 1 %. Both measured systems
have untransposed AC lines. IEEE14 has 216 live nodes, above the educational licence's
200-node limit, and was not run in PSCAD. No system-level impedance comparison passes.

System scans inject four independent currents, `[p1_d,p1_q,p2_d,p2_q]`, to measure direct
network Z. The full 4x4 matrix, both local 2x2 blocks and both cross blocks are scored separately.
Each converter AC/DC current transfer uses its own current base. DC bus voltages and line/cable
terminal currents are also compared with each drive. The remaining devices stay connected.

Coarse scans use 23 active tones, onset 2.0 s, windows [16,24) and [24,32) s and 1.25 us
integration. Half-step repeats use 0.625 us integration. Both use recorder ratio 25.
The limits are 5 % complex error and 3 degrees phase error, with independent measurement checks.
Zero-delay devices use the complete one-step (discrete) network reference.

#### Redesigned P2P at 100 MW (`p2p_redesigned`)

The redesigned P2P has two 1000 MVA MMCs, a 25 km cable/75 km DC overhead link and AC overhead lines
`tl1` (25 km) and `tl78` (90 km), both untransposed.
Each grid has SCR 8 and X/R 10. Both converter transformers use 333/380, with 25 us modulation
delay, OCC PI 0.25/100, 500 Hz voltage feedforward filtering and 2.0 kHz voltage measurement.
The receiving request is 100 MW. Ports use 380 kV LL and 1000 MVA bases, with 2.916e-4 pu
current per tone. The native build has 100 live nodes.

With untransposed flat lines, c2 behind 90 km carries 2.7 % negative-sequence current and its bus
has 0.32 % negative-sequence voltage. The c1 current behind 25 km has 0.68 % negative sequence.
The ±100 Hz image response at c2 reaches 0.50 of the driven response. Blocks driven or measured
at c2 have 14–21 % Frobenius error, while c1's own impedance agrees within 0.46 %.
Every operating-point comparison passes. The untransposed coarse group takes 5537 s of station time.

The transposed variant's 25 km line at 50 Hz differs from PSCAD's line
constants by 7.05e-9 (Z11), 2.29e-8 (Z12), 1.09e-9 (Y11) and 7.71e-10 (Y12) in relative terms.
EMTDC exits abnormally at the end of every recorded 0.15–32 s measurement run with `Transp = 1`.
The physical outputs are complete. The same project with `Transp = 0` ends cleanly.

#### IEEE14 (`ieee14`)

The complete Jan Kircheis circuit has four MMCs, three wind farms, sixteen overhead lines,
two DC cables and five active shunt loads. It uses the standard WF1 PLL, 250 us MMC2 delay
and 61.2 mm cable jacket radii. Ports are MMC1 and MMC4 AC, on 380 kV LL and 1000 MVA bases.
All seven converter current transfers remain separate. Export and offline screen results are
retained. Both refined finite contours have zero closed right-half-plane counts. The 100 kHz
contour requires refinement between 0 and 0.010 Hz to resolve a full determinant-phase turn on
its positive-frequency branch. The distributed infinite spectrum remains unenumerated.
The circuit has 216 live nodes, above the educational licence's 200-node limit, and was not run in PSCAD.

#### P2P with AC grids (`p2p_ac_grids`)

The Cigre 2026 circuit uses untransposed 80 km and 90 km parallel AC lines, a 600 MW request
and a 300 MVAr receiving request. Converter initial phase-RMS voltages are 220 kV. Ports use
380 kV LL and 1000 MVA bases, with 1.0e-4 pu current per tone and the one-step (discrete) reference.
Every operating-point quantity meets its limit except c2's arm-capacitor voltage sums:
788.3–789.9 kV in PSCAD versus 798.6 kV in Julia, a 1.1–1.3 % error against 1 %.

Baseline negative-sequence current is 1.35 % at c2 and 1.3–1.9 % in the line pair.
The c2 bus has 0.61 % negative-sequence voltage. Its 100 Hz P/Q ripple is 0.60 % and 1.4 %
of nominal. The ±100 Hz image ratio is 0.32–0.59. The same kind of MMC pair on balanced
SCR-8 Thevenin grids without AC lines (`two_mmc_dc_cable`), coupled by a 25 km DC cable, shows a
±100 Hz image ratio of 0.0019. Blocks driven at c2 have about 49 % error,
while c1's own impedance agrees within 0.40 %. The status is `model_mismatch`.
The half-amplitude and half-step variants were not run in PSCAD. The coarse group takes 8794 s of station time.

Prepare and run the two systems from the validation environment:

```julia
using PythonCall
include("test/manual/pscad/validation/validation.jl")
PSCADValidation.prepare_systems(["p2p_redesigned", "p2p_ac_grids"])
PSCADValidation.run_systems(; ids=["p2p_redesigned", "p2p_ac_grids"], timeout=100800.)
```

Preparation rejects changed required files and existing output directories. Finite stability
screen results are recorded with the fixture and reported. Measured excursions must be ≤0.01 pu.
The queue saves results and continues within its timeout.

## Time-domain response procedure

The RC-shunt MMC, pi-line MMC and machine/MMC circuits have a separate burst protocol.
Preparation records and reports their frequency-response results and complete-network stability
screen, while preparation and execution proceed for every selected circuit. Each burst uses five
fresh native runs: baseline, full amplitude, half amplitude, half-step baseline and half-step burst. A baseline can pair only with a
project whose hash matches after zeroing actual injection gains. Frequency-response baselines are
not reused.

| Circuit | Carrier / cycles; axis | Onset / end, s | Ringdown interval, s | Peak current, pu | Integration main/half, us |
|---|---|---|---|---|---|
| MMC with RC shunt | 245.5 Hz / 8; d | 16 / 20 | [16.07,16.22) | 1.00e-3 | 2.5/1.25 |
| MMC behind pi line | 367.2 Hz / 8; d | 16 / 20 | [16.05,16.30) | 8.50e-4 | 2.5/1.25 |
| Machine and MMC | 1.487 Hz / 4; d | 64 / 80 | [67,76) | 3.50e-3 | 1.25/0.625 |

The command is `a/2 * (1-cos(2π τ/T)) * cos(2π f τ)` on `0 ≤ τ ≤ T`, zero otherwise, where
`τ=t-onset`, `T=cycles/f`. This Hann burst uses the same dq current port and phase measurement
path. Voltage base is the 380 kV nominal LL rating converted to phase peak; aggregate current
bases apply to injection, while device departures retain their original bases.

Score every declared free-node d/q voltage and individual device/passive-branch current over
[onset,end]. Fit a common complex mode across the two input-port voltage and two selected
device-current coordinates, with independent sine/cosine amplitudes and constant/linear
backgrounds per channel. Report frequency, `α=-Re λ`, `ζ=α/hypot(α,Im λ)`, fit residual and
conditional standard errors. A fit at a search limit or outside the extraction checks is
`unextractable`; invalid baseline/sampling/drive/departures give `invalid_measurement`. Keep the
predeclared windows. Correlated EMT noise can make fit standard errors optimistic.

Julia prediction uses the solved composed nodal equations and Jacobians, passive storage,
ideal-source perturbation clamps, exact modulation-feedback transport and full injection-readout
dq rotation. Double/quadruple padded DFT inversions check circular wraparound. Leading zero drive
samples can be skipped with zero perturbation state. Retain all nonzero pre-onset samples. Each
integration step is compared on its own recorder grid. Raw step changes are diagnostic; scores
against the continuous model are reported separately. A 19 % interface-step damping change in the
pi-line circuit cannot be described as a pass against the continuous model.

The RC-shunt MMC time-domain check passes against the one-step (discrete) model. Its maximum
per-signal RMS error is 0.664 % (limit 5 %), peak error 0.259 % (limit 10 %) and damping-ratio
error 0.167 % (limit 10 %). The half-amplitude repeat passes. The continuous model fails the
waveform comparison.

The pi-line MMC time-domain check passes against the one-step (discrete) model. Its maximum RMS
error is 1.03 % (limit 5 %), peak error 0.283 % (limit 10 %) and damping-ratio error 0.0446 %
(limit 10 %). The half-amplitude repeat passes. The continuous model fails the waveform and
damping-ratio comparisons.

The machine/MMC frequency-response record has a 1.117 % machine entry step change and a 1.34 %
aggregate entry step change against 1 %. Its burst was not run in PSCAD. Offline fitted modes and
convolution tests report numerical self-consistency.

## Instability-growth measurement

PSCAD reproduces the instability Julia predicts for the original P2P. Julia locates two growing
modes at signed abc frequencies +3478.5 Hz with growth 1374 s⁻¹ and -3476.6 Hz with growth
1426 s⁻¹. The fresh-start record at 1.0 us fits a growing mode at +3543 Hz and 1630 s⁻¹ over
0.3–1.8 ms. Frequency is 1.9 % and growth is 19 % above Julia's +3478.5 Hz mode. The second
mode is not resolved; its fit is at -4122 Hz. The relative fit residual is 58 %.

The unforced, burst and half-amplitude records give the same fit. The 1e-7 pu burst has no
measurable effect.

The record is nonlinear in that interval. AC line energisation from the uncharged start gives
11.5 pu peak departure and arm insertion indices outside [0,1]. The harness status is
`invalid_measurement`, and the growth rate is not determined to 10 %.
The `c1` bus space vector rises from 2.3 kV at t = 0 s to 689 kV, about 2.2 pu, at 0.10 ms.
Its upper-arm insertion index ranges from -3.3 to 1.1.
A separate phase-a trace at 1 us fits 3473 Hz and a 0.688 ms growth time (1453 s⁻¹) over
0.3–1.8 ms. That interval was chosen after inspecting the record.

For the P2P with AC grids without its 80 km line, Julia's +160.6 Hz mode at 55.0 s⁻¹ completes
0.24 cycles in the 1.5 ms fit interval. Its 2 ms records cannot show that mode.
The peak departure is 2.2 pu.
EMTDC steps of 0.2 and 0.25 us fail at the converter-transformer star point. Steps of 0.5 and
1.0 us run.

The implemented procedure uses five independent fresh 2.0 ms runs: unforced, burst,
half-amplitude burst, half-step unforced and half-step burst. Recording steps are 5.0/2.5 us.
A one-cycle Hann burst starts at zero with 1.0e-7 pu amplitude and the located mode's dq
polarization. The circuit without the 80 km line uses a 3527 Hz carrier; forcing ends before the fit.
DC precharge remains active during the fixed fit interval.

Complex Clarke vectors from both converter AC voltages and currents are fitted directly,
without subtracting the unforced trace. The model includes signed circular modes, opposite
carrier companions and constant, linear and ±50 Hz backgrounds, with independent complex
channel amplitudes. The [0.3,1.5) and [0.6,1.8) ms fits are diagnostics only.
Frequency error must be ≤2 % and growth error ≤`max(0.10*abs(Re(λ)),0.5/s)`.
Departure must be ≤0.01 pu, precharge commands closed and arm insertion fractions within [0,1]
in the fit interval. Convergence and uncertainty checks apply independently.
Reported results include confidence intervals, residuals, fit condition and per-channel fits.

```julia
PSCADValidation.prepare_systems(["p2p_original", "p2p_ac_single_line"])
PSCADValidation.run_systems(; ids=["p2p_original", "p2p_ac_single_line"], timeout=2400.)
```

## Known failure modes

| Symptom | Recorded facts | Remedy or interpretation |
|---|---|---|
| Growing modes from fixed-frame dq line reduction | Julia's fixed-frame dq reduction of an untransposed line can be non-passive. For the 170 km IEEE9 line, the minimum Hermitian admittance is -0.005134 S in dq versus +0.0005009 S in phase coordinates. With a 100 MVA TLC at bus 2, the dq model predicts a growing pair near 124.24/124.34 kHz (+2.37 s⁻¹); the phase-domain harmonic calculation gives -670.4 s⁻¹, converged at K=1..3. This circuit was not run in PSCAD. | Dq-frame frequency-response and stability comparisons are invalid for systems with significant asymmetry in their untransposed lines at the frequencies of interest; compare in the phase domain instead. |
| ±100 Hz image coupling occurs at a converter behind untransposed AC lines. | Steady negative-sequence unbalance makes the operating point periodic in dq. | Compare in the phase domain; ideal transposition triggers an EMTDC termination fault in these PSCAD projects. |
| EMTDC exits abnormally at the end of runs with `Transp = 1`. | The recorded projects have complete physical outputs. | The same project with `Transp = 0` ends cleanly. |
| EMTDC reports a zero diagonal at a converter-transformer star point. | Steps of 0.2 and 0.25 us fail in the recorded P2P projects. | Steps of 0.5 and 1.0 us run. |
| Original P2P has a growing oscillation in PSCAD. | Julia predicts growing modes at +3478.5 and -3476.6 Hz. | The fresh-start fit gives +3543 Hz and 1630 s⁻¹. Its nonlinear interval has 11.5 pu peak departure; the growth rate is not determined to 10 %. |
| Inconsistent low-frequency voltage phasors despite clean currents | EMT-Nyquist voltage chatter aliases to DC at even recorder/integration ratios | Prepare an odd integer ratio at both steps and preserve coherent windows. Adjacent decimation offsets correlated -0.999, offsets two apart +0.998; 0.74–0.85 V RMS chatter persisted after onset. Ratio 25 separates it at recorder Nyquist. |
| Zero-delay converter Y/step errors rise with frequency | One inherent electrical-measurement-to-source step | Use the one-step (discrete) model and residual step-size check, retaining continuous model errors and raw step changes and KCL readout checks. Positive delays export a rounded residual after subtracting one step. |
| Machine step change exceeds 1 % in the shared machine/MMC circuit | The recorded integration steps are 1.25/0.625 us. | The machine column in `machine_mmc_shared_bus` is valid but fails the raw entry-change limit at 1.117 %. Aggregate Y also fails at 1.34 %. The standalone machine passed at 0.90 %. A finer repeat requires 80 s runs at 0.3125 us. Apply the residual rule only to eligible blocks. |
| Window-entry failure near a lightly damped mode | The measured voltage-matrix condition limit is 100. | Keep the ≤100 condition check and extend predeclared coherent windows. The stiff-grid P/Q MMC had 1.87 % window-entry change at 42 Hz against 1 %; 8 s windows resolve the stored case. Larger amplitude alone did not remove it. |
| DFT rejects an adaptive band | Window lacks whole tone periods | A 75 Hz tone has 7.5 cycles in 0.1 s. Use whole common periods including the 50 Hz frame: [8,8.12), [8.12,8.24) s for the recorded 75/1000 Hz case, and retain enough output to cover both. |
| Large relative error on a tiny cross entry | Reference below the entry floor | Report the 0.02 pu absolute-floor comparison. Do not claim relative accuracy for sub-floor entries or let a passing aggregate hide them. |
| `1e99`, NaNs or rising DC startup voltage | Zero/unsettled divisor or uncharged source-free DC circuit | Inspect physical pole voltages and the divisor selector. Use the exporter’s temporary pre-charge for a source-free Vdc-controlled island; release is 0.2 s. Retain live MMC current/energy feedback. |
| Supervisor cannot launch a long-name local half-step run | Windows path length | Use compact frequency-list prefixes and preflight every possible path. The limit is 240 UTF-16 code units, including scratch, mapped-share and caller roots plus random suffixes. |
| Build reports only the educational node-cap error | Native electrical-node count exceeds 200 | Use a larger licence or smaller physical circuit. IEEE39 has 528 live nodes and was not run in PSCAD. Its offline export checks pass. Measurements of passive elements, single devices and coupled circuits require <100. Complete systems require <200 and one subsystem. |
| Native floating input or `NT_1` despite a valid written stub | Size-0 sheet clamps components on load and leaves wires behind | Export size 5 within [0,14382] coordinates. Inspect `outputs/load-relocations.txt`; check a native-saved project with `check_connectivity(path)`. |
| Isolated YY secondary produces a zero diagonal | Consecutive ideal meters in its only grounding path | Place the shunt meter in the load ground return; retain ordered pins and passive parameters. |
| Distributed line aborts before measurement | Travel time below integration step | Reduce the step. The exporter warns using length/speed-of-light; PSCAD uses calculated travel time. |
| DC cable mean drifts or differs from power flow | Low-frequency fitting and long fit poles | Inspect retained line constants and fit files, then lengthen settling. A tighter in-band target does not constrain true DC. `DCenab=1` fails Yc fitting for the stored cable. |
| Large turn-on voltage peak but small settled departure | Inductive current-drive onset | Keep whole-run maxima diagnostic and apply departure limits only in the declared windows, retaining means. Do not remove a real settled offset. |
| Completed run has a passing norm but failed overall status | Entry, phase, window, amplitude or step check failed | Inspect every required result. The TLC P/Q and P-f records retain this distinction. |

Frequency-list prefixes retain rounded spelling up to 48 characters. Longer lists use
`<first>_<last>_n<count>_<digest>`, with the first 12 SHA-256 hexadecimal characters of the
ordered Float64 IEEE-754 bit strings. This distinguishes half-Hz values without long paths.
Project stems include the same digest; completed short-name runs retain their hashes.

## Data layout and source records

Ignored `data/<key>/manifest.toml` records the circuit, settings, bases, amplitudes, reference
selection, source/dependency hashes, project hashes, native-run entries and comparison results.
Project variants, native `runs/`, references and analysis tables remain alongside it. Coupled
manifests contain coarse/local groups and independent results per measurand. Time-domain data use
a separate directory with suffix `_time_domain`. Its manifest retains channels, bases, fit coordinates,
windows and extraction checks.

Every retained payload has size and SHA-256 plus its producing source. The manifest omits its own
recursive hash. Archived projects and raw outputs remain attached to their original hashes,
including failed and unused candidates. Reference refresh archives the previous manifest/reference
without changing measured bytes. A changed project cannot reuse an older native run.

Useful result fields include `frequency_response_result` for the comparison with the continuous model,
`interface_step_result`, `comparison_summary`, `raw_step_refinement`, `residual_step_refinement`
and `step_refinement` for the selected rule. These are literal stored field names. Corrected
historical orientation analysis can appear under `corrected_analysis`; it must not be confused
with an old uncorrected result retained for comparison. A top-level status can be incomplete while
individual measured responses pass.

### Line and cable reference re-analysis

Use `reanalyse_line_chain.jl` to compare stored measurements with the corrected multiconductor
ABCD references. It selects the untransposed overhead line, coaxial cable, series DC line/cable,
IEEE9 network and available coarse measurements of the two MMCs coupled by a distributed DC cable.

```sh
OPENBLAS_NUM_THREADS=1 julia --project=test/manual/pscad/validation \
  test/manual/pscad/validation/reanalyse_line_chain.jl \
  /path/to/stored/data /tmp/line-chain-analysis
```

Optional trailing fixture keys restrict the selection. The script reads extracted SI matrices,
frozen references and recorded quality flags; it writes its results separately. It records input
hashes, the analysing revision and source hashes, and old/new entry and Frobenius errors using the
existing bases, floors and tolerances. It copies each input manifest and checks the hashes of every
consumed response and project. It reports incomplete measurements as pending.

For the untransposed overhead line (`ac_ohl_untransposed`), the maximum relative Frobenius error decreases from
0.381 % to 0.034 %. The coaxial cable and series DC circuit retain their errors; the IEEE9 coarse
maximum changes from 3.352218 % to 3.351453 %. Continuous and discrete errors for the distributed
DC cable are unchanged at the displayed precision. Re-analysis updates Julia references and
comparison tables without running PSCAD, changing stored measurements or repeating resonance
and stability checks.

## Troubleshooting and extending the suite

Start with the manifest status, required measurand summaries and invalid reasons. Then inspect
`comparison_frequency_response_qualified.tsv`, per-entry results, KCL factors, window and refinement tables, build
messages and recorded solver identity. A process failure or timeout is not a numerical comparison
failure. Increase an execution budget only after identifying which run failed; completed matching
axes resume.

Define a new circuit and physical bases before selecting injection amplitudes. Retain independent
references and physical pin order. Check complete-network stability, exported passive values,
sample coherence, path lengths and expected node count before native execution. Predict amplitude
to size the experiment; use measured departure, drift and repeat checks to accept it. Freeze
windows and reference selection before collecting data. Record every failed row and all model
differences alongside passing results.
