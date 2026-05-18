export CirculatingCurrentSuppressionControl, ZeroSequenceCurrentControl, CirculatingCurrentControl, 
    NoZeroSequenceCurrentControl, NoCirculatingCurrentSuppressionControl

struct NoZeroSequenceCurrentControl <: AbstractInnerCurrentControl end
statenames(::NoZeroSequenceCurrentControl) = ()
function state_space!(F, x, inputs, b::NoZeroSequenceCurrentControl, conv::AbstractMMC)
    return (vMΣ_z_ref = inputs.meas.v_dc_f/2,)
end

struct NoCirculatingCurrentSuppressionControl <: AbstractInnerCurrentControl end
statenames(::NoCirculatingCurrentSuppressionControl) = ()
function state_space!(F, x, inputs, b::NoCirculatingCurrentSuppressionControl, conv::AbstractMMC)
    return (vMΣ_d_ref_c = 0, vMΣ_q_ref_c = 0, )
end

struct ZeroSequenceCurrentControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::ZeroSequenceCurrentControl) = (:ξ_iΣ_z,)

struct CirculatingCurrentSuppressionControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::CirculatingCurrentSuppressionControl) = (:ξ_iΣ_d, :ξ_iΣ_q)

### Lower level structures ###
#TODO: update the equations in comments to match the new version (including taking into account that modulation is now done in a specific function)
function state_space!(F, x, meas, b::CirculatingCurrentSuppressionControl, conv::AbstractMMC) 
    (; ξ_iΣ_d, ξ_iΣ_q, iΣ_d, iΣ_q) = x
    Δθ_c = syncangle(conv.sync, x)
    iΣ_d_ref, iΣ_q_ref = 0, 0 # TODO add this as inputs/parameters if needed

    T_2θ = [cos(-2Δθ_c) -sin(-2Δθ_c); sin(-2Δθ_c) cos(-2Δθ_c)];
    iΣ_d_c, iΣ_q_c = T_2θ * [iΣ_d, iΣ_q]

    F[1] = (b.pi_control.Ki) * (iΣ_d_ref - iΣ_d_c)
    F[2] = (b.pi_control.Ki) * (iΣ_q_ref - iΣ_q_c)
    # vMΣ_d_ref = 2/Vdc*(- Ki_Σ * xiΣ_d - Kp_Σ * (iΣ_d_ref -  iΣ_d) + 2*Larm*iΣ_q)
    # vMΣ_q_ref = 2/Vdc*(- Ki_Σ * xiΣ_q - Kp_Σ * (iΣ_q_ref -  iΣ_q) - 2*Larm*iΣ_d)
    # Assuming constant w
    vMΣ_d_ref_c = (- ξ_iΣ_d - b.pi_control.Kp * (iΣ_d_ref - iΣ_d_c) + 2 * conv.elec.Lₐᵣₘ * iΣ_q_c)
    vMΣ_q_ref_c = (- ξ_iΣ_q - b.pi_control.Kp * (iΣ_q_ref - iΣ_q_c) - 2 * conv.elec.Lₐᵣₘ * iΣ_d_c)

    # Output are in converter reference frame!
    return (vMΣ_d_ref_c=vMΣ_d_ref_c, vMΣ_q_ref_c=vMΣ_q_ref_c)
end

function state_space!(F, x, inputs, b::ZeroSequenceCurrentControl, conv::AbstractMMC)
    (; meas, out_Wtot) = inputs
    (; ξ_iΣ_z, iΣ_z) = x
    iΣ_z_ref, v_dc_f = out_Wtot.iΣ_z_ref, meas.v_dc_f

    F[1] = b.pi_control.Ki * (iΣ_z_ref - iΣ_z);
    # vMΣ_z_ref = 2/Vdc*(Vdc/2 - Kp_Σz*(iΣ_z_ref - iΣ_z) - Ki_Σz * xiΣ_z),
    return ( vMΣ_z_ref = (v_dc_f/2 - b.pi_control.Kp *(iΣ_z_ref - iΣ_z) - ξ_iΣ_z), )
end


struct CirculatingCurrentControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::CirculatingCurrentControl) = (:ξ_iΣ_d, :ξ_iΣ_q, :ξ_iΣ_z)

function state_space!(F, x, inputs, b::CirculatingCurrentControl, conv::AbstractMMC)
    (; sync, meas, out_wΣ, out_wΔ) = inputs
    ξ_iΣ = [x.ξ_iΣ_d, x.ξ_iΣ_q, x.ξ_iΣ_z]
    iΣ = [x.iΣ_d, x.iΣ_q, x.iΣ_z] #TODO implement filters?
    iΣ_ref = [out_wΣ.iΣ_d_dc_ref + out_wΔ.iΣ_d_ac_ref, out_wΣ.iΣ_q_dc_ref + out_wΔ.iΣ_q_ac_ref, out_wΣ.iΣ_z_dc_ref + out_wΔ.iΣ_z_ac_ref]    
    Ki_iΣ = b.pi_control.Ki


    J = [ 0 1 0
         -1 0 0
          0 0 0]
    J_min2ω = -2 * sync.ω_c * J

    F[1:3] = Ki_iΣ * (iΣ_ref - iΣ) - J_min2ω * ξ_iΣ

    vMΣ_ref = -1 * ( ξ_iΣ + b.pi_control.Kp * (iΣ_ref - iΣ) ) + [0, 0, meas.v_dc_f/2] # This last term is added to match PSCAD implementation (the minus sign & + v_dc_f/2 is in the modulation block in PSCAD)

    return (vMΣ_d_ref_c = vMΣ_ref[1], vMΣ_q_ref_c = vMΣ_ref[2], vMΣ_z_ref = vMΣ_ref[3])
    
end
