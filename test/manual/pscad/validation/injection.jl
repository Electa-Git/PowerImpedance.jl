# Component provenance, including every field/port used below:
# - src/PSCAD/emitters/tlc.jl:tlc_electrical_canvas: source_1 (saved
#   local/TLC/Simple_2L_VSC_RL.pscx:3383–3388,3452–3529), breakout, xnode,
#   electrical and scalar control stubs. No converter reactor is added here.
# - src/PSCAD/blocks.jl:lower!: TimeStep, Compare, Gain, Const, Sum, Trig,
#   Mult, ArrayMerge, ArraySplit, DqToAbc. All master fields come from these
#   existing lowerers, not from a new master-library parameter dictionary.
# - src/PSCAD/blocks.jl:dq_to_abc_module (saved TLC dq2abc canvas at line 1851).
# - src/PSCAD/plan.jl:ModuleDefinitionPlan and blocks.jl:lower!(parameters)
#   bind named amplitude gains; ext/PowerImpedancePSCADExt/writer.jl writes
#   their declared forms and instance values with the existing parameter API.
# - src/PSCAD/emitters/sources.jl and probes.jl: source terminal location,
#   retained ammeter, bus voltmeters and PGB fields.

function tone_graph(settings)
    get(settings, :stimulus, "multitone") == "hann_burst" && return burst_graph(settings)
    graph = P.BlockGraph()
    clock, enabled = P.Signal.(("validation_clock_s", "injection_enabled"))
    append!(graph.nodes, P.ControlBlock[P.TimeStep(clock),
        P.Compare(clock, enabled, settings.injection_time)])
    accumulated = P.Signal("tone_zero")
    push!(graph.nodes, P.Const(accumulated, 0.0))
    for (index, (frequency, phase)) in enumerate(zip(settings.frequencies, settings.phases))
        arg, offset, shifted, tone, scaled, total = P.Signal.(
            ["tone_arg_$index", "tone_phase_$index", "tone_shifted_$index",
            "tone_cos_$index", "tone_scaled_$index", "tone_sum_$index"])
        append!(graph.nodes,
            P.ControlBlock[P.Gain(clock, arg, 2π * frequency),
                P.Const(offset, phase), P.Sum([arg, offset], [1, 1], shifted),
                P.Trig(shifted, tone, :cos),
                P.Gain(tone, scaled, settings.voltage_base_kV),
                P.Sum([accumulated, scaled], [1, 1], total)])
        accumulated = total
    end
    perturbation = P.Signal("voltage_perturbation")
    push!(graph.nodes, P.Mult(accumulated, enabled, perturbation))
    return graph, perturbation, clock
end

function voltage_port(project, settings, peak_kV, angle_rad; name = "VoltagePort")
    graph, perturbation, clock = tone_graph(settings)
    d0, q0, delta_d, delta_q, d, q, dq, theta, abc = P.Signal.(
        ["nominal_d", "nominal_q", "perturbation_d", "perturbation_q",
        "voltage_d", "voltage_q", "voltage_dq",
        "nominal_theta", "vM_abc"])
    phase_domain = get(settings, :dimension, 2) == 3
    append!(graph.nodes,
        P.ControlBlock[
            P.Const(d0, peak_kV * cos(angle_rad)), P.Const(q0, -peak_kV * sin(angle_rad)),
            phase_domain ? P.Const(delta_d, 0.0) : P.Gain(perturbation, delta_d, "d_amplitude_pu"),
            phase_domain ? P.Const(delta_q, 0.0) : P.Gain(perturbation, delta_q, "q_amplitude_pu"),
            P.Sum([d0, delta_d], [1, 1], d),
            P.Sum([q0, delta_q], [1, 1], q),
            P.ArrayMerge([d, q], dq), P.Gain(clock, theta, 2π * settings.frequency),
            P.DqToAbc(dq, theta, abc, project * ":Validation_DQ_ABC")])
    canvas = P.CanvasPlan()
    for (phase, y) in enumerate((108, 216, 324))
        signal = P.Signal("v_phase_$phase")
        if phase_domain
            nominal, delta = P.Signal.( ["nominal_phase_$phase", "delta_phase_$phase"] )
            append!(graph.nodes, P.ControlBlock[P.ArraySplit(abc, nominal, phase),
                P.Gain(perturbation, delta, "$( ("a", "b", "c")[phase] )_amplitude_pu"),
                P.Sum([nominal, delta], [1, 1], signal)])
        else
            push!(graph.nodes, P.ArraySplit(abc, signal, phase))
        end
        push!(canvas.components,
            P.ComponentPlan("master:source_1",
                ["Name" => "phase$phase", "Type" => "6", "Grnd" => "1", "Spec" => "0",
                    "Cntrl" => "1", "AC" => "0", "Tc" => "0.0 [s]"], 180, y, 4))
        P.module_signal_stub!(canvas, (180, y + 36), signal.name, -1)
        node = "phase_terminal_$phase"
        P.stub!(canvas, (216, y), node)
        P.stub!(canvas, (576, 216 + 36 * (phase - 2)), node; direction = -1)
    end
    push!(canvas.components, P.ComponentPlan(
        "master:breakout", ["Dis" => "0", "Com" => "0"], 612, 216, 4))
    P.stub!(canvas, (612, 216), "source_ac")
    P.component!(canvas, "xnode", (900, 216), ["Name" => "AC"])
    P.stub!(canvas, (900, 216), "source_ac"; direction = -1)
    P.lower!(canvas, graph; origin = (72, 504))
    ports = [P.ModulePortPlan("AC", :electrical, 36, 0, 3)]
    parameters = [P.ModuleParameterPlan("$(axis)_amplitude_pu", 0.0, "")
        for axis in (phase_domain ? ("a", "b", "c") : ("d", "q"))]
    return P.ModuleDefinitionPlan(name, parameters, ports, canvas)
