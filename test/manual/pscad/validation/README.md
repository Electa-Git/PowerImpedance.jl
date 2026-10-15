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

## L2-05/06 qualification (M9b-6)

Owner station evidence closes L2-02/03/04 at 2.5 us base / 1.25 us witness:
tier A/C and refinements passed, with admittance within 0.48% of Julia.
L2-05/06 remain pending the replacement runs below. All approved gates and
tolerances are unchanged.

L2-05 tier A and half-amplitude pass; maximum C Frobenius error is 3.280349%
at 1000 Hz against the active 5% limit. C nevertheless fails its q-d entry at
1000 Hz: complex error 0.0103594 pu exceeds the 0.00675522 pu entry limit,
and magnitude error is 7.26795%; phase error 1.35183 degrees passes.
The 2.5-to-1.25 us step witness also fails:

| Frequency | Frobenius change | Maximum entry change | Step gate |
| --- | --- | --- | --- |
| 750 Hz | 0.740756% | 1.528204% | 1% |
| 1000 Hz | 1.069342% | 2.168323% | 1% |

Both high-frequency bands carry the entry failure; 1000 Hz carries the maximum
norm and entry changes. The finer witness contains only one injected axis,
so Julia agreement is diagnosed directionally using its own measured terminal
voltage and inward converter current, not a full admittance matrix.
The normalized residual `norm(I-YJulia*V)/max(norm(YJulia*V),0.1)` falls
from **3.610393% to 1.784121% at 750 Hz** and **3.892244% to 1.911976% at
1000 Hz**: the finer step moves toward Julia in both bands. This approximately
first-order convergence does not establish the new pair's qualification.
Per-frequency changes and directional residuals are in `data/m9b6/L2-05/`.

The owner-selected new L2-05 settings are **1.25 us base / 0.625 us witness**,
with unchanged 20 us sampling, 5e-5 pu current tones, 2 s onset and main windows
[8,9), [9,10) s. Sampling is an integer multiple of both integration steps;
all windows contain whole tone/frame periods and sample counts. The complete
previous fixture is retained at `data/archive/m9b6/L2-05/`. Every new project
hash differs; no completed old run is eligible for reuse. Native reference and
operating-point files are preserved.

L2-06 stored-run re-analysis passes tier A and C, with maximum C Frobenius
error **0.479332%**. Half-amplitude changes are **0.0113473% Frobenius /
0.0247406% entry**, passing the unchanged 2% gate.
Its adaptive 75/1000 Hz witness previously used 0.1 s windows: 75 Hz completes
7.5 cycles, so the DFT correctly rejected the bins. The window selector now
rounds the 0.1 s minimum up to whole common periods, including the 50 Hz frame.
The corrected windows are **[8,8.12), [8.12,8.24) s**, with 6000 samples each
at unchanged 20 us sampling, 1.25 us integration and 5e-5 pu amplitude.
Stored witness output ends at 8.2 s and cannot cover both corrected windows.
Only the two 75/1000 Hz witness projects/runs are replaced; originals and the
previous manifest are under `L2-06/history/m9b6-incoherent-witness/`.
Main and half-amplitude projects, hashes and four completed runs are retained.
Their offline re-analysis is recorded in `data/m9b6/L2-06/`; the fixture remains
pending its step gate. Regression tests reproduce the incoherent bins and
insufficient stored duration, recover the corrected tones, and check every
selectable TLC witness band's window and sample coherence.

