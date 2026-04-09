abstract type AbstractEnergyControl             <: AbstractStateSpace end

@with_kw struct TotalEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::TotalEnergyControl) = (:ξ_Wtot,)
initialvalues(::TotalEnergyControl, inputs) = (;) 


function state_space!(F, x, inputs, b::TotalEnergyControl, conv::AbstractMMC)
    ξ_Wtot, vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz = get_states(x, :ξ_Wtot, :vCΔd, :vCΔq, :vCΔZd, :vCΔZq, :vCΣd, :vCΣq, :vCΣz)
    (; P_ac_F, Vdc) = inputs

    # wΣz = (vCΔd^2 + vCΔq^2 + vCΔZd^2 + vCΔZq^2 + vCΣd^2 + vCΣq^2 + 2*vCΣz^2)/(2)
    wΣz = (vCΔd^2 + vCΔq^2 + vCΔZd^2 + vCΔZq^2 + vCΣd^2 + vCΣq^2 + 2vCΣz^2)/2;
    
    F[1] = b.pi_control.Ki * (b.ref - wΣz)
    #iΣz_ref = (Kp_wΣ * (wΣz_ref - wΣz) + Ki_wΣ * xwΣz + Pac_f) / 3 / Vdc,
    return ( (iΣz_ref = (b.pi_control.Kp * (b.ref - wΣz) + ξ_Wtot + P_ac_F) / 3 / Vdc ),)
end
