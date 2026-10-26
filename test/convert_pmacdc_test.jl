using Test
using PowerImpedance
using PowerImpedance.NetworkBuilder: solve_acdcpf, define, powerflow_optimizer,
                                     is_bounded_options, powerflow_setting


Vac = 220 #LL-RMS
Z = 1
 elements = (; 
        sm1 = let machine = synchronousmachine(
            elec = ElectricalSM(rt = 1e-10, lt = 1e-10))
            b = bases(machine)
            component(machine; powerflow = (p = 50.0 / b.S, q = 10.0 / b.S,
                v = (1.0 * Vac * sqrt(2) / sqrt(3)) / b.v_ac))
        end,
        z1 = impedance(z = Z, conductors = 3),
    )
    connections = (
        PowerImpedance.NetworkBuilder.Bus(:machine_;
            ports = ((:z1, :side1), (:sm1, :ac)), domain = ACDQ),
        PowerImpedance.NetworkBuilder.Bus(:gnd_;
            ports = ((:z1, :side2),), domain = ACDQ),
    )

    builder = define(elements, connections)

    data, _, elempitopm = convert(builder, PowerImpedance.PMACDC)

    options = builder.options

    result = solve_acdcpf(
        data,
        PowerImpedance._PM.ACPPowerModel,
        powerflow_optimizer(options),
        is_bounded_options(options);
        setting = powerflow_setting(options),
    )


@testset "PMACDC conversion - dict initialization" begin
    # The synchronous machine is the first non-linear element we want to cover.
    # This network keeps the topology as small as possible while still forcing
    # the PMACDC conversion path to build buses, a generator entry, and branch
    # data instead of short-circuiting as it does for purely linear networks.
   
    

    @test haskey(data, "bus")
    @test haskey(data, "gen")
    @test haskey(data, "branch")
    @test !isempty(data["bus"])
    @test length(data["gen"]) == 1
    @test length(data["branch"]) == 1
    @test length(data["shunt"]) == 1 
end

@testset "PMACDC conversion - analytical result" begin
    
    shunt_P = result["solution"]["branch"]["1"]["pf"] *1000 # 1st bus will be actual bus (2nd bus is then interm bus for SM)
    @test shunt_P ≈ Vac^2/Z
end

@testset "PowerModels buses keyed by port name" begin
    nb = PowerImpedance.NetworkBuilder
    grid = component(ac_source(); v = 220sqrt(2/3))
    dc_grid = component(dc_source(); v = 640.0)
    line = impedance(z = 1.0, conductors = 3)
    converter = tlc(outerActive = OuterActivePowerControl(),
        outerReactive = OuterReactiveQControl())
    state = nb.define((; grid, dc_grid, line, converter), (
        nb.Bus(:DC; ports = ((:dc_grid, :dc), (:converter, :dc))),
        nb.Bus(:Grid; ports = ((:grid, :ac), (:line, :side1)), domain = ACDQ),
        nb.Bus(:Converter; ports = ((:line, :side2), (:converter, :ac))),
    ))
    converted, _, mapping = convert(state, PowerImpedance.PMACDC)
    entry = converted["convdc"][string(mapping[:converter].compkey)]
    @test entry["busac_i"] == 2
    @test entry["busdc_i"] == 1
    entry = converted["branch"][string(mapping[:line].compkey)]
    @test entry["f_bus"] == 1
    @test entry["t_bus"] == 2
end

@testset "Per-port operating point and repeated power flow" begin
    point = OperatingPoint(Dict{Symbol, NamedTuple}(
        :c1 => (ac = ACPortValues(220.0, 0.1, 100.0, 20.0),
            dc = DCPortValues(640.0, -101.0))))
    @test point[:c1].ac.p == 100.0
    @test point[:c1].dc.v == 640.0
    @test get(point, :missing, nothing) === nothing
    @test get(point, :c1, nothing) === point[:c1]
    @test Set(keys(point)) == Set((:c1,))
    @test !isempty(point)
    @test isempty(OperatingPoint())

    first = compute(PowerFlowProblem(builder), ACDCPowerFlow())
    @test !isempty(builder.powerflow_start.primal)
    topology = builder.powerflow_start.topology
    count = length(builder.powerflow_start.primal)
    second = compute(PowerFlowProblem(builder), ACDCPowerFlow())
    @test builder.powerflow_start.topology === topology
    @test length(builder.powerflow_start.primal) == count
    @test first.operating_point[:sm1].ac.v ≈ second.operating_point[:sm1].ac.v
    @test first.operating_point[:sm1].ac.p ≈ second.operating_point[:sm1].ac.p
end

module ConversionSourceFixtures
include("pscad/fixtures.jl")
end

@testset "Converter DC power seeds" begin
    PI = PowerImpedance
    NB = PI.NetworkBuilder
    for factory in (ConversionSourceFixtures.PSCADFixtures.mmc_pq_network,
            ConversionSourceFixtures.PSCADFixtures.tlc_case1_network)
        original = factory()
        for p_dc in (-0.25, 0.0, 0.25)
            model = withinputs(original.elements.DUT; powerflow = (; p_dc))
            elements = merge(original.elements, (; DUT = model))
            state = NB.NetworkState(elements, original.topology, original.options)
            data, _, mapping = convert(state, PI.PMACDC)
            entry = data["convdc"][string(mapping[:DUT].compkey)]
            b = bases(model)
            p_ac = PI.powerflow_targets(model).p_ac * b.S
            fallback = model isa MMC ? p_ac : -p_ac
            expected = (iszero(p_dc) ? fallback : p_dc * b.S) / data["baseMVA"]
            @test entry["Pdcset"] === expected

        end
    end
end

@testset "Solved source terminal values" begin
    state = ConversionSourceFixtures.PSCADFixtures.mmc_pq_network()
    powerflow = compute(PowerFlowProblem(state), ACDCPowerFlow())
    point = powerflow.operating_point
    @test point[:G_AC].ac.v == 380sqrt(2/3)
    @test point[:G_AC].ac.p == 600.0
    @test point[:G_AC].ac.q == 200.0
    @test point[:G_DC].dc.v == 800.0
    path = joinpath(@__DIR__, "reference/v2/numeric.csv")
    line = only(line for line in eachline(path)
        if startswith(line, "mmc_pq.pf.gendc.G_DC.pgdc,"))
    reference_pgdc = parse(Float64, split(line, ',')[5])
    @test point[:G_DC].dc.p == -reference_pgdc * 1000
end


@testset "Physical port-value statistics" begin
    ac = PowerImpedance._statistics_tree([
        ACPortValues(300.0, 0.0, 100.0, 20.0),
        ACPortValues(320.0, 0.2, 200.0, 40.0)])
    @test ac.v.mean == 310.0
    @test ac.p.mean == 150.0
    @test ac.q.std ≈ 10sqrt(2)
    dc = PowerImpedance._statistics_tree([DCPortValues(600.0, 80.0),
        DCPortValues(640.0, 120.0)])
    @test dc.v.mean == 620.0
    @test dc.p.std ≈ 20sqrt(2)
end
