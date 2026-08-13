using Test
using Logging
using Random
using Statistics
using Measurements
using PowerImpedanceACDC
using PowerImpedanceACDC.NetworkBuilder: ⟷

const NB = PowerImpedanceACDC.NetworkBuilder
Logging.global_logger(ConsoleLogger(stderr, Logging.Warn))

function uncertain_builder(axis)
    elements = (
        z1 = NB.impedance(z = axis, pins = 1),
        z2 = NB.impedance(z = 20.0, pins = 1)
    )
    connections = (
        NB.pin(:z1, 1, 1) ⟷ NB.pin(:z2, 1, 1) ⟷ :n1,
        NB.pin(:z1, 2, 1) ⟷ NB.pin(:z2, 2, 1) ⟷ :gnd
    )
    return NB.define(elements, connections)
end

function impedance_study(axis; kwargs...)
    return NB.determine_impedance(
        uncertain_builder(axis);
        nets = [:n1],
        freq_range = (1.0, 10.0, 2),
        kwargs...
    )
end

@testset "Measurements extension" begin
    @test NB._measurement_extension_loaded()
    @test only(NB.Grid(10.0, 5.0)) == measurement(10.0, 0.5)
    @test only(NB.Grid(10.0, NB.AbsoluteError(0.5))) == measurement(10.0, 0.5)

    normal = impedance_study(10.0 ± 1.0; trials = 1000, seed = 123, return_samples = true)
    case = only(normal)
    @test case.trials == 1000
    @test size(case.samples) == (1, 1, 2, 1000)
    @test eltype(case.impedance) == Complex{Measurements.Measurement{Float64}}
    @test isapprox(Measurements.value(case.impedance[1]), 20 / 3; atol = 0.08)
    @test isapprox(Measurements.uncertainty(real(case.impedance[1])), 4 / 9; atol = 0.08)
    @test case.statistics.real[1].n == 1000

    uniform = impedance_study(
        NB.Grid(10.0, NB.AbsoluteError(1.0));
        trials = 1000,
        distribution = :uniform,
        seed = 456
    )
    @test isapprox(Measurements.value(only(uniform).impedance[1]), 20 / 3; atol = 0.08)
    @test isapprox(Measurements.uncertainty(real(only(uniform).impedance[1])), 4 / 9; atol = 0.08)

    first_run = impedance_study(10.0 ± 1.0; trials = 32, seed = 99, return_samples = true)
    second_run = impedance_study(10.0 ± 1.0; trials = 32, seed = 99, return_samples = true)
    @test only(first_run).samples == only(second_run).samples
    @test only(first_run).statistics == only(second_run).statistics

    Random.seed!(0x51f83e18)
    expected_global_draw = rand(UInt64)
    Random.seed!(0x51f83e18)
    impedance_study(10.0 ± 1.0; trials = 4, seed = 101)
    @test rand(UInt64) == expected_global_draw

    zero = impedance_study(10.0 ± 0.0; trials = 1000, seed = 3)
    @test only(zero).trials == 1000
    @test iszero(Measurements.uncertainty(real(only(zero).impedance[1])))

    mixed = impedance_study(NB.Grid([10.0, 12.0], 5.0); trials = 10, seed = 7)
    @test length(mixed) == 2
    @test all(case -> case.trials == 10, mixed)
    @test first(mixed[1].coordinates).first == (:elements, :z1, :z)

    solve_result = NB.solve(uncertain_builder(10.0 ± 1.0); trials = 8, seed = 5)
    @test only(solve_result).powerflow === nothing
    @test only(solve_result).network === nothing
    @test only(solve_result).trials == 8

    @test NB._dkw_trials(20, 0.95, 0.02) ==
          ceil(Int, log(40 / 0.05) / (2 * 0.02^2))

    failure_space = NB.Gridspace{NB.BuilderState}(
        _ -> error("deliberate trial failure"),
        (NB.Grid(1.0, NB.AbsoluteError(0.0)),),
        (:failure_axis,)
    )
    failure = try
        NB.solve(failure_space; trials = 2, seed = 202)
        nothing
    catch error
        error
    end
    @test failure isa ErrorException
    @test occursin("case 1, trial 1", sprint(showerror, failure))
    @test occursin("failure_axis", sprint(showerror, failure))
end

