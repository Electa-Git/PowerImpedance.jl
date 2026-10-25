# electrical.jl

#=
Electrical plant model for the two-level converter (TLC).

This file contains the TLC converter-side electrical state equations and terminal
output calculations. Reusable control and measurement primitives live under
`converter/common`.
=#

export ElectricalTLC

"""
$(TYPEDEF)

Electrical parameters and states of the TLC reactor model.

$(TYPEDFIELDS)
"""
struct ElectricalTLC <: AbstractStateSpace
    "Reactor inductance normalized by the AC inductance base \\[dimensionless\\]."
    Lᵣ::Float64
    "Reactor resistance normalized by the AC impedance base \\[dimensionless\\]."
    Rᵣ::Float64

    # Base values
    "Base electrical angular frequency \\[rad/s\\]."
    ωbase::Float64

    "Three-phase power base \\[MVA\\]."
    Sbase::Float64
    "Pole-to-pole DC voltage base \\[kV\\]."
    vDCbase::Float64
    "AC impedance base \\[Ω\\]."
    zACbase::Float64
    "AC inductance base \\[H\\]."
    lACbase::Float64
    "DC current base \\[kA\\]."
    iDCbase::Float64 
    "AC phase-peak voltage base \\[kV\\]."
    vACbase::Float64 
    "AC phase-peak current base \\[kA\\]."
    iACbase::Float64 
end

elec_inductance(block::ElectricalTLC) = block.Lᵣ
elec_resistance(block::ElectricalTLC) = block.Rᵣ

"""
$(TYPEDSIGNATURES)

Construct a `ElectricalTLC` component from the supplied parameters.

# Arguments

- `ωbase`: Base electrical angular frequency \\[rad/s\\]. Default: `100π`.
- `Lᵣ`: Physical converter-side reactor or transformer inductance \\[H\\]. Default:
  `0.06`.
- `Rᵣ`: Physical converter-side reactor or transformer resistance \\[Ω\\]. Default:
  `0.535`.
- `vACbase_LL_RMS`: Converter-side line-to-line RMS voltage base \\[kV\\]. Default:
  `220.0`.
- `Sbase`: Three-phase power base \\[MVA\\]. Default: `500.0`.
- `vDCbase`: Pole-to-pole DC voltage base \\[kV\\]. Default: `640.0`.

# Returns

- An `ElectricalTLC` instance.

# Notes

```math
V_{ac,b}=\\sqrt{2/3}\\,V_{LL,rms,b},\\quad Z_{ac,b}=\\frac{3V_{ac,b}^2}{2S_b},\\quad L_{ac,b}=Z_{ac,b}/\\omega_b.
```

Voltage inputs use \\[kV\\] and the three-phase power base uses \\[MVA\\], so the resulting
impedance and inductance bases use \\[Ω\\] and \\[H\\]. Stored reactor parameters are
normalized by these bases.

# Examples

```julia
using PowerImpedance
component = ElectricalTLC(Lᵣ=60e-3, Rᵣ=0.535)
```
"""
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

    return ElectricalTLC(Lᵣ, Rᵣ, ωbase, Sbase, vDCbase, zACbase, lACbase, iDCbase, vACbase, iACbase)

end


"""
$(TYPEDSIGNATURES)

Return the TLC reactor state names in derivative order.

# Arguments

- `::ElectricalTLC`: TLC electrical plant.

# Returns

- `(:i_d, :i_q)`: Names of the normalized d/q reactor currents.

# Notes

Other blocks specialize this interface. Composite models concatenate their block state
names in equation order.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
names = P.statenames(ElectricalTLC())
@assert names == (:i_d, :i_q)
```
"""
statenames(::ElectricalTLC) = (:i_d, :i_q)

"""
$(TYPEDSIGNATURES)

Compute initial current states from power-flow inputs and terminal values.

# Arguments

- `block`: Normalized TLC reactor parameters.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]. Its voltage
  angle uses \\[rad\\]. Default: `TerminalValuesPU()`.

# Returns

- `i_d`: Initial d-axis reactor current \\[dimensionless\\].
- `i_q`: Initial q-axis reactor current \\[dimensionless\\].

# Notes

```math
i_d=(v_d p+v_q q)/(v_d^2+v_q^2),\\qquad i_q=(v_q p-v_d q)/(v_d^2+v_q^2).
```

Voltages, powers, and currents use TLC bases \\[dimensionless\\]. The method returns zero
currents for zero voltage magnitude.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
model = ElectricalTLC()
initial = P.initialvalues(model; inputs, terminal_pu=point)
```
"""
function initialvalues(block::ElectricalTLC; inputs, terminal_pu=TerminalValuesPU())
    v_d = inputs.vG_d
    v_q = inputs.vG_q

    V2 = v_d^2 + v_q^2
    iszero(V2) && return (i_d = 0.0, i_q = 0.0)

    p_ac = terminal_pu.p_ac
    q_ac = terminal_pu.q_ac

    i_d0 = (v_d * p_ac + v_q * q_ac) / V2
    i_q0 = (v_q * p_ac - v_d * q_ac) / V2

    return (i_d = i_d0, i_q = i_q0)
end


"""
$(TYPEDSIGNATURES)

Evaluate the TLC reactor current dynamics and electrical outputs.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `data`: Named tuple of electrical input signals and modulation outputs, as shown in
  the example.
- `block`: Normalized TLC reactor parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `i_dc`: Terminal current \\[dimensionless\\].
- `i_d`: Terminal current \\[dimensionless\\].
- `i_q`: Terminal current \\[dimensionless\\].

# Notes

The method writes derivatives for `i_d` and `i_q` and returns the DC current
and AC currents used by output equations and downstream reporting.

```math
\\dot i_d=\\frac{\\omega_b}{L}(v_{Md}-v_{Gd}-Ri_d-Li_q),\\quad \\dot i_q=\\frac{\\omega_b}{L}(v_{Mq}-v_{Gq}-Ri_q+Li_d),\\quad i_{dc}=\\frac{v_{Md}i_d+v_{Mq}i_q}{v_{dc}}.
```

Modulated voltages are ``v_{Md,q}=v_{dc}m_{d,q}/2``. Electrical quantities use converter
bases \\[dimensionless\\] and ``ω_b`` uses \\[rad/s\\]. The DC-current output is zero for
zero DC input voltage.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = model.elec
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
data = (inputs=inputs, mod=(m_d=2.0, m_q=0.0))
outputs = P.state_space!(F, x, data, block, model)
@assert all(isfinite, F)
```
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
