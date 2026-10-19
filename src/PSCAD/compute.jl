function _computation_options(model::PSCADModel, options::NamedTuple)
    allowed = (:remote, :simulation_time, :time_step, :sample_step, :snapshot_time,
        :output_stem, :verbosity, :work_root, :resume_run_directory, :solver_identity, :timing)
    unknown = setdiff(keys(options), allowed)
    isempty(unknown) ||
        throw(ArgumentError("unknown PSCAD computation options: $(sort!(collect(unknown)))"))
    remote = haskey(options, :remote) ? options.remote : RemoteConfig()
    remote isa RemoteConfig || throw(ArgumentError("remote must be a RemoteConfig"))
    remote.transport === :local && !Sys.iswindows() &&
        throw(ArgumentError("PSCAD local transport requires a Windows caller"))
    old = model.settings
    settings = SimulationSettings(;
        simulation_time = get(options, :simulation_time, old.simulation_time),
        time_step = get(options, :time_step, old.time_step),
        sample_step = get(options, :sample_step, old.sample_step),
        snapshot_time = get(options, :snapshot_time, old.snapshot_time),
        output_stem = get(options, :output_stem, old.output_stem),
        frequency = old.frequency, source_ramp = old.source_ramp)
    verbosity = get(options, :verbosity, 0)
    verbosity isa Integer && !(verbosity isa Bool) && verbosity in 0:2 ||
        throw(ArgumentError("verbosity must be 0, 1, or 2"))
    timing = get(options, :timing, false)
    timing isa Bool || throw(ArgumentError("timing must be Bool"))
    work_root = get(options, :work_root, remote.local_root)
    work_root isa AbstractString && !isempty(work_root) ||
        throw(ArgumentError("work_root must be a nonempty path"))
    work_root = abspath(work_root)
    _local_parts(work_root, remote.local_root)
    resume = get(options, :resume_run_directory, nothing)
    (resume === nothing || resume === :latest ||
     resume isa AbstractString && !isempty(resume)) ||
        throw(ArgumentError("resume_run_directory must be nothing, :latest, or a completed run path"))
    if resume isa AbstractString
        resume = abspath(resume)
    end
    expected = get(options, :solver_identity, nothing)
    (expected === nothing || expected isa AbstractDict) ||
        throw(ArgumentError("solver_identity must be the record returned by identify(remote)"))
    expected = expected === nothing ? nothing :
               Dict{String, String}(validate(expected, remote))
    return (; remote, settings, verbosity = Int(verbosity), work_root,
        resume_run_directory = resume, solver_identity = expected, timing)
end

function _settings_record(settings::SimulationSettings)
    record = Dict{String, Any}("time_duration" => settings.simulation_time,
        "time_step_us" => settings.time_step * 1e6, "sample_step_us" =>
            settings.sample_step * 1e6,
        "output_stem" => settings.output_stem, "plot_type" => "OUT")
    settings.snapshot_time === nothing || (record["snapshot_time"] = settings.snapshot_time)
    return record
end

function _pscad_digest(record::AbstractDict)
    bytes2hex(sha256(sprint(io -> TOML.print(io, record; sorted = true))))
end
_file_digest(path::AbstractString) = bytes2hex(open(sha256, path))

function _resume_candidates(options)
    resume = options.resume_run_directory
    resume === nothing && return String[]
    resume === :latest || return [resume]
    isdir(options.work_root) || return String[]
    return sort!(
        filter(
            path -> startswith(basename(path), "run-") && isdir(path) &&
                    isfile(joinpath(path, "complete.toml")),
            readdir(options.work_root; join = true));
        by = path -> mtime(joinpath(path, "complete.toml")), rev = true)
end

