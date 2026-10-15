# PSCAD mapping and station notes

## Terminal-current orientation

`ProbeChannel.orientation` records `:into` / `:out` at the named element terminal;
non-current channels record `nothing`. This is independent of operating power direction.

| Emitter | Positive current direction |
|:--|:--|
| AC/DC impedance, OHL and cable; YY/Dyn11 | Side 1 inward, side 2 outward. Grounded impedance: sole nongrounded terminal inward. |
| AC source and synchronous machine | Outward, injection into the AC bus. |
| DC source | Inward at the positive pole. |
| TLC/MMC | DC side 1 inward; AC side 2 outward. |

The AC-cable correction swaps only the two named-node connections around its
existing side-2 ammeter in `_cable_ac_connection!`; fields, coordinates, wires,
phase order, and electrical circuit stay unchanged. Older AC-cable projects had
both terminal probes inward. Retained-run metadata is audited against each saved
project hash before analysis; it must not be replaced with current exporter metadata.
No signed acceptance equations or machine/converter current conventions changed.
The validation harness negates outward terminal currents for inward Y comparisons;
it retains outward shunt-source currents when measuring network Z directly.


This page records how PowerImpedance drives PSCAD, the facts measured on the reference station,
and the outcome of every risk experiment of the PSCAD integration. Update it whenever an
experiment closes or a station fact changes.

M0–M7 are complete: supported passive AC/DC, line/cable, transformer, machine,
TLC and MMC exports have offline coverage and station records below. The
transformer voltage-unit/level correction is included. IEEE9 passed operating-point
comparison; IEEE39 is export verified but licence-blocked, and P2P reproduced
the Julia-predicted instability rather than passing steady-state acceptance.
The sections cover station lifecycle, component mappings, control equations,
comparison rules and milestone evidence. For the user workflow and current
limitations, see [PSCAD export and simulation](../pscad.md).

## Station execution model

A `RemoteConfig` describes how to reach a Windows machine with PSCAD 5.1.0: the transport
(`:local`, `:ssh` or `:command`), the exchange directory seen from both sides
(`local_root`/`shared_root`), a station scratch root, and the station Julia and Python
executables. `compute(model, PSCADRun(); options)` stages `run-XXXXXX/` in the exchange
directory, and the supervisor (`supervisor.ps1`) copies the case into station scratch and runs
the Windows-side runner (`runner.jl`, PythonCall + `mhi.pscad` 3.1.2).

PSCAD can only build and run EMTDC cases from a logged-on desktop session. Commands that arrive
over SSH run in Windows session 0. A PSCAD started there loads projects and accepts settings, but
cannot detect compilers (`app.settings()` raises "Unable to retrieve detected software"), and
`project.build()`/`project.run()` fail with `SystemError('Could not queue task')`. The optional
`pscad_port` key selects how the runner acquires a build-capable PSCAD:

| `pscad_port` | Behaviour |
|---|---|
| unset | The runner launches a private PSCAD in its own session and quits it. Correct for a local Windows desktop; over SSH the runner fails fast with a message naming `pscad_port`. |
| set, a PSCAD listens on it | The runner attaches with `mhi.pscad.connect(host = "127.0.0.1", port)`, never quits that application, and restores its `silence` flag afterwards. |
| set, nothing listens | The supervisor starts `Pscad.exe /startup:au /port:<P> /silence:true /splash:false` in the desktop session through a transient interactive-only scheduled task (deleted immediately after start), the runner attaches, and the supervisor stops that PSCAD after the run. |

Before the runner attaches to either an existing listener or a PSCAD just started by the
supervisor, `probe.py` connects and reads `app.is_busy()` and `app.version` under a hard
60 s watchdog. This limit is a supervisor constant, independent of `RemoteConfig.timeout`,
because the automation connection's TCP timeout does not bound initialization or idle polling.
The probe changes no application settings and loads no project; its console output is retained
in `outputs/pscad-probe.txt`. It flushes diagnostics and exits directly, bypassing automation
threads and interpreter shutdown. Failure stops the run with a diagnostic asking the user to check
the instance, dialogs and desktop session, or select a port without a listener. Cleanup stops
an instance started by the supervisor. After a successful probe, the runner records its own
connection time in `outputs/pscad-console.txt`.

Every acquired application is silenced (`app.silence = true`) before any settings, load, build or
run call. An unsilenced instance blocks automation on any modal dialog; for example, loading the
staged `generated.pscx` raises "project namespace ... modified to 'generated'".

Ownership is explicit. `owner.txt` records the runner process and `pscad-owner.txt` a PSCAD
started by the supervisor (PID, executable, port, creation time). `lifecycle.ps1` is the single
implementation of stopping the runner, EMTDC executables under the case directory, and an owned
PSCAD. The supervisor's timeout path and caller-side cancellation (Ctrl-C) both use it.
Cleanup polls terminating processes with incomplete identity metadata through the grace period
and never kills them. A confirmed executable or creation-time mismatch warns and removes the
stale owner file without failing a completed run; pre-run cleanup and cancellation apply the
same rule, leaving the different process untouched. Malformed owner records and failures to
stop a positively identified owned process still raise errors.
Native calls to Python and `taskkill` capture stdout and stderr in output files and decide success
by exit code, so native stderr does not interrupt the supervisor in Windows PowerShell 5.1.
A failed stop records its output and exit code, then polls the same identity for another grace
period (10 s in supervisor cleanup and cancellation); a gone or terminating process counts as
stopped. Cleanup attempts every step, reports the primary error first and appends cleanup failures
without replacing it. When the runner console has no failure message or cleanup also failed, the
Julia exception includes the supervisor's stderr error text, decoding CLIXML error records.
Probe stderr is retained separately in `outputs/pscad-probe-stderr.txt`.

## Measured station facts (PSCAD 5.1.0, EDU certificate, GFortran 8.1 x64)

- `project.run()` builds and runs and blocks until EMTDC finishes; outputs are complete when it
  returns (the `vdiv` tutorial took 2.4-3.8 s including the build).
