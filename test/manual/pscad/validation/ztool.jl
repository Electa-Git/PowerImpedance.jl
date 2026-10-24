# Independent component measurements use the pinned scan library and saved SI matrices.
const ZTOOL_FREQUENCIES = Float64.(round.(Int, exp10.(range(0, 3; length = 16))))
const ZTOOL_LIBRARY = joinpath(REPOSITORY, "test/pscad/fixtures/ztool/Z_tool.pslx")

ztool_component_ids() = [entry.id for entry in REGISTRY if entry.category in (:passive, :device)]

function ztool_references(id, record, directory; net = nothing)
    frequencies = record["arguments"]["freq"]
    continuous = read_response(joinpath(directory, record["julia_reference"]), length(record["axes"]), frequencies)
    if !haskey(record, "reference_selection")
        active_case = record["active"] && id in ztool_component_ids()
        if active_case && net === nothing
            net = fixture(id).factory()
            power_flow(net)
        end
        eligible = active_case && interface_step_eligible(net.elements[:DUT].element_model)
        path = joinpath(directory, "suite_reference.toml")
        suite = isfile(path) ? TOML.parsefile(path) : Dict{String, Any}()
        policy = get(suite, "reference", eligible ? "discrete_realization" : "plain_model")
        policy in ("plain_model", "discrete_realization") || error("unknown suite reference: $policy")
        policy == "discrete_realization" && !eligible && error("suite one-step reference needs zero-delay modulation")
        if eligible
            response = one_step_full_y(net.elements[:DUT], record["settings"]["time_step_s"])
            one_step = cat((response(ComplexF64(2π * im * f)) for f in frequencies)...; dims = 3)
        else
            one_step = continuous
        end
        write_response(joinpath(directory, "reference_one_step.tsv"), one_step, frequencies)
        record["one_step_reference"] = "reference_one_step.tsv"
        record["reference_selection"] = Dict("selected" => policy == "discrete_realization" ? "one_step" : "continuous",
            "one_step_applies" => eligible,
            "rule" => isempty(suite) ? "suite zero-delay modulation rule" : "recorded suite reference",
            "one_step_source_sha256" => digest(joinpath(ROOT, "interface_step.jl")),
            "suite_record" => suite)
    end
    one_step = read_response(joinpath(directory, record["one_step_reference"]), length(record["axes"]), frequencies)
    return (; continuous, one_step)
end

function ztool_ports(id, net, list, spec)
    entry = fixture(id)
    entry.category in (:passive, :device) || throw(ArgumentError("$id is outside the component sweep"))
    if entry.category == :device
        bases = device_bases(net.elements[:DUT].element_model.elec)
        ac = (; kind = :ac, name = "AC_scan", element = :DUT, side = bases.ac_side,
            bus = port_probe(list, :DUT, bases.ac_side), measured_side = 2,
            voltage = fill(bases.ac_voltage, 2), current = fill(bases.ac_current, 2))
        bases.dc_voltage === nothing && return [ac]
        return [(; kind = :dc, name = "DC_scan", element = :DUT, side = 1,
                bus = port_probe(list, :DUT, 1), measured_side = 2,
                voltage = [bases.dc_voltage], current = [bases.power / bases.dc_voltage]), ac]
    elseif id == "ieee9_bus_impedance"
        # Bus1 is an ideal-source bus with zero Z. Bus5 has a finite local admittance.
        bus = last(spec.buses)
        voltage = sqrt(2) * bus.base_kV * something(bus.vm_pu, 1.0)
        return [(; kind = :ac, name = "Bus_scan", element = nothing, side = nothing,
            bus, measured_side = 1, voltage = fill(voltage, 2),
            current = fill(2000 / (3voltage), 2))]
    end
    terminals = id == "passive_ac_rlc" ? [("branch", "1"), ("branch", "2")] : spec.currents
    return map(enumerate(terminals)) do (index, (element, side))
        bus = port_probe(list, Symbol(element), parse(Int, side))
        dc = bus.kind == :dc
        voltage = bus.base_kV * something(bus.vm_pu, 1.0) * (dc ? 2 : sqrt(2))
        (; kind = dc ? :dc : :ac, name = "Port$index", element = Symbol(element),
            side = parse(Int, side), bus, measured_side = 2,
            voltage = fill(voltage, dc ? 1 : 2),
            current = fill(dc ? 1000 / voltage : 2000 / (3voltage), dc ? 1 : 2))
    end
end

ztool_axes(ports) = ["$(p.name)-$(p.measured_side)_$axis" for p in ports
                    for axis in (p.kind == :dc ? ("dc",) : ("d", "q"))]

function ztool_topology(ports)
    length(ports) == 1 && return nothing
    names = ["$(p.name)-$side" for p in ports for side in 1:2]
    matrix = zeros(Int, length(names), length(names))
    for i in eachindex(ports)
        matrix[2i - 1, 2i - 1] = 1
        for j in eachindex(ports)
            i == j || (matrix[2i, 2j] = 1)
        end
    end
    return join(names, ' ') * "\n" * join((join(row, ' ') for row in eachrow(matrix)), '\n') * "\n"