@testset "Measurements small-signal responses" begin
    frequencies = 2pi .* [1.0, 3.0, 10.0, 30.0]
    covariance = [1.0 -0.6; -0.6 4.0]
    correlated = Measurements.correlated_values([1.0, 2.0], covariance)
    zero = measurement(0.0, 0.0)
    one = measurement(1.0, 0.0)
    uncertain_response = fill(complex(one, zero), 1, 1, length(frequencies))
    uncertain_response[1, 1, 1] = complex(correlated[1], zero)
    uncertain_response[1, 1, 2] = complex(correlated[2], zero)

    studies = Dict{Symbol, NB.ParametricFrequencyResponse}()
    for (distribution, seed) in ((:normal, 2026), (:uniform, 2027))
        study = @test_logs (
            :warn,
            r"standalone Measurements response"
        ) NB.sampled_frequency_response(
            uncertain_response,
            frequencies;
            trials = 3000,
            distribution,
            seed,
            return_samples = true,
            nodes = [:port]
        )
        studies[distribution] = study
        case = only(study)
        first_values = real.(vec(case.samples[1, 1, 1, :]))
        second_values = real.(vec(case.samples[1, 1, 2, :]))
        @test case.uncertainty_source == :measurements_surrogate
        @test eltype(case.samples) == ComplexF64
        @test isapprox(var(first_values), covariance[1, 1]; atol = 0.12)
        @test isapprox(var(second_values), covariance[2, 2]; atol = 0.35)
        @test isapprox(cov(first_values, second_values), covariance[1, 2]; atol = 0.16)
    end

    repeated = @test_logs (
        :warn,
        r"standalone Measurements response"
    ) NB.sampled_frequency_response(
        uncertain_response,
        frequencies;
        trials = 3000,
        seed = 2026,
        return_samples = true,
        nodes = [:port]
    )
    @test only(repeated).samples == only(studies[:normal]).samples

    first_response = studies[:normal]
    second_response = @test_logs (
        :warn,
        r"standalone Measurements response"
    ) NB.sampled_frequency_response(
        uncertain_response,
        frequencies;
        trials = 3000,
        seed = 99,
        nodes = [:port]
    )
    @test_throws ArgumentError NB.make_loopgain(first_response, second_response)
    aligned = NB.make_loopgain(first_response, second_response; pairing = :aligned)
    independent = NB.make_loopgain(
        first_response,
        second_response;
        pairing = :independent,
        trials = 17,
        seed = 42
    )
    @test only(aligned).trials == 3000
    @test only(independent).trials == 17

    callback(rng, trial_index) = fill(
        complex(rand(rng) + trial_index, 0.0),
        1,
        1,
        length(frequencies)
    )
    callback_first = NB.sampled_frequency_response(
        callback,
        frequencies;
        trials = 12,
        seed = 51
    )
    callback_second = NB.sampled_frequency_response(
        callback,
        frequencies;
        trials = 12,
        seed = 51
    )
    @test only(callback_first).samples == only(callback_second).samples

    captured_offset = [0.0]
    captured_callback = (rng, trial_index) -> fill(
        complex(captured_offset[1] + rand(rng) + trial_index, 0.0),
        1,
        1,
        length(frequencies)
    )
    frozen_callback = NB.sampled_frequency_response(
        captured_callback,
        frequencies;
        trials = 4,
        seed = 52
    )
    original_callback_samples = copy(only(frozen_callback).samples)
    captured_offset[1] = 100.0
    replayed_callback_samples = NB._stack_impedance_samples(
        NB._replay_response(only(frozen_callback)._provenance)
    )
    @test replayed_callback_samples == original_callback_samples

    callback_case = only(callback_first)
    stripped_case = NB.FrequencyResponseCase(
        callback_case.coordinates,
        callback_case.trials,
        callback_case.seed,
        callback_case.distribution,
        callback_case.kind,
        callback_case.output,
        callback_case.response,
        callback_case.frequencies,
        callback_case.nodes,
        callback_case.statistics,
        nothing,
        callback_case.uncertainty_source,
        callback_case._provenance
    )
    replayed = NB.ParametricFrequencyResponse(
        callback_first.kind,
        [stripped_case],
        callback_first._study_id
    )
    @test only(bodeplot(
        replayed;
        display_plot = false,
        return_samples = true
    )).samples == only(bodeplot(
        callback_first;
        display_plot = false,
        return_samples = true
    )).samples

    naked_nyquist = @test_logs (
        :warn,
        r"standalone Measurements response"
    ) nyquistplot(
        uncertain_response,
        frequencies;
        trials = 32,
        seed = 8,
        display_plot = false
    )
    @test only(naked_nyquist).uncertainty_source == :measurements_surrogate

    deterministic_response = ones(ComplexF64, 1, 1, length(frequencies))
    mixed_gain = @test_logs (
        :warn,
        r"standalone Measurements responses"
    ) small_gain(
        uncertain_response,
        deterministic_response,
        frequencies;
        trials = 32,
        seed = 9,
        display_plot = false
    )
    @test only(mixed_gain).uncertainty_source == :measurements_surrogate

    impedance = impedance_study(
        10.0 ± 1.0;
        trials = 20,
        seed = 73,
        return_samples = false
    )
    @test only(impedance).samples === nothing
    impedance_bode = bodeplot(
        impedance;
        display_plot = false,
        return_samples = true
    )
    @test size(only(impedance_bode).samples.magnitude_db) == (1, 1, 2, 20)
