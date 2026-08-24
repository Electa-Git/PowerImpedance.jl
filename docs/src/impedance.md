```@meta
CurrentModule = PowerImpedance
```

# Lumped impedance

`impedance` constructs a series multiport element from a constant or
frequency-dependent impedance matrix. For ``n`` pins, the ABCD representation
of a series impedance ``\mathbf{Z}`` is

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

A scalar `z` produces identical diagonal impedances. A vector with `pins`
entries sets the diagonal independently, while a `pins × pins` matrix retains
all diagonal and mutual terms. A callable `z(s)` provides a frequency-dependent
matrix evaluated at the complex frequency supplied by the analysis kernel.

```julia
scalar = impedance(z = 5.0, pins = 1)
diagonal = impedance(z = [1.0, 2.0, 3.0], pins = 3)
coupled = impedance(z = [1.0 0.1; 0.1 2.0], pins = 2)
dynamic = impedance(z = s -> 0.1 + s * 2e-3, pins = 1)
```

The complete network admittance is assembled using modified nodal analysis
[HoRuehliBrennan1975](@cite). See [`impedance`](@ref) for validation and current
constructor details.
