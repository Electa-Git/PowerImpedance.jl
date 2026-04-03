############################  electrical.jl  ############################

@with_kw struct ElectricalTLC <: AbstractStateSpace
    ω₀::Float64 = 100 * π

    θ::Float64 = 0.0
    Vₘ::Float64 = 333.0
    Vᵈᶜ::Float64 = 640.0

    Lᵣ::Float64 = 60e-3
    Rᵣ::Float64 = 0.535

    vACbase_LL_RMS::Float64 = 220.0
    Sbase::Float64 = 500.0
    vDCbase::Float64 = 640.0

    iDCbase::Float64 = 0.0
    vACbase::Float64 = 0.0
    iACbase::Float64 = 0.0
end

statenames(::ElectricalTLC) = (:i_d, :i_q)

function initialvalues(block::ElectricalTLC; inputs, setpoint=SetPoint(), kwargs...)
    v_d = inputs.v_d
    v_q = inputs.v_q

    V2 = v_d^2 + v_q^2
    iszero(V2) && return (i_d = 0.0, i_q = 0.0)

    P = setpoint.Pac / block.Sbase
    Q = -setpoint.Qac / block.Sbase   # keep legacy sign convention

    i_d0 = (v_d * P + v_q * Q) / V2
    i_q0 = (v_q * P - v_d * Q) / V2

    return (i_d = i_d0, i_q = i_q0)
end

function electrical_outputs(block::ElectricalTLC, x, inputs, mod)
    i_d = x.i_d
    i_q = x.i_q

    vMd = 0.5 * inputs.vdc * mod.m_d
    vMq = 0.5 * inputs.vdc * mod.m_q

    idc = iszero(inputs.vdc) ? 0.0 : (vMd * i_d + vMq * i_q) / inputs.vdc

    return (
        idc = idc,
        i_d = i_d,
        i_q = i_q
    )
end

function measurements(block::ElectricalTLC, x, inputs, mod)
    y = electrical_outputs(block, x, inputs, mod)

    return (
        v_d = inputs.v_d,
        v_q = inputs.v_q,
        vdc = inputs.vdc,
        i_d = y.i_d,
        i_q = y.i_q,
        idc = y.idc,
        θ   = block.θ
    )
end

function state_space!(F, x, inputs, mod, block::ElectricalTLC; conv::AbstractTLC)
    vACbase = block.vACbase_LL_RMS * sqrt(2 / 3)
    zACbase = (3 / 2) * vACbase^2 / block.Sbase
    lACbase = zACbase / block.ω₀

    Rᵣ = block.Rᵣ / zACbase
    Lᵣ = block.Lᵣ / lACbase

    i_d = x.i_d
    i_q = x.i_q

    vMd = 0.5 * inputs.vdc * mod.m_d
    vMq = 0.5 * inputs.vdc * mod.m_q

    F[1] = block.ω₀ * (vMd - inputs.v_d - Rᵣ * i_d - Lᵣ * i_q) / Lᵣ
    F[2] = block.ω₀ * (vMq - inputs.v_q - Rᵣ * i_q + Lᵣ * i_d) / Lᵣ

    return nothing
end