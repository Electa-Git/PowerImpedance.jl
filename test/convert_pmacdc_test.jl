using Test
using PowerImpedance
using PowerImpedance.NetworkBuilder: solve_acdcpf, define, powerflow_optimizer,
                                     is_bounded_options, powerflow_setting


Vac = 220 #LL-RMS
Z = 1
 elements = (; 
        sm1 = synchronousmachine(;elec=ElectricalSM(rt=1e-10,lt=1e-10), setpoint=Setpoint(;Pac = 50, Qac = 10, Vac = 1.0 * Vac / sqrt(3))),
        z1 = impedance(z = Z, pins = 3, transformation = true),
    )
    connections = (
        (node = :machine_d, element = :z1, side = 1, terminal = 1),
        (node = :machine_d, element = :sm1, side = 1, terminal = 1),
        (node = :machine_q, element = :z1, side = 1, terminal = 2),
        (node = :machine_q, element = :sm1, side = 1, terminal = 2),
        (node = :gndD, element = :z1, side = 2, terminal = 1),
        (node = :gndQ, element = :z1, side = 2, terminal = 2),
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
