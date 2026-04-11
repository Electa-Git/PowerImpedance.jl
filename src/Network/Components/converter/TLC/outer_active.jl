############################  outer_active.jl  ############################

abstract type AbstractOuterActiveTLC <: AbstractStateSpace end
abstract type AbstractFrequencySupportTLC <: AbstractStateSpace end

struct NoOuterActiveControl <: AbstractOuterActiveTLC end
statenames(::NoOuterActiveControl) = ()
state_space!(F, x, meas, sync, block::NoOuterActiveControl; conv::AbstractTLC) =
    (; i_d_ref = 0.0)

struct NoFrequencySupport <: AbstractFrequencySupportTLC end
statenames(::NoFrequencySupport) = ()
state_space!(F, x, sync, ::NoFrequencySupport) = (; p_support = 0.0)

@with_kw struct FrequencySupportLag <: AbstractFrequencySupportTLC
    Kω::Float64 = 0.0
    ωc::Float64 = 0.0
end

statenames(::FrequencySupportLag) = (:ξ_f_supp,)

function state_space!(F, x, sync, block::FrequencySupportLag)
    F[1] = block.ωc * (-block.Kω * sync.Δω_sync - x.ξ_f_supp)
    return (; p_support = x.ξ_f_supp)
end

struct OuterActivePowerControl{S<:AbstractFrequencySupportTLC} <: AbstractOuterActiveTLC
    pi_ctrl::PIControl
    p_ref::Float64
    support::S
end

function OuterActivePowerControl(;
    pi_ctrl::PIControl = PIControl(),
    p_ref::Real = 0.0,
    support::AbstractFrequencySupportTLC = NoFrequencySupport(),
)
    return OuterActivePowerControl{typeof(support)}(pi_ctrl, Float64(p_ref), support)
end

function statenames(block::OuterActivePowerControl)
    return (statenames(block.support)..., :ξ_p)
end

# Only propagate nonzero / nontrivial support initial values.
# ξ_p is left to orderedinitialvalues(...), which fills missing states with zero.
function initialvalues(block::OuterActivePowerControl; kwargs...)
    return initialvalues(block.support; kwargs...)
end

function state_space!(F, x, meas, sync, block::OuterActivePowerControl; conv::AbstractTLC)
    P_ac = meas.v_d_f * meas.i_d_f + meas.v_q_f * meas.i_q_f
    ns = n_states(block.support)
    support = state_space!(@view(F[1:ns]), x, sync, block.support)

    p_ref_eff = block.p_ref + support.p_support
    p_error = p_ref_eff - P_ac
    i_d_ref = block.pi_ctrl.Kp * p_error + x.ξ_p
    F[ns + 1] = block.pi_ctrl.Ki * p_error

    return (
        p_ref = p_ref_eff,
        P_ac = P_ac,
        p_error = p_error,
        i_d_ref = i_d_ref,
    )
end

@with_kw struct OuterActiveVdcControl <: AbstractOuterActiveTLC
    pi_ctrl::PIControl = PIControl()
    vdc_ref::Float64 = 1.0
    idc_ref::Float64 = 0.0
end

statenames(::OuterActiveVdcControl) = (:ξ_vdc,)

function state_space!(F, x, meas, sync, block::OuterActiveVdcControl; conv::AbstractTLC)
    vdc_error = block.vdc_ref - meas.vdc_f
    i_d_ref = -(block.pi_ctrl.Kp * vdc_error + x.ξ_vdc)
    F[1] = block.pi_ctrl.Ki * vdc_error

    return (
        vdc_ref = block.vdc_ref,
        vdc_error = vdc_error,
        i_d_ref = i_d_ref,
    )
end
