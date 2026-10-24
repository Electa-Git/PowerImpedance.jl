############################  modulation.jl  ############################

#=
TLC modulation blocks.

Modulation blocks convert inner-current-loop modulation references into the
commands seen by the electrical plant. The generic delay dynamics are provided
by `PadeDelay` in `common/kernels/delay.jl`; this file only adds TLC-specific
phase compensation and modulation outputs.
=#

export AbstractModulationTLC,
       NoModulation,
       DelayModulation,
       PadeModulation

############################  Abstract modulation slot  ############################

"""
$(TYPEDEF)

Abstract supertype for TLC modulation blocks.
"""
abstract type AbstractModulationTLC <: AbstractStateSpace end

############################  No modulation / no delay  ############################

"""
$(TYPEDEF)

TLC modulation block without delay.

$(TYPEDFIELDS)
"""
struct NoModulation <: AbstractModulationTLC end

statenames(::NoModulation) = ()

"""
$(TYPEDSIGNATURES)

Convert inner-current voltage references to undelayed TLC modulation commands.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `block`: The `NoModulation` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `m_d`: Insertion index or modulation command \\[dimensionless\\].
- `m_q`: Insertion index or modulation command \\[dimensionless\\].

# Notes

```math
\\mathbf m=\\frac{2}{v_{dc,f}}R(-\\theta)\\mathbf v^{ref}.
```

Commands are rotated from the synchronization frame to the nominal grid dq frame
and scaled using measured DC voltage. This block has no states or delay and does
not write to `F`.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = NoModulation()
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, iloop=(vMΔ_d_ref_c=1.0, vMΔ_q_ref_c=0.0))
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, block::NoModulation, conv::AbstractTLC)
    (; meas, iloop) = inputs

    md_c = (2 / meas.v_dc_f) * iloop.vMΔ_d_ref_c
    mq_c = (2 / meas.v_dc_f) * iloop.vMΔ_q_ref_c

    m_d, m_q = inverse_frame_transform(md_c, mq_c, syncangle(conv.sync, x))

    return (; m_d, m_q)
end

############################  Time-delay modulation  ############################

"""
$(TYPEDEF)

TLC modulation block backed by a generic Pade delay.

$(TYPEDFIELDS)
"""
struct DelayModulation{D<:PadeDelay} <: AbstractModulationTLC
    "Two-channel d/q modulation delay."
    delay::D
end

"""
$(TYPEDSIGNATURES)

Construct a TLC delay modulation block.

# Arguments

- `timeDelay`: Delay duration \\[s\\]. Default: `0.0`.
- `padeOrderNum`: Requested Padé numerator polynomial order. Default: `0`.
- `padeOrderDen`: Requested Padé denominator polynomial order. Default: `0`.

# Returns

- A `DelayModulation` instance.

# Notes

The internal [`PadeDelay`](@ref) uses two inputs and the `:m_delay` state prefix
to preserve the historical TLC state names.

# Examples

```julia
using PowerImpedance
component = DelayModulation(timeDelay=200e-6, padeOrderNum=3, padeOrderDen=3)
```
"""
function DelayModulation(;
    timeDelay::Real = 0.0,
    padeOrderNum::Int = 0,
    padeOrderDen::Int = 0
)
    delay = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 2,
        state_prefix = :m_delay,
    )
    return DelayModulation{typeof(delay)}(delay)
end

"""
$(TYPEDSIGNATURES)

Compatibility constructor for the previous TLC delay-modulation name.

# Arguments

- `kwargs...`: Keywords forwarded unchanged to `DelayModulation`.

# Returns

- A `DelayModulation` instance; `PadeModulation` is a function alias, not a type.

# Examples

```julia
using PowerImpedance
component = PadeModulation(timeDelay=200e-6, padeOrderNum=3, padeOrderDen=3)
```
"""
PadeModulation(; kwargs...) = DelayModulation(; kwargs...)

statenames(block::DelayModulation) = statenames(block.delay)

"""
$(TYPEDSIGNATURES)

Evaluate delayed TLC modulation commands.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `block`: The `DelayModulation` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `m_d`: Insertion index or modulation command \\[dimensionless\\].
- `m_q`: Insertion index or modulation command \\[dimensionless\\].

# Notes

The generic delay output is phase-compensated by `ωbase * timeDelay` before being
returned to the electrical plant.

```math
\\mathbf u=\\frac{2}{v_{dc,f}}R(-\\theta)\\mathbf v^{ref},\\qquad
\\mathbf m=\\mathcal C_{\\omega_b\\tau}\\!\\left(H_\\tau(s)\\mathbf u\\right).
```

Here ``R(-\\theta)`` rotates into the nominal grid dq frame, ``H_\\tau`` is the
two-channel Padé delay, and ``\\mathcal C`` is `phase_compensated_dq`. The delay
``\\tau`` uses \\[s\\] and the nominal electrical angular frequency ``\\omega_b``
uses \\[rad/s\\]. Commands are normalized \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = DelayModulation(timeDelay=200e-6, padeOrderNum=3, padeOrderDen=3)
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, iloop=(vMΔ_d_ref_c=1.0, vMΔ_q_ref_c=0.0))
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, block::DelayModulation, conv::AbstractTLC)
    (; meas, iloop) = inputs
    
    md_c = (2 / meas.v_dc_f) * iloop.vMΔ_d_ref_c
    mq_c = (2 / meas.v_dc_f) * iloop.vMΔ_q_ref_c 
    
    m_d, m_q = inverse_frame_transform(md_c, mq_c, syncangle(conv.sync, x))

    y = state_space!(F, x, (m_d, m_q), block.delay, conv)
    m_dq_ref = phase_compensated_dq(y, conv.elec.ωbase * block.delay.timeDelay)

    return (
        m_d = m_dq_ref.d,
        m_q = m_dq_ref.q
    )
end
