# DC voltage sources: fields/NA/NB/control pins are owned by sources.jl and
# plan.jl:component_ports; Cntrl=1 instantaneous mode is the validated TLC stage.
# Current injection: tlc.jl:tlc_electrical_canvas and saved TLC lines 5589–5630.
# +command injects out of upper A (the station sign witness at tlc.jl:172–175).
# Meters, stubs, breakout and PGBs use the same existing primitive emitters.
function dc_voltage_port(name, spec, nominal)
    graph, perturbation, _ = tone_graph(merge(spec, (;
        voltage_base_kV = spec.voltage_base_kV / 2)))
    delta, fixed, voltage = P.Signal.(["dc_delta", "dc_nominal", "dc_voltage"])
    append!(graph.nodes,
        P.ControlBlock[P.Gain(perturbation, delta, "amplitude_pu"),
            P.Const(fixed, nominal), P.Sum([fixed, delta], [1, 1], voltage)])
    canvas = P.CanvasPlan()
    P.component!(canvas,
        "source_1",
        (180, 108),
        ["Name" => "controlled_pole", "Type" => "6",
            "Grnd" => "0", "Spec" => "0", "Cntrl" => "1", "AC" => "0", "Tc" => "0.0 [s]"])
    P.module_signal_stub!(canvas, (180, 144), voltage.name, -1)
    for (point, node, y) in (((144, 108), "POS", 108), ((216, 108), "NEG", 216))
        P.stub!(canvas, point, node)
        P.component!(canvas, "xnode", (900, y), ["Name" => node])
        P.stub!(canvas, (900, y), node; direction = -1)
    end
    P.lower!(canvas, graph; origin = (72, 504))
    return P.ModuleDefinitionPlan(
        name, P.ModuleParameterPlan[P.ModuleParameterPlan("amplitude_pu", 0.0, "")],
        [
            P.ModulePortPlan("POS", :electrical, -36, 0), P.ModulePortPlan("NEG", :electrical, 36, 0)], canvas)
end

function current_port(project, name, spec)
    graph, perturbation, clock = tone_graph(merge(spec, (;
        voltage_base_kV = spec.current_base_kA)))
    d, q, dq, theta, abc = P.Signal.([
        "injection_d", "injection_q", "injection_dq", "theta", "injection_abc"])
    if spec.dimension == 3
        phases = [P.Signal("injection_phase_$phase") for phase in ("a", "b", "c")]
        append!(graph.nodes, [P.Gain(perturbation, phases[k], "$( ("a", "b", "c")[k] )_amplitude_pu")
            for k in 1:3])
        push!(graph.nodes, P.ArrayMerge(phases, abc))
    else
    append!(graph.nodes,
        P.ControlBlock[P.Gain(perturbation, d, "d_amplitude_pu"),
            P.Gain(perturbation, q, "q_amplitude_pu"), P.ArrayMerge([d, q], dq),
            P.Gain(clock, theta, 2π * spec.frequency), P.DqToAbc(
                dq, theta, abc, project * ":Validation_DQ_ABC")])
    end
    canvas = P.CanvasPlan()
    measured = P.Signal[]
    for (phase, y) in enumerate((108, 216, 324))
        command = P.Signal("command_$phase")
        current = P.Signal("measured_$phase")
        push!(measured, current)
        push!(graph.nodes, P.ArraySplit(abc, command, phase))
        push!(canvas.components,
            P.ComponentPlan("master:src_ccin_1",
                ["Name" => "phase$phase", "Cntrl" => "1", "Tc" => "0.0 [s]"], 180, y, 1))
        P.module_signal_stub!(canvas, (144, y), command.name, -1)
        # Upper A injects outwards. Upper A -> ammeter -> AC, lower B -> ground.
        P.stub!(canvas, (180, y), "inner_$phase")
        P.stub!(canvas, (180, y + 36), nothing)
        P.component!(canvas, "ammeter", (324, y), ["Name" => current.name])
        P.stub!(canvas, (324, y), "inner_$phase"; direction = -1)
        P.stub!(canvas, (360, y), "phase_$phase")
        P.stub!(canvas, (576, 216 + 36 * (phase - 2)), "phase_$phase"; direction = -1)
    end
    push!(canvas.components, P.ComponentPlan(
        "master:breakout", ["Dis" => "0", "Com" => "0"], 612, 216, 4))
    P.stub!(canvas, (612, 216), "ac_terminal")
    P.component!(canvas, "xnode", (900, 216), ["Name" => "AC"])
    P.stub!(canvas, (900, 216), "ac_terminal"; direction = -1)
    output = P.Signal("measured_abc")
    append!(graph.nodes, P.ControlBlock[P.ArrayMerge(measured, output), P.Export("MEASURED", output)])
    P.lower!(canvas, graph; origin = (72, 504))
    parameters = [P.ModuleParameterPlan("$(axis)_amplitude_pu", 0.0, "")
        for axis in (spec.dimension == 3 ? ("a", "b", "c") : ("d", "q"))]
    ports = [P.ModulePortPlan("AC", :electrical, 36, 0, 3),
        P.ModulePortPlan("MEASURED", :output, 0, 72, 3)]
    return P.ModuleDefinitionPlan(name, parameters, ports, canvas)
