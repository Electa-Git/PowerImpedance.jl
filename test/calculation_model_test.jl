using PowerImpedance
using Test

const CALCULATION_NB = PowerImpedance.NetworkBuilder

function passive_calculation_state()
    elements = (
        branch = impedance(z = 2.0, pins = 1),
        shunt = impedance(z = 4.0, pins = 1)
    )
    connections = (
        (node = :bus, element = :branch, side = 1, terminal = 1),
        (node = :bus, element = :shunt, side = 1, terminal = 1),
        (node = :gnd, element = :branch, side = 2, terminal = 1),
        (node = :gnd, element = :shunt, side = 2, terminal = 1)
    )
    return CALCULATION_NB.define(elements, connections)
end

@testset "Problem, formulation, and result calculations" begin
    state = passive_calculation_state()
    powerflow = compute(
        CALCULATION_NB.PowerFlowProblem(state),
        CALCULATION_NB.ACDCPowerFlow()
    )
    @test powerflow isa PowerFlowResult
    @test powerflow.result === nothing
    @test powerflow.active_setpoint_values == Dict{Symbol, Setpoint}()
    @test convert(OperatingPoint, powerflow) === powerflow.operating_point

    linearization = compute(
        CALCULATION_NB.LinearizationProblem(state, powerflow),
        CALCULATION_NB.AdmittanceLinearization()
    )
    @test linearization isa LinearizationResult
    @test linearization.network_model isa CALCULATION_NB.NetworkModel
    @test linearization.operating_point === powerflow.operating_point

    model = linearization.network_model
    frequency_range = (1.0, 100.0, 5)
    state_problem = PowerImpedanceProblem(
        state;
        nodes = [:bus],
        frequency_range
    )
    model_problem = PowerImpedanceProblem(
        model;
        nodes = [:bus],
        frequency_range
    )

    for formulation in (
        NodalImpedance(),
        NodeAdmittance(),
        EdgeAdmittance(),
        LoopGain()
    )
        from_state = compute(state_problem, formulation)
        from_model = compute(model_problem, formulation)
        @test from_state isa FrequencyResponseResult
        @test from_state.response ≈ from_model.response
        @test from_state.frequencies == from_model.frequencies
        @test from_state.nodes == [:bus]
    end

    impedance_result = compute(state_problem, NodalImpedance())
    impedance, frequencies = determine_impedance(
        state;
        nets = [:bus],
        freq_range = frequency_range
    )
    @test impedance_result.response ≈ impedance
    @test impedance_result.frequencies == frequencies

    node_result = compute(state_problem, NodeAdmittance())
    edge_result = compute(state_problem, EdgeAdmittance())
    loop_result = compute(state_problem, LoopGain())
    @test first(CALCULATION_NB.make_y_node(
        state;
        nodelist = [:bus],
        freq_range = frequency_range
    )) ≈ node_result.response
    @test first(CALCULATION_NB.make_y_edge(
        state;
        nodelist = [:bus],
        freq_range = frequency_range
    )) ≈ edge_result.response
    @test first(CALCULATION_NB.make_loopgain(
        state;
        nodelist = [:bus],
        freq_range = frequency_range
    )) ≈ loop_result.response

    bode = compute(StabilityProblem(edge_result), BodeAnalysis())
    gain = compute(
        StabilityProblem((node_result, edge_result)),
        SmallGainAnalysis()
    )
    @test bode isa StabilityResult
    @test bode.analysis == :bode
    @test gain isa StabilityResult
    @test gain.analysis == :small_gain
    @test bodeplot(edge_result) !== nothing
    @test small_gain(node_result, edge_result) !== nothing
end

@testset "Parametric problem enumeration" begin
    connections = (
        (node = :bus, element = :branch, side = 1, terminal = 1),
        (node = :gnd, element = :branch, side = 2, terminal = 1)
    )
    space = CALCULATION_NB.define(
        (branch = CALCULATION_NB.impedance(
            z = CALCULATION_NB.Grid([1.0, 2.0]),
            pins = 1
        ),),
        connections
    )
    problem = ParametricProblem(
        space,
        NodalImpedance(),
        (nets = [:bus], freq_range = (1.0, 10.0, 3))
    )
    result = compute(problem, Combinatorial())
    @test result isa CALCULATION_NB.ParametricImpedance
    @test length(result) == 2
    @test all(case -> size(case.impedance) == (1, 1, 3), result)

    edge_response = compute(
        ParametricProblem(
            space,
            EdgeAdmittance(),
            (nodelist = [:bus], freq_range = (1.0, 10.0, 3))
        ),
        Combinatorial()
    )
    @test edge_response isa CALCULATION_NB.ParametricFrequencyResponse
    for (formulation, options) in (
        (GeneralizedNyquist(), (display_plot = false,)),
        (BodeAnalysis(), (display_plot = false,)),
        (PassivityAnalysis(), (display_plot = false,)),
        (
        EigenvalueAnalysis(),
        (fmin = 1.0, fmax = 10.0, display_plot = false)
    )
    )
        stability = compute(StabilityProblem(edge_response; options), formulation)
        @test stability isa CALCULATION_NB.ParametricStability
        @test length(stability) == 2
    end
    gain = compute(
        StabilityProblem(
            (edge_response, edge_response);
            options = (display_plot = false,)
        ),
        SmallGainAnalysis()
    )
    @test gain isa CALCULATION_NB.ParametricStability
    @test length(gain) == 2

    uncertain_space = CALCULATION_NB.define(
        (branch = CALCULATION_NB.impedance(
            z = CALCULATION_NB.Grid(1.0, 5.0),
            pins = 1
        ),),
        connections
    )
    @test_throws ArgumentError compute(
        ParametricProblem(
            uncertain_space,
            NodalImpedance(),
            (nets = [:bus], freq_range = (1.0, 10.0, 3))
        ),
        Combinatorial()
    )
end
