using Test
using LinearAlgebra
using Random
using Statistics
using LineCableModels
using Measurements
using PowerImpedanceACDC
using PowerImpedanceACDC.NetworkBuilder: ⟷

const NB = PowerImpedanceACDC.NetworkBuilder
const LCM_EXT = Base.get_extension(
    PowerImpedanceACDC,
    :PowerImpedanceLineCableModelsExt
)

function deterministic_line_parameters(
        order::Integer = 1;
        frequencies = [10.0, 100.0, 1000.0],
        domain = PhaseDomain
)
    count = length(frequencies)
    Z = Array{ComplexF64}(undef, order, order, count)
    Y = Array{ComplexF64}(undef, order, order, count)
    for frequency_index in eachindex(frequencies)
        for column in 1:order, row in 1:order

            if row == column
                Z[row, column, frequency_index] = (1.0 + 0.2frequency_index) * 1e-4 +
                                                  (2.0 + frequency_index) * 1e-4im
                Y[row, column, frequency_index] = (1.0 + 0.1frequency_index) * 1e-8 +
                                                  (3.0 + frequency_index) * 1e-8im
            else
                Z[row, column, frequency_index] = (0.05 + 0.01frequency_index) * 1e-4 +
                                                  (0.1 + 0.02frequency_index) * 1e-4im
                Y[row, column, frequency_index] = (0.02 + 0.01frequency_index) * 1e-8 +
                                                  (0.05 + 0.01frequency_index) * 1e-8im
            end
        end
    end
    return LineParameters(domain, Z, Y, collect(frequencies))
end

function measured_array(values, relative_error)
    return complex.(
        measurement.(real.(values), abs.(real.(values)) .* relative_error),
        measurement.(imag.(values), abs.(imag.(values)) .* relative_error)
    )
end

function measured_line_parameters(
        parameters::LineParameters;
        relative_z = 0.05,
        relative_y = 0.0
)
    return LineParameters(
        LineCableModels.domain(parameters),
        measured_array(Array(parameters.Z), relative_z),
        measured_array(Array(parameters.Y), relative_y),
        parameters.f
    )
end

function passive_line_builder(parameters)
    elements = (
        line = NB.cable(parameters; length = 1e3),
        load = NB.impedance(z = 10.0, pins = 1)
    )
    connections = (
        NB.pin(:line, 1, 1) ⟷ :n1,
        NB.pin(:line, 2, 1) ⟷ NB.pin(:load, 1, 1) ⟷ :n2,
        NB.pin(:load, 2, 1) ⟷ :gnd
    )
    return NB.define(elements, connections)
end

@testset "LineCableModels extension activation" begin
    @test LCM_EXT !== nothing
    @test Base.get_extension(
        PowerImpedanceACDC,
        :PowerImpedanceMeasurementsExt
    ) !== nothing
end

@testset "Native LineParameters line constructors" begin
    parameters = deterministic_line_parameters(3)
    overhead = PowerImpedanceACDC.overhead_line(parameters; length = 25e3)
    cable = PowerImpedanceACDC.cable(parameters; length = 25e3)

    @test overhead isa PowerImpedanceACDC.Element
    @test cable isa PowerImpedanceACDC.Element
    @test overhead.input_pins == overhead.output_pins == 3
    @test cable.input_pins == cable.output_pins == 3
    @test typeof(overhead.element_model) != typeof(cable.element_model)

    frequency = 100.0
    overhead_abcd = PowerImpedanceACDC.eval_abcd(
        overhead.element_model,
        2pi * frequency * im
    )
    cable_abcd = PowerImpedanceACDC.eval_abcd(
        cable.element_model,
        2pi * frequency * im
    )
    @test size(overhead_abcd) == (6, 6)
    @test overhead_abcd ≈ cable_abcd

    shadow = only(NB.overhead_line(parameters; length = 25e3))
    @test PowerImpedanceACDC.eval_abcd(
        shadow.element_model,
        2pi * frequency * im
    ) ≈ overhead_abcd

    length_grid = NB.cable(
        parameters;
        length = NB.Grid([10e3, 20e3])
    )
    @test length(length_grid) == 2
    @test [line.element_model.length for line in length_grid] == [10e3, 20e3]

    diagonal_Z = similar(Array(parameters.Z))
    diagonal_Y = similar(Array(parameters.Y))
    for index in axes(parameters.Z, 3)
        diagonal_Z[:, :, index] = Diagonal(diag(parameters.Z[:, :, index]))
        diagonal_Y[:, :, index] = Diagonal(diag(parameters.Y[:, :, index]))
    end
    diagonal_parameters = LineParameters(
        diagonal_Z,
        diagonal_Y,
        parameters.f
    )
    diagonal_line = PowerImpedanceACDC.overhead_line(
        diagonal_parameters;
        length = 25e3
    )
    @test !isapprox(
        PowerImpedanceACDC.eval_abcd(
            diagonal_line.element_model,
            2pi * frequency * im
        ),
        overhead_abcd
    )
