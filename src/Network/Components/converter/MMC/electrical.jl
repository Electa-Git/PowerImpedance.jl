struct ElectricalMMC <: AbstractStateSpace
    ## Electrical parameters
    Lₐᵣₘ :: Float64        # arm inductance [pu]
    Rₐᵣₘ :: Float64        # equivalent arm resistance [pu]
    Cₐᵣₘ :: Float64        # capacitance per submodule [pu]
    N :: Int               # number of submodules per arm [-]
    turnsRatio :: Float64  # Turns ratio of the converter transformer, converter side/AC side [-]

    ## Base values
    ωbase :: Float64        # Base angular frequncy [rad/s]
    vAC_base :: Float64     # TODO complete this
    vDC_base :: Float64
    Sbase :: Float64

    # Base conversions
    baseConv1 :: Float64
    baseConv2 :: Float64
    baseConv3 :: Float64

    # Equivalent resistance and inductance
    Lₑ :: Float64
    Rₑ :: Float64 
end

elec_inductance(block::ElectricalMMC) = block.Lₑ
elec_resistance(block::ElectricalMMC) = block.Rₑ


function ElectricalMMC(
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

    return ElectricalMMC(Lₐᵣₘ, Rₐᵣₘ, Cₐᵣₘ, N, turnsRatio, ωbase, vAC_base, vDC_base, Sbase, baseConv1, baseConv2, baseConv3, Lₑ, Rₑ)
end

statenames(::ElectricalMMC) = (:iΔ_d, :iΔ_q, :iΣ_d, :iΣ_q, :iΣ_z, :vCΔ_d, :vCΔ_q, :vCΔ_Zd, :vCΔ_Zq, :vCΣ_d, :vCΣ_q, :vCΣ_z)
initialvalues(e::ElectricalMMC; inputs, setpoint_pu) = (; 
    iΔ_d = (inputs.vG_d * e.turnsRatio * setpoint_pu.p_ac - inputs.vG_q * e.turnsRatio * setpoint_pu.q_ac) / ( (inputs.vG_d * e.turnsRatio)^2 + (inputs.vG_q * e.turnsRatio)^2 ),
    iΔ_q = (inputs.vG_q * e.turnsRatio * setpoint_pu.p_ac + inputs.vG_d * e.turnsRatio * setpoint_pu.q_ac) / ( (inputs.vG_d * e.turnsRatio)^2 + (inputs.vG_q * e.turnsRatio)^2 ),
    iΣ_d = setpoint_pu.p_dc / 3 /inputs.v_dc,
    vCΣ_z = inputs.v_dc)


    
function state_space!(F, x, (out_modulation, sig_in, inputs), b::ElectricalMMC, conv::AbstractMMC) 
    
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
    F[1] = -(vG_d * conv.elec.turnsRatio - vMΔd + conv.elec.Rₑ*iΔ_d + conv.elec.Lₑ*iΔ_q)/conv.elec.Lₑ;                 
    # diΔ_q_dt =-(vG_q - vMΔq + Rₑ*iΔ_q - Lₑ*iΔ_d*w)/Lₑ, grid frame
    F[2] = -(vG_q * conv.elec.turnsRatio - vMΔq + conv.elec.Rₑ*iΔ_q - conv.elec.Lₑ*iΔ_d)/conv.elec.Lₑ;                 
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