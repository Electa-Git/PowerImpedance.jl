# Converter equations belong to converter/common, TLC and MMC. This file only
# assembles their supported control objects as PSCAD block diagrams.
const _CONVERTER_STARTUP_RELEASE = 0.2

# Saved time-based real selector: local/TLC/Simple_2L_VSC_RL.pscx:5912–5929.
# Keep one construction for the accepted TLC and MMC measurement handovers.
struct _ConverterStartupHold <: ControlBlock
    clock::Signal
    measured::Signal
    output::Signal
    initial::Float64
end

function lower!(canvas::CanvasPlan, node::_ConverterStartupHold, point)
    unary_block!(canvas, "compare", point,
        ["X" => block_value(_CONVERTER_STARTUP_RELEASE),
            "OL" => block_value(node.initial), "OH" => node.measured.name,
            "INTR" => "0", "Dim" => "1", "conv" => "0"], node.clock, node.output)
end

function converter_equilibrium(e)
    m = e.model
    reactive = m isa PowerImpedance.MMC ? m.delta_control.outer_reactive : m.outerReactive
    reactive isa PowerImpedance.OuterReactiveVacControl &&
        !(reactive.filter isa PowerImpedance.NoFilter) && not_exportable(e, reactive)
    active = m isa PowerImpedance.MMC ?
        (m.delta_control isa PowerImpedance.ΔdqControlGFL ? m.delta_control.outer_active : nothing) :
        m.outerActive
    active isa PowerImpedance.OuterActiveVdcControl &&
        !(active.filter isa PowerImpedance.NoFilter) && not_exportable(e, active)
    active isa PowerImpedance.OuterActivePowerControl &&
        active.support isa PowerImpedance.DCVoltageSupportLag && not_exportable(e, active.support)
    inputs, setpoint_pu = PowerImpedance.pftoinputs(m, e.setpoint)
    vector = PowerImpedance._steady_state(e.element, e.setpoint)
    states = NamedTuple{PowerImpedance.statenames(m)}(Tuple(vector))
    outputs = PowerImpedance.state_space!(
        zeros(length(vector)), states, inputs, setpoint_pu, m)
    if m isa PowerImpedance.MMC
        outputs = mmc_equilibrium_outputs(m, states, inputs, setpoint_pu)
    end
    return (; states, inputs, setpoint_pu, outputs)
end

function not_exportable(e, block)
    throw(ArgumentError(
        "converter :$(e.name): control $(typeof(block)) is not yet exportable"))
end

function converter_definition(name, parameters, graph, inputs, outputs)
    ports = ModulePortPlan[]
    for (kind, names, x) in ((:input, inputs, -54), (:output, outputs, 54))
        for (i, entry) in enumerate(names)
            signal, dimension = entry
            push!(ports, ModulePortPlan(signal, kind, x, 36 * (i - 1), dimension))
        end
    end
    return ModuleDefinitionPlan(name, parameters, ports, lower!(CanvasPlan(), graph))
end

function converter_parameter!(parameters, name, value, unit = "")
    push!(parameters, ModuleParameterPlan(name, Float64(value), unit))
    return name
end

function converter_pi!(graph, parameters, input, output, pi, state, prefix)
    kp = converter_parameter!(parameters, prefix * "Kp", pi.Kp)
    ki = converter_parameter!(parameters, prefix * "Ki", pi.Ki)
    y0 = converter_parameter!(parameters, prefix * "I0", state)
    p, rate, integral = Signal.([
        prefix * "proportional", prefix * "rate", prefix * "integral"])
    append!(graph.nodes,
        ControlBlock[Gain(input, p, kp), Gain(input, rate, ki),
            Integrator(rate, integral, 1.0, y0, -1e8, 1e8), Sum([p, integral], [1, 1], output)])
    return nothing
end

function converter_filter!(
        graph, parameters, input, output, filter::PowerImpedance.NoFilter,
        names, states, u, e)
    push!(graph.nodes, Gain(input, output, 1.0))
    return nothing
end

