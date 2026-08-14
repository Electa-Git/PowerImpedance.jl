```@meta
CurrentModule = PowerImpedance
```

# Transformer

`transformer` represents a single-phase or balanced three-phase transformer as
a cascade of primary winding impedance, excitation branch, ideal turns ratio,
secondary winding impedance, and optional capacitive paths.

The model can be specified directly from its equivalent-circuit parameters or
derived from open-circuit and short-circuit test data. Three-phase construction
supports the organizations implemented by the scalar constructor. The
frequency-dependent winding option scales winding resistance relative to the
model's reference frequency.

For power flow, the detailed ABCD model is converted to the corresponding
balanced branch tap, series admittance, and shunt admittance. Frequency-domain
analysis continues to use the detailed transformer model.

See [`transformer`](@ref) for the current fields, units, supported
organizations, and constructor modes.
