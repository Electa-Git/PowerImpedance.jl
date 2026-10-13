# Frozen measurement definitions; native element/network owners implement physics.
function port_probe(list, element, side)
    entry = only(filter(e -> e.name == element, list.elements))
    terminal = only(filter(t -> t.side == side, entry.terminals))
    return only(filter(b -> b.key == terminal.bus, list.buses))
end

function scan_definition(id, net, list)
    old = l1_settings()
    if id == "L1-01"
        buses = [port_probe(list, :branch, 1)]
        currents = [("branch", "1")]
        quantity, dimension = "Y", 2
    elseif id in ("L1-02", "L1-05")
        last_element = id == "L1-02" ? :rc : :ohl
        buses = [port_probe(list, :line, 1), port_probe(list, last_element, 2)]
        currents = [("line", "1"), (string(last_element), "2")]
        quantity, dimension = "Y", 1
    elseif id == "L1-08"
        buses = [port_probe(list, :g1, 1), port_probe(list, :l5, 1)]
        currents = [("injection_1", "1"), ("injection_2", "1")]
        quantity, dimension = "Z", 2
    else
        buses = [port_probe(list, :line, 1), port_probe(list, :line, 2)]
        currents = [("line", "1"), ("line", "2")]
        quantity, dimension = "Y", 2
    end
    frequencies = id == "L1-01" || dimension == 1 ? old.frequencies :
                  filter(!=(50.0), old.frequencies)
    # AC 50 Hz dq has an abc DC sideband. It is outside the AC line fit and
    # excites slow transformer flux offsets; exclude it before observing EMT.
    axes = id == "L1-01" ? ["d", "q"] :
           ["p$(port)_$(axis)" for port in eachindex(buses)
            for axis in (dimension == 1 ? ("dc",) : ("d", "q"))]
    voltages = [dimension == 1 ? 2b.base_kV * something(b.vm_pu, 1.0) :
                sqrt(2) * b.base_kV * something(b.vm_pu, 1.0) for b in buses]
    id == "L1-01" && (voltages[1] = old.voltage_base_kV)
    currents_base = [dimension == 1 ? 1000 / v : 2000 / (3v) for v in voltages]
    vbase = repeat(voltages; inner = dimension)
    ibase = repeat(currents_base; inner = dimension)
    lengths = [Float64(e.element_model.length)
               for e in values(net.elements)
               if e.element_model isa
                  Union{PowerImpedance.Cable, PowerImpedance.Overhead_line}]
    travel = isempty(lengths) ? 0.0 : minimum(lengths) / 299792458
    spec = merge(old,
        (; id, quantity, dimension, buses, currents, axes, frequencies,
            phases = [-π * k * (k - 1) / length(frequencies)
                      for k in eachindex(frequencies)],
            voltage_bases = vbase, current_bases = ibase, travel_lower_bound_s = travel,
            estimated_station_seconds = (300, 360, 540, 540, 480, 540, 540, 1080)[parse(
                Int, id[(end - 1):end])]))
    reference = scan_reference(net, list, spec)
    normalized = scale_response(reference, spec)
    bound = maximum(sum(abs.(normalized); dims = 3))
    amplitude = id == "L1-01" ? old.tone_peak_pu :
                min(old.tone_peak_pu, 0.004 / max(bound, 1.0))
    return merge(spec, (; tone_peak_pu = amplitude)), reference
end

