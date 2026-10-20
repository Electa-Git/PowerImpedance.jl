# Legacy converter adapters

The [abbreviations](../pscad.md#Abbreviations) are defined in the export guide.

`_legacy_mmc` and `_legacy_tlc` in
`src/Network/NetworkBuilder/gs_converters.jl` map supported legacy keywords to
modular converter inputs. The tables describe the resulting equations, units
and comparison limits. `MMC_legacy.jl`, `TLC_legacy.jl` and `controller_old.jl`
remain independent equation references; they are not a second production
construction path.

## Setpoints and shared keywords

An explicit `Setpoint` field takes precedence over the corresponding legacy
network keyword. An explicit legacy control reference supplies a missing
setpoint. A differing control reference emits `@warn` with the converter name,
control and both values in setpoint units/sign; the explicit setpoint is retained. The legacy `[0]` reference remains
the automatic-reference sentinel. Controllers are copied without mutating their
references. Modular outer controls continue to read the solved power-flow
setpoint without an independent reference keyword.

| Keywords | Mapping and units |
|---|---|
| `P`, `Q` | Explicit network values remain MW/MVAr; missing values can come from control references. MMC `p`/`q` references are MW/MVAr; TLC references are pu and multiplied by `Sbase`. Both legacy `q` references use the dynamic convention, which is also the live modular `Setpoint.Qac` convention. |
| `P_dc`, `Vᵈᶜ` | Explicit MW/kV retained; a `dc` or `vdc_droop` reference is pu and supplies missing `Vdc` after multiplication by the DC-voltage base. |
| `θ` | Angle in radians. |
| `Vₘ` | Existing Gridspace RMS phase-voltage convention retained: `Vac=√2 Vₘ`. Explicit `vac`/`vac_supp` references supply peak phase voltage in kV. The historical MMC field describes amplitude; the separate TLC compatibility shim uses amplitude directly. |
| `P_min`, `P_max`, `Q_min`, `Q_max` | Explicit values retained in `Limits`; defaults differ as listed below. |
| `Lᵣ`, `Rᵣ` | Physical reactor H/Ω passed to the electrical model. |
| MMC `Lₐᵣₘ`, `Rₐᵣₘ`, `Cₐᵣₘ`, `N`, `turnsRatio` | Physical arm H/Ω/F, submodule count and dimensionless transformer ratio passed to `ElectricalMMC`; its existing per-unit normalization is retained. |
| `vACbase_LL_RMS`, `Sbase`, `vDCbase` | Electrical bases: line-to-line RMS kV, MVA and pole-to-pole kV. MMC names the stored DC base `vDC_base`. |
| `ω₀` | Maps to `ωbase` in rad/s. Historical per-unit normalization hard-codes `100π`; non-50-Hz historical equivalence is not established. |
| `timeDelay`, `padeOrderNum`, `padeOrderDen` | Existing MMC `UncompensatedModulation` or TLC `DelayModulation`. TLC validation includes 200 μs, order 3/3. Historical delays require the corresponding current-control path. |
| `controls` | Copied dictionary; direct controller keywords override matching entries. The supported controls below are consumed. |
| `connection` | Forwarded to the element constructor. |
| `equilibrium`, `A`, `B`, `C`, `D` | Computed outputs: core solves and linearizes afresh. They are not model inputs. |
| `vACbase`, `iACbase`, `iDCbase` | Derived bases recomputed by the electrical model; no input override is implemented. |

Existing Gridspace defaults remain unchanged: `P=Q=P_dc=Vᵈᶜ=0`,
`Vₘ=220`, and limits `(0.9,1.1,-0.5,0.5)`. They differ from the old MMC
constructor's `(-10,3,100,640,333)` and limits `(-100,100,-50,50)`.
An explicitly supplied controller reference can change the power-flow
input when the corresponding network value was absent.

## Controls and filters

The control precedence follows the historical equations: `p` before `dc`,
`q` before `vac`. Filter cutoff frequencies are rad/s. A filter is realized
when its order and cutoff are positive. Historical equations determine which filter fields affect the model.

| Control/keyword | Mapping / historical equation |
|---|---|
| MMC/TLC `pll` | PI on the filtered q-axis voltage; `ref` was unused. TLC first filters the AC measurement. |
| MMC `p` | PI gains, setpoint precedence above, and `n_f`/`ω_f` on measured AC power. |
| TLC `p` | PI gains and setpoint precedence; historical `p` filter fields are unused. |
| MMC `q` | PI gains, setpoint precedence, and `n_f`/`ω_f` on measured reactive power. The same filter specification independently filters energy feedforward power. |
| TLC `q` | PI gains and setpoint precedence; historical `q` filter fields are unused. |
| MMC/TLC `dc` | PI gains and setpoint precedence; `OuterActiveVdcControl(filter=...)` maps `n_f`/`ω_f` locally to the DC PI input. Shared DC measurement remains unfiltered for modulation and MMC energy/zcc feedforward. Filter equilibrium equations remain active; only the PI residual is replaced by solved DC current. |
| MMC/TLC `vac` | `OuterReactiveVacControl(filter=...)` filters `sqrt(v_d²+v_q²)` before the PI. Filter states precede `ξ_v_ac`; equilibrium retains their equations and replaces only the PI residual with solved Q. |
| TLC `vac_supp` | `VoltageSupportLag` on the measured voltage magnitude, added to Q reference. |
| MMC `vac_supp`, `n_f=1` | First-order measured-voltage lag, with the equivalent state transformation given below. |
| MMC `vac_supp`, `n_f=0` or ≥2 | Still unsupported; no existing proportional support with this magnitude-filter transfer. Unsupported forms are listed below. |
| MMC/TLC `f_supp` | `FrequencySupportLag(Kω=Kp,ωc=ω_f)`: `Δp'=ω_f(-Kp Δω-Δp)`, added to P reference. This is the TLC historical equation; MMC has no historical `f_supp` equation. |
| MMC `occ` | PI gains and voltage-feedforward filter retained; decoupling uses nominal frequency, as in the historical MMC equation. |
| TLC `occ` | PI gains retained; historical `occ.n_f`/`ω_f` unused, so no additional filter. Decoupling uses synchronized frequency. |
| MMC `energy` | `TotalEnergyControl`: gains, reference (`[0]`→1), and independent AC-power feedforward using the legacy **q** filter. `energy.n_f`/`ω_f` unused. |
| MMC `zcc` | `ZeroSequenceCurrentControl` PI gains and energy-derived reference. `ref`/`n_f`/`ω_f` unused. |
| MMC `ccc` | `CirculatingCurrentSuppressionControl`: gains and both pu current references (`[0]`→`(0,0)`), in the −2ω converter frame. `n_f`/`ω_f` unused. |
| TLC `v_meas_filt`, `i_meas_filt` | `n_f`/`ω_f` on AC voltage/current components; PI gains and references unused. |
| MMC `v_meas_filt`, `i_meas_filt` | Mapped to the existing shared measurement filters; the historical MMC file has no equations for these keywords. |
| MMC/TLC `vdc_droop` | Maps `Kₚ` and `ω_f` to `DCVoltageSupportLag(K=Kₚ,ωc=ω_f)`, subtracted from the `p` reference. The pu voltage reference follows the setpoint policy above. `Kᵢ` and `n_f` are unused by the historical first-order lag. MMC has independent historical equations; TLC uses the same shared equations and has no historical `vdc_droop` branch. |

TLC voltage support uses `Δq'=ω_f(Kp(Vref-|V|)-Δq)`. First-order MMC
voltage support uses `Δq=Kp(Vref-H(s)|V|)`, `H(s)=ω_f/(s+ω_f)`.
For fixed Vref, `Δq=Kp(Vref-Vfiltered)` gives the equivalent lag state.

`TotalEnergyControl(power_filter=NoFilter())` retains the existing modular
filtered-power feedforward exactly. A nontrivial filter independently filters
power from measured voltage/current components. The adapter selects the
historical independent feedforward even with no filter, avoiding a cascade
through `p` filtering. `CirculatingCurrentSuppressionControl(ref=(0.0,0.0))`,
`OuterReactiveVacControl(filter=NoFilter())` and
`OuterActiveVdcControl(filter=NoFilter())` retain modular default
results and state counts. Energy filter states precede `ξ_Wtot` and initialize
at the solved active power. VAC filter states initialize at the solved measured
voltage magnitude. DC-controller filter states precede `ξ_v_dc` and initialize
at the solved DC voltage in pu.

## DC-voltage support and power-flow bases

`DCVoltageSupportLag` implements the historical MMC dynamic equations:

```math
\dot{\Delta p}=\omega_c[K(v_{dc,ref}-v_{dc,f})-\Delta p],\qquad
p_{ref,eff}=p_{ref}-\Delta p.
```

Both voltages use the declared converter DC-voltage base. The lag state
`ξ_vdc_supp` precedes `ξ_P_ac` and initializes at zero. Like the other modular
outer controls, it reads the solved power-flow reference; at the solved point
the voltage error and support contribution are zero. The default gain and
cutoff are both zero, mirroring `FrequencySupportLag`. A zero gain gives
zero power-flow slope; a zero cutoff leaves the lag state constant.

PowerModelsACDC uses type 4 (AC-side power droop). With converter bases
`Sc` in MVA and `Vc` in pole-to-pole kV, system bases `Sg` and `Vg` in the
same units, and physical setpoints `Pac` and `Vdc`, the mapper uses
`droop=(1/K)*(Vc/Vg)/(Sc/Sg)`, `Vdcset=Vdc/Vg`, and `Pacset=-Pac`.
For zero gain, the inverse slope is infinite and the type-4 constraint reduces
to constant active power. The declared base controls both the reference
conversion and the slope, so power flow and dynamics use one operating point.
No separate control reference keyword is introduced.

This deliberately differs from the historical mapper away from nominal
voltage. That mapper substitutes the operating voltage for `Vc`, although
the historical dynamics divide by `vDCbase`. For `K=5`, `Sc=500 MVA`,
`Vc=640 kV` and a legacy reference of `1.05 pu`:

| Operating voltage | Historical power-flow reference | Historical power-flow slope | Modular power-flow and dynamic reference | Modular power-flow and dynamic slope |
|---|---:|---:|---:|---:|
| 640 kV | 672 kV | 3.91 MW/kV | 672 kV | 3.91 MW/kV |
| 672 kV | 705.6 kV | 3.72 MW/kV | 672 kV | 3.91 MW/kV |

Tests compare MMC physical equilibria and terminal admittances against the
independent historical dynamic reference at 672 kV, including distinct
second-order power filters. TLC has no historical DC-droop reference model;
tests compare the shared lag/PI equations directly. Both converter
types and network representations also retain the unmodified dynamic
equations at an off-nominal solved power-flow point, within the existing
equilibrium accuracy.

The adapter requires `p` for `vdc_droop`. Simultaneous `f_supp` and
`vdc_droop` are rejected explicitly because `OuterActivePowerControl` has
one support slot. A simultaneous-support implementation would need to combine both contributions
explicitly; the current adapter rejects that combination.

## Unsupported inputs and comparison limits

| Inputs/path | Current behavior and missing mapping |
|---|---|
| MMC `gfm`, `p=VSE_old`, `vse`, `VI`, `vi` | The adapter builds the GFL differential path. Partial `vse` synchronization does not reproduce the historical GFM differential control. |
| `VSE_old.H`, `K_d`, `K_ω`, `ref`, `ref_ω`, `n_f`, `ω_f` | The original `p` VSE path is unmapped, including inertia/damping/droop, PLL coupling, reference and power filtering. |
| `VI=CCQSEM`: `Rᵥ`, `Lᵥ`, `ref_vd`, `ref_vq`, `n_f`, `ω_f` | Ignored. The complete historical virtual-impedance and voltage-control path has no modular mapping. |
| `VI=FFVI`: `Rᵥ`, `Lᵥ`, `TVR`, `ω_ₜᵥᵣ`, `ref_vd`, `ref_vq` | Ignored. The historical transient virtual-resistance and voltage-feedforward equations have no complete GFM mapping. |
| MMC static/higher-order `vac_supp` | Requires a proportional support block with the specified magnitude filter; a first-order lag has a different transfer function. |
| TLC `Lₐᵣₘ`, `Rₐᵣₘ` | Ignored. Historical power flow combines arm/reactor terms; dynamics use only `Lᵣ`/`Rᵣ`. The physical partition is unresolved. |
| TLC `energy`, `zcc`, `ccc` | Ignored: the historical TLC has no Σ plant or corresponding equations. |
| `PI_control.bandwidth`, `ζ` | Automatic tuning is unsupported. Historical TLC zero-gain `occ` tuning refers to undefined `Lₑ`/`Rₑ`; use explicit gains. |
| `occ.ref` | Historical current-state initial guess, overwritten in TLC; the outer loops supply the dynamic current reference. |
| `PI_control.Kₚ`, `Kᵢ`, `ref`, `n_f`, `ω_f` | Mapped where consumed above; other fields remain unused exactly where their old equations ignore them. |
| TLC `debug` | Legacy output-storage option dropped; use the internal `_steady_state` accessor on the solved element rather than mutable compatibility output fields. |
| Arbitrary `Controller`-valued keywords | Historically stored even without an equation. Stored historically without a corresponding equation; no dynamic behavior is implemented. |
| Defaults, derived-base overrides, non-50-Hz normalization | The current adapter retains these differences; equivalence is not established. |

### Intended TLC PLL difference

The TLC PLL always receives `meas.vG_q_f`, including when its own filter is
`NoFilter()`. This is the modular convention validated against PSCAD. In the
historical TLC, disabling the PLL filter selects raw `Vᴳq`, bypassing an active
AC measurement filter. The adapter deliberately retains the modular convention;
no selector keyword is introduced. For raw q voltage 0.2 pu, measured q voltage
0.1 pu, `Ki=7`, `Kp=0.3` and zero PLL integral, the modular integral derivative
is −0.700 pu/s and frequency is 0.97 pu; the historical bypass gives
−1.40 pu/s and 0.94 pu. An adapter test preserves the selected
filtered input. At steady state a unity-gain measurement filter removes this
input difference, while the dynamic admittance can differ.

A full historical VAC-only TLC comparison is impossible: its dynamic source
has no such branch. Both historical filtered DC branches index `:vdc` although
the accepted controller is `:dc`; block filter/PI equations are compared without
activating or repairing that old construction path. The historical TLC
`vac_supp` automatic reference is already pu before a second division by the AC
base; the selected solved-setpoint policy is tested, rather than reproducing
that unit inconsistency. Support without `q`, and standalone `zcc` without
energy, lack a valid complete historical controller combination. The existing
TLC support-only shim behavior is retained. Historical `q.ref` is in the
dynamic Q convention, as is the live modular
`Setpoint.Qac` (with TLC power-base scaling). The historical update function
negates its Q argument; a comparison must pass the negative of the
modular setpoint to that reference function. Nonzero-Q historical fixtures
exercise this conversion as well as the missing/conflicting-reference cases.

The independent MMC reference test uses the historical generated-expression
callbacks; the later nested callback has out-of-scope variables. The historical equations, gains and solver settings are retained. It compares physical states and terminal admittances with no filters
and with distinct second-order p/q filters, nonzero CCC references, energy
reference 1.1 and nonzero Q. Filter states use different realizations, so their
transfer functions and transformed equations are compared, not their raw coordinates.
TLC comparisons use both independent stored validation datasets, including
P-frequency and DC/Q-voltage support, measurement/PLL filters and modulation
delay; their existing acceptance limits are retained.

PSCAD rejects `DCVoltageSupportLag` and any non-`NoFilter` VAC or DC-voltage outer-control filter as
“not yet exportable” before recovering its equilibrium. Its Σ generator also
needs a separate review for nontrivial energy `power_filter` and nonzero CCC references: the current
generator implements the default equations. Those variants have no verified Σ export mapping.
