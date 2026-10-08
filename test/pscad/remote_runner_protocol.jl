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
