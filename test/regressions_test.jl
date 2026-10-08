@testset "Three-phase classification of untransformed six-pin elements" begin
    abc_branch = impedance(z = s -> 1.0 + 0.01s, pins = 3)
    @test PI.is_three_phase(abc_branch)
    @test PI.pmtype(abc_branch) == "branch"
    @test all(port -> port.domain == 1, NB._port_descriptions(abc_branch))

    abc_source = ac_source(pins = 3)
    @test PI.is_three_phase(abc_source)
    @test PI.pmtype(abc_source) == "gen"

    dq_branch = impedance(z = s -> 1.0, pins = 3, transformation = true)
    @test PI.is_three_phase(dq_branch)

    dc_branch = impedance(z = s -> 1.0, pins = 1)
    @test !PI.is_three_phase(dc_branch)
    @test PI.pmtype(dc_branch) == "branchdc"
end

@testset "NetworkBuilder power flow and network share the default voltage base" begin
    elements = (
        source = ac_source(pins = 3, transformation = true,
            setpoint = Setpoint(Vac = 320 * sqrt(2))),
        load = impedance(z = s -> 100.0, pins = 3, transformation = true),
    )
    connections = (
        (node = :b_d, element = :source, side = 1, terminal = 1),
        (node = :b_q, element = :source, side = 1, terminal = 2),
        (node = :b_d, element = :load, side = 1, terminal = 1),
        (node = :b_q, element = :load, side = 1, terminal = 2),
        (node = :gnd_d, element = :load, side = 2, terminal = 1),
        (node = :gnd_q, element = :load, side = 2, terminal = 2),
    )
    state = NB.define(elements, connections)
    @test !hasproperty(state.options, :voltageBase)
    data, global_dict, _ = convert(state, PI.PMACDC)
    network = NB.build_network(state.elements, state.topology, state.options)
    @test global_dict["V"] / 1e3 == NB.DEFAULT_VOLTAGE_BASE
    @test network.voltageBase[1] == NB.DEFAULT_VOLTAGE_BASE
    @test all(bus -> bus["base_kv"] == network.voltageBase[1], values(data["bus"]))

    explicit = NB.define(elements, connections; options = (voltageBase = 220 / sqrt(3),))
    explicit_data, _, _ = convert(explicit, PI.PMACDC)
    explicit_network = NB.build_network(explicit.elements, explicit.topology, explicit.options)
    @test explicit_network.voltageBase[1] == 220 / sqrt(3)
    @test all(bus -> bus["base_kv"] ≈ 220 / sqrt(3), values(explicit_data["bus"]))
end

@testset "Overhead lines accept explicit conductor positions" begin
    # Explicit coordinates reproduce the equivalent named organization exactly.
    flat = Conductors(organization = :flat, nᵇ = 3, yᵇᶜ = 30, Δxᵇᶜ = 10, dˢᵃᵍ = 10,
        rᶜ = 0.015, Rᵈᶜ = 0.063)
    # Ground-wire heights are measured from yᵇᶜ, so it is set with explicit positions too.
    placed = Conductors(nᵇ = 3, positions = ([-10, 0, 10], [30, 30, 30]), yᵇᶜ = 30,
        dˢᵃᵍ = 10, rᶜ = 0.015, Rᵈᶜ = 0.063)
    ground = Groundwires(nᵍ = 2, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10, rᵍ = 0.0062,
        Rᵍᵈᶜ = 0.92)
    for s in (2π * 50im, 2π * 1e3im)
        @test PI.eval_parameters(
            Overhead_line(conductors = placed, groundwires = ground,
                earth_parameters = (1, 1, 100)), s) ==
              PI.eval_parameters(
            Overhead_line(conductors = flat, groundwires = ground,
                earth_parameters = (1, 1, 100)), s)
    end
    @test_throws ArgumentError PI.eval_parameters(Overhead_line(conductors = Conductors(nᵇ = 3)),
        100π * im)
end

@testset "DC impedance power flow matches its per-pole circuit" begin
    net = Network()
    net.voltageBase[1] = 320.0
    for (name, element) in (
        :ac => ac_source(pins = 3, transformation = true,
            setpoint = Setpoint(Vac = 320sqrt(2), θac = 0.0)),
        :from => dc_source(setpoint = Setpoint(Vdc = 320.0)),
        :to => dc_source(setpoint = Setpoint(Vdc = 318.0)),
        :line => impedance(z = s -> 2.0 + s * 0.05, pins = 1))
        add!(net, name, element)
    end
    for k in 1:2
        connect!(net, (:ac, Symbol("1.$k")), Symbol("AC$k"))
        connect!(net, (:ac, Symbol("2.$k")), :gnd)
    end
    for (element, side, node) in ((:from, 1, :D1), (:from, 2, :gnd), (:to, 1, :D2),
        (:to, 2, :gnd), (:line, 1, :D1), (:line, 2, :D2))
        connect!(net, (element, Symbol("$side.1")), node)
    end
    connect!(net)
    result, data, _, elem2comp = power_flow(net)
    _, index = elem2comp[:line]
    branch = data["branchdc"][string(index)]
    flow = result["solution"]["branchdc"][string(index)]
    v_from = result["solution"]["busdc"][string(branch["fbusdc"])]["vm"] * 320
    v_to = result["solution"]["busdc"][string(branch["tbusdc"])]["vm"] * 320
    # Differential loop resistance 2 ohm -> 1 ohm in each pole.
    pole_current = (v_from - v_to) / 1.0
    @test (flow["pf"] + flow["pt"]) * 1000 ≈ 2 * pole_current^2 * 1.0 rtol = 1e-6
    @test abs(flow["pf"]) * 1000 / (2 * v_from) ≈ pole_current rtol = 1e-6
end

