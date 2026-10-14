# Evaluate the owned blocks because MMC.state_space! returns no diagnostics.
function mmc_equilibrium_outputs(m, states, inputs, setpoint_pu)
    sig_in = PowerImpedance.input_signals(m, states, inputs)
    F = zeros(PowerImpedance.n_states(m))
    meas, i = PowerImpedance.state_space_block!(
        F, states, sig_in, setpoint_pu, m.meas, m, 1)
    sync, i = PowerImpedance.state_space_block!(F, states, meas, setpoint_pu, m.sync, m, i)
    delta, i = PowerImpedance.state_space_block!(
        F, states, (; meas, sync), setpoint_pu, m.delta_control, m, i)
    sigma, i = PowerImpedance.state_space_block!(F, states,
        (; meas, power = (; P_ac_f = meas.P_ac_f), sync), setpoint_pu, m.sigma_control, m, i)
    mod, _ = PowerImpedance.state_space_block!(F, states,
        (; meas, out_delta = delta, out_sigma = sigma), setpoint_pu, m.modulation, m, i)
    return (; sig_in, meas, sync, delta, sigma, mod)
end

mmc_sigma(name, e, equilibrium, transforms) =
    mmc_sigma(name, e, equilibrium, transforms, e.model.sigma_control)
mmc_sigma(name, e, equilibrium, transforms, block) = not_exportable(e, block)

function mmc_sigma(name, e, equilibrium, transforms, block::PowerImpedance.ΣdqzControlTEC)
    parameters = ModuleParameterPlan[]
    inputs = [("iS_abc", 3), ("theta_c", 1), ("P_ac_f", 1), ("v_dc_f", 1), ("v_dc_divisor", 1)]
    append!(inputs, [("v_Ctot_" * arm * "_" * phase, 1)
                     for arm in ("u", "l") for phase in ("a", "b", "c")])
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for (n, _) in inputs])
    invcurrent = converter_parameter!(parameters, "invIbase", e.model.elec.vDC_base /
                                                              e.model.elec.Sbase)
    append!(graph.nodes,
        ControlBlock[Gain(Signal("theta_c"), Signal("sigma_angle"), -2.0),
            AbcToDq(Signal("iS_abc"), Signal("sigma_angle"), Signal("iS_dq_si"), transforms.abc)])
    sum_currents = Signal[]
    for (i, phase) in enumerate(("a", "b", "c"))
        s = Signal("iS_" * phase)
        push!(sum_currents, s)
        push!(graph.nodes, ArraySplit(Signal("iS_abc"), s, i))
    end
    push!(graph.nodes, Sum(sum_currents, [1, 1, 1], Signal("iS_sum")))
    invzero = converter_parameter!(parameters, "invIzero", e.model.elec.vDC_base /
                                                           (3 * e.model.elec.Sbase))
    append!(graph.nodes,
        ControlBlock[Gain(Signal("iS_sum"), Signal("iS_z_measured"), invzero),
            Gain(Signal("iS_z_measured"), Signal("iS_z"), 1.0)])
    for (i, axis) in enumerate(("d", "q"))
        append!(graph.nodes,
            ControlBlock[
                ArraySplit(Signal("iS_dq_si"), Signal("iS_" * axis * "_si"), i),
                Gain(Signal("iS_" * axis * "_si"), Signal("iS_" * axis * "_measured"), invcurrent),
                Gain(Signal("iS_" * axis * "_measured"), Signal("iS_" * axis), 1.0)])
    end
    mmc_total_energy!(graph, parameters, e, equilibrium, block.tec)
    mmc_zero_current!(graph, parameters, e, equilibrium, block.zscc)
    append!(graph.nodes,
        ControlBlock[Gain(Signal("v_dc_f"), Signal("half_dc"), 0.5),
            Sum(Signal.(["half_dc", "zero_pi"]), [1, -1], Signal("vMS_z_ref"))])
    mmc_circulating_current!(graph, parameters, e, equilibrium, block.ccsc)
    append!(graph.nodes, ControlBlock[Export("vMS_z_ref", Signal("vMS_z_ref")), Export("iS_z", Signal("iS_z"))])
    return converter_definition(name, parameters, graph, inputs,
        [(n, 1) for n in ("vMS_d_ref", "vMS_q_ref", "vMS_z_ref", "iS_z")])
end

