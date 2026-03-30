############################  outer_active.jl  ############################

using Parameters

abstract type AbstractOuterActiveTLC <: AbstractStateSpace end

struct NoOuterActiveControl <: AbstractOuterActiveTLC end

statenames(::NoOuterActiveControl) = ()
initialvalues(::NoOuterActiveControl; kwargs...) = (;)

outeractive(::NoOuterActiveControl, x, meas, sync) = (; i_d_ref = 0.0)

state_space!(F, x, meas, sync, ::NoOuterActiveControl; conv::AbstractTLC) = nothing

@with_kw struct OuterActivePowerControl <: AbstractOuterActiveTLC
    ctrl::PIControl = PI_control()
    f_supp::Union{Nothing, PIControl} = nothing
end

function statenames(block::OuterActivePowerControl)
    block.f_supp === nothing ? (:ξ_p,) : (:ξ_f_supp, :ξ_p)
end

function initialvalues(block::OuterActivePowerControl; kwargs...)
    names = statenames(block)
    return NamedTuple{names}(ntuple(_ -> 0.0, length(names)))
end

function outeractive(block::OuterActivePowerControl, x, meas, sync)
    p_ref = block.ctrl.ref[1]
    P_ac = meas.v_d_f * meas.i_d_f + meas.v_q_f * meas.i_q_f

    if block.f_supp === nothing
        i_d_ref = block.ctrl.Kₚ * (p_ref - P_ac) + x.ξ_p
    else
        p_ref = p_ref + x.ξ_f_supp
        i_d_ref = block.ctrl.Kₚ * (p_ref - P_ac) + x.ξ_p
    end

    return (
        p_ref = p_ref,
        P_ac = P_ac,
        i_d_ref = i_d_ref
    )
end

function state_space!(F, x, meas, sync, block::OuterActivePowerControl; conv::AbstractTLC)
    p_ref = block.ctrl.ref[1]
    P_ac = meas.v_d_f * meas.i_d_f + meas.v_q_f * meas.i_q_f

    if block.f_supp === nothing
        F[1] = block.ctrl.Kᵢ * (p_ref - P_ac)
    else
        # Legacy ordering: support state first, then P integrator
        F[1] = block.f_supp.ω_f * (-(block.f_supp.Kₚ) * sync.Δω_sync - x.ξ_f_supp)
        p_ref = p_ref + x.ξ_f_supp
        F[2] = block.ctrl.Kᵢ * (p_ref - P_ac)
    end

    return nothing
end

@with_kw struct OuterActiveVdcControl <: AbstractOuterActiveTLC
    ctrl::PIControl = PI_control()
end

statenames(::OuterActiveVdcControl) = (:ξ_vdc,)
initialvalues(::OuterActiveVdcControl; kwargs...) = (ξ_vdc = 0.0,)

function outeractive(block::OuterActiveVdcControl, x, meas, sync)
    vdc_ref = block.ctrl.ref[1]
    i_d_ref = -(block.ctrl.Kₚ * (vdc_ref - meas.vdc_f) + x.ξ_vdc)

    return (
        vdc_ref = vdc_ref,
        i_d_ref = i_d_ref
    )
end

function state_space!(F, x, meas, sync, block::OuterActiveVdcControl; conv::AbstractTLC)
    F[1] = block.ctrl.Kᵢ * (block.ctrl.ref[1] - meas.vdc_f)
    return nothing
end