############################  common/loops/outer_reactive.jl  ############################

#=
Shared reactive-power and AC-voltage outer-loop blocks.

These blocks compute the q-axis current reference used by downstream loops.
Optional voltage support is represented as a nested state-space block.
=#

export AbstractOuterReactiveControl,
       AbstractVoltageSupportTLC,
       NoOuterReactiveControl,
       NoVoltageSupport,
       OuterReactiveQControl,
       OuterReactiveVacControl,
       VoltageSupportLag

"""
Abstract supertype for reactive-power outer-loop controllers.
"""
abstract type AbstractOuterReactiveControl <: AbstractStateSpace end

"""
Abstract supertype for reactive-power support terms.
"""
abstract type AbstractVoltageSupportTLC <: AbstractStateSpace end

"""
No reactive-power outer-loop control.
"""
struct NoOuterReactiveControl <: AbstractOuterReactiveControl end

"""
Return state names for no reactive control.

$(SIGNATURES)
"""
statenames(::NoOuterReactiveControl) = ()

"""
Return a zero q-axis current reference.

$(SIGNATURES)
"""
state_space!(F, x, inputs, block::NoOuterReactiveControl, conv::AbstractConverter) =
    (; q_ctrl_ref = 0.0)

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
state_space!(F, x, meas, ::NoVoltageSupport) = (; Q_ac_support = 0.0)

"""
Lagged AC-voltage support contribution to reactive-power reference.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct VoltageSupportLag <: AbstractVoltageSupportTLC
    K::Float64 = 0.0
    ωc::Float64 = 0.0
    v_ac_ref::Float64 = 1.0
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
    v_ac = sqrt(meas.vG_d_f^2 + meas.vG_q_f^2)
    Δq_unf = block.K * (block.v_ac_ref - v_ac)
    F[1] = block.ωc * (Δq_unf - x.ξ_vac_supp)
    return (; Q_ac_support = x.ξ_vac_supp)
end

"""
Reactive-power PI controller with optional voltage support.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct OuterReactiveQControl{S<:AbstractVoltageSupportTLC} <: AbstractOuterReactiveControl
    pi_ctrl::PIControl
    Q_ac_ref::Float64
    support::S
end

"""
Construct a reactive-power PI controller.

$(SIGNATURES)
"""
function OuterReactiveQControl(;
    pi_ctrl::PIControl = PIControl(),
    Q_ac_ref::Real = 0.0,
    support::AbstractVoltageSupportTLC = NoVoltageSupport(),
)
    return OuterReactiveQControl{typeof(support)}(pi_ctrl, Float64(Q_ac_ref), support)
end

"""
Return reactive-power controller state names.

$(SIGNATURES)
"""
function statenames(block::OuterReactiveQControl)
    return (statenames(block.support)..., :ξ_Q_ac)
end

function initialvalues(block::OuterReactiveQControl; setpoint_pu=SetpointPU(0, 0, 0, 0), kwargs...)
    return (; initialvalues(block.support; kwargs...)...)
end

"""
Evaluate reactive-power control and support dynamics.

$(SIGNATURES)
"""
function state_space!(F, x, inputs, block::OuterReactiveQControl, conv::AbstractConverter)
    (; meas) = inputs
    ns = n_states(block.support)
    support = state_space!(@view(F[1:ns]), x, meas, block.support)
    Q_ac_f = meas.Q_ac_f

    Q_ac_ref_eff = block.Q_ac_ref + support.Q_ac_support
    F[ns + 1] = block.pi_ctrl.Ki * (Q_ac_ref_eff - Q_ac_f)
    
    return (q_ctrl_ref = block.pi_ctrl.Kp * (Q_ac_ref_eff - Q_ac_f) + x.ξ_Q_ac,)
end

"""
AC-voltage outer-loop controller that produces a q-axis current reference.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct OuterReactiveVacControl <: AbstractOuterReactiveControl
    pi_ctrl::PIControl = PIControl()
    v_ac_ref::Float64 = 1.0
end

"""
Return AC-voltage controller state names.

$(SIGNATURES)
"""
statenames(::OuterReactiveVacControl) = (:ξ_v_ac,)

"""
Evaluate AC-voltage PI control.

$(SIGNATURES)
"""
function state_space!(F, x, inputs, block::OuterReactiveVacControl, conv::AbstractConverter)
    (; meas) = inputs
    v_ac = sqrt(meas.vG_d_f^2 + meas.vG_q_f^2)

    F[1] = block.pi_ctrl.Ki * (block.v_ac_ref - v_ac)
    controller_output = block.pi_ctrl.Kp * (block.v_ac_ref - v_ac) + x.ξ_v_ac 
    return (; q_ctrl_ref = controller_output)
end
