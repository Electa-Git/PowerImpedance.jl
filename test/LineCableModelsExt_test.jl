using Test
using LinearAlgebra
using Random
using Statistics
using LineCableModels
using Measurements
using PowerImpedance

const NB = PowerImpedance.NetworkBuilder
const LCM_EXT = Base.get_extension(PowerImpedance, :PowerImpedanceLineCableModelsExt)
const LCM_MEASUREMENTS_EXT = Base.get_extension(
    PowerImpedance,
    :PowerImpedanceLineCableModelsMeasurementsExt,
)

function deterministic_line_parameters(
    order::Integer=1;
    frequencies=[10.0, 100.0, 1000.0],
)
    count = length(frequencies)
    Z = zeros(ComplexF64, order, order, count)
    Y = zeros(ComplexF64, order, order, count)
    for frequency_index in eachindex(frequencies), column in 1:order, row in 1:order
        diagonal = row == column
        Z[row, column, frequency_index] = diagonal ?
            (1.0 + 0.2frequency_index) * 1e-4 + (2.0 + frequency_index) * 1e-4im :
            (0.05 + 0.01frequency_index) * 1e-4 + (0.1 + 0.02frequency_index) * 1e-4im
        Y[row, column, frequency_index] = diagonal ?
            (1.0 + 0.1frequency_index) * 1e-8 + (3.0 + frequency_index) * 1e-8im :
            (0.02 + 0.01frequency_index) * 1e-8 + (0.05 + 0.01frequency_index) * 1e-8im
    end
    return LineParameters(PhaseDomain, Z, Y, collect(frequencies))
end

function measured_line_parameters(parameters; relative_error=0.05)
    measured(values) = complex.(
        measurement.(real.(values), abs.(real.(values)) .* relative_error),
        measurement.(imag.(values), abs.(imag.(values)) .* relative_error),
    )
    return LineParameters(
        LineCableModels.domain(parameters),
        measured(Array(parameters.Z)),
        measured(Array(parameters.Y)),
        parameters.f,
    )
end

@testset "LineCableModels extension activation" begin
    @test LCM_EXT !== nothing
    @test LCM_MEASUREMENTS_EXT !== nothing
    @test Base.get_extension(PowerImpedance, :PowerImpedanceMeasurementsExt) !== nothing
end

@testset "Deterministic LineParameters interoperability" begin
    parameters = deterministic_line_parameters(3)
    overhead = PowerImpedance.overhead_line(parameters; length=25e3)
    cable = PowerImpedance.cable(parameters; length=25e3)
    @test overhead isa PowerImpedance.Element
    @test cable isa PowerImpedance.Element
    @test overhead.input_pins == overhead.output_pins == 3
    @test cable.input_pins == cable.output_pins == 3

    frequency = 100.0
    overhead_abcd = PowerImpedance.eval_abcd(overhead.element_model, 2pi * frequency * im)
    cable_abcd = PowerImpedance.eval_abcd(cable.element_model, 2pi * frequency * im)
    @test size(overhead_abcd) == (6, 6)
    @test overhead_abcd ≈ cable_abcd

    length_grid = PowerImpedance.cable(
        Grid,
        parameters;
        length=Grid([10e3, 20e3]),
    )
    @test [line.element_model.length for line in length_grid] == [10e3, 20e3]

    two_phase = deterministic_line_parameters(2; frequencies=[10.0, 100.0])
    line = PowerImpedance.cable(two_phase; length=1e3, transformation=true)
    midpoint_Z, midpoint_Y = LCM_EXT._line_parameters_at(line.element_model, 55.0)
    @test midpoint_Z ≈ 0.5 .* two_phase.Z[:, :, 1] .+ 0.5 .* two_phase.Z[:, :, 2]
    @test midpoint_Y ≈ 0.5 .* two_phase.Y[:, :, 1] .+ 0.5 .* two_phase.Y[:, :, 2]
    negative_Z, negative_Y = LCM_EXT._line_parameters_at(line.element_model, -55.0)
    @test negative_Z ≈ conj.(midpoint_Z)
    @test negative_Y ≈ conj.(midpoint_Y)
    @test_throws DomainError LCM_EXT._line_parameters_at(line.element_model, 1.0)

    projection = primitives(parameters, LineParametersInput())
    @test projection.series_impedance === parameters.Z
    @test projection.shunt_admittance === parameters.Y
    @test projection.frequencies === parameters.f
end

@testset "Measurements-dependent LineParameters sampling" begin
    parameters = measured_line_parameters(deterministic_line_parameters(1))
    @test NB._has_measurement(parameters)
    sampled = NB._sample_value(Xoshiro(11), parameters, :normal)
    @test sampled isa LineParameters
    @test eltype(sampled.Z) == ComplexF64
    @test !NB._has_measurement(sampled)

    first_rng = Xoshiro(42)
    second_rng = Xoshiro(42)
    first_samples = [NB._sample_value(first_rng, parameters, :normal) for _ in 1:16]
    second_samples = [NB._sample_value(second_rng, parameters, :normal) for _ in 1:16]
    @test Array.(getproperty.(first_samples, :Z)) ==
        Array.(getproperty.(second_samples, :Z))

    values = real.([sample.Z[1, 1, 1] for sample in first_samples])
    @test std(values) > 0

    grid = NB.cable(parameters; length=1e3)
    configuration = only(configurations(grid))
    numeric_line = rand(Xoshiro(7), configuration; distribution=:normal)
    @test !NB._contains_measurement(numeric_line)
end
