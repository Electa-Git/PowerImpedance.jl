struct ElectricalMMC <: AbstractStateSpace
    ## Electrical parameters
    Lₐᵣₘ :: Float64        # arm inductance [pu]
    Rₐᵣₘ :: Float64        # equivalent arm resistance [pu]
    Cₐᵣₘ :: Float64        # capacitance per submodule [pu]
    N :: Int               # number of submodules per arm [-]
    turnsRatio :: Float64  # Turns ratio of the converter transformer, converter side/AC side [-]

    ## Base values
    wbase :: Float64        # Base angular frequncy [rad/s]
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
        wbase = 100π,
        vACbase_LL_RMS = 380,   # Voltage base LL converter side [kV]
        Sbase = 1000,           # Power base [MW]
        vDC_base = 640)          # DC voltage base [kV])
    
    vAC_base = vACbase_LL_RMS*sqrt(2/3)
    iAC_base = 2*Sbase/3/vAC_base
    iDC_base = Sbase/vDC_base
    zAC_base = (3/2)*vAC_base^2/Sbase
    zDC_base = vDC_base/iDC_base
    lAC_base = zAC_base/wbase
    lDC_base = zDC_base/wbase
    cbase = 1/wbase/zDC_base
    Lₑ = (Lₐᵣₘ / 2 + Lᵣ) / lAC_base
    Rₑ = (Rₐᵣₘ / 2 + Rᵣ) / zAC_base
    Lₐᵣₘ = Lₐᵣₘ / lDC_base
    Rₐᵣₘ = Rₐᵣₘ / zDC_base
    Cₐᵣₘ = Cₐᵣₘ / cbase

    baseConv1 = vAC_base/vDC_base;# AC to DC voltage
    baseConv2 = vDC_base/vAC_base;# DC to AC voltage
    baseConv3 = iAC_base/iDC_base;# AC to DC current

    return ElectricalMMC(Lₐᵣₘ, Rₐᵣₘ, Cₐᵣₘ, N, turnsRatio, wbase, vAC_base, vDC_base, Sbase, baseConv1, baseConv2, baseConv3, Lₑ, Rₑ)
end


statenames(::ElectricalMMC) = (:iΔd, :iΔq, :iΣd, :iΣq, :iΣz, :vCΔd, :vCΔq, :vCΔZd, :vCΔZq, :vCΣd, :vCΣq, :vCΣz)
initialvalues(e::ElectricalMMC, inputs) = (; 
    iΔd = (inputs.Vᴳd * e.turnsRatio * inputs.Pac - inputs.Vᴳq * e.turnsRatio * inputs.Qac) / ( (inputs.Vᴳd * e.turnsRatio)^2 + (inputs.Vᴳq * e.turnsRatio)^2 ),
    iΔq = (inputs.Vᴳq * e.turnsRatio * inputs.Pac + inputs.Vᴳd * e.turnsRatio * inputs.Qac) / ( (inputs.Vᴳd * e.turnsRatio)^2 + (inputs.Vᴳq * e.turnsRatio)^2 ),
    iΣd = inputs.Pdc / 3 /inputs.Vdc,
    vCΣz = inputs.Vdc)


    
