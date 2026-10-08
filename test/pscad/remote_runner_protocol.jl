module PSCADRunnerProtocol
using Test, PythonCall, TOML
const REMOTE_ROOT = normpath(joinpath(@__DIR__, "../../src/PSCAD/remote"))
include(joinpath(REMOTE_ROOT, "runner.jl"))

const PYTHON_AUTOMATION_FIXTURE = raw"""
import importlib.metadata
import os
import runpy
import sys
import types
from collections import namedtuple

IDENTITY = {
    "schema": "2", "version": "5.1.0", "python_version": "fixture",
    "automation_version": "3.1.2", "common_version": "fixture",
    "pscad_path": "fixture", "pscad_sha256": "0" * 64,
    "master_library_path": "fixture", "master_library_sha256": "2" * 64,
    "fortran_version": "fixture-fortran",
}
Message = namedtuple("Message", "text label status scope name link group")
class Real(float):
    pass

class Project:
    def __init__(self, name="generated", filename=None):
        self.name = name
        self.filename = filename
        self.temp_folder = os.environ["PI_RUNNER_TEMP"]
        self.values = {}
        self.calls = []
        self.unloaded = False
        self.saved = False
        self.ran = False

    def parameters(self, **updates):
        if updates:
            self.calls.append(dict(updates))
        self.values.update(updates)
        choices = {"PlotType": {0: "NONE", 1: "OUT", 2: "PSOUT"},
                   "StartType": {0: "STANDARD"}, "SnapType": {0: "NONE", 1: "ONLY_ONCE"},
                   "MrunType": {0: "STANDALONE"}}
        for key, codec in choices.items():
            if key in self.values:
                self.values[key] = codec.get(self.values[key], self.values[key])
        observed = dict(self.values)
        for key in ("time_duration", "time_step", "sample_step", "SnapTime"):
            if key in observed:
                observed[key] = Real(observed[key])
        if os.environ.get("PI_RUNNER_MODE") == "readback":
            observed["time_step"] = Real(-1)
        return observed

    def run(self):
        self.ran = True
        if os.environ.get("PI_RUNNER_MODE") in ("run_error", "run_restore_error"):
            raise RuntimeError("synthetic run failure")
        os.makedirs(self.temp_folder, exist_ok=True)
        stem = self.values["output_filename"][:-4]
        with open(os.path.join(self.temp_folder, stem + ".inf"), "w", encoding="cp1252") as stream:
            stream.write('PGB(1) Output Desc="Mid Point Voltage" Group="main" Units="kV"\n')
            stream.write('PGB(2) Output Desc="Load Current" Group="main" Units="kA"\n')
        rows = round(self.values["time_duration"] / (self.values["sample_step"] * 1e-6)) + 1
        with open(os.path.join(self.temp_folder, stem + "_01.out"), "w") as stream:
            stream.write("TIME Voltage Current\n")
            for index in range(rows):
                stream.write(f"{index * self.values['sample_step'] * 1e-6} 2.0D+0 3.0d-1\n")
        if self.values["SnapType"] == "ONLY_ONCE":
            with open(os.path.join(self.temp_folder, self.values["snapshot_filename"]), "w") as stream:
                stream.write("snapshot fixture")

    def messages(self):
        status = "error" if self.ran and os.environ.get("PI_RUNNER_MODE") == "build_error" else "normal"
        return [Message("fixture build message", "Build", status, "project", "generated", "", ""),
                Message("fixture warning", "Build", "warning", "project", "generated", "", "")]

    def output(self):
        return "fixture project output"

    def save(self):
        self.saved = True

    def unload(self):
        self.unloaded = True

class Application:
    version = "5.1.0"
    def __init__(self, silence=False):
        self._project = Project()
        self._silence = silence
        self.silence_updates = []
        self.silence_at_load = None
        self.restore_after_unload = None
        self.closed = False
        self.quit_calls = 0
        self.settings_calls = 0
        self.loaded_path = None
        self.other = Project("user_project", os.path.join(os.environ["PI_RUNNER_TEMP"], "user.pscx"))
        mode = os.environ.get("PI_RUNNER_MODE")
        self.existing = None
        if mode in ("stale", "foreign"):
            directory = os.environ["PI_RUNNER_SCRATCH"] if mode == "stale" else os.environ["PI_RUNNER_SCRATCH"] + "-foreign"
            self.existing = Project(filename=os.path.join(directory, "old-run", "generated.pscx"))

    @property
    def silence(self):
        return self._silence

    @silence.setter
    def silence(self, value):
        self.silence_updates.append(value)
        if len(self.silence_updates) > 1:
            self.restore_after_unload = self._project.unloaded
            if os.environ.get("PI_RUNNER_MODE") in ("restore_error", "run_restore_error"):
                raise RuntimeError("synthetic silence restore failure")
        self._silence = value

    def licensed(self):
        return os.environ.get("PI_RUNNER_MODE") != "license"

    def load(self, path):
        self.silence_at_load = self.silence
        if not self.silence:
            raise RuntimeError("modal dialog would block")
        self.loaded_path = path
        self._project.filename = path
        if os.environ.get("PI_RUNNER_MODE") == "load_error":
            raise RuntimeError("synthetic partial load failure")

    def project(self, name):
        if name == "user_project":
            return self.other
        if self.existing is not None and not self.existing.unloaded and name == "generated":
            return self.existing
        if self.loaded_path is None:
            raise RuntimeError("project not loaded")
        if name != os.path.splitext(os.path.basename(self.loaded_path))[0]:
            raise RuntimeError("unknown project " + name)
        return self._project

    def projects(self):
        entries = [{"name": "master", "type": "Library", "description": "Master Library"},
                   {"name": "user_project", "type": "Case", "description": "User case"}]
        if self.existing is not None and not self.existing.unloaded:
            entries.append({"name": "generated", "type": "Case", "description": "Existing case"})
        if self.loaded_path is not None and not self._project.unloaded:
            entries.append({"name": "generated", "type": "Case", "description": "Our case"})
        return entries

    def settings(self):
        self.settings_calls += 1
        if os.environ.get("PI_RUNNER_MODE") == "session0":
            raise SystemError("Unable to retrieve detected software")
        return {"fortran_version": "GFortran 8.1 (64-bit)"}

    def _settings(self, updates):
        return {"fortran_version": "fixture-fortran"}

    def quit(self):
        self.quit_calls += 1
        self.closed = True

pscad = types.ModuleType("mhi.pscad")
def launch(**kwargs):
    global LAST_APP, LAST_LAUNCH
    LAST_LAUNCH = kwargs
    LAST_APP = Application(silence=True)
    return LAST_APP
pscad.launch = launch
def connect(**kwargs):
    global LAST_APP, LAST_CONNECT
    LAST_CONNECT = kwargs
    LAST_APP = Application(silence=os.environ.get("PI_RUNNER_SILENCE") == "true")
    return LAST_APP
pscad.connect = connect
mhi = types.ModuleType("mhi")
mhi.pscad = pscad
sys.modules["mhi"] = mhi
sys.modules["mhi.pscad"] = pscad
importlib.metadata.version = lambda name: "3.1.2" if name == "mhi.pscad" else "fixture"
ORIGINAL_RUN_PATH = runpy.run_path
runpy._pi_original_run_path = ORIGINAL_RUN_PATH
runpy.run_path = lambda path: {"identify": lambda version, app: dict(IDENTITY)}
"""

