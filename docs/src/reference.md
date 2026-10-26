```@meta
CurrentModule = PowerImpedance
```

# API reference

The public interface is grouped by its defining module. Ordinary component
constructors and downstream solvers belong to `PowerImpedance`.
Gridspace construction, study definitions, and result containers belong to
`PowerImpedance.Grammar` and are re-exported by the package root and
`PowerImpedance.NetworkBuilder`.

## `PowerImpedance`

Component ports are declared by `Port`, `ACDQ`, `ACABC`, `DC_CM` and
`electricalconnections`. Configurable inputs use `Input`, `inputs`, `inputvalues`,
`withinputs` and `component`. Bases and limits are available through `BaseValues`,
`bases` and `limits`. Control references and converter or machine power-flow setpoints use
the model bases. Source and scan-based MMC inputs use physical units.

Terminal operating points use `ACPortValues` and `DCPortValues`, keyed by port name
in a NamedTuple. `OperatingPoint` stores these NamedTuples by element name:
`op[:c1].ac.p` accesses AC active power into the component, and `op[:c1].dc.v` accesses DC voltage.
`get(op, :missing, nothing)` returns `nothing` for an absent element.
`linearize(model, values)` computes the state-space matrices and
stores the converged state. `steady_state(model, values)` reuses that state when
the terminal values compare equal with `isequal`.

```@autodocs
Modules = [PowerImpedance]
Public = true
Private = false
```

## `PowerImpedance.Grammar`

```@autodocs
Modules = [PowerImpedance.Grammar]
Public = true
Private = false
```

## `PowerImpedance.NetworkBuilder`

`Bus(name; ports, domain = nothing)` connects named component ports and expands
into one net per coordinate. AC names append `d`, `q` or `a`, `b`, `c`. A DC net
retains the bus name. `Net(name; terminals, domain = nothing)` connects individual
terminals using `(component, port, terminal)` triples. Both infer their domain from
the attached ports. An AC bus uses dq coordinates when one attached port declares
`ACDQ`, or when `domain = ACDQ` is supplied. Names starting with `gnd` denote ground.

`define(elements, topology; options = (;), exclude = ())` stores models under their
NamedTuple names. An included model without a topology reference raises `ArgumentError`.
Excluded names are dropped with an informational message.

```@autodocs
Modules = [PowerImpedance.NetworkBuilder]
Public = true
Private = false
```

`solve(state)` and `compute(PowerFlowProblem(state), ACDCPowerFlow())` return
`PowerFlowResult` and always solve the requested network. A
`LinearizationProblem(state, powerflow)` uses the supplied operating point.
Without a supplied result, linearization of linear models uses an empty point.
Nonlinear models require power flow.

Component and configuration Gridspaces use positional dispatch as
`constructor(Grid; kwargs...)`. The keyword-only `constructor(; kwargs...)`
method is the scalar API.

## `PowerImpedance.PSCAD`

```@docs
PowerImpedance.PSCAD
```

See [PSCAD export and simulation](pscad.md) for export, station execution and
operating-point comparison.

## `PowerImpedance.UnitHandler`

```@autodocs
Modules = [PowerImpedance.UnitHandler]
Public = true
Private = false
```

## `PowerImpedance.PlotBuilder`

```@autodocs
Modules = [PowerImpedance.PlotBuilder]
Public = true
Private = false
```

### `PowerImpedance.PlotBuilder.BackendHandler`

```@autodocs
Modules = [PowerImpedance.PlotBuilder.BackendHandler]
Public = true
Private = false
```

Optional-package methods are documented on [Package extensions](package_extensions.md)
because their extension modules are loaded only when the corresponding weak
dependencies are present.
