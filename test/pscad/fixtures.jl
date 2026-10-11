module PSCADFixtures
using PowerImpedance

"""
    small_ac_network()

Return `(classic, state)` representations of the same balanced 50 Hz circuit:
a 380 kV line-to-line RMS source, a 0.19 Ω / 0.0122 H series branch and a
400 Ω per-phase shunt load. Both use a phase RMS voltage base of `380/sqrt(3)`
kV. Source setpoints are phase peak kV with zero cosine-reference angle.
"""
function small_ac_network()
    voltage = 380 / sqrt(3)
    elements = (;
        source = ac_source(; pins = 3, transformation = true,
            setpoint = Setpoint(Vac = voltage * sqrt(2), θac = 0.0)),
        line = impedance(; z = s -> 0.19 + s * 0.0122, pins = 3, transformation = true),
        load = impedance(; z = s -> 400.0, pins = 3, transformation = true))
    rows = [(node = Symbol(bus * suffix), element = name, side = side, terminal = terminal)
            for (name, side, bus) in ((:source, 1, "B1"), (:line, 1, "B1"),
        (:line, 2, "B2"), (:load, 1, "B2"))
            for (terminal, suffix) in enumerate(("d", "q"))]
    append!(rows, [(node = :gnd, element = :load, side = 2, terminal = terminal)
                   for terminal in 1:2])
    state = NetworkBuilder.define(deepcopy(elements), rows; options = (;
        voltageBase = voltage))
    classic = Network()
    classic.voltageBase[1] = voltage
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for terminal in 1:2
        connect!(classic, (:source, Symbol("2.$terminal")), :gnd)
    end
    connect!(classic)
    return (; classic, state)
end

"""
    sm_network()

Return classic and builder representations of `test/adm_SM_test.jl`:
a 900 MW synchronous machine at the shared 380 kV slack bus, with its
native rt/lt branch and default AVR, governor and steam turbine.
The machine's requested voltage is `1.000177992` pu before power flow.
"""
function sm_network()
    voltage = 380 / sqrt(3)
    elements = (;
        sg1 = synchronousmachine(;
            setpoint = Setpoint(Vac = 1.000177992 * voltage * sqrt(2), Pac = 900),
            elec = ElectricalSM(Vᵃᶜ_base = 380.0)),
        g2 = ac_source(; pins = 3, transformation = true,
            setpoint = Setpoint(Vac = voltage * sqrt(2))))
    rows = [(node = Symbol("Bus2" * suffix), element, side = 1, terminal)
            for element in (:sg1, :g2)
            for (terminal, suffix) in enumerate(("d", "q"))]
    state = NetworkBuilder.define(deepcopy(elements), rows;
        options = (; voltageBase = voltage))
    classic = Network()
    classic.voltageBase[1] = voltage
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for name in (:sg1, :g2), (terminal, suffix) in enumerate(("d", "q"))

        connect!(classic, (name, Symbol("2.$terminal")), Symbol("gnd" * suffix))
    end
    connect!(classic)
    return (; classic, state)
end

"""
    passive_ohl_network()

Return `(classic, state)` representations of the small AC fixture with the
25 km `tl1` overhead line from `examples/P2P_HVDC_ALT.jl` replacing the series
impedance. Both declare `voltageBase = 380/sqrt(3)` kV phase RMS.
"""
function passive_ohl_network()
    classic, state = small_ac_network()
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
        earth_parameters = (1, 1, 100), transformation = true)
    # Retain the fixture's designator and connectivity in both representations.
    # Each representation owns its element; solving classic may mutate setpoints.
    tl1.symbol = :line
    tl1.pins = copy(classic.elements[:line].pins)
    classic.elements[:line] = tl1
    elements = merge(state.elements, (; line = deepcopy(tl1)))
    rows = [(; row.node, row.element, row.side, row.terminal)
            for row in state.topology.connections]
    builder = NetworkBuilder.define(elements, rows;
        options = (; voltageBase = 380 / sqrt(3)))
    return (; classic, state = builder)
end