From the repository root, with the harness environment instantiated using the
same Julia version as the station command:

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L2-05 L2-06 --timeout=3600
```

Allow **25–40 minutes** (60-minute shared deadline): six fresh L2-05 runs and
two replacement L2-06 witnesses, plus retained-output loading and analysis.
The previous workflows took 609 / 587 s; the estimate allows for doubled
L2-05 integration work and transfer/analysis overhead. Matching completed new
runs resume after interruption. No station operation occurs during this work.

Offline on Julia **1.12.7 (repository Manifest)** and **1.10.11**:
**17,718/17,718 PSCAD suite checks** per version, including **59 name-guard
checks** and **123 adaptive-window regression checks**; generated-project XML
readback passes **1,064/1,064** per version. Logs and preservation evidence are
under `data/m9b6/`. All 194 archived L2-05 payload files verify unchanged;
L2-06's retained projects and four completed runs verify unchanged. No `src/`
changes or commits.

## L2-05 second step refinement (M9b-7)

Owner station evidence closes **L2-06: passed**, C maximum 0.479332%, with
both refinement witnesses passing. No L2-06 rerun is requested.

L2-05 at 1.25 us passes tier A and half-amplitude; maximum C Frobenius error
is **1.611251% at 1000 Hz** against the unchanged active 5% limit. Its
0.625 us witness changes by **0.531960% Frobenius / 1.107230% entry**.
The entry change still exceeds the 1% gate, so the fixture remains failed.
First-order convergence continues. Halving the pair predicts approximately
**0.265980% norm / 0.553615% entry**; these are extrapolations, not acceptance.

The owner-selected settings are now **0.625 us base / 0.3125 us witness**.
Sampling stays **20 us**, exactly 32 / 64 integration steps. Amplitude stays
5e-5 pu, onset 2 s, main windows [8,9), [9,10) s and duration 10 s.
The prepared 750/1000 Hz witness retains [8,8.1), [8.1,8.2) s; each window
has 5000 samples and whole tone/frame periods. Adaptive witnesses continue to
use the coherent common-period selector. No controller, physical parameter,
reference, tolerance or gate changes.

The complete previous L2-05 fixture is archived at
`data/archive/m9b7/L2-05/`. Native reference and operating-point files are
preserved byte-for-byte. All nine new project hashes differ; the active run
ledger is empty, and no old completed run is eligible for reuse.

With the existing Julia 1.10.11 harness environment, run from the repository root:

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L2-05 --timeout=3600
```

Allow **30–45 minutes** for six fresh runs, transfer and analysis, with a
60-minute deadline. The previous workflow took 969.5 s (16.2 minutes), including
584.8 s of native runs. Doubling native integration work gives approximately
25.9 minutes before additional overhead; the estimate includes margin.
Matching completed new runs resume after interruption. Preparation and offline
checks never contact the station. Evidence and logs are under `data/m9b7/`.

Offline checks pass on Julia **1.12.7 (repository Manifest)** and **1.10.11**:
**17,718/17,718 PSCAD suite checks**, including **59 name-guard checks**, and
**1,064/1,064 generated-project XML checks** per version. All 192 archived
payload files verify unchanged. Comparison of all nine regenerated projects
verifies that only step-dependent settings and nonsemantic XML IDs/revision
metadata differ; physical parameters and connections are unchanged.
No station contact, `src/` changes or commits.

## L2 batch B: grid-following MMC (M9b-8)

L2-01..04 and L2-06 are owner-qualified TLC results. L2-05 is running on the
owner's station; its data and archives are untouched by this preparation.
All six new MMC complete-network gates pass without tuning. Their station
tier A/C and refinement results remain pending.

| Fixture / control | SCR | Solved P / Q (MW / MVAr) | AC voltage (pu) | Rightmost complete-network root (1/s) | Base / witness (us) | Estimated live nodes | Expected time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L2-07 P/Q | 8 | 600 / 200 | 1.0289676 | passed: -10.952732 | 2.5 / 1.25 | 61 | 25–40 min |
| L2-08 P-f + Q | 8 | 600 / 200 | 1.0289676 | passed: -1.991835 | 2.5 / 1.25 | 61 | 25–40 min |
| L2-09 P + Q-V | 8 | 600 / 30.655855 | 1.0084672 | passed: -10.908770 | 2.5 / 1.25 | 61 | 25–40 min |
| L2-10 P + VAC | 8 | 600 / -37.300389 | 1.0000000 | passed: -10.890785 | 2.5 / 1.25 | 61 | 25–40 min |
| L2-11 Vdc + Q | 8 | -603.348423 / 200 | 1.0142020 | passed: -2.414274 | 1.25 / 0.625 | 65 | 35–55 min |
| L2-12 P/Q weak-grid twin | 2.5 | 600 / 200 | 1.0730249 | passed: -10.954107 | 2.5 / 1.25 | 61 | 25–40 min |