end

@testset "LineParameters frequency interpolation" begin
    parameters = deterministic_line_parameters(2; frequencies = [10.0, 100.0])
    line = PowerImpedanceACDC.cable(
        parameters;
        length = 1e3,
        transformation = true
    )

    exact_Z, exact_Y = LCM_EXT._line_parameters_at(line.element_model, 10.0)
    @test exact_Z ≈ parameters.Z[:, :, 1]
    @test exact_Y ≈ parameters.Y[:, :, 1]

    midpoint_Z, midpoint_Y = LCM_EXT._line_parameters_at(line.element_model, 55.0)
    @test midpoint_Z ≈
          0.5 .* parameters.Z[:, :, 1] .+ 0.5 .* parameters.Z[:, :, 2]
    @test midpoint_Y ≈
          0.5 .* parameters.Y[:, :, 1] .+ 0.5 .* parameters.Y[:, :, 2]

    negative_Z, negative_Y = LCM_EXT._line_parameters_at(line.element_model, -55.0)
    @test negative_Z ≈ conj.(midpoint_Z)
    @test negative_Y ≈ conj.(midpoint_Y)

    error = try
        LCM_EXT._line_parameters_at(line.element_model, 1.0)
        nothing
    catch caught
        caught
    end
    @test error isa DomainError
    @test occursin("[10.0, 100.0] Hz", sprint(showerror, error))
    @test occursin("|f ± 50 Hz|", sprint(showerror, error))

    extrapolated = PowerImpedanceACDC.cable(
        parameters;
        length = 1e3,
        transformation = true,
        extrapolation = :linear
    )
    extrapolated_Z, extrapolated_Y = LCM_EXT._line_parameters_at(extrapolated.element_model, 1.0)
    fraction = (1.0 - 10.0) / (100.0 - 10.0)
    @test extrapolated_Z ≈
          (1 - fraction) .* parameters.Z[:, :, 1] .+
          fraction .* parameters.Z[:, :, 2]
    @test extrapolated_Y ≈
          (1 - fraction) .* parameters.Y[:, :, 1] .+
          fraction .* parameters.Y[:, :, 2]
end

