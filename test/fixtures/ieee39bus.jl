using PowerImpedance

# This is a PowerImpedance implementation of the IEEE 39 bus system test system
# Author: Jan Kircheis
# Date: Jan 2026
# Related PSCAD model to be found under Etch: Control-->PowerImpedance-->IEEE 39-bus system
# 345 kV implementation ---> Everything referred to 345 kV

# Arrange environment


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


#TODO:
# Get load parameters :)
# Load Bus 3
R_B3=calc_RLC(107.3333, 0.8, 345, "R")
L_B3=calc_RLC(107.3333, 0.8, 345, "L")

# Loads Bus 4
R_B4a=calc_RLC(166.6667, 61.3333, 345, "R")
L_B4=calc_RLC(166.6667, 61.3333, 345, "L")
R_B4b=calc_RLC(0, 100, 345, "R")
C_B4=calc_RLC(0, 100, 345, "C")

# Load Bus 5
R_B5=calc_RLC(0, 200, 345, "R")
C_B5=calc_RLC(0, 200, 345, "C")

# Load Bus 7
R_B7=calc_RLC(77.93333, 28.0, 345, "R")
L_B7=calc_RLC(77.93333, 28.0, 345, "L")

#Load Bus 8
R_B8=calc_RLC(174.0, 58.6667, 345, "R")
L_B8=calc_RLC(174.0, 58.6667, 345, "L")

# Load Bus 12
R_B12=calc_RLC(2.5, 29.3333, 230, "R")
L_B12=calc_RLC(2.5, 29.3333, 230, "L")

# Load Bus 15
R_B15=calc_RLC(106.6667, 51.0, 345, "R")
L_B15=calc_RLC(106.6667, 51.0, 345, "L")

# Load Bus 16
R_B16=calc_RLC(109.8, 10.7667, 345, "R")
L_B16=calc_RLC(109.8, 10.7667, 345, "L")

# Load Bus 18
R_B18=calc_RLC(52.6667, 10.0, 345, "R")
L_B18=calc_RLC(52.6667, 10.0, 345, "L")

# Load Bus 20
R_B20=calc_RLC(226.6667, 34.3333, 345, "R")
L_B20=calc_RLC(226.6667, 34.3333, 345, "L")

# Load Bus 21
R_B21=calc_RLC(91.3333, 38.3333, 345, "R")
L_B21=calc_RLC(91.3333, 38.3333, 345, "L")

# Load Bus 23
R_B23=calc_RLC(82.5, 28.2, 345, "R")
L_B23=calc_RLC(82.5, 28.2, 345, "L")

# Load Bus 24
R_B24=calc_RLC(102.8667, 30.73333, 345, "R")
C_B24=calc_RLC(102.8667, 30.73333, 345, "C")

# Load Bus 25
R_B25=calc_RLC(74.6667, 15.7333, 345, "R")
L_B25=calc_RLC(74.6667, 15.7333, 345, "L")

# Load Bus 26
R_B26=calc_RLC(46.3333, 5.6667, 345, "R")
L_B26=calc_RLC(46.3333, 5.6667, 345, "L")

# Load Bus 27
R_B27=calc_RLC(93.6667, 25.1667, 345, "R")
L_B27=calc_RLC(93.6667, 25.1667, 345, "L")

# Load Bus 28
R_B28=calc_RLC(68.6667, 9.2, 345, "R")
L_B28=calc_RLC(68.6667, 9.2, 345, "L")

# Load Bus 29
R_B29=calc_RLC(94.5, 8.9667, 345, "R")
L_B29=calc_RLC(94.5, 8.9667, 345, "L")

# Load Bus 31
R_B31=calc_RLC(3.0667, 1.5333, 22, "R")
L_B31=calc_RLC(3.0667, 1.5333, 22, "L")

# Load Bus 39
R_B39=calc_RLC(368, 83.3333, 345, "R")
L_B39=calc_RLC(368, 83.3333, 345, "L")