function scan_reference(net, list, spec)
    if spec.id == "L1-01"
        return cat(
            (PowerImpedance.get_y(net.elements[:branch], ComplexF64(im * 2π * f))[1:2, 1:2]
            for f in spec.frequencies)...;
            dims = 3)
    elseif spec.id in ("L1-03", "L1-04", "L1-06", "L1-07")
        return cat(
            (PowerImpedance.get_y(net.elements[:line], ComplexF64(im * 2π * f))
            for f in spec.frequencies)...;
            dims = 3)
    elseif spec.id == "L1-08"
        inputs = reduce(vcat, [b.nets for b in spec.buses])
        nodes = unique([n for e in values(net.elements) for n in values(e.pins)])
        grounds = filter(n -> occursin("gnd", string(n)), nodes)
        order = [inputs; setdiff(nodes, [inputs; grounds])]
        topology = Dict{Symbol, Array{Union{Symbol, Int}}}(:node_list => order,
            :element_list => collect(keys(net.elements)), :output_list => grounds)
        return cat(
            (PowerImpedance.make_z(net, topology, copy(inputs), copy(grounds),
                 ComplexF64(im * 2π * f)) for f in spec.frequencies)...;
            dims = 3)
    end
    elements = spec.id == "L1-02" ? [:line, :rc] : [:line, :ohl]
    # Match the exporter's two pole-to-ground references at ungrounded internal
    # DC buses. Their differential equivalent is 2*DC_REFERENCE_RESISTANCE.
    frequency_net = deepcopy(net)
    for bus in list.buses
        bus.kind == :dc && !(bus in spec.buses) || continue
        reference_name = Symbol("validation_reference_", bus.name)
        add!(frequency_net, reference_name, impedance(z = s -> 2P.DC_REFERENCE_RESISTANCE, pins = 1))
        connect!(frequency_net, (reference_name, Symbol("1.1")), only(bus.nets))
        connect!(frequency_net, (reference_name, Symbol("2.1")), :gnd_validation_dc)
        push!(elements, reference_name)
    end
    connect!(frequency_net)
    inputs = reduce(vcat, [b.nets for b in spec.buses])
    nodes = unique([n for name in elements
                    for n in values(frequency_net.elements[name].pins)
                    if !occursin("gnd", string(n))])
    order = [inputs; setdiff(nodes, inputs)]
    topology = Dict{Symbol, Array{Union{Symbol, Int}}}(:node_list => order,
        :element_list => elements, :output_list => Symbol[])
    matrices = Matrix{ComplexF64}[]
    for f in spec.frequencies
        y = PowerImpedance.make_y(frequency_net, topology, ComplexF64(im * 2π * f))
        n = length(inputs)
        push!(matrices, y[1:n, 1:n] -
                        y[1:n, (n + 1):end] *
                        (y[(n + 1):end, (n + 1):end] \ y[(n + 1):end, 1:n]))
    end
    return cat(matrices...; dims = 3)
end

function scale_response(matrix, spec)
    input = spec.quantity == "Y" ? spec.voltage_bases : spec.current_bases
    output = spec.quantity == "Y" ? spec.current_bases : spec.voltage_bases
    return matrix .* reshape(1 ./ output, :, 1, 1) .* reshape(input, 1, :, 1)
end

function scan_settings(spec)
    return P.SimulationSettings(simulation_time = spec.simulation_time,
        time_step = spec.time_step, sample_step = spec.sample_step,
        frequency = spec.frequency, source_ramp = 0.0, output_stem = "scan")
end

function scan_record(spec)
    return Dict("quantity" => spec.quantity, "axes" => spec.axes,
        "coordinates" => spec.dimension == 3 ? "abc" : spec.dimension == 2 ? "dq" : "DC differential",
        "protocol" => get(spec, :protocol, ""),
        "applicable_comparison" => spec.dimension == 3 ? "phase-domain physics" : "native dq/DC physics",
        "phase_order" => spec.dimension == 3 ? ["a", "b", "c"] : String[],
        "SI_units" => "phase kV/kA imply S for Y and ohm for Z; phase-peak AC bases, 1000 MVA total three-phase base",
        "IEEE9_blocks" => spec.id == "L1-08" && spec.dimension == 3 ? "separate local Bus1/Bus5 3x3; full 6x6 transfer retained as evidence" : "not applicable",
        "frequencies" => spec.frequencies, "phases" => spec.phases,
        "tone_peak_pu" => spec.tone_peak_pu, "injection_time" => spec.injection_time,
        "window_starts" => collect(spec.window_starts), "window_duration" =>
            spec.window_duration,
        "simulation_time" => spec.simulation_time, "time_step" => spec.time_step,
        "sample_step" => spec.sample_step, "voltage_bases_kV" => spec.voltage_bases,
        "current_bases_kA" => spec.current_bases,
        "travel_time_lower_bound_s" => spec.travel_lower_bound_s,
        "estimated_station_seconds" => spec.estimated_station_seconds,
        "ports" => [Dict("bus" => b.name, "nets" => string.(b.nets), "angle_rad" =>
             something(b.va_rad, 0.0)) for b in spec.buses],
        "refinement" =>
            Dict("amplitude_change_limit" => 0.02, "step_change_limit" => 0.01,
                "selection" => "one worst-error column; half-step baseline plus column at worst frequency and 1000 Hz; retain predeclared coherent windows",
                "amplitude_scale" => 0.5, "half_step_s" => 1e-6),
        "excluded_ac_frequency_Hz" =>
            spec.dimension == 2 && spec.id != "L1-01" ? [50.0] : Float64[])
end
