using Test
using Measurements
using PowerImpedance

const TOPOLOGY_NB = PowerImpedance.NetworkBuilder
const PI = PowerImpedance
if !isdefined(@__MODULE__, :NB)
    const NB = TOPOLOGY_NB
end

function copied_space(value; uncertain = false)
    axis = uncertain ? TOPOLOGY_NB.Grid(0.0 ± 0.0) : TOPOLOGY_NB.Grid(nothing)
    return TOPOLOGY_NB.Gridspace{typeof(value)}(
        _ -> deepcopy(value),
        (axis,),
        (:zero_uncertainty_probe,),
    )
end

function copied_element_spaces(elements)
    spaces = map(copied_space, elements)
    probe_name = first(keys(elements))
    return merge(spaces, NamedTuple{(probe_name,)}((copied_space(elements[probe_name]; uncertain = true),)))
end

function include_fixture_definitions(path)
    skip_testsets(expression) = if expression isa Expr &&
                                   expression.head === :macrocall &&
                                   expression.args[1] === Symbol("@testset")
        :(nothing)
    else
        expression
    end
    return Base.include(skip_testsets, @__MODULE__, path)
end

function assert_zero_uncertainty_impedance(case, reference, frequencies; trials = 1000)
    @test case.trials == trials
    @test case.frequencies == frequencies
    @test size(case.impedance) == size(reference)
    @test Measurements.value.(real.(case.impedance)) ≈ real.(reference)
    @test Measurements.value.(imag.(case.impedance)) ≈ imag.(reference)
    @test all(iszero, Measurements.uncertainty.(real.(case.impedance)))
    @test all(iszero, Measurements.uncertainty.(imag.(case.impedance)))
end

@testset "IEEE39 zero-uncertainty Gridspace" begin
    if !isdefined(Main, :ieee39bus_elements)
        include_fixture_definitions(joinpath(@__DIR__, "NetworkBuilder_test.jl"))
    end

    options = (;
        voltageBase = Vm1,
        power_flow = (; is_bounded = (; bus_voltage = true)),
    )
    builders = TOPOLOGY_NB.define(
        copied_element_spaces(ieee39bus_elements()),
        ieee39bus_connections();
        options,
    )
    scalar = only(builders)
    reference, frequencies = TOPOLOGY_NB.determine_impedance(
        convert(scalar, TOPOLOGY_NB.NetworkModel);
        nets = IEEE39_INPUT_PINS,
        elim_elements = IEEE39_ELIM_ELEMENTS,
        freq_range = (1.0, 5e3, 2),
    )
    result = TOPOLOGY_NB.determine_impedance(
        builders;
        trials = 1000,
        seed = 39,
        nets = IEEE39_INPUT_PINS,
        elim_elements = IEEE39_ELIM_ELEMENTS,
        freq_range = (1.0, 5e3, 2),
    )
    assert_zero_uncertainty_impedance(only(result), reference, frequencies)
end

@testset "P2P HVDC zero-uncertainty Gridspace" begin
    include(joinpath(@__DIR__, "..", "examples", "P2P_HVDC_ALT.jl"))
    elements = ohl_to_ugc(0.5)
    builders = TOPOLOGY_NB.define(copied_element_spaces(elements), connections; options = builder_options)
    scalar = only(builders)
    reference, frequencies = TOPOLOGY_NB.determine_impedance(
        convert(scalar, TOPOLOGY_NB.NetworkModel);
        nets = [:B5],
        elim_elements = [:c2],
        freq_range = (100.0, 5e3, 2),
    )
    result = TOPOLOGY_NB.determine_impedance(
        builders;
        trials = 1000,
        seed = 17,
        nets = [:B5],
        elim_elements = [:c2],
        freq_range = (100.0, 5e3, 2),
    )
    assert_zero_uncertainty_impedance(only(result), reference, frequencies)
end