end

function scan_plan(list, spec, axis; name = lowercase(replace(spec.id, '-' => '_')))
    axis == "baseline" || axis in spec.axes || error("unknown scan axis $axis")
    settings = scan_settings(spec)
    if spec.id == "L1-01"
        # Preserve the proven graph, fields, source replacement and probe map.
        plan = P.build_plan(list; settings, name, dc_reference = :none)
        index = only(findall(
            c -> c isa P.ComponentPlan && c.defn == "master:source_3" &&
                 Dict(c.params)["Name"] == "grid_a",
            plan.main.components))
        source = plan.main.components[index]
        params = Dict(source.params)
        peak = parse(Float64, first(split(params["Vm"]))) * sqrt(2 / 3)
        angle = deg2rad(parse(Float64, first(split(params["Ph"]))) - 90)
        push!(plan.modules, P.dq_to_abc_module("Validation_DQ_ABC"))
        push!(plan.modules, voltage_port(name, spec, peak, angle))
        plan.main.components[index] = P.ModuleInstancePlan(
            name * ":VoltagePort", amplitude_values(spec, axis, 1),
            source.x, source.y, source.orient)
        P.check_connectivity(plan)
        return plan, settings
    end
    # A resistive DC load is already grounded through its zero-voltage remote
    # reference. Disable auxiliary midpoint shunts so the native reduction and
    # PSCAD circuit both contain exactly the stated resistor termination.
    plan = P.build_plan(list; settings, name,
        dc_reference = get(spec,:dc_reference,get(spec,:dc_clamped,true) ? :midpoint_resistors : :none))
    (spec.dimension == 2 || spec.quantity == "Y" && spec.dimension == 3) &&
        push!(plan.modules, P.dq_to_abc_module("Validation_DQ_ABC"))
    current_drive = get(spec, :drive, "") == "current" || spec.quantity == "Z"
    for (port, bus) in enumerate(spec.buses)
        local_spec = merge(spec,
            (; voltage_base_kV = spec.voltage_bases[1 + (port - 1) * spec.dimension],
                current_base_kA = spec.current_bases[1 + (port - 1) * spec.dimension]))
        if spec.dimension == 1
            source_names = [e.pscad
                            for e in list.elements
                            if e.model isa PowerImpedance.Source &&
                any(t -> t.bus == bus.key, e.terminals)]
            source_name = only(source_names)
            for pole in ("P", "N")
                index = only(findall(
                    c -> c isa P.ComponentPlan && c.defn == "master:source_1" &&
                         Dict(c.params)["Name"] == source_name * "_" * pole,
                    plan.main.components))
                source = plan.main.components[index]
                nominal = parse(Float64, first(split(Dict(source.params)["Vm"])))
                module_name = "VoltagePole_$(port)_$pole"
                push!(plan.modules, dc_voltage_port(module_name, local_spec, nominal))
                plan.main.components[index] = P.ModuleInstancePlan(
                    name * ":" * module_name,
                    amplitude_values(spec, axis, port), source.x, source.y, source.orient)
            end
        else
            module_name = (current_drive ? "CurrentPort_" : "VoltagePort_") *
                          string(port)
            definition = current_drive ?
                         current_port(name, module_name, local_spec) :
                         voltage_port(name, local_spec, local_spec.voltage_base_kV,
                something(bus.va_rad, 0.0); name = module_name)
            push!(plan.modules, definition)
            existing = findfirst(
                c -> c isa P.ComponentPlan && c.defn == "master:source_3" &&
                     any(
                         e -> e.model isa PowerImpedance.Source &&
                              e.pscad == Dict(c.params)["Name"] &&
                              any(t -> t.bus == bus.key, e.terminals),
                         list.elements),
                plan.main.components)
            if !current_drive && existing !== nothing
                source = plan.main.components[existing]
                plan.main.components[existing] = P.ModuleInstancePlan(
                    name * ":" * module_name,
                    amplitude_values(spec, axis, port), source.x, source.y, source.orient)
            else
                x = maximum(c.x for c in plan.main.components) + 216
                y = 108 + 216 * port
                push!(plan.main.components,
                    P.ModuleInstancePlan(name * ":" * module_name,
                        amplitude_values(spec, axis, port), x, y, 0))
                P.stub!(plan.main, (x + 36, y), bus.name)
                if current_drive
                    probe = "I_injection_$port"
                    P.module_signal_stub!(plan.main, (x, y + 72), probe, 1)
                    P.output_probe!(plan.main, probe, "injection", "kA", (x + 108, y + 72))
                    push!(plan.probes.channels,
                        P.ProbeChannel(probe, :injection_current, bus.name,
                            "injection_$port", "1", 3, "kA", :out))
                end
            end
        end
    end
    if get(spec, :protocol, "") == "abc_resonance"
        # master:pgb is the existing output_probe! component (probes.jl:29).
        # Remove unused recorder instances and their private label/wire,
        # retaining all electrical meters and connections. No master field or
        # signal is invented; output_probe! owns this exact recorder geometry.
        needed = filter(c -> c.kind == :voltage && c.bus == only(spec.buses).name ||
            c.kind == :injection_current && c.element == only(spec.currents)[1], plan.probes.channels)
        retain_recorders!(plan, needed)
    end
    if get(spec, :recorder_scope, "") == "measurement"
        port_buses=Set(b.name for b in spec.buses)
        voltage_buses=copy(port_buses)
        device_currents=Set{Tuple{String,String}}()
        for e in list.elements
            e.model isa Union{PowerImpedance.TLC,PowerImpedance.MMC,PowerImpedance.SynchronousMachine} || continue
            bases=device_bases(e.model.elec)
            push!(voltage_buses,port_probe(list,e.name,bases.ac_side).name)
            bases.dc_voltage===nothing || push!(voltage_buses,port_probe(list,e.name,1).name)
            push!(device_currents,(string(e.name),string(bases.ac_side)))
        end
        needed=filter(c->c.kind==:injection_current ||
            c.kind==:voltage && c.bus in voltage_buses ||
            c.kind==:current && (c.bus in port_buses || c.dim==1 || (c.element,c.side) in device_currents),
            plan.probes.channels)
        retain_recorders!(plan,needed)
    end
    P.check_connectivity(plan)
    return plan, settings
