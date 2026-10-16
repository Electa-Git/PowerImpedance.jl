function scan_samples(result, model, spec)
    voltages, currents = Matrix{Float64}[], Matrix{Float64}[]
    for (port, bus) in enumerate(spec.buses)
        if spec.dimension == 1
            poles = [only(filter(
                         c -> c.kind == :voltage && c.bus == bus.name && c.side == pole,
                         model.probes.channels)) for pole in ("P", "N")]
            voltage = reshape(
                result.channels[poles[1].name] -
                result.channels[poles[2].name], :, 1)
        else
            probe = only(filter(c -> c.kind == :voltage && c.bus == bus.name, model.probes.channels))
            samples = probe_samples(result, probe)
            voltage = spec.dimension == 3 ? samples : fixed_dq(result.time, samples)
        end
        element, side = spec.currents[port]
        probe = only(filter(
            c -> c.kind == (spec.quantity == "Z" ? :injection_current : :current) &&
                 c.element == element && c.side == side,
            model.probes.channels))
        current = spec.dimension == 1 ? reshape(result.channels[probe.name], :, 1) :
                  spec.dimension == 3 ? probe_samples(result, probe) :
                  fixed_dq(result.time, probe_samples(result, probe))
        # Y uses current entering the measured element. Z uses current injected
        # into the network, i.e. leaving the shunt source. The model must retain
        # the channel metadata of the project which produced this result.
        positive = spec.quantity == "Y" ? :into : :out
        probe.orientation in (:into, :out) || error("missing recorded current orientation")
        probe.orientation == positive || (current = -current)
        push!(voltages, voltage)
        push!(currents, current)
    end
    voltage, current = reduce(hcat, voltages), reduce(hcat, currents)
    input, output = spec.quantity == "Y" ? (voltage, current) : (current, voltage)
    input_base, output_base = spec.quantity == "Y" ?
                              (spec.voltage_bases, spec.current_bases) :
                              (spec.current_bases, spec.voltage_bases)
    if get(spec,:drive,"") == "current"
        probe=only(filter(c->c.kind==:injection_current,model.probes.channels))
        drive=fixed_dq(result.time,probe_samples(result,probe))
        probe.orientation==:out || error("injected current must be recorded outwards")
        if spec.dc_voltage_base_kV===nothing
            return (; voltage,current,input,output,input_base,output_base,drive,drive_base=spec.current_bases)
        end
        poles=[only(filter(c->c.kind==:voltage && c.bus==port_probe(model.netlist,:DUT,1).name && c.side==pole,
            model.probes.channels)) for pole in ("P","N")]
        dc_voltage=result.channels[poles[1].name]-result.channels[poles[2].name]
        return (; voltage,current,input,output,input_base,output_base,drive,drive_base=spec.current_bases,dc_voltage)
    end
    return (; voltage, current, input, output, input_base, output_base)
end

