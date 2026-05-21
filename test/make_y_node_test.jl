function calc_RLC(P,Q,V,component)
# Function to calculate resistance, inductance or capacitance of a 3-phase series load for a given 1-phase active "P" and reactive power "Q" [MVA]
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

        elseif component =="L"

        
        L= Q/(I^2*2*pi*50)
        return L

        elseif component == "C"

        C=(I^2)/(Q*2*pi*50)
        return C
        else
        error("No implemented load component specified!")
        end

end

# Operating points
P_MMC1= -500
Q_MMC1= 0
P_MMC2=-1000
Q_MMC2=0
Q_MMC3=0.0
Q_MMC4=0.0
Pwf=600
Qwf=0

# Get load parameters :)
R_B3=calc_RLC(314,63.333,380,"R")
L_B3=calc_RLC(314,63.333,380,"L")

R_B4=calc_RLC(159.333,13,380,"R")
C_B4=calc_RLC(159.333,13,380,"C")

R_B5=calc_RLC(25.333,5.333,380,"R")
L_B5=calc_RLC(25.333,5.333,380,"L")

R_B6=calc_RLC(37.333,25.0,380,"R")
L_B6=calc_RLC(37.333,25.0,380,"L")

# Stability analysis options
min_f=0.1 # Minimum frequency in Hz
max_f=5e3 # Maximum frequency in Hz 
n_f=100 # Discretization of the frequency, high value needed for PMD

Vm=380/sqrt(3)

# MMCs
MMC1 = PowerImpedanceACDC.mmc(
        elec = PowerImpedanceACDC.ElectricalMMC(
                Lᵣ = 0.18 * (333^2 / 1000) / (2 * pi * 50),
                Rᵣ = 0.001 * (333^2 / 1000),
                Rₐᵣₘ = 0.4,
                Lₐᵣₘ = 46.125e-3,
                Cₐᵣₘ = 11.3867e-3,
                N = 400,
                turnsRatio = 333 / 380,
                vACbase_LL_RMS = 333,
                Sbase = 1000,
                vDC_base = 640,
        ),
        meas = PowerImpedanceACDC.Measurement(
                P_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
                Q_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
        ),
        sync = PowerImpedanceACDC.VSEWithDamping(
                H = 5,
                K_d = 100,
                K_ω = 10,
                P_ac_ref = P_MMC1 / 1000.0,
                ω_ref = 1.0,
                pll = PowerImpedanceACDC.PLLSynchronization(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.28, Ki = 12.5664),
                        filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 75 * 2π),
                ),
        ),
        delta_control = PowerImpedanceACDC.ΔdqControlGFM(
                outer_reactive = PowerImpedanceACDC.OuterReactiveQControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.0, Ki = 3),
                        Q_ac_ref = 0.0,
                        support = PowerImpedanceACDC.NoVoltageSupport(),
                ),
                vi = PowerImpedanceACDC.CCVI(
                        R_v = 0.01,
                        L_v = 0.25,
                        V_d_ref = 1,
                        V_q_ref = 0,
                        filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 200),
                ),
                occ = PowerImpedanceACDC.InnerCurrentPIControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.6532, Ki = 281.1370),
                        filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 200 * 2π),
                ),
        ),
        sigma_control = PowerImpedanceACDC.ΣdqzControlTEC(
                tec = PowerImpedanceACDC.TotalEnergyControl(
                        pi_control = PowerImpedanceACDC.PIControl(Kp = 1.469, Ki = 31.4819),
                ),
                zscc = PowerImpedanceACDC.ZeroSequenceCurrentControl(
                        PowerImpedanceACDC.PIControl(Kp = 0.0936, Ki = 40.5396),
                ),
                ccsc = PowerImpedanceACDC.CirculatingCurrentSuppressionControl(
                        PowerImpedanceACDC.PIControl(Kp = 0.0936, Ki = 40.5396),
                ),
        ),
        modulation = PowerImpedanceACDC.UncompensatedModulation(
                timeDelay = 200e-6,
                padeOrderNum = 5,
                padeOrderDen = 5,
        ),
        setpoint = PowerImpedanceACDC.SetPoint(
                Pac = P_MMC1,
                Qac = Q_MMC1,
                θac = 0.0,
                Vac = Vm,
                Pdc = P_MMC1,
                Vdc = 640,
        ),
        limits = PowerImpedanceACDC.Limits(
                P_min = -1500.0,
                P_max = 1500.0,
                Q_min = -1000.0,
                Q_max = 1000.0,
        ),
)