mmc_total_energy!(graph, parameters, e, equilibrium, block) = not_exportable(e, block)
function mmc_total_energy!(graph, parameters, e, equilibrium,
        ::PowerImpedance.NoTotalEnergyControl)
    push!(graph.nodes, Const(Signal("iS_z_ref"), 0.0))
    return nothing
end
function mmc_total_energy!(graph, parameters, e, equilibrium,
        block::PowerImpedance.TotalEnergyControl)
    invcap = converter_parameter!(parameters, "invVbase", 1 / e.model.elec.vDC_base)
    squares = Signal[]
    for arm in ("u", "l"), phase in ("a", "b", "c")

        stem = arm * "_" * phase
        pu, square = Signal.(["cap_" * stem, "energy_" * stem])
        append!(graph.nodes, ControlBlock[Gain(Signal("v_Ctot_" * stem), pu, invcap), Square(pu, square)])
        push!(squares, square)
    end
    # Six-arm instantaneous energy. Its cycle mean is precisely energy.jl's
    # seven-coordinate wΣz; the abc plant also retains its 6ω ripple.
    push!(graph.nodes, Sum(squares[1:3], [1, 1, 1], Signal("energy_u")))
    push!(graph.nodes, Sum(squares[4:6], [1, 1, 1], Signal("energy_l")))
    # Capacitor energy and inner-current feedback both remain live from t=0.
    append!(graph.nodes,
        ControlBlock[Sum(Signal.(["energy_u", "energy_l"]), [1, 1], Signal("energy_sum")),
            Gain(Signal("energy_sum"), Signal("energy_measured"), 1 / 6),
            Gain(Signal("energy_measured"), Signal("energy_pu"), 1.0)])
    reference = converter_parameter!(parameters, "energy_reference", block.ref)
    append!(graph.nodes,
        ControlBlock[Import(reference, Signal(reference)),
            Sum(Signal.([reference, "energy_pu"]), [1, -1], Signal("energy_error"))])
    converter_pi!(graph, parameters, Signal("energy_error"), Signal("energy_pi"),
        block.pi_control, equilibrium.states.ξ_Wtot, "energy")
    append!(graph.nodes,
        ControlBlock[Sum(Signal.(["energy_pi", "P_ac_f"]), [1, 1], Signal("dc_power")),
            Gain(Signal("dc_power"), Signal("third_power"), 1 / 3),
            Div(Signal("third_power"), Signal("v_dc_divisor"), Signal("iS_z_ref"))])
    return nothing
end

mmc_zero_current!(graph, parameters, e, equilibrium, block) = not_exportable(e, block)
function mmc_zero_current!(graph, parameters, e, equilibrium,
        ::PowerImpedance.NoZeroSequenceCurrentControl)
    push!(graph.nodes, Const(Signal("zero_pi"), 0.0))
    return nothing
end
function mmc_zero_current!(graph, parameters, e, equilibrium,
        block::PowerImpedance.ZeroSequenceCurrentControl)
    push!(graph.nodes,
        Sum(Signal.(["iS_z_ref", "iS_z"]), [1, -1], Signal("zero_error")))
    converter_pi!(graph, parameters, Signal("zero_error"), Signal("zero_pi"),
        block.pi_control, equilibrium.states.ξ_iΣ_z, "zero")
    return nothing
end

mmc_circulating_current!(graph, parameters, e, equilibrium, block) = not_exportable(e, block)
function mmc_circulating_current!(graph, parameters, e, equilibrium,
        ::PowerImpedance.NoCirculatingCurrentSuppressionControl)
    append!(graph.nodes, ControlBlock[Const(Signal("vMS_" * axis * "_ref"), 0.0)
        for axis in ("d", "q")])
    append!(graph.nodes, ControlBlock[Export("vMS_" * axis * "_ref", Signal("vMS_" * axis * "_ref"))
        for axis in ("d", "q")])
    return nothing
end
function mmc_circulating_current!(graph, parameters, e, equilibrium,
        block::PowerImpedance.CirculatingCurrentSuppressionControl)
    cross = converter_parameter!(parameters, "twiceLarm", 2 * e.model.elec.Lₐᵣₘ)
    for (axis, other, sign, initial) in (("d", "q", 1, equilibrium.states.ξ_iΣ_d),
        ("q", "d", -1, equilibrium.states.ξ_iΣ_q))
        error, pi, term, voltage = Signal.(["sigma_" * axis * suffix
                                            for suffix in ("_error", "_pi", "_cross", "_voltage")])
        push!(graph.nodes, Gain(Signal("iS_" * axis), error, -1.0))
        converter_pi!(
            graph, parameters, error, pi, block.pi_control, initial, "sigma_" * axis)
        append!(graph.nodes,
            ControlBlock[Gain(Signal("iS_" * other), term, cross),
                Sum([pi, term], [-1, sign], voltage), Export("vMS_" * axis * "_ref", voltage)])
    end
    return nothing
