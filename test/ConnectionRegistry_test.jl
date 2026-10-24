using PowerImpedance
using Test

const NB = PowerImpedance.NetworkBuilder

function topology_error(f)
    caught = try
        f()
        nothing
    catch error
        error
    end
    @test caught isa ArgumentError
    return sprint(showerror, caught)
end

@testset "Bus expansion and inferred domains" begin
    elements = (grid = ac_source().element_model,
        line = impedance(z = 1.0, pins = 3).element_model,
        dc = dc_source().element_model)
    topology = NB.NetworkTopology(elements, (
        NB.Bus(:Bus7; ports = ((:grid, :ac), (:line, :side1))),
        NB.Bus(:DC1; ports = ((:dc, :dc),)),
    ))
    rows = topology.connections
    @test unique(rows.net) == [:Bus7a, :Bus7b, :Bus7c, :DC1]
    @test rows.component == [:grid, :line, :grid, :line, :grid, :line, :dc]
    @test rows.port == [:ac, :side1, :ac, :side1, :ac, :side1, :dc]
    @test rows.terminal == [:a, :a, :b, :b, :c, :c, :dc]
    @test rows.domain == [1, 1, 1, 1, 1, 1, 2]
    @test rows.frame == [:abc, :abc, :abc, :abc, :abc, :abc, :dc]
    @test all(==(1), rows.bus)
    @test all(net -> !PowerImpedance.isgroundnet(net), rows.net)
    @test length(NB.acconnections(topology)) == 6
    @test length(NB.dcconnections(topology)) == 1
    @test fieldnames(NB.TopologyConnection) ==
        (:net, :bus, :component, :port, :terminal, :domain, :frame)
    @test :Bus in names(NB) && :Net in names(NB)

    state = NB.define(elements, (
        NB.Bus(:Bus7; ports = ((:grid, :ac), (:line, :side1))),
        NB.Bus(:DC1; ports = ((:dc, :dc),)),
    ))
    @test state.elements === elements
    @test NB._node_bus_mapping(state.topology) == Dict(
        :Bus7a => (:ac, 1), :Bus7b => (:ac, 1), :Bus7c => (:ac, 1),
        :DC1 => (:dc, 1))
end

@testset "Bus frames" begin
    line = impedance(z = 1.0, pins = 3).element_model
    machine = synchronousmachine().element_model
    topology = NB.NetworkTopology((; line, machine), (
        NB.Bus(:Bus7; ports = ((:line, :side1), (:machine, :ac))),
        NB.Bus(:Bus8; ports = ((:line, :side2),), domain = ACDQ),
    ))
    @test unique(topology.connections.net) == [:Bus7d, :Bus7q, :Bus8d, :Bus8q]
    @test all(==(:dq), topology.connections.frame)
    @test topology.connections.terminal == [:d, :d, :q, :q, :d, :q]
    @test NB.sortedcomponentconnections(topology, :line).terminal == [:d, :q, :d, :q]
    @test NB.sortedcomponentconnections(topology, :line).port ==
        [:side1, :side1, :side2, :side2]

    message = topology_error() do
        NB.NetworkTopology((; machine), (
            NB.Bus(:ExplicitABC; ports = ((:machine, :ac),), domain = ACABC),))
    end
    @test occursin("ExplicitABC", message)
    message = topology_error() do
        NB.NetworkTopology((; line), (
            NB.Bus(:DQ; ports = ((:line, :side1),), domain = ACDQ),
            NB.Bus(:ABC; ports = ((:line, :side2),), domain = ACABC),))
    end
    @test occursin("line", message)

    dc = dc_source().element_model
    for declaration in (
            NB.Bus(:MixedBus; ports = ((:machine, :ac), (:dc, :dc))),
            NB.Net(:MixedNet; terminals = ((:machine, :ac, :d), (:dc, :dc, :dc))))
        message = topology_error() do
            NB.NetworkTopology((; machine, dc), (declaration,))
        end
        @test occursin(string(declaration.name), message)
    end
    @test_throws ArgumentError NB.NetworkTopology((; dc), (
        NB.Bus(:DC; ports = ((:dc, :dc),), domain = ACDQ),))
