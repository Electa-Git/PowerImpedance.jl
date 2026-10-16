# Zero-delay MMC fixtures qualify the unexplained change of their complete
# discrete response column. Positive-delay fixtures retain the raw witness.
const M9C12_IDS = ["L2-" * lpad(n, 2, '0') for n in 7:12]
residual_step_eligible(id, net) = id in M9C12_IDS &&
    interface_step_eligible(net.elements[:DUT].element_model)

# Read the exact scalar fields emitted in these fixtures, including units.
# These values are never estimated from measured responses.
function exported_passive(text, name, kind, field, unit)
    users = [m.match for m in eachmatch(r"<User\b[^>]*>.*?</User>"s, text)
             if occursin("<param name=\"Name\" value=\"$name\"/>", m.match)]
    user = only(users)
    occursin("defn=\"master:$kind\"", user) || error("unexpected passive $name")
    value = only([m.captures[1] for m in eachmatch(
        Regex("<param name=\"$field\" value=\"([^\"]+)\"/>"), user)])
    suffix = " [$unit]"
    endswith(value, suffix) || error("unexpected unit for $name")
    number = parse(Float64, chop(value; tail = length(suffix)))
    isfinite(number) && number > 0 || error("invalid exported passive $name")
    return number
end

function exported_termination(net, project)
    text = read(project, String)
    resistance = exported_passive(text, "Grid_R", "resistor", "R", "ohm")
    inductance = exported_passive(text, "Grid_L", "inductor", "L", "H")
    form = P.identify_rlc(net.elements[:Grid]).form
    form.topology == :series && form.C === nothing || error("unsupported grid termination")
    isapprox(resistance, form.R; rtol = 1e-8) &&
        isapprox(inductance, form.L; rtol = 1e-8) || error("exported grid differs from fixture")
    dc_resistance = nothing
    if haskey(net.elements, :DC_load)
        poles = [exported_passive(text, "DC_load_$(pole)_R", "resistor", "R", "ohm")
                 for pole in ("P", "N")]
        r = sum(poles) # Differential DC path contains both pole resistors.
        expected = inv(real(PowerImpedance.get_y(net.elements[:DC_load], 0.0im)[1,1]))
        isapprox(r, expected; rtol = 1e-8) || error("exported DC load differs from fixture")
        dc_resistance = r
    end
    return (; resistance, inductance, dc_resistance)
end

injection_readout_factor(frequency, spec) =
    exp(im * 2π * frequency * spec.time_step) / cos(2π * spec.frequency * spec.time_step)

function discrete_response_column(net, spec, column, termination)
    dc_conductance = termination.dc_resistance === nothing ? nothing : inv(termination.dc_resistance)
    y = interface_step_reference(net, spec; dc_conductance)
    y === nothing && error("residual reference requires zero modulation delay")
    columns = Matrix{ComplexF64}[]
    for (k, frequency) in enumerate(spec.frequencies)
        s = im * 2π * frequency
        r, l = termination.resistance, termination.inductance
        z = [r+l*s 2π*spec.frequency*l; -2π*spec.frequency*l r+l*s]
        drive = zeros(ComplexF64, 2)
        drive[column] = 1
        voltage = (y[:,:,k] + inv(z)) \ drive
        current = y[:,:,k] * voltage
        scale = spec.current_bases[column] ./ [spec.voltage_bases; spec.current_bases]
        response = injection_readout_factor(frequency, spec) .* scale .* [voltage; current]
        push!(columns, reshape(response, :, 1))
    end
    return cat(columns...; dims = 3)
end

function kcl_readout_check(kcl, recorded, expected; limit = 1e-6)
    factor = iszero(recorded) ? ComplexF64(NaN, NaN) : kcl / recorded
    error = abs(factor / expected - 1)
    return Dict("passed" => isfinite(error) && error <= limit,
        "relative_error" => error, "limit" => limit,
        "factor_real" => real(factor), "factor_imag" => imag(factor),
        "expected_real" => real(expected), "expected_imag" => imag(expected))
