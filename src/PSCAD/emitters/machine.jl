"""
Conversion from normalized AVR output to PSCAD's open-circuit Ef base.
Julia's field voltage is `v_df = K_A*y*Rf_d/La_d`; its open-circuit terminal
voltage is `La_d*v_df/Rf_d`, so PSCAD receives `Ef = K_A*y`. With saturation
disabled, the settled station Ef equals Ef0 and satisfies the AVR equation.
"""
const SM_AVR_FIELD_VOLTAGE_SCALE = 1.0

"""
PSCAD terminal iron-loss resistance \\[pu\\] for Julia's machine without a
core-loss branch. PSCAD's default 300 pu shunt dissipates `V^2/Ri`, or
3.33 MW at 1 pu on a 1000 MVA base; 1e6 pu reduces this to 0.001 MW.
In the classic fixture's 10 µs, 15 s station run, changing Ri to 1e6 pu
raised internal terminal P from 895.45 MW to 898.778 MW, confirming the loss.
"""
const SM_IRON_LOSS_RESISTANCE_PU = 1.0e6

function machine_avr(name, machine, voltage_pu)
    a = machine.avr
    parameters = ModuleParameterPlan[
        ModuleParameterPlan("vref", a.vref_SG, ""),
        ModuleParameterPlan("T_R", a.T_R, "s"),
        ModuleParameterPlan("T_B", a.T_B, "s"),
        ModuleParameterPlan("T_C", a.T_C, "s"),
        ModuleParameterPlan("T_A", a.T_A, "s"),
        ModuleParameterPlan("K_A", a.K_A, ""),
        ModuleParameterPlan("Vt0", voltage_pu, ""),
        ModuleParameterPlan("Verror0", a.vref_SG - voltage_pu, ""),
        ModuleParameterPlan("Vreg0", a.K_A * (a.vref_SG - voltage_pu), ""),
        ModuleParameterPlan("Ef_scale", SM_AVR_FIELD_VOLTAGE_SCALE, "")]
    vt, vf, ref, error, lead, regulator, ef = Signal.([
        "Vt", "v_f", "vref_signal", "voltage_error", "lead_output", "regulator", "Ef"])
    graph = BlockGraph(ControlBlock[
        Import("Vt", vt), RealPole(vt, vf, 1.0, "T_R", "Vt0"),
        Import("vref", ref), Sum([ref, vf], [1, -1], error),
        LeadLag(error, lead, "T_C", "T_B", "Verror0"),
        RealPole(lead, regulator, "K_A", "T_A", "Vreg0"),
        # Open-circuit Ef normalization removes Julia's Rf_d/La_d factor.
        Gain(regulator, ef, "Ef_scale"), Export("Ef", ef)])
    ports = [ModulePortPlan("Vt", :input, -54, 0),
        ModulePortPlan("Ef", :output, 54, 0)]
    return ModuleDefinitionPlan(name, parameters, ports, lower!(CanvasPlan(), graph))
end

function machine_governor(name, machine, torque_pu)
    g, m = machine.gov, machine.mech
    parameters = ModuleParameterPlan[
        ModuleParameterPlan("T_w", g.T_w, "s"),
        ModuleParameterPlan("T_G", g.T_G, "s"),
        ModuleParameterPlan("R", g.R, ""),
        ModuleParameterPlan("inv_R", 1 / g.R, ""),
        ModuleParameterPlan("T_CH", m.T_CH, "s"),
        ModuleParameterPlan("T_RH", m.T_RH, "s"),
        ModuleParameterPlan("T_CO", m.T_CO, "s"),
        ModuleParameterPlan("F_HP", m.F_HP, ""),
        ModuleParameterPlan("F_IP", m.F_IP, ""),
        ModuleParameterPlan("F_LP", m.F_LP, ""),
        ModuleParameterPlan("Tm0", torque_pu, "")]
    speed, one, dw, filtered, droop, tm0, demand, flow, hp, ip, lp, thp, tip, tlp,
    tm = Signal.(["speed", "one", "speed_error", "dw_filtered", "droop", "torque_ref",
        "valve_demand", "flow", "hp", "ip", "lp", "T_HP", "T_IP", "T_LP", "Tm"])
    graph = BlockGraph(ControlBlock[
        Import("speed", speed), Const(one, 1.0), Sum([one, speed], [1, -1], dw),
        RealPole(dw, filtered, 1.0, "T_w", 0.0), Gain(filtered, droop, "inv_R"),
        Import("Tm0", tm0), Sum([droop, tm0], [1, 1], demand),
        RealPole(demand, flow, 1.0, "T_G", "Tm0"),
        RealPole(flow, hp, 1.0, "T_CH", "Tm0"),
        RealPole(hp, ip, 1.0, "T_RH", "Tm0"),
        RealPole(ip, lp, 1.0, "T_CO", "Tm0"),
        Gain(hp, thp, "F_HP"), Gain(ip, tip, "F_IP"), Gain(lp, tlp, "F_LP"),
        Sum([thp, tip, tlp], [1, 1, 1], tm), Export("Tm", tm)])
    ports = [ModulePortPlan("speed", :input, -54, 0),
        ModulePortPlan("Tm", :output, 54, 0)]
    return ModuleDefinitionPlan(name, parameters, ports, lower!(CanvasPlan(), graph))
