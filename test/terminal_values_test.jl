module TerminalValuesTests
using Test, PowerImpedance
const PI = PowerImpedance
include("parity/structure.jl")
using .ParityData: ParityFixtures
using .ParityFixtures: PSCADFixtures

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
    @test PI.TerminalValuesPU() === PI.TerminalValuesPU(0.0, 0.0, 0.0, 1.0, 0.0, 1.0)
    @test fieldtypes(PI.TerminalValuesPU) == ntuple(_ -> Float64, 6)
    @test all(name -> name ∉ names(PI),
        (:current, :TerminalValuesPU))
    @test PI.PSCAD.steady_state === steady_state
end

model_fields(value::Union{Number, Symbol, AbstractString}) = value
model_fields(value::AbstractArray) = deepcopy(value)
model_fields(model) = (typeof(model), map(model_fields,
    ntuple(i -> getfield(model, i), fieldcount(typeof(model)))))

@testset "Solved port powers and frozen physical inputs" begin
    path = joinpath(@__DIR__, "reference/v2/numeric.csv")
    metadata = ParityData.load_metadata(joinpath(@__DIR__, "reference/v2/metadata.txt"))
    matched, message = ParityData.frozen_environment(metadata)
    if !matched
        println(message)
        @test_skip matched
    end
    for (name, element) in ((:im, :im1), (:sm, :sg1), (:mmc_pq, :DUT), (:tlc_case1, :DUT))
        @testset "$name" begin
            fixture = only(filter(f -> f.name == name, ParityFixtures.FIXTURES))
            network = fixture.build()
            solved = compute(PowerFlowProblem(network), ACDCPowerFlow())
            @test solved.result["termination_status"] == PI.MOI.LOCALLY_SOLVED
            model = network.elements[element]
            values = solved.operating_point[element]
            if matched
                prefix = "$name.op.$element."
                fields = Dict(Symbol(split(line, ',')[1][length(prefix) + 1:end]) =>
                    parse(Float64, split(line, ',')[5]) for line in eachline(path)
                    if startswith(line, prefix))
                frozen = (; fields...)
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
            end
            inputs, pu = PI.pftoinputs(model, values)
            if matched
                @test pu.p_ac === frozen.Pac / bases(model).S
                @test pu.q_ac === frozen.Qac / bases(model).S
                if model isa Union{MMC, TLC}
                    @test pu.p_dc === frozen.Pdc / bases(model).S
                end
            end
        end
    end
end

@testset "State-space linearization purity and isolation" begin
    for (factory, name) in ((PSCADFixtures.mmc_pq_network, :DUT),
            (PSCADFixtures.tlc_case1_network, :DUT),
            (PSCADFixtures.sm_network, :sg1), (PSCADFixtures.im_network, :im1))
        network = factory()
        solved = compute(PowerFlowProblem(network), ACDCPowerFlow())
        model = network.elements[name]
        values = solved.operating_point[name]
        @testset "$(nameof(typeof(model)))" begin
            before = model_fields(model)
            @test !ismutabletype(typeof(model))
            direct = linearize(model, values)
            @test isequal(model_fields(model), before)
            @test !ismutabletype(StateSpaceLinearization)
            @test fieldnames(StateSpaceLinearization) == (:state, :system)
            @test fieldtypes(StateSpaceLinearization) == (Vector{Float64},
                PI.ControlSystemsBase.StateSpace{PI.ControlSystemsBase.Continuous, Float64})
            @test direct isa StateSpaceLinearization
            @test length(direct.state) == length(PI.statenames(model))
            @test size(direct.system.A) == (length(direct.state), length(direct.state))
            state = steady_state(model, values)
            @test reinterpret(UInt64, state) == reinterpret(UInt64, direct.state)
            @test state !== direct.state
            ac = values.ac
            equal_values = merge(values, (; ac = ACPortValues(ac.v, ac.theta, ac.p, ac.q)))
            @test isequal(equal_values, values)
            @test isequal(steady_state(model, equal_values), state)
            @test isequal(model_fields(model), before)

            for configured in (withinputs(model), component(model))
                @test isequal(model_fields(configured), before)
                @test configured.elec === model.elec
            end
            changed = merge(values, (; ac = ACPortValues(ac.v, ac.theta + 0.001,
                ac.p, ac.q)))
            changed_lin = linearize(model, changed)
            @test isequal(steady_state(model, changed), changed_lin.state)
            @test isequal(steady_state(model, values), state)
            @test isequal(model_fields(model), before)
            repeated = linearize(model, values)
            @test isequal(repeated.state, direct.state)
            @test repeated.state !== direct.state
            for field in (:A, :B, :C, :D)
                @test getfield(repeated.system, field) == getfield(direct.system, field)
                @test getfield(repeated.system, field) !== getfield(direct.system, field)
            end
            direct.state[1] = -123.0
            direct.system.A[1, 1] = -456.0
            @test isequal(steady_state(model, values), state)
            @test linearize(model, values).system.A == repeated.system.A
            @test isequal(model_fields(model), before)
        end
    end