end

@testset "Small-signal Monte Carlo orchestration" begin
    response_kwargs = (;
        nodelist = [:n1],
        freq_range = (1.0, 10.0, 2),
        trials = 12,
        seed = 71
    )

    # Warm compilation and any solver-owned temporary state before checking
    # that the response runner removes its memory-mapped trial file.
    NB.make_y_edge(
        uncertain_builder(10.0 ± 1.0);
        response_kwargs...,
        trials = 2
    )
    temporary_before = Set(readdir(tempdir(); join = true))
    without_samples, schema, omega = NB.make_y_edge(
        uncertain_builder(10.0 ± 1.0);
        response_kwargs...,
        return_samples = false
    )
    temporary_after = Set(readdir(tempdir(); join = true))
    retained, _, _ = NB.make_y_edge(
        uncertain_builder(10.0 ± 1.0);
        response_kwargs...,
        return_samples = true
    )
    case = only(without_samples)
    retained_case = only(retained)

    @test case.uncertainty_source == :monte_carlo
    @test case.trials == 12
    @test case.samples === nothing
    @test size(retained_case.samples) == (1, 1, 2, 12)
    @test eltype(retained_case.samples) == ComplexF64
    @test case.statistics == retained_case.statistics
    @test temporary_after == temporary_before
    @test length(schema) == 1
    @test omega == 2pi .* [1.0, 10.0]

    replayed_bode = bodeplot(
        without_samples;
        display_plot = false,
        return_samples = true
    )
    retained_bode = bodeplot(
        retained;
        display_plot = false,
        return_samples = true
    )
    @test only(replayed_bode).samples == only(retained_bode).samples

    adaptive, _, _ = NB.make_y_edge(
        uncertain_builder(10.0 ± 1.0);
        nodelist = [:n1],
        freq_range = (1.0, 10.0, 2),
        tolerance = 0.5,
        seed = 72
    )
    @test only(adaptive).trials == NB._dkw_trials(4, 0.95, 0.5)

    Random.seed!(0x5a17)
    expected_global_draw = rand(UInt64)
    Random.seed!(0x5a17)
    NB.make_y_edge(
        uncertain_builder(10.0 ± 1.0);
        response_kwargs...,
        trials = 3
    )
    @test rand(UInt64) == expected_global_draw

    zero, _, _ = NB.make_y_edge(
        uncertain_builder(10.0 ± 0.0);
        nodelist = [:n1],
        freq_range = (1.0, 10.0, 2),
        trials = 1000,
        seed = 73
    )
    @test only(zero).trials == 1000
    @test all(iszero, Measurements.uncertainty.(real.(only(zero).response)))
    @test all(iszero, Measurements.uncertainty.(imag.(only(zero).response)))

    function topology_builder(value)
        elements = (
            z1 = only(NB.impedance(z = 1.0, pins = 1)),
            z2 = only(NB.impedance(z = 2.0, pins = 1))
        )
        connections = if value > 10
            (
                NB.ConnectionDef([
                        NB.pin(:z1, 1, 1),
                        NB.pin(:z2, 1, 1)
                    ]; name = :n1),
                NB.ConnectionDef([
                        NB.pin(:z1, 2, 1),
                        NB.pin(:z2, 2, 1)
                    ]; name = :gnd)
            )
        else
            (
                NB.ConnectionDef([NB.pin(:z1, 1, 1)]; name = :n1),
                NB.ConnectionDef([
                        NB.pin(:z1, 2, 1),
                        NB.pin(:z2, 1, 1)
                    ]; name = :middle),
                NB.ConnectionDef([NB.pin(:z2, 2, 1)]; name = :gnd)
            )
        end
        return NB.define(elements, connections)
    end

    topology_space = NB.Gridspace{NB.BuilderState}(
        topology_builder,
        (NB.Grid(10.0, NB.AbsoluteError(1.0)),),
        (:topology_axis,)
    )
    topology_error = try
        NB.make_y_edge(
            topology_space;
            nodelist = [:n1],
            freq_range = (1.0, 10.0, 2),
            trials = 20,
            seed = 22
        )
        nothing
    catch error
        error
    end
    @test topology_error isa ErrorException
    @test occursin("ordered node schema changed", sprint(showerror, topology_error))
    @test occursin("trial 2", sprint(showerror, topology_error))
