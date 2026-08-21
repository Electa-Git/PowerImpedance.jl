using Test
using Measurements
using PowerImpedance

const NB = PowerImpedance.NetworkBuilder

function uncertain_impedance_space(; shared=false)
    key = shared ? :shared : nothing
    elements = (
        z=NB.impedance(z=Grid(2.0, 5.0; key), pins=1),
    )
    connections = (
        (node=:bus, element=:z, side=1, terminal=1),
        (node=:gnd, element=:z, side=2, terminal=1),
    )
    return NB.define(elements, connections)
end

@testset "Measurements grammar materialization" begin
    @test Base.get_extension(PowerImpedance, :PowerImpedanceMeasurementsExt) !== nothing
    space = Gridspace{Tuple}(
        (x, y) -> (x, y),
        (Grid(10.0, 5.0; key=:shared), Grid(20.0, 5.0; key=:shared)),
        (:x, :y),
    )
    x, y = materialize(only(configurations(space)))
    @test Measurements.value(x) == 10.0
    @test Measurements.value(y) == 20.0
    @test Measurements.uncertainty(x) == 0.5
    @test Measurements.uncertainty(y) == 1.0
    @test Measurements.cov(x, y) == 0.5
end

@testset "LinearError frequency response" begin
    space = uncertain_impedance_space()
    problems = PowerImpedanceProblem(
        space;
        nodes=[:bus],
        frequency_range=(1.0, 10.0, 3),
    )
    result = compute(
        ParametricProblem(problems),
        LinearError(NodalImpedance()),
    )
    @test result isa LinearErrorResult{<:FrequencyResponseResult}
    @test length(result.values) == length(result.space) == 1
    response = only(result.values).response
    @test eltype(response) <: Complex{<:Measurements.Measurement}
    @test Measurements.value(real(response[1])) ≈ 2.0
    @test Measurements.uncertainty(real(response[1])) ≈ 0.1 rtol=1e-6
    @test result.details.propagation === :first_order
    @test primitives(only(result.values), MeasurementsSurrogate()).response === response
end

@testset "Local Monte Carlo power-flow coupling" begin
    space = uncertain_impedance_space()
    result = compute(
        ParametricProblem(PowerFlowProblem(space)),
        MonteCarlo(ACDCPowerFlow(); trials=4, seed=17, return_samples=true),
    )
    @test result isa MonteCarloResult{<:PowerFlowResult}
    @test result.stats.n == 4
    @test result.details.coupling == (
        method=:local_monte_carlo,
        solver_inputs=:numeric_realizations,
        reconstructed=:bus_measurements,
    )
    @test all(value -> !NB._contains_measurement(value.data),
        result.details.samples.values)

    formulation = ACDCPowerFlow()
    trials = [
        PowerFlowResult(
            formulation,
            Dict("solution" => Dict("bus" => Dict("1" => Dict("vm" => value)))),
            nothing,
            Dict{Symbol,Tuple{Symbol,Int}}(),
            Dict{Symbol,Any}(),
            OperatingPoint(),
            (;),
        )
        for value in (0.9, 1.0, 1.1)
    ]
    buses = PowerImpedance._powerflow_bus_measurements(trials)
    voltage = buses["bus"]["1"]["vm"]
    @test Measurements.value(voltage) == 1.0
    @test Measurements.uncertainty(voltage) ≈ 0.1
end

@testset "Monte Carlo sample retention" begin
    problems = PowerImpedanceProblem(
        uncertain_impedance_space();
        nodes=[:bus],
        frequency_range=(1.0, 10.0, 2),
    )
    discarded = compute(
        ParametricProblem(problems),
        MonteCarlo(NodalImpedance(); trials=3, seed=21),
    )
    retained = compute(
        ParametricProblem(problems),
        MonteCarlo(NodalImpedance(); trials=3, seed=21, return_samples=true),
    )
    @test discarded.details.samples === nothing
    @test retained.details.samples !== nothing
    @test length(only(discarded.details.plot_data.values)) == 3
    @test primitives(retained, EmpiricalSamples()) === retained.details.samples
end