end

@testset "Net terminals and ground" begin
    machine = synchronousmachine().element_model
    line = impedance(z = 1.0, pins = 3).element_model
    dc = impedance(z = 2.0, pins = 1).element_model
    topology = NB.NetworkTopology((; machine, line, dc), (
        NB.Net(:d; terminals = ((:machine, :ac, :d),)),
        NB.Net(:gnd_q; terminals = ((:machine, :ac, :q),)),
        NB.Net(:phase_a; terminals = ((:line, :side1, :a),)),
        NB.Net(:phase_b; terminals = ((:line, :side1, :b),)),
        NB.Net(:phase_c; terminals = ((:line, :side1, :c),)),
        NB.Net(:DC; terminals = ((:dc, :side1, :dc),)),
        NB.Net(:gnd; terminals = ((:dc, :side2, :dc),)),
    ))
    rows = topology.connections
    @test rows.net == [:d, :gnd_q, :phase_a, :phase_b, :phase_c, :DC, :gnd]
    @test rows.bus == [0, 0, 1, 1, 1, 1, 0]
    @test rows.frame == [:dq, :dq, :abc, :abc, :abc, :dc, :dc]
    @test length(NB.acconnections(topology)) == 3
    @test length(NB.dcconnections(topology)) == 1
    @test isempty(NB.sortedcomponentconnections(topology, :machine))
    @test NB.sortedcomponentconnections(topology, :machine; withground = true).net ==
        [:d, :gnd_q]
    for label in (:d, :q, :wrong)
        @test_throws ArgumentError NB.NetworkTopology((; line), (
            NB.Net(:invalid; terminals = ((:line, :side1, label),)),))
    end
    @test_throws ArgumentError NB.NetworkTopology((; machine), (
        NB.Net(:invalid; terminals = ((:machine, :ac, :a),)),))
    @test_throws ArgumentError NB.NetworkTopology((; line), (
        NB.Net(:invalid; terminals = ((:line, :side1, :a),), domain = ACDQ),))

    grounded = NB.NetworkTopology((; line), (
        NB.Bus(:gnd_bus; ports = ((:line, :side2),)),))
    @test all(iszero, grounded.connections.bus)
end

@testset "Deterministic numbering and admittance order" begin
    z1 = impedance(z = 1.0, pins = 1).element_model
    z2 = impedance(z = 2.0, pins = 1).element_model
    grid = ac_source().element_model
    elements = (; z1, z2, grid)
    declarations = (
        NB.Net(:last_alphabetically; terminals = ((:z2, :side2, :dc),)),
        NB.Bus(:AC; ports = ((:grid, :ac),)),
        NB.Net(:first_alphabetically; terminals = ((:z1, :side1, :dc),)),
        NB.Net(:shared; terminals = ((:z1, :side1, :dc), (:z2, :side1, :dc))),
    )
    @test_throws ArgumentError NB.NetworkTopology(elements, declarations)
    declarations = (declarations[1:3]...,
        NB.Net(:shared; terminals = ((:z1, :side2, :dc), (:z2, :side1, :dc))))
    topology = NB.NetworkTopology(elements, declarations)
    @test topology.connections.bus == [1, 1, 1, 1, 2, 3, 3]
    @test topology.connections == NB.NetworkTopology(elements, declarations).connections
    reordered = NB.NetworkTopology(reverse(elements), declarations)
    @test topology.connections == reordered.connections
    @test NB.sortedcomponentconnections(topology, :z2).port == [:side1, :side2]

    converter = tlc().element_model
    topology = NB.NetworkTopology((; converter), (
        NB.Bus(:AC; ports = ((:converter, :ac),)),
        NB.Bus(:DC; ports = ((:converter, :dc),)),))
    @test NB.sortedcomponentconnections(topology, :converter).port == [:dc, :ac, :ac]
    @test NB.sortedcomponentconnections(topology, :converter; acfirst = true).port ==
        [:ac, :ac, :dc]
    @test NB.sortedcomponentconnections(topology.connections, :converter;
        admittance_order = PowerImpedance.admittance_order(converter)).port ==
        [:dc, :ac, :ac]
