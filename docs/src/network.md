```@meta
CurrentModule = PowerImpedance
```

# Network construction

Define component models in a `NamedTuple`, then connect their ports with buses
or individual nets. `NetworkBuilder.define` returns the network used by power
flow, linearization, and frequency-response calculations. Start with the
[component guide](components.md) to choose models and set their inputs.

## Choose bus coordinates

Each port declares an electrical domain and terminal labels. `ACDQ` uses d/q
coordinates, `ACABC` uses a/b/c phase coordinates, and `DC_CM` uses a
differential DC terminal. Inspect a model with `electricalconnections(model)`.

`Bus` connects complete ports. An AC bus uses dq coordinates when an attached
port declares `ACDQ`, or when `domain = ACDQ` is set. The builder transforms
compatible `ACABC` ports to dq. Otherwise, an AC bus uses phase coordinates.
DC ports cannot share a bus with AC ports.

```@example network
using PowerImpedance
using PowerImpedance.NetworkBuilder: Bus, Net, define

source = ac_source(v = 220 / sqrt(3))
line = impedance(z = 0.02 + 0.1im, conductors = 3)
elements = (; source, line)
connections = (
    Bus(:pcc; ports = ((:source, :ac), (:line, :side1)), domain = ACDQ),
    Bus(:remote; ports = ((:line, :side2),), domain = ACDQ),
)
network = define(elements, connections)
electricalconnections(source)
```

AC bus names append `d` and `q` to the supplied name. DC bus names are used as
given. Names starting with `gnd` connect to ground. A topology error identifies
missing components or ports, invalid terminal labels, duplicate terminal
assignments, or incompatible domains and frames.

## Connect individual terminals

Use `Net` when a connection joins selected terminals rather than every
coordinate of a port. Each terminal label must match the port declaration.

```@example network
dc_branch = impedance(z = 2.0, conductors = 1)
dc_load = impedance(z = 10.0, conductors = 1)
dc_elements = (; dc_branch, dc_load)
dc_connections = (
    Net(:dc_line; terminals = ((:dc_branch, :side1, :dc), (:dc_load, :side1, :dc))),
    Net(:gnd; terminals = ((:dc_branch, :side2, :dc), (:dc_load, :side2, :dc))),
)
dc_network = define(dc_elements, dc_connections)
length(dc_network.topology.connections)
```

`Bus` and `Net` declarations can be mixed in one topology. Keep all AC ports of
a component in the same coordinate frame. Three-phase `:ΔY` transformers
require a dq bus. The [transformer guide](transformer.md) describes the supported
connection and its phase shift.

## Define and visualize the network

The keys in the element tuple name the components used by the topology. Pass
power-flow or network options through `define` when a workflow needs them.

```@example network
using GraphMakie
using CairoMakie

diagram_view = diagram(network; interactive = false)
diagram_view.figure
```

The GraphMakie extension provides `diagram`. Activate a Makie backend to render
the returned figure. See the executable [network diagram example](examples/Network_Diagram.md)
for a hybrid AC/DC layout.

For a complete task that includes initialization and frequency analysis, follow
[Getting started](examples/Getting_started_SMIB.md). See [power-flow initialization](initialization.md)
for solved operating points and [impedance and stability analysis](results.md)
for the calculation workflow.

Users upgrading from the former `Element` and `Setpoint` interface can follow
the [migration guide](developers/migrations.md).