end

function mmc_arm_capacitors(states, voltage_base, angle = 0.0)
    phases = angle .+ (0.0, -2π / 3, 2π / 3)
    sigma = states.vCΣ_z .+ states.vCΣ_d .* cos.(-2 .* phases) .+
            states.vCΣ_q .* sin.(-2 .* phases)
    delta = states.vCΔ_d .* cos.(phases) .+ states.vCΔ_q .* sin.(phases) .+
            states.vCΔ_Zd .* cos.(3 .* phases) .+ states.vCΔ_Zq .* sin.(3 .* phases)
    return (;
        upper = voltage_base .* (sigma .+ delta), lower = voltage_base .* (sigma .- delta))
end

mmc_modulation(name, e, equilibrium, transforms, settings) =
    mmc_modulation(name, e, equilibrium, transforms, settings, e.model.modulation)
mmc_modulation(name, e, equilibrium, transforms, settings, block) = not_exportable(e, block)

function mmc_modulation(name, e, equilibrium, transforms, settings,
        block::PowerImpedance.UncompensatedModulation)
    m = e.model
    parameters = ModuleParameterPlan[]
    inputs = [(n, 1)
              for n in ("vM_d_ref", "vM_q_ref", "vMS_d_ref", "vMS_q_ref", "vMS_z_ref", "v_dc_divisor", "theta_rel")]
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for (n, _) in inputs])
    append!(graph.nodes,
        ControlBlock[Const(Signal("two"), 2.0),
            Div(Signal("two"), Signal("v_dc_divisor"), Signal("sigma_factor")),
            Gain(Signal("sigma_factor"), Signal("delta_factor"), -m.elec.baseConv1),
            Gain(Signal("theta_rel"), Signal("sigma_rel"), -2.0)])
    converter_rotation!(graph, Signal("vM_d_ref"), Signal("vM_q_ref"), Signal("theta_rel"),
        Signal("vMD_d_grid"), Signal("vMD_q_grid"), "delta_grid", true)
    converter_rotation!(
        graph, Signal("vMS_d_ref"), Signal("vMS_q_ref"), Signal("sigma_rel"),
        Signal("vMS_d_grid"), Signal("vMS_q_grid"), "sigma_grid", true)
    for (stem, delay, frame, refs, factor) in (
        ("mD", m.modulation.delay1, 1,
        ("vMD_d_grid", "vMD_q_grid"), "delta_factor"),
        ("mS", m.modulation.delay2, -2,
        ("vMS_d_grid", "vMS_q_grid"), "sigma_factor"))
        residual = _converter_export_delay(delay.timeDelay, settings.time_step)
        for (axis, ref) in zip(("d", "q"), refs)
            raw, delayed = Signal.([
                stem * "_" * axis * "_raw", stem * "_" * axis * "_delay"])
            push!(graph.nodes, Mult(Signal(ref), Signal(factor), raw))
            # Exact delay in the global rotating coordinates, with the same
            # explicit frame compensation as MMC/modulation.jl:63–67.
            compensated = frame == 1 ?
                          PowerImpedance.phase_compensated_dq(
                [equilibrium.outputs.mod.mΔd, equilibrium.outputs.mod.mΔq], -m.elec.ωbase *
                                                                            residual) :
                          PowerImpedance.phase_compensated_dq(
                [equilibrium.outputs.mod.mΣd, equilibrium.outputs.mod.mΣq], 2m.elec.ωbase *
                                                                            residual)
            initial = compensated[axis == "d" ? 1 : 2]
            if iszero(residual)
                push!(graph.nodes, Gain(raw, delayed, 1.0))
            else
                td = converter_parameter!(parameters, stem * axis * "Td", residual, "s")
                y0 = converter_parameter!(parameters, stem * axis * "Y0", initial)
                push!(graph.nodes,
                    Delay(raw, delayed, td,
                        ceil(Int, residual / settings.time_step) + 1, y0))
            end
        end
        theta = converter_parameter!(parameters, stem * "phase", frame * m.elec.ωbase *
                                                                 residual)
        push!(graph.nodes, Import(theta, Signal(theta)))
        converter_rotation!(
            graph, Signal(stem * "_d_delay"), Signal(stem * "_q_delay"), Signal(theta),
            Signal(stem * "_d"), Signal(stem * "_q"), stem * "phase", false)
    end
    raw = Signal("mS_z_raw")
    push!(graph.nodes, Mult(Signal("vMS_z_ref"), Signal("sigma_factor"), raw))
    delay = m.modulation.delay3
    residual = _converter_export_delay(delay.timeDelay, settings.time_step)
    if iszero(residual)
        push!(graph.nodes, Gain(raw, Signal("mS_z"), 1.0))
    else
        td = converter_parameter!(parameters, "zeroTd", residual, "s")
        y0 = converter_parameter!(parameters, "zeroY0", equilibrium.outputs.mod.mΣz)
        push!(graph.nodes,
            Delay(raw, Signal("mS_z"), td,
                ceil(Int, residual / settings.time_step) + 1, y0))
    end
    append!(graph.nodes,
        ControlBlock[TimeStep(Signal("mmc_clock_s")),
            Gain(Signal("mmc_clock_s"), Signal("nominal_angle"), m.elec.ωbase),
            Gain(Signal("nominal_angle"), Signal("sigma_nominal"), -2.0),
            ArrayMerge(Signal.(["mD_d", "mD_q"]), Signal("mD_dq")),
            ArrayMerge(Signal.(["mS_d", "mS_q"]), Signal("mS_dq")),
            DqToAbc(Signal("mD_dq"), Signal("nominal_angle"), Signal("mD_abc"), transforms.dq),
            DqToAbc(Signal("mS_dq"), Signal("sigma_nominal"), Signal("mS_abc"), transforms.dq)])
    outputs = Tuple{String, Int}[]
    for (i, phase) in enumerate(("a", "b", "c"))
        d, s, total = Signal.(["mD_" * phase, "mS_" * phase, "mS_total_" * phase])
        append!(graph.nodes,
            ControlBlock[ArraySplit(Signal("mD_abc"), d, i),
                ArraySplit(Signal("mS_abc"), s, i), Sum([s, Signal("mS_z")], [1, 1], total)])
        # Julia mΔ includes the minus sign and factor two: the physical arm
        # assembly vMu=vMS-vMD, vMl=vMS+vMD becomes (mΣ±mΔ)/2.
        for (arm, sign) in (("u", 1), ("l", -1))
            sum, insertion = Signal.([
                "assembled_" * arm * "_" * phase, "m_" * arm * "_" * phase])
            append!(graph.nodes,
                ControlBlock[Sum([total, d], [1, sign], sum), Gain(sum, insertion, 0.5),
                    Export(insertion.name, insertion)])
            push!(outputs, (insertion.name, 1))
        end
    end
    return converter_definition(name, parameters, graph, inputs, outputs)
