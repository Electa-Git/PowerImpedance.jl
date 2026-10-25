# Complete-system study ports

Factories are frozen copies of Jan Kircheis' study data and use current public
constructors. They do not execute or read the source files at runtime. ID
`p2p_redesigned` is the redesigned P2P system. `ieee14` is IEEE14,
`p2p_ac_grids` is P2P-AC with both lines, `p2p_ac_single_line` omits the 80 km line, and `p2p_original`
is the original P2P. The native scientific model is unchanged. The
reviewed export adds one empty row only when a DC precharge clock stub would
intersect preceding wiring (`src/PSCAD/emitters/dc_precharge.jl`). Existing valid
layouts are retained; the offline regression reproduces the IEEE14 collision.
Julia 1.10 syntax and the existing validation environment suffice.


Source snapshots (SHA256; source files were read only):

| File under the source repository | SHA256 |
|---|---|
| `Grids/IEEE14bus/IEEE14bus.jl` | `9025f1ea15d4e0b5dfbdb993a8fb4fe041d24594ebf4777dc9f3a6456b8af6a1` |
| `Grids/P2P_HVDC/P2P_HVDC_AC_grid.jl` | `ea0fe4137b57cf1bb55dac52d765bf2414a75a6f0b0df8a379ddd60515f1ba69` |

## Model and topology declarations

Each factory returns `NetworkBuilder.define(elements, topology; options)` with
component models in a named tuple. `Bus(...; ports, domain = ACDQ)` declares AC
connections. The builder transforms passive ACABC ports to the bus coordinates.
A DC bus contains one differential net; two-conductor cables and overhead lines
attach through `side1` and `side2`. Sources and machines expose `ac` or `dc`;
converters expose `ac` and `dc`.

| Declaration | Physical meaning |
|---|---|
| `options = (; voltageBase = Vm)` | AC phase RMS kV. |
| `ac_source(v = sqrt(2)*V)` | Physical phase-peak kV from phase RMS. |
| `dc_source(v = 640)` | Pole-to-pole kV; PSCAD emits two 320 kV pole sources. |
| `impedance(z = s -> expression, conductors = 3)` | Physical impedance in ohms. |
| `ElectricalMMC` / `ElectricalTLC` | Original SI parameters and MVA/kV bases. |
| `component(model; inputs...)` | Per-unit loop references and power-flow seeds. |
| `compute(PowerFlowProblem(state), ACDCPowerFlow())` | Physical inward port values. |
| `NetworkBuilder.NetworkModel(state, point.operating_point)` | Native admittances. |
| `Limits(...)` | Original operating limits. |

Unspecified historical limits remain ±100 MW / ±50 MVAr.

GFL MMC references live in `delta_control.outer_active` and
`delta_control.outer_reactive`; GFM active power lives in `sync.p_ref`. TLC
references live in `outerActive` and `outerReactive`. P/Q references use MVA bases,
DC voltage uses the pole-to-pole base, and AC voltage uses the model's phase-peak
base. Power-flow seeds retain their original values and converter signs.

All controller gains, optional filters, disabled energy/zero-sequence loops,
modulation delays, geometry and earth parameters remain as specified below.
The IEEE14 wind-farm DC supplies each declare 640 kV on one DC bus. Exported
positive and negative pole sources each retain 320 kV.

Unspecified historical MMC electrical values are made explicit: arm R=1.07 Ω,
L=50 mH, C=10 mF, N=400, transformer R=0.535 Ω and L=60 mH, 380 kV LL / 1000 MVA,
ratio 1. These values are the defaults of the former legacy MMC model.
Initial unspecified Pac=-10 MW and Pdc=100 MW are historical
initial guesses, overwritten by the package power flow; they are not new
specified operating points. TLC DC base is 640 kV. Source source-voltage and
current package naming conventions require the voltage conversions above.

## Redesigned P2P

`p2p_redesigned` builds the redesigned system directly from the original local P2P: two 1000 MVA MMCs, the
25 km cable and 75 km DC overhead line, with the 25/90 km AC lines. Both AC
sources receive SCR-8, X/R-10 impedances. The converter transformer ratios are
333/380, reactor inductance 46.1 mH and resistance 1.10889 ohm. Arm inductances
stay 50/30 mH, arm resistance 1.07 ohm, submodule capacitance 10 mF and count 400.
Both modulation delays are 25 us, OCC PI is 0.25/100, voltage feedforward is
second-order 500 Hz, voltage measurement first-order 2 kHz and PLL first-order
40 Hz with PI 0.14/3.1416. Vdc PI is 3/7.5; P/Q PI is 0.05/15.70795. The receiving
request is 100 MW and both reactive requests are 100 MVAr. The selected OCC uses
instantaneous frequency multiplication. The original source values remain in
`p2p_original`, including its unreferred c1 transformer and 200 us modulation delays.

