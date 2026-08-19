```@meta
CurrentModule = PowerImpedance
```

# API reference

The public interface is grouped by its defining module. Ordinary component
constructors and downstream solvers belong to `PowerImpedance`.
Gridspace construction, study definitions, and result containers belong to
`PowerImpedance.NetworkBuilder`.

## `PowerImpedance`

```@autodocs
Modules = [PowerImpedance]
Public = true
Private = false
```

## `PowerImpedance.NetworkBuilder`

```@autodocs
Modules = [PowerImpedance.NetworkBuilder]
Public = true
Private = false
```

Every component and configuration shadow is available through positional
dispatch as `constructor(Grid; kwargs...)`; `constructor(; kwargs...)` remains
the scalar API. Equivalent qualified `NetworkBuilder.constructor(; kwargs...)`
forms remain available for compatibility but are intentionally not exported.

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
