module PSCADResultsTests
using Test, PowerImpedance
const P = PowerImpedance.PSCAD
const FIXTURES = normpath(joinpath(@__DIR__, "../data/pscad"))
using ..PSCADFixtures: small_ac_network

function synthetic_result(time, channels; probes = P.ProbeManifest(), frequency = 50.0)
    settings = P.SimulationSettings(frequency = frequency, sample_step = 250e-6)
    return PSCADResult(PSCADRun(), time, channels, probes, settings, (;), (;))
end

function add_three_phase!(channels, name, times, phasor; negative = 0.0im, frequency = 50.0)
    for index in 1:3
        phase = cis(-2π * (index - 1) / 3)
        channels["$name:$index"] = real.((phasor * phase + negative / phase) .*
                                         cis.(2π * frequency .* times))
    end
end

@testset "PSCAD settled phasors" begin
    # Nonzero time origin detects a DFT that substitutes sample indices for
    # actual times. A large negative sequence must disappear from X_+.
    times = collect(range(0.0032; step = 250e-6, length = 1201))
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    add_three_phase!(channels, "V_B1", times, 125 * cis(0.42); negative = 80 * cis(-0.7))
    channels["scalar"] = 2.5 .+ 0.4 .* cos.(2π * 50 .* times)
    result = synthetic_result(times, channels)
    settled = P.steady_state(result)
    @test collect(keys(settled)) == ["V_B1", "scalar"]
    @test settled["V_B1"].dim == 3
    @test isapprox(settled["V_B1"].peak, 125; rtol = 1e-12)
    @test isapprox(settled["V_B1"].rms, 125 / sqrt(2); rtol = 1e-12)
    @test isapprox(settled["V_B1"].angle, 0.42; atol = 1e-12)
    @test settled["scalar"].dim == 1
    @test isapprox(settled["scalar"].mean, 2.5; atol = 1e-12)
    @test isapprox(P.steady_state(result; window_cycles = 1)["V_B1"].angle, 0.42; atol = 1e-12)
    # Fewer than ten cycles are acceptable if a complete cycle exists.
    short_times = times[1:81]
    short_channels = PowerImpedance.OrderedDict(name => values[1:81]
    for (name, values) in channels)
    @test isapprox(
        P.steady_state(synthetic_result(short_times, short_channels))["V_B1"].peak,
        125; rtol = 1e-12)
    incomplete = copy(channels)
    delete!(incomplete, "V_B1:2")
    @test_throws ArgumentError P.steady_state(synthetic_result(times, incomplete))
    for invalid in (0, -1, 1.5, true)
        @test_throws ArgumentError P.steady_state(result; window_cycles = invalid)
    end
    irregular = copy(times)
    irregular[100] += 1e-6
    @test_throws ArgumentError P.steady_state(synthetic_result(irregular, channels))
    noninteger = collect(range(0.0; step = 270e-6, length = length(times)))
    @test_throws ArgumentError P.steady_state(synthetic_result(noninteger, channels))
    @test_throws ArgumentError P.steady_state(synthetic_result(times[1:80],
        PowerImpedance.OrderedDict(name => values[1:80] for (name, values) in channels)))
    @test P._probe_present(
        P.ProbeChannel(
            "V_B1", :voltage, "B1", nothing, nothing, 3, "kV"), channels)
    @test !P._probe_present(
        P.ProbeChannel(
            "V_B1", :voltage, "B1", nothing, nothing, 3, "kV"), incomplete)
    @test P._probe_present(
        P.ProbeChannel(
            "scalar", :voltage, "B1", nothing, nothing, 1, "kV"), channels)
end

