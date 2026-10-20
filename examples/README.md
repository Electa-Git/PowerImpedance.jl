# Examples

Each script is a tutorial that the documentation renders under
[Examples](https://electa-git.github.io/PowerImpedance.jl/stable/).
Use an environment with PowerImpedance and CairoMakie, and GraphMakie for the
diagram tutorials. Check each script's `using` lines for its dependencies.
Run a script from the repository root with
`julia --project=<env> examples/<file>.jl`.

- `Connection_DSL.jl`: connect element terminals with named rows.
- `Line_and_cable_models.jl`: calculate overhead-line and cable impedances.
- `IEEE9_bus_impedance.jl`: compare bus impedance with and without an MMC.
- `IEEE39bus.jl`: build the New England system and study its STATCOM at Bus 9.
- `Network_Diagram.jl`: draw a hybrid AC/DC network with its solved operating point.
- `P2P_HVDC_ALT.jl`: vary overhead-line and underground-cable lengths in an HVDC link.
- `P2P_HVDC_stability.jl`: calculate HVDC admittance and AC-terminal stability.
- `MMC_harmonic_stability.jl`: study harmonic stability of an MMC link.
- `Energy_hub_MTDC.jl`: calculate impedance at a three-terminal DC energy hub.
- `GFM_weak_grid.jl`: compare grid and grid-forming MMC impedances.
- `Converter_machine_interaction.jl`: study converters and a synchronous machine.
- `IEEE39bus_Gridspace.jl`: vary soil resistivity and compare bus impedances.
- `SmallSignal_Gridspace.jl`: calculate small-signal stability over parameter samples.
