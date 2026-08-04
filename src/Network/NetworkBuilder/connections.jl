#### Intermediate data structures for defining connections ##########
"""
 Pin(elementid::Symbol, side::Int, terminal::Int)
 Represents a pin of an element, identified by the element's ID, the side of the element, and the terminal number on that side.
"""
struct Pin
	elementid::Symbol
	side::Int
	terminal::Int

	function Pin(elementid::Symbol, side::Int, terminal::Int)
		side > 0 || throw(ArgumentError("Pin side must be >= 1, got $side."))
		terminal > 0 ||
			throw(ArgumentError("Pin terminal must be >= 1, got $terminal."))
		return new(elementid, side, terminal)
	end
end

"""
    Collection of pins of elements and the name of the connection
"""
struct ConnectionDef
	name::Union{Symbol, Nothing}
	endpoints::Vector{Pin}
end

ConnectionDef(endpoints::Vector{Pin};name=nothing) = ConnectionDef(name, endpoints)
ConnectionDef(endpoint::Pin;name=nothing) = ConnectionDef([endpoint,]; name)
ConnectionDef(name::Symbol) = ConnectionDef(name, Pin[])
ConnectionDef(conn::ConnectionDef; name=conn.name) = ConnectionDef(name, conn.endpoints)


"""
	⟷(left, right)
Connects corresponding pins or gives names to the nets


Returns intermediate ConnectionDef (parsed as NamedTuple afterwards).
"""
function ⟷(left,right) 
	
	left_conn = ConnectionDef(left)
	right_conn = ConnectionDef(right)
	
	if !isnothing(left_conn.name) && !isnothing(right_conn.name) && left_conn.name != right_conn.name
		throw(ArgumentError("Cannot connect two named nets with different names: :$(left_conn.name) and :$(right_conn.name)."))
	else 
		name = !isnothing(left_conn.name) ? left_conn.name : right_conn.name
		endpoints = vcat(left_conn.endpoints, right_conn.endpoints)
		return ConnectionDef(endpoints; name)
	end
end


↔(left, right) = left ⟷ right

########## ConnectionsRegistry ############
"""

Fields:
- `nets`: NamedTuple with net names and a collection of connected element pins, e.g. `:net1 => (Pin(:element1, 1, 1), Pin(:element2, 2, 1))`
- `busregistry`: Table collecting bus information bus, elem, side, and, electrical domain 
"""
struct ConnectionsRegistry
    registry::@Table{net::Symbol,bus::Int, elem::Symbol, side::Int, terminal::Int, elecdomain::Int} 
end

"""
	ConnectionsRegistry(elements, connections)

Build a `ConnectionsRegistry` from `elements` and connection definitions.

Each connection definition must provide a `name` and `endpoints`. Endpoints in
the same connection are assigned the same bus, and the registry records the net name, bus number, element, side, terminal, and electrical domain.
"""

function ConnectionsRegistry(elements, connections::Tuple{Vararg{ConnectionDef}}, nonconnected_elements = Set())
	
	#1. Do checks of connections

	# perform merges
	connections_vec = mergebyname(connections) # Merge same netname connections 
	connections_vec = mergebysharedpin(connections_vec) #Merge with shared pin
	connections_vec = updateemptyname(connections_vec) # Update empty names to random unique symbol
	# connections = Tuple(connections_vec)



	#2. Populate registry
	registry = Table(net=Symbol[], bus=Int[], elem=Symbol[], side=Int[], terminal=Int[], elecdomain=Int[])
	for conndef in connections_vec
	
		examplepin = first(conndef.endpoints) #All endpoints should be connected to same bus
		elecdomain = P.elecdomain(elements[examplepin.elementid], examplepin.side)
		bus = internbus(registry, conndef.name, examplepin.elementid, examplepin.side, elecdomain) #Check if net already has a bus via element and side, otherwise assign next bus		
		# TODO: Check whether sides of all other elements are already connected to the same bus of the examplepin + all same elec domain
		for pin in conndef.endpoints
			@assert pin.elementid in keys(elements) "Element :$(pin.elementid) defined in connection but not found in elements."
				
			push!(registry, (;net=conndef.name, bus, elem=pin.elementid, side=pin.side, terminal=pin.terminal, elecdomain))
		
			
		end
        	end

	#Take out connections for non-connected elements (if any)
	connectfilterfunc(row) = row.elem ∉ nonconnected_elements

	registry = filter(connectfilterfunc, registry)

	return ConnectionsRegistry(registry)
end

###### Accessor functions for ConnectionsRegistry ########

"""

We search if a given element and side already exist in the registry. IF yes, they should have the same bus. Busid consists of Int + elecdomain
"""
function internbus(registry::Table, net::Symbol, element::Symbol, side::Int, elecdomain::Int)
	# Find if bus already exists for element and side
	busfilterfunc(row) = row.elem == element && row.side == side	
    busfilter = map(busfilterfunc, registry)

	if any(busfilter)
		bus_vec = registry.bus[busfilter]
		@assert length(bus_vec) == 1 "Multiple buses found for element :$element side $side. This should not happen, check your connections!"
		return bus_vec[1]
	else
		if !P.isgroundnet(net)
			
			domainbus = (filter(row -> row.elecdomain == elecdomain, registry)).bus
			nextbus = maximum(domainbus; init=0) + 1
		else
			nextbus = 0 # Ground bus is always bus 0
		end
		return nextbus
	end
end

#### Helper functions to Connectionregistry

