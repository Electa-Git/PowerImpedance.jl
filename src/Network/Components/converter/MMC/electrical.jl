export ElectricalMMC

"""
$(TYPEDEF)

Store physical circuit parameters of the twelve-state MMC electrical plant.
The state equations normalize arm parameters with DC bases and equivalent AC parameters
with AC bases from the parent model through `perunit(elec, bases)`.

$(TYPEDFIELDS)
"""
@with_kw struct ElectricalMMC <: AbstractStateSpace
    "Physical arm inductance \\[H\\]."
    Lₐᵣₘ::Float64 = 50e-3
    "Physical arm resistance \\[Ω\\]."
    Rₐᵣₘ::Float64 = 1.07
    "Physical submodule capacitance \\[F\\]."
    Cₐᵣₘ::Float64 = 10e-3
    "Number of submodules per arm."
    N::Int = 400
    "Transformer converter-side to grid-side voltage ratio \\[dimensionless\\]."
    turnsRatio::Float64 = 1
    "Physical converter-side reactor or transformer inductance \\[H\\]."
    Lᵣ::Float64 = 60e-3
    "Physical converter-side reactor or transformer resistance \\[Ω\\]."
    Rᵣ::Float64 = 0.535
end

"""
$(TYPEDSIGNATURES)

Compute MMC per-unit electrical parameters from physical circuit values and model bases.

# Arguments

- `e`: Physical MMC circuit parameters.
- `b`: Parent-model power \\[MVA\\], voltage \\[kV\\] and frequency \\[rad/s\\] bases.

# Returns

- Normalized arm parameters `Lₐᵣₘ`, `Rₐᵣₘ`, `Cₐᵣₘ`, equivalent AC parameters
  `Lₑ`, `Rₑ` and ratios `baseConv1`, `baseConv2`, `baseConv3` \\[dimensionless\\].
- `zAC_base`: AC impedance base \\[Ω\\].
- `lAC_base`: AC inductance base \\[H\\].

# Notes

The AC equivalent includes half the arm impedance. Normalization follows

```math
Z_{ac,b}=\\frac{3V_{ac,b}^2}{2S_b},\\quad
L_{ac,b}=Z_{ac,b}/\\omega_b,\\quad
L_e=(L_{arm}/2+L_r)/L_{ac,b},\\quad
R_e=(R_{arm}/2+R_r)/Z_{ac,b}.
```

Arm quantities use DC bases. The parent model stores the power, voltage and
angular-frequency bases. The electrical submodel stores physical circuit values.
"""
function perunit(e::ElectricalMMC, b::BaseValues)
    iAC_base = 2*b.S/3/b.v_ac
    iDC_base = b.S/b.v_dc
    zAC_base = (3/2)*b.v_ac^2/b.S
    zDC_base = b.v_dc/iDC_base
    lAC_base = zAC_base/b.omega
    lDC_base = zDC_base/b.omega
    cbase = 1/b.omega/zDC_base
    Lₑ = (e.Lₐᵣₘ / 2 + e.Lᵣ) / lAC_base
    Rₑ = (e.Rₐᵣₘ / 2 + e.Rᵣ) / zAC_base
    Lₐᵣₘ = e.Lₐᵣₘ / lDC_base
    Rₐᵣₘ = e.Rₐᵣₘ / zDC_base
    Cₐᵣₘ = e.Cₐᵣₘ / cbase
    baseConv1 = b.v_ac/b.v_dc
    baseConv2 = b.v_dc/b.v_ac
    baseConv3 = iAC_base/iDC_base
    return (; Lₐᵣₘ, Rₐᵣₘ, Cₐᵣₘ, zAC_base, lAC_base,
        baseConv1, baseConv2, baseConv3, Lₑ, Rₑ)
end

elec_inductance(block::ElectricalMMC, b::BaseValues) = perunit(block, b).Lₑ
elec_resistance(block::ElectricalMMC, b::BaseValues) = perunit(block, b).Rₑ


