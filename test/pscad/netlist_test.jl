using Test
using PowerImpedance
using LinearAlgebra
include("probe_names.jl")

function pscad_ac_fixture(; abc = false, machine_first = false)
    P = PowerImpedance
    NB = P.NetworkBuilder
    # Source/machine base and setpoint from test/adm_SM_test.jl; passive branch
    # parameters follow the maintained IEEE39 line fixture.
    voltage = 380 / sqrt(3)
    source = component(P.Source(; conductors = 3); v = voltage * sqrt(2))
    line = P.Impedance(; conductors = 3,
        value = s -> Matrix(Diagonal(fill(0.19 + s * 0.0122, 3))))
    # IEEE39 bus-3 calc_RLC load from test/fixtures/ieee39bus.jl.
    load_current = 3 * hypot(107.3333, 0.8) * 1e6 / (sqrt(3) * 345e3)
    load_R = 107.3333e6 / load_current^2
    load_L = 0.8e6 / (load_current^2 * 2π * 50)
    load = P.Impedance(; conductors = 3,
        value = s -> Matrix(Diagonal(fill(load_R + s * load_L, 3))))
    elements = if machine_first
        machine = P.synchronousmachine(; Vᵃᶜ_base = 380.0, elec = ElectricalSM(),
            mech = MechanicalSM(), avr = AVRSM(), gov = GovernorSM(),
            powerflow = (; p = 0.0, q = 0.0, v = 1.0))
        machine = component(machine; powerflow =
            (; p = 900.0 / machine.bases.S, q = 0.0, v = 1.0))
        (; machine, source, line, load)
    else
        (; source, line, load)
    end
    first_ports = machine_first ?
                  ((:machine, :ac), (:source, :ac), (:line, :side1)) :
                  ((:source, :ac), (:line, :side1))
    frame = abc ? ACABC : ACDQ
    topology = (
        NB.Bus(:B1; ports = first_ports, domain = frame),
        NB.Bus(:B2; ports = ((:line, :side2), (:load, :side1)), domain = frame),
        NB.Bus(:gnd; ports = ((:load, :side2),), domain = frame))
    return NB.define(elements, topology; options = (; voltageBase = voltage))
end

@testset "PSCAD frozen probe names" begin
    P = PowerImpedance.PSCAD
    NB = PowerImpedance.NetworkBuilder
    source = component(PowerImpedance.Source(; domain = DC_CM); v = 640.0)
    branch = PowerImpedance.Impedance(; value = ComplexF64[3;;])
    state = NB.define((; SEND_2 = source, dc_line_2 = branch), (
        NB.Bus(:DC1; ports = ((:SEND_2, :dc), (:dc_line_2, :side1))),
        NB.Bus(:DC2; ports = ((:dc_line_2, :side2),))))
    list = P.netlist(state, nothing)
    plan = P.build_plan(list)
    mapping = PSCADProbeNames.name_map(list, plan.probes)
    @test mapping.names == Dict("I_SEND_2_1" => "I_SEND_2_dc",
        "I_dc_line_2_1" => "I_dc_line_2_side1",
        "I_dc_line_2_2" => "I_dc_line_2_side2")
    @test isempty(mapping.truncated)
    graph = Dict("components" => [
        Dict("definition" => "master:ammeter",
            "parameters" => Dict("Name" => "I_dc_line_2_1")),
        Dict("definition" => "master:voltmetergnd",
            "parameters" => Dict("Name" => "V_Bus10_2")),
        Dict("definition" => "master:ammeter",
            "parameters" => Dict("Name" => "I_dc_line_1")),
        Dict("definition" => "master:resistor",
            "parameters" => Dict("Name" => "I_SEND_2_1"))])
    @test PSCADProbeNames.map_graph!(graph, mapping.names) == 1
    @test [c["parameters"]["Name"] for c in graph["components"]] ==
          ["I_dc_line_2_side1", "V_Bus10_2", "I_dc_line_1", "I_SEND_2_1"]
end