end

function machine_module!(state, definition, context, input, output)
    push!(state.modules, definition)
    x, y = allocate_cell!(state.layout)
    point = (x + 144, y + 108)
    params = [p.name => block_value(p.default; unit = isempty(p.unit) ? nothing : p.unit)
              for p in definition.parameters]
    push!(state.main.components, ModuleInstancePlan(
        context.name * ":" * definition.name, params, point..., 0))
    signal_stub!(state.main, (point[1] - 54, point[2]), input)
    signal_stub!(state.main, (point[1] + 54, point[2]), output; direction = -1)
    return nothing
end

function machine_probe!(state, e, bus, kind, suffix, unit)
    name = pscad_name(e.pscad * "_" * suffix; used = state.used)
    push!(state.channels, ProbeChannel(name, kind, bus.name, string(e.name), "1", 1, unit))
    return Signal(name)
end

function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.SynchronousMachine}, context)
    connected = filter(t -> !t.grounded, e.terminals)
    length(connected) == 1 ||
        throw(ArgumentError("machine :$(e.name) requires one connected AC terminal"))
    terminal = only(connected)
    bus = _ac_bus(e, terminal, context)
    machine = e.model
    elec = machine.elec
    isapprox(elec.ωn, 2π * context.settings.frequency; rtol = 1e-12) ||
        throw(ArgumentError("machine :$(e.name) frequency differs from the network frame"))
    flow = get(context.netlist.operating_point.branch_flows, e.name, nothing)
    flow !== nothing && haskey(flow, :terminal_voltage_kV) ||
        throw(ArgumentError("machine :$(e.name) requires solved terminal operating-point data"))
    voltage_pu = flow.terminal_voltage_kV * sqrt(3) / elec.Vᵃᶜ_base
    torque_pu = e.setpoint.Pac / elec.S_base
    s2m, l2n, time = Signal.([pscad_name(e.pscad * suffix; used = state.used)
                              for suffix in ("_S2M", "_L2N", "_time")])
    speed = machine_probe!(state, e, bus, :machine_speed, "speed", "pu")
    vt = machine_probe!(state, e, bus, :machine_voltage, "Vt", "pu")
    p = machine_probe!(state, e, bus, :machine_p, "P", "MW")
    q = machine_probe!(state, e, bus, :machine_q, "Q", "MVAR")
    ef0 = machine_probe!(state, e, bus, :machine_diagnostic, "Ef0", "pu")
    ef = machine_probe!(state, e, bus, :machine_diagnostic, "Ef", "pu")
    tm_init = machine_probe!(state, e, bus, :machine_diagnostic, "Tm_init", "pu")
    tm = Signal(pscad_name(e.pscad * "_Tm"; used = state.used))
    p_pu, q_pu = Signal.([pscad_name(e.pscad * suffix; used = state.used)
                          for suffix in ("_P_pu", "_Q_pu")])

    x, y = allocate_cell!(state.layout)
    point = (x + 144, y + 108)
    params = ["Name" => e.pscad, "Cnfg" => "1", "Nqaxw" => "2",
        "View" => "1", "Neut" => "0", "MM" => "1", "MSat" => "0",
        "IorMVA" => "1", "VolTyp" => "1", "icTyp" => "1", "Ospd" => "1",
        "MVA" => pscad_value(elec.S_base; unit = "MVA"),
        "VbaseLL" => pscad_value(elec.Vᵃᶜ_base; unit = "kV"),
        "OMO" => pscad_value(elec.ωn; unit = "rad/s"),
        "H" => pscad_value(machine.mech.H; unit = "s"), "D" => "0.0 [pu]",
        "Ri" => pscad_value(SM_IRON_LOSS_RESISTANCE_PU; unit = "pu"),
        "VT" => pscad_value(voltage_pu; unit = "pu"),
        "Pheta" => pscad_value(flow.terminal_angle_rad + π / 2; unit = "rad"),
        "P0" => pscad_value(flow.pg; unit = "MW"),
        "Q0" => pscad_value(flow.qg; unit = "MVAR"),
        "Trmpv" => "0.01 [s]", "Sysfl" => "15.0 [pu]", "Ptcon" => "0.05 [s]",
        "Icsp" => "0", "Icmp" => "0", "Igov" => "1", "Iexc" => "1",
        "Term" => "1", "Ts" => "0.0 [s]", "machsw" => s2m.name, "Enab" => l2n.name,
        "InGov" => pscad_name(e.pscad * "_InitGv"; used = state.used),
        "InExc" => pscad_name(e.pscad * "_InitEx"; used = state.used),
        "POut" => p_pu.name, "QOut" => q_pu.name, "PQscl" => "0"]
    append!(params, [key => pscad_value(value; unit = "pu")
                     for (key, value) in sm_equivalent_circuit(elec)])
    component!(state.main, "sync_machine", point, params)
    inner = pscad_name(e.pscad * "_terminal"; used = state.used)
    stub!(state.main, (point[1] + 36, point[2]), inner)
    for (dx, dy, signal, direction) in ((-36, -72, ef, -1), (0, 72, tm, 1),
        (-36, 72, speed, 1), (36, -72, vt, -1), (-72, -72, ef0, -1),
        (36, 72, tm_init, 1))
        signal_stub!(state.main, (point[1] + dx, point[2] + dy), signal; direction)
    end

    # rt/lt is a Y-equivalent branch at the same voltage level, as in Julia.
    x, y = allocate_cell!(state.layout)
    start = (x + 90, y + 72)
    stub!(state.main, start, inner; direction = -1)
    zbase = elec.Vᵃᶜ_base^2 / elec.S_base
    parts = Tuple{String, String, Float64, String}[]
    for (defn, parameter, value, unit) in (("resistor", "R", elec.rt * zbase, "ohm"),
        ("inductor", "L", elec.lt * zbase / elec.ωn, "H"))
        value >= 0 || throw(ArgumentError("machine :$(e.name) has negative rt/lt"))
        iszero(value) || push!(parts, (defn, parameter, value, unit))
    end
    endpoint = component_chain!(state.main, parts, start, e.pscad * "_stepup", state.used)
    current = current_probe!(state, e, terminal, context)
    ammeter_stub!(state.main, endpoint, bus.name, current)
    output_probe!(state.main, current, "branch", "kA", (x + 144, y + 144))

    x, y = allocate_cell!(state.layout)
    lower!(state.main,
        BlockGraph(ControlBlock[
            TimeStep(time), Compare(time, s2m, 0.5), Compare(time, l2n, 1.0)]);
        origin = (x + 126, y + 54))
    avr_name = pscad_name("AVR_" * e.pscad; used = state.used)
    gov_name = pscad_name("GOV_" * e.pscad; used = state.used)
    machine_module!(state, machine_avr(avr_name, machine, voltage_pu), context, vt, ef)
    machine_module!(
        state, machine_governor(gov_name, machine, torque_pu), context, speed, tm)

    x, y = allocate_cell!(state.layout)
    lower!(state.main,
        BlockGraph(ControlBlock[
            Gain(p_pu, p, elec.S_base), Gain(q_pu, q, elec.S_base)]);
        origin = (x + 126, y + 54))
    for signal in (p, q, vt, speed, ef0, ef, tm_init)
        x, y = allocate_cell!(state.layout)
        channel = only(filter(c -> c.name == signal.name, state.channels))
        output_probe!(state.main, signal.name, "machine", channel.unit, (x + 126, y + 72))
    end
    return nothing
end