function runner_arguments(directory, output; verbosity = "0", snapshot = false,
        port = 0, owned = true, remote_root = directory)
    project = joinpath(directory, "generated.pscx")
    write(project, "fixture")
    settings = Dict{String, Any}("time_duration" => 0.0005, "time_step_us" => 50.0,
        "sample_step_us" => 250.0, "output_stem" => "fixture", "plot_type" => "OUT")
    snapshot && (settings["snapshot_time"] = 0.00025)
    input = Dict("schema_version" => 1, "project_name" => "generated", "settings" =>
        settings)
    open(io -> TOML.print(io, input; sorted = true), joinpath(directory, "computation.toml"), "w")
    return [project, output, "generated", "fixture", "5.1.0", verbosity,
        string(port), string(owned), remote_root]
end

function mock_environment(f, root; mode = "success", silence = false)
    environment = pyimport("os").environ
    environment["PI_RUNNER_TEMP"] = joinpath(root, "compiler-temp")
    environment["PI_RUNNER_MODE"] = mode
    environment["PI_RUNNER_SCRATCH"] = root
    environment["PI_RUNNER_SILENCE"] = string(silence)
    try
        f()
    finally
        environment.pop("PI_RUNNER_TEMP", nothing)
        environment.pop("PI_RUNNER_MODE", nothing)
        environment.pop("PI_RUNNER_SCRATCH", nothing)
        environment.pop("PI_RUNNER_SILENCE", nothing)
    end
end

