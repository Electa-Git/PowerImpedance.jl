function converter_rotation!(graph, d, q, angle, out_d, out_q, stem, inverse)
    c, s, dc, qs, ds, qc = Signal.([stem * suffix
                                    for suffix in ("c", "s", "dc", "qs", "ds", "qc")])
    append!(graph.nodes,
        ControlBlock[Trig(angle, c, :cos), Trig(angle, s, :sin),
            Mult(d, c, dc), Mult(q, s, qs), Mult(d, s, ds), Mult(q, c, qc),
            Sum([dc, qs], [1, inverse ? 1 : -1], out_d),
            Sum([ds, qc], [inverse ? -1 : 1, 1], out_q)])
    return nothing
end

function tlc_modulation(name, e, equilibrium, transforms, settings)
    m = e.model
    parameters = ModuleParameterPlan[]
    inputs = [(n, 1) for n in ("vM_d_ref", "vM_q_ref", "v_dc_f", "theta_rel", "v_dc")]
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for (n, _) in inputs])
    append!(graph.nodes,
        ControlBlock[Const(Signal("two"), 2.0),
            Div(Signal("two"), Signal("v_dc_f"), Signal("factor")),
            Mult(Signal("factor"), Signal("vM_d_ref"), Signal("md_c")),
            Mult(Signal("factor"), Signal("vM_q_ref"), Signal("mq_c"))])
    converter_rotation!(graph, Signal("md_c"), Signal("mq_c"), Signal("theta_rel"),
        Signal("md_g"), Signal("mq_g"), "grid", true)
    if m.mod isa PowerImpedance.DelayModulation
        delay = m.mod.delay
        (iszero(delay.timeDelay) || delay.padeOrderNum == delay.padeOrderDen == 3) ||
            not_exportable(e, m.mod)
        residual = _converter_export_delay(delay.timeDelay, settings.time_step; converter = e.name)
        # Carrier rotation and initial history use the residual delay because
        # the acquired electrical signal already includes one step of delay.
        initial = PowerImpedance.phase_compensated_dq(
            [equilibrium.outputs.mod.m_d, equilibrium.outputs.mod.m_q],
            -m.elec.ωbase * residual)
        if !iszero(residual)
            t = converter_parameter!(parameters, "Td", residual, "s")
        end
        for (i, axis) in enumerate(("d", "q"))
            raw, delayed = Signal("m" * axis * "_g"), Signal("m" * axis * "_delay")
            if iszero(residual)
                push!(graph.nodes, Gain(raw, delayed, 1.0))
            else
                x0 = converter_parameter!(parameters, axis * "Delay0", initial[i])
                push!(graph.nodes, Delay(raw, delayed, t,
                    ceil(Int, residual / settings.time_step) + 1, x0))
            end
        end
        converter_parameter!(parameters, "compensation", m.elec.ωbase * residual)
        push!(graph.nodes, Import("compensation", Signal("compensation")))
        converter_rotation!(
            graph, Signal("md_delay"), Signal("mq_delay"), Signal("compensation"),
            Signal("md"), Signal("mq"), "comp", false)
    elseif m.mod isa PowerImpedance.NoModulation
        append!(graph.nodes,
            ControlBlock[Gain(Signal("md_g"), Signal("md"), 1.0),
                Gain(Signal("mq_g"), Signal("mq"), 1.0)])
    else
        not_exportable(e, m.mod)
    end
    w = converter_parameter!(parameters, "wbase", m.elec.ωbase)
    # The controlled source requires physical phase voltage in kV, whereas
    # modulation uses the AC peak-voltage base.
    scale = converter_parameter!(parameters, "voltage_scale", m.elec.vACbase /
                                                              (2m.elec.vDCbase))
    append!(graph.nodes,
        ControlBlock[
            TimeStep(Signal("mod_clock_s")), Gain(Signal("mod_clock_s"), Signal("theta_nom"), w),
            ArrayMerge(Signal.(["md", "mq"]), Signal("m_dq")),
            DqToAbc(Signal("m_dq"), Signal("theta_nom"), Signal("m_abc"), transforms.dq),
            Gain(Signal("v_dc"), Signal("v_dc_scale"), scale)])
    for i in 1:3
        append!(graph.nodes,
            ControlBlock[ArraySplit(Signal("m_abc"), Signal("m$i"), i),
                Mult(Signal("m$i"), Signal("v_dc_scale"), Signal("vM$i"))])
    end
    append!(graph.nodes,
        ControlBlock[ArrayMerge(Signal.(["vM1", "vM2", "vM3"]), Signal("vM_abc")),
            Export("vM_abc", Signal("vM_abc"))])
    return converter_definition(name, parameters, graph, inputs, [("vM_abc", 3)])
