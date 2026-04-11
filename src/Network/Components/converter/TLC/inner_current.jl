############################  inner_current.jl  ############################

abstract type AbstractInnerCurrentTLC <: AbstractStateSpace end

struct NoInnerCurrentControl <: AbstractInnerCurrentTLC end

statenames(::NoInnerCurrentControl) = ()

state_space!(F, x, meas, sync, vloop, block::NoInnerCurrentControl; conv::AbstractTLC) =
    (; m_d = 0.0, m_q = 0.0)

@with_kw struct InnerCurrentPIControl <: AbstractInnerCurrentTLC
    pi_ctrl::PIControl = PIControl()
end

statenames(::InnerCurrentPIControl) = (:ξ_id, :ξ_iq)

function initialvalues(block::InnerCurrentPIControl; inputs, setpoint=SetPoint(), kwargs...)
    conv = kwargs[:conv]
    i0 = initialvalues(conv.elec; inputs, setpoint)

    vACbase = conv.elec.vACbase_LL_RMS * sqrt(2 / 3)
    zACbase = (3 / 2) * vACbase^2 / conv.elec.Sbase
    Rr = conv.elec.Rᵣ / zACbase

    return (
        ξ_id = Rr * i0.i_d,
        ξ_iq = Rr * i0.i_q
    )
end

function state_space!(F, x, meas, sync, vloop, block::InnerCurrentPIControl; conv::AbstractTLC)
    i_d_ref = vloop.i_d_ref
    i_q_ref = vloop.i_q_ref

    i_d = meas.i_d_f
    i_q = meas.i_q_f
    v_d = meas.v_d_f
    v_q = meas.v_q_f
    Δω = sync.Δω_sync

    vACbase = conv.elec.vACbase_LL_RMS * sqrt(2 / 3)
    zACbase = (3 / 2) * vACbase^2 / conv.elec.Sbase
    lACbase = zACbase / conv.elec.ω₀

    Lᵣ = conv.elec.Lᵣ / lACbase

    e_d = i_d_ref - i_d
    e_q = i_q_ref - i_q
    F[1] = block.pi_ctrl.Ki * e_d
    F[2] = block.pi_ctrl.Ki * e_q

    md_c = 2 * (x.ξ_id + block.pi_ctrl.Kp * e_d + Lᵣ * (1 + Δω) * i_q + v_d) / meas.vdc_f
    mq_c = 2 * (x.ξ_iq + block.pi_ctrl.Kp * e_q - Lᵣ * (1 + Δω) * i_d + v_q) / meas.vdc_f

    θ = sync.θ_sync
    cθ = cos(θ)
    sθ = sin(θ)

    m_d =  cθ * md_c + sθ * mq_c
    m_q = -sθ * md_c + cθ * mq_c

    return (
        i_d_ref = i_d_ref,
        i_q_ref = i_q_ref,
        e_d = e_d,
        e_q = e_q,
        m_d = m_d,
        m_q = m_q
    )
end
