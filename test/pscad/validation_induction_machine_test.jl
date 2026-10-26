module PSCADValidationInductionMachineTests
using Test, PowerImpedance, LinearAlgebra, TOML
using ..PSCADValidationTests: V, phase_wave
const P = PowerImpedance.PSCAD

@testset "Induction-machine circuit, SI reference and scan settings" begin
    parent = V.PSCADFixtures.im_network()
    net = V.fixture("induction_machine").factory()
    names = Dict(:im1 => :DUT, :imp => :Grid, :g1 => :G3)
    @test net.options == parent.options
    @test Set(keys(net.elements)) == Set(values(names))
    for (name, element) in pairs(parent.elements)
        actual = net.elements[names[name]]
        @test repr(actual) == repr(element)
        @test inputvalues(actual) == inputvalues(element)
        @test V.component_nets(net, names[name]) == V.component_nets(parent, name)
    end
    list = V.fixture_netlist(net, compute(PowerFlowProblem(net), ACDCPowerFlow()))
    spec, reference = V.applicable_scan("induction_machine", net, list)
    dut = net.elements[:DUT]
    bases = V.device_bases(dut.elec, dut.bases)
    @test bases.ac_voltage ≈ 220sqrt(2 / 3)
    @test bases.ac_current ≈ 1000sqrt(2) / (sqrt(3) * 220)
    @test bases.ac_current / bases.ac_voltage ≈ 1000 / 220^2
    @test spec.protocol == "dq_active" && spec.drive == "current" && spec.quantity == "Y"
    @test spec.currents == [("DUT", "ac")] && spec.axes == ["p1_d", "p1_q"]
    @test !spec.dc_clamped && spec.dc_voltage_base_kV === nothing
    @test length(spec.frequencies) == 29 && issorted(spec.frequencies)
    @test all(f -> f in spec.frequencies, (0.5, 1.5, 48.0, 49.0, 51.0, 52.0, 1000.0))
    @test 50.0 ∉ spec.frequencies
    @test spec.tone_peak_pu == 0.01
    @test spec.time_step == 1e-6 && spec.sample_step == 25e-6
    @test spec.window_starts == (6.0, 8.0) && spec.window_duration == 2.0
    @test spec.simulation_time == 10.0 && spec.injection_time == 2.0
    @test spec.estimated_station_seconds == 1800
    @test V.check_recorder_sampling(spec) == 25
    @test spec.kcl_required && V.scan_record(spec)["kcl_required"]
    @test only(filter(row -> row.owner == "DUT" && row.quantity == "speed_pu",
        V.operating_point_rows(list))).unit == "pu"
    @test spec.settling["voltage_departure_bound_pu"] < 0.004
    @test spec.settling["current_departure_bound_pu"] < 0.004
    @test spec.settling["predicted_normalized_tail"] < spec.settling["prediction_target"]
    @test first(spec.window_starts) - spec.injection_time >=
          spec.settling["decay_times"] / spec.settling["decay_per_s"]
    # A resistive grid has no storage. Eliminating terminal voltage gives this ODE.
    B = dut.cache.B ./ bases.voltage_inputs'
    C = dut.cache.C .* bases.current_outputs
    D = dut.cache.D .* bases.current_outputs ./ bases.voltage_inputs'
    resistance = P.identify_rlc(net.elements[:Grid]).form.R
    @test resistance == 0.01
    closed = dut.cache.A - B * ((I + resistance * D) \ (resistance * C))
    roots = eigvals(closed)
    screen = spec.machine_stability
    @test screen["status"] == "passed" && screen["nyquist_closed_RHP_count"] == 0
    @test length(screen["poles_real_per_s"]) == length(roots) == 5
    @test screen["most_positive_located_real_per_s"] ≈ maximum(real, roots) atol = 1e-10
    @test -1 / maximum(real, roots) ≈ 0.1497042845 rtol = 1e-6
    # The independently built state uses the same SI get_y API as adm_IM_test.jl.
    state = V.PSCADFixtures.im_network()
    native = compute(LinearizationProblem(state), AdmittanceLinearization()).network_model
    expected = NetworkBuilder.get_y(native, :im1, ComplexF64.(2π * im .* spec.frequencies))
    @test reference ≈ expected rtol = 1e-9 atol = 1e-12
    for (k, f) in enumerate(spec.frequencies)
        @test reference[:, :,
            k] ≈ C * ((2π * im * f * I - dut.cache.A) \ B) + D rtol = 1e-10
    end
    for f in (0.5, 1.5, 49.0, 1000.0)
        finer = V.step_definition(spec, f)
        @test finer.time_step == 0.5e-6 && finer.sample_step == 12.5e-6
        @test finer.window_starts == spec.window_starts && finer.window_duration == 2.0
        @test V.check_recorder_sampling(finer) == 25
    end
    for axis in ["baseline"; spec.axes]
        plan, settings = V.scan_plan(list, spec, axis)
        @test P.check_connectivity(plan) === nothing
        probe = only(filter(c -> c.kind == :current && c.element == "DUT", plan.probes.channels))
        @test probe.orientation == :into
        @test settings.time_step == 1e-6 && settings.simulation_time == 10.0
    end
    mktempdir() do directory
        data = joinpath(@__DIR__, "../data/IM_Ztool_1us#Y_AC#-1#.txt")
        report = V.induction_machine_crosscheck(data; directory)
        @test report["diagnostic_only"] && !haskey(report, "passed")
        @test report["frequency_count"] == 80 && report["unit"] == "S"
        @test report["global_relative_error"] ≈ 0.0003292116 rtol = 1e-5
        @test report["max_matrix_relative_error"] ≈ 0.0048777400 rtol = 1e-5
        @test report["admittance_base_S"] ≈ 1000 / 220^2
        @test !isfile(joinpath(directory, "manifest.toml"))
        @test TOML.parsefile(joinpath(directory, "comparison.toml"))["diagnostic_only"]
    end
