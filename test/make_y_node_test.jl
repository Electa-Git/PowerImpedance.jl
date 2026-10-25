
function calc_RLC(P, Q, V, component)
    # Function to calculate resistance, inductance or capacitance of a 3-phase series load
    # for a given 1-phase active "P" and reactive power "Q" [MVA]
    # and phase-rms Voltage V [kV]
    # Discremination of component by string component "R", "L", "C"

    P=P*1e6
    Q=Q*1e6
    V=V*1e3

    S=sqrt(P^2+Q^2) # 1-phase apparent power
    S=S*3 # Get 3-phase power

    # Calculate phase current rms: I

    I=S/(sqrt(3)*V)

    if component == "R"
        R = P/(I^2)

        return R

    elseif component == "L"
        L = Q/(I^2*2*pi*50)
        return L

    elseif component == "C"
        C=(I^2)/(Q*2*pi*50)
        return C
    else
        error("No implemented load component specified!")
    end
end

# Operating points
P_MMC1 = -500
Q_MMC1 = 0
P_MMC2=-1000
Q_MMC2=0
Q_MMC3=0.0
Q_MMC4=0.0
Pwf=600
Qwf=0

# Get load parameters :)
R_B3=calc_RLC(314, 63.333, 380, "R")
L_B3=calc_RLC(314, 63.333, 380, "L")

R_B4=calc_RLC(159.333, 13, 380, "R")
C_B4=calc_RLC(159.333, 13, 380, "C")

R_B5=calc_RLC(25.333, 5.333, 380, "R")
L_B5=calc_RLC(25.333, 5.333, 380, "L")

R_B6=calc_RLC(37.333, 25.0, 380, "R")
L_B6=calc_RLC(37.333, 25.0, 380, "L")

# Stability analysis options
min_f=0.1 # Minimum frequency in Hz
max_f=5e3 # Maximum frequency in Hz
n_f=100 # Discretization of the frequency, high value needed for PMD

Vm=380/sqrt(3)

# MMCs
MMC1 = let model = PowerImpedance.mmc(
        elec = PowerImpedance.ElectricalMMC(
            Lᵣ = 0.18 * (333^2 / 1000) / (2 * pi * 50),
            Rᵣ = 0.001 * (333^2 / 1000),
            Rₐᵣₘ = 0.4,
            Lₐᵣₘ = 46.125e-3,
            Cₐᵣₘ = 11.3867e-3,
            N = 400,
            turnsRatio = 333 / 380,
            vACbase_LL_RMS = 333,
            Sbase = 1000,
            vDC_base = 640
        ),
        meas = PowerImpedance.Measurement(
            P_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
            Q_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π)
        ),
        sync = PowerImpedance.VSEWithDamping(
            H = 5,
            K_d = 100,
            K_ω = 10,
            ω_ref = 1.0,
            pll = PowerImpedance.PLLSynchronization(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.28, Ki = 12.5664),
                filter = PowerImpedance.Butterworth(order = 1, ωc = 75 * 2π)
            )
        ),
        delta_control = PowerImpedance.ΔdqControlGFM(
            outer_reactive = PowerImpedance.OuterReactiveQControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 3),
                support = PowerImpedance.NoVoltageSupport()
            ),
            vi = PowerImpedance.CCVI(
                R_v = 0.01,
                L_v = 0.25,
                V_d_ref = 1,
                V_q_ref = 0,
                filter = PowerImpedance.Butterworth(order = 2, ωc = 200)
            ),
            occ = PowerImpedance.InnerCurrentPIControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.6532, Ki = 281.1370),
                filter = PowerImpedance.Butterworth(order = 2, ωc = 200 * 2π)
            )
        ),
        sigma_control = PowerImpedance.ΣdqzControlTEC(
            tec = PowerImpedance.TotalEnergyControl(
                pi_control = PowerImpedance.PIControl(Kp = 1.469, Ki = 31.4819),
            ),
            zscc = PowerImpedance.ZeroSequenceCurrentControl(
                PowerImpedance.PIControl(Kp = 0.0936, Ki = 40.5396),
            ),
            ccsc = PowerImpedance.CirculatingCurrentSuppressionControl(
                PowerImpedance.PIControl(Kp = 0.0936, Ki = 40.5396),
            )
        ),
        modulation = PowerImpedance.UncompensatedModulation(
            timeDelay = 200e-6,
            padeOrderNum = 5,
            padeOrderDen = 5
        ),
        limits = PowerImpedance.Limits(
            P_min = -1500.0,
            P_max = 1500.0,
            Q_min = -1000.0,
            Q_max = 1000.0
        )
    )
    b = bases(model)
    component(model; sync = (p_ref = (P_MMC1) / b.S,),
        delta_control = (outer_reactive = (q_ref = (Q_MMC1) / b.S,),),
        powerflow = (v_ac = (Vm * sqrt(2)) / b.v_ac, p_dc = (P_MMC1) / b.S,
            v_dc = (640) / b.v_dc))
