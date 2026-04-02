############################  outer_active.jl  ############################

using Parameters

abstract type AbstractOuterActiveTLC <: AbstractStateSpace end
abstract type AbstractFrequencySupportTLC <: AbstractStateSpace end

struct NoOuterActiveControl <: AbstractOuterActiveTLC end
statenames(::NoOuterActiveControl) = ()
initialvalues(::NoOuterActiveControl; kwargs...) = (;)
outeractive(::NoOuterActiveControl, x, meas, sync) = (; i_d_ref = 0.0)
state_space!(F, x, meas, sync, ::NoOuterActiveControl; conv::AbstractTLC) = nothing

struct NoFrequencySupport <: AbstractFrequencySupportTLC end
statenames(::NoFrequencySupport) = ()
initialvalues(::NoFrequencySupport; kwargs...) = (;)
support_output(::NoFrequencySupport, x, sync) = 0.0
state_space!(F, x, sync, ::NoFrequencySupport) = nothing

@with_kw struct FrequencySupportLag <: AbstractFrequencySupportTLC
    Kω::Float64 = 0.0
    ωc::Float64 = 0.0
end

statenames(::FrequencySupportLag) = (:ξ_f_supp,)
initialvalues(::FrequencySupportLag; kwargs...) = (ξ_d_supp = 0.0,)
support_output(::FrequencySupportLag, x, sync) = x.ξ_f_supp
function state_space!(F, x, sync, block::FrequencySupportLag)
    F[1] = block.ωc * (-block.Kω * sync.Δω_sync - x.ξ_f_supp)
    return nothing
end


struct OuterActivePowerControl{S<:AbstractFrequencySupportTLC} <: AbstractOuterActiveTLC
    pi_ctrl::PIControl = PIControl()
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



function initialvalues(block::OuterActivePowerControl; kwargs...)
    names = statenames(block)
    return NamedTuple{names}(ntuple(_ -> 0.0, length(names)))
end

function outeractive(block::OuterActivePowerControl, x, meas, sync)
    P_ac = meas.v_d_f * meas.i_d_f + meas.v_q_f * meas.i_q_f
    p_ref_eff = block.p_ref + support_output(block.support, x, sync)
    i_d_ref = block.pi_ctrl.Kp * (p_ref_eff - P_ac) + x.ξ_p

    return (
        p_ref = p_ref_eff,
        P_ac = P_ac,
        i_d_ref = i_d_ref,
    )
end

function state_space!(F, x, meas, sync, block::OuterActivePowerControl; conv::AbstractTLC)
    ns = n_states(block.support)
    if ns > 0
        state_space!(@view(F[1:ns]), x, sync, block.support)
    end

    P_ac = meas.v_d_f * meas.i_d_f + meas.v_q_f * meas.i_q_f
    p_ref_eff = block.p_ref + support_output(block.support, x, sync)
    F[ns + 1] = block.pi_ctrl.Ki * (p_ref_eff - P_ac)

    return nothing
end

@with_kw struct OuterActiveVdcControl <: AbstractOuterActiveTLC
    pi_ctrl::PIControl = PIControl()
    vdc_ref::Float64 = 1.0
end

statenames(::OuterActiveVdcControl) = (:ξ_vdc,)
initialvalues(::OuterActiveVdcControl; kwargs...) = (ξ_vdc = 0.0,)

function outeractive(block::OuterActiveVdcControl, x, meas, sync)
    i_d_ref = -(block.pi_ctrl.Kp * (block.vdc_ref - meas.vdc_f) + x.ξ_vdc)

    return (
        vdc_ref = block.vdc_ref,
        i_d_ref = i_d_ref,
    )
end

function state_space!(F, x, meas, sync, block::OuterActiveVdcControl; conv::AbstractTLC)
    F[1] = block.pi_ctrl.Ki * (block.vdc_ref - meas.vdc_f)
    return nothing
end