end

function ztool_reference(id, net, list, spec, ports, frequencies)
    if id == "induction_machine"
        return induction_machine_reference(net, list, frequencies)
    elseif fixture(id).category == :device
        return cat((physical_y(net.elements[:DUT], ComplexF64(2π * im * f))
                    for f in frequencies)...; dims = 3)
    elseif id == "passive_ac_rlc"
        return cat((PowerImpedance.get_y(net.elements[:branch], ComplexF64(2π * im * f))
                    for f in frequencies)...; dims = 3)
    elseif id == "ieee9_bus_impedance"
        z = scan_reference(net, list, merge(spec, (; frequencies)))
        return cat((inv(z[3:4, 3:4, k]) for k in eachindex(frequencies))...; dims = 3)
    end
    return scan_reference(net, list, merge(spec, (; frequencies)))
end

function ztool_definition(id, net, list)
    spec, _ = applicable_scan(id, net, list)
    ports = ztool_ports(id, net, list, spec)
    frequencies = copy(ZTOOL_FREQUENCIES)
    # The existing native dq two-port reference supplies four axes for AC passives.
    reference = ztool_reference(id, net, list, spec, ports, frequencies)
    voltage, current = reduce(vcat, getproperty.(ports, :voltage)), reduce(vcat, getproperty.(ports, :current))
    normalized = reference .* reshape(voltage, 1, :, 1) ./ reshape(current, :, 1, 1)
    bound = maximum(sum(abs.(normalized); dims = (2, 3)))
    perturbation = min(1e-4, 0.004 / max(bound, 1.0))
    settling = max(0.0, first(spec.window_starts) - spec.injection_time)
    screen = haskey(spec, :machine_stability) ? spec.machine_stability : stability_gate(net, fixture(id))
    decay = -get(screen, "most_positive_located_real_per_s", 0.0)
    declared = haskey(spec, :settling) ? get(spec.settling, "decay_times", 0.0) : 0.0
    decay > 0 && (settling = max(settling, declared / decay))
    settling = max(1.0, ceil(settling))
    snapshot = ceil(max(first(spec.window_starts), spec.injection_time, 1.0))
    settings = P.SimulationSettings(simulation_time = snapshot, time_step = spec.time_step,
        sample_step = spec.sample_step, frequency = spec.frequency, source_ramp = 0.0,
        output_stem = "sweep")
    scan = ZToolScan(; frequencies, snapshot_time = snapshot, start_fft = settling,
        injection_interval = settling, perturbation, multi_frequency = true)
    P._ztool_arguments(scan, settings)
    active = fixture(id).category == :device
    return (; id, spec, ports, reference, voltage, current, settings, scan, screen,
        decay, declared_decay_times = declared, active)
end

function ztool_estimate(definition)
    (; ports, scan, settings, spec) = definition
    axes = unique([p.kind for p in ports]) == [:dc] ? 1 : any(p -> p.kind == :dc, ports) ? 3 : 2
    # The runner requests the single-port scans and the topology's multi-port scans.
    extra = length(ports) > 1 && all(p -> p.kind == first(ports).kind, ports) ?
        sum(length(p.voltage) for p in ports) : 0
    simulations_per_axis = scan.multi_frequency ? cld(length(scan.frequencies), 8) : length(scan.frequencies)
    injections = simulations_per_axis * (axes + extra)
    duration = scan.start_fft + scan.fft_periods / scan.f_base
    seconds = scan.snapshot_time + scan.injection_interval + (injections + 1) * duration
    # The measured induction-machine rate is about 20 wall seconds per simulated second at 1 us.
    size_factor = fixture(definition.id).estimated_nodes / 45
    minutes = (60 + 20seconds * (1e-6 / settings.time_step) * size_factor) / 60
    return (; simulations = 1 + injections, simulated_seconds = seconds,
        estimated_minutes = minutes, low_minutes = 0.5minutes, high_minutes = 2minutes,
        basis = "induction-machine measured rate; inverse integration step and estimated node count; factor-two range")
end