end

function retain_recorders!(plan, needed)
    names = Set(c.name for c in needed)
    discarded = filter(c -> c isa P.ComponentPlan && c.defn == "master:pgb" &&
        !(Dict(c.params)["Name"] in names), plan.main.components)
    for recorder in discarded
        endpoint=(recorder.x,recorder.y);labelpoint=(recorder.x-36,recorder.y)
        label=only(filter(c -> c isa P.ComponentPlan && c.defn=="master:datalabel" &&
            (c.x,c.y)==labelpoint && Dict(c.params)["Name"]==Dict(recorder.params)["Name"],plan.main.components))
        wire=only(filter(w -> w.vertices==[labelpoint,endpoint],plan.main.wires))
        filter!(c -> c!==recorder && c!==label,plan.main.components)
        filter!(w -> w!==wire,plan.main.wires)
    end
    filter!(c -> c.name in names, plan.probes.channels)
    return nothing
end

function amplitude_values(spec, axis, port)
    if spec.dimension == 1
        return ["amplitude_pu" => string(axis == spec.axes[port] ? spec.tone_peak_pu : 0.0)]
    end
    if spec.dimension == 3
        names = spec.axes[(3port-2):3port]
        return ["$(phase)_amplitude_pu" => string(axis == names[k] ? spec.tone_peak_pu : 0.0)
            for (k, phase) in enumerate(("a", "b", "c"))]
    end
    names = spec.id == "L1-01" ? ["d", "q"] : spec.axes[(2port - 1):2port]
    return ["d_amplitude_pu" => string(axis == names[1] ? spec.tone_peak_pu : 0.0),
        "q_amplitude_pu" => string(axis == names[2] ? spec.tone_peak_pu : 0.0)]
end
