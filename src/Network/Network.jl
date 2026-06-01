# Main network definition

export Network, add!, connect!, disconnect!, @network,
        composite_element, eval_abcd
export power_flow, data, result  # for testing

import Base: delete!

const Net = Vector{Tuple{Symbol,Symbol}} # pairs of element designator and pin name

"""

struct Network
    elements::OrderedDict{Symbol, Element}
    nets :: Dict{Symbol, Net}
    connections :: Dict{Symbol, Net}
    Network() = new(OrderedDict{Symbol, Element}(), Dict{Symbol, Net}(), Dict{Symbol, Vector{Int}}())
end

"""
struct Network
    elements::OrderedDict{Symbol, Element}
    nets :: Dict{Symbol, Net}
    bus :: Dict{Symbol, Net}
    voltageBase :: Array{Float64,1} # Network line-ground RMS voltage base used in the power flow. This is necessary to get a matching power flow result in the presence of voltage controlling converters.
    Network() = new(OrderedDict{Symbol, Element}(), Dict{Symbol, Net}(), Dict{Symbol, Vector{Int}}(), [220/sqrt(3)])
end

########################################################################################################################################################################################
# add and delete function with various methods to handle -----------------> elements
"""
    add!(n::Network, elem::Element)
Adds the element `elem` to the network `n`, creating and returning a new, unique
reference designator, leaving its pins unconnected. #FP: It will be connected with the pin connection at the end of the code (usually at the end)
Returns the element designator, if the element `elem` is already connected to the network `n`.
"""
function add!(n::Network, elem::Element)
    for (k, v) in n.elements 
        if v == elem
            return k
        end
    end
    designator = gensym() #gensym-> generates a symbol that will not conflict with the other variable names
    add!(n, designator, elem) #add the element elem to the network n, with the reference designator: designator
    return designator
end

add!(n::Network, elems::Element...) = ((add!(n, elem) for elem in elems)...,)

"""
    add!(n::Network, designator::Symbol, elem::Element)
Adds the element `elem` to the network `n` with the reference designator
`designator`, leaving its pins unconnected. If the network already contained
an element named `designator`, it is removed first.
"""
function add!(n::Network, designator::Symbol, elem::Element)

    
    if haskey(n.elements, designator) #haskey -> determine whether a collection (n.elements) has a mapping for a given key (designator)
        delete!(n, designator) #delete the element named designator from the network n (disconnecting all its pins)
    end
    
    # Only add the element if connection is true
    # TODO: Future improvement: add element to the elements dict, but not to the nets dict
    # This will allow to keep track of all elements in the network, even if they are not connected
    # Important to check compatibility with the rest of the codebase, espec. make_z, determining_impedance, make_y_node etc.
    if elem.connection == true

        for pin in keys(elem.pins) #Grabs the pins of the element and add the resulting net (designator, pin) to the network "n"
            add!(n, (designator, pin))
        end
        
        add!(elem, :symbol, designator)
        n.elements[designator] = elem
    # Do not add the element to the network if connection is false
    elseif elem.connection == false
        
        @info "Element $(designator) not added to the network as connection=false."
    end

end

#################################################################################################################################################################################
# add and delete function with various methods to handle --------------------------> nets 
"""
    add!(n::Network, pin::Tuple{Symbol, Symbol})
Adds the net `pin` to the nets in `n.nets` with a generic name.
Pin is a net, ie. pin::Tuple{designator, pin}.
"""
function add!(n::Network, pin::Tuple{Symbol, Symbol})
    for (name, elem_pins) in n.nets
        if (pin in elem_pins)
            return
        end
    end
    n.nets[gensym()] = [pin]
end
add!(n::Network, p::Tuple{Symbol,Any}) = add!(n, (p[1], Symbol(p[2])))
"""
    add!(n::Network, name::Symbol, pins::Union{Tuple{Symbol,Any}}...)
Adds the nets in `pins` to the nets in `n.nets` with the key/node name 
`name`
"""
function add!(n::Network, name::Symbol, pins::Union{Tuple{Symbol,Any}}...)
    n.nets[name] = []
    for pin in pins
        append!(n.nets[name], pin)
    end
