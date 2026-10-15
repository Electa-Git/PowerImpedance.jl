const M9C2_IDS = ["L2-" * lpad(n, 2, '0') for n in 7:15]
const M9C2_TLC_DIRECTORY = joinpath(ROOT, "data", "L2-01-1p25us")

# Explicit local preparation only. Archive complete fixture trees, never reuse
# an old run or overwrite the retained 2.5 us TLC evidence.
function prepare_m9c2()
    archive = mkpath(joinpath(ROOT, "data", "archive", "m9c2"))
    for id in M9C2_IDS
        directory = joinpath(ROOT, "data", id)
        destination = joinpath(archive, id)
        ispath(destination) && error("archive already exists: $destination")
        prior = TOML.parsefile(joinpath(directory, "manifest.toml"))
        definition = deepcopy(prior["tier_c"])
        if id in ("L2-07", "L2-08", "L2-09", "L2-10")
            settling = gfl_settling(prior["stability"]; tone_peak_pu = definition["tone_peak_pu"])
            definition["window_starts"] = settling["window_starts_s"]
            definition["simulation_time"] = settling["simulation_time_s"]
            definition["estimated_station_seconds"] = 3300
            definition["settling"] = settling
        end
        mv(directory, destination)
        mkpath(directory)
        for file in ("dq_active_reference.tsv", "operating_point.tsv")
            cp(joinpath(destination, file), joinpath(directory, file))
        end
        models = prepare_fixture(id; directory, definition)
        record = TOML.parsefile(joinpath(directory, "manifest.toml"))
        old_reference = read_response(joinpath(destination, "dq_active_reference.tsv"),
            length(definition["axes"]), definition["frequencies"])
        new_reference = read_response(joinpath(directory, "dq_active_reference.tsv"),
            length(definition["axes"]), definition["frequencies"])
        preservation_spec = (; quantity = "Y", voltage_bases = definition["voltage_bases_kV"],
            current_bases = definition["current_bases_kA"], frequencies = definition["frequencies"])
        native_reference_check(preservation_spec, new_reference, old_reference)["passed"] ||
            error("native reference changed: $id")
        record["archive_directory"] = relpath(destination, ROOT)
        write_manifest(directory, record)
        isempty(record["run_records"]) || error("fresh preparation inherited runs")
    end
    ispath(M9C2_TLC_DIRECTORY) && error("fine-step TLC directory already exists")
    definition = deepcopy(TOML.parsefile(joinpath(ROOT, "data", "L2-01", "manifest.toml"))["tier_c"])
    definition["time_step"] = 1.25e-6
    definition["estimated_station_seconds"] = 2700
    mkpath(M9C2_TLC_DIRECTORY)
    for file in ("dq_active_reference.tsv", "operating_point.tsv")
        cp(joinpath(ROOT, "data", "L2-01", file), joinpath(M9C2_TLC_DIRECTORY, file))
    end
    prepare_fixture("L2-01"; directory = M9C2_TLC_DIRECTORY, definition)
    record = TOML.parsefile(joinpath(M9C2_TLC_DIRECTORY, "manifest.toml"))
    record["variant"] = "L2-01: 1.25 us base / 0.625 us witness; original 2.5 us evidence retained"
    write_manifest(M9C2_TLC_DIRECTORY, record)
    model, directory = prepare_timing()
    return (; archive, timing = directory, tlc = M9C2_TLC_DIRECTORY, fixtures = copy(M9C2_IDS))
end