function converter_filter!(
        graph, parameters, input, output, filter::PowerImpedance.Butterworth,
        names, states, u, e)
    filter.table == PowerImpedance.BUTTERWORTH_TABLE || not_exportable(e, filter)
    # Translate the solved realization, not the initializer's guesses. At an
    # equilibrium every unit-DC-gain cascade section has the same output.
    x = [getproperty(states, n) for n in names]
    y0 = only(filter.C * x + filter.D * [u])
    dy0 = only(filter.C * (filter.A * x + filter.B * [u]))
    sections = filter.table[filter.order]
    previous = input
    for (i, (a, b)) in enumerate(sections)
        prefix = output.name * "_s$i"
        next = i == length(sections) ? output : Signal(prefix)
        initial = converter_parameter!(parameters, prefix * "Y0", y0)
        if iszero(b)
            t = converter_parameter!(parameters, prefix * "T", a / filter.ωc, "s")
            push!(graph.nodes, RealPole(previous, next, 1.0, t, initial))
        else
            w2 = converter_parameter!(parameters, prefix * "W2", filter.ωc^2 / b)
            damping = converter_parameter!(parameters, prefix * "D", a * filter.ωc / b)
            derivative = converter_parameter!(parameters, prefix * "DY0", dy0)
            push!(graph.nodes, SecondOrder(
                previous, next, w2, damping, initial, derivative))
        end
        previous = next
    end
    return nothing
end
function converter_filter!(graph, parameters, input, output, filter, names, states, u, e)
    not_exportable(e, filter)
end

function converter_measurement_filter!(
        graph, parameters, input, output, filter, names, states, u, e)
    if e.model isa PowerImpedance.MMC
        # Hold the input so solved dynamic filter states remain at equilibrium;
        # masking only the output would let zero meter inputs discharge them.
        held = Signal(output.name * "_startup")
        push!(graph.nodes, _ConverterStartupHold(
            Signal("meas_start_clock_s"), input, held, Float64(u)))
        input = held
    end
    converter_filter!(graph, parameters, input, output, filter, names, states, u, e)
end