- Outputs are written to `project.temp_folder`, which is `<case dir>\<project>.gf81\`.
- Legacy output (`PlotType = OUT`): `<stem>.inf` with one line per channel, for example
  `PGB(1)  Output  Desc="Load Current"  Group="Load Current"  Max=100.0  Min=-100.0  Units="kA"  Path="Main(0):Load Current"`,
  plus `<stem>.infx`, plus `<stem>_01.out`, `<stem>_02.out`, ... with at most 10 channels per file.
  Each `.out` file starts with one line holding the project description (blank if none) followed by
  `round(T / sample_step) + 1` numeric rows (time first); line endings are CRLF.
- An array `pgb` (for example a 3-phase voltmeter signal `V_B2`) produces one channel per element:
  `Desc="V_B2:1"`, `"V_B2:2"`, `"V_B2:3"`.
- Settings set through `Project.parameters` read back exactly; choices decode to names (`"OUT"`,
  `"NONE"`, `"STANDARD"`), and `time_step`/`sample_step` are in microseconds.
- The EDU licence prints "Non-professional licenses are limited to a single, electrical subsystem";
  subsystem splitting is disabled.
- PSCAD restores the user's saved workspace on every start; the runner only loads, unloads and
  modifies its own staged project.
- An ideal `source_3` (`Type = 6`) produces "converted to an ideal branch" notes in the run output;
  they are informational.

## Overhead lines

Three-phase AC `Overhead_line` elements export as one TLine `RowDefn` and one
direct-connection wrapper on Main. The row contains `Line_Tower_Universal`,
`Line_Ground`, `Line_FrePhase_Options` and `Line_Out_Disp`. Two series ammeters
join the sending/receiving vertices to 36-pixel stubs and bus node labels.
Two-conductor DC lines use remote scalar interfaces as recorded under M7 below.
Other phase counts are not implemented yet.

| Julia field | PSCAD field | PSCAD unit / convention |
|---|---|---|
| `conductors.organization` / `positions` | `XC1..3`, `YC1..3` | m; tower bundle centres in native physical order |
| `conductors.nᵇ` | tower `Nc`, wrapper `Dim` | 3 phases after ground-wire elimination |
| `conductors.rᶜ` | `RadiusC` | m |
| `conductors.Rᵈᶜ` | `DCResC` | ohm/km per subconductor |
| `conductors.μᵣᶜ` | `PERMC` | relative permeability |
| `conductors.dˢᵃᵍ` | `SAGC` | m; pass tower height without subtracting sag |
| `conductors.nˢᵇ` | `NCondB` | subconductors per phase bundle |
| `conductors.dˢᵇ` | `BSP` | m; adjacent spacing in a regular polygon, `BundSym=0` |
| `conductors.gᶜ` | `ShuntG` | mho/m (S/m) |
| `groundwires.nᵍ` | `NG` | 0–2; `ElimGW=1` reproduces Julia's Kron elimination |
| `groundwires.Δxᵍ` | `XG1..2` | m; `Δxᵍ * i`, `i = -(nᵍ-1)/2:(nᵍ-1)/2` |
| `conductors.yᵇᶜ + groundwires.Δyᵍ` | `YG1..2` | m; tower height before sag correction |
| `groundwires.rᵍ` | `RadiusG` | m |
| `groundwires.Rᵍᵈᶜ` | `DCResG` | ohm/km per ground wire |
| `groundwires.μᵣᵍ` | `PERMG` | relative permeability |
| `groundwires.dᵍˢᵃᵍ` | `SAGG` | m |
| `earth_parameters = (μᵣ, ϵᵣ, ρ)` | `GPERM`, `GRP`, `GRRES` | relative permeability, relative permittivity, ohm*m |
| `length / 1e3` | wrapper `Length` | km |
| `settings.frequency` | wrapper `Freq`, display `DataF` | Hz |
| Native untransposed solid conductors | `Transp=0`, `Hollow=0`, `CDataType=1`, `GDataType=1` | direct material data |
| Three-phase single-line wiring | wrapper `Mode=1`, `Dim=3` | first vertex sends, last receives |

Julia subtracts two thirds of each conductor's sag during frequency-domain
evaluation. PSCAD performs the same correction from `SAGC`/`SAGG`; exporting
already corrected heights would apply sag twice. Ground-wire `positions` are
not used by the native evaluator, so the exporter uses the native offset rule.
The coordinate helper supports explicit phase `positions` for export planning.
The native evaluator's pre-existing rejection of explicit positions is preserved
by this pure refactor; an export that needs to solve such a network still encounters
that rejection. Correcting the evaluator guard requires a separate change.

The default ground settings reproduce `local/OHL/DUT_2.pscx`:
`EarthForm2=0`, `EarthForm=2`, `EarthForm3=2`, `GrRho=0`. Frequency/phase defaults
are `Interp1=1`, `Output=0`, `Inflen=0`, `FS=0.5 Hz`, `FE=1e6 Hz`, `Numf=100`,
`YMaxP=AMaxP=20`, `YMaxE=AMaxE=0.02 %`, `MaxRPtol=2e6`, `CPASS=0`, `DCenab=0`,
`DCCOR=1`, `enablf=1`. Display settings override only `DataF=50 Hz`; other fields
retain mhi-xml defaults.

`export_pscad(...; line_options=(; FS=1.0, Numf=200, EarthForm2=2))` applies
overrides to every line. Keys are PSCAD field names. Supported ground keys are
`EarthForm2`, `EarthForm`, `EarthForm3`, `GrRho`, `GRRES`, `GPERM`, `GRP`.
Supported frequency/phase keys are `Interp1`, `Output`, `Inflen`, `FS`, `FE`,
`Numf`, `YMaxP`, `YMaxE`, `AMaxP`, `AMaxE`, `MaxRPtol`, `W1`, `W2`, `W3`,
`ET_PE`, `NFP`, `FSP`, `MER_PE`, `MIT_PE`, `FEP`, `FDIS`, `CPASS`, `DCenab`,
`DCCOR`, `shntcab`, `enablf`. Numeric values acquire their PSCAD field units;
parameter strings retain their explicit units. Unknown keys raise `ArgumentError`
before a power-flow solve or file write.

`passive_ohl_network()` in `test/pscad/fixtures.jl` copies the 25 km `tl1`
parameters from `examples/P2P_HVDC_ALT.jl` into both network representations.
The manual acceptance script checks voltage RMS at 2% and retains each measured
error in a comparison TSV. XML checks establish export structure; native
acceptance of this exported fixture remains a separate station run.

## Risk experiments

| # | Question | Outcome |
|---|---|---|
| R1 | Source phase reference | Closed. `source_3` `Ph` is sine-referenced; `Ph = rad2deg(va) + 90` reproduces Julia's cosine reference (spike: angle error 0.000 deg). |
| R2 | `nodelabel` on 3-conductor single-line nodes | Closed. Labels join 3-phase single-line wires (6 live nodes for two 3-phase buses). |
| R3 | Single-line passives on 3-conductor wires | Closed. Master `resistor`/`inductor` expand to 3-phase; steady state matched a hand calculation to four digits. |
| R4 | Array `pgb` naming in `.inf` | Closed. `name:1` ... `name:k`, one `PGB` per element. |
| R5 | `<hierarchy>` for mhi-xml-written projects | Closed. PSCAD regenerates the hierarchy on load; no lxml workaround needed. |
| R7 | mhi-xml API details | Closed for M1 OHL. Spike B built and ran with zero errors and computed line constants: `create_tline`, `tower_universal`, row component properties and the Main TLine wrapper XML work. Cable wrappers remain in the cable step. |
| R8 | Licence and EMTDC build | Closed. Headless licence works; builds require a desktop session (see the execution model above). |
| R13 | `run()` blocking and output latency | Closed. Blocking; outputs complete on return. |
| R16 | mhi-xml through CondaPkg on Linux | Closed. CondaPkg (Pixi backend) resolves `mhi-xml==1.3.0` and `lxml`. |
| R9 | AVR field-voltage base | Closed. Unity conversion follows the open-circuit air-gap normalization and is confirmed by settled Ef=Ef0 and the AVR equation. |
| R10 | TLC dq orientation | Closed. Native primitive experiment gives d = cos(0.37), q = -sin(0.37), matching Julia. |
| R11 | TLC reactive-power sign | Closed. Station round 3 confirms solved injected Q at the AC terminal with outward converter current; internal filtered Q uses the same sign. |
| R12 | MMC Σ/Δ arm-voltage assembly sign | Closed. M5 station round 1 confirms upper = Σ − Δ and lower = Σ + Δ; all six indices deviate by at most 4.3570402e-9 over 0.1 s. |
| R6, R14, R15, R17, R18 | | Open; resolved at their milestones. |

## Acceptance record

| Milestone | Case | Result (PSCAD vs power flow, worst row) |
|---|---|---|
| M0 | `vdiv` tutorial, attach / start / no-port / Ctrl-C | 2 channels, 2001 rows; all four station paths behave as specified |
| M1 | `small_ac_network()` (classic and NetworkBuilder) | currents and voltages within 9e-9 relative; angle within 1.1e-5 deg |
| M1 | `passive_ohl_network()` with `tl1` (25 km, frequency-dependent phase model) | currents and voltages within 3.6e-5 relative; angle within 9.8e-4 deg (tolerance 2 %, 1 deg) |

## Transformers

Three-phase `:YY` and `:ΔY` transformers use `master:xfmr-3p2w` with explicit
per-phase, Y-equivalent T-model passives. The turns ratio `n` is the primary to
secondary line-to-line voltage ratio for both organizations. `:ΔY` means Dyn11:
the secondary positive sequence leads the primary by 30 degrees. This is the
user-selected convention, measured with `YD1=1`, `YD2=0`, `Lead=1` on PSCAD 5.1.

| Julia quantity / choice | PSCAD realization | Unit / convention |
|---|---|---|
| Solved primary bus magnitude | `V1 = sqrt(3) * vm_pu * base_kV` | kV LL RMS; unsolved linear plans retain the declared base |
| `n` | `V2 = V1/n` | kV LL RMS |
| `:YY` | `YD1=YD2=0`, `Ideal=0` | near-ideal master winding |
| `:ΔY` (Dyn11) | `YD1=1`, `YD2=0`, `Lead=1`, `Ideal=1` | secondary leads +30 degrees |
| `Rₚ`, `Lₚ` | series `resistor`, `inductor` before primary winding | ohm, H; per-phase Y-equivalent |
| `Rₛ`, `Lₛ` | series `resistor`, `inductor` after secondary winding | ohm, H; same values for YY and ΔY |
| `Lₘ`, `Rₘ` | separate shunts from inner primary node to ground | H, ohm; omit zero or infinite values |
| `Cₜ` | shunt at each external transformer terminal | uF = F * 1e6 |
| `Cₛ` | bridge between external transformer terminals | uF = F * 1e6 |
| Network frequency | `f` | Hz |
| Master base / options | `Tmva=1000 MVA`, `NLL=CuL=0 pu`, `Tap=0`, `View=1`, `Dtls=0`, `Enab=0` | no internal losses, tap or saturation |

Terminal ammeters precede all shunt/bridge paths, so their probes include the
capacitor currents. Winding and terminal nodes use internal labels rather than
bus labels. Each winding, meter and shunt occupies its own existing grid cell.
Frequency-dependent winding resistance and unsupported organizations are rejected.

The station experiment found `Ideal=1` YY singular: its star nodes `NT_1` and
`NT_2` have only winding connections, causing a zero diagonal. The working
near-ideal choice was `Ideal=0`, `Xl=1e-4 pu`, `Im1=1e-4 %`, `NLL=CuL=0`.
For `V1/V2=380/150`, the measured ratio was 2.533333 and the shift 0.0013 degrees.
A warning about a very small diagonal at node 2 remains. The values live in
`YY_LEAKAGE_PU` and `YY_MAGNETIZING_CURRENT_PERCENT` in the transformer emitter.
The orchestrator will tune `Im1` on the station to remove that warning while
keeping error below 1e-4. `Im1` is an existing validated master field; no other
parameter names were added. ΔY uses the ideal winding; these near-ideal fields
are ignored under `Ideal=1`.

`transformer_network(; organization)` retains the existing transformer test's
`Rₚ=10 ohm`, `Lₚ=0.1 H`, `Rₛ=1 ohm`, `Lₛ=0.05 H`, `Rₘ=1e4 ohm`, `Lₘ=10 H`,
with `n=380/150`, zero capacitances and a 400 ohm secondary load. Both classic
and builder representations declare a 380/sqrt(3) kV common phase RMS base.
Local independent 50 Hz T-model evaluation gives secondary phase RMS voltage
85.0088503113 kV, angle -2.9200869964 degrees, primary current 0.1277035631 kA
and secondary current 0.2125221258 kA. The current YY power-flow conversion
gives 85.9288070533 kV, -2.9499388843 degrees, 0.0974509630 kA and
0.2147988850 kA, respectively. The voltage difference is about 1.070603 %, and
the primary current difference is 31.043921 %. This discrepancy predates the
exporter and is material for the full-fixture station acceptance; its 1 %
voltage / 1 degree angle / 2 % current checks remain unchanged. These numbers
compare two local mathematical circuits; they are not native PSCAD measurements.

The separate ΔY model fix owns Julia's Dyn11 shift and zero-sequence isolation.
XML tests export ΔY without solved power-flow evidence. Manual acceptance
constructs the ΔY fixture and compares it only when a 50 Hz positive-sequence
transfer evaluation, relative to YY to remove the no-load loss angle, detects
the +30 degree shift. Otherwise it prints `ΔY skipped: model fix not merged`.
The original legacy ΔY analysis script is omitted by the revised task decision.
Full YY and merged ΔY circuit comparisons, capacitor paths, unbalanced behavior,
and near-ideal warning removal still require station checks.

## DC buses

A one-pin DC bus represents the differential voltage `V_P - V_N` and pole
current. Export expands it into two scalar node labels `<bus>_P` and `<bus>_N`.
The usual PSCAD identifier sanitization and collision handling apply to both
labels and probes; the probe manifest records bus ownership and the pole in
`side = "P"` or `"N"`.

| Julia quantity / choice | PSCAD realization | Unit / convention |
|---|---|---|
| Solved `busdc.vm * base_kV` | each `source_1.Vm` | kV pole-to-ground magnitude |
| Unsolved `dc_source` `Setpoint.Vdc / 2` | each `source_1.Vm` | kV pole-to-ground magnitude from the pole-to-pole setpoint |
| P source | positive `NA` to P bus through ammeter, negative `NB` to ground | station-measured polarity |
| N source | positive `NA` to midpoint ground, negative `NB` to N bus | gives negative N voltage |
| Source options | `AC=0`, `Type=6`, `Cntrl=0`, `Grnd=0`, `Tc=source_ramp` | ideal internally controlled DC, ramp in seconds |
| Series differential impedance `Z` | `Z/2` in P path and `Z/2` in N path | halve R and L; double C |
| Shunt differential impedance `Z` | `Z/2` from each pole to ground | same element scaling for series or parallel RLC forms |
| `dc_reference=:midpoint_resistors` | two `DC_REFERENCE_RESISTANCE=1e7 ohm` resistors per bus without a local source midpoint or grounded DC shunt | small grounding conductance; local rule applies even when another bus has a source |
| `dc_reference=:none` | no additional resistors | preserves a floating midpoint where present |
| Bus probes | two scalar `voltmetergnd` + PGB channels `V_<bus>_P`, `V_<bus>_N` | kV |
| Terminal probes | one series ammeter on the P path per nongrounded terminal | scalar kA, `I_<element>_<side>` |

**Voltage convention:** DC sources and converters use pole-to-pole
`Setpoint.Vdc` in kV. The DC source power-flow conversion uses
`gendc.vgdc = Setpoint.Vdc / (data["dcpol"] * V_base)`. Without a solved record,
the exporter sets each pole source to `Setpoint.Vdc / 2`, so
`dc_source(setpoint = Setpoint(Vdc = 640))` produces +320/-320 kV.
With a solved record, the bus's `vm_pu * base_kV` takes precedence and already
gives the pole-to-ground magnitude in kV.

The station measured positive `source_1.NA`: connecting NA to the positive label
and NB to ground produced +V. Both exported pole sources use this measured
orientation; the midpoint grounds are electrically the same ground node.

After the branch resistance fix (`branchdc.r = real(Z)/2` per pole), local tests
of RL (2 + s*0.05 ohm), R (400 ohm) and parallel RC (400 ohm / 1 uF) at
s=j*1e-6 and j*2*pi*50 give maximum absolute ABCD error 0.0 for both the series
and shunt two-pole reductions. With 320 and 318 kV source pole voltages, the
2 ohm differential branch has 1 ohm per pole, 2 kA current and 8 MW total loss.
Power flow gives `pf=1280.0000000000011 MW`, `pt=-1271.9999999999914 MW`,
loss 8.000000000009777 MW and current 2.0000000000000018 kA. This checks the
circuit reduction and local solver, independently of a native PSCAD run.

Grounded one-pin DC shunts are not physically supported by the current power
flow: conversion creates an ordinary `busdc` for `:gnd`. A local diagnostic
returned `LOCALLY_SOLVED` but assigned ground about 318 kV instead of zero.
`dc_network()` therefore uses the approved two-source series circuit, plus the
independent 320 kV phase RMS AC slack island required by the solver. That
island includes a 400 ohm AC shunt because NetworkBuilder rejects a lone
source terminal as a lumped pin during classic-network materialization. The
exporter supports shunts in unsolved builder plans; their equivalence and
reference suppression are tested separately without claiming a shunt power-flow
comparison.

`compare_operating_point` adds one `:voltage_dc` row per pair, comparing the
window mean of `V_P - V_N` with `2 * vm * base_kV`. It adds `:current_dc` rows
from absolute P-pole window means versus `abs(pf)/V_pp`, `abs(pt)/V_pp`, or
`abs(pgdc)/V_pp` at sources when those solved powers exist. No DC angle is
compared. Missing scalar channels or opposite-pole voltage probes are errors.
Converter-free DC networks retain relative current errors. Converter-connected
DC networks use the reference/base denominator documented in M4 below.
Manual acceptance keeps the 1 % DC voltage check and separately checks positive
P, negative N and `V_P ≈ -V_N` within 1 %. Whole-network grounding behavior and
1e7 ohm reference sensitivity (R14) still require a station experiment.

## Cables

Coaxial `Cable` elements with `eliminate=true` export a Cable `RowDefn`, one
`master:Cable_Coax` per physical position, `Line_Ground`,
`Line_FrePhase_Options` and `Line_Out_Disp`. Ground and fitting defaults and
`line_options` overrides are shared with overhead lines; the fitting start
frequency depends on the terminal buses as described below. Retained sheaths or
armours (`eliminate=false`) raise an element-named `ArgumentError`; exposed
internal-conductor interfaces are outside this step.

The layer mapping is ported from LineCableModels
`src/pscad/importexport/project.jl:246–413`. Radii and resistivity have explicit
`[m]` and `[ohm*m]` units; relative material properties and loss tangents are
dimensionless. The Julia model has no dielectric-loss input, so all `LT` values
are zero. Layer pairs must be ordered `C1/I1` through at most `C4/I4`.

| Julia quantity / choice | PSCAD field | Convention |
|---|---|---|
| Position index | `CABNUM` | 1-based physical position order |
| Element identifier | `Name` | same sanitized name as wrapper and both interfaces |
| `positions[k][1]` | `X` | m |
| `type=:underground`, positive depth | `OHC=0`, `Y=positions[k][2]`, `Y2=0` | m; Julia uses positive underground depth, unlike the donor's signed vertical coordinates |
| `type=:aerial`, positive height | `OHC=1`, `Y=0`, `Y2=positions[k][2]` | m |
| `C1.rᵢ`, `C1.rₒ`, `I1.rₒ` | `R1`, `R2`, `R3` | m |
| `C2.rₒ`, `I2.rₒ` | `R4`, `R5` | m; donor triplet `(R4,R4,R5)` |
| `C3.rₒ`, `I3.rₒ` | `R6`, `R7` | m; donor triplet `(R6,R6,R7)` |
| `C4.rₒ`, `I4.rₒ` | `R8`, `R9` | m; donor triplet `(R8,R8,R9)` |
| `C1..4.ρ` | `RHOC`, `RHOS`, `RHOA`, `RHOO` | ohm*m |
| `C1..4.μᵣ` | `PERMC`, `PERMS`, `PERMA`, `PERMO` | relative permeability |
| `I1..4.ϵᵣ`, `I1..4.μᵣ` | `EPS1..4`, `PERM1..4` | relative permittivity and permeability |
| Ordered conductor keys | `CONNAM1..4` | `C1` through `C4`; absent pairs named `none` with zero material/radius values |
| Lossless dielectrics | `LT1..4=0`, `FLT=settings.frequency` | loss frequency in Hz |
| `eliminate=true` | `elim1..3=1` for present C2..4, otherwise 0 | core retained, grounded internal conductors eliminated |
| Number of conducting/insulating pairs | `LL=2*n_layers-1`, `RorT=0`, `SHRad=1` | last-layer index, radii entry |
| Frequency-dependent phase model | `LC=2`, `CROSSBOND=0` | follows the plan and validation project; donor uses `LC=3` |
| Already converted effective Julia insulation | `SemiCL=0`, `SL1=SL2=0` | no second semiconducting-screen correction |
| Negligible aerial shunt | `ShuntA=1e-38` | mho/m, as in donor |
| `earth_parameters=(μᵣ,ϵᵣ,ρ)` | `GPERM`, `GRP`, `GRRES` | relative properties and ohm*m |

The remote-ends wrapper has `Dim=0`, `Mode=0`, `CoupleEnab=0`,
`CoupleName=row`, `CoupleOffset=0 m`, `CoupleRef=0`, `gen_cnst=1`,
`const_path=""`, `Date=0`, empty `R/X/B`, `tname=tandem_segment`, `sfault=0`,
`linc=10 km`, `steps=3`. `Length` is km. `Freq=0 Hz` for DC and the network
frequency for AC; `FLT` remains the network frequency in both cases.
Vertices relative to the wrapper origin are `(0,0)`, `(-36,0)`, `(-54,-54)`,
`(-54,-72)`. No electrical wires join these graphical vertices.
A separate grid cell holds each wrapper and interface. Row cable instances
are separated by 396 pixels (22 grid steps), snapping the plan's approximate
400-pixel spacing to the 18-pixel grid.

Both `cable_interface` instances share the wrapper `Name`, with `NCAB` equal
to the position count and `C1T..C12T=1`. Other fields copy the validation
project: `pipe=dim_s=dim_r=0`, `GroundS=GroundA=GroundOC=0`,
`ResS=ResA=ResOC=0.001 ohm`, `send_recv=recv_default_type=recv_default=0`.
The sending interface uses orientation 0; receiving uses orientation 4.
Sending core ports are `(-18,54*(k-1))`; receiving ports are assumed mirrored
at `(18,54*(k-1))`.

DC cables have two positions: core 1 joins `<bus>_P`, core 2 joins `<bus>_N`
at both ends. P has a series scalar ammeter; N has a wire stub. Three-position
AC cables use per-phase labels in A/B/C position order, joined through a
`master:breakout` to the existing three-phase bus. A bus-side array ammeter
retains one three-phase current channel per end. The breakout ports follow
the plan: `N(0,0)` and `N1(36,-36)`, `N2(36,0)`, `N3(36,36)`.
All Main electrical ports and wire endpoints lie on the 18-pixel grid.
No additional PSCAD parameter names beyond the donor, validation project and
plan are required.

`dc_cable_network()` copies the example `ugc` material data verbatim with
`rho=100 ohm*m` and length 50 km into classic and NetworkBuilder fixtures.
Manual acceptance checks DC bus voltage within 1% and pole symmetry within
1%, using `simulation_time=1.0` for the impedance DC cases and `3.0` for the
DC cable cases.
`steady_state` warns once per channel if means (scalar) or phasor RMS
magnitudes (arrays, positive sequence for three phases) differ between window
halves by more than `STEADY_STATE_SETTLING_RTOL=1e-3` relative to the larger
magnitude. The returned values and comparison table retain their contracts.

The exported cable fixtures built on the PSCAD 5.1.0 station with zero errors
and zero warnings. The impedance DC acceptance at 1 s is now exact. The DC
cable case initially failed with current 2.3% low. Station experiments through
the public `line_options` showed that a frequency-dependent cable fit starting
at 0.5 Hz leaves its DC behaviour unconstrained:

| `Line_FrePhase_Options` | `I_line_1` at 1 s / 3 s / 5 s [kA] | Window mean versus power flow, 3.6699 kA |
|---|---|---|
| `FS=0.5` (previous default) | 3.562 / 2.708 / – (falling) | 25% low at 3 s |
| `FS=0.01` | 3.698 / 3.654 / – | 0.26% low at 3 s |
| `FS=0.001` | 3.693 / 3.703 / 3.695 | 0.67% high at 5 s |
| `DCenab=1`, `FS=0.5` | Line constants fail | "Error in INVCJD. Singularity occurs" in the Yc fit |

Line elements whose terminal buses are all DC use
`DC_LINE_FIT_START_FREQUENCY=0.001 Hz` as their default `FS`. This shared
selection applies to DC cables and DC overhead lines. AC lines retain
`FS=0.5 Hz`; other validation defaults
are retained. `line_options` overrides the selected defaults, including `FS`.
`DCenab` remains zero because enabling DC correction causes the Yc fit
singularity for this cable. An explicit `DCenab` override is still accepted;
the station failure above records why it is unsuitable for this fixture.
These are measured results for this cable, not a general accuracy guarantee
for other cable fits.

Open station checks:

- Inspect the station-generated constants to confirm `LC=2` phase-model selection,
  absent-layer zeros, eliminated-core terminal count, and computed constants.
- Confirm interface core port spacing and orientation-4 mirroring, including
  three-position AC phase order and breakout wiring.
- Confirm that the validation project's `send_recv=0` at both ends pairs the
  orientation-0 sender and orientation-4 receiver with the wrapper `Name`.
- Confirm `elim1..3=1` reproduces Julia's grounded-conductor Kron reduction;
  interface grounding fields remain zero because those conductors are absent.
- Confirm empty `const_path` and `Date=0` allow portable regenerated constants,
  and check the DC zero-frequency wrapper against the 50 Hz fitting frequency.
- Run both DC cable representations with the new default at 3.0 s, inspect settling warnings and
  verify the unchanged voltage/current comparison plus pole symmetry.

XML round trips and local tests establish export structure only. The native
cable build is verified; M2 scientific acceptance with the revised default
and duration remains for the station run.

## M3 synchronous machines and control modules

`sm_network()` copies `test/adm_SM_test.jl` in classic and NetworkBuilder form:
`sg1` injects 900 MW at the 380 kV slack bus, with the default machine,
AVR, governor and steam turbine. Both exports retain solved power-flow data.
The generator's intermediate terminal bus supplies `VT` and `Pheta`; it is
separate from the external network bus beyond `rt + j*lt`. `P0` and `Q0`
come from the solved generator powers. The external current probe uses the
receiving-end power of that internal branch. No package physics is changed.

The equivalent circuit uses `sm_equivalent_circuit` without converting its
per-unit reactances to henries. The separate step-up branch uses
`Zbase = Vᵃᶜ_base^2/S_base`, `R = rt*Zbase` in ohms and
`L = lt*Zbase/ωn` in henries. This is the native Y-equivalent series branch;
there is no additional voltage-ratio transformer in the Julia machine.

### Field-name provenance

The following are every additional master field written for M3. Line numbers
refer to the read-only `local/SG/SG_Project.pscx` validation project. The
plan's master-library and emitter tables refer to PSCAD 5.1.0; the validation
file predates the explicit line-to-line voltage choice.

| Definition | Fields written | Source |
|---|---|---|
| `sync_machine` | `Rs1`, `XS1`, `XMD0`, `R2D`, `X2D`, `R3D`, `X3D`, `X230`, `XMQ`, `R2Q`, `X2Q`, `R3Q`, `X3Q`, `X231` | Plan equivalent-circuit table; validation lines 1071–1084 |
| `sync_machine` | `Name`, `Cnfg`, `Nqaxw`, `IorMVA`, `MVA` | Plan emitter table; validation lines 1123–1127 |
| `sync_machine` | `VolTyp`, `VbaseLL` | Plan 5.1.0 basic-data table; validation instead has `Vbase` at line 1093 |
| `sync_machine` | `View`, `Neut`, `MM`, `MSat`, `icTyp` | Plan single-line/internal-neutral choice; validation lines 1116–1122 |
| `sync_machine` | `OMO`, `H`, `D` | Plan basic-data table; validation lines 1089–1091 |
| `sync_machine` | `Ri` | Validation line 1086 has 300 pu; the measured iron-loss correction uses 1e6 pu because Julia has no core-loss branch |
| `sync_machine` | `VT`, `Pheta`, `P0`, `Q0`, `Trmpv`, `Sysfl`, `Ptcon` | Plan initial-condition table; validation lines 1028–1034 |
| `sync_machine` | `machsw`, `Enab`, `Igov`, `Iexc`, `Ospd`, `Term`, `Ts` | Plan controller interface; validation lines 1103–1109 |
| `sync_machine` | `InGov`, `InExc`, `PQscl`, `POut`, `QOut` | Validation lines 1012–1014, 1021–1022; output P/Q are machine-base pu |
| `sync_machine` | `Icsp`, `Icmp` | Validation lines 1112–1113; both set to 0 to retain the solved source phase without automatic power correction |
| `realpole` | `G`, `T`, `YO`, `Limit`, `Reset`, `Dim` | Plan primitive table; validation lines 1867, 1869–1872, 1875 |
| `leadlag` | `G`, `T1`, `T2`, `YO`, `Limit`, `Reset`, `Dim` | Validation lines 2012, 2014–2018, 2021 |
| `gain` | `G`, `Dim`, `DPath` | Plan primitive table; validation lines 1961, 1963, 1965 |
| `sumjct` | `A`, `B`, `C`, `D`, `E`, `F`, `G`, `Dim`, `DPath` | Plan primitive table; validation lines 1486–1493, 1495 |
| `const` | `Value`, `Dim` | Plan primitive table; validation lines 1134–1135 |
| `hardlimit` | `UL`, `LL`, `Dim` | Plan primitive table; validation lines 2041–2044 (disabled example); supported by the IR, unused by the unlimited Julia AVR/governor |
| `compare` | `X`, `OL`, `OH`, `INTR`, `Dim`, `conv` | Validation lines 1150–1155 and 1167–1172 |
| `time-sig` | No parameters | Validation lines 1159–1164 |
| `import`, `export` | `Name` | Plan module-boundary rule; validation import line 1140; export from the plan's master-library table |
| `datalabel` | `Name` | Plan signal-wiring rule; validation lines 1178, 1187 |
| `resistor`, `inductor`, `nodelabel`, `ammeter`, `pgb` | `Name`, `R`, `L`; PGB also `Group`, `Units`, `UseSignalName`, `enab` | Existing M1 passive/probe emitters and plan master-library table |

Generated form parameters are project-owned names, rather than master fields.
`AVR_<e>` declares real parameters `vref`, `T_R`, `T_B`, `T_C`, `T_A`, `K_A`,
`Vt0`, `Verror0`, `Vreg0`, `Ef_scale`, with input `Vt` and output `Ef`.
`GOV_<e>` declares real parameters `T_w`, `T_G`, `R`, `inv_R`, `T_CH`, `T_RH`, `T_CO`, `F_HP`, `F_IP`, `F_LP`,
`Tm0`, with input `speed` and output `Tm`. Time constants have form unit `s`;
other control values are dimensionless. Instances supply numeric values from
the Julia objects and solved operating point; primitive parameters refer to
those form fields by plain name. Derived values are computed in Julia.
Module ports are scalar real signals at
`(-54,0)` and `(54,0)` pixels. The writer also supports integer/text form
parameters and electrical ports, covered by a separate XML fixture.

### Controls, start-up and deliberate differences

The AVR is `1/(1+s*T_R)` on terminal voltage, `vref-v_f`,
`(1+s*T_C)/(1+s*T_B)`, then `K_A/(1+s*T_A)` and the Ef conversion gain.
The governor is `1-speed`, `1/(1+s*T_w)`, `1/R`, `+Tm0`,
`1/(1+s*T_G)`, then the cascaded chest/reheater/crossover poles. Weighted
HP/IP/LP torques sum to `Tm`. `Tm0` uses Julia's effective input,
`Pac/S_base + Ra*abs2(I_pf)`; flow and turbine pole initial outputs equal
that corrected `Tm0`.
There are no control limits because the Julia controllers have none.

`BlockGraph` lowers in its stored order, four rows per column, with columns
six grid units apart and rows four apart. Every pin has a 36-pixel vertical
wire stub and a canvas-local datalabel. The two/three-input sums use D/F/B,
with all other inputs disabled. This step implements only scalar M3 blocks.
The definitions and their instances are passive plans; Python resources
remain confined to the extension writer. `definition.module = true` is required
by mhi-xml 1.3.0 to create a module schematic before adding its blocks.

Start-up uses one `time-sig` and two `compare` blocks with `OL=0`, `OH=1`,
`INTR=0`, `conv=1`, thresholds 0.5 s (S2M) and 1.0 s (L2N). The saved validation
project has parameterized comparators, but its SG instance currently passes
zero for both times (lines 400–401); M3 deliberately uses the milestone's
0.5 s / 1.0 s sequence. Exact threshold equality follows the master block.
The validation's `Pheta=1.5708 rad` at line 1033 supports the same sine
reference as the source experiment: emit the solved terminal angle plus π/2.

Two control-interface choices differ from the plan table or saved validation:

- Use `Term=1`, matching validation line 1109, for scalar terminal voltage.
  The plan's `Term=3` gives a three-element Vt/It array and would need an
  additional tap. The scalar AVR needs only Vt. The
  [PSCAD machine interface documentation](https://www.pscad.com/webhelp-pscad-v5.1.0-ol/Master_Library_Models/Machines/Synchronous_Machine/Synchronous_Machine.htm)
  describes these dimensions and the speed-output choice.
- Use `Ts=0 s` and the explicit Julia `T_R` pole. The validation has `Ts=0.05 s`
  with its explicit measurement pole disabled (lines 2049–2062). Retaining
  both poles would add a filter absent from Julia. The exported zero setting
  builds and runs on the station.

R9 is closed with `SM_AVR_FIELD_VOLTAGE_SCALE=1.0`, retained as the named
conversion constant. Julia's AVR produces `v_df = K_A*y*Rf_d/La_d`; at open
circuit, terminal voltage is `La_d*v_df/Rf_d`. PSCAD's air-gap Ef normalization
therefore gives `Ef = K_A*y` with saturation disabled. The station confirms
that settled Ef equals the machine's Ef0 and satisfies `Ef = K_A*(vref-Vt)`
using the internal Vt mean. The validation AVR also feeds its gain-200 output
directly into `efldn` (lines 2025–2038).

### Probes, comparisons and pending station measurements

In addition to `V_<bus>` and `I_<e>_<side>`, the manifest records `<e>_P` in MW,
`<e>_Q` in MVAR, `<e>_Vt` in machine pu and `<e>_speed` in pu. P/Q come from
`POut`/`QOut` and gains of `S_base`; speed and terminal voltage come from the
machine ports. `<e>_Ef0`, `<e>_Ef` and `<e>_Tm_init` retain scalar diagnostic
channels for the initialization/base checks. Names undergo the existing
identifier sanitization and collision reservation.

`compare_operating_point` adds `:machine_p`, `:machine_q`, `:machine_voltage`
and `:machine_speed` rows. Machine P/Q use three-phase fundamental phasors of
`V_<bus>` and `I_<e>_<side>` at the public bus, with positive current toward the
bus. They compare against `pf/qf = -branch.pt/-branch.qt`, the receiving-end
powers of the internal rt/lt branch, rather than generator-terminal `pg/qg`.
Power errors are `abs(measured-reference)/elec.S_base`, with tolerance 0.01.
Terminal voltage uses `Vt = V_bus + (R_export+j*2π*f*L_export)*I`, including
the emitter's parameter rounding, comparing phase RMS magnitude with the solved terminal bus using
`rtol_v`. All three rows use the current probe's name. Speed retains
`abs(speed-1) <= 1e-3 pu`; ordinary bus/current checks retain their contracts.
The internal P, Q, Vt, Ef, Ef0 and Tm_init channels remain in the export and
`steady_state` as diagnostics, without comparison rows.

### Station measurements and acceptance settings

The classic fixture builds with zero errors and runs. Settling takes about
10 s: at 50 µs, Ef was 1.838 at 5 s and 1.896 at 15 s. Final speed is 1 pu.
Both acceptance representations now use 15 s, a 10 µs simulation step and
1 ms sampling; library defaults are unchanged. Diagnostic settled means print
after the comparison table. The station's 10 µs × 15 s run takes about 11 s.

Last-ten-cycle measurements at 15 s, with terminal quantities reconstructed
from the network probes on the 1000 MVA, 380 kV base:

| Step | Internal Q [MVAr] | Network terminal Q [MVAr] | Q gap [MVAr] | Network terminal P [MW] | Terminal \|Vt\| [pu] | Ef [pu] |
|---|---|---|---|---|---|---|
| 50 µs | -14.52 | -6.31 | -8.21 | 894.24 | 1.000223 | 1.8963 |
| 25 µs | -10.63 | -6.59 | -4.04 | 895.14 | 1.000204 | 1.8999 |
| 10 µs | -8.34 | -6.75 | -1.59 | 895.40 | 1.000193 | 1.9021 |
| Power flow | — | -6.90215 | — | 900 | 1.000178 | — |

Internal machine P/Q/Vt have an interface error proportional to step size;
the Q discrepancy is about 0.16 MVAr/µs. The sampled internal Vt has 5–11%
peak-to-peak ripple at 300 Hz while network current is clean to 1e-6. These
observations motivate the network-side phasor comparisons. Internal P is
895.45 MW at all tested steps. At the public bus the solved reference is
897.894627 − j59.536473 MVA; the station measured 892.16 − j58.27 at 50 µs
and 893.31 − j58.85 at 10 µs. The selected end and injection sign agree.

Before the power-flow reference correction described below, the Julia
state-space equilibrium at solved public-bus voltage with `Tm0=0.9` gave
terminal P=898.789379 MW, Q=-2.549114 MVAr,
|Vt|=1.000463367 pu, Te=0.9 pu and Ef=1.907326674 pu in PSCAD normalization.
Its armature loss is 1.210621 MW. The station confirmed that the inherited
`Ri=300 pu` behaves like the saved setting (line 1086),
[a terminal iron-loss shunt](https://www.pscad.com/webhelp-pscad-v5.1.0-ol/Master_Library_Models/Machines/Synchronous_Machine/Synchronous_Machine.htm).
At 10 µs and 15 s, changing Ri to 1e6 pu raised internal P from 895.45 to
898.778 MW, confirming the full 3.33 MW iron-loss gap. Julia has no core-loss
branch, so every exported machine now sets `Ri=1e6 pu` explicitly, leaving
0.001 MW loss at 1 pu on 1000 MVA. The existing formatter writes
`1000000.0 [pu]`. The measured public-bus P/Q were 896.629 MW/-59.1792 MVAr
and reconstructed terminal voltage was 219.435 kV; all approved rows passed.

The remaining public-bus P residual is 1.266 MW (0.13% of rating), consistent
with Julia's convention: power flow places Pac at the generator terminal,
while the dynamic model uses `Tm0=Pac/S_base` as mechanical torque and loses
`Ra*I^2` before the terminal. That mismatch is corrected by the
power-flow-derived references below.
The station evidence in this section used the previous references; builder
acceptance and renewed M3 acceptance remain station checks. Local XML checks
establish structure.

### Machine references derived from the power flow

The machine core now anchors its dynamic equilibrium to the solved generator
terminal P/Q and voltage. Current is positive generation and all quantities
below use the machine's three-phase MVA and line-to-line RMS voltage bases:

```math
V_t = V_{bus} + (r_t + j l_t) I, \qquad
S_t = V_t I^* = p_{pf} + j q_{pf},
```

```math
T_{m0} = p_{pf} + R_a |I_{pf}|^2, \qquad
v_{ref} = |V_{t,pf}| + E_{f,pf}/K_A, \qquad
E_{f,pf} = L_{ad} i_{df} = L_{ad} v_{df}/R_{fd}.
```

Only the armature loss is added to terminal power; the external `rt` loss is
already between the generator terminal and the public bus. The turbine
fractions are assumed to sum to one. `Setpoint.Pac`/`Qac` contain terminal
power, whereas solved `Vac`/`θac` contain the receiving-bus voltage. The core
reconstructs terminal phasors using the high-voltage solution of that branch,
then seeds rotor angle, stator/field currents, speed, governor/turbine states
and AVR states from the same point. Damper currents and speed error start at
zero. The nonlinear solver's existing iteration limit and tolerances are unchanged.

The two effective references are fixed inputs during linearization: armature
loss and field voltage are not recomputed from perturbations. A complete
operating-point setpoint supplied directly to `pftoinputs` receives the same
conversion as a power-flow result. Without one (notably when Q is missing),
`Tm0=Pac/S_base` and the configured `AVRSM.vref_SG` remain in use, with the
previous synchronous-speed/governor seeds. Machine construction alone is passive.
The configured `vref_SG` field stays unchanged; a complete power-flow point
replaces its value only in the effective input to the AVR equations.

The PSCAD emitter consumes those core inputs rather than implementing a
separate correction. M3's generator P0/Q0/VT/angle, electrical model, external
branch, scalar control graphs, gains/time constants, field-voltage scale and
iron-loss resistance remain unchanged. Tm0, vref, Verror0 and Vreg0 change.
The step-6 station rerun with these references passes in both representations;
its remaining voltage-measurement artefact is recorded below.

Fresh Julia 1.10.11 checks give the same corrected equilibrium for Classic
and Builder M3 fixtures:

| Generator-terminal quantity | Previous dynamics | Corrected dynamics | Power flow |
|---|---:|---:|---:|
| P [MW] | 898.789378917 | 900.000000000 | 900.000000000 |
| Q [MVAr] | -2.549114543 | -6.902147328 | -6.902147328 |
| Voltage magnitude [pu] | 1.000463366624 | 1.000177990961 | 1.000177992000 |

The reconstructed voltage differs from the raw power-flow terminal voltage
by 1.04e-9 pu, within its existing solver accuracy. Tests compare terminal P/Q
and the dynamic residual at the unchanged 1e-6 dynamic accuracy, and the
terminal phasor at the unchanged 1e-3 power-flow accuracy.

Across the existing 240-frequency machine validation, the aggregate admittance
change is 0.0390359% and the error against the stored PSCAD reference is
0.877175%; the original `rtol=0.009` passes without changing the data or tolerance.
The largest per-frequency change is 0.566348% at 1.5 Hz. Other converter and
example outputs remain bit-identical. Offset-machine and large PF-only stress
fixtures change through the same reference conversion and initialization.

Both exported M3 fixtures use these updated form defaults and instance values:

| Parameter | Previous | Corrected, serialized |
|---|---:|---:|
| Tm0 | 0.9 | 0.901214639 |
| vref | 1.01 | 1.00970472 |
| Verror0 | 0.009822008 | 0.00952672767 |
| Vreg0 | 1.9644016 | 1.90534553 |

### M3 station rerun with the power-flow-derived references

The step-6 station rerun reported on 2026-10-10 passes in both Classic and
Builder representations. The bus active-power error is `6.8e-5` of machine
rating, compared with `1.3e-3` before the reference correction; machine
terminal P is 899.98 MW. Bus Q is -63.71 MVAr against the -59.54 MVAr
power-flow reference, an error of `4.2e-3` of rating (previously `3.6e-4`).

The station's internal machine Vt output reads approximately `5e-4` pu high
because of the M3 control/electrical time-step interface artefact. The exported
AVR previously regulated on that output, explaining the increased Q error.
The exporter now measures the three-phase network voltage at `<e>_terminal`,
before rt/lt, and feeds the AVR `<e>_Vt_meas =
sqrt((2/3)*(va^2+vb^2+vc^2))/(Vac_base,LL*sqrt(2)/sqrt(3))` in pu.
The existing `<e>_Vt` diagnostic probe still records the machine's internal
output, and the AVR filter starts at the solved terminal voltage `Vt0`.
Local block-chain and XML checks cover this change; its station check is pending,
with bus Q error limited to `1e-3` and bus P error to `2e-4` of machine rating.
The preceding numbers remain reported native station results.

### M3 correction after the first station build

Both initial exports failed to compile on PSCAD 5.1 with 22 errors and three
warnings. The module forms lacked input intent, while `YO` and `G` fields
contained unresolved expressions. An XML round trip did not detect these
native compilation requirements.

The parameter structure follows `local/SG/SG_Project.pscx` lines 949–967:
scalar `intent="Input"`, `dim="1"`, finite `min`/`max`, `helpmode="Append"`,
and `cond`, `help`, `vis` children. The writer uses the supported mhi-xml
1.3.0 `add_real`/`add_integer`/`add_text` keywords for intent, bounds and
children. `Parameter.help_mode` writes `helpmode`; the creation keyword
`help_mode` would write an attribute with the wrong spelling. The category
already has its `cond` child. There is no parameter dimension option, so
the writer sets `dim` on the lxml node. Real bounds are ±1e308; integer bounds
are signed 32-bit; text length bounds are 0/0, as in the saved text forms.

The graphics API emits only `graphics/Port/paramlist`; there is no SVG API
in mhi-xml 1.3.0. The writer replaces the new module's graphics node with
`svg viewBox="-200 -200 200 200" size="4"`, following SG lines 969–978.
Electrical ports use `model="Natural"`, `mode="Electrical"`,
`type="NonRemovable"`. Signal ports use `model="Transfer"`, `mode="Input"`
or `"Output"`, and their signal type, following
`local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx` lines 1218–1221.
Ports retain name, pixel coordinates and dimension, have `internal="false"`,
and contain `true` CDATA. A condition, rectangle and text label complete the
module symbol. Main instances and schematic wiring retain the same ports.
The XML regression fixture copies these saved parameter and port fragments;
tests do not require the local validation projects.

The additional AVR form values are `Verror0 = vref-Vt0` and
`Vreg0 = K_A*(vref-Vt0)`; the governor adds `inv_R = 1/R`. Julia computes
them before planning the block parameters. That earlier correction retained
`Tm0=Pac/S_base`; the reference conversion above supersedes it. Every block
parameter is a literal number or plain form name;
lowering rejects expression strings. R9 and the field-voltage scale are
unchanged by this correction.

Three throwaway `sm_classic` exports isolate the changes for station review:

| Variant | Parameter metadata | Graphics | Derived values |
|---|---|---|---|
| `v1_params_only.pscx` | PSCAD 5 input form | Original graphics | Computed in Julia |
| `v2_graphics_only.pscx` | Original form | PSCAD 5 SVG | Computed in Julia |
| `v3_full.pscx` | PSCAD 5 input form | PSCAD 5 SVG | Computed in Julia |

The variants are written outside the repository, with no diagnostic switches
in production code. All three variants and the regular export failed with the
same missing-parameter errors. Adding an instance `name` attribute did not
change the result. The parameter form and SVG corrections remain because they
match saved PSCAD 5 modules; the comparisons show no harmful effect from them.

### M3 parameter-import binding confirmed by station bisection

The station built the saved `Untitled_6` module copied from
`local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx` without module errors. Removing
only its parameter-import components reproduced the missing-parameter errors.
Adding parameter imports to the generated AVR removed those errors, leaving
only the `const` block's unresolved `Value="vref"`. Restoring the schematic
`classid` had no effect. The isolated saved-module harness had a floating
`pgb` input; that error was outside the module under test.

The saved parameter imports at lines 8659–8668 are `master:import` instances
with `orient="0"` and only `Name="Kd"` or `Name="wf"` in their parameter lists.
They need no output wire when used to bind block coefficients. The shared
module-plan construction now copies the supplied canvas and lowers one import
per declared input parameter, reusing existing connected imports. All declared
parameters are bound, including the governor's retained `R` form value. The
remaining imports follow the successful diagnostic probe layout: four rows per
column, 108 pixels between columns and 72 between rows, beginning at
`(540,72)` or beyond a wider graph. This binding is in the module IR/lowering;
the extension writes these ordinary component plans without a special patch.

The AVR reference comes from the `vref` import's output and the governor's
torque reference from the `Tm0` import's output, each with the usual 36-pixel
stub and local datalabel. The AVR contains no `const` blocks; the governor
retains only the literal `1.0` speed reference. `Const` accepts numeric values
only. Derived initial outputs and inverse droop are still computed in Julia
and referenced by plain parameter names. The PSCAD 5 form, SVG graphics and
R9 field-voltage scale are unchanged.

Plan and XML tests require a unique import for every parameter, literal-only
constants and connected `vref`/`Tm0` reference signals. XML tests also compare
import definition, orientation and parameter fields against saved fragments.
The corrected classic export subsequently built with zero errors. R9 is closed;
both representations use the 15-second acceptance checks above.

## Named-node connectivity on exported canvases

Main and every module canvas connect components through named nodes. Each
connecting wire is a separate, straight, two-vertex stub from one known port
to one `nodelabel`, `datalabel` or ground. Component ports cannot coincide;
stubs cannot share endpoints or pass through another port or label. `build_plan`
and the XML writer also require a stub on every signal input and electrical
port, a stub on every label, and exactly one same-canvas writer for every read
signal name (case-insensitively). Imports and module outputs are writers;
exports, pgbs and module inputs are readers. Meter `Name` outputs and machine
`POut`/`QOut` outputs are counted without a graphic signal pin. Coefficient-only
form imports may remain unwired, as in the saved M3 canvases. The checks include
the sending/receiving ports
of a transmission-line wrapper. A wrapper's `Wire` XML element describes the
line component itself; its four geometry vertices are not connecting wires.
Cable wrappers have no electrical terminals; their `cable_interface` components
carry the terminals. Row definitions contain geometry and material records,
with no connecting wires or electrical pins (`local/OHL/DUT_2.pscx:17213–17301`
and `local/Cable/DUT_2.pscx:17227–17443`).

Orient-0 pin offsets below are pixels relative to the component anchor. The
saved mirrored/rotated transform instances retain their original orientation.

| Component | Orient-0 ports | Saved evidence under `local/` |
|---|---|---|
| R, L, C, ammeter | electrical `(0,0)`, `(36,0)` | `TLC/Simple_2L_VSC_RL.pscx:939–950`; `OHL/DUT_2.pscx:1767–1779`; `TLC/Simple_2L_VSC_RL.pscx:4317–4337` (ammeter and incident wires) |
| `source_1` | positive `(-36,0)`, negative `(36,0)` when ungrounded; external control `(0,36)` | `TLC/Simple_2L_VSC_RL.pscx:3452–3529`, orientation 4 with a grounded negative pole; M2 source polarity station check |
| `source_3` | electrical `(36,0)` with `Grnd=1` | `OHL/DUT_2.pscx:1594–1688`, orientation 3 |
| `src_ccin_1` | electrical `(0,0)`, `(36,0)`; control `(0,36)` | `TLC/Simple_2L_VSC_RL.pscx:5589–5613`, orientation 1 |
| breakout | common `(0,0)`, phases `(36,-36)`, `(36,0)`, `(36,36)` | `TLC/Simple_2L_VSC_RL.pscx:3383–3529`, orientation 4; `Cable/DUT_2.pscx:13590` |
| voltmeter, ground-referenced voltmeter | `(0,0)` and `(0,36)`; ground-referenced version only `(0,0)` | `TLC/Simple_2L_VSC_RL.pscx:5618–5630`; `SG/SG_Project.pscx:2425–2435` |
| `xnode` | electrical `(0,0)` | `TLC/Simple_2L_VSC_RL.pscx:3377–3382,5604–5613` and the incident wires |
| transformer | electrical `(-54,0)`, `(36,0)` | `OHL/DUT_2.pscx:1689–1766` |
| cable interface | `(-18,54*(i-1))`, in cable order | `Cable/DUT_2.pscx:1644–1703`, orientations 0 and 4 |
| synchronous machine | electrical `(36,0)`; Ef `(-36,-72)`, Tm `(0,72)`, speed `(-36,72)`, Vt `(36,-72)`, Ef0 `(-72,-72)`, Tm_init `(36,72)` | `SG/SG_Project.pscx:998–1198`, orientation 4; existing M3 lowering |
| import/export, constants, time signal | `(36,0)` | `TLC/Simple_2L_VSC_RL.pscx:2084–2106,5923–5929`; `P2P HVDC/PowerModelsACDC_ACdroop.pscx:13112–13118` (`const`) |
| unary control blocks | input `(-36,0)`, output `(36,0)` | primitive citations in M4 below; `SG/SG_Project.pscx:1865–1944,1959–1976,2010–2024` (M3 pole, gain, lead-lag) |
| mult/div/dot product | left `(-36,0)`, lower `(0,36)`, output `(36,0)` | saved abc/dq canvases, `TLC/Simple_2L_VSC_RL.pscx:1851–3234` |
| sum junction | enabled D `(-36,0)`, F `(0,36)`, B `(0,-36)`; output `(36,0)` | same saved abc/dq canvases; `SG/SG_Project.pscx:1945–1958` (three-input sum) |
| merge, tap | saved orientation-4 merge inputs `(-18,18*(i-5))`, output `(0,18*(N-3))`; orientation-0 tap input `(0,-18)`, output `(0,0)` | `TLC/Simple_2L_VSC_RL.pscx:2164–2185,2214–2235,4498–4517` |
| pgb | signal `(0,0)` | `TLC/Simple_2L_VSC_RL.pscx:1009` and incident wire; M1–M3 output stubs |

The saved VSC2L boundary uses **explicit physical connections** to its `xnode`
anchors. The exporter keeps these connections: each xnode has a stub to an
internal electrical label shared with the plant ports. The internal label is
distinct from the xnode's boundary name. No implicit connection between an
xnode and a nodelabel with the same name is assumed or used. That alternative
has no saved witness and remains untested.

Internal junctions use case-insensitive name reservations. Main's reservations
also contain the network and probe identifiers; module reservations are local
to each canvas. Empty series paths identify their electrical labels without
adding a circuit element. The saved abc/dq blocks keep every parameter and
orientation; only their coordinates and wires change. Tests compare their pin
net partitions against the original saved fragments. M1–M3 native acceptance
passes after the shunt-meter correction; M4 acceptance progress is recorded below.

## M4: two-level converter export

The modular `TLC` exporter emits shared copies of the validated abc/dq canvases,
per-element MEAS, PLL, PCTRL or VDCCTRL, QCTRL, OCC and MOD definitions, and a
parent `VSC_<element>` with electrical `AC` (dimension 3), `DC_P` and `DC_N`
ports. Its five scalar output ports are `P_ac_f`, `Q_ac_f`, `v_dc_f`, `omega_c`
and `theta_c`; only their `<element>_<signal>` PGBs are added on Main. Electrical
terminal current and bus voltage probes retain the existing naming scheme.

### Saved component evidence and control equations

All source locations below refer to PSCAD-saved files under `local/`.
`test/pscad/fixtures/tlc_saved_fragments.xml` preserves complete saved instances,
with source file and line comments. XML tests check the new emitted master field
names against these witnesses and compare the copied transform instances,
parameters and orientations with the saved canvases; named-node rewiring and
layout changes preserve their original pin-net partitions.

| IR / circuit operation | PSCAD mapping | Saved source |
|---|---|---|
| Integrator | `integral`: `T`, `Yo`, `YLo`, `YHi`, `Extrn=0`, `Reset=0`, `Mthd=0`; explicit input gain for Ki | `TLC/Simple_2L_VSC_RL.pscx:3530–3545` |
| Multiplication / division | `mult` / `div`: `Dim=1`, `DPath=1`; left input and lower input | same file, `3001–3007` / `2100–2106` |
| Sine / cosine | `trig`: `Type=1/2`, `Mode=0`, `Dim=1` | same file, `2113–2122`, `2190–2198`; copied transform wiring |
| Square / square root | `square` / `sqrt`: `Dim=1`, `DPath=1` | same file, `1210–1217` / `1223–1230` |
| First-order filter / support lag | Existing `realpole` lowering with `G`, `T`, `YO`, `Limit=0`, `Reset=2`, `Dim=1` | same file, `3798–3816`; existing M3 lowering |
| Second-order filter section | Two `integral` blocks: `y'' = W2*(u-y) - D*y'`, with precomputed `W2=ωc²/b`, `D=a*ωc/b` | integral above, gain/sum fields inherited from M3; coefficient authority `converter/common/kernels/filter.jl` |
| Exact delay | `tdelay`: `T`, `N=ceil(T/time_step)+1`, `Intp=0`, `Dim=1`, `Init=1`, `X0` | same file, `5037–5050`; initial history confirmed in station round 2 |
| Ordered scalar merge | `datamerge`, orientation 4: `N=2/3`, `Type=2`, `Disp=1`, `View=0`, `Dim1…DimN=1` | same file, `2164–2185`, `2214–2235` |
| Array entry | `datatap`, orientation 0: `Index`, `Dim=1`, `Type=2`, `Style=0`, `Disp=1` | same file, `4498–4517` |
| abc/dq and inverse | Copies of `abc2dq_1` / `dq2abc`, `Xb=1`, `qaxis=1`; their original import/export, trig, dot-product, merge and wire structure | same file, definitions starting at `2457` / `1851` |
| Three phase voltages | `source_1`, orientation 4, `Type=6`, `Grnd=1`, `Spec=0`, `Cntrl=1`, `AC=0`, `Tc=0`; separate per-phase R/L | same file, `3452–3529`; resistor/inductor fields `939–950`, breakout `3383–3388` |
| DC current balance | `src_ccin_1`, orientation 1, `Cntrl=1`, `Tc=0`; phase voltage/current products summed and divided by measured pole-to-pole voltage | same file, `5589–5630`; `xnode` binds electrical module ports |
| DC start-up handover | `time-sig` → `compare`: `X=0.2`, `OL=nominal pole-to-pole kV`, `OH=v_dc_m`, `INTR=0`, `Dim=1`, `conv=0`; output `v_dc` | same file, `5885–5888`, `5912–5929`; guarded voltage supplies all DC divisions and modulation scaling |

