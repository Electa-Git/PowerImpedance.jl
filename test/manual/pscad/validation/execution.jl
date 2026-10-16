function prepare_fixture(id; directory = joinpath(ROOT, "data", id), definition = nothing)
    startswith(id, "L3-") && return prepare_composed(id; directory)
    P._require_extension()
    entry = fixture(id)
    mkpath(directory)
    path = joinpath(directory, "manifest.toml")
    prior = isfile(path) ? manifest_lists!(TOML.parsefile(path)) : nothing
    if prior !== nothing
        prior["fixture_id"] == id || error("fixture mismatch")
        for file in prior["files"]
            kept = joinpath(directory, file["path"])
            isfile(kept) && filesize(kept) == file["bytes"] &&
            digest(kept) == file["sha256"] || error("kept artifact changed: $kept")
        end
    end
    net = entry.factory()
    point = power_flow(net)
    gate = stability_gate(net, entry)
    gate["status"] == "passed" || error("$(entry.id) failed complete-network stability gate: $gate")
    list = fixture_netlist(net, point)
    spec, reference = applicable_scan(id, net, list;
        definition = prior === nothing ? definition : prior["tier_c"])
    check_recorder_sampling(spec)
    if prior !== nothing
        history = mkpath(joinpath(directory, "history"))
        cp(path,
            joinpath(history, "manifest-before-m9a4-" *
                              Dates.format(now(UTC), "yyyymmddTHHMMSS") * ".toml"))
    end
    spec.travel_lower_bound_s == 0 || spec.time_step < spec.travel_lower_bound_s ||
        error("step exceeds conservative travel bound")
    models = prepare_scan_projects(directory, list, spec, spec.axes; prefix = scan_prefix(spec))
    append!(models,
        prepare_scan_projects(
            directory, list, merge(spec, (tone_peak_pu = spec.tone_peak_pu/2,)),
            spec.axes; prefix = scan_prefix(spec) * "half_amplitude_"))
    candidate_step = step_definition(spec, 1000.0)
    append!(models,
        prepare_scan_projects(directory, list, candidate_step, spec.axes;
            prefix = step_prefix(candidate_step)))
    reference_path = joinpath(directory, reference_filename(spec))
    if isfile(reference_path)
        stored = read_response(reference_path, length(spec.axes), spec.frequencies)
        native_reference_check(spec,reference,stored)["passed"] ||
            error("prepared native reference changed beyond solver-scale guard")
    else
        write_response(reference_path, reference, spec.frequencies; quantity = spec.quantity)
    end
    point_path = joinpath(directory, "operating_point.tsv")
    isfile(point_path) || write_operating_point(point_path, first(models).second)
    if prior === nothing
        environment = mkpath(joinpath(directory, "environment"))
        cp(Base.active_project(), joinpath(environment, "Project.toml"))
        active_manifest=joinpath(dirname(Base.active_project()), "Manifest.toml")
        isfile(active_manifest) &&
            cp(active_manifest, joinpath(environment, "Manifest.toml"))
        record = preparation_record(entry, gate, models; directory)
    else
        record = prior
        get!(record, "preparation_source_files", deepcopy(record["source_files"]))
        push!(record["harness_revisions"],
            Dict("purpose"=>"M9a4 phase-domain physics and DC settling",
                "previous_source_files"=>record["source_files"]))
        record["source_files"] = source_record()
        for (axis, model) in models
            record_project!(record, axis, model, directory)
        end
    end
    if get(get(record, "tier_c", Dict()), "protocol", "") != spec.protocol && !isempty(spec.protocol)
        record["previous_tier_c"] = deepcopy(get(record, "tier_c", Dict()))
        record["previous_tier_c_result"] = deepcopy(get(record, "tier_c_result", Dict()))
        for field in ("step_witness_definition", "tier_c_result", "amplitude_refinement", "step_refinement")
            haskey(record, field) && (record["previous_" * field] = pop!(record, field))
        end
    end
    record["tier_c"] = merge(get(record, "tier_c", Dict{String, Any}()), scan_record(spec))
    if spec.dimension == 3
        record["dq_approximation_table"] = [dq_approximation(id, net, list, directory)]
        record["phase_reference_provenance"] = id == "L1-08" ?
            "transformation=false twin: identical copied physical models and replayed a/b/c terminal bus incidence; native make_z ideal-source equations; local Bus1/Bus5 3x3 blocks" :
            "native eval_abcd(element.element_model,s), then abcd_to_y; into-element terminal currents; a/b/c phase order"
    elseif id == "L1-05"
        record["settling"] = Dict("observed_envelope_time_constant_s"=>1/2.1,
            "tail_fit_interval_s"=>[0.6, 3.0], "decay_per_s"=>2.1,
            "oscillation_rad_per_s"=>0.8, "current_fit_rms_kA"=>4.601940024186259e-5,
            "fit_form"=>"Iinf + exp(-alpha*t)*(c*cos(beta*t)+d*sin(beta*t)); 10 ms decimation",
            "fit_current_asymptote_kA"=>0.86126018,
            "chosen_windows_s"=>[6.0, 7.0], "window_duration_s"=>1.0,
            "duration_s"=>8.0, "predicted_drift"=>9.27e-7,
            "acceptance"=>"prediction sizes run only; actual drift <=1e-3 remains mandatory; DC fits unchanged")
    end
    record_native_reference!(record,directory,spec,reference,
        read_response(reference_path,length(spec.axes),spec.frequencies),list; purpose="preparation verification")
    interface_reference = interface_step_reference(net, spec)
    if interface_reference !== nothing
        write_response(joinpath(directory, "interface_step_reference.tsv"), interface_reference, spec.frequencies; quantity = "Y")
        record["interface_step_comparison"] = Dict("label" => "Julia + one inherent interface step",
            "step_s" => spec.time_step, "reference_file" => "interface_step_reference.tsv",
            "status" => "station_pending", "policy" => "separate realization comparison; plain model and refinement statuses retained")
    end
    record["estimated_live_nodes"] = entry.estimated_nodes + 2length(P._dc_precharge_buses(list))
    record["estimated_live_nodes"] < 100 || error("prepared fixture exceeds live-node limit")
    record["stability"] = gate
    record["tiers"] = ["A", "C"]
    if isempty(spec.protocol) && get(get(record, "corrected_analysis", Dict()), "status", "") == "passed"
        record["qualification_status"] = "passed"
        record["status"] = "passed"
        record["accepted_evidence"] = "retained station runs with matching project hashes, recorded orientations, corrected comparison and passing refinements"
    else
        record["qualification_status"] = "refinement pending"
        record["status"] = "prepared_station_pending"
    end
    write_manifest(directory, record)
    return models
