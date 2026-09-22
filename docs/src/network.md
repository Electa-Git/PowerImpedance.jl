```@meta
CurrentModule = PowerImpedance
```

# Network construction

A PowerImpedance system contains named component `Element` objects and an
explicit node–terminal incidence relation. `NetworkBuilder.define` constructs a
`NetworkState` from ordinary numeric elements, connection rows, and numerical
options.

## NetworkBuilder connection rows

Import the construction names used by the model:

```julia
using PowerImpedance
using PowerImpedance.NetworkBuilder: Grid, NetworkTopology, define, solve
```

Each row identifies one connected terminal:

```julia
connections = (
    (node = :bus, element = :branch, side = 1, terminal = 1),
    (node = :gnd, element = :branch, side = 2, terminal = 1),
)
```

The fields have the following meanings:

- `node` is the explicit node name;
- `element` selects an entry in the element named tuple;
- `side` selects a physical element side, starting at 1;
- `terminal` selects a conductor or transformed coordinate on that side,
  starting at 1.

Repeated node names form multiway electrical connections. Input-row order and
the first occurrence of each node determine stored row and node order. AC and
DC bus indices are assigned independently from the component port definitions.
Sources, machines, converters, transformed components, and multiconductor
components define their domain directly. A one-conductor impedance or line has
no intrinsic AC/DC marker; its domain is inferred from fixed-domain terminals
in the same connected network. If none is present, the established DC
interpretation is used. An inferred scalar AC passive model can be used in
frequency-domain calculations, but power flow requires the corresponding
transformed three-phase element.

```julia
elements = (
    branch = impedance(z = 2.0, pins = 1),
    load = impedance(z = 10.0, pins = 1),
)

connections = (
    (node = :bus, element = :branch, side = 1, terminal = 1),
    (node = :bus, element = :load, side = 1, terminal = 1),
    (node = :gnd, element = :branch, side = 2, terminal = 1),
    (node = :gnd, element = :load, side = 2, terminal = 1),
)

network = define(elements, connections)
solution = solve(network)
```

`define` returns a scalar `NetworkState` when every element is scalar and a
`Gridspace{NetworkState}` when an element or option contains a deterministic or
uncertain grid. Deterministic topology alternatives are separate states.
Stochastic topology changes within one Monte Carlo case are rejected.

`NetworkTopology` stores typed columns for the node, electrical-domain bus,
element, side, terminal, and domain. Construction rejects unknown elements,
invalid sides or terminals, duplicate terminal assignments, and node names
shared by AC and DC terminals. Rows referring to an element with
`connection=false` are omitted.

Ideal sources and single-port machines use their physical external terminals.
They do not require artificial ground-side rows. During small-signal
construction, an ideal source terminal is included in the grounded-node
selection because the perturbation voltage of an ideal voltage source is zero.

The complete executable [Connection DSL](examples/Connection_DSL.md) tutorial
covers AC, DC, transformed d/q, multiconductor, converter, machine, multiway,
ground and Gridspace cases.

## Single-line network diagrams

Network diagrams are provided by the optional GraphMakie extension. Install and
load `GraphMakie`, `Graphs`, and `NetworkLayout` together with one Makie backend;
they are weak dependencies and are not loaded by core PowerImpedance.