end

function module_signal_stub!(canvas, point, signal, direction)
    endpoint = (point[1] + 36direction, point[2])
    wire!(canvas, point, endpoint)
    component!(canvas, "datalabel", endpoint, ["Name" => signal])
    return nothing
end

function converter_instance!(canvas, definition, project, point, signals = (;))
    params = [p.name => block_value(p.default; unit = isempty(p.unit) ? nothing : p.unit)
              for p in definition.parameters]
    push!(canvas.components, ModuleInstancePlan(project * ":" * definition.name, params, point..., 0))
    for port in definition.ports
        port.kind == :electrical && continue
        module_signal_stub!(canvas, (point[1] + port.x, point[2] + port.y),
            get(signals, Symbol(port.name), port.name),
            port.kind == :input ? -1 : 1)
    end
    return nothing
end

function tlc_electrical_canvas(e)
    canvas = CanvasPlan()
    si = tlc_si(e.model.elec)
    si.R_r >= 0 && si.L_r > 0 ||
        throw(ArgumentError("converter :$(e.name) requires R_r >= 0 and L_r > 0"))
    # Ground the negative terminal of each controlled phase-voltage source
    # to preserve the common midpoint and phase-voltage polarity.
    graph = BlockGraph()
    for (i, y) in enumerate((108, 216, 324))
        voltage = Signal("vM$i")
        current = Signal("i$i")
        power = Signal("p$i")
        append!(graph.nodes,
            ControlBlock[ArraySplit(Signal("vM_abc"), voltage, i),
                ArraySplit(Signal("i_abc"), current, i), Mult(voltage, current, power)])
        params = ["Name" => "phase$i", "Type" => "6", "Grnd" => "1", "Spec" => "0",
            "Cntrl" => "1", "AC" => "0", "Tc" => "0.0 [s]"]
        push!(canvas.components, ComponentPlan("master:source_1", params, 180, y, 4))
        module_signal_stub!(canvas, (180, y + 36), voltage.name, -1)
        source_node = pscad_name("phase$(i)_source"; used = canvas.used)
        phase_node = pscad_name("phase$(i)_terminal"; used = canvas.used)
        stub!(canvas, (216, y), source_node)
        endpoint = component_chain!(canvas,
            [("resistor", "R", si.R_r, "ohm"), ("inductor", "L", si.L_r, "H")],
            (324, y), "phase$i", canvas.used)
        stub!(canvas, (324, y), source_node; direction = -1)
        stub!(canvas, endpoint, phase_node)
        stub!(canvas, (576, 216 + 36 * (i - 2)), phase_node; direction = -1)
    end
    push!(canvas.components, ComponentPlan(
        "master:breakout", ["Dis" => "0", "Com" => "0"], 612, 216, 4))
    ac_inner = pscad_name("ac_stage"; used = canvas.used)
    ac_terminal = pscad_name("ac_terminal"; used = canvas.used)
    stub!(canvas, (612, 216), ac_inner)
    component!(canvas, "ammeter", (720, 216), ["Name" => "i_abc"])
    stub!(canvas, (720, 216), ac_inner; direction = -1)
    stub!(canvas, (756, 216), ac_terminal)
    component!(canvas, "xnode", (900, 216), ["Name" => "AC"])
    stub!(canvas, (900, 216), ac_terminal; direction = -1)
    component!(canvas, "voltmetergnd", (900, 288), ["Name" => "v_abc"])
    stub!(canvas, (900, 288), ac_terminal; direction = -1)
    # The DC circuit omits auxiliary capacitors because the TLC electrical
    # model contains no DC capacitance.
    push!(canvas.components,
        ComponentPlan("master:src_ccin_1",
            ["Name" => "dc_injection", "Cntrl" => "1", "Tc" => "0.0 [s]"], 1260, 180, 1))
    dc_positive = pscad_name("dc_positive"; used = canvas.used)
    dc_negative = pscad_name("dc_negative"; used = canvas.used)
    for (y, node) in ((180, dc_positive), (216, dc_negative))
        stub!(canvas, (1260, y), node)
        stub!(canvas, (1440, y), node; direction = -1)
        component!(canvas, "xnode", (1620, y), ["Name" => y == 180 ? "DC_P" : "DC_N"])
        stub!(canvas, (1620, y), node; direction = -1)
    end
    component!(canvas, "voltmeter", (1440, 180), ["Name" => "v_dc_m"])
    # The nominal pole-to-pole voltage protects startup divisions until 0.2 s.
    # The selector then supplies measured Vdc to modulation, measurement
    # normalization and the DC-current calculation.
    clock = Signal("dc_start_clock_s")
    lower!(canvas, TimeStep(clock), (756, 360))
    lower!(
        canvas, _ConverterStartupHold(
            clock, Signal("v_dc_m"), Signal("v_dc"), si.vDC_base), (936, 324))
    module_signal_stub!(canvas, (1224, 180), "i_dc_cmd", -1)
    append!(graph.nodes,
        ControlBlock[Sum(Signal.(["p1", "p2", "p3"]), [1, 1, 1], Signal("p_dc")),
            Div(Signal("p_dc"), Signal("v_dc"), Signal("i_dc_absorbed")),
            # A positive source command injects current out of terminal A, whereas
            # ElectricalTLC i_dc is positive for DC power absorption.
            Gain(Signal("i_dc_absorbed"), Signal("i_dc_cmd"), -1.0)])
    controls = lower!(CanvasPlan(), graph)
    append!(canvas.components,
        [ComponentPlan(c.defn, c.params, c.x, c.y + 432, c.orient)
         for c in controls.components])
    append!(canvas.wires, [WirePlan([(x, y + 432) for (x, y) in w.vertices])
                           for w in controls.wires])
    return canvas
