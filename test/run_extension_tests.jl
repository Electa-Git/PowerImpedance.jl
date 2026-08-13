using Test
using Logging
using Random
using Measurements
using PowerImpedanceACDC
using PowerImpedanceACDC.NetworkBuilder: ⟷

const NB = PowerImpedanceACDC.NetworkBuilder
Logging.global_logger(ConsoleLogger(stderr, Logging.Warn))

function uncertain_builder(axis)
    elements = (
        z1 = NB.impedance(z = axis, pins = 1),
        z2 = NB.impedance(z = 20.0, pins = 1),
    )
    connections = (
        NB.pin(:z1, 1, 1) ⟷ NB.pin(:z2, 1, 1) ⟷ :n1,
        NB.pin(:z1, 2, 1) ⟷ NB.pin(:z2, 2, 1) ⟷ :gnd,
    )
    return NB.define(elements, connections)
end

function impedance_study(axis; kwargs...)
    return NB.determine_impedance(
        uncertain_builder(axis);
        nets = [:n1],
        freq_range = (1.0, 10.0, 2),
        kwargs...,
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
        seed = 456,
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
        (:failure_axis,),
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