statenames(::ElectricalMMC) = (:iΔ_d, :iΔ_q, :iΣ_d, :iΣ_q, :iΣ_z, 
                    :vCΔ_d, :vCΔ_q, :vCΔ_Zd, :vCΔ_Zq, :vCΣ_d, :vCΣ_q, :vCΣ_z)
# Capacitor-voltage states use the parent model DC voltage base.
"""
$(TYPEDSIGNATURES)

Return the explicitly specified initial states of the component.

# Arguments

- `e`: Physical MMC circuit parameters.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]. Its voltage
  angle uses \\[rad\\].

# Returns

- `iΔ_d`: Initial d-axis differential current \\[dimensionless\\].
- `iΔ_q`: Initial q-axis differential current \\[dimensionless\\].
- `iΣ_d`: Initial circulating-current coordinate computed from DC power
  \\[dimensionless\\].
- `vCΣ_z`: Initial zero-sequence summed capacitor voltage \\[dimensionless\\].

# Notes

```math
i_{\\Delta d}=(v_d p-v_q q)/(v_d^2+v_q^2),\\quad i_{\\Delta q}=(v_q p+v_d q)/(v_d^2+v_q^2),\\quad i_{\\Sigma d}=p_{dc}/(3v_{dc}),\\quad v_{C\\Sigma z}=v_{dc}.
```

The AC voltage components include the transformer turns ratio. The returned keys,
including `iΣ_d`, follow the implemented initialization. Other states use the default
initializer. Electrical quantities use converter bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
model = ElectricalMMC()
initial = P.initialvalues(model; inputs, terminal_pu=point)
```
"""
initialvalues(e::ElectricalMMC; inputs, terminal_pu) = (;
    iΔ_d = (inputs.vG_d * e.turnsRatio * terminal_pu.p_ac -
        inputs.vG_q * e.turnsRatio * terminal_pu.q_ac) /
        ( (inputs.vG_d * e.turnsRatio)^2 + (inputs.vG_q * e.turnsRatio)^2 ),
    iΔ_q = (inputs.vG_q * e.turnsRatio * terminal_pu.p_ac +
        inputs.vG_d * e.turnsRatio * terminal_pu.q_ac) /
        ( (inputs.vG_d * e.turnsRatio)^2 + (inputs.vG_q * e.turnsRatio)^2 ),
    iΣ_d = terminal_pu.p_dc / 3 /inputs.v_dc,
    vCΣ_z = inputs.v_dc)


    
