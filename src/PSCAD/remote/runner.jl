using PythonCall
using TOML
using SHA: sha256

include(joinpath(@__DIR__, "files.jl"))

const MHI_PSCAD_VERSION = "3.1.2"
_string(value) = pyconvert(String, pybuiltins.str(value))
_components(value) = pyconvert(Vector{Py}, pybuiltins.list(value))

function _schematic_origins(path)
    root = pyimport("xml.etree.ElementTree").parse(String(path)).getroot()
    objects = Dict{Tuple{String, String}, NamedTuple{(:x, :y, :kind), Tuple{Int, Int, String}}}()
    for definition in root.findall("./definitions/Definition")
        name = _string(definition.get("name"))
        for canvas in definition.findall("schematic"), node in canvas.iter()
            pyis(node.get("id"), pybuiltins.None) && continue
            pyis(node.get("x"), pybuiltins.None) && continue
            objects[(name, _string(node.get("id")))] = (
                x = parse(Int, _string(node.get("x"))),
                y = parse(Int, _string(node.get("y"))),
                kind = _string(node.get("defn", node.get("classid", node.tag))))
        end
    end
    return objects
end

function _load_relocations(before, after)
    moved = String[]
    for key in sort!(collect(keys(before)))
        haskey(after, key) || continue
        a, b = before[key], after[key]
        (a.x, a.y) == (b.x, b.y) && continue
        push!(moved, "$(key[1]) id=$(key[2]) $(a.kind): $((a.x, a.y)) -> $((b.x, b.y))")
    end
    return moved
end

function _parameters(component)
    raw = pyconvert(Dict, component.parameters())
    return Dict(string(key) => value for (key, value) in raw)
end

function _messages(project)
    messages = try
        _components(project.messages())
    catch error
        return "Unable to read PSCAD messages: $(sprint(showerror, error))\n"
    end
    return join((_string(message) for message in messages), '\n') * "\n"
end

function _report(console::IO, verbosity::Int, level::Int, message::AbstractString)
    line = "[$(round(time(); digits = 3))] $(String(message))"
    println(console, line)
    flush(console)
    if verbosity >= level
        println(stdout, line)
        flush(stdout)
    end
    return nothing
end

function _project_diagnostics(project)
    parts=String["PSCAD messages:\n$(strip(_messages(project)))"]
    try
        output=strip(_string(project.output()))
        isempty(output) || push!(parts, "PSCAD project output:\n$output")
    catch error
        push!(parts, "Unable to read PSCAD project output: $(sprint(showerror, error))")
    end
    return join(parts, '\n')
end

function _record_diagnostics(
        console::IO,
        project,
        verbosity::Int,
        heading::AbstractString;
        error_stream::Bool = false
)
    text="$(String(heading))\n$(_project_diagnostics(project))"
    println(console, text)
    flush(console)
    if verbosity >= 2
        stream=error_stream ? stderr : stdout
        println(stream, text)
        flush(stream)
    end
    return text
end

function _apply_settings(project, settings, path)
    requested = _project_parameters(settings)
    project.parameters(; (Symbol(key) => value for (key, value) in requested)...)
    raw = project.parameters()
    readback = Dict{String, Any}()
    for (key, value) in requested
        observed = value isa AbstractFloat ? pyconvert(Float64, raw[key]) :
                   value isa Integer ? pyconvert(Int, raw[key]) : _string(raw[key])
        readback[key] = Dict("requested" => value, "observed" => observed)
    end
    open(io -> TOML.print(io, readback; sorted = true), path, "w")
    _verify_settings_readback(readback, settings)
    return readback
end

function _build_messages(project, path)
    messages = _components(project.messages())
    open(path, "w") do io
        for message in messages
            println(io,
                join(
                    (_string(message.status), _string(message.label),
                        _string(message.name), replace(_string(message.text), '\n' => ' ', '\r' =>
                            ' ')),
                    '\t'))
        end
    end
    any(message -> lowercase(_string(message.status)) == "error", messages) &&
        error("PSCAD build messages contain error status; see $path")
    return messages
end

