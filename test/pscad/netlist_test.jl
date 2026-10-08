using Test
using PowerImpedance
using LinearAlgebra

struct PSCADLegacyConverterFixture <: PowerImpedance.Converter end

function pscad_classic_from_rows(elements, rows, voltage = 220 / sqrt(3))
    classic = Network()
    classic.voltageBase[1] = voltage
    for (name, element) in pairs(deepcopy(elements))
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for (name, element) in pairs(classic.elements)
        PowerImpedance.issingleport(element) || continue
        for terminal in 1:PowerImpedance.nop(element)
            connect!(classic, (name, Symbol("2.$terminal")), :gnd)
        end
    end
    connect!(classic)
    return classic
end

function pscad_ac_fixture(; abc = false, machine_first = false)
    P = PowerImpedance
    NB = P.NetworkBuilder
    # Source/machine base and setpoint from test/adm_SM_test.jl; passive branch
    # parameters follow the maintained IEEE39 line fixture.
    voltage = 380 / sqrt(3)
    source = ac_source(; pins = 3, transformation = !abc,
        setpoint = Setpoint(Vac = voltage * sqrt(2), Pac = 0.0, Qac = 0.0))
    line = impedance(; z = s -> 0.19 + s * 0.0122, pins = 3, transformation = !abc)
    # IEEE39 bus-3 calc_RLC load from test/NetworkBuilder_test.jl.
    load_current = 3 * hypot(107.3333, 0.8) * 1e6 / (sqrt(3) * 345e3)
    load_R = 107.3333e6 / load_current^2
    load_L = 0.8e6 / (load_current^2 * 2π * 50)
    load = impedance(; z = s -> load_R + s * load_L, pins = 3, transformation = !abc)
    elements = if machine_first
        machine = synchronousmachine(;
            setpoint = Setpoint(Vac = voltage * sqrt(2), Pac = 900.0, Qac = 0.0),
            elec = ElectricalSM(Vᵃᶜ_base = 380.0))
        (; machine, source, line, load)
    else
        (; source, line, load)
    end
    rows = NamedTuple[]
    suffixes = abc ? ("a", "b", "c") : ("d", "q")
    for (name, _) in pairs(elements)
        for (terminal, suffix) in enumerate(suffixes)
            first_bus = name == :load ? "B2" : "B1"
            push!(rows, (node = Symbol(first_bus * suffix),
                element = name, side = 1, terminal = terminal))
        end
        if name in (:line, :load)
            for (terminal, suffix) in enumerate(suffixes)
                second_bus = name == :line ? Symbol("B2" * suffix) : :gnd
                push!(rows, (
                    node = second_bus, element = name, side = 2, terminal = terminal))
            end
        end
    end
    state = NB.define(deepcopy(elements), rows; options = (; voltageBase = voltage))
    classic = pscad_classic_from_rows(elements, rows, voltage)
    return classic, state
end

function pscad_netlist_shape(netlist)
    return (
        buses = [(bus.name, bus.kind, bus.nets) for bus in netlist.buses],
        elements = [(element.name, element.pscad, element.role,
                        [(terminal.side, terminal.terminals, terminal.nets,
                             terminal.bus, terminal.grounded)
                         for terminal in element.terminals])
                    for element in netlist.elements]
    )
end