@testset "PSCAD standalone runner protocol without station" begin
    pyexec(PYTHON_AUTOMATION_FIXTURE, @__MODULE__)
    @test_throws ArgumentError main(String[])
    mktempdir() do root
        arguments = runner_arguments(root, joinpath(root, "outputs"))
        @test_throws ArgumentError main(setindex!(copy(arguments), "3", 6))
        @test_throws ArgumentError main(setindex!(copy(arguments), "5.0.2", 5))
        @test_throws ArgumentError main(setindex!(copy(arguments), "bad-stem", 4))
        @test_throws ArgumentError main(setindex!(copy(arguments), "1bad", 4))
        @test_throws ArgumentError main(setindex!(copy(arguments), "1023", 7))
        @test_throws ArgumentError main(setindex!(copy(arguments), "false", 8))
    end
    for snapshot in (false, true)
        mktempdir() do root
            output = joinpath(root, "outputs")
            arguments = runner_arguments(root, output; snapshot)
            mock_environment(root) do
                @test main(arguments) === nothing
                @test pyconvert(Bool, pyeval("LAST_APP.closed", @__MODULE__))
                @test pyconvert(Bool, pyeval("LAST_APP._project.unloaded", @__MODULE__))
                @test pyconvert(Bool, pyeval("LAST_APP._project.saved", @__MODULE__))
                @test pyconvert(Bool, pyeval("LAST_APP.silence", @__MODULE__))
                @test pyconvert(Bool, pyeval("LAST_APP.silence_at_load", @__MODULE__))
                @test pyconvert(Vector{Bool}, pyeval("LAST_APP.silence_updates", @__MODULE__)) ==
                      [true]
                calls = pyconvert(Vector{Dict{String, Any}}, pyeval("LAST_APP._project.calls", @__MODULE__))
                @test length(calls) == 1
                @test only(calls)["time_step"] == 50.0
                @test only(calls)["sample_step"] == 250.0
                @test only(calls)["PlotType"] == "OUT"
                @test only(calls)["StartType"] == "STANDARD"
                @test only(calls)["SnapType"] == (snapshot ? "ONLY_ONCE" : "NONE")
                @test only(calls)["MrunType"] == "STANDALONE"
                @test only(calls)["Mruns"] == 1
                @test only(calls)["output_filename"] == "fixture.out"
            end
            readback = TOML.parsefile(joinpath(output, "settings-readback.toml"))
            @test readback["time_step"] == Dict("requested" => 50.0, "observed" => 50.0)
            @test readback["PlotType"]["observed"] == "OUT"
            @test readback["SnapType"]["observed"] == (snapshot ? "ONLY_ONCE" : "NONE")
            @test isfile(joinpath(output, "fixture.inf"))
            @test _data_rows(joinpath(output, "fixture_01.out")) == 3
            @test isfile(joinpath(output, "fixture.snp")) == snapshot
            @test parse(Float64, read(joinpath(output, "timing.txt"), String)) >= 0
            @test TOML.parsefile(joinpath(output, "solver.toml"))["schema"] == "2"
            @test TOML.parsefile(joinpath(output, "solver.toml"))["fortran_version"] ==
                  "fixture-fortran"
            @test occursin("normal\tBuild\tgenerated\tfixture build message",
                read(joinpath(output, "build-messages.txt"), String))
            console = read(joinpath(output, "pscad-console.txt"), String)
            @test occursin("fixture project output", console)
            @test occursin("temp_folder=", console)
            @test occursin("Collected legacy PSCAD outputs", console)
            @test occursin("fortran_version=GFortran 8.1 (64-bit)", console)
            @test occursin("silence: previous=true, now=true", console)
        end
    end
    for mode in ("build_error", "run_error", "readback", "license")
        mktempdir() do root
            output = joinpath(root, "outputs")
            arguments = runner_arguments(root, output; verbosity = "0")
            caught = mock_environment(root; mode) do
                try
                    main(arguments)
                catch error
                    error
                end
            end
            @test caught isa ErrorException
            @test occursin("PSCAD runner failed during", sprint(showerror, caught))
            @test occursin("PSCAD runner failed during", read(joinpath(output, "pscad-console.txt"), String))
            @test pyconvert(Bool, pyeval("LAST_APP.closed", @__MODULE__))
            @test pyconvert(Bool, pyeval("LAST_APP._project.unloaded", @__MODULE__)) ==
                  (mode != "license")
            @test !isfile(joinpath(output, "fixture_01.out"))
            if mode == "build_error"
                @test occursin("error\tBuild\tgenerated", read(joinpath(output, "build-messages.txt"), String))
            elseif mode == "readback"
                @test TOML.parsefile(joinpath(output, "settings-readback.toml"))["time_step"]["observed"] ==
                      -1
            end
        end
    end
    for owned in (false, true),
        mode in ("success", "stale", "foreign", "session0",
            "run_error", "readback", "build_error", "load_error", "license",
            "restore_error", "run_restore_error")

        mktempdir() do root
            output = joinpath(root, "outputs")
            arguments = runner_arguments(root, output; port = 50000, owned)
            caught = mock_environment(root; mode) do
                try
                    main(arguments)
                catch error
                    error
                end
            end
            @test (caught === nothing) == (mode in ("success", "stale", "restore_error"))
            @test pyconvert(Int, pyeval("LAST_APP.quit_calls", @__MODULE__)) == Int(owned)
            @test !pyconvert(Bool, pyeval("LAST_APP.other.unloaded", @__MODULE__))
            @test pyconvert(Bool, pyeval("LAST_APP._project.unloaded", @__MODULE__)) ==
                  !(mode in ("foreign", "session0", "license"))
            @test pyconvert(Dict{String, Any}, pyeval("LAST_CONNECT", @__MODULE__)) ==
                  Dict("host" => "127.0.0.1", "port" => 50000, "timeout" => 30)
            restore_fails = !owned && mode in ("restore_error", "run_restore_error")
            @test pyconvert(Bool, pyeval("LAST_APP.silence", @__MODULE__)) ==
                  (owned || restore_fails)
            @test pyconvert(Vector{Bool}, pyeval("LAST_APP.silence_updates", @__MODULE__)) ==
                  (owned ? [true] : [true, false])
            @test pyconvert(Bool, pyeval("LAST_APP.silence_at_load is True", @__MODULE__)) ==
                  !(mode in ("foreign", "session0", "license"))
            if !owned
                @test pyconvert(Bool, pyeval("LAST_APP.restore_after_unload", @__MODULE__)) ==
                      !(mode in ("foreign", "session0", "license"))
            end
            console = read(joinpath(output, "pscad-console.txt"), String)
            connect_time = match(r"PSCAD connect took ([0-9.]+) s", console)
            @test connect_time !== nothing
            @test parse(Float64, connect_time[1]) >= 0
            @test occursin("silence: previous=false, now=true", console)
            @test occursin("PSCAD silence restore failed", console) == restore_fails
            if restore_fails
                @test occursin("synthetic silence restore failure", console)
            end
            if mode == "run_restore_error"
                @test occursin("synthetic run failure", sprint(showerror, caught))
                @test !occursin("synthetic silence restore failure", sprint(showerror, caught))
            end
            if mode == "stale"
                @test pyconvert(Bool, pyeval("LAST_APP.existing.unloaded", @__MODULE__))
                @test occursin("Unloaded stale PSCAD project generated", console)
            elseif mode == "foreign"
                @test !pyconvert(Bool, pyeval("LAST_APP.existing.unloaded", @__MODULE__))
                @test pyconvert(Bool, pyeval("LAST_APP.loaded_path is None", @__MODULE__))
                @test occursin("Refusing to replace loaded PSCAD project generated", sprint(showerror, caught))
                @test occursin(root * "-foreign", sprint(showerror, caught))
            elseif mode == "session0"
                @test occursin(
                    "PSCAD cannot detect compilers in this Windows session (non-interactive, e.g. SSH session 0); set pscad_port in the station configuration so runs use a PSCAD in the logged-on desktop session",
                    sprint(showerror, caught))
                @test pyconvert(Bool, pyeval("LAST_APP.loaded_path is None", @__MODULE__))
            end
        end
    end
    mktempdir() do root
        output = joinpath(root, "outputs")
        mock_environment(root; silence = true) do
            @test main(runner_arguments(root, output; port = 50000, owned = false)) ===
                  nothing
            @test pyconvert(Bool, pyeval("LAST_APP.silence", @__MODULE__))
            @test pyconvert(Vector{Bool}, pyeval("LAST_APP.silence_updates", @__MODULE__)) ==
                  [true, true]
            @test pyconvert(Bool, pyeval("LAST_APP.restore_after_unload", @__MODULE__))
            @test pyconvert(Int, pyeval("LAST_APP.quit_calls", @__MODULE__)) == 0
        end
        @test occursin("silence: previous=true, now=true",
            read(joinpath(output, "pscad-console.txt"), String))
    end
    mktempdir() do root
        caught = mock_environment(root; mode = "session0") do
            try
                main(runner_arguments(root, joinpath(root, "outputs")))
            catch error
                error
            end
        end
        @test occursin("PSCAD cannot detect compilers in this Windows session", sprint(showerror, caught))
        @test pyconvert(Int, pyeval("LAST_APP.quit_calls", @__MODULE__)) == 1
        @test pyconvert(Bool, pyeval("LAST_APP.loaded_path is None", @__MODULE__))
    end
    mktempdir() do root
        output = joinpath(root, "outputs")
        arguments = runner_arguments(root, output)
        input_path = joinpath(root, "computation.toml")
        input = TOML.parsefile(input_path)
        input["project_name"] = "wrong"
        open(io -> TOML.print(io, input), input_path, "w")
        arguments[3] = "wrong"
        mock_environment(root) do
            @test_throws ErrorException main(arguments)
        end
        @test occursin("Available PSCAD projects", read(joinpath(output, "pscad-console.txt"), String))
        input["schema_version"] = 2
        open(io -> TOML.print(io, input), input_path, "w")
        @test_throws ErrorException main(arguments)
        @test occursin("version-1", read(joinpath(output, "pscad-console.txt"), String))
    end
