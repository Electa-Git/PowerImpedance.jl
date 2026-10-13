# Manual PSCAD physics validation

L1 covers eight passive fixtures; L2 one device, L3 interactions and L4 systems
remain later work. Tier D remains the original P2P early growth fit. Code is
manual and private; `data/`, `Manifest*.toml` and `.CondaPkg/` are gitignored.
No station operation occurs during preparation or offline tests.

## Prepare and run

Use Julia >=1.10. Resolve the **local harness Manifest with the same Julia
version used to run it**. Remove that gitignored Manifest before changing Julia
versions, then instantiate again from the repository root:

```sh
julia --project=test/manual/pscad/validation -e 'using Pkg; Pkg.develop(Pkg.PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=test/manual/pscad/validation test/manual/pscad/validation/prepare.jl L1
```

Preparation solves each power flow, checks passive dissipativity, writes all
full-band and half-amplitude projects plus half-step candidates at 750/1000 Hz,
reference tables, operating points and manifests. Existing project/output hashes
are preserved; manifest history and source revisions document harness changes.
A changed physical project or reference is rejected. No native data are deleted.

With the existing `POWERIMPEDANCE_PSCAD_CONFIG`, **one command** visits all L1
fixtures in order:

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L1
```

An individual fixture ID remains selectable. All completed axis directories are
resumable, including native runs absent from the ledger after a crash. The native
`compute` reuse checks verify project, inputs, toolkit, outputs and current solver
identity. Only missing runs execute. Analysis is repeated. All runs must report
**<100 live nodes**. The all-L1 invocation shares a **5400 s wall-time budget**;
a timeout leaves reusable completed runs and preserved failure evidence.

## Frozen settings

| Fixture | Applicable injection / response | Grid | Base / half step | Full run / windows | Remaining station estimate |
|---|---|---|---|---|---|
| L1-01 RL | d,q; Y 2x2 | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | accepted evidence reused |
| L1-02 DC RLC | differential voltage per outer port; Y 2x2 | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | accepted evidence reused |
| L1-03 AC OHL | a,b,c voltage at each port; Y 6x6 | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | 11 min |
| L1-04 AC cable | a,b,c voltage at each port; Y 6x6, corrected side-2 meter | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | 11 min |
| L1-05 DC cable + OHL | differential voltage per outer port; Y 2x2 | 24 | 2 / 1 us | 8 s; [6,7), [7,8) | 15 min |
| L1-06 YY | d,q voltage at each port; Y 4x4 | 23 | 2 / 1 us | 3 s; [1,2), [2,3) | accepted evidence reused |
| L1-07 Dyn11 | d,q voltage at each port; Y 4x4 | 23 | 2 / 1 us | 3 s; [1,2), [2,3) | accepted evidence reused |
| L1-08 IEEE9 | a,b,c shunt current at Bus1 and Bus5; direct Z, separate local 3x3 blocks | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | 40 min |

The current data need **36 missing runs**: ten each for OHL/cable/IEEE9
(baseline, six axes, one half-amplitude axis, half-step baseline and axis),
and six for DC. Estimated remaining station workflow is **77 minutes**;
the existing **90-minute shared wall-time deadline** remains enforced. Estimates
use the stored workflows, including IEEE9's measured 29-minute original dq scan.
The four accepted fixtures reuse hash-verified operating-point, corrected-C and
refinement evidence. A fresh checkout without that evidence requires those runs;
completed work remains resumable and a deadline never relaxes acceptance.

The 24-tone coherent grid is
`[1,2,3,4,6,7,10,13,18,24,32,42,50,56,75,100,133,178,237,316,422,562,750,1000]` Hz.
The balanced AC dq 23-tone grid omits 50 Hz, which would create an abc DC
sideband. **abc includes 50 Hz**: its tones are physical phase frequencies, with
no Park transformation of perturbations. Nominal voltage alone follows the fixed
50 Hz waveform. All source ramps are zero; onset is 0.5 s. Schroeder cosine phases
are `-pi*k*(k-1)/N` in absolute time. Sampling is 10 us: **100 samples/period at
1000 Hz** in abc/DC (95.24 at the balanced dq highest sideband, 1050 Hz).
The base step is below the conservative light-travel bounds: OHL 83.39 us,
cable 166.78 us and IEEE9 253.51 us; L1-05 shortest cable bound is 83.39 us.
Exact per-tone amplitudes, phases and bases are frozen in each manifest. Amplitudes
are bounded from the native reference to keep estimated departure below 0.004 pu.

AC voltage bases are the solved **phase-peak kV**; phase-peak current bases are
`2000/(3*Vbase)` kA, corresponding to 1000 MVA total / 333.333 MVA per phase.
All a/b/c coordinates at a port use that same base. DFT peak phasors are recorded
in kV/kA, so their ratio is SI S or ohm without an extra sqrt(2) or factor of three.
DC bases remain pole-to-pole kV and `1000/Vbase` kA.

## Measurement and qualification

A still calls `compare_operating_point` unchanged. C subtracts the zero-amplitude
project with identical modules, signal paths and summing junctions. Coherent
rectangular windows use `(2/N)*sum(x(t)*cis(-2*pi*f*t))` directly; no FFT library.
Probe orientation comes from the exact project's metadata. Y uses inward
terminal currents; direct network Z uses current leaving the shunt source.
The abc scans retain every phase sample, including zero sequence. Two-port
references call native `eval_abcd(element.element_model,j2*pi*f)` and `abcd_to_y`.

IEEE9 keeps every original source, transformer, line, load and connection in
PSCAD. Its Julia phase twin copies each physical model, setpoint and limits,
sets `transformation=false` with three pins per terminal, and replays every
terminal's original bus incidence for a/b/c (grounds have zero voltage).
Preparation asserts identical model representations and exact terminal-to-bus
mapping; tests also compare each untransformed ABCD against the original physical
model. The IEEE9 phase reference imposes the emitted YY cores' floating-neutral KCL,
retains external capacitor paths and includes the documented near-ideal terms.
Native `make_y` assembles the other elements; ideal source buses are clamped.
Six shunt-current runs recover
the full 6x6 transfer matrix by **V=Z*I**, without inverting a measured Y. Acceptance
scores the Bus1 and Bus5 **3x3 local blocks separately**; cross-bus entries remain
in the measured evidence. Bus1's ideal-source Z=0 tests clamping only.

Balanced elements retain native dq / differential-DC references. For each
applicable comparison, C keeps **2% complex error**, **0.02 pu entry floor**,
**0.1 Frobenius floor**, and **2 degrees** for reference entries >=0.02 pu.
Input conditioning <=100, baseline drift <=1e-3, window change <=1%, drive
magnitude error <=1%, clamped voltage departure <=1e-6 pu, and input/output
departures <=0.01 pu remain mandatory. abc baseline drift checks both window
means and the 50 Hz operating phasor, so zero-mean AC signals cannot hide drift.

One worst-error axis repeats at half amplitude (response change <=2%). A matching
half-step baseline plus that axis repeat at 1 us (change <=1%), using the worst
frequency and 1000 Hz (750/1000 if worst is 1000). Only those witnesses execute.
Two coherent windows have duration `max(0.1,1/gcd(50,frequencies))` s, starting
no earlier than 0.8 s, or **6 s for L1-05**. Both refinements use the approved
entry/norm floors. Fixture `passed` requires A, the applicable C and both gates;
the asymmetric fixtures' **dq approximation** is informational and never changes
acceptance or tolerances.

L1-05's retained baseline drift was 0.0241505. A damped tail fit over 0.6–3 s
(10 ms decimation) gives `alpha=2.1 1/s`, `beta=0.8 rad/s`, envelope time constant
**0.476 s**, RMS current residual **4.60e-5 kA**. Chosen windows [6,7), [7,8)
have predicted drift 9.27e-7; that extrapolation sizes the run, and the measured
<=1e-3 gate remains authoritative. DC line/cable fit settings are unchanged.
The fitted current asymptote is approximately 0.86126 kA versus Julia's 0.88201 kA,
so settling alone may leave a tier-A/model discrepancy; no physics is adjusted.
The `settled_` and `abc_` project/run keys preserve all original projects and traces.

## dq approximation (informational)

`transformation_dq` projects phase ABCD at s +/- j*omega0; it is exact for
symmetric elements. The untransposed circuits retain phase couplings which a
fixed dq LTI model omits, including +/-2*omega0 sidebands. This is a documented
modelling property, not a pass/fail item. The retained old dq comparisons and
sideband evidence are recorded in `dq_approximation_table` in the manifests.

| Fixture | Max dq error | Sideband ratio | ABCD-first error | Phase-Y-first error |
|---|---|---|---|---|
| L1-03 | 0.0050220685 | 0.042917057 | 0.0050220685 | 0.00072056716 |
| L1-04 | 0.030097387 | 0.11580194 | 0.030097387 | 0.021688525 |
| L1-08 | 0.073918068 | 0.25714039 | 0.073918068 | 0.062930748 |

The sideband ratio is the existing maximum off-grid +/-100 Hz output norm divided
by the maximum driven-band output norm, with its 0.1-times-drive floor. For single
elements the second ordering projects phase Y after ABCD inversion. For IEEE9 each element's projected phase Y is converted back with the native
`y_to_abcd` (round-trip equality asserted), cached at that single frequency in
the existing internal `Impedance` model, and reduced by native `make_z` with
identical pins and unchanged ideal sources. This diagnostic compares element-wise
Y projection against the native element-wise ABCD projection, without a new
physics kernel or modifying the reference circuit used for abc acceptance. Neither ordering receives
an acceptance status. The scans validate sampled bins; unresolved narrow
inter-bin resonances remain a coverage limitation.

Dyn11 secondary voltage leads +30 degrees. In positive-sine-q coordinates the
rotation is `R=[cos(phi) sin(phi);-sin(phi) cos(phi)]`. Both voltage and inward
current rotate, preserving power. Both ports here use the same global 50 Hz
frame; the solved secondary angle enters the voltage clamp, and native `get_y`
contains the vector-group rotation. No additional secondary rotation is applied
only to voltage. A secondary local frame would transform the **whole** matrix
with `T=diag(I,R)` on both row and column coordinates.

## Component authority and fairness ledger

| Added construction | Existing field/port authority |
|---|---|
| Controlled instantaneous AC voltage | `emitters/tlc.jl:tlc_electrical_canvas`, saved TLC sources 3383-3388,3452-3529 |
| Balanced controlled DC pole voltages, Grnd=0/Cntrl=1 | `emitters/sources.jl:dc_source!`, the TLC controlled source, `plan.jl:component_ports(source_1)` |
| Shunt controlled current, upper A positive injection | TLC canvas and saved TLC 5589-5630; station sign witness in `tlc.jl:172-175` |
| Tone/gate/gain/sum, dq->abc, merge, taps and exports | Existing `blocks.jl:lower!`, `dq_to_abc_module`; saved TLC dq2abc 1851 |
| Module parameters and natural/signal ports | `ModuleDefinitionPlan`, existing writer parameter/port API |
| Breakout, xnode, ammeter, datalabel/PGB | Existing TLC/probe/impedance emitters; no new master fields |

Retain raw geometry, sheath/ground elimination, rational fit settings, YY
regularization and PF/T-model differences. The DC frequency reference includes
the exporter's two 10 Mohm midpoint resistors as their 20 Mohm differential
equivalent. Native `Source` ABCD equations are ideal, matching IEEE9 voltage
clamps; `eval_y(Source)`'s numerical regularization is not substituted for them.
Positive resistance and source/loaded termination justify the registered passive
stability gate; no Nyquist scan or active-device inference is performed.

Every kept payload file has size/SHA256 and provenance in its fixture manifest.
The manifest excludes its own recursive hash; its size/hash are printed after
writing. Original manifests, raw runs and unused prepared candidates are retained.
Artifacts remain gitignored; decide on committing them from measured sizes later.

## Offline checks

```sh
julia --project=test/manual/pscad/validation -e 'using Test, PowerImpedance; include("test/pscad/runtests.jl")'
julia --project=test/manual/pscad/validation test/manual/pscad/validation/check_projects.jl
```

The suite includes full 1x1/2x2/3x3/4x4/6x6 coherent synthetic recovery to 1e-9, all probe
constructions, DC connectivity/pole scaling, direct-Z input selection, Dyn11
rotation of both voltage/current coordinates, refinement limits, manifest round
trip, native completed-run reuse and the manual-script name guard. XML readback
checks every written variant against its matching baseline and declared settings.

## Probe directions and stored-data diagnosis

Terminal-current metadata stores `into` / `out` relative to the element. Passive
branches retain direction 1 → 2; Y extraction negates outward terminal currents.
Direct Z retains outward shunt-source current as network injection. AC-cable
side 2 now follows the branch convention; historical L1-04 runs remain recorded
as both-inward. Every native run ledger retains its project hash and probe
metadata, and offline analysis reads those records rather than current emitters.

`reanalyse.jl L1` reads existing OUT/INF files locally, checks the saved project
hash, uses the approved tolerances, and writes `analysis/probe-orientation/`.
It never calls native compute. Original comparisons and native runs are retained.
The corrected analysis is separate from current-project station status; L1-04's
historical dq evidence remains informational; the current abc projects use the corrected cable meter.

`data/orientation-regression/regression.tsv` lists every re-export comparison.
Only L1-04's side-2 meter node-label connections change; nonsemantic XML ids and
export revision timestamps are excluded from that comparison. Per-frequency and
per-entry diagnosis tables are stored under each fixture's analysis directory.

## Run 2 offline diagnosis (M9a5)

The abc drift gate already measures **DC window means and 50 Hz phasors**, not
instantaneous sine samples. Their separate values now appear as
`baseline_dc_drift` and `baseline_fundamental_drift`; the 1e-3 gate is unchanged.
Stored OHL/cable baselines have decaying DC offsets; their dq window averages
reject these oscillatory terms after Park projection. Numerical C agreement
alone therefore cannot clear the measurement/qualification gate.

The original IEEE9 copied-model phase reference wrongly treated the YY stars
as ground-referenced. Emitted `xfmr-3p2w` internal star points float (mapping doc
232–237 and the emitter); the copied model/terminal hash proof did not test this
hidden grounding. The corrected private reference imposes neutral-current KCL
using `Q=I-11'/3` on the winding paths, preserves externally grounded Ct and
bridging Cs paths, and includes Xl=1e-4 pu / Im1=1e-3 percent (symmetric leakage
split). Each winding's positive/negative sequence response is unchanged exactly
when regularization is excluded. The corrected 50 Hz Bus5 positive-sequence Z is
4.195817+j39.754151 ohm versus native dq at s=0, 4.194747+j39.757768 ohm: 9.43e-5
relative difference, consistent with the untransposed dq approximation.
The corrected C maximum is 0.0318756; it still fails 2%. Original comparisons and
the grounded reference are retained under `analysis/m9a5/`. The corrected worst
axis/band is p2_c at 316 Hz; old p2_a, 2/1000 Hz witnesses cannot qualify that
new selection. No additional runs occur during this diagnosis.