function converter_measurements(name, e, equilibrium, transforms,
        bases = (; v = e.model.elec.vACbase, i = e.model.elec.iACbase,
            dc = e.model.elec.vDCbase))
    m = e.model
    parameters = ModuleParameterPlan[]
    graph = BlockGraph()
    for n in ("v_abc", "i_abc", "v_dc", "theta_c", "theta_rel")
        push!(graph.nodes, Import(n, Signal(n)))
    end
    m isa PowerImpedance.MMC &&
        push!(graph.nodes, TimeStep(Signal("meas_start_clock_s")))
    for (stem, base, definition) in (("v", bases.v, transforms.abc),
        ("i", bases.i, transforms.abc))
        abc, dq = Signal.([stem * "_abc", stem * "_dq"])
        push!(graph.nodes, AbcToDq(abc, Signal("theta_c"), dq, definition))
        invbase = converter_parameter!(parameters, stem * "_invbase", 1 / base)
        for (axis, i) in (("d", 1), ("q", 2))
            raw = Signal(stem * "_" * axis * "_si")
            output = Signal((stem == "v" ? "vG_" : "i_") * axis)
            append!(graph.nodes, ControlBlock[ArraySplit(dq, raw, i), Gain(raw, output, invbase)])
        end
    end
    invdc = converter_parameter!(parameters, "invDCbase", 1 / bases.dc)
    push!(graph.nodes, Gain(Signal("v_dc"), Signal("v_dc_pu"), invdc))
    inputs = [("v_abc", 3), ("i_abc", 3), ("v_dc", 1), ("theta_c", 1), ("theta_rel", 1)]
    if m isa PowerImpedance.MMC
        invcurrent = converter_parameter!(parameters, "invDCcurrent", bases.dc /
                                                                      m.elec.Sbase)
        append!(graph.nodes,
            ControlBlock[Import("i_dc_si", Signal("i_dc_si")),
                Gain(Signal("i_dc_si"), Signal("i_dc"), invcurrent)])
        push!(inputs, ("i_dc_si", 1))
    else
        push!(graph.nodes, Const(Signal("i_dc"), 0.0))
    end
    raw = equilibrium.outputs.sig_in
    for field in (:vG_d, :vG_q, :v_dc, :i_d, :i_q, :i_dc, :θ)
        measurement = getproperty(m.meas, field)
        signal = field == :θ ? "theta_rel" : field == :v_dc ? "v_dc_pu" : string(field)
        filtered = field == :θ ? "theta_f" : string(field) * "_f"
        converter_measurement_filter!(
            graph, parameters, Signal(signal), Signal(filtered), measurement.filter,
            PowerImpedance.statenames(measurement), equilibrium.states, getproperty(raw, field), e)
    end
    vd, vq, id, iq = Signal.(["vG_d_f", "vG_q_f", "i_d_f", "i_q_f"])
    dd, qq, qd, dq, p, q, pdc = Signal.([
        "vdid", "vqiq", "vqid", "vdiq", "P_ac", "Q_ac", "P_dc"])
    append!(graph.nodes,
        ControlBlock[Mult(vd, id, dd), Mult(vq, iq, qq),
            Sum([dd, qq], [1, 1], p), Mult(vq, id, qd), Mult(vd, iq, dq),
            Sum([qd, dq], [-1, 1], q), Mult(Signal("v_dc_f"), Signal("i_dc_f"), pdc)])
    measured = equilibrium.outputs.meas
    for (field, u) in ((
        :P_ac, measured.vG_d_f * measured.i_d_f + measured.vG_q_f * measured.i_q_f),
        (:Q_ac, -measured.vG_q_f * measured.i_d_f + measured.vG_d_f * measured.i_q_f),
        (:P_dc, measured.v_dc_f * measured.i_dc_f))
        measurement = getproperty(m.meas, field)
        converter_measurement_filter!(
            graph, parameters, Signal(string(field)), Signal(string(field) * "_f"),
            measurement.filter, PowerImpedance.statenames(measurement), equilibrium.states, u, e)
    end
    outputs = [(n, 1)
               for n in ("vG_d_f", "vG_q_f", "i_d_f", "i_q_f", "v_dc_f", "P_ac_f", "Q_ac_f")]
    append!(graph.nodes, [Export(n, Signal(n)) for (n, _) in outputs])
    return converter_definition(name, parameters, graph, inputs, outputs)
end

function converter_pll(name, e, equilibrium, block = e.model.sync)
    block isa PowerImpedance.PLLSynchronization || not_exportable(e, block)
    parameters = ModuleParameterPlan[]
    inputs = [("vG_q_f", 1)]
    graph = BlockGraph(ControlBlock[Import("vG_q_f", Signal("vG_q_f"))])
    voltage = Signal("vG_q_f")
    initial_voltage = equilibrium.outputs.meas.vG_q_f
    if e.model.sync isa PowerImpedance.VSEWithDamping
        append!(inputs, [("vG_d_f", 1), ("theta_vsm_rel", 1)])
        append!(graph.nodes, ControlBlock[Import("vG_d_f", Signal("vG_d_f")),
            Import("theta_vsm_rel", Signal("theta_vsm_rel")),
            Sum(Signal.(["theta_rel", "theta_vsm_rel"]), [1, -1], Signal("pll_frame_angle"))])
        converter_rotation!(graph, Signal("vG_d_f"), Signal("vG_q_f"),
            Signal("pll_frame_angle"), Signal("vG_d_pll"), Signal("vG_q_pll"), "pll_frame", false)
        voltage = Signal("vG_q_pll")
        initial_voltage = PowerImpedance.frame_transform(equilibrium.outputs.meas.vG_d_f,
            initial_voltage, equilibrium.states.Δθ_pll - equilibrium.states.Δθ_VSM).q
    end
    converter_filter!(graph, parameters, voltage, Signal("v_pll"), block.filter,
        PowerImpedance.filter_statenames(:v_q_pll_f, block.filter), equilibrium.states,
        initial_voltage, e)
    append!(graph.nodes, ControlBlock[Gain(Signal("v_pll"), Signal("error"), -1.0)])
    converter_pi!(graph, parameters, Signal("error"), Signal("dw"), block.pi_ctrl,
        equilibrium.states.ξ_pll, "pll")
    w = converter_parameter!(parameters, "wbase", e.model.elec.ωbase)
    initial = converter_parameter!(parameters, "theta0", equilibrium.states.Δθ_pll)
    append!(graph.nodes,
        ControlBlock[Const(Signal("one"), 1.0),
            Sum([Signal("one"), Signal("dw")], [1, 1], Signal("omega_c")),
            Gain(Signal("omega_c"), Signal("w_rad"), w),
            Integrator(Signal("w_rad"), Signal("theta_c"), 1.0, initial, -1e8, 1e8),
            TimeStep(Signal("pll_clock_s")), Gain(Signal("pll_clock_s"), Signal("theta_nom"), w),
            Sum([Signal("theta_c"), Signal("theta_nom")], [1, -1], Signal("theta_rel"))])
    outputs = [("omega_c", 1), ("theta_c", 1), ("theta_rel", 1)]
    append!(graph.nodes, [Export(n, Signal(n)) for (n, _) in outputs])
    return converter_definition(name, parameters, graph, inputs, outputs)
