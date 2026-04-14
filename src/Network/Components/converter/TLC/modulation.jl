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
Abstract supertype for TLC modulation blocks.
"""
abstract type AbstractModulationTLC <: AbstractStateSpace end

############################  No modulation / no delay  ############################

"""
Pass-through modulation block without delay.
"""
struct NoModulation <: AbstractModulationTLC end

"""
Return state names for no modulation.

$(SIGNATURES)
"""
statenames(::NoModulation) = ()

"""
Forward inner-current modulation commands.

$(SIGNATURES)
"""
state_space!(F, x, iloop, block::NoModulation; conv::AbstractTLC) =
    (; m_d = iloop.m_d, m_q = iloop.m_q)

############################  Time-delay modulation  ############################

"""
TLC modulation block backed by a generic Pade delay.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct DelayModulation{D<:PadeDelay} <: AbstractModulationTLC
    delay::D
end

"""
Construct a TLC delay modulation block.

$(SIGNATURES)

# Details

The internal [`PadeDelay`](@ref) uses two inputs and the `:m_delay` state prefix
to preserve the historical TLC state names.
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
Compatibility constructor for the previous TLC delay-modulation name.

$(SIGNATURES)
"""
PadeModulation(; kwargs...) = DelayModulation(; kwargs...)

"""
Return state names of the modulation delay block.

$(SIGNATURES)
"""
statenames(block::DelayModulation) = statenames(block.delay)

"""
Evaluate delayed TLC modulation commands.

$(SIGNATURES)

# Details

The generic delay output is phase-compensated by `ωbase * timeDelay` before being
returned to the electrical plant.
"""
function state_space!(F, x, (meas, iloop), block::DelayModulation, conv::AbstractTLC)
    
    md_c = (2 / meas.v_dc_f) * iloop.vMΔd_ref_c
    mq_c = (2 / meas.v_dc_f) * iloop.vMΔq_ref_c 
    
    m_d, m_q = inverse_frame_transform(md_c, mq_c, syncangle(conv.sync, x))

    y = state_space!(F, x, (m_d, m_q), block.delay)
    m_dq_ref = phase_compensated_dq(y, conv.elec.ωbase * block.delay.timeDelay)

    return (
        m_d = m_dq_ref.d,
        m_q = m_dq_ref.q
    )
end