# Grid parameters
Vm1=345/sqrt(3) # rms - phase [kV]


# Transformer parameters
Lb_345=(345e3)^2/(2*pi*50*1000e6) # in H
Rb_345=(345e3)^2/(1000e6) # in Ohms

#STATCOM parameters
Vdc_ST=110 #Pole-pole DC voltage
S_ST=269 # MVA
Z_ST_base = 345^2/S_ST
Lf_ST = 0.08 * Z_ST_base / 2/pi/50
Rf_ST = 0.01 * 0.08 * Z_ST_base
# Operating point
Q_ST=-0.5    #pu
Vac_ref_ST=0.9 #pu


const IEEE39_INPUT_PINS = [:Bus9d, :Bus9q]
const IEEE39_OUTPUT_PINS = [:gndd, :gndq]
const IEEE39_ELIM_ELEMENTS = [:STATCOM]
const IEEE39_FREQ_RANGE = (1e0, 5e3, 10)

function ieee39bus_elements()
    elec = PowerImpedance.ElectricalTLC(
        Lᵣ = Lf_ST,
        Rᵣ = Rf_ST,
        Sbase = S_ST,
        vACbase_LL_RMS = 345,
        vDCbase = Vdc_ST
    )

    meas = PowerImpedance.Measurement(
        v_ac = PowerImpedance.Butterworth(order = 2, ωc = 0.5e4),
        i_ac = PowerImpedance.Butterworth(order = 2, ωc = 0.5e4)
    )

    sync = PowerImpedance.PLLSynchronization(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.397887357729738,
            Ki = 7.957747154594767
        ),
        filter = PowerImpedance.Butterworth(order = 2, ωc = 2π * 80)
    )

    innerVoltage = PowerImpedance.NoInnerVoltageControl()

    innerCurrent = PowerImpedance.InnerCurrentPIControl(
        pi_ctrl = PowerImpedance.PIControl(
        Kp = 0.254647908947033,
        Ki = 0.8
    ),
    )

    mod = PowerImpedance.PadeModulation(
        timeDelay = 200e-6,
        padeOrderNum = 3,
        padeOrderDen = 3
    )

    limits = PowerImpedance.Limits(
        P_min = -1000.0,
        P_max = 1000.0,
        Q_min = -1000.0,
        Q_max = 1000.0
    )

    outerActive = PowerImpedance.OuterActiveVdcControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 5.0, Ki = 5.0),
    )

    outerReactive = PowerImpedance.OuterReactiveQControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
        support = PowerImpedance.VoltageSupportLag(
            K = 5.0,
            ωc = 1 / 0.5
        )
    )

    return (;

        # Sources @ 345 kV
        G30 = ac_source(v = Vm1*sqrt(2)),
        G31 = ac_source(v = Vm1*sqrt(2)),
        G32 = ac_source(v = Vm1*sqrt(2)),
        G33 = ac_source(v = Vm1*sqrt(2)),
        G34 = ac_source(v = Vm1*sqrt(2)),
        G35 = ac_source(v = Vm1*sqrt(2)),
        G36 = ac_source(v = Vm1*sqrt(2)),
        G37 = ac_source(v = Vm1*sqrt(2)),
        G38 = ac_source(v = Vm1*sqrt(2)),
        G39 = ac_source(v = Vm1*sqrt(2)),

        # Source impedances @ 345 kV
        Zg30 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg31 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg32 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg33 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg34 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg35 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg36 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg37 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg38 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),
        Zg39 = impedance(;
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            conductors = 3),

        # DC voltage source to arrange Powerflow of Statcom, not possible to directly
        # connect to DC-controlling STATCOM
        G_DC = dc_source(v = Vdc_ST),

        STATCOM = let model = PowerImpedance.tlc(;
            elec = elec,
            meas = meas,
            sync = sync,
            outerActive = outerActive,
            outerReactive = outerReactive,
            innerVoltage = innerVoltage,
            innerCurrent = innerCurrent,
            mod = mod,
            limits = limits
        )
            b = bases(model)
            component(model; outerActive = (v_dc_ref = (Vdc_ST) / b.v_dc,),
                outerReactive = (q_ref = (Q_ST*S_ST) / b.S,
                    support = (v_ac_ref = (Vm1*sqrt(2)*Vac_ref_ST) / b.v_ac,)),
                powerflow = (; p_ac = (0.0) / b.S,
                    p_dc = (0.0) / b.S))
        end,

        # Dummy impedance to arrange powerflow of DC-controlling STATCOM
        dummy_impedance = impedance(; z = 1e4, conductors = 1),

        # Transformers
        # Bus 2 - Bus 30
        TR2_30 = transformer(;
            n = 345/345,
            Lₚ = (0.0181/2)*Lb_345,
            Lₛ = (0.0181/2)*Lb_345,
            conductors = 3),

        # Bus 6 - Bus 31
        TR6_31 = transformer(;
            n = 345/345,
            Lₚ = (0.025/2)*Lb_345,
            Lₛ = (0.025/2)*Lb_345,
            conductors = 3),

        # Bus 10 - Bus 32
        TR10_32 = transformer(;
            n = 345/345,
            Lₚ = (0.02/2)*Lb_345,
            Lₛ = (0.02/2)*Lb_345,
            conductors = 3),

        # Bus 11 - Bus 12
        TR11_12 = transformer(;
            n = 345/345,
            Lₚ = (0.0435/2)*Lb_345,
            Rₚ = (0.0016/2)*Rb_345,
            Lₛ = (0.0435/2)*Lb_345,
            Rₛ = (0.0016/2)*Rb_345,
            conductors = 3),

        # Bus 12 - Bus 13
        TR12_13 = transformer(;
            n = 345/345,
            Lₚ = (0.0435/2)*Lb_345,
            Rₚ = (0.0016/2)*Rb_345,
            Lₛ = (0.0435/2)*Lb_345,
            Rₛ = (0.0016/2)*Rb_345,
            conductors = 3),

        # Bus 19 - Bus 20
        TR19_20 = transformer(;
            n = 345/345,
            Lₚ = (0.0138 / 2)*Lb_345,
            Rₚ = (0.0007/2)*Rb_345,
            Lₛ = (0.0138 / 2)*Lb_345,
            Rₛ = (0.0007/2)*Rb_345,
            conductors = 3),

        # Bus 19 - Bus 33
        TR19_33 = transformer(;
            n = 345/345,
            Lₚ = (0.0142 / 2)*Lb_345,
            Rₚ = (0.0007/2)*Rb_345,
            Lₛ = (0.0142 / 2)*Lb_345,
            Rₛ = (0.0007/2)*Rb_345,
            conductors = 3),

        # Bus 20 - Bus 34
        TR20_34 = transformer(;
            n = 345/345,
            Lₚ = (0.0180 / 2)*Lb_345,
            Rₚ = (0.0009/2)*Rb_345,
            Lₛ = (0.0180 / 2)*Lb_345,
            Rₛ = (0.0009/2)*Rb_345,
            conductors = 3),

        # Bus 22 - Bus 35
        TR22_35 = transformer(;
            n = 345/345,
            Lₚ = (0.0143 / 2)*Lb_345,
            Lₛ = (0.0143 / 2)*Lb_345,
            conductors = 3),

        # Bus 23 - Bus 36
        TR23_36 = transformer(;
            n = 345/345,
            Lₚ = (0.0272 / 2)*Lb_345,
            Rₚ = (0.0005/2)*Rb_345,
            Lₛ = (0.0272 / 2)*Lb_345,
            Rₛ = (0.0005/2)*Rb_345,
            conductors = 3),

        # Bus 25 - Bus 37
        TR25_37 = transformer(;
            n = 345/345,
            Lₚ = (0.0232 / 2)*Lb_345,
            Rₚ = (0.0006/2)*Rb_345,
            Lₛ = (0.0232 / 2)*Lb_345,
            Rₛ = (0.0006/2)*Rb_345,
            conductors = 3),

        # Bus 29 - Bus 38
        TR29_38 = transformer(;
            n = 345/345,
            Lₚ = (0.0156 / 2)*Lb_345,
            Rₚ = (0.0008/2)*Rb_345,
            Lₛ = (0.0156 / 2)*Lb_345,
            Rₛ = (0.0008/2)*Rb_345,
            conductors = 3),

        # Power lines
        T1_2 = overhead_line(; length = 72.4730e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T1_39 = overhead_line(; length = 44.0833e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T2_3 = overhead_line(; length = 26.6263e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T2_25 = overhead_line(; length = 15.1647e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T3_4 = overhead_line(; length = 37.5590e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T3_18 = overhead_line(; length = 23.4523e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T4_5 = overhead_line(; length = 22.5707e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T4_14 = overhead_line(; length = 22.7470e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T5_6 = overhead_line(; length = 4.5847e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T5_8 = overhead_line(; length = 19.7493e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T6_7 = overhead_line(; length = 16.2227e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T6_11 = overhead_line(; length = 14.4593e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T7_8 = overhead_line(; length = 8.1113e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T8_9 = overhead_line(; length = 64.009e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T9_39 = overhead_line(; length = 44.0833e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T10_11 = overhead_line(; length = 7.5823e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T10_13 = overhead_line(; length = 7.5823e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T13_14 = overhead_line(; length = 17.8097e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T14_15 = overhead_line(; length = 38.2643e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T15_16 = overhead_line(; length = 16.5753e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T16_17 = overhead_line(; length = 15.6937e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T16_19 = overhead_line(; length = 34.3850e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T16_21 = overhead_line(; length = 23.8050e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T16_24 = overhead_line(; length = 10.4037e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T17_18 = overhead_line(; length = 14.4593e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T17_27 = overhead_line(; length = 30.5057e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T21_22 = overhead_line(; length = 24.6867e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T22_23 = overhead_line(; length = 16.9280e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T23_24 = overhead_line(; length = 61.7167e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T25_26 = overhead_line(; length = 56.95573e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T26_27 = overhead_line(; length = 25.9210e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T26_28 = overhead_line(; length = 83.5820e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T26_29 = overhead_line(; length = 110.2083e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        T28_29 = overhead_line(; length = 26.6263e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
                rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2,
                Rᵍᵈᶜ = 0.92,
                rᵍ = 0.0062,
                Δxᵍ = 6.5,
                Δyᵍ = 7.5,
                dᵍˢᵃᵍ = 10
            ),
            earth_parameters = (1, 1, 100)),

        # Loads
        # Load Bus 3
        LoadB3 =
        impedance(; z = (s::Complex) -> (R_B3+s*L_B3), conductors = 3),

        # Load Bus 4
        LoadB4a =
        impedance(; z = (s::Complex) -> (R_B4a+s*L_B4), conductors = 3),
        LoadB4b = impedance(;
            z = (s::Complex) -> (R_B4b+(1/(s*C_B4))),
            conductors = 3),

        # Load Bus 5
        LoadB5 = impedance(;
            z = (s::Complex) -> (R_B5+(1/(s*C_B5))),
            conductors = 3),

        # Load Bus 7
        LoadB7 =
        impedance(; z = (s::Complex) -> (R_B7+s*L_B7), conductors = 3),

        # Load Bus 8
        LoadB8 =
        impedance(; z = (s::Complex) -> (R_B8+s*L_B8), conductors = 3),

        # Load Bus 12
        #Referring load to 345 kV side
        LoadB12 = impedance(;
            z = (s::Complex)->(345/230)*(345/230)*(R_B12+s*L_B12),
            conductors = 3),

        # Load Bus 15
        LoadB15 =
        impedance(; z = (s::Complex) -> (R_B15+s*L_B15), conductors = 3),

        # Load Bus 16
        LoadB16 =
        impedance(; z = (s::Complex) -> (R_B16+s*L_B16), conductors = 3),

        # Load Bus 18
        LoadB18 =
        impedance(; z = (s::Complex) -> (R_B18+s*L_B18), conductors = 3),

        # Load Bus 20
        LoadB20 =
        impedance(; z = (s::Complex) -> (R_B20+s*L_B20), conductors = 3),

        # Load Bus 21
        LoadB21 =
        impedance(; z = (s::Complex) -> (R_B21+s*L_B21), conductors = 3),

        # Load Bus 23
        LoadB23 =
        impedance(; z = (s::Complex) -> (R_B23+s*L_B23), conductors = 3),

        # Load Bus 24
        LoadB24 = impedance(;
            z = (s::Complex) -> (R_B24+(1/(s*C_B24))),
            conductors = 3),

        # Load Bus 25
        LoadB25 =
        impedance(; z = (s::Complex) -> (R_B25+s*L_B25), conductors = 3),

        # Load Bus 26
        LoadB26 =
        impedance(; z = (s::Complex) -> (R_B26+s*L_B26), conductors = 3),

        # Load Bus 27
        LoadB27 =
        impedance(; z = (s::Complex) -> (R_B27+s*L_B27), conductors = 3),

        # Load Bus 28
        LoadB28 =
        impedance(; z = (s::Complex) -> (R_B28+s*L_B28), conductors = 3),

        # Load Bus 29
        LoadB29 =
        impedance(; z = (s::Complex) -> (R_B29+s*L_B29), conductors = 3),

        # Load Bus 31
        #Referring load to 345 kV side
        LoadB31 = impedance(;
            z = (s::Complex)->(345/22)*(345/22)*(R_B31+s*L_B31),
            conductors = 3),

        # Load Bus 39
        LoadB39 =
        impedance(; z = (s::Complex) -> (R_B39+s*L_B39), conductors = 3))
end

function ieee39bus_connections()
    return (
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB3, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB4a, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB4b, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB5, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB7, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB8, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB12, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB15, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB16, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB18, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB20, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB21, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB23, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB24, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB25, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB26, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB27, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB28, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB29, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB31, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:LoadB39, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:link_G30_Zg30_;
            ports = ((:G30, :ac), (:Zg30, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G31_Zg31_;
            ports = ((:G31, :ac), (:Zg31, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G32_Zg32_;
            ports = ((:G32, :ac), (:Zg32, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G33_Zg33_;
            ports = ((:G33, :ac), (:Zg33, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G34_Zg34_;
            ports = ((:G34, :ac), (:Zg34, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G35_Zg35_;
            ports = ((:G35, :ac), (:Zg35, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G36_Zg36_;
            ports = ((:G36, :ac), (:Zg36, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G37_Zg37_;
            ports = ((:G37, :ac), (:Zg37, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G38_Zg38_;
            ports = ((:G38, :ac), (:Zg38, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G39_Zg39_;
            ports = ((:G39, :ac), (:Zg39, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:link_G_DC_dummy_impedance_1; ports = ((:G_DC, :dc),)),
        NetworkBuilder.Bus(:link_G_DC_dummy_impedance_1;
            ports = ((:dummy_impedance, :side2),)),
        NetworkBuilder.Bus(:Bus1;
            ports = ((:T1_39, :side1), (:T1_2, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus2;
            ports = ((:T2_25, :side1), (:T1_2, :side2), (:T2_3, :side1), (:TR2_30,
                :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus3;
            ports = ((:T2_3, :side2), (:T3_18, :side1), (:T3_4, :side1), (:LoadB3,
                :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus4;
            ports = ((:T3_4, :side2), (:T4_5, :side1), (:T4_14, :side1), (:LoadB4a,
                :side1), (:LoadB4b, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus5;
            ports = ((:T4_5, :side2), (:T5_6, :side1), (:T5_8, :side1), (:LoadB5,
                :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus6;
            ports = ((:T5_6, :side2), (:T6_7, :side1), (:T6_11, :side1), (:TR6_31,
                :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus7;
            ports = ((:T6_7, :side2), (:T7_8, :side1), (:LoadB7, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus8;
            ports = ((:T7_8, :side2), (:T8_9, :side1), (:T5_8, :side2), (:LoadB8,
                :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus9;
            ports = ((:T8_9, :side2), (:T9_39, :side1), (:STATCOM, :ac)), domain = ACDQ),
        NetworkBuilder.Bus(:link_dummy_impedance_STATCOM_1;
            ports = ((:dummy_impedance, :side1), (:STATCOM, :dc))),
        NetworkBuilder.Bus(:Bus10;
            ports = ((:T10_11, :side1), (:T10_13, :side1), (:TR10_32, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus11;
            ports = ((:T10_11, :side2), (:T6_11, :side2), (:TR11_12, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus12;
            ports = ((:TR11_12, :side2), (:TR12_13, :side1), (:LoadB12, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus13;
            ports = ((:T10_13, :side2), (:T13_14, :side1), (:TR12_13, :side2)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus14;
            ports = ((:T14_15, :side1), (:T13_14, :side2), (:T4_14, :side2)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus15;
            ports = ((:T14_15, :side2), (:T15_16, :side1), (:LoadB15, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus16;
            ports = ((:T15_16, :side2), (:T16_17, :side1), (:T16_19, :side1), (:T16_21,
                :side1), (:T16_24, :side1), (:LoadB16, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus17;
            ports = ((:T16_17, :side2), (:T17_18, :side1), (:T17_27, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus18;
            ports = ((:T17_18, :side2), (:LoadB18, :side1), (:T3_18, :side2)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus19;
            ports = ((:T16_19, :side2), (:TR19_20, :side1), (:TR19_33, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus20;
            ports = ((:TR19_20, :side2), (:TR20_34, :side1), (:LoadB20, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus21;
            ports = ((:T16_21, :side2), (:LoadB21, :side1), (:T21_22, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus22;
            ports = ((:T21_22, :side2), (:T22_23, :side1), (:TR22_35, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus23;
            ports = ((:T22_23, :side2), (:LoadB23, :side1), (:T23_24, :side1),
                (:TR23_36, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus24;
            ports = ((:T16_24, :side2), (:T23_24, :side2), (:LoadB24, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus25;
            ports = ((:T2_25, :side2), (:LoadB25, :side1), (:T25_26, :side1), (:TR25_37,
                :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus26;
            ports = ((:T25_26, :side2), (:LoadB26, :side1), (:T26_27, :side1), (:T26_28,
                :side1), (:T26_29, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus27;
            ports = ((:T26_27, :side2), (:T17_27, :side2), (:LoadB27, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus28;
            ports = ((:T26_28, :side2), (:T28_29, :side1), (:LoadB28, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus29;
            ports = ((:T26_29, :side2), (:LoadB29, :side1), (:T28_29, :side2),
                (:TR29_38, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus30;
            ports = ((:TR2_30, :side2), (:Zg30, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus31;
            ports = ((:TR6_31, :side2), (:Zg31, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus32;
            ports = ((:TR10_32, :side2), (:Zg32, :side2), (:LoadB31, :side1)),
                domain = ACDQ),
        NetworkBuilder.Bus(:Bus33;
            ports = ((:TR19_33, :side2), (:Zg33, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus34;
            ports = ((:TR20_34, :side2), (:Zg34, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus35;
            ports = ((:TR22_35, :side2), (:Zg35, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus36;
            ports = ((:TR23_36, :side2), (:Zg36, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus37;
            ports = ((:TR25_37, :side2), (:Zg37, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus38;
            ports = ((:TR29_38, :side2), (:Zg38, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:Bus39;
            ports = ((:Zg39, :side2), (:T1_39, :side2), (:T9_39, :side2), (:LoadB39,
                :side1)), domain = ACDQ)
    )
end