Butterworth filters use the existing `BUTTERWORTH_TABLE` without another
coefficient table. A section `(a,0)` becomes `1/(1+s*a/ωc)`; `(a,b)` becomes
`(ωc²/b)/(s²+(a*ωc/b)*s+ωc²/b)`. The explicit second-order realization allows
both output and output derivative to be initialized. Unsupported filter families
and control variants fail with an element name and concrete control type.

The MEAS block filters controller-frame voltage/current before multiplying them.
It implements the current Julia equation `Q_ac = -v_q*i_d + v_d*i_q`, including
its sign. PLL uses `dξ_pll/dt=-Ki*v_pll`, `Δω=-Kp*v_pll+ξ_pll` and
`dΔθ_pll/dt=ωbase*Δω`. The EMT transform angle is `ωbase*t+Δθ_pll`.
Frequency support is `ξ_f' = ωc*(-Kω*(omega_c-1)-ξ_f)`; voltage support is
`ξ_v' = ωc*(K*(Vacref-hypot(v_d_f,v_q_f))-ξ_v)`. VDCCTRL negates its PI
output. QCTRL and PCTRL use the native PI signs. OCC retains voltage feed-forward
and cross terms `+Lpu*omega_c*i_q_f` / `-Lpu*omega_c*i_d_f`, or the configured
constant frequency factor. TLC's current `input_signals` supplies zero `i_dc`
to MEAS; the exporter retains that signal and the resulting Pdc measurement.
The electrical DC current source independently implements physical power balance.

MOD first converts voltage references to modulation in the controller frame,
rotates back to the global synchronous frame, delays the two scalar dq commands,
and applies the core `phase_compensated_dq` rotation by `+ωbase*Td`. It then
uses the nominal EMT angle for dq/abc conversion. After the start-up handover,
physical phase commands are
`vM_abc = m_abc * Vdc_measured * vACbase/(2*vDCbase)` in kV. The AC peak base
factor is necessary: Julia's modulation command is not an SI duty ratio.
After that handover the DC absorption current is
`sum(vM_phase*i_phase)/Vdc_measured` in kA.
The source command is its negative: `src_ccin_1` orientation 1 injects positive
current out of upper terminal A, whereas Julia's electrical `i_dc` is positive
for absorbed DC power. This direction is established by the PSCAD 5.1.0
station experiment below.
The saved stage's two auxiliary 100 μF capacitors are disabled in the reference
(`5870–5884`) and are absent from `ElectricalTLC`; the exporter omits them.
Grounded ideal phase sources retain the saved
common reference; external DC sources/reference resistors set pole symmetry.

### Converged-state initialization

`update(::Element{<:AbstractStateSpace}, setpoint)` retains its converged state
vector after successful linearization, together with the model and setpoint.
The internal, unexported `_steady_state` accessor returns a copy in the model's
state order, including the same below-`1e-15` zeroing used for linearization.
The exporter reads that vector and evaluates the existing state-space blocks;
it no longer constructs or solves a second nonlinear problem. Builder export
passes the solved network's elements in the declared order, preserving the
builder definition. For a direct netlist whose elements have not been solved
at its effective setpoint, the accessor calls the core `update` once and then
reuses its retained vector. The core's initial guesses, `maxiters=20`,
`abstol=reltol=1e-6` and successful-return check are unchanged. Every generated
dynamic control block uses the converged vector or its evaluated outputs.

| Julia solved state(s) | PSCAD initial value |
|---|---|
| `vG_d_f_x*`, `vG_q_f_x*`, `i_d_f_x*`, `i_q_f_x*` | Each corresponding MEAS section output `Y0=C*x+D*u`; second-order derivative `DY0=C*(A*x+B*u)` |
| States of optional `v_dc`, `i_dc`, `θ`, P/Q/Pdc measurement filters | Same output/derivative projection, using their own solved state slices and raw input |
| `v_q_pll_f_x*` | PLL filter section output and derivative from the solved realization |
| `ξ_pll` | PLL PI `pllI0` → `integral.Yo` |
| `Δθ_pll` | `theta0` → EMT angle `integral.Yo`; nominal ramp subtraction gives the relative controller angle |
| `ξ_P_ac` / `ξ_v_dc` | PCTRL `pI0` / VDCCTRL `vdcI0` → `integral.Yo` |
| `ξ_Q_ac` | QCTRL `qI0` → `integral.Yo` |
| `ξ_f_supp` / `ξ_vac_supp` | Support-lag `support0` → `realpole.YO` |
| `vG_d_occ_f_x*`, `vG_q_occ_f_x*` when present | OCC feed-forward section output and derivative from the solved realization |
| `ξ_id`, `ξ_iq` | OCC `dI0`, `qI0` → `integral.Yo` |
| `m_delay_x1…x6` plus solved undelayed dq commands | Padé output `C*x+D*u` → exact-delay `dDelay0`, `qDelay0` → `tdelay.X0` |

