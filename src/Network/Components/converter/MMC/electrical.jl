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

struct ElectricalMMCInputs
    modulation
    input_signals
    MMC_inputs
end

statenames(::ElectricalMMC) = (:iΔ_d, :iΔ_q, :iΣd, :iΣq, :iΣz, :vCΔd, :vCΔq, :vCΔZd, :vCΔZq, :vCΣd, :vCΣq, :vCΣz)
initialvalues(e::ElectricalMMC; inputs, setpoint_pu) = (; 
    iΔ_d = (inputs.vG_d * e.turnsRatio * setpoint_pu.p_ac - inputs.vG_q * e.turnsRatio * setpoint_pu.q_ac) / ( (inputs.vG_d * e.turnsRatio)^2 + (inputs.vG_q * e.turnsRatio)^2 ),
    iΔ_q = (inputs.vG_q * e.turnsRatio * setpoint_pu.p_ac + inputs.vG_d * e.turnsRatio * setpoint_pu.q_ac) / ( (inputs.vG_d * e.turnsRatio)^2 + (inputs.vG_q * e.turnsRatio)^2 ),
    iΣd = setpoint_pu.p_dc / 3 /inputs.v_dc,
    vCΣz = inputs.v_dc)


    
function state_space!(F, x, inputs::ElectricalMMCInputs, b::ElectricalMMC, conv::AbstractMMC) 
    
    (; iΔ_d, iΔ_q, iΣd, iΣq, iΣz, vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz) = x
    (; mΔd, mΔq, mΔZd, mΔZq, mΣd, mΣq, mΣz) = inputs.modulation
    v_dc = inputs.MMC_inputs.v_dc
    (; vG_d_g, vG_q_g) = inputs.input_signals 
    vG_d, vG_q = vG_d_g, vG_q_g # Everything in grid reference frame for the electrical equations

    # Matrix from Freytes thesis
    VΣΔ_CmdqZ = 1/4 * [ 2 * vCΣz       0              2 * vCΣd               vCΔd + vCΔZd       vCΔZq - vCΔq       vCΔd       vCΔq
                        0              2 * vCΣz       2 * vCΣq               -vCΔq - vCΔZq      vCΔZd - vCΔd       vCΔq       -vCΔd
                        vCΣd           vCΣq           2 * vCΣz               vCΔd               vCΔq               vCΔZd      vCΔZq
                        -vCΔd - vCΔZd  vCΔq + vCΔZq   -2 * vCΔd              -vCΣd - 2 * vCΣz   vCΣq               -vCΣd      vCΣq
                        vCΔq - vCΔZq   vCΔd - vCΔZd   -2 * vCΔq              vCΣq               vCΣd - 2 * vCΣz    -vCΣq      -vCΣd
                        -vCΔd          -vCΔq          -2 * vCΔZd             -vCΣd              -vCΣq              -2 * vCΣz  0
                        -vCΔq          vCΔd           -2 * vCΔZq             vCΣq               -vCΣd              0          -2 * vCΣz]
    
    (vMΣd, vMΣq, vMΣz, vMΔd, vMΔq, _, _) = VΣΔ_CmdqZ * [mΣd; mΣq; mΣz; mΔd; mΔq; mΔZd; mΔZq]
    vMΔd *= conv.elec.baseConv2
    vMΔq *= conv.elec.baseConv2

    # Hard coded equations (old code). Kept for reference --- will be deleted soon
    # vMΔd = conv.elec.baseConv2 * ((mΔq*vCΣq)/4 - (mΔd*vCΣz)/2 - (mΔd*vCΣd)/4 - (mΔZd*vCΣd)/4 + (mΔZq*vCΣq)/4 - (mΣd*vCΔd)/4 - (mΣz*vCΔd)/2 +
    #         (mΣq*vCΔq)/4 - (mΣd*vCΔZd)/4 + (mΣq*vCΔZq)/4);
    # vMΔq = conv.elec.baseConv2 * ((mΔd*vCΣq)/4 + (mΔq*vCΣd)/4 - (mΔq*vCΣz)/2 - (mΔZd*vCΣq)/4 - (mΔZq*vCΣd)/4 + (mΣd*vCΔq)/4 + (mΣq*vCΔd)/4 -
    #         (mΣz*vCΔq)/2 - (mΣd*vCΔZq)/4 - (mΣq*vCΔZd)/4);

    # # vMΣd = (mΔd*vCΔd)/4 - (mΔq*vCΔq)/4 + (mΔd*vCΔZd)/4 + (mΔZd*vCΔd)/4 + (mΔq*vCΔZq)/4 + (mΔZq*vCΔq)/4 + (mΣd*vCΣz)/2 + (mΣz*vCΣd)/2;
    # vMΣd =mΔd*vCΔd/4 - mΔq*vCΔq/4 + mΔd*vCΔZd/4 + mΔZd*vCΔd/4 + mΔq*vCΔZq/4 + mΔZq*vCΔq/4 + mΣd*vCΣz/2 + mΣz*vCΣd/2;
    # # vMΣq = (mΔq*vCΔZd)/4 - (mΔq*vCΔd)/4 - (mΔd*vCΔZq)/4 - (mΔd*vCΔq)/4 + (mΔZd*vCΔq)/4 - (mΔZq*vCΔd)/4 + (mΣq*vCΣz)/2 + (mΣz*vCΣq)/2;
    # vMΣq = mΔq*vCΔZd/4 - mΔq*vCΔd/4 - mΔd*vCΔZq/4 - mΔd*vCΔq/4 + mΔZd*vCΔq/4 - mΔZq*vCΔd/4 + mΣq*vCΣz/2 + mΣz*vCΣq/2;
    # # vMΣz = (mΔd*vCΔd)/4 + (mΔq*vCΔq)/4 + (mΔZd*vCΔZd)/4 + (mΔZq*vCΔZq)/4 + (mΣd*vCΣd)/4 + (mΣq*vCΣq)/4 + (mΣz*vCΣz)/2;
    # vMΣz = mΔd*vCΔd/4 + mΔq*vCΔq/4 + mΔZd*vCΔZd/4 + mΔZq*vCΔZq/4 + mΣd*vCΣd/4 + mΣq*vCΣq/4 + mΣz*vCΣz/2;


    # diΔ_d_dt =-(vG_d - vMΔd + Rₑ*iΔ_d + Lₑ*iΔ_q*w)/Lₑ, grid frame
    F[1] = -(vG_d * conv.elec.turnsRatio - vMΔd + conv.elec.Rₑ*iΔ_d + conv.elec.Lₑ*iΔ_q)/conv.elec.Lₑ;                 
    # diΔ_q_dt =-(vG_q - vMΔq + Rₑ*iΔ_q - Lₑ*iΔ_d*w)/Lₑ, grid frame
    F[2] = -(vG_q * conv.elec.turnsRatio - vMΔq + conv.elec.Rₑ*iΔ_q - conv.elec.Lₑ*iΔ_d)/conv.elec.Lₑ;                 
    # diΣd_dt =-(vMΣd + Rₐᵣₘ*iΣd - 2*Lₐᵣₘ*iΣq*w)/Lₐᵣₘ, grid 2w frame
    F[3] = -(vMΣd + conv.elec.Rₐᵣₘ*iΣd - 2*conv.elec.Lₐᵣₘ*iΣq)/conv.elec.Lₐᵣₘ;                                 
    # diΣq_dt =-(vMΣq + Rₐᵣₘ*iΣq + 2*Lₐᵣₘ*iΣd*w)/Lₐᵣₘ,  grid 2w frame
    F[4] = -(vMΣq + conv.elec.Rₐᵣₘ*iΣq + 2*conv.elec.Lₐᵣₘ*iΣd)/conv.elec.Lₐᵣₘ;                                  
    # diΣz_dt =-(vMΣz - Vᵈᶜ/2 + Rₐᵣₘ*iΣz)/Lₐᵣₘ
    F[5] = -(vMΣz - v_dc/2 + conv.elec.Rₐᵣₘ*iΣz)/conv.elec.Lₐᵣₘ;                                     
    # dvCΔd_dt =(N*(iΣz*mΔd - (iΔ_q*mΣq)/4 + iΣd*(mΔd/2 + mΔZd/2) - iΣq*(mΔq/2 + mΔZq/2) + iΔ_d*(mΣd/4 + mΣz/2) - (2*Cₐᵣₘ*vCΔq*w)/N))/(2*Cₐᵣₘ)
    F[6] = (conv.elec.N*(iΣz*mΔd - iΔ_q*conv.elec.baseConv3*mΣq/4 + iΣd*(mΔd/2 + mΔZd/2) - iΣq*(mΔq/2 + mΔZq/2) + iΔ_d*conv.elec.baseConv3*(mΣd/4 + mΣz/2) - 2*conv.elec.Cₐᵣₘ*vCΔq/conv.elec.N))/2/conv.elec.Cₐᵣₘ;
    # dvCΔq_dt =-(N*((iΔ_d*mΣq)/4 - iΣz*mΔq + iΣq*(mΔd/2 - mΔZd/2) + iΣd*(mΔq/2 - mΔZq/2) + iΔ_q*(mΣd/4 - mΣz/2) - (2*Cₐᵣₘ*vCΔd*w)/N))/(2*Cₐᵣₘ)
    F[7] = -(conv.elec.N*((iΔ_d*conv.elec.baseConv3*mΣq)/4 - iΣz*mΔq + iΣq*(mΔd/2 - mΔZd/2) + iΣd*(mΔq/2 - mΔZq/2) + iΔ_q*conv.elec.baseConv3*(mΣd/4 - mΣz/2) - 2*conv.elec.Cₐᵣₘ*vCΔd/conv.elec.N))/2/conv.elec.Cₐᵣₘ;
    # dvCΔZd_dt =(N*(iΔ_d*mΣd + 2*iΣd*mΔd + iΔ_q*mΣq + 2*iΣq*mΔq + 4*iΣz*mΔZd))/(8*Cₐᵣₘ) - 3*vCΔZq*w
    F[8] = (conv.elec.N*(iΔ_d*conv.elec.baseConv3*mΣd + 2*iΣd*mΔd + iΔ_q*conv.elec.baseConv3*mΣq + 2*iΣq*mΔq + 4*iΣz*mΔZd))/(8*conv.elec.Cₐᵣₘ) - 3*vCΔZq;
    # dvCΔZq_dt =3*vCΔZd*w + (N*(iΔ_q*mΣd - iΔ_d*mΣq + 2*iΣd*mΔq - 2*iΣq*mΔd + 4*iΣz*mΔZq))/(8*Cₐᵣₘ)
    F[9] = 3*vCΔZd + (conv.elec.N*(iΔ_q*conv.elec.baseConv3*mΣd - iΔ_d*conv.elec.baseConv3*mΣq + 2*iΣd*mΔq - 2*iΣq*mΔd + 4*iΣz*mΔZq))/(8*conv.elec.Cₐᵣₘ);
    # dvCΣd_dt =(N*(iΣd*mΣz + iΣz*mΣd + iΔ_d*(mΔd/4 + mΔZd/4) - iΔ_q*(mΔq/4 - mΔZq/4) + (4*Cₐᵣₘ*vCΣq*w)/N))/(2*Cₐᵣₘ)
    F[10] = (conv.elec.N*(iΣd*mΣz + iΣz*mΣd + iΔ_d*conv.elec.baseConv3*(mΔd/4 + mΔZd/4) - iΔ_q*conv.elec.baseConv3*(mΔq/4 - mΔZq/4) + 4*conv.elec.Cₐᵣₘ*vCΣq/conv.elec.N))/(2*conv.elec.Cₐᵣₘ);
    # dvCΣq_dt =-(N*(iΔ_q*(mΔd/4 - mΔZd/4) - iΣz*mΣq - iΣq*mΣz + iΔ_d*(mΔq/4 + mΔZq/4) + (4*Cₐᵣₘ*vCΣd*w)/N))/(2*Cₐᵣₘ)
    F[11] = -(conv.elec.N*(iΔ_q*conv.elec.baseConv3*(mΔd/4 - mΔZd/4) - iΣz*mΣq - iΣq*mΣz + iΔ_d*conv.elec.baseConv3*(mΔq/4 + mΔZq/4) + 4*conv.elec.Cₐᵣₘ*vCΣd/conv.elec.N))/(2*conv.elec.Cₐᵣₘ);
    # dvCΣz_dt =(N*(iΔ_d*mΔd + iΔ_q*mΔq + 2*iΣd*mΣd + 2*iΣq*mΣq + 4*iΣz*mΣz))/(8*Cₐᵣₘ)
    F[12] = (conv.elec.N*(iΔ_d*conv.elec.baseConv3*mΔd + iΔ_q*conv.elec.baseConv3*mΔq + 2*iΣd*mΣd + 2*iΣq*mΣq + 4*iΣz*mΣz))/(8*conv.elec.Cₐᵣₘ);
    F[1:12] *= conv.elec.ωbase

end