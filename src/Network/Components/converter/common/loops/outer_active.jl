############################  common/loops/outer_active.jl  ############################

#=
Shared active-power outer-loop blocks.

These blocks compute the d-axis current reference used by downstream voltage or
current loops. Optional frequency support is represented as a nested state-space
block so the outer loop remains composable.
=#

export AbstractOuterActiveControl,
       AbstractFrequencySupport,
       NoOuterActiveControl,
       NoFrequencySupport,
       OuterActivePowerControl,
       FrequencySupportLag,
       OuterActiveVdcControl

"""
Abstract supertype for active-power outer-loop controllers.
"""
abstract type AbstractOuterActiveControl <: AbstractStateSpace end

"""
Abstract supertype for active-power support terms.
"""
abstract type AbstractFrequencySupport <: AbstractStateSpace end

"""
No active-power outer-loop control.
"""
struct NoOuterActiveControl <: AbstractOuterActiveControl end

"""
Return state names for no active control.

$(SIGNATURES)
"""
statenames(::NoOuterActiveControl) = ()

"""
Return a zero d-axis current reference.

$(SIGNATURES)
"""
state_space!(F, x, meas, sync, block::NoOuterActiveControl; conv::AbstractConverter) =
    (; i_d_ref = 0.0)

"""
No frequency-support contribution.
"""
struct NoFrequencySupport <: AbstractFrequencySupport end

"""
Return state names for no frequency support.

$(SIGNATURES)
"""
statenames(::NoFrequencySupport) = ()

"""
Return zero active-power support.

$(SIGNATURES)
"""
state_space!(F, x, sync, ::NoFrequencySupport) = (; P_ac_support = 0.0)

"""
Lagged frequency-support active-power contribution.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct FrequencySupportLag <: AbstractFrequencySupport
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
    F[1] = block.ωc * (-block.Kω * (sync.ω_c - 1) - x.ξ_f_supp)
    return (; P_ac_support = x.ξ_f_supp)
end

"""
Active-power PI controller with optional frequency support.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct OuterActivePowerControl{S<:AbstractFrequencySupport,F<:AbstractMeasurementFilter} <: AbstractOuterActiveControl
    pi_ctrl::PIControl
    P_ac_ref::Float64
    support::S
    filter::F
end

"""
Construct an active-power PI controller.

$(SIGNATURES)
"""
function OuterActivePowerControl(;
    pi_ctrl::PIControl = PIControl(),
    P_ac_ref::Real = 0.0,
    support::AbstractFrequencySupport = NoFrequencySupport(),
    filter::AbstractMeasurementFilter = NoFilter(),
)
    filter = measurement_filter_ss(filter)
    return OuterActivePowerControl{typeof(support),typeof(filter)}(pi_ctrl, Float64(P_ac_ref), support, filter)
end

"""
Return active-power controller state names.

$(SIGNATURES)
"""
function statenames(block::OuterActivePowerControl)
    return (statenames(block.support)..., filter_statenames(:P_ac_f, block.filter)..., :ξ_P_ac)
end

function initialvalues(block::OuterActivePowerControl; setpoint_pu=SetpointPU(0, 0, 0, 0))
    names = filter_statenames(:P_ac_f, block.filter)
    return (; initialvalues(block.support)..., filter_initialvalues(block.filter, names, setpoint_pu.p_ac)...)
end


"""
Evaluate active-power control and its support dynamics.

$(SIGNATURES)
"""
function state_space!(F, x, (meas, sync), block::OuterActivePowerControl, conv::AbstractConverter)
    P_ac = meas.vG_d_f * meas.i_d_f + meas.vG_q_f * meas.i_q_f
    ns = n_states(block.support)
    support = state_space!(@view(F[1:ns]), x, sync, block.support)
    P_ac_f, i = filter_step!(F, ns + 1, x, block.filter, filter_statenames(:P_ac_f, block.filter), P_ac)

    Peff_ref = block.P_ac_ref + support.P_ac_support

    F[i] = block.pi_ctrl.Ki * (Peff_ref - P_ac_f)

    return (iΔ_d_ref = block.pi_ctrl.Kp * (Peff_ref - P_ac_f) + x.ξ_P_ac, P_ac_f = P_ac_f)
end

"""
DC-voltage outer-loop controller that produces a d-axis current reference.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct OuterActiveVdcControl <: AbstractOuterActiveControl
    pi_ctrl::PIControl = PIControl()
    v_dc_ref::Float64 = 1.0
end

"""
Return DC-voltage controller state names.

$(SIGNATURES)
"""
statenames(::OuterActiveVdcControl) = (:ξ_v_dc,)

"""
Evaluate DC-voltage PI control.

$(SIGNATURES)
"""
function state_space!(F, x, (meas, sync), block::OuterActiveVdcControl, conv::AbstractConverter)
    F[1] = block.pi_ctrl.Ki * (block.v_dc_ref - meas.v_dc_f)

    return (iΔ_d_ref = -1 * (block.pi_ctrl.Kp * (block.v_dc_ref - meas.v_dc_f) + x.ξ_v_dc), )
end