"""
    acconnections(registry)

Return all AC connections with a nonzero (nongrounded) bus.
"""
function acconnections(registry::ConnectionsRegistry)
	#Filter out ground bus and DC bus
	return filter(row -> (row.elecdomain == 1) && row.bus !=0, registry.registry)
end

"""
    dcconnections(registry)

Return all DC connections with a nonzero (nongrounded) bus.
"""
function dcconnections(registry::ConnectionsRegistry)
	return filter(row -> row.elecdomain == 2 && row.bus !=0, registry.registry)
end
"""
    sortedcomponentconnections(registry, component; kwargs...)

Return the connections of `component` sorted by domain, side, and terminal.
"""
sortedcomponentconnections(registry::ConnectionsRegistry, component::Symbol; kwargs...) = sortedcomponentconnections(registry.registry, component; kwargs...)

function sortedcomponentconnections(registry::Table, component::Symbol;withground=false, acfirst=true)
	# Find connections of component
	compconn = filter(row -> row.elem == component, registry)
	# Filter out the ground connections if necessary ()
	groundfilt(row) = row.bus != 0
	if !withground
		filter!(groundfilt, compconn)
	end
	#Sorting depends if we want ac first (elecdomain=1 so first)
	sortfunc(row) = acfirst ? (row.elecdomain, row.side, row.terminal) : (row.side, row.terminal)

	sort!(compconn, by = sortfunc)
	
	return compconn

end





######## Util functions ########
"""
    updateemptyname(conns)

Assign unique names to unnamed connections.
"""
function updateemptyname(conns::Vector{ConnectionDef})
	for i in eachindex(conns)
		if isnothing(conns[i].name)
			conns[i] = ConnectionDef(conns[i].endpoints; name=gensym())
		end
	end
	return conns
end
"""
    mergebyname(conns)

Merge connections that share the same name.
"""
function mergebyname(conns::Tuple{Vararg{ConnectionDef}})
	named = Dict{Symbol, Vector{Pin}}()
	unnamed = ConnectionDef[]
	for c in conns
		if c.name === nothing
			push!(unnamed, c)
		else
			push!(get!(named, c.name, Pin[]), c.endpoints...)
		end
	end
	out = ConnectionDef[]
	for (nm, pins) in named
		push!(out, ConnectionDef(pins; name=nm))
	end
	append!(out, unnamed)
	return out

end
"""
    mergebysharedpin(conns)

Merge connections that share at least one pin.
"""
function mergebysharedpin(conns::Vector{ConnectionDef})
	# union-find via iterative merging
	changed = true
	conns = copy(conns)
	pin_id(p::Pin) = (p.elementid, p.side, p.terminal)
	while changed
		changed = false
		n = length(conns)
		i = 1
		while i <= n
			j = i+1
			while j <= n
				seti = Set(pin_id.(conns[i].endpoints))
				setj = Set(pin_id.(conns[j].endpoints))
				if !isempty(intersect(seti, setj))
					# merge j into i
					allpins = vcat(conns[i].endpoints, conns[j].endpoints)
					# remove duplicate pins
					unique_pins = Dict{Tuple,Pin}()
					for p in allpins
						unique_pins[pin_id(p)] = p
					end
					mergedpins = collect(values(unique_pins))
					# determine name (prefer existing name if any)
					name = conns[i].name === nothing ? conns[j].name : conns[i].name
					conns[i] = ConnectionDef(mergedpins; name=name)
					splice!(conns, j)
					n -= 1
					changed = true
					continue
				end
				j += 1
			end
			i += 1
		end
	end
	return conns
end

pin(element::Symbol, side::Integer, terminal::Integer) =
	Pin(element, Int(side), Int(terminal))

pin(element::Symbol, name) = begin
	side, terminal = parse_pin_name(name)
	Pin(element, side, terminal)
end

"""
Parse a pin name in the form "side.terminal", Symbol 1.1, or a tuple (side, terminal) into a (side, terminal) pair of integers.
"""
function parse_pin_name(name)
	name isa Tuple{<:Integer, <:Integer} && return (Int(name[1]), Int(name[2]))

	parts = split(string(name), ".")
	length(parts) == 2 ||
		throw(
			ArgumentError(
				"Pin name must contain side and terminal in the form side.terminal, got $(repr(name)).",
			),
		)

	all(!isempty(part) for part in parts) ||
		throw(ArgumentError("Pin name cannot contain empty side or terminal: $(repr(name))."))

	try
		side = parse(Int, parts[1])
		terminal = parse(Int, parts[2])
		side > 0 || throw(ArgumentError("Pin side must be >= 1, got $side."))
		terminal > 0 || throw(ArgumentError("Pin terminal must be >= 1, got $terminal."))
		return (side, terminal)
	catch err
		err isa ArgumentError && rethrow()
		throw(
			ArgumentError(
				"Pin name must contain integer side and terminal in the form side.terminal, got $(repr(name)).",
			),
		)
	end
end
"""
Generate a unique pin name based on the element, side, and terminal. The name is in the form "side.terminal", e.g. "1.1" for side 1 terminal 1.
This is the legacy naming convention for pins in PIACDC
"""
pin_name(pin::Pin) = Symbol("$(pin.side).$(pin.terminal)")
pin_name(side::Int, terminal::Int) = Symbol("$(side).$(terminal)")

function Base.getproperty(pin::Pin, field::Symbol)
	field === :name && return pin_name(pin)
	return getfield(pin, field)
end

function Base.propertynames(::Pin, private::Bool = false)
	props = (:element, :side, :terminal, :name)
	return private ? props : props
end

connrowtonwpin(row) = (row.elem, pin_name(row.side, row.terminal))