end

# VSM primitive witnesses: local/GFM-MMC/FFVI-VSM/PSCAD model/FFVI.pscx:
# 69653–69864, 69925–69984. Coefficients and equations belong to synchronization.jl.
function converter_vsm(name, e, equilibrium, block::PowerImpedance.VSEWithDamping)
    parameters = ModuleParameterPlan[]
    inputs = [("P_ac_f", 1), ("omega_pll", 1)]
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for (n, _) in inputs])
    for (n, v, unit) in (("p_reference", equilibrium.setpoint_pu.p_ac, ""),
        ("omega_reference", block.ω_ref, ""), ("Kd", block.K_d, ""),
        ("Kw", block.K_ω, ""), ("inv2H", 1 / (2block.H), ""),
        ("wbase", e.model.elec.ωbase, ""),
        ("omega0", equilibrium.states.ω_VSM, ""),
        ("theta0", equilibrium.states.Δθ_VSM, ""))
        converter_parameter!(parameters, n, v, unit)
    end
    append!(graph.nodes, ControlBlock[
        Import("p_reference", Signal("p_reference")),
        Import("omega_reference", Signal("omega_reference")),
        Sum(Signal.(["omega_c", "omega_pll"]), [1, -1], Signal("damping_error")),
        Gain(Signal("damping_error"), Signal("damping"), "Kd"),
        Sum(Signal.(["omega_c", "omega_reference"]), [1, -1], Signal("droop_error")),
        Gain(Signal("droop_error"), Signal("droop"), "Kw"),
        Sum(Signal.(["p_reference", "P_ac_f", "damping"]), [1, -1, -1], Signal("power_balance")),
        Sum(Signal.(["power_balance", "droop"]), [1, -1], Signal("swing_power")),
        Gain(Signal("swing_power"), Signal("omega_rate"), "inv2H"),
        Integrator(Signal("omega_rate"), Signal("omega_c"), 1.0, "omega0", -1e8, 1e8),
        Gain(Signal("omega_c"), Signal("angle_rate"), "wbase"),
        Integrator(Signal("angle_rate"), Signal("theta_c"), 1.0, "theta0", -1e8, 1e8),
        TimeStep(Signal("vsm_clock_s")), Gain(Signal("vsm_clock_s"), Signal("theta_nom"), "wbase"),
        Sum(Signal.(["theta_c", "theta_nom"]), [1, -1], Signal("theta_rel"))])
    outputs = [("omega_c", 1), ("theta_c", 1), ("theta_rel", 1)]
    append!(graph.nodes, [Export(n, Signal(n)) for (n, _) in outputs])
    return converter_definition(name, parameters, graph, inputs, outputs)
end

