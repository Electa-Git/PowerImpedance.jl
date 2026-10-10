# Legacy converter adapter audit

Step 2 restores the supported legacy control mappings. DC-voltage filtering
is local to the DC PI; the TLC PLL retains the modular filtered-measurement
convention validated against PSCAD.

This audit covers `_legacy_mmc` and `_legacy_tlc` in
`src/Network/NetworkBuilder/gs_converters.jl`, against the constructor fields,
compatibility keyword set and equations in `MMC_legacy.jl`, `TLC_legacy.jl` and
`controller_old.jl`. The historical sources are retained as references, rather
than activated as a second production construction path.

The complete keyword ledger has 108 rows: 34 MMC fields, 40 TLC compatibility
keywords, the equation-backed controls and their parameter fields. The original
and resulting ledgers are `legacy-keyword-audit.tsv` and
`legacy-keyword-audit-after.tsv` in `/tmp/package-fixes-step2/`. The tables below
cover those keywords, grouping fields with the same disposition. “Different”
records an existing semantic difference, rather than a claim of complete
historical equivalence.

## Setpoints and shared keywords

An explicit `Setpoint` field takes precedence over the corresponding legacy
network keyword. An explicit legacy control reference supplies a missing
setpoint. A differing control reference emits `@warn` with the converter name,
control and both values in setpoint units/sign; the setpoint wins. The legacy `[0]` reference remains
the automatic-reference sentinel. Controllers are copied without mutating their
references. Modular outer controls continue to read the solved power-flow
setpoint; they gain no independent reference keyword.

| Keywords | Before | Result and units |
|---|---|---|
| `P`, `Q` | Mapped, different defaults | Explicit network values remain MW/MVAr; missing values can come from control references. MMC `p`/`q` references are MW/MVAr; TLC references are pu and multiplied by `Sbase`. Both legacy `q` references use the dynamic convention, which is also the live modular `Setpoint.Qac` convention. |
| `P_dc`, `Vᵈᶜ` | Mapped, different defaults | Explicit MW/kV retained; a `dc` reference is pu and supplies missing `Vdc` after multiplication by the DC-voltage base. |
| `θ` | Mapped | Angle in radians. |
| `Vₘ` | Different | Existing Gridspace RMS phase-voltage convention retained: `Vac=√2 Vₘ`. Explicit `vac`/`vac_supp` references supply peak phase voltage in kV. The historical MMC field describes amplitude; the separate TLC compatibility shim uses amplitude directly. |
| `P_min`, `P_max`, `Q_min`, `Q_max` | Mapped, different defaults | Explicit values retained in `Limits`; default compatibility is a remaining proposal. |
| `Lᵣ`, `Rᵣ` | Mapped | Physical reactor H/Ω passed to the electrical owner. |
| MMC `Lₐᵣₘ`, `Rₐᵣₘ`, `Cₐᵣₘ`, `N`, `turnsRatio` | Mapped | Physical arm H/Ω/F, submodule count and dimensionless transformer ratio passed to `ElectricalMMC`; its existing per-unit normalization is retained. |
| `vACbase_LL_RMS`, `Sbase`, `vDCbase` | Mapped | Electrical bases: line-to-line RMS kV, MVA and pole-to-pole kV. MMC names the stored DC base `vDC_base`. |
| `ω₀` | Different | Maps to `ωbase` in rad/s. Historical per-unit normalization hard-codes `100π`; non-50-Hz historical equivalence is not established. |
| `timeDelay`, `padeOrderNum`, `padeOrderDen` | Mapped, conditional differences | Existing MMC `UncompensatedModulation` or TLC `DelayModulation`. TLC validation includes 200 μs, order 3/3. Historical delays require the corresponding current-control path. |
| `controls` | Selectively mapped | Copied dictionary; direct controller keywords override matching entries. The supported controls below are consumed. |
| `connection` | Mapped | Forwarded to the element constructor. |
| `equilibrium`, `A`, `B`, `C`, `D` | Dropped | Computed outputs: core solves and linearizes afresh. They are not model inputs. |
| `vACbase`, `iACbase`, `iDCbase` | Dropped | Derived bases recomputed by the electrical owner; no override contract implemented. |

Existing Gridspace defaults remain unchanged: `P=Q=P_dc=Vᵈᶜ=0`,
`Vₘ=220`, and limits `(0.9,1.1,-0.5,0.5)`. They differ from the old MMC
constructor's `(-10,3,100,640,333)` and limits `(-100,100,-50,50)`.
An explicitly supplied controller reference can now change the power-flow
input when the corresponding network value was absent.

## Controls and filters

