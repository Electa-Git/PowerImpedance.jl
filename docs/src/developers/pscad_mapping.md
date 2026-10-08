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
