using PythonCall
using TOML

include(joinpath(@__DIR__, "files.jl"))

const MHI_PSCAD_VERSION = "3.1.2"
_string(value) = pyconvert(String, pybuiltins.str(value))
_components(value) = pyconvert(Vector{Py}, pybuiltins.list(value))

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
    length(arguments) == 6 || throw(ArgumentError(
        "runner expects project, output, project name, output stem, PSCAD version, and verbosity"))
    project_path, output, project_name, output_stem, pscad_version,
    verbosity_text = arguments
    verbosity = parse(Int, verbosity_text)
    verbosity in 0:2 || throw(ArgumentError("verbosity must be 0, 1, or 2"))
    pscad_version == "5.1.0" || throw(ArgumentError("PSCAD 5.1.0 is required"))
    occursin(r"^[A-Za-z][A-Za-z0-9_]{0,19}$", output_stem) ||
        throw(ArgumentError("invalid PSCAD output stem $output_stem"))
    mkpath(output)
    app = nothing
    project = nothing
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
        phase = "PSCAD launch"
        _report(console, verbosity, 1, "Launching PSCAD 5.1.0")
        app = cd(abspath(output)) do
            pscad.launch(; version = pscad_version, x64 = true, minimize = true,
                splash = false, silence = true, timeout = 60)
        end
        pyconvert(Bool, app.licensed()) || error("PSCAD refused the configured license")
        _string(app.version) == pscad_version ||
            error("PSCAD launched an unexpected version")
        initial_identity = pyconvert(Dict{String, String}, identify(pscad_version, app))
        open(io -> TOML.print(io, initial_identity; sorted = true), joinpath(output, "solver.toml"), "w")
        expected_identity = get(input, "expected_solver", nothing)
        expected_identity === nothing || initial_identity == expected_identity ||
            error("PSCAD installation does not match the expected solver identity")
        phase = "project load"
        _report(console, verbosity, 1, "Loading staged project $project_name")
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
                # The original failure and all build messages are already retained.
            end
        end
        message = "PSCAD runner failed during $phase: $(sprint(showerror, error))"
        println(console, message)
        flush(console)
        throw(ErrorException(message))
    finally
        project === nothing || try
            project.unload()
        catch error
            println(console, "PSCAD project unload failed: ", sprint(showerror, error))
        end
        app === nothing || try
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
