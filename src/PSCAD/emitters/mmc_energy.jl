# MMC/energy.jl:67–151 and inner_current.jl:81–104. The fixed-frame
# integrators implement x' = u - J_frame*x, including the zero-sequence axis.
# Every block is an existing M4/M6a primitive; no transfer-function guesses.
function mmc_rotating_integrators!(
        graph, parameters, inputs, states, initial, frame, prefix)
    for (i, (input, state, value)) in enumerate(zip(inputs, states, initial))
        rate = Signal(prefix * "rate" * string(i))
        if iszero(frame)
            push!(graph.nodes, Gain(input, rate, 1.0))
        else
            other = states[3 - i]
            cross = Signal(prefix * "cross" * string(i))
            rotation = converter_parameter!(parameters, prefix * "rotation" * string(i),
                i == 1 ? -frame : frame)
            push!(graph.nodes, Gain(other, cross, rotation))
            push!(graph.nodes, Sum([input, cross], [1, 1], rate))
        end
        y0 = converter_parameter!(parameters, prefix * "initial" * string(i), value)
        push!(graph.nodes, Integrator(rate, state, 1.0, y0, -1e8, 1e8))
    end
end

function mmc_energy_loop!(
        graph, parameters, energy, initial, pi, reference, wn, frame, prefix)
    first_states = Signal.([prefix * "F1" * string(i) for i in eachindex(energy)])
    second_states = Signal.([prefix * "F2" * string(i) for i in eachindex(energy)])
    integral_states = Signal.([prefix * "xi" * string(i) for i in eachindex(energy)])
    first_inputs, second_inputs, integral_inputs, outputs = (Signal[] for _ in 1:4)
    damping = converter_parameter!(parameters, prefix * "damping", sqrt(2) * wn)
    square_frequency = converter_parameter!(parameters, prefix * "wn2", -wn^2)
    kp = converter_parameter!(parameters, prefix * "Kp", pi.Kp)
    ki = converter_parameter!(parameters, prefix * "Ki", pi.Ki)
    for (i, input) in enumerate(energy)
        filtered, damped, forcing, error, rate, proportional, output = Signal.([prefix *
                                                                                stem *
                                                                                string(i)
                                                                                for stem in ("filtered", "damped", "forcing", "error", "kirate", "proportional", "output")])
        ref = converter_parameter!(parameters, prefix * "ref" * string(i), reference[i])
        append!(graph.nodes,
            ControlBlock[
                Sum([input, first_states[i]], [1, 1], filtered), Gain(filtered, damped, damping),
                Sum([second_states[i], damped], [1, -1], forcing),
                Gain(first_states[i], Signal(prefix * "secondforcing" * string(i)), square_frequency),
                Import(ref, Signal(ref)), Sum([Signal(ref), filtered], [1, -1], error),
                Gain(error, rate, ki), Gain(error, proportional, kp),
                Sum([integral_states[i], proportional], [1, 1], output)])
        push!(first_inputs, forcing)
        push!(second_inputs, Signal(prefix * "secondforcing" * string(i)))
        push!(integral_inputs, rate)
        push!(outputs, output)
    end
    mmc_rotating_integrators!(
        graph, parameters, first_inputs, first_states, initial[1], frame, prefix * "first")
    mmc_rotating_integrators!(graph, parameters, second_inputs, second_states,
        initial[2], frame, prefix * "second")
    mmc_rotating_integrators!(graph, parameters, integral_inputs,
        integral_states, initial[3], frame, prefix * "pi")
    return outputs
end