"""
    transformer_network(; organization = :YY, Rₘ = 1e6, Lₘ = 1000.0)

Return classic and builder circuits with a 380/150 kV LL transformer and a
400 Ω per-phase secondary load. Use the winding values from Transformer_test:
Rₚ = 10 Ω, Lₚ = 0.1 H, Rₛ = 1 Ω, Lₛ = 0.05 H. The default magnetizing branch
draws about 1 % of the load current; `Rₘ = 1e4, Lₘ = 10.0` reproduces the
Transformer_test stress values, whose large magnetizing current exposes the
power-flow pi-model approximation of the T-model.
Both representations declare 380/sqrt(3) kV phase RMS as the common base.
"""
function transformer_network(; organization = :YY, Rₘ = 1e6, Lₘ = 1000.0)
    classic, state = small_ac_network()
    winding = transformer(; pins = 3, transformation = true, organization,
        n = 380 / 150, Rₚ = 10.0, Lₚ = 0.1, Rₛ = 1.0, Lₛ = 0.05,
        Rₘ, Lₘ, Cₜ = 0.0, Cₛ = 0.0)
    winding.symbol = :line
    winding.pins = copy(classic.elements[:line].pins)
    classic.elements[:line] = winding
    elements = merge(state.elements, (; line = deepcopy(winding)))
    rows = [(; row.node, row.element, row.side, row.terminal)
            for row in state.topology.connections]
    builder = NetworkBuilder.define(elements, rows;
        options = (; voltageBase = 380 / sqrt(3)))
    return (; classic, state = builder)
end

"""
    dc_network()

Return classic and builder representations of two DC voltage sources at 320
and 318 kV pole-to-ground, joined by the differential series impedance
2 + s*0.05 Ω. The common base is 320 kV. An independent AC slack island
supports the classic power-flow solve; a 400 Ω AC shunt also makes that island
materializable by NetworkBuilder. Grounded DC shunts currently become
ordinary nonzero-voltage buses in that solver, so this fixture omits them.
"""
function dc_network()
    elements = (;
        ac = ac_source(; pins = 3, transformation = true,
            setpoint = Setpoint(Vac = 320sqrt(2), θac = 0.0)),
        from = dc_source(; setpoint = Setpoint(Vdc = 640.0)),
        to = dc_source(; setpoint = Setpoint(Vdc = 636.0)),
        line = impedance(; z = s -> 2.0 + s * 0.05, pins = 1),
        ac_load = impedance(; z = s -> 400.0, pins = 3, transformation = true))
    rows = [(node = Symbol("AC$k"), element, side = 1, terminal = k)
            for element in (:ac, :ac_load) for k in 1:2]
    append!(rows, [(node = :gnd, element = :ac_load, side = 2, terminal = k) for k in 1:2])
    for (element, side, node) in ((:from, 1, :D1), (:to, 1, :D2),
        (:line, 1, :D1), (:line, 2, :D2))
        push!(rows, (; node, element, side, terminal = 1))
    end
    state = NetworkBuilder.define(deepcopy(elements), rows; options = (;
        voltageBase = 320.0))
    classic = Network()
    classic.voltageBase[1] = 320.0
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for (name, count) in ((:ac, 2), (:from, 1), (:to, 1)), k in 1:count

        connect!(classic, (name, Symbol("2.$k")), :gnd)
    end
    connect!(classic)
    return (; classic, state)
end

"""
    dc_cable_network()

Return the M2 DC circuit with the two-position `ugc` cable from
`examples/P2P_HVDC_ALT.jl` as its 50 km DC branch. Layer and earth parameters
are copied from the example (rho = 100 Ω·m); both ends retain the transformed
differential terminal and grounded internal-conductor elimination.
"""
function dc_cable_network()
    classic, state = dc_network()
    ugc = cable(
        length = 50e3,
        positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
        I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
        C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
        I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
        C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
        I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
        earth_parameters = (1, 1, 100.0),
        transformation = true
    )
    ugc.symbol = :line
    ugc.pins = copy(classic.elements[:line].pins)
    classic.elements[:line] = ugc
    elements = merge(state.elements, (; line = deepcopy(ugc)))
    rows = [(; row.node, row.element, row.side, row.terminal)
            for row in state.topology.connections]
    builder = NetworkBuilder.define(elements, rows; options = state.options)
    return (; classic, state = builder)
end
"""
    tlc_case1_network()

Return classic and builder representations with the case-1 Vdc/Q controls
from `test/adm_TLC_test.jl`, 100 MVA / 220 kV AC / 640 kV pole-to-pole DC,
and the test's 10 km DC cable. Include the 0.5 s voltage-support lag.
"""
tlc_case1_network() = tlc_network(true)

