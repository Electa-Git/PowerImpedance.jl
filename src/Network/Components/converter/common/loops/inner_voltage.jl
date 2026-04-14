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

@with_kw struct CCVI <: AbstractVirtualImpedance
    R_v::Float64 = 0.01     # Virtual Resistance [pu]
    L_v::Float64 = 0.25     # Virtual inductance [pu]
    V_d_ref::Float64 = 1     # Vd voltage reference [pu]
    V_q_ref::Float64 = 0     # Vq voltage reference [pu]
end
statenames(::CCVI) = ()

function state_space!(F, x, (meas, sync, out_reactive), b::CCVI, conv::AbstractConverter)
    (;R_v, L_v, V_d_ref, V_q_ref) = b
    (;vG_d_f, vG_q_f) = meas
    ω_c = sync.ω_c
    vgfm_d_ref = out_reactive.vgfm_d_ref

    #TODO: check if turnRatio is needed (it was used in old code)

    den = (R_v^2 + ω_c^2*L_v^2)
    return (iΔ_d_ref=(R_v * (V_d_ref+vgfm_d_ref-vG_d_f) + ω_c * L_v * (vG_q_f-V_q_ref)) /den,
            iΔ_q_ref=(R_v * (V_q_ref-vG_q_f) + ω_c * L_v * (-vG_d_f+V_d_ref+vgfm_d_ref)) /den)

end