end

@testset "Configured model isolation" begin
    model = synchronousmachine()
    before = model_fields(model)
    configured = withinputs(model; avr = (v_ref = 1.02,))
    @test configured.avr.v_ref === 1.02
    @test model.avr.v_ref === 1.01
    @test isequal(model_fields(model), before)
    @test configured.elec === model.elec

    configuration = first(configurations(tlc(Grid)))
    first_model = materialize(configuration)
    second_model = materialize(configuration)
    @test isequal(model_fields(first_model), model_fields(second_model))
end

@testset "Shared state-space models use each component's operating point" begin
    for factory in (PSCADFixtures.mmc_pq_network, PSCADFixtures.tlc_case1_network,
            PSCADFixtures.sm_network, PSCADFixtures.im_network)
        original = factory()
        name = first(n for (n, m) in pairs(original.elements) if m isa PI.AbstractStateSpace)
        model = original.elements[name]
        before = model_fields(model)
        solved = compute(PowerFlowProblem(original), ACDCPowerFlow())
        first_point = solved.operating_point[name]
        ac = first_point.ac
        second_point = merge(first_point, (; ac = ACPortValues(ac.v, ac.theta + 0.17,
            ac.p, ac.q)))
        points = OperatingPoint(Dict(:first => first_point, :second => second_point))
        ports = keys(electricalconnections(model))
        topology = Tuple(PI.NetworkBuilder.Bus(Symbol(name, "_", port);
            ports = ((name, port),), domain = port == :ac ? ACDQ : DC_CM)
            for name in (:first, :second) for port in ports)
        network = PI.NetworkBuilder.define((; first = model, second = model), topology)
        @test network.elements.first === network.elements.second === model
        frequencies = ComplexF64.(2π * im .* [13.0, 155.0])
        expected = Dict{Symbol, Array{ComplexF64, 3}}()
        for n in (:first, :second)
            sys = linearize(model, points[n]).system
            expected[n] = cat(((sys.C * ((s * PI.I - sys.A) \ sys.B) + sys.D) .*
                PI.SI_scale(model) for s in frequencies)...; dims = 3)
        end
        @test !isapprox(expected[:first], expected[:second]; rtol = 1e-6)
        built = PI.NetworkBuilder.NetworkModel(network, points)
        for n in (:first, :second, :first)
            @test PI.NetworkBuilder.get_y(built, n, frequencies) ≈ expected[n] rtol = 1e-10
        end
        @test isequal(model_fields(model), before)
    end
end

@testset "Unknown synchronous-machine reactive power" begin
    model = synchronousmachine(avr = AVRSM(v_ref = 1.07))
    values = (ac = ACPortValues(220sqrt(2/3), 0.17, -100.0, NaN),)
    direct, direct_pu = PI.pftoinputs(model, values)
    @test direct_pu === nothing
    @test direct.vref_SG === 1.07
    @test direct.Tm0 === -values.ac.p / model.bases.S
    @test direct.vd === values.ac.v * cos(values.ac.theta) /
        model.bases.v_ac
    @test direct.vq === -values.ac.v * sin(values.ac.theta) /
        model.bases.v_ac
end
end