@testset "PSCAD operating-point comparison" begin
    classic, state = small_ac_network()
    netlist = P.netlist(classic, power_flow(classic))
    plan = P.build_plan(netlist)
    model = PSCADModel("synthetic.pscx", "synthetic", netlist, plan.probes,
        P.SimulationSettings(), netlist.operating_point, (source = :fixture,))
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    # Independent circuit solution in phase RMS kV and kA. Shift the entire
    # PSCAD voltage reference to verify relative-angle comparison.
    source_voltage = 380 / sqrt(3)
    impedance_value = 0.19 + 2π * 50 * 0.0122im
    current = source_voltage / (400 + impedance_value)
    receiving_voltage = 400 * current
    offset = cis(0.52)
    add_three_phase!(channels, "V_B1", times, sqrt(2) * source_voltage * offset)
    add_three_phase!(channels, "V_B2", times, sqrt(2) * receiving_voltage * offset)
    for name in ("I_source_1", "I_line_1", "I_line_2", "I_load_1")
        add_three_phase!(channels, name, times, sqrt(2) * current * offset)
    end
    result = synthetic_result(times, channels; probes = plan.probes)
    comparison = compare_operating_point(result, model)
    @test length(comparison) == 7
    @test all(comparison.within_tolerance)
    @test maximum(comparison.error) < 1e-7
    @test count(==(:voltage_rms), comparison.quantity) == 2
    @test count(==(:voltage_angle), comparison.quantity) == 1
    @test count(==(:current_rms), comparison.quantity) == 4
    @test only(comparison.name[comparison.quantity .== :voltage_angle]) == "V_B2"
    @test isapprox(
        only(comparison.pscad[(comparison.quantity .== :current_rms) .& (comparison.name .== "I_load_1")]),
        abs(current); rtol = 1e-12)
    @test isapprox(abs(receiving_voltage) * sqrt(3), 379.80216745; atol = 1e-7)
    @test isapprox(abs(current), 0.548197209; atol = 1e-9)
    doubled = deepcopy(channels)
    for index in 1:3
        doubled["I_line_2:$index"] .*= 2
    end
    failed = compare_operating_point(synthetic_result(times, doubled), model)
    @test failed.name[.!failed.within_tolerance] == ["I_line_2"]
    # The two terminal power records must remain distinct, including receiving
    # reactive power. These independent records deliberately differ.
    flows = copy(model.operating_point.branch_flows)
    flows[:line] = (pf = 120.0, qf = 30.0, pt = -90.0, qt = -40.0)
    point = P.OperatingPointRecord(model.operating_point.bus_states, flows,
        model.operating_point.setpoints, model.operating_point.slack_bus, model.operating_point.bases)
    sides_model = PSCADModel(model.project_path, model.project_name, model.netlist,
        model.probes, model.settings, point, model.provenance)
    sides = compare_operating_point(result, sides_model)
    @test only(sides.powerflow[sides.name .== "I_line_1"]) ==
          hypot(120, 30) / (3 * source_voltage)
    @test only(sides.powerflow[sides.name .== "I_line_2"]) ==
          hypot(90, 40) / (3 * (netlist.buses[2].vm_pu * netlist.buses[2].base_kV))
    voltage_manifest = P.ProbeManifest(filter(c -> c.kind == :voltage, model.probes.channels), "B1")
    voltage_model = PSCADModel(model.project_path, model.project_name, model.netlist,
        voltage_manifest, model.settings, model.operating_point, model.provenance)
    @test length(compare_operating_point(result, voltage_model)) == 3
    missing = copy(channels)
    delete!(missing, "V_B1:3")
    @test_throws ArgumentError compare_operating_point(synthetic_result(times, missing), model)
    plain = P.netlist(state, nothing)
    no_pf = PSCADModel("synthetic.pscx", "synthetic", plain, plan.probes,
        model.settings, plain.operating_point, (;))
    @test_throws ArgumentError compare_operating_point(result, no_pf)
    delete!(flows, :line)
    @test_throws ArgumentError compare_operating_point(result, sides_model)
    @test_throws ArgumentError compare_operating_point(result, model; rtol_v = -1)
end

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
