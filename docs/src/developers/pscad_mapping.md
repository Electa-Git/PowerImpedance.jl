# PSCAD mapping and station notes

This page records how PowerImpedance drives PSCAD, the facts measured on the reference station,
and the outcome of every risk experiment of the PSCAD integration. Update it whenever an
experiment closes or a station fact changes.

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
Other phase counts, including two-conductor DC lines, are not implemented yet.

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
`YMaxP=AMaxP=20`, `YMaxE=AMaxE=0.2 %`, `MaxRPtol=2e6`, `CPASS=0`, `DCenab=0`,
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
| R6, R10-R12, R14, R15, R17, R18 | | Open; resolved at their milestones. |

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
| Primary bus base | `V1 = sqrt(3) * base_kV` | kV LL RMS, independent of solved bus magnitude |
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
selection applies to DC cables and will apply to DC overhead lines when their
emitter is supported. AC lines retain `FS=0.5 Hz`; other validation defaults
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
HP/IP/LP torques sum to `Tm`. `Tm0 = setpoint.Pac/S_base` matches Julia's
input conversion; flow and turbine pole initial outputs equal `Tm0`.
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

The Julia state-space equilibrium at solved public-bus voltage with
`Tm0=0.9` gives terminal P=898.789379 MW, Q=-2.549114 MVAr,
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
`Ra*I^2` before the terminal. This convention remains unchanged. Builder
acceptance remains a station check; local XML checks establish structure.

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
them before planning the block parameters. `Tm0` remains the already computed
`Pac/S_base`. Every block parameter is a literal number or plain form name;
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