function state_space!(F, x, inputs, b::ElectricalMMC, conv::AbstractMMC) 
    
    iΔd, iΔq, iΣd, iΣq, iΣz, vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz = get_states(x, :iΔd, :iΔq, :iΣd, :iΣq, :iΣz, :vCΔd, :vCΔq, :vCΔZd, :vCΔZq, :vCΣd, :vCΣq, :vCΣz)
    (; mΔd, mΔq, mΔZd, mΔZq, mΣd, mΣq, mΣz) = inputs
    (; Vᴳd, Vᴳq) = inputs

    vMΔd = conv.elec.baseConv2 * ((mΔq*vCΣq)/4 - (mΔd*vCΣz)/2 - (mΔd*vCΣd)/4 - (mΔZd*vCΣd)/4 + (mΔZq*vCΣq)/4 - (mΣd*vCΔd)/4 - (mΣz*vCΔd)/2 +
            (mΣq*vCΔq)/4 - (mΣd*vCΔZd)/4 + (mΣq*vCΔZq)/4);
    vMΔq = conv.elec.baseConv2 * ((mΔd*vCΣq)/4 + (mΔq*vCΣd)/4 - (mΔq*vCΣz)/2 - (mΔZd*vCΣq)/4 - (mΔZq*vCΣd)/4 + (mΣd*vCΔq)/4 + (mΣq*vCΔd)/4 -
            (mΣz*vCΔq)/2 - (mΣd*vCΔZq)/4 - (mΣq*vCΔZd)/4);

    # vMΣd = (mΔd*vCΔd)/4 - (mΔq*vCΔq)/4 + (mΔd*vCΔZd)/4 + (mΔZd*vCΔd)/4 + (mΔq*vCΔZq)/4 + (mΔZq*vCΔq)/4 + (mΣd*vCΣz)/2 + (mΣz*vCΣd)/2;
    vMΣd =mΔd*vCΔd/4 - mΔq*vCΔq/4 + mΔd*vCΔZd/4 + mΔZd*vCΔd/4 + mΔq*vCΔZq/4 + mΔZq*vCΔq/4 + mΣd*vCΣz/2 + mΣz*vCΣd/2;
    # vMΣq = (mΔq*vCΔZd)/4 - (mΔq*vCΔd)/4 - (mΔd*vCΔZq)/4 - (mΔd*vCΔq)/4 + (mΔZd*vCΔq)/4 - (mΔZq*vCΔd)/4 + (mΣq*vCΣz)/2 + (mΣz*vCΣq)/2;
    vMΣq = mΔq*vCΔZd/4 - mΔq*vCΔd/4 - mΔd*vCΔZq/4 - mΔd*vCΔq/4 + mΔZd*vCΔq/4 - mΔZq*vCΔd/4 + mΣq*vCΣz/2 + mΣz*vCΣq/2;
    # vMΣz = (mΔd*vCΔd)/4 + (mΔq*vCΔq)/4 + (mΔZd*vCΔZd)/4 + (mΔZq*vCΔZq)/4 + (mΣd*vCΣd)/4 + (mΣq*vCΣq)/4 + (mΣz*vCΣz)/2;
    vMΣz = mΔd*vCΔd/4 + mΔq*vCΔq/4 + mΔZd*vCΔZd/4 + mΔZq*vCΔZq/4 + mΣd*vCΣd/4 + mΣq*vCΣq/4 + mΣz*vCΣz/2;
    # diΔd_dt =-(Vᴳd - vMΔd + Rₑ*iΔd + Lₑ*iΔq*w)/Lₑ, grid frame
    F[1] = -(Vᴳd * conv.elec.turnsRatio - vMΔd + conv.elec.Rₑ*iΔd + conv.elec.Lₑ*iΔq)/conv.elec.Lₑ;                 
    # diΔq_dt =-(Vᴳq - vMΔq + Rₑ*iΔq - Lₑ*iΔd*w)/Lₑ, grid frame
    F[2] = -(Vᴳq * conv.elec.turnsRatio - vMΔq + conv.elec.Rₑ*iΔq - conv.elec.Lₑ*iΔd)/conv.elec.Lₑ;                 
    # diΣd_dt =-(vMΣd + Rₐᵣₘ*iΣd - 2*Lₐᵣₘ*iΣq*w)/Lₐᵣₘ, grid 2w frame
    F[3] = -(vMΣd + conv.elec.Rₐᵣₘ*iΣd - 2*conv.elec.Lₐᵣₘ*iΣq)/conv.elec.Lₐᵣₘ;                                 
    # diΣq_dt =-(vMΣq + Rₐᵣₘ*iΣq + 2*Lₐᵣₘ*iΣd*w)/Lₐᵣₘ,  grid 2w frame
    F[4] = -(vMΣq + conv.elec.Rₐᵣₘ*iΣq + 2*conv.elec.Lₐᵣₘ*iΣd)/conv.elec.Lₐᵣₘ;                                  
    # diΣz_dt =-(vMΣz - Vᵈᶜ/2 + Rₐᵣₘ*iΣz)/Lₐᵣₘ
    F[5] = -(vMΣz - inputs.Vdc/2 + conv.elec.Rₐᵣₘ*iΣz)/conv.elec.Lₐᵣₘ;                                     
    # dvCΔd_dt =(N*(iΣz*mΔd - (iΔq*mΣq)/4 + iΣd*(mΔd/2 + mΔZd/2) - iΣq*(mΔq/2 + mΔZq/2) + iΔd*(mΣd/4 + mΣz/2) - (2*Cₐᵣₘ*vCΔq*w)/N))/(2*Cₐᵣₘ)
    F[6] = (conv.elec.N*(iΣz*mΔd - iΔq*conv.elec.baseConv3*mΣq/4 + iΣd*(mΔd/2 + mΔZd/2) - iΣq*(mΔq/2 + mΔZq/2) + iΔd*conv.elec.baseConv3*(mΣd/4 + mΣz/2) - 2*conv.elec.Cₐᵣₘ*vCΔq/conv.elec.N))/2/conv.elec.Cₐᵣₘ;
    # dvCΔq_dt =-(N*((iΔd*mΣq)/4 - iΣz*mΔq + iΣq*(mΔd/2 - mΔZd/2) + iΣd*(mΔq/2 - mΔZq/2) + iΔq*(mΣd/4 - mΣz/2) - (2*Cₐᵣₘ*vCΔd*w)/N))/(2*Cₐᵣₘ)
    F[7] = -(conv.elec.N*((iΔd*conv.elec.baseConv3*mΣq)/4 - iΣz*mΔq + iΣq*(mΔd/2 - mΔZd/2) + iΣd*(mΔq/2 - mΔZq/2) + iΔq*conv.elec.baseConv3*(mΣd/4 - mΣz/2) - 2*conv.elec.Cₐᵣₘ*vCΔd/conv.elec.N))/2/conv.elec.Cₐᵣₘ;
    # dvCΔZd_dt =(N*(iΔd*mΣd + 2*iΣd*mΔd + iΔq*mΣq + 2*iΣq*mΔq + 4*iΣz*mΔZd))/(8*Cₐᵣₘ) - 3*vCΔZq*w
    F[8] = (conv.elec.N*(iΔd*conv.elec.baseConv3*mΣd + 2*iΣd*mΔd + iΔq*conv.elec.baseConv3*mΣq + 2*iΣq*mΔq + 4*iΣz*mΔZd))/(8*conv.elec.Cₐᵣₘ) - 3*vCΔZq;
    # dvCΔZq_dt =3*vCΔZd*w + (N*(iΔq*mΣd - iΔd*mΣq + 2*iΣd*mΔq - 2*iΣq*mΔd + 4*iΣz*mΔZq))/(8*Cₐᵣₘ)
    F[9] = 3*vCΔZd + (conv.elec.N*(iΔq*conv.elec.baseConv3*mΣd - iΔd*conv.elec.baseConv3*mΣq + 2*iΣd*mΔq - 2*iΣq*mΔd + 4*iΣz*mΔZq))/(8*conv.elec.Cₐᵣₘ);
    # dvCΣd_dt =(N*(iΣd*mΣz + iΣz*mΣd + iΔd*(mΔd/4 + mΔZd/4) - iΔq*(mΔq/4 - mΔZq/4) + (4*Cₐᵣₘ*vCΣq*w)/N))/(2*Cₐᵣₘ)
    F[10] = (conv.elec.N*(iΣd*mΣz + iΣz*mΣd + iΔd*conv.elec.baseConv3*(mΔd/4 + mΔZd/4) - iΔq*conv.elec.baseConv3*(mΔq/4 - mΔZq/4) + 4*conv.elec.Cₐᵣₘ*vCΣq/conv.elec.N))/(2*conv.elec.Cₐᵣₘ);
    # dvCΣq_dt =-(N*(iΔq*(mΔd/4 - mΔZd/4) - iΣz*mΣq - iΣq*mΣz + iΔd*(mΔq/4 + mΔZq/4) + (4*Cₐᵣₘ*vCΣd*w)/N))/(2*Cₐᵣₘ)
    F[11] = -(conv.elec.N*(iΔq*conv.elec.baseConv3*(mΔd/4 - mΔZd/4) - iΣz*mΣq - iΣq*mΣz + iΔd*conv.elec.baseConv3*(mΔq/4 + mΔZq/4) + 4*conv.elec.Cₐᵣₘ*vCΣd/conv.elec.N))/(2*conv.elec.Cₐᵣₘ);
    # dvCΣz_dt =(N*(iΔd*mΔd + iΔq*mΔq + 2*iΣd*mΣd + 2*iΣq*mΣq + 4*iΣz*mΣz))/(8*Cₐᵣₘ)
    F[12] = (conv.elec.N*(iΔd*conv.elec.baseConv3*mΔd + iΔq*conv.elec.baseConv3*mΔq + 2*iΣd*mΣd + 2*iΣq*mΣq + 4*iΣz*mΣz))/(8*conv.elec.Cₐᵣₘ);
    F[1:12] *= conv.elec.wbase

end