function ztool_source_switch(kind; stem = "scan_switch", open_at = 1.0, left = "A", right = "B",
        left_negative = left * "_N", right_negative = right * "_N")
    ac = kind == :ac
    canvas = P.CanvasPlan()
    command = P.Signal(stem * "_open")
    P.lower!(canvas, P.BlockGraph(P.ControlBlock[P.TimeStep(P.Signal(stem * "_clock")),
        P.Compare(P.Signal(stem * "_clock"), command, open_at)]); origin = (1440, 108))
    if ac
        for (point, node, orient) in (((252, 216), left, 0), ((972, 216), right, 4))
            push!(canvas.components, P.ComponentPlan("master:breakout", ["Dis" => "0", "Com" => "0"], point..., orient))
            P.stub!(canvas, point, node; direction = orient == 0 ? -1 : 1)
        end
        for phase in 1:3
            P.stub!(canvas, (288, 180 + 36(phase - 1)), stem * "_left_$phase")
            P.stub!(canvas, (936, 180 + 36(phase - 1)), stem * "_right_$phase"; direction = -1)
        end
    end
    for phase in 1:(ac ? 3 : 2)
        y = 108phase
        P.component!(canvas, "breaker1", (612, y),
            ["NAME" => command.name, "BOpen" => "0", "ENAB" => "0", "OPCUR" => "1",
                "RON" => "0.0 [ohm]", "ROFF" => ac ? "1.0E100 [ohm]" :
                    P.pscad_value(P.DC_REFERENCE_RESISTANCE; unit = "ohm"), "CLVL" => "0.0 [kA]",
                "ViewB" => "0", "VBR" => "", "SBR" => "", "IBR" => ""])
        P.stub!(canvas, (576, y), ac ? stem * "_left_$phase" :
            phase == 1 ? left : left_negative; direction = -1)
        P.stub!(canvas, (648, y), ac ? stem * "_right_$phase" :
            phase == 1 ? right : right_negative)
    end
    return canvas
end

function ztool_measurement_plan(list, settings, requests)
    plan = P.build_plan(list; settings, name = "scan")
    scans = P._resolve_ztool_probes(list, requests)
    layout = P.GridLayout(6cld(maximum(c.y for c in plan.main.components) + 216, 216))
    state = P.PlanState(plan.main, plan.lines, plan.wrappers, plan.modules, layout,
        plan.probes.channels, plan.main.used)
    dc_labels = Dict(b.key => (b.name * "_P", b.name * "_N") for b in list.buses if b.kind == :dc)
    terminals = Dict{Tuple{Symbol, Symbol}, Tuple{Vararg{String}}}()
    context = (; settings, dc_labels, ztool_terminals = terminals)
    replacements = Dict{String, Any}[]
    for scan in scans
        (; probe, bus, terminal) = scan
        old_labels = P.ComponentPlan[]
        if terminal !== nothing
            channel = only(filter(c -> c.kind == :current && c.element == string(probe.element) &&
                c.port == probe.port, plan.probes.channels))
            meter = only(filter(c -> c isa P.ComponentPlan && c.defn == "master:ammeter" &&
                get(Dict(c.params), "Name", "") == channel.name, plan.main.components))
            pins = [(meter.x, meter.y), (meter.x + 36, meter.y)]
            meter_wires = filter(w -> any(p -> p in w.vertices, pins), plan.main.wires)
            length(meter_wires) == 2 || error("terminal meter needs two labelled stubs: $(channel.name)")
            endpoints = [only(filter(p -> p ∉ pins, w.vertices)) for w in meter_wires]
            append!(old_labels, [only(filter(c -> c isa P.ComponentPlan && c.defn == "master:nodelabel" &&
                (c.x, c.y) == point, plan.main.components)) for point in endpoints])
            bus_name = bus.kind == :dc ? first(dc_labels[bus.key]) : bus.name
            bus_name = get(plan.main.aliases, lowercase(bus_name), bus_name)
            inner = only(filter(c -> Dict(c.params)["Name"] != bus_name, old_labels))
            terminals[(probe.element, probe.port)] = bus.kind == :dc ?
                (Dict(inner.params)["Name"], last(dc_labels[bus.key])) : (Dict(inner.params)["Name"],)
            output_points = [(c.x, c.y) for c in plan.main.components if c isa P.ComponentPlan &&
                c.defn in ("master:pgb", "master:datalabel") && get(Dict(c.params), "Name", "") == channel.name]
            filter!(w -> !(w in meter_wires) && !any(p -> p in output_points, w.vertices), plan.main.wires)
            filter!(c -> c !== meter && !(c in old_labels) && (c.x, c.y) ∉ output_points, plan.main.components)
            filter!(c -> c !== channel, plan.probes.channels)
            push!(replacements, Dict("readout" => channel.name, "probe" => probe.name,
                "measurement" => probe.name * "-2", "original_orientation" => string(channel.orientation)))
        end
        P._emit_ztool_probe!(state, scan, context)
        for old in old_labels
            extra = filter(p -> first(p) != "Name", old.params)
            isempty(extra) && continue
            name = Dict(old.params)["Name"]
            index = findlast(c -> c isa P.ComponentPlan && c.defn == "master:nodelabel" &&
                Dict(c.params)["Name"] == name, plan.main.components)
            c = plan.main.components[index]
            plan.main.components[index] = P.ComponentPlan(c.defn, [c.params; extra], c.x, c.y, c.orient)
        end
    end
    return plan, replacements
end

