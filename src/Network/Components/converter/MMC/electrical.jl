export ElectricalMMC

"""
$(TYPEDEF)

Store the twelve-state MMC electrical plant and its physical bases. Arm parameters use
DC bases, and equivalent AC-side parameters use AC bases \\[dimensionless\\]. The keyword
constructor accepts physical parameters and performs this normalization.

$(TYPEDFIELDS)
"""
struct ElectricalMMC <: AbstractStateSpace
    ## Electrical parameters
    "Arm inductance normalized by the DC inductance base \\[dimensionless\\]."
    Lₐᵣₘ :: Float64        # arm inductance [pu]
    "Arm resistance normalized by the DC impedance base \\[dimensionless\\]."
    Rₐᵣₘ :: Float64        # equivalent arm resistance [pu]
    "Submodule capacitance normalized by the DC capacitance base \\[dimensionless\\]."
    Cₐᵣₘ :: Float64        # capacitance per submodule [pu]
    "Number of submodules per arm."
    N :: Int               # number of submodules per arm [-]
    "Transformer converter-side to grid-side voltage ratio \\[dimensionless\\]."
    turnsRatio :: Float64  # Turns ratio of the converter transformer, converter side/AC side [-]

    ## Base values
    "Base electrical angular frequency \\[rad/s\\]."
    ωbase :: Float64        # Base angular frequncy [rad/s]
    "Converter-side AC phase-peak voltage base \\[kV\\]."
    vAC_base :: Float64     # TODO complete this
    "Pole-to-pole DC voltage base \\[kV\\]."
    vDC_base :: Float64
    "Three-phase power base \\[MVA\\]."
    Sbase :: Float64
    "AC impedance base \\[Ω\\]."
    zAC_base :: Float64
    "AC inductance base \\[H\\]."
    lAC_base :: Float64

    # Base conversions
    "AC-to-DC voltage-base ratio \\[dimensionless\\]."
    baseConv1 :: Float64
    "DC-to-AC voltage-base ratio \\[dimensionless\\]."
    baseConv2 :: Float64
    "AC-to-DC current-base ratio \\[dimensionless\\]."
    baseConv3 :: Float64

    # Equivalent resistance and inductance
    "Equivalent AC inductance, including half the arm inductance \\[dimensionless\\]."
    Lₑ :: Float64
    "Equivalent AC resistance, including half the arm resistance \\[dimensionless\\]."
    Rₑ :: Float64 
end

elec_inductance(block::ElectricalMMC) = block.Lₑ
elec_resistance(block::ElectricalMMC) = block.Rₑ