end

@testset "Exclusion and validation" begin
    z = impedance(z = 1.0, pins = 1).element_model
    off = impedance(z = 2.0, pins = 1).element_model
    elements = (; z, off)
    declarations = (NB.Bus(:DC; ports = ((:z, :side1), (:off, :side1))),)
    state = @test_logs (:info, r"Excluded elements.*off") NB.define(
        elements, declarations; exclude = (:off,))
    @test keys(state.elements) == (:z,)
    @test state.topology.connections.component == [:z]
    @test state.elements.z === z
    @test_throws ArgumentError NB.define(elements, declarations; exclude = (:absent,))
    message = topology_error() do
        NB.define(elements, (NB.Bus(:DC; ports = ((:z, :side1),)),))
    end
    @test occursin("off", message)
    @test_throws ArgumentError NB.define((; z), (NB.Bus(:DC; ports = ((:absent, :dc),)),))
    @test_throws ArgumentError NB.define((; z), (NB.Bus(:DC; ports = ((:z, :absent),)),))
    @test_throws ArgumentError NB.define((; z), (
        NB.Bus(:DC1; ports = ((:z, :side1),)),
        NB.Bus(:DC2; ports = ((:z, :side1),)),))
    bad = impedance(z = 1.0, pins = 4).element_model
    message = topology_error() do
        NB.define((; bad), (NB.Bus(:DC; ports = ((:bad, :side1),)),))
    end
    @test occursin("bad", message)
    @test occursin("4 conductors", message)

    blackbox = PowerImpedance.Blackbox_MMC()
    topology = (NB.Bus(:AC; ports = ((:blackbox, :ac),)),
        NB.Bus(:DC; ports = ((:blackbox, :dc),)))
    @test NB.NetworkTopology((; blackbox), topology).connections.port == [:ac, :ac, :dc]
    @test NB.define((; blackbox), topology).elements.blackbox === blackbox
end