end

function mmc_arm_canvas!(canvas, si; stem = "", origin = (0, 0),
        positive = "arm_positive", negative = "arm_negative",
        insertion = "m_arm", current = "i_arm", capacitor = "v_Ctot",
        cap_gain = "capGain", cap_initial = "capInitial", measured_capacitor = nothing)
    private(n) = Signal(isempty(stem) ? n : stem * "_" * n)
    applied, measured, charging, rate, history = private.([
        "applied_insertion", "solved_current", "cap_current", "cap_rate_out", "cap_rate"])
    # Charge uses the command actually applied before this solve and its solved
    # current. The next dynamics pass integrates that history, not a future m.
    graph = BlockGraph(ControlBlock[
        _ConverterPhaseTransfer(Signal(insertion), applied, :dsout, 1),
        _ConverterPhaseTransfer(Signal(current), measured, :dsout, 1),
        Mult(applied, measured, charging), Gain(charging, rate, cap_gain),
        _ConverterPhaseTransfer(rate, history, :dsdyn, 1),
        Integrator(history, Signal(capacitor), 1.0, cap_initial, -100000.0, 100000.0),
        Mult(Signal(insertion), Signal(capacitor), private("arm_voltage"))])
    if measured_capacitor !== nothing
        # The physical capacitor changes only in DSDYN and is held throughout
        # the following network solve/DSOUT. Snapshot that applied state at the
        # explicit feedback boundary: next DSDYN then sees the same capacitor
        # level as its completed-solve arm currents, before any state advances.
        # Capturing a previous DSOUT copy here would add another whole step.
        push!(graph.nodes, _ConverterStateSnapshot(Signal(capacitor),
            Signal(measured_capacitor), cap_initial))
    end
    lower!(canvas, graph; origin = (origin[1] + 72, origin[2] + 432))
    at(x, y) = (origin[1] + x, origin[2] + y)
    label(n) = private(n).name
    # ArmAvg_1: local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx:7624–7741.
    # Preserve source polarity, positive charging current and physical L/R.
    component!(canvas, "source_1", at(180, 108),
        ["Name" => label("arm_source"), "Type" => "6", "Grnd" => "0", "Spec" => "0",
            "Cntrl" => "1", "AC" => "0", "Tc" => "0.0 [s]"])
    stub!(canvas, at(144, 108), positive; direction = -1)
    stub!(canvas, at(216, 108), label("arm_after_source"))
    module_signal_stub!(canvas, at(180, 144), label("arm_voltage"), 1)
    component!(canvas, "inductor", at(360, 108),
        ["Name" => label("arm_inductance"), "L" => pscad_value(si.L_arm; unit = "H")])
    stub!(canvas, at(360, 108), label("arm_after_source"); direction = -1)
    stub!(canvas, at(396, 108), label("arm_after_L"))
    component!(canvas, "resistor", at(540, 108),
        ["Name" => label("arm_resistance"), "R" => pscad_value(si.R_arm; unit = "ohm")])
    stub!(canvas, at(540, 108), label("arm_after_L"); direction = -1)
    stub!(canvas, at(576, 108), label("arm_after_R"))
    component!(canvas, "ammeter", at(720, 108), ["Name" => current])
    stub!(canvas, at(720, 108), label("arm_after_R"); direction = -1)
    stub!(canvas, at(756, 108), negative)
    return canvas