"""
    tlc_case2_network()

Return the case-2 P/Q controllers with the 0.5 s frequency-support lag.
Use the same electrical data and 10 km DC cable as case 1, as required by
M4; the original case-2 admittance grid connects its DC source directly.
"""
tlc_case2_network() = tlc_network(false)

function tlc_vac_network()
    tlc_network(false,
        PowerImpedance.OuterReactiveVacControl(pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 100.0)))
end

function tlc_network(vdc_control, reactive = nothing)
    zbase = 220.0^2 / 100.0
    elec = PowerImpedance.ElectricalTLC(Lᵣ = 0.08zbase / (2π * 50), Rᵣ = 0.0008zbase,
        Sbase = 100.0, vACbase_LL_RMS = 220.0, vDCbase = 640.0)
    active = vdc_control ?
             PowerImpedance.OuterActiveVdcControl(pi_ctrl = PowerImpedance.PIControl(Kp = 5.0, Ki = 5.0)) :
             PowerImpedance.OuterActivePowerControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
        support = PowerImpedance.FrequencySupportLag(Kω = 5.0, ωc = 2.0))
    support = vdc_control ? PowerImpedance.VoltageSupportLag(K = 5.0, ωc = 2.0) :
              PowerImpedance.NoVoltageSupport()
    elements = (;
        DUT = tlc(elec = elec,
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
            innerCurrent = PowerImpedance.InnerCurrentPIControl(pi_ctrl = PowerImpedance.PIControl(
                Kp = 0.254647908947033, Ki = 0.8)),
            mod = PowerImpedance.PadeModulation(timeDelay = 200e-6, padeOrderNum = 3, padeOrderDen = 3),
            setpoint = Setpoint(
                Pac = 70.0, Qac = 20.0, Vac = 220sqrt(2 / 3), Pdc = 70.0, Vdc = 640.0),
            limits = vdc_control ?
                     PowerImpedance.Limits(P_min = -100.0, P_max = 100.0, Q_min = -50.0, Q_max = 50.0) :
                     PowerImpedance.Limits(P_min = -1000.0, P_max = 1000.0, Q_min = -1000.0, Q_max = 1000.0)),
        G3 = ac_source(pins = 3, transformation = true, setpoint = Setpoint(Vac = 220sqrt(2 /
                                                                                          3))),
        G_DC = dc_source(setpoint = Setpoint(Vdc = 640.0)),
        CableDC12 = cable(length = 10e3, positions = [(-0.5, 1.0), (0.5, 1.0)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10.0),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true))
    if reactive isa PowerImpedance.OuterReactiveVacControl
        # Give VAC its own voltage-controlled bus, as in the MMC VAC script.
        elements = merge(elements, (;
            Grid = impedance(z = s -> 0.1s, pins = 3, transformation = true)))
    end
    rows = [(node = Symbol("AC" * axis), element, side, terminal)
            for (element, side) in ((:DUT, 2), (:G3, 1))
            for (terminal, axis) in enumerate(("d", "q"))]
    if reactive isa PowerImpedance.OuterReactiveVacControl
        rows = [(; node = r.element == :G3 ? Symbol("Grid" * string(r.terminal)) : r.node,
                    r.element, r.side, r.terminal) for r in rows]
        append!(rows,
            [(node = Symbol("Grid" * string(t)), element = :Grid, side = 1, terminal = t)
             for t in 1:2])
        append!(rows,
            [(node = Symbol("AC" * axis), element = :Grid, side = 2, terminal = t)
             for (t, axis) in enumerate(("d", "q"))])
    end
    append!(rows,
        [(node = :DC1, element = :DUT, side = 1, terminal = 1),
            (node = :DC1, element = :CableDC12, side = 1, terminal = 1),
            (node = :DC2, element = :CableDC12, side = 2, terminal = 1),
            (node = :DC2, element = :G_DC, side = 1, terminal = 1)])
    state = NetworkBuilder.define(deepcopy(elements), rows; options = (;
        voltageBase = 220 / sqrt(3)))
    classic = Network()
    classic.voltageBase[1] = 220 / sqrt(3)
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for (element, count) in ((:G3, 2), (:G_DC, 1)), terminal in 1:count

        connect!(classic, (element, Symbol("2.$terminal")), :gnd)
    end
    connect!(classic)
    return (; classic, state)
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

