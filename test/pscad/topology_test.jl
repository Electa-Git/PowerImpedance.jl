include("topology.jl")
using .PSCADTopology, TOML

@testset "PSCAD electrical topology reference fixtures" begin
    directory = joinpath(@__DIR__, "fixtures/topology_8be21ee")
    files = sort(filter(file -> endswith(file, ".toml"), readdir(directory; join = true)))
    @test length(files) == 14
    for file in files
        reference = TOML.parsefile(file)
        @test reference["commit"] == "8be21eecabb85d29d2896bc51562f61344338604"
        @test occursin(r"^[0-9a-f]{64}$", reference["source_sha256"])
        for (name, graph) in reference["canvases"]
            @test PSCADTopology.check_degrees(graph, name) === nothing
            @test PSCADTopology.equivalent(graph, graph)
            # Component order and net order carry no electrical meaning. Cable
            # interfaces also exercise bijections of equal parameter records.
            reordered = deepcopy(graph)
            reverse!(reordered["components"])
            reverse!(reordered["nets"])
            for net in reordered["nets"], pin in net["ports"]

                pin[1] = length(reordered["components"]) + 1 - pin[1]
            end
            @test PSCADTopology.equivalent(graph, reordered)
        end
    end
end

@testset "PSCAD electrical topology detects changed branches" begin
    graph = TOML.parsefile(joinpath(@__DIR__,
        "fixtures/topology_8be21ee/transformer_yy_classic.toml"))["canvases"]["Main"]
    components = graph["components"]
    index(name) = only(findall(c -> get(c["parameters"], "Name", "") == name, components))
    for name in ("line_primary_R", "line_primary_L", "line_secondary_R", "line_secondary_L",
        "line_magnetizing_R", "line_magnetizing_L", "load_R")
        changed = deepcopy(graph)
        changed["components"][index(name)]["parameters"]["Name"] = name * "_changed"
        @test !PSCADTopology.equivalent(graph, changed)
    end
    changed = deepcopy(graph)
    changed["components"][index("line_primary_R")]["parameters"]["R"] = "11.0 [ohm]"
    @test !PSCADTopology.equivalent(graph, changed)
    # Lost ground, a disconnected R/L junction, and an ammeter polarity reversal
    # are different failures; all must be visible in the graph comparison.
    changed = deepcopy(graph)
    only(filter(n -> n["ground"], changed["nets"]))["ground"] = false
    @test !PSCADTopology.equivalent(graph, changed)
    for name in ("line_primary_L", "line_secondary_L", "line_magnetizing_L",
        "line_magnetizing_R", "load_R")
        changed = deepcopy(graph)
        i = index(name)
        net = only(filter(n -> [i, 2] in n["ports"], changed["nets"]))
        deleteat!(net["ports"], only(findall(==([i, 2]), net["ports"])))
        push!(changed["nets"], Dict("ports" => [[i, 2]], "ground" => false, "probe" =>
            false))
        @test !PSCADTopology.equivalent(graph, changed)
        @test_throws ArgumentError PSCADTopology.check_degrees(changed, "Main")
    end
    changed = deepcopy(graph)
    i = index("I_line_1")
    for net in changed["nets"], pin in net["ports"]

        pin[1] == i && (pin[2] = 3 - pin[2])
    end
    @test !PSCADTopology.equivalent(graph, changed)
    # The degree check also retains labels with no attached component port.
    push!(changed["nets"], Dict("ports" => [], "ground" => false, "probe" => false))
    @test_throws ArgumentError PSCADTopology.check_degrees(changed, "Main")
end

@testset "PSCAD series construction retains electrical nets" begin
    P = PowerImpedance.PSCAD
    old = P.CanvasPlan()
    for (defn, parameter, value, x) in (("resistor", "R", "10.0 [ohm]", 72),
        ("inductor", "L", "0.1 [H]", 108))
        P.component!(old, defn, (x, 72), [
            "Name" => "winding_" * parameter, parameter => value])
    end
    P.stub!(old, (72, 72), "terminal"; direction = -1)
    P.stub!(old, (144, 72), nothing)
    P.component!(old, "voltmetergnd", (72, 216), ["Name" => "V_terminal"])
    P.stub!(old, (72, 216), "terminal"; direction = -1)
    current = P.CanvasPlan()
    parts = [("resistor", "R", 10.0, "ohm"), ("inductor", "L", 0.1, "H")]
    finish = P.component_chain!(current, parts, (72, 72), "winding", P._NameReservations())
    P.stub!(current, (72, 72), "terminal"; direction = -1)
    P.stub!(current, finish, nothing)
    P.component!(current, "voltmetergnd", (72, 216), ["Name" => "V_terminal"])
    P.stub!(current, (72, 216), "terminal"; direction = -1)
    before = PSCADTopology.electrical_graph(old, Dict())
    after = PSCADTopology.electrical_graph(current, Dict())
    @test PSCADTopology.equivalent(before, after)
    @test PSCADTopology.check_degrees(after, "series") === nothing
    for (i, c) in enumerate(current.components)
        c.defn == "master:nodelabel" || continue
        # Renaming all copies of a junction preserves topology, including
        # case-insensitive connections; renaming just one copy disconnects it.
        name = Dict(c.params)["Name"]
        name == "winding_junction_1" || continue
        current.components[i] = P.ComponentPlan(
            c.defn, ["Name" => "LOST_junction"], c.x, c.y, c.orient)
        break
    end
    disconnected = PSCADTopology.electrical_graph(current, Dict())
    @test !PSCADTopology.equivalent(before, disconnected)
    @test_throws ArgumentError PSCADTopology.check_degrees(disconnected, "series")
