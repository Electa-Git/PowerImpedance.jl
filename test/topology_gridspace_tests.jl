using Test
using Measurements
using PowerImpedance

const TOPOLOGY_NB = PowerImpedance.NetworkBuilder
if !isdefined(@__MODULE__, :PI)
    const PI = PowerImpedance
end
if !isdefined(@__MODULE__, :NB)
    const NB = TOPOLOGY_NB
end

function copied_space(value; uncertain = false)
    axis = uncertain ? TOPOLOGY_NB.Grid(0.0, AbsoluteError(0.0)) :
           TOPOLOGY_NB.Grid(nothing)
    return TOPOLOGY_NB.Gridspace{typeof(value)}(
        _ -> deepcopy(value),
        (axis,),
        (:zero_uncertainty_probe,),
    )
end

function copied_element_spaces(elements)
    spaces = map(copied_space, elements)
    probe_name = first(keys(elements))
    probe = copied_space(elements[probe_name]; uncertain = true)
    return merge(spaces, NamedTuple{(probe_name,)}((probe,)))
end

function assert_zero_uncertainty_impedance(result, reference, frequencies)
    @test result isa LinearErrorResult{<:FrequencyResponseResult}
    case = only(result.values)
    @test case.frequencies == frequencies
    @test size(case.response) == size(reference)
    @test Measurements.value.(real.(case.response)) ≈ real.(reference)
    @test Measurements.value.(imag.(case.response)) ≈ imag.(reference)
    @test all(iszero, Measurements.uncertainty.(real.(case.response)))
    @test all(iszero, Measurements.uncertainty.(imag.(case.response)))
end

function zero_uncertainty_response(
    builders;
    nodes,
    eliminated_elements,
    frequency_range,
)
    problems = PowerImpedanceProblem(
        builders;
        nodes,
        eliminated_elements,
        frequency_range,
    )
    return compute(
        ParametricProblem(problems),
        LinearError(NodalImpedance()),
    )
end

@testset "IEEE39 zero-uncertainty Gridspace" begin
    if !isdefined(@__MODULE__, :ieee39bus_elements)
        include("fixtures/ieee39bus.jl")
    end

    options = (;
        voltageBase = Vm1,
        power_flow = (; is_bounded = (; bus_voltage = true)),
    )
    builders = TOPOLOGY_NB.define(
        copied_element_spaces(ieee39bus_elements()),
        ieee39bus_connections();
        options,
        exclude = (:T8_9,),
    )
    scalar = only(builders)
    model = compute(
        LinearizationProblem(scalar),
        AdmittanceLinearization(),
    ).network_model
    reference, frequencies = TOPOLOGY_NB.determine_impedance(
        model;
        nets = IEEE39_INPUT_PINS,
        elim_elements = IEEE39_ELIM_ELEMENTS,
        freq_range = (1.0, 5e3, 2),
    )
    result = zero_uncertainty_response(
        builders;
        nodes=IEEE39_INPUT_PINS,
        eliminated_elements=IEEE39_ELIM_ELEMENTS,
        frequency_range=(1.0, 5e3, 2),
    )
    assert_zero_uncertainty_impedance(result, reference, frequencies)
end

@testset "P2P HVDC zero-uncertainty Gridspace" begin
    include("parity/fixtures.jl")
    fixture = ParityFixtures.P2PAlt
    elements = fixture.ohl_to_ugc(0.5)
    builders = TOPOLOGY_NB.define(copied_element_spaces(elements), fixture.connections;
        options = fixture.builder_options)
    scalar = only(builders)
    model = compute(
        LinearizationProblem(scalar),
        AdmittanceLinearization(),
    ).network_model
    reference, frequencies = TOPOLOGY_NB.determine_impedance(
        model;
        nets = [:B5],
        elim_elements = [:c2],
        freq_range = (100.0, 5e3, 2),
    )
    result = zero_uncertainty_response(
        builders;
        nodes=[:B5],
        eliminated_elements=[:c2],
        frequency_range=(100.0, 5e3, 2),
    )
    assert_zero_uncertainty_impedance(result, reference, frequencies)
end