end
end

module PSCADProbeProtocol
using Test

const PYTHON_PROBE_FIXTURE = raw"""
import atexit
import runpy
import sys
import threading
import time
import types

source, host, port, limit, mode, trace = sys.argv[1:]
def shutdown():
    with open(trace + ".shutdown", "w") as stream:
        stream.write("interpreter shutdown")
atexit.register(shutdown)

def record(call):
    with open(trace, "a") as stream:
        stream.write(call + "\n")
    if mode == call:
        while True:
            time.sleep(1)
    if mode in ("error", "shutdown_error"):
        raise RuntimeError("synthetic remote-call failure")

class Application:
    __slots__ = ()
    def is_busy(self):
        record("is_busy")
        return mode == "shutdown_success"
    @property
    def version(self):
        record("version")
        return "5.1.0"

def connect(**kwargs):
    assert kwargs == {"host": host, "port": int(port), "timeout": float(limit)}
    if mode in ("shutdown_success", "shutdown_error"):
        threading.Thread(target=lambda: time.sleep(30), daemon=False).start()
    record("connect")
    if mode == "stderr_success":
        print("synthetic automation diagnostic", file=sys.stderr, flush=True)
    return Application()

mhi = types.ModuleType("mhi")
mhi.pscad = types.ModuleType("mhi.pscad")
mhi.pscad.connect = connect
sys.modules["mhi"] = mhi
sys.modules["mhi.pscad"] = mhi.pscad
sys.argv = [source, host, port, limit]
runpy.run_path(source, run_name="__main__")
"""

@testset "PSCAD responsiveness probe without station" begin
    python = ENV["JULIA_PYTHONCALL_EXE"]
    probe = normpath(joinpath(@__DIR__, "../../src/PSCAD/remote/probe.py"))
    for mode in ("success", "shutdown_success", "stderr_success",
        "connect", "is_busy", "version", "error",
        "shutdown_error")
        mktempdir() do root
            trace = joinpath(root, "calls.txt")
            console = joinpath(root, "pscad-probe.txt")
            command = `$python -u -c $PYTHON_PROBE_FIXTURE $probe 127.0.0.1 50000 1 $mode $trace`
            process = open(console, "w") do io
                run(pipeline(ignorestatus(command); stdout = io, stderr = io); wait = false)
            end
            try
                @test timedwait(() -> process_exited(process), 10) == :ok
            finally
                process_running(process) && kill(process)
                wait(process)
            end
            output = read(console, String)
            calls = readlines(trace)
            @test !isfile(trace * ".shutdown")
            @test occursin("Probing PSCAD on 127.0.0.1:50000 (limit=1 s)", output)
            if mode in ("success", "shutdown_success", "stderr_success")
                @test process.exitcode == 0
                @test calls == ["connect", "is_busy", "version"]
                busy = mode == "shutdown_success" ? "True" : "False"
                @test occursin("PSCAD remote calls answered: busy=$busy, version=5.1.0", output)
                @test !occursin("probe exceeded", output)
                @test occursin("synthetic automation diagnostic", output) ==
                      (mode == "stderr_success")
            elseif mode in ("error", "shutdown_error")
                @test process.exitcode == 1
                @test calls == ["connect"]
                @test occursin("synthetic remote-call failure", output)
                @test !occursin("probe exceeded", output)
            else
                @test process.exitcode == 124
                @test last(calls) == mode
                @test occursin("PSCAD remote-call probe exceeded 1 s", output)
                @test !occursin("PSCAD remote calls answered", output)
            end
        end
    end
end
end

module PSCADLifecycleProtocol
using Test, TOML