Line-constants matrix dumps, reports and fitted models were **not collected**.
Needed files in the completed run's `scan/generated.gf81/` build directory:
L1-04 `line.out`, `line.clo`; L1-05 `line.out`, `line.clo`, `ohl.out`, `ohl.tlo`.
Auxiliary `<name>_zm.out`, `_zp.out`, `_ym.out`, `_yp.out` hold per-length matrices
in ohm/m and S/m (possibly in the constants process working directory). `.clo`
and `.tlo` contain Fre-Phase poles/residues, constants and propagation delays
needed to evaluate the fit at DC/50 Hz. Names/formats are verified against local
retained PSCAD artifacts, not inferred from waveform `scan_*.out` files.
Constants-vs-fit attribution is unresolved until those existing artifacts are
available; native matrices and stored-trace evidence are in `analysis/m9a5/`.

M9a6 offline attribution and re-run preparation:

- The retained `line.out` / `ohl.out` contain full per-length phase Z/Y at 50 Hz.
  The Fre-Phase `.clo` / `.tlo` poles, residues, real Yc constants and delayed
  propagation groups are evaluated directly at DC, 50 Hz and the scan tones;
  numeric results and format provenance are under `data/m9a6/`.
- L1-03 and L1-04 now use `abc_settled`: coherent one-second windows at 5/6 s
  and 20/21 s respectively, with 7/22 s durations. No source ramp, tone,
  physical parameter, time step or acceptance threshold changes. Half-step
  witnesses retain the same late settle time. Previous abc projects/runs are
  retained under their original keys and hashes.