"""
$(TYPEDSIGNATURES)

Evaluate MMC electrical plant derivatives, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `data`: Named tuple of electrical input signals and modulation outputs, as shown in
  the example.
- `b`: Physical MMC circuit parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- The twelve-entry assigned derivative slice in normalized electrical coordinates per
  second \\[s⁻¹\\].

# Notes

```math
\\dot i_{\\Delta d}=\\frac{\\omega_b}{L_e}(v_{M\\Delta d}-v_{Gd}-R_e i_{\\Delta d}-L_e i_{\\Delta q}),\\quad \\dot i_{\\Sigma z}=\\frac{\\omega_b}{L_{arm}}(v_{dc}/2-v_{M\\Sigma z}-R_{arm}i_{\\Sigma z}).
```

The plant writes twelve differential equations: five current and seven capacitor-voltage
states. The inserted voltages are the implemented seven-by-seven capacitor-voltage
coupling matrix times the insertion-index vector, with explicit AC/DC base conversion.
Electrical states are normalized \\[dimensionless\\] and derivatives are per second.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = model.elec
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
data = (inputs=inputs, sig_in=(vG_d_g=1.0, vG_q_g=0.0),
    out_modulation=(mΔd=-2 * P.perunit(model.elec, model.bases).baseConv1, mΔq=0.0,
        mΔZd=0.0, mΔZq=0.0, mΣd=0.0, mΣq=0.0, mΣz=1.0))
P.state_space!(F, x, data, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, data, b::ElectricalMMC, conv::AbstractMMC) 
    pu = perunit(b, conv.bases)
    (; out_modulation, sig_in, inputs) = data
    
    (; iΔ_d, iΔ_q, iΣ_d, iΣ_q, iΣ_z, vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; mΔd, mΔq, mΔZd, mΔZq, mΣd, mΣq, mΣz) = out_modulation
    v_dc = inputs.v_dc
    (; vG_d_g, vG_q_g) = sig_in
    vG_d, vG_q = vG_d_g, vG_q_g # Everything in grid reference frame for the electrical equations

    # Matrix from Freytes thesis
    VΣΔ_CmdqZ = 1/4 * [ 2 * vCΣ_z       0              2 * vCΣ_d               vCΔ_d + vCΔ_Zd       vCΔ_Zq - vCΔ_q       vCΔ_d       vCΔ_q
                        0              2 * vCΣ_z       2 * vCΣ_q               -vCΔ_q - vCΔ_Zq      vCΔ_Zd - vCΔ_d       vCΔ_q       -vCΔ_d
                        vCΣ_d           vCΣ_q           2 * vCΣ_z               vCΔ_d               vCΔ_q               vCΔ_Zd      vCΔ_Zq
                        -vCΔ_d - vCΔ_Zd  vCΔ_q + vCΔ_Zq   -2 * vCΔ_d              -vCΣ_d - 2 * vCΣ_z   vCΣ_q               -vCΣ_d      vCΣ_q
                        vCΔ_q - vCΔ_Zq   vCΔ_d - vCΔ_Zd   -2 * vCΔ_q              vCΣ_q               vCΣ_d - 2 * vCΣ_z    -vCΣ_q      -vCΣ_d
                        -vCΔ_d          -vCΔ_q          -2 * vCΔ_Zd             -vCΣ_d              -vCΣ_q              -2 * vCΣ_z  0
                        -vCΔ_q          vCΔ_d           -2 * vCΔ_Zq             vCΣ_q               -vCΣ_d              0          -2 * vCΣ_z]
    
    (vMΣd, vMΣq, vMΣz, vMΔd, vMΔq, _, _) = VΣΔ_CmdqZ * [mΣd; mΣq; mΣz; mΔd; mΔq; mΔZd; mΔZq]
    vMΔd *= pu.baseConv2
    vMΔq *= pu.baseConv2

    # Reference equations
    # ```julia
    # vMΔd = pu.baseConv2 * ((mΔq*vCΣ_q)/4 - (mΔd*vCΣ_z)/2 - (mΔd*vCΣ_d)/4 - (mΔZd*vCΣ_d)/4 + (mΔZq*vCΣ_q)/4 - (mΣd*vCΔ_d)/4 - (mΣz*vCΔ_d)/2 +
    #         (mΣq*vCΔ_q)/4 - (mΣd*vCΔ_Zd)/4 + (mΣq*vCΔ_Zq)/4);
    # vMΔq = pu.baseConv2 * ((mΔd*vCΣ_q)/4 + (mΔq*vCΣ_d)/4 - (mΔq*vCΣ_z)/2 - (mΔZd*vCΣ_q)/4 - (mΔZq*vCΣ_d)/4 + (mΣd*vCΔ_q)/4 + (mΣq*vCΔ_d)/4 -
    #         (mΣz*vCΔ_q)/2 - (mΣd*vCΔ_Zq)/4 - (mΣq*vCΔ_Zd)/4);
    # ```

    # ```julia
    # # vMΣd = (mΔd*vCΔ_d)/4 - (mΔq*vCΔ_q)/4 + (mΔd*vCΔ_Zd)/4 + (mΔZd*vCΔ_d)/4 + (mΔq*vCΔ_Zq)/4 + (mΔZq*vCΔ_q)/4 + (mΣd*vCΣ_z)/2 + (mΣz*vCΣ_d)/2;
    # vMΣd =mΔd*vCΔ_d/4 - mΔq*vCΔ_q/4 + mΔd*vCΔ_Zd/4 + mΔZd*vCΔ_d/4 + mΔq*vCΔ_Zq/4 + mΔZq*vCΔ_q/4 + mΣd*vCΣ_z/2 + mΣz*vCΣ_d/2;
    # # vMΣq = (mΔq*vCΔ_Zd)/4 - (mΔq*vCΔ_d)/4 - (mΔd*vCΔ_Zq)/4 - (mΔd*vCΔ_q)/4 + (mΔZd*vCΔ_q)/4 - (mΔZq*vCΔ_d)/4 + (mΣq*vCΣ_z)/2 + (mΣz*vCΣ_q)/2;
    # vMΣq = mΔq*vCΔ_Zd/4 - mΔq*vCΔ_d/4 - mΔd*vCΔ_Zq/4 - mΔd*vCΔ_q/4 + mΔZd*vCΔ_q/4 - mΔZq*vCΔ_d/4 + mΣq*vCΣ_z/2 + mΣz*vCΣ_q/2;
    # # vMΣz = (mΔd*vCΔ_d)/4 + (mΔq*vCΔ_q)/4 + (mΔZd*vCΔ_Zd)/4 + (mΔZq*vCΔ_Zq)/4 + (mΣd*vCΣ_d)/4 + (mΣq*vCΣ_q)/4 + (mΣz*vCΣ_z)/2;
    # vMΣz = mΔd*vCΔ_d/4 + mΔq*vCΔ_q/4 + mΔZd*vCΔ_Zd/4 + mΔZq*vCΔ_Zq/4 + mΣd*vCΣ_d/4 + mΣq*vCΣ_q/4 + mΣz*vCΣ_z/2;
    # ```


    # diΔ_d_dt =-(vG_d - vMΔd + Rₑ*iΔ_d + Lₑ*iΔ_q*w)/Lₑ, grid frame
    F[1] = -(vG_d - vMΔd + pu.Rₑ*iΔ_d + pu.Lₑ*iΔ_q)/pu.Lₑ;
    # diΔ_q_dt =-(vG_q - vMΔq + Rₑ*iΔ_q - Lₑ*iΔ_d*w)/Lₑ, grid frame
    F[2] = -(vG_q - vMΔq + pu.Rₑ*iΔ_q - pu.Lₑ*iΔ_d)/pu.Lₑ;
    # diΣ_d_dt =-(vMΣd + Rₐᵣₘ*iΣ_d - 2*Lₐᵣₘ*iΣ_q*w)/Lₐᵣₘ, grid 2w frame
    F[3] = -(vMΣd + pu.Rₐᵣₘ*iΣ_d - 2*pu.Lₐᵣₘ*iΣ_q)/pu.Lₐᵣₘ;
    # diΣ_q_dt =-(vMΣq + Rₐᵣₘ*iΣ_q + 2*Lₐᵣₘ*iΣ_d*w)/Lₐᵣₘ,  grid 2w frame
    F[4] = -(vMΣq + pu.Rₐᵣₘ*iΣ_q + 2*pu.Lₐᵣₘ*iΣ_d)/pu.Lₐᵣₘ;
    # diΣ_z_dt =-(vMΣz - Vᵈᶜ/2 + Rₐᵣₘ*iΣ_z)/Lₐᵣₘ
    F[5] = -(vMΣz - v_dc/2 + pu.Rₐᵣₘ*iΣ_z)/pu.Lₐᵣₘ;
    # dvCΔ_d_dt =(N*(iΣ_z*mΔd - (iΔ_q*mΣq)/4 + iΣ_d*(mΔd/2 + mΔZd/2) - iΣ_q*(mΔq/2 + mΔZq/2) + iΔ_d*(mΣd/4 + mΣz/2) - (2*Cₐᵣₘ*vCΔ_q*w)/N))/(2*Cₐᵣₘ)
    F[6] = (conv.elec.N*(iΣ_z*mΔd - iΔ_q*pu.baseConv3*mΣq/4 + iΣ_d*(mΔd/2 + mΔZd/2) -
        iΣ_q*(mΔq/2 + mΔZq/2) + iΔ_d*pu.baseConv3*(mΣd/4 + mΣz/2) -
        2*pu.Cₐᵣₘ*vCΔ_q/conv.elec.N))/2/pu.Cₐᵣₘ;
    # dvCΔ_q_dt =-(N*((iΔ_d*mΣq)/4 - iΣ_z*mΔq + iΣ_q*(mΔd/2 - mΔZd/2) + iΣ_d*(mΔq/2 - mΔZq/2) + iΔ_q*(mΣd/4 - mΣz/2) - (2*Cₐᵣₘ*vCΔ_d*w)/N))/(2*Cₐᵣₘ)
    F[7] = -(conv.elec.N*((iΔ_d*pu.baseConv3*mΣq)/4 - iΣ_z*mΔq + iΣ_q*(mΔd/2 -
        mΔZd/2) + iΣ_d*(mΔq/2 - mΔZq/2) + iΔ_q*pu.baseConv3*(mΣd/4 - mΣz/2) -
        2*pu.Cₐᵣₘ*vCΔ_d/conv.elec.N))/2/pu.Cₐᵣₘ;
    # dvCΔ_Zd_dt =(N*(iΔ_d*mΣd + 2*iΣ_d*mΔd + iΔ_q*mΣq + 2*iΣ_q*mΔq + 4*iΣ_z*mΔZd))/(8*Cₐᵣₘ) - 3*vCΔ_Zq*w
    F[8] = (conv.elec.N*(iΔ_d*pu.baseConv3*mΣd + 2*iΣ_d*mΔd + iΔ_q*pu.baseConv3*mΣq +
        2*iΣ_q*mΔq + 4*iΣ_z*mΔZd))/(8*pu.Cₐᵣₘ) - 3*vCΔ_Zq;
    # dvCΔ_Zq_dt =3*vCΔ_Zd*w + (N*(iΔ_q*mΣd - iΔ_d*mΣq + 2*iΣ_d*mΔq - 2*iΣ_q*mΔd + 4*iΣ_z*mΔZq))/(8*Cₐᵣₘ)
    F[9] = 3*vCΔ_Zd + (conv.elec.N*(iΔ_q*pu.baseConv3*mΣd - iΔ_d*pu.baseConv3*mΣq +
        2*iΣ_d*mΔq - 2*iΣ_q*mΔd + 4*iΣ_z*mΔZq))/(8*pu.Cₐᵣₘ);
    # dvCΣ_d_dt =(N*(iΣ_d*mΣz + iΣ_z*mΣd + iΔ_d*(mΔd/4 + mΔZd/4) - iΔ_q*(mΔq/4 - mΔZq/4) + (4*Cₐᵣₘ*vCΣ_q*w)/N))/(2*Cₐᵣₘ)
    F[10] = (conv.elec.N*(iΣ_d*mΣz + iΣ_z*mΣd + iΔ_d*pu.baseConv3*(mΔd/4 + mΔZd/4) -
        iΔ_q*pu.baseConv3*(mΔq/4 - mΔZq/4) + 4*pu.Cₐᵣₘ*vCΣ_q/conv.elec.N))/(2*pu.Cₐᵣₘ);
    # dvCΣ_q_dt =-(N*(iΔ_q*(mΔd/4 - mΔZd/4) - iΣ_z*mΣq - iΣ_q*mΣz + iΔ_d*(mΔq/4 + mΔZq/4) + (4*Cₐᵣₘ*vCΣ_d*w)/N))/(2*Cₐᵣₘ)
    F[11] = -(conv.elec.N*(iΔ_q*pu.baseConv3*(mΔd/4 - mΔZd/4) - iΣ_z*mΣq - iΣ_q*mΣz +
        iΔ_d*pu.baseConv3*(mΔq/4 + mΔZq/4) + 4*pu.Cₐᵣₘ*vCΣ_d/conv.elec.N))/(2*pu.Cₐᵣₘ);
    # dvCΣ_z_dt =(N*(iΔ_d*mΔd + iΔ_q*mΔq + 2*iΣ_d*mΣd + 2*iΣ_q*mΣq + 4*iΣ_z*mΣz))/(8*Cₐᵣₘ)
    F[12] = (conv.elec.N*(iΔ_d*pu.baseConv3*mΔd + iΔ_q*pu.baseConv3*mΔq + 2*iΣ_d*mΣd +
        2*iΣ_q*mΣq + 4*iΣ_z*mΣz))/(8*pu.Cₐᵣₘ);
    F[1:12] *= conv.bases.omega

end
