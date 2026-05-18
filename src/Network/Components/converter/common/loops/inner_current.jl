#=
Shared inner-current control blocks for modular converters.

The inner-current layer converts current references into modulation commands for
converter models that dispatch through the TLC control interface. The file lives
under `common/loops` so the same API can be reused by other converter
implementations as they adopt the modular loop structure.
=#

export AbstractInnerCurrentControl,
       NoInnerCurrentControl,
       InnerCurrentPIControl

"""
Abstract supertype for TLC inner-current controllers.
"""
abstract type AbstractInnerCurrentControl <: AbstractStateSpace end

"""
No inner-current control.
"""
struct NoInnerCurrentControl <: AbstractInnerCurrentControl end

"""
Return state names for no inner-current control.

$(SIGNATURES)
"""
statenames(::NoInnerCurrentControl) = ()

"""
Return zero modulation commands.

$(SIGNATURES)
"""
state_space!(F, x, inputs, block::NoInnerCurrentControl, conv::AbstractConverter) =
    (; vMΔ_d_ref_c = 0.0, vMΔ_q_ref_c = 0.0)

"""
PI inner-current controller for TLC modulation commands.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct InnerCurrentPIControl{F<:AbstractMeasurementFilter} <: AbstractInnerCurrentControl
    pi_ctrl::PIControl
    filter::F
    activate_ω_c_multiplication::Bool
end

function InnerCurrentPIControl(;
    pi_ctrl::PIControl = PIControl(),
    filter::AbstractMeasurementFilter = NoFilter(),
    activate_ω_c_multiplication::Bool = true
)
    filter = measurement_filter_ss(filter)
    return InnerCurrentPIControl{typeof(filter)}(pi_ctrl, filter, activate_ω_c_multiplication)
end

InnerCurrentPIControl(pi_ctrl::PIControl) = InnerCurrentPIControl(pi_ctrl = pi_ctrl)

"""
Return inner-current controller state names.

$(SIGNATURES)
"""
function statenames(block::InnerCurrentPIControl)
    return (filter_statenames(:vG_d_occ_f, block.filter)..., filter_statenames(:vG_q_occ_f, block.filter)..., :ξ_id, :ξ_iq)
end

"""
Initialize inner-current PI integrator states.

$(SIGNATURES)
"""
function initialvalues(block::InnerCurrentPIControl; inputs, conv::AbstractConverter)
    ratio = voltage_filter_ratio(conv)
    vG_d0 = inputs.vG_d * ratio
    vG_q0 = inputs.vG_q * ratio
    dnames = filter_statenames(:vG_d_occ_f, block.filter)
    qnames = filter_statenames(:vG_q_occ_f, block.filter)

    return (;
        filter_initialvalues(block.filter, dnames, vG_d0)...,
        filter_initialvalues(block.filter, qnames, vG_q0)...,
        ξ_id = 0,
        ξ_iq = 0,
    )
end

"""
Evaluate TLC inner-current PI control.

$(SIGNATURES)

# Details

The method writes integrator derivatives and returns current errors plus
stationary-frame modulation commands.
"""
function state_space!(F, x, inputs, block::InnerCurrentPIControl, conv::AbstractConverter)
    (; meas, sync, vloop) = inputs
    i_d_ref = vloop.iΔ_d_ref
    i_q_ref = vloop.iΔ_q_ref

    i_d = meas.i_d_f
    i_q = meas.i_q_f
    v_d, i = filter_step!(F, 1, x, block.filter, filter_statenames(:vG_d_occ_f, block.filter), meas.vG_d_f)
    v_q, i = filter_step!(F, i, x, block.filter, filter_statenames(:vG_q_occ_f, block.filter), meas.vG_q_f)

    Lᵣ = elec_inductance(conv.elec)

    e_d = i_d_ref - i_d
    e_q = i_q_ref - i_q
    F[i] = block.pi_ctrl.Ki * e_d
    F[i + 1] = block.pi_ctrl.Ki * e_q

    multiplication_factor = block.activate_ω_c_multiplication ? sync.ω_c : 1

    vMΔ_d_ref_c = x.ξ_id + block.pi_ctrl.Kp * e_d + Lᵣ * multiplication_factor * i_q + v_d
    vMΔ_q_ref_c = x.ξ_iq + block.pi_ctrl.Kp * e_q - Lᵣ * multiplication_factor * i_d + v_q

    return (; vMΔ_d_ref_c, vMΔ_q_ref_c)
end
