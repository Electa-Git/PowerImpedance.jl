module SteadyStateTests
using Test, PowerImpedance
include("pscad/fixtures.jl")
using .PSCADFixtures
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
    first_point = (ac = ACPortValues(1.0, 0.0, 1.25, 0.0),)
    second_point = (ac = ACPortValues(1.0, 0.0, 1.5, 0.0),)
    @test model.cache.state === nothing
    A, B, C, D = linearize(model, first_point)
    @test (A, B, C, D) == (reshape([-1.0], 1, 1), reshape([1.0], 1, 1),
        reshape([1.0], 1, 1), reshape([0.0], 1, 1))
    @test model.seeds[] == 1
    state = steady_state(model, first_point)
    @test state == [1.25]
    @test steady_state(model, first_point) === state
    @test model.seeds[] == 1
    state[1] = -10.0
    @test steady_state(model, first_point) == [-10.0]

    linearize(model, second_point)
    @test isequal(model.cache.values, second_point)
    @test steady_state(model, second_point) == [1.5]
    @test model.seeds[] == 2
    @test steady_state(model, first_point) == [1.25]
    @test model.seeds[] == 3
    linearize(model, second_point)
    @test isequal(model.cache.values, second_point)
    @test steady_state(model, second_point) == [1.5]
    @test (model.cache.A, model.cache.B, model.cache.C, model.cache.D) == (A, B, C, D)
    @test model.seeds[] == 4
    linearize(model, second_point)
    @test model.seeds[] == 5

    model.fail[] = true
    @test_throws ErrorException linearize(model, first_point)
    @test isequal(model.cache.values, second_point)
    model.fail[] = false
    @test steady_state(model, second_point) == [1.5]
    replacement = RecordedState(Ref(0), Ref(false), PI.LinearizationCache())
    @test replacement.cache.state === nothing
    @test steady_state(replacement, second_point) == [1.5]
    @test replacement.seeds[] == 1

    # Preserve the exact vector used for the core's small-value zeroing.
    tiny = (ac = ACPortValues(1.0, 0.0, 1e-16, 0.0),)
    linearize(model, tiny)
    @test isequal(steady_state(model, tiny), [0.0])
end

@testset "PSCAD consumes retained converter states" begin
    for factory in (PSCADFixtures.tlc_case1_network, PSCADFixtures.tlc_case2_network,
            PSCADFixtures.tlc_vac_network, PSCADFixtures.mmc_pq_network,
            PSCADFixtures.mmc_vdc_network, PSCADFixtures.mmc_pf_network,
            PSCADFixtures.mmc_qv_network, PSCADFixtures.mmc_vac_network)
        fixture = factory()
        solved = NB.solve(fixture)
        builder = NB.NetworkModel(fixture, solved.operating_point)
        @test Set(keys(builder.indices.elements)) == Set(name
            for (name, model) in pairs(fixture.elements) if !PI.is_source(model))
        list = P.netlist(fixture, solved)
        for e in list.elements
            PI.is_converter(e.model) || continue
            model = e.model
            point = e.values
            saved = model.cache.state
            @test saved !== nothing
            retained = copy(saved)
            vector = steady_state(model, point)
            @test vector === saved
            equilibrium = P.converter_equilibrium(e)
            @test isequal(collect(values(equilibrium.states)), retained)
            @test model.cache.state === saved
            @test isequal(collect(values(P.converter_equilibrium(e).states)), retained)
            @test model.cache.state === saved
            @test isequal(vector, retained)
            @test model.cache.state === saved
            @test isequal(steady_state(model, point), retained)
            @test model.cache.state === saved
            inputs, sp = PI.pftoinputs(model, point)
            residual = zeros(length(vector))
            PI._state_space!(residual, vector, collect(values(inputs)), sp,
                model, PI.Equil())
            @test maximum(abs, residual) <= 1e-6
            @test model === fixture.elements[e.name]
        end
        name = first(name for (name, model) in pairs(fixture.elements)
            if PI.is_converter(model))
        entry = only(filter(e -> e.name == name, list.elements))
        original = entry.model.cache.state
        fresh = PI.Parameters.reconstruct(deepcopy(fixture.elements[name]);
            cache = PI.LinearizationCache())
        @test fresh !== entry.model
        converter = P.NetlistElement(name, entry.pscad, fresh, entry.ports,
            entry.terminals, entry.role, entry.values)
        @test fresh.cache.state === nothing
        initial = P.converter_equilibrium(converter)
        saved = fresh.cache.state
        @test saved !== nothing
        @test isequal(P.converter_equilibrium(converter).states, initial.states)
        @test fresh.cache.state === saved
        @test fresh.cache.state !== entry.model.cache.state
        @test entry.model.cache.state === original
    end
end
end