end

MMC2 = let model = PowerImpedance.mmc(
        elec = PowerImpedance.ElectricalMMC(
            Lᵣ = 0.18 * (333^2 / 1000) / (2 * pi * 50),
            Rᵣ = 0.001 * (333^2 / 1000),
            Rₐᵣₘ = 0.4,
            Lₐᵣₘ = 46.125e-3,
            Cₐᵣₘ = 11.3867e-3,
            N = 400,
            turnsRatio = 333 / 380,
            vACbase_LL_RMS = 333,
            Sbase = 1000,
            vDC_base = 640
        ),
        meas = PowerImpedance.Measurement(
            P_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
            Q_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π)
        ),
        sync = PowerImpedance.VSEWithDamping(
            H = 5,
            K_d = 100,
            K_ω = 10,
            ω_ref = 1.0,
            pll = PowerImpedance.PLLSynchronization(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.28, Ki = 12.5664),
                filter = PowerImpedance.Butterworth(order = 1, ωc = 75 * 2π)
            )
        ),
        delta_control = PowerImpedance.ΔdqControlGFM(
            outer_reactive = PowerImpedance.OuterReactiveQControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 3),
                support = PowerImpedance.NoVoltageSupport()
            ),
            vi = PowerImpedance.CCVI(
                R_v = 0.0,
                L_v = 0.4,
                V_d_ref = 1,
                V_q_ref = 0,
                filter = PowerImpedance.Butterworth(order = 2, ωc = 200)
            ),
            occ = PowerImpedance.InnerCurrentPIControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.6532, Ki = 281.1370),
                filter = PowerImpedance.Butterworth(order = 2, ωc = 400 * 2π)
            )
        ),
        sigma_control = PowerImpedance.ΣdqzControlTEC(
            tec = PowerImpedance.TotalEnergyControl(
                pi_control = PowerImpedance.PIControl(Kp = 1.469, Ki = 31.4819),
            ),
            zscc = PowerImpedance.ZeroSequenceCurrentControl(
                PowerImpedance.PIControl(Kp = 0.0936, Ki = 40.5396),
            ),
            ccsc = PowerImpedance.CirculatingCurrentSuppressionControl(
                PowerImpedance.PIControl(Kp = 0.0936, Ki = 40.5396),
            )
        ),
        modulation = PowerImpedance.UncompensatedModulation(
            timeDelay = 200e-6,
            padeOrderNum = 5,
            padeOrderDen = 5
        ),
        limits = PowerImpedance.Limits(
            P_min = -1500.0,
            P_max = 1500.0,
            Q_min = -1000.0,
            Q_max = 1000.0
        )
    )
    b = bases(model)
    component(model; sync = (p_ref = (P_MMC2) / b.S,),
        delta_control = (outer_reactive = (q_ref = (Q_MMC2) / b.S,),),
        powerflow = (v_ac = (Vm * sqrt(2)) / b.v_ac, p_dc = (P_MMC2) / b.S,
            v_dc = (640) / b.v_dc))