end

function readout_evidence(result, baseline, model, spec, column; axis = spec.axes[column])
    result.time == baseline.time || error("KCL sample times differ")
    bus = only(spec.buses).name
    branches = [only(filter(c -> c.kind == :current && c.element == element && c.bus == bus,
        model.probes.channels)) for element in ("DUT", "Grid")]
    injection = only(filter(c -> c.kind == :injection_current, model.probes.channels))
    injection.orientation == :out || error("injection orientation missing")
    currents = [begin
        c.orientation in (:into, :out) || error("branch orientation missing")
        sign = c.orientation == :into ? 1 : -1
        sign .* fixed_dq(result.time, probe_samples(result, c) - probe_samples(baseline, c))
    end for c in branches]
    kcl = sum(currents)
    drive = fixed_dq(result.time, probe_samples(result, injection) - probe_samples(baseline, injection))
    rows = Dict{String, Any}[]
    for start in spec.window_starts
        kp = dft_phasors(result.time, kcl, spec.frequencies; start, duration = spec.window_duration)
        ip = dft_phasors(result.time, drive, spec.frequencies; start, duration = spec.window_duration)
        for (k, frequency) in enumerate(spec.frequencies)
            check = kcl_readout_check(kp[column,k], ip[column,k], injection_readout_factor(frequency, spec))
            push!(rows, merge(check, Dict("axis" => axis, "frequency_Hz" => frequency,
                "window_start_s" => start, "time_step_s" => spec.time_step)))
        end
    end
    return Dict("passed" => all(row["passed"] for row in rows),
        "max_relative_error" => maximum(row["relative_error"] for row in rows),
        "limit" => 1e-6, "rows" => rows,
        "measurement" => "baseline-subtracted inward DUT + grid current / recorded driven injection component, each coherent window")
end

function residual_step_change(main, half, predicted_main, predicted_half; valid)
    delta = (half - predicted_half) - (main - predicted_main)
    frobenius = maximum(norm(delta[:,:,k]) / max(norm(main[:,:,k]), 0.1) for k in axes(main, 3))
    entry = maximum(abs.(delta) ./ max.(abs.(main), 0.02))
    diagnostic = matrix_change(half - predicted_half, main - predicted_main; epsilon = 0.01)
    change = Dict{String, Any}("frobenius_change" => frobenius, "entry_change" => entry,
        "limit" => 0.01, "valid" => valid, "passed" => valid && frobenius <= 0.01 && entry <= 0.01,
        "residual_normalised_frobenius" => diagnostic["frobenius_change"],
        "residual_normalised_entry" => diagnostic["entry_change"])
    change["status"] = !valid ? "invalid_measurement" : change["passed"] ? "passed" : "failed"
    return change
end

