module ParityFixtures
using PowerImpedance
const PI = PowerImpedance
const NB = PI.NetworkBuilder
include("../pscad/fixtures.jl")

module IEEE39
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from test/NetworkBuilder_test.jl:70-216.
# Rewritten from `examples/IEEE39bus.jl:18`.
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

        dummy_impedance = impedance(; z = 1e4, conductors = 1),

        TR2_30 = transformer(;
            n = 345/345,
            Lₚ = (0.0181/2)*Lb_345,
            Lₛ = (0.0181/2)*Lb_345,
            conductors = 3),

        TR6_31 = transformer(;
            n = 345/345,
            Lₚ = (0.025/2)*Lb_345,
            Lₛ = (0.025/2)*Lb_345,
            conductors = 3),

        TR10_32 = transformer(;
            n = 345/345,
            Lₚ = (0.02/2)*Lb_345,
            Lₛ = (0.02/2)*Lb_345,
            conductors = 3),

        TR11_12 = transformer(;
            n = 345/345,
            Lₚ = (0.0435/2)*Lb_345,
            Rₚ = (0.0016/2)*Rb_345,
            Lₛ = (0.0435/2)*Lb_345,
            Rₛ = (0.0016/2)*Rb_345,
            conductors = 3),

        TR12_13 = transformer(;
            n = 345/345,
            Lₚ = (0.0435/2)*Lb_345,
            Rₚ = (0.0016/2)*Rb_345,
            Lₛ = (0.0435/2)*Lb_345,
            Rₛ = (0.0016/2)*Rb_345,
            conductors = 3),

        TR19_20 = transformer(;
            n = 345/345,
            Lₚ = (0.0138 / 2)*Lb_345,
            Rₚ = (0.0007/2)*Rb_345,
            Lₛ = (0.0138 / 2)*Lb_345,
            Rₛ = (0.0007/2)*Rb_345,
            conductors = 3),

        TR19_33 = transformer(;
            n = 345/345,
            Lₚ = (0.0142 / 2)*Lb_345,
            Rₚ = (0.0007/2)*Rb_345,
            Lₛ = (0.0142 / 2)*Lb_345,
            Rₛ = (0.0007/2)*Rb_345,
            conductors = 3),

        TR20_34 = transformer(;
            n = 345/345,
            Lₚ = (0.0180 / 2)*Lb_345,
            Rₚ = (0.0009/2)*Rb_345,
            Lₛ = (0.0180 / 2)*Lb_345,
            Rₛ = (0.0009/2)*Rb_345,
            conductors = 3),

        TR22_35 = transformer(;
            n = 345/345,
            Lₚ = (0.0143 / 2)*Lb_345,
            Lₛ = (0.0143 / 2)*Lb_345,
            conductors = 3),

        TR23_36 = transformer(;
            n = 345/345,
            Lₚ = (0.0272 / 2)*Lb_345,
            Rₚ = (0.0005/2)*Rb_345,
            Lₛ = (0.0272 / 2)*Lb_345,
            Rₛ = (0.0005/2)*Rb_345,
            conductors = 3),

        TR25_37 = transformer(;
            n = 345/345,
            Lₚ = (0.0232 / 2)*Lb_345,
            Rₚ = (0.0006/2)*Rb_345,
            Lₛ = (0.0232 / 2)*Lb_345,
            Rₛ = (0.0006/2)*Rb_345,
            conductors = 3),

        TR29_38 = transformer(;
            n = 345/345,
            Lₚ = (0.0156 / 2)*Lb_345,
            Rₚ = (0.0008/2)*Rb_345,
            Lₛ = (0.0156 / 2)*Lb_345,
            Rₛ = (0.0008/2)*Rb_345,
            conductors = 3),

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

        LoadB3 =
        impedance(; z = (s::Complex) -> (R_B3+s*L_B3), conductors = 3),

        LoadB4a =
        impedance(; z = (s::Complex) -> (R_B4a+s*L_B4), conductors = 3),
        LoadB4b = impedance(;
            z = (s::Complex) -> (R_B4b+(1/(s*C_B4))),
            conductors = 3),

        LoadB5 = impedance(;
            z = (s::Complex) -> (R_B5+(1/(s*C_B5))),
            conductors = 3),

        LoadB7 =
        impedance(; z = (s::Complex) -> (R_B7+s*L_B7), conductors = 3),

        LoadB8 =
        impedance(; z = (s::Complex) -> (R_B8+s*L_B8), conductors = 3),

        LoadB12 = impedance(;
            z = (s::Complex)->(345/230)*(345/230)*(R_B12+s*L_B12),
            conductors = 3),

        LoadB15 =
        impedance(; z = (s::Complex) -> (R_B15+s*L_B15), conductors = 3),

        LoadB16 =
        impedance(; z = (s::Complex) -> (R_B16+s*L_B16), conductors = 3),

        LoadB18 =
        impedance(; z = (s::Complex) -> (R_B18+s*L_B18), conductors = 3),

        LoadB20 =
        impedance(; z = (s::Complex) -> (R_B20+s*L_B20), conductors = 3),

        LoadB21 =
        impedance(; z = (s::Complex) -> (R_B21+s*L_B21), conductors = 3),

        LoadB23 =
        impedance(; z = (s::Complex) -> (R_B23+s*L_B23), conductors = 3),

        LoadB24 = impedance(;
            z = (s::Complex) -> (R_B24+(1/(s*C_B24))),
            conductors = 3),

        LoadB25 =
        impedance(; z = (s::Complex) -> (R_B25+s*L_B25), conductors = 3),

        LoadB26 =
        impedance(; z = (s::Complex) -> (R_B26+s*L_B26), conductors = 3),

        LoadB27 =
        impedance(; z = (s::Complex) -> (R_B27+s*L_B27), conductors = 3),

        LoadB28 =
        impedance(; z = (s::Complex) -> (R_B28+s*L_B28), conductors = 3),

        LoadB29 =
        impedance(; z = (s::Complex) -> (R_B29+s*L_B29), conductors = 3),

        LoadB31 = impedance(;
            z = (s::Complex)->(345/22)*(345/22)*(R_B31+s*L_B31),
            conductors = 3),

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

