@testset "Small-signal response boundary" begin
    function captured_closure()
        captured_values = [1.0, 2.0]
        return value -> captured_values[1] + value, captured_values
    end
    captured_materializer, captured_values = captured_closure()
    frozen_materializer = deepcopy(captured_materializer)
    @test NB._same_study_value(frozen_materializer, captured_materializer)
    captured_values[1] = 3.0
    @test !NB._same_study_value(frozen_materializer, captured_materializer)

    anonymous_elements = (
        first = NB.impedance(z = 1.0, pins = 1),
        second = NB.impedance(z = 2.0, pins = 1)
    )
    anonymous_connections = (
        NB.ConnectionDef([
            NB.pin(:first, 1, 1),
            NB.pin(:second, 1, 1)
        ]),
        NB.ConnectionDef([
                NB.pin(:first, 2, 1),
                NB.pin(:second, 2, 1)
            ]; name = :gnd)
    )
    first_builder = only(NB.define(anonymous_elements, anonymous_connections))
    second_builder = only(NB.define(anonymous_elements, anonymous_connections))
    first_anonymous = only(unique(
        row.net
    for row in first_builder.connections.registry
    if startswith(String(row.net), "##")
    ))
    stable_key = NB._node_keys(first_builder, [first_anonymous])
    resolved_anonymous = only(NB._resolve_node_keys(second_builder, stable_key))
    @test resolved_anonymous != first_anonymous
    @test NB._node_key(second_builder, resolved_anonymous) == only(stable_key)

    frequencies = 2pi .* 10.0 .^ range(0, 2; length = 24)
    response = Array{ComplexF64}(undef, 2, 2, length(frequencies))
    for index in eachindex(frequencies)
        frequency = frequencies[index]
        response[:, :, index] = ComplexF64[0.45 / (1 + im * frequency / 70) 0.02im
                                           -0.01im 0.25 / (1 + im * frequency / 110)]
    end

    sampled = NB.sampled_frequency_response(
        reshape(response, 2, 2, length(frequencies), 1),
        frequencies;
        nodes = [:a, :b],
        trial_ids = [41]
    )
    case = only(sampled)
    @test sampled isa NB.ParametricFrequencyResponse
    @test length(sampled) == 1
    @test only(sampled) === sampled[1]
    @test case.response == response
    @test case.nodes == [:a, :b]
    @test case.uncertainty_source == :deterministic
    @test size(case.samples) == (2, 2, 24, 1)

    function with_coordinate(source, value)
        return NB.FrequencyResponseCase(
            Pair{Tuple, Any}[(:case,) => value],
            source.trials,
            source.seed,
            source.distribution,
            source.kind,
            source.output,
            source.response,
            source.frequencies,
            source.nodes,
            source.statistics,
            source.samples,
            source.uncertainty_source,
            source._provenance
        )
    end

    first_collection = NB.ParametricFrequencyResponse(
        :external,
        [with_coordinate(case, 1), with_coordinate(case, 2)],
        UInt64(1)
    )
    second_collection = NB.ParametricFrequencyResponse(
        :external,
        [with_coordinate(case, 3), with_coordinate(case, 4)],
        UInt64(2)
    )
    cartesian_loopgain = NB.make_loopgain(first_collection, second_collection)
    cartesian_gain = small_gain(
        first_collection,
        second_collection;
        display_plot = false
    )
    @test length(cartesian_loopgain) == 4
    @test length(cartesian_gain) == 4
    @test all(result -> length(result.coordinates) == 2, cartesian_loopgain)
    @test_throws ArgumentError NB.make_loopgain(
        first_collection,
        second_collection;
        pairing = :independent,
        trials = 0
    )

    matching_shared = NB.ParametricFrequencyResponse(
        :external,
        [with_coordinate(case, 1), with_coordinate(case, 2)],
        first_collection._study_id
    )
    shared_loopgain = NB.make_loopgain(first_collection, matching_shared)
    @test shared_loopgain[1].coordinates == first_collection[1].coordinates
    @test shared_loopgain[2].coordinates == first_collection[2].coordinates
    independently_paired = NB.make_loopgain(
        first_collection,
        matching_shared;
        pairing = :independent,
        trials = 1,
        seed = 17
    )
    @test independently_paired._study_id != first_collection._study_id

    mismatched_shared = NB.ParametricFrequencyResponse(
        :external,
        [with_coordinate(case, 2), with_coordinate(case, 1)],
        first_collection._study_id
    )
    @test_throws ArgumentError NB.make_loopgain(first_collection, mismatched_shared)
    @test_throws ArgumentError small_gain(
        first_collection,
        mismatched_shared;
        display_plot = false
    )

    edge = similar(response)
    for index in axes(edge, 3)
        edge[:, :, index] = ComplexF64[2.0 0.1; 0.2 1.5]
    end
    expected_loopgain = cat(
        (inv(edge[:, :, index]) * response[:, :, index]
        for index in axes(edge, 3))...;
        dims = 3
    )
    @test make_loopgain(edge, response) ≈ expected_loopgain
    @test_throws ArgumentError make_loopgain(edge, response; pairing = :independent)

    nyquist = nyquistplot(sampled; display_plot = false, return_samples = true)
    bode = bodeplot(sampled; display_plot = false, return_samples = true)
    passive = passivity(sampled; display_plot = false, return_samples = true)
    evd = EVD(
        sampled,
        nothing,
        first(frequencies) / (2pi),
        last(frequencies) / (2pi);
        display_plot = false,
        return_samples = true
    )
    margin = stabilitymargin(sampled; return_samples = true)
    unstable = unstable_frequency(
        sampled;
        make_plot = false,
        display_plot = false,
        return_samples = true
    )
    gain = small_gain(
        sampled,
        sampled;
        display_plot = false,
        return_samples = true
    )

    @test nyquist isa NB.ParametricStability
    @test only(nyquist).analysis == :nyquist
    @test only(bode).analysis == :bode
    @test only(passive).analysis == :passivity
    @test only(evd).analysis == :evd
    @test only(margin).analysis == :stabilitymargin
    @test only(unstable).analysis == :unstable_frequency
    @test only(gain).analysis == :small_gain
    @test size(only(nyquist).samples.responses) == (2, 2, 24, 1)
    @test all(isapprox(1.0; atol = 1e-12),
        sum(only(evd).output.participation; dims = 2))
    @test only(gain).output.probability_complete_scan in (0.0, 1.0)

    @test_throws ArgumentError NB.sampled_frequency_response(
        reshape(response, 2, 2, length(frequencies), 1),
        reverse(frequencies)
    )
    @test_throws ArgumentError NB.sampled_frequency_response(
        reshape(response, 2, 2, length(frequencies), 1),
        complex.(frequencies, 1.0)
    )
    @test_throws DimensionMismatch NB.sampled_frequency_response(
        reshape(response, 2, 2, length(frequencies), 1),
        frequencies;
        nodes = [:a]
    )

    singular_edge = zeros(ComplexF64, 1, 1, 2)
    nonsingular_node = ones(ComplexF64, 1, 1, 2)
    @test_throws LinearAlgebra.SingularException make_loopgain(
        singular_edge,
        nonsingular_node
    )