end

function l1_plan(netlist, name, axis)
    axis in (:baseline, :d, :q) || throw(ArgumentError("unknown injection axis"))
    spec = l1_settings()
    settings = P.SimulationSettings(simulation_time = spec.simulation_time,
        time_step = spec.time_step, sample_step = spec.sample_step,
        frequency = spec.frequency, source_ramp = 0.0, output_stem = "scan")
    plan = P.build_plan(netlist; settings, name, dc_reference = :none)
    index = only(findall(
        c -> c isa P.ComponentPlan && c.defn == "master:source_3" &&
             Dict(c.params)["Name"] == "grid_a",
        plan.main.components))
    source = plan.main.components[index]
    params = Dict(source.params)
    peak_kV = parse(Float64, first(split(params["Vm"]))) * sqrt(2 / 3)
    angle_rad = deg2rad(parse(Float64, first(split(params["Ph"]))) - 90)
    push!(plan.modules, P.dq_to_abc_module("Validation_DQ_ABC"))
    push!(plan.modules, voltage_port(name, spec, peak_kV, angle_rad))
    # The original source's sole AC terminal and all probes/wires remain at
    # exactly the same coordinates. The new module exposes that same terminal.
    plan.main.components[index] = P.ModuleInstancePlan(name * ":VoltagePort",
        ["d_amplitude_pu" => string(axis == :d ? spec.tone_peak_pu : 0.0),
            "q_amplitude_pu" => string(axis == :q ? spec.tone_peak_pu : 0.0)],
        source.x, source.y, source.orient)
    P.check_connectivity(plan)
    return (; plan, settings)
end

# Clone the emitted baseline byte for byte, changing only the driven amplitude.
# The exact param spelling is produced by write_component!(ModuleInstancePlan).
# No module IDs, namespaces, settings or signal paths are regenerated.
function injection_project(baseline::String, axis)
    axis in (:baseline, :d, :q) || throw(ArgumentError("unknown injection axis"))
    for component in (:d, :q)
        parameter = "<param name=\"$(component)_amplitude_pu\" value=\"0.0\"/>"
        length(findall(parameter, baseline)) == 1 ||
            error("expected exactly one zero-valued $component amplitude instance parameter")
    end
    axis == :baseline && return baseline
    before = "<param name=\"$(axis)_amplitude_pu\" value=\"0.0\"/>"
    after = "<param name=\"$(axis)_amplitude_pu\" value=\"$(l1_settings().tone_peak_pu)\"/>"
    return replace(baseline, before => after; count = 1)
end

function reference_admittance(net)
    return cat(
        (PowerImpedance.get_y(net.elements[:branch], ComplexF64(im * 2π * f))[1:2, 1:2]
        for f in l1_settings().frequencies)...;
        dims = 3)
end
