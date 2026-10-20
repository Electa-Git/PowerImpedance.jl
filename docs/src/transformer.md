```@meta
CurrentModule = PowerImpedance
```

# Transformer

`transformer` represents a single-phase or balanced three-phase transformer
with a T-model containing primary winding impedance, excitation branch, ideal
voltage ratio, secondary winding impedance, and optional capacitive paths.

The model can be specified directly from its equivalent-circuit parameters or
derived from open-circuit and short-circuit test data. For three phases, `n` is
always the primary-to-secondary **line-to-line voltage ratio**, for both `:YY`
and `:ΔY`. All T-model parameters retain their per-phase, Y-equivalent `:YY`
meaning: winding resistances `Rₚ`, `Rₛ` [Ω] and leakage inductances `Lₚ`, `Lₛ`
[H] are referred to their own side; `Rₘ` [Ω] and `Lₘ` [H] form the primary
excitation branch; `Cₜ` and `Cₛ` [F] retain the same per-phase capacitive paths.
Zero `Rₘ` or `Lₘ` means that excitation term is absent. `hasRω` and `k` use the
same winding-resistance multiplier `(abs(s)/(2π*50))^k` in both organizations.

The `:ΔY` organization is **Dyn11**: delta primary and grounded-Y secondary,
with secondary positive-sequence voltage leading the primary by 30°.
For the ideal stage, with currents oriented from primary to secondary,

```math
r_\pm = n e^{\mp j\pi/6}, \qquad
V_{1,\pm} = r_\pm V_{2,\pm}, \qquad
I_{1,\pm} = \frac{I_{2,\pm}}{\overline{r_\pm}}.
```

`N± = diag(r±, 1/conj(r±)) = exp(∓jπ/6)·diag(n, 1/n)` and
`V1·conj(I1) = V2·conj(I2)` across the ideal stage. The same rotation applies
to the complete per-phase `:YY` model, including the capacitive paths, so that
`ABCD± = exp(∓jπ/6)·ABCDYY`. Negative sequence has the opposite shift.

The internal six-by-six phase matrix applies the Fortescue basis to both the
voltage and current halves, with phase order `[a,b,c]` and sequence order
`[0,+,-]`:

```math
T = \begin{bmatrix}1&1&1\\1&a^2&a\\1&a&a^2\end{bmatrix},
\qquad a=e^{j2\pi/3}.
```

Delta-to-Y zero-sequence isolation has no phase-domain ABCD representation.
The internal zero-sequence block is an identity placeholder exactly decoupled
from positive and negative sequence; it does not model physical zero-sequence
transfer. The supported three-phase use requires `transformation=true`, which
discards zero sequence and produces the dq model. An untransformed three-phase
`:ΔY` element throws `ArgumentError` at construction. In dq, Dyn11 rotates the
secondary frame by +30° relative to the primary. The repository uses a lagging
q axis, `[d,q] = [V cos θ, -V sin θ]`; with
`R(θ) = [cos θ -sin θ; sin θ cos θ]`, the ideal voltage ABCD block is
`n·R(+π/6)` and the ideal current block is `R(+π/6)/n`. For primary dq voltage
`[n,0]`, the secondary is `[cos(π/6), -sin(π/6)]`.

For power flow, the detailed ABCD model is converted to a balanced branch tap,
series admittance, and shunt admittance. These values are identical for `:YY`
and `:ΔY` with the same parameters. PowerModels defines the complex tap as
`tap·exp(j·shift)` and the unloaded voltage as `V_to = V_from/t`; Dyn11 uses `shift = -π/6` [rad]. Frequency-domain analysis retains the detailed
transformer model.

See [`transformer`](@ref) for fields, units, and constructor modes.
