# Phase-coordinate references reuse native component ABCD and native make_z.
# No component formula or source regularization is reimplemented here.
function phase_twin(net, list)
    twin = Network()
    twin.voltageBase .= net.voltageBase
    for (name, original) in net.elements
        original.transformation && original.input_pins == original.output_pins == 2 ||
            error("phase twin requires passive three-phase two-ports")
        add!(twin, name, PowerImpedance.Element(element_model = deepcopy(original.element_model),
            input_pins = 3, output_pins = 3, transformation = false,
            setpoint = deepcopy(original.setpoint), limits = deepcopy(original.limits)))
    end
    for entry in list.elements, terminal in entry.terminals, phase in 1:3
        bus = terminal.grounded ? "gnd" : only(filter(b -> b.key == terminal.bus, list.buses)).name
        connect!(twin, (entry.name, Symbol(terminal.side, ".", phase)), Symbol(bus, "_", phase))
    end
    connect!(twin)
    # Each model is copied without reconstructing parameters; every terminal's
    # three phases replay its original bus incidence (including source/load grounds).
    for entry in list.elements
        original, copy = net.elements[entry.name], twin.elements[entry.name]
        repr(original.element_model) == repr(copy.element_model) || error("phase twin model differs")
        for terminal in entry.terminals, phase in 1:3
            bus = terminal.grounded ? "gnd" : only(filter(b -> b.key == terminal.bus, list.buses)).name
            copy.pins[Symbol(terminal.side, ".", phase)] == Symbol(bus, "_", phase) ||
                error("phase twin incidence differs")
        end
    end
    return twin
end

function phase_network_z(twin, buses, frequency; floating_stars = false)
    floating_stars && return floating_star_network_z(twin, buses, frequency)
    inputs = [Symbol(b.name, "_", phase) for b in buses for phase in 1:3]
    nodes = unique([n for e in values(twin.elements) for n in values(e.pins)])
    grounds = filter(n -> startswith(string(n), "gnd_"), nodes)
    order = [inputs; setdiff(nodes, [inputs; grounds])]
    topology = Dict{Symbol, Array{Union{Symbol, Int}}}(:node_list => order,
        :element_list => collect(keys(twin.elements)), :output_list => grounds)
    return PowerImpedance.make_z(twin, topology, copy(inputs), copy(grounds),
        ComplexF64(im * 2π * frequency))
end

function applicable_scan(id, net, list; definition = nothing)
    spec, reference = scan_definition(id, net, list)
    if id in ("L1-03", "L1-04", "L1-08")
        frequencies = l1_settings().frequencies # phase tones have no shifted DC sideband
        spec = merge(spec, (; dimension = 3,
            axes = ["p$(port)_$(phase)" for port in eachindex(spec.buses) for phase in ("a", "b", "c")],
            frequencies, phases = [-π*k*(k-1)/length(frequencies) for k in eachindex(frequencies)],
            voltage_bases = repeat(spec.voltage_bases[1:2:end]; inner = 3),
            current_bases = repeat(spec.current_bases[1:2:end]; inner = 3),
            protocol = "abc", estimated_station_seconds = id == "L1-08" ? 2400 : 660))
        if id == "L1-08"
            twin = phase_twin(net, list)
            reference = cat((phase_network_z(twin, spec.buses, f; floating_stars = true) for f in frequencies)...; dims = 3)
        else
            reference = cat((PowerImpedance.abcd_to_y(
                eval_abcd(net.elements[:line].element_model, ComplexF64(im*2π*f)))
                for f in frequencies)...; dims = 3)
        end
        bound = maximum(sum(abs.(scale_response(reference, spec)); dims = 3))
        spec = merge(spec, (; tone_peak_pu = min(5e-5, 0.004/max(bound, 1.0))))
        if id in ("L1-03", "L1-04")
            # Measured cold-start DC-offset time constants: 0.6 s / 3.5 s.
            # Retain the source path and tones; only delay coherent windows.
            start = id == "L1-03" ? 5.0 : 20.0
            spec = merge(spec, (; protocol = "abc_settled",
                window_starts = (start, start + 1.0), simulation_time = start + 2.0,
                estimated_station_seconds = id == "L1-03" ? 840 : 2040))
        end
    elseif startswith(id,"L2-")
        # Already frozen by the active-device measurement definition.
    elseif id == "L1-05"
        spec = merge(spec, (; protocol = "settled", window_starts = (6.0, 7.0),
            simulation_time = 8.0, estimated_station_seconds = 900))
    else
        spec = merge(spec, (; protocol = ""))
    end
    if definition !== nothing && get(definition, "protocol", "") == spec.protocol
        # The prepared measurement settings are authoritative. Reuse their
        # exact floating values instead of deriving amplitude/bases/angles anew
        # from tiny solver or reduction round-off in a fresh process.
        voltages = Float64.(definition["voltage_bases_kV"])
        currents = Float64.(definition["current_bases_kA"])
        buses = [P.Bus(b.key, b.name, b.nets, b.kind, b.base_kV,
            voltages[1+(port-1)*spec.dimension]/(spec.dimension == 1 ? 2b.base_kV : sqrt(2)*b.base_kV),
            definition["ports"][port]["angle_rad"], b.pf_index)
            for (port, b) in enumerate(spec.buses)]
        spec = merge(spec, (; buses, voltage_bases = voltages, current_bases = currents,
            tone_peak_pu = Float64(definition["tone_peak_pu"])))
    end
    return spec, reference
