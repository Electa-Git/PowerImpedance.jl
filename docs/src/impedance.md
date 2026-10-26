```@meta
CurrentModule = PowerImpedance
```

# Lumped impedance

`impedance(; z, conductors)` returns an `Impedance` model with `side1` and
`side2` ports. A scalar `z` repeats on the diagonal. A vector defines independent
series branches. For a diagonal branch-impedance matrix ``\mathbf{Z}``, the
ABCD representation is

```math
\begin{bmatrix}
\mathbf{A} & \mathbf{B} \\
\mathbf{C} & \mathbf{D}
\end{bmatrix}
=
\begin{bmatrix}
\mathbf{I} & \mathbf{Z} \\
\mathbf{0} & \mathbf{I}
\end{bmatrix}.
```

For an array specification, each nonzero `z[i,j]` connects terminal `i` of
`side1` to terminal `j` of `side2` with branch admittance `1/z[i,j]`. An
off-diagonal entry adds a cross-terminal branch. Zero entries omit branches.
A callable `z(s)` returns a scalar or compatible array at complex frequency
`s` in s⁻¹. Impedances are in Ω.

```@example impedances
using PowerImpedance

single = impedance(z = 5.0, conductors = 1)
diagonal = impedance(z = [1.0, 2.0, 3.0], conductors = 3)
cross_connected = impedance(z = [1.0 0.1; 0.1 2.0], conductors = 2)
dynamic = impedance(z = s -> 0.1 + s * 2e-3, conductors = 1)
electricalconnections(diagonal)
```

A model with three conductors declares `ACABC` ports. A model with one or two
conductors declares one `DC_CM` differential port per end. The bus selects the coordinates.
`ACABC` ports on an `ACDQ` bus are transformed to dq. The DC two-conductor
model eliminates common-mode voltage.

The complete network admittance is assembled using modified nodal analysis
[HoRuehliBrennan1975](@cite). See [`impedance`](@ref) for shape checks and
constructor details.