end

@testset "PSCAD approved shunt meter returns" begin
    policy = TOML.parsefile(joinpath(@__DIR__, "fixtures/shunt_meter_moves.toml"))
    @test length(policy) == 14
    for (fixture, moves) in policy
        reference = TOML.parsefile(joinpath(@__DIR__, "fixtures/topology_8be21ee",
            fixture * ".toml"))["canvases"]["Main"]
        expected = PSCADTopology.shunt_meter_returns(reference, moves)
        @test expected["components"] == reference["components"]
        @test PSCADTopology.check_degrees(expected, fixture) === nothing
        @test PSCADTopology.equivalent(reference, expected) == isempty(moves)
        for (meter, part) in moves
            @test PSCADTopology.shunt_meter_direction(expected, meter, part) == 1
            reversed = deepcopy(expected)
            i = only(findall(c -> get(c["parameters"], "Name", "") == meter,
                reversed["components"]))
            for n in reversed["nets"], pin in n["ports"]

                pin[1] == i && (pin[2] = 3 - pin[2])
            end
            @test PSCADTopology.shunt_meter_direction(reversed, meter, part) == -1
            @test !PSCADTopology.equivalent(expected, reversed)
        end
    end
    graph = TOML.parsefile(joinpath(@__DIR__,
        "fixtures/topology_8be21ee/transformer_yy_classic.toml"))["canvases"]["Main"]
    @test_throws ErrorException PSCADTopology.shunt_meter_returns(graph, [[
        "I_line_1", "load_R"]])
    @test_throws ErrorException PSCADTopology.shunt_meter_returns(graph, [[
        "I_load_1", "line_secondary_R"]])
end

@testset "PSCAD shunt return construction and native phase" begin
    P = PowerImpedance.PSCAD
    native = TOML.parsefile(joinpath(@__DIR__, "fixtures/yy_load_return_phasors.toml"))
    reference = complex.(native["yy_ref"]["peak_real_kA"], native["yy_ref"]["peak_imag_kA"])
    measured = complex.(native["yy_named_load_return"]["peak_real_kA"],
        native["yy_named_load_return"]["peak_imag_kA"])
    classic, _ = PSCADFixtures.transformer_network()
    plan = P.build_plan(P.netlist(classic, nothing))
    graph = PSCADTopology.electrical_graph(plan.main, Dict())
    direction = PSCADTopology.shunt_meter_direction(graph, "I_load_1", "load_R")
    @test direction == 1
    for (i, (value, expected)) in enumerate(zip(direction .* measured, reference))
        # Existing comparison defaults: 2% RMS current and 1 degree angle.
        @test isapprox(abs(value) / sqrt(2), abs(expected) / sqrt(2); rtol = 0.02)
        @test abs(rad2deg(angle(value / expected))) <= 1.0
        @test isapprox(value, expected; rtol = 0.02)
        line = complex(native["yy_named_load_return"]["line_peak_real_kA"][i],
            native["yy_named_load_return"]["line_peak_imag_kA"][i])
        @test isapprox(value, line; rtol = 0.02)
    end
    @test !isapprox(-first(measured), first(reference); rtol = 0.02)
    @test abs(rad2deg(angle(-first(measured) / first(reference)))) > 1.0

    for (topology, parameters) in ((:series, [("resistor", "R", 400.0, "ohm")]),
        (:series, [("resistor", "R", 400.0, "ohm"), ("inductor", "L", 0.05, "H")]),
        (:series, [("resistor", "R", 400.0, "ohm"), ("capacitor", "C", 2.0, "uF")]),
        (:parallel, [("resistor", "R", 400.0, "ohm"), ("capacitor", "C", 2.0, "uF")]),
        (:parallel, [("resistor", "R", 400.0, "ohm"), ("inductor", "L", 0.05, "H")]))
        state = P.PlanState(P.CanvasPlan(), P.AbstractLineDefinitionPlan[],
            P.AbstractLineWrapperPlan[], P.ModuleDefinitionPlan[], P.GridLayout(),
            P.ProbeChannel[], P._NameReservations())
        P.impedance_path!(state, parameters, topology, "bus", nothing, "shunt";
            first_probe = "I_shunt_1")
        @test P.check_connectivity(state.main, "shunt") === nothing
        g = PSCADTopology.electrical_graph(state.main, Dict())
        components, nets = g["components"], g["nets"]
        meter = only(findall(c -> c["definition"] == "master:ammeter", components))
        @test only(filter(n -> [meter, 2] in n["ports"], nets))["ground"]
        @test !only(filter(n -> [meter, 1] in n["ports"], nets))["ground"]
        @test Dict(only(filter(c -> c.defn == "master:ammeter", state.main.components)).params)["Name"] ==
              "I_shunt_1"
        for c in filter(
            c -> c.defn in ("master:resistor", "master:inductor", "master:capacitor"),
            state.main.components)
            port = (c.x, c.y)
            wire = only(filter(w -> port in w.vertices, state.main.wires))
            label = only(filter(!=(port), wire.vertices))
            @test only(filter(n -> (n.x, n.y) == label, state.main.components)).defn ==
                  "master:nodelabel"
        end
    end
end
