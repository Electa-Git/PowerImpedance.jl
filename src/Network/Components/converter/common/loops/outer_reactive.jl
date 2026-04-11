############################  common/loops/outer_reactive.jl  ############################

#=
Shared reactive-power and AC-voltage outer-loop blocks.

These blocks compute the q-axis current reference used by downstream loops.
Optional voltage support is represented as a nested state-space block.
=#

export AbstractOuterReactiveTLC,
       AbstractVoltageSupportTLC,
       NoOuterReactiveControl,
       NoVoltageSupport,
       OuterReactiveQControl,
       OuterReactiveVacControl,
       VoltageSupportLag

"""
Abstract supertype for reactive-power outer-loop controllers.
"""
abstract type AbstractOuterReactiveTLC <: AbstractStateSpace end

"""
Abstract supertype for reactive-power support terms.
"""
abstract type AbstractVoltageSupportTLC <: AbstractStateSpace end

"""
No reactive-power outer-loop control.
"""
struct NoOuterReactiveControl <: AbstractOuterReactiveTLC end

"""
Return state names for no reactive control.

$(SIGNATURES)
"""
statenames(::NoOuterReactiveControl) = ()

"""
Return a zero q-axis current reference.

$(SIGNATURES)
"""
state_space!(F, x, meas, sync, block::NoOuterReactiveControl; conv::AbstractTLC) =
    (; i_q_ref = 0.0)

"""
No voltage-support contribution.
"""
struct NoVoltageSupport <: AbstractVoltageSupportTLC end

"""
Return state names for no voltage support.

$(SIGNATURES)
"""
statenames(::NoVoltageSupport) = ()

"""
Return zero reactive-power support.

$(SIGNATURES)
"""
state_space!(F, x, meas, ::NoVoltageSupport) = (; q_support = 0.0)

"""
Lagged AC-voltage support contribution to reactive-power reference.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct VoltageSupportLag <: AbstractVoltageSupportTLC
    K::Float64 = 0.0
    ωc::Float64 = 0.0
    vac_ref::Float64 = 1.0
end

"""
Return voltage-support state names.

$(SIGNATURES)
"""
statenames(::VoltageSupportLag) = (:ξ_vac_supp,)

"""
Evaluate the voltage-support lag equation.

$(SIGNATURES)
"""
function state_space!(F, x, meas, block::VoltageSupportLag)
    Vac = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
    Δq_unf = block.K * (block.vac_ref - Vac)
    F[1] = block.ωc * (Δq_unf - x.ξ_vac_supp)
    return (; q_support = x.ξ_vac_supp)
end

"""
Reactive-power PI controller with optional voltage support.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct OuterReactiveQControl{S<:AbstractVoltageSupportTLC} <: AbstractOuterReactiveTLC
    pi_ctrl::PIControl
    q_ref::Float64
    support::S
end

"""
Construct a reactive-power PI controller.

$(SIGNATURES)
"""
function OuterReactiveQControl(;
    pi_ctrl::PIControl = PIControl(),
    q_ref::Real = 0.0,
    support::AbstractVoltageSupportTLC = NoVoltageSupport(),
)
    return OuterReactiveQControl{typeof(support)}(pi_ctrl, Float64(q_ref), support)
end

"""
Return reactive-power controller state names.

$(SIGNATURES)
"""
function statenames(block::OuterReactiveQControl)
    return (statenames(block.support)..., :ξ_q)
end

"""
Return initial values for nested voltage support.

$(SIGNATURES)
"""
function initialvalues(block::OuterReactiveQControl; kwargs...)
    return initialvalues(block.support; kwargs...)
end

"""
Evaluate reactive-power control and support dynamics.

$(SIGNATURES)
"""
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

"""
AC-voltage outer-loop controller that produces a q-axis current reference.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct OuterReactiveVacControl <: AbstractOuterReactiveTLC
    pi_ctrl::PIControl = PIControl()
    vac_ref::Float64 = 1.0
end

"""
Return AC-voltage controller state names.

$(SIGNATURES)
"""
statenames(::OuterReactiveVacControl) = (:ξ_vac,)

"""
Evaluate AC-voltage PI control.

$(SIGNATURES)
"""
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