const POWERSHELL_LIFECYCLE_FIXTURE = raw"""
param([string] $Lifecycle, [string] $LocalCase, [string] $Mode, [string] $EntryPoint)
. $Lifecycle
$ownerPath = Join-Path $LocalCase "pscad-owner.txt"
$exe = Join-Path $LocalCase "Pscad.exe"
$created = [DateTime]::Parse("2026-10-08T12:00:00Z").ToUniversalTime()
Set-Content -LiteralPath $ownerPath -Value @(5308, $exe, 54330, $created.ToString('o'))
$application = [PSCustomObject] @{
    ProcessId = 5308
    ExecutablePath = $exe
    CommandLine = 'Pscad.exe /port:54330'
    CreationDate = $created
    ExecutionState = 3
}
if ($EntryPoint -eq 'runner') {
    $ownerPath = Join-Path $LocalCase 'owner.txt'
    $runner = "$LocalCase\invoke-runner.cmd"
    Set-Content -LiteralPath $ownerPath -Value @(5308, $runner)
    $application.CommandLine = $runner
} elseif ($EntryPoint -eq 'simulation') {
    $application.ExecutablePath = "$LocalCase\fixture.exe"
    Remove-Item -LiteralPath $ownerPath
}
$script:frames = @($application)
switch ($Mode) {
    'gone' { $script:frames = @($null) }
    'terminated' { $application.ExecutionState = 7; $script:frames += $null }
    'empty_executable' { $application.ExecutablePath = ''; $script:frames += $null }
    'empty_command' { $application.CommandLine = ' '; $script:frames += $null }
    'empty_creation' { $application.CreationDate = $null; $script:frames += $null }
    'persistent_empty' { $application.ExecutablePath = $null }
    'recovers' {
        $incomplete = [PSCustomObject] @{
            ProcessId = 5308; ExecutablePath = ''; CommandLine = 'Pscad.exe /port:54330'
            CreationDate = $created; ExecutionState = 3
        }
        $script:frames = @($incomplete, $application, $null)
    }
    'different_executable' { $application.ExecutablePath = Join-Path $LocalCase 'other.exe' }
    'different_creation' { $application.CreationDate = $created.AddSeconds(1) }
    'different_port' { $application.CommandLine = 'Pscad.exe /port:54331' }
    'stop_gone' { $script:frames += $null }
    'stop_throw_gone' { $script:frames += $null }
    'stop_exiting' {
        $script:frames += [PSCustomObject] @{
            ProcessId = 5308; ExecutablePath = ''; CommandLine = $null
            CreationDate = $null; ExecutionState = 7
        }
    }
    'stop_different_executable' {
        $script:frames += [PSCustomObject] @{
            ProcessId = 5308; ExecutablePath = 'other.exe'; CommandLine = 'other.exe'
            CreationDate = $created; ExecutionState = 3
        }
    }
    'stop_different_creation' {
        $script:frames += [PSCustomObject] @{
            ProcessId = 5308; ExecutablePath = $exe; CommandLine = 'Pscad.exe /port:54330'
            CreationDate = $created.AddSeconds(1); ExecutionState = 3
        }
    }
}
$script:queries = 0
$script:kills = 0
$script:afterStopQueries = 0
function Get-CimInstance {
    param([string] $ClassName, [string] $Filter)
    if ([string]::IsNullOrEmpty($Filter)) {
        if ($EntryPoint -eq 'simulation') { return $application }
        return
    }
    if ($ClassName -ne 'Win32_Process' -or $Filter -ne 'ProcessId = 5308') {
        throw "Unexpected process query: $ClassName $Filter"
    }
    if ($Mode -eq 'stop_delayed_gone') {
        $script:queries++
        if ($script:kills -eq 0) { return $application }
        $script:afterStopQueries++
        if ($script:afterStopQueries -le 2) { return $application }
        return
    }
    $index = [Math]::Min($script:queries, $script:frames.Count - 1)
    $script:queries++
    return $script:frames[$index]
}
function taskkill.exe {
    if (($args -join ' ') -ne '/PID 5308 /T /F') { throw "Unexpected stop: $args" }
    $script:kills++
    if ($Mode.StartsWith('stop_throw_')) { throw 'synthetic stop command failure' }
    if ($ErrorActionPreference -ne 'Continue') { throw 'Native command requires Continue' }
    Write-Output 'synthetic taskkill output'
    Write-Error 'synthetic taskkill stderr'
    $code = if ($Mode.StartsWith('stop_')) { 128 } else { 0 }
    $global:LASTEXITCODE = $code
}
$exitCode = 0
$caught = ''
try {
    # Represents a runner that has already returned a successful exit code.
    try {
    } finally {
        $grace = if ($Mode -eq 'stop_delayed_gone') { 2 } elseif ($Mode -eq 'matched' -or $Mode.StartsWith('stop_')) { 0 } elseif ($Mode -eq 'persistent_empty') { 1 } else { 2 }
        if ($EntryPoint -eq 'case') {
            Stop-PSCADCase -LocalCase $LocalCase -GraceSeconds $grace
        } elseif ($EntryPoint -eq 'runner') {
            Stop-OwnedRunner -OwnerPath $ownerPath -OwnedRoot $LocalCase -GraceSeconds $grace
        } elseif ($EntryPoint -eq 'simulation') {
            Stop-EMTDC -CaseDirectory $LocalCase -GraceSeconds $grace
        } else {
            Stop-OwnedPSCAD -OwnerPath $ownerPath -GraceSeconds $grace
        }
    }
} catch {
    $exitCode = 1
    $caught = $_.Exception.Message
    [Console]::Error.WriteLine($caught)
}
Set-Content -LiteralPath (Join-Path $LocalCase 'observed.toml') -Value @(
    "queries = $script:queries", "kills = $script:kills", "exit_code = $exitCode",
    "owner_exists = $((Test-Path -LiteralPath $ownerPath).ToString().ToLowerInvariant())",
    "caught = '$caught'"
)
exit $exitCode
"""