"""
$(TYPEDSIGNATURES)

Construct a `ElectricalMMC` component from the supplied parameters.

# Arguments

- `Lₐᵣₘ`: Physical arm inductance \\[H\\]. Default: `0.05`.
- `Rₐᵣₘ`: Physical arm resistance \\[Ω\\]. Default: `1.07`.
- `Cₐᵣₘ`: Physical submodule capacitance \\[F\\]. Default: `0.01`.
- `N`: Number of submodules per arm. Default: `400`.
- `turnsRatio`: Transformer converter-side to grid-side voltage ratio \\[dimensionless\\].
  Default: `1`.
- `Lᵣ`: Physical converter-side reactor or transformer inductance \\[H\\]. Default:
  `0.06`.
- `Rᵣ`: Physical converter-side reactor or transformer resistance \\[Ω\\]. Default:
  `0.535`.
- `ωbase`: Base electrical angular frequency \\[rad/s\\]. Default: `100π`.
- `vACbase_LL_RMS`: Converter-side line-to-line RMS voltage base \\[kV\\]. Default: `380`.
- `Sbase`: Three-phase power base \\[MVA\\]. Default: `1000`.
- `vDC_base`: Pole-to-pole DC voltage base \\[kV\\]. Default: `640`.

# Returns

- An `ElectricalMMC` instance.

# Notes

```math
V_{ac,b}=\\sqrt{2/3}\\,V_{LL,rms,b},\\quad Z_{ac,b}=\\frac{3V_{ac,b}^2}{2S_b},\\quad L_{ac,b}=Z_{ac,b}/\\omega_b.
```

Voltage inputs use \\[kV\\] and the three-phase power base uses \\[MVA\\], so the resulting
impedance and inductance bases use \\[Ω\\] and \\[H\\]. Stored reactor parameters are
normalized by these bases.

```math
L_e=(L_{arm}/2+L_r)/L_{ac,b},\\quad R_e=(R_{arm}/2+R_r)/Z_{ac,b},\\quad C_{dc,b}=1/(\\omega_b Z_{dc,b}).
```

Arm resistance, arm inductance, and submodule capacitance are normalized using DC bases;
the equivalent AC reactor uses AC bases.

# Examples

```julia
using PowerImpedance
component = ElectricalMMC(Lᵣ=60e-3, Rᵣ=0.535)
```
"""
function ElectricalMMC(;
    ## Elec params
    Lₐᵣₘ = 50e-3,        # arm inductance [H]
    Rₐᵣₘ = 1.07,         # equivalent arm resistance[Ω]
    Cₐᵣₘ = 10e-3,        # capacitance per submodule [F]
    N = 400,             # number of submodules per arm [-]
    turnsRatio  = 1,     # Turns ratio of the converter transformer, converter side/AC side [-]
    Lᵣ = 60e-3,          # inductance of the converter transformer at the converter side [H]
    Rᵣ = 0.535,          # resistance of the converter transformer at the converter side [Ω]

    ## Base values
    ωbase = 100π,
    vACbase_LL_RMS = 380,   # Voltage base LL converter side [kV]
    Sbase = 1000,           # Power base [MW]
    vDC_base = 640)          # DC voltage base [kV])
    
    vAC_base = vACbase_LL_RMS*sqrt(2/3)
    iAC_base = 2*Sbase/3/vAC_base
    iDC_base = Sbase/vDC_base
    zAC_base = (3/2)*vAC_base^2/Sbase
    zDC_base = vDC_base/iDC_base
    lAC_base = zAC_base/ωbase
    lDC_base = zDC_base/ωbase
    cbase = 1/ωbase/zDC_base
    Lₑ = (Lₐᵣₘ / 2 + Lᵣ) / lAC_base
    Rₑ = (Rₐᵣₘ / 2 + Rᵣ) / zAC_base
    Lₐᵣₘ = Lₐᵣₘ / lDC_base
    Rₐᵣₘ = Rₐᵣₘ / zDC_base
    Cₐᵣₘ = Cₐᵣₘ / cbase

    baseConv1 = vAC_base/vDC_base;# AC to DC voltage
    baseConv2 = vDC_base/vAC_base;# DC to AC voltage
    baseConv3 = iAC_base/iDC_base;# AC to DC current

    return ElectricalMMC(Lₐᵣₘ, Rₐᵣₘ, Cₐᵣₘ, N, turnsRatio, ωbase, vAC_base, vDC_base, Sbase, zAC_base, lAC_base, baseConv1, baseConv2, baseConv3, Lₑ, Rₑ)
end

statenames(::ElectricalMMC) = (:iΔ_d, :iΔ_q, :iΣ_d, :iΣ_q, :iΣ_z, 
                    :vCΔ_d, :vCΔ_q, :vCΔ_Zd, :vCΔ_Zq, :vCΣ_d, :vCΣ_q, :vCΣ_z) # Per-unit base for capacitor voltages is vDC_base
