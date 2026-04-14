abstract type AbstractVirtualImpedance          <: AbstractStateSpace end

@with_kw struct CCVI <: AbstractVirtualImpedance
    R_v::Float64 = 0.01     # Virtual Resistance [pu]
    L_v::Float64 = 0.25     # Virtual inductance [pu]
    Vd_ref::Float64 = 1     # Vd voltage reference [pu]
    Vq_ref::Float64 = 0     # Vq voltage reference [pu]
end
statenames(::CCVI) = ()

function state_space!(F, x, inputs, b::CCVI, conv::AbstractMMC)
    (;R_v, L_v, Vd_ref, Vq_ref) = b
    (;vG_d, vG_q, Vⱽd_ref, ω_c, Δθ_c) = inputs

    T_θ = [cos(Δθ_c) -sin(Δθ_c); sin(Δθ_c) cos(Δθ_c)]
    vG_d_c, vG_q_c = T_θ * [vG_d; vG_q] * conv.elec.turnsRatio

    vG_d_f = vG_d_c # if voltage is filtered, change this #TODO
    vG_q_f = vG_q_c # if voltage is filtered!

    den = (R_v^2 + ω_c^2*L_v^2)
    return (iΔ_d_ref=(R_v * (Vd_ref+Vⱽd_ref-vG_d_f) + ω_c * L_v * (vG_q_f-Vq_ref)) /den,
            iΔ_q_ref=(R_v * (Vq_ref-vG_q_f) + ω_c * L_v * (-vG_d_f+Vd_ref+Vⱽd_ref)) /den)

end