# Examples

The documentation renders the tutorials below under
[Examples](https://electa-git.github.io/PowerImpedance.jl/stable/).
Models are the components. Configure their references and power-flow seeds with
`component`, connect named ports with `NetworkBuilder.Bus` or `Net`, and pass the
components and topology to `NetworkBuilder.define`.
Control references use per unit on `bases(model)`. Source inputs use physical units.
`compute(PowerFlowProblem(state), ACDCPowerFlow())` returns per-port operating values,
with power positive into each component.

Run a script from the repository root with
`julia --project=docs examples/<file>.jl`. The documentation environment includes
CairoMakie and GraphMakie. Check each script's `using` lines for other dependencies.

- `Connection_DSL.jl`: connect component ports with buses and individual terminals with nets.
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

`PSCAD_tutorial.jl` is displayed as static code. Its first three sections build the
network, solve power flow and export a local project. Later sections run PSCAD and
Z-tool using the configured station. Execute them when that station is available.
The exporter requires PythonCall in the active environment.

The research studies `P2P_HVDC_Gridspace.jl` and `Gridspace_uncertainty.jl` run
standalone and are kept outside the documentation build. They study converter and
cable uncertainty, and deterministic and uncertain impedance calculations.
