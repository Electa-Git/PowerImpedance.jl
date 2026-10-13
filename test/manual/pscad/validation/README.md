# Manual PSCAD physics validation

L1 is closed with seven passes and one owner-explained system result. L2 starts
with one strong-grid TLC fixture; L3 interactions and L4 systems remain later work. Tier D remains the original P2P early growth fit. Code is
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

## Layer 1 closure (M9b-1)

All tier-A comparisons passed under the existing rules. C errors below are
maximum relative Frobenius errors after recorded orientation and model
corrections; dq projection results remain informational for asymmetric
fixtures. Seven fixtures also passed the amplitude/step refinement gates.

| Fixture | Element / physics | Domain | Tier A | C max error | Status | Key evidence |
|---|---|---|---|---|---|---|
| L1-01 | RL; dq coupling, loss | dq Y 2x2 | passed | 0.00131% | passed | all 24 frequencies; refinements passed |
| L1-02 | DC RLC; charging, pole bases | differential DC Y 2x2 | passed | 0.00131% | passed | inward-current conversion; refinements passed |
| L1-03 | AC OHL; earth return, propagation | abc Y 6x6 | passed | 0.381% | passed | later settling, tighter fit; refinements passed |
| L1-04 | AC cable; sheath elimination, earth return | abc Y 6x6 | passed | 0.843% | passed | corrected native earth constant/depth; unchanged PSCAD project; refinements passed |
| L1-05 | DC cable + OHL; mixed-medium/DC loss | differential DC Y 2x2 | passed | 0.303% | passed | longer settling, tighter fit and native earth correction; refinements passed |
| L1-06 | YY; turns ratio, winding loss | dq Y 4x4 | passed | 0.0118% | passed | terminal orientation applied; refinements passed |
| L1-07 | Dyn11; phase shift, winding loss | dq Y 4x4 | passed | 0.0122% | passed | +30 degree convention; refinements passed |
| L1-08 | IEEE9; network resonance/reduction | abc local Z 3x3 | passed | 3.88% point error (3.35% coarse grid) | explained | resonance centre/width reproduced; remaining point failures retained |

L1-08 disposition: **explained: resonance reproduced; point failures from slope
amplification and marginal single entries**. At the 0.25 Hz refined grid, Julia
and PSCAD centres are 316.9407 / 316.8704 Hz (0.0222%); half-power widths are
3.29618 / 3.29380 Hz (0.0721%). All 126 in-band comparison rows pass the approved
resonance rule. Steep shoulders just outside its band still fail the unchanged
2% point rule (2.0–2.6%); the point profile peaks near 3.9% at resonance and is
1.2% at ±5 Hz. Marginal single entries remain at 237, 562 and 1000 Hz. This owner
disposition preserves failing rows and is not numerical acceptance of them.
Resonance amplitude/step witnesses passed. Raw results and manifest history remain.

Outcomes: the cable investigation identified the native earth-return constant
`exp(gamma)=1.7811` and each cable's own self-term depth; correcting them reduced
L1-04 C to 0.843% without changing PSCAD projects. Separately, PSCAD fit targets
`YMaxE=AMaxE=0.02%` reduced fit-versus-own-constants terminal errors from
4.34/2.88/4.31% to 0.84/0.49/0.35% for AC cable/DC cable/DC OHL. Constants physics
and fit accuracy remain separate ledger items; comparison tolerances did not change.

## L2-01: TLC P/Q against a strong grid

The M4 case-2 current API supplies the 100 MVA, 220 kV line-line RMS, 640 kV DC
TLC, P/Q PI controllers, PLL, OCC, measurement filters, frequency-support lag
and 200 us Padé 3/3 modulation. Setpoints are 70 MW / 5 MVAr (0.7 / 0.05 pu).
Its DC cable is replaced by a direct ideal DC source. The AC ideal source remains
behind a series RL: `|Z|=60.5 ohm`, `R=6.019975 ohm`, `L=0.191621756 H`.
SCR is exactly 8 at the 100 MVA / 220 kV rating and X/R is exactly 10.
The solved terminal voltage is 1.0111003 pu at 0.0855993 rad; the terminal-voltage
short-circuit ratio is 8.17859. DC power is 70.03854 MW including converter loss.

