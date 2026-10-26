```@meta
CurrentModule = PowerImpedance
```

# Modular multilevel converter

`mmc` constructs an `MMC` model from electrical, measurement, synchronization,
control, modulation and delay blocks. It declares `ac = Port(ACDQ)` and
`dc = Port(DC_CM)`. Grid-following and grid-forming configurations use the
exported control types.

## Configure references

```@example mmc_inputs
using PowerImpedance

converter = mmc(
    sync = PLLSynchronization(),
    delta_control = ΔdqControlGFL(
        outer_active = OuterActivePowerControl(),
        outer_reactive = OuterReactiveQControl(),
        occ = InnerCurrentPIControl(),
    ),
    sigma_control = ΣdqzControlTEC(),
)
b = bases(converter)
configured = component(converter;
    delta_control = (
        outer_active = (p_ref = 100.0/b.S,),
        outer_reactive = (q_ref = 0.0,),
    ),
    powerflow = (v_ac = 1.0, v_dc = 1.0),
)
inputvalues(configured).delta_control.outer_active
```

Control references and the `powerflow` group use per-unit values on
`BaseValues(S, v_ac, v_dc, omega)`: MVA, phase-peak kV, pole-to-pole kV, and
rad/s. `inputs(converter)` describes the selected nested input tree with
`Input` leaves. `inputvalues` gives configured values. `withinputs` changes
references in a copy, and `component` can also replace `limits`.

The `powerflow` group declares `p_ac`, `q_ac`, `v_ac`, `p_dc` and `v_dc`.
A selected loop supplies the quantity it controls. Other quantities use the
stored setpoints. Setting a setpoint already supplied by a loop warns and leaves the
loop reference in use. `powerflow.p_dc` is positive into the DC port.
MMC power bounds interpret `Limits` as per unit on `b.S`.

## Solved values and linearization

Power flow supplies physical `ACPortValues` and `DCPortValues`. For a converter
named `c1`, `op[:c1].ac.p` is AC power into the converter, while
`op[:c1].dc.p` is DC power into it. A converter receiving 603 MW from DC and
delivering 600 MW to AC has `dc.p = 603` and `ac.p = -600`.

`linearize(converter, op[:c1])` solves the detailed nonlinear equilibrium and
returns a `StateSpaceLinearization` with the converged `state` and continuous-time
`system`. `steady_state(converter, op[:c1])` computes the equilibrium without
forming the electrical system. Each call uses the solved terminal values and leaves
the model unchanged.
Electrical and control uncertainty is sampled before power flow, equilibrium,
and linearization. Each numeric sample repeats those calculations.

See [`mmc`](@ref), [`MMC`](@ref), and the [API reference](reference.md).