end

scan_prefix(spec) = isempty(get(spec, :protocol, "")) ? "" : spec.protocol * "_"
reference_filename(spec) = scan_prefix(spec) * "reference.tsv"

# IEEE9 acceptance concerns each local 3x3 impedance. Cross-bus transfer is
# retained as evidence but cannot dilute either local block's Frobenius error.
function response_rows(spec, actual, reference; kwargs...)
    if spec.id == "L1-08" && spec.dimension == 3
        rows = NamedTuple[]
        for port in eachindex(spec.buses)
            indices = (3port-2):3port
            local_rows = comparison_rows(spec.frequencies, actual[indices, indices, :],
                reference[indices, indices, :]; kwargs...)
            append!(rows, [merge(row, (; row = row.row+3(port-1), column = row.column+3(port-1)))
                for row in local_rows])
        end
        return rows
    end
    return comparison_rows(spec.frequencies, actual, reference; kwargs...)
end

# Diagnostic only: the existing Impedance ABCD cache holds one evaluated
# matrix. Native conversions and native make_z retain physics and topology.
function projected_admittance_z(net, list, spec, frequency)
    evaluated = deepcopy(net)
    for (name, original) in net.elements
        original.element_model isa PowerImpedance.Source && continue
        projected = PowerImpedance.transformation_dq(
            PowerImpedance.abcd_to_y(eval_abcd(original.element_model, ComplexF64(im*2π*(frequency+50)))),
            PowerImpedance.abcd_to_y(eval_abcd(original.element_model, ComplexF64(im*2π*(frequency-50)))))
        abcd = PowerImpedance.y_to_abcd(projected)
        isapprox(PowerImpedance.abcd_to_y(abcd), projected; rtol = 1e-10, atol = 1e-12) ||
            error("projected admittance cache does not preserve its matrix")
        evaluated.elements[name] = PowerImpedance.Element(
            element_model = PowerImpedance.Impedance(ABCD = abcd),
            input_pins = 2, output_pins = 2, transformation = false,
            pins = copy(original.pins), symbol = name)
    end
    return scan_reference(evaluated, list, merge(spec, (; frequencies = [frequency])))[:, :, 1]
end

function dq_approximation(id, net, list, directory)
    spec, native = scan_definition(id, net, list)
    analysis = joinpath(directory, "analysis", "probe-orientation")
    response_path = joinpath(analysis, spec.quantity == "Y" ? "measured_S.tsv" : "measured_ohm.tsv")
    if !isfile(response_path) || !isfile(joinpath(directory, "manifest.toml"))
        return Dict("fixture"=>id, "label"=>"dq approximation", "informational_only"=>true,
            "measurement_status"=>"not measured; applicable abc comparison is independent")
    end
    measured = read_response(joinpath(analysis, spec.quantity == "Y" ? "measured_S.tsv" : "measured_ohm.tsv"),
        length(spec.axes), spec.frequencies)
    if id == "L1-08"
        alternative = cat((projected_admittance_z(net, list, spec, f)
            for f in spec.frequencies)...; dims = 3)
        order = "native network reduction of projected element ABCD versus projected element phase Y; ideal sources unchanged"
    else
        model = net.elements[:line].element_model
        alternative = cat((PowerImpedance.transformation_dq(
            PowerImpedance.abcd_to_y(eval_abcd(model, ComplexF64(im*2π*(f+50)))),
            PowerImpedance.abcd_to_y(eval_abcd(model, ComplexF64(im*2π*(f-50)))))
            for f in spec.frequencies)...; dims = 3)
        order = "ABCD projection then Y versus phase Y then projection"
    end
    native = read_response(joinpath(directory, "reference.tsv"), length(spec.axes), spec.frequencies)
    base_rows = comparison_rows(spec.frequencies, scale_response(measured, spec), scale_response(native, spec))
    alt_rows = comparison_rows(spec.frequencies, scale_response(measured, spec), scale_response(alternative, spec))
    record = TOML.parsefile(joinpath(directory, "manifest.toml"))
    sideband = record["corrected_analysis"]["tier_c_result"]["omitted_sideband_ratio"]
    output = mkpath(joinpath(directory, "analysis", "dq-approximation"))
    write_table(joinpath(output, "per-frequency.tsv"),
        [(frequency_Hz = f, label = "dq approximation",
            ABCD_projection_error = maximum(r.frobenius_error for r in base_rows if r.frequency_Hz == f),
            admittance_projection_error = maximum(r.frobenius_error for r in alt_rows if r.frequency_Hz == f))
            for f in spec.frequencies])
    write_table(joinpath(output, "per-entry.tsv"),
        [(frequency_Hz = r.frequency_Hz, row = r.row, column = r.column,
            label = "dq approximation", complex_error_pu = r.complex_error_pu,
            normalized_entry_error = r.complex_error_pu/max(abs(complex(r.reference_real_pu,r.reference_imag_pu)),0.02),
            phase_error_deg = r.phase_error_deg) for r in base_rows])
    return Dict("fixture"=>id, "label"=>"dq approximation", "informational_only"=>true,
        "max_dq_error"=>maximum(r.frobenius_error for r in base_rows),
        "sideband_ratio"=>sideband,
        "ABCD_projection_error"=>maximum(r.frobenius_error for r in base_rows),
        "admittance_projection_error"=>maximum(r.frobenius_error for r in alt_rows),
        "projection_order"=>order,
        "provenance"=>"recorded old dq run project hashes and orientations; corrected measured response; native harmonic projection",
        "source_directory"=>"analysis/probe-orientation")
