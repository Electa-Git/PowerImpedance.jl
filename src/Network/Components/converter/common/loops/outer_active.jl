############################  common/loops/outer_active.jl  ############################

#=
Shared active-power outer-loop blocks.

These blocks compute the d-axis current reference used by downstream voltage or
current loops. Optional frequency support is represented as a nested state-space
block so the outer loop remains composable.
=#

export AbstractOuterActiveTLC,
       AbstractFrequencySupportTLC,
       NoOuterActiveControl,
       NoFrequencySupport,
       OuterActivePowerControl,
       FrequencySupportLag,
       OuterActiveVdcControl

"""
Abstract supertype for active-power outer-loop controllers.
"""
abstract type AbstractOuterActiveTLC <: AbstractStateSpace end

"""
Abstract supertype for active-power support terms.
"""
abstract type AbstractFrequencySupportTLC <: AbstractStateSpace end

"""
No active-power outer-loop control.
"""
struct NoOuterActiveControl <: AbstractOuterActiveTLC end

"""
Return state names for no active control.

$(SIGNATURES)
"""
statenames(::NoOuterActiveControl) = ()

"""
Return a zero d-axis current reference.

$(SIGNATURES)
"""
state_space!(F, x, meas, sync, block::NoOuterActiveControl; conv::AbstractTLC) =
    (; i_d_ref = 0.0)

"""
No frequency-support contribution.
"""
struct NoFrequencySupport <: AbstractFrequencySupportTLC end

"""
Return state names for no frequency support.

$(SIGNATURES)
"""
statenames(::NoFrequencySupport) = ()

"""
Return zero active-power support.

$(SIGNATURES)
"""
state_space!(F, x, sync, ::NoFrequencySupport) = (; p_support = 0.0)

"""
Lagged frequency-support active-power contribution.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct FrequencySupportLag <: AbstractFrequencySupportTLC
    Kω::Float64 = 0.0
    ωc::Float64 = 0.0
end

"""
Return state names for frequency support.

$(SIGNATURES)
"""
statenames(::FrequencySupportLag) = (:ξ_f_supp,)

"""
Evaluate the frequency-support lag equation.

$(SIGNATURES)
"""
function state_space!(F, x, sync, block::FrequencySupportLag)
    F[1] = block.ωc * (-block.Kω * sync.Δω_sync - x.ξ_f_supp)
    return (; p_support = x.ξ_f_supp)
end

"""
Active-power PI controller with optional frequency support.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct OuterActivePowerControl{S<:AbstractFrequencySupportTLC} <: AbstractOuterActiveTLC
    pi_ctrl::PIControl
    p_ref::Float64
    support::S
end

"""
Construct an active-power PI controller.

$(SIGNATURES)
"""
function OuterActivePowerControl(;
    pi_ctrl::PIControl = PIControl(),
    p_ref::Real = 0.0,
    support::AbstractFrequencySupportTLC = NoFrequencySupport(),
)
    return OuterActivePowerControl{typeof(support)}(pi_ctrl, Float64(p_ref), support)
end

"""
Return active-power controller state names.

$(SIGNATURES)
"""
function statenames(block::OuterActivePowerControl)
    return (statenames(block.support)..., :ξ_p)
end

"""
Return initial values for nested frequency support.

$(SIGNATURES)
"""
function initialvalues(block::OuterActivePowerControl; kwargs...)
    return initialvalues(block.support; kwargs...)
end

"""
Evaluate active-power control and its support dynamics.

$(SIGNATURES)
"""
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

"""
DC-voltage outer-loop controller that produces a d-axis current reference.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct OuterActiveVdcControl <: AbstractOuterActiveTLC
    pi_ctrl::PIControl = PIControl()
    vdc_ref::Float64 = 1.0
    idc_ref::Float64 = 0.0
end

"""
Return DC-voltage controller state names.

$(SIGNATURES)
"""
statenames(::OuterActiveVdcControl) = (:ξ_vdc,)

"""
Evaluate DC-voltage PI control.

$(SIGNATURES)
"""
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