The control precedence follows the historical equations: `p` before `dc`,
`q` before `vac`. Filter cutoff frequencies are rad/s. A filter is realized
when its order and cutoff are positive. Fields unused by a historical equation
are not given invented dynamics.

| Control/keyword | Before | Result / historical equation |
|---|---|---|
| MMC/TLC `pll` | Gains/filter mapped | PI on the filtered q-axis voltage; `ref` was unused. TLC first filters the AC measurement. |
| MMC `p` | Reference and P filter dropped | PI gains, reference policy above, and `n_f`/`ω_f` on measured AC power. |
| TLC `p` | Reference dropped | PI gains and reference policy; historical `p` filter fields are unused. |
| MMC `q` | Reference and Q filter dropped | PI gains, reference policy, and `n_f`/`ω_f` on measured reactive power. The same filter specification independently filters energy feedforward power. |
| TLC `q` | Reference dropped | PI gains and reference policy; historical `q` filter fields are unused. |
| MMC/TLC `dc` | Reference dropped; MMC filter dropped | PI gains and reference policy; `OuterActiveVdcControl(filter=...)` maps `n_f`/`ω_f` locally to the DC PI input. Shared DC measurement remains unfiltered for modulation and MMC energy/zcc feedforward. Filter equilibrium equations remain active; only the PI residual is replaced by solved DC current. |
| MMC/TLC `vac` | Reference and magnitude filter dropped | `OuterReactiveVacControl(filter=...)` filters `sqrt(v_d²+v_q²)` before the PI. Filter states precede `ξ_v_ac`; equilibrium retains their equations and replaces only the PI residual with solved Q. |
| TLC `vac_supp` | Reference dropped | `VoltageSupportLag`: `Δq'=ω_f(Kp(Vref-|V|)-Δq)`, added to Q reference; reference policy above. |
| MMC `vac_supp`, `n_f=1` | Dropped | Exact existing lag equivalent: `Δq=Kp(Vref-H(s)|V|)`, `H(s)=ω_f/(s+ω_f)`. The state transformation is `Δq=Kp(Vref-Vfiltered)` for fixed Vref. |
| MMC `vac_supp`, `n_f=0` or ≥2 | Dropped | Still unsupported; no existing proportional support with this magnitude-filter transfer. Proposal below. |
| MMC/TLC `f_supp` | Dropped | `FrequencySupportLag(Kω=Kp,ωc=ω_f)`: `Δp'=ω_f(-Kp Δω-Δp)`, added to P reference. This is the TLC historical equation; MMC has no historical `f_supp` equation. |
| MMC `occ` | Incorrect frequency factor | PI gains and voltage-feedforward filter retained; decoupling uses nominal frequency, as in the historical MMC equation. |
| TLC `occ` | Extra feedforward filter | PI gains retained; historical `occ.n_f`/`ω_f` unused, so no additional filter. Decoupling uses synchronized frequency. |
| MMC `energy` | Dropped | `TotalEnergyControl`: gains, reference (`[0]`→1), and independent AC-power feedforward using the legacy **q** filter. `energy.n_f`/`ω_f` unused. |
| MMC `zcc` | Dropped | `ZeroSequenceCurrentControl` PI gains and energy-derived reference. `ref`/`n_f`/`ω_f` unused. |
| MMC `ccc` | Dropped | `CirculatingCurrentSuppressionControl`: gains and both pu current references (`[0]`→`(0,0)`), in the −2ω converter frame. `n_f`/`ω_f` unused. |
| TLC `v_meas_filt`, `i_meas_filt` | Mapped | `n_f`/`ω_f` on AC voltage/current components; PI gains and references unused. |
| MMC `v_meas_filt`, `i_meas_filt` | Dropped | Mapped to the existing shared measurement filters; the historical MMC file has no equations for these keywords. |
| MMC/TLC `vdc_droop` | Dropped | Deferred to the separate `DCVoltageSupportLag` change. |

`TotalEnergyControl(power_filter=NoFilter())` retains the existing modular
filtered-power feedforward exactly. A nontrivial filter independently filters
power from measured voltage/current components. The adapter selects the
historical independent feedforward even with no filter, avoiding a cascade
through `p` filtering. `CirculatingCurrentSuppressionControl(ref=(0.0,0.0))`,
`OuterReactiveVacControl(filter=NoFilter())` and
`OuterActiveVdcControl(filter=NoFilter())` likewise retain modular default
results and state counts. Energy filter states precede `ξ_Wtot` and initialize
at the solved active power. VAC filter states initialize at the solved measured
voltage magnitude. DC-controller filter states precede `ξ_v_dc` and initialize
at the solved DC voltage in pu.