# CCVI primitives: the same FFVI.pscx, VI_VSM_CCQSEM_1:65787–66124.
function converter_ccvi(name, e, equilibrium, block::PowerImpedance.CCVI)
    parameters = ModuleParameterPlan[]
    inputs = [(n, 1) for n in ("vG_d_f", "vG_q_f", "omega_c", "q_voltage_ref")]
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for (n, _) in inputs])
    for (n, v) in (("Rv", block.R_v), ("Lv", block.L_v),
        ("vd_reference", block.V_d_ref), ("vq_reference", block.V_q_ref))
        converter_parameter!(parameters, n, v)
    end
    for axis in ("d", "q")
        converter_filter!(graph, parameters, Signal("vG_" * axis * "_f"),
            Signal("vi_v" * axis), block.filter,
            PowerImpedance.filter_statenames(Symbol("vG_" * axis * "_vi_f"), block.filter),
            equilibrium.states, getproperty(equilibrium.outputs.meas, Symbol("vG_" * axis * "_f")), e)
    end
    append!(graph.nodes, ControlBlock[
        Import("Rv", Signal("Rv")), Import("vd_reference", Signal("vd_reference")),
        Import("vq_reference", Signal("vq_reference")),
        Sum(Signal.(["vd_reference", "q_voltage_ref", "vi_vd"]), [1, 1, -1], Signal("vi_ed")),
        Sum(Signal.(["vq_reference", "vi_vq"]), [1, -1], Signal("vi_eq")),
        Gain(Signal("omega_c"), Signal("omega_L"), "Lv"),
        Square(Signal("Rv"), Signal("R2")), Square(Signal("omega_L"), Signal("omega_L2")),
        Sum(Signal.(["R2", "omega_L2"]), [1, 1], Signal("vi_den")),
        Gain(Signal("vi_ed"), Signal("R_ed"), "Rv"),
        Mult(Signal("omega_L"), Signal("vi_eq"), Signal("L_eq")),
        Sum(Signal.(["R_ed", "L_eq"]), [1, -1], Signal("vi_d_num")),
        Gain(Signal("vi_eq"), Signal("R_eq"), "Rv"),
        Mult(Signal("omega_L"), Signal("vi_ed"), Signal("L_ed")),
        Sum(Signal.(["R_eq", "L_ed"]), [1, 1], Signal("vi_q_num")),
        Div(Signal("vi_d_num"), Signal("vi_den"), Signal("i_d_ref")),
        Div(Signal("vi_q_num"), Signal("vi_den"), Signal("i_q_ref"))])
    outputs = [("i_d_ref", 1), ("i_q_ref", 1)]
    append!(graph.nodes, [Export(n, Signal(n)) for (n, _) in outputs])
    return converter_definition(name, parameters, graph, inputs, outputs)
end
converter_ccvi(name, e, equilibrium, block) = not_exportable(e, block)

function converter_frequency_support!(
        graph, parameters, block::PowerImpedance.NoFrequencySupport,
        equilibrium, e)
    push!(graph.nodes, Const(Signal("support"), 0.0))
end
function converter_frequency_support!(
        graph, parameters, block::PowerImpedance.FrequencySupportLag,
        equilibrium, e)
    block.ωc > 0 || not_exportable(e, block)
    k = converter_parameter!(parameters, "supportK", -block.Kω)
    t = converter_parameter!(parameters, "supportT", 1 / block.ωc, "s")
    y0 = converter_parameter!(parameters, "support0", equilibrium.states.ξ_f_supp)
    append!(graph.nodes,
        ControlBlock[Const(Signal("one"), 1.0),
            Sum([Signal("omega_c"), Signal("one")], [1, -1], Signal("dw")),
            RealPole(Signal("dw"), Signal("support"), k, t, y0)])
end
function converter_frequency_support!(graph, parameters, block, equilibrium, e)
    not_exportable(e, block)
end

function converter_active(name, e, equilibrium, block::PowerImpedance.OuterActivePowerControl)
    parameters = ModuleParameterPlan[]
    graph = BlockGraph(ControlBlock[Import("P_ac_f", Signal("P_ac_f")), Import("omega_c", Signal("omega_c"))])
    converter_frequency_support!(graph, parameters, block.support, equilibrium, e)
    converter_parameter!(parameters, "reference", equilibrium.setpoint_pu.p_ac)
    append!(graph.nodes,
        ControlBlock[Import("reference", Signal("reference")),
            Sum([Signal("reference"), Signal("support"), Signal("P_ac_f")], [1, 1, -1], Signal("error"))])
    converter_pi!(graph, parameters, Signal("error"), Signal("i_d_ref"), block.pi_ctrl,
        equilibrium.states.ξ_P_ac, "p")
    push!(graph.nodes, Export("i_d_ref", Signal("i_d_ref")))
    return converter_definition(
        name, parameters, graph, [("P_ac_f", 1), ("omega_c", 1)], [("i_d_ref", 1)])
