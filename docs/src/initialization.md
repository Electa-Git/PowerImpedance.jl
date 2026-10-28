```@meta
CurrentModule = PowerImpedance
```

# Power-flow initialization

Power-flow initialization provides the steady-state terminal values used to
linearize nonlinear converter and machine models. Use it before calculating a
frequency response that includes those models. A network made only from linear
sources and passive components can be linearized without a solved operating
point.

## Solve and reuse an operating point

An explicit power-flow request always solves the network, including a network
of sources and passive components. Reuse the result when linearizing so the
frequency-domain model uses the same operating point:

```julia
power_flow = compute(PowerFlowProblem(network), ACDCPowerFlow())
linearized = compute(
    LinearizationProblem(network, power_flow),
    AdmittanceLinearization(),
)
```

If nonlinear models need an operating point and you omit it, the network is
solved before linearization. `NetworkBuilder.solve(network)` is a shorthand
for an explicit solve.
The [Getting started tutorial](examples/Getting_started_SMIB.md) shows this
sequence in a complete network.

## Inspect solved values

`PowerFlowResult.operating_point` stores values by component and port. Read
`power_flow.operating_point[:machine].ac.p` or
`power_flow.operating_point[:converter].dc.v`. AC voltage is phase-peak kV,
DC voltage is pole-to-pole kV. Angles are rad, and powers are MW or MVAr.

Port powers are positive into a component. A source or generator delivering
900 MW has `ac.p = -900`. A motor absorbing 916 MW has `ac.p = 916`. A converter
receiving 603 MW from DC and delivering 600 MW to AC has `dc.p = 603` and
`ac.p = -600`.

The result also contains solver status and diagnostics. Check these values when
the solve does not converge before calculating an impedance response.

## Choose setpoints and references

Setpoints use the units of the component model:

| Component | Setpoint units | Where to configure |
|:--|:--|:--|
| AC or DC source | kV, rad, MW, MVAr | Constructor keywords `v`, `theta`, `p`, and `q` |
| Synchronous machine | Per unit on machine bases | Constructor `powerflow = (p, q, v)` |
| MMC or TLC | Per unit on converter bases | `powerflow` input tree and selected control-loop references |
| Induction machine | Electrical loading from its mechanical model | `MechanicalIM` constructor values |

For MMC and TLC models, the selected control loop supplies the quantity it
controls. `OuterActivePowerControl.p_ref` sets AC active power,
while `OuterActiveVdcControl.v_dc_ref` sets DC voltage. A stored setpoint for a
quantity controlled by a loop does not replace its reference. The component
guides describe their selected inputs and bases: [sources](source.md),
[machines](machines.md), [MMC](MMC.md), and [TLC](TLC.md).

Use `inputs(model)` to inspect declared input names and units, and
`inputvalues(model)` to inspect configured values. See
[Component definitions and inputs](components.md) for copy-based updates.

## Repeated and parametric calculations

Each materialized Gridspace configuration performs its required power-flow
solve before linearization. Changed passive parameters can change the solved
voltages and powers. See [Parametric and uncertainty studies](gridspace.md)
for deterministic and Monte Carlo workflows.

For detailed branch and converter equivalents, and the equations used to
initialize component states, see [Fundamental concepts](manual/fundamental_concepts.md).
