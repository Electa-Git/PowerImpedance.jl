module TerminalValuesTests
using Test, PowerImpedance
const PI = PowerImpedance
include("pscad/fixtures.jl")

@testset "Physical terminal values" begin
    ac = ACPortValues(2, 1//4, 3, 4f0)
    @test (ac.v, ac.theta, ac.p, ac.q) === (2.0, 0.25, 3.0, 4.0)
    @test PI.current(ac) === 5/3
    @test PI.current(ACPortValues(2.0, 0.0, -3.0, -4.0)) === 5/3
    @test isnan(ACPortValues(2, 0, 3, NaN).q)
    @test isnan(PI.current(ACPortValues(2, 0, 3, NaN)))
    dc = DCPortValues(4, -2//1)
    @test (dc.v, dc.p) === (4.0, -2.0)
    @test PI.current(dc) === -0.5
    @test PI.SetpointPU === PI.TerminalValuesPU
    @test PI.TerminalValuesPU() === PI.SetpointPU(0.0, 0.0, 0.0, 1.0, 0.0, 1.0)
    @test fieldtypes(PI.TerminalValuesPU) == ntuple(_ -> Float64, 6)
    @test all(name -> name ∉ names(PI),
        (:current, :TerminalValuesPU, :LinearizationCache))
    @test PI.PSCAD.steady_state === steady_state
end

empty_cache(cache) = all(f -> getfield(cache, f) === nothing, fieldnames(typeof(cache)))

@testset "State-space terminal values and retained state" begin
    for (factory, name) in ((PSCADFixtures.mmc_pq_network, :DUT),
            (PSCADFixtures.tlc_case1_network, :DUT),
            (PSCADFixtures.sm_network, :sg1), (PSCADFixtures.im_network, :im1))
        network = factory().classic
        power_flow(network)
        element = network.elements[name]
        model = element.element_model
        point = element.setpoint
        values = PI._terminal_values(model, point)
        @testset "$(nameof(typeof(model)))" begin
            direct = linearize(model, values)
            @test all(pair -> pair[1] === pair[2], zip(direct,
                (model.cache.A, model.cache.B, model.cache.C, model.cache.D)))
            legacy = PI.update(element, point)
            for (a, b) in zip(direct, legacy)
                @test size(a) == size(b)
                @test all(a .=== b)
            end
            @test all(model.cache.state .=== PI._steady_state(element))
            state = steady_state(model, values)
            ac = values.ac
            equal_values = merge(values, (; ac = ACPortValues(ac.v, ac.theta, ac.p, ac.q)))
            @test isequal(equal_values, values)
            @test steady_state(model, equal_values) === state
            @test model.cache.state === state

            for configured in (withinputs(model), component(model))
                @test configured.cache !== model.cache
                @test empty_cache(configured.cache)
                @test configured.elec === model.elec
            end
            changed = merge(values, (; ac = ACPortValues(ac.v, ac.theta + 0.001,
                ac.p, ac.q)))
            linearize(model, changed)
            changed_state = steady_state(model, changed)
            @test changed_state !== state
            @test isequal(model.cache.values, changed)
            @test steady_state(model, changed) === changed_state
            @test steady_state(model, values) !== changed_state
            @test isequal(model.cache.values, values)
            previous = model.cache.state
            linearize(model, values)
            @test model.cache.state !== previous
        end
    end
end

@testset "Configured cache ownership" begin
    model = synchronousmachine().element_model
    model.cache.values = (ac = ACPortValues(220sqrt(2/3), 0.0, 100.0, 0.0),)
    configured = withinputs(model; avr = (v_ref = 1.02,))
    @test configured.avr.v_ref === 1.02
    @test model.avr.v_ref === 1.01
    @test configured.cache !== model.cache
    @test empty_cache(configured.cache)

    configuration = first(configurations(tlc(Grid)))
    first_model = materialize(configuration).element_model
    second_model = materialize(configuration).element_model
    @test first_model.cache !== second_model.cache
    @test empty_cache(first_model.cache)
    @test empty_cache(second_model.cache)

end

@testset "Unknown synchronous-machine reactive power" begin
    model = synchronousmachine(avr = AVRSM(v_ref = 1.07)).element_model
    point = Setpoint(Vac = 220sqrt(2/3), θac = 0.17, Pac = 100.0)
    input, pu = PI.pftoinputs(model, point)
    values = (ac = ACPortValues(point.Vac, point.θac, point.Pac, NaN),)
    direct, direct_pu = PI.pftoinputs(model, values)
    @test input === direct
    @test pu === direct_pu === nothing
    @test direct.vref_SG === 1.07
    @test direct.Tm0 === point.Pac / model.elec.S_base
    @test direct.vd === point.Vac * cos(point.θac) / (model.elec.Vᵃᶜ_base * sqrt(2/3))
    @test direct.vq === -point.Vac * sin(point.θac) / (model.elec.Vᵃᶜ_base * sqrt(2/3))
end
end
