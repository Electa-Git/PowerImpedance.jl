############################  common/loops/synchronization.jl  ############################

#=
Shared synchronization blocks for converter control models.

Synchronization blocks provide the control-frame angle and frequency deviation
used by downstream outer and inner loops. The current implementations cover a
no-synchronization pass-through and a filtered PLL.
=#

export AbstractSynchronization,
       NoSynchronization,
       PLLSynchronization

"""
Abstract supertype for TLC-compatible synchronization blocks.
"""
abstract type AbstractSynchronization <: AbstractStateSpace end

"""
Synchronization block that fixes the control frame to the stationary frame.
"""
struct NoSynchronization <: AbstractSynchronization end

"""
Return state names for no synchronization.

$(SIGNATURES)
"""
statenames(::NoSynchronization) = ()

"""
Return the synchronization angle used before measurement filtering.

$(SIGNATURES)
"""
syncangle(::NoSynchronization, x) = 0.0

"""
Return nominal synchronization outputs without state equations.

$(SIGNATURES)
"""
state_space!(F, x, meas, block::NoSynchronization; conv::AbstractConverter) = (ω_c = 1.0,)

"""
Phase-locked-loop synchronization block.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct PLLSynchronization{Filter<:AbstractMeasurementFilter} <: AbstractSynchronization
    pi_ctrl::PIControl
    filter::Filter
end

"""
Construct a PLL synchronization block.

$(SIGNATURES)

# Details

The `filter` argument filters the measured q-axis voltage before the PI
controller computes the frequency deviation.
"""
function PLLSynchronization(; pi_ctrl::PIControl = PIControl(), filter::AbstractMeasurementFilter = NoFilter())
    filter = measurement_filter_ss(filter)

    return PLLSynchronization{typeof(filter)}(
        pi_ctrl,
        filter,
    )
end

"""
Return the PLL angle used before measurement filtering.

$(SIGNATURES)
"""
syncangle(::PLLSynchronization, x) = x.Δθ_pll

"""
Return PLL state names.

$(SIGNATURES)
"""
function statenames(block::PLLSynchronization)
    n = size(block.filter.A, 1)
    return (
        ntuple(i -> Symbol("v_q_pll_f_x$i"), n)...,
        :ξ_pll,
        :Δθ_pll,
    )
end

"""
Evaluate PLL filter, PI integrator, and angle state equations.

$(SIGNATURES)
"""
function state_space!(F, x, meas, block::PLLSynchronization, conv::AbstractConverter)
    n = size(block.filter.A, 1)
    xf = collect(getfield(x, Symbol("v_q_pll_f_x$i")) for i in 1:n)
    vG_d_g_f, vG_q_g_f = inverse_frame_transform(meas.vG_d_f, meas.vG_q_f, x.Δθ_pll)
    _, vG_q_pll_f = frame_transform(vG_d_g_f, vG_q_g_f, x.Δθ_pll)
    u = [vG_q_pll_f]
    # u = [meas.vG_q_f] #TODO change this (this is just a test)

    dx_f = block.filter.A * xf + block.filter.B * u
    v_pll = (block.filter.C * xf + block.filter.D * u)[1]
    Δω = -block.pi_ctrl.Kp * v_pll + x.ξ_pll

    @inbounds for i in 1:n
        F[i] = dx_f[i]
    end

    F[n + 1] = -block.pi_ctrl.Ki * v_pll
    F[n + 2] = conv.elec.ωbase * Δω

    return (ω_c = Δω + 1,)
end