end

# Retain the isolated arm experiment, sharing exactly the parent-canvas physics.
function mmc_arm(name, si, initial)
    parameters = [ModuleParameterPlan("capGain", si.N / si.C_SM, ""),
        ModuleParameterPlan("capInitial", initial, "")]
    canvas = CanvasPlan()
    mmc_arm_canvas!(canvas, si)
    lower!(canvas, BlockGraph(ControlBlock[Import("m_arm", Signal("m_arm")),
        Export("i_arm", Signal("i_arm")), Export("v_Ctot", Signal("v_Ctot"))]);
        origin = (72, 864))
    for (port, node, x) in (("POS", "arm_positive", 72), ("NEG", "arm_negative", 936))
        component!(canvas, "xnode", (x, 216), ["Name" => port])
        stub!(canvas, (x, 216), node)
    end
    return ModuleDefinitionPlan(name, parameters,
        [ModulePortPlan("POS", :electrical, -54, 0),
            ModulePortPlan("NEG", :electrical, 54, 0),
            ModulePortPlan("m_arm", :input, -54, 72), ModulePortPlan("i_arm", :output, 54, 72),
            ModulePortPlan("v_Ctot", :output, 54, 108)], canvas)
end

function mmc_electrical_canvas(e, equilibrium, si)
    canvas = CanvasPlan()
    initial = mmc_arm_capacitors(equilibrium.states, si.vDC_base)
    for (phase_index, phase) in enumerate(("a", "b", "c")),
        (arm_index, half) in enumerate(("u", "l"))

        stem = half * "_" * phase
        cap = half == "u" ? initial.upper[phase_index] : initial.lower[phase_index]
        positive, negative = half == "u" ? ("dc_positive", "phase_" * phase) :
                             ("phase_" * phase, "dc_negative")
        mmc_arm_canvas!(canvas, si; stem,
            origin = (1728 * (phase_index - 1), 1296 * (arm_index - 1)),
            positive, negative, insertion = "m_" * stem, current = "i_" * stem,
            capacitor = "v_Ctot_" * stem, cap_gain = si.N / si.C_SM, cap_initial = cap,
            measured_capacitor = "v_Cmeas_" * stem)
    end
    # Keep the physical interface below the six exposed arm schematics.
    interface = CanvasPlan()
    for (i, phase) in enumerate(("a", "b", "c"))
        y = 720 + 144 * (i - 1)
        parts = Tuple{String, String, Float64, String}[]
        iszero(si.R_r) || push!(parts, ("resistor", "R", si.R_r, "ohm"))
        iszero(si.L_r) || push!(parts, ("inductor", "L", si.L_r, "H"))
        if isempty(parts)
            join_node_labels!(interface, "phase_" * phase, "reactor_" * phase)
        else
            endpoint = component_chain!(
                interface, parts, (180, y), "reactor_" * phase, interface.used)
            stub!(interface, (180, y), "phase_" * phase; direction = -1)
            stub!(interface, endpoint, "reactor_" * phase)
        end
        stub!(interface, (576, 864 + 36 * (i - 2)), "reactor_" * phase; direction = -1)
    end
    push!(interface.components, ComponentPlan(
        "master:breakout", ["Dis" => "0", "Com" => "0"], 612, 864, 4))
    stub!(interface, (612, 864), "converter_ac")
    component!(interface, "ammeter", (756, 864), ["Name" => "i_abc"])
    stub!(interface, (756, 864), "converter_ac"; direction = -1)
    stub!(interface, (792, 864), "transformer_ac")
    component!(interface, "voltmetergnd", (936, 936), ["Name" => "v_abc"])
    stub!(interface, (936, 936), "transformer_ac"; direction = -1)
    if si.turnsRatio == 1
        join_node_labels!(interface, "transformer_ac", "network_ac")
    else
        # YY near-ideal construction accepted in M2/M4. Every field is saved
        # at local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx:11813–11889;
        # source/return solvability is retained through the physical arm/DC path.
        component!(interface, "xfmr-3p2w", (1116, 864),
            ["Name" => "converter_transformer",
                "Tmva" => pscad_value(si.Sbase; unit = "MVA"),
                "f" => pscad_value(si.ωbase / (2π); unit = "Hz"), "YD1" => "0", "YD2" => "0", "Lead" => "1",
                "Ideal" => "0", "Xl" => pscad_value(YY_LEAKAGE_PU; unit = "pu"),
                "Im1" => pscad_value(YY_MAGNETIZING_CURRENT_PERCENT; unit = "%"),
                "NLL" => "0.0 [pu]", "CuL" => "0.0 [pu]", "Tap" => "0", "View" => "1", "Dtls" => "0",
                "V1" => pscad_value(si.vAC_base_LL_RMS; unit = "kV"),
                "V2" => pscad_value(si.vAC_base_LL_RMS / si.turnsRatio; unit = "kV"), "Enab" => "0"])
        stub!(interface, (1062, 864), "transformer_ac"; direction = -1)
        stub!(interface, (1152, 864), "network_ac")
    end
    for (port, node, point) in (("AC", "network_ac", (1368, 864)),
        ("DC_P", "dc_positive", (1800, 108)), ("DC_N", "dc_negative", (1800, 252)))
        component!(interface, "xnode", point, ["Name" => port])
        stub!(interface, point, node)
    end
    component!(interface, "voltmeter", (1800, 432), ["Name" => "v_dc"])
    stub!(interface, (1800, 432), "dc_positive"; direction = -1)
    stub!(interface, (1800, 468), "dc_negative"; direction = -1)
    append!(canvas.components,
        [ComponentPlan(c.defn, c.params, c.x, c.y + 2592, c.orient)
         for c in interface.components])
    append!(canvas.wires, [WirePlan([(x, y + 2592) for (x, y) in w.vertices])
                           for w in interface.wires])
    merge!(canvas.aliases, interface.aliases)
    # Use the existing arm currents for controls rather than adding another
    # ideal DC meter in series with the Main terminal meter.
    graph = BlockGraph()
    currents = Signal[]
    for phase in ("a", "b", "c")
        sum, average = Signal.(["iS_sum_" * phase, "iS_" * phase * "_si"])
        append!(graph.nodes,
            ControlBlock[_ConverterPhaseTransfer(Signal("i_u_" * phase),
                    Signal("i_u_solved_" * phase), :dsout, 1),
                _ConverterPhaseTransfer(Signal("i_l_" * phase),
                    Signal("i_l_solved_" * phase), :dsout, 1),
                Sum(Signal.(["i_u_solved_" * phase, "i_l_solved_" * phase]), [1, 1], sum),
                Gain(sum, average, 0.5)])
        push!(currents, average)
    end
    append!(graph.nodes,
        ControlBlock[ArrayMerge(currents, Signal("iS_solved_abc")),
            Sum(currents, [1, 1, 1], Signal("i_dc_solved_si")),
            _ConverterPhaseTransfer(Signal("iS_solved_abc"), Signal("iS_abc"), :dsdyn, 3),
            _ConverterPhaseTransfer(Signal("i_dc_solved_si"), Signal("i_dc_si"), :dsdyn, 1)])
    lower!(canvas, graph; origin = (2520, 2592))
    return canvas