Every fixture retains the M5a/M5b `mmc_network(mode)` MMC: 1000 MVA, 333 kV
converter winding / 380 kV external grid terminal, transformer ratio 333/380,
800 kV DC, 400 submodules per arm, 50 mH / 1.07 ohm arms and 10 mF submodule
capacitance. TEC (1.386/29.70), ZSCC/CCSC (0.1048/48.1914), PLL
(0.28/12.5664), OCC (0.7691/522.7654), measurement and uncompensated modulation
are unchanged. P/Q PI is 0.1/31.4159; DVC PI 5/15; P-f K=5, cutoff 2 rad/s;
Q-V K=20, cutoff 100 rad/s; VAC PI 0/100 with **NoFilter**. Setpoint requests
are 600 MW / 200 MVAr, or 800 kV / 200 MVAr for the physical DC load case.

SCR is defined at the **external 380 kV / 1000 MVA rating**, not the 333 kV
converter winding. X/R is 10 at 50 Hz. Strong-grid R=1.796042128 ohm,
L=0.057169797 H; weak-grid R=5.747334811 ohm, L=0.182943349 H.
The ideal source is behind that RL. L2-11 consumes 600 MW through
R=800^2/600=1066.666667 ohm differential, implemented as two 533.333333 ohm
pole-to-ground legs. Its PF-only remote zero-voltage reference contracts to
ground using the existing fixture netlist conversion; no terminal DC clamp
or auxiliary midpoint shunts are added. Its AC reference is the native full
converter Y plus resistor nodal reduction. All other cases clamp DC at 800 kV.

The complete-network gate retains every converter state, both RL dq states,
and DC feedback where applicable. Native SI scaling, including the transformer
cross terms and DC output, is checked against full native three-port Y.
The existing 6001-point 0.01 Hz–100 kHz contour and all finite descriptor roots
give zero closed RHP count for every fixture. Roots and design records are
under `data/m9b8/`; no converter-only stability shortcut or gain adjustment is used.

Common scan settings: **5e-5 pu current per tone = 0.107434 A peak**, 23 coherent
integer tones at 1–1000 Hz excluding 50 Hz, 20 us sampling, 2 s onset, main
windows [8,9), [9,10) s and 10 s duration. External phase-peak bases are
310.268700753 kV / 2.148675213 kA. The shared nominal-frame shunt-current
construction measures full 2x2 AC-port Y from the actual voltage matrix and
inward converter currents. DC clamp normalization now uses the declared
converter DC base (800 kV for MMC, 640 kV for TLC).

Nine projects are prepared per admitted fixture; six normally execute:
baseline, d, q, selected half-amplitude axis and a matching half-step baseline
plus that axis. The adaptive witness selects the worst band plus 1000 Hz,
using the existing coherent common-period windows. All approved active C
**5% / 3 degrees**, floors, conditioning, drift, departures, drive/window and
amplitude/step gates are unchanged. Native settled voltage/current triangle
bounds are at most 0.001879 / 0.000371 pu; they are predictions, not station
gate results. TLC convergence does not qualify these MMCs.

