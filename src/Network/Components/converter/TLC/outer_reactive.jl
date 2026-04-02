############################  outer_reactive.jl  ############################

using Parameters

abstract type AbstractOuterReactiveTLC <: AbstractStateSpace end
abstract type AbstractVoltageSupportTLC <: AbstractStateSpace end

struct NoOuterReactiveControl <: AbstractOuterReactiveTLC end
statenames(::NoOuterReactiveControl) = ()
initialvalues(::NoOuterReactiveControl; kwargs...) = (;)
outerreactive(::NoOuterReactiveControl, x, meas, sync) = (; i_q_ref = 0.0)
state_space!(F, x, meas, sync, ::NoOuterReactiveControl; conv::AbstractTLC) = nothing


struct NoVoltageSupport <:AbstractVoltageSupportTLC end
statenames(::NoVoltageSupport) = ()
initialvalues(::NoVoltageSupport; kwargs...) = (;)
support_output(::NoVoltageSupport, x, meas) = 0.0
state_space!(F, x, meas, ::NoVoltageSupport) = nothing

@with_kw struct VoltageSupportLag <: AbstractVoltageSupportTLC
    K::Float64 = 0.0
    ωc::Float64 = 0.0
    vac_ref::Float64 = 1.0
end

statenames(::VoltageSupportLag) = (:ξ_vac_supp,)
initialvalues(::VoltageSupportLag; kwargs...) = (ξ_vac_supp = 0.0,)
support_output(::VoltageSupportLag, x, meas) = x.ξ_vac_supp
function state_space!(F, x, meas, block::VoltageSupportLag)
    Vac = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
    Δq_unf = block.K * (block.vac_ref - Vac)
    F[1] = block.ωc * (Δq_unf - x.ξ_vac_supp)
    return nothing
end








struct OuterReactiveQControl{S<:AbstractVoltageSupportTLC} <: AbstractOuterReactiveTLC
    pi_ctrl::PIControl
    q_ref::Float64
    support::S
end

function OuterReactiveQControl(;
    pi_ctrl::PIControl = PIControl(),
    q_ref::Real = 0.0,
    support::AbstractVoltageSupportTLC = NoVoltageSupport(),
    )
    return OuterReactiveQControl{typeof(support)}(pi_ctrl, Float64(q_ref), support)
end    

function statenames(block::OuterReactiveQControl)
    return (statenames(block.support)..., :ξ_q)
end

function initialvalues(block::OuterReactiveQControl; kwargs...)
    names = statenames(block)
    return NamedTuple{names}(ntuple(_ -> 0.0, length(names)))
end

function outerreactive(block::OuterReactiveQControl, x, meas, sync)
    Q_ac = -meas.v_q_f * meas.i_d_f + meas.v_d_f * meas.i_q_f
    q_ref_eff = block.q_ref + support_output(block.support, x, meas)
    i_q_ref = block.pi_ctrl.Kp * (q_ref_eff - Q_ac) + x.ξ_q

    return (
        q_ref = q_ref_eff,
        Q_ac = Q_ac,
        i_q_ref = i_q_ref,
    )
end

function state_space!(F, x, meas, sync, block::OuterReactiveQControl; conv::AbstractTLC)
    ns = n_states(block.support)

    if ns  > 0
        state_space!(@view(F[1:ns]), x, meas, block.support)
    end



    Q_ac = -meas.v_q_f * meas.i_d_f + meas.v_d_f * meas.i_q_f
    q_ref_eff = block.q_ref + support_output(block.support, x, meas)
    F[ns + 1] = block.pi_ctrl.Ki * (q_ref_eff - Q_ac)

    return nothing
end

@with_kw struct OuterReactiveVacControl <: AbstractOuterReactiveTLC
    pi_ctrl::PIControl = PIControl()
    vac_ref::Float64 = 1.0
end

statenames(::OuterReactiveVacControl) = (:ξ_vac,)
initialvalues(::OuterReactiveVacControl; kwargs...) = (ξ_vac = 0.0,)

function outerreactive(block::OuterReactiveVacControl, x, meas, sync)
    Vac = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
    i_q_ref = block.pi_ctrl.Kp * (block.vac_ref - Vac) + x.ξ_vac

    return (
        Vac = Vac,
        i_q_ref = i_q_ref,
    )
end

function state_space!(F, x, meas, sync, block::OuterReactiveVacControl; conv::AbstractTLC)
    Vac = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
    F[1] = block.pi_ctrl.Ki * (block.vac_ref - Vac)
    return nothing
end