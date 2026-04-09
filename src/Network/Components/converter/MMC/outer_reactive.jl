abstract type AbstractOuterReactiveControl      <: AbstractStateSpace end


@with_kw struct QControl <: AbstractOuterReactiveControl 
    pi_control::PIControl
    Q_ac_ref::Float64 = 0
end
statenames(::QControl) = (:ξ_Q_ac,)
initialvalues(::QControl, inputs) = (;) 


function state_space!(F, x, inputs, b::QControl, conv::AbstractMMC) 
    ξ_Q_ac = get_state(:ξ_Q_ac, x)
    Q_ac_F = inputs.Q_ac_F

    F[1] = b.pi_control.Ki *(b.Q_ac_ref - Q_ac_F)

    out = b.pi_control.Kp*(b.Q_ac_ref - Q_ac_F) + ξ_Q_ac
    return out_q_control(conv.delta_control, out)
end