At an equilibrium every unity-DC-gain Butterworth cascade section has the same
output; the coordinate translation uses that solved output, rather than copying
realization coordinates into a different state basis. `NoFilter` has no dynamic
state or initial-value field. All coefficient products, divisions and initial
values are precomputed form values; block fields contain only literals or plain
parameter names. Each form parameter has exactly one schematic import.

### Power comparisons and pending station checks

The AC current probe points from TLC toward the bus. The shared machine/TLC
comparison calculates three-phase fundamental power `sum(V_k*conj(I_k))/2`
using peak phasors in kV/kA, and compares TLC side 2 with the solved
`-pgrid/-qgrid` in MW/MVAr. The error is `abs(diff)/elec.Sbase`, with the binding
`0.01` tolerance; both rows use `I_<element>_2`. Existing bus voltage, relative
angle, terminal current and DC rows are retained.

Internal P/Q are pu settled means on the converter's `elec.Sbase`. Their
references are the solved terminal flows divided by that rating. Their errors
are `abs(measured_pu-reference_pu)`, equivalently `abs(diff_MW)/Sbase` for P
and `abs(diff_MVAr)/Sbase` for Q, with tolerance `0.01`. This uses the same
rating normalization as the network-side rows. The power-flow adapter
sets `Pac=-pgrid` and `Qac=qgrid`; native `q_ref=-Qac/Sbase` therefore equals
injected `-qgrid/Sbase`. With the inherited cosine d / sine q orientation,
`-v_q*i_d+v_d*i_q` is standard injected Q. These signs and conversions are
checked in Julia equations, synthetic output tests and station round 3, which
closes R11. `v_dc_f`, `omega_c` and `theta_c` are diagnostics. The absolute
EMT angle increases at nominal speed; its generic settling warning is expected
and does not establish converter non-settling.

The two classic/builder fixture pairs use the test's 100 MVA, 220 kV AC,
640 kV pole-to-pole DC data, Butterworth measurement/PLL filters, OCC and
200 μs Padé(3,3) specification. Both contain the requested 10 km DC cable.
The original case-2 admittance test connects directly to its DC source; this
fixture deliberately adds the case-1 cable. Case 1 holds both cable ends at
640 kV and consequently solves near zero P (approximately -0.0032 MW), rather
than its original requested 70 MW. The station measured approximately
`-3.083e-5` pu against `-3.2e-5` pu: a `1.17e-6` pu difference, or 117 W on
100 MVA. Rating normalization accepts that difference; dividing by the
near-zero reference would report approximately 3.7 %. The solved reference
is retained exactly. Both internal powers use rating normalization, replacing
the previous 1 % relative rule so near-zero references do not amplify small
absolute residuals.

Proposed native acceptance settings are **10 s, 10 μs integration, 40 μs
sampling**, and the supported **0.05 s source ramp**. The integration/sampling
match `TLC/Simple_2L_VSC_RL.pscx:4–6`; 10 s covers twenty 0.5 s support-lag time
constants. These acceptance/experiment exports select the existing
`dc_reference=:none`: the DC source midpoint grounds the connected cable.
Additional reference resistors would change case 1's near-zero P balance.
Both fixtures retain the existing frequency-dependent cable fit and
DC fitting corrections. Inspect its build diagnostics and P/Q/current settling
warnings before accepting the final ten-cycle window; elapsed duration alone
is insufficient (R15).

R18 replaces Padé(3,3) with exact delay in the same dq coordinates, retaining the
phase rotation. Both have unity DC gain, so steady state is unaffected. Their
transient and high-frequency responses differ; this export does not certify
admittance equivalence. Station round 2 closes R10, integrator gain/limits,
first/second-order initial values, delay initial history and array dimensions/pins.
The divider's zero-denominator behavior is measured. Station round 3 confirms
the corrected start-up sequence and full-converter equilibrium and closes R11.
After the shunt-meter correction, full native M1–M3 acceptance passed again:
small AC `9e-9`, OHL `3.6e-5`, YY `3.2e-4`, DC `8e-10`, DC cable `0.97 %`
and machine `1.4e-3`. Named-node TLC case 1 classic passed every AC, converter
power and voltage row. Acceptance stopped on its near-zero-reference DC
current rows; case 1 builder and both case 2 variants await that acceptance
continuation. The approved DC current normalization below addresses those rows.
No native numerical acceptance is inferred from Julia/XML tests. The
experiment exports and their decisive channels are described in
`/tmp/pscad-m4-experiments/README.md`.

The station generator is `test/manual/pscad/write_m4_experiments.jl`, alongside
the acceptance tooling. Run it in the PythonCall-enabled XML environment to
write the seven projects; it imports the offline fixtures from
`test/pscad/fixtures.jl`. The manual-script identifier guard checks it, including
the local bindings in its comprehensions.

### Converter-connected DC current comparisons

DC current magnitudes in a DC network containing a converter use the following
error, with the existing `rtol_i` tolerance (default `0.02`), to retain a
rating-based denominator at low load:

`abs(measured_kA-reference_kA) / max(abs(reference_kA), Sbase/vDCbase)`.

`Sbase` is the converter rating in MVA and `vDCbase` its pole-to-pole kV base;
the owned electrical model's `iDCbase` supplies this kA base. It is independent
of the solved DC bus voltage used to obtain the reference `abs(P)/V_pp`.
Connectivity means the transitive connected component of nongrounded DC buses
joined by each element's DC terminals. Thus a DC cable joins its two ends and
propagates the base to the remote DC source. AC terminals and common ground
do not join DC components. Converter terminals, DC branch ends and DC sources
in that component all use the base. Components without a converter retain
the previous relative rule, including its zero-reference behavior.
Several converters with identical current bases can share a component.
Different bases currently raise an explicit comparison error pending selection
of a shared base; no aggregation rule is inferred. Both M4 fixtures have one
converter.

For 100 MVA and 640 kV, the base is `0.15625 kA`. The reported case-1 means
`7.837e-5 kA` and `9.956e-5 kA`, against references `2.66e-13 kA` and
`1.83e-14 kA`, produce errors approximately `0.000501568` and `0.000637184`.
All four current rows pass `rtol_i`. This changes comparison normalization
only; channel names, power-flow references and exported equations are unchanged.

### Case-1 residual DC power and cable current

The native final ten-cycle window (`9.8 < t <= 10 s`) in
`local/pscad-exchange/run-uAk5Oe/outputs/` gives signed converter current
`-9.9562135e-5 kA` and source current `+7.8371025e-5 kA`, with approximately
640 kV pole-to-pole voltage. Positive terminal current means absorption into
the element. The converter therefore injects approximately **63.72 kW** into
the DC cable, and the source absorbs approximately **50.16 kW**. Magnitude
comparison does not retain this directional information.

Julia's simultaneous dq power balance is
`i_dc=(vMd*i_d+vMq*i_q)/v_dc`
(`src/Network/Components/converter/TLC/electrical.jl:116–120`). Its case-1 DC
power is approximately zero: the solved AC absorption supplies reactor loss.
The exported instantaneous balance multiplies each phase voltage command by
the measured electrical current, sums the products and divides by measured
Vdc (`src/PSCAD/emitters/tlc.jl:109–112,166–171`). These are signals on the
control/electrical time-step interface.

Network-side fundamental phasors from the native output give
`S_ac=-0.003082707845+j20.000000298403 MVA`. Adding the exported reactor's
`Z*sum(abs2(I_peak))/2`, with `Z=0.3872+j38.72 ohm`, gives voltage-source
power `S_M=0.000117292326+j20.320000315554 MVA`. For
`δ=2π*50*10e-6`, `real(S_M*exp(jδ))=-0.063719766957 MW`; the signed measured
DC power is `-0.063719767907 MW`. They differ by **0.00095 W**. This is strong
evidence of a one-step voltage/current alignment in the instantaneous power
calculation: `P_M*cos(δ)-Q_M*sin(δ)`, whose reactive cross term is approximately
63.84 kW. It explains the converter discrepancy much better than cable leakage
alone. The exact native internal scheduling has not been inspected; this is
a quantitative inference from network phasors and signed DC means. No timing
compensation or physics change is made. Repeating at 5 μs and 2.5 μs, with the
same channels, should reduce that cross term to about 31.92 kW and 15.96 kW if
this explanation holds. It does not establish transient equivalence.