# This function is called only by the owner's station command. An interrupted
# queue resumes matching completed runs through the existing native hash checks.
function run_m9c2(; remote = RemoteConfig(), timeout = 43200.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    deadline = time() + timeout
    run_timing(remote, deadline)
    run_fixture("L2-05"; remote, deadline)
    run_fixture("L2-01"; remote, directory = M9C2_TLC_DIRECTORY, deadline)
    for id in M9C2_IDS
        run_fixture(id; remote, deadline)
    end
    return nothing
end

# The acceptance script owns fresh exports and station runs. Keep its command
# separate from inclusion so loading the harness never contacts the station.
function converter_acceptance_command()
    project = Base.active_project()
    project === nothing && error("converter acceptance requires an active Julia project")
    script = joinpath(REPOSITORY, "test", "manual", "pscad", "acceptance.jl")
    return `$(Base.julia_cmd()) --project=$(dirname(project)) $script --converters`
end

# L2 resumes matching runs; acceptance always starts fresh after L2 completes.
# Its per-run timeouts belong to the station configuration, not the L2 deadline.
function run_m9c3(; timeout = 43200.0)
    run_m9c2(; timeout)
    run(converter_acceptance_command())
    return nothing
end

# The timing and TLC checks are already complete. This queue resumes only the
# fresh MMC measurements, then starts the converter acceptance with fresh runs.
function run_m9c6(; timeout = 43200.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    deadline = time() + timeout
    remote = RemoteConfig()
    for id in M9C2_IDS
        run_fixture(id; remote, deadline)
    end
    run(converter_acceptance_command())
    return nothing
end

# Catch fixture failures outside run_fixture's inner analysis try block too
# (input verification, reconstruction and stability can fail before that block).
function run_fixture_continuing(id; directory = joinpath(ROOT, "data", id),
        remote, deadline)
    try
        return run_fixture(id; directory, remote, deadline)
    catch failure
        failure isa InterruptException && rethrow()
        record = manifest_lists!(TOML.parsefile(joinpath(directory, "manifest.toml")))
        record["status"] = "run_or_analysis_failed"
        record["failure"] = sprint(showerror, failure)
        write_manifest(directory, record)
        @warn "Fixture failed; continuing queue" fixture = id error = record["failure"]
        return record
    end
end

# Acceptance is deliberately first; its own native runs remain fresh.
function run_m9c7(; timeout = 43200.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    acceptance_directory = mkpath(joinpath(ROOT, "data", "m9c7"))
    acceptance = Dict{String, Any}("status" => "completed")
    try
        run(converter_acceptance_command())
    catch failure
        failure isa InterruptException && rethrow()
        acceptance["status"] = "run_or_analysis_failed"
        acceptance["failure"] = sprint(showerror, failure)
        @warn "Converter acceptance failed; continuing queue" error = acceptance["failure"]
    end
    open(io -> TOML.print(io, acceptance), joinpath(acceptance_directory, "acceptance.toml"), "w")
    remote = RemoteConfig()
    deadline = time() + timeout
    for n in 11:15
        run_fixture_continuing("L2-" * lpad(n, 2, '0'); remote, deadline)
    end
    run_settling_experiment(; remote, deadline)
    return nothing
end

# Local preparation only; old station evidence is retained in complete trees.
function prepare_m9c8()
    machine = joinpath(ROOT, "data", "L2-16")
    archive = joinpath(ROOT, "data", "archive", "m9c8", "L2-16")
    timing = joinpath(ROOT, "data", "m9c8", "timing")
    ispath(archive) && error("archive already exists: $archive")
    ispath(timing) && error("timing witness already prepared: $timing")
    prior = TOML.parsefile(joinpath(machine, "manifest.toml"))
    prepare_settling_experiment()
    prepare_timing(timing)
    definition = deepcopy(prior["tier_c"])
    definition["time_step"] = 1.25e-6
    definition["estimated_station_seconds"] = 9000
    mkpath(dirname(archive))
    mv(machine, archive)
    mkpath(machine)
    for file in ("dq_active_reference.tsv", "operating_point.tsv")
        cp(joinpath(archive, file), joinpath(machine, file))
    end
    prepare_fixture("L2-16"; directory = machine, definition)
    record = TOML.parsefile(joinpath(machine, "manifest.toml"))
    record["archive_directory"] = relpath(archive, ROOT)
    record["variant"] = "1.25 us base / 0.625 us witness; 2.5 us evidence archived"
    write_manifest(machine, record)
    return nothing
end

# Each outcome is saved before advancing. Native completion/hash verification
# provides resumption; failed items are retried on the next invocation.
function run_m9c8(; timeout = 14400.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    directory = mkpath(joinpath(ROOT, "data", "m9c8"))
    record = Dict{String, Any}()
    remote = RemoteConfig()
    deadline = time() + timeout
    try
        result = run_settling_experiment(; remote, deadline)
        record["settling"] = Dict("status" => result["status"])
        haskey(result, "failure") && (record["settling"]["failure"] = result["failure"])
    catch failure
        failure isa InterruptException && rethrow()
        record["settling"] = Dict("status" => "run_or_analysis_failed",
            "failure" => sprint(showerror, failure))
        @warn "Settling experiment failed; continuing queue" error = record["settling"]["failure"]
    end
    write_manifest(directory, record)
    try
        run_timing(remote, deadline; directory = joinpath(directory, "timing"))
        record["timing"] = Dict("status" => "passed")
    catch failure
        failure isa InterruptException && rethrow()
        record["timing"] = Dict("status" => "run_or_analysis_failed",
            "failure" => sprint(showerror, failure))
        @warn "Timing witness failed; continuing queue" error = record["timing"]["failure"]
    end
    write_manifest(directory, record)
    result = run_fixture_continuing("L2-16"; remote, deadline)
    record["L2-16"] = Dict("status" => result["status"])
    haskey(result, "failure") && (record["L2-16"]["failure"] = result["failure"])
    write_manifest(directory, record)
    return record
end