function record_step_witness!(record, net, spec, step_spec, column,
        main, half, main_quality, half_quality, model, step_model, checks, output)
    indices = [only(findall(==(f), spec.frequencies)) for f in step_spec.frequencies]
    raw = Dict{String, Any}(matrix_change(half, main[:,:,indices]; epsilon = 0.01))
    raw["valid"] = main_quality["valid"] && half_quality["valid"]
    raw["passed"] &= raw["valid"]
    raw["status"] = !raw["valid"] ? "invalid_measurement" : raw["passed"] ? "passed" : "failed"
    raw["axis"] = spec.axes[column]
    raw["quality"] = half_quality
    raw["frequencies"] = step_spec.frequencies
    record["raw_step_refinement"] = raw
    write_table(joinpath(output, "comparison_half_step.tsv"),
        refinement_rows(step_spec.frequencies, half, main[:,:,indices]; limit = 0.01, valid = raw["valid"]))
    if !residual_step_eligible(spec.id, net)
        record["step_refinement"] = raw
        return raw
    end
    termination = exported_termination(net, model.project_path)
    termination == exported_termination(net, step_model.project_path) || error("step termination changed")
    predicted = discrete_response_column(net, spec, column, termination)
    predicted_half = discrete_response_column(net, step_spec, column, termination)
    reproduction = matrix_change(main, predicted; epsilon = 0.01)
    half_reproduction = matrix_change(half, predicted_half; epsilon = 0.01)
    readout_valid = !isempty(checks) && all(check["passed"] for check in checks)
    valid = raw["valid"] && readout_valid && reproduction["passed"] && half_reproduction["passed"]
    residual = residual_step_change(main[:,:,indices], half, predicted[:,:,indices], predicted_half; valid)
    residual["axis"] = spec.axes[column]
    residual["frequencies"] = step_spec.frequencies
    residual["quality"] = half_quality
    residual["main_reproduction"] = reproduction
    residual["half_reproduction"] = half_reproduction
    residual["readout_checks"] = checks
    residual["termination"] = Dict("grid_R_ohm" => termination.resistance,
        "grid_L_H" => termination.inductance,
        "dc_load" => termination.dc_resistance === nothing ? "clamped" : "resistive",
        "dc_resistance_ohm" => something(termination.dc_resistance, 0.0))
    residual["reference"] = "gamma_h diag(Ibase/Vbase,Ibase/Vbase,1,1) [v_h;i_h]; exact one-step DUT + exported termination"
    residual["rule"] = "dR=(M_half-P_half)-(M_h-P_h); norm(dR)/max(norm(M_h),0.1) and abs(dR)/max(abs(M_h),0.02) <= 0.01"
    residual["diagnostic_normalisation"] = "residual_normalised_* use M_h-P_h denominators; diagnostic only, never gating"
    rows = NamedTuple[]
    for (k, frequency) in enumerate(step_spec.frequencies)
        j = indices[k]
        a, b = main[:,:,j:j], half[:,:,k:k]
        p, q = predicted[:,:,j:j], predicted_half[:,:,k:k]
        raw_row = matrix_change(b, a; epsilon = 0.01)
        residual_row = residual_step_change(a, b, p, q; valid)
        reproduction_row = matrix_change(a, p; epsilon = 0.01)
        half_row = matrix_change(b, q; epsilon = 0.01)
        push!(rows, (frequency_Hz = frequency, raw_F = raw_row["frobenius_change"],
            raw_entry = raw_row["entry_change"], residual_F = residual_row["frobenius_change"],
            residual_entry = residual_row["entry_change"],
            residual_normalised_frobenius = residual_row["residual_normalised_frobenius"],
            residual_normalised_entry = residual_row["residual_normalised_entry"],
            main_reproduction_F = reproduction_row["frobenius_change"],
            main_reproduction_entry = reproduction_row["entry_change"],
            half_reproduction_F = half_row["frobenius_change"], half_reproduction_entry = half_row["entry_change"],
            valid, passed = residual_row["passed"]))
    end
    residual["per_frequency"] = [Dict(string(k) => v for (k,v) in pairs(row)) for row in rows]
    write_table(joinpath(output, "comparison_residual_step.tsv"), rows)
    # Retain complex columns so the residual can be independently reconstructed.
    columns = [(step = label, frequency_Hz = f, row = r,
        measured_real = real(m[r,1,k]), measured_imag = imag(m[r,1,k]),
        predicted_real = real(p[r,1,k]), predicted_imag = imag(p[r,1,k]))
        for (label, fs, m, p) in (("main", spec.frequencies, main, predicted),
            ("half", step_spec.frequencies, half, predicted_half))
        for (k,f) in enumerate(fs) for r in axes(m,1)]
    write_table(joinpath(output, "residual_columns.tsv"), columns)
    record["residual_step_refinement"] = residual
    record["step_refinement"] = residual
    return residual
end

