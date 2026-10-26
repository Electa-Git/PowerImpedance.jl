# PSCAD component mapping

The [abbreviations](../pscad.md#Abbreviations) are defined in the export guide.

The exporter translates solved networks into PSCAD 5 projects. The tables describe
component fields, electrical conventions and generated control equations. The
manual suite in `test/manual/pscad/validation/README.md` describes frequency-response
and time-domain measurements. XML checks verify the written project. A native
build and measured response test its execution in PSCAD.

## Component mapping

| Julia element | PSCAD components | Supported form |
|---|---|---|
| AC source | `source_3` | Three-phase ideal source at the solved voltage and angle |
| DC source | Two `source_1` instances | Symmetric positive and negative poles |
| AC scan | `Z_tool:ACscan` on Main | Three-phase `A1=(-54,0)` to bus. `A2=(54,0)` to element, or open. |
| DC scan | `Z_tool:DCscan` on Main | `A1=(-36,0)` and `A2=(36,0)` on P. `B1=(0,36)` to bus N. |
| Lumped impedance | `resistor`, `inductor`, `capacitor` | Supported series or parallel RLC realizations |
| AC overhead line | TLine `RowDefn` and direct wrapper | Conductor count 3 after ground-wire elimination |
| DC overhead line | TLine row, remote wrapper and `tline_interface` pair | Two conductors, P then N |
| Cable | Cable `RowDefn`, `Cable_Coax`, remote wrapper and `cable_interface` pair | Coaxial AC/DC cable with eliminated internal conductors |
| Transformer | `xfmr-3p2w` and explicit T-model passives | YY or Dyn11 |
| Synchronous machine | `sync_machine`, external R/L, AVR and governor modules | Native equivalent circuit and steam turbine |
| Induction machine | `wound_rotor` and load torque module | Native equivalent circuit and speed-dependent load torque |
| TLC | Controlled phase-voltage sources and DC-current source | Averaged grid-following converter |
| MMC | Averaged arm sources (6), capacitors, R/L and control modules | Grid-following or grid-forming converter |

### Overhead-line fields

Three-phase AC `Overhead_line` elements export as one TLine `RowDefn` and one
direct-connection wrapper on Main. The row contains `Line_Tower_Universal`,
`Line_Ground`, `Line_FrePhase_Options` and `Line_Out_Disp`. Series ammeters at both ends join the sending and receiving vertices to 36-pixel stubs and bus node labels.
Two-conductor DC lines use the remote scalar interfaces described below.
Other phase counts are not implemented yet.

| Julia field | PSCAD field | PSCAD unit / convention |
|---|---|---|
| `conductors.organization` / `positions` | `XC1..3`, `YC1..3` | m, tower bundle centres in native physical order |
| `conductors.nᵇ` | tower `Nc`, wrapper `Dim` | 3 phases after ground-wire elimination |
| `transposition` | `Transp` | `transposition = :ideal` maps to `Transp = 1`. The default `:none` maps to `0`. EMTDC exits abnormally at termination with `Transp = 1` in the PSCAD 5.1 validation measurement projects, despite complete physical outputs. |
| `conductors.rᶜ` | `RadiusC` | m |
| `conductors.Rᵈᶜ` | `DCResC` | ohm/km per subconductor |
| `conductors.μᵣᶜ` | `PERMC` | relative permeability |
| `conductors.dˢᵃᵍ` | `SAGC` | m, pass tower height without subtracting sag |
| `conductors.nˢᵇ` | `NCondB` | subconductors per phase bundle |
| `conductors.dˢᵇ` | `BSP` | m, adjacent spacing in a regular polygon, `BundSym=0` |
| `conductors.gᶜ` | `ShuntG` | mho/m (S/m) |
| `groundwires.nᵍ` | `NG` | 0–2. `ElimGW=1` reproduces Julia's Kron elimination |
| `groundwires.Δxᵍ` | `XG1..2` | m. `Δxᵍ * i`, `i = -(nᵍ-1)/2:(nᵍ-1)/2` |
| `conductors.yᵇᶜ + groundwires.Δyᵍ` | `YG1..2` | m, tower height before sag correction |
| `groundwires.rᵍ` | `RadiusG` | m |
| `groundwires.Rᵍᵈᶜ` | `DCResG` | ohm/km per ground wire |
| `groundwires.μᵣᵍ` | `PERMG` | relative permeability |
| `groundwires.dᵍˢᵃᵍ` | `SAGG` | m |
| `earth_parameters = (μᵣ, ϵᵣ, ρ)` | `GPERM`, `GRP`, `GRRES` | relative permeability, relative permittivity, ohm*m |
| `length / 1e3` | wrapper `Length` | km |
| `settings.frequency` | wrapper `Freq`, display `DataF` | Hz |
| Native solid conductors | `Hollow=0`, `CDataType=1`, `GDataType=1` | direct material data |
| Three-phase single-line wiring | wrapper `Mode=1`, `Dim=3` | first vertex sends, last receives |

Julia and PSCAD both subtract two thirds of conductor sag during evaluation.
Export tower heights before sag correction. Ground-wire coordinates use the
native offset rule. Explicit phase positions retain their physical order.

The ground defaults are `EarthForm2=0`, `EarthForm=2`, `EarthForm3=2`,
`GrRho=0`. Frequency-dependent phase defaults are `Interp1=1`, `Output=0`,
`Inflen=0`, `FE=1e6 Hz`, `Numf=100`, `YMaxP=AMaxP=20`,
`YMaxE=AMaxE=0.02 %`, `MaxRPtol=2e6`, `CPASS=0`, `DCenab=0`, `DCCOR=1`,
`enablf=1`. AC uses `FS=0.5 Hz`. A line whose terminal buses are all DC uses
`FS=0.001 Hz`. `Freq=0 Hz` on DC wrappers. The fitting loss frequency remains
the network frequency. Display `DataF` is 50 Hz.

`line_options` applies PSCAD field overrides to every line and cable. Ground
keys are `EarthForm2`, `EarthForm`, `EarthForm3`, `GrRho`, `GRRES`, `GPERM`,
`GRP`. Fitting keys are `Interp1`, `Output`, `Inflen`, `FS`, `FE`, `Numf`,
`YMaxP`, `YMaxE`, `AMaxP`, `AMaxE`, `MaxRPtol`, `W1`, `W2`, `W3`, `ET_PE`,
`NFP`, `FSP`, `MER_PE`, `MIT_PE`, `FEP`, `FDIS`, `CPASS`, `DCenab`, `DCCOR`,
`shntcab`, `enablf`. Numeric values acquire PSCAD units. Strings retain explicit
units. Unknown keys raise `ArgumentError` before solving or writing.

AC row components are `Line_Tower_Universal`, `Line_Ground`,
`Line_FrePhase_Options` and `Line_Out_Disp`. Series array ammeters at both ends connect
the direct wrapper to bus labels through 36-pixel stubs.

DC wrappers use `Mode=0`, `Dim=2`, matching `Name`, `NC=2`, `View=0`,
`send_recv=0`, `dim_s=dim_r=0` on both `tline_interface` instances. Sending
orientation is 0. Receiving orientation is 4. Scalar A/C ports are
`(-18,-18)` and `(-18,18)` at orientation 0. Orientation 4 mirrors x.
Conductor order is P then N. P contains a series ammeter. N uses a direct stub.
The wrapper vertices describe graphics. Electrical pins are on the interfaces.
`test/pscad/fixtures/dc_ohl_interface.xml` retains the master-library fields
and ports used by this mapping.

### Z-tool scan fields

| Julia input | PSCAD field | Convention |
|---|---|---|
| `ZToolProbe.name` | `Name` | Unique ASCII name for the PSCAD instance |
| `settings.frequency` | `f0` | Hz, for AC and DC |
| Solved AC `vm_pu * base_kV * sqrt(2)`, or `voltage` | `V0_peak` | Peak line-to-ground kV |
| Solved DC `2 * vm_pu * base_kV`, or `voltage` | `V0_peak` | Pole-to-pole kV relative to `B1` |
| `perturbation` | `V_perturb_mag` | pu. Default 0.01. |
| `vac_control`, `f_control` | `Vac_control`, `f_control` | AC Boolean flags become 0 or 1 |
| `vdc_control` | `Vdc_control` | DC Boolean flag becomes 0 or 1 |
| Library idle settings | `T_inj`, `Tdecoupling` | 1e8 s |
| Library scan settings | `selector`, `single_frequency`, `block_id` | 0, 1, 0 |

The [scan guide](../pscad.md#Z-tool-scan-probes) describes placement and the
library workspace. `ZToolProbe(...; element, port)` selects series placement
by component and port name, such as `port = :ac` or `port = :side1`. It changes
only the selected terminal label.
The existing ammeter and its channel orientation remain in the through-path.

### Z-tool sweep inputs

`ZToolScan` adds a `ztool` table to `computation.toml`.
It records `ztoolacdc` version 0.1.52 and the sweep arguments.
Ordinary `PSCADRun` requests have no `ztool` table.

| Julia input | Z-tool argument | Unit or rule |
|---|---|---|
| `frequencies` | `freq` | Positive increasing values in Hz |
| `f_min`, `f_max`, `f_points`, `f_base` | Same names | `create_freq.loglist` rounds and fills the list |
| `snapshot_time` | `t_snap` | s, before decoupling |
| `start_fft` | Same name | s, settling before the FFT |
| `fft_periods` | Same name | Window length is `fft_periods/f_base` s |
| `injection_interval` | `dt_injections` | s, delay after decoupling |
| `perturbation` | `v_perturb_mag` | pu of the block's nominal voltage |
| `multi_frequency` | `multi_freq_scan` | Boolean flag for up to eight tones together |
| `time_step` | `t_step` | Seconds become microseconds |
| `sample_step` | Same name | Seconds become microseconds |
| `num_parallel_sim` | Same name | Positive volley count, default 1 |
| `topology` | Same name | Path to the staged copy of the local file |
| Detected GFortran version | `fortran_ext` | 8.1 gives `.gf81`, and 4.6 gives `.gf46` |
| Staged run directory | `working_dir` | Contains the project and build folder |
| Run result directory | `results_folder` | Runner copies the result files into `outputs` |

The topology header lists `Name-1 Name-2` for each block.
A symmetric binary matrix follows, with one row and column per named side.
A diagonal one selects a component at that side. Off-diagonal ones connect
sides for a combined scan. The library ports `A1` and `A2` correspond to
sides 1 and 2 in topology headers and result filenames.

The runner replaces the `connect` attribute in `ztoolacdc.frequency_sweep`
with a callable that returns its own application. It restores the attribute
in a `finally` block. It passes `launch_and_load_PSCAD=False`,
`close_PSCAD=False`, `release_certificates=False` and
`delete_PSCAD_output_files=False`. It also passes `run_sim=True` and disables
every plotting or display flag.

`outputs/ztool.toml` records the installed version, arguments and result filenames.
The completion record hashes these files, including the angle and power-flow
files. Each admittance file stores its matrix entries in row order.
The reader assigns them to `admittance[row, column, frequency_index]` in S.
Rows and columns follow the header axes, including mixed AC/DC files.

### Cable fields

Coaxial `Cable` elements require `eliminate=true`. A row contains one
`master:Cable_Coax` per physical position plus the shared ground, fitting and
display components. Exposed sheath and armour interfaces raise an element-named
`ArgumentError`. Radii and resistivities use explicit `[m]` and `[ohm*m]`.
Layer pairs are ordered `C1/I1` through `C4/I4`. Dielectric loss tangents are
zero because the Julia model has no dielectric-loss input.


| Julia quantity / choice | PSCAD field | Convention |
|---|---|---|
| Position index | `CABNUM` | 1-based physical position order |
| Component identifier | `Name` | same sanitized name as wrapper and both interfaces |
| `positions[k][1]` | `X` | m |
| `type=:underground`, positive depth | `OHC=0`, `Y=positions[k][2]`, `Y2=0` | m, Julia uses positive underground depth, unlike the donor's signed vertical coordinates |
| `type=:aerial`, positive height | `OHC=1`, `Y=0`, `Y2=positions[k][2]` | m |
| `C1.rᵢ`, `C1.rₒ`, `I1.rₒ` | `R1`, `R2`, `R3` | m |
| `C2.rₒ`, `I2.rₒ` | `R4`, `R5` | m, donor triplet `(R4,R4,R5)` |
| `C3.rₒ`, `I3.rₒ` | `R6`, `R7` | m, donor triplet `(R6,R6,R7)` |
| `C4.rₒ`, `I4.rₒ` | `R8`, `R9` | m, donor triplet `(R8,R8,R9)` |
| `C1..4.ρ` | `RHOC`, `RHOS`, `RHOA`, `RHOO` | ohm*m |
| `C1..4.μᵣ` | `PERMC`, `PERMS`, `PERMA`, `PERMO` | relative permeability |
| `I1..4.ϵᵣ`, `I1..4.μᵣ` | `EPS1..4`, `PERM1..4` | relative permittivity and permeability |
| Ordered conductor keys | `CONNAM1..4` | `C1` through `C4`. Absent pairs named `none` with zero material and radius values |
| Lossless dielectrics | `LT1..4=0`, `FLT=settings.frequency` | loss frequency in Hz |
| `eliminate=true` | `elim1..3=1` for present C2..4, otherwise 0 | core retained, grounded internal conductors eliminated |
| Number of conducting and insulating pairs | `LL=2*n_layers-1`, `RorT=0`, `SHRad=1` | last-layer index, radii entry |
| Frequency-dependent phase model | `LC=2`, `CROSSBOND=0` | follows the plan and validation project. Donor uses `LC=3` |
| Already converted effective Julia insulation | `SemiCL=0`, `SL1=SL2=0` | no second semiconducting-screen correction |
| Negligible aerial shunt | `ShuntA=1e-38` | mho/m, as in donor |
| `earth_parameters=(μᵣ,ϵᵣ,ρ)` | `GPERM`, `GRP`, `GRRES` | relative properties and ohm*m |


The remote wrapper uses `Dim=0`, `Mode=0`, `CoupleEnab=0`, `CoupleName=row`,
`CoupleOffset=0 m`, `CoupleRef=0`, `gen_cnst=1`, `const_path=""`, `Date=0`,
empty `R/X/B`, `tname=tandem_segment`, `sfault=0`, `linc=10 km`, `steps=3`.
`Length` is km. Graphical vertices relative to its origin are `(0,0)`,
`(-36,0)`, `(-54,-54)`, `(-54,-72)`. They have no electrical wires.
Row cable instances are 396 pixels apart on the 18-pixel grid.

Both `cable_interface` instances share the wrapper name, set `NCAB` to the
position count and use `C1T..C12T=1`. Other fields are
`pipe=dim_s=dim_r=0`, `GroundS=GroundA=GroundOC=0`,
`ResS=ResA=ResOC=0.001 ohm`, `send_recv=recv_default_type=recv_default=0`.
Sending orientation is 0 with ports `(-18,54*(k-1))`. Receiving orientation 4
mirrors x. DC position 1 connects P, position 2 connects N. AC positions follow
A/B/C order through a `breakout`. Its ports are common `(0,0)` and phases
`(36,-36)`, `(36,0)`, `(36,36)`.

### Transformer fields

Three-phase transformers use explicit per-phase, Y-equivalent T-model passives.
`n` is the primary-to-secondary line-to-line voltage ratio. Dyn11 secondary
positive-sequence voltage leads the primary by 30 degrees.


| Julia quantity / choice | PSCAD realization | Unit / convention |
|---|---|---|
| Solved primary bus magnitude | `V1 = sqrt(3) * vm_pu * base_kV` | kV LL RMS. Unsolved linear plans retain the declared base |
| `n` | `V2 = V1/n` | kV LL RMS |
| `:YY` | `YD1=YD2=0`, `Ideal=0` | near-ideal master winding |
| `:ΔY` (Dyn11) | `YD1=1`, `YD2=0`, `Lead=1`, `Ideal=1` | secondary leads +30 degrees |
| `Rₚ`, `Lₚ` | series `resistor`, `inductor` before primary winding | ohm, H, per-phase Y-equivalent |
| `Rₛ`, `Lₛ` | series `resistor`, `inductor` after secondary winding | ohm, H, same values for YY and ΔY |
| `Lₘ`, `Rₘ` | separate shunts from inner primary node to ground | H, ohm, omit zero or infinite values |
| `Cₜ` | shunt at each external transformer terminal | uF = F * 1e6 |
| `Cₛ` | bridge between external transformer terminals | uF = F * 1e6 |
| Network frequency | `f` | Hz |
| Master base / options | `Tmva=1000 MVA`, `NLL=CuL=0 pu`, `Tap=0`, `View=1`, `Dtls=0`, `Enab=0` | no internal losses, tap or saturation |

Terminal ammeters precede all shunt and bridge paths, including their currents.
YY uses `Xl=1e-4 pu`, `Im1=1e-3 %`, zero no-load and copper loss. Ideal YY
windings have floating star nodes and can produce a zero diagonal. Dyn11 uses
`Ideal=1`. Frequency-dependent winding resistance and other organizations
are rejected. Winding ratings follow solved primary voltage. Using a common
network base can produce a zero diagonal in networks with several voltage levels.

The validation phase reference imposes floating-neutral winding KCL using
`Q=I-11'/3`, retaining external `Cₜ` ground paths and bridging `Cₛ` paths.
Positive/negative sequence winding response is unchanged when the near-ideal
terms are excluded. Use a floating-neutral YY phase model to represent the emitted windings.

### DC circuits

A `DC_CM` bus represents differential voltage `V_P - V_N` and pole current.
Export expands it into `<bus>_P` and `<bus>_N`. Source input `v` and converter
`values.dc.v` use pole-to-pole kV. Solved `vm_pu * base_kV` is already a
pole-to-ground magnitude. It takes precedence over a declared source input.

| Julia quantity / choice | PSCAD realization | Unit / convention |
|---|---|---|
| Solved `busdc.vm * base_kV` | each `source_1.Vm` | kV pole-to-ground magnitude |
| Unsolved `dc_source` input `v / 2` | each `source_1.Vm` | kV pole-to-ground magnitude from the pole-to-pole input |
| P source | positive `NA` to P bus through ammeter, negative `NB` to ground | station-measured polarity |
| N source | positive `NA` to midpoint ground, negative `NB` to N bus | gives negative N voltage |
| Source options | `AC=0`, `Type=6`, `Cntrl=0`, `Grnd=0`, `Tc=source_ramp` | ideal internally controlled DC, ramp in seconds |
| Series differential impedance `Z` | `Z/2` in P path and `Z/2` in N path | halve R and L. Double C |
| Shunt differential impedance `Z` | `Z/2` from each pole to ground | same element scaling for series or parallel RLC forms |
| `dc_reference=:midpoint_resistors` | two `DC_REFERENCE_RESISTANCE=1e7 ohm` resistors per bus without a local source midpoint or grounded DC shunt | small grounding conductance. Local rule applies even when another bus has a source |
| `dc_reference=:none` | no additional resistors | preserves a floating midpoint where present |
| Bus probes | two scalar `voltmetergnd` + PGB channels `V_<bus>_P`, `V_<bus>_N` | kV |
| Terminal probes | one series ammeter on the P path per nongrounded terminal | scalar kA, `I_<element>_<port>` |


For `dc_source(v = 640)`, pole sources use +320/-320 kV before a solved
voltage is supplied. Public export always obtains or receives a solved result.
A differential impedance `Z` becomes `Z/2` in each pole: halve R and L,
double C. This applies to series and grounded shunt RLC forms. A 2 ohm
branch between 320 and 318 kV poles carries 2 kA and loses 8 MW in total.

Grounded differential DC shunts require care in power flow: conversion can create
an ordinary `busdc` for `:gnd` and solve it at nonzero voltage. Validation
fixtures explicitly eliminate a zero-voltage reference into ground. Check the solved shunt voltage when comparing power flow with the emitted
circuit.

## Signs, bases and reference frames

`ProbeChannel.orientation` is `:into` for every exported port-current channel.
Non-current channels use `nothing`. Channel names are `I_<element>_<port>`. Bus
voltage channel names remain `V_<bus>`.

| Component | Port | Positive current direction |
|:--|:--|:--|
| AC/DC impedance, overhead line, cable, YY/Dyn11 | `side1`, `side2` | Inward at each end. |
| Grounded impedance | Nongrounded port | Inward. |
| AC source, synchronous machine, induction machine | `ac` | From the bus into the component. |
| DC source | `dc` | Inward at the positive pole. |
| TLC/MMC | `ac`, `dc` | Inward at both ports. |

Port powers in `ACPortValues` and `DCPortValues` use the same inward sign.
A source delivering 900 MW has `ac.p = -900`. A converter receiving 603 MW
from DC and delivering 600 MW to AC has `dc.p = 603` and `ac.p = -600`.
Y comparisons use the recorded inward current directly. A shunt source's
injection into a network is the negative of its inward current. Read older
recordings with their saved orientation metadata. Current magnitudes alone
cannot detect reversed polarity. The parity tests map frozen probe names and
reverse meter terminals where the former orientation differs.

AC source `Ph = rad2deg(va) + 90` converts Julia's cosine angle to PSCAD's
sine reference. The dq convention is `d=cos(theta)`, `q=-sin(theta)`.
Balanced input at 0.37 rad measured `0.932` and `-0.362` in PSCAD.
The measured q sign agrees with Julia. Rotate both voltage and current when
changing a port frame. A matrix frame change acts on rows and columns.

AC DFT peak phasors use kV/kA, so `sum(V_k*conj(I_k))/2` gives three-phase
MW/MVAr. SI admittance and impedance use the peak-to-power conversion directly. Converter AC bases are phase peak. MMC uses `vAC_base`,
`2*Sbase/(3*vAC_base)` and pole-to-pole `vDC_base`. Its physical transformer
already converts the measured voltage and current to the converter side.
Synchronous-machine terminal Y is converted from pu by `Sbase/VLL^2`.

## Modules, canvases and layout

Main and each module connect ports through named nodes. Each connecting wire is
a straight segment with two vertices. It joins one known port to a label or ground.
Ports cannot coincide. Stubs cannot share endpoints or pass through another
port or label. Every electrical port, signal input and label requires a stub.
Signal names are case-insensitive and require one same-canvas writer. Imports
and module outputs write signals. Exports, recorders and module inputs read
them. Meter names and machine `POut`/`QOut` also write signals.

Electrical module ports require a wire from their `xnode` anchors to an internal
node label, including when both names match. Empty series paths identify electrical labels without adding
a component. Line rows contain geometry and material records without circuit pins.

Generated names reject PSCAD intrinsic identifiers case-insensitively. Name
reservations include network, module and probe identifiers. Saved transform
fragments retain parameters, orientations and pin-net partitions while their
coordinates and wires are relocated.

Orient-0 pin offsets below are pixels relative to the component anchor. The
saved mirrored or rotated transform instances retain their original orientation.

| Component | Orient-0 ports | Saved reference under `local/` |
|---|---|---|
| R, L, C, ammeter | electrical `(0,0)`, `(36,0)` | `TLC/Simple_2L_VSC_RL.pscx:939–950`. `OHL/DUT_2.pscx:1767–1779`. `TLC/Simple_2L_VSC_RL.pscx:4317–4337` (ammeter and incident wires) |
| `source_1` | positive `(-36,0)`, negative `(36,0)` when ungrounded. External control `(0,36)` | `TLC/Simple_2L_VSC_RL.pscx:3452–3529`, orientation 4 with a grounded negative pole. Source polarity check |
| `source_3` | electrical `(36,0)` with `Grnd=1` | `OHL/DUT_2.pscx:1594–1688`, orientation 3 |
| `src_ccin_1` | electrical `(0,0)`, `(36,0)`. Control `(0,36)` | `TLC/Simple_2L_VSC_RL.pscx:5589–5613`, orientation 1 |
| breakout | common `(0,0)`, phases `(36,-36)`, `(36,0)`, `(36,36)` | `TLC/Simple_2L_VSC_RL.pscx:3383–3529`, orientation 4. `Cable/DUT_2.pscx:13590` |
| voltmeter, ground-referenced voltmeter | `(0,0)` and `(0,36)`. Ground-referenced version only `(0,0)` | `TLC/Simple_2L_VSC_RL.pscx:5618–5630`. `SG/SG_Project.pscx:2425–2435` |
| `xnode` | electrical `(0,0)` | `TLC/Simple_2L_VSC_RL.pscx:3377–3382,5604–5613` and the incident wires |
| transformer | electrical `(-54,0)`, `(36,0)` | `OHL/DUT_2.pscx:1689–1766` |
| cable interface | `(-18,54*(i-1))`, in cable order | `Cable/DUT_2.pscx:1644–1703`, orientations 0 and 4 |
| synchronous machine | electrical `(36,0)`. Ef `(-36,-72)`, Tm `(0,72)`, speed `(-36,72)`, Vt `(36,-72)`, Ef0 `(-72,-72)`, Tm_init `(36,72)` | `SG/SG_Project.pscx:998–1198`, orientation 4. Shared control translation |
| induction machine | stator `(54,0)`, speed input `(-54,-36)`, speed selector `(-54,0)`, torque input `(-54,36)` | PSCAD 5.1.0 `wound_rotor` definition, single-line view |
| import and export, constants, time signal | `(36,0)` | `TLC/Simple_2L_VSC_RL.pscx:2084–2106,5923–5929`. `P2P HVDC/PowerModelsACDC_ACdroop.pscx:13112–13118` (`const`) |
| unary control blocks | input `(-36,0)`, output `(36,0)` | control primitives below. `SG/SG_Project.pscx:1865–1944,1959–1976,2010–2024` (pole, gain, lead-lag) |
| multiplication, division, dot product | left `(-36,0)`, lower `(0,36)`, output `(36,0)` | saved abc/dq canvases, `TLC/Simple_2L_VSC_RL.pscx:1851–3234` |
| sum junction | enabled D `(-36,0)`, F `(0,36)`, B `(0,-36)`. Output `(36,0)` | same saved abc/dq canvases. `SG/SG_Project.pscx:1945–1958` (three-input sum) |

| merge, tap | saved orientation-4 merge inputs `(-18,18*(i-5))`, output `(0,18*(N-3))`. Orientation-0 tap input `(0,-18)`, output `(0,0)` | `TLC/Simple_2L_VSC_RL.pscx:2164–2185,2214–2235,4498–4517` |
| pgb | signal `(0,0)` | `TLC/Simple_2L_VSC_RL.pscx:1009` and incident wire. Passive and machine output stubs |


Every canvas, including Main and line definitions, uses sheet `size=5`.
Instance origins and absolute wire vertices must lie in `[0,14382]` on both
axes. Native loading can clamp size-0 objects before growing the sheet and
leave wires at their original positions. Explicit module schematic settings
also retain `orient=1` and `auto_sequence=1`.

`BlockGraph` lowers in stored order, four rows per column, with columns six
grid units apart and rows four apart. Signal stubs are 36 pixels. Two/three-input
sums use D/F/B and disable unused inputs. Set `definition.module=true` before
adding blocks with mhi-xml 1.3.0.

Module input forms require `intent="Input"`, `dim="1"`, finite bounds,
`helpmode="Append"`, and `cond`, `help`, `vis` children. The writer uses
`add_real`/`add_integer`/`add_text`. `Parameter.help_mode` writes the correct
attribute. Real bounds are ±1e308, integer bounds signed 32-bit, text bounds
0/0. The XML node supplies `dim` because the creation API has no dimension
option. Module symbols use `svg viewBox="-200 -200 200 200" size="4"`.
Electrical ports use `model="Natural"`, `mode="Electrical"`,
`type="NonRemovable"`. Signal ports use `model="Transfer"`, input or output mode,
and their signal type. Ports contain `true` character data (CDATA) and `internal="false"`.

Declare one schematic import for each input parameter using `master:import`,
including parameters used only as block coefficients. Coefficient-only imports
may be unwired.
Connected references such as AVR `vref` and governor `Tm0` use the import output.
`Const` accepts numeric literals. Block parameters accept literals or plain
form names. Compute products, ratios and initial values in Julia.
Electrical component parameters inside modules must be finite SI literals.

Probed shunts use `bus -> element -> meter -> ground`. Parallel shunts share
a return meter. Consecutive ideal meters on an isolated floating YY
secondary can cause a native zero diagonal. Moving the load meter to its ground
return reproduced the reference load current `0.215 kA` without changing
passive parameters. The structural check follows galvanic islands through module
ports and paired interfaces, excluding voltage probes as conducting paths.

`test/pscad/topology.jl` compares serialized electrical graphs with independent
reference graphs. It retains ordered pins, component, material and fitting parameters
and module connections, while ignoring coordinates, IDs and internal label
spelling. Isomorphic cable interfaces are matched. Nets require two attached
ports unless grounded or carrying a voltage probe. Only listed shunt-meter
moves are accepted. Unlisted moves and meter reversals fail.

## Synchronous-machine realization

The machine uses `sm_equivalent_circuit`. Reactances use per unit.
The external branch is `R=rt*Zbase`, `L=lt*Zbase/ωn`,
`Zbase=Vᵃᶜ_base^2/S_base`. The branch represents impedance on the same voltage base.
Machine `VT`/`Pheta` refer to the terminal before rt/lt, with angle plus π/2.
`P0`/`Q0` come from solved generator power. External current corresponds to
the receiving end of the internal branch.

| Machine fields | Meaning |
|---|---|
| `Rs1`, `XS1`, `XMD0`, `R2D`, `X2D`, `R3D`, `X3D`, `X230`, `XMQ`, `R2Q`, `X2Q`, `R3Q`, `X3Q`, `X231` | Native equivalent-circuit parameters |
| `Name`, `Cnfg`, `Nqaxw`, `IorMVA`, `MVA`, `VolTyp`, `VbaseLL` | Identity, configuration and LL RMS base |
| `View`, `Neut`, `MM`, `MSat`, `icTyp`, `OMO`, `H`, `D` | Single-line view, neutral, saturation and mechanical settings |
| `Ri=1e6 pu` | Approximately 0.001 MW iron loss at 1 pu on 1000 MVA. Julia has no iron-loss branch |
| `VT`, `Pheta`, `P0`, `Q0`, `Trmpv`, `Sysfl`, `Ptcon` | Initialization and transfer settings |
| `machsw`, `Enab`, `Igov`, `Iexc`, `Ospd`, `Term=1`, `Ts=0 s` | Scalar terminal voltage and external control interface |
| `InGov`, `InExc`, `PQscl`, `POut`, `QOut` | Control inputs and power outputs in pu on the machine base |
| `Icsp=Icmp=0` | Preserve solved source phase without automatic power correction |

The AVR applies `1/(1+s*T_R)`, `vref-v_f`,
`(1+s*T_C)/(1+s*T_B)`, `K_A/(1+s*T_A)` and field-voltage conversion.
`Ts=0` avoids adding a second measurement pole. The governor applies
`1-speed`, `1/(1+s*T_w)`, `1/R`, `+Tm0`, `1/(1+s*T_G)` and the cascaded
chest, reheater and crossover poles. Weighted high-pressure, intermediate-pressure and low-pressure turbine torques sum to `Tm`.
There are no controller limits because the Julia controllers have none.

The machine core computes its equilibrium from the solved generator
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

Only the armature loss is added to terminal power. The external `rt` loss is
already between the generator terminal and the public bus. The turbine
fractions are assumed to sum to one. Solved `values.ac.p` and `values.ac.q`
contain inward terminal powers. Generation in the equations above uses their
negatives. `values.ac.v` and `values.ac.theta` describe the receiving-bus voltage. The core
reconstructs terminal phasors using the high-voltage solution of that branch,
then sets initial values for rotor angle, stator and field currents, speed, governor,
turbine and AVR states from the same point. Damper currents and speed error start at
zero. The nonlinear solver's existing iteration limit and tolerances are unchanged.


These references remain fixed during linearization. With incomplete operating
values with unknown reactive power, `Tm0=-values.ac.p/S_base` and configured `AVRSM.v_ref` remain in use.
The configured field itself is unchanged by the effective reference conversion.

`SM_AVR_FIELD_VOLTAGE_SCALE=1.0`: Julia's `v_df=K_A*y*Rf_d/La_d` and
open-circuit terminal voltage `La_d*v_df/Rf_d` give PSCAD `Ef=K_A*y`.
The machine transfers from source mode at 0.5 s and to mechanical control at
1.0 s through `time-sig`/`compare` blocks (`OL=0`, `OH=1`, `INTR=0`, `conv=1`).

AVR feedback uses network terminal voltage measured before rt/lt:
`<e>_Vt_meas = sqrt((2/3)*(va^2+vb^2+vc^2))/(Vac_base,LL*sqrt(2)/sqrt(3))`.
The machine's internal `<e>_Vt` remains diagnostic: it measured about
`5e-4 pu` high from the interface between control and electrical calculations. The AVR filter starts
at solved `Vt0`. Internal P/Q outputs also contain step-dependent discrepancies.
Compare public-bus phasors and reconstructed terminal voltage.

## Induction-machine fields

The induction machine uses `master:wound_rotor` with a closed rotor circuit,
grounded stator neutral and linear magnetizing and leakage inductances.
The power base is three-phase MVA. The voltage base is line-to-line RMS kV.
The frequency base is electrical rad/s. The field values follow the PSCAD 5.1.0
component definition and the validated `IM.pscx` instance.

| Machine field | Julia value or selected setting | Effect |
|---|---|---|
| `Name` | Component name | Identification |
| `Pbase` | `bases(model).S` MVA | Rated power |
| `Vbase` | `model.Vac_base` kV | Line-to-line RMS base in single-line view |
| `OMEG` | `bases(model).omega` rad/s | Base angular frequency |
| `TRN` | `1` | Stator/rotor turns ratio retained from the reference instance |
| `J` | `2*mech.H` s | Angular inertia coefficient |
| `D` | `0` pu | Zero mechanical damping |
| `View` | `1` | Single-line display and three-phase stator terminal |
| `ERC` | `0` | Closed rotor circuit |
| `MM` | `0` | External speed selector and load torque input |
| `SNP` | `1` | Grounded stator neutral |
| `Cage` | `0` | Zero squirrel cages |
| `NCW` | `1` | Inactive because the cage count is `NCW*Cage=0` |
| `Msat`, `Lsat` | `0`, `0` | Linear magnetizing and leakage inductances |
| `R1` | `elec.r_s+elec.rt` pu | Stator series resistance |
| `R2` | `elec.r_r` pu | Wound rotor resistance |
| `R3`, `R4`, `R5` | `0.298`, `0.018`, `0.018` pu | Inactive cage resistances |
| `Xmd` | `elec.l_m` pu | Magnetizing inductance |
| `Xa` | `elec.l_sl+elec.lt` pu | Series leakage inductance of the stator |
| `Xkd1` | `elec.l_rl` pu | Leakage inductance of the wound rotor |
| `Xkd2`, `Xkd3`, `Xkd4` | `0.05` pu each | Inactive cage leakage inductances |
| `Xkd12`, `Xkd13`, `Xkd14`, `Xkd23`, `Xkd24`, `Xkd34` | `0.02` pu each | Inactive mutual cage inductances |
| `I1M`, `V1M` | `0`, `0` pu | Inactive magnetizing curve point |
| `I2M`, `V2M` | `0.5`, `0.5` pu | Inactive magnetizing curve point |
| `I3M`, `V3M` | `0.8`, `0.79` pu | Inactive magnetizing curve point |
| `I4M`, `V4M` | `1`, `0.947` pu | Inactive magnetizing curve point |
| `I5M`, `V5M` | `1.2`, `1.076` pu | Inactive magnetizing curve point |
| `I6M`, `V6M` | `1.5`, `1.2` pu | Inactive magnetizing curve point |
| `I7M`, `V7M` | `1.8`, `1.26` pu | Inactive magnetizing curve point |
| `I8M`, `V8M` | `2.2`, `1.32` pu | Inactive magnetizing curve point |
| `I9M`, `V9M` | `3.2`, `1.42` pu | Inactive magnetizing curve point |
| `I10M`, `V10M` | `4.2`, `1.5` pu | Inactive magnetizing curve point |
| `I1`, `V1` | `0`, `0` pu | Inactive leakage curve point |
| `I2`, `V2` | `1.196`, `0.286` pu | Inactive leakage curve point |
| `I3`, `V3` | `1.82`, `0.4` pu | Inactive leakage curve point |
| `I4`, `V4` | `2.861`, `0.564` pu | Inactive leakage curve point |
| `I5`, `V5` | `5.882`, `0.981` pu | Inactive leakage curve point |
| `I6`, `V6`, `I7`, `V7`, `I8`, `V8`, `I9`, `V9`, `I10`, `V10` | `-1` pu each | Inactive leakage curve points |
| `NpntsM`, `NpntsL` | `10`, `10` | Inactive curve lengths with saturation disabled |
| `MSF`, `LSF` | Empty | Unrecorded saturation factor outputs |
| `Spd` | `<e>_speed` pu | Mechanical speed output |
| `Tel` | `<e>_Te` pu | Diagnostic electrical torque output |
| `TmOp` | `<e>_Tm` pu | Diagnostic mechanical torque output |
| `ThetaR` | Empty | Unrecorded rotor position output in rad |
| `Vwdg` | `0.3983` kV | Inactive winding voltage with `View=1` |

The script sets the cage coefficients to zero and substitutes linear curves
with `Msat=Lsat=0`. It passes `TRN` to the compiled machine routine with `ERC=0`.
The effect inside that routine remains unknown. The exporter retains the
reference value `1`.

Julia uses the inverse-Γ coefficients
`l_r=l_m+l_rl`, `l_M=l_m^2/l_r`, `l_σ=l_m+l_sl+lt-l_M` and
`r_R=(l_m/l_r)^2*r_r`. The native component receives the original winding
parameters. `R2` is `r_r`, before the inverse-Γ conversion.
The stator sums include `rt` and `lt` on the same machine base.

Julia power flow uses `r_s+rt` and `l_sl+lt` for the stator series impedance.
The state equations omit `p_f`. Speed and torque have no extra pole factor.

Power flow scales `T_0`, the initial air-gap power and the power limits by the
ratio of the machine power base to the network power base.

The load module computes

```math
T_m = T_0(A\omega_r^m+B\omega_r+C),\qquad
\dot\omega_r = (T_e-T_m)/(2H).
```

| Julia field | Control blocks |
|---|---|
| `T_0` | Final gain with `G=T_0` |
| `A` | Gain with `G=A` after the integer power |
| `B` | Gain with `G=B` on speed |
| `C` | Parameter import for the constant term |
| `m` | Products, squares and a reciprocal construct `ω_r^m` |

Integer powers use products, squares and a reciprocal for negative exponents.
The module imports `T_0`, `A`, `B` and `C`. The reference feeds `0.9` pu
directly to `TMI`. Its separate base calculations end at the unused `Tau_base`.
`TmOp` names an output. `IM_custom.pscx` contains an unfinished inverse-Γ
calculation with disconnected integrators and gains.

The speed command starts at Julia's solved `ω_r`. The reference start-up uses
`time-sig` and `compare` with `X=0.2`, `OL=1`, `OH=0`, `INTR=0`, `conv=0`.
The export uses `conv=1` to supply the integer input `SW` with the same levels.
It imposes speed until 0.2 s and then applies the load torque law. The form lacks
fields for rotor-flux and winding-current initial values. Those states settle
during start-up. The load torque starts at its value at the imposed speed.

Named node and data labels connect every port through separate stubs.

The branch current points from the bus into the motor. Terminal P/Q use that
current and the bus voltage phasors, with error divided by `S_base` and tolerance
`0.01`. Mean speed uses Julia's equilibrium speed and absolute tolerance
`1e-3` pu. Electrical and mechanical torque outputs are diagnostic.

## Converter controls

TLC exports shared abc/dq transforms, MEAS, PLL, active and reactive control, OCC
and MOD inside `VSC_<element>`. Electrical ports are `AC` (dimension 3),
`DC_P`, `DC_N`. Scalar outputs are `P_ac_f`, `Q_ac_f`, `v_dc_f`, `omega_c`,
`theta_c`. MMC reuses the measurement and outer-control and current-control generators
with its Δ control objects and physical six-arm plant.

### Control primitives


| Intermediate representation / circuit operation | PSCAD mapping | Saved source |
|---|---|---|
| Integrator | `integral`: `T`, `Yo`, `YLo`, `YHi`, `Extrn=0`, `Reset=0`, `Mthd=0`. Explicit input gain for Ki | `TLC/Simple_2L_VSC_RL.pscx:3530–3545` |
| Multiplication / division | `mult` / `div`: `Dim=1`, `DPath=1`. Left input and lower input | same file, `3001–3007` / `2100–2106` |
| Sine / cosine | `trig`: `Type=1/2`, `Mode=0`, `Dim=1` | same file, `2113–2122`, `2190–2198`. Copied transform wiring |
| Square / square root | `square` / `sqrt`: `Dim=1`, `DPath=1` | same file, `1210–1217` / `1223–1230` |
| First-order filter / support lag | Existing `realpole` translation with `G`, `T`, `YO`, `Limit=0`, `Reset=2`, `Dim=1` | same file, `3798–3816`. Shared control translation |
| Second-order filter section | Paired `integral` blocks: `y'' = W2*(u-y) - D*y'`, with precomputed `W2=ωc²/b`, `D=a*ωc/b` | integral above, shared gain and sum fields. Coefficient implementation `converter/common/kernels/filter.jl` |
| Exact delay | `tdelay`: `T`, `N=ceil(T/time_step)+1`, `Intp=0`, `Dim=1`, `Init=1`, `X0` | same file, `5037–5050`. Initialized history |
| Ordered scalar merge | `datamerge`, orientation 4: `N=2/3`, `Type=2`, `Disp=1`, `View=0`, `Dim1…DimN=1` | same file, `2164–2185`, `2214–2235` |
| Array entry | `datatap`, orientation 0: `Index`, `Dim=1`, `Type=2`, `Style=0`, `Disp=1` | same file, `4498–4517` |
| abc/dq and inverse | Copies of `abc2dq_1` / `dq2abc`, `Xb=1`, `qaxis=1`. Their original import and export, trig, dot-product, merge and wire structure | same file, definitions starting at `2457` / `1851` |
| Phase-voltage commands | `source_1`, orientation 4, `Type=6`, `Grnd=1`, `Spec=0`, `Cntrl=1`, `AC=0`, `Tc=0`. Separate per-phase R/L | same file, `3452–3529`. Resistor/inductor fields `939–950`, breakout `3383–3388` |
| DC current balance | `src_ccin_1`, orientation 1, `Cntrl=1`, `Tc=0`. Phase voltage and current products summed and divided by measured pole-to-pole voltage | same file, `5589–5630`. `xnode` binds electrical module ports |

Butterworth coefficients come from `BUTTERWORTH_TABLE`. A section `(a,0)`
becomes `1/(1+s*a/ωc)`. `(a,b)` becomes
`(ωc²/b)/(s²+(a*ωc/b)*s+ωc²/b)`. Explicit second-order states permit output
and derivative initialization. Unsupported filter families or control types
raise an error with the element name and concrete type. Saved fragments in
`test/pscad/fixtures/` retain the component fields, pins and orientations.

### Measurements, PLL and outer control

MEAS filters controller-frame voltage and current before multiplying them:
`Q_ac = -v_q*i_d + v_d*i_q`. The TLC supplies zero `i_dc` to its measurement
block. Its electrical current source separately implements physical DC balance.

PLL uses `dξ_pll/dt=-Ki*v_pll`, `Δω=-Kp*v_pll+ξ_pll`,
`dΔθ_pll/dt=ωbase*Δω`. The EMT angle is `ωbase*t+Δθ_pll`.
OCC includes voltage feedforward and `+Lpu*omega_c*i_q_f` /
`-Lpu*omega_c*i_d_f`, or the configured constant-frequency factor.
MMC inductance is `Lₑ=(L_arm/2+Lr)/L_AC_base`, obtained from
`elec_inductance(elec, bases(model))`.

| Control | Generated equation / initialization | Saved evidence |
|---|---|---|
| Vdc | `e=vdc_ref-v_dc_f`, `i_d_ref=-(Kp*e+ξ_v_dc)`, `ξ'=Ki*e`. VDCCTRL integral starts at converged `ξ_v_dc` | `local/GFL-MMC/DVC-Mode/GFL_MMC_Validation.pscx:2020–2045` (5/15 gains, 800 kV). Shared split PI and negation |
| P-f | `ξ_f'=ωc*(-Kω*(omega_c-1)-ξ_f)`, `P_eff=p_ac_ref+ξ_f`. Lag starts at converged `ξ_f_supp` and P PI at `ξ_P_ac` | `local/TLC/Simple_2L_VSC_RL.pscx:876–877`: `kp_f=5`, `tau_f=0.5 s`. Current API `Kω=5`, `ωc=2 rad/s` |
| Q-V | `ξ_v'=ωc*(K*(v_ac_ref-hypot(vG_d_f,vG_q_f))-ξ_v)`, `Q_eff=q_ac_ref+ξ_v`. Lag starts at `ξ_vac_supp`, Q PI at `ξ_Q_ac` | `local/GFL-MMC/Q-V_Droop/GFL_MMC_Validation.pscx:11992–11998`: `Kd=20`, `wf=100`. Shared `realpole` fields and pins |
| VAC | `e=v_ac_ref-hypot(vG_d_f,vG_q_f)`, `i_q_ref=Kp*e+ξ_v_ac`, `ξ'=Ki*e`. PI starts at converged `ξ_v_ac` | `local/GFL-MMC/VAC_Control/GFL_MMC_Validation.pscx:8025–8215` (split PI), `11936–11941` (0/100 gains). Shared square and square-root primitives |

Q-V and VAC references use `terminal_pu.v_ac*voltage_filter_ratio(model)`:
`turnsRatio` for MMC, 1 for TLC. Measured quantities and references use the same transformer side. VAC equilibrium replaces the `ξ_v_ac` residual
with `terminal_pu.q_ac-y.meas.Q_ac_f`. Normal dynamics retain the voltage PI.
Q-V already determines Q through its support equation.
Grid-following MMC VAC and Q-V select `type_ac=2`. VAC has `acq_droop=0`,
Q-V has `acq_droop=1` with `kq_droop=K*Sbase/(global_dict["S"]*1e-6)`.

### Grid-forming differential control

`ΔdqControlGFM` exports the current Julia sequence: reactive outer control,
`CCVI`, then the existing OCC. `VSEWithDamping` reuses the shared PLL generator.
Its voltage is rotated by `Δθ_pll-Δθ_VSM` before the embedded PLL filter.
The VSM implements
`ω_VSM'=(p_ac_ref-P_ac_f-K_d*(ω_VSM-ω_PLL)-K_ω*(ω_VSM-ω_ref))/(2H)`.
Its EMT angle integrates `ωbase*ω_VSM`. Subtracting the nominal angle gives
the Julia relative angle with derivative `ωbase*(ω_VSM-1)`.
`omega_c` is the VSM frequency. PLL outputs use separate local nets.

CCVI filters both measured voltage axes and sets `e_d=V_d_ref+q_ctrl_ref-v_d`,
`e_q=V_q_ref-v_q`. Its current references are
`i_d=(R_v*e_d-ω_c*L_v*e_q)/(R_v²+(ω_c*L_v)²)` and
`i_q=(R_v*e_q+ω_c*L_v*e_d)/(R_v²+(ω_c*L_v)²)`, exactly as `inner_voltage.jl`.
The reactive generator's output is connected as a voltage correction before
CCVI. Its two current outputs supply OCC.

Solved filter outputs and derivatives initialize the exported Butterworth realization.
The saved voltage-feedforward project supplies primitive examples, while the generated
CCVI/OCC sequence follows the Julia equations.

### MMC arms, total energy and circulating current

Each arm contains a controlled source, `L_arm`, `R_arm`, a current meter and
capacitor integrator:
`dv_Ctot/dt=(N/C_SM)*m_arm*i_arm`, `v_arm=m_arm*v_Ctot`.
Positive current charges the capacitor. The kA/kV scaling is direct.
Arm sources and capacitor integrators are on the parent canvas.

TEC uses six-arm energy `sum(v_Ctot.^2)/(6*vDC_base^2)`. Its cycle mean is the
current harmonic model's
`(vCΔ_d²+vCΔ_q²+vCΔ_Zd²+vCΔ_Zq²+vCΣ_d²+vCΣ_q²+2vCΣ_z²)/2`
(`MMC/energy.jl:19–28`). The physical arm plant retains a 6ω energy ripple from
the triplen pair. The measured energy retains that ripple. TEC's PI output
plus `P_ac_f`, divided by `3*v_dc_f` after startup release, sets the zero-sequence current reference.
ZSCC subtracts its PI output from `v_dc_f/2`.

CCSC transforms the circulating-current pair with the `-2θ` rotation and emits
`vMS_d_ref = -PI(-iS_d)+2*Larm*iS_q` and
`vMS_q_ref = -PI(-iS_q)-2*Larm*iS_d`, where Larm and currents use the DC bases.
These are the current equations in `MMC/inner_current.jl:31–49`, with ZSCC at
53–61. The Δ loops are the shared current-API outer P/Q and inner PI loops.
`MMC/MMC.jl:141–153` supplies their composition.

Uncompensated modulation maps Δ references back to the grid frame at
`theta_rel` and Σ references at `-2*theta_rel`. After startup release, its grid-coordinate commands are `mΔ=-2*baseConv1*vMΔ_ref/v_dc_f`, `mΣ=2*vMΣ_ref/v_dc_f` and
`mΣz=2*vMS_z_ref/v_dc_f` (`MMC/modulation.jl:43–71`). Physical arm
insertion indices are upper `(mΣ_abc+mΣz+mΔ_abc)/2` and lower
`(mΣ_abc+mΣz-mΔ_abc)/2`. Julia's negative Δ normalization produces the specified
physical voltage assembly `vMu=vMS-vMD`, `vMl=vMS+vMD`.

Uncompensated modulation uses five scalar transport channels: two Δ, two Σ
and one zero-sequence channel. `phase_compensated_dq` applies +ωbase delay
rotation for Δ, -2ωbase for Σ and none for zero sequence. The residual-delay
calculation below supplies the realized delay and matching initial history values.
Exact transport and Padé responses differ away from steady state.

Initial arm capacitor voltages reconstruct the solved harmonic coordinates at
nominal grid angle zero: Σ is `vCΣ_z + vCΣ_d*cos(-2θ) + vCΣ_q*sin(-2θ)`, Δ is
`vCΔ_d*cos(θ)+vCΔ_q*sin(θ)+vCΔ_Zd*cos(3θ)+vCΔ_Zq*sin(3θ)`. Upper and lower totals
are `(Σ±Δ)*vDC_base`. Control PI, filter and delay initial values come from
`converter_equilibrium`, from the converged state. The 0.2 s DC-divisor
hold protects measured-DC divisions while feedback remains live.

Disabled total-energy control supplies zero `iΣ_z_ref`. Disabled zero-sequence
current control removes its PI correction while retaining live `v_dc_f/2`.
Disabled circulating-current suppression supplies zero d/q commands. Disabled controls retain their zero contribution.

### Leg-energy control and compensated modulation

`ΣdqzControlLEC` exports `ΣEnergyControl`, `ΔEnergyControl` and
`CirculatingCurrentControl` in their Julia sequence (`MMC/MMC.jl:128–136`).
The live energies are `(vu²+vl²)/vDC_base²` and `(vl²-vu²)/vDC_base²`.
Their projections give Julia's `2wΣ` and `-2wΔ`
(`src/Network/Components/converter/MMC/energy.jl:67–151`). Σ d/q use
`-2*ωbase*t`. Δ d/q use `ωbase*t`. The scalar Δ zero sequence is lifted
into the triplen pair by twice its product with `cos(3*ωbase*t)` and
`sin(3*ωbase*t)`. Cycle means reproduce the seven energy coordinates.
The physical abc plant retains additional harmonics, including the 6ω
triplen ripple.

The explicit notch states obey `F1'=F2-sqrt(2)*ωn*(F1+u)-Jframe*F1`,
`F2'=-ωn²*F1-Jframe*F2`, with output `u+F1` and rotating PI
`ξ'=Ki*(ref-u-F1)-Jframe*ξ`. Σ uses `ωn=2ωbase`, `Jframe=-2ωbase*J`
and references `(0,0,2ref)`. Δ uses `ωn=ωbase`, frames `+ωbase` and
`+3ωbase`, zero references, and current outputs
`3/4*(d+Zd, -(q+Zq), 0)`. The filters use the Julia nominal frequencies.

The corrected triplen block follows the reconstruction
`T=[cos(3θ) sin(3θ); sin(3θ) -cos(3θ)]`: `Tdot*T=-3ωbase*J`, so
`x'=u-Jframe*x` requires `Jframe=+3ωbase*J`. The former `-3ωbase*J`
notch/PI block rotated against the plant. The validation case retains the original
Δ PI gains (`k=1`), matching the core compensated-admittance test. Its former
`+0.116 ± j943 s^-1` pair (150 Hz, 99.8% Δ-triplen PI participation)
becomes `-12.6 ± j941 s^-1`. All 89 poles are stable. Beyond the
slow stable OCC filter poles (`-6.28e-4 s^-1`), the
least-damped pair is `-4.87 ± j10.3 s^-1`. These values come from Julia linearization.

CCC adds the Σ and Δ references to grid-frame current control. It implements `ξ_i'=Ki*(iref-i)-J_-2ω*ξ_i` and
`vMΣref=-(ξ_i+Kp*(iref-i))+(0,0,v_dc_f/2)`
(`src/Network/Components/converter/MMC/inner_current.jl:81–104`).
Unlike TEC/CCSC, these currents are measured at the nominal grid angle,
without a VSM-relative rotation. All three current measurements and all seven
capacitor-energy inputs are live from `t=0`, closing CCC under the live energy
loops. Only the measured DC-voltage divisor in the three Σ current commands
uses the shared 0.2 s hold. The half-DC feedforward is live.
All 24 notch/PI integrators use the converged states. Physical arm
currents and capacitor dynamics remain active throughout startup.

The standard EMT compensated realization uses physical arm-capacitor division:
each upper arm uses `(vΣref-vΔref)/v_Ctot,u`, each lower arm
`(vΣref+vΔref)/v_Ctot,l`, followed by the existing exact `tdelay` primitive.
Δ references use the AC voltage base and `theta_c`. Σ uses the DC base
and nominal `-2ωbase` frame, following `modulation.jl:138–141`.

There are six 200 us physical arm delays, with histories initialized to
that arm's own solved physical ratio at the initial angle. Exact delay
and the specified Julia Padé(5,5) have different frequency responses
away from steady state, as already recorded for uncompensated modulation.

Julia's law is a seven-coordinate harmonic-domain matrix solve
(`src/Network/Components/converter/MMC/modulation.jl:143–152`), which
approximates the physical per-arm division. A steady-harmonic
check with positive arm capacitors measured insertion indices differing by up to
`0.00399` before any delay.
Julia's `mΔZd*cos(3θ)+mΔZq*sin(3θ)` maps to the third-harmonic content of
the physical upper-minus-lower insertion waveform. Per-arm division also
produces higher harmonics. Physical delays apply to the entire waveform,
including its triplen content.

A compensated case grew non-finite at 2.88 s with 10 us integration. At 1 us it settled
with `P=0.700`, `Q≈1e-7`, `omega=1`, capacitor means 639.4–639.5 kV
and 77.9 kV ripple. Export warns above 1 us and retains the requested step.
Use 1 us and verify refinement when extending this case.

### Equilibrium initialization

The exporter obtains the converged vector through `steady_state(model, values)`
and evaluates the existing state-space blocks. Equal cached per-port values
reuse the converged vector. A missing or different operating point calls
`linearize` to solve and store it. The returned vector is the cached object.
The table gives TLC state mappings. MMC control blocks use the same projection
of solved outputs, together with the arm-capacitor reconstruction above.

| Julia solved state(s) | PSCAD initial value |
|---|---|
| `vG_d_f_x*`, `vG_q_f_x*`, `i_d_f_x*`, `i_q_f_x*` | Each corresponding MEAS section output `Y0=C*x+D*u`. Second-order derivative `DY0=C*(A*x+B*u)` |
| States of optional `v_dc`, `i_dc`, `θ`, P/Q/Pdc measurement filters | Same output and derivative projection, using their own solved state slices and raw input |
| `v_q_pll_f_x*` | PLL filter section output and derivative from the solved realization |
| `ξ_pll` | PLL PI `pllI0` → `integral.Yo` |
| `Δθ_pll` | `theta0` → EMT angle `integral.Yo`. Nominal ramp subtraction gives the relative controller angle |
| `ξ_P_ac` / `ξ_v_dc` | PCTRL `pI0` / VDCCTRL `vdcI0` → `integral.Yo` |
| `ξ_Q_ac` | QCTRL `qI0` → `integral.Yo` |
| `ξ_f_supp` / `ξ_vac_supp` | Support-lag `support0` → `realpole.YO` |
| `vG_d_occ_f_x*`, `vG_q_occ_f_x*` when present | OCC feed-forward section output and derivative from the solved realization |
| `ξ_id`, `ξ_iq` | OCC `dI0`, `qI0` → `integral.Yo` |
| `m_delay_x1…x6` plus solved undelayed dq commands | Padé output `C*x+D*u` → exact-delay `dDelay0`, `qDelay0` → `tdelay.X0` |

A different filter realization receives its solved output and derivative. `NoFilter` has no initial state. Form parameters contain
precomputed coefficients and initial values.

### Execution order and modulation delay

`master:force_dsout` captures applied insertion indices and post-solve arm
currents. Their products drive capacitor charging. `master:force_dsdyn`
transfers that history to the next dynamics pass. Same-solve upper and lower
currents form circulating-current and DC-current measurements.

`master:zminusone` selects initialized synchronization-angle snapshots.
Acquisition and inverse rotations use the same relative-angle snapshot plus
nominal angle at the current timestamp. GFM retains separate VSM and PLL
snapshots. Fresh measured q voltage drives the PLL rate.

SIGMA and compensated MOD share six initialized snapshots of applied physical
capacitor states. Each snapshot reads the physical integrator output directly.
Physical states advance in DSDYN and remain fixed through the solve and DSOUT.
The next snapshot then matches acquired arm currents. Delaying a DSOUT copy
again would add an extra step. Source products and probes use advancing states.

Kept native builds verify one inherent measurement-to-source step for TLC,
grid-following MMC, grid-forming MMC and compensated MMC. Capacitor snapshots
precede consumers and commit after source preparation. No additional capacitor
feedback step remains.

For positive model delay, export requests `tau_model-dt` and rejects
`0 < tau_model < dt`. Residual steps use `RoundNearestTiesUp`: nearest integer,
positive half-step ties upward. Integer round-off is treated as integer timing.
Fractional residuals warn with converter name, model delay, step, requested and
realized residual, realized total and signed error, bounded by `dt/2`.
At zero model delay, explicit transport is zero and the inherent interface step remains.
Zero residual bypasses the queue.

TLC and uncompensated MMC use residual carrier rotations (+omega for Δ,
-2omega for Σ) and inverse-rotated initial history values. Compensated MMC delays abc
insertion indices and keeps physical initial history values without a dq rotation.
For `dt=10 us`, model delay 25 us requests 15 us residual, realizes 20 us
residual and 30 us total. Exact transport and Julia Padé delay differ away
from steady state with delay compensation.

## DC startup and pre-charge

TLC substitutes nominal pole-to-pole voltage until 0.2 s in MEAS, modulation
scaling and the electrical DC-current denominator, using the saved comparator
fields `X=0.2`, `OL=nominal kV`, `OH=v_dc_m`, `INTR=0`, `Dim=1`, `conv=0`.
An externally commanded current source ignores its `Tc` ramp. PSCAD division by
zero returns `1e99`, so a completed run can contain NaNs.

The MMC startup selector fixes the measured DC-voltage **divisor** at its solved value for
`t<0.2 s`. All feedback, including capacitor energy, currents, P/Q, PLL and
Vdc error, remains live. MEAS filters live voltage and supplies a private
`v_dc_divisor` to TEC/LEC current-command division and uncompensated modulation.
The Σ half-DC feedforward uses live `v_dc_f`. Compensated modulation divides
by live arm-capacitor voltage. Integrator states and delay histories start
from the solved equilibrium without resets or frozen derivatives.
At release the divisor becomes live, including any subsequent zero voltage.

Holding energy can conceal uncontrolled capacitor charging. Holding circulating
current opens the inner current loop under the live outer energy loop. Both
constructions diverged in compensated-MMC startup experiments. The divisor-only
selector keeps the control loops active while preventing initial DC division
by an unsettled voltage.

`emitters/dc_precharge.jl` finds connected DC buses through DC terminals.
DC islands are defined independently of ground and converter AC terminals. An island receives
pre-charge when it has no DC `Source` and has a TLC or grid-following MMC with
`OuterActiveVdcControl`. PQ-only and GFM-only islands receive none. Pre-charge
requires a positive solved pole voltage at each bus. Pre-charge planning uses
the supplied power-flow result.

Each bus receives temporary ideal sources at its positive and negative solved
pole-to-ground voltage behind `master:breaker1`. Sources have zero ramp.
Breaker `NAME=0` closes and `NAME=1` opens: the master calls
`E1PBRKR1_EXE(...,NINT(1-NAME))`. `OPCUR=1` permits opening at nonzero DC
current, `ENAB=0` disables insertion resistors, `RON=0`, `ROFF=1e100 ohm`
leaves `1e-100 S`. `TimeStep`/`Compare` supplies `open=(TIME >= 0.2)` using
`_CONVERTER_STARTUP_RELEASE`. NAME has no graphical signal pin and requires
one named driver. Final midpoint references remain in place.

Pre-charged DC bus probes use a conducting `nodelabel` with `MeasV=1`, `PU=0`
and the original probe name as `VName`. It evaluates `EMTDC_VVDC`, as does
`voltmetergnd`, without a separate meter branch that can move on load.
`check_connectivity(path)` verifies serialized or native-saved coordinates.
Export checks both the plan and written XML.

## Probes and recorders

The manifest retains probe names, units, element, side and direction. Machine
channels include P/Q in MW/MVAR, Vt and speed in pu, plus Ef0/Ef/Tm_init
initialization diagnostics. MMC adds six `<e>_v_Ctot_{u,l}_{a,b,c}` channels
in kV and `<e>_iS_z` on `Sbase/vDC_base`. Rotating `theta_c` is diagnostic.
Its nominal growth produces a settling warning even at a stable operating point.

Operating-point comparisons use public-bus fundamental machine and converter P/Q,
internal converter P/Q means, DC pole differences and current magnitudes.
Power error is divided by device MVA rating. Machine terminal voltage is
reconstructed through the exported rt/lt values. MMC capacitor cycle means
compare with solved pole-to-pole Vdc. Signed DC current compares with
`3*mean(iS_z)*Sbase/vDC_base`. The `powerflow` column contains that measured current reference.

Converter-connected DC currents use
`abs(measured_kA-reference_kA)/max(abs(reference_kA),Sbase/vDCbase)`.
DC connectivity propagates this base through branches, excluding ground and
AC terminals. Identical converter bases can share an island. Differing bases
raise an error. Converter-free networks retain relative current error.

Legacy OUT output contains an `.inf` channel list, `.infx`, and numbered
`.out` files with at most 10 channels each. Array names append the element index, starting with `name:1` and `name:2`.
OUT starts with a description line, followed by time and numeric values with
carriage-return and line-feed (CRLF) endings. Expected rows are `round(T/sample_step)+1`. PSCAD writes to
`project.temp_folder`, normally `<case dir>\<project>.gf81\`.

The validation runner subtracts identical zero-amplitude baselines, uses
coherent rectangular windows and requires an odd integer recording interval to integration step
ratio. That ratio prevents EMT-Nyquist chatter folding to DC. The validation README
describes KCL timing, reference selection and comparison limits.

## Remote execution and checks

The Windows station requires a logged-on desktop session to build EMTDC.
Secure Shell (SSH) session 0 cannot build. `RemoteConfig.pscad_port` selects the following
execution paths.

| Configuration | Application lifecycle |
|---|---|
| No port | `mhi.pscad.launch()` in the caller session. Stop it after execution. SSH fails before execution. |
| Port with responsive listener | Attach to the existing application. Restore its original `silence` flag and leave it running. |
| Port without listener | Start PSCAD in the desktop through a transient interactive scheduled task. Delete the task after launch and stop that application after execution. |

Before attachment, `probe.py` reads `app.is_busy()` and `app.version` under a
60 s watchdog, independently of `RemoteConfig.timeout`. Settings and projects
remain unchanged by the probe. Diagnostics go to `outputs/pscad-probe.txt` and
`outputs/pscad-probe-stderr.txt`. Failure stops execution before loading.
The runner sets `app.silence=true` before applying settings or loading a project.

`owner.txt` identifies the runner. `pscad-owner.txt` identifies a launched
application by process identifier, executable, port and creation time. `lifecycle.ps1` stops
identified runner processes, case-directory EMTDC executables and a PSCAD
instance started for the run. Timeout and caller cancellation share this path.
An executable or creation-time mismatch leaves the different process untouched
and removes the stale record. Malformed records and failure to stop an
identified process raise errors. Cleanup attempts every step and reports the
primary error before cleanup failures. Native stdout, stderr and exit codes
are retained. PowerShell command-line XML (CLIXML) stderr is decoded for Julia exceptions.

The runner compares schematic object origins before load and after saving
applied settings. Movement fails the `load geometry` phase before simulation,
reports up to 20 objects and retains `outputs/load-relocations.txt`.
`project.run()` blocks through build and execution. Settings readback uses
microseconds for `time_step`/`sample_step`. Output collection waits for stable
file sizes, then checks row counts without a counting timeout. Fresh runs retain
input, project, runner, solver and output hashes. Reuse requires all of them to match.

## Known limitations

Julia's fixed-frame dq reduction of an untransposed line can be non-passive. For the
170 km IEEE9 line, the minimum Hermitian admittance is -0.005134 S in dq versus
+0.0005009 S in phase coordinates. With a 100 MVA TLC at bus 2, the dq model predicts
a growing pair near 124.24/124.34 kHz (+2.37 s⁻¹). The phase-domain harmonic
calculation gives -670.4 s⁻¹, converged at K=1..3. The IEEE9 circuit with a TLC was not run
in PSCAD. Use phase-domain frequency-response and stability comparisons when untransposed
line asymmetry affects the frequencies of interest.

Untransposed AC lines produce steady negative-sequence unbalance and ±100 Hz image coupling
that a fixed-frame dq LTI comparison omits. With untransposed flat lines, the redesigned P2P's
c2 current has 2.7 % negative sequence and its bus voltage has 0.32 % negative sequence.
The image ratio reaches 0.50 and response errors are 14–21 %. The P2P circuit with AC grids
has 1.35 % negative-sequence current and 0.61 % negative-sequence bus voltage at c2,
image ratios of 0.32–0.59 and about 49 % response error.
The redesigned P2P uses untransposed lines and requires phase-domain comparison.
Ideal transposition remains available in Julia. PSCAD projects with `Transp = 1`
exit abnormally at termination, preventing successful PSCAD measurement runs.

### Line fitting and DC extrapolation

Tighter `YMaxE=AMaxE=0.02 %` targets reduce fit-versus-own-constants terminal-Y
error over 1–1000 Hz. AC cable/DC cable/DC overhead-line maxima are
0.84/0.49/0.35%, versus 4.34/2.88/4.31% at 0.2% targets. Increasing only
`Numf=400` gave 3.68/7.32/4.09%. More sample points alone did not improve
these fits. Constants differences and fit errors have separate denominators.

At `FS=0.001 Hz`, `DCenab=0`, a DC cable fit gives 0.484 ohm per pole at
s=0 versus 0.272 ohm in Julia (+77.8%). At 0.001 Hz it gives
0.275 ohm (+1.07%), with 2.17% full terminal-Y error. The DC OHL true-DC resistance error is 0.257 % on a 2.00 ohm reference. The fit's true-DC limit requires evaluation at s=0. One cable fit has a 260 s pole.
`DCenab=1` fails cable Yc fitting with `Error in INVCJD. Singularity occurs`.
The export retains the specified lossless dielectric inputs.

### Small DC powers

A TLC near-zero-power case at 10 us measured -63.7 kW converter DC power
and +50.2 kW source absorption. The network fundamental power calculation
`real(S_M*exp(jδ))`, with `δ=2π*50*10e-6`, predicts -63.7 kW and matches
the unrounded signed measurement within 0.95 mW. This supports a one-step voltage and current
alignment explanation, with a reactive-power cross term around 63.8 kW.
The remaining 21.2 mA cable-end difference can include low-frequency fit
conductance and settling. Its physical cause remains unresolved.

### Unsupported controls and circuits

`DCVoltageSupportLag` and non-`NoFilter` VAC/DC outer-control filters raise
“not yet exportable” before equilibrium recovery. Nontrivial energy
`power_filter` and nonzero CCC references need a separate Σ-generator review.
Exposed cable sheath and armour interfaces, AC counts other than three and DC
line counts other than two are unsupported.

### Distributed-line travel time and licence size

Emitters warn when `length/299_792_458 m/s < time_step`. PSCAD uses its own
calculated travel time and aborts when it is shorter than the integration step.
A 100 m OHL/cable measured 0.329/0.648 us. It cannot run at 10 us.
Reduce the integration step or explicitly change physical section length.

The recorded educational licence permits 200 electrical nodes and one
subsystem. IEEE9 uses 78 live nodes. Both recorded IEEE39 representations
use 528 and build
with only the node-cap error, zero warnings. Their exports pass offline checks.
They were not run in PSCAD under that licence. Licence usage counts the internal component nodes as well as bus conductors.

### P2P instability

PSCAD reproduces the instability Julia predicts for the original P2P. Julia locates two growing
modes at signed abc frequencies +3478.5 Hz with growth 1374 s⁻¹ and -3476.6 Hz with growth
1426 s⁻¹. The fresh-start record at 1.0 us fits a growing mode at +3543 Hz and 1630 s⁻¹ over
0.3–1.8 ms. Frequency is 1.9 % and growth is 19 % above Julia's +3478.5 Hz mode. The second
mode remains unresolved, with a fit at -4122 Hz.

The record is nonlinear in that interval. AC line energisation from the uncharged start gives
11.5 pu peak departure and arm insertion indices outside [0,1]. The harness status is
`invalid_measurement`, and the growth rate is not determined to 10 %.
A separate phase-a trace at 1 us fits 3473 Hz and a 0.688 ms growth time (1453 s⁻¹) over
0.3–1.8 ms. That interval was chosen after inspecting the record.

For the P2P with AC grids without its 80 km line, Julia's +160.6 Hz mode at 55.0 s⁻¹ completes
0.24 cycles in the 1.5 ms fit interval. Its 2 ms records cannot show that mode.
EMTDC steps of 0.2 and 0.25 us fail at the converter-transformer star point. Steps of 0.5 and
1.0 us run.

The 200 us modulation delay interacts with the roughly 3 kHz overhead-line resonance.
Differential modulation-delay states account for 98.81–98.84 % of explicit converter-state
participation, with distributed-line states excluded.

The builder screen gives converter `c1` the AC interface of converter `c2`: 333 kV, ratio 333/380,
`Lᵣ=0.0461 H`, `Rᵣ=0.4103 Ω`. With both converter delays varied and
Padé orders fixed at 5/5, every candidate is unstable on the 0.01 Hz to 100 kHz
complete-network scan:

| Both delays | Largest located Re(s), s⁻¹ | dq frequency, Hz | Nyquist net |
|---|---:|---:|---:|
| 200 us | +1341 | 3500 | 10 |
| 100 us | +331 | 8933 | 6 |
| 50 us | +264 | 15059 | 2 |

All three delay settings remain unstable.

The separate IEEE14 hybrid has positive roots +72.8 s⁻¹ at
29.7 Hz and +20.5 s⁻¹ at 82.8 Hz. The hybrid has no recorded PSCAD run. The complete IEEE14 circuit has
216 live nodes, above the educational licence's 200-node limit, and was not run in PSCAD.

The weak-grid grid-forming MMC at SCR 2.5 has Julia complete-network roots +101 ± j360 s⁻¹.
The circuit was not run in PSCAD. Screen results are recorded with each validation case and reported during
preparation.

### Operating-point results and their scope

IEEE9 passes all 41 operating-point rows: maximum voltage error 2.19e-5
relative, angle error 4.99e-4 degrees, current error 0.169% (3.9 A), against
1% voltage, 1 degree angle and 2% current limits. MMC Vdc/P-f/Q-V/VAC and
TLC VAC comparisons pass all 252 recorded rows. Worst capacitor errors are
0.174 % for Vdc and 0.0692 % for P-f, against 1%. Worst TLC VAC current
errors are 0.0179/0.0182 %, against 2%. Each representation uses its own solved comparison point. Frequency-response
agreement requires the separate injection measurements.
