```@meta
CurrentModule = PowerImpedance
```

# Network construction

Component constructors return models directly. Store them in a NamedTuple whose
keys identify the components, then connect their ports with
`NetworkBuilder.Bus` or `NetworkBuilder.Net`. `define` returns a `NetworkState`
containing these models, the expanded topology, and numerical options.

## Models and named ports

`electricalconnections(model)` returns a NamedTuple of `Port` declarations.
Each port has an electrical domain and an ordered tuple of terminal labels:

| Domain | Terminal labels | Coordinates |
|:--|:--|:--|
| `ACABC` | `(:a, :b, :c)` | Three-phase AC |
| `ACDQ` | `(:d, :q)` | Rotating AC frame |
| `DC_CM` | `(:dc,)` | Differential DC voltage and current |

Two-port passives use `side1` and `side2`. An AC source or machine uses `ac`,
a DC source uses `dc`, and a converter declares `(ac, dc)`. Three-conductor
passives and AC sources declare `ACABC`. Converters and machines declare `ACDQ`.
One- and two-conductor passives expose one differential `DC_CM` port per end.
An AC source always represents three phases.

```@example network
using PowerImpedance
using PowerImpedance.NetworkBuilder: Bus, Net, define, solve

branch = impedance(z = s -> 0.19 + s * 0.0122, conductors = 3)
electricalconnections(branch)
```

## Buses and individual nets

`Bus` connects complete ports and expands into one net per coordinate. An AC
bus uses dq when any attached port declares `ACDQ`, or when `domain = ACDQ`
is supplied. Otherwise it uses abc. The builder transforms `ACABC` models
attached to an `ACDQ` bus. An `ACDQ` port on an explicitly declared `ACABC` bus
raises `ArgumentError`, as does a bus mixing AC and DC ports. All AC ports of
one component must use the same frame.

```@example network
elements = (
    grid = ac_source(v = 380sqrt(2/3)),
    branch = branch,
    load = impedance(z = 400.0, conductors = 3),
)
topology = (
    Bus(:B1; ports = ((:grid, :ac), (:branch, :side1)), domain = ACDQ),
    Bus(:B2; ports = ((:branch, :side2), (:load, :side1)), domain = ACDQ),
    Bus(:gnd; ports = ((:load, :side2),), domain = ACDQ),
)
network = define(elements, topology; options = (; voltageBase = 380/sqrt(3)))
network.topology.connections
```

This topology has nets `B1d`, `B1q`, `B2d`, `B2q`, `gndd`, and `gndq`.
A DC bus retains its supplied name. Names starting with `gnd` connect to ground.
Ideal sources and single-port machines need only their external port. Ideal
source nets also have zero perturbation voltage in frequency-domain analysis.
A three-phase `:ΔY` transformer requires an `ACDQ` bus.

`Net` joins individual terminals with `(component, port, terminal)` triples.
Use the terminal labels declared by the ports:

```@example network
dc_elements = (
    branch = impedance(z = 2.0, conductors = 1),
    load = impedance(z = 10.0, conductors = 1),
)
dc_topology = (
    Net(:DC1; terminals = ((:branch, :side1, :dc), (:load, :side1, :dc))),
    Net(:gnd; terminals = ((:branch, :side2, :dc), (:load, :side2, :dc))),
)
dc_network = define(dc_elements, dc_topology)
nothing # hide
```

`NetworkTopology` stores `net`, `bus`, `component`, `port`, `terminal`, `domain`
and `frame` columns. Bus 0 denotes ground. Other buses follow the first stored
row, with AC and DC numbering assigned separately. Construction rejects missing
components or ports, invalid terminal labels, duplicate terminal assignments,
and inconsistent frames.

Use `define(elements, topology; exclude = (:g2,))` to omit named components and
their topology entries. An included model with no topology reference raises
`ArgumentError`. Exclusions produce an informational message.

## Inputs, bases and limits

`inputs(model)` returns nested input declarations with `Input` leaves. Each
leaf records `default`, `unit`, `type` and `description`. The tree follows the
selected control blocks, including empty groups. `inputvalues(model)` returns
the same tree with the configured values at its leaves.

```@example network
source = ac_source(v = 380sqrt(2/3))
declaration = inputs(source).v
(declaration.default, declaration.unit, declaration.type, declaration.description)
```

`withinputs` makes a configured copy from partial nested NamedTuples. It converts
values to their declared types and reports unknown keys with their full path.
`component(model; limits = nothing, inputs...)` also replaces stored limits when
requested. The original model is unchanged. Unchanged sub-blocks are reused.
Configured state-space models start with a fresh linearization cache.