With the Julia 1.10.11 harness environment, one resumable command selects all
six admitted fixtures and shares a **300-minute deadline**:

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L2-07 L2-08 L2-09 L2-10 L2-11 L2-12 --timeout=18000
```

Allow **160–255 minutes** overall. These planning estimates account for finer
integration than retained 10 s / 10 us MMC runs (11.0–12.3 s native runtime),
the larger MMC recorder payload, transfer and analysis, with TLC scan workflows
as additional timing evidence. No new station timings have been measured.
Retained averaged MMC builds reported 34–40 live nodes; the estimates above
allow for grid RL, injection and metering. Actual native runs still must report
**<100 live nodes**. Matching completed project hashes resume after interruption.

Projects, operating points, references and producing-source pins are under
`data/L2-07/` through `data/L2-12/`. Preparation creates no native run directories.
XML verification accepts explicit fixture IDs, so the batch can be checked
without reading the in-progress L2-05 payload. No station contact, `src/`
changes or commits.

Offline on Julia **1.12.7 (repository Manifest)** and **1.10.11**:
**17,925/17,925 PSCAD suite checks** per version, including **207 MMC batch
construction checks** and **59 name-guard checks**. Batch-only XML readback
passes **270/270** per version. All 54 project hashes, 78 retained payload
files and 49 producing-source hashes per fixture verify; native references
pass the unchanged one-ppm identity guard. Logs and summary: `data/m9b8/`.

## L2 batch C: GFM/energy MMC and machine (M9b-9)

All six TLC fixtures L2-01..06 are owner-qualified at 97bdf86. Batch B is
running on the owner's station; `data/L2-07/` through `data/L2-12/` are untouched.
Four batch-C fixtures pass the complete-network gate without tuning and are
prepared. Their station tier A/C and refinements remain pending. L2-17 fails
and has no projects or native runs.

| Fixture / device | SCR | Solved P / Q (MW / MVAr) | AC voltage (pu) | Gate / rightmost finite root (1/s) | Base / witness (us) | Estimated nodes | Expected time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L2-13 GFM, VSE/CCVI + TEC/ZSCC/CCSC | 8 | 742 / 0 | 1.0049037 | passed: -0.000628312 | 2.5 / 1.25 | 65 | 25–40 min |
| L2-14 LEC/CCC, compensated | 8 | 742 / 0 | 1.0049037 | passed: -0.000628319 | 1 / 0.5 | 65 | 45–75 min |
| L2-15 P/Q, disabled TEC/ZSCC, CCSC on | 8 | 100 / 100 | 1.0134393 | passed: -19.693285 | 2.5 / 1.25 | 65 | 25–40 min |
| L2-16 machine, AVR/governor/steam turbine | 8 | 900 / 6.633245 | 0.9991198 | passed: -0.197564 | 5 / 2.5 | 45 | 45–75 min |
| L2-17 GFM weak-grid twin | 2.5 | 742 / 0 | 0.9875930 | failed: +100.731659 +/- j359.941514 | requested 2.5 / 1.25 | 65 (not built) | skipped |

L2-13/14/17 retain the M6a/M6b factories unchanged: 1060 MVA, 320/400 kV
converter winding/external terminal, ratio 0.8 and 640 kV clamped DC. VSE
H=5, Kd=100, Komega=10; CCVI Rv=0.01, Lv=0.25 with its 200 rad/s second-order
filter; measurement, PLL, OCC and 200 us Padé 5/5 modulation are unchanged.
L2-14 retains original Sigma/Delta-energy PI 0.5544/5.94, CCC and compensated
modulation. No energy-gain scaling or replacement of its corrected triplen
controller frame is applied. The very slow OCC filter poles (about -0.0006283/s,
1592 s decay time) remain in the gate. The 8 s measurement candidate relies on
the native equilibrium initialization, not full slow-filter decay; measured
baseline drift and window consistency remain mandatory.

L2-15 reuses the actual legacy-mapped P2P receiving converter `c2` through the
existing test factory, including 1000 MVA, 333/380 kV, 640 kV DC, 30 mH arms,
P/Q 100 MW / 100 MVAr, NoTotalEnergyControl, NoZeroSequenceCurrentControl and
CCSC on. This clamped-DC fixture does not qualify the full P2P system.
L2-16 retains the M3 1000 MVA / 380 kV machine, 900 MW request, original voltage
request 1.000177992 pu, rt/lt, AVR, governor and steam-turbine parameters.

All grids use X/R=10 at 50 Hz and rated external voltage for SCR. For the
1060 MVA / 400 kV devices, strong-grid R=1.877428661 ohm, L=0.059760410 H;
the weak twin scales these by 8/2.5. The 1000 MVA / 380 kV devices use
R=1.796042128 ohm, L=0.057169797 H. Each AC reference measures DUT current
alone. The native machine `get_y` is per-unit; its full 2x2 AC-terminal Y is
converted to SI by Sbase/VLL^2 at the harness boundary, without a source change.
No DC port, clamp gate or converter AC subblock is assumed for the machine.

The singular KCL descriptor originally reported a finite 7.45e17/s quotient
for L2-15's algebraic infinity. QZ beta now distinguishes finite poles using
the same backward-error-scale criterion as the existing independent descriptor
test. The unchanged strict negative finite-root margin and Nyquist rule are
retained. Independent KCL elimination gives an ordinary state matrix and
checks all finite-mode counts and rightmost roots, including the weak-grid
rejection. L2-17 has two closed RHP roots at the pair shown above; its full
located spectrum and operating point are in `data/L2-17/stability_rejected.toml`.

The machine's slowest mode is -0.197563788/s (tau=5.06166 s). The next pair is
-0.472166676 +/- j8.7230884/s; governor/turbine and AVR states remain included.
Settling starts from the existing emitter's 1 s mechanical-control transfer:
ceil(1+12*tau)=62 s, also exceeding eight decay times from the 2 s tone onset.
Main and witness windows are **[62,64), [64,66) s**, with 66 s runs. A 1 s
window is mathematically coherent at 1 Hz; the chosen **2 s windows** provide
two cycles per window and more low-frequency averaging. Longer windows are
not required for coherence; actual drift/window gates decide qualification.

Other admitted fixtures keep 2 s onset, [8,9), [9,10) s main windows and 10 s
runs. All use 20 us sampling, the existing 23 integer tones at 1–1000 Hz
excluding 50 Hz, 5e-5 pu current per tone and adaptive coherent witnesses.
All active C **5% / 3 degrees**, floors, conditioning, departure, drift,
drive/window and amplitude/step gates are unchanged. Native settled-response
triangle bounds are at most 0.000426 pu voltage / 0.000463 pu current;
these are predictions, not station acceptance.

One resumable command selects only the four admitted fixtures:

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L2-13 L2-14 L2-15 L2-16 --timeout=18000
```

