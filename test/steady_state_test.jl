module SteadyStateTests
using Test, PowerImpedance
using ..PSCADFixtures
const PI = PowerImpedance
const NB = PI.NetworkBuilder
const P = PI.PSCAD

struct RecordedState <: PI.AbstractStateSpace
    seeds::Base.RefValue{Int}
    fail::Base.RefValue{Bool}
    cache::PI.LinearizationCache
end
PI.statenames(::RecordedState) = (:x,)
PI.inputnames(::RecordedState) = (:u,)
PI.outputnames(::RecordedState) = (:y,)
PI._terminal_values(::RecordedState, sp::Setpoint) =
    (ac = ACPortValues(1.0, 0.0, sp.Pac, 0.0),)
PI.pftoinputs(::RecordedState, values::NamedTuple) = ((; u=values.ac.p), nothing)
function PI.initialvalues(model::RecordedState; kwargs...)
    model.seeds[] += 1
    model.fail[] && error("initialization failure")
    return (; x=0.0)
end
function PI.state_space!(F, x, inputs, ::RecordedState)
    F[1] = inputs.u - x.x
    return (; y=x.x)
end
PI.outputequations!(F, x, inputs, y, ::RecordedState) = (F[1] = y.y)

@testset "Core retained steady state lifecycle" begin
    model = RecordedState(Ref(0), Ref(false), PI.LinearizationCache())
    first_point = Setpoint(Pac=1.25)
    second_point = Setpoint(Pac=1.5)
    element = PI.Element(; element_model=model, input_pins=1, output_pins=1,
        setpoint=first_point)
    @test :_steady_state ∉ names(PI)
    @test_throws ArgumentError PI._steady_state(element)
    A, B, C, D = PI.update(element, first_point)
    @test (A, B, C, D) == (reshape([-1.0], 1, 1), reshape([1.0], 1, 1),
        reshape([1.0], 1, 1), reshape([0.0], 1, 1))
    @test model.seeds[] == 1
    state = PI._steady_state(element)
    @test state == [1.25]
    @test PI._steady_state(element, first_point) == state
    @test model.seeds[] == 1
    state[1] = -10.0
    @test PI._steady_state(element) == [1.25]

    # The matrix-returning update used by builder linearization also retains
    # its solved state, without changing the element's declared setpoint.
    PI.update(element, second_point)
    @test isequal(element.setpoint, first_point)
    @test PI._steady_state(element) == [1.5]
    @test model.seeds[] == 2
    @test PI._steady_state(element, first_point) == [1.25]
    @test model.seeds[] == 3
    PI.update!(element, second_point)
    @test isequal(element.setpoint, second_point)
    @test PI._steady_state(element) == [1.5]
    @test (element.A, element.B, element.C, element.D) == (A, B, C, D)
    @test model.seeds[] == 4
    PI.update!(element, second_point)
    @test model.seeds[] == 5

    model.fail[] = true
    @test_throws ErrorException PI.update(element, first_point)
    @test_throws ArgumentError PI._steady_state(element)
    model.fail[] = false
    @test PI._steady_state(element, second_point) == [1.5]
    replacement = RecordedState(Ref(0), Ref(false), PI.LinearizationCache())
    element.element_model = replacement
    @test_throws ArgumentError PI._steady_state(element)
    @test PI._steady_state(element, second_point) == [1.5]
    @test replacement.seeds[] == 1

    # Preserve the exact vector used for the core's small-value zeroing.
    PI.update!(element, Setpoint(Pac=1e-16))
    @test isequal(PI._steady_state(element), [0.0])
end

@testset "PSCAD consumes retained converter states" begin
    for factory in (PSCADFixtures.tlc_case1_network, PSCADFixtures.tlc_case2_network,
            PSCADFixtures.tlc_vac_network, PSCADFixtures.mmc_pq_network,
            PSCADFixtures.mmc_vdc_network, PSCADFixtures.mmc_pf_network,
            PSCADFixtures.mmc_qv_network, PSCADFixtures.mmc_vac_network)
        fixture = factory()
        pf = power_flow(fixture.classic)
        classic = P.netlist(fixture.classic, pf)
        solved = NB.solve(fixture.state)
        elements = NamedTuple{keys(fixture.state.elements)}(
            Tuple(solved.network.elements[name] for name in keys(fixture.state.elements)))
        builder = P.netlist(fixture.state, solved.powerflow, elements)
        @test [e.name for e in builder.elements] == collect(keys(fixture.state.elements))
        for list in (classic, builder), e in list.elements
            e.model isa Union{PI.MMC, PI.TLC} || continue
            saved = e.element._equilibrium
            @test saved !== nothing
            vector = PI._steady_state(e.element)
            equilibrium = P.converter_equilibrium(e)
            @test isequal(collect(values(equilibrium.states)), vector)
            @test e.element._equilibrium === saved
            @test isequal(collect(values(P.converter_equilibrium(e).states)), vector)
            @test e.element._equilibrium === saved
            residual = zeros(length(vector))
            PI._state_space!(residual, vector, collect(values(equilibrium.inputs)),
                equilibrium.setpoint_pu, e.model, PI.Equil())
            @test maximum(abs, residual) <= 1e-6
            if list === builder
                @test e.element === solved.network.elements[e.name]
                @test e.element !== fixture.state.elements[e.name]
                @test fixture.state.elements[e.name]._equilibrium === nothing
            end
        end
        # A direct netlist of declared builder elements has no stored solve;
        # the accessor obtains it once through the core and then reuses it.
        declared = P.netlist(fixture.state, solved.powerflow)
        converter = first(e for e in declared.elements if e.model isa Union{PI.MMC, PI.TLC})
        @test converter.element._equilibrium === nothing
        initial = P.converter_equilibrium(converter)
        saved = converter.element._equilibrium
        @test saved !== nothing
        @test isequal(P.converter_equilibrium(converter).states, initial.states)
        @test converter.element._equilibrium === saved
    end
end
end