function build()
    return NetworkBuilder.define(ieee39bus_elements(), ieee39bus_connections();
        exclude = (:T8_9,), options = (; voltageBase = Vm1,
            power_flow = (; is_bounded = (; bus_voltage = true))))
end

end

module Droop
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from test/dc_voltage_support_test.jl:9-47.

function converter(kind; K = 5.0, voltage = 672.0, dcbase = 640.0)

    limits = PI.Limits(P_min = -100.0, P_max = 100.0, Q_min = -50.0, Q_max = 50.0)
    outer = OuterActivePowerControl(pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0),
        support = DCVoltageSupportLag(; K, ωc = 2.0))
    reactive = OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0))
    sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.085, Ki = 32.0))
    occ = InnerCurrentPIControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 43.0))
    return kind === :mmc ?
           let model = mmc(;
        elec = ElectricalMMC(Sbase = 500.0, vDC_base = dcbase),
        delta_control = ΔdqControlGFL(outer_active = outer,
            outer_reactive = reactive, occ = occ),
        sigma_control = ΣdqzControlTEC(
            tec = TotalEnergyControl(pi_control = PIControl(Kp = 1.4, Ki = 30.0)),
            zscc = ZeroSequenceCurrentControl(PIControl(Kp = 0.1, Ki = 43.0)),
            ccsc = CirculatingCurrentSuppressionControl(PIControl(Kp = 0.1, Ki = 43.0))),
        sync = sync, limits = limits)
               b = bases(model)
               component(model; delta_control = (outer_active = (p_ref = (50.0) / b.S,
                       support = (v_dc_ref = voltage / b.v_dc,)),
                       outer_reactive = (q_ref = (25.0) / b.S,),),
                   powerflow = (; v_ac = (380sqrt(2/3)) / b.v_ac,
                       p_dc = (50.0) / b.S))
           end :
           let model = tlc(;
        elec = ElectricalTLC(Sbase = 500.0, vACbase_LL_RMS = 380.0, vDCbase = dcbase),
        outerActive = outer, outerReactive = reactive, innerCurrent = occ,
        sync = sync, limits = limits)
               b = bases(model)
               component(model; outerActive = (p_ref = (50.0) / b.S,
                       support = (v_dc_ref = voltage / b.v_dc,)),
                   outerReactive = (q_ref = (25.0) / b.S,),
                   powerflow = (; v_ac = (380sqrt(2/3)) / b.v_ac,
                       p_dc = (50.0) / b.S))
           end
end

function droop_network(kind; K = 5.0)
    elements = (;
        DUT = converter(kind; K),
        G_AC = ac_source(v = 380sqrt(2/3)),
        G_DC = dc_source(v = 680.0),
        line = impedance(; z = s -> 0.5, conductors = 1))
    rows = (
        Bus(:AC; ports = ((:DUT, :ac),), domain = ACDQ),
        Bus(:AC; ports = ((:G_AC, :ac),), domain = ACDQ),
        Bus(:DC1; ports = ((:DUT, :dc), (:line, :side1))),
        Bus(:DC2; ports = ((:line, :side2), (:G_DC, :dc))))
    return NB.define(elements, rows; options = (; voltageBase = 380/sqrt(3)))
end
const PI = PowerImpedance
const NB = PI.NetworkBuilder

end

module P2PAlt
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from examples/P2P_HVDC_ALT.jl:12-171.
# Rewritten from `examples/P2P_HVDC_ALT.jl:12`.
transmissionVoltage = 380 / sqrt(3)
pHVDC1 = 100
qC1 = 100
qC2 = 100

rho = 100.0
L = 100e3