end

function mmc_controls(state, e, equilibrium, context, delta::PowerImpedance.ΔdqControlGFL)
    m = e.model
    transforms = context.converter_transforms
    names = [pscad_name(prefix * "_" * e.pscad; used = state.used)
             for prefix in ("MEAS", "PLL",
        delta.outer_active isa PowerImpedance.OuterActiveVdcControl ? "VDCCTRL" : "PCTRL",
        "QCTRL", "OCC", "SIGMA", "MOD")]
    definitions = [
        converter_measurements(names[1], e, equilibrium, transforms,
            (; v = m.elec.vAC_base, i = 2m.elec.Sbase / (3m.elec.vAC_base),
                dc = m.elec.vDC_base)),
        converter_pll(names[2], e, equilibrium), converter_active(names[3], e, equilibrium, delta.outer_active),
        converter_reactive(names[4], e, equilibrium, delta.outer_reactive), converter_occ(
            names[5], e, equilibrium, delta.occ),
        mmc_sigma(names[6], e, equilibrium, transforms), mmc_modulation(
            names[7], e, equilibrium, transforms, context.settings)]
    return [d => (i == 2 ? (; theta_c = "theta_next", theta_rel = "theta_rel_next") : (;))
            for (i, d) in enumerate(definitions)]
end