@testset "Old rows and configured models" begin
    row(node, element, side, terminal) = (; node, element, side, terminal)
    grid = ac_source(setpoint = Setpoint(Vac = 132.0, θac = 0.1, Pac = 12.0, Qac = 3.0),
        pins = 3, transformation = true)
    grid.limits = PowerImpedance.Limits(P_max = 20.0)
    dc = dc_source(setpoint = Setpoint(Vdc = 640.0, Pdc = 4.0))
    line = impedance(z = 1.0, pins = 3, transformation = true)
    off = impedance(z = 2.0, pins = 1)
    off.connection = false
    rows = (row(:d, :grid, 1, 1), row(:d, :line, 1, 1),
        row(:q, :grid, 1, 2), row(:q, :line, 1, 2),
        row(:DC, :dc, 1, 1), row(:ignored, :off, 1, 1),
        row(:gnd_d, :line, 2, 1), row(:gnd_q, :line, 2, 2))
    state = @test_logs (:info, r"Excluded elements.*off") NB.define(
        (; grid, dc, line, off), rows)
    @test state.topology.connections.net == [:d, :d, :q, :q, :DC, :gnd_d, :gnd_q]
    @test state.topology.connections.bus == [1, 1, 1, 1, 1, 0, 0]
    @test state.topology.connections.terminal == [:d, :d, :q, :q, :dc, :d, :q]
    @test PowerImpedance.inputvalues(state.elements.grid) ==
        (v = 132.0, theta = 0.1, p = 12.0, q = 3.0)
    @test PowerImpedance.inputvalues(state.elements.dc) == (v = 640.0, p = 4.0)
    @test PowerImpedance.limits(state.elements.grid) == grid.limits
    @test grid.element_model !== state.elements.grid
    @test state.elements.line === line.element_model
    @test PowerImpedance.inputvalues(grid.element_model) ==
        (v = 132.0, theta = 0.1, p = 12.0, q = 3.0)
    @test all(model -> model isa PowerImpedance.AbstractElementModel,
        values(state.elements))
    @test_throws ArgumentError NB.define((; dc), ((node = :DC, element = :dc, side = 1),))
    @test_throws ArgumentError NB.define((; dc), (row(:DC, :dc, 2, 1),))
    @test_throws ArgumentError NB.define((; dc), (row(:DC, :dc, 1, 2),))

    constructors = (
        point -> mmc(sync = PLLSynchronization(),
            delta_control = ΔdqControlGFL(outer_active = OuterActivePowerControl(),
                outer_reactive = OuterReactiveQControl(), occ = InnerCurrentPIControl()),
            sigma_control = ΣdqzControlTEC(), setpoint = point),
        point -> tlc(outerActive = OuterActiveVdcControl(),
            outerReactive = OuterReactiveVacControl(), setpoint = point),
    )
    for constructor in constructors
        point = Setpoint(Pac = 120.0, Qac = 30.0, Vac = 210.0,
            Pdc = -121.0, Vdc = 630.0, θac = 0.0)
        converter = constructor(point)
        converter.limits = PowerImpedance.Limits(P_max = 9.0)
        state = NB.define((; converter), (
            row(:DC, :converter, 1, 1), row(:d, :converter, 2, 1),
            row(:q, :converter, 2, 2)))
        model = state.elements.converter
        b = bases(model)
        @test PowerImpedance.powerflow_targets(model) == (
            p_ac = 120.0 / b.S, q_ac = 30.0 / b.S, v_ac = 210.0 / b.v_ac,
            p_dc = point.Pdc / b.S, v_dc = 630.0 / b.v_dc)
        @test limits(model) == converter.limits
        @test model.cache !== converter.element_model.cache
        @test state.topology.connections.port == [:dc, :ac, :ac]
    end

    scalar = impedance(z = 2.0, pins = 1)
    inferred = NB.NetworkTopology((; grid, scalar), (
        row(:d, :grid, 1, 1), row(:q, :grid, 1, 2),
        row(:d, :scalar, 1, 1), row(:gnd_d, :scalar, 2, 1)))
    @test all(==(1), inferred.connections.domain)
    @test all(==(:dq), inferred.connections.frame)

    machine = synchronousmachine(setpoint =
        Setpoint(Pac = 15.0, Qac = 3.0, Vac = 220.0, θac = 0.0))
    state = NB.define((; machine),
        (row(:d, :machine, 1, 1), row(:q, :machine, 1, 2)))
    b = bases(state.elements.machine)
    @test inputvalues(state.elements.machine).powerflow ==
        (p = 15.0 / b.S, q = 3.0 / b.S, v = 220.0 / b.v_ac)
end

@testset "Gridspace materializes old Elements through define" begin
    line = impedance(NB.Grid; z = NB.Grid((1.0, 2.0)), pins = 1)
    off = impedance(z = 3.0, pins = 1)
    rows = ((node = :DC, element = :line, side = 1, terminal = 1),)
    space = NB.define((; line, off), rows; exclude = (:off,))
    states = [@test_logs (:info, r"Excluded elements.*off") NB.materialize(config)
        for config in NB.configurations(space)]
    @test length(states) == 2
    @test all(state -> keys(state.elements) == (:line,), states)
    @test all(state -> state.elements.line isa PowerImpedance.Impedance, states)
    @test all(state -> state.topology.connections.net == [:DC], states)
end