connections = (
    NetworkBuilder.Bus(:B3; ports = ((:tl1, :side2), (:c1, :ac)), domain = ACDQ),
    NetworkBuilder.Bus(:B2; ports = ((:g4, :ac), (:tl1, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:B4; ports = ((:ugc, :side1), (:c1, :dc))),
    NetworkBuilder.Bus(:BX; ports = ((:ugc, :side2), (:ohl, :side1))),
    NetworkBuilder.Bus(:B5; ports = ((:ohl, :side2), (:c2, :dc))),
    NetworkBuilder.Bus(:B6; ports = ((:tl78, :side1), (:c2, :ac)), domain = ACDQ),
    NetworkBuilder.Bus(:B7; ports = ((:g1, :ac), (:tl78, :side2)), domain = ACDQ)
)

# Bus-voltage bounds belong in the builder options used for every case.
builder_options = (;
    voltageBase = transmissionVoltage,
    power_flow = (;
        is_bounded = (;
        bus_voltage = true,
    ),
    )
)

# `x` is the fraction of the corridor implemented as underground cable. A 100 m
# regularization at either endpoint avoids singular zero-length line models.
function ohl_to_ugc(x)
    share = clamp(x, 1e-3, 1 - 1e-3)
    ohl_model = overhead_line(;
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
        ), earth_parameters = (1, 1, rho))

    ugc_model = cable(;
        length = L * share,
        positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
        I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
        C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
        I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
        C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
        I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
        earth_parameters = (1, 1, rho))

    return (;
        g1 = ac_source(v = transmissionVoltage*sqrt(2), p = pHVDC1),

        c1 = let model = only(mmc(Grid;
            elec = ElectricalMMC(
                Sbase = 1000.0, vDC_base = 640.0,
                vACbase_LL_RMS = 380.0, turnsRatio = 1.0),
            limits = PowerImpedance.Limits(P_min = -1500.0, P_max = 1500.0,
                Q_min = -500.0, Q_max = 500.0),
            sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664)),
            delta_control = ΔdqControlGFL(
                outer_active = OuterActiveVdcControl(
                    pi_ctrl = PIControl(Kp = 6.0, Ki = 15.0)),
                outer_reactive = OuterReactiveQControl(
                    pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
                occ = InnerCurrentPIControl(
                    pi_ctrl = PIControl(Kp = 0.7691, Ki = 522.7654),
                    activate_ω_c_multiplication = false)),
            sigma_control = ΣdqzControlTEC(
                ccsc = CirculatingCurrentSuppressionControl(
                    PIControl(Kp = 0.1048, Ki = 48.1914))),
            modulation = UncompensatedModulation(timeDelay = 200e-6,
                padeOrderNum = 5, padeOrderDen = 5)
        ))
            b = bases(model)
            component(model; delta_control = (outer_active = (v_dc_ref = (640.0) / b.v_dc,),
                    outer_reactive = (q_ref = (qC1) / b.S,),),
                powerflow = (; p_ac = (-pHVDC1) / b.S,
                    v_ac = (transmissionVoltage * sqrt(2)) / b.v_ac,
                    p_dc = (0.0) / b.S))
        end,

        c2 = let model = only(mmc(Grid;
            elec = ElectricalMMC(
                Sbase = 1000.0, vDC_base = 640.0,
                vACbase_LL_RMS = 333.0, turnsRatio = 333 / 380,
                Lᵣ = 0.0461, Rᵣ = 0.4103,
                Lₐᵣₘ = 30e-3
            ),
            limits = PowerImpedance.Limits(P_min = -1000.0, P_max = 1000.0,
                Q_min = -1000.0, Q_max = 1000.0),
            sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664)),
            delta_control = ΔdqControlGFL(
                outer_active = OuterActivePowerControl(
                    pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
                outer_reactive = OuterReactiveQControl(
                    pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
                occ = InnerCurrentPIControl(
                    pi_ctrl = PIControl(Kp = 0.7691, Ki = 522.7654),
                    activate_ω_c_multiplication = false)),
            sigma_control = ΣdqzControlTEC(
                ccsc = CirculatingCurrentSuppressionControl(
                    PIControl(Kp = 0.1048, Ki = 48.1914))),
            modulation = UncompensatedModulation(timeDelay = 200e-6,
                padeOrderNum = 5, padeOrderDen = 5)
        ))
            b = bases(model)
            component(model; delta_control = (outer_active = (p_ref = (pHVDC1) / b.S,),
                    outer_reactive = (q_ref = (qC2) / b.S,),),
                powerflow = (; v_dc = (640.0) / b.v_dc,
                    v_ac = (transmissionVoltage * sqrt(2)) / b.v_ac,
                    p_dc = (0.0) / b.S))
        end,

        ugc = ugc_model,
        ohl = ohl_model,

        g4 = ac_source(v = transmissionVoltage*sqrt(2), p = pHVDC1),

        tl1 = overhead_line(; length = 25e3,
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
            earth_parameters = (1, 1, 100)),

        tl78 = overhead_line(; length = 90e3,
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
            earth_parameters = (1, 1, 100))
    )
end

build() = NetworkBuilder.define(ohl_to_ugc(0.5), connections; options = builder_options)

end

module P2PGridspace
using PowerImpedance
using PowerImpedance.NetworkBuilder
# Copied from examples/P2P_HVDC_Gridspace.jl:22-285.
# Rewritten from `examples/P2P_HVDC_Gridspace.jl:22`.
const transmission_voltage = 380 / sqrt(3)
const p_hvdc = 100.0
const q_c1 = 100.0
const q_c2 = 100.0
const soil_resistivity = 100.0
const corridor_length = 100e3;