end

"""
    delete!(n::Network, designator::Symbol)
Deletes the element named `designator` from the network `n` (disconnecting all
its pins).
"""
function delete!(n::Network, designator::Symbol)
    for (sym,net) in n.nets
        filter!(elempin -> elempin[1] != designator, net)
    end
    delete!(n.elements, designator)
end
"""
    netfor!(n::Network, p::Tuple{Symbol,Symbol})
Returns the net `p` if it is an element of the network nets `n.nets`
If not, throws an error.
"""
# Return the matching net in n "net" for the input net "p"
function netfor!(n::Network, p::Tuple{Symbol,Symbol})
    for (name, net) in n.nets
        p ∈ net && return net
    end
    throw(ArgumentError("Unknown pin $p"))
end
netfor!(n::Network, p::Tuple{Symbol,Any}) = netfor!(n, (p[1], Symbol(p[2])))
"""
    netfor!(n::Network, name::Symbol) 
Returns the nets `p` for the key `name` in `n.nets`.
Create a new entry in n.nets if key doesnt yet exist in `n.nets`
"""
function netfor!(n::Network, name::Symbol) 
    if !haskey(n.nets, name)
        n.nets[name] = [] # Create new node if it does not exist!
    end
    n.nets[name]
end
"""
    netname(n::Network, name::Symbol)
Checks whether key `name` is in the network `n` nets, `n.nets`.
Throws an expection if not existent
"""
function netname(n::Network, name::Symbol)
    if haskey(n.nets, name)
        return name
    else
        throw(ArgumentError("Unknown net name $name."))
    end
end
"""
    netname(n::Network, pin::Tuple{Symbol,Symbol})
Returns the key/node name `name` of the net `pin`.
Throws an expection if `pin` is not element of `n.nets`
"""
function netname(n::Network, pin::Tuple{Symbol,Symbol})
    for (name, pins) in n.nets
        pin ∈ pins && return name
    end
    #throw(ArgumentError("Unknown pin $pin."))
    return Symbol()
end
netname(n::Network, pin::Tuple{Symbol, Any}) = netname(n, Tuple(pin[1], Symbol(pin[2])))

function netname(n::Network, pins::Union{Symbol,Tuple{Symbol, Symbol}}...)
    for (name, net_pins) in n.nets
        all((isa(pin, Symbol) && (pin == name)) || (pin ∈ net_pins) for pin ∈ pins) && return name
    end
    throw(ArgumentError("Unknown net connected to pins $pins."))
    return Symbol()
end
"""
    netname(n::Network, pins::Array{Tuple{Symbol, Symbol}})
Returns the key/node names `name` of the nets `pins`.
"""
function netname(n::Network, pins::Array{Tuple{Symbol, Symbol}})
    for (name, net_pins) in n.nets
        all((pin ∈ net_pins) for pin ∈ pins) &&
            length(pins) > 0 && return name
    end
    return Symbol()
end

"""
    connect!(n::Network)
Connects all elements' pins with their node names.
"""
function connect!(n::Network)
    for net in keys(n.nets)
        for pin in n.nets[net]
            n.elements[pin[1]].pins[pin[2]] = net
        end
    end
end



@doc doc"""
    connect!(n::Network, pins::Union{Symbol,Tuple{Symbol,Any}}...)
Connects the given pins (or named nets) to each other in the network `n`. Named
nets are given as `Symbol`s, pins are given as `Tuple{Symbols,Any}`s, where the
first entry is the reference designator of an element in `c`, and the second
entry is the pin name. For convenience, the latter is automatically converted to
a `Symbol` as needed.
# Example

"""
function connect!(n::Network, pins::Union{Symbol,Tuple{Symbol,Any}}...)
    nets = []
    
    # Filter out nets of elements that are not in the element dict of the network
    # Element dict of the network is initialized when adding elements to the network
    filtered_pins=[]
    for pin in pins

        if isa(pin,Tuple{Symbol,Any})
            if haskey(n.elements, pin[1])
                
                push!(filtered_pins, pin)

            end
        else
            push!(filtered_pins, pin)

        end

    end

    pins=Tuple(filtered_pins)

    for net in unique([netfor!(n, pin) for pin in pins])
        #println(net)
        append!(nets, net)
        delete!(n.nets, netname(n, net))
    end

    # add pins to named net
    if any(isa(pin, Symbol) for pin in pins)
        n.nets[filter(p -> isa(p, Symbol), collect(pins))[]] = nets
    else
        add!(n, nets[1])
        n.nets[netname(n, nets[1])] = nets
    end