end
function converter_active(name, e, equilibrium, block::PowerImpedance.OuterActiveVdcControl)
    block.filter isa PowerImpedance.NoFilter || not_exportable(e, block)
    parameters = ModuleParameterPlan[]
    converter_parameter!(parameters, "reference", equilibrium.setpoint_pu.v_dc)
    graph = BlockGraph(ControlBlock[
        Import("v_dc_f", Signal("v_dc_f")), Import("reference", Signal("reference")),
        Sum([Signal("reference"), Signal("v_dc_f")], [1, -1], Signal("error"))])
    converter_pi!(graph, parameters, Signal("error"), Signal("pi"), block.pi_ctrl,
        equilibrium.states.ξ_v_dc, "vdc")
    append!(graph.nodes,
        ControlBlock[Gain(Signal("pi"), Signal("i_d_ref"), -1.0),
            Export("i_d_ref", Signal("i_d_ref"))])
    return converter_definition(name, parameters, graph, [("v_dc_f", 1)], [("i_d_ref", 1)])
end
converter_active(name, e, equilibrium, block) = not_exportable(e, block)

function converter_voltage_support!(
        graph, parameters, block::PowerImpedance.NoVoltageSupport, equilibrium, e)
    push!(graph.nodes, Const(Signal("support"), 0.0))
end
function converter_voltage_support!(
        graph, parameters, block::PowerImpedance.VoltageSupportLag, equilibrium, e)
    block.ωc > 0 || not_exportable(e, block)
    converter_parameter!(parameters, "vac_reference",
        equilibrium.setpoint_pu.v_ac * PowerImpedance.voltage_filter_ratio(e.model))
    k = converter_parameter!(parameters, "supportK", block.K)
    t = converter_parameter!(parameters, "supportT", 1 / block.ωc, "s")
    y0 = converter_parameter!(parameters, "support0", equilibrium.states.ξ_vac_supp)
    append!(graph.nodes,
        ControlBlock[Square(Signal("vG_d_f"), Signal("vd2")),
            Square(Signal("vG_q_f"), Signal("vq2")), Sum(
                [Signal("vd2"), Signal("vq2")], [
                    1, 1], Signal("v2")),
            Sqrt(Signal("v2"), Signal("vac")), Import("vac_reference", Signal("vac_reference")),
            Sum([Signal("vac_reference"), Signal("vac")], [1, -1], Signal("vac_error")),
            RealPole(Signal("vac_error"), Signal("support"), k, t, y0)])
end
function converter_voltage_support!(graph, parameters, block, equilibrium, e)
    not_exportable(e, block)
end

function converter_reactive(name, e, equilibrium)
    converter_reactive(name, e, equilibrium, e.model.outerReactive)
end

function converter_reactive(name, e, equilibrium, block::PowerImpedance.OuterReactiveQControl)
    parameters = ModuleParameterPlan[]
    graph = BlockGraph(ControlBlock[Import(n, Signal(n))
                                    for n in ("Q_ac_f", "vG_d_f", "vG_q_f")])
    converter_voltage_support!(graph, parameters, block.support, equilibrium, e)
    converter_parameter!(parameters, "reference", equilibrium.setpoint_pu.q_ac)
    append!(graph.nodes,
        ControlBlock[Import("reference", Signal("reference")),
            Sum([Signal("reference"), Signal("support"), Signal("Q_ac_f")], [1, 1, -1], Signal("error"))])
    converter_pi!(graph, parameters, Signal("error"), Signal("i_q_ref"), block.pi_ctrl,
        equilibrium.states.ξ_Q_ac, "q")
    push!(graph.nodes, Export("i_q_ref", Signal("i_q_ref")))
    return converter_definition(name, parameters, graph,
        [("Q_ac_f", 1), ("vG_d_f", 1), ("vG_q_f", 1)], [("i_q_ref", 1)])