const connections = (
    NetworkBuilder.Bus(:B3; ports = ((:tl1, :side2), (:c1, :ac)), domain = ACDQ),
    NetworkBuilder.Bus(:B2; ports = ((:g4, :ac), (:tl1, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:B4; ports = ((:ugc, :side1), (:c1, :dc))),
    NetworkBuilder.Bus(:BX; ports = ((:ugc, :side2), (:ohl, :side1))),
    NetworkBuilder.Bus(:B5; ports = ((:ohl, :side2), (:c2, :dc))),
    NetworkBuilder.Bus(:B6; ports = ((:tl78, :side1), (:c2, :ac)), domain = ACDQ),
    NetworkBuilder.Bus(:B7; ports = ((:g1, :ac), (:tl78, :side2)), domain = ACDQ),
);

const builder_options = (;
    voltageBase = transmission_voltage,
    power_flow = (; is_bounded = (; bus_voltage = true))
);

# These elements do not change in the length or cable-geometry studies. The
# lazy constructors still return singleton Gridspaces; `only` makes the
# fixed scalar elements explicit.
const fixed_element_specs = (;
    g1 = ac_source(Grid; v = transmission_voltage * sqrt(2), p = p_hvdc),
    c1 = mmc(Grid;
        elec = ElectricalMMC(
            Sbase = 1000.0, vDC_base = 640.0,
            vACbase_LL_RMS = 380.0, turnsRatio = 1.0),
        limits = PowerImpedance.Limits(P_min = -1500.0, P_max = 1500.0,
            Q_min = -500.0, Q_max = 500.0),
        sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664)),
        delta_control = ΔdqControlGFL(
            outer_active = OuterActiveVdcControl(
                pi_ctrl = PIControl(Kp = 6.0, Ki = 15.0)),
            outer_reactive = OuterReactiveQControl(
                pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
            occ = InnerCurrentPIControl(
                pi_ctrl = PIControl(Kp = 0.7691, Ki = 522.7654),
                activate_ω_c_multiplication = false)),
        sigma_control = ΣdqzControlTEC(
            ccsc = CirculatingCurrentSuppressionControl(
                PIControl(Kp = 0.1048, Ki = 48.1914))),
        modulation = UncompensatedModulation(timeDelay = 200e-6,
            padeOrderNum = 5, padeOrderDen = 5)
    ),
    c2 = mmc(Grid;
        elec = ElectricalMMC(
            Sbase = 1000.0, vDC_base = 640.0,
            vACbase_LL_RMS = 333.0, turnsRatio = 333 / 380,
            Lᵣ = 0.0461, Rᵣ = 0.4103,
            Lₐᵣₘ = 30e-3
        ),
        limits = PowerImpedance.Limits(P_min = -1000.0, P_max = 1000.0,
            Q_min = -1000.0, Q_max = 1000.0),
        sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664)),
        delta_control = ΔdqControlGFL(
            outer_active = OuterActivePowerControl(
                pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
            outer_reactive = OuterReactiveQControl(
                pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
            occ = InnerCurrentPIControl(
                pi_ctrl = PIControl(Kp = 0.7691, Ki = 522.7654),
                activate_ω_c_multiplication = false)),
        sigma_control = ΣdqzControlTEC(
            ccsc = CirculatingCurrentSuppressionControl(
                PIControl(Kp = 0.1048, Ki = 48.1914))),
        modulation = UncompensatedModulation(timeDelay = 200e-6,
            padeOrderNum = 5, padeOrderDen = 5)
    ),
    g4 = ac_source(Grid; v = transmission_voltage * sqrt(2), p = p_hvdc),
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
        earth_parameters = (1, 1, soil_resistivity)),
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
        earth_parameters = (1, 1, soil_resistivity))
);

const fixed_elements = let models = map(only, fixed_element_specs)
    c1 = let model = models.c1
        b = bases(model)
        component(model; delta_control = (outer_active = (v_dc_ref = (640.0) / b.v_dc,),
                outer_reactive = (q_ref = (q_c1) / b.S,),),
            powerflow = (; p_ac = (-p_hvdc) / b.S,
                v_ac = (transmission_voltage * sqrt(2)) / b.v_ac,
                p_dc = (0.0) / b.S))
    end
    c2 = let model = models.c2
        b = bases(model)
        component(model; delta_control = (outer_active = (p_ref = (p_hvdc) / b.S,),
                outer_reactive = (q_ref = (q_c2) / b.S,),),
            powerflow = (; v_dc = (640.0) / b.v_dc,
                v_ac = (transmission_voltage * sqrt(2)) / b.v_ac,
                p_dc = (0.0) / b.S))
    end
    merge(models, (; c1, c2))
end;

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

# Cable layer boundaries are generated from positive thicknesses. Independent
# perturbations therefore cannot invert or overlap adjacent layers.
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