```julia
using PowerImpedance
using PowerImpedance.NetworkBuilder: define
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
components remain separate, and ground is represented on the component rather
than as one global bus vertex.

If power flow has already been computed, pass the completed result explicitly:

```julia
powerflow = compute(PowerFlowProblem(network), ACDCPowerFlow())
view = diagram(network, powerflow; interactive = false)
```

Rendering never solves or reconverts the network. The network remains the
source of topology, element identity, sides, terminals, and node names. The
supplied `PowerFlowResult` only enriches that projection from its retained
`data`, `result`, `nodes2bus`, and `elem2comp` payloads. A result whose mappings
do not agree with the network raises an error.

The returned handle exposes `figure`, `axis`, `plots`, `model`, and resolved
`positions`. `selected` is a Makie `Observable` whose value is `nothing`, a bus
key, or a component key. `details` is another `Observable` with structured bus
or component information suitable for an external side panel. With an
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
line, and SVG export button. Network diagrams intentionally have no logarithmic
axis control or legend, and the diagram canvas uses the full available content
width. By default, `figure_size = :auto` fits the initial window to the resolved
network-layout aspect; pass an explicit `(width, height)` tuple to override it.
`diagram_view` is the same extension-owned handle returned by `diagram`,
including `selected` and `details`. Use `graph_layout` for a NetworkLayout
algorithm because PlotBuilder reserves `layout` for its page layout.

CairoMakie exports the same figure through ordinary Makie functions:

```julia
save("network.svg", view.figure)
```

For browser rendering, activate WGLMakie instead; the diagram construction path
is unchanged and the figure can be embedded by a Bonito application without
making Bonito a PowerImpedance dependency:

```julia
using WGLMakie
using GraphMakie

view = diagram(network, powerflow)
view.figure
```

The complete executable [Hybrid AC/DC network diagram](examples/Network_Diagram.md)
builds a small two-bus AC/two-bus DC example with a converter, AC and DC
branches, a source, and a grounded load.

## Calculation sequence

`NetworkState` stores component definitions, `NetworkTopology`, numerical
options, and an optional `OperatingPoint`. Active-component calculations use
one sequence:

```text
PowerFlowProblem + ACDCPowerFlow
                ↓
         PowerFlowResult
                ↓
LinearizationProblem + AdmittanceLinearization
                ↓
       LinearizationResult
                ↓
          NetworkModel
```

`PowerFlowResult` retains the exact PowerModelsACDC result, converted data,
node-to-bus mapping, element-to-component mapping, solver diagnostics, and the
calculated `OperatingPoint`. `NetworkModel` contains one `AdmittanceLookup`,
integer active/passive element selections, grounded/retained node selections,
and symbol-to-index lookup tables.

Frequency-response problems can start from either representation:

```julia
problem = PowerImpedanceProblem(
    network;
    nodes = [:bus],
    frequency_range = (1.0, 1e3, 400),
)

impedance_result = compute(problem, NodalImpedance())

model = compute(
    LinearizationProblem(network),
    AdmittanceLinearization(),
).network_model
edge_result = compute(
    PowerImpedanceProblem(
        model;
        nodes = [:bus],
        frequency_range = (1.0, 1e3, 400),
    ),
    EdgeAdmittance(),
)
```

Starting from `NetworkState` performs any required power flow and
linearization. Starting from `NetworkModel` evaluates the frequency response
directly. Existing `solve`, `determine_impedance`, `make_y_node`, `make_y_edge`,
and `make_loopgain` calls use the same calculation sequence and retain their
established return shapes.

## Classic network DSL

The Classic network DSL remains available through explicit import:

```julia
using PowerImpedance
import PowerImpedance: @network

network = @network begin
    source = ac_source(V = 230.0)
    branch = impedance(z = 0.1 + 0.5im, pins = 1)

    source[1.1] ⟷ branch[1.1] ⟷ bus
    source[2.1] ⟷ branch[2.1] ⟷ gnd
end
```

`Network`, `add!`, `connect!`, and `disconnect!` remain available. The macro is
not imported by `using PowerImpedance`. Import it explicitly with
`import PowerImpedance: @network`.

## Migration from the removed NetworkBuilder names

The former temporary type names were removed, not aliased. Calling one of the
retired constructors raises an error with the replacement and this migration
page.

| Removed name | Replacement |
|:--|:--|
| `BuilderState` | `NetworkState` |
| `ConnectionsRegistry` | `NetworkTopology` |
| `LinearizedAdmittanceCollection` | `AdmittanceLookup` |
| `LinearizedInterface` | `NetworkLookup` |
| `LinearizedAdmittanceNetwork` | `NetworkModel` |

The former NetworkBuilder `Pin`, `ConnectionDef`, `pin`, `⟷`, and `↔` grammar
has no compatibility spelling. Replace every chained connection with one named
row per connected terminal.

The complete public surface is grouped by module in the
[API reference](reference.md).
