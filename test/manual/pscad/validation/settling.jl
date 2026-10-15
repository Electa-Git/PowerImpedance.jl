function gfl_settling(gate; tone_peak_pu = 5e-5)
    decay = -gate["most_positive_located_real_per_s"]
    decay > 0 || error("settling requires stable complete-network modes")
    # Conservative 1 pu transient, divided by the single-tone drive and the
    # unchanged 0.02 entry floor. Target 0.1%, tenfold below the 1% window gate.
    target = 0.001
    decay_times = log(1 / (tone_peak_pu * 0.02 * target))
    start = ceil(max(16.0, 0.2 + decay_times/decay, 2.0 + decay_times/decay))
    return Dict("decay_per_s" => decay, "decay_times" => decay_times,
        "assumed_initial_transient_pu" => 1.0, "prediction_target" => target,
        "entry_floor_pu" => 0.02, "tone_peak_pu" => tone_peak_pu,
        "window_starts_s" => [start, start + 1.0], "window_duration_s" => 1.0,
        "simulation_time_s" => start + 2.0,
        "predicted_normalized_tail" => exp(-decay*(start-2.0))/(tone_peak_pu*0.02),
        "scope" => "native pole envelope sizing; sampled/unmodelled modes and residues unbounded; actual unchanged gates mandatory")
end

const MMC_SETTLING_DIRECTORY = joinpath(ROOT, "data", "m9c7", "L2-07-settling")

# Rebuild the bounded experiment from its frozen design, retaining all old runs.
function prepare_settling_experiment()
    directory = MMC_SETTLING_DIRECTORY
    archive = joinpath(ROOT, "data", "archive", "m9c7", "L2-07-settling")
    ispath(archive) && error("archive already exists: $archive")
    prior = TOML.parsefile(joinpath(directory, "manifest.toml"))
    definition = deepcopy(prior["tier_c"])
    mkpath(dirname(archive))
    mv(directory, archive)
    mkpath(directory)
    net = fixture("L2-07").factory()
    list = fixture_netlist(net, power_flow(net))
    spec, reference = applicable_scan("L2-07", net, list; definition)
    models = prepare_scan_projects(directory, list, spec, ["p1_d"]; prefix = scan_prefix(spec))
    record = preparation_record(fixture("L2-07"), prior["stability"], models; directory)
    record["tier_c"] = scan_record(spec)
    record["status"] = "diagnostic_prepared"
    record["experiment"] = prior["experiment"]
    record["archive_directory"] = relpath(archive, ROOT)
    write_response(joinpath(directory, reference_filename(spec)), reference, spec.frequencies)
    write_manifest(directory, record)
    return record
end

# Diagnostic only: one baseline and one d-axis drive. No Y identification or
# fixture qualification can be inferred from this single injected axis.
function run_settling_experiment(; remote, deadline)
    directory = MMC_SETTLING_DIRECTORY
    record = manifest_lists!(TOML.parsefile(joinpath(directory, "manifest.toml")))
    try
        verify_inputs(directory, record)
        net = fixture("L2-07").factory()
        list = fixture_netlist(net, power_flow(net))
        spec, _ = applicable_scan("L2-07", net, list; definition = record["tier_c"])
        results, models = Dict{String, P.PSCADResult}(), Dict{String, P.PSCADModel}()
        for axis in ("baseline", "p1_d")
            key = scan_prefix(spec) * axis
            model = existing_model(record, key, list, spec, directory)
            results[axis] = execute_axis!(record, key, model, directory, remote, deadline)
            models[axis] = model
        end
        baseline = scan_samples(results["baseline"], models["baseline"], spec)
        injected = scan_samples(results["p1_d"], models["p1_d"], spec)
        report = settling_window_changes(results["baseline"].time, baseline, injected, spec)
        record["settling_result"] = report
        record["status"] = "diagnostic_complete"
    catch failure
        failure isa InterruptException && rethrow()
        record["status"] = "run_or_analysis_failed"
        record["failure"] = sprint(showerror, failure)
        @warn "Settling experiment failed" error = record["failure"]
    finally
        write_manifest(directory, record)
    end
    return record
end

function settling_window_changes(times, baseline, injected, spec)
    output = Dict{String, Any}()
    for (label, starts, duration) in (("early", (8.0, 12.0, 16.0), 4.0),
            ("late", Tuple(spec.window_starts), spec.window_duration))
        responses = Array{ComplexF64, 3}[]
        for start in starts
            drive = dft_phasors(times, injected.drive - baseline.drive, spec.frequencies;
                start, duration)
            response = vcat(dft_phasors(times, injected.voltage - baseline.voltage,
                spec.frequencies; start, duration),
                dft_phasors(times, injected.current - baseline.current,
                    spec.frequencies; start, duration)) ./ drive[1:1, :]
            response .*= baseline.drive_base[1] ./ [baseline.input_base; baseline.output_base]
            push!(responses, reshape(response, size(response, 1), 1, :))
        end
        changes = [matrix_change(responses[k + 1], responses[k]; epsilon = 0.01) for k in 1:2]
        qualities = [scan_quality(times, baseline, [injected],
            merge(spec, (; window_starts = (starts[k], starts[k + 1]), window_duration = duration));
            columns = [1]) for k in 1:2]
        output[label] = Dict("window_starts_s" => collect(starts), "window_duration_s" => duration,
            "adjacent_changes" => changes, "qualities" => qualities,
            "valid" => all(c["passed"] for c in changes) && all(q["valid"] for q in qualities))
    end
    output["interpretation"] = "Compare early/late adjacent directional V/Idrive and I/Idrive changes; both late pairs must satisfy the unchanged 1% Frobenius AND entry rule. Persistence at 60 s bounds this experiment only; it does not prove an asymptotic limit cycle. One axis cannot identify a full admittance."
    return output
end
