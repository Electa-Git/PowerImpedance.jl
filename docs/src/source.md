```@meta
CurrentModule = PowerImpedance
```

# Voltage sources

`ac_source(; v, theta, p, q)` returns an immutable, ideal three-phase source
with one `ac = Port(ACABC)` port. `dc_source(; v, p)` returns an ideal DC source
with one `dc = Port(DC_CM)` port. Source inputs use physical units. Voltages are in kV, with phase-peak values for AC and
pole-to-pole values for DC. Angles use rad, and powers use MW and MVAr.

```@example sources
using PowerImpedance

ac = ac_source(v = 380sqrt(2/3), theta = 0.0, p = 100.0, q = 0.0)
dc = dc_source(v = 640.0, p = 100.0)
limited = component(ac; limits = PowerImpedance.Limits(P_max = 200.0))
changed = withinputs(dc; v = 650.0)
(inputvalues(dc), inputvalues(changed))
```

Set source limits through `component`. The source constructors accept only their
declared physical inputs. `inputs(source)` describes those inputs, while
`inputvalues(source)` gives their configured values. `bases(source)` returns
`nothing`.

The source's configured `p` and `q` use generator output targets for power flow.
Solved `ACPortValues` and `DCPortValues` report power into the source:
a source delivering 900 MW has `p = -900` at its port.

Connect an AC source to a bus with `domain = ACDQ` when the external network
uses dq coordinates. The builder applies the coordinate transform from the bus.
Its ideal perturbation voltage is zero, so source nets are grounded in the
frequency-domain network model. Source uncertainty changes the operating point.
Gridspace repeats the required calculations for each sampled source.

See [`ac_source`](@ref), [`dc_source`](@ref), and
[Component definitions and inputs](components.md), and
[Network construction](network.md).
