# Migration from Element and Setpoint

This page helps users of the former `Element` and `Setpoint` interface move to
the current model and named-port API. For current construction details, see
[Network construction](../network.md), [Choose and configure components](../components.md),
and the [API reference](../reference.md).

## Replace wrappers and positional terminals

The former interface used the `Element` wrapper for models and `Setpoint` for
operating targets. It connected terminals by number through a connection
table. The current API uses component models directly. Set declared values
through constructor keywords or `withinputs`. Connect named component ports
with `Bus` or `Net`.

An old source-and-branch setup:

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

The equivalent current style uses named ports and an explicit frame:

```julia
source = ac_source(v = 310.0, p = 100.0)
branch = impedance(z = 400.0, conductors = 3)
connections = (
    Bus(:bus; ports = ((:source, :ac), (:branch, :side1)), domain = ACDQ),
    Bus(:gnd; ports = ((:branch, :side2),), domain = ACDQ),
)
state = define((; source, branch), connections;
    options = (; voltageBase = 310.0/sqrt(2)))
powerflow = solve(state)
powerflow.operating_point[:source].ac.p
```

The source's `p` input describes generated power. Solved `ac.p` is power into
the component, so it is negative when the source delivers power. Check each
model's input units and port names in its component guide before translating
old values.

## Replace setpoints and result access

Move converter references into the selected control-block input tree. Use the
model's documented bases when converting physical references. Configure
inputs with constructor keywords or `withinputs(model)`. Use `component`
when applying inputs and limits together. Use `exclude` to omit models from a
network declaration, and use symbolic terminal labels with `Net` when
individual terminal connections are required.

Power-flow results are returned as `PowerFlowResult`. Read solved values from
its operating point rather than from the original model:

```julia
powerflow = solve(state)
powerflow.operating_point[:grid].ac.p
```

The sign convention is power into the component. See [power-flow
initialization](../initialization.md) for solve and reuse workflows and the
[API reference](../reference.md) for result types and fields.