Preparation runs the complete-network gate before writing projects: native
admittances on 6001 logarithmic points from 0.01 Hz to 100 kHz, generalized
Nyquist net 0, plus all finite poles of the source-clamped TLC + RL descriptor.
The most positive located real part is -1.9917811 /s (0.5021 s time constant);
next poles are -3.12835, -3.13641 and -24.39368 /s. The standalone subsystem is
also stable. The descriptor retains grid dq dynamics and imposes terminal KCL;
converter-only pole stability is insufficient. Native characteristic residuals
and all poles are saved in the manifest.

A shunt controlled current source adds zero current at the operating point.
Two d/q runs measure converter current (recorded outward, converted inward)
and the actual terminal voltage matrix; `I_converter=Y_converter*V_terminal`
recovers the native `get_y(DUT,s)[2:3,2:3]`, with DC clamped. No network-Y subtraction
or measured-Y inversion is used. Construction reuses `current_port`, whose
`master:src_ccin_1` fields and current sign are from `src/PSCAD/emitters/tlc.jl`
and the saved M4 TLC project, plus the existing `dq_to_abc_module`.
The nominal fixed 50 Hz frame matches native TLC input coordinates.

| Axes / grid | Integration / sampling | Injection / windows | Per-tone amplitude | Station estimate |
|---|---|---|---|---|
| d,q; 23 coherent tones 1–1000 Hz, omit 50 Hz | 2.5 us / 20 us; half step 1.25 us | onset 2 s; [8,9), [9,10) s | 5e-5 pu current (0.0186 A peak); Schroeder phases | 15–25 min; 60 min deadline |

