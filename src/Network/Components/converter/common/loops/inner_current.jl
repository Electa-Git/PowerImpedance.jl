#=
Shared inner-current control blocks for modular converters.

The inner-current layer converts current references into modulation commands for
converter models that dispatch through the TLC control interface. The file lives
under `common/loops` so the same API can be reused by other converter
implementations as they adopt the modular loop structure.
=#

export AbstractInnerCurrentTLC,
       NoInnerCurrentControl,
       InnerCurrentPIControl

"""
Abstract supertype for TLC inner-current controllers.
"""
abstract type AbstractInnerCurrentTLC <: AbstractStateSpace end

"""
No inner-current control.
"""
struct NoInnerCurrentControl <: AbstractInnerCurrentTLC end

"""
Return state names for no inner-current control.

$(SIGNATURES)
"""
statenames(::NoInnerCurrentControl) = ()

"""
Return zero modulation commands.

$(SIGNATURES)
"""
state_space!(F, x, meas, sync, vloop, block::NoInnerCurrentControl; conv::AbstractTLC) =
    (; m_d = 0.0, m_q = 0.0)

"""
PI inner-current controller for TLC modulation commands.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct InnerCurrentPIControl <: AbstractInnerCurrentTLC
    pi_ctrl::PIControl = PIControl()
end

"""
Return inner-current controller state names.

$(SIGNATURES)
"""
statenames(::InnerCurrentPIControl) = (:ξ_id, :ξ_iq)

"""
Initialize inner-current PI integrator states.

$(SIGNATURES)
"""
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

"""
Evaluate TLC inner-current PI control.

$(SIGNATURES)

# Details

The method writes integrator derivatives and returns current errors plus
stationary-frame modulation commands.
"""
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

    m = inverse_frame_transform(md_c, mq_c, sync.θ_sync)

    return (
        i_d_ref = i_d_ref,
        i_q_ref = i_q_ref,
        e_d = e_d,
        e_q = e_q,
        m_d = m.d,
        m_q = m.q
    )
end