function scan_quality(time, baseline, runs, spec; columns = eachindex(spec.axes))
    windows = [searchsortedfirst(time, start):(searchsortedfirst(time, start + spec.window_duration) - 1)
               for start in spec.window_starts]
    dc_drift = maximum(norm(vec(mean(signal[windows[1], :]; dims = 1)) -
                         vec(mean(signal[windows[2], :]; dims = 1))) /
                    max(norm(vec(mean(signal[windows[1], :]; dims = 1))), 0.1)
    for signal in (baseline.input ./ baseline.input_base', baseline.output ./
                                                           baseline.output_base'))
    fundamental_drift = 0.0
    if spec.dimension == 3
        for signal in (baseline.input ./ baseline.input_base', baseline.output ./ baseline.output_base')
            phasors = [dft_phasors(time, signal, [spec.frequency]; start,
                duration = spec.window_duration) for start in spec.window_starts]
            fundamental_drift = max(fundamental_drift, norm(phasors[2]-phasors[1])/max(norm(phasors[1]), 0.1))
        end
    end
    drift = max(dc_drift, fundamental_drift)
    # The linearity gate qualifies the same settled, coherent windows as C.
    # A sharp shunt-current turn-on into inductors produces a voltage impulse
    # proportional to amplitude/dt; retain that full-run maximum diagnostically.
    # Do not remove means: a steady baseline offset still counts as departure.
    input_deltas = [(run.input-baseline.input) ./ baseline.input_base' for run in runs]
    output_deltas = [(run.output-baseline.output) ./ baseline.output_base' for run in runs]
    full_input_departure = maximum(maximum(abs,delta) for delta in input_deltas)
    full_output_departure = maximum(maximum(abs,delta) for delta in output_deltas)
    input_departure = maximum(maximum(abs,delta[window,:]) for delta in input_deltas for window in windows)
    output_departure = maximum(maximum(abs,delta[window,:]) for delta in output_deltas for window in windows)
    amplitude_error, clamped = 0.0, 0.0
    for (run, column) in zip(runs, columns), start in spec.window_starts

        driven = get(spec,:drive,"")=="current"
        signal = driven ? run.drive-baseline.drive : run.input-baseline.input
        base = driven ? baseline.drive_base : baseline.input_base
        phasors = dft_phasors(time, signal, spec.frequencies;
            start, duration = spec.window_duration)
        amplitude_error = max(amplitude_error,
            maximum(abs.(abs.(phasors[column, :]) ./
                         (spec.tone_peak_pu * base[column]) .- 1)))
        if spec.quantity == "Y" && !driven
            others = setdiff(axes(run.input, 2), [column])
            isempty(others) || (clamped = max(clamped,
                maximum(abs,
                    (run.input[:, others] - baseline.input[:, others]) ./
                    baseline.input_base[others]')))
        end
    end
    if get(spec,:drive,"")=="current" && get(spec,:dc_clamped,true)
        clamped=maximum(maximum(abs,run.dc_voltage-baseline.dc_voltage)/spec.dc_voltage_base_kV for run in runs)
    end
    valid = drift <= 1e-3 && input_departure <= 0.01 && output_departure <= 0.01 &&
            amplitude_error <= 0.01 && clamped <= 1e-6
    return Dict{String, Any}("valid" => valid, "baseline_drift" => drift,
        "baseline_dc_drift" => dc_drift, "baseline_fundamental_drift" => fundamental_drift,
        "input_departure_pu" => input_departure, "output_departure_pu" => output_departure,
        "departure_scope" => "baseline-subtracted samples in the declared coherent measurement windows; means retained",
        "full_run_input_departure_pu" => full_input_departure,
        "full_run_output_departure_pu" => full_output_departure,
        "drive_amplitude_error" => amplitude_error, "clamped_voltage_departure_pu" =>
            clamped)
end

function matrix_change(actual, expected; epsilon)
    size(actual) == size(expected) || error("refinement dimensions")
    norm_error = maximum(norm(actual[:, :, k] - expected[:, :, k]) /
                         max(norm(expected[:, :, k]), 0.1) for k in axes(expected, 3))
    entry_error = maximum(abs.(actual - expected) ./ max.(abs.(expected), 0.02))
    return Dict("passed" => norm_error <= epsilon && entry_error <= epsilon,
        "frobenius_change" => norm_error, "entry_change" => entry_error, "limit" => epsilon)
end

function single_response(result, baseline_result, model, spec, column)
    result.time == baseline_result.time || error("witness/baseline sample times differ")
    baseline = scan_samples(baseline_result, model, spec)
    run = scan_samples(result, model, spec)
    matrices = Array{ComplexF64, 3}[]
    for start in spec.window_starts
        input = dft_phasors(result.time, run.input - baseline.input,
            spec.frequencies; start, duration = spec.window_duration)
        output = dft_phasors(result.time, run.output - baseline.output,
            spec.frequencies; start, duration = spec.window_duration)
        if get(spec,:drive,"")=="current"
            # One current-drive witness cannot identify two Y columns when the
            # terminal voltage couples dq. Qualify both measured V/I responses
            # per injected current instead, preserving the ONE-axis witness.
            input=dft_phasors(result.time,run.drive-baseline.drive,spec.frequencies;
                start,duration=spec.window_duration)
            output=vcat(dft_phasors(result.time,run.voltage-baseline.voltage,spec.frequencies;
                start,duration=spec.window_duration),output)
        end
        all(>(0), abs.(input[column, :])) || error("zero witness drive")
        response = reshape(output ./ input[column:column, :], size(output, 1), 1, :)
        input_base = get(spec,:drive,"")=="current" ? baseline.drive_base[column] : baseline.input_base[column]
        output_base = get(spec,:drive,"")=="current" ? [baseline.input_base;baseline.output_base] : baseline.output_base
        push!(matrices,response .* reshape(input_base ./ output_base,:,1,1))
    end
    quality = scan_quality(result.time, baseline, [run], spec; columns = [column])
    change = matrix_change(matrices[2], matrices[1]; epsilon = 0.01)
    quality["window_change"] = change["frobenius_change"]
    quality["valid"] &= change["passed"]
    if spec.id == "L1-01"
        departure = maximum(abs,
            branch_samples(result, model).clamped_voltage -
            branch_samples(baseline_result, model).clamped_voltage) / spec.voltage_bases[1]
        quality["clamped_voltage_departure_pu"] = max(quality["clamped_voltage_departure_pu"], departure)
        quality["valid"] &= departure <= 1e-6
    end
    return sum(matrices) / length(matrices), quality
end

step_prefix(spec) = scan_prefix(spec) * "half_step_" * join(round.(Int, spec.frequencies), "_") * "__"

function step_definition(spec, frequency)
    frequencies = frequency == 1000.0 ? [750.0, 1000.0] : unique(sort([frequency, 1000.0]))
    common_frequency = gcd(50, reduce(gcd, round.(Int, frequencies)))
    # The minimum window must contain whole common periods too: 75/1000 Hz
    # needs 0.12 s, since a 0.1 s window contains 7.5 cycles at 75 Hz.
    duration = ceil(Int, get(spec,:minimum_witness_window_s,0.1) * common_frequency) / common_frequency
    settle = get(spec, :protocol, "") in ("settled", "abc_settled", "dq_active") ?
             first(spec.window_starts) : 0.8
    start = ceil(Int, settle * common_frequency) / common_frequency
    n = length(frequencies)
    # Preserve an odd recorder ratio at the witness's own half step. Historical
    # even-ratio definitions retain their original sampling for stored analyses.
    sample_step = isodd(round(Int, spec.sample_step / spec.time_step)) ?
        spec.sample_step / 2 : spec.sample_step
    return merge(spec,
        (; frequencies, phases = [-π * k * (k - 1) / n for k in 1:n],
            time_step = spec.time_step / 2, sample_step, window_duration = duration,
            window_starts = (start, start + duration), simulation_time = start + 2duration))
end

function write_response(path, matrix, frequencies; quantity = "Y")
    rows = [(frequency_Hz = f, row = r, column = c, real = real(matrix[r, c, k]),
                imag = imag(matrix[r, c, k]), unit = quantity == "Y" ? "S" : "ohm")
            for (k, f) in enumerate(frequencies) for c in axes(matrix, 2)
            for r in axes(matrix, 1)]
    return write_table(path, rows)
end

function read_response(path, dimension, frequencies)
    rows = [split(line, '\t') for line in readlines(path)[2:end]]
    length(rows) == dimension^2 * length(frequencies) || error("reference shape")
    return reshape(
        [complex(parse(Float64, row[4]), parse(Float64, row[5])) for row in rows],
        dimension, dimension, length(frequencies))
end

# Clone a baseline from the existing writer; change only declared instance
# amplitude parameters. Project IDs, namespaces and all physical fields remain identical.
function axis_project(baseline, plan, spec, axis)
    text = baseline
    for component in plan.main.components
        component isa P.ModuleInstancePlan || continue
        occursin("Port", component.defn) || occursin("Pole", component.defn) || continue
        marker = "defn=\"$(component.defn)\""
        region = findfirst(marker, text)
        region === nothing && error("missing injection module instance")
        finish = findnext("</User>", text, last(region))
        finish === nothing && error("unfinished module instance")
        segment = text[first(region):last(finish)]
        for (name, value) in component.params
            pattern = "<param name=\"$name\" value=\"0.0\"/>"
            length(findall(pattern, segment)) == 1 ||
                error("ambiguous amplitude parameter $name")
            segment = replace(segment, pattern => "<param name=\"$name\" value=\"$value\"/>"; count = 1)
        end
        text = text[1:(first(region) - 1)] * segment * text[(last(finish) + 1):end]
    end
    return text
end

function prepare_scan_projects(directory, list, spec, axes; prefix = "")
    check_recorder_sampling(spec)
    name = lowercase(replace(spec.id, '-' => '_'))
    baseline_axis = prefix * "baseline"
    baseline_path = joinpath(mkpath(joinpath(directory, baseline_axis)), name * ".pscx")
    plan, settings = scan_plan(list, spec, "baseline"; name)
    if endswith(prefix, "half_amplitude_") && !isfile(baseline_path)
        template = get(spec, :baseline_template, scan_prefix(spec) * "baseline")
        cp(joinpath(directory, template, name * ".pscx"), baseline_path)
    end
    if isfile(baseline_path)
        baseline = read(baseline_path, String)
        version = Base.get_extension(PowerImpedance, :PowerImpedancePSCADExt)._mhi_xml_version()
    else
        written = P._write_project(plan, baseline_path)
        baseline = read(written.path, String)
        version = written.mhi_xml_version
    end
    models = Pair{String, P.PSCADModel}[]
    for axis in ["baseline"; axes]
        key = prefix * axis
        axis_plan, settings = scan_plan(list, spec, axis; name)
        path = joinpath(mkpath(joinpath(directory, key)), name * ".pscx")
        generated = axis_project(baseline, axis_plan, spec, axis)
        if isfile(path)
            read(path, String) == generated ||
                error("existing scan project differs: $path; preserve it before changing a fixture")
        else
            write(path, generated)
        end
        push!(models,
            key => P.PSCADModel(abspath(path), name, list, axis_plan.probes,
                settings, list.operating_point,
                (source = :validation, mhi_xml_version = version, baseline_axis = baseline_axis)))
    end
    return models
end

function record_project!(record, axis, model, directory)
    item = Dict("axis" => axis, "path" => relpath(model.project_path, directory),
        "sha256" => digest(model.project_path), "settings" =>
            P._settings_record(model.settings),
        "mhi_xml_version" => model.provenance.mhi_xml_version,
        "baseline_axis" => model.provenance.baseline_axis,
        "probes" => probe_record.(model.probes.channels))
    index = findfirst(p -> p["axis"] == axis, record["projects"])
    if index === nothing
        push!(record["projects"], item)
    else
        record["projects"][index]["sha256"] == item["sha256"] ||
            error("project changed during preparation")
        record["projects"][index] = item
    end
end

function execute_axis!(record, key, model, directory, remote, deadline)
    remaining = floor(Int, deadline-time())
    remaining > 0 || error("L1 station runtime budget exhausted")
    result = resume_axis(model, key, directory, budget_remote(remote, remaining))
    if result === nothing
        remaining = floor(Int, deadline-time())
        remaining > 0 || error("L1 station runtime budget exhausted")
        println("Running ", record["fixture_id"], " ",
            key, "; remaining budget [s]=", remaining)
        parent = mkpath(joinpath(remote.local_root, "validation", record["fixture_id"]))
        work_root = mktempdir(parent; prefix = key * "-", cleanup = false)
        destination = joinpath(directory, "runs", basename(work_root))
        mkpath(dirname(destination))
        try
            result = compute(model,
                PSCADRun();
                options = (
                    remote = budget_remote(remote, remaining), work_root, verbosity = 1))
        finally
            cp(work_root, destination)
        end
        native = relpath(result.paths.run_directory, work_root)
    else
        destination = dirname(result.paths.run_directory)
        native = basename(result.paths.run_directory)
        println("Resuming ", record["fixture_id"], " ", key)
    end
    messages = read(result.paths.build_messages, String)
    matched = match(r"The total number of live nodes: (\d+)", messages)
    live = matched === nothing ? 0 : parse(Int, matched[1])
    0 < live < 100 || error("missing/over-budget live node count: $live")
    solver = result.diagnostics.solver_identity
    item = Dict("axis"=>key, "path"=>relpath(destination, directory),
        "native_run_directory"=>native,
        "live_nodes"=>live, "project_run_seconds"=>result.diagnostics.elapsed_seconds,
        "reused"=>result.diagnostics.reused, "solver"=>solver, "settings_readback"=>result.diagnostics.settings_readback,
        "build_warnings"=>result.diagnostics.build_warnings, "project_sha256"=>digest(model.project_path))
    item["probes"] = only(filter(p -> p["axis"] == key, record["projects"]))["probes"]
    index = findfirst(r -> r["axis"] == key && r["path"] == item["path"], record["run_records"])
    if index === nothing
        push!(record["run_records"], item)
    else
        record["run_records"][index] = item
    end
    record["pscad_version_observed"] = solver["version"]
    record["compiler_observed"] = solver["fortran_version"]
    write_manifest(directory, record)
    return result
end

function existing_model(record, key, list, spec, directory; prefix = scan_prefix(spec))
    project = only(filter(p -> p["axis"] == key, record["projects"]))
    logical = chop(key; head = length(prefix), tail = 0)
    axis = logical == "baseline" ? "baseline" : replace(logical, "half_amplitude_"=>"")
    plan, settings = scan_plan(list, spec, axis)
    return P.PSCADModel(
        joinpath(directory, project["path"]), lowercase(replace(spec.id, '-'=>'_')),
        list, recorded_probes(project["probes"], plan.probes.reference_bus),
        settings, list.operating_point, (source = :validation,))
end

function run_fixture(id; remote = RemoteConfig(),
        directory = joinpath(ROOT, "data", id), deadline = time()+5400)
    startswith(id, "L3-") && return run_composed(id; remote, directory, deadline)
    record = manifest_lists!(TOML.parsefile(joinpath(directory, "manifest.toml")))
    verify_inputs(directory, record)
    record["fixture_id"] == id || error("fixture mismatch")
    entry = fixture(id)
    net = entry.factory()
    point = power_flow(net)
    gate = stability_gate(net, entry)
    gate["status"] == "passed" || error("$(entry.id) failed complete-network stability gate: $gate")
    list = fixture_netlist(net, point)
    spec, reference = applicable_scan(id, net, list; definition = record["tier_c"])
    stored = read_response(joinpath(directory, reference_filename(spec)), length(spec.axes), spec.frequencies)
    record_native_reference!(record,directory,spec,reference,stored,list)
    scan_record(spec) ==
    Dict(key=>record["tier_c"][key] for key in keys(scan_record(spec))) ||
        error("scan definition changed")
    if startswith(get(record,"status",""),"explained:")
        println(id,": ",record["status"],"; owner disposition retained, numerical rules unchanged")
        return record
    end
    accepted = get(record, "status", "") == "passed" &&
        get(record, "tier_a_status", "") == "passed" &&
        get(get(record, "corrected_analysis", Dict()), "status", "") == "passed" &&
        get(get(record, "amplitude_refinement", Dict()), "passed", false) &&
        get(get(record, "step_refinement", Dict()), "passed", false)
    if isempty(scan_prefix(spec)) && accepted
        println(id, ": passed; retained operating-point, comparison and refinement evidence verified")
        return record
    end
    results, models = Dict{String, P.PSCADResult}(), Dict{String, P.PSCADModel}()
    started = time()
    comparison_directory = mkpath(joinpath(directory, "analysis", isempty(scan_prefix(spec)) ? "dq" : spec.protocol))
    record["status"] = "running"
    pop!(record, "failure", nothing)
    try
        for key in ["baseline"; spec.axes]
            ledger_key = scan_prefix(spec) * key
            model = existing_model(record, ledger_key, list, spec, directory)
            result = execute_axis!(record, ledger_key, model, directory, remote, deadline)
            models[key], results[key] = model, result
            if key == "baseline"
                rows = compare_operating_point(result, model)
                write_table(joinpath(comparison_directory, "comparison_A.tsv"), rows)
                record["tier_a_status"] = all(rows.within_tolerance) ? "passed" : "failed"
                write_manifest(directory, record)
            end
        end
        record["tier_c_result"] = compare_frequency_runs(
            results, models, stored, comparison_directory; spec)
        record_interface_comparison!(record, net, spec, directory, comparison_directory)
        # Reference-only revisions do not invalidate measured method witnesses.
        # Retain their original axis/band instead of requesting another run.
        selected = haskey(record, "step_witness_definition") ?
            only(findall(==(record["step_witness_definition"]["axis"]), spec.axes)) :
            record["tier_c_result"]["worst_column"]
        axis = spec.axes[selected]
        half_spec = merge(spec, (tone_peak_pu = spec.tone_peak_pu/2,))
        half_key = scan_prefix(spec) * "half_amplitude_" * axis
        half_model = existing_model(record, half_key, list, half_spec, directory)
        half_result = execute_axis!(
            record, half_key, half_model, directory, remote, deadline)
        base_column, base_quality = single_response(
            results[axis], results["baseline"], models[axis], spec, selected)
        half_column, half_quality = single_response(
            half_result, results["baseline"], half_model, half_spec, selected)
        amp = matrix_change(half_column, base_column; epsilon = 0.02)
        amp["valid"] = base_quality["valid"] && half_quality["valid"]
        amp["passed"] &= amp["valid"]
        write_table(joinpath(comparison_directory, "comparison_half_amplitude.tsv"),
            refinement_rows(spec.frequencies, half_column, base_column;
                limit = 0.02, valid = amp["valid"]))
        record["amplitude_refinement"] = merge(amp, Dict("axis"=>axis, "quality"=>half_quality))
        write_manifest(directory, record)
        witness_frequency = haskey(record, "step_witness_definition") ?
            first(record["step_witness_definition"]["frequencies"]) :
            record["tier_c_result"]["worst_frequency_Hz"]
        step_spec = step_definition(spec, witness_frequency)
        if !haskey(record, "step_witness_definition")
            record["step_witness_definition"] = merge(scan_record(step_spec), Dict("axis"=>axis))
        else
            record["step_witness_definition"]["axis"] == axis &&
            record["step_witness_definition"]["frequencies"] == step_spec.frequencies ||
                error("refinement selection changed; preserve previous evidence before selecting a new witness")
        end
        # Local project writing only. The manual environment activates the
        # existing writer; no native component or public API is introduced.
        prefix = step_prefix(step_spec)
        step_models = prepare_scan_projects(directory, list, step_spec, [axis]; prefix)
        for (key, model) in step_models
            record_project!(record, key, model, directory)
        end
        write_manifest(directory, record)
        step_baseline = execute_axis!(
            record, prefix * "baseline", first(step_models).second,
            directory, remote, deadline)
        step_run = execute_axis!(
            record, prefix * axis, last(step_models).second, directory, remote, deadline)
        step_column, step_quality = single_response(
            step_run, step_baseline, last(step_models).second, step_spec, selected)
        checks = Dict{String, Any}[]
        if residual_step_eligible(id, net)
            for (index, key) in enumerate(spec.axes)
                push!(checks, readout_evidence(results[key], results["baseline"], models[key], spec, index))
            end
            push!(checks, readout_evidence(half_result, results["baseline"], half_model, half_spec, selected;
                axis = half_key))
            push!(checks, readout_evidence(step_run, step_baseline, last(step_models).second, step_spec, selected;
                axis = prefix * axis))
        end
        record_step_witness!(record, net, spec, step_spec, selected,
            base_column, step_column, base_quality, step_quality, models[axis],
            last(step_models).second, checks, comparison_directory)
        qualify_fixture!(record; residual = residual_step_eligible(id, net))
        if haskey(record, "resonance_scan")
            run_resonance!(record, net, list, spec; directory, remote, deadline)
        end
    catch failure
        record["status"] = "run_or_analysis_failed"
        record["failure"] = sprint(showerror, failure)
        rethrow()
    finally
        record["station_workflow_seconds"] = time()-started
        write_manifest(directory, record)
    end
    println(id, ": ", record["status"], "; comparisons: ", get(record, "comparison_summary", Dict()))
    return record
end

function run_l1(; remote = RemoteConfig(), deadline = time()+5400)
    records = [run_fixture(entry.id; remote, deadline) for entry in REGISTRY if startswith(entry.id,"L1-")]
    return records
end

function refinement_rows(frequencies, actual, reference; limit, valid)
    rows=NamedTuple[]
    for (k, f) in enumerate(frequencies)
        change=matrix_change(actual[:, :, k:k], reference[:, :, k:k]; epsilon = limit)
        push!(rows,
            (frequency_Hz = f, frobenius_change = change["frobenius_change"],
                entry_change = change["entry_change"],
                change_limit = limit, valid, within_tolerance = valid && change["passed"]))
    end
    return rows
end

# A fixed dq LTI reference predicts no +/-100 Hz conversion. Retain this check
# for untransposed phase-domain circuits; the approved 2% complex budget and
# 0.1 pu norm floor bound omitted coupling rather than relaxing comparisons.
function sideband_coupling(time, baseline, runs, spec)
    spec.dimension==2 && spec.id!="L1-01" || return 0.0
    frequencies=unique(sort([abs(f+shift) for f in spec.frequencies
                             for shift in (-100.0, 100.0)
                             if abs(f+shift)>0 && !(abs(f+shift) in spec.frequencies)]))
    isempty(frequencies) && return 0.0
    maximum_coupling=0.0
    for run in runs, start in spec.window_starts

        phasors=dft_phasors(
            time, (run.output-baseline.output) ./ baseline.output_base', frequencies;
            start, duration = spec.window_duration)
        main=dft_phasors(
            time, (run.output-baseline.output) ./ baseline.output_base', spec.frequencies;
            start, duration = spec.window_duration)
        level=max(maximum(norm(main[:, k]) for k in axes(main, 2)), 0.1spec.tone_peak_pu)
        maximum_coupling=max(maximum_coupling, maximum(norm(phasors[:, k])
        for k in axes(phasors, 2))/level)
    end
    return maximum_coupling
end