function mmc_controls(state, e, equilibrium, context, delta::PowerImpedance.ΔdqControlGFM)
    m = e.model
    m.sync isa PowerImpedance.VSEWithDamping || not_exportable(e, m.sync)
    delta.vi isa PowerImpedance.CCVI || not_exportable(e, delta.vi)
    transforms = context.converter_transforms
    names = [pscad_name(prefix * "_" * e.pscad; used = state.used)
             for prefix in ("MEAS", "PLL", "VSM", "QCTRL", "CCVI", "OCC", "SIGMA", "MOD")]
    controls = [
        converter_measurements(names[1], e, equilibrium, transforms,
            (; v = m.elec.vAC_base, i = 2m.elec.Sbase / (3m.elec.vAC_base),
                dc = m.elec.vDC_base)) => (;),
        converter_pll(names[2], e, equilibrium, m.sync.pll) =>
            (; omega_c = "omega_pll", theta_c = "theta_pll_next", theta_rel = "theta_pll_rel_next",
                theta_vsm_rel = "theta_rel"),
        converter_vsm(names[3], e, equilibrium, m.sync) =>
            (; theta_c = "theta_next", theta_rel = "theta_rel_next"),
        converter_reactive(names[4], e, equilibrium, delta.outer_reactive) =>
            (; i_q_ref = "q_voltage_ref"),
        converter_ccvi(names[5], e, equilibrium, delta.vi) => (;),
        converter_occ(names[6], e, equilibrium, delta.occ) => (;),
        mmc_sigma(names[7], e, equilibrium, transforms) => (;),
        mmc_modulation(names[8], e, equilibrium, transforms, context.settings) => (;)]
    return controls
end

