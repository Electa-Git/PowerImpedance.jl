############################  electrical.jl  ############################

#=
Electrical plant model for the two-level converter (TLC).

This file contains the converter-side electrical state equations and terminal
output calculations. It is intentionally TLC-specific; reusable control and
measurement primitives live under `converter/common`.
=#

export ElectricalTLC

"""
Electrical parameters and states of the TLC reactor model.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct ElectricalTLC <: AbstractStateSpace
    Lᵣ::Float64
    Rᵣ::Float64

    # Base values
    ωbase::Float64

    Sbase::Float64
    vDCbase::Float64
    zACbase::Float64
    iDCbase::Float64 
    vACbase::Float64 
    iACbase::Float64 
end

elec_inductance(block::ElectricalTLC) = block.Lᵣ
elec_resistance(block::ElectricalTLC) = block.Rᵣ

function ElectricalTLC(; 
    ωbase = 100 * π,

    Lᵣ = 60e-3,
    Rᵣ = 0.535,

    vACbase_LL_RMS = 220.0,
    Sbase = 500.0,
    vDCbase = 640.0,
)
    vACbase = vACbase_LL_RMS * sqrt(2 / 3)
    zACbase = (3 / 2) * vACbase^2 / Sbase
    lACbase = zACbase / ωbase

    iACbase = 2 * Sbase / (3 * vACbase)
    iDCbase = Sbase / vDCbase

    Rᵣ = Rᵣ / zACbase
    Lᵣ = Lᵣ / lACbase

    return ElectricalTLC(Lᵣ, Rᵣ, ωbase, Sbase, vDCbase, zACbase, iDCbase, vACbase, iACbase)

end


"""
Return electrical state names.

$(SIGNATURES)
"""
statenames(::ElectricalTLC) = (:i_d, :i_q)

"""
Compute initial current states from power-flow inputs and setpoints.

$(SIGNATURES)
"""
function initialvalues(block::ElectricalTLC; inputs, setpoint_pu=SetPoint())
    v_d = inputs.vG_d
    v_q = inputs.vG_q

    V2 = v_d^2 + v_q^2
    iszero(V2) && return (i_d = 0.0, i_q = 0.0)

    p_ac = setpoint_pu.p_ac
    q_ac = setpoint_pu.q_ac

    i_d0 = (v_d * p_ac + v_q * q_ac) / V2
    i_q0 = (v_q * p_ac - v_d * q_ac) / V2

    return (iΔ_d = i_d0, iΔ_q = i_q0)
end


"""
Evaluate the TLC reactor current dynamics and electrical outputs.

$(SIGNATURES)

# Details

The method writes derivatives for `i_d` and `i_q` and returns the DC current
and AC currents used by output equations and downstream reporting.
"""
function state_space!(F, x, data, block::ElectricalTLC, conv::AbstractTLC)
    (; inputs, mod) = data
    Rᵣ = block.Rᵣ
    Lᵣ = block.Lᵣ

    i_d = x.i_d
    i_q = x.i_q

    vMd = 0.5 * inputs.v_dc * mod.m_d
    vMq = 0.5 * inputs.v_dc * mod.m_q

    i_dc = iszero(inputs.v_dc) ? 0.0 : (vMd * i_d + vMq * i_q) / inputs.v_dc

    F[1] = block.ωbase * (vMd - inputs.vG_d - Rᵣ * i_d - Lᵣ * i_q) / Lᵣ
    F[2] = block.ωbase * (vMq - inputs.vG_q - Rᵣ * i_q + Lᵣ * i_d) / Lᵣ

    return (
        i_dc = i_dc,
        i_d = i_d,
        i_q = i_q
    )
end