@testset "PSCAD netlist" begin
    P = PowerImpedance
    NB = P.NetworkBuilder
    pscad = P.PSCAD
    classic, state = pscad_ac_fixture()
    plain_classic = pscad.netlist(classic, nothing)
    plain_builder = pscad.netlist(state, nothing)
    @test pscad_netlist_shape(plain_classic) == pscad_netlist_shape(plain_builder)
    @test [bus.name for bus in plain_classic.buses] == ["B1", "B2"]
    @test all(bus -> bus.kind == :ac3_dq, plain_classic.buses)
    @test all(bus -> bus.base_kV == 380 / sqrt(3), plain_classic.buses)
    @test all(
        bus -> bus.vm_pu === nothing && bus.va_rad === nothing && bus.pf_index === nothing,
        plain_classic.buses)
    @test isempty(plain_classic.operating_point.bus_states)
    @test isempty(plain_classic.operating_point.branch_flows)
    @test isempty(plain_classic.operating_point.setpoints)
    @test plain_classic.operating_point.slack_bus === nothing
    @test plain_classic.operating_point.bases === nothing
    @test plain_classic.frequency == 50.0
    @test plain_classic.voltageBase == 380 / sqrt(3)
    @test [element.name for element in plain_classic.elements] == [:source, :line, :load]
    @test [element.role for element in plain_classic.elements] ==
          [:source, :ac_branch, :shunt]
    for index in (1, 3)
        ground = plain_classic.elements[index].terminals[2]
        @test ground.grounded
        @test ground.bus === nothing
        @test ground.terminals == [1, 2]
        @test ground.nets == [:gnd, :gnd]
    end
    @test plain_classic.elements[2].terminals[1].bus == pscad.BusKey(1, 1)
    @test plain_classic.elements[2].terminals[2].bus == pscad.BusKey(1, 2)
    @test plain_classic.elements[2].element === classic.elements[:line]
    @test plain_classic.elements[2].model === classic.elements[:line].element_model

    @test NB.solve(state).powerflow === nothing
    empty_pf = compute(NB.PowerFlowProblem(state), NB.ACDCPowerFlow())
    @test pscad.netlist(state, empty_pf).operating_point.bases === nothing
    # NB.solve intentionally skips this linear network. Solve its actual
    # PowerModels conversion explicitly for the independent PF parity check.
    classic_pf = power_flow(classic)
    data, global_bases, mapping = convert(state, P.PMACDC)
    result = NB.solve_acdcpf(data, P._PM.ACPPowerModel,
        NB.powerflow_optimizer(state.options), NB.is_bounded_options(state.options);
        setting = NB.powerflow_setting(state.options))
    builder_pf = PowerFlowResult(NB.ACDCPowerFlow(), result, data,
        NB._node_bus_mapping(state.topology), mapping, OperatingPoint(), (;))
    classic_points = [element.setpoint for element in values(classic.elements)]
    builder_points = [element.setpoint for element in values(state.elements)]
    with_classic_pf = pscad.netlist(classic, classic_pf)
    with_builder_pf = pscad.netlist(state, builder_pf)
    @test pscad_netlist_shape(with_classic_pf) == pscad_netlist_shape(with_builder_pf)
    for (left, right) in zip(with_classic_pf.buses, with_builder_pf.buses)
        @test isapprox(left.vm_pu, right.vm_pu; atol = 1e-9, rtol = 0)
        @test isapprox(left.va_rad, right.va_rad; atol = 1e-9, rtol = 0)
    end
    @test all(left === right
    for (left, right) in zip(classic_points,
        (element.setpoint for element in values(classic.elements))))
    @test all(left === right
    for (left, right) in zip(builder_points,
        (element.setpoint for element in values(state.elements))))
    @test with_classic_pf.operating_point.slack_bus == with_classic_pf.buses[1].key
    @test with_classic_pf.operating_point.bases ==
          (S_MVA = 1000.0, V_kV = classic_pf[2]["bus"]["1"]["base_kv"], dcpol = 2)
    changed_declaration = deepcopy(classic)
    changed_declaration.voltageBase[1] = 999.0
    recorded_base = pscad.netlist(changed_declaration, classic_pf)
    @test recorded_base.voltageBase == classic_pf[2]["bus"]["1"]["base_kv"]
    @test all(bus -> bus.base_kV == recorded_base.voltageBase, recorded_base.buses)
    @test pscad.netlist(changed_declaration, nothing).voltageBase == 999.0
    for field in (:pf, :qf, :pt, :qt)
        comp_type, index = classic_pf[4][:line]
        @test with_classic_pf.operating_point.branch_flows[:line][field] ==
              classic_pf[1]["solution"][comp_type][string(index)][string(field)] * 1000
    end
    @test with_classic_pf.operating_point.setpoints[:source] ===
          classic.elements[:source].setpoint
    source_type, source_index = classic_pf[4][:source]
    source_solution = classic_pf[1]["solution"][source_type][string(source_index)]
    @test with_classic_pf.operating_point.branch_flows[:source] ==
          (pg = source_solution["pg"] * 1000, qg = source_solution["qg"] * 1000)

    # A machine inserts a node-less PF bus before the next external bus.
    # Check a real solve, with distinct receiving-bus voltage and angle.
    offset_classic, offset_state = pscad_ac_fixture(; machine_first = true)
    offset_pf = power_flow(offset_classic)
    offset_netlist = pscad.netlist(offset_classic, offset_pf)
    receiving = only(filter(bus -> bus.name == "B2", offset_netlist.buses))
    @test receiving.key.index == 2
    @test receiving.pf_index == 3
    expected = offset_pf[1]["solution"]["bus"]["3"]
    @test receiving.vm_pu == expected["vm"]
    @test receiving.va_rad == expected["va"]
    @test !isapprox(receiving.vm_pu, offset_pf[1]["solution"]["bus"]["2"]["vm"]; atol = 1e-9)
    @test offset_netlist.elements[1].role == :machine

    # NB.solve returns the operating point without modifying state.elements.
    old_setpoint = offset_state.elements.machine.setpoint
    solved = NB.solve(offset_state)
    @test solved.powerflow isa PowerFlowResult
    builder_netlist = pscad.netlist(offset_state, solved.powerflow)
    @test offset_state.elements.machine.setpoint === old_setpoint
    @test builder_netlist.elements[1].setpoint ===
          solved.powerflow.operating_point[:machine]
    @test builder_netlist.operating_point.setpoints[:machine] ===
          solved.powerflow.operating_point[:machine]
    @test builder_netlist.buses[2].pf_index == 2
    # Without options.voltageBase, NetworkBuilder's power flow and materialized
    # network share one default; the solved records own the bus bases.
    unspecified_base = NB.NetworkState(deepcopy(offset_state.elements), offset_state.topology, (;))
    @test !hasproperty(unspecified_base.options, :voltageBase)
    declared_default = pscad.netlist(unspecified_base, nothing)
    @test declared_default.voltageBase == NB.DEFAULT_VOLTAGE_BASE
    @test all(bus -> bus.base_kV == NB.DEFAULT_VOLTAGE_BASE, declared_default.buses)
    default_solved = NB.solve(unspecified_base)
    @test default_solved.powerflow isa PowerFlowResult
    @test default_solved.network.voltageBase[1] == NB.DEFAULT_VOLTAGE_BASE
    default_netlist = pscad.netlist(unspecified_base, default_solved.powerflow)
    @test default_netlist.voltageBase == 320.0
    @test default_netlist.operating_point.bases.V_kV == 320.0
    for bus in default_netlist.buses
        @test bus.base_kV == 320.0
        input = default_solved.powerflow.data["bus"][string(bus.pf_index)]
        solution = default_solved.powerflow.result["solution"]["bus"][string(bus.pf_index)]
        @test bus.base_kV == input["base_kv"]
        @test bus.vm_pu == solution["vm"]
        @test bus.va_rad == solution["va"]
    end
    for (left, right) in zip(offset_netlist.buses, builder_netlist.buses)
        @test isapprox(left.vm_pu, right.vm_pu; atol = 1e-9, rtol = 0)
        @test isapprox(left.va_rad, right.va_rad; atol = 1e-9, rtol = 0)
    end

    # An abc transformer has an explicit AC port domain.
    abc_elements = (; transformer = transformer(; pins = 3, n = 2.0))
    abc_rows = [(node = Symbol("B$side$suffix"), element = :transformer,
                    side = side, terminal = terminal)
                for side in 1:2 for (terminal, suffix) in enumerate(("a", "b", "c"))]
    abc_state = NB.define(abc_elements, abc_rows)
    abc_classic = pscad_classic_from_rows(abc_elements, abc_rows)
    abc = pscad.netlist(abc_classic, nothing)
    @test [bus.name for bus in abc.buses] == ["B1", "B2"]
    @test all(bus -> bus.kind == :ac3_abc, abc.buses)
    @test pscad_netlist_shape(abc) == pscad_netlist_shape(pscad.netlist(abc_state, nothing))
    # Untransformed six-pin sources and branches are three-phase AC elements.
    untransformed_classic, untransformed_state = pscad_ac_fixture(; abc = true)
    untransformed = pscad.netlist(untransformed_classic, nothing)
    @test all(bus -> bus.kind == :ac3_abc, untransformed.buses)
    @test pscad_netlist_shape(untransformed) ==
          pscad_netlist_shape(pscad.netlist(untransformed_state, nothing))

    dc_elements = (; source = dc_source(), branch = impedance(z = 3, pins = 1))
    dc_rows = (
        (node = :DC₁, element = :source, side = 1, terminal = 1),
        (node = :DC₁, element = :branch, side = 1, terminal = 1),
        (node = :DC₂, element = :branch, side = 2, terminal = 1)
    )
    dc_state = NB.define(dc_elements, dc_rows; options = (; voltageBase = 320.0))
    dc_classic = pscad_classic_from_rows(dc_elements, dc_rows, 320.0)
    dc = pscad.netlist(dc_state, nothing)
    @test pscad_netlist_shape(dc) == pscad_netlist_shape(pscad.netlist(dc_classic, nothing))
    @test [bus.name for bus in dc.buses] == ["DC1", "DC2"]
    @test all(bus -> bus.kind == :dc && bus.key.domain == 2 && bus.base_kV == 320.0, dc.buses)
    @test [element.role for element in dc.elements] == [:source, :dc_branch]
    # Independent supplied DC solution: exercise index mapping and MW flows.
    dc_result = Dict("solution" => Dict(
        "busdc" => Dict("7" => Dict("vm" => 1.03), "9" => Dict("vm" => 0.97)),
        "branchdc" => Dict("1" => Dict("pf" => 0.2, "pt" => -0.19))))
    dc_data = Dict("branchdc" => Dict("1" => Dict("transformer" => false)),
        "busdc" => Dict("7" => Dict("basekVdc" => 400.0), "9" => Dict("basekVdc" => 400.0)))
    dc_mapping = Dict(Set([:DC₁]) => ("busdc", 7), Set([:DC₂]) => ("busdc", 9))
    dc_pf = (dc_result, dc_data, dc_mapping, Dict(:branch => ("branchdc", 1)))
    dc_solved = pscad.netlist(dc_classic, dc_pf)
    @test [bus.pf_index for bus in dc_solved.buses] == [7, 9]
    @test [bus.vm_pu for bus in dc_solved.buses] == [1.03, 0.97]
    @test all(bus -> bus.va_rad === nothing, dc_solved.buses)
    @test dc_solved.operating_point.branch_flows[:branch] == (pf = 200.0, pt = -190.0)
    @test dc_solved.operating_point.slack_bus === nothing
    @test all(bus -> bus.base_kV == 400.0, dc_solved.buses)
    @test dc_solved.voltageBase == 400.0
    @test dc_solved.operating_point.bases.V_kV == 400.0
    inconsistent_dc_data = deepcopy(dc_data)
    inconsistent_dc_data["busdc"]["9"]["basekVdc"] = 401.0
    @test_throws ArgumentError pscad.netlist(dc_classic,
        (dc_result, inconsistent_dc_data, dc_mapping, dc_pf[4]))

    # Supplied converter evidence uses standard PowerModels power signs and
    # carries the solved setpoint independently of the builder's declarations.
    conv_elements = (; converter = tlc())
    conv_rows = (
        (node = :DC, element = :converter, side = 1, terminal = 1),
        (node = :ACd, element = :converter, side = 2, terminal = 1),
        (node = :ACq, element = :converter, side = 2, terminal = 2)
    )
    conv_state = NB.define(conv_elements, conv_rows; options = (; voltageBase = 320.0))
    solved_setpoint = Setpoint(Pac = 320.0, Qac = 80.0, Pdc = 300.0,
        Vac = 1.02 * 320 * sqrt(2), θac = 0.1, Vdc = 0.99 * 2 * 320)
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
        OperatingPoint(Dict(:converter => solved_setpoint)), (;))
    conv = pscad.netlist(conv_state, conv_pf)
    @test only(conv.elements).role == :converter
    @test only(conv.elements).setpoint === solved_setpoint
    @test conv.operating_point.branch_flows[:converter] ==
          (pgrid = -320.0, qgrid = 80.0, pdc = 300.0)
    @test only(conv.elements).terminals[1].bus == pscad.BusKey(2, 1)
    @test only(conv.elements).terminals[2].bus == pscad.BusKey(1, 1)
    @test conv.buses[1].vm_pu == 0.99
    @test conv.buses[2].va_rad == 0.1
    @test ismissing(conv_state.elements.converter.setpoint.Pac)
    inconsistent_conv_data = deepcopy(conv_data)
    inconsistent_conv_data["bus"]["1"]["base_kv"] = 400.0
    inconsistent_conv_pf = PowerFlowResult(conv_pf.formulation, conv_pf.result,
        inconsistent_conv_data, conv_pf.nodes2bus, conv_pf.elem2comp,
        conv_pf.operating_point, conv_pf.diagnostics)
    @test_throws ArgumentError pscad.netlist(conv_state, inconsistent_conv_pf)

    for model in (P.Blackbox_line(), P.Blackbox_MMC(), inductionmachine().element_model,
        PSCADLegacyConverterFixture())
        bad = Network()
        add!(bad, :unsupported_thing, P.Element(; element_model = model, input_pins = 1, output_pins = 1))
        err = try
            pscad.netlist(bad, nothing)
        catch exception
            exception
        end
        @test err isa ArgumentError
        @test occursin(":unsupported_thing", sprint(showerror, err))
        bad_state = NB.NetworkState(
            (; unsupported_thing = bad.elements[:unsupported_thing]),
            NB.NetworkTopology((;), NamedTuple[]), (;))
        @test_throws ArgumentError pscad.netlist(bad_state, nothing)
    end

    unsupported_bus = NB.define((; source = ac_source(pins = 3, transformation = true)),
        [(node = :only_phase, element = :source, side = 1, terminal = 1)])
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
        bad_node_map, builder_pf.elem2comp, builder_pf.operating_point, builder_pf.diagnostics)
    @test_throws ArgumentError pscad.netlist(state, bad_pf)
    @test_throws ArgumentError pscad.netlist(classic,
        (classic_pf[1], classic_pf[2], Dict(), classic_pf[4]))

    # Arbitrary names fall back deterministically; collisions remain bounded.
    renamed_rows = [merge(row,
                        (;
                            node = row.node == :B2d ? :B1_different :
                                   row.node == :B2q ? :unrelated : row.node))
                    for row in state.topology.connections]
    connections = [(; row.node, row.element, row.side, row.terminal)
                   for row in renamed_rows]
    fallback = pscad.netlist(NB.define(state.elements, connections), nothing)
    @test fallback.buses[2].name == "BUS2"
    collision_rows = [(; row.node, row.element, row.side, row.terminal)
                      for row in dc_state.topology.connections]
    collision_rows = [merge(row, (; node = row.node == :DC₂ ? :DC1 : row.node))
                      for row in collision_rows]
    collision = pscad.netlist(NB.define(dc_elements, collision_rows), nothing)
    @test [bus.name for bus in collision.buses] == ["DC1", "DC1_2"]

    empty = pscad.netlist(Network(), nothing)
    @test isempty(empty.buses) && isempty(empty.elements)
    unconnected = Network()
    add!(unconnected, :unconnected, impedance(z = 3, pins = 1))
    @test isempty(only(pscad.netlist(unconnected, nothing).elements).terminals)
end
