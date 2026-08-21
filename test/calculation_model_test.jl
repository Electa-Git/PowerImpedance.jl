using PowerImpedance
using Test

const CALCULATION_NB = PowerImpedance.NetworkBuilder

function passive_calculation_state(; impedance_value=2.0)
    elements = (
        branch=impedance(z=impedance_value, pins=1),
        shunt=impedance(z=4.0, pins=1),
    )
    connections = (
        (node=:bus, element=:branch, side=1, terminal=1),
        (node=:bus, element=:shunt, side=1, terminal=1),
        (node=:gnd, element=:branch, side=2, terminal=1),
        (node=:gnd, element=:shunt, side=2, terminal=1),
    )
    return CALCULATION_NB.define(elements, connections)
end

@testset "Primitive result contracts" begin
    state = passive_calculation_state()
    original_impedance = copy(state.elements.branch.element_model.value)
    powerflow = compute(PowerFlowProblem(state), ACDCPowerFlow())
    @test powerflow isa PowerFlowResult
    @test fieldnames(typeof(powerflow)) == (
        :formulation,
        :result,
        :data,
        :nodes2bus,
        :elem2comp,
        :operating_point,
        :diagnostics,
    )
    @test powerflow.result === nothing
    @test convert(OperatingPoint, powerflow) === powerflow.operating_point
    @test state.elements.branch.element_model.value == original_impedance

    linearization = compute(LinearizationProblem(state, powerflow),
        AdmittanceLinearization())
    @test linearization isa LinearizationResult
    @test fieldnames(typeof(linearization)) == (
        :formulation,
        :network_model,
        :operating_point,
        :diagnostics,
    )
    @test linearization.network_model isa CALCULATION_NB.NetworkModel
    @test linearization.operating_point === powerflow.operating_point

    frequency_range = (1.0, 100.0, 5)
    state_problem = PowerImpedanceProblem(state; nodes=[:bus], frequency_range)
    model_problem = PowerImpedanceProblem(
        linearization.network_model;
        nodes=[:bus],
        frequency_range,
    )
    for formulation in (NodalImpedance(), NodeAdmittance(), EdgeAdmittance(), LoopGain())
        from_state = compute(state_problem, formulation)
        from_model = compute(model_problem, formulation)
        @test from_state isa FrequencyResponseResult
        @test fieldnames(typeof(from_state)) == (
            :formulation,
            :kind,
            :response,
            :frequencies,
            :nodes,
            :network_model,
            :diagnostics,
        )
        @test from_state.response ≈ from_model.response
        @test from_state.frequencies == from_model.frequencies
        @test from_state.nodes == [:bus]
    end

    edge = compute(state_problem, EdgeAdmittance())
    node = compute(state_problem, NodeAdmittance())
    loop = compute(state_problem, LoopGain())
    analyses = (
        compute(StabilityProblem(loop), GeneralizedNyquist()),
        compute(StabilityProblem(edge), BodeAnalysis()),
        compute(StabilityProblem(edge), PassivityAnalysis()),
        compute(StabilityProblem((node, edge)), SmallGainAnalysis()),
        compute(StabilityProblem(edge), EigenvalueAnalysis(fmin=1.0, fmax=100.0)),
        compute(StabilityProblem(loop), UnstableFrequencyAnalysis()),
    )
    @test all(result -> result isa StabilityResult, analyses)
    @test fieldnames(StabilityResult) == (:formulation, :analysis, :output, :diagnostics)
    @test all(result -> !hasproperty(result, :plots), analyses)
end

function calculation_space(axis)
    connections = (
        (node=:bus, element=:branch, side=1, terminal=1),
        (node=:gnd, element=:branch, side=2, terminal=1),
    )
    return CALCULATION_NB.define(
        (branch=CALCULATION_NB.impedance(z=axis, pins=1),),
        connections,
    )
end

@testset "Composite execution and checkpoints" begin
    deterministic = calculation_space(Grid([1.0, 2.0]))
    owned = PowerImpedanceProblem(
        deterministic;
        nodes=[:bus],
        frequency_range=(1.0, 10.0, 3),
    )
    response = compute(
        ParametricProblem(owned),
        Combinatorial(NodalImpedance()),
    )
    @test response isa ParametricResult{<:FrequencyResponseResult}
    @test length(response.values) == length(response.space) == 2
    @test all(value -> size(value.response) == (1, 1, 3), response.values)

    edge_response = compute(
        ParametricProblem(owned),
        Combinatorial(EdgeAdmittance()),
    )
    checkpoint = preprocess(edge_response, BodeAnalysis())
    bode = compute(checkpoint, Combinatorial(BodeAnalysis()))
    @test bode isa ParametricResult{<:StabilityResult}
    @test all(value -> value.analysis === :bode, bode.values)

    uncertain = calculation_space(Grid(1.0, 5.0))
    uncertain_owned = PowerImpedanceProblem(
        uncertain;
        nodes=[:bus],
        frequency_range=(1.0, 10.0, 3),
    )
    @test_throws ArgumentError compute(
        ParametricProblem(uncertain_owned),
        Combinatorial(NodalImpedance()),
    )
    monte_carlo = compute(
        ParametricProblem(uncertain_owned),
        MonteCarlo(NodalImpedance(); trials=4, seed=42),
    )
    @test monte_carlo isa MonteCarloResult{<:FrequencyResponseResult}
    @test monte_carlo.stats.n == 4
    @test monte_carlo.details.samples === nothing
    @test length(only(monte_carlo.details.plot_data.values)) == 4

    stability_checkpoint = preprocess(monte_carlo, BodeAnalysis())
    monte_carlo_bode = compute(
        stability_checkpoint,
        MonteCarlo(BodeAnalysis(); seed=42),
    )
    @test monte_carlo_bode isa MonteCarloResult{<:StabilityResult}
    @test monte_carlo_bode.stats.n == 4
    @test length(only(monte_carlo_bode.details.plot_data.values)) == 4
end

@testset "Explicit checkpoint boundaries" begin
    result = compute(
        PowerImpedanceProblem(
            passive_calculation_state();
            nodes=[:bus],
            frequency_range=(1.0, 10.0, 2),
        ),
        NodalImpedance(),
    )
    @test_throws ArgumentError primitives(result, EmpiricalSamples())
    @test_throws ArgumentError preprocess(result, LineParametersInput())
end