function mmc_sigma(name, e, equilibrium, transforms, block::PowerImpedance.ΣdqzControlLEC)
    block.wsigma isa PowerImpedance.ΣEnergyControl || not_exportable(e, block.wsigma)
    block.wdelta isa PowerImpedance.ΔEnergyControl || not_exportable(e, block.wdelta)
    block.ccc isa PowerImpedance.CirculatingCurrentControl || not_exportable(e, block.ccc)
    m, x = e.model, equilibrium.states
    parameters = ModuleParameterPlan[]
    inputs = [("iS_abc", 3), ("P_ac_f", 1), ("v_dc_f", 1), ("v_dc_divisor", 1)]
    append!(inputs, [("v_Ctot_" * arm * "_" * phase, 1)
                     for arm in ("u", "l") for phase in ("a", "b", "c")])
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for (n, _) in inputs])
    clock = Signal("lec_clock_s")
    nominal_omega = converter_parameter!(parameters, "nominalOmega", m.elec.ωbase)
    append!(graph.nodes,
        ControlBlock[TimeStep(clock),
            Gain(clock, Signal("lec_angle"), nominal_omega),
            Gain(Signal("lec_angle"), Signal("lec_sigma_angle"), -2.0),
            Gain(Signal("lec_angle"), Signal("lec_triplen_angle"), 3.0)])
    invcurrent = converter_parameter!(parameters, "invIbase", m.elec.vDC_base /
                                                              m.elec.Sbase)
    append!(graph.nodes,
        ControlBlock[
            AbcToDq(Signal("iS_abc"), Signal("lec_sigma_angle"), Signal("lec_i_dq"), transforms.abc)])
    for (i, axis) in enumerate(("d", "q"))
        append!(graph.nodes,
            ControlBlock[
                ArraySplit(Signal("lec_i_dq"), Signal("lec_i_" * axis * "_si"), i),
                Gain(
                    Signal("lec_i_" * axis * "_si"), Signal("lec_i_" * axis *
                                                            "_measured"), invcurrent),
                Gain(Signal("lec_i_" * axis * "_measured"), Signal("iS_" * axis), 1.0)])
    end
    currents, sum_energy, delta_energy = (Signal[] for _ in 1:3)
    invcap = converter_parameter!(parameters, "invVbase", 1 / m.elec.vDC_base)
    for (i, phase) in enumerate(("a", "b", "c"))
        current = Signal("lec_i_" * phase)
        push!(graph.nodes, ArraySplit(Signal("iS_abc"), current, i))
        push!(currents, current)
        for arm in ("u", "l")
            stem = arm * "_" * phase
            append!(graph.nodes,
                ControlBlock[
                    Gain(Signal("v_Ctot_" * stem), Signal("lec_cap_" * stem), invcap),
                    Square(Signal("lec_cap_" * stem), Signal("lec_energy_" * stem))])
        end
        sigma, delta = Signal.(["lec_sum_" * phase, "lec_delta_" * phase])
        # 2*wΣ = (vu²+vl²)/Vbase²; -2*wΔ = (vl²-vu²)/Vbase².
        push!(graph.nodes, Sum(
            Signal.(["lec_energy_u_" * phase, "lec_energy_l_" * phase]), [
                1, 1], sigma))
        push!(graph.nodes, Sum(
            Signal.(["lec_energy_l_" * phase, "lec_energy_u_" * phase]), [
                1, -1], delta))
        push!(sum_energy, sigma)
        push!(delta_energy, delta)
    end
    append!(graph.nodes,
        ControlBlock[Sum(currents, [1, 1, 1], Signal("lec_i_sum")),
            Gain(Signal("lec_i_sum"), Signal("lec_i_z_measured"), m.elec.vDC_base /
                                                                  (3m.elec.Sbase)),
            Gain(Signal("lec_i_z_measured"), Signal("iS_z"), 1.0),
            ArrayMerge(sum_energy, Signal("lec_sum_abc")),
            ArrayMerge(delta_energy, Signal("lec_delta_abc")),
            AbcToDq(Signal("lec_sum_abc"), Signal("lec_sigma_angle"), Signal("lec_sum_dq"), transforms.abc),
            AbcToDq(Signal("lec_delta_abc"), Signal("lec_angle"), Signal("lec_delta_dq"), transforms.abc),
            Const(Signal("lec_legs"), 3.0),
            Sum(sum_energy, [1, 1, 1], Signal("lec_sum_all")),
            Div(Signal("lec_sum_all"), Signal("lec_legs"), Signal("lec_sum_z_measured")),
            Sum(delta_energy, [1, 1, 1], Signal("lec_delta_all")),
            Gain(Signal("lec_delta_all"), Signal("lec_delta_twice"), 2.0),
            Div(Signal("lec_delta_twice"), Signal("lec_legs"), Signal("lec_delta_zero"))])
    for (i, axis) in enumerate(("d", "q")), stem in ("sum", "delta")

        push!(graph.nodes,
            ArraySplit(
                Signal("lec_" * stem * "_dq"), Signal("lec_" * stem * "_" * axis *
                                                      "_measured"), i))
    end
    # Synchronous lifting of the scalar triplen energy into its two quadratures.
    # Its cycle means are Julia's Zd/Zq; the abc plant retains the 6ω ripple.
    for (axis, kind) in (("Zd", :cos), ("Zq", :sin))
        carrier = Signal("lec_triplen_" * axis)
        append!(graph.nodes,
            ControlBlock[Trig(Signal("lec_triplen_angle"), carrier, kind),
                Mult(Signal("lec_delta_zero"), carrier, Signal("lec_delta_" * axis *
                                                               "_measured"))])
    end
    # All seven capacitor-energy inputs and all current feedback are live.
    for (stem, axes) in (("sum", ("d", "q", "z")),
        ("delta", ("d", "q", "Zd", "Zq")))
        for axis in axes
            push!(graph.nodes,
                Gain(Signal("lec_" * stem * "_" * axis * "_measured"),
                    Signal("lec_" * stem * "_" * axis), 1.0))
        end
    end
    omega = m.elec.ωbase
    sigma_outputs = Signal[]
    for (axes, frame, refs, prefix) in ((("d", "q"), -2omega, [0.0, 0.0], "wsdq"),
        (("z",), 0.0, [2block.wsigma.ref], "wsz"))
        states = [[getproperty(x, Symbol(stem * axis)) for axis in axes]
                  for stem in ("FΣ1_", "FΣ2_", "ξ_wΣ_")]
        append!(sigma_outputs,
            mmc_energy_loop!(graph, parameters,
                Signal.(["lec_sum_" * axis for axis in axes]), states,
                block.wsigma.pi_control, refs, 2omega, frame, prefix))
    end
    delta_outputs = Signal[]
    for (axes, frame, prefix) in ((("d", "q"), omega, "wddq"), (
        ("Zd", "Zq"), 3omega, "wdZ"))
        states = [[getproperty(x, Symbol(stem * axis)) for axis in axes]
                  for stem in ("FΔ1_", "FΔ2_", "ξ_wΔ_")]
        append!(delta_outputs,
            mmc_energy_loop!(graph, parameters,
                Signal.(["lec_delta_" * axis for axis in axes]), states,
                block.wdelta.pi_control, [0.0, 0.0], omega, frame, prefix))
    end
    append!(graph.nodes,
        ControlBlock[
            Gain(Signal("P_ac_f"), Signal("lec_third_power"), 1/3),
            Sum([sigma_outputs[3], Signal("lec_third_power")], [1, 1], Signal("lec_zero_power")),
            Sum(delta_outputs[[1, 3]], [1, 1], Signal("lec_delta_d_sum")),
            Gain(Signal("lec_delta_d_sum"), Signal("lec_delta_d_ref"), 3/4),
            Sum(delta_outputs[[2, 4]], [1, 1], Signal("lec_delta_q_sum")),
            Gain(Signal("lec_delta_q_sum"), Signal("lec_delta_q_ref"), -3/4)])
    errors = Signal[]
    for (axis, power) in zip(("d", "q", "z"), [
        sigma_outputs[1], sigma_outputs[2], Signal("lec_zero_power")])
        dc_ref, ref, error = Signal.(["lec_dc_" * axis * "_ref", "lec_i_" * axis * "_ref",
            "lec_ccc_" * axis * "_error"])
        push!(graph.nodes, Div(power, Signal("v_dc_divisor"), dc_ref))
        if axis == "z"
            push!(graph.nodes, Gain(dc_ref, ref, 1.0))
        else
            push!(graph.nodes, Sum([dc_ref, Signal("lec_delta_" * axis * "_ref")], [1, 1], ref))
        end
        push!(graph.nodes, Sum([ref, Signal("iS_" * axis)], [1, -1], error))
        push!(errors, error)
    end
    ccc_integrals, ccc_forcing = (Signal[] for _ in 1:2)
    ki = converter_parameter!(parameters, "cccKi", block.ccc.pi_control.Ki)
    kp = converter_parameter!(parameters, "cccKp", block.ccc.pi_control.Kp)
    for (axis, error) in zip(("d", "q", "z"), errors)
        integral, rate = Signal.([
            "lec_ccc_" * axis * "_xi", "lec_ccc_" * axis * "_forcing"])
        push!(graph.nodes, Gain(error, rate, ki))
        push!(ccc_integrals, integral)
        push!(ccc_forcing, rate)
        append!(graph.nodes,
            ControlBlock[Gain(error, Signal("lec_ccc_" * axis * "_p"), kp),
                Sum([integral, Signal("lec_ccc_" * axis * "_p")],
                    [-1, -1], Signal("lec_ccc_" * axis * "_voltage"))])
    end
    mmc_rotating_integrators!(graph, parameters, ccc_forcing[1:2], ccc_integrals[1:2],
        [x.ξ_iΣ_d, x.ξ_iΣ_q], -2omega, "cccdq")
    mmc_rotating_integrators!(
        graph, parameters, ccc_forcing[3:3], ccc_integrals[3:3], [x.ξ_iΣ_z], 0.0, "cccz")
    append!(graph.nodes,
        ControlBlock[Gain(Signal("v_dc_f"), Signal("lec_half_dc"), 0.5),
            Sum([Signal("lec_ccc_z_voltage"), Signal("lec_half_dc")], [1, 1], Signal("vMS_z_ref")),
            Export("vMS_d_ref", Signal("lec_ccc_d_voltage")),
            Export("vMS_q_ref", Signal("lec_ccc_q_voltage")),
            Export("vMS_z_ref", Signal("vMS_z_ref")), Export("iS_z", Signal("iS_z"))])
    return converter_definition(name, parameters, graph, inputs,
        [(n, 1) for n in ("vMS_d_ref", "vMS_q_ref", "vMS_z_ref", "iS_z")])