@testset "PSCAD owned-process cleanup without station" begin
    powershell = get(ENV, "POWERIMPEDANCE_PSCAD_TEST_POWERSHELL", "")
    if isempty(powershell)
        @test_skip "lifecycle protocol requires a local PowerShell interpreter"
    else
        lifecycle = normpath(joinpath(@__DIR__, "../../src/PSCAD/remote/lifecycle.ps1"))
        for entry in ("final", "case"),
            mode in ("gone", "terminated", "empty_executable", "empty_command",
                "empty_creation", "persistent_empty", "recovers", "different_executable",
                "different_creation", "different_port", "matched", "stop_gone", "stop_exiting",
                "stop_different_executable", "stop_different_creation", "stop_alive",
                "stop_throw_gone", "stop_throw_alive", "stop_delayed_gone")

            mktempdir() do root
                fixture = joinpath(root, "lifecycle-fixture.ps1")
                write(fixture, POWERSHELL_LIFECYCLE_FIXTURE)
                console = joinpath(root, "console.txt")
                command = `$powershell -NoLogo -NoProfile -NonInteractive -File $fixture -Lifecycle $lifecycle -LocalCase $root -Mode $mode -EntryPoint $entry`
                process = open(console, "w") do io
                    run(pipeline(ignorestatus(command); stdout = io, stderr = io); wait = false)
                end
                try
                    @test timedwait(() -> process_exited(process), 15) == :ok
                finally
                    process_running(process) && kill(process)
                    wait(process)
                end
                stop_failed = mode in ("stop_alive", "stop_throw_alive")
                @test process.exitcode == Int(stop_failed)
                observed = TOML.parsefile(joinpath(root, "observed.toml"))
                @test observed["exit_code"] == Int(stop_failed)
                @test observed["owner_exists"] == stop_failed
                @test observed["kills"] ==
                      Int(mode == "matched" || startswith(mode, "stop_"))
                expected_queries = entry == "final" && mode == "recovers" ? 3 :
                                   startswith(mode, "stop_") ? 2 :
                                   entry == "final" &&
                                   mode in ("terminated", "empty_executable",
                    "empty_command", "empty_creation", "persistent_empty") ? 2 : 1
                @test observed["queries"] >= expected_queries
                console_text = read(console, String)
                killed = mode == "matched" || startswith(mode, "stop_")
                @test occursin("taskkill PID=5308 exit code=", console_text) == killed
                if killed && !startswith(mode, "stop_throw_")
                    @test occursin("synthetic taskkill output", console_text)
                    @test occursin("synthetic taskkill stderr", console_text)
                    @test isfile(joinpath(root, "result", "taskkill-5308-stdout.txt"))
                    @test isfile(joinpath(root, "result", "taskkill-5308-stderr.txt"))
                end
                mode == "stop_delayed_gone" && @test observed["queries"] >= 5
                mismatch = mode in
                           ("different_executable", "different_creation", "different_port",
                    "stop_different_executable", "stop_different_creation")
                @test occursin("Warning: PID 5308", console_text) == mismatch
                @test occursin("no longer belongs to the recorded owned PSCAD", console_text) ==
                      (mode in ("different_executable", "different_creation",
                    "stop_different_executable", "stop_different_creation"))
                @test occursin("Could not stop owned PSCAD process tree 5308", observed["caught"]) ==
                      stop_failed
            end
        end
        for entry in ("runner", "simulation"),
            mode in ("matched", "stop_delayed_gone", "stop_alive")

            mktempdir() do root
                fixture = joinpath(root, "lifecycle-fixture.ps1")
                write(fixture, POWERSHELL_LIFECYCLE_FIXTURE)
                console = joinpath(root, "console.txt")
                command = `$powershell -NoLogo -NoProfile -NonInteractive -File $fixture -Lifecycle $lifecycle -LocalCase $root -Mode $mode -EntryPoint $entry`
                process = open(console, "w") do io
                    run(pipeline(ignorestatus(command); stdout = io, stderr = io); wait = false)
                end
                try
                    @test timedwait(() -> process_exited(process), 15) == :ok
                finally
                    process_running(process) && kill(process)
                    wait(process)
                end
                @test process.exitcode == Int(mode == "stop_alive")
                observed = TOML.parsefile(joinpath(root, "observed.toml"))
                @test observed["kills"] == 1
                mode == "stop_delayed_gone" && @test observed["queries"] >= 3
                @test occursin("synthetic taskkill stderr", read(console, String))
                @test occursin("Could not stop", observed["caught"]) ==
                      (mode == "stop_alive")
            end
        end
    end
end
end

module PSCADSupervisorProtocol
using Test, TOML

const POWERSHELL_SUPERVISOR_FIXTURE = raw"""
param([string] $Supervisor, [string] $Lifecycle, [string] $Root, [string] $Python, [string] $Mode)
$shared = Join-Path $Root 'shared'
$local = Join-Path $Root 'scratch'
$toolkit = Join-Path $shared 'toolkit'
$harness = Join-Path $Root 'harness'
New-Item -ItemType Directory -Path $toolkit, $harness -Force | Out-Null
Copy-Item -LiteralPath $Supervisor -Destination (Join-Path $harness 'supervisor.ps1')
# The actual supervisor runs with local process and Windows service mocks.
Set-Content -LiteralPath (Join-Path $harness 'lifecycle.ps1') -Value @'
. $Lifecycle
$script:cleanupCalls = [Collections.Generic.List[string]]::new()
$script:emtdcCalls = 0
function Get-CimInstance { return }
function Get-NetTCPConnection {
    # Simulate the ownership recorded by a successful desktop start.
    $script:pscadOwned = $Mode -ne 'stderr_success'
    [PSCustomObject] @{ OwningProcess = 17284 }
}
function Stop-EMTDC {
    param([string] $CaseDirectory)
    $script:cleanupCalls.Add('EMTDC')
    $script:emtdcCalls++
    if ($script:emtdcCalls -gt 1 -and $Mode -eq 'probe_failure_cleanup_failure') {
        throw 'synthetic EMTDC cleanup failure'
    }
}
function Stop-OwnedPSCAD {
    param([string] $OwnerPath, [int] $GraceSeconds)
    $script:cleanupCalls.Add('PSCAD')
    if ($script:pscadOwned) { throw 'synthetic owned PSCAD cleanup failure' }
}
function Stop-OwnedRunner {
    param([string] $OwnerPath, [string] $OwnedRoot)
    $script:cleanupCalls.Add('runner')
    if ($Mode -eq 'runner_primary_cleanup_failure' -and (Test-Path -LiteralPath $OwnerPath)) { throw 'synthetic runner cleanup failure' }
}
function Start-Process {
    param($FilePath, $ArgumentList, [switch] $PassThru, $WindowStyle)
    Set-Content -LiteralPath (Join-Path $LocalCase 'result/exit-code.txt') -Value '0'
    Set-Content -LiteralPath (Join-Path $LocalCase 'result/stdout.txt') -Value 'mock runner completed'
    Set-Content -LiteralPath (Join-Path $LocalCase 'result/stderr.txt') -Value ''
    Set-Content -LiteralPath (Join-Path $SharedCase 'runner-started.txt') -Value 'started'
    $process = [PSCustomObject] @{ Id = 42; HasExited = $Mode -ne 'runner_primary_cleanup_failure' }
    $process | Add-Member ScriptMethod WaitForExit { return }
    $process | Add-Member ScriptMethod Refresh { throw 'synthetic primary runner failure' }
    return $process
}
function Copy-Result {
    param([string] $Source, [string] $Destination)
    $script:cleanupCalls.Add('copy')
    if ($Mode -eq 'probe_failure_cleanup_failure') { throw 'synthetic output copy failure' }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
}
function Remove-Item {
    param([string] $LiteralPath, [switch] $Recurse, [switch] $Force, $ErrorAction)
    # Record all cleanup attempts even if earlier steps failed.
    if ($LiteralPath.EndsWith('owner.txt')) {
        Set-Content -LiteralPath (Join-Path $SharedCase 'cleanup.txt') -Value $script:cleanupCalls
    }
    Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
}
'@
# Override Copy-Result after the supervisor has defined it, at the first port query.
$wrapper = Get-Content -LiteralPath (Join-Path $harness 'lifecycle.ps1') -Raw
$wrapper = $wrapper.Replace('function Get-NetTCPConnection {', @'
function Get-NetTCPConnection {
    Set-Item Function:script:Copy-Result -Value {
        param([string] $Source, [string] $Destination)
        $script:cleanupCalls.Add('copy')
        if ($Mode -eq 'probe_failure_cleanup_failure') { throw 'synthetic output copy failure' }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
    }
'@)
Set-Content -LiteralPath (Join-Path $harness 'lifecycle.ps1') -Value $wrapper
Set-Content -LiteralPath (Join-Path $toolkit 'runner.jl') -Value '# mock runner'
Set-Content -LiteralPath (Join-Path $toolkit 'Project.toml') -Value ''
Set-Content -LiteralPath (Join-Path $shared 'generated.pscx') -Value 'fixture'
$probeExit = if ($Mode -eq 'probe_failure_cleanup_failure') { 1 } else { 0 }
Set-Content -LiteralPath (Join-Path $toolkit 'probe.py') -Value @(
    'import os, sys',
    'print("PSCAD remote calls answered: busy=True, version=5.1.0", flush=True)',
    'print("synthetic native stderr", file=sys.stderr, flush=True)',
    "os._exit($probeExit)"
)
& (Join-Path $harness 'supervisor.ps1') -SharedCase $shared -LocalCase $local -RemoteRoot $Root -Julia $Python -Python $Python -ProjectName fixture -OutputStem pi -PSCADVersion 5.1.0 -PSCADPort 54330 -Verbosity 0 -TimeoutSeconds 5
exit $LASTEXITCODE
"""