"""
$(TYPEDSIGNATURES)

Return the explicitly specified initial states of the component.

# Arguments

- `e`: Normalized MMC plant parameters.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]; its voltage
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
including `iΣ_d`, follow the implemented initialization. Other states are not explicitly
initialized. Electrical quantities use converter bases \\[dimensionless\\].

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
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `data`: Named tuple of electrical input signals and modulation outputs, as shown in
  the example.
- `b`: Normalized MMC plant parameters.
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
All electrical states are normalized \\[dimensionless\\] and derivatives are per second.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC()).element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = model.elec
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
data = (inputs=inputs, sig_in=(vG_d_g=1.0, vG_q_g=0.0),
    out_modulation=(mΔd=-2model.elec.baseConv1, mΔq=0.0, mΔZd=0.0,
        mΔZq=0.0, mΣd=0.0, mΣq=0.0, mΣz=1.0))
P.state_space!(F, x, data, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, data, b::ElectricalMMC, conv::AbstractMMC) 
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
    vMΔd *= conv.elec.baseConv2
    vMΔq *= conv.elec.baseConv2

    # Hard coded equations (old code). Kept for reference --- will be deleted soon
    # vMΔd = conv.elec.baseConv2 * ((mΔq*vCΣ_q)/4 - (mΔd*vCΣ_z)/2 - (mΔd*vCΣ_d)/4 - (mΔZd*vCΣ_d)/4 + (mΔZq*vCΣ_q)/4 - (mΣd*vCΔ_d)/4 - (mΣz*vCΔ_d)/2 +
    #         (mΣq*vCΔ_q)/4 - (mΣd*vCΔ_Zd)/4 + (mΣq*vCΔ_Zq)/4);
    # vMΔq = conv.elec.baseConv2 * ((mΔd*vCΣ_q)/4 + (mΔq*vCΣ_d)/4 - (mΔq*vCΣ_z)/2 - (mΔZd*vCΣ_q)/4 - (mΔZq*vCΣ_d)/4 + (mΣd*vCΔ_q)/4 + (mΣq*vCΔ_d)/4 -
    #         (mΣz*vCΔ_q)/2 - (mΣd*vCΔ_Zq)/4 - (mΣq*vCΔ_Zd)/4);

    # # vMΣd = (mΔd*vCΔ_d)/4 - (mΔq*vCΔ_q)/4 + (mΔd*vCΔ_Zd)/4 + (mΔZd*vCΔ_d)/4 + (mΔq*vCΔ_Zq)/4 + (mΔZq*vCΔ_q)/4 + (mΣd*vCΣ_z)/2 + (mΣz*vCΣ_d)/2;
    # vMΣd =mΔd*vCΔ_d/4 - mΔq*vCΔ_q/4 + mΔd*vCΔ_Zd/4 + mΔZd*vCΔ_d/4 + mΔq*vCΔ_Zq/4 + mΔZq*vCΔ_q/4 + mΣd*vCΣ_z/2 + mΣz*vCΣ_d/2;
    # # vMΣq = (mΔq*vCΔ_Zd)/4 - (mΔq*vCΔ_d)/4 - (mΔd*vCΔ_Zq)/4 - (mΔd*vCΔ_q)/4 + (mΔZd*vCΔ_q)/4 - (mΔZq*vCΔ_d)/4 + (mΣq*vCΣ_z)/2 + (mΣz*vCΣ_q)/2;
    # vMΣq = mΔq*vCΔ_Zd/4 - mΔq*vCΔ_d/4 - mΔd*vCΔ_Zq/4 - mΔd*vCΔ_q/4 + mΔZd*vCΔ_q/4 - mΔZq*vCΔ_d/4 + mΣq*vCΣ_z/2 + mΣz*vCΣ_q/2;
    # # vMΣz = (mΔd*vCΔ_d)/4 + (mΔq*vCΔ_q)/4 + (mΔZd*vCΔ_Zd)/4 + (mΔZq*vCΔ_Zq)/4 + (mΣd*vCΣ_d)/4 + (mΣq*vCΣ_q)/4 + (mΣz*vCΣ_z)/2;
    # vMΣz = mΔd*vCΔ_d/4 + mΔq*vCΔ_q/4 + mΔZd*vCΔ_Zd/4 + mΔZq*vCΔ_Zq/4 + mΣd*vCΣ_d/4 + mΣq*vCΣ_q/4 + mΣz*vCΣ_z/2;


    # diΔ_d_dt =-(vG_d - vMΔd + Rₑ*iΔ_d + Lₑ*iΔ_q*w)/Lₑ, grid frame
    F[1] = -(vG_d - vMΔd + conv.elec.Rₑ*iΔ_d + conv.elec.Lₑ*iΔ_q)/conv.elec.Lₑ;                 
    # diΔ_q_dt =-(vG_q - vMΔq + Rₑ*iΔ_q - Lₑ*iΔ_d*w)/Lₑ, grid frame
    F[2] = -(vG_q - vMΔq + conv.elec.Rₑ*iΔ_q - conv.elec.Lₑ*iΔ_d)/conv.elec.Lₑ;                 
    # diΣ_d_dt =-(vMΣd + Rₐᵣₘ*iΣ_d - 2*Lₐᵣₘ*iΣ_q*w)/Lₐᵣₘ, grid 2w frame
    F[3] = -(vMΣd + conv.elec.Rₐᵣₘ*iΣ_d - 2*conv.elec.Lₐᵣₘ*iΣ_q)/conv.elec.Lₐᵣₘ;                                 
    # diΣ_q_dt =-(vMΣq + Rₐᵣₘ*iΣ_q + 2*Lₐᵣₘ*iΣ_d*w)/Lₐᵣₘ,  grid 2w frame
    F[4] = -(vMΣq + conv.elec.Rₐᵣₘ*iΣ_q + 2*conv.elec.Lₐᵣₘ*iΣ_d)/conv.elec.Lₐᵣₘ;                                  
    # diΣ_z_dt =-(vMΣz - Vᵈᶜ/2 + Rₐᵣₘ*iΣ_z)/Lₐᵣₘ
    F[5] = -(vMΣz - v_dc/2 + conv.elec.Rₐᵣₘ*iΣ_z)/conv.elec.Lₐᵣₘ;                                     
    # dvCΔ_d_dt =(N*(iΣ_z*mΔd - (iΔ_q*mΣq)/4 + iΣ_d*(mΔd/2 + mΔZd/2) - iΣ_q*(mΔq/2 + mΔZq/2) + iΔ_d*(mΣd/4 + mΣz/2) - (2*Cₐᵣₘ*vCΔ_q*w)/N))/(2*Cₐᵣₘ)
    F[6] = (conv.elec.N*(iΣ_z*mΔd - iΔ_q*conv.elec.baseConv3*mΣq/4 + iΣ_d*(mΔd/2 + mΔZd/2) - iΣ_q*(mΔq/2 + mΔZq/2) + iΔ_d*conv.elec.baseConv3*(mΣd/4 + mΣz/2) - 2*conv.elec.Cₐᵣₘ*vCΔ_q/conv.elec.N))/2/conv.elec.Cₐᵣₘ;
    # dvCΔ_q_dt =-(N*((iΔ_d*mΣq)/4 - iΣ_z*mΔq + iΣ_q*(mΔd/2 - mΔZd/2) + iΣ_d*(mΔq/2 - mΔZq/2) + iΔ_q*(mΣd/4 - mΣz/2) - (2*Cₐᵣₘ*vCΔ_d*w)/N))/(2*Cₐᵣₘ)
    F[7] = -(conv.elec.N*((iΔ_d*conv.elec.baseConv3*mΣq)/4 - iΣ_z*mΔq + iΣ_q*(mΔd/2 - mΔZd/2) + iΣ_d*(mΔq/2 - mΔZq/2) + iΔ_q*conv.elec.baseConv3*(mΣd/4 - mΣz/2) - 2*conv.elec.Cₐᵣₘ*vCΔ_d/conv.elec.N))/2/conv.elec.Cₐᵣₘ;
    # dvCΔ_Zd_dt =(N*(iΔ_d*mΣd + 2*iΣ_d*mΔd + iΔ_q*mΣq + 2*iΣ_q*mΔq + 4*iΣ_z*mΔZd))/(8*Cₐᵣₘ) - 3*vCΔ_Zq*w
    F[8] = (conv.elec.N*(iΔ_d*conv.elec.baseConv3*mΣd + 2*iΣ_d*mΔd + iΔ_q*conv.elec.baseConv3*mΣq + 2*iΣ_q*mΔq + 4*iΣ_z*mΔZd))/(8*conv.elec.Cₐᵣₘ) - 3*vCΔ_Zq;
    # dvCΔ_Zq_dt =3*vCΔ_Zd*w + (N*(iΔ_q*mΣd - iΔ_d*mΣq + 2*iΣ_d*mΔq - 2*iΣ_q*mΔd + 4*iΣ_z*mΔZq))/(8*Cₐᵣₘ)
    F[9] = 3*vCΔ_Zd + (conv.elec.N*(iΔ_q*conv.elec.baseConv3*mΣd - iΔ_d*conv.elec.baseConv3*mΣq + 2*iΣ_d*mΔq - 2*iΣ_q*mΔd + 4*iΣ_z*mΔZq))/(8*conv.elec.Cₐᵣₘ);
    # dvCΣ_d_dt =(N*(iΣ_d*mΣz + iΣ_z*mΣd + iΔ_d*(mΔd/4 + mΔZd/4) - iΔ_q*(mΔq/4 - mΔZq/4) + (4*Cₐᵣₘ*vCΣ_q*w)/N))/(2*Cₐᵣₘ)
    F[10] = (conv.elec.N*(iΣ_d*mΣz + iΣ_z*mΣd + iΔ_d*conv.elec.baseConv3*(mΔd/4 + mΔZd/4) - iΔ_q*conv.elec.baseConv3*(mΔq/4 - mΔZq/4) + 4*conv.elec.Cₐᵣₘ*vCΣ_q/conv.elec.N))/(2*conv.elec.Cₐᵣₘ);
    # dvCΣ_q_dt =-(N*(iΔ_q*(mΔd/4 - mΔZd/4) - iΣ_z*mΣq - iΣ_q*mΣz + iΔ_d*(mΔq/4 + mΔZq/4) + (4*Cₐᵣₘ*vCΣ_d*w)/N))/(2*Cₐᵣₘ)
    F[11] = -(conv.elec.N*(iΔ_q*conv.elec.baseConv3*(mΔd/4 - mΔZd/4) - iΣ_z*mΣq - iΣ_q*mΣz + iΔ_d*conv.elec.baseConv3*(mΔq/4 + mΔZq/4) + 4*conv.elec.Cₐᵣₘ*vCΣ_d/conv.elec.N))/(2*conv.elec.Cₐᵣₘ);
    # dvCΣ_z_dt =(N*(iΔ_d*mΔd + iΔ_q*mΔq + 2*iΣ_d*mΣd + 2*iΣ_q*mΣq + 4*iΣ_z*mΣz))/(8*Cₐᵣₘ)
    F[12] = (conv.elec.N*(iΔ_d*conv.elec.baseConv3*mΔd + iΔ_q*conv.elec.baseConv3*mΔq + 2*iΣ_d*mΣd + 2*iΣ_q*mΣq + 4*iΣ_z*mΣz))/(8*conv.elec.Cₐᵣₘ);
    F[1:12] *= conv.elec.ωbase

end