end

function induction_recordings(net, list, spec; amplitude_scale = 1.0)
    reference = V.scan_reference(net, list, spec)
    times = collect(0.0:spec.sample_step:spec.simulation_time)
    models, results = Dict{String, PSCADModel}(), Dict{String, PSCADResult}()
    for (column, axis) in enumerate(["baseline"; spec.axes])
        plan, settings = V.scan_plan(list, spec, axis)
        voltage = repeat([first(spec.voltage_bases) 0.0], length(times), 1)
        current = repeat([0.5first(spec.current_bases) 0.2first(spec.current_bases)], length(times), 1)
        grid, drive = zeros(length(times), 2), zeros(length(times), 2)
        # The common coherent interference requires subtraction before identification.
        voltage[:, 1] .+= 0.001first(spec.voltage_bases) .* cos.(π .* times)
        current[:, 2] .+= 0.001first(spec.current_bases) .* sin.(π .* times)
        if axis != "baseline"
            j = column - 1
            for (k, f) in enumerate(spec.frequencies)
                source = zeros(ComplexF64, 2)
                source[j] = amplitude_scale * spec.tone_peak_pu * spec.current_bases[j]
                yg = V.physical_y(net.elements[:Grid], ComplexF64(2π * im * f))[1:2, 1:2]
                v = (reference[:, :, k] + yg) \ (V.injection_readout_factor(f, spec) * source)
                i, ig = reference[:, :, k] * v, yg * v
                for row in 1:2
                    wave = cis.(2π * f .* times)
                    voltage[:, row] .+= real.(v[row] .* wave)
                    current[:, row] .+= real.(i[row] .* wave)
                    grid[:, row] .+= real.(ig[row] .* wave)
                    drive[:, row] .+= real.(source[row] .* wave)
                end
            end
        end
        vp = only(filter(c -> c.kind == :voltage && c.bus == only(spec.buses).name, plan.probes.channels))
        ip = only(filter(c -> c.kind == :current && c.element == "DUT", plan.probes.channels))
        gp = only(filter(
            c -> c.kind == :current && c.element == "Grid" && c.port == :side1,
                plan.probes.channels))
        dp = only(filter(c -> c.kind == :injection_current, plan.probes.channels))
        channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
        for (probe, dq) in ((vp, voltage), (ip, current), (gp, grid), (dp, drive))
            sign = probe.kind == :current && probe.orientation == :out ||
                   probe.kind == :injection_current && probe.orientation == :into ? -1 : 1
            samples = phase_wave(times, sign .* dq)
            for phase in 1:3
                channels[probe.name * ":" * string(phase)] = samples[:, phase]
            end
        end
        models[axis] = PSCADModel("synthetic.pscx", plan.name, list, plan.probes, settings,
            list.operating_point, (;))
        results[axis] = PSCADResult(PSCADRun(), times, channels, plan.probes, settings, (;), (;))
    end
    return models, results, reference