function _verified_completed_run(options, signature)
    station_identity = nothing
    for candidate in _resume_candidates(options)
        record_path = joinpath(candidate, "complete.toml")
        isfile(record_path) ||
            throw(ArgumentError("PSCAD run has no completion record: $candidate"))
        record = TOML.parsefile(record_path)
        if get(record, "schema_version", nothing) != 1 ||
           get(record, "input_sha256", nothing) != signature
            options.resume_run_directory === :latest && continue
            throw(ArgumentError("PSCAD completed run has different inputs or schema: $candidate"))
        end
        stored = TOML.parsefile(joinpath(candidate, "computation.toml"))
        _pscad_digest(stored) == get(record, "request_sha256", nothing) ||
            throw(ArgumentError("PSCAD completed-run input integrity check failed: $candidate"))
        numerical = copy(stored)
        pop!(numerical, "expected_solver", nothing)
        _pscad_digest(numerical) == signature ||
            throw(ArgumentError("PSCAD completed-run numerical input integrity check failed: $candidate"))
        _file_digest(joinpath(candidate, "generated.pscx")) == stored["project_sha256"] ||
            throw(ArgumentError("PSCAD completed-run project changed: $candidate"))
        for (name, digest) in get(stored, "resources", Dict())
            path = joinpath(candidate, name)
            isfile(path) && _file_digest(path) == digest ||
                throw(ArgumentError("PSCAD completed-run resource changed: $path"))
        end
        for (name, digest) in stored["toolkit"]
            path = joinpath(candidate, "toolkit", name)
            isfile(path) && _file_digest(path) == digest ||
                throw(ArgumentError("PSCAD completed-run toolkit integrity check failed: $path"))
        end
        outputs = get(record, "outputs", Dict())
        all(name -> haskey(outputs, name), _required_outputs(options.settings.output_stem)) ||
            throw(ArgumentError("PSCAD completed run has an incomplete output record: $candidate"))
        for (name, digest) in outputs
            basename(name) == name ||
                throw(ArgumentError("invalid PSCAD completion output path: $name"))
            path = joinpath(candidate, "outputs", name)
            isfile(path) && _file_digest(path) == digest ||
                throw(ArgumentError("PSCAD completed-run output integrity check failed: $path"))
        end
        stem = options.settings.output_stem
        count = length(_inf_entries(joinpath(candidate, "outputs", stem * ".inf")))
        data_names = [stem * "_" * lpad(string(index), 2, '0') * ".out"
                      for index in 1:cld(count, 10)]
        options.settings.snapshot_time === nothing || push!(data_names, stem * ".snp")
        all(name -> haskey(outputs, name), data_names) || throw(ArgumentError(
            "PSCAD completed run has unattested data or snapshot files: $candidate"))
        actual = Dict{String, String}(validate(
            TOML.parsefile(joinpath(candidate, "outputs", "solver.toml")), options.remote))
        actual == get(record, "observed_solver", nothing) ||
            throw(ArgumentError("PSCAD completed run has no matching solver attestation: $candidate"))
        station_identity === nothing && (station_identity = identify(options.remote))
        options.solver_identity === nothing ||
            options.solver_identity == station_identity ||
            throw(ArgumentError("PSCAD station does not match the expected solver identity"))
        if actual != station_identity
            options.resume_run_directory === :latest && continue
            throw(ArgumentError("PSCAD completed run belongs to a different solver installation: $candidate"))
        end
        return candidate
    end
    return nothing
end

function _build_warnings(path)
    warnings = String[]
    for line in eachline(path)
        fields = split(strip(line))
        isempty(fields) && continue
        status = lowercase(first(fields))
        status == "error" &&
            throw(ArgumentError("PSCAD build messages contain an error: $line"))
        status == "warning" && push!(warnings, line)
    end
    return warnings
end

function _complete_run(root, input, signature, actual)
    output = joinpath(root, "outputs")
    completion = Dict("schema_version" => 1, "input_sha256" => signature,
        "request_sha256" => _pscad_digest(input), "observed_solver" => actual,
        "outputs" => Dict(name => _file_digest(joinpath(output, name))
        for name in readdir(output) if isfile(joinpath(output, name))))
    temporary = tempname(root)
    try
        open(io -> TOML.print(io, completion; sorted = true), temporary, "w")
        mv(temporary, joinpath(root, "complete.toml"); force = false)
    finally
        isfile(temporary) && rm(temporary)
    end
    return nothing
end