```@example network
configured = component(source; v = 390sqrt(2/3),
    limits = PowerImpedance.Limits(P_max = 1000.0))
(inputvalues(source).v, inputvalues(configured).v, limits(configured).P_max)
```

Converter control references and power-flow setpoints are per unit on `bases(model)`.
`BaseValues` contains `S` in MVA, `v_ac` in phase-peak kV, `v_dc` in pole-to-pole
kV, and `omega` in rad/s. AC-only machines have `v_dc = nothing`. Sources,
passives and the scan-based MMC return `nothing` from `bases`.
Source inputs use physical kV, rad, MW and MVAr. The scan-based MMC also uses
physical power-flow inputs. See the [MMC](MMC.md), [TLC](TLC.md), and
[source](source.md) pages for configuration examples.

`limits(model)` returns the stored `Limits`, or `nothing` for a model without
limits. MMC power bounds use per-unit limits. Source, TLC, scan-based MMC and
synchronous-machine limits use MW and MVAr. These model-specific conventions
also apply when configuring a copy.

## Power flow and per-port values

```@example network
powerflow = compute(PowerFlowProblem(network), ACDCPowerFlow())
op = powerflow.operating_point
(op[:grid].ac.v, op[:grid].ac.p)
```

An explicit `PowerFlowProblem` always solves, including networks containing only
sources and passives. `solve(network)` returns the same `PowerFlowResult` type.
The result retains `result`, `data`, `nodes2bus`, `elem2comp`, diagnostics, and
an `OperatingPoint`. The state retains the converged solver starting values for
later solves. The calculated `OperatingPoint` belongs to the result.

`OperatingPoint.values` stores a NamedTuple per non-passive component, keyed by
port name. AC ports use `ACPortValues(v, theta, p, q)` in phase-peak kV, rad, MW
and MVAr. DC ports use `DCPortValues(v, p)` in pole-to-pole kV and MW. Access a
converter's values with `op[:c1].ac.p` or `op[:c1].dc.v`.
`get(op, :missing, nothing)` returns `nothing` for an absent component.

Power and signed current are positive into the component at each port, as in
`Y = I_in / V`. A source delivering 900 MW has `ac.p = -900`. A motor drawing
916 MW has `ac.p = 916`. A converter receiving 603 MW from DC and delivering
600 MW to AC has `dc.p = 603` and `ac.p = -600`. Reactive power uses the same
rule. `PowerImpedance.current(values)` returns an unsigned AC peak-current
magnitude or a signed DC current, in kA. Unknown AC reactive power is `NaN`.

## Calculation sequence

```@example network
linearized = compute(LinearizationProblem(network, powerflow),
    AdmittanceLinearization())
model = linearized.network_model
response = compute(PowerImpedanceProblem(model;
    nodes = [:B2d, :B2q], frequency_range = (1.0, 1e3, 20)), NodalImpedance())
size(response.response)
```

`LinearizationProblem(network, powerflow)` uses that exact result.
Without an explicit result, power flow is calculated before the nonlinear
models are linearized. A network containing only linear models uses an empty operating point.
Starting a frequency-response calculation from `NetworkModel` directly evaluates
its admittances. Starting from `NetworkState` first performs the required
power flow and linearization.

For an individual state-space model, `linearize(model, values)` computes
`A, B, C, D` from physical per-port values and stores the converged state.
`steady_state(model, values)` reuses that state when the values compare equal
with `isequal`. Otherwise it recomputes. See [Power-flow initialization](initialization.md)
and [Impedance and stability analysis](results.md).

`define` returns a `Gridspace{NetworkState}` when a component or direct option
contains a grid. Each numeric realization uses its own topology and inputs.
The [Gridspace guide](gridspace.md) describes deterministic and uncertain studies.

## Single-line network diagrams

Network diagrams are provided by the optional GraphMakie extension. Install and
load `GraphMakie`, `Graphs`, and `NetworkLayout` together with one Makie backend.
These packages are weak dependencies.

```julia
using PowerImpedance
using PowerImpedance.NetworkBuilder: Bus, Net, define
using GraphMakie
using Graphs
using NetworkLayout
using CairoMakie

view = diagram(network; interactive = false)
view.figure
```

`diagram(network)` projects `network.topology.connections` into a deterministic
bipartite layout: physical buses and named PowerImpedance components are both
vertices. AC and DC bus numbers remain distinct through their `(domain, bus)`
identity, transformed conductor coordinates aggregate at one busbar, parallel
components remain separate, and each component shows its ground connections.

If power flow has already been computed, pass the completed result explicitly:

```julia
powerflow = compute(PowerFlowProblem(network), ACDCPowerFlow())
view = diagram(network, powerflow; interactive = false)
```

The network supplies topology, component names, ports, terminals, and net names. The
supplied `PowerFlowResult` enriches that projection from its retained
`data`, `result`, `nodes2bus`, and `elem2comp` payloads. A result whose mappings
do not agree with the network raises an error.

The returned handle exposes `figure`, `axis`, `plots`, `model`, and resolved
`positions`. `selected` is a Makie `Observable` whose value is `nothing`, a bus
key, or a component key. `details` is another `Observable` with structured bus
or component information suitable for an external side panel. Component details include
`grounded_ports` and `terminal_rows`. Each terminal row uses `port` for its
port name. The `operating_point` entry contains per-port values. With an
interactive backend, clicking a bus or component updates both observables.

The same renderer is available as the `NetworkDiagramDefinition` PlotBuilder
recipe:

```julia
handles = PowerImpedance.plot(
    network,
    powerflow;
    display_plot = false,
    open_export = false,
)
ui = only(handles)
diagram_view = ui.artifacts[:network_diagram]
```

This form retains PlotBuilder's responsive layout, reset-view button, status
line, and SVG export button. A legend beside the axis identifies each type of bus,
branch and component shown, and the figure grows to keep the diagram size.
Network diagrams have no logarithmic axis control. By default,
`figure_size = :auto` fits the initial diagram area to the aspect of the resolved
layout. Pass an explicit `(width, height)` tuple to override it.
`diagram_view` is the same extension-owned handle returned by `diagram`,
including `selected` and `details`. Use `graph_layout` for a NetworkLayout
algorithm because PlotBuilder reserves `layout` for its page layout.

CairoMakie exports the same figure through ordinary Makie functions:

```julia
save("network.svg", view.figure)
```

For browser rendering, activate WGLMakie. The same diagram construction produces
a figure that a Bonito application can embed:

```julia
using WGLMakie
using GraphMakie

view = diagram(network, powerflow)
view.figure
```

The complete executable [Hybrid AC/DC network diagram](https://github.com/Electa-Git/PowerImpedance.jl/blob/main/examples/Network_Diagram.jl)
builds a small two-bus AC/two-bus DC example with a converter, AC and DC
branches, a source, and a grounded load.

## Migrating from Element and Setpoint

Replace the component wrapper and its operating targets with a model and declared
inputs. The following blocks marked as text show the former API.

Before:

```text
source = ac_source(setpoint = Setpoint(Vac = 310.0, Pac = 100.0),
    pins = 3, transformation = true)
branch = impedance(z = 400.0, pins = 3, transformation = true)
connections = (
    (node = :busd, element = :source, side = 1, terminal = 1),
    (node = :busq, element = :source, side = 1, terminal = 2),
    (node = :busd, element = :branch, side = 1, terminal = 1),
    (node = :busq, element = :branch, side = 1, terminal = 2),
    (node = :gndd, element = :branch, side = 2, terminal = 1),
    (node = :gndq, element = :branch, side = 2, terminal = 2),
)
state = define((; source, branch), connections;
    options = (; voltageBase = 310.0/sqrt(2)))
```

After:

```@example network
source = ac_source(v = 310.0, p = 100.0)
branch = impedance(z = 400.0, conductors = 3)
connections = (
    Bus(:bus; ports = ((:source, :ac), (:branch, :side1)), domain = ACDQ),
    Bus(:gnd; ports = ((:branch, :side2),), domain = ACDQ),
)
state = define((; source, branch), connections;
    options = (; voltageBase = 310.0/sqrt(2)))
migration_powerflow = solve(state)
migration_powerflow.operating_point[:source].ac.p
```

A source's `p` input is its generated power, as `Pac` was, while its solved
`ac.p` is power into the source and is negative when it delivers power.

Move converter references into the selected control-block input tree. Divide
physical references by the appropriate model base. Use `exclude` for omitted
components, let the bus select the frame, and use symbol terminal labels in
`Net`. Read the power-flow result from `PowerFlowResult`:

Before:

```text
network = @network begin
    g1 = ac_source(setpoint = Setpoint(Vac = 310.0))
end
power_flow(network)
network.elements[:g1].setpoint.Pac
```

After:

```@example network
powerflow.operating_point[:grid].ac.p
```

Read results by port and apply the inward power sign. Replace component updates
with `linearize` or `steady_state`, and use `ZToolProbe(...; port = :ac)` for a
converter scan. Public functions and types are listed in the [API reference](reference.md).
