module ParityFixtures
using PowerImpedance
const PI = PowerImpedance
const NB = PI.NetworkBuilder
include("../pscad/fixtures.jl")

module IEEE39
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from test/NetworkBuilder_test.jl:70-216.
function calc_RLC(P, Q, V, component)
    P=P*1e6
    Q=Q*1e6
    V=V*1e3

    S=sqrt(P^2+Q^2)
    S=S*3

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

R_B3=calc_RLC(107.3333, 0.8, 345, "R")
L_B3=calc_RLC(107.3333, 0.8, 345, "L")

R_B4a=calc_RLC(166.6667, 61.3333, 345, "R")
L_B4=calc_RLC(166.6667, 61.3333, 345, "L")
R_B4b=calc_RLC(0, 100, 345, "R")
C_B4=calc_RLC(0, 100, 345, "C")

R_B5=calc_RLC(0, 200, 345, "R")
C_B5=calc_RLC(0, 200, 345, "C")

R_B7=calc_RLC(77.93333, 28.0, 345, "R")
L_B7=calc_RLC(77.93333, 28.0, 345, "L")

R_B8=calc_RLC(174.0, 58.6667, 345, "R")
L_B8=calc_RLC(174.0, 58.6667, 345, "L")

R_B12=calc_RLC(2.5, 29.3333, 230, "R")
L_B12=calc_RLC(2.5, 29.3333, 230, "L")

R_B15=calc_RLC(106.6667, 51.0, 345, "R")
L_B15=calc_RLC(106.6667, 51.0, 345, "L")

R_B16=calc_RLC(109.8, 10.7667, 345, "R")
L_B16=calc_RLC(109.8, 10.7667, 345, "L")

R_B18=calc_RLC(52.6667, 10.0, 345, "R")
L_B18=calc_RLC(52.6667, 10.0, 345, "L")

R_B20=calc_RLC(226.6667, 34.3333, 345, "R")
L_B20=calc_RLC(226.6667, 34.3333, 345, "L")

R_B21=calc_RLC(91.3333, 38.3333, 345, "R")
L_B21=calc_RLC(91.3333, 38.3333, 345, "L")

R_B23=calc_RLC(82.5, 28.2, 345, "R")
L_B23=calc_RLC(82.5, 28.2, 345, "L")

R_B24=calc_RLC(102.8667, 30.73333, 345, "R")
C_B24=calc_RLC(102.8667, 30.73333, 345, "C")

R_B25=calc_RLC(74.6667, 15.7333, 345, "R")
L_B25=calc_RLC(74.6667, 15.7333, 345, "L")

R_B26=calc_RLC(46.3333, 5.6667, 345, "R")
L_B26=calc_RLC(46.3333, 5.6667, 345, "L")

R_B27=calc_RLC(93.6667, 25.1667, 345, "R")
L_B27=calc_RLC(93.6667, 25.1667, 345, "L")

R_B28=calc_RLC(68.6667, 9.2, 345, "R")
L_B28=calc_RLC(68.6667, 9.2, 345, "L")

R_B29=calc_RLC(94.5, 8.9667, 345, "R")
L_B29=calc_RLC(94.5, 8.9667, 345, "L")

R_B31=calc_RLC(3.0667, 1.5333, 22, "R")
L_B31=calc_RLC(3.0667, 1.5333, 22, "L")

R_B39=calc_RLC(368, 83.3333, 345, "R")
L_B39=calc_RLC(368, 83.3333, 345, "L")

Vm1=345/sqrt(3)

Lb_345=(345e3)^2/(2*pi*50*1000e6)
Rb_345=(345e3)^2/(1000e6)

Vdc_ST=110
S_ST=269
Z_ST_base = 345^2/S_ST
Lf_ST = 0.08 * Z_ST_base / 2/pi/50
Rf_ST = 0.01 * 0.08 * Z_ST_base

Q_ST=-0.5
Vac_ref_ST=0.9

