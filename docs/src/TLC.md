```@meta
CurrentModule = PowerImpedance
```

# Two-level converter

`tlc` returns a `TLC` model assembled from electrical, measurement,
synchronization, control, modulation and delay blocks. It declares
`ac = Port(ACDQ)` and `dc = Port(DC_CM)`.

```@example tlc_inputs
using PowerImpedance

converter = tlc(
    sync = PLLSynchronization(),
    outerActive = OuterActivePowerControl(),
    outerReactive = OuterReactiveQControl(),
    innerCurrent = InnerCurrentPIControl(),
)
b = bases(converter)
configured = withinputs(converter;
    outerActive = (p_ref = 100.0/b.S,),
    outerReactive = (q_ref = 0.0,),
    powerflow = (v_ac = 1.0, v_dc = 1.0),
)
inputvalues(configured).outerActive
```

References and converter power-flow setpoints are per unit on `bases(converter)`.
`BaseValues` reports MVA, phase-peak AC kV, pole-to-pole DC kV, and rad/s.
`inputs` describes the nested input tree selected by the control blocks.
`inputvalues` returns the configured values. `component` also accepts replacement
limits. TLC `Limits` use MW and MVAr for power-flow bounds.

The `powerflow` group contains `p_ac`, `q_ac`, `v_ac`, `p_dc` and `v_dc`.
Selected loops supply their controlled quantities. Remaining quantities use the
stored setpoints. A setpoint for a quantity already supplied by a loop warns and is
ignored during target selection. `powerflow.p_dc` is positive into the DC port.

After power flow, `op[:c1]` contains physical values at `ac` and `dc` for a
converter named `c1`. Powers are positive into each port. A converter receiving
603 MW from DC and delivering 600 MW to AC has `dc.p = 603` and `ac.p = -600`.
`linearize(converter, op[:c1])` returns `A, B, C, D`, and
`steady_state(converter, op[:c1])` returns the converged state. The detailed
control equations use the solved terminal values. Configured copies have a
fresh linearization cache.

Gridspace accepts deterministic and uncertain values in the constructor tree.
A numeric sample is solved and linearized before its response contributes
to the statistics. See [`tlc`](@ref), [`TLC`](@ref), and
[Power-flow initialization](initialization.md).