function pscad_solved_linear(state)
    P = PowerImpedance
    NB = P.NetworkBuilder
    data, bases, mapping = convert(state, P.PMACDC)
    result = NB.solve_acdcpf(data, P._PM.ACPPowerModel,
        NB.powerflow_optimizer(state.options), NB.is_bounded_options(state.options);
        setting = NB.powerflow_setting(state.options))
    point = NB._operating_point(result, bases, state, mapping)
    return PowerFlowResult(NB.ACDCPowerFlow(), result, data,
        NB._node_bus_mapping(state.topology), mapping, point, (;))
end

@testset "PSCAD netlist" begin
    P = PowerImpedance
    NB = P.NetworkBuilder
    pscad = P.PSCAD
    state = pscad_ac_fixture()
    plain = pscad.netlist(state, nothing)
    @test [bus.name for bus in plain.buses] == ["B1", "B2"]
    @test all(bus -> bus.kind == :ac3_dq, plain.buses)
    @test all(bus -> bus.base_kV == 380 / sqrt(3), plain.buses)
    @test all(bus -> bus.vm_pu === nothing && bus.va_rad === nothing &&
                    bus.pf_index === nothing, plain.buses)
    @test isempty(plain.operating_point.bus_states)
    @test isempty(plain.operating_point.branch_flows)
    @test isempty(plain.operating_point.values)
    @test plain.operating_point.slack_bus === nothing
    @test plain.operating_point.bases === nothing
    @test plain.frequency == 50.0
    @test plain.voltageBase == 380 / sqrt(3)
    @test [e.name for e in plain.elements] == [:source, :line, :load]
    @test [e.pscad for e in plain.elements] == ["source", "line", "load"]
    @test [e.role for e in plain.elements] == [:source, :ac_branch, :shunt]
    for index in (1, 3)
        ground = plain.elements[index].terminals[2]
        @test ground.grounded
        @test ground.bus === nothing
        @test ground.port == (index == 1 ? :ac : :side2)
        @test ground.terminals == [:d, :q]
        @test ground.nets == (index == 1 ? [:gnd, :gnd] : [:gndd, :gndq])
    end
    @test plain.elements[2].terminals[1].bus == pscad.BusKey(1, 1)
    @test plain.elements[2].terminals[2].bus == pscad.BusKey(1, 2)
    @test [t.port for t in plain.elements[2].terminals] == [:side1, :side2]
    @test plain.elements[2].model === state.elements.line
    @test plain.elements[2].ports == electricalconnections(state.elements.line)
    @test all(e -> e.values === nothing, plain.elements)
    @test NB.solve(state) isa PowerFlowResult
    powerflow = compute(NB.PowerFlowProblem(state), NB.ACDCPowerFlow())
    @test powerflow.result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
    @test pscad.netlist(state, powerflow).operating_point.bases ==
          (S_MVA = 1000.0, V_kV = powerflow.data["bus"]["1"]["base_kv"], dcpol = 2)
    # Solve its actual PowerModels conversion explicitly for the independent
    # PF parity check.
    source_inputs = inputvalues(state.elements.source)
    builder_pf = pscad_solved_linear(state)
    solved = pscad.netlist(state, builder_pf)
    @test inputvalues(state.elements.source) == source_inputs
    @test solved.operating_point.slack_bus == solved.buses[1].key
    @test solved.operating_point.bases ==
          (S_MVA = 1000.0, V_kV = builder_pf.data["bus"]["1"]["base_kv"], dcpol = 2)
    for bus in solved.buses
        @test bus.vm_pu == builder_pf.result["solution"]["bus"][string(bus.pf_index)]["vm"]
        @test bus.va_rad == builder_pf.result["solution"]["bus"][string(bus.pf_index)]["va"]
    end
    changed_declaration = NB.NetworkState(state.elements, state.topology,
        (; voltageBase = 999.0))
    recorded_base = pscad.netlist(changed_declaration, builder_pf)
    @test recorded_base.voltageBase == builder_pf.data["bus"]["1"]["base_kv"]
    @test all(bus -> bus.base_kV == recorded_base.voltageBase, recorded_base.buses)
    @test pscad.netlist(changed_declaration, nothing).voltageBase == 999.0
    for field in (:pf, :qf, :pt, :qt)
        comp_type, index = builder_pf.elem2comp[:line]
        @test solved.operating_point.branch_flows[:line][field] ==
              builder_pf.result["solution"][comp_type][string(index)][string(field)] * 1000
    end
    source_type, source_index = builder_pf.elem2comp[:source]
    source_solution = builder_pf.result["solution"][source_type][string(source_index)]
    @test solved.operating_point.branch_flows[:source] ==
          (pg = -source_solution["pg"] * 1000, qg = -source_solution["qg"] * 1000)
    @test solved.elements[1].values === builder_pf.operating_point[:source]
    @test solved.operating_point.values[:source] === builder_pf.operating_point[:source]
    @test solved.elements[2].values === nothing
    @test solved.elements[3].values === nothing
    shunt_type, shunt_index = builder_pf.elem2comp[:load]
    shunt = builder_pf.data[shunt_type][string(shunt_index)]
    voltage = builder_pf.result["solution"]["bus"][string(shunt["shunt_bus"])]["vm"]
    @test solved.operating_point.branch_flows[:load] ==
          (pf = shunt["gs"] * voltage^2 * 1000, qf = -shunt["bs"] * voltage^2 * 1000)

    # A machine inserts a node-less PF bus before the next external bus.
    # Check a real solve, with distinct receiving-bus voltage and angle.
    machine_state = pscad_ac_fixture(; machine_first = true)
    declared_inputs = inputvalues(machine_state.elements.machine)
    machine_pf = NB.solve(machine_state)
    machine_list = pscad.netlist(machine_state, machine_pf)
    receiving = only(filter(bus -> bus.name == "B2", machine_list.buses))
    @test receiving.key.index == 2
    @test receiving.pf_index == 2
    expected = machine_pf.result["solution"]["bus"]["2"]
    @test receiving.vm_pu == expected["vm"]
    @test receiving.va_rad == expected["va"]
    _, machine_index = machine_pf.elem2comp[:machine]
    terminal_index = machine_pf.data["gen"][string(machine_index)]["gen_bus"]
    @test terminal_index != receiving.pf_index
    terminal_bus = machine_pf.result["solution"]["bus"][string(terminal_index)]
    @test !isapprox(receiving.vm_pu, terminal_bus["vm"]; atol = 1e-9)
    @test machine_list.elements[1].role == :machine
    @test inputvalues(machine_state.elements.machine) == declared_inputs
    @test machine_list.elements[1].values === machine_pf.operating_point[:machine]
    @test machine_list.operating_point.values[:machine] ===
          machine_pf.operating_point[:machine]
    machine_flow = machine_list.operating_point.branch_flows[:machine]
    branch = machine_pf.result["solution"]["branch"][string(machine_index)]
    @test machine_flow.pf == branch["pt"] * 1000
    @test machine_flow.qf == branch["qt"] * 1000
    @test machine_flow.terminal_voltage_kV == terminal_bus["vm"] *
          machine_pf.data["bus"][string(terminal_index)]["base_kv"]
    @test machine_flow.terminal_angle_rad == terminal_bus["va"]
    # Without options.voltageBase, NetworkBuilder's power flow and materialized network
    # share one default; solved records specify the bus bases.
    unspecified_base = NB.NetworkState(deepcopy(machine_state.elements),
        machine_state.topology, (;))
    @test !hasproperty(unspecified_base.options, :voltageBase)
    declared_default = pscad.netlist(unspecified_base, nothing)
    @test declared_default.voltageBase == NB.DEFAULT_VOLTAGE_BASE
    @test all(bus -> bus.base_kV == NB.DEFAULT_VOLTAGE_BASE, declared_default.buses)
    default_pf = NB.solve(unspecified_base)
    @test default_pf isa PowerFlowResult
    default_list = pscad.netlist(unspecified_base, default_pf)
    @test default_list.voltageBase == 320.0
    @test default_list.operating_point.bases.V_kV == 320.0
    for bus in default_list.buses
        @test bus.base_kV == 320.0
        input = default_pf.data["bus"][string(bus.pf_index)]
        solution = default_pf.result["solution"]["bus"][string(bus.pf_index)]
        @test bus.base_kV == input["base_kv"]
        @test bus.vm_pu == solution["vm"]
        @test bus.va_rad == solution["va"]
    end

    # An abc transformer has an explicit AC port domain.
    abc_elements = (; transformer = P.Transformer(; conductors = 3, n = 2.0))
    abc_state = NB.define(abc_elements, (
        NB.Bus(:B1; ports = ((:transformer, :side1),)),
        NB.Bus(:B2; ports = ((:transformer, :side2),))))
    abc = pscad.netlist(abc_state, nothing)
    @test [bus.name for bus in abc.buses] == ["B1", "B2"]
    @test all(bus -> bus.kind == :ac3_abc, abc.buses)
    @test all(t -> t.terminals == [:a, :b, :c], only(abc.elements).terminals)
    # Untransformed six-pin sources and branches are three-phase AC elements.
    untransformed = pscad.netlist(pscad_ac_fixture(; abc = true), nothing)
    @test all(bus -> bus.kind == :ac3_abc, untransformed.buses)
    @test untransformed.elements[1].terminals[2].terminals == [:a, :b, :c]
    @test untransformed.elements[1].terminals[2].grounded

    dc_elements = (; source = component(P.Source(; domain = DC_CM); v = 640.0),
        branch = P.Impedance(; value = ComplexF64[3;;]))
    dc_state = NB.define(dc_elements, (
        NB.Bus(:DC₁; ports = ((:source, :dc), (:branch, :side1))),
        NB.Bus(:DC₂; ports = ((:branch, :side2),)));
        options = (; voltageBase = 320.0))
    dc = pscad.netlist(dc_state, nothing)
    @test [bus.name for bus in dc.buses] == ["DC1", "DC2"]
    @test all(bus -> bus.kind == :dc && bus.key.domain == 2 &&
                    bus.base_kV == 320.0, dc.buses)
    @test [e.role for e in dc.elements] == [:source, :dc_branch]
    @test dc.elements[1].terminals[2].terminals == [:dc]
    @test dc.elements[1].terminals[2].port == :dc
    @test dc.elements[1].terminals[2].grounded
    # Independent supplied DC solution: exercise index mapping and MW flows.
    dc_result = Dict("solution" => Dict(
        "busdc" => Dict("1" => Dict("vm" => 1.03), "2" => Dict("vm" => 0.97)),
        "branchdc" => Dict("1" => Dict("pf" => 0.2, "pt" => -0.19))))
    dc_data = Dict("branchdc" => Dict("1" => Dict("transformer" => false)),
        "gendc" => Dict("1" => Dict()),
        "busdc" => Dict("1" => Dict("basekVdc" => 400.0),
            "2" => Dict("basekVdc" => 400.0)))
    dc_values = (; dc = DCPortValues(824.0, -200.0))
    dc_pf = PowerFlowResult(NB.ACDCPowerFlow(), dc_result, dc_data,
        NB._node_bus_mapping(dc_state.topology),
        Dict(:branch => ("branchdc", 1), :source => ("gendc", 1)),
        OperatingPoint(Dict{Symbol, NamedTuple}(:source => dc_values)), (;))
    dc_solved = pscad.netlist(dc_state, dc_pf)
    @test [bus.pf_index for bus in dc_solved.buses] == [1, 2]
    @test [bus.vm_pu for bus in dc_solved.buses] == [1.03, 0.97]
    @test all(bus -> bus.va_rad === nothing, dc_solved.buses)
    @test dc_solved.operating_point.branch_flows[:branch] == (pf = 200.0, pt = -190.0)
    @test dc_solved.operating_point.slack_bus === nothing
    @test all(bus -> bus.base_kV == 400.0, dc_solved.buses)
    @test dc_solved.voltageBase == 400.0
    @test dc_solved.operating_point.bases.V_kV == 400.0
    @test dc_solved.elements[1].values === dc_values
    inconsistent_dc_data = deepcopy(dc_data)
    inconsistent_dc_data["busdc"]["2"]["basekVdc"] = 401.0
    inconsistent_dc_pf = PowerFlowResult(dc_pf.formulation, dc_pf.result,
        inconsistent_dc_data, dc_pf.nodes2bus, dc_pf.elem2comp,
        dc_pf.operating_point, dc_pf.diagnostics)
    @test_throws ArgumentError pscad.netlist(dc_state, inconsistent_dc_pf)

    # Supplied converter results use standard PowerModels power signs and provide the
    # solved terminal values independently of builder declarations.
    conv_state = NB.define((; converter = tlc()), (
        NB.Bus(:DC; ports = ((:converter, :dc),)),
        NB.Bus(:AC; ports = ((:converter, :ac),)));
        options = (; voltageBase = 320.0))
    conv_values = (ac = ACPortValues(1.02 * 320 * sqrt(2), 0.1, -320.0, 80.0),
        dc = DCPortValues(0.99 * 2 * 320, 300.0))
    conv_result = Dict("solution" => Dict(
        "bus" => Dict("1" => Dict("vm" => 1.02, "va" => 0.1)),
        "busdc" => Dict("1" => Dict("vm" => 0.99)),
        "convdc" => Dict("1" => Dict("pgrid" => -0.32, "qgrid" => 0.08, "pdc" => 0.30))))
    conv_data = Dict("convdc" => Dict("1" => Dict("busac_i" => 1, "busdc_i" => 1)),
        "bus" => Dict("1" => Dict("base_kv" => 320.0)),
        "busdc" => Dict("1" => Dict("basekVdc" => 320.0)))
    conv_pf = PowerFlowResult(NB.ACDCPowerFlow(), conv_result, conv_data,
        NB._node_bus_mapping(conv_state.topology),
        Dict(:converter => (pmtype = "convdc", compkey = 1)),
        OperatingPoint(Dict{Symbol, NamedTuple}(:converter => conv_values)), (;))
    conv = pscad.netlist(conv_state, conv_pf)
    @test only(conv.elements).role == :converter
    @test only(conv.elements).values === conv_values
    @test only(conv.elements).ports == electricalconnections(conv_state.elements.converter)
    @test conv.operating_point.branch_flows[:converter] ==
          (pgrid = -320.0, qgrid = 80.0, pdc = 300.0, pf = 300.0, pt = 320.0, qt = -80.0)
    @test only(conv.elements).terminals[1].port == :ac
    @test only(conv.elements).terminals[1].bus == pscad.BusKey(1, 1)
    @test only(conv.elements).terminals[2].port == :dc
    @test only(conv.elements).terminals[2].bus == pscad.BusKey(2, 1)
    @test conv.buses[1].vm_pu == 0.99
    @test conv.buses[2].va_rad == 0.1
    @test inputvalues(conv_state.elements.converter).powerflow.p_ac == 0.0
    inconsistent_conv_data = deepcopy(conv_data)
    inconsistent_conv_data["bus"]["1"]["base_kv"] = 400.0
    inconsistent_conv_pf = PowerFlowResult(conv_pf.formulation, conv_pf.result,
        inconsistent_conv_data, conv_pf.nodes2bus, conv_pf.elem2comp,
        conv_pf.operating_point, conv_pf.diagnostics)
    @test_throws ArgumentError pscad.netlist(conv_state, inconsistent_conv_pf)

    for model in (P.Blackbox_line(), P.Blackbox_MMC())
        bad_state = NB.NetworkState((; unsupported_thing = model),
            NB.NetworkTopology((;), ()), (;))
        err = try
            pscad.netlist(bad_state, nothing)
        catch exception
            exception
        end
        @test err isa ArgumentError
        @test occursin(":unsupported_thing", sprint(showerror, err))
        @test occursin(string(typeof(model)), sprint(showerror, err))
    end
    unsupported_bus = NB.define((; source = P.Source()),
        (NB.Net(:only_phase; terminals = ((:source, :ac, :a),)),))
    err = try
        pscad.netlist(unsupported_bus, nothing)
    catch exception
        exception
    end
    @test err isa ArgumentError
    @test occursin("only_phase", sprint(showerror, err))

    # Missing maps must fail instead of accidentally reading topology indices.
    bad_node_map = copy(builder_pf.nodes2bus)
    bad_node_map[:B2d] = (:ac, 77)
    bad_pf = PowerFlowResult(builder_pf.formulation, builder_pf.result, builder_pf.data,
        bad_node_map, builder_pf.elem2comp, builder_pf.operating_point,
        builder_pf.diagnostics)
    @test_throws ArgumentError pscad.netlist(state, bad_pf)
    missing_map = copy(builder_pf.nodes2bus)
    delete!(missing_map, :B2d)
    @test_throws ArgumentError pscad.netlist(state, PowerFlowResult(
        builder_pf.formulation, builder_pf.result, builder_pf.data, missing_map,
        builder_pf.elem2comp, builder_pf.operating_point, (;)))
    @test_throws ArgumentError pscad.netlist(state, PowerFlowResult(
        builder_pf.formulation, builder_pf.result, builder_pf.data, builder_pf.nodes2bus,
        Dict(), builder_pf.operating_point, (;)))
    @test_throws ArgumentError pscad.netlist(state, PowerFlowResult(
        builder_pf.formulation, nothing, nothing, builder_pf.nodes2bus,
        builder_pf.elem2comp, OperatingPoint(), (;)))

    # Arbitrary names fall back deterministically; collisions remain bounded.
    fallback = pscad.netlist(NB.define(abc_elements, (
        NB.Bus(:B1; ports = ((:transformer, :side1),)),
        NB.Net(:B1_different; terminals = ((:transformer, :side2, :a),)),
        NB.Net(:unrelated; terminals = ((:transformer, :side2, :b),)),
        NB.Net(:third; terminals = ((:transformer, :side2, :c),)))), nothing)
    @test fallback.buses[2].name == "BUS2"
    collision = pscad.netlist(NB.define(dc_elements, (
        NB.Bus(:DC₁; ports = ((:source, :dc), (:branch, :side1))),
        NB.Bus(:DC1; ports = ((:branch, :side2),)))), nothing)
    @test [bus.name for bus in collision.buses] == ["DC1", "DC1_2"]
    empty = pscad.netlist(NB.define((;), ()), nothing)
    @test isempty(empty.buses) && isempty(empty.elements)
    @test_throws ArgumentError NB.define((; unconnected = dc_elements.branch), ())
    @test !isdefined(PowerImpedance, :Network)
    @test pscad.current_probe_name(:c1, :ac) == "I_c1_ac"
    @test pscad.current_probe_name(:c1, :dc) == "I_c1_dc"
    @test pscad.current_probe_name(:tl1, :side1) == "I_tl1_side1"
    scan = ZToolProbe(:ac, "scan"; element = :line, port = :side1, voltage = 380.0)
    @test scan.port == :side1
    @test only(pscad._resolve_ztool_probes(plain, [scan])).terminal.port == :side1
    @test_throws r"port as a Symbol" ZToolProbe(:ac, "scan"; element = :line, port = 1)
    @test_throws r"unknown port" pscad._resolve_ztool_probes(plain,
        [ZToolProbe(:ac, "scan"; element = :line, port = :missing, voltage = 380.0)])
    @test_throws r"grounded" pscad._resolve_ztool_probes(plain,
        [ZToolProbe(:ac, "scan"; element = :load, port = :side2, voltage = 380.0)])
end
