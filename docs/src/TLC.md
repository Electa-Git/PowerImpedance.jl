```@meta
CurrentModule = PowerImpedance
```

# Two-level converter

`tlc` constructs a two-level voltage-source converter from its electrical
model and selected measurement, synchronization, control, modulation, and delay
blocks. The same AC/DC power-flow, nonlinear-equilibrium, and small-signal
linearization sequence used for MMCs applies to the detailed TLC model.

Gridspace accepts deterministic or uncertain values in the corresponding
constructor tree. Because a changed converter can change the operating point,
every numeric sample is solved and linearized before its response is included
in statistics.

See [`tlc`](@ref), [`TLC`](@ref), and the exported control types in the
[API reference](reference.md).