end

function mmc_modulation(name, e, equilibrium, transforms, settings,
        block::PowerImpedance.CompensatedModulation)
    m = e.model
    parameters = ModuleParameterPlan[]
    inputs = [(n, 1)
              for n in ("vM_d_ref", "vM_q_ref", "vMS_d_ref", "vMS_q_ref", "vMS_z_ref", "theta_c")]
    append!(inputs, [("v_Ctot_" * arm * "_" * phase, 1)
                     for arm in ("u", "l") for phase in ("a", "b", "c")])
    graph = BlockGraph(ControlBlock[Import(n, Signal(n)) for (n, _) in inputs])
    # CompensatedModulation leaves Σ in the grid frame (modulation.jl:139).
    # Its Δ refs remain on the AC voltage base, Σ refs on the DC voltage base.
    sigma_angle = Signal("comp_sigma_angle")
    sigma_omega = converter_parameter!(parameters, "sigmaOmega", -2m.elec.ωbase)
    append!(graph.nodes,
        ControlBlock[TimeStep(Signal("comp_clock_s")),
            Gain(Signal("comp_clock_s"), sigma_angle, sigma_omega),
            ArrayMerge(Signal.(["vM_d_ref", "vM_q_ref"]), Signal("comp_delta_dq")),
            ArrayMerge(Signal.(["vMS_d_ref", "vMS_q_ref"]), Signal("comp_sigma_dq")),
            DqToAbc(Signal("comp_delta_dq"), Signal("theta_c"), Signal("comp_delta_abc"), transforms.dq),
            DqToAbc(Signal("comp_sigma_dq"), sigma_angle, Signal("comp_sigma_abc"), transforms.dq)])
    dcbase = converter_parameter!(parameters, "DCbase", m.elec.vDC_base)
    acbase = converter_parameter!(parameters, "ACbase", m.elec.vAC_base)
    push!(graph.nodes, Gain(Signal("vMS_z_ref"), Signal("comp_zero_kV"), dcbase))
    delay = block.delay1
    residual = _converter_export_delay(delay.timeDelay, settings.time_step; converter = e.name)
    caps = mmc_arm_capacitors(equilibrium.states, m.elec.vDC_base)
    theta0 = PowerImpedance.syncangle(m.sync, equilibrium.states)
    phases = (0.0, -2π/3, 2π/3)
    delta0 = equilibrium.outputs.delta
    sigma0 = equilibrium.outputs.sigma
    outputs = Tuple{String, Int}[]
    for (i, phase) in enumerate(("a", "b", "c"))
        append!(graph.nodes,
            ControlBlock[
                ArraySplit(Signal("comp_delta_abc"), Signal("comp_delta_" * phase), i),
                Gain(Signal("comp_delta_" * phase), Signal("comp_delta_" * phase * "_kV"), acbase),
                ArraySplit(Signal("comp_sigma_abc"), Signal("comp_sigma_" * phase), i),
                Gain(Signal("comp_sigma_" * phase), Signal("comp_sigma_" * phase * "_kV"), dcbase),
                Sum(Signal.(["comp_sigma_" * phase * "_kV", "comp_zero_kV"]),
                    [1, 1], Signal("comp_total_" * phase))])
        vd0 = m.elec.vAC_base * (delta0.vMΔ_d_ref_c*cos(phases[i] + theta0) +
               delta0.vMΔ_q_ref_c*sin(phases[i] + theta0))
        vs0 = m.elec.vDC_base * (sigma0.vMΣ_z_ref + sigma0.vMΣ_d_ref_c*cos(-2phases[i]) +
               sigma0.vMΣ_q_ref_c*sin(-2phases[i]))
        for (arm, sign, cap) in (("u", -1, caps.upper[i]), ("l", 1, caps.lower[i]))
            stem = arm * "_" * phase
            voltage, raw, output = Signal.([
                "comp_voltage_" * stem, "comp_raw_" * stem, "m_" * stem])
            append!(graph.nodes,
                ControlBlock[
                    Sum(
                        Signal.(["comp_total_" * phase, "comp_delta_" * phase * "_kV"]), [
                            1, sign], voltage),
                    Div(voltage, Signal("v_Ctot_" * stem), raw)])
            if iszero(residual)
                push!(graph.nodes, Gain(raw, output, 1.0))
            else
                td = converter_parameter!(parameters, "arm" * stem * "Td", residual, "s")
                y0 = converter_parameter!(parameters, "arm" * stem * "Y0", (vs0 + sign*vd0)/cap)
                push!(graph.nodes,
                    Delay(raw, output, td,
                        ceil(Int, residual/settings.time_step) + 1, y0))
            end
            push!(graph.nodes, Export(output.name, output))
            push!(outputs, (output.name, 1))
        end
    end
    return converter_definition(name, parameters, graph, inputs, outputs)
end