Allow **140–230 minutes overall**, with a **300-minute shared deadline**.
Estimates include finer compensated integration, 66 s machine traces,
transfer and analysis; no new station timings are claimed. Estimated live
nodes are below 100; actual native counts must still pass the existing gate.
Nine projects per admitted fixture normally require six fresh runs and resume
only matching completed hashes. XML checking can select L2-13..17 explicitly;
it reports the rejected fixture without reading batch B.

Projects, references, operating points and source pins are in `data/L2-13/`
through `data/L2-16/`. Gate spectra, preparation evidence and logs are under
`data/m9b9/`. No station contact, `src/` changes or commits.

Offline on Julia **1.12.7 (repository Manifest)** and **1.10.11**:
**18,032/18,032 PSCAD suite checks** per version, including **107 new batch-C
checks** and **59 name-guard checks**. Batch-only XML/rejection checks pass
**181/181** per version (180 project checks plus the explicit L2-17 rejection).
All 36 admitted project hashes, 52 retained payload files and 53 producing-source
hashes per fixture verify. Independent ODE reduction confirms every finite
mode count and rightmost root; machine synthetic dq recovery passes below
1e-9 normalized error. No gate or comparison tolerance was changed.


## L2-07 diagnosis and L2-16 refinement (M9b-10/11)

L2-07 stored-run diagnosis rejects the turns-ratio scaling hypotheses in the
measurements, OCC, PLL, voltage feedforward and interface L/R referral. An
**effective two-EMT-step lag in the exported Delta modulation path** reproduces
the high-frequency discrepancy: 5 us lag at the 2.5 us base step reduces the
133–1000 Hz residual to 0.12–0.17%; the independent 1.25 us witness fits 2.5 us
lag. Delaying only Delta reproduces it; delaying only Sigma does not. The exact
scheduling stages are not located because compiled EMTDC source was not retained.
The 11.5% plateau uses the approved Frobenius floor, and the stored witness
also fails its entry gate. Full audit and numerical evidence: `data/m9b10/`.

Owner decision: **locate the source of each step from a kept build, remove
avoidable lags, and compensate the inherent one-step lag in the exported
modulation delay when the model has one**. MMC fixtures wait for that exporter
change; this settings round does not implement it. L2-17 remains recorded as
**unstable in Julia**, with roots +100.731659 +/- j359.941514 /s, and is skipped
without tuning.

Owner station evidence for L2-16: tier A and half-amplitude passed; C error is
0.02–0.1% through 100 Hz and rises approximately with frequency squared to
5.52348% at 1000 Hz, above the active 5% limit. The 5-to-2.5 us witness fails:
1.61323% Frobenius / 3.54330% entry change against the unchanged 1% gate.
This is retained as time-step evidence, not qualification.

L2-16 is re-prepared at **2.5 us base / 1.25 us witness**. All runs remain
**66 s**, with **[62,64), [64,66) s** windows, **2 s** window duration,
**20 us** sampling, 2 s tone onset, the original 23 coherent tones and 5e-5 pu
amplitude. Physical parameters, operating point, complete-network gate and all
approved tolerances/refinement gates are unchanged. The entire previous tree
is archived at `data/archive/m9b11/L2-16/`; new project hashes differ and no
completed old run is eligible for reuse.