MMC2 = PowerImpedanceACDC.mmc(
        elec = PowerImpedanceACDC.ElectricalMMC(
                Lᵣ = 0.18 * (333^2 / 1000) / (2 * pi * 50),
                Rᵣ = 0.001 * (333^2 / 1000),
                Rₐᵣₘ = 0.4,
                Lₐᵣₘ = 46.125e-3,
                Cₐᵣₘ = 11.3867e-3,
                N = 400,
                turnsRatio = 333 / 380,
                vACbase_LL_RMS = 333,
                Sbase = 1000,
                vDC_base = 640,
        ),
        meas = PowerImpedanceACDC.Measurement(
                P_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
                Q_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
        ),
        sync = PowerImpedanceACDC.VSEWithDamping(
                H = 5,
                K_d = 100,
                K_ω = 10,
                P_ac_ref = P_MMC2 / 1000.0,
                ω_ref = 1.0,
                pll = PowerImpedanceACDC.PLLSynchronization(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.28, Ki = 12.5664),
                        filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 75 * 2π),
                ),
        ),
        delta_control = PowerImpedanceACDC.ΔdqControlGFM(
                outer_reactive = PowerImpedanceACDC.OuterReactiveQControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.0, Ki = 3),
                        Q_ac_ref = Q_MMC2/1000.0,
                        support = PowerImpedanceACDC.NoVoltageSupport(),
                ),
                vi = PowerImpedanceACDC.CCVI(
                        R_v = 0.0,
                        L_v = 0.4,
                        V_d_ref = 1,
                        V_q_ref = 0,
                        filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 200),
                ),
                occ = PowerImpedanceACDC.InnerCurrentPIControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.6532, Ki = 281.1370),
                        filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 400 * 2π),
                ),
        ),
        sigma_control = PowerImpedanceACDC.ΣdqzControlTEC(
                tec = PowerImpedanceACDC.TotalEnergyControl(
                        pi_control = PowerImpedanceACDC.PIControl(Kp = 1.469, Ki = 31.4819),
                ),
                zscc = PowerImpedanceACDC.ZeroSequenceCurrentControl(
                        PowerImpedanceACDC.PIControl(Kp = 0.0936, Ki = 40.5396),
                ),
                ccsc = PowerImpedanceACDC.CirculatingCurrentSuppressionControl(
                        PowerImpedanceACDC.PIControl(Kp = 0.0936, Ki = 40.5396),
                ),
        ),
        modulation = PowerImpedanceACDC.UncompensatedModulation(
                timeDelay = 200e-6,
                padeOrderNum = 5,
                padeOrderDen = 5,
        ),
        setpoint = PowerImpedanceACDC.SetPoint(
                Pac = P_MMC2,
                Qac = Q_MMC2,
                θac = 0.0,
                Vac = Vm,
                Pdc = P_MMC2,
                Vdc = 640,
        ),
        limits = PowerImpedanceACDC.Limits(
                P_min = -1500.0,
                P_max = 1500.0,
                Q_min = -1000.0,
                Q_max = 1000.0,
        ),
)

