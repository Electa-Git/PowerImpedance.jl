abstract type AbstractInnerCurrentControl       <: AbstractStateSpace end

struct ZeroSequenceCurrentControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::ZeroSequenceCurrentControl) = (:ξ_iΣz,)
initialvalues(::ZeroSequenceCurrentControl, inputs) = (;) 

struct CirculatingCurrentSuppressionControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::CirculatingCurrentSuppressionControl) = (:ξ_iΣd, :ξ_iΣq)
initialvalues(::CirculatingCurrentSuppressionControl, inputs) = (;) 

struct OutputCurrentControl <: AbstractInnerCurrentControl 
    pi_control::PIControl
end
statenames(::OutputCurrentControl) = (:ξ_iΔd, :ξ_iΔq)
initialvalues(::OutputCurrentControl, inputs) =  (;)



### Lower level structures ###
#TODO: update the equations in comments to match the new version (including taking into account that modulation is now done in a specific function)
function state_space!(F, x, inputs, b::CirculatingCurrentSuppressionControl, conv::AbstractMMC) 
    ξ_iΣd, ξ_iΣq, iΣd, iΣq = get_states(x, :ξ_iΣd, :ξ_iΣq, :iΣd, :iΣq)
    Δθ_c = inputs.Δθ_c
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
    ξ_iΣz, iΣz = get_states(x, :ξ_iΣz, :iΣz)
    (;iΣz_ref, Vdc)  = inputs

    F[1] = b.pi_control.Ki * (iΣz_ref - iΣz);
    # vMΣz_ref = 2/Vdc*(Vdc/2 - Kp_Σz*(iΣz_ref - iΣz) - Ki_Σz * xiΣz),
    return ( vMΣz_ref = (Vdc/2 - b.pi_control.Kp *(iΣz_ref - iΣz) - ξ_iΣz), )
end


function state_space!(F, x, inputs, b::OutputCurrentControl, conv::AbstractMMC) 
    ξ_iΔd, ξ_iΔq, iΔd, iΔq = get_states(x, :ξ_iΔd, :ξ_iΔq, :iΔd, :iΔq)
    (; iΔd_ref, iΔq_ref, Vᴳd, Vᴳq, Δθ_c) = inputs 

    T_θ = [cos(Δθ_c) -sin(Δθ_c); sin(Δθ_c) cos(Δθ_c)]
    iΔd_c, iΔq_c = T_θ * [iΔd, iΔq]
    Vᴳd_c, Vᴳq_c = T_θ * [Vᴳd; Vᴳq] * conv.elec.turnsRatio

    Vᴳd_fc = Vᴳd_c # if voltage is filtered, change this #TODO
    Vᴳq_fc = Vᴳq_c # if voltage is filtered!

    F[1] = b.pi_control.Ki * (iΔd_ref - iΔd_c)
    F[2] = b.pi_control.Ki * (iΔq_ref - iΔq_c)
    
    # TODO: add omega in these equations! (here, uses approximation w=1)
    # vMΔd_ref = 2/Vdc*(Ki_Δ * xiΔd + Kp_Δ * (iΔd_ref -  iΔd) + Leqac*iΔq + Vᴳd)
    # vMΔq_ref = 2/Vdc*(Ki_Δ * xiΔq + Kp_Δ * (iΔq_ref -  iΔq) - Leqac*iΔd + Vᴳq)
    vMΔd_ref_c = ( ξ_iΔd +
                b.pi_control.Kp * (iΔd_ref - iΔd_c) + conv.elec.Lₑ * iΔq_c + 1*Vᴳd_fc);
    vMΔq_ref_c = (ξ_iΔq +
                b.pi_control.Kp * (iΔq_ref - iΔq_c) - conv.elec.Lₑ * iΔd_c + 1*Vᴳq_fc);

    
    # Output are in converter reference frame!
    return (vMΔd_ref_c=vMΔd_ref_c, vMΔq_ref_c=vMΔq_ref_c)
end
