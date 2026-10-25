module PSCADFixtures
using PowerImpedance
include("ieee9_network.jl")

# The 220 kV case from adm_IM_test.jl, with independent elements in each representation.
function _im_circuit(; elec = ElectricalIM(r_s = 0.01),
        mech = MechanicalIM(T_0 = 0.9, A = 0.0, B = 0.0, C = 1.0, m = 0))
    voltage = 220 / sqrt(3)
    elements = (;
        g1 = ac_source(v = voltage * sqrt(2), theta = 0.0, p = -500),
        im1 = inductionmachine(; elec, mech),
        imp = impedance(; z = 0.01, conductors = 3))
    rows = [NetworkBuilder.Bus(Symbol(name); ports = ((element, port),), domain = ACDQ)
            for (element, port, name) in ((:im1, :ac, "machine_"),
                (:imp, :side1, "machine_"), (:imp, :side2, "grid_"),
                (:g1, :ac, "grid_"))]
    return (; elements, rows, options = (;
        voltageBase = voltage, power_flow = (; is_bounded = (; bus_voltage = true))))
end

function _small_ac_circuit()
    voltage = 380 / sqrt(3)
    elements = (;
        source = ac_source(v = voltage * sqrt(2), theta = 0.0),
        line = impedance(; z = s -> 0.19 + s * 0.0122, conductors = 3),
        load = impedance(; z = s -> 400.0, conductors = 3))
    rows = (
        NetworkBuilder.Bus(:B1; ports = ((:source, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:B1; ports = ((:line, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:B2; ports = ((:line, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:B2; ports = ((:load, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:load, :side2),), domain = ACDQ))
    return (; elements, rows, options = (;
        voltageBase = voltage))
end

function _sm_circuit()
    voltage = 380 / sqrt(3)
    elements = (;
        sg1 = let model = synchronousmachine(;
            elec = ElectricalSM(Vᵃᶜ_base = 380.0))
            b = bases(model)
            component(model; powerflow = (p = 900 / b.S,
                q = model.powerflow.q * b.S / b.S,
                    v = 1.000177992 * voltage * sqrt(2) / b.v_ac))
        end,
        g2 = ac_source(v = voltage * sqrt(2)))
    rows = [NetworkBuilder.Bus(:Bus2; ports = ((element, :ac),), domain = ACDQ)
            for element in (:sg1, :g2)]
    return (; elements, rows, options = (; voltageBase = voltage))
end

function _passive_ohl_circuit()
    circuit = _small_ac_circuit()
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
        earth_parameters = (1, 1, 100))
    elements = merge(circuit.elements, (; line = tl1))
    return (; elements, circuit.rows, circuit.options)
end

function _transformer_circuit(; organization = :YY, Rₘ = 1e6, Lₘ = 1000.0)
    circuit = _small_ac_circuit()
    winding = transformer(; conductors = 3, organization,
        n = 380 / 150, Rₚ = 10.0, Lₚ = 0.1, Rₛ = 1.0, Lₛ = 0.05,
        Rₘ, Lₘ, Cₜ = 0.0, Cₛ = 0.0)
    elements = merge(circuit.elements, (; line = winding))
    return (; elements, circuit.rows, circuit.options)
end

function _dc_circuit()
    elements = (;
        ac = ac_source(v = 320sqrt(2), theta = 0.0),
        from = dc_source(v = 640.0),
        to = dc_source(v = 636.0),
        line = impedance(; z = s -> 2.0 + s * 0.05, conductors = 1),
        ac_load = impedance(; z = s -> 400.0, conductors = 3))
    rows = (
        NetworkBuilder.Bus(:AC; ports = ((:ac, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:AC; ports = ((:ac_load, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:ac_load, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:D1; ports = ((:from, :dc),)),
        NetworkBuilder.Bus(:D2; ports = ((:to, :dc),)),
        NetworkBuilder.Bus(:D1; ports = ((:line, :side1),)),
        NetworkBuilder.Bus(:D2; ports = ((:line, :side2),)))
    return (; elements, rows, options = (;
        voltageBase = 320.0))
end

function _dc_cable_circuit()
    circuit = _dc_circuit()
    ugc = cable(;
        length = 50e3,
        positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
        I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
        C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
        I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
        C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
        I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
        earth_parameters = (1, 1, 100.0))
    elements = merge(circuit.elements, (; line = ugc))
    return (; elements, circuit.rows, circuit.options)
end
"""
    tlc_case1_network()

Return a network state with the case-1 Vdc/Q controls from
`test/adm_TLC_test.jl`. Ratings are 100 \\[MVA\\], 220 \\[kV\\] AC and
640 \\[kV\\] pole-to-pole DC, with a 10 \\[km\\] cable and 0.5 \\[s\\]
voltage-support lag.

# Returns

- Network state with the stated circuit.
"""
tlc_case1_network() = tlc_network(true)

"""
    tlc_case2_network()

Return a network state with case-2 P/Q controls and a
0.5 \\[s\\] frequency-support lag. Use the case-1 electrical data and
10 \\[km\\] cable to keep converter-mode comparisons on the same circuit.
The case-2 admittance circuit in `test/adm_TLC_test.jl` connects its DC source directly.

# Returns

- Network state with the stated circuit.
"""
tlc_case2_network() = tlc_network(false)

function tlc_vac_network()
    tlc_network(false,
        PowerImpedance.OuterReactiveVacControl(
            pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 100.0)))
end

function _tlc_circuit(vdc_control, reactive = nothing)
    zbase = 220.0^2 / 100.0
    elec = PowerImpedance.ElectricalTLC(Lᵣ = 0.08zbase / (2π * 50), Rᵣ = 0.0008zbase,
        Sbase = 100.0, vACbase_LL_RMS = 220.0, vDCbase = 640.0)
    active = vdc_control ?
             PowerImpedance.OuterActiveVdcControl(
                 pi_ctrl = PowerImpedance.PIControl(Kp = 5.0, Ki = 5.0)) :
             PowerImpedance.OuterActivePowerControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
        support = PowerImpedance.FrequencySupportLag(Kω = 5.0, ωc = 2.0))
    support = vdc_control ? PowerImpedance.VoltageSupportLag(K = 5.0, ωc = 2.0) :
              PowerImpedance.NoVoltageSupport()
    elements = (;
        DUT = let model = tlc(; elec = elec,
            meas = PowerImpedance.Measurement(
                v_ac = PowerImpedance.Butterworth(order = 2, ωc = 5000.0),
                i_ac = PowerImpedance.Butterworth(order = 2, ωc = 5000.0)),
            sync = PowerImpedance.PLLSynchronization(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.397887357729738,
                    Ki = 7.957747154594767),
                filter = PowerImpedance.Butterworth(order = 2, ωc = 2π * 80)),
            outerActive = active,
            outerReactive = isnothing(reactive) ?
                            PowerImpedance.OuterReactiveQControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
                support = support) : reactive,
            innerVoltage = PowerImpedance.NoInnerVoltageControl(),
            innerCurrent = PowerImpedance.InnerCurrentPIControl(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.254647908947033, Ki = 0.8)),
            mod = PowerImpedance.PadeModulation(timeDelay = 200e-6, padeOrderNum = 3,
                padeOrderDen = 3),
            limits = vdc_control ?
                     PowerImpedance.Limits(P_min = -100.0, P_max = 100.0, Q_min = -50.0,
                         Q_max = 50.0) :
                     PowerImpedance.Limits(P_min = -1000.0, P_max = 1000.0,
                         Q_min = -1000.0, Q_max = 1000.0))
            b = bases(model)
            active_inputs = vdc_control ?
                (; v_dc_ref = (640.0) / b.v_dc) : (; p_ref = (70.0) / b.S)
            active_seeds = vdc_control ?
                (; p_ac = (70.0) / b.S) : (; v_dc = (640.0) / b.v_dc)
            reactive_inputs = reactive isa PowerImpedance.OuterReactiveVacControl ?
                (; v_ac_ref = (220sqrt(2 / 3)) / b.v_ac) :
                vdc_control ? (; q_ref = (20.0) / b.S,
                    support = (v_ac_ref = (220sqrt(2 / 3)) / b.v_ac,)) :
                (; q_ref = (20.0) / b.S)
            reactive_seeds = reactive isa PowerImpedance.OuterReactiveVacControl ?
                (; q_ac = (20.0) / b.S) : vdc_control ? (;) :
                (; v_ac = (220sqrt(2 / 3)) / b.v_ac)
            component(model; outerActive = active_inputs,
                outerReactive = reactive_inputs,
                powerflow = (; active_seeds...,
                    reactive_seeds...,
                    p_dc = (70.0) / b.S))
        end,
        G3 = ac_source(v = 220sqrt(2 / 3)),
        G_DC = dc_source(v = 640.0),
        CableDC12 = cable(; length = 10e3, positions = [(-0.5, 1.0), (0.5, 1.0)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10.0),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3)))
    if reactive isa PowerImpedance.OuterReactiveVacControl
        # Give VAC its own voltage-controlled bus, as in the MMC VAC script.
        elements = merge(elements, (;
            Grid = impedance(; z = s -> 0.1s, conductors = 3)))
    end
    rows = NetworkBuilder.Bus[
        NetworkBuilder.Bus(:AC; ports = ((:DUT, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(reactive isa PowerImpedance.OuterReactiveVacControl ?
            :Grid : :AC; ports = ((:G3, :ac),), domain = ACDQ)]
    if reactive isa PowerImpedance.OuterReactiveVacControl
        append!(rows, (
            NetworkBuilder.Bus(:Grid; ports = ((:Grid, :side1),), domain = ACDQ),
            NetworkBuilder.Bus(:AC; ports = ((:Grid, :side2),), domain = ACDQ)))
    end
    append!(rows, (
        NetworkBuilder.Bus(:DC1; ports = ((:DUT, :dc), (:CableDC12, :side1))),
        NetworkBuilder.Bus(:DC2; ports = ((:CableDC12, :side2), (:G_DC, :dc)))))
    return (; elements, rows, options = (;
        voltageBase = 220 / sqrt(3)))
end

# Electrical and Δ/CCSC gains: local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx:621–644.
# TEC gains: test/adm_MMC_test.jl:108–110; no saved PQ counterpart exists.
# ZSCC uses the saved CCSC gains. 31_10.jl supplies no optional filter or delay.
# Its ideal AC source and PQ control omit the saved source R and voltage droop.
mmc_pq_network() = mmc_network(:pq)
mmc_vdc_network() = mmc_network(:vdc)
mmc_pf_network() = mmc_network(:pf)
mmc_qv_network() = mmc_network(:qv)
mmc_vac_network() = mmc_network(:vac)

function _mmc_circuit(mode)
    PI = PowerImpedance
    voltage = 380 / sqrt(3)
    zbase = 333.0^2 / 1000.0
    active = mode == :vdc ?
             PI.OuterActiveVdcControl(pi_ctrl = PI.PIControl(Kp = 5.0, Ki = 15.0)) :
             PI.OuterActivePowerControl(pi_ctrl = PI.PIControl(Kp = 0.1, Ki = 31.4159),
        support = mode == :pf ? PI.FrequencySupportLag(Kω = 5.0, ωc = 2.0) :
                  PI.NoFrequencySupport())
    reactive = mode == :vac ?
               PI.OuterReactiveVacControl(pi_ctrl = PI.PIControl(Kp = 0.0, Ki = 100.0)) :
               PI.OuterReactiveQControl(pi_ctrl = PI.PIControl(Kp = 0.1, Ki = 31.4159),
        support = mode == :qv ? PI.VoltageSupportLag(K = 20.0, ωc = 100.0) :
                  PI.NoVoltageSupport())
    elements = (;
        DUT = let model = mmc(;
            elec = PI.ElectricalMMC(Lₐᵣₘ = 50e-3, Rₐᵣₘ = 1.07,
                Cₐᵣₘ = 10e-3, N = 400, turnsRatio = 333 / 380,
                Lᵣ = 0.1305zbase / (100π), Rᵣ = 0.0037zbase,
                vACbase_LL_RMS = 333.0, Sbase = 1000.0, vDC_base = 800.0),
            meas = PI.Measurement(),
            sync = PI.PLLSynchronization(pi_ctrl = PI.PIControl(Kp = 0.28, Ki = 12.5664),
                filter = PI.NoFilter()),
            delta_control = PI.ΔdqControlGFL(
                outer_active = active,
                outer_reactive = reactive,
                occ = PI.InnerCurrentPIControl(pi_ctrl = PI.PIControl(Kp = 0.7691,
                    Ki = 522.7654))),
            sigma_control = PI.ΣdqzControlTEC(
                tec = PI.TotalEnergyControl(pi_control = PI.PIControl(Kp = 1.386,
                    Ki = 29.70)),
                zscc = PI.ZeroSequenceCurrentControl(PI.PIControl(Kp = 0.1048,
                    Ki = 48.1914)),
                ccsc = PI.CirculatingCurrentSuppressionControl(PI.PIControl(Kp = 0.1048,
                    Ki = 48.1914))),
            modulation = PI.UncompensatedModulation(),
            limits = PI.Limits(P_min = -1500.0, P_max = 1500.0, Q_min = -1000.0,
                Q_max = 1000.0))
            b = bases(model)
            active_inputs = mode == :vdc ?
                (; v_dc_ref = (800.0) / b.v_dc) : (; p_ref = (600.0) / b.S)
            active_seeds = mode == :vdc ?
                (; p_ac = (600.0) / b.S) : (; v_dc = (800.0) / b.v_dc)
            reactive_inputs = mode == :vac ?
                (; v_ac_ref = (380sqrt(2 / 3)) / b.v_ac) :
                mode == :qv ? (; q_ref = (200.0) / b.S,
                    support = (v_ac_ref = (380sqrt(2 / 3)) / b.v_ac,)) :
                (; q_ref = (200.0) / b.S)
            reactive_seeds = mode == :vac ?
                (; q_ac = (200.0) / b.S) : mode == :qv ? (;) :
                (; v_ac = (380sqrt(2 / 3)) / b.v_ac)
            component(model; delta_control = (outer_active = active_inputs,
                    outer_reactive = reactive_inputs,),
                powerflow = (; active_seeds...,
                    reactive_seeds...,
                    p_dc = (600.0) / b.S))
        end,
        G_AC = ac_source(v = 380sqrt(2 / 3)),
        G_DC = dc_source(v = 800.0))
    if mode in (:qv, :vac)
        # Q-V saved source R: Q-V_Droop/GFL_MMC_Validation.pscx:687–710.
        # VAC script's explicit grid reactor: VAC_Control/VAC_Control.jl:116.
        grid = mode == :qv ? impedance(; z = s -> 0.01, conductors = 3) :
               impedance(; z = s -> 0.1s, conductors = 3)
        elements = merge(elements, (; Grid = grid))
    elseif mode == :vdc
        # DVC saved project supplies current, not a stiff voltage (2565–2573).
        # Its Julia validation supplies that DC side with a remote PQ MMC and
        # 60 km cable: DC_Voltage_Control.jl:62–104,126–133.
        remote = deepcopy(_mmc_circuit(:pq).elements.DUT)
        b = bases(remote)
        remote = component(remote;
            delta_control = (outer_active = (p_ref = (-608.3578) / b.S,),
                outer_reactive = (q_ref = (-200.0) / b.S,),),
            powerflow = (; v_dc = (800 * 1.00009) / b.v_dc,
                v_ac = (380sqrt(2 / 3)) / b.v_ac,
                p_dc = (-608.3578) / b.S))
        dc_cable = cable(; length = 60e3, positions = [(-0.5, 1.0), (0.5, 1.0)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10.0),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3))
        elements = (; elements.DUT, elements.G_AC, SEND = remote,
            G_SEND = deepcopy(elements.G_AC), CableDC = dc_cable)
    end
    rows = NetworkBuilder.Bus[
        NetworkBuilder.Bus(:AC; ports = ((:DUT, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(mode in (:qv, :vac) ? :Grid : :AC;
            ports = ((:G_AC, :ac),), domain = ACDQ)]
    if mode in (:qv, :vac)
        append!(rows, (
            NetworkBuilder.Bus(:Grid; ports = ((:Grid, :side1),), domain = ACDQ),
            NetworkBuilder.Bus(:AC; ports = ((:Grid, :side2),), domain = ACDQ)))
    end
    if mode == :vdc
        append!(rows, (
            NetworkBuilder.Bus(:Send; ports = ((:SEND, :ac),), domain = ACDQ),
            NetworkBuilder.Bus(:Send; ports = ((:G_SEND, :ac),), domain = ACDQ),
            NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc), (:CableDC, :side2))),
            NetworkBuilder.Bus(:DC_SEND; ports = ((:SEND, :dc), (:CableDC, :side1)))))
    else
        push!(rows, NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc), (:G_DC, :dc))))
    end
    return (; elements, rows, options = (;
        voltageBase = voltage))
end

# Modular GFM fixture: test/adm_MMC_test.jl:58–193, build_mmc_grid(). Saved PSCAD
# primitives are cited in fixtures/mmc_gfm_saved_fragments.xml.
function _mmc_gfm_circuit()
    Pmmc, Qmmc = 0.7 * 1060, 0.0
    Vm, Vdc = 400 / sqrt(3), 640.0
    elec = PowerImpedance.ElectricalMMC(
        vDC_base = 640.0,
        Sbase = 1060.0,
        vACbase_LL_RMS = 320.0,
        turnsRatio = 320 / 400,
        Lᵣ = 0.18 * (320^2 / 1060) / (2π * 50),
        Rᵣ = 0.001 * (320^2 / 1060),
        Rₐᵣₘ = 0.4,
        Lₐᵣₘ = 46.125e-3,
        Cₐᵣₘ = 11.3867e-3,
        N = 400,
    )

    meas = PowerImpedance.Measurement(
        P_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
        Q_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
    )

    pll = PowerImpedance.PLLSynchronization(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.28,
            Ki = 12.5664,
        ),
        filter = PowerImpedance.Butterworth(order = 1, ωc = 75 * 2π),
    )

    synch = PowerImpedance.VSEWithDamping(
        H = 5.0,
        K_d = 100.0,
        K_ω = 10.0,
        pll = pll,
    )

    outerReactive = PowerImpedance.OuterReactiveQControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 30.0),
    )

    innerVoltage = PowerImpedance.CCVI(
        R_v = 0.01,
        L_v = 0.25,
        V_d_ref = 1.0,
        V_q_ref = 0.0,
        filter = PowerImpedance.Butterworth(order = 2, ωc = 200.0),
    )

    innerCurrent = PowerImpedance.InnerCurrentPIControl(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.6787,
            Ki = 292.2087,
        ),
        filter = PowerImpedance.Butterworth(order = 1, ωc = 0.0001 * 2π),
    )

    delta_control = PowerImpedance.ΔdqControlGFM(
        outer_reactive = outerReactive,
        vi = innerVoltage,
        occ = innerCurrent,
    )

    energy = PowerImpedance.TotalEnergyControl(
        pi_control = PowerImpedance.PIControl(Kp = 1.386, Ki = 29.70),
    )

    zeroCurrent = PowerImpedance.ZeroSequenceCurrentControl(
        PowerImpedance.PIControl(Kp = 0.0992, Ki = 42.9719),
    )

    circulatingCurrent = PowerImpedance.CirculatingCurrentSuppressionControl(
        PowerImpedance.PIControl(Kp = 0.0992, Ki = 42.9719),
    )

    sigma_control = PowerImpedance.ΣdqzControlTEC(
        tec = energy,
        zscc = zeroCurrent,
        ccsc = circulatingCurrent,
    )

    mod = PowerImpedance.UncompensatedModulation(
        timeDelay = 200e-6,
        padeOrderNum = 5,
        padeOrderDen = 5,
    )


    limits = PowerImpedance.Limits(
        P_min = -1500.0,
        P_max = 1500.0,
        Q_min = -1000.0,
        Q_max = 1000.0,
    )

    elements = (;
        DUT = let model = mmc(; elec = elec, meas = meas, sync = synch,
            delta_control = delta_control, sigma_control = sigma_control,
            modulation = mod, limits = limits)
            b = bases(model)
            component(model; sync = (p_ref = (Pmmc) / b.S,),
                delta_control = (outer_reactive = (q_ref = (Qmmc) / b.S,),),
                powerflow = (; v_dc = (Vdc) / b.v_dc,
                    v_ac = (Vm * sqrt(2)) / b.v_ac,
                    p_dc = (Pmmc) / b.S))
        end,
        G3 = ac_source(v = Vm * sqrt(2)),
        G_DC = dc_source(v = Vdc))
    rows = (
        NetworkBuilder.Bus(:AC; ports = ((:DUT, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:AC; ports = ((:G3, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc), (:G_DC, :dc))))
    return (; elements, rows, options = (; voltageBase = Vm))
end


# test/adm_MMC_compensated_test.jl:53–190, build_mmc_grid().
function _mmc_compensated_circuit()
    Pmmc, Qmmc = 0.7 * 1060, 0.0
    Vm, Vdc = 400 / sqrt(3), 640.0
    elec = PowerImpedance.ElectricalMMC(
        vDC_base = 640.0,
        Sbase = 1060.0,
        vACbase_LL_RMS = 320.0,
        turnsRatio = 320 / 400,
        Lᵣ = 0.18 * (320^2 / 1060) / (2π * 50),
        Rᵣ = 0.001 * (320^2 / 1060),
        Rₐᵣₘ = 0.4,
        Lₐᵣₘ = 46.125e-3,
        Cₐᵣₘ = 11.3867e-3,
        N = 400,
    )

    meas = PowerImpedance.Measurement(
        P_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
        Q_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
    )

    pll = PowerImpedance.PLLSynchronization(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.28,
            Ki = 12.5664,
        ),
        filter = PowerImpedance.Butterworth(order = 1, ωc = 75 * 2π),
    )

    synch = PowerImpedance.VSEWithDamping(
        H = 5.0,
        K_d = 100.0,
        K_ω = 10.0,
        pll = pll,
    )

    outerReactive = PowerImpedance.OuterReactiveQControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 30.0),
    )

    innerVoltage = PowerImpedance.CCVI(
        R_v = 0.01,
        L_v = 0.25,
        V_d_ref = 1.0,
        V_q_ref = 0.0,
        filter = PowerImpedance.Butterworth(order = 2, ωc = 200.0),
    )

    innerCurrent = PowerImpedance.InnerCurrentPIControl(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.6787,
            Ki = 292.2087,
        ),
        filter = PowerImpedance.Butterworth(order = 1, ωc = 0.0001 * 2π),
    )

    delta_control = PowerImpedance.ΔdqControlGFM(
        outer_reactive = outerReactive,
        vi = innerVoltage,
        occ = innerCurrent,
    )

    wsigma = PowerImpedance.ΣEnergyControl(
        pi_control = PowerImpedance.PIControl(Kp = 0.4 * 1.386, Ki = 0.2 * 29.70))
    wdelta = PowerImpedance.ΔEnergyControl(
        pi_control = PowerImpedance.PIControl(Kp = 0.4 * 1.386, Ki = 0.2 * 29.70))
    ccc = PowerImpedance.CirculatingCurrentControl(
        PowerImpedance.PIControl(Kp = 0.0992, Ki = 42.9719))
    sigma_control = PowerImpedance.ΣdqzControlLEC(; wsigma, wdelta, ccc)
    mod = PowerImpedance.CompensatedModulation(
        timeDelay = 200e-6, padeOrderNum = 5, padeOrderDen = 5)


    limits = PowerImpedance.Limits(
        P_min = -1500.0,
        P_max = 1500.0,
        Q_min = -1000.0,
        Q_max = 1000.0,
    )

    elements = (;
        DUT = let model = mmc(; elec = elec, meas = meas, sync = synch,
            delta_control = delta_control, sigma_control = sigma_control,
            modulation = mod, limits = limits)
            b = bases(model)
            component(model; sync = (p_ref = (Pmmc) / b.S,),
                delta_control = (outer_reactive = (q_ref = (Qmmc) / b.S,),),
                powerflow = (; v_dc = (Vdc) / b.v_dc,
                    v_ac = (Vm * sqrt(2)) / b.v_ac,
                    p_dc = (Pmmc) / b.S))
        end,
        G3 = ac_source(v = Vm * sqrt(2)),
        G_DC = dc_source(v = Vdc))
    rows = (
        NetworkBuilder.Bus(:AC; ports = ((:DUT, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:AC; ports = ((:G3, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc), (:G_DC, :dc))))
    return (; elements, rows, options = (; voltageBase = Vm))
end

function im_network(; elec = ElectricalIM(r_s = 0.01),
        mech = MechanicalIM(T_0 = 0.9, A = 0.0, B = 0.0, C = 1.0, m = 0))
    (; elements, rows, options) = _im_circuit(; elec, mech)
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

"""
    small_ac_network()

Return a network state for a balanced circuit at 50 \\[Hz\\].
The source is 380 \\[kV\\] line-to-line RMS, the series branch is 0.19 \\[Ω\\]
with 0.0122 \\[H\\], and the shunt load is 400 \\[Ω\\] per phase.
Source setpoints use phase-peak voltage with zero cosine-reference angle.

# Returns

- Network state with the stated circuit and voltage base.
"""
function small_ac_network()
    (; elements, rows, options) = _small_ac_circuit()
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

"""
    sm_network()

Return a network state for the circuit in `test/adm_SM_test.jl`.
The synchronous machine supplies 900 \\[MW\\] at a 380 \\[kV\\] slack bus,
with the native `rt`/`lt` branch and default AVR, governor and steam turbine.
Its requested voltage is 1.000177992 \\[pu\\] before power flow.

# Returns

- Network state with the stated circuit.
"""
function sm_network()
    (; elements, rows, options) = _sm_circuit()
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

"""
    passive_ohl_network()

Return the small AC circuit with the `tl1` overhead line from
`examples/P2P_HVDC_ALT.jl` replacing its series impedance.

# Returns

- Network state with the stated circuit and voltage base.
"""
function passive_ohl_network()
    (; elements, rows, options) = _passive_ohl_circuit()
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

"""
    transformer_network(; organization = :YY, Rₘ = 1e6, Lₘ = 1000.0)

Return a network state with a 380/150 \\[kV\\] line-to-line
transformer and a 400 \\[Ω\\] per-phase secondary load.

# Arguments

- `organization`: Winding connection. Default: `:YY`.
- `Rₘ`: Primary magnetizing resistance \\[Ω\\]. Default: `1e6`.
- `Lₘ`: Primary magnetizing inductance \\[H\\]. Default: `1000.0`.

# Returns

- Network state with the stated circuit and voltage base.

# Notes

Winding values from `Transformer_test.jl` are `Rₚ = 10` \\[Ω\\],
`Lₚ = 0.1` \\[H\\], `Rₛ = 1` \\[Ω\\] and `Lₛ = 0.05` \\[H\\].
The default magnetizing current is about 1% of load current. Values
`Rₘ = 1e4` \\[Ω\\] and `Lₘ = 10` \\[H\\] reproduce the stress case,
whose magnetizing current exposes the power-flow pi approximation of the T-model.
"""
function transformer_network(; organization = :YY, Rₘ = 1e6, Lₘ = 1000.0)
    (; elements, rows, options) = _transformer_circuit(; organization, Rₘ, Lₘ)
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

"""
    dc_network()

Return a network state for a DC circuit with sources at
320 and 318 \\[kV\\] pole-to-ground and a differential series branch
with resistance 2 \\[Ω\\] and inductance 0.05 \\[H\\].

# Returns

- Network state with the stated circuit and voltage base.

# Notes

An independent AC slack island supports power flow; a 400 \\[Ω\\] AC shunt
permits builder reconstruction. Grounded DC shunts become nonzero-voltage
buses in this solver and are omitted from the fixture.
"""
function dc_network()
    (; elements, rows, options) = _dc_circuit()
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

"""
    dc_cable_network()

Return the DC circuit with the two-position `ugc` cable from
`examples/P2P_HVDC_ALT.jl` as its 50 \\[km\\] branch. Cable-layer data and
earth resistivity 100 \\[Ω·m\\] come from that example.
Both ends use the differential transform and grounded internal-conductor elimination.

# Returns

- Network state with the stated circuit.
"""
function dc_cable_network()
    (; elements, rows, options) = _dc_cable_circuit()
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

function tlc_network(vdc_control, reactive = nothing)
    (; elements, rows, options) = _tlc_circuit(vdc_control, reactive)
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

function mmc_network(mode)
    (; elements, rows, options) = _mmc_circuit(mode)
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

function mmc_gfm_network()
    (; elements, rows, options) = _mmc_gfm_circuit()
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

"""
    mmc_compensated_network()

Return a network state for the compensated MMC circuit.
The Δ-energy PI gains are `Kp = 0.5544`, `Ki = 5.94` with `k = 1`.
Plant ratings are 1060 \\[MVA\\], 320/400 \\[kV\\] line-to-line RMS and
640 \\[kV\\] DC.

# Returns

- Network state with the stated circuit.

# Notes

The +3ωbase triplen notch/PI frame gives poles
``-12.550944 ± j940.716108`` \\[s⁻¹\\]. Excluding slow stable OCC filter poles,
the least-damped pair is ``-4.873459 ± j10.339475`` \\[s⁻¹\\] without gain scaling.
The opposite triplen rotation gives ``+0.115752 ± j942.538554`` \\[s⁻¹\\].
"""
function mmc_compensated_network()
    (; elements, rows, options) = _mmc_compensated_circuit()
    return NetworkBuilder.define(deepcopy(elements), rows; options)
end

end