function ztool_disconnect_sources!(plan, list, ports, scan)
    records = Dict{String, Any}[]
    seen = Set{Symbol}()
    row = isempty(plan.main.components) ? 0 : maximum(c.y for c in plan.main.components)
    for port in ports, source in list.elements
        source.model isa PowerImpedance.Source || continue
        any(t -> !t.grounded && t.bus == port.bus.key, source.terminals) || continue
        source.name in seen && continue
        push!(seen, source.name)
        channel = only(filter(c -> c.kind == :current && c.element == string(source.name), plan.probes.channels))
        meter = only(filter(c -> c isa P.ComponentPlan && c.defn == "master:ammeter" &&
            get(Dict(c.params), "Name", "") == channel.name, plan.main.components))
        pins = [(meter.x, meter.y), (meter.x + 36, meter.y)]
        labels = Int[]
        for wire in plan.main.wires, pin in pins
            pin in wire.vertices || continue
            point = only(filter(!=(pin), wire.vertices))
            for (index, component) in enumerate(plan.main.components)
                component isa P.ComponentPlan && component.defn == "master:nodelabel" || continue
                (component.x, component.y) == point || continue
                name = Dict(component.params)["Name"]
                startswith(name, channel.name * "_node") || push!(labels, index)
            end
        end
        label_index = only(unique(labels))
        label = plan.main.components[label_index]
        bus_node = Dict(label.params)["Name"]
        inner = P.pscad_name("scan_source_" * string(source.name); used = plan.main.used)
        plan.main.components[label_index] = P.ComponentPlan(label.defn, ["Name" => inner], label.x, label.y, label.orient)
        negative = if port.kind == :dc
            negative_source = only(filter(c -> c isa P.ComponentPlan && c.defn == "master:source_1" &&
                startswith(get(Dict(c.params), "Name", ""), source.pscad * "_N"), plan.main.components))
            pin = (negative_source.x + 36, negative_source.y)
            wire = only(filter(w -> pin in w.vertices, plan.main.wires))
            point = only(filter(!=(pin), wire.vertices))
            index = only(findall(c -> c isa P.ComponentPlan && c.defn == "master:nodelabel" &&
                (c.x, c.y) == point, plan.main.components))
            old = plan.main.components[index]
            node = P.pscad_name(inner * "_N"; used = plan.main.used)
            plan.main.components[index] = P.ComponentPlan(old.defn, ["Name" => node], old.x, old.y, old.orient)
            (; left_negative = node, right_negative = Dict(old.params)["Name"])
        else
            (;)
        end
        row += 504
        switch = ztool_source_switch(port.kind; stem = inner, open_at = scan.snapshot_time,
            left = inner, right = bus_node, negative...)
        append!(plan.main.components, [P.ComponentPlan(c.defn, c.params, c.x, c.y + row, c.orient)
            for c in switch.components])
        append!(plan.main.wires, [P.WirePlan([(x, y + row) for (x, y) in w.vertices]) for w in switch.wires])
        push!(records, Dict("source" => string(source.name), "probe" => port.name,
            "bus" => port.bus.name, "open_threshold_s" => scan.snapshot_time,
            "opening" => "first integration step after Tdecoupling; strict time comparator; no interpolation",
            "conductors" => port.kind == :ac ? "all three phases" : "both poles",
            "open_resistance_ohm" => port.kind == :ac ? 1e100 : P.DC_REFERENCE_RESISTANCE,
            "reference" => port.kind == :ac ? "none" :
                "equal 10 Mohm off resistances to the original pole voltages keep a weak common-mode reference",
            "excluded_result" => port.name * "-1"))
    end
    return records
end