## IEEE14 source selection and authorized changes

Source: `Grids/IEEE14bus/IEEE14bus.jl`, not either instability-study file.
WF1 PLL is Kp=0.397887357729738, Ki=7.957747154594767, first-order 80 Hz, as
commented beside its unstable tuning and as used by WF2/WF3. MMC2 delay is
250 µs, the first specifically Julia-and-PSCAD-stable value in the notes at
source lines 589–598. MMC1/3/4 retain 200 µs and all retain Padé 5/5. Both
cables' I2 outer radii change from 6.12 to 61.2 mm; inner radius stays 55.4 mm.

The executable source has **five** loads, B2/B3/B4/B5/B6. Its B9/B10/B11/B12/
B13/B14 definitions and connections are commented out; there is no B8. Those
comments remain inactive. The B9-load note records an earlier removal; the active circuit retains five loads. All five
active loads retain their parallel R-L or R-C expressions and `calc_RLC`
values (`V²/(3S)` and the corresponding 50 Hz L/C formulas).

## Every physical/control difference from `test/make_y_node_test.jl`

The committed test remains untouched. Formatting, variable scope, lambda
annotations, and replacement of syntax-only construction are not physical
changes. The following list includes source defaults that the committed test
had replaced explicitly.

| Field | Committed test | `ieee14` |
|---|---|---|
| MMC1 Pac request | -500 MW | -1000 MW |
| All four MMC Q limits | ±1000 MVAr | ±500 MVAr |
| All MMC OCC cross coupling | default instantaneous `ω_c` multiplication | fixed-base coupling, explicit false |
| MMC1/2 energy feedforward | shared P measurement, no extra energy filter | independent 2nd-order 140 Hz q-filter feedforward, matching legacy source |
| MMC2 modulation delay | 200 µs | 250 µs (authorized stable choice) |
| MMC3/4 arm R/L/C | 0.4 Ω / 46.125 mH / 11.3867 mF | historical unspecified defaults: 1.07 Ω / 50 mH / 10 mF |
| MMC3/4 power measurement filters | P and Q 2nd-order 140 Hz | none |
| MMC3/4 PLL filter | 1st-order 80 Hz | none |
| MMC3/4 OCC PI | 0.1048 / 48.1914 | 0.7691 / 522.7654 |
| MMC3 OCC feedforward filter | 2nd-order 600 Hz | none |
| MMC4 OCC feedforward filter | 2nd-order 100 Hz | none |
| MMC3/4 CCSC PI | 0.0992 / 42.9719 | 0.1048 / 48.1914 (ZSCC remains 0.0992 / 42.9719) |
| MMC3 delay | 250 µs | 200 µs |
| MMC3/4 initial Pac/Pdc | 0 / 0 MW | historical initial -10 / 100 MW; Vdc control determines solved Pac |
| MMC1/2 and all WF initial Pdc | Pac request | historical initial 100 MW; solved Pdc replaces it |
| WF1/2/3 PLL PI | rounded 0.3978 / 7.9577 | exact 0.397887357729738 / 7.957747154594767 |
| WF1 PLL filter | 50 Hz | 80 Hz |
| WF1/2/3 limits | ±1000 MW / ±1000 MVAr | historical unspecified ±100 MW / ±50 MVAr |
| Zg2 resistance | 1.0263 Ω | 1.026 Ω |
| T2_4 | 250 km | 100 km |
| T6_11, T10_11, T9_10, T7_9 | 20 km each | 5 km each |
| Both cable I2 outer radii | 6.12 mm | 61.2 mm (authorized correction) |
| Loads | four series loads B3/B4/B5/B6, joint P/Q series conversion | five parallel loads B2/B3/B4/B5/B6, independent P/Q shunt conversion |

All remaining electrical values, line geometries/lengths, cable materials,
source voltage levels, and element connectivity agree after accounting for the
added B2 load; B8 remains absent in both.

## P2P with AC grids

