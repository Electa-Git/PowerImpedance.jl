```@meta
CurrentModule = PowerImpedance
```

# Voltage sources

`ac_source` and `dc_source` define ideal voltage-source equivalents and their
power-flow setpoints. They are single electrical ports internally, while the
classic element representation retains input and output pin groups for network
compatibility.

An AC source can represent a one-phase or three-phase grid equivalent. Its
`Setpoint` contains the voltage and active/reactive power targets, and `Limits`
contains the corresponding operating bounds. A DC source provides the DC
voltage and active-power operating conditions for a DC grid. For both sources
and converters, `Setpoint.Vdc` is the pole-to-pole DC voltage in kV. The legacy
DC source field `V` uses the same convention. Callers that previously halved
the pole-to-pole voltage must pass it without halving.

Use `transformation=true` for a supported three-phase source whose external
network variables are expressed in transformed coordinates. Source uncertainty
changes the operating-point context, so Gridspace repeats power flow and
linearization for every sampled source.

See [`ac_source`](@ref), [`dc_source`](@ref), [`Setpoint`](@ref), and the
[API reference](reference.md) for the current signatures.