Voltage/current bases are nominal phase-peak 179.6292478 kV / 0.37113481 kA,
100 MVA total three-phase rating. Sampling gives 47.62 samples/period at the
1050 Hz highest sideband. The 8 s settle exceeds 15 slow-mode time constants
from the 0.2 s DC-divisor hold, and 11.95 from tone onset. Baseline drift,
window consistency and departures are measured, not inferred from that estimate.
Six runs execute: baseline, d, q, one half-amplitude axis, half-step baseline
and that axis at the worst band plus 1000 Hz. Prepared half-step candidates are
18/1000 and 750/1000 Hz; the runner selects the new worst band from the new comparison.
For current drive the one-axis refinements compare both `V/Idrive` and
`Iconverter/Idrive`; a single coupled voltage axis cannot identify a Y column.
Expected half-amplitude change is below the unchanged 2% linearity gate (an
expectation pending station measurement). C uses the approved **5% / 3 degrees**
active rule with unchanged floors; full-matrix conditioning and both refinement
gates remain mandatory. Padé versus exact-delay mismatch is recorded separately.

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L2-01 --timeout=3600
```

M9b-2 stored-run diagnosis: the 10-to-5 us witness change is 0.453% Frobenius /
2.319% worst entry at 18 Hz, and 3.318% / 3.748% at 1000 Hz. Comparing measured
converter current with `YJulia * Vmeasured`, the normalized directional residual
falls from 1.270% to 0.635% at 18 Hz and 1.932% to 0.952% at 1000 Hz. A single
5 us injected axis cannot identify a full 2x2 Y; this directional comparison
uses its measured voltage rather than mixing it with the other 10 us run.
The complete 10 us Y errors are 1.579% / 1.960%; 18 Hz is the worst-entry selection,
while 1000 Hz carries the maximum Frobenius error. Profiles and component values
are in `data/m9b2/`. Old projects, outputs and evaluations are archived at
`data/L2-01/history/m9b1-station-run/`; no old run is eligible for reuse.

M9b-3 identified the departure scope error. The former quantity was
`max(abs((Vaxis(t)-Vbaseline(t))/Vbase))` over **every recorded time**, including
turn-on. Both runs peak at exactly 2 s, with no difference before onset. The
voltage jump is 1.95152 / 1.95145 kV. Halving amplitude and step together keeps
`amplitude/dt=10 /s` unchanged; this is the inductive turn-on impulse, not an
operating-point offset. With `Lgrid || Lfilter = 0.0750062 H` and the Schroeder
onset current jump 0.1300815 A, the inductive companion estimate
`2*Leq*DeltaI/dt = 1.95138 kV` agrees with the observed jump. It is consistent
with the sampled inductive switching response; the internal block responsible
for the subsequent first-order interface error has not been isolated.

The corrected input/output departure gates take the same baseline-subtracted
samples **only in the predeclared C windows**, [8,9) and [9,10) s. The 0.01 gate
is unchanged, and means are retained so steady offsets still count. Whole-run
maxima remain diagnostic fields. The current signal, voltage/current bases,
orientation, source path and nominal frame are unchanged.

| Stored run | Base step | Window input departure | C max Frobenius error | C result | Remaining qualification failures |
|---|---|---|---|---|---|
| 1 | 10 us | 0.000357836 pu | 1.96038% | failed, valid measurement | 18 Hz d-d entry: error 0.00187869 pu > 0.001 pu limit; step 3.31770% |
| 2 | 5 us | 0.000180544 pu | 0.96533% | passed, valid measurement | step 1.65658% |

Tier A and half-amplitude gates pass for both stored runs. Their overall status
remains failed under the unchanged entry and step rules. Re-evaluation tables
are retained beside the old station evaluations; no raw data are changed.

| Frequency | Julia directional current residual, 10 us | 5 us | 2.5 us |
|---|---|---|---|
| 18 Hz | 1.27024% | 0.63489% | 0.31731% |
| 1000 Hz | 1.93234% | 0.95194% | 0.47279% |

These residuals score `norm(I-YJulia*V)/max(norm(YJulia*V),0.1)` using normalized
current-drive response vectors and recorded inward converter currents. The
2.5 us data contain one witness axis, so this is a directional admittance check,
not a full 2x2 identification. Full-matrix maxima at 10 / 5 us are 1.96038 /
0.96533%. Step-response-vector changes at 1000 Hz are 3.31770 / 1.65658% for
10-to-5 / 5-to-2.5 us. Halving dt approximately halves both errors: documented
**first-order converter/interface discretization error** over this band.

For 1–1000 Hz, recommend **2.5 us base / 1.25 us witness** for the remaining TLC
fixtures, and as the initial candidate for uncompensated MMC fixtures. MMC must
qualify independently for each control mode and grid variant; TLC does not
establish MMC convergence. Compensated MMC retains its **1 us** requirement
(with a half-step witness). Keep all phase, complex, floor and refinement gates.
The new L2-01 pair is predicted to give about 0.828% norm / 0.937% entry change
under first-order scaling; actual station qualification is mandatory.

New projects use amplitude 5e-5 pu, 2.5 / 1.25 us integration, and unchanged
20 us sampling, 2 s onset and settled windows. Expected input departure is
about 0.000181 pu, based on the measured settled response. Six fresh runs are
estimated at **15–25 minutes** from run 2's measured 658.5 s workflow; the
60-minute deadline remains. The full previous tree is archived at
`data/L2-01/history/m9b2-station-run/`, including run 1's nested archive. All
new project hashes differ. Diagnostics and convergence are under `data/m9b3/`.

Offline on Julia 1.12.7 and 1.10.11: **17,467/17,467 PSCAD suite checks**
(including 59 name-guard checks, 53 TLC/gate checks and 8 departure-scope checks), plus **819/819 XML
checks** per version. Synthetic converter Y recovery error is 1.83e-13; the
known unstable network is rejected. Station tier A/C/refinement remain pending.

Projects/reference/manifest are under `data/L2-01/`. Existing hash-valid completed
runs resume; no L2 station execution has occurred during preparation.

## L2 batch A (M9b-4)

Owner station evidence closes L2-01: tier A and refinement passed; converter admittance within 0.48% of Julia at 2.5 us. The five new fixtures are prepared; their station results are pending.

| Fixture / control | SCR / X:R | Solved P / Q (MW / MVAr) | AC voltage (pu) | Gate: most positive real part (1/s) | Expected station time |
|---|---|---|---|---|---|
| L2-02 P-f + Q | 8 / 10 | 70.00000 / 5.00000 | 1.0111003 | passed: -1.9917811 | 15–25 min |
| L2-03 P + Q-V | 8 / 10 | 70.00000 / -1.37412 | 1.0031871 | passed: -3.1363304 | 15–25 min |
| L2-04 P + VAC | 8 / 10 | 70.00000 / -3.91261 | 1.0000000 | passed: -3.0903588 | 15–25 min |
| L2-05 Vdc + Q / DC resistor | 8 / 10 | -70.03996 / 5.00000 | 0.9935849 | passed: -0.7760760 | 18–30 min |
| L2-06 P/Q weak-grid twin | 2.5 / 10 | 70.00000 / 5.00000 | 1.0090226 | passed: -1.9714563 | 15–25 min |

All retain the 100 MVA, 220 kV AC / 640 kV DC M4 TLC, PLL, OCC and averaged electrical/modulation blocks. SCR uses the rated AC voltage: strong-grid R=6.019975 ohm, L=0.191621756 H; weak-grid R=19.263920 ohm, L=0.613189618 H. X/R=10 at 50 Hz. No gains or grid strengths were tuned.

M4 `tlc_network` supplies P/Q PI 0.04/40, P-f support K=5 and cutoff 2 rad/s, PLL/current-loop/filter/modulation parameters and limits. M5b mapping evidence supplies Q-V K=20/cutoff 100 rad/s and VAC PI 0/100 with **NoFilter**. Vdc PI is the M4 TLC 5/5. L2-03/04 have plain P (NoFrequencySupport); L2-05 has plain Q (NoVoltageSupport). **L2-01 already has the M4 P-f lag**, so L2-02 explicitly repeats that physics. L2-06 preserves every L2-01 controller and request.

L2-05 consumes 70 MW on DC through R=640^2/70=5851.428571 ohm differential (2925.714286 ohm per pole to ground). It rectifies 70.039956 MW from AC, including loss. Native PF uses a remote ideal zero-voltage reference; the harness contracts that zero-voltage source to ground using internal Netlist/Terminal metadata. Existing `src/PSCAD/emitters/impedance.jl:emit!` supplies the grounded R/2 legs; no DC voltage-source component or auxiliary midpoint shunts are exported. This contraction is electrically exact. The AC reference is the native 3-port converter plus resistor nodal Schur reduction, **not** the converter AC block with DC clamped. The measured DUT current excludes the AC grid branch. DC voltage may respond; only the DC clamp check is inapplicable. AC departure, drive, drift and refinement thresholds remain unchanged.

The complete-network gate retains all converter and RL states (and DC feedback for L2-05), native admittances on 6001 points at 0.01 Hz–100 kHz, and all finite descriptor roots. VAC has an open-subsystem integrator at zero but stable complete-network poles. The corrected Nyquist contour uses Re(s)=1e-6 1/s, its real-axis closure point, and the enclosed open-loop pole count; it requires zero closed RHP count and the unchanged strict negative complete-network root margin. Tests cover an integrator stabilized by its network, a stabilized RHP subsystem, and the known unstable pair. This fixes the earlier assumption that every standalone subsystem must itself be strictly stable.

Common C settings: two nominal fixed-frame dq shunt-current drives; **2.5 us integration / 1.25 us witness**, **20 us sampling**, onset 2 s, windows **[8,9), [9,10) s**, 10 s main runs. Half-amplitude repeat: 2.5e-5 pu on one selected axis; half-step baseline plus that axis at the worst band and 1000 Hz. Nine projects per fixture are prepared; six normally run, and the runner writes an adaptive witness band when needed.

Per-tone peak **5e-5 pu current = 0.01856 A**; Schroeder phases -pi*k*(k-1)/N. Bases: 179.629247804 kV AC phase peak and 0.371134809513 kA phase peak. The 23 integer coherent bins (Hz) are: 1, 2, 3, 4, 6, 7, 10, 13, 18, 24, 32, 42, 56, 75, 100, 133, 178, 237, 316, 422, 562, 750, 1000. Sampling provides 47.6 samples/period at the highest 1050 Hz sideband. Active C remains **5% complex / 3 degrees**, with the approved 0.02-entry and 0.1-Frobenius floors. No tolerance changed.

Slowest decay times are 0.5021, 0.3188, 0.3236, **1.2885**, 0.5072 s. The common 8 s settle is retained as requested; it is 6.21 time constants for L2-05, and its measured baseline drift remains mandatory. Native triangle bounds on settled AC voltage/current departures are <=0.000954 pu across this batch; they are predictions, not station gate results. Each fixture still must pass the half-amplitude and half-step measurements.

Resumable command (78–130 min estimate; 180 min deadline):

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L2-02 L2-03 L2-04 L2-05 L2-06 --timeout=10800
```

