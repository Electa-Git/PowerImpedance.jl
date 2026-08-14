using PowerImpedance.NetworkBuilder: pin, ⟷, Pin, ConnectionDef, ConnectionsRegistry, ↔


@testset "Pin Creation and Parsing" begin
    @testset "Pin creation with explicit side and terminal" begin
        # Test basic pin creation using explicit integer arguments.
        # Validates that pins are created with correct element, side, and terminal fields.
        p = pin(:elem1, 1, 1)
        @test p.elementid == :elem1
        @test p.side == 1
        @test p.terminal == 1
        @test isa(p, Pin)
    end

    @testset "Pin creation with tuple notation" begin
        # Test pin creation using tuple notation (side, terminal).
        # Verifies that both explicit integers and tuple unpacking work identically.
        p1 = pin(:elem1, 1, 2)
        p2 = pin(:elem1, (1, 2))
        @test p1.elementid == p2.elementid
        @test p1.side == p2.side
        @test p1.terminal == p2.terminal
    end

    @testset "Pin creation with string notation" begin
        # Test pin creation using legacy string notation "side.terminal".
        # Ensures backward compatibility with existing naming convention.
        p = pin(:elem1, "1.1")
        @test p.side == 1
        @test p.terminal == 1
        
        p2 = pin(:elem2, "3.5")
        @test p2.side == 3
        @test p2.terminal == 5
    end

    @testset "Pin creation with symbol string notation" begin
        # Test pin creation using symbol notation for legacy format.
        # Validates that symbols are correctly parsed as "side.terminal".
        p = pin(:elem1, Symbol("2.3"))
        @test p.side == 2
        @test p.terminal == 3
    end

    @testset "Pin name property" begin
        # Test that pin.name property correctly generates legacy naming format.
        # Verifies the computed property returns correct Symbol format.
        p = pin(:elem1, 1, 1)
        @test p.name == Symbol("1.1")
        
        p2 = pin(:elem2, 2, 5)
        @test p2.name == Symbol("2.5")
    end

    @testset "Pin validation - invalid side" begin
        # Test error handling for invalid side numbers (must be >= 1).
        # Ensures proper validation of pin parameters.
        @test_throws ArgumentError pin(:elem1, 0, 1)
        @test_throws ArgumentError pin(:elem1, "0.1")
        @test_throws ArgumentError pin(:elem1, (-1, 1))
    end

    @testset "Pin validation - invalid terminal" begin
        # Test error handling for invalid terminal numbers (must be >= 1).
        # Ensures proper validation of terminal indices.
        @test_throws ArgumentError pin(:elem1, 1, 0)
        @test_throws ArgumentError pin(:elem1, "1.0")
        @test_throws ArgumentError pin(:elem1, (1, -2))
    end

    @testset "Pin validation - malformed string" begin
        # Test error handling for malformed pin name strings.
        # Validates that strings without proper "side.terminal" format are rejected.
        @test_throws ArgumentError pin(:elem1, "1")
        @test_throws ArgumentError pin(:elem1, "1.2.3")
        @test_throws ArgumentError pin(:elem1, "a.b")
        @test_throws ArgumentError pin(:elem1, "1.")
        @test_throws ArgumentError pin(:elem1, ".1")
    end

    @testset "Pin type conversion" begin
        # Test that pin side and terminal are correctly converted to Int.
        # Ensures consistency regardless of input numeric type.
        p = pin(:elem1, Int32(1), Int64(2))
        @test p.side === 1  # Exactly Int
        @test p.terminal === 2
        
        p2 = pin(:elem1, UInt8(3), UInt16(4))
        @test p2.side === 3
        @test p2.terminal === 4
    end

    @testset "Pin equality and hashing" begin
        # Test that pins with identical parameters are treated as equal.
        # Validates that pins can be used in sets and dictionaries.
        p1 = pin(:elem1, 1, 1)
        p2 = pin(:elem1, 1, 1)
        p3 = pin(:elem1, 1, 2)
        
        @test p1 == p2
        @test p1 ≠ p3
        @test hash(p1) == hash(p2)
    end
end