- L1-08 retains all original abc axis runs. The pending witnesses are `p2_c`
  at half amplitude on the original grid, and baseline plus `p2_c` at 1 us on
  316/1000 Hz. The runner still chooses the worst column/band from comparison.
- L1-05 needs no additional tier-C run: simulation follows the saved fit.
  Its eight-second tier-A current must not be labelled the fit's DC limit:
  the saved cable fit contains a 260 s characteristic-admittance pole and
  its true DC limit differs substantially. No DC fitting settings changed.
- Expected remaining station time: OHL 14 min, cable 34 min, IEEE9 6 min;
  54 min total based on stored run times scaled by simulated duration/step,
  with overhead allowance. The explicit multi-fixture command has a shared
  60 min deadline and resumes only matching completed project hashes:

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L1-03 L1-04 L1-08
```

The gitignored harness Manifest must be instantiated with the Julia version
used for that command. Diagnostic build-only copies are at
`local/pscad-exchange/diag/lc-l104/matrices/l1_04.pscx` and
`local/pscad-exchange/diag/lc-l105/matrices/l1_05.pscx`. Only existing `Output`
fields change from 0 to 1 (one cable / cable plus OHL); neither was built here.
The matrices across the fit grid are needed to separate low-frequency
constants differences from fitting error. These diagnostic builds are separate
from the timed waveform command above.

M9a9 current projects and station budgets:

The default `YMaxE`/`AMaxE` is now 0.02% for all AC/DC overhead lines and cables.
The entire previous L1-03/04/05/08 directories, including completed/incomplete
runs, projects, manifests and comparisons, are retained at
`data/archive/m9a9-0.2/<fixture>/`. New active projects have different hashes;
old runs are not reused. Native references, frames, amplitudes, coherent windows
and source paths are retained. Refinements still select the new worst axis/band.

Use separate invocations. Observed old workflow times (including transfer and
analysis) were 23 min for OHL, 36 min for cable before its half-step witnesses,
13 min for DC, and 33 min for IEEE9. Increased fit order can add work; these
estimates include all required refinement runs and larger deadline margins:

| Fixture | Expected full workflow | Deadline | Command argument |
|---|---:|---:|---|
| L1-03 | 30–40 min | 60 min | `L1-03 --timeout=3600` |
| L1-04 | 60–75 min | 120 min | `L1-04 --timeout=7200` |
| L1-05 | 20–30 min | 60 min | `L1-05 --timeout=3600` |
| L1-08 | 45–60 min | 90 min | `L1-08 --timeout=5400` |

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L1-03 --timeout=3600
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L1-04 --timeout=7200
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L1-05 --timeout=3600
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L1-08 --timeout=5400
```

`--timeout` is a finite positive workflow budget in seconds, shared if multiple
fixtures are requested; it is private manual-script syntax, not a package API.
The same commands resume matching completed **new-project** runs after an
interruption. The gitignored harness Manifest must be instantiated with the
Julia version used. The tightened targets improve the initial tier-C band;
the documented true-DC cable fit limitation and all acceptance gates remain.