@testset "LineParameters validation" begin
    one_phase = deterministic_line_parameters(1)
    two_phase = deterministic_line_parameters(2)
    three_phase = deterministic_line_parameters(3)

    @test PowerImpedanceACDC.cable(one_phase; length = 1e3).input_pins == 1
    @test PowerImpedanceACDC.cable(
        two_phase;
        length = 1e3,
        transformation = true
    ).input_pins == 1
    @test PowerImpedanceACDC.overhead_line(
        three_phase;
        length = 1e3,
        transformation = true
    ).input_pins == 2

    @test_throws ArgumentError PowerImpedanceACDC.cable(
        one_phase;
        length = 1e3,
        transformation = true
    )
    @test_throws ArgumentError PowerImpedanceACDC.cable(
        two_phase;
        length = 1e3
    )
    @test_throws ArgumentError PowerImpedanceACDC.cable(
        deterministic_line_parameters(4);
        length = 1e3
    )
    @test_throws ArgumentError PowerImpedanceACDC.cable(
        deterministic_line_parameters(2; domain = ModalDomain);
        length = 1e3,
        transformation = true
    )

    mismatched = LineParameters(
        zeros(ComplexF64, 2, 2, 2),
        zeros(ComplexF64, 3, 3, 2),
        [10.0, 100.0]
    )
    @test_throws DimensionMismatch PowerImpedanceACDC.cable(
        mismatched;
        length = 1e3,
        transformation = true
    )

    @test_throws ArgumentError PowerImpedanceACDC.cable(
        deterministic_line_parameters(1; frequencies = [10.0]);
        length = 1e3
    )
    @test_throws ArgumentError PowerImpedanceACDC.cable(
        deterministic_line_parameters(1; frequencies = [10.0, 10.0]);
        length = 1e3
    )
    @test_throws ArgumentError PowerImpedanceACDC.cable(
        deterministic_line_parameters(1; frequencies = [0.0, 10.0]);
        length = 1e3
    )

    uncertain_frequencies = LineParameters(
        Array(one_phase.Z),
        Array(one_phase.Y),
        measurement.([10.0, 100.0, 1000.0], [0.1, 0.1, 0.1])
    )
    @test_throws ArgumentError NB.cable(uncertain_frequencies; length = 1e3)

    nonfinite_Z = Array(one_phase.Z)
    nonfinite_Z[1] = Inf + im
    @test_throws ArgumentError PowerImpedanceACDC.cable(
        LineParameters(nonfinite_Z, Array(one_phase.Y), one_phase.f);
        length = 1e3
    )
    @test_throws ArgumentError PowerImpedanceACDC.cable(one_phase; length = 0.0)
    @test_throws ArgumentError PowerImpedanceACDC.cable(
        one_phase;
        length = 1e3,
        extrapolation = :flat
    )

    uncertain = measured_line_parameters(one_phase)
    native_error = try
        PowerImpedanceACDC.cable(uncertain; length = 1e3)
        nothing
    catch caught
        caught
    end
    @test native_error isa ArgumentError
    @test occursin("NetworkBuilder.cable", sprint(showerror, native_error))

    plan = only(NB._gridspace_plans(NB.cable(uncertain; length = 1e3)))
    sampled = plan.sample(Xoshiro(12), :normal)
    @test plan.uncertain
    @test eltype(sampled.element_model.parameters.Z) == ComplexF64
    @test !NB._has_measurement(sampled.element_model.parameters)
end

function correlated_line_parameters()
    parameters = deterministic_line_parameters(2)
    Z = measured_array(Array(parameters.Z), 0.0)
    Y = measured_array(Array(parameters.Y), 0.0)
    covariance = [1.0 -0.6; -0.6 4.0]
    correlated = Measurements.correlated_values([1.0, 2.0], covariance)
    Z[1, 1, 1] = complex(correlated[1], measurement(0.0, 0.0))
    Y[2, 2, 2] = complex(correlated[2], measurement(0.0, 0.0))
    return LineParameters(Z, Y, parameters.f), covariance
end

@testset "Covariance-aware LineParameters sampling" begin
    parameters, covariance = correlated_line_parameters()
    @test NB._has_measurement(parameters)
    @test !NB._zero_measurement(parameters)

    for (distribution, seed) in ((:normal, 2026), (:uniform, 2027))
        rng = Xoshiro(seed)
        samples = [NB._sample_value(rng, parameters, distribution) for _ in 1:5000]
        Z_values = real.([sample.Z[1, 1, 1] for sample in samples])
        Y_values = real.([sample.Y[2, 2, 2] for sample in samples])
        @test isapprox(mean(Z_values), 1.0; atol = 0.06)
        @test isapprox(mean(Y_values), 2.0; atol = 0.12)
        @test isapprox(var(Z_values), covariance[1, 1]; atol = 0.12)
        @test isapprox(var(Y_values), covariance[2, 2]; atol = 0.35)
        @test isapprox(cov(Z_values, Y_values), covariance[1, 2]; atol = 0.14)
    end

    first_rng = Xoshiro(99)
    second_rng = Xoshiro(99)
    first_run = [NB._sample_value(first_rng, parameters, :normal) for _ in 1:32]
    second_run = [NB._sample_value(second_rng, parameters, :normal) for _ in 1:32]
    @test [Array(sample.Z) for sample in first_run] ==
          [Array(sample.Z) for sample in second_run]
    @test [Array(sample.Y) for sample in first_run] ==
          [Array(sample.Y) for sample in second_run]

    zero_parameters = measured_line_parameters(
        deterministic_line_parameters(1);
        relative_z = 0.0,
        relative_y = 0.0
    )
    @test NB._has_measurement(zero_parameters)
    @test NB._zero_measurement(zero_parameters)
    sampled = NB._sample_value(Xoshiro(1), zero_parameters, :normal)
    @test eltype(sampled.Z) == ComplexF64
    @test !NB._has_measurement(sampled)