end

function converter_reactive(name, e, equilibrium, block::PowerImpedance.OuterReactiveVacControl)
    block.filter isa PowerImpedance.NoFilter || not_exportable(e, block)
    parameters = ModuleParameterPlan[]
    converter_parameter!(parameters, "vac_reference",
        equilibrium.setpoint_pu.v_ac * PowerImpedance.voltage_filter_ratio(e.model))
    # VacControl: local/GFL-MMC/VAC_Control/GFL_MMC_Validation.pscx:8025–8215.
    # Use the already witnessed square/sqrt voltage magnitude and split PI.
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for n in ("vG_d_f", "vG_q_f")])
    append!(graph.nodes,
        ControlBlock[Square(Signal("vG_d_f"), Signal("vd2")),
            Square(Signal("vG_q_f"), Signal("vq2")),
            Sum([Signal("vd2"), Signal("vq2")], [1, 1], Signal("v2")),
            Sqrt(Signal("v2"), Signal("vac")), Import("vac_reference", Signal("vac_reference")),
            Sum([Signal("vac_reference"), Signal("vac")], [1, -1], Signal("error"))])
    converter_pi!(graph, parameters, Signal("error"), Signal("i_q_ref"), block.pi_ctrl,
        equilibrium.states.ξ_v_ac, "vac")
    push!(graph.nodes, Export("i_q_ref", Signal("i_q_ref")))
    return converter_definition(name, parameters, graph,
        [("vG_d_f", 1), ("vG_q_f", 1)], [("i_q_ref", 1)])
end
converter_reactive(name, e, equilibrium, block) = not_exportable(e, block)

function converter_occ(name, e, equilibrium, block = e.model.innerCurrent)
    block isa PowerImpedance.InnerCurrentPIControl || not_exportable(e, block)
    if e.model isa PowerImpedance.TLC
        e.model.innerVoltage isa PowerImpedance.NoInnerVoltageControl ||
            not_exportable(e, e.model.innerVoltage)
    end
    parameters = ModuleParameterPlan[]
    inputs = [(n, 1)
              for n in ("i_d_ref", "i_q_ref", "i_d_f", "i_q_f", "vG_d_f", "vG_q_f", "omega_c")]
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for (n, _) in inputs])
    l = converter_parameter!(parameters, "Lpu", PowerImpedance.elec_inductance(e.model.elec))
    for (axis, other, sign, initial) in (("d", "q", 1, equilibrium.states.ξ_id), (
        "q", "d", -1, equilibrium.states.ξ_iq))
        error, pi, feed, cross, term, output = Signal.([axis * s
                                                        for s in ("error", "pi", "feed", "cross", "term", "voltage")])
        push!(graph.nodes, Sum(
            [Signal("i_" * axis * "_ref"), Signal("i_" * axis * "_f")], [
                1, -1], error))
        converter_pi!(graph, parameters, error, pi, block.pi_ctrl, initial, axis)
        input = Signal("vG_" * axis * "_f")
        converter_filter!(graph, parameters, input, feed, block.filter,
            PowerImpedance.filter_statenames(Symbol("vG_" * axis * "_occ_f"), block.filter),
            equilibrium.states, getproperty(equilibrium.outputs.meas, Symbol(input.name)), e)
        if block.activate_ω_c_multiplication
            push!(graph.nodes, Mult(Signal("omega_c"), Signal("i_" * other * "_f"), cross))
        else
            push!(graph.nodes, Gain(Signal("i_" * other * "_f"), cross, 1.0))
        end
        append!(graph.nodes,
            ControlBlock[Gain(cross, term, l), Sum([pi, feed, term], [1, 1, sign], output),
                Export("vM_" * axis * "_ref", output)])
    end
    return converter_definition(
        name, parameters, graph, inputs, [("vM_d_ref", 1), ("vM_q_ref", 1)])
end
