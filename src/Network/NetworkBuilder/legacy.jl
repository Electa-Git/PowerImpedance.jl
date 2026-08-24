function build_network(
        elements::NamedTuple,
        topology::NetworkTopology,
        options::NamedTuple
)
    connections = deepcopy(topology.connections)

    # The Classic network represents one-port devices with a second side tied to
    # ground. This conversion does not modify the NetworkTopology.
    single_port_rows = filter(
        row -> !P.isgroundnet(row.node) && P.issingleport(elements[row.element]),
        connections
    )
    connected_sides = unique(
        Table(
        element = single_port_rows.element,
        side = single_port_rows.side,
        domain = single_port_rows.domain
    ),
    )
    for row in connected_sides
        ground_side = row.side == 1 ? 2 : 1
        terminal_count = row.side == 1 ? P.nip(elements[row.element]) :
                         P.nop(elements[row.element])
        for terminal in 1:terminal_count
            push!(
                connections,
                (
                    node = :gnd,
                    bus = 0,
                    element = row.element,
                    side = ground_side,
                    terminal,
                    domain = row.domain
                )
            )
        end
    end

    network_elements = deepcopy(elements)
    network = P.Network()
    network.voltageBase[1] = option_value(
        options,
        :voltageBase,
        network.voltageBase[1]
    )

    for (name, element) in pairs(network_elements)
        element isa P.Element || throw(
            ArgumentError("NetworkBuilder element :$name must be an Element"),
        )
        P.add!(network, name, element)
    end

    for node in unique(connections.node)
        rows = filter(row -> row.node == node, connections)
        classic_pins = Any[map(connection_to_classic_pin, rows)...]
        push!(classic_pins, node)
        P.connect!(network, classic_pins...)
    end

    P.check_lumped_elements(network)
    P.connect!(network)
    return network
end