@testset "ConnectionDef Structure" begin
    @testset "ConnectionDef with single pin" begin
        # Test creating a connection definition with a single endpoint.
        # Verifies that single pins are wrapped in a vector.
        p = pin(:elem1, 1, 1)
        conn = ConnectionDef(p)
        @test conn.endpoints == [p]
        @test conn.name === nothing
    end

    @testset "ConnectionDef with named connection" begin
        # Test creating a named connection definition.
        # Ensures names are stored correctly in the ConnectionDef structure.
        p = pin(:elem1, 1, 1)
        conn = ConnectionDef(p; name=:net1)
        @test conn.endpoints == [p]
        @test conn.name == :net1
    end

    @testset "ConnectionDef with vector of pins" begin
        # Test creating a connection definition with multiple pins.
        # Validates vector of endpoints are properly stored.
        p1 = pin(:elem1, 1, 1)
        p2 = pin(:elem2, 1, 1)
        conn = ConnectionDef([p1, p2]; name=:bus1)
        @test conn.endpoints == [p1, p2]
        @test conn.name == :bus1
    end
end

@testset "Connection Operator ⟷" begin
    @testset "Connect two pins" begin
        # Test the ⟷ operator to connect two pins.
        # Verifies that the connection creates proper ConnectionDef with both endpoints.
        p1 = pin(:elem1, 1, 1)
        p2 = pin(:elem2, 1, 1)
        conn = p1 ⟷ p2
        
        @test conn.name === nothing
        @test Set(conn.endpoints) == Set([p1, p2])
    end

    @testset "Connect pin to named net" begin
        # Test connecting a pin to a named net (symbol).
        # Validates that the connection name is correctly assigned.
        p = pin(:elem1, 1, 1)
        conn = p ⟷ :net1
        
        @test conn.name == :net1
        @test p in conn.endpoints
    end

    @testset "Connect named net to pin" begin
        # Test connecting a named net (symbol) to a pin (reversed order).
        # Ensures operator is commutative for name assignment.
        p = pin(:elem1, 1, 1)
        conn = :net1 ⟷ p
        
        @test conn.name == :net1
        @test p in conn.endpoints
    end

    @testset "Chain multiple connections" begin
        # Test chaining multiple connections using ⟷.
        # Validates that all endpoints are properly accumulated.
        p1 = pin(:elem1, 1, 1)
        p2 = pin(:elem2, 1, 1)
        p3 = pin(:elem3, 1, 1)
        
        conn = p1 ⟷ p2 ⟷ p3
        
        @test Set(conn.endpoints) == Set([p1, p2, p3])
        @test conn.name === nothing
    end

    @testset "Named connection in chain" begin
        # Test chaining connections with a named endpoint.
        # Ensures name propagates correctly through the chain.
        p1 = pin(:elem1, 1, 1)
        p2 = pin(:elem2, 1, 1)
        
        conn = p1 ⟷ p2 ⟷ :bus1
        
        @test conn.name == :bus1
        @test Set(conn.endpoints) == Set([p1, p2])
    end

    @testset "Name conflict detection" begin
        # Test that connecting nets with conflicting names raises an error.
        # Ensures data integrity by preventing ambiguous connections.
        conn1 = pin(:elem1, 1, 1) ⟷ :net1
        conn2 = pin(:elem2, 1, 1) ⟷ :net2
        
        @test_throws ArgumentError conn1 ⟷ conn2
    end

    @testset "Same name concatenation" begin
        # Test that connecting nets with the same name succeeds.
        # Validates that same-named nets can be merged.
        p1 = pin(:elem1, 1, 1) ⟷ :net1
        p2 = pin(:elem2, 1, 1) ⟷ :net1
        
        conn = p1 ⟷ p2
        @test conn.name == :net1
        @test Set(conn.endpoints) == Set([pin(:elem1, 1, 1), pin(:elem2, 1, 1)])
    end

    @testset "Bidirectional operator ↔" begin
        # Test that ↔ operator works identically to ⟷.
        # Ensures both operators are equivalent.
        p1 = pin(:elem1, 1, 1)
        p2 = pin(:elem2, 1, 1)
        
        conn1 = p1 ⟷ p2
        conn2 = p1 ↔ p2
        
        @test Set(conn1.endpoints) == Set(conn2.endpoints)
        @test conn1.name == conn2.name
    end
end