The cable-end difference is **21.191 mA**, equivalent to approximately
13.56 kW at 640 kV. Julia's cable shunt admittance is `Y=s*inv(P)`
(`src/Network/Components/transmission_line/cable.jl:364`) and has no DC shunt
conductance. The export's explicit `ShuntA=1e-38 mho/m` over 10 km is far too
small to explain the difference; the case export records it at
`local/pscad-exchange/exports/m4-EzT7OH/tlc_case1_classic.pscx:9227,9283`.
Its frequency-dependent fit starts at `0.001 Hz` (line 9350), with DC correction
disabled (line 9369) following the documented failed DC-correction fit.
PSCAD documents that finite low-frequency fitting can introduce an effective
shunt conductance substantially above the explicit value and lose DC current
between ends: [Curve Fitting Starting and End Frequencies](https://www.pscad.com/webhelp-pscad-v5.1.0-ol/Master_Library_Models/Transmission_Lines_Cables/Distributed_Line_Models/Curve_Fitting_Starting_and_End_Frequencies.htm).
It also describes DC fit errors and the role of
[DC Correction](https://www.pscad.com/webhelp-pscad-v5.1.0-ol/EMTDC/Transmission_Lines/DC_Correction.htm).
The source current mean changes by about 0.329 mA between the last two-second
window and the final ten cycles, so slowly settling fit states may contribute
as well. A longer run and native fit diagnostics can distinguish a remaining
tail from a persistent effective DC shunt. The inferred 21 mA is not assigned
to a physical leakage parameter, and no cable settings are changed.


### M4 station correction: intrinsic names and DC source direction

The first PSCAD 5.1.0 build reported reserved-name errors for the bare signal
`time` in all four TLC cases, the primitive project and the divider project.
PLL and MOD now use `pll_clock_s` and `mod_clock_s`; isolated experiments use
`experiment_clock_s`. M3 machine signal names retain their element prefix.
`Signal` rejects the 120 intrinsic identifiers documented in PSCAD's
[Include Files](https://www.pscad.com/webhelp-pscad-v5.1.0-ol/EMTDC/Custom_Model_Design/include_files.htm)
tables, with case-insensitive comparison. This includes `TIME`, `DELT`, the
other `s1.h` variables, storage arrays/pointers, network variables, constants,
file variables and warning identifiers. The source comment cites that list.

Generated name reservations also compare case-insensitively. Each netlist or
project builder owns a dictionary from lowercase identifiers to their retained
spelling; each candidate uses a hash lookup, including numeric suffixes. Seeded
names are folded once when that dictionary is constructed. Before applying
this change, all 18 classic/builder exports for small AC, OHL, YY, Dyn11, DC,
DC cable, machine and the two TLC cases were compared: no node label, signal,
module/definition or probe/PGB identifier changed. The 176 fixture probe names
are retained as an independent XML regression fixture. The six failed naming
assertions concerned synthetic `Bus`/`bus`, `Probe`/`probe`/`PROBE`, aggregate
uniqueness, and truncated stems/suffixes; they were not fixture collisions.

The DC injection project built and ran at 10 μs integration and 40 μs sampling.
A +0.01 kA command into 10000 Ω produced +100.0 kV at the upper A pole from
the first sample to the end, with zero peak-to-peak variation; the grounded
lower pole measured zero. Therefore `Cntrl=1` accepts a DC instantaneous command,
and a positive command injects current out of A into the external circuit.
The TLC stage retains its saved orientation and pole wiring, and negates the
calculated absorption current before the source input. Julia's
`ElectricalTLC.state_space!` calculates positive absorption as
`i_dc=(vMd*i_d+vMq*i_q)/v_dc`. Tests compare the emitted command with that
owned output in SI units for both current directions and check power balance.
No core equation or internal measurement sign is changed.

This closes the isolated source-direction/control-mode question. At that round,
the six reserved-name failures supplied no native dq, Q, delay-history or
divider-startup results. The next round supplies the results below.

### M4 station round 2: primitives and start-up handover

PSCAD 5.1.0 built all seven experiments without errors. At 10 μs integration
and 40 μs sampling, every primitive gave its expected value. The integrator
started at 0.5, gave 0.50008 at the first 40 μs sample and reached its 1.0 limit
at 0.25 s. Product/division gave 6/1.5, sine/cosine 0.5/0.8660254, square/root
9/3, and the array entries 2/3. The first-order pole started at 0.4, gave
0.40239521 at 40 μs and settled to 1. The second-order filter started at 0.4,
gave 0.40001348 at 40 μs and settled to 1. Delay history was 0.7, followed by
the input delayed 200 μs (0.2498 at 0.25 s).

**R10 is closed.** Independent balanced phase inputs at 0.37 rad produced
`Frame_P_ac_f=0.93232735=cos(0.37)` and
`Frame_Q_ac_f=-0.36161543=-sin(0.37)`. The inverse phase-A value was also
cos(0.37). This matches Julia's `vG_d=v*cos(theta)` and
`vG_q=-v*sin(theta)`; no q-axis correction is needed. At this round, R11 still
required settled network-side P/Q evidence from the full cases; round 3
subsequently supplied it.

The isolated divider silently returned `1e99` at a zero denominator, then
6250 at 40 μs and 1.0 at 0.25 s for `0.25/t`. All four full TLC cases built
cleanly but became non-finite during start-up. In case 2, measured `v_dc_f`
started at zero despite its approximately 0.99997 pu equilibrium reference;
the voltage divisions produced values of order `1e99` at 240 μs and NaNs at
280 μs. A completed EMTDC run therefore did not establish a finite solution.

The saved start-up constructions were inspected before changing the export:

| Saved project under `local/` | Start-up evidence, with line ranges |
|---|---|
| `TLC/Simple_2L_VSC_RL.pscx` | Active AC source `1291–1332` and two DC sources `1733–1792` use `Tc=0.05 s`. Controlled phase voltages use `Tc=0` (`3452–3529`). The active DC-current source has `Cntrl=1`, `Tc=0.05 s` (`5589–5598`). |
| Same TLC project | The active time comparator (`5912–5929`) substitutes 640 kV until 0.2 s, then `v_dc_m`. Its `v_dc` output (`5885–5888`) feeds the DC-current denominator (`5775–5806`), normalized voltage/modulation denominator (`5825–5859`, `5562–5568`) and phase-voltage scaling (`5784–5795`). The two 100 μF capacitors are disabled (`5870–5884`). All six control integrators use `Reset=0` (`3530–3545`, `3620–3635`, `4041–4056`, `4109–4124`, `4155–4170`, `4229–4244`). |
| Same TLC project | `select` blocks (`4717–4768`) choose frequency/voltage support according to imported `f_sup`/`v_sup`; they are configuration selectors. The `emtconst` blocks at `4542–4555`, `4769–4775` supply literal constants, rather than a timed converter enable. |
| `GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx` and `Q-V_Droop/GFL_MMC_Validation.pscx` | Both AC/DC voltage sources use `Tc=0` (`686–727`, `799–824`). `PICtrl_1` has `Reset=1` (`3356–3370`, `3413–3427`) driven by a time comparator (`3169–3181`). Its `t_rst` is passed through the parent (`9284–9309`) and is zero in the saved Main instance (`621–644`). Arm-voltage initialization is the averaged capacitor state's `integral.Yo=640` (`7699–7714`), rather than an added TLC capacitor. |
| `GFL-MMC/VAC_Control/GFL_MMC_Validation.pscx` | Voltage-source `Tc=0` (`715–756`, `828–853`), PI comparator `3198–3210`, `Reset=1` (`3385–3399`, `3442–3456`), saved `t_rst=0` (`650–673`), arm-state `Yo=640` (`7728–7743`). |
| `GFL-MMC/DC voltage droop/PSCAD model/GFL_MMC_Validation.pscx` | Voltage-source `Tc=0` (`689–730`, `771–796`), PI comparator `3143–3155`, `Reset=1` (`3330–3344`, `3387–3401`), saved `t_rst=0` (`621–644`), arm-state `Yo=640` (`7673–7688`). |
| `GFL-MMC/DVC-Mode/GFL_MMC_Validation.pscx` | AC source `Tc=0` (`2088–2129`), internally controlled DC current `Cntrl=0`, `f=0`, `Tc=0.05 s` (`2565–2574`), PI comparator `4611–4623`, `Reset=1` (`4798–4812`, `4855–4869`), saved `t_rst=0` (`2020–2043`), arm-state `Yo=640` (`9141–9156`). |

The current-source [Signal Parameters documentation](https://www.pscad.com/webhelp-pscad-v5.1.0-ol/Master_Library_Models/Sources/Current_Source/c_source.htm)
states that its ramp-up time is used only with internal control. Consequently
the TLC's external instantaneous current command is not ramped by `Tc`;
copying that field alone would not fix the zero-voltage division.

The exporter copies the TLC's existing time comparator with its 0.2 s threshold
and real output (`conv=0`). Its low output is the element's nominal
pole-to-pole voltage in kV (640 for these fixtures); the high output is the raw
meter signal `v_dc_m`. Guarded `v_dc` supplies MEAS, MOD's physical scaling and
the electrical DC-current denominator. This reproduces the saved connections,
including the nominal-voltage phase scaling during start-up. It introduces
neither a persistent voltage floor nor a current limiter. The unchanged phase
and current source modes retain their validated polarity.

All control integrator/filter initial values still come from the converged
Julia state vector, as listed above. No controller reset, hold or new delay is
introduced. After the timed release, `v_dc` is exactly the measured voltage;
the original controller equations, modulation scaling and power balance are
recovered. The solved equilibrium is therefore unchanged. Tests exercise a
plant at rest, prove both voltage divisions finite during the guard, and check
identity with measured voltage after release, including zero/negative inputs
to rule out an undocumented persistent clamp. Station round 3 subsequently
confirmed stable handover and the converged equilibrium, as recorded below.

The four case projects are regenerated at **10 s / 10 μs / 40 μs**, retaining
the **0.05 s source ramp**. Before 0.2 s, `DUT_v_dc_f` reports nominal voltage
after the configured measurement filter, not the uncharged cable voltage;
use the existing `V_DC1_P - V_DC1_N` probes to inspect the actual converter-side
voltage. At approximately 0.2 s the raw measurement takes over; the 200 μs
modulation delay then clears its pre-release history. This is a finite start-up
sequence to test, not steady-state acceptance. The proposed steady-state window
is the final ten 50 Hz cycles, **9.8–10.0 s**, only after checking settling and
the frequency-dependent cable's diagnostics (R15). No window before release
is valid, and elapsed time alone is insufficient.

### M4 station round 3: start-up and equilibrium

PSCAD 5.1.0, at 10 μs integration and 40 μs sampling, settled all four
classic/builder TLC cases using the timed start-up construction. Case 2's
internal P/Q relative errors were `8e-9` / `2e-9`. Its network-side power was
`70.0015 + j20.0004` MVA, matching the solved reference; P/Q errors normalized
by 100 MVA were `6e-9` / `4e-10`. Case 1's Q error was `2e-8`, `v_dc_f` was
within `3e-8` of the reference, and drift was below `2e-6` over the final
2 s. Classic and builder results agreed. These are the reported station
metrics; the current internal P/Q acceptance rule uses absolute pu differences
on the rating, rather than those relative errors.

**R11 is closed.** Fundamental Q at the converter's AC terminal equals solved
injected Q with the same sign when measured with outward converter current.
The internal Q reference is the solved terminal Q divided by `elec.Sbase`,
consistent with the verified `-Qac/Sbase` conversion above.

This station round tested the start-up construction before the named-node
connectivity change. It confirms that construction and its equilibrium;
native regression of the subsequent Main/module/row rewiring remains pending.

### M4 station round 4: transform floating inputs

The station reported six distinct floating-input messages in the named-node
abc/dq canvases. The DC injection experiment still ran at +100 kV. The
following reconstruction uses pins witnessed by wires and abutments in
`local/TLC/Simple_2L_VSC_RL.pscx`; offsets are not inferred from the messages.

| Reported component | Read pin in emitted canvas | Signal and emitted driver pin | Saved pin witness |
|---|---|---|---|
| ABC_DQ N=2 merge A2 at `(108,756)`, orient 4 | `(90,702)` | `transform_node_10`, dot product `(1224,108)` | Merge at `(504,324)`, A2 `(486,270)`, wired to dot output `(486,306)`: `2937–2961`; dot `2727–2732` |
| ABC_DQ trig input at `(756,756)` | `(720,756)` | `transform_node_16`, sum `(1224,324)` | Trig `(324,216)` input `(288,216)` abuts mirrored sum `(252,216)` output: `2797–2810,2980–2988` |
| DQ_ABC N=2 merge A1 at `(324,540)`, orient 4 | `(306,468)` | `transform_node_16`, trig `(1224,324)` | Merge `(612,162)` A1 `(594,90)` wired to trig `(468,54)` output `(504,54)`: `2185–2202,2214–2234` |
| DQ_ABC trig input at `(324,756)` | `(288,756)` | `transform_node_24`, sum `(1224,540)` | Trig `(468,324)` input `(432,324)` abuts sum `(396,324)` output: `2292–2305,2319–2327` |
| DQ_ABC gain input at `(540,972)` | `(504,972)` | `transform_node_9`, trig `(1224,108)` | Gain `(540,252)` input `(504,252)` abuts trig `(468,252)` output: `2113–2121,2437–2444` |
| DQ_ABC label `transform_node_15` at `(1260,756)` | Reader is N=3 merge A2 `(954,270)` | Dot product `(1224,756)` | Middle dot `(648,288)` output `(684,288)` abuts N=3 merge `(702,342)` A2: `2164–2184,2385–2398` |

In the written XML, all six read pins already have stubs and each named net has
one writer. All six writers are in the last transform column, at x=1224,
with output labels at x=1260. This common geometry is evidence to investigate;
it does not establish a native clipping or rotation rule. The original offsets
and net partitions remain unchanged.

A separate verified mismatch was missing module schematic settings. The XML
writer now writes the saved settings explicitly, including `size=0`, `orient=1`
and `auto_sequence=1`, from `2069–2083` (dq2abc) and `2675–2689` (abc2dq_1).
The station coordinate diagnostics subsequently built all three variants:
standard spacing with explicit saved settings at x=1260, compact spacing with
settings, and compact spacing without settings. All returned the exact frame
values. This closes the reported transform floating inputs: module canvases
need the explicit saved settings, or labels beyond the default extent are lost.

Tests independently assert the saved orient-4 N=2/N=3 merge and unary input
coordinates, then disconnect the input stub, remove the writer stub, and add a
second writer for each of the six reported nets. Each variant must fail with
the canvas and read-pin coordinates. These tests close the missing completeness
and driver checks; they do not reproduce a native loader losing a connection
whose two endpoints are still present in XML.

### Named-node M1–M3 topology regression guard

`test/pscad/topology.jl` reconstructs electrical nets from the serialized XML,
using the saved-project port table, original wire segments and abutments,
case-insensitive node label names, ground and module xnodes. The comparison
preserves every component parameter and ordered electrical port; it ignores
coordinates, component ids and internal node label names. Cable interface
records with identical parameters are matched by graph isomorphism. Line row
material/fitting fields and wrapper parameters are retained as well. Nets with
fewer than two attached ports fail unless grounded or carrying a voltage probe;
the fixture buses all carry voltage probes. Unattached labels remain visible.

The 14 classic/builder M1–M3 reference graphs in
`test/pscad/fixtures/topology_8be21ee/` came from exports generated once from
unmodified `8be21eecabb85d29d2896bc51562f61344338604`; each records the source
XML SHA-256. XML round trips compare every M1–M3 canvas against these references
and check degrees on all four TLC exports. Tests also disconnect junctions and
grounds, reverse ammeter ports, change physical parameters and reorder records.

The station's failing `m4-bz1oQX/transformer_yy_classic.pscx` has the same 15
electrical component records, full parameters and 11 nets as the reference.
It passes both equivalence and net-degree checks. No lost R/L junction or
magnetizing ground is present in that written XML. The native compiled files subsequently established a different ideal-meter
construction, described below. Raw net equivalence alone did not capture how
PSCAD selected a branch current when components abutted. The original reference
graphs remain unchanged; an explicit shunt-meter policy now describes the only
approved connectivity difference. No electrical parameter or tolerance changed.


### Named-node shunt-meter ground return

The station's `yy_named_load_return` diagnostic built and ran without errors.
Its secondary voltage and terminal currents agreed with the passing d40f623
reference to seven reported digits. Separate R/L junction nodes were harmless.
The failing construction put B2 between `I_line_2` and `I_load_1`, two separate
ideal A branches on an isolated YY secondary whose star points are ungrounded.
The passing small-AC circuit had a source-grounded galvanic island instead.

The compiled named branch records are in
`local/pscad-exchange/diag/yy_named-report/Main.dta:22–27`; node 23 is
`line_terminal_2(3)` in `yy_named.map:92–95`, adjoining its inductor and meter.
The reference reused the load resistor's current, whereas the named construction
instantiated a separate load-meter branch. The station's passing change moved
only the load meter to the ground return. Its saved circuit and fields are in
`local/pscad-exchange/diag/yy_named_load_return.pscx:346–373` (resistor,
node labels, orient-0 ammeter and ground). EMTDC's internal pivot trace is not
available; the diagnostic isolates the triggering construction without changing
resistance, inductance or transformer parameters.

Every probed shunt emitted through `impedance_path!` now uses
`bus -> element -> meter -> ground`. Parallel shunts share one return meter
measuring their total current. Unprobed shunts, winding passives and series
branch meters retain their construction. Probe names, manifest sides and the
positive bus-to-element current direction stay unchanged. No limiter, numerical
resistance or physics fallback is added.

Independent native outputs in
`local/pscad-exchange/diag/yy_ref-report/pi_02.out` and
`yy_named_load_return-report/pi_02.out` give load phase RMS currents
`0.21482524` kA. Using `2/N sum(x exp(-j 2 pi 50 t))` over
`1.8 < t <= 2.0` s, the return-meter phase angles are
`[-2.93004909, -122.93004826, 117.06995128]` degrees; the reference angles are
`[-2.93004845, -122.93004878, 117.06995116]` degrees. Load and outward
secondary-line phasors have the same sign. The independent phasor fixture
records source hashes and the extraction window. Plan/XML tests verify ordered
meter pins, RMS and phase using existing 2% current/1-degree tolerances.

The production structural check excludes voltage probes from conducting
connections and keeps transformer windings as separate galvanic islands.
It follows named stubs through module xnodes, line terminals and paired cable
interfaces. It rejects a source-free isolated part whose remaining grounding
connection contains consecutive ideal meters with only two meter branches at
an intermediate node. A source on the island or an alternate direct grounding
path removes this trigger. The saved failing `m4-bz1oQX` YY XML must fail the
check, naming `I_line_2`, `I_load_1`, its canvas and coordinates.

The 8be21ee reference graphs are preserved. A reviewed per-fixture list permits
only the specified shunt meter to move from the bus end to the ground return,
preserving full parameters and ordered current pins. XML verification reports
every accepted move explicitly; unlisted moves, other net changes and meter
reversals fail. All TLC canvas graphs still undergo net-degree and named-stub
checks. Full M1–M4 native acceptance of the production exports remains pending.

## M5a — grid-following MMC, PQ mode

`emitters/mmc.jl` exports the current modular `mmc(...)` model with
`ΔdqControlGFL`, `ΣdqzControlTEC` containing `TotalEnergyControl`,
`ZeroSequenceCurrentControl` and `CirculatingCurrentSuppressionControl`, and
`UncompensatedModulation`. The supported operating mode is P/Q without
frequency or voltage support. Other Δ/Σ/modulation structures and outer-control
variants fail with `not yet exportable`. No core model is changed.

The shared M4 MEAS, PLL, PCTRL/VDCCTRL, QCTRL and OCC generators remain the
control authority. MMC supplies its Δ control objects to those generators;
OCC reads the owned `elec_inductance` generic, which gives
`Lₑ = (L_arm/2 + Lr)/L_AC_base` for MMC. MEAS receives converter-side phase
voltage/current and the measured DC current. MMC voltage/current/DC bases are
`vAC_base`, `2*Sbase/(3*vAC_base)` and `vDC_base`; measurements follow
`MMC/MMC.jl:185–202`. The transformer ratio belongs to the physical transformer,
so MEAS does not multiply its already transformed phase voltage by the ratio.
The current core MMC returns no diagnostic tuple from `state_space!`; the
exporter evaluates its existing constituent blocks to retain their outputs
alongside the converged state vector.

The saved PQ witnesses are
`local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx`:

| Construction | Saved lines | Export mapping |
|---|---|---|
| Arm capacitor dynamics and voltage multiplication | 6401–7499 (`ArmVoltage_1`), especially 6635–6673, 7119–7198 | Six integrators: `dv_Ctot/dt=(N/C_SM)*m_arm*i_arm`; controlled voltage `m_arm*v_Ctot`. Currents in kA and voltages in kV require no additional factor of 1000. |
| Averaged arm source and current direction | 7624–7741 (`ArmAvg_1`) | Positive source pole precedes the meter, with positive current charging the capacitor. `Type=6`, `Grnd=0`, `Spec=0`, `Cntrl=1`, `AC=0`, `Tc=0`. The saved orient-1 electrical pins are `(828,414)` and `(828,486)`, control `(792,450)`. The generated orient-0 pins use the already validated source geometry. |
| Arm L/R | 11345–11442 | Each arm has `L_arm` and `R_arm` in series; the common arm definition includes the source, L, R and current meter. Electrical L/R fields are formatted SI literals, following `L="50e-3 [H]"` and `R="1.07 [ohm]"` at 11345–11359. Six instances supply separate capacitor initial values. |
| Converter transformer | 11813–11889 | Converter-side reactor Lr/Rr are recovered separately with `mmc_si`. A transformer is emitted only when `turnsRatio != 1`, with rated converter-side voltage and network-side voltage divided by the ratio. The accepted YY realization uses `Ideal=0`, `Xl=1e-4 pu`, `Im1=1e-3 %`, zero no-load and copper losses. |
| Σ frame and zero-sequence component | 10335–10342, 10441–10494, 10738–10743 | Sum upper/lower currents and divide by two; transform the resulting three-phase circulating current at `-2*theta_c`. Its mean over three phases, on the DC-current base, is `iS_z`. |
| Project timing | 4–6 | 10 s duration, 10 us integration, 250 us sampling. |
| AC-source start-up | 687–700 | `Tc=0`, 380 kV LL RMS, 50 Hz. The saved DC source also has `Tc=0` (see the M4 five-variant start-up inventory). |

All generated master fields have saved witnesses in the above project or the
M4 primitive/transform canvases. `fixtures/mmc_saved_fragments.xml` retains
individual saved instances with source-line comments. The XML tests check field
coverage, source/integrator modes, module parameters and ports, and complete
canvas connectivity/topology after writing and rereading the project. There is
no guessed component field or additional primitive.

Every electrical and signal port has its own straight stub to a named label or
ground. The transformer side retains its electrical reference through the six
arms and the source-referenced DC network. Controls compute DC current from the
existing arm meters; adding another ideal DC meter in series with Main's
terminal meter would recreate the isolated-meter grounding failure. There is
one converter-side AC meter and the ordinary outward network-side terminal
meter; they lie on opposite sides of the transformer. `check_connectivity`
recursively checks the complete hierarchy. Each generated module retains the
saved canvas settings from M4.

### Σ, Δ and modulation equations

TEC uses six-arm energy `sum(v_Ctot.^2)/(6*vDC_base^2)`. Its cycle mean is the
current harmonic model's
`(vCΔ_d²+vCΔ_q²+vCΔ_Zd²+vCΔ_Zq²+vCΣ_d²+vCΣ_q²+2vCΣ_z²)/2`
(`MMC/energy.jl:19–28`). The physical arm plant retains a 6ω energy ripple from
the triplen pair. No filter is added to conceal that difference. TEC's PI output
plus `P_ac_f`, divided by `3*v_dc_f`, sets the zero-sequence current reference.
ZSCC subtracts its PI output from `v_dc_f/2`.

CCSC transforms the circulating-current pair with the `-2θ` rotation and emits
`vMS_d_ref = -PI(-iS_d)+2*Larm*iS_q` and
`vMS_q_ref = -PI(-iS_q)-2*Larm*iS_d`, where Larm and currents use the DC bases.
These are the current equations in `MMC/inner_current.jl:31–49`, with ZSCC at
53–61. The Δ loops are the shared current-API outer P/Q and inner PI loops;
`MMC/MMC.jl:141–153` supplies their composition.

Uncompensated modulation maps Δ references back to the grid frame at
`theta_rel` and Σ references at `-2*theta_rel`. Its grid-coordinate commands are
`mΔ=-2*baseConv1*vMΔ_ref/v_dc_f`, `mΣ=2*vMΣ_ref/v_dc_f` and
`mΣz=2*vMS_z_ref/v_dc_f` (`MMC/modulation.jl:43–71`). Therefore physical arm
insertion indices are upper `(mΣ_abc+mΣz+mΔ_abc)/2` and lower
`(mΣ_abc+mΣz-mΔ_abc)/2`. Julia's negative Δ normalization produces the specified
physical voltage assembly `vMu=vMS-vMD`, `vMl=vMS+vMD`.

For nonzero Padé delays, five scalar exact `tdelay` blocks replace the two Δ,
two Σ and one zero-sequence delay channels. Their histories come from the
converged realization. The existing `phase_compensated_dq` rotations are kept:
`+ωbase*Td` for Δ, `-2*ωbase*Td` for Σ, none for zero sequence. This preserves
the steady rotating-frame convention; exact delay and Padé frequency responses
are different away from DC (R18). There is no claim of full frequency-response
equivalence. R12 and the nonzero-delay construction have separate station
experiments with prescribed inputs.

Initial arm capacitor voltages reconstruct the solved harmonic coordinates at
nominal grid angle zero: Σ is `vCΣ_z + vCΣ_d*cos(-2θ) + vCΣ_q*sin(-2θ)`, Δ is
`vCΔ_d*cos(θ)+vCΔ_q*sin(θ)+vCΔ_Zd*cos(3θ)+vCΔ_Zq*sin(3θ)`. Upper/lower totals
are `(Σ±Δ)*vDC_base`. Control PI/filter/delay initial values come from
`converter_equilibrium`, not from the initialization guesses. No unwitnessed
inductor initialization field is introduced. The final 0.2 s DC-divisor
hold below protects measured-DC divisions while all feedback stays live.
Station round 3 validated the earlier broader-hold PQ exports only.

### PQ fixture and parameter provenance

`PSCADFixtures.mmc_pq_network()` returns classic and NetworkBuilder versions of
one current-API MMC between AC and DC sources. Electrical data and Δ/CCSC gains
come from the saved module instance at 621–644: 1000 MVA, 333 kV converter-side
LL RMS, 800 kV pole-to-pole DC, 400 submodules per arm, 50 mH, 1.07 Ω and
10 mF per submodule. Transformer ratio is `333/380`; Lr/Rr use the saved
0.1305/0.0037 pu on `333²/1000` Ω and 50 Hz. The P/Q PI gains are
0.1/31.4159, OCC 0.7691/522.7654, CCSC 0.1048/48.1914, PLL 0.28/12.5664.

`local/GFL-MMC/PQ-Mode/31_10.jl:20–30,97–105` supplies the 600 MW / 200 MVAr
setpoints, 380 kV source and conversion of the transformer data. Its network
contains two converters and a cable; the fixture retains the PQ converter and
replaces the remote DC system with the requested ideal DC source. The script
specifies no optional measurement/PLL/OCC filtering or modulation delay;
the fixture uses `NoFilter` and zero delay. Its legacy API is not invoked.

The saved project and script differ in two further respects. The saved AC
source has `R=0.5 ohm` (687–710), while the script uses an ideal AC source and
comments out its 0.5-ohm grid impedance (114–116); the fixture follows the
script. The saved voltage-droop module has `Kd=20`, `wf=100` (11992–11998),
with the `Vacref`/`Vac` to `Qref` lag construction at 8460–8742. The script's
PQ controller supplies neither voltage support nor those parameters; the
fixture retains `NoVoltageSupport`. The saved voltage gain is rounded to
0.8763 (11894–11902); the fixture uses the script's exact `333/380` ratio.
These saved-project parameters have no one-to-one counterpart in the fixture.
The saved DC source also includes `R=0.05 ohm` (799–813); the reduced fixture
uses an ideal DC source. Saved arm-capacitor integrator guesses are 640 kV
(6644, 7128–7192, 7708), replaced by the required converged-state reconstruction.

Two control parameters have no one-to-one PQ reference: the full TEC gains
1.386/29.70 are the current modular validation values from
`test/adm_MMC_test.jl:108–110`; ZSCC uses the saved CCSC gains
0.1048/48.1914. The saved PQ project contains no TEC or ZSCC gain pair. These
choices exercise the requested full Σ structure and are explicit additions to
the legacy PQ configuration tested in station round 3. The near-ideal YY
leakage and exciting current are the already accepted exporter construction,
not extra terms from the Julia plant. The reactor retains the full Julia Lr/Rr.

The saved MMC voltage sources use `Tc=0`; this does not initialize their meter
outputs. The approved start-up holds only the measured DC-voltage divisor until
0.2 s, using the TLC's saved selector construction; control measurements are
live. M5a station round 3 used
zero source ramp. Both M5b ramp experiments passed, establishing support for
any finite, nonnegative `SimulationSettings.source_ramp` for every supported
converter. The library default remains 0.05 s, the MMC fixtures retain zero,
and TLC fixtures retain the default. No public name or keyword is added.
Native checks must inspect the first samples:
PSCAD `div` returns 1e99 at a zero denominator. No persistent clamp, protection
reset, or physics fallback is inserted.

### Probes, comparison and station checks

The approved exact exported names for the fixture are:

- `DUT_P_ac_f`, `DUT_Q_ac_f`, `DUT_v_dc_f`, `DUT_omega_c`, `DUT_theta_c`.
- `DUT_v_Ctot_u_a`, `DUT_v_Ctot_u_b`, `DUT_v_Ctot_u_c` (upper arms, kV).
- `DUT_v_Ctot_l_a`, `DUT_v_Ctot_l_b`, `DUT_v_Ctot_l_c` (lower arms, kV).
- `DUT_iS_z` (circulating zero-sequence current, pu of `Sbase/vDC_base`).

All use `<elem>_<signal>`. The standard network terminal current probes retain
the accepted `I_DUT_1` / `I_DUT_2` names. Network-side and internal P/Q reuse
the existing converter rows and 0.01 pu absolute-error rule on Sbase. MMCs now
participate in the existing converter-connected DC current normalization.
The only extra rows are six capacitor cycle means against solved pole-to-pole
Vdc, and the signed identity `I_DUT_1 = 3*DUT_iS_z*Sbase/vDC_base`.

No additional tolerance is defined. Approved M5 station acceptance reuses the
existing `rtol_v=0.01` for capacitor means and `rtol_i=0.02` for the current
identity, with denominator `max(abs(3*iS_z*Sbase/vDC_base),Sbase/vDC_base)`.
Callers retain the existing tolerance keywords. `iS_z` itself is reported
against its solved equilibrium value by the acceptance script, without an
assertion. `omega_c` and `theta_c` remain diagnostics; `theta_c` grows at
nominal angular speed and is not a settled
scalar. Arm instantaneous voltages retain ripple and are not compared sample
by sample with constant Vdc.

`test/manual/pscad/acceptance.jl` includes both PQ representations with 10 s,
10 us, 250 us and zero source ramp, matching saved timing. Converged control
states and the longer duration address R15; P/Q, Vdc, iS_z and capacitor
settling passed station round 3 over the final ten cycles, `[9.8,10.0] s`.
Inspect settling again when changing the network or settings. The local fixture has a grounded
DC source midpoint and uses `dc_reference=:none`; it adds no resistive DC
reference (R14).

`test/manual/pscad/write_m5_experiments.jl` writes the following into
`/tmp/pscad-m5-experiments/`, with README run instructions and reference TSVs:
`mmc_r12`, `mmc_delay`, `mmc_sigma`, `mmc_arm`, `mmc_pq_classic` and
`mmc_pq_builder`. The PQ TSVs include solved terminal/bus values, internal pu
references, all six initial arm voltages and the complete converged state
vector. Namespace and output settings are preserved exactly as written by the
exporter. Local plan, equation and XML checks establish structural/numerical
mapping and do not establish station acceptance by themselves.

### Station round 1

PSCAD 5.1.0 built and ran `mmc_r12`, `mmc_delay` and `mmc_sigma` for
0.1 s with 10 us step/sampling. The supplied CSVs in
`/tmp/pscad-m5-results/` each contain 10001 samples. Evaluation covers the
entire run against the original analytic predictions and reference TSVs.

| Experiment/channel | Outcome | Maximum absolute deviation |
|---|---|---|
| R12, all six indices | PASS; R12 closed: upper = Σ − Δ, lower = Σ + Δ | 4.3570402e-9 |
| Delay, all six indices | PASS; delayed step arrives at 0.0202 s; both frame compensations confirmed | 4.3552753e-9 |
| Σ zero-sequence current | PASS | 2.4999999e-10 pu |
| Σ z voltage reference | PASS | 1.1839700e-8 pu |
| Σ d voltage reference | PASS | 7.4962259e-12 pu |
| Σ q voltage reference | PASS | 7.7104817e-10 pu |

The delay's phase-A upper/lower indices are equal at 0.02019 s and become
0.4199999999907/0.6200000000093 at 0.0202 s. All six traces follow the
predicted delayed fundamental and second-harmonic rotations. Fitting the Σ
voltage-reference polynomials at 0, 0.05 and 0.1 s gives maximum initial-value deviation
1.4496993e-10 pu, maximum slope deviation 6.8758301e-8 pu/s and z quadratic
coefficient deviation 4.8188999e-7 pu/s². The TEC error inferred from that
quadratic coefficient is −0.0201000020201 versus the predicted −0.0201
(deviation 2.0201e-9). These residuals do not define new acceptance tolerances.
The original predictions are retained.

The largest Σ residual is explained by the exporter's decimal gain rendering:
`1/6` is written as `0.166666667`, `1/3` as `0.333333333`, and `invIzero` as
`0.266666667`. Re-evaluating the z polynomial with the serialized values gives
initial value 0.5009731939049684, slope 0.4683691994383955 and quadratic
coefficient 4.794803824889667. This reproduces the native trace to
9.44e-15 pu over the entire run. The gain formatting and original reference
TSVs are unchanged.

`mmc_arm` failed station compilation because the inductor's `L="armL"`
and resistor's `R="armR"` did not resolve to finite numbers. Those fields
now contain literal SI values; unused armL/armR module parameters are removed.
`check_connectivity(plan)` rejects nonnumeric or non-finite parameters of
electrical components inside every generated module, except `Name` identifier
metadata. Control-module parameters remain supported. There is no admitted
symbolic electrical construction without saved station evidence. The saved
literal witnesses are the arm inductor/resistor at
`local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx:11345–11359`.

At the end of round 1 the regenerated `mmc_arm` and both full PQ cases awaited
station build and run. Round 1 closes the assembly-sign risk R12 and verifies
the isolated delay/Σ modules; it does not establish full electrical-stage,
start-up or R15 settling acceptance.

### Station round 2: arm polarity passed, PQ start-up blocked

PSCAD 5.1.0 built and ran `mmc_arm`. The station reports `Arm_i_arm=+0.01 kA`
from the second sample and `Arm_v_Ctot=800 kV` at zero, `800.001 kV` at
10 us and `809.999 kV` at 0.05 s, with a 20 kV rise over 0.1 s. The
200 kV/s slope and positive-current charging direction pass the isolated arm
check. The two reported nonzero-time values are 0.001 kV below `800+200*t`;
no complete arm output was supplied to calculate a whole-run maximum error.

Both full PQ cases built without errors or ITRIANG, but failed start-up. The
classic `pi.inf` and three `.out` files in
`/tmp/pscad-m5-results/pq_round2/` contain 40001 samples from 0 to 10 s.
Twenty-one of 25 channels are non-finite at every sample from 250 us onward;
only the three AC bus voltages and negative DC-pole voltage remain finite.
The builder failure is reported by the station; its raw outputs were not
supplied for a separate numerical audit.

| Classic channel | Initial native value | Solved reference | Initial deviation |
|---|---|---|---|
| `DUT_P_ac_f` | 0 | 0.6 pu | −0.6 pu |
| `DUT_Q_ac_f` | 0 | 0.2 pu | −0.2 pu |
| `DUT_v_dc_f` | 0 | 1 pu | −1 pu |
| `DUT_iS_z` | 0 | 0.20127207609887254 pu | −0.20127207609887254 pu |

The initial `omega_c=1` and `theta_c=0` agree with the reference. All six
initial capacitor voltages agree with the original TSV to within
3.5632854e-7 kV, consistent with their serialized initial values. The physical
DC terminals are already at ±400 kV while the modulation's measured denominator
is zero. Full Σ control also divides by zero in
`iS_z_ref=(energy_pi+P_ac_f)/(3*v_dc_f)`. Guarding only the modulation would
leave this second division unprotected. R15 settling cannot be assessed from
these failed runs.

The five saved GFL-MMC projects were traced through the actual module pins,
wires and named labels. They all use measured DC voltage, rather than a
nominal-voltage replacement. The detailed PQ witness is
`local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx`:

| Saved construction | Lines | Finding |
|---|---|---|
| Measured DC voltage | 10956–10960, 10052–10056, 9338–9347 | `V_dc_2` from the voltmeter enters `PerUnit_2`. |
| Per-unit DC voltage | 4770–4780, 5055–5063 | Measured voltage is divided by imported `Vbase_dc`. |
| Δ/CCSC normalization | 9783–9787, 9865–9869, 2954–2969, 3276–3291 | Both `PICtrl_1` inputs use `V_dc_pu_2`; their d/q commands are divided by half this measured value. |
| PI reset/enable | 3172–3182, 3356–3371, 3413–3428, 621–644 | `Reset=1`, `Yo=YRst=0`; the time comparator uses `t_rst`, which is zero in Main. There is no positive enable delay. |
| Σ zero-sequence insertion | 10738–10745 | Fixed `Value=1`; the saved model does not contain the current full TEC/ZSCC structure. |

No applicable nominal-Vdc selector, initialized DC measurement output or
positive delayed enable was found in these MMC canvases. The saved zero-state
PI reset and fixed Σ insertion differ materially from the required converged
control initialization and full TEC/ZSCC equations. Saved XML alone does not
explain the legacy model's first-step execution order or establish a safe
construction for this exporter. The TLC's 0.2 s nominal-voltage selector is
separate evidence (`local/TLC/Simple_2L_VSC_RL.pscx:5885–5888,5912–5929`);
transferring it to MMC would select new start-up behavior.

All five saved workspaces also contain perturbation-task start overrides.
The PQ witness is
`local/GFL-MMC/PQ-Mode/GFL_MMC_Validation_workSpace.pswx:26–27,42–43`:
`start_method=1`, `startup_inputfile=Snapshot.snp`, with both override flags
true. The project itself has `StartType=0` at line 9. Its
`freq_sweep_ACDC_full.py:38–46` explicitly prepares a cold-start snapshot via
`frequency_sweep`; the imported helper is absent from the supplied local
bundle. These files do not establish which first-step initialization sequence
was used for the validated perturbation runs. No workspace enum meaning or
snapshot start is inferred for the exporter's fresh-run contract.

Every one of the fixture's ten measurement filters is `NoFilter`, with zero
states. The emitted unit gain matches the current Julia pass-through equation
(`converter/common/loops/measurement.jl:95–104`), so its output is zero when
the raw meter input is zero; there is no solved filter-output state to set.
`iS_z` is also a stateless sum of arm-meter outputs, not a separately initialized
filter. A static audit of Butterworth orders 1–6 for all ten measurement
quantities confirms that the existing emitter seeds dynamic outputs from their
solved realization: 60 initial-output comparisons with the owned filter equation
have maximum deviation zero. Those filters are not used by the PQ fixture.
Adding them to fix start-up would change its Julia model.

At the end of round 2 implementation stopped under the required start-up
decision rule. Options
for review are a finite hold of solved measurement outputs, including Vdc,
P/Q, dq measurements and `iS_z`, followed by the existing measured equations,
or a station experiment establishing native meter/inductor initialization and
control execution order before choosing initialization-only seeding. Any hold
duration needs an explicit decision; the TLC's 0.2 s is precedent, not an MMC
selection. A permanent nominal-Vdc denominator would change the current
`UncompensatedModulation` and DC response and is not an equivalent correction.
No start-up policy, filter, component field or numerical tolerance was selected
in that round. The PQ projects and reference TSVs were retained without regeneration.

Audit artifacts in `/tmp/pscad-m5-results/` are
`round2_pq_channel_audit.tsv`, `round2_saved_startup_audit.tsv`,
`round2_measurement_initialization.tsv` and
`round2_butterworth_initialization.tsv`. The experiment README records the
passed arm check, failed unheld PQ runs and revised projects awaiting station
acceptance at the end of round 2. Station round 3 results are recorded below.
No Julia core defect was found.

### Approved MMC DC-divisor hold

Every MMC, compensated or uncompensated, uses the same start-up rule to avoid
division by zero while retaining live feedback: **only the measured DC-voltage
value used as a divisor is held at its solved value for `t<0.2 s`**. Every feedback measurement is live
from `t=0`: AC/DC voltage and current, P/Q, PLL inputs, circulating-current
d/q/z, capacitor voltages and all TEC/Σ/Δ energies. The electrical plant
starts from rest; its closed control loops bring it to the operating point.
Controller/filter/capacitor integrators and delay histories retain their
converged initial values, without resets or freezing their derivatives.

The shared measurement construction filters the live DC voltage normally,
then exports a private `v_dc_divisor` alongside the live `v_dc_f`. One
selector in MEAS supplies this denominator to all measured-DC divisions:
TEC's zero-sequence current command, LEC's three Σ current commands, and
uncompensated modulation's common `2/Vdc` factor. Vdc feedback errors,
DC-power products and the Σ half-DC voltage feedforward consume live
`v_dc_f`. The divisor is an internal module connection, with no new probe,
public keyword, comparison row or tolerance. Compensated modulation divides
by each arm's live capacitor voltage and does not use the measured DC divisor.
There are no selectors in Σ or modulation, nor on any other loop input.

The single selector uses the validated TLC construction at
`local/TLC/Simple_2L_VSC_RL.pscx:5912–5929`: `time-sig` feeds real-valued
`compare` with `X=0.2`, `OL=solved filtered DC voltage`, `OH=v_dc_f`,
`INTR=0`, `Dim=1`, `conv=0`. `_CONVERTER_STARTUP_RELEASE` remains the
single private release constant shared by TLC and MMC. TLC's existing
nominal-voltage handover, canvas and fields are unchanged. Named-node
connections retain their separate straight stubs, including `OH`.
At exactly 0.2 s the saved construction selects the live filtered voltage;
a later zero voltage passes through as zero, with no clamp or threshold guard.
Dynamic measurement filters run on live input from their solved states
throughout startup; the selector protects only their DC output's divisor use.

Both earlier M6b classic projects built but diverged on the station:

- Holding solved energy as well as meter measurements hid capacitor charging.
  The capacitors rose from 635/641 kV initially to 7,260/8,488 kV at 0.05 s
  and about 10,000 kV before release; DC current reached 9–27 kA against
  about 1.16 kA solved. At 0.201 s `iS_z` jumped to -98.7 pu, and results
  became non-finite at 0.278 s. Compensated per-arm division removes the
  natural capacitor-voltage balance, so frozen energy feedback left charging
  uncontrolled during the hold.
- The subsequent meter-only hold made energy feedback live but still froze
  `iS_z`. This opened the inner current loop under a live outer energy loop:
  the current controller integrated against a fixed measurement. `I_DUT_1`
  went from -0.13 to -59 kA in 5 ms, the lower-arm capacitor from 641 to
  -94 kV in 2 ms, and results became non-finite at 0.608 s. Compensated
  modulation cannot tolerate this open-loop startup window either.

The divisor-only policy keeps every inner and outer loop closed from the
first step while preventing measured-DC divisions by an unsettled startup
voltage. All diagnostic probes now report live measured/filtered values,
including P/Q/Vdc/iS_z before 0.2 s. The earlier station round 3 below
records the historical broader-hold exports; it does not validate this revision.

Regenerated M6b and M5 classic/builder projects retain 10 s duration, 10 us
integration, 250 us sampling, zero source ramp, their existing probes and
rating-normalised comparison rules. Inspect finite startup, the denominator
handover and settling; compare the final ten 50 Hz cycles `[9.8,10.0] s`.
These revised projects require station build/run acceptance.

Tests check the single saved selector and its release, immediate live meter
feedback through the whole control cascade, independent energy/current
changes in TEC and LEC/CCC before release, and the live Vdc feedforward
separately from its held divisor. All ten measurement filters are exercised
with `NoFilter` and Butterworth orders 1–6. XML round trips compare the
selector fields/orientation with the cited TLC fragment and check all module
connections, topology and the absence of other MMC selectors.

### Station round 3 and approved MMC comparison rows

Station-reported PSCAD 5.1.0 results for `mmc_pq_classic` and `mmc_pq_builder`
are identical. Both ran for 10 s with 10 us integration, 250 us sampling,
`source_ramp=0` and the 0.2 s solved-measurement hold. The handover was clean,
with no ITRIANG. The final ten 50 Hz cycles, `[9.8,10.0] s`, settled and passed
the approved comparisons:

| Measurement | Settled result | Reference / reported deviation |
|---|---|---|
| `DUT_P_ac_f` | 0.5999999 pu | 0.6 pu; absolute difference 1e-7 pu |
| `DUT_Q_ac_f` | 0.2000000 pu | 0.2 pu |
| `DUT_v_dc_f` | 1.0 pu | 1.0 pu |
| `DUT_omega_c` | 1.000000001 pu | 1.0 pu; diagnostic |
| Network-side converter AC-terminal power | 600.0 + j199.95 MVA | 600 + j200 MVA; P/Q errors 2.6e-9 / 5e-5 pu on 1000 MVA |
| Six arm capacitor cycle means | 799.46–799.54 kV | Solved pole-to-pole Vdc 800 kV; approximately −0.06 % |
| Arm capacitor ripple | 83 kV peak to peak | Reported ripple; no sample-by-sample Vdc assertion |
| `DUT_iS_z` | 0.200977 pu | Solved 0.201272 pu; −0.15 %, diagnostic only |
| `I_DUT_1` | 0.753663 kA | `3*DUT_iS_z*1.25 kA`, agreeing to 1e-6 kA |
| DC terminal current against power flow | 0.753663 kA | 603.41 MW / 800 kV; −0.08 % |

`DUT_v_Ctot_{u,l}_{a,b,c}` and `DUT_iS_z` provide capacitor cycle means versus
solved pole-to-pole Vdc with `rtol_v`, and the signed DC-current identity with
`rtol_i`, checking arm energy and current consistency without suppressing ripple.
`compare_operating_point` emits these rows for the
corresponding probes of every exported MMC:

| `quantity` | Row `name` | `pscad` / `powerflow` columns | Error and tolerance |
|---|---|---|---|
| `:converter_arm_voltage` | Each `<elem>_v_Ctot_{u,l}_{a,b,c}` | Settled capacitor cycle mean / solved DC bus pole-to-pole voltage, both kV | `abs(mean-Vdc)/abs(Vdc) <= rtol_v` |
| `:converter_dc_current_identity` | `<elem>_iS_z` | Signed DC side-1 terminal current mean / `3*mean(iS_z)*Sbase/vDC_base`, both kA | `abs(diff)/max(abs(reference),Sbase/vDC_base) <= rtol_i` |

The identity's `powerflow` column retains the table's existing field name but
contains its reference calculated from measured `iS_z`, rather than a solved
power-flow current. The ordinary DC-current row separately compares the
terminal current with power flow. `Sbase` in MVA divided by `vDC_base` in kV
gives kA directly; no factor 1000 is applied. The capacitor reference uses the
solved DC bus voltage, which can differ from the converter's rated DC base.
The existing `rtol_v=0.01` and `rtol_i=0.02` defaults are retained. No separate
comparison of `iS_z` with its equilibrium value is asserted.

Synthetic tests cover both network representations, capacitor ripple and
exclusion of start-up samples, changed solved Vdc, pass/fail cases for every
arm, signed and zero current, the low-load current-base denominator, alternate
MMC bases, incorrect units and missing probes. These checks exercise comparison
arithmetic independently of the station-reported round 3 results.

## M5b prerequisites: modular voltage control and deferred defects

The modular MMC uses converter-side AC-voltage measurements. Its shared
`OuterReactiveVacControl` and `VoltageSupportLag` references therefore multiply
`SetpointPU.v_ac` by the existing `voltage_filter_ratio(conv)`, which is
`turnsRatio` for an MMC and 1 for a TLC. Terminal inputs and setpoint
normalization retain their existing definitions. This restores the legacy
choice in `src/Network/Components/converter/MMC_legacy.jl:539` (Q-V support)
and `:600` (AC-voltage control): divide the physical reference by
`vAC_base/turnsRatio`. TLC reference arithmetic remains unchanged.

Grid-following MMCs now use the reactive outer block's existing `pf_type_ac`
and `pf_acq_droop` rules, already used by the TLC. VAC and Q-V support select
`type_ac=2`; VAC has `acq_droop=0`, whereas Q-V support has `acq_droop=1` and
`kq_droop=K*Sbase/(global_dict["S"]*1e-6)`. The AC bus becomes voltage controlled
unless it already has a higher-priority slack source. `Vtar` and bus `vm` use
the setpoint's phase peak AC voltage divided by `sqrt(2)` and the system
phase RMS voltage base. These match the legacy mapping in
`src/Network/Components/converter/common/conv_power_flow.jl:78–108`.

PowerModelsACDC 0.10.1 reads `Vtar`, `Q_g` and `kq_droop` in
`src/core/constraint_template.jl:169–173`. Its `src/formconv/acp.jl:154–159`
constraint is `qgrid = -Q_g - kq_droop*(Vtar-vm)`; `Q_g` is converted from Mvar
to system pu by `src/core/data.jl:668–685`, while `Vtar` and `kq_droop` are
already pu and are not rescaled there. `src/prob/acdcpf.jl:194–201` selects
this constraint for type 2 with droop enabled and the bus-voltage target for
type 2 without droop. The focused Julia tests check these fields, an alternate
power base, and solved VAC/Q-V equilibria at `turnsRatio=333/380` in both
network representations.

With terminal voltage prescribed, the VAC PI equation is identically satisfied
and does not determine reactive current. The old modular and legacy MMC
equilibrium paths added only the DC-voltage constraint (legacy
`src/Network/Components/converter/MMC_legacy.jl:1742–1751`). During equilibrium
recovery, MMC and TLC now dispatch through both their active and reactive
outer controls. `OuterReactiveVacControl` replaces the `ξ_v_ac` residual with
`setpoint_pu.q_ac - y.meas.Q_ac_f`. After the stored-setpoint sign correction,
the live modular reference is `Setpoint.Qac/Sbase`,
matching the existing Q controller and the measurement convention
`Q_ac = vG_d_f*i_q_f - vG_q_f*i_d_f`. Reusing the measurement result preserves
its frame, transformer scaling and filtering conventions. The normal dynamic
VAC PI equation remains intact; Q-V droop already determines Q and receives
no extra equilibrium condition. The focused tests check the solved P/Q and
full equilibrium residual for both MMC representations and for TLC VAC with
P and Vdc control. M5b station round-1 results are recorded below.

The complete before/after Julia regression archives in
`/tmp/mmc-vac-baseline/` contain 1,393 networks, 2,756 converter records and
2,703 numerical calculation outputs per phase. The per-network table
`regression.tsv` reports 1,389 bit-identical networks; only the four MMC
VAC/Q-V diagnostics change their power-flow points, steady states and
dependent admittances. All original calculation outputs and all 29 TLC
records without VAC are bit-identical. Both previously failing VAC
point-consistency checks pass in the focused 82-test suite. Converter
validation passes 5,938 assertions, and Aqua passes all 11 checks. The final
Julia 1.10.11 `Pkg.test()` run passes all 112,292 suite assertions.

The legacy Σ adapter defect was corrected in
[step 2](legacy_converter_adapters.md) (`f6392c2`). Restoring those controls also
resolved converter-uncertainty trial 94 in `examples/P2P_HVDC_Gridspace.jl`
(master seed 2028, derived seed `1756036741226661978`). Step 3 verified both
converter equilibria return `Success`, with infinity residual
`4.656612873077393e-10`, and all 100 trials complete without an exclusion.
Solver tolerances and iteration limits were unchanged. The Classic fallback's
undefined name was fixed in step 1 (`8af4577`), and the repeated converter
equilibrium solve is removed by the internal retained-state accessor in step 4.

Developer known gaps:

- M3 passes the station rerun with the step-6 references. The exported AVR now
  uses the network-side terminal-voltage magnitude; its station check is pending.
  The internal machine Vt output remains a diagnostic; see the M3 note above.
- Step 5 adds modular `DCVoltageSupportLag` and maps legacy `:vdc_droop` for
  MMC and TLC. PSCAD generation remains deferred: the exporter rejects this
  support as “not yet exportable” before recovering its equilibrium. The
  declared-base power-flow mapping deliberately corrects the historical
  off-nominal voltage mismatch; see the 672 kV example in
  [Legacy converter adapters](legacy_converter_adapters.md#DC-voltage-support-and-power-flow-bases).
- The complete legacy keyword audit, supported mappings, historical comparison
  limits and remaining proposals are recorded in
  [Legacy converter adapters](legacy_converter_adapters.md). Static and
  higher-order MMC voltage support, old GFM/virtual-impedance paths
  and TLC arm-parameter ownership remain separate design decisions. Legacy DC
  filters are local to the DC PI. The TLC PLL retains the validated modular
  filtered-measurement convention, an intended historical difference recorded
  with numerical evidence in the adapter audit.
- Archived `test/converter_voltage_test.jl:183:solved.network:2` is an accepted
  cross-formulation initialization limitation, not a package code defect or
  evidence of infeasibility. Its extreme shared-bus case places about
  −125,000 MW at the converter; the upstream default current-magnitude seed
  is negative (about −125 pu) despite a nonnegative bound. Restoration fails
  with constraint violation about `1.56e4`. The archived feasible point seeds
  the unchanged strict solve successfully, with maximum violation
  `5.066394805908203e-7` (`/tmp/package-fixes-step1/archived-repro-after.log`).
  Current fixtures with an explicit grid reactor converge. No solver setting
  or additional production workaround is changed.
- Nontrivial `OuterReactiveVacControl.filter` and `OuterActiveVdcControl.filter`
  are supported by the Julia model but fail fast as “not yet exportable” in
  PSCAD. The generator currently implements only `NoFilter`. Nontrivial total-energy feedforward filters and
  nonzero CCC references also require a separate Σ-generator review; see the
  adapter audit.

## M5b: remaining grid-following MMC outer controls

M5b enables `OuterActiveVdcControl`, P-f support through
`OuterActivePowerControl`/`FrequencySupportLag`, Q-V support through
`OuterReactiveQControl`/`VoltageSupportLag`, and `OuterReactiveVacControl`.
The MMC uses the M4 shared active/reactive generators rather than separate
MMC implementations. VAC is a new shared reactive generator, also exercised
with a TLC. Unsupported concrete blocks still fail by dispatch. The existing
Σ, electrical, modulation, module-canvas and named-node constructions remain
in force. No core code or public API is changed.

| Control | Generated equation / initialization | Saved evidence |
|---|---|---|
| Vdc | `e=vdc_ref-v_dc_f`, `i_d_ref=-(Kp*e+ξ_v_dc)`, `ξ'=Ki*e`; VDCCTRL integral starts at converged `ξ_v_dc` | `local/GFL-MMC/DVC-Mode/GFL_MMC_Validation.pscx:2020–2045` (5/15 gains, 800 kV); existing M4 split PI and negation |
| P-f | `ξ_f'=ωc*(-Kω*(omega_c-1)-ξ_f)`, `P_eff=p_ac_ref+ξ_f`; lag starts at converged `ξ_f_supp` and P PI at `ξ_P_ac` | `local/TLC/Simple_2L_VSC_RL.pscx:876–877`: `kp_f=5`, `tau_f=0.5 s`; current API `Kω=5`, `ωc=2 rad/s` |
| Q-V | `ξ_v'=ωc*(K*(v_ac_ref-hypot(vG_d_f,vG_q_f))-ξ_v)`, `Q_eff=q_ac_ref+ξ_v`; lag starts at `ξ_vac_supp`, Q PI at `ξ_Q_ac` | `local/GFL-MMC/Q-V_Droop/GFL_MMC_Validation.pscx:11992–11998`: `Kd=20`, `wf=100`; M4 `realpole` fields and pins |
| VAC | `e=v_ac_ref-hypot(vG_d_f,vG_q_f)`, `i_q_ref=Kp*e+ξ_v_ac`, `ξ'=Ki*e`; PI starts at converged `ξ_v_ac` | `local/GFL-MMC/VAC_Control/GFL_MMC_Validation.pscx:8025–8215` (split PI), `11936–11941` (0/100 gains); M4 square/sqrt primitives |

Both Q-V and VAC references are `SetpointPU.v_ac*voltage_filter_ratio(model)`:
MMC references and measurements use the converter side of the transformer;
TLC has ratio 1. The normal VAC PI remains a dynamic equation. Initialization
uses the committed equilibrium constraint, including solved reactive power,
instead of the original requested Q or an initial guess. Every new mode
recovers the same converged Julia problem and uses its states, filter outputs
and derivatives, PI integrals, support lags, arm capacitors and delay histories.
The final MMC 0.2 s hold protects only the measured DC-voltage divisor.
VAC Q feedback and Vdc voltage feedback run live from the first step.

`test/pscad/fixtures.jl` supplies classic and builder versions of each mode.
All MMCs retain the M5a 1000 MVA / 333 kV / 800 kV plant, exact 333/380 ratio,
OCC/PLL/CCSC gains, full Σ additions, NoFilter and zero modulation delay.
Their additional provenance and non-one-to-one parameters are:

- Vdc uses the saved 5/15 PI and 800 kV target. Its DC side has no stiff DC
  source: the remote PQ MMC and 60 km bipolar cable are rebuilt directly from
  `local/GFL-MMC/DVC-Mode/DC_Voltage_Control.jl:62–104,126–133`, including
  the -608.3578 MW/-200 MVAr sending request, its 800*1.00009 kV seed and
  cable layers/positions. The saved PSCAD current source at `:2565–2573`
  (`0.7527 kA`, 0 Hz, zero phase, 0.05 s ramp) is replaced by that script's
  remote plant. Its current/ramp parameters have no one-to-one counterpart.
  The script's ideal AC sources are retained rather than the saved source's
  0.5 Ω R field. The saved 1 Ω feed resistor (`:2538–2545`) is omitted with that source.
  The existing exporter supplies 1e7 Ω pole references at both DC buses;
  their placement differs from the saved single ground return (`:2548–2553`).
  No artificial DC-voltage target is introduced.
- P-f reuses the entire PQ plant and 600 MW/200 MVAr request. Its frequency
  support parameters come from the validated TLC, not a saved MMC P-f case;
  only the support lag is added, using the MMC's own P PI and power base.
- Q-V retains the saved `Kd=20`, `wf=100` and the Main 600/-200 power constants
  (`Q-V_Droop/GFL_MMC_Validation.pscx:785–797`). Its source R field is
  0.01 Ω (`:687–710`), represented as an explicit series resistor. Other
  saved source impedance fields are not used to infer an additional circuit.
  The remote DC system is reduced to M5a's ideal DC source; the saved
  0.05 Ω DC-source resistance is omitted.
- VAC retains the saved 0/100 PI and the explicit 0.1 H AC grid reactor in
  `VAC_Control/VAC_Control.jl:104–116,133–138`. This gives VAC a controlled
  bus separate from the source. The saved source's Type=4/R/L/C fields are
  not interpreted as another impedance; the fixture follows the script.
  The remote DC converter/cable is reduced to M5a's ideal DC source, omitting
  saved DC source R=0.05 Ω. The 200 MVAr request is a seed: solved Q supplies
  the operating-point reference and VAC integral.
- The TLC VAC test/experiment uses the M4 TLC plant and the same shared VAC
  block, with the validated 0.1 H reactor separating its controlled AC bus
  from the source. TLC cases without VAC keep their original fixtures.

References are rebuilt from the solved Julia setpoints, as in M4/M5a.
Consequently Q-V uses the solved terminal voltage and Q (rather than the saved
fixed 1 pu/200 MVAr requests) when recovering its support/PI equilibrium;
VAC uses solved Q to select its integral. Each representation has its own
reference TSV, including its power-flow differences.

The M5a differences also apply to every new MMC: TEC gains 1.386/29.70 and
ZSCC gains 0.1048/48.1914 are explicit full-Σ additions, rounded saved voltage
ratio 0.8763 becomes exact 333/380, saved 640 kV capacitor guesses become
converged values, and the accepted near-ideal YY realization adds its existing
leakage/exciting current. Saved `t_rst=0` does not introduce a control reset;
all integrators use solved states and the existing fresh-run/hold construction.
During this campaign the legacy adapter dropping Σ controls was bypassed.
Step 2 subsequently restored those controls; step 5 adds modular DC-voltage
droop, with its PSCAD generation still deferred as documented above.

The acceptance script retains every M1–M5a case and adds all new classic/builder
fixtures and both ramp cases in one pass (32 projects). MMC cases use saved 10 s / 10 us / 250 us settings and
zero source ramp; 10 s covers twenty P-f lag time constants. TLC VAC retains
M4's 10 s / 10 us / 40 us and 0.05 s ramp. The existing comparison rows and
limits apply: internal/terminal P/Q on the converter base, capacitor cycle
means against solved Vdc, signed DC currents and `idc=3*iS_z`. No tolerance
or probe template is added. `test/manual/pscad/write_m5b_experiments.jl` writes
`/tmp/pscad-m5b-experiments/` with README and reference TSVs containing solved
terminal/bus values, internal pu references and complete converged vectors.

Both source-ramp experiments passed station round 1: PQ MMC with the default
0.05 s ramp, and TLC case 2 with zero ramp. The original PQ diagnostic project
changed only Main source `Tc` fields after building the zero-ramp plan; all
module sources, namespace, canvas and output settings were retained. It ran
10 s with finite output, as did the zero-ramp TLC, whose settled result was
unchanged from its ramped case. These results remove the MMC-only rejection:
every supported converter now accepts any finite, nonnegative source ramp.
The library default remains 0.05 s; normal MMC fixtures retain zero and normal
TLC fixtures retain the default. The experiment writer now exports default-ramp
PQ directly, and the acceptance script includes both cases. Tests cover default
and nondefault ramps for every new mode, verify Main source `Tc`, and preserve
all module initial states, control components and wiring.

Plan tests check named-node connectivity and electrical topology on every new
canvas, solved startup including VAC Q, and PI/lag values and derivatives
against the Julia equations at displaced inputs. Synthetic comparison rows
use each mode's solved terminal references. XML round trips cover all new
exports and retain complete cited witnesses in
`test/pscad/fixtures/mmc_modes_saved_fragments.xml`; existing M4/M5a witnesses
still cover every primitive field, port and orientation. These are local
structural/equation checks. Native station evidence follows.


### M5b station round 1

All twelve projects built and ran 10 s with finite channels and no build/runtime
errors. MMC sampling was 250 us and TLC sampling was 40 us. The archived inputs
are `/tmp/pscad-m5b-results/<project>.csv` and each project's own
`/tmp/pscad-m5b-experiments/<project>_reference.tsv`. The manual
`test/manual/pscad/compare_m5b_results.jl` reconstructs probe ownership but takes
all numeric bus/terminal comparison references from those TSVs, rather than
rebasing them to a new solve. Detailed rows and the summary are in
`/tmp/pscad-m5b-comparison/`. Every one of 252 rows passes the existing policy:
1% voltage/capacitor means, 2% current with the approved DC bases, 1 degree
relative AC angle, and 0.01 pu of rating for terminal/internal P/Q. Signed
`i_dc=3*mean(iS_z)*Sbase/vDC_base` identities also pass. DC voltages use the
physical pole difference; internal Vdc/frequency/rotating angle remain the
existing diagnostics. The rotating `theta_c` settling warning is expected
for its continuously increasing nominal-frequency angle, not an operating-point
comparison failure.

The worst row per project, selected by error divided by its approved limit, is:

| Project | Rows | Result | Worst row | Error | Limit |
|---|---:|---|---|---:|---:|
| mmc_vdc_classic | 35 | pass | SEND_2_v_Ctot_u_b | 0.173734% | 1% |
| mmc_vdc_builder | 35 | pass | SEND_2_v_Ctot_u_b | 0.173734% | 1% |
| mmc_pf_classic | 17 | pass | DUT_v_Ctot_l_b | 0.069215% | 1% |
| mmc_pf_builder | 17 | pass | DUT_v_Ctot_l_b | 0.069215% | 1% |
| mmc_qv_classic | 21 | pass | DUT_v_Ctot_l_b | 0.069053% | 1% |
| mmc_qv_builder | 21 | pass | DUT_v_Ctot_l_b | 0.069048% | 1% |
| mmc_vac_classic | 21 | pass | DUT_v_Ctot_u_a | 0.056697% | 1% |
| mmc_vac_builder | 21 | pass | DUT_v_Ctot_u_a | 0.056723% | 1% |
| tlc_vac_classic | 17 | pass | I_DUT_1 | 0.017938% | 2% |
| tlc_vac_builder | 17 | pass | I_DUT_1 | 0.018201% | 2% |
| mmc_pq_default_ramp | 17 | pass | DUT_v_Ctot_l_b | 0.069215% | 1% |
| tlc_case2_zero_ramp | 13 | pass | I_CableDC12_1 | 0.082770% | 2% |

Capacitor errors are relative to solved Vdc. TLC current errors use the
approved converter DC current base, rather than relative error at a small
reference current. Full CSV comparison checks every channel for finite data
and includes each converter's network-side fundamental P/Q, its filtered
internal P/Q, DC voltages/currents and all six MMC capacitor means.

Q-V and MMC VAC differences between representations primarily reflect their
distinct solved points and exported references, not a changed control topology:

| Mode / representation | Solved Q [MVAr] | Native terminal Q [MVAr] | Native internal Q [MVAr] |
|---|---:|---:|---:|
| Q-V classic | 199.216172 | 198.768574 | 198.818523 |
| Q-V builder | 199.169011 | 198.721613 | 198.771560 |
| VAC classic | 39.329910 | 39.311339 | 39.357494 |
| VAC builder | 38.679827 | 38.676647 | 38.722803 |

Q-V's solved Q difference is 0.047161 MVAr and its native internal difference
is 0.046963 MVAr. VAC's corresponding differences are 0.650083 and 0.634690
MVAr; the difference between their own-point residuals is only 0.015393 MVAr.
The actual projects retain those targets: Q-V source line RMS voltages are
379.999109/380.0 kV and measured-side references are
1.000039196865/1.000041549425 pu; VAC source voltages are
380.000342/380.019669 kV and references are 1.000000963924/0.999912741066 pu
(classic/builder). VAC also retains each solved integral. The small voltage
differences matter for voltage regulation through the 0.1 H reactor. Internal
Q and network-side Q are separate measurements across the accepted near-ideal
YY realization; both are tested against each representation's solved Q.
No implementation change or tolerance relaxation is needed for these results.

The reference writer also corrects the reactive-power unit labels for `qgrid`
and `qg` to MVAr. Twenty-eight archived labels were corrected with every numeric
reference and state unchanged; the metadata changes are listed in
`/tmp/pscad-m5b-comparison/reference_unit_corrections.tsv`.

### Stop condition: repeated classic power flow reverses fixed Q

The supplied station projects still pass all 252 rows. A subsequent cross-check
of the newly exported ramp cases against those station projects exposed a
separate core defect: calling `power_flow` twice on the same classic modular
converter network reverses the fixed reactive-power request. A standalone
reproduction, without PSCAD export, is recorded in
`/tmp/pscad-m5b-comparison/repeat_q_powerflow.jl` and its TSV/log:

| Converter | Solve | Qac before [MVAr] | Solved qgrid [pu on 1000 MVA] | AC injection [MVAr] | Qac after [MVAr] |
|---|---:|---:|---:|---:|---:|
| MMC | 1 | 200 | -0.2 | 200 | -200 |
| MMC | 2 | -200 | 0.2 | -200 | 200 |
| TLC | 1 | 20 | -0.020000428 | 20.000428 | -20.000428 |
| TLC | 2 | -20.000428 | 0.020000428 | -20.000428 | 20.000428 |

Current `src/Network/power_flow.jl:192–197` stores the solved `qgrid` directly
in `Setpoint.Qac`. The next conversion reads that setpoint directly into `Q_g`
(`converter/MMC/MMC.jl:407`, `converter/TLC/TLC.jl:481`), so the request changes
sign. The legacy MMC applies `Qac *= -1` before storing `converter.Q`
(`src/Network/Components/converter/MMC_legacy.jl:173–179`). Thus the current
request/solved-point sign handling differs from the legacy path. Core files
are unchanged in this work; no correction or workaround is implemented.
The new acceptance/XML ramp entries currently re-solve networks already used
by the regular PQ/TLC exports and therefore trigger this defect. Their new
exports must not be treated as reproductions of the accepted station cases.
The experiment writer and CSV comparator use fresh fixture instances for those
cases; the original station project files and numeric references are retained.

Work stopped under the core-defect rule. The approved ramp rejection removal
is present, and the new mode/ramp tests pass 526/526. The PSCAD suite reports
15,204 passed and two failed obsolete zero-ramp rejection assertions at
`test/pscad/mmc_test.jl:212`; these remain to be updated. XML round trips pass
260,870/260,870 across 32 exports, which checks serialization rather than this
cross-export operating-point invariance. Aqua passes 11/11, changed-code
formatting and `git diff --check` pass, and the final full `Pkg.test()` was not
started after the stop condition was confirmed. M5b follow-up is incomplete.

## M6a: grid-forming MMC with VSM and CCVI

`ΔdqControlGFM` exports the current Julia sequence: reactive outer control,
`CCVI`, then the existing OCC. `VSEWithDamping` reuses the M4 PLL generator;
its voltage is rotated by `Δθ_pll-Δθ_VSM` before the embedded PLL filter.
The VSM implements
`ω_VSM'=(p_ac_ref-P_ac_f-K_d*(ω_VSM-ω_PLL)-K_ω*(ω_VSM-ω_ref))/(2H)`.
Its EMT angle integrates `ωbase*ω_VSM`; subtracting the nominal angle gives
the Julia relative angle with derivative `ωbase*(ω_VSM-1)`.
`omega_c` is the VSM frequency. PLL outputs use separate local nets.

CCVI filters both measured voltage axes and sets `e_d=V_d_ref+q_ctrl_ref-v_d`,
`e_q=V_q_ref-v_q`. Its current references are
`i_d=(R_v*e_d-ω_c*L_v*e_q)/(R_v²+(ω_c*L_v)²)` and
`i_q=(R_v*e_q+ω_c*L_v*e_d)/(R_v²+(ω_c*L_v)²)`, exactly as `inner_voltage.jl`.
No denominator floor, additional filter or control limit is introduced.
The reactive generator's output is connected as a voltage correction before
CCVI; its two current outputs supply OCC.

The saved primitive witnesses are in
`local/GFM-MMC/FFVI-VSM/PSCAD model/FFVI.pscx`: CCVI at 65168–66145,
PLL at 67793–68955, swing equation at 68956–70164, and voltage/power filters
at 57638–58619. `test/pscad/fixtures/mmc_gfm_saved_fragments.xml` retains
cited fragments. The exporter composes these primitives to follow Julia;
the saved project's separate FFVI direct voltage path is not the requested
CCVI/OCC model. The existing Butterworth realization supplies solved output
and derivative initial values rather than the saved transfer-function guesses.

`mmc_gfm_network()` mirrors `build_mmc_grid()` in `test/adm_MMC_test.jl`:
1060 MVA, 320/400 kV LL RMS, 640 kV DC, 742 MW/0 MVAr, VSM 5/100/10,
CCVI 0.01/0.25, the test's PLL/measurement/CCVI/OCC filters,
TEC/ZSCC/CCSC and 200 us Padé(5,5) modulation specification.
The export retains the accepted near-ideal YY transformer and exact dq delay
with phase compensation; the previously documented transient/frequency-response
difference from Padé remains. Converged states come through the core accessor.
TEC circulating-current feedback uses the core `syncangle`, which is
`Δθ_VSM` for this model, live from the first step. The final construction
has one measured-DC divisor selector in MEAS and no Σ current/energy selectors.

Both acceptance cases use 10 s, 10 us integration, 250 us sampling and zero
source ramp, with `dc_reference=:none` because the DC source grounds its midpoint.
The saved FFVI timing is 5 s/1 us/250 us (lines 4–6); the selected 10 us step
follows the accepted MMC cases. Probe names and converter comparison rows are
reused. The existing `omega_c` probe uses the existing `:machine_speed` kind
and row with `abs(mean(omega_c)-1)<=1e-3 pu`; all other limits are unchanged.
Its row is selected by probe metadata, including when name reservation adds a suffix.

`test/manual/pscad/write_m6a_experiments.jl` writes both projects to
`/tmp/pscad-m6a/`, their solved terminal/internal references, all 59 converged
states in indexed TSVs, and a short README. Local plan/connectivity/topology,
XML round trips and state-equation tests establish the mapping. Native station
acceptance remains separate: both cases must build, run finite, settle and pass
every row over the final ten cycles `[9.8,10.0] s`.

## M6b: leg-energy control and physical compensated modulation

`ΣdqzControlLEC` exports `ΣEnergyControl`, `ΔEnergyControl` and
`CirculatingCurrentControl` in their Julia sequence (`MMC/MMC.jl:128–136`).
The live energies are `(vu²+vl²)/vDC_base²` and `(vl²-vu²)/vDC_base²`.
Their projections give Julia's `2wΣ` and `-2wΔ`
(`src/Network/Components/converter/MMC/energy.jl:67–151`). Σ d/q use
`-2*ωbase*t`; Δ d/q use `ωbase*t`. The scalar Δ zero sequence is lifted
into the triplen pair by twice its product with `cos(3*ωbase*t)` and
`sin(3*ωbase*t)`. Cycle means reproduce the seven energy coordinates;
the physical abc plant retains additional harmonics, including the 6ω
triplen ripple, as in M5's physical total-energy measurement.

The explicit notch states obey `F1'=F2-sqrt(2)*ωn*(F1+u)-Jframe*F1`,
`F2'=-ωn²*F1-Jframe*F2`, with output `u+F1` and rotating PI
`ξ'=Ki*(ref-u-F1)-Jframe*ξ`. Σ uses `ωn=2ωbase`, `Jframe=-2ωbase*J`
and references `(0,0,2ref)`. Δ uses `ωn=ωbase`, frames `+ωbase` and
`+3ωbase`, zero references, and current outputs
`3/4*(d+Zd, -(q+Zq), 0)`. Frequencies stay at their Julia nominal values;
there is no additional filter or actual-frequency substitution.

The corrected triplen block follows the reconstruction
`T=[cos(3θ) sin(3θ); sin(3θ) -cos(3θ)]`: `Tdot*T=-3ωbase*J`, so
`x'=u-Jframe*x` requires `Jframe=+3ωbase*J`. The former `-3ωbase*J`
notch/PI block rotated against the plant. The fixture retains the original
Δ PI gains (`k=1`), matching the core compensated-admittance test. Its former
`+0.115752 ± j942.538554 s^-1` pair (150 Hz, 99.8% Δ-triplen PI participation)
becomes `-12.550944 ± j940.716108 s^-1`; all 89 poles are stable. Beyond the
deliberately slow stable OCC filter poles (`-0.000628319 s^-1`), the
least-damped pair is `-4.873459 ± j10.339475 s^-1`. These are Julia
linearization results; native station evidence follows below.

CCC uses the grid-frame currents directly, adds the Σ and Δ current
references, and implements `ξ_i'=Ki*(iref-i)-J_-2ω*ξ_i` and
`vMΣref=-(ξ_i+Kp*(iref-i))+(0,0,v_dc_f/2)`
(`src/Network/Components/converter/MMC/inner_current.jl:81–104`).
Unlike TEC/CCSC, these currents are measured at the nominal grid angle,
without a VSM-relative rotation. All three current measurements and all seven
capacitor-energy inputs are live from `t=0`, closing CCC under the live energy
loops. Only the measured DC-voltage divisor in the three Σ current commands
uses the shared 0.2 s hold; the half-DC feedforward is live.
All 24 notch/PI integrators use the converged states. Physical arm
currents and capacitor dynamics remain active throughout startup.

The standard EMT compensated realization uses physical arm-capacitor division:
each upper arm uses `(vΣref-vΔref)/v_Ctot,u`, each lower arm
`(vΣref+vΔref)/v_Ctot,l`, followed by the existing exact `tdelay` primitive.
Δ references use the AC voltage base and `theta_c`; Σ uses the DC base
and nominal `-2ωbase` frame, following `modulation.jl:138–141`.
There are six 200 us physical arm delays, with histories initialized to
that arm's own solved physical ratio at the initial angle. Exact delay
and the specified Julia Padé(5,5) have different frequency responses
away from steady state, as already recorded for uncompensated modulation.

Julia's law is a seven-coordinate harmonic-domain matrix solve
(`src/Network/Components/converter/MMC/modulation.jl:143–152`), which
approximates the physical per-arm division. The prescribed steady-harmonic
preflight, with positive arm capacitors, measured insertion indices
differing by up to `0.00399397` (about `0.004`) before any delay.
This is measured evidence for that preflight, not a universal bound.
Julia's `mΔZd*cos(3θ)+mΔZq*sin(3θ)` maps to the third-harmonic content of
the physical upper-minus-lower insertion waveform. Per-arm division also
produces higher harmonics; the six physical delays apply to the entire
waveform, including its triplen content. No extra triplen voltage command,
insertion-index probe, comparison row or tolerance is introduced.

`mmc_compensated_network()` mirrors `test/adm_MMC_compensated_test.jl:53–190`
in classic and NetworkBuilder form: the M6a 1060 MVA / 320–400 kV / 640 kV
plant and VSM/CCVI/OCC, Σ and Δ energy PI gains `0.5544/5.94`, CCC
`0.0992/42.9719`, and 200 us compensated modulation. Saved primitive
witnesses are retained with exact source-line comments in
`test/pscad/fixtures/mmc_energy_saved_fragments.xml`: FFVI's CCVI division
and multiplication (65904–65910, 65832–65838), VSM integrator
(69814–69829), energy square (70421–70427), rotation trig (66570–66578),
constant (3604–3610), and GFL PQ exact delay (8950–8961). These witness primitive fields and
ports; the energy equations are the current Julia equations, rather than
an unrelated saved control substituted for them.

The acceptance entry and `test/manual/pscad/write_m6b_experiments.jl` use
5 s / 1 us / 250 us for compensated MMCs, zero source ramp and `dc_reference=:none`.
Both the exported settings and the acceptance run options use this timing.
Other acceptance cases and the writer's ten M5 cases retain their existing timing.
The writer produces both revised projects in `/tmp/pscad-m6b/`, each project's
solved references and all 89 converged states in indexed TSVs, and a README.
It also writes ten revised M5 MMC exports (pq, pf, qv, vac and vdc, classic
and builder) with their own references to `/tmp/pscad-m6b/m5-recheck/`.
Probes and rating-normalized converter comparison rows are reused;
energy references are checked through the six arm-capacitor cycle means.
The existing VSM speed row remains. After the core frame correction
(`3d92c61`), the station's 10 us compensated case still grew from about
2 s and became non-finite at 2.88 s. At 1 us, the integration step of the
validated FFVI reference, it remained settled from 1 s through 4.8 s:
`P=0.7000000`, `Q≈1e-7`, `omega=1`, `iS_z=0.233935` (reference `0.233948`),
all six arm-capacitor means 639.4–639.5 kV and constant 77.9 kV ripple.
The remaining instability is a time-step effect of the PSCAD realization.

`export_pscad` emits one warning per export when any MMC uses
`CompensatedModulation` and the requested `time_step` exceeds 1 us. The
warning names the affected converters and requested step, identifies 1 us
as the validated step and states that 10 us grows unstable. Export continues
with the requested settings; the global default is unchanged. No warning
is emitted at or below 1 us, or for other modulation types.
Offline equation, connectivity, topology and XML checks remain separate
from station acceptance: both cases must build, run finite, settle and
pass every existing row over the final ten cycles `[4.8,5.0] s`.

## M7: IEEE9 acceptance and P2P dynamic validation

The legacy MMC mapping used by `examples/P2P_HVDC_ALT.jl` selects
`NoTotalEnergyControl` and `NoZeroSequenceCurrentControl`, with the supplied
circulating-current suppression PI. The exporter now follows the owned optional
Σ controls individually. `NoTotalEnergyControl` supplies zero `iΣ_z_ref`;
`NoZeroSequenceCurrentControl` supplies zero PI correction, retaining live
`v_dc_f/2`; `NoCirculatingCurrentSuppressionControl` supplies zero d/q commands.
There is no added energy loop, power feedforward, state or reset for a disabled
control. Enabled controls retain their existing equations and initial states.
The measurement module's single DC-divisor hold and all live feedback remain
unchanged. Tests compare all eight combinations with the owned state-space
equations at displaced current, capacitor energy and DC voltage inputs.

Two-conductor DC `Overhead_line` elements use the same universal-tower row and
material/earth/fitting mapping as AC lines. Physical conductor 1 is P and
conductor 2 is N, at both ends. Coordinates are exported before sag correction;
ground wires remain eliminated. DC fitting retains `FS=0.001 Hz`, `DCenab=0`.
The TLine wrapper uses `Mode=0`, `Dim=2`, `Freq=0 Hz` and its existing length
and coupling fields; its vertices are graphical. Each remote end uses
`master:tline_interface` with matching `Name`, `NC=2`, `View=0`, `send_recv=0`,
`dim_s=dim_r=0`. Both automatic end specifications follow the uncoupled-line
mapping. Sending orientation is 0, receiving orientation is 4. P has a scalar
series ammeter; N has a direct node-label stub.

These fields and ports were read from the PSCAD 5.1.0 station's `master.pslx`,
SHA256 `0d181e2f1c3eb57ae8019ba6d6311aee458dda02d080a8c4a92c26e6fdad5aeb`.
For `NC=2` and individual-phase view, its scalar A/C ports are `(-18,-18)` and
`(-18,18)`; orientation 4 mirrors x. The relevant form/port definitions are
retained in `test/pscad/fixtures/dc_ohl_interface.xml`. The official
[overhead-line interface documentation](https://www.pscad.com/webhelp/Master_Library_Models/Transmission_Lines_Cables/Transmission_Line_Models/tline_cable_int.htm)
specifies conductor order from top to bottom. Connectivity checks treat remote
TLine wrappers as graphical and their interfaces as the electrical terminals;
the existing direct AC wrapper remains unchanged.

`test/manual/pscad/acceptance_m7.jl` is separate from M1–M6. It writes projects,
reference TSVs and inventory to `/tmp/pscad-m7/`, runs **only IEEE9**, and applies
`compare_operating_point` with the existing 1% AC voltage, 1 degree relative
angle and 2% current rules. IEEE39 classic and builder are also built through
the existing runner; their fresh `build-messages.txt` files determine the
build-only verdict. P2P is exported without building, running or comparing.
`--export-only` does not contact the station.

After the transformer rating correction, all 36 M1–M6 projects were re-exported
and compared with the `718636a` baseline
with the same Julia 1.12.7 Manifest. Their serialized bytes agree after replacing
only object IDs and the mhi-xml revision timestamp; no other difference remains.
The standalone YY/ΔY fixtures retain `V1/V2=380/150` kV; MMC interface ratings
are unchanged.

### EDUCATIONAL licence and network counts

The EDUCATIONAL licence allows **200 electrical nodes and one subsystem**
([edition limits](https://www.pscad.com/webhelp-v5-ol/Getting_Started/Dimension_Limits.htm)).
The station message `Subsystem splitting has been internally disabled` is
normal for this licence. Distributed lines/cables naturally separate electrical
subsystems, but splitting is disabled here. Bus conductor nodes exclude ground
and internal component nodes; they are not the licence-counted live-node total.

| Case | Elements | AC/DC buses | Bus conductor nodes | Live nodes | Natural / EDU subsystems |
| --- | ---: | ---: | ---: | ---: | ---: |
| IEEE9 classic | 15 | 9 / 0 | 27 | 78, station evidence | 6 / 1 |
| P2P classic / builder share 0.25 | 8 | 4 / 3 | 18 | 65, station evidence | 5 / 1 |
| IEEE39 classic | 90 | 49 / 2 | 151 | 528, station evidence | 28 / 1 |
| IEEE39 builder | 89 | 49 / 2 | 151 | 528, station evidence | 28 / 1 |

IEEE39 classic and builder are **export verified (licence-blocked)**: both
station builds report the sole error `The current license is limited to a maximum of
200 electrical nodes. This project contains 528 electrical nodes.` and
the summary `Build: 1 errors, 0 warnings`.
The criterion is a completed export with all offline checks and a station build
whose only error is the licence node-cap message, with no warnings.
Classic has 11 sources, one TLC, 12 transformers, 32 impedances and 34 OHLs;
builder disconnects `T8_9`, giving 33 OHLs. The existing legacy STATCOM mapping
keeps its explicit `Vₘ`-derived setpoint despite the differing supplied
`vac_supp` reference; no example parameter is rewritten.

### P2P dynamic-validation record

The classic 25 km cable + 75 km DC OHL network is unstable at its solved Julia
point. Two verified c1 network roots are **+1374.359 / +1426.121 s⁻¹** at
**3428.518 / 3526.556 Hz dq**. The nearby 50 Hz abc sidebands are
3478.518 / 3476.556 Hz (approximately 3.48 kHz), with growth times
0.728 / 0.701 ms. The station's 1 us, 50 us sampled B3 phase-a trace fits
**3473.033 Hz / 0.687548 ms** over 0.3–1.8 ms. PSCAD therefore reproduces the
unstable mode; this is **dynamic validation, not operating-point acceptance**.
Among explicit converter states, c1 differential modulation-delay states carry
98.81–98.84% participation; implicit distributed-line states are excluded from
that normalization. The 200 us modulation delay interacts with `tl1`'s roughly
3 kHz resonance. Exact delay versus Padé 5/5 phase differs by only 0.0345–0.0458
degrees at the two roots.

The authorized builder screen used share 0.25, all original parameters, and
c1's c2 interface (`333 kV`, `333/380`, `Lᵣ=0.0461 H`, `Rᵣ=0.4103 Ω`). Both
converter delays were varied as below; Padé orders stayed 5/5. All power flows
solved; complete-network scans over 0.01 Hz–100 kHz failed every candidate:

| Candidate | Both delays | Largest located Re(s), s⁻¹ | dq frequency, Hz | Nyquist net |
| --- | ---: | ---: | ---: | ---: |
| V1 | 200 us | +1341.276 | 3500.142 | 10 |
| V2 | 100 us | +331.226 | 8932.535 | 6 |
| V3 | 50 us | +263.933 | 15058.576 | 2 |

No fourth variant or physical correction was applied. P2P returns to the model
owner. The committed IEEE14 hybrid (`test/make_y_node_test.jl`) also failed its
unchanged complete-network screen: largest located root **+72.786701 s⁻¹ at
29.652282 Hz dq**, full-network Nyquist net **3** over the same band. Its second
confirmed RHP root is +20.515535 s⁻¹ at 82.762656 Hz; no variant or export followed.

P2P builder is now exported only at share **0.25** (25 km cable + 75 km DC OHL).
The gitignored classic file remains guarded by `isfile` and is loaded only in
this manual script. Its old phase-RMS source `V` maps to `sqrt(2)*V`; diagnostic
scans/plots are excluded. P2P and IEEE39 records retain **25 s / 10 us / 250 us**,
zero source ramp. Saved failing endpoint projects and station traces remain
historical evidence, outside the script's acceptance cases.

### Short distributed sections

OHL and cable emitters warn when `length / 299_792_458 m/s < time_step`, naming
the element, length and step. This conservative check is a warning, not an
error; PSCAD aborts if its calculated travel time is below the step. A smaller
step or a longer section is needed. The P2P example regularizes its cable/OHL
endpoints to 100 m, which cannot run at 10 us: station travel times were
0.329330 us for the OHL and 0.648293 us for the cable. No length is silently changed.

### IEEE9 acceptance fixture

`PSCADFixtures.ieee9_network()` is a classic `@network` fixture copied from
`local/IEEE9bus/IEEE9bus_abc.jl`, independent of that gitignored file. Every line,
transformer, load impedance and connection is preserved. The source `V` values
are already phase peak (16.5, 18 and 13.8 kV LL times `sqrt(2/3)`): they become
`Setpoint.Vac` unchanged, with **no extra sqrt(2)**. P/Q remain unspecified;
all three ideal sources become type-3 reference buses at angle zero, and their
P/Q injections are solved from the fixed voltages and network/load equations.
The current classic default phase-RMS base `220/sqrt(3)` kV is retained.
The explicit transformer model receives only inferred PF-bound rating metadata:
`V₁ᵒ=(16.5e3,18e3,13.8e3)/sqrt(3)`, `V₂ᵒ=230e3/sqrt(3)` V phase RMS. This follows
`test/Transformer_test.jl:113`; it avoids transformer conversion assuming the
common base at each primary. These fields do not enter `eval_abcd` for the
explicit model; no circuit parameter or tolerance changes.

SymEngine series impedances become functions of `s`; `transformation=true`
selects the supported balanced dq representation with the same steady state.
All three YY transformers retain `Cₜ=7 nF`, `Cₛ=12 nF`. These existing exported
paths follow `eval_abcd(::Transformer)` in
`src/Network/Components/transformer/transformer.jl`: terminal `Y_turn` shunts
around the T cascade, and `connect_parallel!` adds the stray bridge. No new
transformer field or equation is introduced. The near-ideal YY realization
remains the accepted M1–M6 mapping.

Settings are **3 s / 10 us / 100 us**, default **0.05 s source ramp**, final ten
cycles **(2.8,3.0] s**. The station measured **78 live nodes**, below the 200 cap;
rating YY and ΔY windings from the solved primary LL RMS voltage (rather than
the common bus base, or `V₁ᵒ`/`V₂ᵒ` metadata) gives IEEE9 16.5/230, 18/230 and
13.8/230 kV, and changing only these ratings removed the `NT_2` zero diagonal
and produced a finite 3 s station run (Bus1 peak 13.47 kV, Bus7 approximately
189 kV). Solved source dispatch and all nine
bus voltages/angles are written to `ieee9_classic_reference.tsv`.

IEEE9 **passed** on the EDUCATIONAL licence: **41 comparison rows**, all within
tolerance, with worst voltage magnitude error **2.19e-5 relative**, worst angle
error **4.99e-4 degrees**, and worst current error **0.169%** (`I_tl64_2`, **3.9 A**).
Evidence is `/tmp/pscad-m7/ieee9_classic_comparison.tsv`, station run
`local/pscad-exchange/m7/ieee9_classic/run-Hcm4nU`.


### M9a7–M9a9: constants attribution and tighter fitting defaults

Every AC/DC overhead-line and cable export now defaults to
`YMaxE=AMaxE=0.02 %`, retaining all other settings. `line_options` can override
both fields numerically or with explicit PSCAD unit strings. Projects containing
these components change; electrical topology, probe orientation, power-flow
references and Julia physics do not.

M9a7 used PSCAD per-length matrix dumps with the same conductor ordering and
internal sheath/armour/ground-wire elimination as Julia. Near 1 Hz, the AC cable
has both a constants difference (7.51% in per-length Z, 1.55% in terminal Y)
and a fitting contribution (4.32% in terminal Y). These percentages have
different denominators/directions and are not additive. DC OHL constants at
0.001 Hz give 1.9950563 ohm/pole, matching Julia, while its original fit gives
2.0516059 ohm/pole (+2.8345%): that resistance error belongs to the fit.

M9a8's sampled 1–1000 Hz **fit-versus-constants** relative Frobenius terminal-Y
errors were:

| Element | Original targets (0.2%) | Numf=400 | Targets 0.02% |
|---|---:|---:|---:|
| AC cable | 4.34% | 3.68% | 0.84% |
| DC cable | 2.88% | 7.32% | 0.49% |
| DC OHL | 4.31% | 4.09% | 0.35% |

The two tighter targets are the smallest tested successful change for this band;
changing only one target has not been tested. Yc orders per column rise from
10/13/11 to 19/20/18 for AC cable/DC cable/DC OHL. H orders per delay group
rise from 10/12/(6,7) to 15/18/(10,12). Retained build-plus-run times were
19.27/62.28 s for the two tighter-target diagnostic projects versus baseline
18.59/62.37 s; isolated build time is unavailable. These single measurements
are not a performance guarantee or a station tier-C pass.

Enabling functional-form DC correction (`DCenab=1`, `DCCOR=1`, FS=0.001 Hz)
failed both cable-containing diagnostic projects during Yc fitting:
`Error in INVCJD. Singularity occurs`. Both logs terminate in line constants.
Zero dielectric loss tangents with the V5 loss-tangent method are consistent
with a singular DC shunt/characteristic-admittance limit; the failed matrix is
not exposed, so that mechanism remains an inference. No leakage is added and
DC correction remains disabled by default.

**Documented PSCAD fitting limitation:** tighter targets do not constrain the
DC cable's true-DC extrapolation. With the 0.02% targets and FS=0.001 Hz,
DCenab=0, fitted resistance at s=0 is 0.4844791 ohm/pole versus Julia's
0.2724856 ohm (+77.8%); at 0.001 Hz it is 0.2754051 ohm (+1.07%), and full
terminal-Y fit error there is still 2.17%. DC OHL's fitted true-DC resistance
is 2.0001793 ohm versus 1.9950563 ohm (+0.257%). These are measured fixture
limitations, not assertions about every PSCAD cable. Constants differences
remain documented physics; no tolerance is relaxed and DC-cable operating-point
acceptance is not implied by the band improvement.

Evidence is retained locally in the gitignored validation data's
`m9a7/report.md` and `m9a8/report.md`, per-frequency tables, fit files, logs and
input hashes. PSCAD's [line/cable modelling guidelines](https://www.pscad.com/knowledge-base/download/Overhead%20Lines%20and%20Cable%20Modeling%20Guidelines%20for%20PSCAD.pdf),
printed pp.12 and 40–41, describe functional-form correction and the V5
loss-tangent handling. Existing station runs with 0.2% targets retain their
original project hashes and require re-acceptance under the new default.


## Converter execution boundaries

The MMC parent canvas contains the six arm sources, inductances, resistances,
meters and capacitor integrators. The isolated arm experiment shares this same
construction. The arm voltage product uses the insertion index from MOD in the
current dynamics evaluation, with no opaque ARM module command boundary.

`master:force_dsout` captures each applied insertion index and its post-solve arm
current. Their product supplies capacitor charging; `master:force_dsdyn` transfers
that charging history to the following dynamics pass. This preserves the physical
insertion/current pairing while exposing the source command dependency to PSCAD's
sequencer. Same-solve upper/lower currents also form the circulating-current
vector and DC-current sum in the electrical-output phase. One dynamics transfer
supplies that common measurement set to both TEC and LEC consumers.

MMC and TLC select their synchronization feedback boundary with
`master:zminusone`, initialized from the solved relative angle. All acquisition
and inverse rotations use that one relative-angle snapshot plus the nominal
angle at the current timestamp. GFM uses separate initialized VSM and PLL
snapshots; its PLL frame rotation uses their difference. The fresh measured q
voltage drives the PLL rate, and the updated relative angle feeds the next
evaluation's snapshot. Controller equations, physical values, initial capacitor
voltages, probes and the 0.2 s DC-divisor hold are retained.

This stage leaves every model modulation delay unchanged. Electrical measurement
and subsequent actuation retain the inherent EMT interface step. Native generated
order must be checked in kept builds (L2-07, L2-01 and L2-13): current MOD indices
must precede all six arm-source preparations, Σ/DC aggregation must occur after
one completed solve, and fresh q acquisition must precede PLL evaluation. Offline
connectivity/XML tests establish the requested structure, not the native schedule.
Delay compensation is deferred until that schedule is verified.


The first kept builds showed that the sources do consume current MOD outputs,
with fresh q acquisition preceding PLL evaluation. They also showed a capacitor
feedback cut: SIGMA received five advanced physical capacitor states and one
cached state (lower-c in L2-07, lower-a in L2-13). Capacitor measurement therefore
belongs in the same electrical-output acquisition set as the arm currents.
The seq3 and seq4 attempts captured physical capacitor voltages in DSOUT and
returned initialized deviations to DSDYN. Seq4 moved all deviation arithmetic
into DSOUT, but the dynamics reconstructions still formed a feedback cycle:
SIGMA (and compensated MOD) read selected previous reconstructions. Execution
phase qualifiers select scripts; they do not declare a state-history cut.

Each capacitor consumer now reads an initialized `master:zminusone` snapshot
of the applied physical capacitor state. This is the same explicit feedback
boundary used for synchronization states. Its input is the physical integrator
output, not an already acquired DSOUT copy. The physical state changes only in
DSDYN and is held throughout the following solve and DSOUT; therefore the next
DSDYN snapshot equals the capacitor voltage observed by that completed solve,
coherent with its acquired arm currents. Feeding a DSOUT copy through this
selector instead would add another step. SIGMA and compensated MOD share these
six snapshots. Source products and probes retain the advancing physical states,
and each snapshot has the same initial voltage as its physical integrator.

The next kept builds must show all six initialized capacitor snapshots available
before SIGMA and compensated MOD, with snapshot commits after the capacitor consumers and physical state
advances, and current-pass commands at every source. The previous applied capacitor level must equal
the completed DSOUT level; no extra delayed measurement may enter the selector.
Offline checks cover the bindings, initialization and distinct successive state
levels. Native ordering remains pending. Delay compensation remains deferred.


Seq4b kept builds verify one remaining interface step for MMC GFL, TLC, MMC
GFM and LEC/compensated MMC. All six capacitor snapshots are initialized before
consumers and committed from current physical states after source preparation.
The complete DSOUT level matches the following pass's state/current acquisition.
There is no residual two-step capacitor path in those builds.

Positive model delays now export `tau_model - dt`, valid only for
`tau_model >= dt`. Shorter positive delays require a finer step and are rejected.
Zero model delay retains zero explicit delay and the one inherent interface step.
A zero residual bypasses the queue; positive residuals retain the existing
history capacity rule and master delay realization. TLC and uncompensated MMC
use the residual carrier rotations (+omega for Delta, -2omega for Sigma) with
buffer initialization inverse-rotated from the target physical equilibrium.
Compensated MMC delays abc insertion indices with the residual and retains its
physical initial insertion values, with no additional dq phase rotation.
Model fields, controller formulas/gains, physical parameters and the divisor
startup hold are unchanged. Exact export delay versus Julia Pade realization
remains a separate model difference. The isolated electrical timing witness
checks actual library/interface timing before the L2 re-validation queue.


## Nearest-step residuals and DC pre-charge (M9c-2)

The converter residual budget rounds `(tau_model-dt)/dt` with
`RoundNearestTiesUp`: nearest integer, positive half-step ties upward. Zero model
delay retains the inherent step, and `0 < tau_model < dt` is rejected. Round-off
at an integer boundary is treated as integer timing; a fractional residual warns
with converter name, model delay, dt, requested/realized residual, realized total
and signed error. Quantization changes total physical transport by at most dt/2.
TLC and uncompensated MMC rotations/history seeds use the rounded residual;
compensated MMC uses the same rounded abc queue length and physical seed.

`emitters/dc_precharge.jl` owns DC-island detection and the startup sources.
Islands traverse elements' DC terminal incidence; ground is not an island edge,
and converters do not connect DC through their AC side. A qualifying island has
no `Source` attached to a DC bus and at least one TLC `OuterActiveVdcControl` or
GFL MMC active Vdc controller. PQ-only and GFM-only islands do not qualify.
Every bus in that island has a pair of sources at its positive solved
pole-to-ground magnitude and its negative. Missing/nonpositive solved voltages
are rejected; no power flow is silently performed by the plan builder.

Source fields/polarity follow the supplied
`local/P2P HVDC/PowerStabilityACDC_Validation.pscx:19424–19450` 639.843 kV source
and the existing `emitters/sources.jl` orient-0 NA-positive mapping. The series
`master:breaker1` field/pin witness is the same saved project:24613–24635;
orient-0 electrical ports are (-36,0), (+36,0). These saved instances are disabled
and therefore establish construction provenance, not native acceptance of this
new composite. The supplied station master `breaker1:5452–5665` declares NAME as
a real input and calls `E1PBRKR1_EXE(...,NINT(1-NAME))` (internal close flag). NAME=0 closes, NAME=1
opens, as specified in the [Single-Phase Breaker documentation](https://www.pscad.com/webhelp-v502-ol/Master_Library_Models/Breakers_And_Faults/Breakers/1p_break.htm). OPCUR=1 permits opening at nonzero DC current; ENAB=0 disables insertion
resistors. RON=0 is allowed by that definition; ROFF=1e100 ohm represents the
open branch to numerical precision, with 1e-100 S residual conductance.

The release uses the already exercised `TimeStep` / `Compare`
primitives: `open = (TIME >= 0.2)`, at the same owner-local release constant
as the measured-DC-divisor handover. Breaker NAME is a named input without a
schematic signal pin; connectivity checks require exactly one driver. No
controller gain, setpoint, load, model delay field or final midpoint reference
changes. Physical sources have zero ramp even when permanent sources ramp.

For the existing M4–M7 acceptance inventory, the pre-charge additions affect
M5 `mmc_vdc_classic` and `mmc_vdc_builder`, and M7 `p2p_classic` /
`p2p_builder` (including the all-OHL builder XML fixture). M4's Vdc TLC still has
an ideal DC source in its DC island and gains no pre-charge. Other M4–M6 cases,
M7 IEEE9 and IEEE39 remain unchanged by pre-charge. In L2 it affects L2-05 and
L2-11 only. The detailed bus/source/breaker inventory is retained under
`test/manual/pscad/validation/data/m9c2/export-change-list.tsv`. Only L2-11 is
re-prepared in this queue; retained L2-05 evidence is not overwritten. Existing
native acceptance does not qualify the changed Vdc/P2P exports until re-run.

### Pre-charged DC voltage taps and native coordinate checks

The kept `local/pscad-exchange/diag/nt1-mvdc/mmc_vdc_classic-report/` build
shows `V_DC_P` (component 298012955) at (1026,3150) after loading, versus
(1026,3168) in the source. Its wire still ends at (1026,3168); the loaded
meter terminal is unlabelled and reported as `NT_1`. The pre-load plan checker
could not observe that relocation. Its trigger inside native loading is not
established by these files.

On pre-charged DC islands, bus voltage outputs now use `master:nodelabel`
with `MeasV=1`, `PU=0` and the original probe name as `VName`, on an existing
conducting branch stub. No separate voltage-meter branch is placed. The saved
master at `local/pscad-exchange/m7-master.pslx:246190–246203` emits
`EMTDC_VVDC` for `$VDC:A:0`; `voltmetergnd` at 359606–359608 emits the same
function for `$VDC:N1:0`. Pole voltage, ground reference, units, probe names,
measurement stage and final circuit are preserved. The pre-charge qualification
rule, sources, breaker release and controller parameters are unchanged.

`check_connectivity(path)` checks the actual serialized or native-saved
coordinates through the same canvas guard. Export now checks both the plan
and its written XML. A portable fragment of the kept dangling terminal is
retained in `test/pscad/fixtures/nt1_loaded_fragment.pscx`; native build
acceptance of the corrected project remains a separate station check.

Every schematic canvas, including `Main` and line definitions, is written with
sheet `size = 5`. Native load experiments showed that size 0 can clamp objects
before PSCAD grows the sheet, leaving their wires at the original coordinates.
The offline plan and XML guards require instance origins and absolute wire
vertices to lie in `[0, 14382]` on both axes; the XML guard also requires size 5.
The remote runner records schematic object origins before loading and compares
them immediately after saving the applied settings. Any movement fails the
`load geometry` phase, reports up to 20 objects, and retains the full list in
`outputs/load-relocations.txt` before simulation starts.
