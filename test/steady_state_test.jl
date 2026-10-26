module SteadyStateTests
using Test, PowerImpedance
include("pscad/fixtures.jl")
using .PSCADFixtures
const PI = PowerImpedance
const NB = PI.NetworkBuilder
const P = PI.PSCAD

struct RecordedState <: PI.AbstractStateSpace
    seeds::Base.RefValue{Int}
    outputs::Base.RefValue{Int}
    fail::Base.RefValue{Bool}
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
function PI.outputequations!(F, x, inputs, y, model::RecordedState)
    model.outputs[] += 1
    F[1] = y.y
end

@testset "Equilibrium recomputation without output differentiation" begin
    model = RecordedState(Ref(0), Ref(0), Ref(false))
    first_point = (ac = ACPortValues(1.0, 0.0, 1.25, 0.0),)
    second_point = (ac = ACPortValues(1.0, 0.0, 1.5, 0.0),)
    lin = linearize(model, first_point)
    A, B, C, D = lin.system.A, lin.system.B, lin.system.C, lin.system.D
    @test (A, B, C, D) == (reshape([-1.0], 1, 1), reshape([1.0], 1, 1),
        reshape([1.0], 1, 1), reshape([0.0], 1, 1))
    @test model.seeds[] == 1
    @test model.outputs[] > 0
    differentiated = model.outputs[]
    state = steady_state(model, first_point)
    @test state == lin.state == [1.25]
    @test model.seeds[] == 2
    @test steady_state(model, first_point) == state
    @test model.seeds[] == 3
    state[1] = -10.0
    @test steady_state(model, first_point) == [1.25]
    @test steady_state(model, second_point) == [1.5]
    @test model.seeds[] == 5
    @test model.outputs[] == differentiated
    @test lin.state == [1.25]
    second = linearize(model, second_point)
    @test second.state == [1.5]
    @test lin.state == [1.25]
    @test second.system == lin.system
    @test model.seeds[] == 6
    model.fail[] = true
    @test_throws ErrorException linearize(model, first_point)
    @test_throws ErrorException steady_state(model, first_point)
    @test second.state == [1.5]
    model.fail[] = false
    @test steady_state(model, second_point) == [1.5]
    tiny = (ac = ACPortValues(1.0, 0.0, 1e-16, 0.0),)
    @test isequal(linearize(model, tiny).state, steady_state(model, tiny))
    @test isequal(steady_state(model, tiny), [0.0])
end

@testset "PSCAD computes converter equilibria without changing models" begin
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
            before = repr(model)
            point = e.values
            lin = linearize(model, point)
            vector = steady_state(model, point)
            @test isequal(vector, lin.state)
            equilibrium = P.converter_equilibrium(e)
            @test isequal(collect(values(equilibrium.states)), vector)
            @test isequal(P.converter_equilibrium(e).states, equilibrium.states)
            @test repr(model) == before
            inputs, sp = PI.pftoinputs(model, point)
            residual = zeros(length(vector))
            PI._state_space!(residual, vector, collect(values(inputs)), sp,
                model, PI.Equil())
            @test maximum(abs, residual) <= 1e-6
            @test model === fixture.elements[e.name]
            vector[1] = -123.0
            @test isequal(collect(values(P.converter_equilibrium(e).states)), lin.state)
            @test repr(model) == before
        end
    end
end
end