end

@testset "Analytical uncertain stability statistics" begin
    frequencies = 2pi .* 10 .^ range(-2, 2; length = 400)
    nyquist_samples = Array{ComplexF64}(undef, 1, 1, length(frequencies), 2)
    nyquist_samples[1, 1, :, 1] .= 7.5 ./ (1 .+ im .* frequencies) .^ 3
    nyquist_samples[1, 1, :, 2] .= 8.5 ./ (1 .+ im .* frequencies) .^ 3
    response = NB.sampled_frequency_response(
        nyquist_samples,
        frequencies;
        nodes = [:loop],
        trial_ids = [101, 102]
    )
    nyquist = nyquistplot(
        response;
        display_plot = false,
        return_samples = true
    )
    unstable = unstable_frequency(
        response;
        make_plot = false,
        display_plot = false,
        return_samples = true
    )
    @test only(nyquist).output.assessment_probabilities == Dict(
        :stable_if_subsystems_stable => 0.5,
        :unstable_system => 0.5
    )
    @test only(unstable).output.probability_detected == 0.5
    @test only(unstable).output.probability_not_detected == 0.5

    short_frequencies = 2pi .* [1.0, 2.0, 3.0, 4.0, 5.0]
    gain_samples = Array{ComplexF64}(undef, 1, 1, 5, 2)
    gain_samples[1, 1, :, 1] .= 0.5
    gain_samples[1, 1, :, 2] .= 2.0
    gain_response = NB.sampled_frequency_response(
        gain_samples,
        short_frequencies;
        nodes = [:channel],
        trial_ids = [1, 2]
    )
    gain = small_gain(
        gain_response,
        gain_response;
        pairing = :aligned,
        display_plot = false,
        return_samples = true
    )
    @test only(gain).output.probability_by_frequency == fill(0.5, 5)
    @test only(gain).output.probability_complete_scan == 0.5

    passivity_samples = copy(gain_samples)
    passivity_samples[1, 1, :, 2] .= -0.5
    passivity_response = NB.sampled_frequency_response(
        passivity_samples,
        short_frequencies;
        nodes = [:channel],
        trial_ids = [1, 2]
    )
    passive = passivity(
        passivity_response;
        display_plot = false,
        return_samples = true
    )
    @test only(passive).output.probability_by_frequency == fill(0.5, 5)
    @test only(passive).output.probability_complete_scan == 0.5

    phases = deg2rad.([170.0, 179.0, -179.0, -170.0, -160.0])
    bode_samples = Array{ComplexF64}(undef, 1, 1, 5, 2)
    bode_samples[1, 1, :, 1] .= cis.(phases)
    bode_samples[1, 1, :, 2] .= cis.(phases .+ deg2rad(2.0))
    bode_response = NB.sampled_frequency_response(
        bode_samples,
        short_frequencies;
        nodes = [:channel],
        trial_ids = [1, 2]
    )
    bode = bodeplot(
        bode_response;
        display_plot = false,
        return_samples = true
    )
    first_phase = vec(only(bode).samples.phase_deg[1, 1, :, 1])
    second_phase = vec(only(bode).samples.phase_deg[1, 1, :, 2])
    @test first_phase ≈ [170.0, 179.0, 181.0, 190.0, 200.0]
    @test second_phase - first_phase ≈ fill(2.0, 5)
end

@testset "Extension load order" begin
    project = dirname(@__DIR__)
    code = "using PowerImpedanceACDC; " *
           "NB = PowerImpedanceACDC.NetworkBuilder; " *
           "@assert !NB._measurement_extension_loaded(); " *
           "using Measurements; " *
           "@assert NB._measurement_extension_loaded(); " *
           "@assert length(collect(NB.Grid(1.0, 1.0))) == 1"
    command = `$(Base.julia_cmd()) --project=$project --startup-file=no -e $code`
    @test success(pipeline(command; stdout = devnull, stderr = devnull))
end

if get(ENV, "PIACDC_SKIP_TOPOLOGY_TESTS", "false") != "true"
    include("topology_gridspace_tests.jl")
end
