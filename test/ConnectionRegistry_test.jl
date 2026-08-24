using PowerImpedance
using Test

const NB = PowerImpedance.NetworkBuilder

row(node, element, side, terminal) = (; node, element, side, terminal)

@testset "NetworkTopology named rows" begin
    elements = (
        z1 = impedance(z = 1.0, pins = 1),
        z2 = impedance(z = 2.0, pins = 1),
        z3 = impedance(z = 3.0, pins = 1)
    )
    connections = (
        row(:n1, :z1, 1, 1),
        row(:n1, :z2, 1, 1),
        row(:n1, :z3, 1, 1),
        row(:gnd, :z1, 2, 1),
        row(:gnd, :z2, 2, 1),
        row(:gnd, :z3, 2, 1)
    )
    topology = NB.NetworkTopology(elements, connections)

    @test topology.connections.node == [:n1, :n1, :n1, :gnd, :gnd, :gnd]
    @test topology.connections.element == [:z1, :z2, :z3, :z1, :z2, :z3]
    @test all(==(1), topology.connections.bus[1:3])
    @test all(iszero, topology.connections.bus[4:6])
    @test all(==(2), topology.connections.domain)

    builder = NB.define(elements, collect(connections))
    @test builder isa NB.NetworkState
    @test builder.topology.connections == topology.connections
    @test collect(keys(builder.elements)) == collect(keys(elements))

    reordered = NB.NetworkTopology(
        elements,
        ((element = :z1, terminal = 1, node = :n1, side = 1),)
    )
    @test only(reordered.connections).node == :n1
end

@testset "NetworkTopology component ports" begin
    overhead = overhead_line(
        length = 1e3,
        conductors = Conductors(organization = :flat, nᵇ = 3),
        transformation = true
    )
    cable_element = cable(
        length = 1e3,
        positions = [(-1.0, 1.0), (0.0, 1.0), (1.0, 1.0)],
        C1 = Conductor(rₒ = 0.01),
        transformation = true
    )
    blackbox_line_element = blackbox_line(
        data_type = :Ztool,
        n = 3,
        transformation = true
    )
    transformer_element = transformer(
        pins = 3,
        n = 1.0,
        Rₚ = 0.1,
        Lₚ = 1e-3,
        Rₛ = 0.1,
        Lₛ = 1e-3,
        transformation = true
    )
    two_level = tlc()
    delta_control = ΔdqControlGFL(
        outer_active = NoOuterActiveControl(),
        outer_reactive = NoOuterReactiveControl(),
        occ = NoInnerCurrentControl()
    )
    modular_multilevel = mmc(
        sync = NoSynchronization(),
        delta_control = delta_control,
        sigma_control = ΣdqzControlTEC()
    )
    blackbox_converter = PowerImpedance.Element(
        input_pins = 1,
        output_pins = 2,
        element_model = PowerImpedance.Blackbox_MMC()
    )

    families = (
        dc_source = dc_source(),
        ac_source = ac_source(pins = 3, transformation = true),
        impedance = impedance(z = 1.0, pins = 3, transformation = true),
        transformer = transformer_element,
        overhead = overhead,
        cable = cable_element,
        blackbox_line = blackbox_line_element,
        mmc = modular_multilevel,
        tlc = two_level,
        blackbox_converter = blackbox_converter,
        synchronous_machine = synchronousmachine(),
        induction_machine = inductionmachine()
    )

    @test [(port.side, port.terminals, port.domain)
           for port in NB._port_descriptions(families.dc_source)] == [(1, 1, 2)]
    @test [(port.side, port.terminals, port.domain)
           for port in NB._port_descriptions(families.ac_source)] == [(1, 2, 1)]
    for name in (:mmc, :tlc, :blackbox_converter)
        @test [(port.side, port.terminals, port.domain)
               for port in NB._port_descriptions(families[name])] ==
              [(1, 1, 2), (2, 2, 1)]
    end
    for name in (:impedance, :transformer, :overhead, :cable, :blackbox_line)
        @test [(port.side, port.terminals, port.domain)
               for port in NB._port_descriptions(families[name])] ==
              [(1, 2, 1), (2, 2, 1)]
    end
    @test only(NB._port_descriptions(families.synchronous_machine)).domain == 1
    @test only(NB._port_descriptions(families.induction_machine)).domain == 1
    @test all(
        iszero(port.domain)
    for port in NB._port_descriptions(impedance(z = 1.0, pins = 1))
    )
end

@testset "NetworkTopology infers scalar passive domains" begin
    elements = (
        ac = impedance(z = 1.0, pins = 3, transformation = true),
        d_load = impedance(z = 2.0, pins = 1)
    )
    connections = (
        row(:d, :ac, 1, 1),
        row(:d, :d_load, 1, 1),
        row(:gnd_d, :d_load, 2, 1)
    )
    topology = NB.NetworkTopology(elements, connections)
    @test all(==(1), topology.connections.domain)

    dc = NB.NetworkTopology(
        (branch = impedance(z = 2.0, pins = 1),),
        (row(:dc, :branch, 1, 1), row(:gnd, :branch, 2, 1))
    )
    @test all(==(2), dc.connections.domain)

    active_elements = (
        machine = synchronousmachine(),
        load = impedance(z = 2.0, pins = 1)
    )
    active_connections = (
        row(:d, :machine, 1, 1),
        row(:q, :machine, 1, 2),
        row(:d, :load, 1, 1),
        row(:gnd_d, :load, 2, 1)
    )
    active_network = NB.define(active_elements, active_connections)
    error = try
        PowerImpedance.compute(
            NB.PowerFlowProblem(active_network),
            NB.ACDCPowerFlow()
        )
        nothing
    catch caught
        caught
    end
    @test error isa ArgumentError
    @test occursin("transformed three-phase element", sprint(showerror, error))
