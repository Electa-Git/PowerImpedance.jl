#=
Shared inner-voltage-loop slot for modular converters.

The current modular TLC implementation only provides a pass-through voltage
loop. The abstraction is kept so voltage-loop implementations can be added
without changing the surrounding converter orchestration.
=#

export AbstractInnerVoltage,
       NoInnerVoltageControl, 
       CCVI

"""
Abstract supertype for TLC inner-voltage controllers.
"""
abstract type AbstractInnerVoltage <: AbstractStateSpace end

"""
Pass-through inner-voltage controller.

Forwards active and reactive current references to the inner-current loop.
"""
struct NoInnerVoltageControl <: AbstractInnerVoltage end

"""
Return state names for no inner-voltage control.

$(SIGNATURES)
"""
statenames(::NoInnerVoltageControl) = ()

"""
Forward outer-loop current references.

$(SIGNATURES)
"""
state_space!(F, x, (meas, sync, pact, qact), block::NoInnerVoltageControl, conv::AbstractConverter) =
    (; iΔ_d_ref = pact.iΔ_d_ref, iΔ_q_ref = qact.iΔ_q_ref)


abstract type AbstractVirtualImpedance          <: AbstractInnerVoltage end

struct CCVI{F<:AbstractMeasurementFilter} <: AbstractVirtualImpedance
    R_v::Float64     # Virtual Resistance [pu]
    L_v::Float64     # Virtual inductance [pu]
    V_d_ref::Float64 # Vd voltage reference [pu]
    V_q_ref::Float64 # Vq voltage reference [pu]
    filter::F
end

function CCVI(;
    R_v::Real = 0.01,
    L_v::Real = 0.25,
    V_d_ref::Real = 1,
    V_q_ref::Real = 0,
    filter::AbstractMeasurementFilter = NoFilter(),
)
    filter = measurement_filter_ss(filter)
    return CCVI{typeof(filter)}(Float64(R_v), Float64(L_v), Float64(V_d_ref), Float64(V_q_ref), filter)
end

function statenames(b::CCVI)
    return (filter_statenames(:vG_d_vi_f, b.filter)..., filter_statenames(:vG_q_vi_f, b.filter)...)
end

function initialvalues(b::CCVI; inputs, conv=nothing, kwargs...)
    ratio = voltage_filter_ratio(conv)
    vG_d0 = inputs.vG_d * ratio
    vG_q0 = inputs.vG_q * ratio
    dnames = filter_statenames(:vG_d_vi_f, b.filter)
    qnames = filter_statenames(:vG_q_vi_f, b.filter)
    return (; filter_initialvalues(b.filter, dnames, vG_d0)..., filter_initialvalues(b.filter, qnames, vG_q0)...)
end

function state_space!(F, x, (meas, sync, out_reactive), b::CCVI, conv::AbstractConverter)
    (;R_v, L_v, V_d_ref, V_q_ref) = b
    ω_c = sync.ω_c
    vgfm_d_ref = out_reactive.vgfm_d_ref
    vG_d_f, i = filter_step!(F, 1, x, b.filter, filter_statenames(:vG_d_vi_f, b.filter), meas.vG_d_f)
    vG_q_f, _ = filter_step!(F, i, x, b.filter, filter_statenames(:vG_q_vi_f, b.filter), meas.vG_q_f)

    den = (R_v^2 + ω_c^2*L_v^2)
    return (iΔ_d_ref=(R_v * (V_d_ref+vgfm_d_ref-vG_d_f) + ω_c * L_v * (vG_q_f-V_q_ref)) /den,
            iΔ_q_ref=(R_v * (V_q_ref-vG_q_f) + ω_c * L_v * (-vG_d_f+V_d_ref+vgfm_d_ref)) /den)

end