end

function probe_samples(result, probe)
    probe.dim == 3 || error("expected an abc probe")
    return hcat((result.channels[probe.name * ":" * string(phase)] for phase in 1:3)...)
end

function branch_samples(result, model)
    current = only(filter(
        c -> c.kind == :current && c.element == "branch" && c.side == "1",
        model.probes.channels))
    voltage = only(filter(c -> c.kind == :voltage && c.bus == current.bus, model.probes.channels))
    other_current = only(filter(
        c -> c.kind == :current && c.element == "branch" && c.side == "2",
        model.probes.channels))
    other_voltage = only(filter(c -> c.kind == :voltage && c.bus == other_current.bus, model.probes.channels))
    return (voltage = fixed_dq(result.time, probe_samples(result, voltage)),
        current = fixed_dq(result.time, probe_samples(result, current)),
        clamped_voltage = fixed_dq(result.time, probe_samples(result, other_voltage)))
end

function compare_frequency_runs(results, models, reference, directory; spec = nothing)
    if spec === nothing
        spec, _ = scan_definition("L1-01", ac_rl_network(), models["baseline"].netlist)
    end
    baseline = scan_samples(results["baseline"], models["baseline"], spec)
    all(results[axis].time == results["baseline"].time for axis in spec.axes) ||
        error("sample times differ")
    injected = [scan_samples(results[axis], models[axis], spec) for axis in spec.axes]
    extracted = extract_response(results["baseline"].time, [run.input for run in injected],
        [run.output for run in injected], baseline.input, baseline.output, spec.frequencies;
        starts = spec.window_starts, duration = spec.window_duration, input_bases = baseline.input_base)
    normalized = [scale_response(matrix, spec) for matrix in extracted.matrices]
    measured = sum(extracted.matrices) / length(extracted.matrices)
    change = matrix_change(normalized[2], normalized[1]; epsilon = 0.01)
    quality = scan_quality(results["baseline"].time, baseline, injected, spec)
    quality["valid"] &= change["passed"]
    if spec.id == "L1-01"
        held = branch_samples(results["baseline"], models["baseline"]).clamped_voltage
        departure = maximum(maximum(abs, branch_samples(results[axis], models[axis]).clamped_voltage -
                                         held) for axis in spec.axes) /
                    spec.voltage_bases[1]
        quality["clamped_voltage_departure_pu"] = max(quality["clamped_voltage_departure_pu"], departure)
        quality["valid"] &= departure <= 1e-6
    end
    coupling = sideband_coupling(results["baseline"].time, baseline, injected, spec)
    mismatch = coupling > C_PASSIVE.epsilon ?
               "phase-domain frequency coupling absent from native fixed-dq LTI reference" :
               ""
    rows = response_rows(spec, scale_response(measured, spec),
        scale_response(reference, spec); active = get(spec,:active,false), valid = quality["valid"], model_mismatch = mismatch)
    write_table(joinpath(directory, "comparison_C.tsv"), rows)
    write_response(
        joinpath(directory, spec.quantity == "Y" ? "measured_S.tsv" : "measured_ohm.tsv"),
        measured, spec.frequencies; quantity = spec.quantity)
    worst = argmax([row.complex_error_pu /
                    max(abs(complex(row.reference_real_pu, row.reference_imag_pu)), 0.02)
                    for row in rows])
    quality["omitted_sideband_ratio"] = coupling
    quality["model_mismatch"] = coupling > C_PASSIVE.epsilon ?
                                "phase-domain frequency coupling absent from native fixed-dq LTI reference" :
                                ""
    quality["status"] = !isempty(quality["model_mismatch"]) ? "model_mismatch" :
                        !quality["valid"] ? "invalid_measurement" :
                        all(row.within_tolerance for row in rows) ? "passed" : "failed"
    quality["window_change"] = change["frobenius_change"]
    quality["window_entry_change"] = change["entry_change"]
    window_worst = argmax(abs.(normalized[2] - normalized[1]) ./ max.(abs.(normalized[1]), 0.02))
    quality["window_worst_frequency_Hz"] = spec.frequencies[window_worst[3]]
    quality["window_worst_row"] = window_worst[1]
    quality["window_worst_column"] = window_worst[2]
    write_table(joinpath(directory, "comparison_windows.tsv"),
        refinement_rows(spec.frequencies, normalized[2], normalized[1]; limit = 0.01, valid = true))
    quality["max_input_condition"] = maximum(extracted.conditions)
    quality["max_frobenius_error"] = maximum(row.frobenius_error for row in rows)
    quality["worst_column"] = rows[worst].column
    quality["worst_frequency_Hz"] = rows[worst].frequency_Hz
    return quality
