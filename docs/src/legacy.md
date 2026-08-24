```@meta
CurrentModule = PowerImpedance
```

# Classic scalar interface

The `@network` DSL and scalar analysis methods remain supported. The macro now
requires `import PowerImpedance: @network`; its network semantics are
unchanged. These methods operate on a mutable
`Network`, assemble ABCD or nodal matrices, and return the historical scalar
result types.

NetworkBuilder separates elements from connection declarations and supports
lazy parameter grids through positional dispatch without changing scalar
component implementations. Its row grammar is documented under
[Network construction](network.md).

The following classic entry points remain documented in the
[API reference](reference.md): `@network`, `Network`, `add!`, `connect!`,
`disconnect!`, `composite_element`, `make_abcd`, `make_z`, `make_y_matrix`, and
the scalar overloads of the impedance and stability tools.