"""
$(TYPEDSIGNATURES)

Write a component measurement copy and its Julia admittance reference in \\[S\\].
The copy opens adjacent source feeds after the snapshot time in \\[s\\].
Preparation records unstable predictions and does not contact PSCAD.

# Keywords

- `directory`: Case data directory with the `ztool` suffix.
- `library`: Local pinned scan library. Default: the repository fixture.
- `scan`: Optional sweep with explicit frequencies and snapshot time in \\[s\\].
  Default: the case settings and sixteen multi-frequency tones.

# Returns

- The saved case manifest, including frequency settings in \\[Hz\\] and file hashes.
"""
function prepare_ztool(id; directory = joinpath(ROOT, "data", id, "ztool"), library = ZTOOL_LIBRARY, scan = nothing)
    id in ztool_component_ids() || throw(ArgumentError("$id is outside the component sweep"))
    ispath(directory) && return ztool_load(directory; id)
    P._require_extension()
    net = fixture(id).factory()
    point = power_flow(net)
    list = fixture_netlist(net, point)
    definition = ztool_definition(id, net, list)
    requested = scan
    if requested !== nothing
        requested isa ZToolScan || throw(ArgumentError("scan must be a ZToolScan"))
        requested.frequencies === nothing && throw(ArgumentError("measurement preparation needs explicit frequencies"))
        requested.snapshot_time === nothing && throw(ArgumentError("measurement preparation needs an explicit snapshot time"))
        arguments = P._ztool_arguments(requested, definition.settings)
        settings = P.SimulationSettings(simulation_time = requested.snapshot_time,
            time_step = arguments["t_step"] / 1e6, sample_step = arguments["sample_step"] / 1e6,
            frequency = definition.settings.frequency, source_ramp = definition.settings.source_ramp,
            output_stem = definition.settings.output_stem)
        reference = ztool_reference(id, net, list, definition.spec, definition.ports, requested.frequencies)
        definition = merge(definition, (; settings, scan = requested, reference))
    end
    (; ports, settings, scan, reference) = definition
    requests = [p.element === nothing ?
                ZToolProbe(p.kind, p.name; bus = p.bus.name,
                    perturbation = scan.perturbation) :
                ZToolProbe(p.kind, p.name;
                    element = p.element, port = terminal_port(list, p.element, p.side),
                    perturbation = scan.perturbation) for p in ports]
    mkpath(directory)
    topology = ztool_topology(ports)
    topology === nothing || write(joinpath(directory, "topology.txt"), topology)
    plan, replacements = ztool_measurement_plan(list, settings, requests)
    original = P._export_project(list, joinpath(mkpath(joinpath(directory, "original")), "scan.pscx"),
        "scan", settings, false, (;), :midpoint_resistors, ZToolProbe[], nothing)
    openings = ztool_disconnect_sources!(plan, list, ports, scan)
    for (index, component) in enumerate(plan.main.components)
        component isa P.ComponentPlan && startswith(component.defn, "Z_tool:") || continue
        params = [key => (key == "Tdecoupling" ? P.pscad_value(scan.snapshot_time) : value)
                  for (key, value) in component.params]
        plan.main.components[index] = P.ComponentPlan(component.defn, params,
            component.x, component.y, component.orient)
    end
    P.check_connectivity(plan)
    path = joinpath(directory, "scan.pscx")
    P._write_project(plan, path)
    source = P._ztool_library(library)
    cp(source.path, joinpath(directory, "Z_tool.pslx"))
    write(joinpath(directory, "scan.pswx"), P._ztool_workspace("scan", "scan.pscx"))
    P._write_ztool_frequency_tables(directory, P._ztool_frequency_tables(settings.frequency))
    write_response(joinpath(directory, "reference.tsv"), reference, scan.frequencies)
    arguments = P._ztool_arguments(scan, settings)
    topology === nothing || (arguments["topology"] = "topology.txt")
    estimate = ztool_estimate(definition)
    record = Dict{String, Any}("schema_version" => 1, "fixture_id" => id,
        "status" => "prepared_station_pending", "ztoolacdc_version" => "0.1.52",
        "settings" => Dict("simulation_time_s" => settings.simulation_time,
            "time_step_s" => settings.time_step, "sample_step_s" => settings.sample_step,
            "frequency_Hz" => settings.frequency, "source_ramp_s" => settings.source_ramp,
            "output_stem" => settings.output_stem), "arguments" => arguments,
        "axes" => ztool_axes(ports), "voltage_bases_kV" => definition.voltage,
        "current_bases_kA" => definition.current, "active" => definition.active,
        "julia_reference" => "reference.tsv", "reference_unit" => "S",
        "reference_frame" => "fixed nominal frame; positive-sine q; DC,d,q for converters; port order for passives",
        "source_openings" => openings, "stability" => definition.screen,
        "replaced_terminal_readouts" => replacements,
        "excluded_sides" => [Dict("name" => p.name * "-" * string(3 - p.measured_side),
            "reason" => any(o -> o["bus"] == p.bus.name, openings) ?
                "source feed disconnected; only the element side is compared" :
                "only the element or selected bus side is compared") for p in ports],
        "suite_decay_time_margin" => definition.declared_decay_times,
        "perturbation_reason" => requested === nothing ?
            "at most 0.0001 pu per tone; eight simultaneous tones; reference current bound at most 0.004 pu" :
            "caller-selected formulation; perturbation and timing stored in arguments",
        "ports" => [Dict("name" => p.name, "kind" => string(p.kind), "bus" => p.bus.name,
            "measured_side" => p.measured_side, "source_angle_rad" => something(p.bus.va_rad, 0.0)) for p in ports],
        "comparison_rule" => Dict(string(k) => v for (k, v) in pairs(definition.active ? ACTIVE_FREQUENCY_LIMITS : PASSIVE_FREQUENCY_LIMITS)),
        "estimate" => Dict(string(k) => v for (k, v) in pairs(estimate)),
        "source_files" => source_record(), "julia_version" => string(VERSION),
        "library_sha256" => source.sha256)
    if haskey(definition.screen, "most_positive_located_real_per_s")
        record["slowest_decay_per_s"] = definition.decay
        record["settling_decay_times"] = max(definition.decay, 0) * scan.start_fft
    else
        record["settling_basis"] = "case settled windows; dissipativity does not give a decay rate"
    end
    ztool_references(id, record, directory; net)
    write_manifest(directory, record)
    return record
end

function ztool_load(directory; id = nothing)
    record = TOML.parsefile(joinpath(directory, "manifest.toml"))
    id === nothing || record["fixture_id"] == id || error("Z-tool fixture differs")
    for file in record["files"]
        path = normpath(joinpath(directory, file["path"]))
        startswith(relpath(path, directory), "..") && error("invalid Z-tool file path")
        isfile(path) && filesize(path) == file["bytes"] && digest(path) == file["sha256"] ||
            error("Z-tool stored file changed: $(file["path"])")
    end
    return record