MMC3 = PowerImpedanceACDC.mmc(
        elec = PowerImpedanceACDC.ElectricalMMC(
                Lᵣ = 0.1305 * (333^2 / 1000) / (2 * pi * 50),
                Rᵣ = 0.0037 * (333^2 / 1000),
                Rₐᵣₘ = 0.4,
                Lₐᵣₘ = 46.125e-3,
                Cₐᵣₘ = 11.3867e-3,
                N = 400,
                turnsRatio = 333 / 380,
                vACbase_LL_RMS = 333,
                Sbase = 1000,
                vDC_base = 640,
        ),
        meas = PowerImpedanceACDC.Measurement(
                P_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
                Q_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
        ),
        sync = PowerImpedanceACDC.PLLSynchronization(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.28, Ki = 12.5664),
                filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 80 * 2π),
        ),
        delta_control = PowerImpedanceACDC.ΔdqControlGFL(
                outer_active = PowerImpedanceACDC.OuterActiveVdcControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 5, Ki = 15),
                        v_dc_ref = 1.0,
                ),
                outer_reactive = PowerImpedanceACDC.OuterReactiveQControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.1, Ki = 31.4159),
                        Q_ac_ref = Q_MMC3/1000.0,
                        support = PowerImpedanceACDC.NoVoltageSupport(),
                ),
                occ = PowerImpedanceACDC.InnerCurrentPIControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.1048, Ki = 48.1914),
                        filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 600 * 2π),
                ),
        ),
        sigma_control = PowerImpedanceACDC.ΣdqzControlTEC(
                tec = PowerImpedanceACDC.TotalEnergyControl(
                        pi_control = PowerImpedanceACDC.PIControl(Kp = 1.2894, Ki = 27.63),
                ),
                zscc = PowerImpedanceACDC.ZeroSequenceCurrentControl(
                        PowerImpedanceACDC.PIControl(Kp = 0.0992, Ki = 42.9719),
                ),
                ccsc = PowerImpedanceACDC.CirculatingCurrentSuppressionControl(
                        PowerImpedanceACDC.PIControl(Kp = 0.0992, Ki = 42.9719),
                ),
        ),
        modulation = PowerImpedanceACDC.UncompensatedModulation(
                timeDelay = 250e-6,
                padeOrderNum = 5,
                padeOrderDen = 5,
        ),
        setpoint = PowerImpedanceACDC.SetPoint(
                Pac = 0.0,
                Qac = Q_MMC3,
                θac = 0.0,
                Vac = Vm,
                Pdc = 0.0,
                Vdc = 640,
        ),
        limits = PowerImpedanceACDC.Limits(
                P_min = -1500.0,
                P_max = 1500.0,
                Q_min = -1000.0,
                Q_max = 1000.0,
        ),
)

MMC4 = PowerImpedanceACDC.mmc(
        elec = PowerImpedanceACDC.ElectricalMMC(
                Lᵣ = 0.1305 * (333^2 / 1000) / (2 * pi * 50),
                Rᵣ = 0.0037 * (333^2 / 1000),
                Rₐᵣₘ = 0.4,
                Lₐᵣₘ = 46.125e-3,
                Cₐᵣₘ = 11.3867e-3,
                N = 400,
                turnsRatio = 333 / 380,
                vACbase_LL_RMS = 333,
                Sbase = 1000,
                vDC_base = 640,
        ),
        meas = PowerImpedanceACDC.Measurement(
                P_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
                Q_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
        ),
        sync = PowerImpedanceACDC.PLLSynchronization(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.28, Ki = 12.5664),
                filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 80 * 2π),
        ),
        delta_control = PowerImpedanceACDC.ΔdqControlGFL(
                outer_active = PowerImpedanceACDC.OuterActiveVdcControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 5, Ki = 15),
                        v_dc_ref = 1.0,
                ),
                outer_reactive = PowerImpedanceACDC.OuterReactiveQControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.1, Ki = 31.4159),
                        Q_ac_ref = Q_MMC4/1000.0,
                        support = PowerImpedanceACDC.NoVoltageSupport(),
                ),
                occ = PowerImpedanceACDC.InnerCurrentPIControl(
                        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.1048, Ki = 48.1914),
                        filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 100 * 2π),
                ),
        ),
        sigma_control = PowerImpedanceACDC.ΣdqzControlTEC(
                tec = PowerImpedanceACDC.TotalEnergyControl(
                        pi_control = PowerImpedanceACDC.PIControl(Kp = 1.2894, Ki = 27.63),
                ),
                zscc = PowerImpedanceACDC.ZeroSequenceCurrentControl(
                        PowerImpedanceACDC.PIControl(Kp = 0.0992, Ki = 42.9719),
                ),
                ccsc = PowerImpedanceACDC.CirculatingCurrentSuppressionControl(
                        PowerImpedanceACDC.PIControl(Kp = 0.0992, Ki = 42.9719),
                ),
        ),
        modulation = PowerImpedanceACDC.UncompensatedModulation(
                timeDelay = 200e-6,
                padeOrderNum = 5,
                padeOrderDen = 5,
        ),
        setpoint = PowerImpedanceACDC.SetPoint(
                Pac = 0.0,
                Qac = Q_MMC4,
                θac = 0.0,
                Vac = Vm,
                Pdc = 0.0,
                Vdc = 640,
        ),
        limits = PowerImpedanceACDC.Limits(
                P_min = -1500.0,
                P_max = 1500.0,
                Q_min = -1000.0,
                Q_max = 1000.0,
        ),
)