end

@testset "Induction-machine measured Y and required refinements" begin
    net = V.fixture("induction_machine").factory()
    list = V.fixture_netlist(net, compute(PowerFlowProblem(net), ACDCPowerFlow()))
    original, _ = V.applicable_scan("induction_machine", net, list)
    spec = merge(original, (; frequencies = [0.5, 1.5, 49.0, 750.0, 1000.0], phases = zeros(5),
        window_starts = (0.0, 2.0), simulation_time = 4.0, injection_time = 0.0))
    models, results, reference = induction_recordings(net, list, spec)
    half_spec = merge(spec, (; tone_peak_pu = spec.tone_peak_pu / 2))
    half_models, half_results, _ = induction_recordings(net, list, half_spec)
    step_spec = V.step_definition(spec, 1000.0)
    step_models, step_results, _ = induction_recordings(net, list, step_spec)
    mktempdir() do directory
        quality = V.compare_frequency_runs(results, models, reference, directory; spec)
        @test quality["status"] == "passed" && quality["valid"]
        @test quality["max_frobenius_error"] < 1e-8
        checks = [V.readout_evidence(results[axis], results["baseline"], models[axis], spec, j)
                  for (j, axis) in enumerate(spec.axes)]
        @test all(check["passed"] for check in checks)
        @test all(length(check["rows"]) == 2length(spec.frequencies) for check in checks)
        axis = first(spec.axes)
        main, main_quality = V.single_response(results[axis], results["baseline"], models[axis], spec, 1)
        half, half_quality = V.single_response(half_results[axis], half_results["baseline"], half_models[axis], half_spec, 1)
        @test main_quality["valid"] && half_quality["valid"]
        @test V.matrix_change(half, main; epsilon = 0.02)["passed"]
        finer, finer_quality = V.single_response(step_results[axis], step_results["baseline"], step_models[axis], step_spec, 1)
        push!(checks, V.readout_evidence(half_results[axis], half_results["baseline"], half_models[axis], half_spec, 1))
        push!(checks, V.readout_evidence(step_results[axis], step_results["baseline"], step_models[axis], step_spec, 1))
        @test all(check["passed"] for check in checks)
        for evidence in (checks, Dict{String, Any}[], [Dict("passed" => false)])
            record = Dict{String, Any}()
            raw = V.record_step_witness!(record, net, spec, step_spec, 1,
                main, finer, main_quality, finer_quality, models[axis], step_models[axis], evidence, directory)
            accepted = evidence === checks
            @test raw["valid"] == raw["passed"] == accepted
            @test raw["status"] == (accepted ? "passed" : "invalid_measurement")
            @test haskey(raw, "readout_checks") && !haskey(record, "residual_step_refinement")
        end
        bad = deepcopy(results[axis])
        gp = only(filter(
            c -> c.kind == :current && c.element == "Grid" && c.port == :side1,
            models[axis].probes.channels))
        for phase in 1:3
            bad.channels[gp.name * ":" * string(phase)] .*= 0.99
        end
        @test !V.readout_evidence(bad, results["baseline"], models[axis], spec, 1)["passed"]
    end
end
end
