```@meta
CurrentModule = PowerImpedanceACDC
```

# API reference

The public interface is grouped by its defining module. Ordinary component
constructors and downstream solvers belong to `PowerImpedanceACDC`.
Gridspace construction, orchestration, and result containers belong to
`PowerImpedanceACDC.NetworkBuilder`.

## `PowerImpedanceACDC`

```@autodocs
Modules = [PowerImpedanceACDC]
Public = true
Private = false
```

## `PowerImpedanceACDC.NetworkBuilder`

```@autodocs
Modules = [PowerImpedanceACDC.NetworkBuilder]
Public = true
Private = false
```

Every component and configuration shadow is available through positional
dispatch as `constructor(Grid; kwargs...)`; `constructor(; kwargs...)` remains
the scalar API. Equivalent qualified `NetworkBuilder.constructor(; kwargs...)`
forms remain available for compatibility but are intentionally not exported.

Optional-package methods are documented on [Package extensions](package_extensions.md)
because their extension modules are loaded only when the corresponding weak
dependencies are present.