# ## Deterministic OHL/UGC transition
#
# One explicit `Grid` holds the paired lengths. Treating the OHL and UGC
# lengths as independent grids would create an unphysical Cartesian product.
# A 100 m endpoint regularization avoids the singular zero-length line model;
# the labels retain the requested 0% and 100% values.

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
                earth_parameters = (1, 1, soil_resistivity))),
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
                earth_parameters = (1, 1, soil_resistivity)))
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
# Rewritten from `examples/Energy_hub_MTDC.jl:9`.
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

MMC1 = let model = mmc(; elec = electrical, meas = mmc_measurement, sync = sync,
    delta_control = pq_control, sigma_control = internal_control, modulation = modulation)
    b = bases(model)
    component(model; delta_control = (outer_active = (p_ref = (700/3) / b.S,),
            outer_reactive = (q_ref = (0) / b.S,),),
        powerflow = (; v_dc = (640) / b.v_dc,
            v_ac = (voltage * sqrt(2)) / b.v_ac,
            p_dc = model.powerflow.p_dc * b.S / b.S))
end;

MMC2 = let model = mmc(; elec = electrical, meas = mmc_measurement, sync = sync,
    delta_control = pq_control, sigma_control = internal_control, modulation = modulation)
    b = bases(model)
    component(model; delta_control = (outer_active = (p_ref = (-1400/3) / b.S,),
            outer_reactive = (q_ref = (0) / b.S,),),
        powerflow = (; v_dc = (640) / b.v_dc,
            v_ac = (voltage * sqrt(2)) / b.v_ac,
            p_dc = model.powerflow.p_dc * b.S / b.S))
end;

MMC3 = let model = mmc(; elec = electrical, meas = mmc_measurement, sync = sync,
    delta_control = vdc_control, sigma_control = internal_control, modulation = modulation)
    b = bases(model)
    component(model; delta_control = (outer_active = (v_dc_ref = (640) / b.v_dc,),
            outer_reactive = (q_ref = (0) / b.S,),),
        powerflow = (; p_ac = (1400/3) / b.S,
            v_ac = (voltage * sqrt(2)) / b.v_ac,
            p_dc = model.powerflow.p_dc * b.S / b.S))
end;

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
OWF = let model = tlc(; elec = wind_electrical, meas = wind_measurement, sync = wind_sync,
    outerActive = wind_power, outerReactive = wind_reactive, innerCurrent = wind_current,
    innerVoltage = NoInnerVoltageControl(), mod = NoModulation(), limits = wind_limits)
    b = bases(model)
    component(model; outerActive = (p_ref = (700) / b.S,),
        outerReactive = (q_ref = (-150) / b.S,),
        powerflow = (; v_dc = (640) / b.v_dc,
            v_ac = (voltage * sqrt(2)) / b.v_ac,
            p_dc = (0) / b.S))
end;

CableDC12 = cable(; length = 250e3, positions = [(-0.5, 1), (0.5, 1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3));

CableDC23 = cable(; length = 60e3, positions = [(-0.5, 1), (0.5, 1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3));

CableAC23 = cable(;
    length = 60e3, positions = [(0, 1.33562), (-0.0575, 1.4322), (0.0575, 1.4322)],
    C1 = Conductor(rₒ = 25.45e-3, ρ = 2.63e-8),
    I1 = Insulator(rᵢ = 25.45e-3, rₒ = 50.65e-3, a = 2e-3, b = 1.5e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 50.65e-3, rₒ = 52.35e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 52.35e-3, rₒ = 55.75e-3, ϵᵣ = 100),
    earth_parameters = (1, 1, 1));

CableAC24 = cable(;
    length = 10e3, positions = [(0, 1.33562), (-0.0575, 1.4322), (0.0575, 1.4322)],
    C1 = Conductor(rₒ = 25.45e-3, ρ = 2.63e-8),
    I1 = Insulator(rᵢ = 25.45e-3, rₒ = 50.65e-3, a = 2e-3, b = 1.5e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 50.65e-3, rₒ = 52.35e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 52.35e-3, rₒ = 55.75e-3, ϵᵣ = 100),
    earth_parameters = (1, 1, 1));

conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
    rᶜ = 0.015, yᵇᶜ = 30, Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10);
groundwires = Groundwires(
    nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10);

OHLAC01 = overhead_line(; length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));

OHLAC35 = overhead_line(; length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));

G1 = ac_source(v = voltage * sqrt(2));
Zg1 = impedance(; z = s -> 0.1 + 0.005s, conductors = 3);
G3 = ac_source(v = voltage * sqrt(2));
Zg3 = impedance(; z = s -> 0.1 + 0.005s, conductors = 3);

Q2 = impedance(; z = s -> 1 + compensation_inductance * s, conductors = 3);
Q3 = impedance(; z = s -> 1 + compensation_inductance * s, conductors = 3);
G_dc = dc_source(v = 640);
elements = (; MMC1, MMC2, MMC3, OWF, CableDC12, CableDC23, CableAC23, CableAC24,
    OHLAC01, OHLAC35, G1, G3, Zg1, Zg3, Q2, Q3, G_dc);