function mmc_network(mode)
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
        DUT = mmc(
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
                occ = PI.InnerCurrentPIControl(pi_ctrl = PI.PIControl(Kp = 0.7691, Ki = 522.7654))),
            sigma_control = PI.ΣdqzControlTEC(
                tec = PI.TotalEnergyControl(pi_control = PI.PIControl(Kp = 1.386, Ki = 29.70)),
                zscc = PI.ZeroSequenceCurrentControl(PI.PIControl(Kp = 0.1048, Ki = 48.1914)),
                ccsc = PI.CirculatingCurrentSuppressionControl(PI.PIControl(Kp = 0.1048, Ki = 48.1914))),
            modulation = PI.UncompensatedModulation(),
            setpoint = Setpoint(Pac = 600.0, Qac = 200.0, Vac = 380sqrt(2 / 3),
                Vdc = 800.0, Pdc = 600.0),
            limits = PI.Limits(P_min = -1500.0, P_max = 1500.0, Q_min = -1000.0, Q_max = 1000.0)),
        G_AC = ac_source(pins = 3, transformation = true, setpoint = Setpoint(Vac = 380sqrt(2 /
                                                                                            3))),
        G_DC = dc_source(setpoint = Setpoint(Vdc = 800.0)))
    if mode in (:qv, :vac)
        # Q-V saved source R: Q-V_Droop/GFL_MMC_Validation.pscx:687–710.
        # VAC script's explicit grid reactor: VAC_Control/VAC_Control.jl:116.
        grid = mode == :qv ? impedance(z = s -> 0.01, pins = 3, transformation = true) :
               impedance(z = s -> 0.1s, pins = 3, transformation = true)
        elements = merge(elements, (; Grid = grid))
    elseif mode == :vdc
        # DVC saved project supplies current, not a stiff voltage (2565–2573).
        # Its Julia validation supplies that DC side with a remote PQ MMC and
        # 60 km cable: DC_Voltage_Control.jl:62–104,126–133.
        remote = deepcopy(mmc_pq_network().state.elements.DUT)
        remote.setpoint = Setpoint(Pac = -608.3578, Qac = -200.0,
            Vac = 380sqrt(2 / 3), Vdc = 800 * 1.00009, Pdc = -608.3578)
        dc_cable = cable(length = 60e3, positions = [(-0.5, 1.0), (0.5, 1.0)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10.0),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)
        elements = (; elements.DUT, elements.G_AC, SEND = remote,
            G_SEND = deepcopy(elements.G_AC), CableDC = dc_cable)
    end
    rows = [(node = Symbol("AC" * axis), element, side, terminal)
            for (element, side) in ((:DUT, 2), (:G_AC, 1))
            for (terminal, axis) in enumerate(("d", "q"))]
    if mode in (:qv, :vac)
        rows = [(;
                    node = r.element == :G_AC ? Symbol("Grid" * string(r.terminal)) :
                           r.node,
                    r.element, r.side, r.terminal) for r in rows]
        append!(rows,
            [(node = Symbol("Grid" * string(t)), element = :Grid, side = 1, terminal = t)
             for t in 1:2])
        append!(rows,
            [(node = Symbol("AC" * axis), element = :Grid, side = 2, terminal = t)
             for (t, axis) in enumerate(("d", "q"))])
    end
    if mode == :vdc
        append!(rows,
            [(node = Symbol("Send" * axis), element, side, terminal)
             for (element, side) in ((:SEND, 2), (:G_SEND, 1))
             for (terminal, axis) in enumerate(("d", "q"))])
        append!(rows,
            [(node = :DC, element = :DUT, side = 1, terminal = 1),
                (node = :DC, element = :CableDC, side = 2, terminal = 1),
                (node = :DC_SEND, element = :SEND, side = 1, terminal = 1),
                (node = :DC_SEND, element = :CableDC, side = 1, terminal = 1)])
    else
        append!(rows, [(node = :DC, element, side = 1, terminal = 1)
                       for element in (:DUT, :G_DC)])
    end
    state = NetworkBuilder.define(deepcopy(elements), rows; options = (;
        voltageBase = voltage))
    classic = Network()
    classic.voltageBase[1] = voltage
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    sources = mode == :vdc ? ((:G_AC, 2), (:G_SEND, 2)) : ((:G_AC, 2), (:G_DC, 1))
    for (element, count) in sources, terminal in 1:count

        connect!(classic, (element, Symbol("2.$terminal")), :gnd)
    end
    connect!(classic)
    return (; classic, state)
