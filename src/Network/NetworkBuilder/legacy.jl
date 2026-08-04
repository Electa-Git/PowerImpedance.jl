function updateelempins!(elements, connectionsregistry)
	for (name, element) in pairs(elements)
		pins = filter(row -> row.elem == name, connectionsregistry.registry)
		for pin in pins
			legacypinname = pin_name(pin.side, pin.terminal)
			net = pin.net
			element.pins[legacypinname] = net
		end
	end
end

function build_network(elements::NamedTuple, connections::ConnectionsRegistry, options::NamedTuple)
	
    ## Add not connected side of single-port elements to ground
	connreg = deepcopy(connections.registry)	
    singleportconnections = filter(row -> !P.isgroundnet(row.net) && P.issingleport(elements[row.elem]), connreg)
    elemsidetable = Table(elements = singleportconnections.elem, side = singleportconnections.side, elecdomain=singleportconnections.elecdomain)
    elemsidetable = Table(unique(elemsidetable))
	for row in elemsidetable
        to_add_side = row.side == 1 ? 2 : 1
        to_add_pins = row.side == 1 ? P.nip(elements[row.elements]) : P.nop(elements[row.elements])
        for pin in 1:to_add_pins
            newrow = (; net = Symbol("gnd"), bus=0, elem = row.elements, side = to_add_side, terminal = pin, elecdomain = row.elecdomain)
            push!(connreg, newrow)
        end
    end

    elements = deepcopy(elements) # Avoid rewriting of elements in new version
    network = P.Network()
	network.voltageBase[1] = option_value(options, :voltageBase, network.voltageBase[1])

	for (name, element) in pairs(elements)
		element isa P.Element ||
			throw(ArgumentError("NetworkBuilder element :$name must be an Element."))
		P.add!(network, name, element)
	end

	netnames = unique(connreg.net) # Collection of net names
	
	for net in netnames
		net_entries = filter(r -> r.net == net, connreg)
		networkpins = Any[map(connrowtonwpin, net_entries)...]
		push!(networkpins, net) # Add net name as pin for backward compatibility with previous behavior
		P.connect!(network, networkpins...)
		
	end

    P.check_lumped_elements(network)

	
	P.connect!(network)
	return network
end