############################  common/kernels/reference_frames.jl  ############################

#=
Reference-frame helper routines for converter dq/αβ transformations.

The functions in this file are small allocation-free scalar transforms where
possible. The complex matrices are kept as shared constants for legacy
dq/αβ phase-compensation formulas.
=#

"Legacy dq-to-αβ helper matrix \\[dimensionless\\]."
const T_AB_DQ = 0.5 * ComplexF64[1 im; -im 1]

"Legacy αβ-to-dq helper matrix \\[dimensionless\\]."
const T_DQ_AB = 0.5 * ComplexF64[1 -im; im 1]

"""
$(TYPEDSIGNATURES)

Rotate a `d`/`q` vector by angle `θ`.

# Arguments

- `d`: d-axis component, in the units of the transformed signal.
- `q`: q-axis component, in the units of the transformed signal.
- `θ`: Rotation angle \\[rad\\].

# Returns

- `d`: Transformed d component in the input signal units.
- `q`: Transformed q component in the input signal units.

# Notes

Returns a named tuple `(d, q)`. TLC uses this for transforming electrical
inputs and currents into the synchronization frame.

```math
\\begin{bmatrix}d^\\prime\\\\q^\\prime\\end{bmatrix}=\\begin{bmatrix}\\cos\\theta&-\\sin\\theta\\\\\\sin\\theta&\\cos\\theta\\end{bmatrix}\\begin{bmatrix}d\\\\q\\end{bmatrix}.
```

The angle ``θ`` uses \\[rad\\] and component units are preserved.

# Examples

```julia
using PowerImpedance
PowerImpedance.frame_transform(1.0, 0.0, π/6)
```
"""
function frame_transform(d, q, θ)
    cθ = cos(θ)
    sθ = sin(θ)
    d_rot = cθ * d - sθ * q
    q_rot = sθ * d + cθ * q
    return (
        d = d_rot,
        q = q_rot,
    )
end

"""
$(TYPEDSIGNATURES)

Apply the inverse rotation of [`frame_transform`](@ref).

# Arguments

- `d`: d-axis component, in the units of the transformed signal.
- `q`: q-axis component, in the units of the transformed signal.
- `θ`: Rotation angle \\[rad\\].

# Returns

- `d`: Transformed d component in the input signal units.
- `q`: Transformed q component in the input signal units.

# Notes

Returns a named tuple `(d, q)`. TLC uses this to map controller voltage commands
back to the nominal grid dq frame used by the electrical model.

```math
\\begin{bmatrix}d^\\prime\\\\q^\\prime\\end{bmatrix}=\\begin{bmatrix}\\cos\\theta&\\sin\\theta\\\\-\\sin\\theta&\\cos\\theta\\end{bmatrix}\\begin{bmatrix}d\\\\q\\end{bmatrix}.
```

The angle ``θ`` uses \\[rad\\] and component units are preserved.

# Examples

```julia
using PowerImpedance
PowerImpedance.inverse_frame_transform(1.0, 0.0, π/6)
```
"""
function inverse_frame_transform(d, q, θ)
    cθ = cos(θ)
    sθ = sin(θ)
    d_rot =  cθ * d + sθ * q
    q_rot = -sθ * d + cθ * q
    return (
        d = d_rot,
        q = q_rot,
    )
end

"""
$(TYPEDSIGNATURES)

Apply delay phase compensation to a two-component dq vector.

# Arguments

- `y`: Two-element vector of delayed d/q components, in the units of the input signal.
- `angle`: Electrical delay-compensation angle \\[rad\\].

# Returns

- `d`: Transformed d component in the input signal units.
- `q`: Transformed q component in the input signal units.

# Notes

`y` is expected to contain the delayed `d` and `q` components. `angle` is the
electrical angle accumulated over the delay duration, typically `ω₀ * τ`.

```math
z=e^{-j\\alpha}T_{dq,\\alpha\\beta}y,\\qquad u=\\operatorname{Re}(T_{\\alpha\\beta,dq}\\overline{z}+\\overline{T_{\\alpha\\beta,dq}}z).
```

The helper matrices are `T_DQ_AB` and `T_AB_DQ`; ``α`` is the delay-compensation angle
\\[rad\\].

# Examples

```julia
using PowerImpedance
PowerImpedance.phase_compensated_dq([1.0, 0.0], 100π * 200e-6)
```
"""
function phase_compensated_dq(y, angle)
    m_ab_ref = cis(-angle) * (T_DQ_AB * y)
    m_dq_ref = real(T_AB_DQ * conj(m_ab_ref) + conj(T_AB_DQ) * m_ab_ref)
    return (
        d = m_dq_ref[1],
        q = m_dq_ref[2],
    )
end