Allow **70–90 minutes**, with a **120-minute deadline**, for six fresh runs,
transfer and analysis. The old workflow took 47.52 minutes, including 21.94
minutes of native runs; doubling integration work with unchanged output volume
predicts about 69.46 minutes before margin. This is a planning estimate.
From the repository root, with the Julia 1.10.11 harness environment:

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/validation/run_station.jl L2-16 --timeout=7200
```

The command resumes only matching completed new-project runs. Preparation and
offline checks perform no station operation. Evidence and logs: `data/m9b11/`.

Offline on Julia **1.12.7 (repository Manifest)** and **1.10.11**:
**18,033/18,033 PSCAD suite assertions**, **59/59 standalone name-guard
assertions**, and **45/45 L2-16 project XML assertions** per version. Archived
inventory hashes, all nine changed project hashes and all 53 fresh producing-source
pins verify. Native reference and operating-point bytes are unchanged.

## Converter interface compensation and re-validation (M9b-17)

The owner-kept seq4b builds prove **exactly one inherent measurement-to-source
step** for L2-07 MMC GFL, L2-01 TLC, L2-13 MMC GFM and L2-14 LEC/compensated MMC.
All six initialized capacitor snapshots precede SIGMA/compensated MOD and are
committed from the applied physical states after source preparation. Those
states remain fixed through the solve/DSOUT, so their next-pass history matches
the acquired arm currents. No extra capacitor-to-Sigma/MOD step remains; the
owner's optional residual-lag calculation is unnecessary. Detailed native line
references and the 57 source hashes are under `data/m9b17/`.

Stage 2 exports **tau_model - dt** for positive delays with tau_model >= dt;
shorter positive delays are rejected. Zero model delay keeps zero explicit
transport and the unavoidable dt. Zero residual uses unity. TLC/uncompensated
MMC update carrier rotation and equilibrium buffer initialization together;
compensated MMC updates its abc insertion queue without a dq phase rotation.
Controller formulas, gains, initial operating points, electrical values, probes,
0.2 s divisor hold and every approved tolerance/gate remain unchanged.

L2-01..15 are freshly prepared with the frozen settings. Entire old fixture
folders are retained at `data/archive/m9b17/L2-xx/`, including completed runs and
status/evidence. New ledgers are empty and old runs are not eligible for reuse.
L2-16 remains as prepared and L2-17 remains Julia-unstable, skipped without tuning.

The first queue item is `data/m9b17/timing/converter_timing.pscx`: five grounded
source nodes, 20 ms duration, 10 us integration/sampling, with zero, one-step,
40 us and noninteger 25 us model-delay branches. Its sampled transport comparison
checks for an extra interface/library step, including fractional timing. A
failure stops the queue before L2. Its 1e-6 kV timing check is an isolated
realization check; the approved scientific fixture gates are unchanged.

From the repository root with the existing station configuration:

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/run_converter_validation.jl --timeout=43200
```

This one resumable queue runs the timing witness, then L2-01 through L2-15 in
order. It shares a **12-hour deadline** and resumes only verified completed
new-project runs. Expected total: **6–10 hours**, including witness/overhead.
Per fixture: L2-01..04/06 15–25 min each; L2-05 30–45 min; L2-07..10/12/13/15
25–40 min each; L2-11 35–55 min; L2-14 45–75 min. Timing witness: 2–5 min.
Active source pins include common and energy modulation emitters.

M4–M6 operating-point acceptance, 22 converter cases (the existing full command
remains available without the selection flag):

```sh
julia +1.10.11 --project=test/manual/pscad/validation test/manual/pscad/acceptance.jl --converters
```

Allow **90–150 minutes** for this separate acceptance command. Both classic and
builder cases, source-ramp variants, physical DC termination and M6b's 1 us step
are retained. These are estimates; native timing and A/C/refinement acceptance
are pending owner execution. No station connection occurs during preparation.

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


## M9c-2 preparation: realization comparison, settling and DC pre-charge

