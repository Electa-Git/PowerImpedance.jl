############################  common/kernels/reference_frames.jl  ############################

#=
Reference-frame helper routines for converter dq/αβ transformations.

The functions in this file are small allocation-free scalar transforms where
possible. The complex matrices are kept as shared constants for legacy
dq/αβ phase-compensation formulas.
=#

"""
dq-to-αβ helper matrix used by legacy phase-compensation expressions.
"""
const T_AB_DQ = 0.5 * ComplexF64[1 im; -im 1]

"""
αβ-to-dq helper matrix used by legacy phase-compensation expressions.
"""
const T_DQ_AB = 0.5 * ComplexF64[1 -im; im 1]

"""
Rotate a `d`/`q` vector by angle `θ`.

$(SIGNATURES)

# Details

Returns a named tuple `(d, q)`. TLC uses this for transforming electrical
inputs and currents into the synchronization frame.
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
Apply the inverse rotation of [`frame_transform`](@ref).

$(SIGNATURES)

# Details

Returns a named tuple `(d, q)`. TLC uses this to map controller voltage commands
back to the stationary converter modulation frame.
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
Apply delay phase compensation to a two-component dq vector.

$(SIGNATURES)

# Details

`y` is expected to contain the delayed `d` and `q` components. `angle` is the
electrical angle accumulated over the delay duration, typically `ω₀ * τ`.
"""
function phase_compensated_dq(y, angle)
    m_ab_ref = cis(-angle) * (T_DQ_AB * y)
    m_dq_ref = real(T_AB_DQ * conj(m_ab_ref) + conj(T_AB_DQ) * m_ab_ref)
    return (
        d = m_dq_ref[1],
        q = m_dq_ref[2],
    )
end