# TLCs
WF1 = PowerImpedanceACDC.tlc(
        elec = PowerImpedanceACDC.ElectricalTLC(
                Lᵣ = 0.08 * (380^2 / 600) / (2 * pi * 50),
                Rᵣ = 0.0008 * (380^2 / 600),
                Sbase = 600,
                vACbase_LL_RMS = 380,
                vDCbase = 640,
        ),
        meas = PowerImpedanceACDC.Measurement(
                v_ac = PowerImpedanceACDC.Butterworth(order = 1, ωc = 1e4),
                i_ac = PowerImpedanceACDC.Butterworth(order = 1, ωc = 1e4),
        ),
        sync = PowerImpedanceACDC.PLLSynchronization(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.3978, Ki = 7.9577),
                filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 2 * pi * 50),
        ),
        outerActive = PowerImpedanceACDC.OuterActivePowerControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.01, Ki = 10),
                P_ac_ref = 0.0,
                support = PowerImpedanceACDC.NoFrequencySupport(),
        ),
        outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.01, Ki = 10),
                Q_ac_ref = 0.0,
                support = PowerImpedanceACDC.NoVoltageSupport(),
        ),
        innerVoltage = PowerImpedanceACDC.NoInnerVoltageControl(),
        innerCurrent = PowerImpedanceACDC.InnerCurrentPIControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.254647908947033, Ki = 0.8),
        ),
        mod = PowerImpedanceACDC.NoModulation(),
        setpoint = PowerImpedanceACDC.SetPoint(
                Pac = Pwf,
                Qac = Qwf,
                θac = 0.0,
                Vac = Vm * sqrt(2),
                Pdc = Pwf,
                Vdc = 640,
        ),
        limits = PowerImpedanceACDC.Limits(
                P_min = -1000.0,
                P_max = 1000.0,
                Q_min = -1000.0,
                Q_max = 1000.0,
        ),
)

WF2 = PowerImpedanceACDC.tlc(
        elec = PowerImpedanceACDC.ElectricalTLC(
                Lᵣ = 0.08 * (380^2 / 600) / (2 * pi * 50),
                Rᵣ = 0.0008 * (380^2 / 600),
                Sbase = 600,
                vACbase_LL_RMS = 380,
                vDCbase = 640,
        ),
        meas = PowerImpedanceACDC.Measurement(
                v_ac = PowerImpedanceACDC.Butterworth(order = 1, ωc = 1e4),
                i_ac = PowerImpedanceACDC.Butterworth(order = 1, ωc = 1e4),
        ),
        sync = PowerImpedanceACDC.PLLSynchronization(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.3978, Ki = 7.9577),
                filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 2 * pi * 80),
        ),
        outerActive = PowerImpedanceACDC.OuterActivePowerControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.01, Ki = 10),
                P_ac_ref = 0.0,
                support = PowerImpedanceACDC.NoFrequencySupport(),
        ),
        outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.01, Ki = 10),
                Q_ac_ref = 0.0,
                support = PowerImpedanceACDC.NoVoltageSupport(),
        ),
        innerVoltage = PowerImpedanceACDC.NoInnerVoltageControl(),
        innerCurrent = PowerImpedanceACDC.InnerCurrentPIControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.254647908947033, Ki = 0.8),
        ),
        mod = PowerImpedanceACDC.NoModulation(),
        setpoint = PowerImpedanceACDC.SetPoint(
                Pac = Pwf,
                Qac = Qwf,
                θac = 0.0,
                Vac = Vm * sqrt(2),
                Pdc = Pwf,
                Vdc = 640,
        ),
        limits = PowerImpedanceACDC.Limits(
                P_min = -1000.0,
                P_max = 1000.0,
                Q_min = -1000.0,
                Q_max = 1000.0,
        ),
)