The original active C rule (5% complex / 3 degrees), 0.02/0.1 floors,
qualification and all quality gates are unchanged. Plain Julia C remains
reported with its own status and controls the original fixture status. Zero-model
modulation-delay converter fixtures additionally report **Julia + one inherent
interface step**, using exact `exp(-s dt)` inside modulation feedback with native
carrier corrections. This reference is frozen separately; it does not multiply
terminal Y by a phase factor. Its rows/status and the plain status are both in
the fixture summary. Neither reference can waive amplitude/step/window failure.
Positive-delay models and the machine do not receive this comparison.

L2-07–10 main windows are now **[16,17), [17,18) s**, duration **18 s**. Tone onset
remains 2 s, amplitude 5e-5 pu, dt 2.5 us / witness 1.25 us and sampling 20 us.
Sizing uses each complete-network native rightmost root, a conservative 1 pu
transient normalized by the tone and unchanged entry floor, and target 0.1%
(tenfold below the window gate). The slowest root is L2-08's -1.99183483/s;
at 16 s the estimated normalized tail from onset is below 7.8e-7. The pole
estimate does not bound residues or unmodelled sampled/transformer startup modes;
actual window and refinement measurements still determine qualification.
High-band witnesses start at 16 s and normally end at 16.2 s; adaptive lower
bands retain whole common periods and may end later. No tolerances changed.

L2-11 now has temporary pre-charge sources at its solved +/-400 kV DC poles,
closed through series breakers until 0.2 s, then released with its resistor and
Vdc controller still live. The final circuit and native reference are retained.
The exporter rule also affects L2-05; M9c-3 archives its previous evidence under
`data/archive/m9c3/L2-05/` and prepares fresh projects with the same frozen settings.
The new native startup/release remains pending station execution.

L2-01's finer-step variant is separate at `data/L2-01-1p25us/`: **1.25 us base /
0.625 us witness**, 20 us sampling, original [8,9), [9,10) s windows and 10 s main
runs. Its original 2.5 us folder and failed rows remain intact. L2-07 through
L2-15 old trees are retained under `data/archive/m9c2/`; no old run is reused.
New ledgers pin exporter/harness source hashes and start with no run records.

The isolated timing witness is under `data/m9c2/timing/`. Fractional residuals
round to nearest step, half-step ties upward: dt=10 us, model=25 us requests
15 us residual and realizes 20 us, hence **30 us total** (5 us quantization
error). Its expected response is that integer sampled shift; it is no longer
compared to a fractional linear blend. It runs first and stops the queue if its
unchanged voltage-error gate fails.

One resumable station command (existing station configuration; Julia 1.10.11):

```sh
julia +1.10.11 --project=test/manual/pscad/validation -e 'using PowerImpedance, PythonCall; include("test/manual/pscad/validation/validation.jl"); PSCADValidation.run_m9c3(timeout=43200.0)'
```

