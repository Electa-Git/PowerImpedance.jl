############################  common/loops/outer_active.jl  ############################

#=
Shared active-power outer-loop blocks.

These blocks compute the d-axis current reference used by downstream voltage or
current loops. Optional active-power support is represented as a nested state-space
block so the outer loop remains composable.
=#

export AbstractOuterActiveControl,
       AbstractFrequencySupport,
       NoOuterActiveControl,
       NoFrequencySupport,
       OuterActivePowerControl,
       FrequencySupportLag,
       DCVoltageSupportLag,
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
state_space!(F, x, inputs, block::NoOuterActiveControl, conv::AbstractConverter) =
    (; iΔ_d_ref = 0.0)

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
Lagged DC-voltage support, subtracted from the active-power reference.
The reference is the solved DC-voltage setpoint, normalized by the converter's
declared DC-voltage base, as is the measured voltage.

$(TYPEDEF)

```math
\\dot{\\xi}_{vdc,supp}=\\omega_c[K(v_{dc,ref}-v_{dc,f})-\\xi_{vdc,supp}],
\\qquad p_{ref,eff}=p_{ref}-\\xi_{vdc,supp}.
```

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct DCVoltageSupportLag <: AbstractFrequencySupport
    "Droop gain in pu active power per pu DC voltage."
    K::Float64 = 0.0
    "First-order low-pass cutoff in \\[rad/s\\]."
    ωc::Float64 = 0.0
end

statenames(::DCVoltageSupportLag) = (:ξ_vdc_supp,)
initialvalues(::DCVoltageSupportLag; kwargs...) = (; ξ_vdc_supp = 0.0)

function state_space!(F, x, inputs, setpoint_pu::SetpointPU, block::DCVoltageSupportLag)
    F[1] = block.ωc * (block.K * (setpoint_pu.v_dc - inputs.meas.v_dc_f) - x.ξ_vdc_supp)
    return (; P_ac_support = -x.ξ_vdc_supp)
end

state_space!(F, x, inputs, setpoint_pu::SetpointPU, block::AbstractFrequencySupport) =
    state_space!(F, x, inputs.sync, block)

"""
Return the inverse DC-voltage droop slope on the power-flow system base.
Voltage references and slopes both use the declared converter DC-voltage base.

$(SIGNATURES)
"""
pf_dc_droop(::AbstractOuterActiveControl, dcbase, powerbase, global_dict, data) = 0.0

"""
Active-power PI controller with optional frequency or DC-voltage support.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct OuterActivePowerControl{S<:AbstractFrequencySupport} <: AbstractOuterActiveControl
    pi_ctrl::PIControl
    support::S
end

"""
Construct an active-power PI controller.

$(SIGNATURES)
"""
function OuterActivePowerControl(;
    pi_ctrl::PIControl = PIControl(),
    support::AbstractFrequencySupport = NoFrequencySupport(),
)
    return OuterActivePowerControl{typeof(support)}(pi_ctrl, support)
end

function pf_dc_droop(block::OuterActivePowerControl{DCVoltageSupportLag}, dcbase, powerbase, global_dict, data)
    return (1 / block.support.K) * (dcbase / (data["dcpol"] * global_dict["V"] / 1e3)) /
        (powerbase / (global_dict["S"] * 1e-6))
end

"""
Return active-power controller state names.

$(SIGNATURES)
"""
function statenames(block::OuterActivePowerControl)
    return (statenames(block.support)..., :ξ_P_ac)
end

function initialvalues(block::OuterActivePowerControl; setpoint_pu=SetpointPU(0, 0, 0, 0))
    return (; initialvalues(block.support)...)
end


"""
Evaluate active-power control and its support dynamics.

$(SIGNATURES)
"""
function state_space!(F, x, inputs, setpoint_pu::SetpointPU, block::OuterActivePowerControl, conv::AbstractConverter)
    (; meas) = inputs
    ns = n_states(block.support)
    support = state_space!(@view(F[1:ns]), x, inputs, setpoint_pu, block.support)
    P_ac_f = meas.P_ac_f

    Peff_ref = setpoint_pu.p_ac + support.P_ac_support

    F[ns + 1] = block.pi_ctrl.Ki * (Peff_ref - P_ac_f)

    return (iΔ_d_ref = block.pi_ctrl.Kp * (Peff_ref - P_ac_f) + x.ξ_P_ac, P_ac_f = P_ac_f)
end

"""
DC-voltage outer-loop controller that produces a d-axis current reference.
The measured DC voltage passes through `filter` only for this controller;
shared measurement, modulation and energy feedforward signals are unchanged.
`NoFilter()` retains the zero-state measurement and existing PI equations.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct OuterActiveVdcControl{F<:AbstractMeasurementFilter} <: AbstractOuterActiveControl
    "Voltage PI gains in the converter per-unit system."
    pi_ctrl::PIControl
    "Local measured DC-voltage filter; cutoff in \\[rad/s\\]."
    filter::F
end

"""
Construct a DC-voltage PI controller with an optional local measurement filter.

$(SIGNATURES)
"""
function OuterActiveVdcControl(; pi_ctrl::PIControl = PIControl(),
        filter::AbstractMeasurementFilter = NoFilter())
    realized = measurement_filter_ss(filter)
    return OuterActiveVdcControl{typeof(realized)}(pi_ctrl, realized)
end
OuterActiveVdcControl(pi_ctrl::PIControl) = OuterActiveVdcControl(; pi_ctrl)

"""
Return DC-voltage controller state names.

$(SIGNATURES)
"""
statenames(block::OuterActiveVdcControl) =
    (filter_statenames(:v_dc_ctrl_f, block.filter)..., :ξ_v_dc)

"""
Initialize local DC-voltage filter states at the solved reference \\[pu\\].

$(SIGNATURES)
"""
function initialvalues(block::OuterActiveVdcControl; setpoint_pu=SetpointPU())
    return filter_initialvalues(block.filter,
        filter_statenames(:v_dc_ctrl_f, block.filter), setpoint_pu.v_dc)
end

"""
Evaluate DC-voltage PI control.

$(SIGNATURES)

# Notes

```math
\\dot{\\xi}_{vdc}=K_i(v_{dc,ref}-v_f),\\qquad
i_{d,ref}=-[K_p(v_{dc,ref}-v_f)+\\xi_{vdc}],
```

where ``v_f`` is the locally filtered measured DC voltage and ``v_{dc,ref}``
is the solved reference in pu.
"""
function state_space!(F, x, inputs, setpoint_pu::SetpointPU, block::OuterActiveVdcControl, conv::AbstractConverter)
    (; meas) = inputs
    v_dc, idx = filter_step!(F, 1, x, block.filter,
        filter_statenames(:v_dc_ctrl_f, block.filter), meas.v_dc_f)
    F[idx] = block.pi_ctrl.Ki * (setpoint_pu.v_dc - v_dc)

    return (iΔ_d_ref = -1 * (block.pi_ctrl.Kp * (setpoint_pu.v_dc - v_dc) + x.ξ_v_dc), )
end