end

"""
    disconnect!(n::Network, p::Tuple{Symbol,Symbol})
Disconnects the given pin `p` from anything else in the network `n`. The pin is
given as a `Tuple{Symbols,Any}`, where the first entry is the reference
designator of an element in `n`, and the second entry is the pin name. For
convenience, the latter is automatically converted to a `Symbol` as needed. Note
that if e.g. three pin `p1`, `p2`, and `p3` are connected then
`disconnect!(n, p1)` will disconnect `p1` from `p2` and `p3`, but leave `p2` and
`p3` connected to each other.
"""
function disconnect!(n::Network, pin::Tuple{Symbol,Symbol})
    net = netfor!(n, pin)
    filter!(p -> p != pin, net)

    push!(n.nets, [pin])
end
disconnect!(n::Network, p::Tuple{Symbol,Any}) = disconnect!(n, (p[1], Symbol(p[2])))

"""
    check_lumped_elements(net :: Network)
Checks if pins of all elements are connected.
"""
function check_lumped_elements(net :: Network)
    for (sym, elements) in net.nets
        if occursin("gnd", string(sym))
            continue
        else
            if length(elements) == 1
                (s, p) = elements[1]
                throw(ArgumentError("Element $s has lumped pin $p."))
            end
        end
    end
end


#####################################################################################################################################################################################
# Network macro

@doc doc"""
    @network begin #= ... =# end
Provides a simple domain-specific language to decribe networks. The
`begin`/`end` block can hold element definitions of the form
`refdes = elementfunc(params)` and connection specifications of the form
`refdes1[pin1] ⟷ refdes2[pin2]`.
# Example
To create a network with a voltage source connected to a resistor:


Alternatively, connection specifications can be given after an element
specification, separated by commas. In that case, the `refdes` may be omitted,
defaulting to the current element.
# Example

Finally, a connection endpoint may simply be of the form `netname`, to connect
to a named net. (Such named nets are created as needed.)
# Example

If a net or pin specification is not just a single symbol or number, and has to
be put in quotes (e.g. `"in+"`, `"9V"`)
!!! note
    Instead of `⟷` (`\\longleftrightarrow`), one can also use `==`.
"""
macro network(cdef)
    is_conn_spec(expr::Expr) =
        (expr.head === :call && (expr.args[1] === :(⟷) || expr.args[1] === :(↔) || expr.args[1] === :(==))) ||
        (expr.head === :comparison && all(c -> c === :(==), expr.args[2:2:end]))
    is_conn_spec(::Any) = false

    function elem_spec(expr)
        if !isa(expr, Expr) || expr.head !== :(=)
            error("invalid element specification$locinfo: $(expr)")
        end
        if !isa(expr.args[1], Symbol)
            error("invalid element identifier$locinfo: $(expr.args[1])")
        end
        if isa(expr.args[2], Expr) && expr.args[2].head === :tuple
            if isempty(expr.args[2].args)
                error("invalid element specification$locinfo: $(expr.args[2])")
            end
            elemspec = expr.args[2].args[1]
            conn_exprs = expr.args[2].args[2:end]
        else
            if expr.args[1] == :voltageBase
                push!(ccode.args, :(network.voltageBase[1] = $(esc(expr.args[2]))))
                return #TODO: Such ugly code
            end
            elemspec = expr.args[2]
            conn_exprs = []
        end
        push!(ccode.args, :(add!(network, $(QuoteNode(expr.args[1])), $(esc(elemspec)))))
        for conn_expr in conn_exprs
            if !is_conn_spec(conn_expr)
                error("invalid connection specification$locinfo: $conn_expr")
            end
            push!(ccode.args, Expr(:call, :connect!, :network, extractpins(conn_expr, expr.args[1])...))
        end
    end

    function extractpins(expr::Expr, default_element=nothing)
        if expr.head === :call && (expr.args[1] === :(⟷) || expr.args[1] === :(↔) || expr.args[1] === :(==))
            return vcat((extractpins(a, default_element) for a in expr.args[2:end])...)
        elseif expr.head === :comparison && all(c -> c === :(==), expr.args[2:2:end])
            return vcat((extractpins(a, default_element) for a in expr.args[1:2:end])...)
        elseif expr.head === :ref
            return [:(($(QuoteNode(expr.args[1])), $(QuoteNode(expr.args[2]))))]
        elseif expr.head === :vect && length(expr.args) == 1
            if default_element === nothing
                error("missing element$(locinfo): $expr")
            end
            return [:(($(QuoteNode(default_element)), $(QuoteNode(expr.args[1]))))]
        else
            error("invalid pin specification$(locinfo): $expr")
        end
    end

    function extractpins(netname::Symbol, default_element=nothing)
        return [QuoteNode(netname)]
    end

    extractpins(netname::String, default_element=nothing) =
        extractpins(Symbol(netname), default_element)

    if !isa(cdef, Expr) || cdef.head !== :block
        error("@network must be followed by a begin/end block")
    end
    ccode = Expr(:block)
    push!(ccode.args, :(network = Network()))
    locinfo = ""
    for expr in cdef.args
        if isa(expr, LineNumberNode)
            locinfo = " at $(expr.file):$(expr.line)"
            continue
        end
        if !isa(expr, Expr)
            error("invalid statement in network definition$locinfo: $expr")
        end
        if expr.head === :line
            locinfo = " at $(expr.args[2]):$(expr.args[1])"
        elseif expr.head === :(=)
            elem_spec(expr)
        elseif is_conn_spec(expr)
            push!(ccode.args, Expr(:call, :connect!, :network, extractpins(expr)...))
        else 
            error("invalid statement in network definition$locinfo: $expr")
        end
    end

    # here you can add functions for network before the end of the code
    push!(ccode.args, :(check_lumped_elements(network)))
    push!(ccode.args, :(connect!(network)))
    push!(ccode.args, :(power_flow(network)))
    push!(ccode.args, :(network))
    return ccode
