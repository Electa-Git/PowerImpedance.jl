```@meta
CurrentModule = PowerImpedance
```

# Modular multilevel converter

`mmc` constructs a modular multilevel converter from its electrical plant,
measurement paths, synchronization, inner controls, outer controls, modulation,
and delay models. Both grid-following and grid-forming configurations can be
assembled from the exported controller objects.

The converter's power-flow representation determines its AC/DC steady-state
operating point. The detailed nonlinear model is then equilibrated and
linearized for frequency-domain evaluation. Electrical and controller
uncertainty is sampled before these steps. A sampled converter causes the
package to repeat power flow, equilibrium, and linearization.

The high-level [`mmc`](@ref) constructor remains available for existing models.
The composable [`MMC`](@ref), controller, synchronization, modulation, and
measurement types are listed in the [API reference](reference.md). The
[P2P HVDC Gridspace tutorial](examples/P2P_HVDC_Gridspace.md) studies how the
OHL/UGC split, cable geometry, and converter tolerances move resonances.
