module PSCADConfigTests
using Test, PowerImpedance, TOML, Base64, Logging
const P = PowerImpedance.PSCAD

function P.remote_command(::Val{:fetch_fixture}, config::RemoteConfig, command::AbstractString)
    destination = only(match(r"\$destination='([^']+)'", command).captures)
    relative = replace(destination, '\\' => '/')
    path = joinpath(config.local_root, relpath(relative, replace(config.shared_root, '\\' =>
        '/')))
    script = "write(" * repr(path) * ", \"station file fixture\")"
    return `$(Base.julia_cmd()) --startup-file=no --project=@stdlib -e $script`
end

@testset "PSCAD remote configuration and commands" begin
    mktempdir() do directory
        filename = joinpath(directory, "station.toml")
        fields = Dict{String, Any}(
            "host" => "user@station.invalid", "local_root" => "not-created/exchange",
            "shared_root" => raw"Z:\shared space\exchange", "remote_root" =>
                raw"C:\scratch space",
            "julia_executable" => raw"C:\Julia\julia.exe", "python_executable" =>
                raw"C:\Python\python.exe")
        save() = open(io -> TOML.print(io, fields), filename, "w")
        save()
        config = RemoteConfig(filename)
        @test config.local_root == joinpath(directory, "not-created", "exchange")
        @test !ispath(config.local_root)
        @test config.shared_root == fields["shared_root"]
        @test config.remote_root == fields["remote_root"]
        @test config.transport === :ssh
        @test config.timeout == 1800
        @test config.pscad_port === nothing
        for port in (1024, 50000, 65535)
            fields["pscad_port"] = port
            save()
            @test RemoteConfig(filename).pscad_port == port
            @test RemoteConfig("fixture", "shared", "scratch", "julia", "python";
                local_root = directory, pscad_port = port).pscad_port == port
        end
        for port in (true, false, 0, 1023, 65536, -1, 50000.0, "50000")
            fields["pscad_port"] = port
            save()
            @test_throws ArgumentError RemoteConfig(filename)
            @test_throws ArgumentError RemoteConfig(
                "fixture", "shared", "scratch", "julia", "python";
                local_root = directory, pscad_port = port)
        end
        delete!(fields, "pscad_port")
        save()
        @test isempty(config.command)
        withenv("POWERIMPEDANCE_PSCAD_CONFIG" => filename) do
            @test RemoteConfig().local_root == config.local_root
        end
        for value in (nothing, "")
            withenv("POWERIMPEDANCE_PSCAD_CONFIG" => value) do
                caught = try
                    RemoteConfig()
                catch error
                    error
                end
                @test caught isa ArgumentError
                @test occursin("POWERIMPEDANCE_PSCAD_CONFIG", sprint(showerror, caught))
            end
        end
        powershell = "Write-Output 'spaces, quotes and Ω'"
        argv = P._powershell_argv(powershell)
        decoded = transcode(String, ltoh.(reinterpret(UInt16, base64decode(last(argv)))))
        @test decoded == "\$ProgressPreference='SilentlyContinue'; " * powershell
        @test argv[1:4] ==
              ["powershell.exe", "-NoProfile", "-NonInteractive", "-EncodedCommand"]
        @test collect(P.remote_command(config, powershell))[1:2] == ["ssh", fields["host"]]
        @test collect(P.remote_command(Val(:local), config, powershell)) == argv
        fields["transport"] = "command"
        fields["command"] = [
            "wrapper path", "ssh", "{host}", "literal-{host}", "\$(literal)"]
        save()
        config = RemoteConfig(filename)
        @test collect(P.remote_command(config, powershell))[1:5] ==
              ["wrapper path", "ssh", fields["host"], "literal-{host}", "\$(literal)"]
        @test collect(P.remote_command(config, powershell))[6:end] == argv
        for (key, value) in (("timeout_seconds", 1), ("unknown", 1), ("timeout", true),
            ("host", 42), ("local_root", ""), ("transport", 1), ("command", "ssh"),
            ("command", [1]), ("command", String[]))
            saved = copy(fields)
            fields[key] = value
            save()
            @test_throws ArgumentError RemoteConfig(filename)
            empty!(fields)
            merge!(fields, saved)
        end
        @test_throws ArgumentError RemoteConfig(
            "fixture", "shared", "scratch", "julia", "python";
            local_root = directory, verbosity = 2)
        @test !ispath(joinpath(directory, "not-created"))
        @test P._ps_quote("a'b") == "'a''b'"
        @test P._remote_project_name(raw"C:\folder\generated.pscx") == "generated"
        supervisor = P._supervisor_command(
            config, raw"Z:\case's", raw"C:\scratch", "generated";
            output_stem = "pi", verbosity = 2)
        for text in ("-SharedCase 'Z:\\case''s'", "-ProjectName 'generated'", "-OutputStem 'pi'",
            "-PSCADVersion '5.1.0'", "-PSCADPort 0", "-RemoteRoot 'C:\\scratch space'",
            "-Verbosity '2'", "-TimeoutSeconds '1800'")
            @test occursin(text, supervisor)
        end
        @test !occursin("-Formulation", supervisor)
        @test !occursin("-Frequency", supervisor)
        fields["pscad_port"] = 50000
        save()
        @test occursin("-PSCADPort 50000",
            P._supervisor_command(
                RemoteConfig(filename), "shared", "scratch", "generated"; output_stem = "pi"))
        cancel = P._cancel_command(raw"Z:\case's\toolkit", raw"C:\scratch\case's")
        @test cancel ==
              ". 'Z:\\case''s\\toolkit\\lifecycle.ps1'; Stop-PSCADCase -LocalCase 'C:\\scratch\\case''s'"
        for text in ("lifecycle.ps1", "Stop-PSCADCase", "-LocalCase")
            @test occursin(text, cancel)
        end
        lifecycle = P.PSCAD_REMOTE_SOURCES["lifecycle.ps1"]
        for text in ("owner.txt", "pscad-owner.txt", "EMTDC", "ExecutablePath", "CreationDate",
            "Get-CimInstance", "taskkill.exe /PID", "/T /F", "StartsWith", "CommandLine")
            @test occursin(text, lifecycle)
        end
        @test !occursin("exit 0", lifecycle)
        @test occursin(". (Join-Path \$PSScriptRoot \"lifecycle.ps1\")",
            P.PSCAD_REMOTE_SOURCES["supervisor.ps1"])
        for name in ("Stop-OwnedRunner", "Stop-EMTDC", "Stop-OwnedPSCAD", "Stop-PSCADCase")
            @test occursin("function $name {", lifecycle)
            @test !occursin("function $name {", P.PSCAD_REMOTE_SOURCES["supervisor.ps1"])
        end
        long_case = "C:\\scratch\\" * repeat("x", 189)
        @test length(long_case) == 200
        @test length(join(
            P._powershell_argv(P._cancel_command(
                P._remote_path(long_case, "toolkit"), long_case)), ' ')) < 2000
        @test_throws ArgumentError P.validate(Dict("version" => 5), config)
    end
    mktempdir() do root
        config = RemoteConfig("fixture", raw"Z:\exchange", "scratch", "julia", "python";
            local_root = root, transport = :fetch_fixture)
        path = joinpath(root, "inputs", "case.pscx")
        @test P.fetch_station_file(config, raw"C:\examples\case.pscx", path) == path
        @test read(path, String) == "station file fixture"
        cd(root) do
            relative = joinpath("inputs", "relative.pscx")
            @test P.fetch_station_file(config, "station-source", relative) == relative
            @test read(relative, String) == "station file fixture"
        end
        @test_throws ArgumentError P.fetch_station_file(
            config, "source", joinpath(dirname(root), "outside.pscx"))
        mktempdir() do outside
            if !Sys.iswindows()
                symlink(outside, joinpath(root, "escape"))
                @test_throws ArgumentError P.fetch_station_file(
                    config, "source", joinpath(root, "escape", "case.pscx"))
            end
        end
    end
