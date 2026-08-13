```@meta
CurrentModule = PowerImpedanceACDC
```

# Legacy scalar interface

The original `@network` DSL and scalar analysis methods remain supported so
existing studies continue to run unchanged. They operate on a mutable
`Network`, assemble ABCD or nodal matrices, and return the historical scalar
result types.

New systems should generally use the declarative [NetworkBuilder](network.md)
interface. It separates elements from connection declarations, supports lazy
parameter grids through positional dispatch, and enables reproducible
uncertainty studies without changing scalar component implementations.

The following legacy entry points remain documented in the
[API reference](reference.md): `@network`, `Network`, `add!`, `connect!`,
`disconnect!`, `composite_element`, `make_abcd`, `make_z`, `make_y_matrix`, and
the scalar overloads of the impedance and stability tools.