const POWERSHELL_CASE_FAILURE_FIXTURE = raw"""
param([string] $Lifecycle, [string] $Root, [string] $Python)
. $Lifecycle
$ErrorActionPreference = 'Stop'
$stdout = Join-Path $Root 'native-stdout.txt'
$stderr = Join-Path $Root 'native-stderr.txt'
$code = Invoke-PSCADNative -Executable $Python -Arguments @('-c', 'import sys; print("Pscad.exe"); print("synthetic find_exe stderr", file=sys.stderr)') -StdoutPath $stdout -StderrPath $stderr
if ($code -ne 0 -or $ErrorActionPreference -ne 'Stop') { throw 'Native invocation changed caller error handling' }
$script:stages = [Collections.Generic.List[string]]::new()
function Stop-OwnedRunner { $script:stages.Add('runner'); throw 'primary runner stop failure' }
function Stop-EMTDC { $script:stages.Add('EMTDC'); throw 'secondary EMTDC stop failure' }
function Stop-OwnedPSCAD { $script:stages.Add('PSCAD'); throw 'secondary PSCAD stop failure' }
try {
    Stop-PSCADCase -LocalCase $Root
    throw 'Expected cleanup failure'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    Set-Content -LiteralPath (Join-Path $Root 'stages.txt') -Value $script:stages
}
"""

@testset "PSCAD supervisor primary errors and native stderr without station" begin
    powershell = get(ENV, "POWERIMPEDANCE_PSCAD_TEST_POWERSHELL", "")
    if isempty(powershell)
        @test_skip "supervisor protocol requires a local PowerShell interpreter"
    else
        supervisor = normpath(joinpath(@__DIR__, "../../src/PSCAD/remote/supervisor.ps1"))
        lifecycle = normpath(joinpath(@__DIR__, "../../src/PSCAD/remote/lifecycle.ps1"))
        python = ENV["JULIA_PYTHONCALL_EXE"]
        for mode in ("stderr_success", "probe_failure_cleanup_failure", "runner_primary_cleanup_failure")
            mktempdir() do root
                fixture = joinpath(root, "supervisor-fixture.ps1")
                write(fixture, POWERSHELL_SUPERVISOR_FIXTURE)
                console = joinpath(root, "console.txt")
                command = `$powershell -NoLogo -NoProfile -NonInteractive -File $fixture -Supervisor $supervisor -Lifecycle $lifecycle -Root $root -Python $python -Mode $mode`
                process = open(console, "w") do io
                    run(pipeline(ignorestatus(command); stdout = io, stderr = io); wait = false)
                end
                try
                    @test timedwait(() -> process_exited(process), 15) == :ok
                finally
                    process_running(process) && kill(process)
                    wait(process)
                end
                text = read(console, String)
                @test process.exitcode == Int(mode != "stderr_success")
                shared = joinpath(root, "shared")
                @test isfile(joinpath(shared, "runner-started.txt")) ==
                      (mode != "probe_failure_cleanup_failure")
                if mode != "probe_failure_cleanup_failure"
                    output = joinpath(shared, "outputs")
                    @test occursin("PSCAD remote calls answered",
                        read(joinpath(output, "pscad-probe.txt"), String))
                    @test occursin("synthetic native stderr",
                        read(joinpath(output, "pscad-probe-stderr.txt"), String))
                end
                stages = readlines(joinpath(shared, "cleanup.txt"))
                @test stages[end] == "copy"
                if mode == "stderr_success"
                    @test !occursin("Cleanup failure:", text)
                    @test !occursin("not answering remote calls", text)
                else
                    primary = mode == "probe_failure_cleanup_failure" ?
                              "PSCAD on port 54330 is not answering remote calls within 60 s" :
                              "synthetic primary runner failure"
                    primary_at = findfirst(primary, text)
                    cleanup_at = findfirst("Cleanup failure:", text)
                    @test primary_at !== nothing
                    @test cleanup_at !== nothing
                    @test first(primary_at) < first(cleanup_at)
                    @test occursin("synthetic owned PSCAD cleanup failure", text)
                    @test "PSCAD" in stages
                    if mode == "probe_failure_cleanup_failure"
                        @test occursin("synthetic EMTDC cleanup failure", text)
                        @test occursin("synthetic output copy failure", text)
                    else
                        @test occursin("synthetic runner cleanup failure", text)
                        @test "runner" in stages
                    end
                end
            end
        end
        mktempdir() do root
            fixture = joinpath(root, "case-failure-fixture.ps1")
            write(fixture, POWERSHELL_CASE_FAILURE_FIXTURE)
            console = joinpath(root, "console.txt")
            command = `$powershell -NoLogo -NoProfile -NonInteractive -File $fixture -Lifecycle $lifecycle -Root $root -Python $python`
            process = open(console, "w") do io
                run(pipeline(ignorestatus(command); stdout = io, stderr = io); wait = false)
            end
            try
                @test timedwait(() -> process_exited(process), 15) == :ok
            finally
                process_running(process) && kill(process)
                wait(process)
            end
            @test process.exitcode == 0
            @test readlines(joinpath(root, "stages.txt")) == ["runner", "EMTDC", "PSCAD"]
            text = read(console, String)
            @test first(findfirst("primary runner stop failure", text)) <
                  first(findfirst("secondary EMTDC stop failure", text)) <
                  first(findfirst("secondary PSCAD stop failure", text))
            @test occursin("Pscad.exe", read(joinpath(root, "native-stdout.txt"), String))
            @test occursin("synthetic find_exe stderr", read(joinpath(root, "native-stderr.txt"), String))
        end
    end