end

MMC3 = let model = PowerImpedance.mmc(
        elec = PowerImpedance.ElectricalMMC(
            Lᵣ = 0.1305 * (333^2 / 1000) / (2 * pi * 50),
            Rᵣ = 0.0037 * (333^2 / 1000),
            Rₐᵣₘ = 0.4,
            Lₐᵣₘ = 46.125e-3,
            Cₐᵣₘ = 11.3867e-3,
            N = 400,
            turnsRatio = 333 / 380,
            vACbase_LL_RMS = 333,
            Sbase = 1000,
            vDC_base = 640
        ),
        meas = PowerImpedance.Measurement(
            P_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
            Q_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π)
        ),
        sync = PowerImpedance.PLLSynchronization(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.28, Ki = 12.5664),
            filter = PowerImpedance.Butterworth(order = 1, ωc = 80 * 2π)
        ),
        delta_control = PowerImpedance.ΔdqControlGFL(
            outer_active = PowerImpedance.OuterActiveVdcControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 5, Ki = 15),
            ),
            outer_reactive = PowerImpedance.OuterReactiveQControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.1, Ki = 31.4159),
                support = PowerImpedance.NoVoltageSupport()
            ),
            occ = PowerImpedance.InnerCurrentPIControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.1048, Ki = 48.1914),
                filter = PowerImpedance.Butterworth(order = 2, ωc = 600 * 2π)
            )
        ),
        sigma_control = PowerImpedance.ΣdqzControlTEC(
            tec = PowerImpedance.TotalEnergyControl(
                pi_control = PowerImpedance.PIControl(Kp = 1.2894, Ki = 27.63),
            ),
            zscc = PowerImpedance.ZeroSequenceCurrentControl(
                PowerImpedance.PIControl(Kp = 0.0992, Ki = 42.9719),
            ),
            ccsc = PowerImpedance.CirculatingCurrentSuppressionControl(
                PowerImpedance.PIControl(Kp = 0.0992, Ki = 42.9719),
            )
        ),
        modulation = PowerImpedance.UncompensatedModulation(
            timeDelay = 250e-6,
            padeOrderNum = 5,
            padeOrderDen = 5
        ),
        limits = PowerImpedance.Limits(
            P_min = -1500.0,
            P_max = 1500.0,
            Q_min = -1000.0,
            Q_max = 1000.0
        )
    )
    b = bases(model)
    component(model;
        delta_control = (outer_active = (v_dc_ref = (640) / b.v_dc,),
            outer_reactive = (q_ref = (Q_MMC3) / b.S,)),
        powerflow = (p_ac = (0.0) / b.S,
            v_ac = (Vm * sqrt(2)) / b.v_ac, p_dc = (0.0) / b.S))
end