end

# Emitted YY cores have two floating internal stars (mapping doc, transformer
# emitter). The original phase model grounds their voltage references. For
# IEEE9, remove each winding zero-sequence path while preserving external Ct/Cs
# ground/bridge paths. Q = I - 11'/3 is exact elimination of the two floating
# neutral voltages for these identical phase windings. Near-ideal Xl and Im1
# are the existing emitter values; leakage is split symmetrically. No PSCAD
# project, geometry or package formula changes. Native make_y owns assembly
# of the remaining elements; ideal source buses are voltage-clamped.
function floating_star_network_z(net, buses, frequency)
    s = ComplexF64(im * 2π * frequency)
    inputs = [Symbol(b.name, "_", phase) for b in buses for phase in 1:3]
    grounds = [node for e in values(net.elements) for node in values(e.pins)
        if startswith(string(node), "gnd_")]
    append!(grounds, [node for e in values(net.elements)
        if e.element_model isa PowerImpedance.Source for node in values(e.pins)])
    nodes = setdiff(unique([node for e in values(net.elements) for node in values(e.pins)]), grounds)
    other_elements = [name for (name, e) in net.elements
        if !(e.element_model isa Union{PowerImpedance.Source, PowerImpedance.Transformer})]
    topology = Dict{Symbol, Array{Union{Symbol, Int}}}(:node_list => nodes,
        :element_list => other_elements)
    admittance = PowerImpedance.make_y(net, topology, s)
    for e in values(net.elements)
        e.element_model isa PowerImpedance.Transformer || continue
        winding = floating_star_transformer_y(e.element_model, s)
        for (pin, node) in e.pins, (other_pin, other_node) in e.pins
            row = findfirst(==(node), nodes)
            column = findfirst(==(other_node), nodes)
            row === nothing || column === nothing ||
                (admittance[row, column] += winding[
                    PowerImpedance._admittance_index(e, pin, 3),
                    PowerImpedance._admittance_index(e, other_pin, 3)])
        end
    end
    drive = zeros(ComplexF64, length(nodes), length(inputs))
    for (column, node) in enumerate(inputs)
        row = findfirst(==(node), nodes)
        row === nothing || (drive[row, column] = 1)
    end
    voltage = admittance \ drive
    response = zeros(ComplexF64, length(inputs), length(inputs))
    for (row, node) in enumerate(inputs)
        index = findfirst(==(node), nodes)
        index === nothing || (response[row, :] = voltage[index, :])
    end
    return response
end

function floating_star_transformer_y(original, s; regularization = true)
    original.organization == :YY && original.Rₘ == original.Lₘ == 0 ||
        error("floating-star reference is restricted to the IEEE9 YY circuits without external excitation shunts")
    model = deepcopy(original)
    if regularization
        impedance_base = (sqrt(3) * model.V₁ᵒ / 1000)^2 / P.TRANSFORMER_BASE_MVA
        leakage = P.YY_LEAKAGE_PU * impedance_base / (2π * 50)
        model.Lₚ += leakage / 2
        model.Lₛ += leakage / (2model.n^2)
        model.Lₘ = impedance_base / (2π * 50 * (P.YY_MAGNETIZING_CURRENT_PERCENT / 100))
    end
    total = PowerImpedance.abcd_to_y(eval_abcd(model, s))
    model.Cₜ = model.Cₛ = 0
    winding = PowerImpedance.abcd_to_y(eval_abcd(model, s))
    projection = kron(Matrix{Float64}(I, 2, 2), Matrix{Float64}(I, 3, 3) .- 1/3)
    # Terminal shunts and the bridge remain ground-referenced as emitted.
    return projection * winding * projection + (total - winding)
end