end

function budget_remote(remote, seconds)
    return P.RemoteConfig(remote.host, remote.shared_root, remote.remote_root,
        remote.julia_executable, remote.python_executable; local_root = remote.local_root,
        pscad_version = remote.pscad_version, pscad_port = remote.pscad_port,
        transport = remote.transport, command = remote.command, timeout = min(remote.timeout, seconds))
end

# The copied native completion record remains authoritative even if the harness
# crashed before adding a run_records entry. Native compute owns integrity checks.
function completed_axis_runs(directory, axis, project_sha256)
    runs = joinpath(directory, "runs")
    isdir(runs) || return String[]
    candidates = String[]
    for work_root in readdir(runs; join = true)
        isdir(work_root) && startswith(basename(work_root), axis * "-") || continue
        for root in readdir(work_root; join = true)
            isdir(root) && startswith(basename(root), "run-") &&
            isfile(joinpath(root, "complete.toml")) &&
            isfile(joinpath(root, "computation.toml")) &&
            isfile(joinpath(root, "generated.pscx")) || continue
            stored = try
                TOML.parsefile(joinpath(root, "computation.toml"))
            catch failure
                failure isa TOML.ParserError || rethrow()
                @warn "Invalid retained computation record" run_directory = root
                continue
            end
            get(stored, "project_sha256", nothing) == project_sha256 || continue
            push!(candidates, root)
        end
    end
    return sort!(candidates; by = root -> mtime(joinpath(root, "complete.toml")), rev = true)
