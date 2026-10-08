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

Every acquired application is silenced (`app.silence = true`) before any settings, load, build or
run call. An unsilenced instance blocks automation on any modal dialog; for example, loading the
staged `generated.pscx` raises "project namespace ... modified to 'generated'".

Ownership is explicit. `owner.txt` records the runner process and `pscad-owner.txt` a PSCAD
started by the supervisor (PID, executable, port, creation time). `lifecycle.ps1` is the single
implementation of stopping the runner, EMTDC executables under the case directory, and an owned
PSCAD. The supervisor's timeout path and caller-side cancellation (Ctrl-C) both use it.

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
| R6, R9-R12, R14, R15, R17, R18 | | Open; resolved at their milestones. |

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
| Unsolved `dc_source` `Setpoint.Vdc` | each `source_1.Vm` | kV pole-to-ground, following power flow |
| P source | positive `NA` to P bus through ammeter, negative `NB` to ground | station-measured polarity |
| N source | positive `NA` to midpoint ground, negative `NB` to N bus | gives negative N voltage |
| Source options | `AC=0`, `Type=6`, `Cntrl=0`, `Grnd=0`, `Tc=source_ramp` | ideal internally controlled DC, ramp in seconds |
| Series differential impedance `Z` | `Z/2` in P path and `Z/2` in N path | halve R and L; double C |
| Shunt differential impedance `Z` | `Z/2` from each pole to ground | same element scaling for series or parallel RLC forms |
| `dc_reference=:midpoint_resistors` | two `DC_REFERENCE_RESISTANCE=1e7 ohm` resistors per bus without a local source midpoint or grounded DC shunt | small grounding conductance; local rule applies even when another bus has a source |
| `dc_reference=:none` | no additional resistors | preserves a floating midpoint where present |
| Bus probes | two scalar `voltmetergnd` + PGB channels `V_<bus>_P`, `V_<bus>_N` | kV |
| Terminal probes | one series ammeter on the P path per nongrounded terminal | scalar kA, `I_<element>_<side>` |

**Voltage convention:** the existing DC source power-flow conversion uses
`gendc.vgdc = Setpoint.Vdc/V_base`, so its `Vdc` is pole-to-ground. Converter
setpoints use pole-to-pole `Vdc`. The exporter follows these existing semantics;
this ambiguity is documented and no source or converter physics is changed.
Thus `dc_source(Setpoint(Vdc=320))` produces +320/-320 kV, or 640 kV pole-to-pole,
without a solved record. With a record the solved bus voltage takes precedence.

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
