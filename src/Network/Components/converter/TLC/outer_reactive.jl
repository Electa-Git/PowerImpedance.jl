############################  outer_reactive.jl  ############################

abstract type AbstractOuterReactiveTLC <: AbstractStateSpace end
abstract type AbstractVoltageSupportTLC <: AbstractStateSpace end

struct NoOuterReactiveControl <: AbstractOuterReactiveTLC end
statenames(::NoOuterReactiveControl) = ()
state_space!(F, x, meas, sync, block::NoOuterReactiveControl; conv::AbstractTLC) =
    (; i_q_ref = 0.0)

struct NoVoltageSupport <: AbstractVoltageSupportTLC end
statenames(::NoVoltageSupport) = ()
state_space!(F, x, meas, ::NoVoltageSupport) = (; q_support = 0.0)

@with_kw struct VoltageSupportLag <: AbstractVoltageSupportTLC
    K::Float64 = 0.0
    ωc::Float64 = 0.0
    vac_ref::Float64 = 1.0
end

statenames(::VoltageSupportLag) = (:ξ_vac_supp,)

function state_space!(F, x, meas, block::VoltageSupportLag)
    Vac = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
    Δq_unf = block.K * (block.vac_ref - Vac)
    F[1] = block.ωc * (Δq_unf - x.ξ_vac_supp)
    return (; q_support = x.ξ_vac_supp)
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

# Only propagate nonzero / nontrivial support initial values.
# ξ_q is left to orderedinitialvalues(...), which fills missing states with zero.
function initialvalues(block::OuterReactiveQControl; kwargs...)
    return initialvalues(block.support; kwargs...)
end

function state_space!(F, x, meas, sync, block::OuterReactiveQControl; conv::AbstractTLC)
    Q_ac = -meas.v_q_f * meas.i_d_f + meas.v_d_f * meas.i_q_f
    ns = n_states(block.support)
    support = state_space!(@view(F[1:ns]), x, meas, block.support)

    q_ref_eff = block.q_ref + support.q_support
    q_error = q_ref_eff - Q_ac
    i_q_ref = block.pi_ctrl.Kp * q_error + x.ξ_q
    F[ns + 1] = block.pi_ctrl.Ki * q_error

    return (
        q_ref = q_ref_eff,
        Q_ac = Q_ac,
        q_error = q_error,
        i_q_ref = i_q_ref,
    )
end

@with_kw struct OuterReactiveVacControl <: AbstractOuterReactiveTLC
    pi_ctrl::PIControl = PIControl()
    vac_ref::Float64 = 1.0
end

statenames(::OuterReactiveVacControl) = (:ξ_vac,)

function state_space!(F, x, meas, sync, block::OuterReactiveVacControl; conv::AbstractTLC)
    Vac = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
    vac_error = block.vac_ref - Vac
    i_q_ref = block.pi_ctrl.Kp * vac_error + x.ξ_vac
    F[1] = block.pi_ctrl.Ki * vac_error

    return (
        Vac = Vac,
        vac_error = vac_error,
        i_q_ref = i_q_ref,
    )
end
