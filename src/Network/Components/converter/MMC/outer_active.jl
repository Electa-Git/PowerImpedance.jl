abstract type AbstractOuterActiveControl        <: AbstractStateSpace end


@with_kw struct PControl <: AbstractOuterActiveControl 
    pi_control::PIControl
    P_ac_ref::Float64 = 0
end
statenames(::PControl ) = (:ξ_P_ac,)
initialvalues(::PControl, inputs) = (;)


function state_space!(F, x, inputs, b::PControl, conv::AbstractMMC) 
    ## Get state, inputs and parameters
    ξ_P_ac = get_state(:ξ_P_ac, x)
    P_ac_F = inputs.P_ac_F
    P_ac_ref = b.P_ac_ref
    
    ## Differential eq for ξ_P_ac
    F[1] =  b.pi_control.Ki * (P_ac_ref - P_ac_F)
    ## Controller output
    return (iΔd_ref = b.pi_control.Kp * (P_ac_ref - P_ac_F) + ξ_P_ac,)
end