MMC4 = let model = PowerImpedance.mmc(
        elec = PowerImpedance.ElectricalMMC(
            Lᵣ = 0.1305 * (333^2 / 1000) / (2 * pi * 50),
            Rᵣ = 0.0037 * (333^2 / 1000),
            Rₐᵣₘ = 0.4,
            Lₐᵣₘ = 46.125e-3,
            Cₐᵣₘ = 11.3867e-3,
            N = 400,
            turnsRatio = 333 / 380,
            vACbase_LL_RMS = 333,
            Sbase = 1000,
            vDC_base = 640
        ),
        meas = PowerImpedance.Measurement(
            P_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
            Q_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π)
        ),
        sync = PowerImpedance.PLLSynchronization(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.28, Ki = 12.5664),
            filter = PowerImpedance.Butterworth(order = 1, ωc = 80 * 2π)
        ),
        delta_control = PowerImpedance.ΔdqControlGFL(
            outer_active = PowerImpedance.OuterActiveVdcControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 5, Ki = 15),
            ),
            outer_reactive = PowerImpedance.OuterReactiveQControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.1, Ki = 31.4159),
                support = PowerImpedance.NoVoltageSupport()
            ),
            occ = PowerImpedance.InnerCurrentPIControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.1048, Ki = 48.1914),
                filter = PowerImpedance.Butterworth(order = 2, ωc = 100 * 2π)
            )
        ),
        sigma_control = PowerImpedance.ΣdqzControlTEC(
            tec = PowerImpedance.TotalEnergyControl(
                pi_control = PowerImpedance.PIControl(Kp = 1.2894, Ki = 27.63),
            ),
            zscc = PowerImpedance.ZeroSequenceCurrentControl(
                PowerImpedance.PIControl(Kp = 0.0992, Ki = 42.9719),
            ),
            ccsc = PowerImpedance.CirculatingCurrentSuppressionControl(
                PowerImpedance.PIControl(Kp = 0.0992, Ki = 42.9719),
            )
        ),
        modulation = PowerImpedance.UncompensatedModulation(
            timeDelay = 200e-6,
            padeOrderNum = 5,
            padeOrderDen = 5
        ),
        limits = PowerImpedance.Limits(
            P_min = -1500.0,
            P_max = 1500.0,
            Q_min = -1000.0,
            Q_max = 1000.0
        )
    )
    b = bases(model)
    component(model;
        delta_control = (outer_active = (v_dc_ref = (640) / b.v_dc,),
            outer_reactive = (q_ref = (Q_MMC4) / b.S,)),
        powerflow = (p_ac = (0.0) / b.S,
            v_ac = (Vm * sqrt(2)) / b.v_ac, p_dc = (0.0) / b.S))
end

# TLCs
WF1 = let model = PowerImpedance.tlc(
        elec = PowerImpedance.ElectricalTLC(
            Lᵣ = 0.08 * (380^2 / 600) / (2 * pi * 50),
            Rᵣ = 0.0008 * (380^2 / 600),
            Sbase = 600,
            vACbase_LL_RMS = 380,
            vDCbase = 640
        ),
        meas = PowerImpedance.Measurement(
            v_ac = PowerImpedance.Butterworth(order = 1, ωc = 1e4),
            i_ac = PowerImpedance.Butterworth(order = 1, ωc = 1e4)
        ),
        sync = PowerImpedance.PLLSynchronization(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.3978, Ki = 7.9577),
            filter = PowerImpedance.Butterworth(order = 1, ωc = 2 * pi * 50)
        ),
        outerActive = PowerImpedance.OuterActivePowerControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.01, Ki = 10),
            support = PowerImpedance.NoFrequencySupport()
        ),
        outerReactive = PowerImpedance.OuterReactiveQControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.01, Ki = 10),
            support = PowerImpedance.NoVoltageSupport()
        ),
        innerVoltage = PowerImpedance.NoInnerVoltageControl(),
        innerCurrent = PowerImpedance.InnerCurrentPIControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.254647908947033, Ki = 0.8),
        ),
        mod = PowerImpedance.NoModulation(),
        limits = PowerImpedance.Limits(
            P_min = -1000.0,
            P_max = 1000.0,
            Q_min = -1000.0,
            Q_max = 1000.0
        )
    )
    b = bases(model)
    component(model; outerActive = (p_ref = (Pwf) / b.S,),
        outerReactive = (q_ref = (Qwf) / b.S,),
        powerflow = (v_ac = (Vm * sqrt(2)) / b.v_ac, p_dc = (Pwf) / b.S,
            v_dc = (640) / b.v_dc))
end