WF3 = PowerImpedanceACDC.tlc(
        elec = PowerImpedanceACDC.ElectricalTLC(
                Lᵣ = 0.08 * (380^2 / 600) / (2 * pi * 50),
                Rᵣ = 0.0008 * (380^2 / 600),
                Sbase = 600,
                vACbase_LL_RMS = 380,
                vDCbase = 640,
        ),
        meas = PowerImpedanceACDC.Measurement(
                v_ac = PowerImpedanceACDC.Butterworth(order = 1, ωc = 1e4),
                i_ac = PowerImpedanceACDC.Butterworth(order = 1, ωc = 1e4),
        ),
        sync = PowerImpedanceACDC.PLLSynchronization(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.3978, Ki = 7.9577),
                filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 2 * pi * 80),
        ),
        outerActive = PowerImpedanceACDC.OuterActivePowerControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.01, Ki = 10),
                P_ac_ref = 0.0,
                support = PowerImpedanceACDC.NoFrequencySupport(),
        ),
        outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.01, Ki = 10),
                Q_ac_ref = 0.0,
                support = PowerImpedanceACDC.NoVoltageSupport(),
        ),
        innerVoltage = PowerImpedanceACDC.NoInnerVoltageControl(),
        innerCurrent = PowerImpedanceACDC.InnerCurrentPIControl(
                pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.254647908947033, Ki = 0.8),
        ),
        mod = PowerImpedanceACDC.NoModulation(),
        setpoint = PowerImpedanceACDC.SetPoint(
                Pac = Pwf,
                Qac = Qwf,
                θac = 0.0,
                Vac = Vm * sqrt(2),
                Pdc = Pwf,
                Vdc = 640,
        ),
        limits = PowerImpedanceACDC.Limits(
                P_min = -1000.0,
                P_max = 1000.0,
                Q_min = -1000.0,
                Q_max = 1000.0,
        ),
)


IEEE14bus = @network begin

voltageBase = Vm

# Sources
G1=ac_source(pins = 3,setpoint=SetPoint(Vac = Vm), transformation = true)
G2=ac_source(pins = 3, setpoint=SetPoint(Vac = Vm), transformation = true)
DC_WF1=dc_source(pins = 2, setpoint=SetPoint(Vdc = 320), transformation = true)
DC_WF2=dc_source(pins = 2, setpoint=SetPoint(Vdc = 320), transformation = true)
DC_WF3=dc_source(pins = 2, setpoint=SetPoint(Vdc = 320), transformation = true)
Zg2=impedance(z = (s::Complex)-> (1.0263 + s*0.0327), pins = 3, transformation = true) # Top area
Zg1=impedance(z = (s::Complex)-> (0.2874  + s*0.0091)  , pins = 3, transformation = true) # Bottom area


#Converters
MMC1 = MMC1
MMC2 = MMC2
MMC3 = MMC3
MMC4 = MMC4
WF1 = WF1
WF2 = WF2
WF3 = WF3



# Overhead lines

# Bottom area ⬇
T1_2 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T1_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
# Create HFO instability with trip of T2_5
T2_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T4_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T2_4 = overhead_line(length = 250e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)


T2_3 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T3_4 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

# Top area⬆
T12_13 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_12 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_13 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_11 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)


T10_11 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T13_14 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T9_14 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T9_10 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
T7_9 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

# Cables
# ABB Datasheet cables with no amouring to represent onshore cables 
CableDC23 = cable(length = 200e3, positions = [(0,1.5), (1,1.5)],
    C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
    I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
    C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
    I2 = Insulator(rᵢ = 55.4e-3, rₒ = 6.12e-3, ϵᵣ = 2.3), transformation = true)  

CableDC23_1 = cable(length = 200e3, positions = [(0,1.5), (1,1.5)],
    C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
    I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
    C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
    I2 = Insulator(rᵢ = 55.4e-3, rₒ = 6.12e-3, ϵᵣ = 2.3), transformation = true)     

# Loads
# Modeled as shunt branches with resistance and inductance/capacitance


# LoadB3

LoadB3= impedance(z =(s::Complex)->  (R_B3+s*L_B3), pins = 3, transformation = true)


# LoadB4

LoadB4= impedance(z = (s::Complex)-> (R_B4+(1/(s*C_B4))), pins = 3, transformation = true)


# LoadB5

LoadB5= impedance(z = (s::Complex)-> (R_B5+s*L_B5), pins = 3, transformation = true)

# LoadB6

LoadB6= impedance(z = (s::Complex)-> (R_B6+s*L_B6), pins = 3, transformation = true)



# Connections

# Load grounding

LoadB3[2.1] ⟷ gndD
LoadB3[2.2] ⟷ gndQ

LoadB4[2.1] ⟷ gndD
LoadB4[2.2] ⟷ gndQ

LoadB5[2.1] ⟷ gndD
LoadB5[2.2] ⟷ gndQ

