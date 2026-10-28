```@meta
CurrentModule = PowerImpedance
```

# Synchronous and induction machines

Both machine models connect through an AC port in dq coordinates. Use a
synchronous machine when rotor, excitation, and governor dynamics are part of
the study. Use an induction machine for a rotor-flux and mechanical-load model.

## Synchronous machine

`synchronousmachine` combines an electrical circuit, shaft and turbine model,
governor, and AVR. The three-phase power base `S_base` is in MVA. The voltage
base `Vᵃᶜ_base` is line-to-line RMS in kV. The nominal frequency `ωn` is in
rad/s. Electrical-circuit parameters use the machine per-unit bases.

```@example machines
using PowerImpedance

machine = synchronousmachine(
    S_base = 1000.0,
    Vᵃᶜ_base = 220.0,
    ωn = 100π,
    elec = ElectricalSM(rt = 0.0026, lt = 0.065),
    mech = MechanicalSM(H = 4.0),
    avr = AVRSM(v_ref = 1.01),
    gov = GovernorSM(R = 0.05),
    powerflow = (p = 0.5, q = 0.0, v = 1.0),
)
(electricalconnections(machine), inputvalues(machine))
```

The `(p, q, v)` power-flow targets use per-unit values on the machine base.
Here `p` is generator output. The solved `ac.p` in `OperatingPoint` is power
into the machine, so it has the opposite sign. Power flow supplies the
terminal phasor used to initialize the electrical and control states. See
[Power-flow initialization](initialization.md).

## Induction machine

`inductionmachine` combines the electrical rotor model and a mechanical load.
Set the power and voltage bases with `S_base` and `Vac_base`. Give `ωn` in
rad/s. Configure the load through `MechanicalIM` and its reference torque
`T_0`.

```@example machines
motor = inductionmachine(
    S_base = 1000.0,
    Vac_base = 220.0,
    ωn = 100π,
    elec = ElectricalIM(),
    mech = MechanicalIM(T_0 = 0.9),
)
electricalconnections(motor)
```

Induction-machine loading follows its mechanical torque. The model has no
declared `inputs` tree. Inspect and configure its electrical and mechanical
parameters through the constructor. Its solved `ac.p` is positive when the
motor absorbs power.

See [`synchronousmachine`](@ref), [`inductionmachine`](@ref),
[`ElectricalSM`](@ref), [`MechanicalSM`](@ref),
[`ElectricalIM`](@ref), and [`MechanicalIM`](@ref) for complete parameters.