Projects, native references, hashes, settings and root lists are in `data/L2-02/` through `data/L2-06/`. Completed runs resume only with matching project hashes and valid completion records. Evidence summary: `data/m9b4/summary.tsv`; native stability records: `data/m9b4/L2-0x-gate.toml`. Instantiate the gitignored harness Manifest with the Julia version used for the station command.

Offline final checks on Julia 1.12.7 and 1.10.11: **17,575/17,575 PSCAD suite assertions** per version, including **59 name-guard assertions**; **1,044/1,044 XML assertions** per version. The new batch/DC-termination testset is 103/103; converter-port synthetic recovery remains 1.83e-13 normalized, and DC-terminated recovery is <=1.54e-17 S. The independent unreduced DC descriptor matches the finite-mode count and rightmost mode, with normalized pencil residual <=4.31e-18. It uses QZ beta to distinguish algebraic infinity and backward error for root consistency; no C or qualification tolerance changed. All nine prepared project hashes, retained file inventories and producing-source hashes verify for each new fixture. No station execution or src/dependency changes. Logs and checksums: `data/m9b4/`.

## Frozen settings

| Fixture | Applicable injection / response | Grid | Base / half step | Full run / windows | Original station estimate |
|---|---|---|---|---|---|
| L1-01 RL | d,q; Y 2x2 | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | accepted evidence reused |
| L1-02 DC RLC | differential voltage per outer port; Y 2x2 | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | accepted evidence reused |
| L1-03 AC OHL | a,b,c voltage at each port; Y 6x6 | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | 11 min |
| L1-04 AC cable | a,b,c voltage at each port; Y 6x6, corrected side-2 meter | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | 11 min |
| L1-05 DC cable + OHL | differential voltage per outer port; Y 2x2 | 24 | 2 / 1 us | 8 s; [6,7), [7,8) | 15 min |
| L1-06 YY | d,q voltage at each port; Y 4x4 | 23 | 2 / 1 us | 3 s; [1,2), [2,3) | accepted evidence reused |
| L1-07 Dyn11 | d,q voltage at each port; Y 4x4 | 23 | 2 / 1 us | 3 s; [1,2), [2,3) | accepted evidence reused |
| L1-08 IEEE9 | a,b,c shunt current at Bus1 and Bus5; direct Z, separate local 3x3 blocks | 24 | 2 / 1 us | 3 s; [1,2), [2,3) | 40 min |