end

function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.TLC}, context)
    connected = filter(t -> !t.grounded, e.terminals)
    length(connected) == 2 && any(t -> t.side == 1 && t.bus.domain == 2, connected) &&
    any(t -> t.side == 2 && t.bus.domain == 1, connected) ||
        throw(ArgumentError("converter :$(e.name) requires DC side 1 and AC side 2"))
    dc, ac = only(filter(t -> t.side == 1, connected)),
    only(filter(t -> t.side == 2, connected))
    bus = _ac_bus(e, ac, context)
    _terminal_bus(e, dc, context)
    m = e.model
    isapprox(m.elec.ωbase, 2π * context.settings.frequency; rtol = 1e-12) ||
        throw(ArgumentError("converter :$(e.name) frequency differs from the network frame"))
    haskey(context.netlist.operating_point.branch_flows, e.name) ||
        throw(ArgumentError("converter :$(e.name) requires solved operating-point data"))
    equilibrium = converter_equilibrium(e)
    transforms = context.converter_transforms
    names = [pscad_name(prefix * "_" * e.pscad; used = state.used)
             for prefix in ("MEAS", "PLL",
        m.outerActive isa PowerImpedance.OuterActiveVdcControl ? "VDCCTRL" : "PCTRL",
        "QCTRL", "OCC", "MOD")]
    definitions = [converter_measurements(names[1], e, equilibrium, transforms),
        converter_pll(names[2], e, equilibrium), converter_active(names[3], e, equilibrium, m.outerActive),
        converter_reactive(names[4], e, equilibrium), converter_occ(names[5], e, equilibrium),
        tlc_modulation(names[6], e, equilibrium, transforms, context.settings)]
    append!(state.modules, definitions)
    canvas = tlc_electrical_canvas(e)
    converter_angle_snapshot!(canvas, e, equilibrium; origin = (2160, 1512))
    for (i, definition) in enumerate(definitions)
        converter_instance!(canvas, definition, context.name,
            (2160 + 432 * ((i - 1) ÷ 3), 108 + 432 * ((i - 1) % 3)),
            i == 2 ? (; theta_c = "theta_next", theta_rel = "theta_rel_next") : (;))
    end
    outputs = ("P_ac_f", "Q_ac_f", "v_dc_f", "omega_c", "theta_c")
    diagnostics = lower!(CanvasPlan(), BlockGraph(ControlBlock[Export(n, Signal(n))
                                                               for n in outputs]))
    append!(canvas.components,
        [ComponentPlan(c.defn, c.params, c.x + 3024, c.y, c.orient)
         for c in diagnostics.components])
    append!(canvas.wires, [WirePlan([(x + 3024, y) for (x, y) in w.vertices])
                           for w in diagnostics.wires])
    ports = [ModulePortPlan("AC", :electrical, 54, 0, 3),
        ModulePortPlan("DC_P", :electrical, -54, 0), ModulePortPlan("DC_N", :electrical, -54, 36)]
    append!(ports, [ModulePortPlan(n, :output, 54, 72 + 36 * (i - 1))
                    for (i, n) in enumerate(outputs)])
    name = pscad_name("VSC_" * e.pscad; used = state.used)
    definition = ModuleDefinitionPlan(name, ModuleParameterPlan[], ports, canvas)
    push!(state.modules, definition)
    x, y = allocate_cell!(state.layout)
    state.layout.next += 6 # The output ports need more vertical space than an ordinary control block.
    point = (x + 144, y + 108)
    push!(state.main.components,
        ModuleInstancePlan(context.name * ":" * name, Pair{String, String}[], point..., 0))
    ac_current = current_probe!(state, e, ac, context; orientation = :out)
    ammeter_stub!(state.main, (point[1] + 54, point[2]), only(_terminal_labels(e, ac, context)), ac_current)
    dc_current = current_probe!(state, e, dc, context; orientation = :into)
    positive, negative = _terminal_labels(e, dc, context)
    ammeter_stub!(
        state.main, (point[1] - 54, point[2]), positive, dc_current; direction = -1)
    stub!(state.main, (point[1] - 54, point[2] + 36), negative; direction = -1)
    for (i, signal) in enumerate(outputs)
        probe = pscad_name(e.pscad * "_" * signal; used = state.used)
        kind = signal == "P_ac_f" ? :converter_p :
               signal == "Q_ac_f" ? :converter_q : :converter_diagnostic
        unit = signal == "theta_c" ? "rad" : "pu"
        push!(state.channels, ProbeChannel(
            probe, kind, bus.name, string(e.name), "2", 1, unit))
        module_signal_stub!(state.main, (point[1] + 54, point[2] + 72 + 36 * (i - 1)), probe, 1)
        px, py = allocate_cell!(state.layout)
        output_probe!(state.main, probe, "converter", unit, (px + 126, py + 72))
    end
    for (probe, unit) in ((ac_current, "kA"), (dc_current, "kA"))
        px, py = allocate_cell!(state.layout)
        output_probe!(state.main, probe, "branch", unit, (px + 126, py + 72))
    end
    return nothing
end
