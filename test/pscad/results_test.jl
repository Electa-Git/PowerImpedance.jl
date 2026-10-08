module PSCADResultsTests
using Test, PowerImpedance
const P = PowerImpedance.PSCAD
const FIXTURES = normpath(joinpath(@__DIR__, "../data/pscad"))

@testset "PSCAD settings and existing-project types" begin
    settings = P.SimulationSettings()
    @test settings.simulation_time == 2.0
    @test settings.time_step == 10e-6
    @test settings.sample_step == 100e-6
    @test settings.snapshot_time === nothing
    @test settings.output_stem == "pi"
    @test settings.frequency == 50.0
    @test settings.source_ramp == 0.05
    for field in (:simulation_time, :time_step, :sample_step, :frequency, :source_ramp),
        value in (0, -1, Inf, NaN, true)

        @test_throws ArgumentError P.SimulationSettings(; (field => value,)...)
    end
    for value in (0, -1, 3.0, Inf, NaN, true)
        @test_throws ArgumentError P.SimulationSettings(snapshot_time = value)
    end
    @test P.SimulationSettings(snapshot_time = 2).snapshot_time == 2.0
    @test_throws ArgumentError P.SimulationSettings(sample_step = 1e-6)
    for value in ("", "1bad", "bad-stem", repeat("a", 21), "café", "pi/escape")
        @test_throws ArgumentError P.SimulationSettings(output_stem = value)
    end
    @test isempty(P.ProbeManifest().channels)
    @test PSCADRun() isa AbstractFormulation
    @test PSCADRun().backend === P.PSCADBackend
    @test PowerImpedance._default_backend(PSCADRun) === P.PSCADBackend
    mktempdir() do root
        path = joinpath(root, "handbuilt.pscx")
        write(path, "fixture")
        model = PSCADModel(path)
        @test model.project_path == path
        @test model.project_name == "handbuilt"
        @test model.netlist === nothing
        @test model.operating_point === nothing
        @test model.provenance == (source = :file,)
        @test_throws ArgumentError PSCADModel(path * "missing")
        other = joinpath(root, "bad.txt")
        write(other, "fixture")
        @test_throws ArgumentError PSCADModel(other)
    end
end

@testset "PSCAD INF and legacy output parser" begin
    expected = ["V_BUS:1", "V_BUS:2", "Voltage", "right:Voltage", "Repeated",
        "main:Repeated", "Café", "main:Repeated:2", "C9", "C10", "C11", "C12"]
    @test P.parse_inf(joinpath(FIXTURES, "fixture.inf")) == expected
    result = read_pscad_output(FIXTURES; stem = "fixture")
    @test result.time == [0.0, 0.25, 0.5]
    @test collect(keys(result.channels)) == expected
    @test result.channels["C12"] == [12.0, 112.0, 212.0]
    @test result.channels["V_BUS:1"] == [1.0, 101.0, 201.0]
    @test basename.(result.outs) == ["fixture_01.out", "fixture_02.out"]
    @test P._data_rows(first(result.outs)) == 3
    for (text, value) in ((".5D+1", 5.0), ("-.5d+1", -5.0), ("1.25-02", 0.0125))
        @test P._pscad_number(text) == value
    end
    @test_throws ArgumentError P._pscad_number("invalid")
    @test_throws ArgumentError read_pscad_output(FIXTURES; stem = "malformed")
    mktempdir() do root
        for name in ("fixture.inf", "fixture_01.out", "fixture_02.out")
            cp(joinpath(FIXTURES, name), joinpath(root, name))
        end
        @test P._wait_outputs(
            [root, root], "fixture", 3; timeout = 1, poll_interval = 0.01).outs ==
              [joinpath(root, basename(path)) for path in result.outs]
        original = read(joinpath(root, "fixture_02.out"), String)
        for text in ("0 11 12\n0.25 111 112\n", "0 11 12\n0 111 112\n0.5 211 212\n",
            "0 11 12\n0.25 Inf 112\n0.5 211 212\n", "0 11\n0.25 111 112\n0.5 211 212\n",
            "0 11 12\n0.3 111 112\n0.5 211 212\n")
            write(joinpath(root, "fixture_02.out"), text)
            @test_throws ArgumentError read_pscad_output(root; stem = "fixture")
        end
        write(joinpath(root, "fixture_02.out"), original)
        duplicate = mkpath(joinpath(root, "duplicate"))
        cp(joinpath(root, "fixture.inf"), joinpath(duplicate, "fixture.inf"))
        @test_throws ArgumentError P._wait_outputs(
            [root], "fixture", 3; timeout = 0.1, poll_interval = 0.01)
        rm(duplicate; recursive = true)
        rm(joinpath(root, "fixture_02.out"))
        @test_throws ArgumentError read_pscad_output(root; stem = "fixture")
        caught = try
            P._wait_outputs([root], "fixture", 3; timeout = 0.05, poll_interval = 0.01)
        catch error
            error
        end
        @test caught isa ArgumentError
        @test occursin("OUT files found", sprint(showerror, caught))
        @test occursin("rows per file", sprint(showerror, caught))
        @test occursin("[3]", sprint(showerror, caught))
    end
end
end