end
end

module PSCADSupervisorErrorProtocol
using Test

Base.include(@__MODULE__, joinpath(@__DIR__, "../../src/PSCAD/remote/remote.jl")) do expression
    expression isa Expr && expression.head === :function && expression.args[1] isa Expr &&
    expression.args[1].head === :call &&
    expression.args[1].args[1] === :_supervisor_errors ?
    expression : nothing
end

@testset "PSCAD supervisor error stream without station" begin
    mktempdir() do root
        stderr = joinpath(root, "transport-stderr.txt")
        @test _supervisor_errors(stderr) == ""
        write(stderr,
            "#< CLIXML\n" *
            "<Objs xmlns=\"http://schemas.microsoft.com/powershell/2004/04\">" *
            "<S S=\"Information\">ignored</S>" *
            "<S S=\"Error\">PSCAD on port 54330 is not answering._x000D__x000A_</S>" *
            "<S N=\"message\" S=\"Error\">Check &lt;desktop&gt; &amp; &quot;session&quot;._x000D__x000A_</S></Objs>")
        @test _supervisor_errors(stderr) ==
              "PSCAD on port 54330 is not answering.\nCheck <desktop> & \"session\"."
        write(stderr, "#< CLIXML\n<Objs><S S=\"Progress\">ignored</S></Objs>")
        @test _supervisor_errors(stderr) == ""
        write(stderr, "plain supervisor error\n")
        @test _supervisor_errors(stderr) == "plain supervisor error"
    end
end
end

module PSCADIdentityProtocol
using Test, PythonCall

@testset "PSCAD identity source with mock installation" begin
    mktempdir() do root
        executable = joinpath(mkpath(joinpath(root, "bin", "win64")), "Pscad.exe")
        write(executable, "fixture executable")
        write(joinpath(root, "master.pslx"), "fixture master library")
        globals = pydict()
        globals["EXECUTABLE"] = executable
        globals["IDENTITY_SOURCE"] = normpath(joinpath(@__DIR__, "../../src/PSCAD/remote/identity.py"))
        pyexec(
            raw"""
import hashlib
import importlib.metadata
import runpy
import sys
import types

common = types.ModuleType("mhi.common")
common.process = types.SimpleNamespace(find_exe=lambda *args, **kw: EXECUTABLE)
sys.modules["mhi.common"] = common
# Use the original reader, rather than the runner fixture's identity replacement.
import mhi.pscad
original_reader = runpy._pi_original_run_path
identity_function = original_reader(IDENTITY_SOURCE)["identify"]
closed = []
launches = []
def unexpected_launch(**kw):
    launches.append(kw)
    raise RuntimeError("attached identity must not launch")
mhi.pscad.launch = unexpected_launch
app = types.SimpleNamespace(version="5.1.0", _settings=lambda kw: {"fortran_version": "GF81x64"},
                            settings=lambda: {"fortran_version": "GFortran 8.1 (64-bit)"},
                            quit=lambda: closed.append(True))
observed = identity_function("5.1.0", app)
""", globals)
        observed = pyconvert(Dict{String, String}, globals["observed"])
        @test observed["schema"] == "2"
        @test observed["fortran_version"] == "GF81x64"
        @test observed["pscad_path"] == executable
        @test occursin(r"^[0-9a-f]{64}$", observed["pscad_sha256"])
        @test occursin(r"^[0-9a-f]{64}$", observed["master_library_sha256"])
        @test !haskey(observed, "line_constants_sha256")
        pyexec(raw"""
def detected_software_error():
    raise SystemError("Unable to retrieve detected software")
app.settings = detected_software_error
observed = identity_function("5.1.0", app)
""", globals)
        @test pyconvert(String, globals["observed"]["fortran_version"]) == "GF81x64"
        pyexec(raw"""
app._settings = lambda kw: {}
observed = identity_function("5.1.0", app)
""", globals)
        @test pyconvert(String, globals["observed"]["fortran_version"]) == "unknown"
        pyexec(raw"""
def settings_error(kw):
    raise RuntimeError("station settings unavailable")
app._settings = settings_error
observed = identity_function("5.1.0", app)
""", globals)
        @test pyconvert(String, globals["observed"]["fortran_version"]) == "unknown"
        @test pyconvert(Int, pybuiltins.len(globals["closed"])) == 0
        @test pyconvert(Int, pybuiltins.len(globals["launches"])) == 0
        pyexec(raw"""
session_app = types.SimpleNamespace(version="5.1.0",
    _settings=lambda kw: {"fortran_version": "GF81x64"},
    settings=detected_software_error, quit=lambda: closed.append(True))
def launch_session(**kw):
    launches.append(kw)
    return session_app
mhi.pscad.launch = launch_session
launch_identity = identity_function("5.1.0")
""", globals)
        @test pyconvert(Dict{String, String}, globals["launch_identity"]) == observed
        @test pyconvert(Int, pybuiltins.len(globals["launches"])) == 1
        @test pyconvert(Int, pybuiltins.len(globals["closed"])) == 1
        @test_throws PyException globals["identity_function"]("5.0.2", globals["app"])
    end
end
end
