abstract type AbstractEnergyControl             <: AbstractStateSpace end

@with_kw struct TotalEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::TotalEnergyControl) = (:ξ_Wtot,)

function state_space!(F, x, meas, b::TotalEnergyControl, conv::AbstractMMC)
    (; ξ_Wtot, vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz) = x
    (; v_dc_f) = meas
    P_ac_f = meas.vG_d_f * meas.i_d_f + meas.vG_q_f * meas.i_q_f
    # wΣz = (vCΔd^2 + vCΔq^2 + vCΔZd^2 + vCΔZq^2 + vCΣd^2 + vCΣq^2 + 2*vCΣz^2)/(2)
    wΣz = (vCΔd^2 + vCΔq^2 + vCΔZd^2 + vCΔZq^2 + vCΣd^2 + vCΣq^2 + 2*vCΣz^2)/2;
    
    F[1] = b.pi_control.Ki * (b.ref - wΣz)
    #iΣz_ref = (Kp_wΣ * (wΣz_ref - wΣz) + Ki_wΣ * xwΣz + Pac_f) / 3 / Vdc,
    return ( (iΣz_ref = (b.pi_control.Kp * (b.ref - wΣz) + ξ_Wtot + P_ac_f) / 3 / v_dc_f ),)
end

@with_kw struct ΣEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::ΣEnergyControl) = (:ξ_Wtot,)

function state_space!(F, x, inputs, b::ΣEnergyControl, conv::AbstractMMC)
    (; vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz) = x
    (; P_ac_F, Vdc) = inputs

    # values in per-unit # TODO check base values!
    wΣd = (vCΔd^2 - vCΔq^2 + 2 * vCΔZd * vCΔd + 2 * vCΔZq * vCΔq + 4 * vCΣd * vCΣz)/2
    wΣq = (2* vCΔq * vCΔZd - 2 * vCΔd * vCΔZq - 2 * vCΔd * vCΔq + 4 * vCΣq * vCΣz)/2
    wΣz = (vCΔd^2 + vCΔq^2 + vCΔZd^2 + vCΔZq^2 + vCΣd^2 + vCΣq^2 + 2*vCΣz^2)/2;

end

@with_kw struct ΔEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::ΔEnergyControl) = (:ξ_Wtot,)

function state_space!(F, x, inputs, b::ΔEnergyControl, conv::AbstractMMC)
    (; ξ_Wtot, vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz) = x
    (; P_ac_F, Vdc) = inputs

    # values in per-unit # TODO check base values!
    wΔd = vCΔd * vCΣd + 2 * vCΔd * vCΣz - vCΔq * vCΣq + vCΔZd * vCΣd - vCΔZq * vCΣq
    wΔq = 2 * vCΔq * vCΣz - vCΔq * vCΣd - vCΔd * vCΣq + vCΔZd * vCΣq + vCΔZq * vCΣd
    wΔZd = vCΔd * vCΣd + vCΔq * vCΣq + 2 * vCΔZd * vCΣz
    wΔZq = vCΔq * vCΣd - vCΔd * vCΣq + 2 * vCΔZq * vCΣz

end