end

# Port the donor's reader fault injection without replacing package methods.
module ReaderFailures
const RemoteConfig = NamedTuple
const fail_at_eof = Ref(false)
const readers_started = Channel{Nothing}(2)
const child = Ref{Base.Process}()
remote_command(config::RemoteConfig, ::AbstractString) = config.command
function run(command; wait)
    child[] = Base.run(command; wait)
end
struct Lines{T}
    source::T
end
function eachline(pipe::Pipe)
    put!(readers_started, nothing)
    return Lines(Base.eachline(pipe))
end
function Base.iterate(lines::Lines, state...)
    entry = iterate(lines.source, state...)
    entry === nothing && fail_at_eof[] && error("synthetic reader cleanup failure")
    entry === nothing || first(entry) != "FAIL" || error("synthetic reader failure")
    return entry
end
Base.include(@__MODULE__, joinpath(@__DIR__, "../../src/PSCAD/remote/remote.jl")) do expression
    expression isa Expr && expression.head === :function && expression.args[1] isa Expr &&
    expression.args[1].head === :call && expression.args[1].args[1] === :_run_remote ?
    expression : nothing
end
end

@testset "PSCAD transport reader failures and interruption" begin
    R = ReaderFailures
    for stream in ("stdout", "stderr")
        script = "println($stream, \"partial\"); println($stream, \"FAIL\"); flush($stream); sleep(30)"
        command = `$(Base.julia_cmd()) --startup-file=no --handle-signals=no --project=@stdlib -e $script`
        mktempdir() do root
            caught = try
                R._run_remote((; command, timeout = 10.0), "unused";
                    stdout_path = joinpath(root, "out.log"), stderr_path = joinpath(root, "err.log"))
            catch error
                error
            end
            @test caught isa TaskFailedException
            @test occursin("synthetic reader failure", sprint(showerror, caught))
            @test process_exited(R.child[])
            @test read(joinpath(root, stream == "stdout" ? "out.log" : "err.log"), String) ==
                  "partial\n"
            take!(R.readers_started)
            take!(R.readers_started)
        end
    end
    command = `$(Base.julia_cmd()) --startup-file=no --handle-signals=no --project=@stdlib -e 'sleep(30)'`
    R.fail_at_eof[] = true
    logger = Test.TestLogger(min_level = Logging.Warn)
    canceled = Ref(false)
    try
        task = with_logger(logger) do
            @async try
                R._run_remote((; command, timeout = 10.0), "unused";
                    on_interrupt = () -> (canceled[] = true))
            catch error
                error
            end
        end
        take!(R.readers_started)
        take!(R.readers_started)
        schedule(task, InterruptException(); error = true)
        @test fetch(task) isa InterruptException
        @test canceled[]
        @test process_exited(R.child[])
        @test Set(record.kwargs[:stream] for record in logger.logs) ==
              Set((:stdout, :stderr))
        @test all(record -> occursin("reader failed during cleanup", string(record.message)), logger.logs)
    finally
        R.fail_at_eof[] = false
    end
end
end