end

function resume_axis(model, axis, directory, remote)
    for root in completed_axis_runs(directory, axis, digest(model.project_path))
        result = try
            compute(model, PSCADRun(); options = (
                remote, resume_run_directory = root, verbosity = 1))
        catch failure
            # Explicit resume never launches a new run. Reject damaged retained
            # data; transport failures and interrupts must still stop the runner.
            (failure isa ArgumentError || failure isa TOML.ParserError ||
             (failure isa ErrorException &&
              startswith(failure.msg, "PSCAD result validation failed:"))) || rethrow()
            @warn "Retained axis run cannot be resumed" axis run_directory=root reason=sprint(
                showerror, failure)
            continue
        end
        result.diagnostics.reused || error("explicit resume unexpectedly executed an axis")
        return result
    end
    return nothing
end

# Decode the channels recorded for this exact project hash, rather than using
# the current emitter's convention for a historical native output.
function stored_axis(record, key, list, spec, directory)
    run = last(filter(r -> r["axis"] == key, record["run_records"]))
    root = joinpath(directory, run["path"], run["native_run_directory"])
    project = joinpath(root, "generated.pscx")
    digest(project) == run["project_sha256"] || error("stored run project hash differs")
    plan, settings = scan_plan(list, spec, "baseline")
    probes = recorded_probes(run["probes"], plan.probes.reference_bus)
    model = P.PSCADModel(project, plan.name, list, probes, settings,
        list.operating_point, (source = :stored_station_run,))
    parsed = P.read_pscad_output(joinpath(root, "outputs"); stem = settings.output_stem)
    result = P.PSCADResult(PSCADRun(), parsed.time, parsed.channels, probes, settings,
        (stored_project_sha256 = run["project_sha256"],), (run_directory = root,))
    return model, result
end

function reanalyse_fixture(id; directory = joinpath(ROOT, "data", id))
    record = manifest_lists!(TOML.parsefile(joinpath(directory, "manifest.toml")))
    net = fixture(id).factory()
    list = P.netlist(net, power_flow(net))
    spec, _ = scan_definition(id, net, list)
    reference = read_response(joinpath(directory, "reference.tsv"), length(spec.axes), spec.frequencies)
    models, results = Dict{String, P.PSCADModel}(), Dict{String, P.PSCADResult}()
    for key in ["baseline"; spec.axes]
        models[key], results[key] = stored_axis(record, key, list, spec, directory)
    end
    output = mkpath(joinpath(directory, "analysis", "probe-orientation"))
    rows = compare_operating_point(results["baseline"], models["baseline"])
    write_table(joinpath(output, "comparison_A.tsv"), rows)
    # Signed and magnitude acceptance rows are evaluated from unchanged raw
    # channels; orientation metadata is used only by the Y/Z extraction.
    read(joinpath(output, "comparison_A.tsv"), String) ==
    read(joinpath(directory, "comparison_A.tsv"), String) || error("tier A rows changed")
    result = compare_frequency_runs(results, models, reference, output; spec)
    qualified = record["amplitude_refinement"]["passed"] && record["step_refinement"]["passed"]
    # Applying the same diagonal +/-1 row matrix to both witness matrices
    # preserves entry differences and Frobenius norms exactly. Existing witness
    # gates and quality metrics therefore retain their measured values.
    status = result["status"] == "model_mismatch" ? "model_mismatch" :
             all(rows.within_tolerance) && result["status"] == "passed" && qualified ? "passed" : "failed"
    record["corrected_analysis"] = Dict("status"=>status, "tier_c_result"=>result,
        "directory"=>relpath(output, directory), "tier_a_rows_unchanged"=>true,
        "witness_gates_unchanged"=>true,
        "provenance"=>"raw station outputs; saved project hash and recorded probe orientations")
    record["source_files"] = source_record()
    write_manifest(directory, record)
    println(id, ": stored-run status=", status, " max_F=", result["max_frobenius_error"])
    return record["corrected_analysis"]