function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.MMC}, context)
    connected = filter(t -> !t.grounded, e.terminals)
    length(connected) == 2 && any(t -> t.side == 1 && t.bus.domain == 2, connected) &&
    any(t -> t.side == 2 && t.bus.domain == 1, connected) ||
        throw(ArgumentError("converter :$(e.name) requires DC side 1 and AC side 2"))
    dc, ac = only(filter(t -> t.side == 1, connected)),
    only(filter(t -> t.side == 2, connected))
    bus = _ac_bus(e, ac, context)
    _terminal_bus(e, dc, context)
    m = e.model
    m.sync isa Union{PowerImpedance.PLLSynchronization, PowerImpedance.VSEWithDamping} ||
        not_exportable(e, m.sync)
    m.delta_control isa Union{PowerImpedance.ΔdqControlGFL, PowerImpedance.ΔdqControlGFM} ||
        not_exportable(e, m.delta_control)
    m.sigma_control isa Union{PowerImpedance.ΣdqzControlTEC, PowerImpedance.ΣdqzControlLEC} ||
        not_exportable(e, m.sigma_control)
    m.modulation isa Union{PowerImpedance.UncompensatedModulation, PowerImpedance.CompensatedModulation} ||
        not_exportable(e, m.modulation)
    m.delta_control.occ isa PowerImpedance.InnerCurrentPIControl ||
        not_exportable(e, m.delta_control.occ)
    isapprox(m.elec.ωbase, 2π * context.settings.frequency; rtol = 1e-12) ||
        throw(ArgumentError("converter :$(e.name) frequency differs from the network frame"))
    haskey(context.netlist.operating_point.branch_flows, e.name) ||
        throw(ArgumentError("converter :$(e.name) requires solved operating-point data"))
    si = mmc_si(m.elec)
    all(x -> isfinite(x) && x >= 0, (si.L_r, si.R_r, si.R_arm)) && si.L_arm > 0 &&
    si.C_SM > 0 && si.N > 0 &&
    isfinite(si.turnsRatio) && si.turnsRatio > 0 ||
        throw(ArgumentError("converter :$(e.name) has invalid MMC electrical parameters"))
    equilibrium = converter_equilibrium(e)
    controls = mmc_controls(state, e, equilibrium, context, m.delta_control)
    append!(state.modules, first.(controls))
    canvas = mmc_electrical_canvas(e, equilibrium, si)
    converter_angle_snapshot!(canvas, e, equilibrium; origin = (5400, 2160))
    capacitor_measurements = (; (Symbol("v_Ctot_" * half * "_" * phase) =>
        "v_Cmeas_" * half * "_" * phase for half in ("u", "l") for phase in ("a", "b", "c"))...)
    for (i, (definition, signals)) in enumerate(controls)
        converter_instance!(canvas, definition, context.name,
            (5400 + 540 * ((i - 1) ÷ 3), 108 + 540 * ((i - 1) % 3)),
            merge(capacitor_measurements, signals))
    end
    outputs = ["P_ac_f", "Q_ac_f", "v_dc_f", "omega_c", "theta_c",
        ["v_Ctot_" * half * "_" * phase for half in ("u", "l") for phase in ("a", "b", "c")]..., "iS_z"]
    lower!(canvas, BlockGraph(ControlBlock[Export(n, Signal(n)) for n in outputs]); origin = (
        7200, 108))
    ports = [ModulePortPlan("AC", :electrical, 54, 0, 3),
        ModulePortPlan("DC_P", :electrical, -54, 0),
        ModulePortPlan("DC_N", :electrical, -54, 36)]
    append!(ports, [ModulePortPlan(n, :output, 54, 72 + 36 * (i - 1))
                    for (i, n) in enumerate(outputs)])
    name = pscad_name("MMC_" * e.pscad; used = state.used)
    push!(state.modules, ModuleDefinitionPlan(name, ModuleParameterPlan[], ports, canvas))
    x, y = allocate_cell!(state.layout)
    state.layout.next += 12
    point = (x + 144, y + 108)
    push!(state.main.components,
        ModuleInstancePlan(context.name * ":" * name, Pair{String, String}[], point..., 0))
    ac_current = current_probe!(state, e, ac, context; orientation = :out)
    ammeter_stub!(state.main, (point[1] + 54, point[2]), bus.name, ac_current)
    dc_current = current_probe!(state, e, dc, context; orientation = :into)
    positive, negative = context.dc_labels[dc.bus]
    ammeter_stub!(
        state.main, (point[1] - 54, point[2]), positive, dc_current; direction = -1)
    stub!(state.main, (point[1] - 54, point[2] + 36), negative; direction = -1)
    for (i, signal) in enumerate(outputs)
        probe = pscad_name(e.pscad * "_" * signal; used = state.used)
        kind = signal == "P_ac_f" ? :converter_p :
               signal == "Q_ac_f" ? :converter_q :
               signal == "omega_c" && m.sync isa PowerImpedance.VSEWithDamping ? :machine_speed :
               startswith(signal, "v_Ctot_") ? :converter_arm_voltage :
               signal == "iS_z" ? :converter_sum_current : :converter_diagnostic
        unit = signal == "theta_c" ? "rad" : startswith(signal, "v_Ctot_") ? "kV" : "pu"
        push!(state.channels, ProbeChannel(
            probe, kind, bus.name, string(e.name), "2", 1, unit))
        module_signal_stub!(state.main, (point[1] + 54, point[2] + 72 + 36 * (i - 1)), probe, 1)
        px, py = allocate_cell!(state.layout)
        output_probe!(state.main, probe, "converter", unit, (px + 126, py + 72))
    end
    for probe in (ac_current, dc_current)
        px, py = allocate_cell!(state.layout)
        output_probe!(state.main, probe, "branch", "kA", (px + 126, py + 72))
    end
    return nothing
end