"""
$(TYPEDSIGNATURES)

Execute a PSCAD project on a configured station and read its INF/OUT files.
A fresh call copies `generated.pscx`, the computation record and the runner
files into a persistent `run-XXXXXX` directory. Write the completion record
atomically after checking settings, solver identity, outputs and probes.

# Arguments

- `model`: Existing PSCAD project and requested measurements.
- `formulation`: `PSCADRun` selecting the execution backend.
- `options`: Named tuple of computation options. Default: empty.
  `remote` defaults to `RemoteConfig()`. The duration, integration step,
  output interval and snapshot overrides are `simulation_time`, `time_step`,
  `sample_step` and `snapshot_time` \\[s\\]. Other options are `output_stem`,
  `verbosity` (0–2, default 0), `work_root` (within `remote.local_root`),
  `resume_run_directory` (`nothing`, `:latest`, or a path), `solver_identity`
  (the record from `PSCAD.identify(remote)`), and `timing::Bool` (default `false`).
  Check simulation overrides together and reject unknown keys.

# Returns

- A `PSCADResult` with ordered channels and execution diagnostics.
  `elapsed_seconds` \\[s\\] measures `project.run()`, excluding file transfer
  and output waits. With `timing = true`, fresh runs also record caller
  `wall_seconds` \\[s\\]; reused results have `timing = (;)`.

# Notes

Reuse requires an explicit `resume_run_directory`, matching hashes for inputs,
runner files and outputs, and a check of the current station installation.
Python runs on the station. Project libraries and external files must be
available there, because this method copies only the project and runner files.
"""
function compute(model::PSCADModel, formulation::PSCADRun; options::NamedTuple = (;))
    _require_backend(formulation, PSCADBackend)
    resolved = _computation_options(model, options)
    started = time_ns()
    input = Dict{String, Any}("schema_version" => 1,
        "project_sha256" => _file_digest(model.project_path), "project_name" => "generated",
        "settings" => _settings_record(resolved.settings),
        "probes" => Dict("names" => [channel.name for channel in model.probes.channels]),
        "toolkit" => Dict(name => bytes2hex(sha256(source))
        for (name, source) in PSCAD_REMOTE_SOURCES))
    if model.ztool_library !== nothing
        library = model.ztool_library
        isfile(library.path) && _file_digest(library.path) == library.sha256 ||
            throw(ArgumentError("Z-tool model library changed: $(library.path)"))
        workspace = _ztool_workspace("generated", "generated.pscx")
        input["resources"] = Dict("Z_tool.pslx" => library.sha256,
            "generated.pswx" => bytes2hex(sha256(workspace)))
        frequency_tables = _ztool_frequency_tables(resolved.settings.frequency)
        for (name, contents) in frequency_tables
            input["resources"][name] = bytes2hex(sha256(contents))
        end
    end
    signature = _pscad_digest(input)
    resolved.solver_identity === nothing ||
        (input["expected_solver"] = resolved.solver_identity)
    root = _verified_completed_run(resolved, signature)
    reused = root !== nothing
    if reused
        resolved.verbosity >= 1 &&
            @info "PSCAD reuses a verified completed run" run_directory = root
    else
        root = mktempdir(mkpath(resolved.work_root); prefix = "run-", cleanup = false)
        staged = joinpath(root, "generated.pscx")
        cp(model.project_path, staged)
        _file_digest(staged) == input["project_sha256"] ||
            throw(ArgumentError("PSCAD project changed during staging: $(model.project_path)"))
        if model.ztool_library !== nothing
            cp(model.ztool_library.path, joinpath(root, "Z_tool.pslx"))
            write(joinpath(root, "generated.pswx"), _ztool_workspace("generated", "generated.pscx"))
            _write_ztool_frequency_tables(root, frequency_tables)
            for (name, digest) in input["resources"]
                _file_digest(joinpath(root, name)) == digest ||
                    throw(ArgumentError("PSCAD resource changed during staging: $name"))
            end
        end
        open(io -> TOML.print(io, input; sorted = true), joinpath(root, "computation.toml"), "w")
        resolved.verbosity >= 1 && @info "Executing PSCAD project" run_directory = root
        run_remote_pscad(resolved.remote, staged, joinpath(root, "outputs");
            output_stem = resolved.settings.output_stem, verbosity = resolved.verbosity)
    end
    output = joinpath(root, "outputs")
    console = joinpath(output, "pscad-console.txt")
    build_messages = joinpath(output, "build-messages.txt")
    actual = Dict{String, String}(validate(TOML.parsefile(joinpath(output, "solver.toml")), resolved.remote))
    resolved.solver_identity === nothing || actual == resolved.solver_identity ||
        throw(ArgumentError("PSCAD result does not match the expected solver identity: $root"))
    readback = _verify_settings_readback(
        TOML.parsefile(joinpath(output, "settings-readback.toml")), input["settings"])
    warnings = _build_warnings(build_messages)
    parsed = try
        result = read_pscad_output(output; stem = resolved.settings.output_stem)
        expected_rows = round(Int, resolved.settings.simulation_time /
                                   resolved.settings.sample_step) + 1
        length(result.time) == expected_rows || throw(ArgumentError(
            "PSCAD output has $(length(result.time)) rows; expected $expected_rows"))
        missing = [channel.name
                   for channel in model.probes.channels
                   if !_probe_present(channel, result.channels)]
        isempty(missing) ||
            throw(ArgumentError("PSCAD output is missing probe channels: $missing"))
        if resolved.settings.snapshot_time !== nothing
            path = joinpath(output, resolved.settings.output_stem * ".snp")
            isfile(path) && filesize(path) > 0 ||
                throw(ArgumentError("PSCAD snapshot is missing or empty: $path"))
        end
        result
    catch error
        throw(ErrorException("PSCAD result validation failed: $(sprint(showerror, error))" *
                             "\nLast PSCAD diagnostics:\n$(_diagnostic_tail(console))\nFull PSCAD diagnostics: $console"))
    end
    elapsed = parse(Float64, strip(read(joinpath(output, "timing.txt"), String)))
    isfinite(elapsed) && elapsed >= 0 ||
        throw(ArgumentError("invalid PSCAD execution timing"))
    reused || _complete_run(root, input, signature, actual)
    diagnostics = (; elapsed_seconds = elapsed, reused, solver_identity = actual,
        settings_readback = readback, build_warnings = warnings)
    if resolved.timing
        diagnostics = merge(diagnostics,
            (timing = reused ? (;) : (wall_seconds = (time_ns() - started) * 1e-9,),))
    end
    return PSCADResult(formulation, parsed.time, parsed.channels, model.probes,
        resolved.settings, diagnostics,
        (; run_directory = root, outputs = output,
            console, build_messages, inf = parsed.inf))
end