connections = (
    NetworkBuilder.Bus(:AC1; ports = ((:MMC1, :ac), (:OHLAC01, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:AC2;
        ports = ((:MMC2, :ac), (:CableAC23, :side1), (:CableAC24, :side1), (:Q2,
            :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:AC3;
        ports = ((:MMC3, :ac), (:CableAC23, :side2), (:OHLAC35, :side1), (:Q3, :side1)),
            domain = ACDQ),
    NetworkBuilder.Bus(:WindAC;
        ports = ((:OWF, :ac), (:CableAC24, :side2)), domain = ACDQ),
    NetworkBuilder.Bus(:Grid1;
        ports = ((:Zg1, :side2), (:OHLAC01, :side2)), domain = ACDQ),
    NetworkBuilder.Bus(:Grid3;
        ports = ((:Zg3, :side2), (:OHLAC35, :side2)), domain = ACDQ),
    NetworkBuilder.Bus(:Source1; ports = ((:G1, :ac), (:Zg1, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:Source3; ports = ((:G3, :ac), (:Zg3, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:gnd; ports = ((:Q2, :side2), (:Q3, :side2)), domain = ACDQ),
    NetworkBuilder.Bus(:DC1; ports = ((:MMC1, :dc), (:CableDC12, :side1))),
    NetworkBuilder.Bus(:DC2;
        ports = ((:MMC2, :dc), (:CableDC12, :side2), (:CableDC23, :side1))),
    NetworkBuilder.Bus(:DC3; ports = ((:MMC3, :dc), (:CableDC23, :side2))),
    NetworkBuilder.Bus(:WindDC; ports = ((:G_dc, :dc), (:OWF, :dc)))
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
# Rewritten from `examples/Converter_machine_interaction.jl:8`.
voltage = 380 / sqrt(3);

machine_electrical = ElectricalSM(Vᵃᶜ_base = 380, S_base = 1000, ωn = 100π,
    lt = 0.065, rt = 0.0026, La_d = 1.66, La_q = 1.61, Ll = 0.15, Ra = 0.0015);

machine_mechanical = MechanicalSM(
    H = 4, T_CH = 2, T_RH = 5, T_CO = 1, F_HP = 0.3, F_IP = 0.4, F_LP = 0.3);

machine_governor = GovernorSM(R = 0.05, T_w = 0.1, T_G = 0.2);

machine_avr = AVRSM(v_ref = 1.01, T_R = 0.05, T_B = 1, T_C = 0.1, T_A = 0.02, K_A = 200);

sg1 = let model = synchronousmachine(; elec = machine_electrical, mech = machine_mechanical,
    gov = machine_governor, avr = machine_avr)
    b = bases(model)
    component(model; powerflow = (p = 900 / b.S,
        q = -100 / b.S, v = voltage * sqrt(2) / b.v_ac))
end;
sg1 = component(sg1; limits = PowerImpedance.Limits(P_min = -2000,
    P_max = 2000, Q_min = -2000, Q_max = 2000));

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

c1 = let model = mmc(;
    elec = electrical, meas = measurement, sync = sync, delta_control = remote_control,
    sigma_control = internal_control, modulation = modulation, limits = remote_limits)
    b = bases(model)
    component(model; delta_control = (outer_active = (v_dc_ref = (800) / b.v_dc,),
            outer_reactive = (q_ref = (0) / b.S,),),
        powerflow = (; p_ac = (-600) / b.S,
            v_ac = (voltage * sqrt(2)) / b.v_ac,
            p_dc = model.powerflow.p_dc * b.S / b.S))
end;

c2 = let model = mmc(; elec = electrical, meas = measurement, sync = sync,
    delta_control = bus7_control,
    sigma_control = internal_control, modulation = modulation, limits = receiving_limits)
    b = bases(model)
    component(model; delta_control = (outer_active = (p_ref = (600) / b.S,),
            outer_reactive = (v_ac_ref = (voltage * sqrt(2)) / b.v_ac,),),
        powerflow = (; v_dc = (800) / b.v_dc,
            q_ac = (100) / b.S,
            p_dc = model.powerflow.p_dc * b.S / b.S))
end;

c3 = let model = mmc(;
    elec = electrical, meas = measurement, sync = sync, delta_control = remote_control,
    sigma_control = internal_control, modulation = modulation, limits = remote_limits)
    b = bases(model)
    component(model; delta_control = (outer_active = (v_dc_ref = (800) / b.v_dc,),
            outer_reactive = (q_ref = (0) / b.S,),),
        powerflow = (; p_ac = (-600) / b.S,
            v_ac = (voltage * sqrt(2)) / b.v_ac,
            p_dc = model.powerflow.p_dc * b.S / b.S))
end;

c4 = let model = mmc(; elec = electrical, meas = measurement, sync = sync,
    delta_control = bus5_control,
    sigma_control = internal_control, modulation = modulation, limits = receiving_limits)
    b = bases(model)
    component(model; delta_control = (outer_active = (p_ref = (600) / b.S,),
            outer_reactive = (q_ref = (100) / b.S,
                support = (v_ac_ref = (voltage * sqrt(2)) / b.v_ac,)),),
        powerflow = (; v_dc = (800) / b.v_dc,
            p_dc = model.powerflow.p_dc * b.S / b.S))
end;

conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,
    yᵇᶜ = 30, Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10);
groundwires = Groundwires(
    nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10);

tl89 = overhead_line(; length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));

tl75 = overhead_line(; length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));

tl96 = overhead_line(; length = 90e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));

tl54 = overhead_line(; length = 120e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));

tl64 = overhead_line(; length = 70e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));

tl1 = overhead_line(; length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));
tl2 = overhead_line(; length = 50e3, conductors = conductors, groundwires = groundwires,
    earth_parameters = (1, 1, 100));

tl78 = cable(; length = 30e3, positions = [(-0.5, 1.9), (0, 1.9), (0.5, 1.9)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8), I1 = Insulator(rᵢ = 24.25e-3,
        rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8), I2 = Insulator(
        rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10), I3 = Insulator(
        rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3),
    earth_parameters = (1, 1, 100));

dc_line = cable(; length = 100e3, positions = [(-0.5, 1), (0.5, 1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8), I1 = Insulator(rᵢ = 24.25e-3,
        rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8), I2 = Insulator(
        rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10), I3 = Insulator(
        rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3));

dc_line_2 = cable(; length = 50e3, positions = [(-0.5, 1), (0.5, 1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8), I1 = Insulator(rᵢ = 24.25e-3,
        rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8), I2 = Insulator(
        rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10), I3 = Insulator(
        rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3));

t3 = transformer(; n = 1, Lₚ = 0.0269/2, Lₛ = 0.0269/2, Rₚ = 0, Rₛ = 0,
    Cₜ = 7e-9, Cₛ = 12e-9, conductors = 3);

g3 = ac_source(v = voltage * sqrt(2));
g4 = ac_source(v = voltage * sqrt(2), p = 600);
g5 = ac_source(v = voltage * sqrt(2), p = 600);

l5 = impedance(; z = s -> 192.5 * 4.6s / (192.5 + 4.6s), conductors = 3);
l6 = impedance(; z = s -> 192.5 * 4.6s / (192.5 + 4.6s), conductors = 3);
l8 = impedance(; z = s -> 192.5 * 4.6s / (192.5 + 4.6s), conductors = 3);
elements = (; sg1, c1, c2, c3, c4, tl78, tl89, tl75, tl96, tl54, tl64, tl1, tl2,
    dc_line, dc_line_2, t3, g3, g4, g5, l5, l6, l8);

connections = (
    NetworkBuilder.Bus(:Bus4;
        ports = ((:sg1, :ac), (:tl64, :side1), (:tl54, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:Bus6;
        ports = ((:tl64, :side2), (:l6, :side1), (:tl96, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:Bus5;
        ports = ((:tl54, :side2), (:l5, :side1), (:tl75, :side1), (:c4, :ac)),
            domain = ACDQ),
    NetworkBuilder.Bus(:Bus9;
        ports = ((:tl96, :side2), (:tl89, :side1), (:t3, :side2)), domain = ACDQ),
    NetworkBuilder.Bus(:Bus7;
        ports = ((:tl75, :side2), (:tl78, :side1), (:c2, :ac)), domain = ACDQ),
    NetworkBuilder.Bus(:Bus8;
        ports = ((:tl78, :side2), (:tl89, :side2), (:l8, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:gnd;
        ports = ((:l5, :side2), (:l6, :side2), (:l8, :side2)), domain = ACDQ),
    NetworkBuilder.Bus(:Bus3; ports = ((:g3, :ac), (:t3, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:Remote1; ports = ((:c1, :ac), (:tl1, :side2)), domain = ACDQ),
    NetworkBuilder.Bus(:Source1; ports = ((:g4, :ac), (:tl1, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:Remote2; ports = ((:c3, :ac), (:tl2, :side2)), domain = ACDQ),
    NetworkBuilder.Bus(:Source2; ports = ((:g5, :ac), (:tl2, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:DC1; ports = ((:c1, :dc), (:dc_line, :side1))),
    NetworkBuilder.Bus(:DC2; ports = ((:c2, :dc), (:dc_line, :side2))),
    NetworkBuilder.Bus(:DC3; ports = ((:c3, :dc), (:dc_line_2, :side1))),
    NetworkBuilder.Bus(:DC4; ports = ((:c4, :dc), (:dc_line_2, :side2)))
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
# Rewritten from `examples/Connection_DSL.jl:192`.
delta_control = ΔdqControlGFL(
    outer_active = NoOuterActiveControl(),
    outer_reactive = NoOuterReactiveControl(),
    occ = NoInnerCurrentControl()
);

converter_elements = (
    dc_grid = dc_source(v = 480.0),
    ac_grid = ac_source(),
    mmc = mmc(;
        sync = NoSynchronization(),
        delta_control = delta_control,
        sigma_control = ΣdqzControlTEC()
    ),
    tlc = tlc(;),
    blackbox_converter = PowerImpedance.Blackbox_MMC()
);

converter_connections = (
    NetworkBuilder.Bus(:dc_bus;
        ports = ((:dc_grid, :dc), (:mmc, :dc), (:tlc, :dc), (:blackbox_converter, :dc))),
    NetworkBuilder.Bus(:ac_bus_;
        ports = ((:ac_grid, :ac), (:mmc, :ac), (:tlc, :ac), (:blackbox_converter, :ac)),
            domain = ACDQ)
);

build() = NetworkBuilder.define(converter_elements, converter_connections)

end

function replace_model(fixture, name; replacements...)
    model = fixture.elements[name]
    fields = merge(
        NamedTuple{fieldnames(typeof(model))}(
            Tuple(getfield(model, f) for f in fieldnames(typeof(model)))),
        (; replacements..., cache = PI.LinearizationCache()))
    replacement = Base.typename(typeof(model)).wrapper(values(fields)...)
    elements = merge(fixture.elements, NamedTuple{(name,)}((replacement,)))
    return NB.NetworkState(elements, fixture.topology, fixture.options)
end

function no_control()
    fixture = PSCADFixtures.mmc_pq_network()
    sigma = PI.ΣdqzControlTEC(tec = PI.NoTotalEnergyControl(),
        zscc = PI.NoZeroSequenceCurrentControl(),
        ccsc = PI.NoCirculatingCurrentSuppressionControl())
    return replace_model(fixture, :DUT; sigma_control = sigma)
end

function filter_fixture(kind)
    fixture = PSCADFixtures.mmc_pq_network()
    meas = fixture.elements.DUT.meas
    fields = NamedTuple{fieldnames(typeof(meas))}(
        Tuple(getfield(meas, f) for f in fieldnames(typeof(meas))))
    fields = merge(fields, (;
        v_dc = PI.MeasurementSignal(:v_dc,
        kind(order = 2, ωc = 100π))))
    return replace_model(fixture, :DUT; meas = PI.Measurement(values(fields)...))
end

function modulation_fixture(block)
    return replace_model(PSCADFixtures.tlc_case1_network(), :DUT; mod = block)
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
    source_nets = Set(row.net for row in rows if row.component in sources)
    nets = unique(row.net for row in rows if row.bus != 0 && row.net ∉ source_nets)
    if length(nets) > 12
        retained = Set(nets)
        nets = unique(row.net for row in rows if row.net in retained &&
                      row.component in active)
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

register(:im, () -> PSCADFixtures.im_network(),
    "test/pscad/fixtures.jl:im_network")
register(:small_ac, () -> PSCADFixtures.small_ac_network(),
    "test/pscad/fixtures.jl:small_ac_network")
register(:sm, () -> PSCADFixtures.sm_network(),
    "test/pscad/fixtures.jl:sm_network")
register(:passive_ohl, () -> PSCADFixtures.passive_ohl_network(),
    "test/pscad/fixtures.jl:passive_ohl_network")
register(:transformer_yy, () -> PSCADFixtures.transformer_network(),
    "test/pscad/fixtures.jl:transformer_network")
register(
    :transformer_dy, () -> PSCADFixtures.transformer_network(; organization = :ΔY),
    "test/pscad/fixtures.jl:transformer_network")
register(:dc, () -> PSCADFixtures.dc_network(),
    "test/pscad/fixtures.jl:dc_network")
register(:dc_cable, () -> PSCADFixtures.dc_cable_network(),
    "test/pscad/fixtures.jl:dc_cable_network")
register(:tlc_case1, () -> PSCADFixtures.tlc_case1_network(),
    "test/pscad/fixtures.jl:tlc_case1_network")
register(:tlc_case2, () -> PSCADFixtures.tlc_case2_network(),
    "test/pscad/fixtures.jl:tlc_case2_network")
register(:tlc_vac, () -> PSCADFixtures.tlc_vac_network(),
    "test/pscad/fixtures.jl:tlc_vac_network")
register(:mmc_pq, () -> PSCADFixtures.mmc_pq_network(),
    "test/pscad/fixtures.jl:mmc_pq_network")
register(:mmc_vdc, () -> PSCADFixtures.mmc_vdc_network(),
    "test/pscad/fixtures.jl:mmc_vdc_network")
register(:mmc_pf, () -> PSCADFixtures.mmc_pf_network(),
    "test/pscad/fixtures.jl:mmc_pf_network")
register(:mmc_qv, () -> PSCADFixtures.mmc_qv_network(),
    "test/pscad/fixtures.jl:mmc_qv_network")
register(:mmc_vac, () -> PSCADFixtures.mmc_vac_network(),
    "test/pscad/fixtures.jl:mmc_vac_network")
register(:mmc_gfm, () -> PSCADFixtures.mmc_gfm_network(),
    "test/pscad/fixtures.jl:mmc_gfm_network")
register(:mmc_compensated, () -> PSCADFixtures.mmc_compensated_network(),
    "test/pscad/fixtures.jl:mmc_compensated_network")
register(:mmc_no_control, no_control, "test/pscad/mmc_no_control_test.jl")
register(:mmc_energy, () -> PSCADFixtures.mmc_compensated_network(),
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