LoadB6[2.1] ⟷ gndD
LoadB6[2.2] ⟷ gndQ

#Sources grounding
G1[2.1] ⟷ gndD
G1[2.2] ⟷ gndQ

G2[2.1] ⟷ gndD
G2[2.2] ⟷ gndQ
DC_WF1[2.1] ⟷ gndDC
DC_WF2[2.1] ⟷ gndDC
DC_WF3[2.1] ⟷ gndDC

# Bottom area

Zg1[1.1] ⟷ G1[1.1] 
Zg1[1.2] ⟷ G1[1.2] 

Zg1[2.1] ⟷ T1_2[1.1] ⟷ T1_5[1.1] ⟷ Bus1d
Zg1[2.2] ⟷ T1_2[1.2] ⟷ T1_5[1.2] ⟷ Bus1q

T2_3[1.1] ⟷ T2_4[1.1]  ⟷ T1_2[2.1]  ⟷ T2_5[1.1] ⟷ Bus2d#  #
T2_3[1.2] ⟷ T2_4[1.2]  ⟷ T1_2[2.2]  ⟷ T2_5[1.2] ⟷Bus2q# #

T2_3[2.1] ⟷ T3_4[1.1] ⟷  LoadB3[1.1] ⟷ Bus3d 
T2_3[2.2] ⟷ T3_4[1.2] ⟷  LoadB3[1.2] ⟷ Bus3q 

T4_5[1.1] ⟷ T2_4[2.1] ⟷ T3_4[2.1] ⟷  MMC4[2.1] ⟷ LoadB4[1.1] ⟷ Bus4d 
T4_5[1.2] ⟷ T2_4[2.2] ⟷ T3_4[2.2] ⟷  MMC4[2.2] ⟷ LoadB4[1.2] ⟷ Bus4q  

T4_5[2.1] ⟷ T1_5[2.1] ⟷ MMC3[2.1] ⟷  LoadB5[1.1] ⟷ T2_5[2.1] ⟷Bus5d ##
T4_5[2.2] ⟷ T1_5[2.2] ⟷ MMC3[2.2] ⟷ LoadB5[1.2] ⟷ T2_5[2.2] ⟷Bus5q#  #

# HVDC links

CableDC23[1.1] ⟷ MMC1[1.1] ⟷ BusDC1
CableDC23_1[1.1] ⟷ MMC2[1.1] ⟷ BusDC2
CableDC23[2.1] ⟷ MMC3[1.1] ⟷ BusDC3
CableDC23_1[2.1] ⟷ MMC4[1.1] ⟷ BusDC4

# DC side TLC

WF1[1.1] ⟷ DC_WF1[1.1]
WF2[1.1] ⟷ DC_WF2[1.1]
WF3[1.1] ⟷ DC_WF3[1.1]

# Top area

Zg2[1.1] ⟷ G2[1.1] 
Zg2[1.2] ⟷ G2[1.2]

Zg2[2.1] ⟷ MMC1[2.1] ⟷ T6_12[1.1] ⟷ T6_13[1.1] ⟷ T6_11[1.1] ⟷ LoadB6[1.1] ⟷Bus6d 
Zg2[2.2] ⟷ MMC1[2.2] ⟷ T6_12[1.2] ⟷ T6_13[1.2] ⟷ T6_11[1.2] ⟷ LoadB6[1.2] ⟷Bus6q

T6_12[2.1] ⟷ T12_13[1.1] ⟷ WF1[2.1] ⟷ Bus12d
T6_12[2.2] ⟷ T12_13[1.2] ⟷ WF1[2.2] ⟷ Bus12q

T12_13[2.1] ⟷ T6_13[2.1] ⟷ T13_14[1.1] ⟷ WF2[2.1] ⟷ Bus13d
T12_13[2.2] ⟷ T6_13[2.2] ⟷ T13_14[1.2] ⟷ WF2[2.2] ⟷ Bus13q

T9_14[1.1] ⟷ T13_14[2.1]  ⟷ WF3[2.1] ⟷ Bus14d
T9_14[1.2] ⟷ T13_14[2.2]  ⟷ WF3[2.2] ⟷ Bus14q