The first analytical network is used, not the later black-box alternative.
Both variants retain pHVDC1=600 MW, qC1=0, qC2=300 MVAr; c2 PLL Kp=7,
Ki=12.5664 and first-order 50 Hz filter. `p2p_ac_grids` restores the exact commented
80 km line in parallel with the 90 km line. `p2p_ac_single_line` omits that branch, matching
the executable analytical network. Source notes at lines 171–186 state that
both connected/disconnected outcomes were PSCAD validated, including this
600 MW / 300 MVAr operating point. Their numerical modal frequencies and growth rates are unspecified.

**Owner decision (2026-10-16):** both P2P MMC calls omit `Vₘ`; use the
current legacy adapter's default **220 kV phase RMS**, mapped to
`terminal values.Vac=220sqrt(2)` kV phase peak. This is the adapter's rounded nominal
phase voltage for the 380 kV grids (`380/sqrt(3)` is approximately 219.393 kV).
The archived constructor's 333 kV default would request approximately 1.52 pu
on the 1.0 / 0.9 pu grids, inconsistent with the documented PSCAD-validated
operation. Powers, bounds, PLL gains and grid voltages are otherwise unchanged.
The source notes give only qualitative stable/unstable outcomes; no reference
modal frequency or growth rate is invented.

## Offline screen interpretation and rerun

All numerical evidence is **post-line-fix**. `system_screens.jl` uses the existing
complete-network native assembly with ideal source nodes clamped and exported
DC midpoint-reference conductances included. AC pi seeds are positive-sequence
at 50 Hz; DC pi seeds are differential at 1 Hz. Final root refinement and two
finite contours (0.01 Hz–100 kHz / 6001 points and 1e-6 Hz–1 MHz / 12001 points)
use the full native distributed elements. Refinement samples the real-axis corner,
nominal-carrier neighborhoods and located-mode widths, then subdivides rapid
phase turns and magnitude curvature. Initial counts remain saved alongside the
refined counts, their frequencies and unresolved intervals. As for `two_mmc_dc_cable`, the infinite spectrum
is unenumerated and behavior at infinite frequency is not proved. Unresolved seed tracks
and contour phase increments are retained. A passing finite screen is not a
complete-spectrum proof or native validation.

Conditioning is sampled on 3001 logarithmic frequencies from 1 to 1000 Hz plus
the exact drive tones: full SI nodal Y, the 4x4 Schur Y at the two measurement
ports and each port's 2x2 Schur Y. It is a static
screen, not the future measured input-matrix conditioning check. Static electrical partitions and external bus nodes do not establish native live
nodes or licence subsystem counts. The exporter uses one top-level Main
subsystem. Complete-system native builds must show <200 live nodes and one subsystem. Existing
passive elements, single devices and coupled circuits limits remain <100.

From this worktree:

```sh
julia --startup-file=no --project=test/manual/pscad/validation test/manual/pscad/run_system_screens.jl
```

The validation Manifests point at this worktree. The original `Manifest.toml`
is resolved for Julia 1.10.11 and the ignored `Manifest-v1.12.toml` for Julia
1.12.7. The Project dependencies are unchanged. Exports use the installed
mhi-xml Python environment with `JULIA_CONDAPKG_BACKEND=Null`,
`JULIA_PYTHONCALL_EXE` set to its executable and `PYTHONDONTWRITEBYTECODE=1`.
Trailing IDs select a subset. `SYSTEM_SCREEN_DATA` and `SYSTEM_SCREEN_EXPORTS` select output
folders, defaulting to this worktree's ignored `data/system_screens/` and
`/tmp/system_exports/`. Each project includes two zero-amplitude current ports,
full metering, 0.01 s duration, 2.5 us integration, 62.5 us recording and sheet
size 5. A failed numerical screen still leaves its short export available for
a separate native build.

## IEEE14 conditioning ports

The measurement ports are MMC1 and MMC4 AC, in that order, with d then q at
each port. Their 4x4 Schur admittance eliminates internal AC/DC nodes while
retaining every converter's dynamics. Separate 2x2 screens eliminate the other
measurement port with zero external injection. The first raw diagnostic also
retains the 14x14 matrix across all seven converter AC terminals and its seven
single-terminal reductions. Its full result can be reproduced with
`system_conditioning(system_circuit(net))` after power flow. These are sampled target
matrix conditions; the measured drive matrix is tested separately during each
four-current experiment.
