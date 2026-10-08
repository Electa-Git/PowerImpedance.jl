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
    def __init__(self):
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
        if os.environ.get("PI_RUNNER_MODE") == "run_error":
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
    def __init__(self):
        self._project = Project()
        self.closed = False
        self.loaded_path = None

    def licensed(self):
        return os.environ.get("PI_RUNNER_MODE") != "license"

    def load(self, path):
        self.loaded_path = path

    def project(self, name):
        if name != os.path.splitext(os.path.basename(self.loaded_path))[0]:
            raise RuntimeError("unknown project " + name)
        return self._project

    def projects(self):
        return ["generated"]

    def _settings(self, updates):
        return {"fortran_version": "fixture-fortran"}

    def quit(self):
        self.closed = True

pscad = types.ModuleType("mhi.pscad")
def launch(**kwargs):
    global LAST_APP, LAST_LAUNCH
    LAST_LAUNCH = kwargs
    LAST_APP = Application()
    return LAST_APP
pscad.launch = launch
mhi = types.ModuleType("mhi")
mhi.pscad = pscad
sys.modules["mhi"] = mhi
sys.modules["mhi.pscad"] = pscad
importlib.metadata.version = lambda name: "3.1.2" if name == "mhi.pscad" else "fixture"
ORIGINAL_RUN_PATH = runpy.run_path
runpy._pi_original_run_path = ORIGINAL_RUN_PATH
runpy.run_path = lambda path: {"identify": lambda version, app: dict(IDENTITY)}
"""

function runner_arguments(directory, output; verbosity = "0", snapshot = false)
    project = joinpath(directory, "generated.pscx")
    write(project, "fixture")
    settings = Dict{String, Any}("time_duration" => 0.0005, "time_step_us" => 50.0,
        "sample_step_us" => 250.0, "output_stem" => "fixture", "plot_type" => "OUT")
    snapshot && (settings["snapshot_time"] = 0.00025)
    input = Dict("schema_version" => 1, "project_name" => "generated", "settings" =>
        settings)
    open(io -> TOML.print(io, input; sorted = true), joinpath(directory, "computation.toml"), "w")
    return [project, output, "generated", "fixture", "5.1.0", verbosity]
end

function mock_environment(f, root; mode = "success")
    environment = pyimport("os").environ
    environment["PI_RUNNER_TEMP"] = joinpath(root, "compiler-temp")
    environment["PI_RUNNER_MODE"] = mode
    try
        f()
    finally
        environment.pop("PI_RUNNER_TEMP", nothing)
        environment.pop("PI_RUNNER_MODE", nothing)
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
            @test !isfile(joinpath(output, "fixture_01.out"))
            if mode == "build_error"
                @test occursin("error\tBuild\tgenerated", read(joinpath(output, "build-messages.txt"), String))
            elseif mode == "readback"
                @test TOML.parsefile(joinpath(output, "settings-readback.toml"))["time_step"]["observed"] ==
                      -1
            end
        end
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
original_reader = runpy._pi_original_run_path
identity_function = original_reader(IDENTITY_SOURCE)["identify"]
closed = []
app = types.SimpleNamespace(version="5.1.0", _settings=lambda kw: {"fortran_version": "GF81x64"},
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
app._settings = lambda kw: {"Fortran Selection": "raw-selection"}
observed = identity_function("5.1.0", app)
""", globals)
        @test pyconvert(String, globals["observed"]["fortran_version"]) == "raw-selection"
        pyexec(raw"""
def settings_error(kw):
    raise RuntimeError("station settings unavailable")
app._settings = settings_error
observed = identity_function("5.1.0", app)
""", globals)
        @test pyconvert(String, globals["observed"]["fortran_version"]) == "unknown"
        @test pyconvert(Int, pybuiltins.len(globals["closed"])) == 0
        pyexec(raw"""
import mhi.pscad
mhi.pscad.launch = lambda **kw: app
observed = identity_function("5.1.0")
""", globals)
        @test pyconvert(Int, pybuiltins.len(globals["closed"])) == 1
        @test_throws PyException globals["identity_function"]("5.0.2", globals["app"])
    end
end
end