end

function ztool_formulation(record, directory)
    a = record["arguments"]
    return ZToolScan(frequencies = a["freq"], f_base = a["f_base"], snapshot_time = a["t_snap"],
        start_fft = a["start_fft"], fft_periods = a["fft_periods"], injection_interval = a["dt_injections"],
        perturbation = a["v_perturb_mag"], multi_frequency = a["multi_freq_scan"],
        time_step = a["t_step"] / 1e6, sample_step = a["sample_step"] / 1e6,
        num_parallel_sim = a["num_parallel_sim"],
        topology = haskey(a, "topology") ? joinpath(directory, a["topology"]) : nothing)
end

function ztool_frame(record, angle_path)
    lines = split.(readlines(angle_path)[2:end])
    angles = Dict(row[1] => parse(Float64, row[3]) for row in lines if !isempty(row))
    n = length(record["axes"])
    transform = Matrix{Float64}(I, n, n)
    arguments = record["arguments"]
    sample = arguments["sample_step"] * 1e-6
    # Match frequency_sweep's rounded snapshot sampling time, including its ceil.
    sample_time = round(ceil((arguments["t_snap"] + arguments["dt_injections"]) / sample) * sample; digits = 6)
    phase = 2π * rem(record["settings"]["frequency_Hz"] * sample_time, 1)
    offset = 1
    for port in record["ports"]
        if port["kind"] == "ac"
            haskey(angles, port["name"]) || error("missing Z-tool frame angle for $(port["name"])")
            angle = angles[port["name"]] - phase
            transform[offset:(offset + 1), offset:(offset + 1)] .=
                [cos(angle) -sin(angle); sin(angle) cos(angle)]
            offset += 2
        else
            offset += 1
        end
    end
    return transform
end

function ztool_comparison(record, actual, reference)
    frequencies = record["arguments"]["freq"]
    voltage, current = record["voltage_bases_kV"], record["current_bases_kA"]
    scale(matrix) = matrix .* reshape(voltage, 1, :, 1) ./ reshape(current, :, 1, 1)
    entries = comparison_rows(frequencies, scale(actual), scale(reference); active = record["active"])
    rows = [(; frequency_Hz = f,
        relative_frobenius_error = norm(actual[:, :, k] - reference[:, :, k]) / max(norm(reference[:, :, k]), eps()),
        scored_frobenius_error = first(filter(row -> row.frequency_Hz == f, entries)).frobenius_error,
        limit = record["comparison_rule"]["epsilon"],
        passed = norm(actual[:, :, k] - reference[:, :, k]) / max(norm(reference[:, :, k]), eps()) <=
            record["comparison_rule"]["epsilon"] &&
            all(row -> row.within_tolerance, filter(row -> row.frequency_Hz == f, entries)))
        for (k, f) in enumerate(frequencies)]
    summary = Dict("status" => all(row.passed for row in rows) ? "passed" : "failed_comparison",
        "passing_frequencies" => count(row -> row.passed, rows), "frequency_count" => length(rows),
        "maximum_relative_frobenius_error" => maximum(row.relative_frobenius_error for row in rows),
        "maximum_scored_frobenius_error" => maximum(row.scored_frobenius_error for row in rows))
    return (; entries, rows, summary)
end

function ztool_phase_projection(id, record, directory)
    path = joinpath(directory, "reference_phase_projection.tsv")
    frequencies = record["arguments"]["freq"]
    if !isfile(path)
        net = fixture(id).factory()
        list = fixture_netlist(net, power_flow(net))
        if id == "ieee9_bus_impedance"
            twin = phase_twin(net, list)
            bus = only(filter(b -> b.name == only(record["ports"])["bus"], list.buses))
            # The owned two-port projection also projects two copies of a local
            # phase admittance. Its first block gives the local dq result.
            phase_y(f) = kron(Matrix{Float64}(I, 2, 2),
                inv(phase_network_z(twin, [bus], f; floating_stars = true)))
            reference = cat((PowerImpedance.transformation_dq(phase_y(f + 50), phase_y(f - 50))[1:2, 1:2]
                for f in frequencies)...; dims = 3)
        else
            model = net.elements[:line].element_model
            reference = cat((PowerImpedance.transformation_dq(
                PowerImpedance.abcd_to_y(eval_abcd(model, ComplexF64(2π * im * (f + 50)))),
                PowerImpedance.abcd_to_y(eval_abcd(model, ComplexF64(2π * im * (f - 50)))))
                for f in frequencies)...; dims = 3)
        end
        write_response(path, reference, frequencies)
    end
    return read_response(path, length(record["axes"]), frequencies)
end