function qualify_fixture!(record; residual = false)
    quality = record["tier_c_result"]
    comparison = residual ? record["interface_step_result"] : quality
    amp, step = record["amplitude_refinement"], record["step_refinement"]
    valid = quality["valid"] && get(amp, "valid", false) && get(step, "valid", false)
    qualified = valid && amp["passed"] && step["passed"]
    record["qualification_status"] = !valid ? "invalid_measurement" : qualified ? "passed" : "failed"
    record["status"] = !isempty(quality["model_mismatch"]) ? "model_mismatch" :
        !valid ? "invalid_measurement" :
        record["tier_a_status"] == "passed" && comparison["status"] == "passed" && qualified ? "passed" : "failed"
    record["comparison_summary"] = Dict{String, Any}("plain_model" => quality["status"],
        "one_step_realization" => get(get(record, "interface_step_result", Dict()), "status", "not_applicable"),
        "raw_step" => get(get(record, "raw_step_refinement", step), "status", step["passed"] ? "passed" : "failed"),
        "residual_step" => get(get(record, "residual_step_refinement", Dict()), "status", "not_applicable"),
        "qualification_reference" => residual ? "discrete_realization" : "plain_model",
        "qualification" => record["qualification_status"], "fixture" => record["status"])
    record["comparison_summary"]["plain_max_frobenius_error"] = get(quality, "max_frobenius_error", NaN)
    record["comparison_summary"]["one_step_max_frobenius_error"] =
        get(get(record, "interface_step_result", Dict()), "max_frobenius_error", NaN)
    return record
end

# Completion verification is strictly local. In particular, explicit native
# resume is not used because it also identifies the currently connected solver.
function m9c12_stored_axis(record, key, list, spec, directory, inputs)
    run = last(filter(r -> r["axis"] == key, record["run_records"]))
    root = joinpath(directory, run["path"], run["native_run_directory"])
    complete_path = joinpath(root, "complete.toml")
    complete = TOML.parsefile(complete_path)
    request = TOML.parsefile(joinpath(root, "computation.toml"))
    complete["schema_version"] == 1 || error("unsupported native completion schema")
    P._pscad_digest(request) == complete["request_sha256"] || error("native request changed")
    numerical = copy(request)
    pop!(numerical, "expected_solver", nothing)
    P._pscad_digest(numerical) == complete["input_sha256"] || error("native inputs changed")
    expected_settings = P._settings_record(scan_settings(spec))
    # Validate through the existing numeric readback contract, which permits
    # only its fixed floating round-off budget (not new scan settings).
    settings_check = Dict(k => Dict("requested" => v, "observed" => v)
        for (k,v) in P._project_parameters(request["settings"]))
    P._verify_settings_readback(settings_check, expected_settings)
    request["project_sha256"] == run["project_sha256"] || error("native project identity differs")
    for (name, hash) in complete["outputs"]
        basename(name) == name || error("invalid native output path")
        path = joinpath(root, "outputs", name)
        digest(path) == hash || error("native output changed: $name")
        push!(inputs, Dict("path" => abspath(path), "sha256" => hash))
    end
    readback = TOML.parsefile(joinpath(root, "outputs", "settings-readback.toml"))
    P._verify_settings_readback(readback, request["settings"])
    push!(inputs, Dict("path" => abspath(complete_path), "sha256" => digest(complete_path)))
    model, result = stored_axis(record, key, list, spec, directory)
    push!(inputs, Dict("path" => abspath(model.project_path), "sha256" => digest(model.project_path)))
    println("Read stored ", record["fixture_id"], " ", key)
    flush(stdout)
    return model, result
end