## Remaining proposals and comparison limits

| Inputs/path | Disposition and proposed next decision |
|---|---|
| MMC `gfm`, `p=VSE_old`, `vse`, `VI`, `vi` | Existing adapter still builds the GFL differential path; its partial `vse` synchronization is not the historical GFM model. Design a complete mapping of synchronization and differential control together before implementation. |
| `VSE_old.H`, `K_d`, `K_ω`, `ref`, `ref_ω`, `n_f`, `ω_f` | Original `p` VSE path is not mapped. Review inertia/damping/droop, PLL coupling, reference and power-filter ownership together. |
| `VI=CCQSEM`: `Rᵥ`, `Lᵥ`, `ref_vd`, `ref_vq`, `n_f`, `ω_f` | Dropped. Compare the complete historical virtual-impedance and voltage-control path with modular GFM before selecting a public contract. |
| `VI=FFVI`: `Rᵥ`, `Lᵥ`, `TVR`, `ω_ₜᵥᵣ`, `ref_vd`, `ref_vq` | Dropped. Review the transient virtual-resistance and voltage-feedforward equations as a complete GFM path. |
| MMC static/higher-order `vac_supp` | Propose a separately approved proportional support block with an optional magnitude filter, rather than replacing its transfer by a first-order lag. |
| TLC `Lₐᵣₘ`, `Rₐᵣₘ` | Dropped. Old power flow combines arm/reactor terms while dynamics use only `Lᵣ`/`Rᵣ`; decide the physical partition before adding an equivalent. |
| TLC `energy`, `zcc`, `ccc` | No historical TLC Σ plant/equations; no equivalent mapping proposed. Decide whether unsupported inputs should be rejected explicitly. |
| `PI_control.bandwidth`, `ζ` | No automatic tuning restored. The old TLC zero-gain `occ` tuning refers to undefined `Lₑ`/`Rₑ`; choose reactor/base semantics or require explicit gains. |
| `occ.ref` | Historical current-state initial guess, overwritten in TLC; outer loops own the dynamic current reference. No new reference API or alternate initialization policy introduced. |
| `PI_control.Kₚ`, `Kᵢ`, `ref`, `n_f`, `ω_f` | Mapped where consumed above; other fields remain unused exactly where their old equations ignore them. |
| TLC `debug` | Dropped solved-state storage; use the separately planned internal steady-state accessor rather than mutable compatibility output fields. |
| Arbitrary `Controller`-valued keywords | Historically stored even without an equation. Propose explicit unsupported-input diagnostics, rather than inventing behavior. |
| Defaults, derived-base overrides, non-50-Hz normalization | Retain current adapter contract; make each compatibility/physics choice separately. |

### Intended TLC PLL difference

The TLC PLL always receives `meas.vG_q_f`, including when its own filter is
`NoFilter()`. This is the modular convention validated against PSCAD. In the
historical TLC, disabling the PLL filter selects raw `Vᴳq`, bypassing an active
AC measurement filter. The adapter deliberately retains the modular convention;
no selector keyword is introduced. For raw q voltage 0.2 pu, measured q voltage
0.1 pu, `Ki=7`, `Kp=0.3` and zero PLL integral, the modular integral derivative
is −0.7000000000000001 pu/s and frequency is 0.97 pu; the historical bypass gives
−1.4000000000000001 pu/s and 0.94 pu. An adapter test preserves the selected
filtered input. At steady state a unity-gain measurement filter removes this
particular difference, while the dynamic admittance can differ.

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
negates its Q argument; a comparison must therefore pass the negative of the
modular setpoint to that reference function. Nonzero-Q historical fixtures
exercise this conversion as well as the missing/conflicting-reference cases.

The independent MMC reference test restores the generated-expression callbacks
already present in the old source, removing its later nested callback with
out-of-scope variables. It changes no historical equation, gain or solver
setting. It compares physical states and terminal admittances with no filters
and with distinct second-order p/q filters, nonzero CCC references, energy
reference 1.1 and nonzero Q. Filter states use different realizations, so their
transfer functions and transformed equations are compared, not their raw coordinates.
TLC comparisons use both independent stored validation datasets, including
P-frequency and DC/Q-voltage support, measurement/PLL filters and modulation
delay; their existing acceptance limits are retained.

PSCAD rejects any non-`NoFilter` VAC or DC-voltage outer-control filter as
“not yet exportable” before recovering its equilibrium. Its Σ generator also
needs a separate review for nontrivial energy `power_filter` and nonzero CCC references: the current
canonical generator assumes the default equations. No new Σ exporter support
is implemented here.
