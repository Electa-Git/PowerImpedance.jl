abstract type AbstractOuterActiveControl        <: AbstractStateSpace end


@with_kw struct PControl <: AbstractOuterActiveControl 
    pi_control::PIControl
    P_ac_ref::Float64 = 0
end
statenames(::PControl ) = (:ξ_P_ac,)
initialvalues(::PControl, inputs) = (;)


function state_space!(F, x, meas, b::PControl, conv::AbstractMMC) 
    ## Get state, inputs and parameters
    (; ξ_P_ac) = x
    P_ac_f = meas.vG_d_f * meas.i_d_f + meas.vG_q_f * meas.i_q_f
    P_ac_ref = b.P_ac_ref
    
    ## Differential eq for ξ_P_ac
    F[1] =  b.pi_control.Ki * (P_ac_ref - P_ac_f)
    ## Controller output
    return (iΔ_d_ref = b.pi_control.Kp * (P_ac_ref - P_ac_f) + ξ_P_ac,)
end