WF2 = let model = PowerImpedance.tlc(
        elec = PowerImpedance.ElectricalTLC(
            Lᵣ = 0.08 * (380^2 / 600) / (2 * pi * 50),
            Rᵣ = 0.0008 * (380^2 / 600),
            Sbase = 600,
            vACbase_LL_RMS = 380,
            vDCbase = 640
        ),
        meas = PowerImpedance.Measurement(
            v_ac = PowerImpedance.Butterworth(order = 1, ωc = 1e4),
            i_ac = PowerImpedance.Butterworth(order = 1, ωc = 1e4)
        ),
        sync = PowerImpedance.PLLSynchronization(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.3978, Ki = 7.9577),
            filter = PowerImpedance.Butterworth(order = 1, ωc = 2 * pi * 80)
        ),
        outerActive = PowerImpedance.OuterActivePowerControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.01, Ki = 10),
            support = PowerImpedance.NoFrequencySupport()
        ),
        outerReactive = PowerImpedance.OuterReactiveQControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.01, Ki = 10),
            support = PowerImpedance.NoVoltageSupport()
        ),
        innerVoltage = PowerImpedance.NoInnerVoltageControl(),
        innerCurrent = PowerImpedance.InnerCurrentPIControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.254647908947033, Ki = 0.8),
        ),
        mod = PowerImpedance.NoModulation(),
        limits = PowerImpedance.Limits(
            P_min = -1000.0,
            P_max = 1000.0,
            Q_min = -1000.0,
            Q_max = 1000.0
        )
    )
    b = bases(model)
    component(model; outerActive = (p_ref = (Pwf) / b.S,),
        outerReactive = (q_ref = (Qwf) / b.S,),
        powerflow = (v_ac = (Vm * sqrt(2)) / b.v_ac, p_dc = (Pwf) / b.S,
            v_dc = (640) / b.v_dc))
end

WF3 = let model = PowerImpedance.tlc(
        elec = PowerImpedance.ElectricalTLC(
            Lᵣ = 0.08 * (380^2 / 600) / (2 * pi * 50),
            Rᵣ = 0.0008 * (380^2 / 600),
            Sbase = 600,
            vACbase_LL_RMS = 380,
            vDCbase = 640
        ),
        meas = PowerImpedance.Measurement(
            v_ac = PowerImpedance.Butterworth(order = 1, ωc = 1e4),
            i_ac = PowerImpedance.Butterworth(order = 1, ωc = 1e4)
        ),
        sync = PowerImpedance.PLLSynchronization(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.3978, Ki = 7.9577),
            filter = PowerImpedance.Butterworth(order = 1, ωc = 2 * pi * 80)
        ),
        outerActive = PowerImpedance.OuterActivePowerControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.01, Ki = 10),
            support = PowerImpedance.NoFrequencySupport()
        ),
        outerReactive = PowerImpedance.OuterReactiveQControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.01, Ki = 10),
            support = PowerImpedance.NoVoltageSupport()
        ),
        innerVoltage = PowerImpedance.NoInnerVoltageControl(),
        innerCurrent = PowerImpedance.InnerCurrentPIControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.254647908947033, Ki = 0.8),
        ),
        mod = PowerImpedance.NoModulation(),
        limits = PowerImpedance.Limits(
            P_min = -1000.0,
            P_max = 1000.0,
            Q_min = -1000.0,
            Q_max = 1000.0
        )
    )
    b = bases(model)
    component(model; outerActive = (p_ref = (Pwf) / b.S,),
        outerReactive = (q_ref = (Qwf) / b.S,),
        powerflow = (v_ac = (Vm * sqrt(2)) / b.v_ac, p_dc = (Pwf) / b.S,
            v_dc = (640) / b.v_dc))
end

