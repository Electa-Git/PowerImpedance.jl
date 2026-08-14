```@meta
CurrentModule = PowerImpedance
```

# Network construction

A PowerImpedance system is a collection of component `Element` objects and
their electrical connections. Each connection joins named component pins to a
network node. Ground nodes are represented explicitly.

## Declarative NetworkBuilder interface

`NetworkBuilder` is the preferred construction path for new systems. Import
only the small set of composition symbols required by the model:

```julia
using PowerImpedance
using PowerImpedance.NetworkBuilder: Grid, define, pin, solve, ⟷
```

Scalar elements use the ordinary keyword constructors. Passing `Grid` as the
first positional argument selects a lazy constructor for a parametric model:

```julia
source = ac_source(V = 220 / sqrt(3), pins = 3, transformation = true)
branch = impedance(z = 0.2 + 0.8im, pins = 3)

branch_space = impedance(Grid;
    z = Grid([0.1 + 0.4im, 0.2 + 0.8im, 0.3 + 1.2im]),
    pins = 3,
)
```

Connections are declared separately from the element data:

```julia
elements = (; source, branch)
connections = (
    pin(:source, 1, 1) ⟷ pin(:branch, 1, 1) ⟷ :bus,
    pin(:source, 2, 1) ⟷ pin(:branch, 2, 1) ⟷ :gnd,
)

builder = define(elements, connections)
solution = solve(builder)
```

`define` returns a scalar `BuilderState` when all elements are scalar and a
`Gridspace{BuilderState}` when any constructor contains a deterministic or
uncertain grid. Connections remain fixed within one stochastic case; topology
variants are separate deterministic cases.

See [Parametric and uncertainty studies](gridspace.md) for grid construction,
sampling, power-flow invalidation, and result aggregation.

## Classic network DSL

The `@network` macro remains supported for existing models. It constructs a
`Network` by naming elements and chaining their pins through nodes:

```julia
network = @network begin
    source = ac_source(V = 230.0)
    branch = impedance(z = 0.1 + 0.5im, pins = 1)

    source[1.1] ⟷ branch[1.1] ⟷ bus
    source[2.1] ⟷ branch[2.1] ⟷ gnd
end
```

The mutation helpers `add!`, `connect!`, and `disconnect!` also remain part of
the scalar interface. New parametric studies should use NetworkBuilder so each
physical case can be materialized reproducibly without mutating a shared
network.

## From construction to analysis

`solve` returns the power-flow result and constructed scalar network. Direct
frequency-domain routines accept scalar networks, while Gridspace-aware
overloads enumerate deterministic cases and sample uncertainty before any
numeric component reaches power flow, nonlinear equilibrium, linearization, or
admittance assembly.

The complete public surface is grouped by module in the [API reference](reference.md).