Order: timing witness; L2-05; L2-01 finer-step variant;
L2-07,08,09,10,11,12,13,14,15; M4–M6 converter acceptance (`--converters`, 22 cases).
Expected times: witness 2–5 min; L2-05 30–45 min; finer TLC 30–45 min;
L2-07–10 **40–65 min each**; L2-11 35–55 min; L2-12/13/15 25–40 min each;
L2-14 45–75 min; acceptance 90–150 min. Total **467–755 min (about 8–13 hours)**.
The shared **12-hour** deadline covers timing and L2; the final acceptance subprocess
uses the same Julia version, active project and inherited station configuration,
with its existing per-run timeouts. Timing/L2 resume hash-matching completed runs;
acceptance creates fresh exports and runs on each invocation. This is preparation only;
no new native result or passing status is claimed. All runs must report <100
live nodes (L2-11's conservative estimate increases from 65 to 67).

## M9c-6: MMC amplitude sizing and final queue

The owner approved larger current-drive amplitudes for L2-07 through L2-15.
Each amplitude targets a **0.0045 pu** maximum baseline-subtracted terminal
voltage departure in the existing coherent main windows, predicted from the
native Julia converter-plus-grid admittance and the unchanged Schroeder tones.
The combined injected voltage waveform must exceed **100 V RMS** (1000 times
0.1 V noise) on each driven axis. This is an aggregate waveform criterion;
individual low-frequency tone responses are smaller and are tabulated separately.
Predicted converter-current departures are checked against the unchanged 0.01
gate. Predictions size the runs; measured departure, window, amplitude and step
gates still decide qualification. The half-amplitude witness remains mandatory.

Per-fixture settings, predictions and offline checks are in `data/m9c6/report.md`
and `amplitudes.toml`. Complete old fixture trees are retained at
`data/archive/m9c6/L2-07` through `L2-15`; fresh ledgers contain no old runs.
Native references and operating points are retained byte-for-byte. Integration,
sampling, onset, windows, durations, circuit, fitting targets and all approved
gates remain unchanged. Main and half-step drives use the new per-fixture
amplitude; the half-amplitude drive uses exactly half that value.

From the repository root, using the existing station configuration:

```sh
julia +1.10.11 --project=test/manual/pscad/validation -e 'using PowerImpedance, PythonCall; include("test/manual/pscad/validation/validation.jl"); PSCADValidation.run_m9c6(timeout=43200.0)'
```

Order: **L2-07, L2-08, L2-09, L2-10, L2-11, L2-12, L2-13, L2-14,
L2-15, then M4–M6 converter acceptance (`acceptance.jl --converters`, 22 cases)**.
The completed timing and TLC checks are omitted. Expected total **405–660 min
(6 h 45 min–11 h)**: GFL 07–10 40–65 min each; 11 35–55 min;
12/13/15 25–40 min each; 14 45–75 min; acceptance 90–150 min.
The 12-hour deadline covers L2; acceptance uses its existing per-run timeouts.
L2 resumes only hash-matching fresh runs. Acceptance creates fresh exports/runs
on each invocation; interruption there restarts acceptance. No station contact
occurs when loading the harness or preparing these settings.

## M9c-7: crash correction and bounded settling check

The conducting-label voltage emitter overwrote its pole-loop index with a
component index, tagging both DC voltage channels as N. The signals and
circuit are present; the fix restores the P/N metadata. L2-11's electrical
projects and native baseline are retained, with corrected metadata and an
archived prior manifest. L2-12–15 retain their projects/settings; only source
pins/history are refreshed. The pre-charged M5 Vdc pair, M7 P2P classic/builder/
overhead-line builder, L2-05 and L2-11 are checked offline for P/N pairs and DC
operating-point comparison. No comparison gate is relaxed.

```sh
julia +1.10.11 --project=test/manual/pscad/validation -e 'using PowerImpedance, PythonCall; include("test/manual/pscad/validation/validation.jl"); PSCADValidation.run_m9c7(timeout=43200.0)'
```

Order: converter acceptance (`--converters`, 22 cases), L2-11,12,13,14,15,
then one L2-07 baseline/d-axis settling experiment. Fixture exceptions record
`run_or_analysis_failed` and their error, then continue. Acceptance failure is
recorded in `data/m9c7/acceptance.toml` and also permits the rest of the queue.
Interrupts still stop execution. L2 and experiment native runs resume matching
completed projects; the acceptance subprocess creates fresh exports/runs on
each invocation.

The separate experiment at `data/m9c7/L2-07-settling` has exactly **two 60 s
runs**, unchanged 2.5 us integration, 20 us sampling, 2 s onset, original M9c6
amplitude and tone phases. Three late windows **[48,52), [52,56), [56,60) s**
are compared with three early windows [8,12), [12,16), [16,20) s. Every window
is coherent for all integer tones. Directional V/Idrive and I/Idrive, both
adjacent norm/entry changes and baseline/departure/drive quality are retained.
Both late pairs must meet the existing 1% window rule. This is a bounded
settling diagnosis, with no full Y identification or fixture qualification.
Persistence at 60 s cannot establish an asymptotic limit cycle.

The M9c6 large-amplitude station result rejects M9c5's additive-noise
explanation for the persistent window inconsistency. No further amplitude,
controller, step or gate change is made. Expected total **215–365 min
(3 h 35 min–6 h 5 min)**: acceptance 90–150; L2-11 20–30; L2-12/13/15 15–30 each;
L2-14 30–50; bounded experiment 30–45. The 12-hour shared deadline starts
after acceptance. M9c-7b verification is restricted to the PSCAD suite, name
guard and affected XML on Julia 1.12.7; full package testing belongs to the owner.
