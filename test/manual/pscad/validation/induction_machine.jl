# Retain the reference circuit, with the element names used by device measurements.
function induction_machine_network()
    parent = ClassicFixtures.im_network()
    names = Dict(:im1 => :DUT, :imp => :Grid, :g1 => :G3)
    net = Network()
    net.voltageBase .= parent.voltageBase
    for (name, element) in parent.elements
        add!(net, names[name], deepcopy(element))
    end
    for (node, pins) in parent.nets, (element, pin) in pins
        connect!(net, (names[element], pin), node)
    end
    connect!(net)
    return net
end

function device_bases(e::PowerImpedance.ElectricalIM)
    voltage = e.Vac_base * sqrt(2 / 3)
    current = 2e.S_base / (3voltage)
    return (voltage_inputs = fill(voltage, 2), current_outputs = fill(current, 2),
        ac_voltage = voltage, ac_current = current, dc_voltage = nothing,
        power = e.S_base, ac_side = 1, ac_indices = 1:2)
end

# Use the same frequency-model API and SI scaling as adm_IM_test.jl. Replay the
# written circuit's dq connections and retain its solved machine setpoint.
function induction_machine_reference(net, list, frequencies)
    elements = NamedTuple{Tuple(keys(net.elements))}(
        Tuple(deepcopy(element) for element in values(net.elements)))
    connections = [(node = node, element = e.name,
                       side = terminal_side(list, e.name, t.port), terminal = k)
                   for e in list.elements for t in e.terminals if !t.grounded
                   for (k, node) in enumerate(t.nets)]
    builder = NetworkBuilder.define(elements, connections)
    # transitional
    point = PowerImpedance.OperatingPoint(Dict(:DUT =>
        PowerImpedance._terminal_values(builder.elements.DUT, net.elements[:DUT].setpoint)))
    model = NetworkBuilder.NetworkModel(builder, point)
    return NetworkBuilder.get_y(model, :DUT, ComplexF64.(2π * im .* frequencies))
end

function induction_machine_scan(net, list, spec)
    # Half-Hz bins resolve the mechanical band. Neighbours of 50 Hz sample the
    # stator-current mode without imposing an abc DC component.
    frequencies = sort!([spec.frequencies; 0.5; 1.5; 48.0; 49.0; 51.0; 52.0])
    spec = merge(spec, (; frequencies,
        phases = [-π * k * (k - 1) / length(frequencies) for k in eachindex(frequencies)],
        time_step = 1e-6, sample_step = 25e-6, window_duration = 2.0,
        voltage_base_kV = first(spec.voltage_bases), current_base_kA = first(spec.current_bases),
        minimum_witness_window_s = 2.0, kcl_required = true,
        station_budget_seconds = 1800, estimated_station_seconds = 1800))
    reference = scan_reference(net, list, spec)
    impedance = [inv(reference[:, :, k] +
        PowerImpedance.get_y(net.elements[:Grid], ComplexF64(2π * im * f))[1:2, 1:2])
        for (k, f) in enumerate(frequencies)]
    vbase, ibase = first(spec.voltage_bases), first(spec.current_bases)
    voltage = cat((z * (ibase / vbase) for z in impedance)...; dims = 3)
    current = cat((reference[:, :, k] * z for (k, z) in enumerate(impedance))...; dims = 3)
    voltage_bound = maximum(sum(abs.(voltage); dims = 3))
    current_bound = maximum(sum(abs.(current); dims = 3))
    amplitude = min(0.01, 0.004 / max(voltage_bound, current_bound))
    voltage_tone = amplitude * minimum(minimum(svdvals(z)) for z in eachslice(voltage; dims = 3))
    screen = stability_gate(net, fixture(spec.id))
    decay = -screen["most_positive_located_real_per_s"]
    target, entry_floor = 0.001, 0.02
    decay_times = log(1 / (voltage_tone * entry_floor * target))
    start = decay > 0 ? ceil(max(6.0, 0.2 + decay_times / decay,
        spec.injection_time + decay_times / decay)) : 6.0
    settling = Dict("status" => decay > 0 ? "decaying" : "nondecaying",
        "decay_per_s" => decay, "decay_times" => decay_times,
        "assumed_initial_transient_pu" => 1.0, "prediction_target" => target,
        "entry_floor_pu" => entry_floor, "tone_peak_pu" => amplitude,
        "minimum_voltage_tone_pu" => voltage_tone,
        "voltage_departure_bound_pu" => amplitude * voltage_bound,
        "current_departure_bound_pu" => amplitude * current_bound,
        "window_starts_s" => [start, start + 2.0], "window_duration_s" => 2.0,
        "simulation_time_s" => start + 4.0,
        "predicted_normalized_tail" => exp(-decay * (start - spec.injection_time)) /
            (voltage_tone * entry_floor),
        "scope" => "native pole envelope and terminal response size the run; measured drift, windows, amplitude, step and KCL checks determine validity")
    spec = merge(spec, (; tone_peak_pu = amplitude, machine_stability = screen, settling,
        window_starts = (start, start + 2.0), simulation_time = start + 4.0))
    return spec, reference
end

# This comparison reports the independent data in SI units. It does not read or
# change a fixture manifest, measurement status or comparison tolerance.
function induction_machine_crosscheck(path; directory)
    rows = split.(readlines(path)[2:end])
    frequencies = real.([parse(ComplexF64, replace(row[1], "(" => "")) for row in rows])
    measured = cat((transpose(reshape(
        parse.(ComplexF64, replace.(row[2:end], "(" => "")), 2, 2)) for row in rows)...; dims = 3)
    net = fixture("induction_machine").factory()
    list = fixture_netlist(net, power_flow(net))
    reference = induction_machine_reference(net, list, frequencies)
    errors = [norm(reference[:, :, k] - measured[:, :, k]) / norm(measured[:, :, k])
              for k in eachindex(frequencies)]
    bases = device_bases(net.elements[:DUT].element_model.elec)
    report = Dict("diagnostic_only" => true, "data_file" => abspath(path),
        "data_sha256" => digest(path), "frequency_count" => length(frequencies),
        "frequency_band_Hz" => [minimum(frequencies), maximum(frequencies)],
        "coordinates" => "fixed nominal 50 Hz dq; d=cos(theta), q=sin(theta); inward current",
        "unit" => "S", "voltage_base_phase_peak_kV" => bases.ac_voltage,
        "current_base_phase_peak_kA" => bases.ac_current,
        "admittance_base_S" => bases.ac_current / bases.ac_voltage,
        "reference" => "NetworkBuilder.get_y with the solved machine setpoint and native SI_scale",
        "global_relative_error" => norm(reference - measured) / norm(measured),
        "max_matrix_relative_error" => maximum(errors),
        "worst_matrix_frequency_Hz" => frequencies[argmax(errors)],
        "max_absolute_error_S" => maximum(abs, reference - measured),
        "max_entry_relative_error" => maximum(abs.(reference - measured) ./ abs.(measured)))
    mkpath(directory)
    write_table(joinpath(directory, "frequency_errors.tsv"),
        [(frequency_Hz = f, relative_matrix_error = errors[k]) for (k, f) in enumerate(frequencies)])
    write_response(joinpath(directory, "julia_S.tsv"), reference, frequencies)
    write_response(joinpath(directory, "ztool_S.tsv"), measured, frequencies)
    open(joinpath(directory, "comparison.toml"), "w") do io
        TOML.print(io, report; sorted = true)
    end
    return report
end