T9_14[2.1] ⟷ T7_9[1.1]  ⟷ T9_10[1.1]  ⟷ Bus9d
T9_14[2.2] ⟷ T7_9[1.2]  ⟷ T9_10[1.2]  ⟷ Bus9q
# T7_8 Floating no Bus 8!
MMC2[2.1] ⟷ T7_9[2.1]  ⟷ Bus7d
MMC2[2.2] ⟷ T7_9[2.2]  ⟷ Bus7q

T10_11[1.1] ⟷ T9_10[2.1] ⟷ Bus10d
T10_11[1.2] ⟷ T9_10[2.2] ⟷ Bus10q

T10_11[2.1] ⟷ T6_11[2.1]  ⟷ Bus11d
T10_11[2.2] ⟷ T6_11[2.2]  ⟷ Bus11q

end

# Calculation of the Y node admittance matrix
Ynode1,nodelist_node,omegas=make_y_node(IEEE14bus,freq_range = (min_f,max_f,n_f)) # Automatic nodelist


# Calculate Ynode with explicit nodelist 
nodelist_manual=[
 :Bus1d
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
 :Bus14q
]
Ynode2,_,_=make_y_node(IEEE14bus,freq_range = (min_f,max_f,n_f),nodelist = nodelist_manual) # Manual nodelist



# Manual calculation of the Y node admittance matrix
# Applying the node ordering from above :)
Ynode_manual=[]

for i in eachindex(omegas)

    Ynode_manual_f=zeros(Complex{Float64},20,20)

    # MMCs
    MMC1_adm=PowerImpedanceACDC.get_y(IEEE14bus.elements[:MMC1],omegas[i]*im)
    MMC2_adm=PowerImpedanceACDC.get_y(IEEE14bus.elements[:MMC2],omegas[i]*im)
    MMC3_adm=PowerImpedanceACDC.get_y(IEEE14bus.elements[:MMC3],omegas[i]*im)
    MMC4_adm=PowerImpedanceACDC.get_y(IEEE14bus.elements[:MMC4],omegas[i]*im)
    MMC1_adm=vcat(MMC1_adm[1:1,1:3],-MMC1_adm[2:3,1:3])
    MMC2_adm=vcat(MMC2_adm[1:1,1:3],-MMC2_adm[2:3,1:3])
    MMC3_adm=vcat(MMC3_adm[1:1,1:3],-MMC3_adm[2:3,1:3])
    MMC4_adm=vcat(MMC4_adm[1:1,1:3],-MMC4_adm[2:3,1:3])


    # TLCs
    TLC1_adm=(-PowerImpedanceACDC.get_y(IEEE14bus.elements[:WF1],omegas[i]*im))[2:3,2:3]
    TLC2_adm=(-PowerImpedanceACDC.get_y(IEEE14bus.elements[:WF2],omegas[i]*im))[2:3,2:3]
    TLC3_adm=(-PowerImpedanceACDC.get_y(IEEE14bus.elements[:WF3],omegas[i]*im))[2:3,2:3]

    # Sources
    SRC1=PowerImpedanceACDC.get_y(IEEE14bus.elements[:Zg1],omegas[i]*im)[1:2,1:2]
    SRC2=PowerImpedanceACDC.get_y(IEEE14bus.elements[:Zg2],omegas[i]*im)[1:2,1:2]

    #Source
    Ynode_manual_f[1:2,:1:2]=SRC1

    #MMC
    Ynode_manual_f[3:5,:3]=MMC1_adm[:,1]
    Ynode_manual_f[3,3:5]=MMC1_adm[1,:]
    Ynode_manual_f[4:5,4:5]=MMC1_adm[2:3,2:3]+SRC2

    Ynode_manual_f[6:8,:6:8]=MMC2_adm
    Ynode_manual_f[9:11,:9:11]=MMC3_adm
    Ynode_manual_f[12:14,:12:14]=MMC4_adm

    #TLCs
    Ynode_manual_f[15:16,:15:16]=TLC1_adm       
    Ynode_manual_f[17:18,:17:18]=TLC2_adm
    Ynode_manual_f[19:20,:19:20]=TLC3_adm       

    push!(Ynode_manual,Ynode_manual_f)


end

# Compare manual Yedge with automate Yedge
columns=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]

for i in eachindex(omegas)

    for c in columns

        for r in columns
            

            @test (Ynode_manual[i][r,c]) ≈ (Ynode1[i][r,c])  rtol=1e-8
            @test (Ynode_manual[i][r,c]) ≈ (Ynode2[i][r,c])  rtol=1e-8

        end



    end


end
