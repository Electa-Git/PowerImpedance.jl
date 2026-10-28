```@meta
CurrentModule = PowerImpedance
```

# Component definitions and inputs

Choose a component model for each source, passive branch, converter, or machine
in the network. Each constructor documents its parameters, units, terminals,
and limits. Connect the returned models with the methods in
[Network construction](network.md).

## Set constructor parameters

Use a constructor's keywords for the model's physical or electrical
parameters. The `ac_source` constructor accepts voltage and power targets.
`impedance` accepts an impedance value or function. `transformer` accepts
equivalent-circuit or test-data parameters. These options depend on the model.
See its component guide and API entry for details.

```@example component_inputs
using PowerImpedance

source = ac_source(v = 220 / sqrt(3), p = 20.0, q = 0.0)
branch = impedance(z = s -> 0.02 + s * 1e-3, conductors = 3)
(electricalconnections(source), electricalconnections(branch))
```

## Inspect and change declared inputs

Some models declare configurable inputs separately from their constructor
parameters. `inputs(model)` reports the nested input tree, defaults, units, and
descriptions. `inputvalues(model)` returns the values currently stored in that
tree.

Use `withinputs(model; ...)` to create a configured copy. The keyword tree
follows the names in `inputs(model)` and can update only the branches that
change. `component(model; ...)` accepts the same input changes and can also
replace model limits. Both leave the original model unchanged.

```@example component_inputs
original = ac_source()
updated = withinputs(original; v = 230 / sqrt(3))
bounded = component(updated; limits = PowerImpedance.Limits(P_min = -100, P_max = 100))
(inputvalues(original), inputvalues(bounded))
```

Converter and machine constructors can also accept operating-point setpoints.
For a synchronous machine, `powerflow = (p, q, v)` values are per
unit on its machine base. Converter references use the selected control-loop
input tree and converter base. A loop reference supplies the quantity it
controls. See the [MMC](MMC.md), [two-level converter](TLC.md), and
[power-flow initialization](initialization.md) guides for those choices.

## Component guides

- [Voltage sources](source.md): ideal AC and DC voltage sources.
- [Lumped impedances](impedance.md): series branches, shunts, and multiconductor impedances.
- [Transformers](transformer.md): single-phase and balanced three-phase models.
- [Transmission lines and cables](transmission_line.md): geometry-based and imported line data.
- [Machines](machines.md): synchronous and induction machines.
- [Modular multilevel converters](MMC.md): detailed and scan-based models.
- [Two-level converters](TLC.md): control configurations and operating-point references.
- [Black-box models](blackbox.md): imported line and converter frequency responses.

The [API reference](reference.md) lists complete signatures and exported
types. See [Fundamental concepts](manual/fundamental_concepts.md) for the
reviewed mathematical background.