IEEE14bus = let

    # Sources
    G1=ac_source(v = Vm*sqrt(2))
    G2=ac_source(v = Vm*sqrt(2))
    DC_WF1=dc_source(v = 640)
    DC_WF2=dc_source(v = 640)
    DC_WF3=dc_source(v = 640)
    Zg2=impedance(z = (s::Complex) -> (1.0263 + s*0.0327), conductors = 3) # Top area
    Zg1=impedance(z = (s::Complex) -> (0.2874 + s*0.0091), conductors = 3) # Bottom area

    #Converters

    # Overhead lines

    # Bottom area ⬇
    T1_2 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T1_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))
    # Create HFO instability with trip of T2_5
    T2_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T4_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T2_4 = overhead_line(length = 250e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T2_3 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T3_4 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    # Top area⬆
    T12_13 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T6_12 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T6_13 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T6_11 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T10_11 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T13_14 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T9_14 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    T9_10 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))
    T7_9 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5,
            Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    # Cables
    # ABB Datasheet cables with no amouring to represent onshore cables
    CableDC23 = cable(length = 200e3, positions = [(0, 1.5), (1, 1.5)],
        C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
        I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3, ϵᵣ = 2.5),
        C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
        I2 = Insulator(rᵢ = 55.4e-3, rₒ = 6.12e-3, ϵᵣ = 2.3))

    CableDC23_1 = cable(length = 200e3, positions = [(0, 1.5), (1, 1.5)],
        C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
        I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3, ϵᵣ = 2.5),
        C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
        I2 = Insulator(rᵢ = 55.4e-3, rₒ = 6.12e-3, ϵᵣ = 2.3))

    # Loads
    # Modeled as shunt branches with resistance and inductance/capacitance

    # LoadB3

    LoadB3 = impedance(z = (s::Complex) -> (R_B3+s*L_B3), conductors = 3)

    # LoadB4

    LoadB4 = impedance(z = (s::Complex) -> (R_B4+(1/(s*C_B4))), conductors = 3)

    # LoadB5

    LoadB5 = impedance(z = (s::Complex) -> (R_B5+s*L_B5), conductors = 3)

    # LoadB6

    LoadB6 = impedance(z = (s::Complex) -> (R_B6+s*L_B6), conductors = 3)

    # Connections

    # Load grounding

    #Sources grounding

    # Bottom area

    #  #
    # #

    ##
    #  #

    # HVDC links

    # DC side TLC

    # Top area

    # T7_8 Floating no Bus 8!

    elements = (; G1, G2, DC_WF1, DC_WF2, DC_WF3, Zg2, Zg1, MMC1, MMC2, MMC3, MMC4, WF1,
        WF2, WF3, T1_2, T1_5, T2_5, T4_5, T2_4, T2_3, T3_4, T12_13, T6_12, T6_13, T6_11,
        T10_11, T13_14, T9_14, T9_10, T7_9, CableDC23, CableDC23_1, LoadB3, LoadB4,
        LoadB5, LoadB6)
    topology = (
        NetworkBuilder.Bus(:gnd;
            ports = ((:LoadB3, :side2), (:LoadB4, :side2),
                (:LoadB5, :side2), (:LoadB6, :side2)),
            domain = ACDQ),
        NetworkBuilder.Bus(:Zg1_side1; ports = ((:Zg1, :side1), (:G1, :ac)), domain = ACDQ),
        NetworkBuilder.Bus(
            :Bus1; ports = ((:Zg1, :side2), (:T1_2, :side1), (:T1_5,
                :side1)),
            domain = ACDQ),
        NetworkBuilder.Bus(:Bus2;
            ports = ((:T2_3, :side1), (:T2_4, :side1), (:T1_2,
                    :side2), (:T2_5, :side1)),
            domain = ACDQ),
        NetworkBuilder.Bus(
            :Bus3; ports = ((:T2_3, :side2), (:T3_4, :side1), (:LoadB3,
                :side1)),
            domain = ACDQ),
        NetworkBuilder.Bus(:Bus4;
            ports = ((:T4_5, :side1), (:T2_4, :side2), (:T3_4,
                    :side2),
                (:MMC4, :ac), (:LoadB4, :side1)),
            domain = ACDQ),
        NetworkBuilder.Bus(:Bus5;
            ports = ((:T4_5, :side2), (:T1_5, :side2), (:MMC3,
                    :ac),
                (:LoadB5, :side1), (:T2_5, :side2)),
            domain = ACDQ),
        NetworkBuilder.Bus(:BusDC1; ports = ((:CableDC23, :side1), (:MMC1, :dc))),
        NetworkBuilder.Bus(:BusDC2; ports = ((:CableDC23_1, :side1), (:MMC2, :dc))),
        NetworkBuilder.Bus(:BusDC3; ports = ((:CableDC23, :side2), (:MMC3, :dc))),
        NetworkBuilder.Bus(:BusDC4; ports = ((:CableDC23_1, :side2), (:MMC4, :dc))),
        NetworkBuilder.Bus(:WF1_dc; ports = ((:WF1, :dc), (:DC_WF1, :dc))),
        NetworkBuilder.Bus(:WF2_dc; ports = ((:WF2, :dc), (:DC_WF2, :dc))),
        NetworkBuilder.Bus(:WF3_dc; ports = ((:WF3, :dc), (:DC_WF3, :dc))),
        NetworkBuilder.Bus(:Zg2_side1; ports = ((:Zg2, :side1), (:G2, :ac)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus6;
            ports = ((:Zg2, :side2), (:MMC1, :ac), (:T6_12,
                    :side1),
                (:T6_13, :side1), (:T6_11, :side1), (:LoadB6, :side1)),
            domain = ACDQ),
        NetworkBuilder.Bus(
            :Bus12; ports = ((:T6_12, :side2), (:T12_13, :side1), (:WF1,
                :ac)),
            domain = ACDQ),
        NetworkBuilder.Bus(:Bus13;
            ports = ((:T12_13, :side2), (:T6_13, :side2),
                (:T13_14, :side1), (:WF2, :ac)),
            domain = ACDQ),
        NetworkBuilder.Bus(
            :Bus14; ports = ((:T9_14, :side1), (:T13_14, :side2), (:WF3,
                :ac)),
            domain = ACDQ),
        NetworkBuilder.Bus(
            :Bus9; ports = ((:T9_14, :side2), (:T7_9, :side1), (:T9_10,
                :side1)),
            domain = ACDQ),
        NetworkBuilder.Bus(:Bus7; ports = ((:MMC2, :ac), (:T7_9, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus10; ports = ((:T10_11, :side1), (:T9_10, :side2)),
            domain = ACDQ),
        NetworkBuilder.Bus(:Bus11; ports = ((:T10_11, :side2), (:T6_11, :side2)),
            domain = ACDQ)
    )
    NetworkBuilder.define(elements, topology; options = (; voltageBase = Vm))
end
powerflow = compute(PowerFlowProblem(IEEE14bus), ACDCPowerFlow())
network_model = NetworkBuilder.NetworkModel(IEEE14bus, powerflow.operating_point)
omegas = 2π .* 10 .^ range(log10(min_f), log10(max_f), length = n_f)
s = ComplexF64.(im .* omegas)
# Calculation of the Y node admittance matrix
source_elements = [network_model.indices.elements[name] for name in (:Zg1, :Zg2)]
node_elements = union(network_model.active_elements, source_elements)
# Automatic nodelist
node_indices = union(network_model.retained_nodes,
    [network_model.indices.nodes[name] for name in (:Bus1d, :Bus1q)])
node_indices = setdiff(node_indices, network_model.grounded_nodes)
node_names = Dict(index => name for (name, index) in network_model.indices.nodes)
nodelist_node = [node_names[index] for index in node_indices]
Ynode_auto = NetworkBuilder.make_y(network_model, node_elements, s, node_indices)

# Calculate Ynode with explicit nodelist
nodelist_manual=[:Bus1d
                 :Bus1q
                 :BusDC1
                 :Bus6d
                 :Bus6q
                 :BusDC2
                 :Bus7d
                 :Bus7q
                 :BusDC3
                 :Bus5d
                 :Bus5q
                 :BusDC4
                 :Bus4d
                 :Bus4q
                 :Bus12d
                 :Bus12q
                 :Bus13d
                 :Bus13q
                 :Bus14d
                 :Bus14q]
manual_indices = [network_model.indices.nodes[name] for name in nodelist_manual]
# Manual nodelist
Ynode2 = NetworkBuilder.make_y(network_model, node_elements, s, manual_indices)
permutation = [findfirst(==(name), nodelist_node) for name in nodelist_manual]
Ynode1 = Ynode_auto[permutation, permutation, :]

function ieee14_y(model, s)
    A, B, C, D = model.cache.A, model.cache.B, model.cache.C, model.cache.D
    Y = C * ((s * I - A) \ B) + D
    b = bases(model)
    if model isa MMC
        ratio = model.elec.turnsRatio
        Y[1, :] .*= b.S / b.v_dc
        Y[2:3, :] .*= 2b.S / (3b.v_ac) * ratio
    else
        Y[1, :] .*= model.elec.iDCbase
        Y[2:3, :] .*= model.elec.iACbase
    end
    Y[:, 1] ./= b.v_dc
    Y[:, 2:3] ./= b.v_ac
    return Y
end

# Manual calculation of the Y node admittance matrix
# Applying the node ordering from above :)
Ynode_manual=[]

for i in eachindex(omegas)
    Ynode_manual_f=zeros(Complex{Float64}, 20, 20)

    # MMCs
    MMC1_adm=ieee14_y(IEEE14bus.elements[:MMC1], omegas[i]*im)
    MMC2_adm=ieee14_y(IEEE14bus.elements[:MMC2], omegas[i]*im)
    MMC3_adm=ieee14_y(IEEE14bus.elements[:MMC3], omegas[i]*im)
    MMC4_adm=ieee14_y(IEEE14bus.elements[:MMC4], omegas[i]*im)
    MMC1_adm=vcat(MMC1_adm[1:1, 1:3], MMC1_adm[2:3, 1:3])
    MMC2_adm=vcat(MMC2_adm[1:1, 1:3], MMC2_adm[2:3, 1:3])
    MMC3_adm=vcat(MMC3_adm[1:1, 1:3], MMC3_adm[2:3, 1:3])
    MMC4_adm=vcat(MMC4_adm[1:1, 1:3], MMC4_adm[2:3, 1:3])

    # TLCs
    TLC1_adm=(ieee14_y(IEEE14bus.elements[:WF1], omegas[i]*im))[2:3, 2:3]
    TLC2_adm=(ieee14_y(IEEE14bus.elements[:WF2], omegas[i]*im))[2:3, 2:3]
    TLC3_adm=(ieee14_y(IEEE14bus.elements[:WF3], omegas[i]*im))[2:3, 2:3]

    # Sources
    SRC1=NetworkBuilder.admittance(IEEE14bus.elements[:Zg1], omegas[i]*im, :dq)[1:2, 1:2]
    SRC2=NetworkBuilder.admittance(IEEE14bus.elements[:Zg2], omegas[i]*im, :dq)[1:2, 1:2]

    #Source
    Ynode_manual_f[1:2, :1:2]=SRC1

    #MMC
    Ynode_manual_f[3:5, :3]=MMC1_adm[:, 1]
    Ynode_manual_f[3, 3:5]=MMC1_adm[1, :]
    Ynode_manual_f[4:5, 4:5]=MMC1_adm[2:3, 2:3]+SRC2

    Ynode_manual_f[6:8, :6:8]=MMC2_adm
    Ynode_manual_f[9:11, :9:11]=MMC3_adm
    Ynode_manual_f[12:14, :12:14]=MMC4_adm

    #TLCs
    Ynode_manual_f[15:16, :15:16]=TLC1_adm
    Ynode_manual_f[17:18, :17:18]=TLC2_adm
    Ynode_manual_f[19:20, :19:20]=TLC3_adm

    push!(Ynode_manual, Ynode_manual_f)
end

# Compare manual Yedge with automate Yedge
columns=[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]

for i in eachindex(omegas)
    for c in columns
        for r in columns
            @test (Ynode_manual[i][r, c]) ≈ (Ynode1[r, c, i]) rtol=1e-8
            @test (Ynode_manual[i][r, c]) ≈ (Ynode2[r, c, i]) rtol=1e-8
        end
    end
end
