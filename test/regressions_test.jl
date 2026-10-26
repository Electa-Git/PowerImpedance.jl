using Test, PowerImpedance
if !isdefined(@__MODULE__, :PI)
    const PI = PowerImpedance
end
if !isdefined(@__MODULE__, :NB)
    const NB = PI.NetworkBuilder
end

@testset "Three-phase classification of untransformed six-pin elements" begin
    abc_branch = impedance(z = s -> 1.0 + 0.01s, conductors = 3)
    @test PI.is_three_phase(abc_branch)
    @test PI.pmtype(abc_branch, ((bus = 1,), (bus = 2,))) == "branch"
    @test all(port -> port.domain == ACABC, electricalconnections(abc_branch))

    abc_source = ac_source()
    @test PI.is_three_phase(abc_source)
    @test PI.pmtype(abc_source, ()) == "gen"

    dq_branch = impedance(z = s -> 1.0, conductors = 3)
    @test PI.is_three_phase(dq_branch)

    dc_branch = impedance(z = s -> 1.0, conductors = 1)
    @test !PI.is_three_phase(dc_branch)
    @test PI.pmtype(dc_branch, ((bus = 1,), (bus = 2,))) == "branchdc"
end

@testset "NetworkBuilder power flow uses the default voltage base" begin
    elements = (
        source = ac_source(v = 320 * sqrt(2)),
        load = impedance(z = s -> 100.0, conductors = 3),
    )
    connections = (
        NB.Bus(:b_; ports = ((:source, :ac), (:load, :side1)), domain = ACDQ),
        NB.Bus(:gnd_; ports = ((:load, :side2),), domain = ACDQ),
    )
    state = NB.define(elements, connections)
    @test !hasproperty(state.options, :voltageBase)
    data, global_dict, _ = convert(state, PI.PMACDC)
    @test global_dict["V"] / 1e3 == NB.DEFAULT_VOLTAGE_BASE
    @test all(bus -> bus["base_kv"] == NB.DEFAULT_VOLTAGE_BASE, values(data["bus"]))

    explicit = NB.define(elements, connections; options = (voltageBase = 220 / sqrt(3),))
    explicit_data, _, _ = convert(explicit, PI.PMACDC)
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
    elements = (
        ac = ac_source(v = 320sqrt(2), theta = 0.0),
        from = dc_source(v = 640.0),
        to = dc_source(v = 636.0),
        line = impedance(z = s -> 2.0 + s * 0.05, conductors = 1),
    )
    topology = (
        NB.Bus(:AC; ports = ((:ac, :ac),), domain = ACDQ),
        NB.Bus(:D1; ports = ((:from, :dc), (:line, :side1))),
        NB.Bus(:D2; ports = ((:to, :dc), (:line, :side2))),
    )
    net = NB.define(elements, topology; options = (; voltageBase = 320.0))
    solved = compute(PowerFlowProblem(net), ACDCPowerFlow())
    result, data = solved.result, solved.data
    index = solved.elem2comp[:line].compkey
    branch = data["branchdc"][string(index)]
    flow = result["solution"]["branchdc"][string(index)]
    v_from = result["solution"]["busdc"][string(branch["fbusdc"])]["vm"] * 320
    v_to = result["solution"]["busdc"][string(branch["tbusdc"])]["vm"] * 320
    # Differential loop resistance 2 ohm -> 1 ohm in each pole.
    pole_current = (v_from - v_to) / 1.0
    @test (flow["pf"] + flow["pt"]) * 1000 ≈ 2 * pole_current^2 * 1.0 rtol = 1e-6
    @test abs(flow["pf"]) * 1000 / (2 * v_from) ≈ pole_current rtol = 1e-6
end