end

@testset "LineParameters Gridspace impedance studies" begin
    deterministic = deterministic_line_parameters(
        1;
        frequencies = [1.0, 10.0, 100.0, 1000.0]
    )
    uncertain = measured_line_parameters(deterministic; relative_z = 0.05)
    result = NB.determine_impedance(
        passive_line_builder(uncertain);
        nets = [:n1],
        freq_range = (10.0, 100.0, 3),
        trials = 16,
        seed = 314,
        return_samples = true
    )
    case = only(result)
    @test case.trials == 16
    @test size(case.samples) == (1, 1, 3, 16)
    @test eltype(case.impedance) ==
          Complex{Measurements.Measurement{Float64}}
    @test Measurements.uncertainty(real(case.impedance[1])) > 0
    @test only(case.coordinates).first ==
          (:elements, :line, :line_parameters)
    @test only(case.coordinates).second.kind == :line_parameters

    zero_parameters = measured_line_parameters(
        deterministic;
        relative_z = 0.0,
        relative_y = 0.0
    )
    zero = NB.determine_impedance(
        passive_line_builder(zero_parameters);
        nets = [:n1],
        freq_range = (10.0, 100.0, 3),
        trials = 1000,
        seed = 315
    )
    @test only(zero).trials == 1000
    @test iszero(Measurements.uncertainty(real(only(zero).impedance[1])))
end

@testset "Three-phase dq LineParameters study" begin
    parameters = deterministic_line_parameters(
        3;
        frequencies = [1.0, 50.0, 200.0]
    )
    elements = (
        line = NB.overhead_line(
            parameters;
            length = 1e3,
            transformation = true
        ),
        d_load = NB.impedance(z = 10.0, pins = 1),
        q_load = NB.impedance(z = 10.0, pins = 1)
    )
    connections = (
        NB.pin(:line, 1, 1) ⟷ :d1,
        NB.pin(:line, 1, 2) ⟷ :q1,
        NB.pin(:line, 2, 1) ⟷ NB.pin(:d_load, 1, 1) ⟷ :d2,
        NB.pin(:d_load, 2, 1) ⟷ :gnd_d,
        NB.pin(:line, 2, 2) ⟷ NB.pin(:q_load, 1, 1) ⟷ :q2,
        NB.pin(:q_load, 2, 1) ⟷ :gnd_q
    )
    result = NB.determine_impedance(
        NB.define(elements, connections);
        nets = [:d1],
        freq_range = (10.0, 100.0, 3)
    )
    @test size(only(result).impedance) == (1, 1, 3)
end

@testset "LineCableModels extension load order" begin
    project = dirname(Base.active_project())
    extension_check = "@assert Base.get_extension(PowerImpedanceACDC, " *
                      ":PowerImpedanceLineCableModelsExt) !== nothing"

    powerimpedance_first = "using PowerImpedanceACDC; " *
                           "@assert Base.get_extension(PowerImpedanceACDC, " *
                           ":PowerImpedanceLineCableModelsExt) === nothing; " *
                           "using LineCableModels; " * extension_check
    command = `$(Base.julia_cmd()) --project=$project --startup-file=no -e $powerimpedance_first`
    @test success(pipeline(command; stdout = devnull, stderr = devnull))

    linecablemodels_first = "using LineCableModels; using PowerImpedanceACDC; " *
                            extension_check
    command = `$(Base.julia_cmd()) --project=$project --startup-file=no -e $linecablemodels_first`
    @test success(pipeline(command; stdout = devnull, stderr = devnull))
end