end

# Change only Julia's evaluation of a retained measurement; the native project,
# probes, drive, bases and refinement comparisons remain the recorded ones.
function refresh_references(id; directory = joinpath(ROOT, "data", id))
    id in ("L1-04", "L1-05") || error("reference refresh is restricted to the corrected cable fixtures")
    record = manifest_lists!(TOML.parsefile(joinpath(directory, "manifest.toml")))
    stamp = Dates.format(now(UTC), "yyyymmddTHHMMSS")
    history = mkpath(joinpath(directory, "history", "m9a11-" * stamp))
    for file in ("manifest.toml", "operating_point.tsv", reference_filename((; protocol=record["tier_c"]["protocol"])))
        cp(joinpath(directory,file),joinpath(history,file))
    end
    analysis = joinpath(directory,"analysis", isempty(record["tier_c"]["protocol"]) ? "dq" : record["tier_c"]["protocol"])
    measured_path = joinpath(analysis, "measured_S.tsv")
    saved = only(filter(f -> f["path"] == relpath(measured_path, directory), record["files"]))
    digest(measured_path) == saved["sha256"] || error("retained measured matrix changed")
    cp(analysis,joinpath(history,"analysis"))
    projects = Dict(p["path"]=>p["sha256"] for p in record["projects"])
    all(digest(joinpath(directory,path))==hash for (path,hash) in projects) || error("project hash changed")
    net = fixture(id).factory(); list = P.netlist(net,power_flow(net))
    spec, reference = applicable_scan(id,net,list;definition=record["tier_c"])
    model, result = stored_axis(record,scan_prefix(spec)*"baseline",list,spec,directory)
    rows_a = compare_operating_point(result,model)
    write_table(joinpath(analysis,"comparison_A.tsv"),rows_a)
    write_operating_point(joinpath(directory,"operating_point.tsv"),model)
    write_response(joinpath(directory,reference_filename(spec)),reference,spec.frequencies;quantity=spec.quantity)
    measured = read_response(measured_path,length(spec.axes),spec.frequencies)
    quality = deepcopy(record["tier_c_result"])
    rows = response_rows(spec,scale_response(measured,spec),scale_response(reference,spec);
        valid=quality["valid"],model_mismatch=quality["model_mismatch"])
    write_table(joinpath(analysis,"comparison_C.tsv"),rows)
    quality["max_frobenius_error"] = maximum(r.frobenius_error for r in rows)
    quality["status"] = !isempty(quality["model_mismatch"]) ? "model_mismatch" :
        !quality["valid"] ? "invalid_measurement" : all(r.within_tolerance for r in rows) ? "passed" : "failed"
    worst = argmax([r.complex_error_pu/max(abs(complex(r.reference_real_pu,r.reference_imag_pu)),.02) for r in rows])
    quality["worst_column"] = rows[worst].column; quality["worst_frequency_Hz"] = rows[worst].frequency_Hz
    record["tier_a_status"] = all(rows_a.within_tolerance) ? "passed" : "failed"
    record["tier_c_result"] = quality
    qualified = record["amplitude_refinement"]["passed"] && record["step_refinement"]["passed"]
    record["status"] = record["tier_a_status"]==quality["status"]=="passed" && qualified ? "passed" : "failed"
    push!(record["harness_revisions"],Dict("purpose"=>"M9a11 corrected cable Julia references only",
        "history"=>relpath(history,directory),"reference_commit"=>readchomp(`git -C $REPOSITORY rev-parse HEAD`),
        "old_source_files"=>record["source_files"],"projects_unchanged"=>true,
        "measurement"=>"retained extracted SI matrices and original quality gates; baseline raw output for tier A",
        "refinements"=>"reference-independent measured half-amplitude and half-step gates retained"))
    record["source_files"] = source_record()
    record["corrected_analysis"] = Dict("status"=>record["status"],"tier_c_result"=>quality)
    all(digest(joinpath(directory,path))==hash for (path,hash) in projects) || error("project hash changed")
    write_manifest(directory,record)
    println(id,": A=",record["tier_a_status"]," C=",quality["status"]," max_F=",quality["max_frobenius_error"])
    return record
end