const IEEE39_INPUT_PINS = [:Bus9d, :Bus9q]
const IEEE39_OUTPUT_PINS = [:gndD, :gndQ]
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

    setpoint = PowerImpedance.Setpoint(
        Pac = 0.0,
        Qac = Q_ST*S_ST,
        θac = 0.0,
        Vac = Vm1*sqrt(2)*Vac_ref_ST,
        Pdc = 0.0,
        Vdc = Vdc_ST
    )
    return (;

        G30 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G31 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G32 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G33 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G34 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G35 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G36 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G37 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G38 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),
        G39 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm1*sqrt(2)),
            transformation = true),

        Zg30 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg31 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg32 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg33 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg34 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg35 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg36 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg37 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg38 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),
        Zg39 = impedance(
            z = (s::Complex) -> (0.191736 + s*0.0122063),
            pins = 3,
            transformation = true
        ),

        G_DC = dc_source(pins = 1, setpoint = Setpoint(Vdc = Vdc_ST)),

        STATCOM = PowerImpedance.tlc(
            elec = elec,
            meas = meas,
            sync = sync,
            outerActive = outerActive,
            outerReactive = outerReactive,
            innerVoltage = innerVoltage,
            innerCurrent = innerCurrent,
            mod = mod,
            setpoint = setpoint,
            limits = limits
        ),

        dummy_impedance = impedance(z = 1e4, pins = 1),

        TR2_30 = transformer(
            n = 345/345,
            Lₚ = (0.0181/2)*Lb_345,
            Lₛ = (0.0181/2)*Lb_345,
            pins = 3,
            transformation = true
        ),

        TR6_31 = transformer(
            n = 345/345,
            Lₚ = (0.025/2)*Lb_345,
            Lₛ = (0.025/2)*Lb_345,
            pins = 3,
            transformation = true
        ),

        TR10_32 = transformer(
            n = 345/345,
            Lₚ = (0.02/2)*Lb_345,
            Lₛ = (0.02/2)*Lb_345,
            pins = 3,
            transformation = true
        ),

        TR11_12 = transformer(
            n = 345/345,
            Lₚ = (0.0435/2)*Lb_345,
            Rₚ = (0.0016/2)*Rb_345,
            Lₛ = (0.0435/2)*Lb_345,
            Rₛ = (0.0016/2)*Rb_345,
            pins = 3,
            transformation = true
        ),

        TR12_13 = transformer(
            n = 345/345,
            Lₚ = (0.0435/2)*Lb_345,
            Rₚ = (0.0016/2)*Rb_345,
            Lₛ = (0.0435/2)*Lb_345,
            Rₛ = (0.0016/2)*Rb_345,
            pins = 3,
            transformation = true
        ),

        TR19_20 = transformer(
            n = 345/345,
            Lₚ = (0.0138 / 2)*Lb_345,
            Rₚ = (0.0007/2)*Rb_345,
            Lₛ = (0.0138 / 2)*Lb_345,
            Rₛ = (0.0007/2)*Rb_345,
            pins = 3,
            transformation = true
        ),

        TR19_33 = transformer(
            n = 345/345,
            Lₚ = (0.0142 / 2)*Lb_345,
            Rₚ = (0.0007/2)*Rb_345,
            Lₛ = (0.0142 / 2)*Lb_345,
            Rₛ = (0.0007/2)*Rb_345,
            pins = 3,
            transformation = true
        ),

        TR20_34 = transformer(
            n = 345/345,
            Lₚ = (0.0180 / 2)*Lb_345,
            Rₚ = (0.0009/2)*Rb_345,
            Lₛ = (0.0180 / 2)*Lb_345,
            Rₛ = (0.0009/2)*Rb_345,
            pins = 3,
            transformation = true
        ),

        TR22_35 = transformer(
            n = 345/345,
            Lₚ = (0.0143 / 2)*Lb_345,
            Lₛ = (0.0143 / 2)*Lb_345,
            pins = 3,
            transformation = true
        ),

        TR23_36 = transformer(
            n = 345/345,
            Lₚ = (0.0272 / 2)*Lb_345,
            Rₚ = (0.0005/2)*Rb_345,
            Lₛ = (0.0272 / 2)*Lb_345,
            Rₛ = (0.0005/2)*Rb_345,
            pins = 3,
            transformation = true
        ),

        TR25_37 = transformer(
            n = 345/345,
            Lₚ = (0.0232 / 2)*Lb_345,
            Rₚ = (0.0006/2)*Rb_345,
            Lₛ = (0.0232 / 2)*Lb_345,
            Rₛ = (0.0006/2)*Rb_345,
            pins = 3,
            transformation = true
        ),

        TR29_38 = transformer(
            n = 345/345,
            Lₚ = (0.0156 / 2)*Lb_345,
            Rₚ = (0.0008/2)*Rb_345,
            Lₛ = (0.0156 / 2)*Lb_345,
            Rₛ = (0.0008/2)*Rb_345,
            pins = 3,
            transformation = true
        ),

        T1_2 = overhead_line(length = 72.4730e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T1_39 = overhead_line(length = 44.0833e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T2_3 = overhead_line(length = 26.6263e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T2_25 = overhead_line(length = 15.1647e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T3_4 = overhead_line(length = 37.5590e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T3_18 = overhead_line(length = 23.4523e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T4_5 = overhead_line(length = 22.5707e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T4_14 = overhead_line(length = 22.7470e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T5_6 = overhead_line(length = 4.5847e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T5_8 = overhead_line(length = 19.7493e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T6_7 = overhead_line(length = 16.2227e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T6_11 = overhead_line(length = 14.4593e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T7_8 = overhead_line(length = 8.1113e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T8_9 = overhead_line(length = 64.009e3,
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
            earth_parameters = (1, 1, 100), transformation = true, connection = false),

        T9_39 = overhead_line(length = 44.0833e3,
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
            earth_parameters = (1, 1, 100), transformation = true, connection = true),

        T10_11 = overhead_line(length = 7.5823e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T10_13 = overhead_line(length = 7.5823e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T13_14 = overhead_line(length = 17.8097e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T14_15 = overhead_line(length = 38.2643e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T15_16 = overhead_line(length = 16.5753e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T16_17 = overhead_line(length = 15.6937e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T16_19 = overhead_line(length = 34.3850e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T16_21 = overhead_line(length = 23.8050e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T16_24 = overhead_line(length = 10.4037e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T17_18 = overhead_line(length = 14.4593e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T17_27 = overhead_line(length = 30.5057e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T21_22 = overhead_line(length = 24.6867e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T22_23 = overhead_line(length = 16.9280e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T23_24 = overhead_line(length = 61.7167e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T25_26 = overhead_line(length = 56.95573e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T26_27 = overhead_line(length = 25.9210e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T26_28 = overhead_line(length = 83.5820e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T26_29 = overhead_line(length = 110.2083e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        T28_29 = overhead_line(length = 26.6263e3,
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
            earth_parameters = (1, 1, 100), transformation = true),

        LoadB3 =
        impedance(z = (s::Complex) -> (R_B3+s*L_B3), pins = 3, transformation = true),

        LoadB4a =
        impedance(z = (s::Complex) -> (R_B4a+s*L_B4), pins = 3, transformation = true),
        LoadB4b = impedance(
            z = (s::Complex) -> (R_B4b+(1/(s*C_B4))),
            pins = 3,
            transformation = true
        ),

        LoadB5 = impedance(
            z = (s::Complex) -> (R_B5+(1/(s*C_B5))),
            pins = 3,
            transformation = true
        ),

        LoadB7 =
        impedance(z = (s::Complex) -> (R_B7+s*L_B7), pins = 3, transformation = true),

        LoadB8 =
        impedance(z = (s::Complex) -> (R_B8+s*L_B8), pins = 3, transformation = true),

        LoadB12 = impedance(
            z = (s::Complex)->(345/230)*(345/230)*(R_B12+s*L_B12),
            pins = 3,
            transformation = true
        ),

        LoadB15 =
        impedance(z = (s::Complex) -> (R_B15+s*L_B15), pins = 3, transformation = true),

        LoadB16 =
        impedance(z = (s::Complex) -> (R_B16+s*L_B16), pins = 3, transformation = true),

        LoadB18 =
        impedance(z = (s::Complex) -> (R_B18+s*L_B18), pins = 3, transformation = true),

        LoadB20 =
        impedance(z = (s::Complex) -> (R_B20+s*L_B20), pins = 3, transformation = true),

        LoadB21 =
        impedance(z = (s::Complex) -> (R_B21+s*L_B21), pins = 3, transformation = true),

        LoadB23 =
        impedance(z = (s::Complex) -> (R_B23+s*L_B23), pins = 3, transformation = true),

        LoadB24 = impedance(
            z = (s::Complex) -> (R_B24+(1/(s*C_B24))),
            pins = 3,
            transformation = true
        ),

        LoadB25 =
        impedance(z = (s::Complex) -> (R_B25+s*L_B25), pins = 3, transformation = true),

        LoadB26 =
        impedance(z = (s::Complex) -> (R_B26+s*L_B26), pins = 3, transformation = true),

        LoadB27 =
        impedance(z = (s::Complex) -> (R_B27+s*L_B27), pins = 3, transformation = true),

        LoadB28 =
        impedance(z = (s::Complex) -> (R_B28+s*L_B28), pins = 3, transformation = true),

        LoadB29 =
        impedance(z = (s::Complex) -> (R_B29+s*L_B29), pins = 3, transformation = true),

        LoadB31 = impedance(
            z = (s::Complex)->(345/22)*(345/22)*(R_B31+s*L_B31),
            pins = 3,
            transformation = true
        ),

        LoadB39 =
        impedance(z = (s::Complex) -> (R_B39+s*L_B39), pins = 3, transformation = true))
end

function ieee39bus_connections()
    return (
        (node = :gndD, element = :LoadB3, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB3, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB4a, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB4a, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB4b, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB4b, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB5, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB5, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB7, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB7, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB8, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB8, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB12, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB12, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB15, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB15, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB16, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB16, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB18, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB18, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB20, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB20, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB21, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB21, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB23, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB23, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB24, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB24, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB25, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB25, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB26, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB26, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB27, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB27, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB28, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB28, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB29, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB29, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB31, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB31, side = 2, terminal = 2),
        (node = :gndD, element = :LoadB39, side = 2, terminal = 1),
        (node = :gndQ, element = :LoadB39, side = 2, terminal = 2),
        (node = :link_G30_Zg30_1, element = :G30, side = 1, terminal = 1),
        (node = :link_G30_Zg30_1, element = :Zg30, side = 1, terminal = 1),
        (node = :link_G30_Zg30_2, element = :G30, side = 1, terminal = 2),
        (node = :link_G30_Zg30_2, element = :Zg30, side = 1, terminal = 2),
        (node = :link_G31_Zg31_1, element = :G31, side = 1, terminal = 1),
        (node = :link_G31_Zg31_1, element = :Zg31, side = 1, terminal = 1),
        (node = :link_G31_Zg31_2, element = :G31, side = 1, terminal = 2),
        (node = :link_G31_Zg31_2, element = :Zg31, side = 1, terminal = 2),
        (node = :link_G32_Zg32_1, element = :G32, side = 1, terminal = 1),
        (node = :link_G32_Zg32_1, element = :Zg32, side = 1, terminal = 1),
        (node = :link_G32_Zg32_2, element = :G32, side = 1, terminal = 2),
        (node = :link_G32_Zg32_2, element = :Zg32, side = 1, terminal = 2),
        (node = :link_G33_Zg33_1, element = :G33, side = 1, terminal = 1),
        (node = :link_G33_Zg33_1, element = :Zg33, side = 1, terminal = 1),
        (node = :link_G33_Zg33_2, element = :G33, side = 1, terminal = 2),
        (node = :link_G33_Zg33_2, element = :Zg33, side = 1, terminal = 2),
        (node = :link_G34_Zg34_1, element = :G34, side = 1, terminal = 1),
        (node = :link_G34_Zg34_1, element = :Zg34, side = 1, terminal = 1),
        (node = :link_G34_Zg34_2, element = :G34, side = 1, terminal = 2),
        (node = :link_G34_Zg34_2, element = :Zg34, side = 1, terminal = 2),
        (node = :link_G35_Zg35_1, element = :G35, side = 1, terminal = 1),
        (node = :link_G35_Zg35_1, element = :Zg35, side = 1, terminal = 1),
        (node = :link_G35_Zg35_2, element = :G35, side = 1, terminal = 2),
        (node = :link_G35_Zg35_2, element = :Zg35, side = 1, terminal = 2),
        (node = :link_G36_Zg36_1, element = :G36, side = 1, terminal = 1),
        (node = :link_G36_Zg36_1, element = :Zg36, side = 1, terminal = 1),
        (node = :link_G36_Zg36_2, element = :G36, side = 1, terminal = 2),
        (node = :link_G36_Zg36_2, element = :Zg36, side = 1, terminal = 2),
        (node = :link_G37_Zg37_1, element = :G37, side = 1, terminal = 1),
        (node = :link_G37_Zg37_1, element = :Zg37, side = 1, terminal = 1),
        (node = :link_G37_Zg37_2, element = :G37, side = 1, terminal = 2),
        (node = :link_G37_Zg37_2, element = :Zg37, side = 1, terminal = 2),
        (node = :link_G38_Zg38_1, element = :G38, side = 1, terminal = 1),
        (node = :link_G38_Zg38_1, element = :Zg38, side = 1, terminal = 1),
        (node = :link_G38_Zg38_2, element = :G38, side = 1, terminal = 2),
        (node = :link_G38_Zg38_2, element = :Zg38, side = 1, terminal = 2),
        (node = :link_G39_Zg39_1, element = :G39, side = 1, terminal = 1),
        (node = :link_G39_Zg39_1, element = :Zg39, side = 1, terminal = 1),
        (node = :link_G39_Zg39_2, element = :G39, side = 1, terminal = 2),
        (node = :link_G39_Zg39_2, element = :Zg39, side = 1, terminal = 2),
        (node = :link_G_DC_dummy_impedance_1, element = :G_DC, side = 1, terminal = 1),
        (node = :link_G_DC_dummy_impedance_1,
            element = :dummy_impedance, side = 2, terminal = 1),
        (node = :Bus1d, element = :T1_39, side = 1, terminal = 1),
        (node = :Bus1d, element = :T1_2, side = 1, terminal = 1),
        (node = :Bus1q, element = :T1_39, side = 1, terminal = 2),
        (node = :Bus1q, element = :T1_2, side = 1, terminal = 2),
        (node = :Bus2d, element = :T2_25, side = 1, terminal = 1),
        (node = :Bus2d, element = :T1_2, side = 2, terminal = 1),
        (node = :Bus2d, element = :T2_3, side = 1, terminal = 1),
        (node = :Bus2d, element = :TR2_30, side = 1, terminal = 1),
        (node = :Bus2q, element = :T2_25, side = 1, terminal = 2),
        (node = :Bus2q, element = :T1_2, side = 2, terminal = 2),
        (node = :Bus2q, element = :T2_3, side = 1, terminal = 2),
        (node = :Bus2q, element = :TR2_30, side = 1, terminal = 2),
        (node = :Bus3d, element = :T2_3, side = 2, terminal = 1),
        (node = :Bus3d, element = :T3_18, side = 1, terminal = 1),
        (node = :Bus3d, element = :T3_4, side = 1, terminal = 1),
        (node = :Bus3d, element = :LoadB3, side = 1, terminal = 1),
        (node = :Bus3q, element = :T2_3, side = 2, terminal = 2),
        (node = :Bus3q, element = :T3_18, side = 1, terminal = 2),
        (node = :Bus3q, element = :T3_4, side = 1, terminal = 2),
        (node = :Bus3q, element = :LoadB3, side = 1, terminal = 2),
        (node = :Bus4d, element = :T3_4, side = 2, terminal = 1),
        (node = :Bus4d, element = :T4_5, side = 1, terminal = 1),
        (node = :Bus4d, element = :T4_14, side = 1, terminal = 1),
        (node = :Bus4d, element = :LoadB4a, side = 1, terminal = 1),
        (node = :Bus4d, element = :LoadB4b, side = 1, terminal = 1),
        (node = :Bus4q, element = :T3_4, side = 2, terminal = 2),
        (node = :Bus4q, element = :T4_5, side = 1, terminal = 2),
        (node = :Bus4q, element = :T4_14, side = 1, terminal = 2),
        (node = :Bus4q, element = :LoadB4a, side = 1, terminal = 2),
        (node = :Bus4q, element = :LoadB4b, side = 1, terminal = 2),
        (node = :Bus5d, element = :T4_5, side = 2, terminal = 1),
        (node = :Bus5d, element = :T5_6, side = 1, terminal = 1),
        (node = :Bus5d, element = :T5_8, side = 1, terminal = 1),
        (node = :Bus5d, element = :LoadB5, side = 1, terminal = 1),
        (node = :Bus5q, element = :T4_5, side = 2, terminal = 2),
        (node = :Bus5q, element = :T5_6, side = 1, terminal = 2),
        (node = :Bus5q, element = :T5_8, side = 1, terminal = 2),
        (node = :Bus5q, element = :LoadB5, side = 1, terminal = 2),
        (node = :Bus6d, element = :T5_6, side = 2, terminal = 1),
        (node = :Bus6d, element = :T6_7, side = 1, terminal = 1),
        (node = :Bus6d, element = :T6_11, side = 1, terminal = 1),
        (node = :Bus6d, element = :TR6_31, side = 1, terminal = 1),
        (node = :Bus6q, element = :T5_6, side = 2, terminal = 2),
        (node = :Bus6q, element = :T6_7, side = 1, terminal = 2),
        (node = :Bus6q, element = :T6_11, side = 1, terminal = 2),
        (node = :Bus6q, element = :TR6_31, side = 1, terminal = 2),
        (node = :Bus7d, element = :T6_7, side = 2, terminal = 1),
        (node = :Bus7d, element = :T7_8, side = 1, terminal = 1),
        (node = :Bus7d, element = :LoadB7, side = 1, terminal = 1),
        (node = :Bus7q, element = :T6_7, side = 2, terminal = 2),
        (node = :Bus7q, element = :T7_8, side = 1, terminal = 2),
        (node = :Bus7q, element = :LoadB7, side = 1, terminal = 2),
        (node = :Bus8d, element = :T7_8, side = 2, terminal = 1),
        (node = :Bus8d, element = :T8_9, side = 1, terminal = 1),
        (node = :Bus8d, element = :T5_8, side = 2, terminal = 1),
        (node = :Bus8d, element = :LoadB8, side = 1, terminal = 1),
        (node = :Bus8q, element = :T7_8, side = 2, terminal = 2),
        (node = :Bus8q, element = :T8_9, side = 1, terminal = 2),
        (node = :Bus8q, element = :T5_8, side = 2, terminal = 2),
        (node = :Bus8q, element = :LoadB8, side = 1, terminal = 2),
        (node = :Bus9d, element = :T8_9, side = 2, terminal = 1),
        (node = :Bus9d, element = :T9_39, side = 1, terminal = 1),
        (node = :Bus9d, element = :STATCOM, side = 2, terminal = 1),
        (node = :Bus9q, element = :T8_9, side = 2, terminal = 2),
        (node = :Bus9q, element = :T9_39, side = 1, terminal = 2),
        (node = :Bus9q, element = :STATCOM, side = 2, terminal = 2),
        (node = :link_dummy_impedance_STATCOM_1,
            element = :dummy_impedance, side = 1, terminal = 1),
        (node = :link_dummy_impedance_STATCOM_1,
            element = :STATCOM, side = 1, terminal = 1),
        (node = :Bus10d, element = :T10_11, side = 1, terminal = 1),
        (node = :Bus10d, element = :T10_13, side = 1, terminal = 1),
        (node = :Bus10d, element = :TR10_32, side = 1, terminal = 1),
        (node = :Bus10q, element = :T10_11, side = 1, terminal = 2),
        (node = :Bus10q, element = :T10_13, side = 1, terminal = 2),
        (node = :Bus10q, element = :TR10_32, side = 1, terminal = 2),
        (node = :Bus11d, element = :T10_11, side = 2, terminal = 1),
        (node = :Bus11d, element = :T6_11, side = 2, terminal = 1),
        (node = :Bus11d, element = :TR11_12, side = 1, terminal = 1),
        (node = :Bus11q, element = :T10_11, side = 2, terminal = 2),
        (node = :Bus11q, element = :T6_11, side = 2, terminal = 2),
        (node = :Bus11q, element = :TR11_12, side = 1, terminal = 2),
        (node = :Bus12d, element = :TR11_12, side = 2, terminal = 1),
        (node = :Bus12d, element = :TR12_13, side = 1, terminal = 1),
        (node = :Bus12d, element = :LoadB12, side = 1, terminal = 1),
        (node = :Bus12q, element = :TR11_12, side = 2, terminal = 2),
        (node = :Bus12q, element = :TR12_13, side = 1, terminal = 2),
        (node = :Bus12q, element = :LoadB12, side = 1, terminal = 2),
        (node = :Bus13d, element = :T10_13, side = 2, terminal = 1),
        (node = :Bus13d, element = :T13_14, side = 1, terminal = 1),
        (node = :Bus13d, element = :TR12_13, side = 2, terminal = 1),
        (node = :Bus13q, element = :T10_13, side = 2, terminal = 2),
        (node = :Bus13q, element = :T13_14, side = 1, terminal = 2),
        (node = :Bus13q, element = :TR12_13, side = 2, terminal = 2),
        (node = :Bus14d, element = :T14_15, side = 1, terminal = 1),
        (node = :Bus14d, element = :T13_14, side = 2, terminal = 1),
        (node = :Bus14d, element = :T4_14, side = 2, terminal = 1),
        (node = :Bus14q, element = :T14_15, side = 1, terminal = 2),
        (node = :Bus14q, element = :T13_14, side = 2, terminal = 2),
        (node = :Bus14q, element = :T4_14, side = 2, terminal = 2),
        (node = :Bus15d, element = :T14_15, side = 2, terminal = 1),
        (node = :Bus15d, element = :T15_16, side = 1, terminal = 1),
        (node = :Bus15d, element = :LoadB15, side = 1, terminal = 1),
        (node = :Bus15q, element = :T14_15, side = 2, terminal = 2),
        (node = :Bus15q, element = :T15_16, side = 1, terminal = 2),
        (node = :Bus15q, element = :LoadB15, side = 1, terminal = 2),
        (node = :Bus16d, element = :T15_16, side = 2, terminal = 1),
        (node = :Bus16d, element = :T16_17, side = 1, terminal = 1),
        (node = :Bus16d, element = :T16_19, side = 1, terminal = 1),
        (node = :Bus16d, element = :T16_21, side = 1, terminal = 1),
        (node = :Bus16d, element = :T16_24, side = 1, terminal = 1),
        (node = :Bus16d, element = :LoadB16, side = 1, terminal = 1),
        (node = :Bus16q, element = :T15_16, side = 2, terminal = 2),
        (node = :Bus16q, element = :T16_17, side = 1, terminal = 2),
        (node = :Bus16q, element = :T16_19, side = 1, terminal = 2),
        (node = :Bus16q, element = :T16_21, side = 1, terminal = 2),
        (node = :Bus16q, element = :T16_24, side = 1, terminal = 2),
        (node = :Bus16q, element = :LoadB16, side = 1, terminal = 2),
        (node = :Bus17d, element = :T16_17, side = 2, terminal = 1),
        (node = :Bus17d, element = :T17_18, side = 1, terminal = 1),
        (node = :Bus17d, element = :T17_27, side = 1, terminal = 1),
        (node = :Bus17q, element = :T16_17, side = 2, terminal = 2),
        (node = :Bus17q, element = :T17_18, side = 1, terminal = 2),
        (node = :Bus17q, element = :T17_27, side = 1, terminal = 2),
        (node = :Bus18d, element = :T17_18, side = 2, terminal = 1),
        (node = :Bus18d, element = :LoadB18, side = 1, terminal = 1),
        (node = :Bus18d, element = :T3_18, side = 2, terminal = 1),
        (node = :Bus18q, element = :T17_18, side = 2, terminal = 2),
        (node = :Bus18q, element = :LoadB18, side = 1, terminal = 2),
        (node = :Bus18q, element = :T3_18, side = 2, terminal = 2),
        (node = :Bus19d, element = :T16_19, side = 2, terminal = 1),
        (node = :Bus19d, element = :TR19_20, side = 1, terminal = 1),
        (node = :Bus19d, element = :TR19_33, side = 1, terminal = 1),
        (node = :Bus19q, element = :T16_19, side = 2, terminal = 2),
        (node = :Bus19q, element = :TR19_20, side = 1, terminal = 2),
        (node = :Bus19q, element = :TR19_33, side = 1, terminal = 2),
        (node = :Bus20d, element = :TR19_20, side = 2, terminal = 1),
        (node = :Bus20d, element = :TR20_34, side = 1, terminal = 1),
        (node = :Bus20d, element = :LoadB20, side = 1, terminal = 1),
        (node = :Bus20q, element = :TR19_20, side = 2, terminal = 2),
        (node = :Bus20q, element = :TR20_34, side = 1, terminal = 2),
        (node = :Bus20q, element = :LoadB20, side = 1, terminal = 2),
        (node = :Bus21d, element = :T16_21, side = 2, terminal = 1),
        (node = :Bus21d, element = :LoadB21, side = 1, terminal = 1),
        (node = :Bus21d, element = :T21_22, side = 1, terminal = 1),
        (node = :Bus21q, element = :T16_21, side = 2, terminal = 2),
        (node = :Bus21q, element = :LoadB21, side = 1, terminal = 2),
        (node = :Bus21q, element = :T21_22, side = 1, terminal = 2),
        (node = :Bus22d, element = :T21_22, side = 2, terminal = 1),
        (node = :Bus22d, element = :T22_23, side = 1, terminal = 1),
        (node = :Bus22d, element = :TR22_35, side = 1, terminal = 1),
        (node = :Bus22q, element = :T21_22, side = 2, terminal = 2),
        (node = :Bus22q, element = :T22_23, side = 1, terminal = 2),
        (node = :Bus22q, element = :TR22_35, side = 1, terminal = 2),
        (node = :Bus23d, element = :T22_23, side = 2, terminal = 1),
        (node = :Bus23d, element = :LoadB23, side = 1, terminal = 1),
        (node = :Bus23d, element = :T23_24, side = 1, terminal = 1),
        (node = :Bus23d, element = :TR23_36, side = 1, terminal = 1),
        (node = :Bus23q, element = :T22_23, side = 2, terminal = 2),
        (node = :Bus23q, element = :LoadB23, side = 1, terminal = 2),
        (node = :Bus23q, element = :T23_24, side = 1, terminal = 2),
        (node = :Bus23q, element = :TR23_36, side = 1, terminal = 2),
        (node = :Bus24d, element = :T16_24, side = 2, terminal = 1),
        (node = :Bus24d, element = :T23_24, side = 2, terminal = 1),
        (node = :Bus24d, element = :LoadB24, side = 1, terminal = 1),
        (node = :Bus24q, element = :T16_24, side = 2, terminal = 2),
        (node = :Bus24q, element = :T23_24, side = 2, terminal = 2),
        (node = :Bus24q, element = :LoadB24, side = 1, terminal = 2),
        (node = :Bus25d, element = :T2_25, side = 2, terminal = 1),
        (node = :Bus25d, element = :LoadB25, side = 1, terminal = 1),
        (node = :Bus25d, element = :T25_26, side = 1, terminal = 1),
        (node = :Bus25d, element = :TR25_37, side = 1, terminal = 1),
        (node = :Bus25q, element = :T2_25, side = 2, terminal = 2),
        (node = :Bus25q, element = :LoadB25, side = 1, terminal = 2),
        (node = :Bus25q, element = :T25_26, side = 1, terminal = 2),
        (node = :Bus25q, element = :TR25_37, side = 1, terminal = 2),
        (node = :Bus26d, element = :T25_26, side = 2, terminal = 1),
        (node = :Bus26d, element = :LoadB26, side = 1, terminal = 1),
        (node = :Bus26d, element = :T26_27, side = 1, terminal = 1),
        (node = :Bus26d, element = :T26_28, side = 1, terminal = 1),
        (node = :Bus26d, element = :T26_29, side = 1, terminal = 1),
        (node = :Bus26q, element = :T25_26, side = 2, terminal = 2),
        (node = :Bus26q, element = :LoadB26, side = 1, terminal = 2),
        (node = :Bus26q, element = :T26_27, side = 1, terminal = 2),
        (node = :Bus26q, element = :T26_28, side = 1, terminal = 2),
        (node = :Bus26q, element = :T26_29, side = 1, terminal = 2),
        (node = :Bus27d, element = :T26_27, side = 2, terminal = 1),
        (node = :Bus27d, element = :T17_27, side = 2, terminal = 1),
        (node = :Bus27d, element = :LoadB27, side = 1, terminal = 1),
        (node = :Bus27q, element = :T26_27, side = 2, terminal = 2),
        (node = :Bus27q, element = :T17_27, side = 2, terminal = 2),
        (node = :Bus27q, element = :LoadB27, side = 1, terminal = 2),
        (node = :Bus28d, element = :T26_28, side = 2, terminal = 1),
        (node = :Bus28d, element = :T28_29, side = 1, terminal = 1),
        (node = :Bus28d, element = :LoadB28, side = 1, terminal = 1),
        (node = :Bus28q, element = :T26_28, side = 2, terminal = 2),
        (node = :Bus28q, element = :T28_29, side = 1, terminal = 2),
        (node = :Bus28q, element = :LoadB28, side = 1, terminal = 2),
        (node = :Bus29d, element = :T26_29, side = 2, terminal = 1),
        (node = :Bus29d, element = :LoadB29, side = 1, terminal = 1),
        (node = :Bus29d, element = :T28_29, side = 2, terminal = 1),
        (node = :Bus29d, element = :TR29_38, side = 1, terminal = 1),
        (node = :Bus29q, element = :T26_29, side = 2, terminal = 2),
        (node = :Bus29q, element = :LoadB29, side = 1, terminal = 2),
        (node = :Bus29q, element = :T28_29, side = 2, terminal = 2),
        (node = :Bus29q, element = :TR29_38, side = 1, terminal = 2),
        (node = :Bus30d, element = :TR2_30, side = 2, terminal = 1),
        (node = :Bus30d, element = :Zg30, side = 2, terminal = 1),
        (node = :Bus30q, element = :TR2_30, side = 2, terminal = 2),
        (node = :Bus30q, element = :Zg30, side = 2, terminal = 2),
        (node = :Bus31d, element = :TR6_31, side = 2, terminal = 1),
        (node = :Bus31d, element = :Zg31, side = 2, terminal = 1),
        (node = :Bus31q, element = :TR6_31, side = 2, terminal = 2),
        (node = :Bus31q, element = :Zg31, side = 2, terminal = 2),
        (node = :Bus32d, element = :TR10_32, side = 2, terminal = 1),
        (node = :Bus32d, element = :Zg32, side = 2, terminal = 1),
        (node = :Bus32d, element = :LoadB31, side = 1, terminal = 1),
        (node = :Bus32q, element = :TR10_32, side = 2, terminal = 2),
        (node = :Bus32q, element = :Zg32, side = 2, terminal = 2),
        (node = :Bus32q, element = :LoadB31, side = 1, terminal = 2),
        (node = :Bus33d, element = :TR19_33, side = 2, terminal = 1),
        (node = :Bus33d, element = :Zg33, side = 2, terminal = 1),
        (node = :Bus33q, element = :TR19_33, side = 2, terminal = 2),
        (node = :Bus33q, element = :Zg33, side = 2, terminal = 2),
        (node = :Bus34d, element = :TR20_34, side = 2, terminal = 1),
        (node = :Bus34d, element = :Zg34, side = 2, terminal = 1),
        (node = :Bus34q, element = :TR20_34, side = 2, terminal = 2),
        (node = :Bus34q, element = :Zg34, side = 2, terminal = 2),
        (node = :Bus35d, element = :TR22_35, side = 2, terminal = 1),
        (node = :Bus35d, element = :Zg35, side = 2, terminal = 1),
        (node = :Bus35q, element = :TR22_35, side = 2, terminal = 2),
        (node = :Bus35q, element = :Zg35, side = 2, terminal = 2),
        (node = :Bus36d, element = :TR23_36, side = 2, terminal = 1),
        (node = :Bus36d, element = :Zg36, side = 2, terminal = 1),
        (node = :Bus36q, element = :TR23_36, side = 2, terminal = 2),
        (node = :Bus36q, element = :Zg36, side = 2, terminal = 2),
        (node = :Bus37d, element = :TR25_37, side = 2, terminal = 1),
        (node = :Bus37d, element = :Zg37, side = 2, terminal = 1),
        (node = :Bus37q, element = :TR25_37, side = 2, terminal = 2),
        (node = :Bus37q, element = :Zg37, side = 2, terminal = 2),
        (node = :Bus38d, element = :TR29_38, side = 2, terminal = 1),
        (node = :Bus38d, element = :Zg38, side = 2, terminal = 1),
        (node = :Bus38q, element = :TR29_38, side = 2, terminal = 2),
        (node = :Bus38q, element = :Zg38, side = 2, terminal = 2),
        (node = :Bus39d, element = :Zg39, side = 2, terminal = 1),
        (node = :Bus39d, element = :T1_39, side = 2, terminal = 1),
        (node = :Bus39d, element = :T9_39, side = 2, terminal = 1),
        (node = :Bus39d, element = :LoadB39, side = 1, terminal = 1),
        (node = :Bus39q, element = :Zg39, side = 2, terminal = 2),
        (node = :Bus39q, element = :T1_39, side = 2, terminal = 2),
        (node = :Bus39q, element = :T9_39, side = 2, terminal = 2),
        (node = :Bus39q, element = :LoadB39, side = 1, terminal = 2)
    )
end

function build()
    return NetworkBuilder.define(ieee39bus_elements(), ieee39bus_connections();
        options = (; voltageBase = Vm1,
            power_flow = (; is_bounded = (; bus_voltage = true))))
end

end

module Droop
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from test/dc_voltage_support_test.jl:9-47.

function converter(kind; K = 5.0, voltage = 672.0, dcbase = 640.0)
    point = Setpoint(Pac = 50.0, Qac = 25.0, Vac = 380sqrt(2/3), Vdc = voltage, Pdc = 50.0)
    limits = PI.Limits(P_min = -100.0, P_max = 100.0, Q_min = -50.0, Q_max = 50.0)
    outer = OuterActivePowerControl(pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0),
        support = DCVoltageSupportLag(; K, ωc = 2.0))
    reactive = OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0))
    sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.085, Ki = 32.0))
    occ = InnerCurrentPIControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 43.0))
    return kind === :mmc ?
           mmc(
        elec = ElectricalMMC(Sbase = 500.0, vDC_base = dcbase),
        delta_control = ΔdqControlGFL(outer_active = outer,
            outer_reactive = reactive, occ = occ),
        sigma_control = ΣdqzControlTEC(
            tec = TotalEnergyControl(pi_control = PIControl(Kp = 1.4, Ki = 30.0)),
            zscc = ZeroSequenceCurrentControl(PIControl(Kp = 0.1, Ki = 43.0)),
            ccsc = CirculatingCurrentSuppressionControl(PIControl(Kp = 0.1, Ki = 43.0))),
        sync = sync, setpoint = point, limits = limits) :
           tlc(
        elec = ElectricalTLC(Sbase = 500.0, vACbase_LL_RMS = 380.0, vDCbase = dcbase),
        outerActive = outer, outerReactive = reactive, innerCurrent = occ,
        sync = sync, setpoint = point, limits = limits)
end

function droop_network(kind; K = 5.0)
    elements = (;
        DUT = converter(kind; K),
        G_AC = ac_source(pins = 3, transformation = true,
            setpoint = Setpoint(Vac = 380sqrt(2/3))),
        G_DC = dc_source(setpoint = Setpoint(Vdc = 680.0)),
        line = impedance(z = s -> 0.5, pins = 1))
    rows = [(node = Symbol("AC" * axis), element, side, terminal)
            for (element, side) in ((:DUT, 2), (:G_AC, 1))
            for (terminal, axis) in enumerate(("d", "q"))]
    append!(rows,
        [
            (node = :DC1, element = :DUT, side = 1, terminal = 1),
            (node = :DC1, element = :line, side = 1, terminal = 1),
            (node = :DC2, element = :line, side = 2, terminal = 1),
            (node = :DC2, element = :G_DC, side = 1, terminal = 1)])
    return NB.define(elements, rows; options = (; voltageBase = 380/sqrt(3)))
end
const PI = PowerImpedance
const NB = PI.NetworkBuilder

end

module P2PAlt
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from examples/P2P_HVDC_ALT.jl:12-171.
transmissionVoltage = 380 / sqrt(3)
pHVDC1 = 100
qC1 = 100
qC2 = 100

rho = 100.0
L = 100e3

connections = (
    (node = :B3d, element = :tl1, side = 2, terminal = 1),
    (node = :B3d, element = :c1, side = 2, terminal = 1),
    (node = :B3q, element = :tl1, side = 2, terminal = 2),
    (node = :B3q, element = :c1, side = 2, terminal = 2),
    (node = :B2d, element = :g4, side = 1, terminal = 1),
    (node = :B2d, element = :tl1, side = 1, terminal = 1),
    (node = :B2q, element = :g4, side = 1, terminal = 2),
    (node = :B2q, element = :tl1, side = 1, terminal = 2),
    (node = :B4, element = :ugc, side = 1, terminal = 1),
    (node = :B4, element = :c1, side = 1, terminal = 1),
    (node = :BX, element = :ugc, side = 2, terminal = 1),
    (node = :BX, element = :ohl, side = 1, terminal = 1),
    (node = :B5, element = :ohl, side = 2, terminal = 1),
    (node = :B5, element = :c2, side = 1, terminal = 1),
    (node = :B6d, element = :tl78, side = 1, terminal = 1),
    (node = :B6d, element = :c2, side = 2, terminal = 1),
    (node = :B6q, element = :tl78, side = 1, terminal = 2),
    (node = :B6q, element = :c2, side = 2, terminal = 2),
    (node = :B7d, element = :g1, side = 1, terminal = 1),
    (node = :B7d, element = :tl78, side = 2, terminal = 1),
    (node = :B7q, element = :g1, side = 1, terminal = 2),
    (node = :B7q, element = :tl78, side = 2, terminal = 2)
)

builder_options = (;
    voltageBase = transmissionVoltage,
    power_flow = (;
        is_bounded = (;
        bus_voltage = true,
    ),
    )
)

function ohl_to_ugc(x)
    share = clamp(x, 1e-3, 1 - 1e-3)
    ohl_model = overhead_line(
        length = L * (1 - share),
        conductors = Conductors(
            organization = :flat,
            nᵇ = 2,
            nˢᵇ = 1,
            Rᵈᶜ = 0.0266, rᶜ = 44.8e-3 / 2,
            yᵇᶜ = 18.0, Δyᵇᶜ = 0.0, Δxᵇᶜ = 7.3, Δ̃xᵇᶜ = 0.0,
            dˢᵇ = 0.0,
            dˢᵃᵍ = 6.0
        ),
        groundwires = Groundwires(
            nᵍ = 2,
            Rᵍᵈᶜ = 0.92, rᵍ = 0.0062,
            Δxᵍ = 7.3, Δyᵍ = 7.0, dᵍˢᵃᵍ = 6.0
        ), earth_parameters = (1, 1, rho),
        transformation = true
    )

    ugc_model = cable(
        length = L * share,
        positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
        I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
        C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
        I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
        C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
        I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
        earth_parameters = (1, 1, rho),
        transformation = true
    )

    return (;
        g1 = ac_source(
            setpoint = Setpoint(Vac = transmissionVoltage*sqrt(2),
                Pac = pHVDC1),
            P_min = -2000,
            P_max = 2000,
            Q_max = 1000,
            Q_min = -1000,
            pins = 3,
            transformation = true
        ),

        c1 = only(mmc(Grid; Vᵈᶜ = 640, vDCbase = 640, Vₘ = transmissionVoltage,
            P_max = 1500, P_min = -1500, P = -pHVDC1, Q = qC1, Q_max = 500,
            Q_min = -500,
            occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
            ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
            pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
            q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
            dc = PI_control(Kₚ = 6, Kᵢ = 15), timeDelay = 200e-6, padeOrderNum = 5,
            padeOrderDen = 5
        )),

        c2 = only(mmc(Grid; Vᵈᶜ = 640, vDCbase = 640, Vₘ = transmissionVoltage,
            P_max = 1000, P_min = -1000, P = pHVDC1, Q = qC2, Q_max = 1000,
            Q_min = -1000,
            vACbase_LL_RMS = 333, turnsRatio = 333 / 380, Lᵣ = 0.0461, Rᵣ = 0.4103,
            Lₐᵣₘ = 30e-3,
            occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
            ccc = PI_control(Kₚ = 1 * 0.1048, Kᵢ = 1 * 48.1914),
            pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
            p = PI_control(Kₚ = 1 * 0.1, Kᵢ = 31.4159),
            q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159), timeDelay = 200e-6,
            padeOrderNum = 5, padeOrderDen = 5
        )),

        ugc = ugc_model,
        ohl = ohl_model,

        g4 = ac_source(
            setpoint = Setpoint(Vac = transmissionVoltage*sqrt(2),
                Pac = pHVDC1),
            P_min = -2000,
            P_max = 2000,
            Q_max = 1000,
            Q_min = -1000,
            pins = 3,
            transformation = true
        ),

        tl1 = overhead_line(length = 25e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1,
                Rᵈᶜ = 0.063,
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
            earth_parameters = (1, 1, 100), transformation = true),

        tl78 = overhead_line(length = 90e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1,
                Rᵈᶜ = 0.063,
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
            earth_parameters = (1, 1, 100), transformation = true)
    )
end

build() = NetworkBuilder.define(ohl_to_ugc(0.5), connections; options = builder_options)

end

module P2PGridspace
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from examples/P2P_HVDC_Gridspace.jl:22-285.
const transmission_voltage = 380 / sqrt(3)
const p_hvdc = 100.0
const q_c1 = 100.0
const q_c2 = 100.0
const soil_resistivity = 100.0
const corridor_length = 100e3;

const connections = (
    (node = :B3d, element = :tl1, side = 2, terminal = 1),
    (node = :B3d, element = :c1, side = 2, terminal = 1),
    (node = :B3q, element = :tl1, side = 2, terminal = 2),
    (node = :B3q, element = :c1, side = 2, terminal = 2),
    (node = :B2d, element = :g4, side = 1, terminal = 1),
    (node = :B2d, element = :tl1, side = 1, terminal = 1),
    (node = :B2q, element = :g4, side = 1, terminal = 2),
    (node = :B2q, element = :tl1, side = 1, terminal = 2),
    (node = :B4, element = :ugc, side = 1, terminal = 1),
    (node = :B4, element = :c1, side = 1, terminal = 1),
    (node = :BX, element = :ugc, side = 2, terminal = 1),
    (node = :BX, element = :ohl, side = 1, terminal = 1),
    (node = :B5, element = :ohl, side = 2, terminal = 1),
    (node = :B5, element = :c2, side = 1, terminal = 1),
    (node = :B6d, element = :tl78, side = 1, terminal = 1),
    (node = :B6d, element = :c2, side = 2, terminal = 1),
    (node = :B6q, element = :tl78, side = 1, terminal = 2),
    (node = :B6q, element = :c2, side = 2, terminal = 2),
    (node = :B7d, element = :g1, side = 1, terminal = 1),
    (node = :B7d, element = :tl78, side = 2, terminal = 1),
    (node = :B7q, element = :g1, side = 1, terminal = 2),
    (node = :B7q, element = :tl78, side = 2, terminal = 2)
);

const builder_options = (;
    voltageBase = transmission_voltage,
    power_flow = (; is_bounded = (; bus_voltage = true))
);

const fixed_element_specs = (;
    g1 = ac_source(Grid;
        setpoint = Setpoint(Vac = transmission_voltage * sqrt(2),
            Pac = p_hvdc),
        P_min = -2000,
        P_max = 2000,
        Q_min = -1000,
        Q_max = 1000,
        pins = 3,
        transformation = true
    ),
    c1 = mmc(Grid;
        Vᵈᶜ = 640,
        vDCbase = 640,
        Vₘ = transmission_voltage,
        P = -p_hvdc,
        Q = q_c1,
        P_min = -1500,
        P_max = 1500,
        Q_min = -500,
        Q_max = 500,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
        dc = PI_control(Kₚ = 6.0, Kᵢ = 15.0),
        timeDelay = 200e-6,
        padeOrderNum = 5,
        padeOrderDen = 5
    ),
    c2 = mmc(Grid;
        Vᵈᶜ = 640,
        vDCbase = 640,
        Vₘ = transmission_voltage,
        P = p_hvdc,
        Q = q_c2,
        P_min = -1000,
        P_max = 1000,
        Q_min = -1000,
        Q_max = 1000,
        vACbase_LL_RMS = 333,
        turnsRatio = 333 / 380,
        Lᵣ = 0.0461,
        Rᵣ = 0.4103,
        Lₐᵣₘ = 30e-3,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
        timeDelay = 200e-6,
        padeOrderNum = 5,
        padeOrderDen = 5
    ),
    g4 = ac_source(Grid;
        setpoint = Setpoint(Vac = transmission_voltage * sqrt(2),
            Pac = p_hvdc),
        P_min = -2000,
        P_max = 2000,
        Q_min = -1000,
        Q_max = 1000,
        pins = 3,
        transformation = true
    ),
    tl1 = overhead_line(Grid;
        length = 25e3,
        conductors = Conductors(Grid;
            organization = :flat,
            nᵇ = 3,
            nˢᵇ = 1,
            Rᵈᶜ = 0.063,
            rᶜ = 0.015,
            yᵇᶜ = 30.0,
            Δyᵇᶜ = 0.0,
            Δxᵇᶜ = 10.0,
            Δ̃xᵇᶜ = 0.0,
            dˢᵇ = 0.0,
            dˢᵃᵍ = 10.0
        ),
        groundwires = Groundwires(Grid;
            nᵍ = 2,
            Rᵍᵈᶜ = 0.92,
            rᵍ = 0.0062,
            Δxᵍ = 6.5,
            Δyᵍ = 7.5,
            dᵍˢᵃᵍ = 10.0
        ),
        earth_parameters = (1, 1, soil_resistivity),
        transformation = true
    ),
    tl78 = overhead_line(Grid;
        length = 90e3,
        conductors = Conductors(Grid;
            organization = :flat,
            nᵇ = 3,
            nˢᵇ = 1,
            Rᵈᶜ = 0.063,
            rᶜ = 0.015,
            yᵇᶜ = 30.0,
            Δyᵇᶜ = 0.0,
            Δxᵇᶜ = 10.0,
            Δ̃xᵇᶜ = 0.0,
            dˢᵇ = 0.0,
            dˢᵃᵍ = 10.0
        ),
        groundwires = Groundwires(Grid;
            nᵍ = 2,
            Rᵍᵈᶜ = 0.92,
            rᵍ = 0.0062,
            Δxᵍ = 6.5,
            Δyᵍ = 7.5,
            dᵍˢᵃᵍ = 10.0
        ),
        earth_parameters = (1, 1, soil_resistivity),
        transformation = true
    )
);

const fixed_elements = map(only, fixed_element_specs);

const corridor_conductors = only(Conductors(Grid;
    organization = :flat,
    nᵇ = 2,
    nˢᵇ = 1,
    Rᵈᶜ = 0.0266,
    rᶜ = 44.8e-3 / 2,
    yᵇᶜ = 18.0,
    Δyᵇᶜ = 0.0,
    Δxᵇᶜ = 7.3,
    Δ̃xᵇᶜ = 0.0,
    dˢᵇ = 0.0,
    dˢᵃᵍ = 6.0
));

const corridor_groundwires = only(Groundwires(Grid;
    nᵍ = 2,
    Rᵍᵈᶜ = 0.92,
    rᵍ = 0.0062,
    Δxᵍ = 7.3,
    Δyᵍ = 7.0,
    dᵍˢᵃᵍ = 6.0
));

@gridspace struct P2PCableGeometry
    spacing::Float64
    burial_depth::Float64
    core_radius::Float64
    insulation_1::Float64
    sheath::Float64
    insulation_2::Float64
    screen::Float64
    insulation_3::Float64
end;

const nominal_geometry = only(P2PCableGeometry(
    spacing = 1.0,
    burial_depth = 1.0,
    core_radius = 0.02622,
    insulation_1 = 0.06006 - 0.02622,
    sheath = 0.06336 - 0.06006,
    insulation_2 = 0.06636 - 0.06336,
    screen = 0.06651 - 0.06636,
    insulation_3 = 0.07256 - 0.06651
));

const characteristic_shares = (0.0, 0.05, 0.1, 0.5, 0.9, 1.0)
const endpoint_fraction = 1e-3
const corridor_lengths = Grid(map(characteristic_shares) do share
    effective_share = clamp(share, endpoint_fraction, 1 - endpoint_fraction)
    (;
        share,
        ohl = corridor_length * (1 - effective_share),
        ugc = corridor_length * effective_share
    )
end);

transition_builders = Gridspace{NetworkState}(
    lengths -> begin
        r1 = nominal_geometry.core_radius
        r2 = r1 + nominal_geometry.insulation_1
        r3 = r2 + nominal_geometry.sheath
        r4 = r3 + nominal_geometry.insulation_2
        r5 = r4 + nominal_geometry.screen
        r6 = r5 + nominal_geometry.insulation_3

        affected_elements = (;
            ohl = only(overhead_line(Grid;
                length = lengths.ohl,
                conductors = corridor_conductors,
                groundwires = corridor_groundwires,
                earth_parameters = (1, 1, soil_resistivity),
                transformation = true
            )),
            ugc = only(cable(Grid;
                length = lengths.ugc,
                positions = [
                    (-nominal_geometry.spacing / 2, nominal_geometry.burial_depth),
                    (nominal_geometry.spacing / 2, nominal_geometry.burial_depth)
                ],
                C1 = Conductor(rₒ = r1, ρ = 2.354e-8, μᵣ = 1.035),
                I1 = Insulator(rᵢ = r1, rₒ = r2, ϵᵣ = 2.67, μᵣ = 1.469),
                C2 = Conductor(rᵢ = r2, rₒ = r3, ρ = 2.14e-7, μᵣ = 1.0),
                I2 = Insulator(rᵢ = r3, rₒ = r4, ϵᵣ = 2.3, μᵣ = 1.0),
                C3 = Conductor(rᵢ = r4, rₒ = r5, ρ = 2.826e-8, μᵣ = 1.0),
                I3 = Insulator(rᵢ = r5, rₒ = r6, ϵᵣ = 2.3, μᵣ = 1.0),
                earth_parameters = (1, 1, soil_resistivity),
                transformation = true
            ))
        )
        define(merge(deepcopy(fixed_elements), affected_elements), connections;
            options = builder_options)
    end,
    (corridor_lengths,),
    (:corridor_lengths,)
);

build() = deepcopy(transition_builders[4])

end

module EnergyHub
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from examples/Energy_hub_MTDC.jl:9-216.
voltage = 220 / sqrt(3);
transformer_base = 333^2 / 1000;
compensation_inductance = 3 * voltage^2 / (2π * 50 * 50);

electrical = ElectricalMMC(vDC_base = 640, Sbase = 1000, vACbase_LL_RMS = 333,
    turnsRatio = 333/220, Lᵣ = 0.18 * transformer_base / (2π * 50), Rᵣ = 0.005 *
                                                                         transformer_base);

mmc_measurement = Measurement();

power_control = OuterActivePowerControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159));

dc_control = OuterActiveVdcControl(pi_ctrl = PIControl(Kp = 5, Ki = 15));

reactive_control = OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159));

current_control = InnerCurrentPIControl(pi_ctrl = PIControl(Kp = 0.7691, Ki = 522.7654),
    activate_ω_c_multiplication = false);

internal_control = ΣdqzControlTEC(
    ccsc = CirculatingCurrentSuppressionControl(PIControl(Kp = 0.1048, Ki = 48.1914)));

sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664));

modulation = UncompensatedModulation();
pq_control = ΔdqControlGFL(
    outer_active = power_control, outer_reactive = reactive_control, occ = current_control);
vdc_control = ΔdqControlGFL(outer_active = dc_control,
    outer_reactive = reactive_control, occ = current_control);

MMC1 = mmc(elec = electrical, meas = mmc_measurement, sync = sync,
    delta_control = pq_control, sigma_control = internal_control, modulation = modulation,
    setpoint = Setpoint(Pac = 700/3, Qac = 0, Vac = voltage * sqrt(2), Vdc = 640));

MMC2 = mmc(elec = electrical, meas = mmc_measurement, sync = sync,
    delta_control = pq_control, sigma_control = internal_control, modulation = modulation,
    setpoint = Setpoint(Pac = -1400/3, Qac = 0, Vac = voltage * sqrt(2), Vdc = 640));

MMC3 = mmc(elec = electrical, meas = mmc_measurement, sync = sync,
    delta_control = vdc_control, sigma_control = internal_control, modulation = modulation,
    setpoint = Setpoint(Pac = 1400/3, Qac = 0, Vac = voltage * sqrt(2), Vdc = 640));

wind_electrical = ElectricalTLC(Lᵣ = 0.01232, Rᵣ = 0.03872, Sbase = 1000,
    vACbase_LL_RMS = 220);

wind_measurement = Measurement(v_ac = PowerImpedance.Butterworth(order = 1, ωc = 1e4),
    i_ac = PowerImpedance.Butterworth(order = 1, ωc = 1e4));

wind_sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 1, Ki = 31.830988618379067),
    filter = PowerImpedance.Butterworth(order = 1, ωc = 2π * 80));

wind_power = OuterActivePowerControl(pi_ctrl = PIControl(Kp = 0.01, Ki = 10));

wind_reactive = OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.01, Ki = 10));

wind_current = InnerCurrentPIControl(pi_ctrl = PIControl(Kp = 0.254647908947033, Ki = 0.8));
wind_limits = PowerImpedance.Limits(
    P_min = 0.9 * 1000, P_max = 1.1 * 1000, Q_min = -0.5 * 1000, Q_max = 0.5 * 1000);
OWF = tlc(elec = wind_electrical, meas = wind_measurement, sync = wind_sync,
    outerActive = wind_power, outerReactive = wind_reactive, innerCurrent = wind_current,
    innerVoltage = NoInnerVoltageControl(), mod = NoModulation(), limits = wind_limits,
    setpoint = Setpoint(
        Pac = 700, Qac = -150, Pdc = 0, θac = 0, Vac = voltage * sqrt(2), Vdc = 640));

CableDC12 = cable(length = 250e3, positions = [(-0.5, 1), (0.5, 1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true);

CableDC23 = cable(length = 60e3, positions = [(-0.5, 1), (0.5, 1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true);

CableAC23 = cable(
    length = 60e3, positions = [(0, 1.33562), (-0.0575, 1.4322), (0.0575, 1.4322)],
    C1 = Conductor(rₒ = 25.45e-3, ρ = 2.63e-8),
    I1 = Insulator(rᵢ = 25.45e-3, rₒ = 50.65e-3, a = 2e-3, b = 1.5e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 50.65e-3, rₒ = 52.35e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 52.35e-3, rₒ = 55.75e-3, ϵᵣ = 100),
    earth_parameters = (1, 1, 1), transformation = true);

CableAC24 = cable(
    length = 10e3, positions = [(0, 1.33562), (-0.0575, 1.4322), (0.0575, 1.4322)],
    C1 = Conductor(rₒ = 25.45e-3, ρ = 2.63e-8),
    I1 = Insulator(rᵢ = 25.45e-3, rₒ = 50.65e-3, a = 2e-3, b = 1.5e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 50.65e-3, rₒ = 52.35e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 52.35e-3, rₒ = 55.75e-3, ϵᵣ = 100),
    earth_parameters = (1, 1, 1), transformation = true);

conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
    rᶜ = 0.015, yᵇᶜ = 30, Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10);
groundwires = Groundwires(
    nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10);

OHLAC01 = overhead_line(length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);

OHLAC35 = overhead_line(length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);

G1 = ac_source(setpoint = Setpoint(Vac = voltage * sqrt(2)), pins = 3,
    transformation = true);
Zg1 = impedance(z = s -> 0.1 + 0.005s, pins = 3, transformation = true);
G3 = ac_source(setpoint = Setpoint(Vac = voltage * sqrt(2)), pins = 3,
    transformation = true);
Zg3 = impedance(z = s -> 0.1 + 0.005s, pins = 3, transformation = true);

Q2 = impedance(z = s -> 1 + compensation_inductance * s, pins = 3, transformation = true);
Q3 = impedance(z = s -> 1 + compensation_inductance * s, pins = 3, transformation = true);
G_dc = dc_source(setpoint = Setpoint(Vdc = 640));
elements = (; MMC1, MMC2, MMC3, OWF, CableDC12, CableDC23, CableAC23, CableAC24,
    OHLAC01, OHLAC35, G1, G3, Zg1, Zg3, Q2, Q3, G_dc);

connections = (
    (node = :AC1d, element = :MMC1, side = 2, terminal = 1),
    (node = :AC1d, element = :OHLAC01, side = 1, terminal = 1),
    (node = :AC1q, element = :MMC1, side = 2, terminal = 2),
    (node = :AC1q, element = :OHLAC01, side = 1, terminal = 2),
    (node = :AC2d, element = :MMC2, side = 2, terminal = 1),
    (node = :AC2d, element = :CableAC23, side = 1, terminal = 1),
    (node = :AC2d, element = :CableAC24, side = 1, terminal = 1),
    (node = :AC2d, element = :Q2, side = 1, terminal = 1),
    (node = :AC2q, element = :MMC2, side = 2, terminal = 2),
    (node = :AC2q, element = :CableAC23, side = 1, terminal = 2),
    (node = :AC2q, element = :CableAC24, side = 1, terminal = 2),
    (node = :AC2q, element = :Q2, side = 1, terminal = 2),
    (node = :AC3d, element = :MMC3, side = 2, terminal = 1),
    (node = :AC3d, element = :CableAC23, side = 2, terminal = 1),
    (node = :AC3d, element = :OHLAC35, side = 1, terminal = 1),
    (node = :AC3d, element = :Q3, side = 1, terminal = 1),
    (node = :AC3q, element = :MMC3, side = 2, terminal = 2),
    (node = :AC3q, element = :CableAC23, side = 2, terminal = 2),
    (node = :AC3q, element = :OHLAC35, side = 1, terminal = 2),
    (node = :AC3q, element = :Q3, side = 1, terminal = 2),
    (node = :WindACd, element = :OWF, side = 2, terminal = 1),
    (node = :WindACd, element = :CableAC24, side = 2, terminal = 1),
    (node = :WindACq, element = :OWF, side = 2, terminal = 2),
    (node = :WindACq, element = :CableAC24, side = 2, terminal = 2),
    (node = :Grid1d, element = :Zg1, side = 2, terminal = 1),
    (node = :Grid1d, element = :OHLAC01, side = 2, terminal = 1),
    (node = :Grid1q, element = :Zg1, side = 2, terminal = 2),
    (node = :Grid1q, element = :OHLAC01, side = 2, terminal = 2),
    (node = :Grid3d, element = :Zg3, side = 2, terminal = 1),
    (node = :Grid3d, element = :OHLAC35, side = 2, terminal = 1),
    (node = :Grid3q, element = :Zg3, side = 2, terminal = 2),
    (node = :Grid3q, element = :OHLAC35, side = 2, terminal = 2),
    (node = :Source1d, element = :G1, side = 1, terminal = 1),
    (node = :Source1d, element = :Zg1, side = 1, terminal = 1),
    (node = :Source1q, element = :G1, side = 1, terminal = 2),
    (node = :Source1q, element = :Zg1, side = 1, terminal = 2),
    (node = :Source3d, element = :G3, side = 1, terminal = 1),
    (node = :Source3d, element = :Zg3, side = 1, terminal = 1),
    (node = :Source3q, element = :G3, side = 1, terminal = 2),
    (node = :Source3q, element = :Zg3, side = 1, terminal = 2),
    (node = :gndd, element = :Q2, side = 2, terminal = 1),
    (node = :gndd, element = :Q3, side = 2, terminal = 1),
    (node = :gndq, element = :Q2, side = 2, terminal = 2),
    (node = :gndq, element = :Q3, side = 2, terminal = 2),
    (node = :DC1, element = :MMC1, side = 1, terminal = 1),
    (node = :DC1, element = :CableDC12, side = 1, terminal = 1),
    (node = :DC2, element = :MMC2, side = 1, terminal = 1),
    (node = :DC2, element = :CableDC12, side = 2, terminal = 1),
    (node = :DC2, element = :CableDC23, side = 1, terminal = 1),
    (node = :DC3, element = :MMC3, side = 1, terminal = 1),
    (node = :DC3, element = :CableDC23, side = 2, terminal = 1),
    (node = :WindDC, element = :G_dc, side = 1, terminal = 1),
    (node = :WindDC, element = :OWF, side = 1, terminal = 1)
);

network = NetworkBuilder.define(elements, connections;
    options = (; voltageBase = voltage,
        power_flow = (; is_bounded = (; bus_voltage = true),
            optimizer = (; hessian_approximation = "limited-memory"))));
build() = network

end

module ConverterMachine
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from examples/Converter_machine_interaction.jl:8-204.
voltage = 380 / sqrt(3);

machine_electrical = ElectricalSM(Vᵃᶜ_base = 380, S_base = 1000, ωn = 100π,
    lt = 0.065, rt = 0.0026, La_d = 1.66, La_q = 1.61, Ll = 0.15, Ra = 0.0015);

machine_mechanical = MechanicalSM(
    H = 4, T_CH = 2, T_RH = 5, T_CO = 1, F_HP = 0.3, F_IP = 0.4, F_LP = 0.3);

machine_governor = GovernorSM(R = 0.05, T_w = 0.1, T_G = 0.2);

machine_avr = AVRSM(vref_SG = 1.01, T_R = 0.05, T_B = 1, T_C = 0.1, T_A = 0.02, K_A = 200);

sg1 = synchronousmachine(elec = machine_electrical, mech = machine_mechanical,
    gov = machine_governor, avr = machine_avr,
    setpoint = Setpoint(Pac = 900, Qac = -100, Vac = voltage * sqrt(2)));
sg1.limits = PowerImpedance.Limits(P_min = -2000, P_max = 2000, Q_min = -2000,
    Q_max = 2000);

electrical = ElectricalMMC(vDC_base = 800, vACbase_LL_RMS = 380, Sbase = 1000,
    Lₐᵣₘ = 0.05, Rₐᵣₘ = 1.07, Cₐᵣₘ = 0.01, N = 400, Lᵣ = 0.06, Rᵣ = 0.535);

measurement = Measurement();

sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664));

dc_control = OuterActiveVdcControl(pi_ctrl = PIControl(Kp = 5, Ki = 15));

power_control = OuterActivePowerControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159));

reactive_control = OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159));

voltage_control = OuterReactiveVacControl(pi_ctrl = PIControl(Kp = 0, Ki = 100));

voltage_support = VoltageSupportLag(K = 20, ωc = 100);

support_control = OuterReactiveQControl(
    pi_ctrl = PIControl(Kp = 0.1,
        Ki = 31.4159), support = voltage_support);

current_control = InnerCurrentPIControl(
    pi_ctrl = PIControl(Kp = 0.7691, Ki = 522.7654), activate_ω_c_multiplication = false);

internal_control = ΣdqzControlTEC(ccsc = CirculatingCurrentSuppressionControl(PIControl(
    Kp = 0.067, Ki = 30.8425)));

modulation = UncompensatedModulation();
remote_control = ΔdqControlGFL(
    outer_active = dc_control, outer_reactive = reactive_control, occ = current_control);
bus7_control = ΔdqControlGFL(
    outer_active = power_control, outer_reactive = voltage_control, occ = current_control);
bus5_control = ΔdqControlGFL(
    outer_active = power_control, outer_reactive = support_control, occ = current_control);
remote_limits = PowerImpedance.Limits(P_min = -1.5, P_max = 1.5, Q_min = -0.5, Q_max = 0.5);
receiving_limits = PowerImpedance.Limits(P_min = -1, P_max = 1, Q_min = -1, Q_max = 1);

c1 = mmc(
    elec = electrical, meas = measurement, sync = sync, delta_control = remote_control,
    sigma_control = internal_control, modulation = modulation, limits = remote_limits,
    setpoint = Setpoint(Pac = -600, Qac = 0, Vac = voltage * sqrt(2), Vdc = 800));

c2 = mmc(elec = electrical, meas = measurement, sync = sync, delta_control = bus7_control,
    sigma_control = internal_control, modulation = modulation, limits = receiving_limits,
    setpoint = Setpoint(Pac = 600, Qac = 100, Vac = voltage * sqrt(2), Vdc = 800));

c3 = mmc(
    elec = electrical, meas = measurement, sync = sync, delta_control = remote_control,
    sigma_control = internal_control, modulation = modulation, limits = remote_limits,
    setpoint = Setpoint(Pac = -600, Qac = 0, Vac = voltage * sqrt(2), Vdc = 800));

c4 = mmc(elec = electrical, meas = measurement, sync = sync, delta_control = bus5_control,
    sigma_control = internal_control, modulation = modulation, limits = receiving_limits,
    setpoint = Setpoint(Pac = 600, Qac = 100, Vac = voltage * sqrt(2), Vdc = 800));

conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,
    yᵇᶜ = 30, Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10);
groundwires = Groundwires(
    nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10);

tl89 = overhead_line(length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);

tl75 = overhead_line(length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);

tl96 = overhead_line(length = 90e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);

tl54 = overhead_line(length = 120e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);

tl64 = overhead_line(length = 70e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);

tl1 = overhead_line(length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);
tl2 = overhead_line(length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100), transformation = true);

tl78 = cable(length = 30e3, positions = [(-0.5, 1.9), (0, 1.9), (0.5, 1.9)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8), I1 = Insulator(rᵢ = 24.25e-3,
        rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8), I2 = Insulator(
        rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10), I3 = Insulator(
        rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3),
    earth_parameters = (1, 1, 100), transformation = true);

dc_line = cable(length = 100e3, positions = [(-0.5, 1), (0.5, 1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8), I1 = Insulator(rᵢ = 24.25e-3,
        rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8), I2 = Insulator(
        rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10), I3 = Insulator(
        rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true);

dc_line_2 = cable(length = 50e3, positions = [(-0.5, 1), (0.5, 1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8), I1 = Insulator(rᵢ = 24.25e-3,
        rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8), I2 = Insulator(
        rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10), I3 = Insulator(
        rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true);

t3 = transformer(n = 1, Lₚ = 0.0269/2, Lₛ = 0.0269/2, Rₚ = 0, Rₛ = 0,
    Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true);

grid_limits = PowerImpedance.Limits(P_min = -2000, P_max = 2000, Q_min = -1000,
    Q_max = 1000);
g3 = ac_source(setpoint = Setpoint(Vac = voltage * sqrt(2)),
    limits = grid_limits, pins = 3, transformation = true);
g4 = ac_source(setpoint = Setpoint(Vac = voltage * sqrt(2), Pac = 600),
    limits = grid_limits, pins = 3, transformation = true);
g5 = ac_source(setpoint = Setpoint(Vac = voltage * sqrt(2), Pac = 600),
    limits = grid_limits, pins = 3, transformation = true);

l5 = impedance(z = s -> 192.5 * 4.6s / (192.5 + 4.6s), pins = 3, transformation = true);
l6 = impedance(z = s -> 192.5 * 4.6s / (192.5 + 4.6s), pins = 3, transformation = true);
l8 = impedance(z = s -> 192.5 * 4.6s / (192.5 + 4.6s), pins = 3, transformation = true);
elements = (; sg1, c1, c2, c3, c4, tl78, tl89, tl75, tl96, tl54, tl64, tl1, tl2,
    dc_line, dc_line_2, t3, g3, g4, g5, l5, l6, l8);

connections = (
    (node = :Bus4d, element = :sg1, side = 1, terminal = 1),
    (node = :Bus4d, element = :tl64, side = 1, terminal = 1),
    (node = :Bus4d, element = :tl54, side = 1, terminal = 1),
    (node = :Bus4q, element = :sg1, side = 1, terminal = 2),
    (node = :Bus4q, element = :tl64, side = 1, terminal = 2),
    (node = :Bus4q, element = :tl54, side = 1, terminal = 2),
    (node = :Bus6d, element = :tl64, side = 2, terminal = 1),
    (node = :Bus6d, element = :l6, side = 1, terminal = 1),
    (node = :Bus6d, element = :tl96, side = 1, terminal = 1),
    (node = :Bus6q, element = :tl64, side = 2, terminal = 2),
    (node = :Bus6q, element = :l6, side = 1, terminal = 2),
    (node = :Bus6q, element = :tl96, side = 1, terminal = 2),
    (node = :Bus5d, element = :tl54, side = 2, terminal = 1),
    (node = :Bus5d, element = :l5, side = 1, terminal = 1),
    (node = :Bus5d, element = :tl75, side = 1, terminal = 1),
    (node = :Bus5d, element = :c4, side = 2, terminal = 1),
    (node = :Bus5q, element = :tl54, side = 2, terminal = 2),
    (node = :Bus5q, element = :l5, side = 1, terminal = 2),
    (node = :Bus5q, element = :tl75, side = 1, terminal = 2),
    (node = :Bus5q, element = :c4, side = 2, terminal = 2),
    (node = :Bus9d, element = :tl96, side = 2, terminal = 1),
    (node = :Bus9d, element = :tl89, side = 1, terminal = 1),
    (node = :Bus9d, element = :t3, side = 2, terminal = 1),
    (node = :Bus9q, element = :tl96, side = 2, terminal = 2),
    (node = :Bus9q, element = :tl89, side = 1, terminal = 2),
    (node = :Bus9q, element = :t3, side = 2, terminal = 2),
    (node = :Bus7d, element = :tl75, side = 2, terminal = 1),
    (node = :Bus7d, element = :tl78, side = 1, terminal = 1),
    (node = :Bus7d, element = :c2, side = 2, terminal = 1),
    (node = :Bus7q, element = :tl75, side = 2, terminal = 2),
    (node = :Bus7q, element = :tl78, side = 1, terminal = 2),
    (node = :Bus7q, element = :c2, side = 2, terminal = 2),
    (node = :Bus8d, element = :tl78, side = 2, terminal = 1),
    (node = :Bus8d, element = :tl89, side = 2, terminal = 1),
    (node = :Bus8d, element = :l8, side = 1, terminal = 1),
    (node = :Bus8q, element = :tl78, side = 2, terminal = 2),
    (node = :Bus8q, element = :tl89, side = 2, terminal = 2),
    (node = :Bus8q, element = :l8, side = 1, terminal = 2),
    (node = :gndd, element = :l5, side = 2, terminal = 1),
    (node = :gndd, element = :l6, side = 2, terminal = 1),
    (node = :gndd, element = :l8, side = 2, terminal = 1),
    (node = :gndq, element = :l5, side = 2, terminal = 2),
    (node = :gndq, element = :l6, side = 2, terminal = 2),
    (node = :gndq, element = :l8, side = 2, terminal = 2),
    (node = :Bus3d, element = :g3, side = 1, terminal = 1),
    (node = :Bus3d, element = :t3, side = 1, terminal = 1),
    (node = :Bus3q, element = :g3, side = 1, terminal = 2),
    (node = :Bus3q, element = :t3, side = 1, terminal = 2),
    (node = :Remote1d, element = :c1, side = 2, terminal = 1),
    (node = :Remote1d, element = :tl1, side = 2, terminal = 1),
    (node = :Remote1q, element = :c1, side = 2, terminal = 2),
    (node = :Remote1q, element = :tl1, side = 2, terminal = 2),
    (node = :Source1d, element = :g4, side = 1, terminal = 1),
    (node = :Source1d, element = :tl1, side = 1, terminal = 1),
    (node = :Source1q, element = :g4, side = 1, terminal = 2),
    (node = :Source1q, element = :tl1, side = 1, terminal = 2),
    (node = :Remote2d, element = :c3, side = 2, terminal = 1),
    (node = :Remote2d, element = :tl2, side = 2, terminal = 1),
    (node = :Remote2q, element = :c3, side = 2, terminal = 2),
    (node = :Remote2q, element = :tl2, side = 2, terminal = 2),
    (node = :Source2d, element = :g5, side = 1, terminal = 1),
    (node = :Source2d, element = :tl2, side = 1, terminal = 1),
    (node = :Source2q, element = :g5, side = 1, terminal = 2),
    (node = :Source2q, element = :tl2, side = 1, terminal = 2),
    (node = :DC1, element = :c1, side = 1, terminal = 1),
    (node = :DC1, element = :dc_line, side = 1, terminal = 1),
    (node = :DC2, element = :c2, side = 1, terminal = 1),
    (node = :DC2, element = :dc_line, side = 2, terminal = 1),
    (node = :DC3, element = :c3, side = 1, terminal = 1),
    (node = :DC3, element = :dc_line_2, side = 1, terminal = 1),
    (node = :DC4, element = :c4, side = 1, terminal = 1),
    (node = :DC4, element = :dc_line_2, side = 2, terminal = 1)
);

network = NetworkBuilder.define(elements, connections;
    options = (; voltageBase = voltage,
        power_flow = (; is_bounded = (; bus_voltage = true),
            optimizer = (; hessian_approximation = "limited-memory"))));
build() = network

end

module ConnectionDSL
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from examples/Connection_DSL.jl:192-230.
delta_control = ΔdqControlGFL(
    outer_active = NoOuterActiveControl(),
    outer_reactive = NoOuterReactiveControl(),
    occ = NoInnerCurrentControl()
);

converter_elements = (
    dc_grid = dc_source(setpoint = Setpoint(Vdc = 480.0)),
    ac_grid = ac_source(pins = 3, transformation = true),
    mmc = mmc(
        sync = NoSynchronization(),
        delta_control = delta_control,
        sigma_control = ΣdqzControlTEC()
    ),
    tlc = tlc(),
    blackbox_converter = PowerImpedance.Element(
        input_pins = 1,
        output_pins = 2,
        element_model = PowerImpedance.Blackbox_MMC()
    )
);

converter_connections = (
    (node = :dc_bus, element = :dc_grid, side = 1, terminal = 1),
    (node = :dc_bus, element = :mmc, side = 1, terminal = 1),
    (node = :dc_bus, element = :tlc, side = 1, terminal = 1),
    (node = :dc_bus, element = :blackbox_converter, side = 1, terminal = 1),
    (node = :ac_bus_d, element = :ac_grid, side = 1, terminal = 1),
    (node = :ac_bus_d, element = :mmc, side = 2, terminal = 1),
    (node = :ac_bus_d, element = :tlc, side = 2, terminal = 1),
    (node = :ac_bus_d, element = :blackbox_converter, side = 2, terminal = 1),
    (node = :ac_bus_q, element = :ac_grid, side = 1, terminal = 2),
    (node = :ac_bus_q, element = :mmc, side = 2, terminal = 2),
    (node = :ac_bus_q, element = :tlc, side = 2, terminal = 2),
    (node = :ac_bus_q, element = :blackbox_converter, side = 2, terminal = 2)
);

converter_topology = NetworkTopology(converter_elements, converter_connections);
converter_topology.connections

function build()
    return NetworkBuilder.define(converter_elements, converter_connections)
end

end

function replace_model(state, name; replacements...)
    element = state.elements[name]
    model = element.element_model
    fields = merge(
        NamedTuple{fieldnames(typeof(model))}(
            Tuple(getfield(model, f) for f in fieldnames(typeof(model)))),
        (; replacements...))
    replacement = Base.typename(typeof(model)).wrapper(values(fields)...)
    # Element's model parameter changes with the selected converter blocks.
    updated = PI.Element(;
        input_pins = element.input_pins + element.transformation,
        output_pins = element.output_pins + element.transformation,
        element_model = replacement, setpoint = deepcopy(element.setpoint),
        limits = deepcopy(element.limits), transformation = element.transformation,
        connection = element.connection)
    elements = merge(state.elements, NamedTuple{(name,)}((updated,)))
    rows = [(; r.node, r.element, r.side, r.terminal)
            for r in state.topology.connections]
    return NB.define(elements, rows; options = state.options)
end

function no_control()
    state = PSCADFixtures.mmc_pq_network().state
    sigma = PI.ΣdqzControlTEC(tec = PI.NoTotalEnergyControl(),
        zscc = PI.NoZeroSequenceCurrentControl(),
        ccsc = PI.NoCirculatingCurrentSuppressionControl())
    return replace_model(state, :DUT; sigma_control = sigma)
end

function filter_fixture(kind)
    state = PSCADFixtures.mmc_pq_network().state
    meas = state.elements.DUT.element_model.meas
    fields = NamedTuple{fieldnames(typeof(meas))}(
        Tuple(getfield(meas, f) for f in fieldnames(typeof(meas))))
    fields = merge(fields, (;
        v_dc = PI.MeasurementSignal(:v_dc,
        kind(order = 2, ωc = 100π))))
    return replace_model(state, :DUT; meas = PI.Measurement(values(fields)...))
end

function modulation_fixture(block)
    return replace_model(PSCADFixtures.tlc_case1_network().state, :DUT; mod = block)
end

function probes(state; elim_elements = Symbol[], abcd_elements = Symbol[], pscad = true)
    rows = state.topology.connections
    sources, active = Set{Symbol}(), Set{Symbol}()
    for name in keys(state.elements)
        element = state.elements[name]
        if PI.is_source(element)
            push!(sources, name)
        elseif PI.is_active(element)
            push!(active, name)
        end
    end
    source_nets = Set(row.node for row in rows if row.element in sources)
    nets = unique(row.node for row in rows if row.bus != 0 && row.node ∉ source_nets)
    if length(nets) > 12
        retained = Set(nets)
        nets = unique(row.node for row in rows if row.node in retained &&
                      row.element in active)
        nets = nets[1:min(12, length(nets))]
    end
    return (; nets = collect(nets), elim_elements, abcd_elements, pscad)
end

const FIXTURES = NamedTuple[]
const SOURCES = Dict{Symbol, String}()
function register(name, build, source; kwargs...)
    SOURCES[name] = source
    state = build()
    push!(FIXTURES, (;
        name, build = () -> deepcopy(build()), probes = probes(state; kwargs...)))
    SOURCES[name] = source
end

register(:im, () -> PSCADFixtures.im_network().state,
    "test/pscad/fixtures.jl:im_network")
register(:small_ac, () -> PSCADFixtures.small_ac_network().state,
    "test/pscad/fixtures.jl:small_ac_network")
register(:sm, () -> PSCADFixtures.sm_network().state,
    "test/pscad/fixtures.jl:sm_network")
register(:passive_ohl, () -> PSCADFixtures.passive_ohl_network().state,
    "test/pscad/fixtures.jl:passive_ohl_network")
register(:transformer_yy, () -> PSCADFixtures.transformer_network().state,
    "test/pscad/fixtures.jl:transformer_network")
register(
    :transformer_dy, () -> PSCADFixtures.transformer_network(; organization = :ΔY).state,
    "test/pscad/fixtures.jl:transformer_network")
register(:dc, () -> PSCADFixtures.dc_network().state,
    "test/pscad/fixtures.jl:dc_network")
register(:dc_cable, () -> PSCADFixtures.dc_cable_network().state,
    "test/pscad/fixtures.jl:dc_cable_network")
register(:tlc_case1, () -> PSCADFixtures.tlc_case1_network().state,
    "test/pscad/fixtures.jl:tlc_case1_network")
register(:tlc_case2, () -> PSCADFixtures.tlc_case2_network().state,
    "test/pscad/fixtures.jl:tlc_case2_network")
register(:tlc_vac, () -> PSCADFixtures.tlc_vac_network().state,
    "test/pscad/fixtures.jl:tlc_vac_network")
register(:mmc_pq, () -> PSCADFixtures.mmc_pq_network().state,
    "test/pscad/fixtures.jl:mmc_pq_network")
register(:mmc_vdc, () -> PSCADFixtures.mmc_vdc_network().state,
    "test/pscad/fixtures.jl:mmc_vdc_network")
register(:mmc_pf, () -> PSCADFixtures.mmc_pf_network().state,
    "test/pscad/fixtures.jl:mmc_pf_network")
register(:mmc_qv, () -> PSCADFixtures.mmc_qv_network().state,
    "test/pscad/fixtures.jl:mmc_qv_network")
register(:mmc_vac, () -> PSCADFixtures.mmc_vac_network().state,
    "test/pscad/fixtures.jl:mmc_vac_network")
register(:mmc_gfm, () -> PSCADFixtures.mmc_gfm_network().state,
    "test/pscad/fixtures.jl:mmc_gfm_network")
register(:mmc_compensated, () -> PSCADFixtures.mmc_compensated_network().state,
    "test/pscad/fixtures.jl:mmc_compensated_network")
register(:mmc_no_control, no_control, "test/pscad/mmc_no_control_test.jl")
register(:mmc_energy, () -> PSCADFixtures.mmc_compensated_network().state,
    "test/pscad/mmc_energy_test.jl")
register(:ieee39, IEEE39.build, "test/NetworkBuilder_test.jl:1312-2515";
    elim_elements = [:STATCOM])
register(:droop_mmc, () -> Droop.droop_network(:mmc),
    "test/dc_voltage_support_test.jl:9-47";
    pscad = false)
register(:droop_tlc, () -> Droop.droop_network(:tlc),
    "test/dc_voltage_support_test.jl:9-47";
    pscad = false)
register(:p2p_alt, P2PAlt.build, "examples/P2P_HVDC_ALT.jl:12-171")
register(:p2p_gridspace_nominal, P2PGridspace.build,
    "examples/P2P_HVDC_Gridspace.jl:22-284")
register(:energy_hub_mtdc, EnergyHub.build, "examples/Energy_hub_MTDC.jl:9-216")
register(:converter_machine, ConverterMachine.build,
    "examples/Converter_machine_interaction.jl:8-204")
register(:connection_dsl, ConnectionDSL.build, "examples/Connection_DSL.jl";
    pscad = false)

register(:cov_chebyshev, () -> filter_fixture(PI.Chebyshev),
    "mmc_pq: v_dc measurement filter";
    pscad = false)
register(:cov_bessel, () -> filter_fixture(PI.Bessel),
    "mmc_pq: v_dc measurement filter";
    pscad = false)
register(:cov_criticaldamping, () -> filter_fixture(PI.CriticalDamping),
    "mmc_pq: v_dc measurement filter";
    pscad = false)
register(:cov_delaymodulation, () -> modulation_fixture(PI.DelayModulation()),
    "tlc_case1: modulation")
register(:cov_nomodulation, () -> modulation_fixture(PI.NoModulation()),
    "tlc_case1: modulation")
end