function main(arguments)
    length(arguments) == 9 || throw(ArgumentError(
        "runner expects project, output, project name, output stem, PSCAD version, verbosity, port, ownership, and scratch root"))
    project_path, output, project_name, output_stem, pscad_version,
    verbosity_text, port_text, owned_text, remote_root = arguments
    port = parse(Int, port_text)
    (port == 0 || port in 1024:65535) || throw(ArgumentError("invalid PSCAD port"))
    owned = parse(Bool, owned_text)
    port == 0 && !owned && throw(ArgumentError("a private PSCAD launch must be owned"))
    verbosity = parse(Int, verbosity_text)
    verbosity in 0:2 || throw(ArgumentError("verbosity must be 0, 1, or 2"))
    pscad_version == "5.1.0" || throw(ArgumentError("PSCAD 5.1.0 is required"))
    occursin(r"^[A-Za-z][A-Za-z0-9_]{0,19}$", output_stem) ||
        throw(ArgumentError("invalid PSCAD output stem $output_stem"))
    mkpath(output)
    app = nothing
    previous_silence = nothing
    project = nothing
    library = nothing
    library_path = nothing
    library_load_attempted = false
    load_attempted = false
    phase = "initialization"
    console = open(joinpath(output, "pscad-console.txt"), "w")
    build_path = joinpath(output, "build-messages.txt")
    write(build_path, "")
    try
        input = TOML.parsefile(joinpath(dirname(project_path), "computation.toml"))
        get(input, "schema_version", nothing) == 1 ||
            throw(ArgumentError("PSCAD runner requires the version-1 computation record"))
        settings = input["settings"]
        settings["output_stem"] == output_stem ||
            throw(ArgumentError("runner output stem differs from computation.toml"))
        get(input, "project_name", nothing) == project_name ||
            throw(ArgumentError("runner project name differs from computation.toml"))
        metadata = pyimport("importlib.metadata")
        observed = _string(metadata.version("mhi.pscad"))
        observed == MHI_PSCAD_VERSION || throw(ArgumentError(
            "mhi.pscad $MHI_PSCAD_VERSION is required; found $observed"))
        identify = pyimport("runpy").run_path(joinpath(@__DIR__, "identity.py"))["identify"]
        pscad = pyimport("mhi.pscad")
        phase = "PSCAD acquisition"
        if port == 0
            _report(console, verbosity, 1, "Launching PSCAD 5.1.0")
            app = cd(abspath(output)) do
                pscad.launch(; version = pscad_version, x64 = true, minimize = true,
                    splash = false, silence = true, timeout = 60)
            end
        else
            _report(console, verbosity, 1, "Connecting to PSCAD on port $port (owned=$owned)")
            connect_started = time_ns()
            app = pscad.connect(; host = "127.0.0.1", port, timeout = 30)
            connect_seconds = (time_ns() - connect_started) / 1e9
            _report(console, verbosity, 1,
                "PSCAD connect took $(round(connect_seconds; digits = 3)) s")
        end
        phase = "PSCAD dialog suppression"
        previous_silence = pyconvert(Bool, app.silence)
        app.silence = true
        _report(console, verbosity, 1, "silence: previous=$previous_silence, now=true")
        phase = "compiler detection"
        application_settings = try
            app.settings()
        catch capability_error
            occursin("Unable to retrieve detected software", sprint(showerror, capability_error)) ||
                rethrow()
            error("PSCAD cannot detect compilers in this Windows session (non-interactive, e.g. SSH session 0); set pscad_port in the station configuration so runs use a PSCAD in the logged-on desktop session")
        end
        _report(console, verbosity, 1, "fortran_version=$(_string(application_settings["fortran_version"]))")
        phase = "PSCAD licence and identity"
        pyconvert(Bool, app.licensed()) || error("PSCAD refused the configured license")
        _string(app.version) == pscad_version ||
            error("PSCAD acquired an unexpected version")
        initial_identity = pyconvert(Dict{String, String}, identify(pscad_version, app))
        open(io -> TOML.print(io, initial_identity; sorted = true), joinpath(output, "solver.toml"), "w")
        expected_identity = get(input, "expected_solver", nothing)
        expected_identity === nothing || initial_identity == expected_identity ||
            error("PSCAD installation does not match the expected solver identity")
        phase = "project load"
        # PSCAD restores the saved workspace on startup, which can include a
        # project with the same name as the staged project.
        for entry in _components(app.projects())
            _string(entry["name"]) == project_name || continue
            existing = app.project(project_name)
            filename = _string(existing.filename)
            root = lowercase(replace(normpath(abspath(remote_root)), '\\' => '/'))
            path = lowercase(replace(normpath(abspath(filename)), '\\' => '/'))
            startswith(path, rstrip(root, '/') * "/") ||
                error("Refusing to replace loaded PSCAD project $project_name from $filename; it is outside the station scratch root $remote_root")
            existing.unload()
            _report(console, verbosity, 1, "Unloaded stale PSCAD project $project_name from $filename")
        end
        if haskey(input, "resources")
            phase = "Z-tool library load"
            library_path = joinpath(dirname(project_path), "Z_tool.pslx")
            digest = input["resources"]["Z_tool.pslx"]
            isfile(library_path) && bytes2hex(open(sha256, library_path)) == digest ||
                error("Staged Z-tool library SHA-256 differs from computation.toml")
            loaded = any(entry -> _string(entry["name"]) == "Z_tool", _components(app.projects()))
            if loaded
                filename = _string(app.project("Z_tool").filename)
                isfile(filename) && bytes2hex(open(sha256, filename)) == digest ||
                    error("Loaded Z_tool library differs from the staged library: $filename")
            else
                _report(console, verbosity, 1, "Loading staged Z-tool library")
                library_load_attempted = true
                app.load(abspath(library_path))
                library = app.project("Z_tool")
            end
        end
        _report(console, verbosity, 1, "Loading staged project $project_name")
        load_attempted = true
        origins = _schematic_origins(project_path)
        app.load(abspath(project_path))
        project = try
            app.project(project_name)
        catch
            println(console, "Available PSCAD projects: ", _string(app.projects()))
            flush(console)
            rethrow()
        end
        phase = "simulation settings"
        _apply_settings(project, settings, joinpath(output, "settings-readback.toml"))
        project.save()
        phase = "load geometry"
        moved = _load_relocations(origins, _schematic_origins(project_path))
        if !isempty(moved)
            relocation_path = joinpath(output, "load-relocations.txt")
            write(relocation_path, join(moved, '\n') * "\n")
            error("PSCAD moved $(length(moved)) schematic objects on load; see $relocation_path\n" *
                join(first(moved, 20), '\n'))
        end
        _record_diagnostics(console, project, verbosity, "PSCAD diagnostics before execution")
        phase = "project run"
        _report(console, verbosity, 1, "Starting PSCAD project.run()")
        started = time_ns()
        project.run()
        elapsed = (time_ns() - started) * 1e-9
        write(joinpath(output, "timing.txt"), string(elapsed))
        _report(console, verbosity, 1, "PSCAD run call returned in $(round(elapsed; digits = 3)) seconds")
        phase = "build messages"
        _record_diagnostics(console, project, verbosity, "PSCAD diagnostics after execution")
        _build_messages(project, build_path)
        roots = [abspath(_string(project.temp_folder)),
            abspath(dirname(project_path)), abspath(output)]
        phase = "output completion"
        expected_rows = round(Int, settings["time_duration"] /
                                   (settings["sample_step_us"] * 1e-6)) + 1
        _report(console, verbosity, 1, "Waiting for $expected_rows output rows; temp_folder=$(first(roots))")
        files = _wait_outputs(roots, output_stem, expected_rows)
        for source in (files.inf, files.outs...)
            destination = joinpath(output, basename(source))
            abspath(source) == abspath(destination) || cp(source, destination; force = true)
        end
        if haskey(settings, "snapshot_time")
            snapshots = _output_matches(roots, output_stem * ".snp")
            length(snapshots) == 1 ||
                error("PSCAD did not emit exactly one $(output_stem).snp snapshot: $snapshots")
            source = only(snapshots)
            destination = joinpath(output, basename(source))
            abspath(source) == abspath(destination) || cp(source, destination; force = true)
        end
        observed = pyconvert(Dict{String, String}, identify(pscad_version, app))
        observed == initial_identity || error("PSCAD installation changed during execution")
        open(io -> TOML.print(io, observed; sorted = true), joinpath(output, "solver.toml"), "w")
        _report(console, verbosity, 1, "Collected legacy PSCAD outputs")
    catch error
        if project !== nothing
            _record_diagnostics(console, project, verbosity,
                "PSCAD diagnostics at failure"; error_stream = true)
            try
                _build_messages(project, build_path)
            catch
                # Keep the simulation error if collection of build messages also fails.
            end
        end
        message = "PSCAD runner failed during $phase: $(sprint(showerror, error))"
        println(console, message)
        flush(console)
        throw(ErrorException(message))
    finally
        # A failed load can leave the staged project open, so it needs explicit cleanup.
        if project === nothing && load_attempted
            try
                loaded = app.project(project_name)
                normpath(abspath(_string(loaded.filename))) ==
                normpath(abspath(project_path)) &&
                    (project = loaded)
            catch error
                println(console, "PSCAD project lookup during cleanup failed: ", sprint(showerror, error))
            end
        end
        project === nothing || try
            project.unload()
        catch error
            println(console, "PSCAD project unload failed: ", sprint(showerror, error))
        end
        if library === nothing && library_load_attempted
            try
                loaded = app.project("Z_tool")
                normpath(abspath(_string(loaded.filename))) ==
                    normpath(abspath(library_path)) && (library = loaded)
            catch error
                println(console, "PSCAD Z-tool library lookup during cleanup failed: ", sprint(showerror, error))
            end
        end
        library === nothing || try
            library.unload()
        catch error
            println(console, "PSCAD Z-tool library unload failed: ", sprint(showerror, error))
        end
        if app !== nothing && !owned && previous_silence !== nothing
            try
                app.silence = previous_silence
            catch error
                println(console, "PSCAD silence restore failed: ", sprint(showerror, error))
            end
        end
        app === nothing || !owned ||
            try
                app.quit()
            catch error
                println(console, "PSCAD application close failed: ", sprint(showerror, error))
            end
        flush(console)
        close(console)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        main(ARGS)
    catch error
        println(stderr, sprint(showerror, error))
        exit(1)
    end
end