"""
    reanalyse_m9c12(ids; data_root, output_root=joinpath(ROOT, "data", "m9c12"))

Re-evaluate completed L2-07..12 native evidence locally. Read `data_root/<id>`;
write analysis only below this worktree's `data/m9c12` or `/tmp`. Native runs and
source manifests are never changed. Record the analysing revision and file hashes.
"""
function reanalyse_m9c12(ids; data_root, output_root = joinpath(ROOT, "data", "m9c12"))
    selected = ids isa AbstractString ? [ids] : collect(ids)
    !isempty(selected) && all(in(M9C12_IDS), selected) || error("M9c12 requires L2-07..12")
    destination = abspath(output_root)
    ancestor = destination
    while !ispath(ancestor)
        ancestor = dirname(ancestor)
    end
    resolved = normpath(joinpath(realpath(ancestor), relpath(destination, ancestor)))
    allowed = (joinpath(realpath(ROOT), "data", "m9c12"), realpath("/tmp"))
    any(root -> resolved == root || startswith(resolved, root * "/"), allowed) ||
        error("analysis output must be under worktree data/m9c12 or /tmp")
    outcomes = Dict{String, Any}()
    for id in selected
        directory = abspath(joinpath(data_root, id))
        output = joinpath(destination, id)
        startswith(output * "/", directory * "/") && error("output overlaps native evidence")
        source_manifest = joinpath(directory, "manifest.toml")
        source_hash = digest(source_manifest)
        original = TOML.parsefile(source_manifest)
        original["fixture_id"] == id || error("stored fixture identity differs")
        record = deepcopy(original)
        record["native_evidence_directory"] = directory
        mkpath(output)
        record["analysis_revision"] = Dict("purpose" => "M9c12 residual step witness",
            "commit" => readchomp(`git -C $REPOSITORY rev-parse HEAD`),
            "julia_version" => string(VERSION), "source_files" => source_record(),
            "environment_project_sha256" => digest(Base.active_project()),
            "environment_manifest_sha256" => digest(joinpath(dirname(Base.active_project()), "Manifest.toml")),
            "source_manifest" => source_manifest, "source_manifest_sha256" => source_hash)
        inputs = Dict{String, String}[]
        record["analysis_inputs"] = inputs
        net = fixture(id).factory()
        list = fixture_netlist(net, power_flow(net))
        residual_step_eligible(id, net) || error("fixture no longer has zero modulation delay")
        spec, reference = applicable_scan(id, net, list; definition = record["tier_c"])
        frozen = read_response(joinpath(directory, reference_filename(spec)), length(spec.axes), spec.frequencies)
        check = native_reference_check(spec, reference, frozen)
        check["passed"] || error("plain reference changed beyond identity budget")
        check["operating_point"] = native_operating_point_check(list, joinpath(directory, "operating_point.tsv"))
        check["operating_point"]["passed"] || error("stored operating point differs")
        record["analysis_native_reference_check"] = check
        models, results = Dict{String, P.PSCADModel}(), Dict{String, P.PSCADResult}()
        for key in ["baseline"; spec.axes]
            models[key], results[key] = m9c12_stored_axis(record, scan_prefix(spec)*key, list, spec, directory, inputs)
        end
        rows_a = compare_operating_point(results["baseline"], models["baseline"])
        write_table(joinpath(output, "comparison_A.tsv"), rows_a)
        record["tier_a_status"] = all(rows_a.within_tolerance) ? "passed" : "failed"
        record["tier_c_result"] = compare_frequency_runs(results, models, frozen, output; spec)
        record_interface_comparison!(record, net, spec, directory, output)
        axis = record["step_witness_definition"]["axis"]
        column = only(findall(==(axis), spec.axes))
        main, main_quality = single_response(results[axis], results["baseline"], models[axis], spec, column)
        checks = [readout_evidence(results[key], results["baseline"], models[key], spec, index)
                  for (index,key) in enumerate(spec.axes)]
        half_spec = merge(spec, (; tone_peak_pu = spec.tone_peak_pu / 2))
        half_key = scan_prefix(spec) * "half_amplitude_" * axis
        half_model, half_result = m9c12_stored_axis(record, half_key, list, half_spec, directory, inputs)
        half, half_quality = single_response(half_result, results["baseline"], half_model, half_spec, column)
        amp = matrix_change(half, main; epsilon = 0.02)
        amp["valid"] = main_quality["valid"] && half_quality["valid"]
        amp["passed"] &= amp["valid"]
        record["amplitude_refinement"] = merge(amp, Dict("axis" => axis, "quality" => half_quality))
        write_table(joinpath(output, "comparison_half_amplitude.tsv"),
            refinement_rows(spec.frequencies, half, main; limit = 0.02, valid = amp["valid"]))
        push!(checks, readout_evidence(half_result, results["baseline"], half_model, half_spec, column; axis = half_key))
        half_model = half_result = nothing
        GC.gc()
        step_spec = step_definition(spec, first(record["step_witness_definition"]["frequencies"]))
        scan_record(step_spec) == Dict(k => record["step_witness_definition"][k] for k in keys(scan_record(step_spec))) ||
            error("stored step definition differs")
        step_model, step_baseline = m9c12_stored_axis(record, step_prefix(step_spec)*"baseline", list, step_spec, directory, inputs)
        step_model, step_result = m9c12_stored_axis(record, step_prefix(step_spec)*axis, list, step_spec, directory, inputs)
        half, half_quality = single_response(step_result, step_baseline, step_model, step_spec, column)
        push!(checks, readout_evidence(step_result, step_baseline, step_model, step_spec, column;
            axis = step_prefix(step_spec)*axis))
        record_step_witness!(record, net, spec, step_spec, column, main, half,
            main_quality, half_quality, models[axis], step_model, checks, output)
        qualify_fixture!(record; residual = true)
        digest(source_manifest) == source_hash || error("source manifest changed during analysis")
        # Original run paths resolve against native_evidence_directory; the
        # output inventory contains only newly written analysis files.
        record["native_runs_unchanged"] = true
        write_manifest(output, record)
        outcomes[id] = record
        println(id, ": ", record["comparison_summary"])
        flush(stdout)
        GC.gc()
    end
    write_table(joinpath(destination, "summary.tsv"), [
        (fixture = id, status = outcomes[id]["status"], plain = outcomes[id]["tier_c_result"]["status"],
            one_step = outcomes[id]["interface_step_result"]["status"],
            plain_F = outcomes[id]["tier_c_result"]["max_frobenius_error"],
            one_step_F = outcomes[id]["interface_step_result"]["max_frobenius_error"],
            raw_F = outcomes[id]["raw_step_refinement"]["frobenius_change"],
            raw_entry = outcomes[id]["raw_step_refinement"]["entry_change"],
            residual_F = outcomes[id]["residual_step_refinement"]["frobenius_change"],
            residual_entry = outcomes[id]["residual_step_refinement"]["entry_change"],
            residual_normalised_frobenius = outcomes[id]["residual_step_refinement"]["residual_normalised_frobenius"],
            residual_normalised_entry = outcomes[id]["residual_step_refinement"]["residual_normalised_entry"],
            raw_step = outcomes[id]["raw_step_refinement"]["status"],
            residual_step = outcomes[id]["residual_step_refinement"]["status"],
            main_reproduction_F = outcomes[id]["residual_step_refinement"]["main_reproduction"]["frobenius_change"],
            main_reproduction_entry = outcomes[id]["residual_step_refinement"]["main_reproduction"]["entry_change"],
            kcl_max_relative_error = maximum(check["max_relative_error"]
                for check in outcomes[id]["residual_step_refinement"]["readout_checks"]))
        for id in selected])
    return outcomes
end

# Full dq transport for a matrix identified from all measured drive coordinates.
function injection_readout_transport(frequency,spec)
    angle=2π*spec.frequency*spec.time_step
    return exp(im*2π*frequency*spec.time_step).*[cos(angle) sin(angle);-sin(angle) cos(angle)]
end