Layer 1 uses retained, hash-verified station evidence. No layer-1 re-run is
requested by the L2 preparation. The historical settings above describe the
original workflow; later settling and resonance settings are recorded below.

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

## Cable reference refresh and resolved resonances (M9a-11)

`reanalyse.jl L1-04 --refresh-reference` (and `L1-05`) archives the previous
manifest, operating point, reference and analysis, regenerates Julia's power-flow
and admittance references, and compares the retained SI measurements. It reads
baseline output for tier A, preserves recorded probe orientations and measured
refinement gates, and verifies every prepared project hash before and after.
It performs no station operation and does not regenerate native projects.

A resonance qualifies only when **both** curves have a bracketed magnitude peak
(or admittance dip), both half-power crossings, at least five samples inside,
and at least six grid intervals across the half-power width. Magnitude is the
local port-matrix Frobenius norm. A three-point quadratic power interpolation
estimates the centre; linear interpolation determines the half-power crossings.
A dip uses reciprocal admittance magnitude. Unresolved curves retain the
ordinary complex rule and cannot qualify a resonance measurement.

Inside either qualified half-power band, comparison uses centre-frequency error
<= max(1% of Julia centre, one local grid interval) and relative half-power-width
error <=10%. Outside both bands the original complex, magnitude and phase
checks apply. Point errors remain recorded inside the bands as information.
`comparison_C_qualified.tsv` records `comparison_rule` on every point; the
manifest retains both fitted bands, resolution evidence and original complex
results. Measurement and amplitude/time-step refinement gates still apply.

L1-08 has an additional **Bus5-only**, unchanged-topology current-injection scan:
312–322 Hz every 0.25 Hz, excluding the completed 316 Hz tone (40 extra bins).
The completed 316 Hz local Z is merged for resonance qualification, without a
repeat of its original injections. Three new phase injections and a matching
zero-amplitude baseline measure local 3x3 Z directly. Coherent windows are
[2,6) and [6,10) s (4 s each); source injection begins at 0.5 s. The normal step
is 2 us; sampling is 64 us (48.5 samples per 322 Hz period). One phase-a
half-amplitude repeat and a matching half-step baseline/phase-a repeat cover
only those extra bins. Exact amplitude and hashes are in `resonance_scan`.
Existing base-band amplitude/step witnesses are reused by project hash.

