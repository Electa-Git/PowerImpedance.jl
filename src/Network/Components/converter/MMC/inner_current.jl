abstract type AbstractInnerCurrentControl       <: AbstractStateSpace end

struct ZeroSequenceCurrentControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::ZeroSequenceCurrentControl) = (:ξ_iΣz,)

struct CirculatingCurrentSuppressionControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::CirculatingCurrentSuppressionControl) = (:ξ_iΣd, :ξ_iΣq)

struct OutputCurrentControl <: AbstractInnerCurrentControl 
    pi_control::PIControl
end
statenames(::OutputCurrentControl) = (:ξ_iΔ_d, :ξ_iΔ_q)


### Lower level structures ###
#TODO: update the equations in comments to match the new version (including taking into account that modulation is now done in a specific function)
function state_space!(F, x, inputs, b::CirculatingCurrentSuppressionControl, conv::AbstractMMC) 
    (; ξ_iΣd, ξ_iΣq, iΣd, iΣq) = x
    Δθ_c = syncangle(conv.sync, x)
    iΣd_ref, iΣq_ref = 0, 0 # TODO add this as inputs/parameters if needed

    T_2θ = [cos(-2Δθ_c) -sin(-2Δθ_c); sin(-2Δθ_c) cos(-2Δθ_c)];
    iΣd_c, iΣq_c = T_2θ * [iΣd, iΣq]

    F[1] = (b.pi_control.Ki) * (iΣd_ref - iΣd_c)
    F[2] = (b.pi_control.Ki) * (iΣq_ref - iΣq_c)
    # vMΣd_ref = 2/Vdc*(- Ki_Σ * xiΣd - Kp_Σ * (iΣd_ref -  iΣd) + 2*Larm*iΣq)
    # vMΣq_ref = 2/Vdc*(- Ki_Σ * xiΣq - Kp_Σ * (iΣq_ref -  iΣq) - 2*Larm*iΣd)
    # Assuming constant w
    vMΣd_ref_c = (- ξ_iΣd - b.pi_control.Kp * (iΣd_ref - iΣd_c) + 2 * conv.elec.Lₐᵣₘ * iΣq_c)
    vMΣq_ref_c = (- ξ_iΣq - b.pi_control.Kp * (iΣq_ref - iΣq_c) - 2 * conv.elec.Lₐᵣₘ * iΣd_c)

    # Output are in converter reference frame!
    return (vMΣd_ref_c=vMΣd_ref_c, vMΣq_ref_c=vMΣq_ref_c)
end

function state_space!(F, x, inputs, b::ZeroSequenceCurrentControl, conv::AbstractMMC)
    (; ξ_iΣz, iΣz) = x
    (;iΣz_ref, v_dc_f)  = inputs

    F[1] = b.pi_control.Ki * (iΣz_ref - iΣz);
    # vMΣz_ref = 2/Vdc*(Vdc/2 - Kp_Σz*(iΣz_ref - iΣz) - Ki_Σz * xiΣz),
    return ( vMΣz_ref = (v_dc_f/2 - b.pi_control.Kp *(iΣz_ref - iΣz) - ξ_iΣz), )
end


function state_space!(F, x, (inputs, meas), b::OutputCurrentControl, conv::AbstractMMC) 
    (; ξ_iΔ_d, ξ_iΔ_q, iΔ_d, iΔ_q) = x
    (; iΔ_d_ref, iΔ_q_ref) = inputs 
    (; vG_d_f, vG_q_f) = meas
    Δθ_c = syncangle(conv.sync, x)

    T_θ = [cos(Δθ_c) -sin(Δθ_c); sin(Δθ_c) cos(Δθ_c)]
    iΔ_d_c, iΔ_q_c = T_θ * [iΔ_d, iΔ_q]

    F[1] = b.pi_control.Ki * (iΔ_d_ref - iΔ_d_c)
    F[2] = b.pi_control.Ki * (iΔ_q_ref - iΔ_q_c)
    
    # TODO: add omega in these equations! (here, uses approximation w=1)
    # vMΔd_ref = 2/Vdc*(Ki_Δ * xiΔ_d + Kp_Δ * (iΔ_d_ref -  iΔ_d) + Leqac*iΔ_q + vG_d)
    # vMΔq_ref = 2/Vdc*(Ki_Δ * xiΔ_q + Kp_Δ * (iΔ_q_ref -  iΔ_q) - Leqac*iΔ_d + vG_q)
    vMΔd_ref_c = ( ξ_iΔ_d +
                b.pi_control.Kp * (iΔ_d_ref - iΔ_d_c) + conv.elec.Lₑ * iΔ_q_c + 1*vG_d_f);
    vMΔq_ref_c = (ξ_iΔ_q +
                b.pi_control.Kp * (iΔ_q_ref - iΔ_q_c) - conv.elec.Lₑ * iΔ_d_c + 1*vG_q_f);

    
    # Output are in converter reference frame!
    return (vMΔd_ref_c=vMΔd_ref_c, vMΔq_ref_c=vMΔq_ref_c)
end