function ztool_repeat_results!(record, directory)
    root = joinpath(directory, "repeats")
    if !isdir(root)
        haskey(record, "repeat_conclusion") && error("Z-tool repeat evidence is missing")
        return nothing
    end
    results = Dict{String, Any}[]
    for name in sort(readdir(root))
        archive = joinpath(root, name)
        isdir(archive) || continue
        path = joinpath(archive, "manifest.toml")
        repeat = TOML.parsefile(path)
        repeat["fixture_id"] == record["fixture_id"] || error("Z-tool repeat fixture differs: $name")
        files = filter(file -> startswith(file["path"], "comparison_") && endswith(file["path"], ".tsv"), repeat["files"])
        for file in files
            basename(file["path"]) == file["path"] || error("invalid Z-tool repeat comparison path")
            comparison = joinpath(archive, file["path"])
            isfile(comparison) && filesize(comparison) == file["bytes"] && digest(comparison) == file["sha256"] ||
                error("Z-tool repeat comparison changed: $name/$(file["path"])")
        end
        push!(results, Dict("name" => name, "manifest" => relpath(path, directory),
            "manifest_sha256" => digest(path), "status" => repeat["status"],
            "arguments" => repeat["arguments"], "settings" => repeat["settings"],
            "comparison_files" => [relpath(joinpath(archive, file["path"]), directory) for file in files],
            "reference_results" => get(repeat, "reference_results", Dict{String, Any}())))
    end
    record["repeat_results"] = results
    if haskey(record, "repeat_conclusion")
        conclusion = record["repeat_conclusion"]
        names = Set(result["name"] for result in results)
        !isempty(conclusion["repeats"]) && all(in(names), conclusion["repeats"]) ||
            error("Z-tool repeat conclusion refers to missing evidence")
        record["comparison_status"] = record["status"]
        record["classification"] = conclusion["classification"]
        record["status"] = replace(lowercase(conclusion["classification"]), r"[\s-]+" => "_")
    end
    return nothing
end

"""
$(TYPEDSIGNATURES)

Compare stored Z-tool matrices with continuous and one-step Julia matrices in \\[S\\].
Use file headers to order the axes and rotate measured dq blocks into the fixed frame.
Build missing references locally and reuse the saved matrices afterwards.
Keep nonfinite results as diverged outcomes without contacting PSCAD.

# Keywords

- `directory`: Case data directory with the `ztool` suffix.

# Returns

- The updated manifest with per-frequency errors and a comparison verdict.
"""
function reanalyse_ztool(id; directory = joinpath(ROOT, "data", id, "ztool"))
    record = ztool_load(directory; id)
    output = joinpath(directory, "outputs")
    if !isfile(joinpath(output, "ztool.toml"))
        archived = [joinpath(directory, run, "outputs") for run in get(record, "kept_runs", String[])
                    if isfile(joinpath(directory, run, "outputs", "ztool.toml"))]
        if isempty(archived)
            record["status"] = "no_result"
            record["analysis_error"] = "Z-tool metadata is missing from outputs and archived runs"
            write_manifest(directory, record)
            return record
        end
        source = only(archived)
        isdir(output) && error("incomplete outputs already exist: $output")
        cp(source, output)
        record["recovered_outputs"] = relpath(source, directory)
    end
    metadata = TOML.parsefile(joinpath(output, "ztool.toml"))
    metadata["version"] == record["ztoolacdc_version"] || error("Z-tool version differs")
    for (key, expected) in record["arguments"]
        key == "topology" && continue
        get(metadata["arguments"], key, nothing) == expected || error("Z-tool argument differs: $key")
    end
    candidates = [read_ztool_admittance(joinpath(output, file)) for file in metadata["files"] if occursin("#Y_", file)]
    selected = only(filter(result -> Set(result.axes) == Set(record["axes"]), candidates))
    selected.frequencies == record["arguments"]["freq"] || error("Z-tool frequencies differ")
    if any(!isfinite, selected.admittance)
        record["status"] = "diverged"
        record["result_file"] = relpath(selected.path, directory)
        record["nonfinite_entries"] = count(!isfinite, selected.admittance)
        record["nonfinite_frequencies_Hz"] = selected.frequencies[
            [any(!isfinite, selected.admittance[:, :, k]) for k in eachindex(selected.frequencies)]]
        record["observation"] = "nonfinite measured admittances; Julia stability prediction is stored separately"
        write_manifest(directory, record)
        return record
    end
    order = [only(findall(==(axis), selected.axes)) for axis in record["axes"]]
    transform = ztool_frame(record, joinpath(output, "sweep_angles.txt"))
    actual = cat((transform' * selected.admittance[order, order, k] * transform
                  for k in eachindex(selected.frequencies))...; dims = 3)
    references = ztool_references(id, record, directory)
    selected_reference = record["reference_selection"]["selected"]
    record["reference_results"] = Dict{String, Any}()
    for (label, reference) in pairs(references)
        comparison = ztool_comparison(record, actual, reference)
        write_table(joinpath(directory, "comparison_$(label)_entries.tsv"), comparison.entries)
        write_table(joinpath(directory, "comparison_$(label)_frequencies.tsv"), comparison.rows)
        record["reference_results"][string(label)] = comparison.summary
        if string(label) == selected_reference
            write_table(joinpath(directory, "comparison_entries.tsv"), comparison.entries)
            write_table(joinpath(directory, "comparison_frequencies.tsv"), comparison.rows)
        end
    end
    write_response(joinpath(directory, "measured_fixed_frame.tsv"), actual, selected.frequencies)
    summary = record["reference_results"][selected_reference]
    record["status"] = summary["status"]
    record["result_file"] = relpath(selected.path, directory)
    record["maximum_relative_frobenius_error"] = summary["maximum_relative_frobenius_error"]
    record["maximum_scored_frobenius_error"] = summary["maximum_scored_frobenius_error"]
    if id in ("ac_ohl_untransposed", "ac_cable_coaxial", "ieee9_bus_impedance")
        projection = ztool_comparison(record, actual, ztool_phase_projection(id, record, directory))
        write_table(joinpath(directory, "comparison_phase_projection_entries.tsv"), projection.entries)
        write_table(joinpath(directory, "comparison_phase_projection_frequencies.tsv"), projection.rows)
        record["phase_projection_result"] = projection.summary
        record["classification"] = "dq approximation"
        record["informational_only"] = true
        record["status"] = "informational_dq_approximation"
        evidence = joinpath(directory, "dq_evidence.toml")
        record["dq_evidence"] = isfile(evidence) ? TOML.parsefile(evidence) :
            Dict("supported" => false, "observation" => "no stored sequence or image measurement attached")
    end
    record["measured_angles_to_fixed_frame"] = [collect(row) for row in eachrow(transform)]
    ztool_repeat_results!(record, directory)
    record["analysis_source_sha256"] = digest(@__FILE__)
    record["analysis_julia_version"] = string(VERSION)
    write_manifest(directory, record)
    return record