end

#################################################################################################################################################################################
# Additional functions

@doc doc"""
    function composite_element(subnet::Network, input_pins::Array{Any}, output_pins::Array{Any})
Create a net element from the (sub-)network `net`. The `input_pins` and `output_pin`
define input and output nodes of the element.
# Example

"""
function composite_element(subnet::Network, input_pins::Array{Any}, output_pins::Array{Any})
    element = Element(input_pins = length(input_pins), output_pins = length(output_pins),
            element_value = subnet)
    for i in 1:length(input_pins)
        name = netname(subnet, input_pins[i])
        subnet.connections[Symbol("1.",i)] = subnet.nets[name]
        element.pins[Symbol("1.",i)] = name
    end
    for i in 1:length(output_pins)
        name = netname(subnet, output_pins[i])
        subnet.connections[Symbol("2.",i)] = subnet.nets[name]
        element.pins[Symbol("2.",i)] = name
    end

    return element
end


function eval_abcd(subnet :: Network, s :: Complex)
    start_pins = Symbol[]
    end_pins = Symbol[]
    dict = Dict{Symbol, Array{Union{Symbol,Int}}}(:node_list => Symbol[], :element_list => Symbol[],
        :output_list => Symbol[])
    dict[:element_list] = [elem_symbol for elem_symbol in keys(subnet.elements)]
    for (key, val) in subnet.connections
        if occursin("2.", string(key))
            push!(dict[:output_list], netname(subnet, val))
            push!(end_pins, netname(subnet, val))
        else
            push!(start_pins, netname(subnet, val))
        end

    end
    dict[:node_list] = setdiff([node_symbol for node_symbol in keys(subnet.nets)], vcat(start_pins, end_pins))
    dict[:node_list] = vcat(start_pins, dict[:node_list])

    make_abcd(subnet, dict, start_pins, end_pins, s)
end