end

@testset "NetworkTopology physical one-port rows" begin
    elements = (
        grid = ac_source(pins = 3, transformation = true),
        machine = synchronousmachine(),
        line = impedance(z = 1.0, pins = 3, transformation = true)
    )
    connections = (
        row(:grid_d, :grid, 1, 1),
        row(:grid_d, :line, 1, 1),
        row(:grid_q, :grid, 1, 2),
        row(:grid_q, :line, 1, 2),
        row(:machine_d, :line, 2, 1),
        row(:machine_d, :machine, 1, 1),
        row(:machine_q, :line, 2, 2),
        row(:machine_q, :machine, 1, 2)
    )
    topology = NB.NetworkTopology(elements, connections)
    @test all(
        row -> row.side == 1,
        filter(row -> row.element in (:grid, :machine), topology.connections)
    )
    @test isempty(filter(row -> PowerImpedance.isgroundnet(row.node), topology.connections))

    classic = NB.build_network(elements, topology, (;))
    @test haskey(classic.nets, :grid_d)
    @test haskey(classic.nets, :machine_q)
end

@testset "NetworkTopology validation" begin
    dc = impedance(z = 1.0, pins = 1)
    ac = impedance(z = 1.0, pins = 3, transformation = true)
    elements = (; dc, ac)

    @test_throws ArgumentError NB.NetworkTopology(
        elements,
        ((node = :n1, element = :dc, side = 1),)
    )
    @test_throws ArgumentError NB.NetworkTopology(
        elements,
        (row(:n1, :missing, 1, 1),)
    )
    @test_throws ArgumentError NB.NetworkTopology(
        elements,
        (row(:n1, :dc, 3, 1),)
    )
    @test_throws ArgumentError NB.NetworkTopology(
        elements,
        (row(:n1, :dc, 1, 2),)
    )
    @test_throws ArgumentError NB.NetworkTopology(
        elements,
        (row(:n1, :dc, 1, 1), row(:n2, :dc, 1, 1))
    )
    mixed_elements = (
        dc_source = dc_source(),
        ac_source = ac_source(pins = 3, transformation = true)
    )
    @test_throws ArgumentError NB.NetworkTopology(
        mixed_elements,
        (row(:mixed, :dc_source, 1, 1), row(:mixed, :ac_source, 1, 1))
    )
    bridge_elements = (
        dc_source = dc_source(),
        ac_source = ac_source(pins = 3, transformation = true),
        bridge = impedance(z = 1.0, pins = 1)
    )
    @test_throws ArgumentError NB.NetworkTopology(
        bridge_elements,
        (
            row(:dc_bus, :dc_source, 1, 1),
            row(:dc_bus, :bridge, 1, 1),
            row(:ac_bus, :ac_source, 1, 1),
            row(:ac_bus, :bridge, 2, 1)
        )
    )

    off = impedance(z = 2.0, pins = 1)
    off.connection = false
    builder = NB.define(
        (; dc, off),
        (row(:n1, :dc, 1, 1), row(:ignored, :off, 1, 1))
    )
    @test !haskey(builder.elements, :off)
    @test all(!=(:off), builder.topology.connections.element)
end

@testset "Retired NetworkBuilder names" begin
    replacements = (
        BuilderState = "NetworkState",
        ConnectionsRegistry = "NetworkTopology",
        LinearizedAdmittanceCollection = "AdmittanceLookup",
        LinearizedInterface = "NetworkLookup",
        LinearizedAdmittanceNetwork = "NetworkModel"
    )
    for (removed, replacement) in pairs(replacements)
        error = try
            getfield(NB, removed)()
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        @test occursin(String(removed), sprint(showerror, error))
        @test occursin(replacement, sprint(showerror, error))
        @test occursin("migration", sprint(showerror, error))
    end
    @test !isdefined(NB, :pin)
    @test !isdefined(NB, :Pin)
    @test !isdefined(NB, :ConnectionDef)
    @test !isdefined(NB, Symbol("⟷"))
    @test !isdefined(NB, Symbol("↔"))
end

module ClassicNetworkDSLTest
import PowerImpedance: @network
using PowerImpedance: impedance

function build()
    return @network begin
        z1 = impedance(z = 1.0, pins = 1)
        z2 = impedance(z = 2.0, pins = 1)
        z1[1.1] ⟷ z2[1.1] ⟷ n1
        z1[2.1] ⟷ z2[2.1] ⟷ gnd
    end
end
end

@testset "Explicit Classic network DSL import" begin
    classic = ClassicNetworkDSLTest.build()
    @test Set(classic.nets[:n1]) ==
          Set([(:z1, Symbol("1.1")), (:z2, Symbol("1.1"))])
    @test Set(classic.nets[:gnd]) ==
          Set([(:z1, Symbol("2.1")), (:z2, Symbol("2.1"))])
end