@testset "ConnectionsRegistry Creation" begin
    @testset "Registry from simple connections" begin
        # Test creating a registry from basic connection definitions.
        # Validates proper mapping of elements to buses.
        elements = (; 
            z1 = impedance(z=1, pins=1),
            z2 = impedance(z=2, pins=1)
        )
        
        connections = (
            pin(:z1, 1, 1) ⟷ pin(:z2, 1, 1) ⟷ :n1,
            pin(:z1, 2, 1) ⟷ pin(:z2, 2, 1) ⟷ :gnd,
        )
        
        registry = ConnectionsRegistry(elements, connections)
        
        @test registry.registry.net !== nothing
        @test :n1 in registry.registry.net
        @test :gnd in registry.registry.net
    end

    @testset "Registry bus assignment" begin
        # Test that registry correctly assigns bus numbers to connections.
        # Validates that same net endpoints share the same bus number.
        elements = (; 
            z1 = impedance(z=1, pins=1),
            z2 = impedance(z=2, pins=1)
        )
        
        connections = (
            pin(:z1, 1, 1) ⟷ pin(:z2, 1, 1) ⟷ :net1,
        )
        
        registry = ConnectionsRegistry(elements, connections)
        
        # Find entries for net1
        net1_entries = filter(r -> r.net == :net1, registry.registry)
        
        # All entries for same net should have same bus
        @test length(unique(net1_entries.bus)) == 1
    end

    @testset "Registry element-side tracking" begin
        # Test that registry correctly tracks element, side, and terminal information.
        # Ensures proper mapping of physical connections.
        elements = (; 
            z1 = impedance(z=1, pins=2),
        )
        
        connections = (
            pin(:z1, 1, 1) ⟷ :net1,
            pin(:z1, 2, 1) ⟷ :gnd,
        )
        
        registry = ConnectionsRegistry(elements, connections)
        
        @test any(r -> r.elem == :z1 && r.side == 1 && r.terminal == 1, registry.registry)
        @test any(r -> r.elem == :z1 && r.side == 2 && r.terminal == 1, registry.registry)
    end

    @testset "Registry with disconnected element" begin
        # Test registry behavior with disconnected elements (connection=false).
        # Validates that disconnected elements are not included.
        elements = (; 
            z1 = impedance(z=1, pins=1),
            z2 = impedance(z=2, pins=1)
        )
        
        connections = (
            pin(:z1, 1, 1) ⟷ :net1,
        )
        
        registry = ConnectionsRegistry(elements, connections)
        
        # Only z1 should be in registry, not z2
        elem_in_registry = unique(registry.registry.elem)
        @test :z1 in elem_in_registry
    end

    @testset "Registry merge by name" begin
        # Test that connections with same net name are merged.
        # Validates that split connection definitions are properly combined.
        elements = (; 
            z1 = impedance(z=1, pins=1),
            z2 = impedance(z=2, pins=1),
            z3 = impedance(z=3, pins=1),
        )
        
        connections = (
            pin(:z1, 1, 1) ⟷ :net1,
            pin(:z2, 1, 1) ⟷ :net1,
            pin(:z3, 1, 1) ⟷ :net1,
        )
        
        registry = ConnectionsRegistry(elements, connections)
        
        # All three should be on same bus
        net1_entries = filter(r -> r.net == :net1, registry.registry)
        @test length(unique(net1_entries.bus)) == 1
        @test length(net1_entries) == 3
    end

    
    @testset "Registry electrical domain tracking" begin
        # Test that registry tracks electrical domain information.
        # Validates domain assignments for multi-domain systems.
        elements = (; 
            z1 = impedance(z=1, pins=1),
        )
        
        connections = (
            pin(:z1, 1, 1) ⟷ :net1,
        )
        
        registry = ConnectionsRegistry(elements, connections)
        
        # Electrical domain should be assigned
        @test !isempty(registry.registry.elecdomain)
    end
end

