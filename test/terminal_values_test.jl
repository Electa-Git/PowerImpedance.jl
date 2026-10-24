module TerminalValuesTests
using Test, PowerImpedance
const PI = PowerImpedance
include("parity/fixtures.jl")
using .ParityFixtures: PSCADFixtures
include("manual/pscad/validation/classic_fixtures.jl")

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
    @test !isdefined(PI, :SetpointPU)
    @test PI.TerminalValuesPU() === PI.TerminalValuesPU(0.0, 0.0, 0.0, 1.0, 0.0, 1.0)
    @test fieldtypes(PI.TerminalValuesPU) == ntuple(_ -> Float64, 6)
    @test all(name -> name ∉ names(PI),
        (:current, :TerminalValuesPU, :LinearizationCache))
    @test PI.PSCAD.steady_state === steady_state
end

empty_cache(cache) = all(f -> getfield(cache, f) === nothing, fieldnames(typeof(cache)))

@testset "Solved port powers and frozen Setpoint inputs" begin
    path = joinpath(@__DIR__, "reference/v2/numeric.csv")
    for (name, element) in ((:im, :im1), (:sm, :sg1), (:mmc_pq, :DUT), (:tlc_case1, :DUT))
        @testset "$name" begin
            fixture = only(filter(f -> f.name == name, ParityFixtures.FIXTURES))
            network = fixture.build()
            solved = compute(PowerFlowProblem(network), ACDCPowerFlow())
            @test solved.result["termination_status"] == PI.MOI.LOCALLY_SOLVED
            model = network.elements[element]
            values = solved.operating_point[element]
            prefix = "$name.op.$element."
            fields = Dict(Symbol(split(line, ',')[1][length(prefix) + 1:end]) =>
                parse(Float64, split(line, ',')[5]) for line in eachline(path)
                if startswith(line, prefix))
            frozen = Setpoint(; fields...)
            if model isa PI.InductionMachine
                @test values.ac.p === frozen.Pac
                @test values.ac.q === frozen.Qac
            else
                @test values.ac.p === -frozen.Pac
                @test values.ac.q === -frozen.Qac
                if model isa Union{MMC, TLC}
                    @test values.dc.p === frozen.Pdc
                end
            end
            inputs, pu = PI.pftoinputs(model, values)
            old_inputs, old_pu = PI.pftoinputs(model, frozen)
            @test inputs === old_inputs
            @test pu === old_pu
            @test pu.p_ac === frozen.Pac / bases(model).S
            @test pu.q_ac === frozen.Qac / bases(model).S
            if model isa Union{MMC, TLC}
                @test pu.p_dc === frozen.Pdc / bases(model).S
            end
        end
    end
end

@testset "State-space terminal values and retained state" begin
    for (factory, name) in ((PSCADFixtures.mmc_pq_network, :DUT),
            (PSCADFixtures.tlc_case1_network, :DUT),
            (PSCADFixtures.sm_network, :sg1), (PSCADFixtures.im_network, :im1))
        network = getfield(ClassicFixtures, nameof(factory))()
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
    model.cache.values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
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
    values = (ac = ACPortValues(point.Vac, point.θac, -point.Pac, NaN),)
    direct, direct_pu = PI.pftoinputs(model, values)
    @test input === direct
    @test pu === direct_pu === nothing
    @test direct.vref_SG === 1.07
    @test direct.Tm0 === point.Pac / model.elec.S_base
    @test direct.vd === point.Vac * cos(point.θac) / (model.elec.Vᵃᶜ_base * sqrt(2/3))
    @test direct.vq === -point.Vac * sin(point.θac) / (model.elec.Vᵃᶜ_base * sqrt(2/3))
end
end