end

"""
$(TYPEDSIGNATURES)

Run a prepared component measurement with `compute(model, ZToolScan(...))`.
Copy its outputs into the case directory and reanalyse the stored matrices.

# Keywords

- `directory`: Case data directory with the `ztool` suffix.
- `remote`: Station configuration. Default: `RemoteConfig()`.
- `deadline`: Absolute wall time in \\[s\\]. Default: four hours from the call.
- `resume`: Reuse a completed matching sweep. Default: `true`.

# Returns

- The updated manifest. Execution failures keep their diagnostic and raise the error.
"""
function run_ztool(id; directory = joinpath(ROOT, "data", id, "ztool"),
        remote = RemoteConfig(), deadline = time() + 14400, resume = true)
    record = ztool_load(directory; id)
    verify_inputs(directory, record)
    s = record["settings"]
    settings = P.SimulationSettings(simulation_time = s["simulation_time_s"],
        time_step = s["time_step_s"], sample_step = s["sample_step_s"],
        frequency = s["frequency_Hz"], source_ramp = s["source_ramp_s"], output_stem = s["output_stem"])
    scan = ztool_formulation(record, directory)
    all(opening["open_threshold_s"] == scan.snapshot_time for opening in record["source_openings"]) ||
        error("source opening and Z-tool decoupling times differ")
    model = PSCADModel(joinpath(directory, "scan.pscx"); settings,
        ztool_library = joinpath(directory, "Z_tool.pslx"))
    remaining = floor(Int, deadline - time())
    remaining > 0 || error("Z-tool time budget exhausted")
    work_root = mkpath(joinpath(remote.local_root, "validation-ztool", id))
    record["work_root"] = work_root
    try
        result = compute(model, scan; options = (; remote = budget_remote(remote, remaining),
            work_root, resume_run_directory = resume ? :latest : nothing, verbosity = 1, timing = true))
        destination = joinpath(directory, "outputs")
        if isdir(destination)
            for name in readdir(destination)
                isfile(joinpath(result.paths.outputs, name)) &&
                    digest(joinpath(destination, name)) == digest(joinpath(result.paths.outputs, name)) ||
                    error("stored Z-tool output differs: $name")
            end
        else
            cp(result.paths.outputs, destination)
        end
        record["run_directory"] = result.paths.run_directory
        record["elapsed_seconds"] = result.diagnostics.elapsed_seconds
        record["solver"] = result.diagnostics.solver_identity
        record["status"] = "measured_analysis_pending"
        write_manifest(directory, record)
        record = reanalyse_ztool(id; directory)
        return record
    catch failure
        record["status"] = "run_or_analysis_failed"
        record["failure"] = sprint(showerror, failure)
        rethrow()
    finally
        history = mkpath(joinpath(directory, "runs"))
        for path in readdir(work_root; join = true)
            isdir(path) && startswith(basename(path), "run-") || continue
            destination = joinpath(history, basename(path))
            isdir(destination) || cp(path, destination)
        end
        record["kept_runs"] = [relpath(path, directory) for path in readdir(history; join = true)]
        write_manifest(directory, record)
    end
end
