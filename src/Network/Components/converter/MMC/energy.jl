abstract type AbstractEnergyControl             <: AbstractStateSpace end

@with_kw struct TotalEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::TotalEnergyControl) = (:ξ_Wtot,)

function state_space!(F, x, meas, b::TotalEnergyControl, conv::AbstractMMC)
    (; ξ_Wtot, vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; v_dc_f) = meas
    P_ac_f = meas.vG_d_f * meas.i_d_f + meas.vG_q_f * meas.i_q_f
    # wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/(2)
    wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/2;
    
    F[1] = b.pi_control.Ki * (b.ref - wΣz)
    #iΣ_z_ref = (Kp_wΣ * (wΣz_ref - wΣz) + Ki_wΣ * xwΣz + Pac_f) / 3 / Vdc,
    return ( iΣ_z_ref = ( (b.pi_control.Kp * (b.ref - wΣz) + ξ_Wtot + P_ac_f) / 3 / v_dc_f ),)
end

@with_kw struct ΣEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::ΣEnergyControl) = (:ξ_Wtot,)

function state_space!(F, x, inputs, b::ΣEnergyControl, conv::AbstractMMC)
    (; vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; P_ac_F, Vdc) = inputs

    # values in per-unit # TODO check base values!
    wΣd = (vCΔ_d^2 - vCΔ_q^2 + 2 * vCΔ_Zd * vCΔ_d + 2 * vCΔ_Zq * vCΔ_q + 4 * vCΣ_d * vCΣ_z)/2
    wΣq = (2* vCΔ_q * vCΔ_Zd - 2 * vCΔ_d * vCΔ_Zq - 2 * vCΔ_d * vCΔ_q + 4 * vCΣ_q * vCΣ_z)/2
    wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/2;

end

@with_kw struct ΔEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::ΔEnergyControl) = (:ξ_Wtot,)

function state_space!(F, x, inputs, b::ΔEnergyControl, conv::AbstractMMC)
    (; ξ_Wtot, vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; P_ac_F, Vdc) = inputs

    # values in per-unit # TODO check base values!
    wΔd = vCΔ_d * vCΣ_d + 2 * vCΔ_d * vCΣ_z - vCΔ_q * vCΣ_q + vCΔ_Zd * vCΣ_d - vCΔ_Zq * vCΣ_q
    wΔq = 2 * vCΔ_q * vCΣ_z - vCΔ_q * vCΣ_d - vCΔ_d * vCΣ_q + vCΔ_Zd * vCΣ_q + vCΔ_Zq * vCΣ_d
    wΔZd = vCΔ_d * vCΣ_d + vCΔ_q * vCΣ_q + 2 * vCΔ_Zd * vCΣ_z
    wΔZq = vCΔ_q * vCΣ_d - vCΔ_d * vCΣ_q + 2 * vCΔ_Zq * vCΣ_z

end