end

@testset "Analytical small-signal fixtures" begin
    frequencies = 2pi .* 10 .^ range(-2, 2; length = 400)
    stable_locus = 7.5 ./ (1 .+ im .* frequencies) .^ 3
    unstable_locus = 8.5 ./ (1 .+ im .* frequencies) .^ 3
    unstable_tensor = reshape(
        ComplexF64.(unstable_locus),
        1,
        1,
        length(frequencies),
        1
    )
    unstable_response = NB.sampled_frequency_response(
        unstable_tensor,
        frequencies;
        nodes = [:loop],
        trial_ids = [1]
    )

    stable_metrics = PowerImpedance._nyquist_trial(
        reshape(ComplexF64.(stable_locus), :, 1),
        frequencies
    )
    unstable_metrics = PowerImpedance._nyquist_trial(
        reshape(ComplexF64.(unstable_locus), :, 1),
        frequencies
    )
    @test stable_metrics.net == 0
    @test stable_metrics.assessment == :stable_if_subsystems_stable
    @test unstable_metrics.net == 1
    @test unstable_metrics.assessment == :unstable_system
    @test only(unstable_metrics.unstable_frequencies) ≈ 0.2842065516
    @test length(only(unstable_metrics.margins).phase) == 1
    @test length(only(unstable_metrics.margins).gain) == 1

    nyquist = nyquistplot(
        unstable_response;
        display_plot = false,
        return_samples = true
    )
    margins = stabilitymargin(
        unstable_response;
        SM = "GM",
        return_samples = true
    )
    unstable = unstable_frequency(
        unstable_response;
        make_plot = false,
        display_plot = false,
        return_samples = true
    )
    @test only(nyquist).output.encirclements.net == 1
    @test only(nyquist).output.assessment_probabilities[:unstable_system] == 1.0
    @test only(margins).output.margins.gain[1].probability_detected == 1.0
    @test only(unstable).output.probability_detected == 1.0
    @test only(unstable).output.frequencies.median ≈ 0.2842065516

    bode_frequencies = 2pi .* [1.0, 2.0, 3.0, 4.0, 5.0]
    wrapped_phase = deg2rad.([170.0, 179.0, -179.0, -170.0, -160.0])
    bode_tensor = reshape(
        ComplexF64.(cis.(wrapped_phase)),
        1,
        1,
        length(bode_frequencies),
        1
    )
    bode_response = NB.sampled_frequency_response(
        bode_tensor,
        bode_frequencies;
        nodes = [:channel],
        trial_ids = [1]
    )
    bode = bodeplot(
        bode_response;
        display_plot = false,
        return_samples = true
    )
    @test vec(only(bode).samples.phase_deg) ≈ [170.0, 179.0, 181.0, 190.0, 200.0]

    mimo = Array{ComplexF64}(undef, 2, 2, length(bode_frequencies), 1)
    for index in eachindex(bode_frequencies)
        mimo[:, :, index, 1] = ComplexF64[0.5 0.0; 0.0 0.25]
    end
    mimo_response = NB.sampled_frequency_response(
        mimo,
        bode_frequencies;
        nodes = [:d, :q],
        trial_ids = [1]
    )
    gain = small_gain(
        mimo_response,
        mimo_response;
        display_plot = false,
        return_samples = true
    )
    @test only(gain).output.first_gain == fill(0.5, length(bode_frequencies))
    @test only(gain).output.product_gain == fill(0.25, length(bode_frequencies))
    @test only(gain).output.probability_complete_scan == 1.0

    nonpassive = copy(mimo)
    nonpassive[2, 2, :, :] .= -0.25
    nonpassive_response = NB.sampled_frequency_response(
        nonpassive,
        bode_frequencies;
        nodes = [:d, :q],
        trial_ids = [1]
    )
    passive = passivity(
        nonpassive_response;
        display_plot = false,
        return_samples = true
    )
    @test only(passive).output.index == fill(-0.5, length(bode_frequencies))
    @test only(passive).output.probability_complete_scan == 0.0

    pnd_tensor = Array{ComplexF64}(undef, 1, 1, length(bode_frequencies), 1)
    pnd_tensor[1, 1, :, 1] .= ComplexF64[
        -1 + 1im,
        -1 + 0.5im,
        -1 - 0.5im,
        -1 - 1im,
        -1 - 2im
    ]
    pnd_response = NB.sampled_frequency_response(
        pnd_tensor,
        bode_frequencies;
        nodes = [:mode],
        trial_ids = [1]
    )
    modes = EVD(
        pnd_response,
        nothing,
        1.0,
        5.0;
        display_plot = false,
        return_samples = true
    )
    @test only(modes).output.pnd_unstable_probability == 1.0
    @test only(modes).output.pnd_modes.probability_detected == 1.0
    @test only(modes).output.pnd_modes.frequencies.median == 2.0
    @test all(isapprox(1.0; atol = 1e-12),
        sum(only(modes).output.participation; dims = 2))
end

@testset "Scalar stability APIs remain scalar" begin
    frequencies = 2pi .* [1.0, 10.0, 100.0]
    response = [ComplexF64[0.2 / (1 + im * frequency / 20);;]
                for frequency in frequencies]
    tensor = cat(response...; dims = 3)

    @test passivity(tensor, frequencies) isa Vector{Float64}
    @test small_gain(tensor, tensor, frequencies) isa Vector{Float64}
    @test bodeplot(tensor, frequencies) isa AbstractVector
end

@testset "BuilderState device partition" begin
    builder = build_ieee39bus_with_networkbuilder().builder
    result = check_stability(
        builder,
        :STATCOM;
        direction = :ac,
        freq_range = (10.0, 100.0, 3),
        display_plot = false,
        return_samples = false
    )
    case = only(result)

    @test result isa NB.ParametricStability
    @test case.analysis == :check_stability
    @test case.output.element == :STATCOM
    @test case.output.direction == :ac
    @test case.uncertainty_source == :deterministic
    @test case.samples === nothing
end
