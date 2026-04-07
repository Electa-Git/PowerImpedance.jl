abstract type AbstractVirtualImpedance          <: AbstractStateSpace end

@with_kw struct CCVI <: AbstractVirtualImpedance
    R_v::Float64 = 0.01     # Virtual Resistance [pu]
    L_v::Float64 = 0.25     # Virtual inductance [pu]
    Vd_ref::Float64 = 1     # Vd voltage reference [pu]
    Vq_ref::Float64 = 0     # Vq voltage reference [pu]
end
statenames(::CCVI) = ()
initialvalues(::CCVI, inputs) = (;) 


function state_space!(F, x, inputs, b::CCVI, conv::AbstractMMC)
    (;R_v, L_v, Vd_ref, Vq_ref) = b
    (;Vᴳd, Vᴳq, Vⱽd_ref, ω_c, Δθ_c) = inputs

    T_θ = [cos(Δθ_c) -sin(Δθ_c); sin(Δθ_c) cos(Δθ_c)]
    Vᴳd_c, Vᴳq_c = T_θ * [Vᴳd; Vᴳq] * conv.elec.turnsRatio

    Vᴳd_f = Vᴳd_c # if voltage is filtered, change this #TODO
    Vᴳq_f = Vᴳq_c # if voltage is filtered!

    den = (R_v^2 + ω_c^2*L_v^2)
    return (iΔd_ref=(R_v * (Vd_ref+Vⱽd_ref-Vᴳd_f) + ω_c * L_v * (Vᴳq_f-Vq_ref)) /den,
            iΔq_ref=(R_v * (Vq_ref-Vᴳq_f) + ω_c * L_v * (-Vᴳd_f+Vd_ref+Vⱽd_ref)) /den)

end