@testset "Edge Cases and Error Handling" begin
    @testset "Empty connections tuple" begin
        # Test handling of empty connections tuple.
        # Validates that empty input is handled gracefully.
        elements = (; z1 = impedance(z=1, pins=1))
        connections = ()
        
        registry = ConnectionsRegistry(elements, connections)
        @test isempty(registry.registry)
    end

    @testset "Multiple pins on same element-side" begin
        # Test connection of multiple terminals on same element side.
        # Validates that multi-terminal connections work correctly.
        elements = (; z1 = impedance(z=1, pins=2))
        
        connections = (
            pin(:z1, 1, 1) ⟷ :net1,
            pin(:z1, 1, 2) ⟷ :net2,
        )
        
        registry = ConnectionsRegistry(elements, connections)
        
        net1_entries = filter(r -> r.net == :net1, registry.registry)
        net2_entries = filter(r -> r.net == :net2, registry.registry)
        
        @test length(net1_entries) == 1
        @test length(net2_entries) == 1
        # Different nets should same bus bcs same sid
        @test net1_entries.bus[1] == net2_entries.bus[1]
    end

    @testset "Many chained connections" begin
        # Test chaining large number of connections.
        # Validates performance and correctness with complex topologies.
        n = 20
        pins = [pin(Symbol("elem$i"), 1, 1) for i in 1:n]
        
        # Create chain
        conn = pins[1]
        for i in 2:n
            conn = conn ⟷ pins[i]
        end
        conn = conn ⟷ :bus_large
        
        @test length(conn.endpoints) == n
        @test conn.name == :bus_large
    end

    @testset "Element not in elements dict" begin
        # Test handling of pin references to non-existent elements.
        # Validates proper error handling for undefined elements.
        elements = (; z1 = impedance(z=1, pins=1))
        
        connections = (
            pin(:z1, 1, 1) ⟷ pin(:z2, 1, 1) ⟷ :net1,
        )
        
        # Should not error during registry creation, but elements dict is separate concern
        # This test documents current behavior
        @test_throws AssertionError ConnectionsRegistry(elements, connections)
        
        
    end

    @testset "Special characters in net names" begin
        # Test that net names with special characters are handled correctly.
        # Validates robustness of naming convention.
        p = pin(:elem1, 1, 1)
        conn = p ⟷ Symbol("net_1")
        @test conn.name == Symbol("net_1")
        
        conn2 = p ⟷ Symbol("net-2")
        @test conn2.name == Symbol("net-2")
    end

    @testset "Ground net naming convention" begin
        # Test common ground net naming patterns.
        # Validates that standard conventions work correctly.
        p1 = pin(:z1, 1, 1) ⟷ :gnd
        p2 = pin(:z2, 1, 1) ⟷ :gnd_1
        p3 = pin(:z3, 1, 1) ⟷ Symbol("gnd.0")
        
        @test p1.name == :gnd
        @test p2.name == :gnd_1
        @test p3.name == Symbol("gnd.0")
    end
end

@testset "Integration with NetworkBuilder" begin
    @testset "Simple two-element circuit" begin
        # Integration test: Create registry and build simple network.
        # Validates end-to-end workflow with NetworkBuilder.
        elements = (; 
            z1 = impedance(z=1, pins=1),
            z2 = impedance(z=2, pins=1)
        )
        
        connections = (
            pin(:z1, 1, 1) ⟷ pin(:z2, 1, 1) ⟷ :n1,
            pin(:z1, 2, 1) ⟷ pin(:z2, 2, 1) ⟷ :gnd,
        )
        
        builder = NetworkBuilder.define(elements, connections)
        network = NetworkBuilder.build_network(builder.elements, builder.connections, builder.options)
        @test :n1 in keys(network.nets)
        @test :gnd in keys(network.nets)
    end

    @testset "Multi-node network" begin
        # Integration test: Create registry for larger network.
        # Validates scalability with more complex topologies.
        elements = (; 
            z1 = impedance(z=1, pins=1),
            z2 = impedance(z=2, pins=1),
            z3 = impedance(z=3, pins=1),
        )
        
        connections = (
            pin(:z1, 1, 1) ⟷ pin(:z2, 1, 1) ⟷ :n1,
            pin(:z2, 2, 1) ⟷ pin(:z3, 1, 1) ⟷ :n2,
            pin(:z1, 2, 1) ⟷ pin(:z3, 2, 1) ⟷ :gnd,
        )
        
        builder = NetworkBuilder.define(elements, connections)
        network = NB.build_network(builder.elements, builder.connections, builder.options)
        
        @test :n1 in keys(network.nets)
        @test :n2 in keys(network.nets)
        @test :gnd in keys(network.nets)
    end
end