Run from the repository root, with the harness environment instantiated using
the same Julia version:

```sh
julia --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L1-08 --timeout=7200
```

Allow **45–75 minutes** (120-minute deadline), including retained-output loading,
seven new runs and refinement analysis. Completed runs resume by matching hash.
Existing base-band failures outside the resolved resonance keep their ordinary
rule; qualification of the 317 Hz peak alone does not waive them.

Reference-only results after 4ac59bd:

| Fixture | Tier A | Tier C maximum Frobenius error | Refinement | Projects |
| --- | --- | --- | --- | --- |
| L1-04 | 7/7 pass | 0.842910% (all 864 entries pass; maximum phase 0.97656 degrees) | Existing gates pass | All 25 hashes unchanged |
| L1-05 | 12/12 pass | 0.303155% (all 96 entries pass; maximum phase 0.37478 degrees) | Existing gates pass | All 13 hashes unchanged |

The old evaluations are under each fixture's `history/m9a11-*`; raw runs are
shared and remain unchanged. Stored witness axes/bands stay fixed when only a
Julia reference changes. Source pins for the remaining fixtures are refreshed
only after their native references verify unchanged, with the prior manifest
retained in history.

IEEE9's current data also have seven failed entry rows at 237, 562 and 1000 Hz,
outside the prepared 317 Hz band. These stay subject to the complex rule. The
new resonance runs therefore qualify the peak method; they do not establish
that all of L1-08 passes. Detailed reference results and those unchanged rows
are retained in `data/m9a11/evidence.json`.

## Sampling and output volume (M9a-12)

New resonance plans choose the largest multiple of the integration step that
also divides every window boundary, window duration and run duration, with at
least 40 samples per period at the highest measured sideband. dq includes
f+50 Hz; abc includes the measured nominal 50 Hz baseline fundamental; DC uses
the injected band. Completed base-band projects retain their recorded sample
intervals and hashes. Integration steps and the approved comparisons do not
change.

For the 312–322 Hz abc scan, 80 us would give only 38.8 samples per 322 Hz
period. **64 us** meets the band and coherence constraints for both 2 us and
1 us integration: each four-second window has **62,500 samples** and each
10-second run has **156,251 output rows**, including both endpoints.

Only **Bus5 voltage a/b/c** and **injected current a/b/c** are recorded. The
harness removes unused Main recorder assemblies (`master:pgb` plus their
private control label and wire, constructed by
`src/PSCAD/emitters/probes.jl:output_probe!`). Electrical meters, connections,
line definitions and control modules remain intact. No new master field is
used. Base-band projects retain every tier-A channel.

| Run group | Count executed | Integration step | Sample interval | OUT files/run | Rows/run | Expected OUT bytes/run |
| --- | --- | --- | --- | --- | --- | --- |
| Resonance baseline and a/b/c injections | 4 | 2 us | 64 us | 1 | 156,251 | 26,406,493 (~26.4 MB) |
| Half-amplitude phase-a injection | 1 | 2 us | 64 us | 1 | 156,251 | 26,406,493 (~26.4 MB) |
| Half-step baseline and phase-a injection | 2 | 1 us | 64 us | 1 | 156,251 | 26,406,493 (~26.4 MB) |

Sizes are estimates from the retained fixed-width PSCAD OUT format: six signal
columns plus time, 169 bytes per row including CRLF and a 74-byte header. INF,
console/build logs and projects are additional small files. The seven expected
OUT files total **184,845,451 bytes (~185 MB)**. The old 102-signal, eleven-file
resonance projects would produce about 2.72 GB per run at 10 us; the failed run's
large OUT files were not retained locally, so this old size is an estimate,
not a measured size. Its console records 1,000,001 rows in each of eleven files.

Old resonance projects/manifest are archived under `L1-08/history/`; native
runs and failure evidence stay at their original hashes. Changed resonance
projects must run again; completed base-band projects and witnesses resume.
The unchanged 60-second output wait remains a separate robustness item.
The command above has a 120-minute deadline; **45–75 minutes** is the estimate
for the seven runs, retained base-band loading and comparison. Integration
work is unchanged, so the output reduction does not imply the same reduction
in simulation time.