end

# Current modular GFM fixture: test/adm_MMC_test.jl:58–193, build_mmc_grid().
# Saved PSCAD primitives are cited in fixtures/mmc_gfm_saved_fragments.xml.
function mmc_gfm_network()
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

    setpoint = PowerImpedance.Setpoint(
        Pac = Pmmc,
        Qac = Qmmc,
        θac = 0.0,
        Vac = Vm * sqrt(2),
        Pdc = Pmmc,
        Vdc = Vdc,
    )

    limits = PowerImpedance.Limits(
        P_min = -1500.0,
        P_max = 1500.0,
        Q_min = -1000.0,
        Q_max = 1000.0,
    )

    elements = (;
        DUT = mmc(elec = elec, meas = meas, sync = synch,
            delta_control = delta_control, sigma_control = sigma_control,
            modulation = mod, setpoint = setpoint, limits = limits),
        G3 = ac_source(pins = 3, transformation = true,
            setpoint = Setpoint(Vac = Vm * sqrt(2))),
        G_DC = dc_source(setpoint = Setpoint(Vdc = Vdc)))
    rows = [(node = Symbol("AC" * axis), element, side, terminal)
            for (element, side) in ((:DUT, 2), (:G3, 1))
            for (terminal, axis) in enumerate(("d", "q"))]
    append!(rows, [(node = :DC, element, side = 1, terminal = 1)
                  for element in (:DUT, :G_DC)])
    state = NetworkBuilder.define(deepcopy(elements), rows; options = (; voltageBase = Vm))
    classic = Network()
    classic.voltageBase[1] = Vm
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for (element, count) in ((:G3, 2), (:G_DC, 1)), terminal in 1:count
        connect!(classic, (element, Symbol("2.$terminal")), :gnd)
    end
    connect!(classic)
    return (; classic, state)
end


# test/adm_MMC_compensated_test.jl:53–190, build_mmc_grid().
"""
    mmc_compensated_network()

Return `(classic, state)` representations of the compensated MMC validation
network with its original Δ-energy PI gains `Kp=0.5544`, `Ki=5.94` (`k=1`).
The plant is rated 1060 MVA, 320/400 kV line-to-line RMS and 640 kV DC.

With the corrected +3ωbase triplen notch/PI frame, the former
`+0.115752 ± j942.538554` \\[s⁻¹\\] pair becomes
`-12.550944 ± j940.716108` \\[s⁻¹\\]. Apart from the deliberately slow
stable OCC filter poles, the least-damped pair is
`-4.873459 ± j10.339475` \\[s⁻¹\\]. No gain scaling is applied.
"""
function mmc_compensated_network()
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

    setpoint = PowerImpedance.Setpoint(
        Pac = Pmmc,
        Qac = Qmmc,
        θac = 0.0,
        Vac = Vm * sqrt(2),
        Pdc = Pmmc,
        Vdc = Vdc,
    )

    limits = PowerImpedance.Limits(
        P_min = -1500.0,
        P_max = 1500.0,
        Q_min = -1000.0,
        Q_max = 1000.0,
    )

    elements = (;
        DUT = mmc(elec = elec, meas = meas, sync = synch,
            delta_control = delta_control, sigma_control = sigma_control,
            modulation = mod, setpoint = setpoint, limits = limits),
        G3 = ac_source(pins = 3, transformation = true,
            setpoint = Setpoint(Vac = Vm * sqrt(2))),
        G_DC = dc_source(setpoint = Setpoint(Vdc = Vdc)))
    rows = [(node = Symbol("AC" * axis), element, side, terminal)
            for (element, side) in ((:DUT, 2), (:G3, 1))
            for (terminal, axis) in enumerate(("d", "q"))]
    append!(rows, [(node = :DC, element, side = 1, terminal = 1)
                  for element in (:DUT, :G_DC)])
    state = NetworkBuilder.define(deepcopy(elements), rows; options = (; voltageBase = Vm))
    classic = Network()
    classic.voltageBase[1] = Vm
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for (element, count) in ((:G3, 2), (:G_DC, 1)), terminal in 1:count
        connect!(classic, (element, Symbol("2.$terminal")), :gnd)
    end
    connect!(classic)
    return (; classic, state)
end

end
