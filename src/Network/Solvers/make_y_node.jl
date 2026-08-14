export make_y_node

function _node_from_pin(network::Network, designator::Symbol, pin::Symbol)
    return PowerImpedance.netname(network, (designator, pin))
end

function _converter_nodes_in_order(network::Network, designator::Symbol, element::Element)

    # Monopolar converter ordering: [dc, d, q]
    return Symbol[
        _node_from_pin(network, designator, Symbol("1.1")),
        _node_from_pin(network, designator, Symbol("2.1")),
        _node_from_pin(network, designator, Symbol("2.2")),
    ]
end

function _is_source_connected_node(network::Network, node::Symbol; exclude::Symbol = Symbol(""))
    node == Symbol("") && return false
    for (designator, _) in netfor!(network, node)
        designator == exclude && continue
        if is_source(network.elements[designator])
            return true
        end
    end
    return false
end

function make_y_node(network::Network; nodelist = [], freq_range = (1,1e3, 1000))


node_list= Symbol[] #Node list to generate Ynode
element_list= Symbol[] #Element list to generate Ynode

# 1. Node list creation
# Here we only include nodes which are connected to active elements: converters, SGs, sources.
# For sources, we include the grid-side nodes of the connected passive elements
if nodelist == []

    for (designator,element) in network.elements
        


            # Check whether element is an active element: converter, SG, source
            if is_passive(element) 
                continue # Skip passives 
            end
            if is_source(element) || is_converter(element) || is_generator(element)

                if is_generator(element)

                    for (pin,node) in element.pins

                        if occursin("gnd", string(node))
                            continue # Skip ground nodes
                        else # AC node either ACd or ACq
                        
                            if occursin(".1", string(pin)) # ACd

                                ACpin=replace(string(pin), ".1" => ".2") # Replace .1 with .2 to search for the other AC node 
                                ACpin=Symbol(ACpin)
                                node2=PowerImpedance.netname(network, (designator,ACpin)) # ACq
                                # Add the nodes to the list [ACd, ACq]
                                if !in(node, node_list)
                                        push!(node_list,node) 
                                end
                                if !in(node2, node_list)
                                        push!(node_list,node2) 
                                end

                            end
                            if occursin(".2", string(pin)) # ACq

                                ACpin=replace(string(pin), ".2" => ".1") # Replace .2 with .1 to search for the other AC node 
                                ACpin=Symbol(ACpin)
                                node2=PowerImpedance.netname(network, (designator,ACpin)) # ACd
                                # Add the nodes to the list [ACd, ACq]
                                if !in(node2, node_list)
                                        push!(node_list,node2) 
                                end
                                if !in(node, node_list)
                                        push!(node_list,node) 
                                end 

                            end


                        end

                    end

                end
                if is_source(element) && element.input_pins > 1 # AC source, DC source will be skipped --> DC bus not part of Ynode
                #TODO: Generalize for DC source as well

                    source_nodes=[] # Temporary list to store source nodes: nodes without ground
                    for (pin,node) in element.pins
                        

                        if occursin("gnd", string(node))
                            continue # Skip ground nodes
                        
                        else
                            push!(source_nodes, node) # Store source nodes temporaril

                        end

                    end

                    for node in source_nodes # These are the nodes where an element is connected to the source

                        for net in netfor!(network,node)

                            designator2=net[1]

                            if designator2 == designator # Source itself
                                continue
                            else


                                for (pin2,node2) in network.elements[designator2].pins

                                    if !in(node2, source_nodes) # Node can be added


                                        if occursin(".1", string(pin2)) # ACd

                                            ACpin=replace(string(pin2), ".1" => ".2") # Replace .1 with .2 to search for the other AC node 
                                            ACpin=Symbol(ACpin)
                                            node2_2=PowerImpedance.netname(network, (designator2,ACpin)) # ACq
                                            # Add the nodes to the list [ACd, ACq]
                                            if !in(node2, node_list)
                                                    push!(node_list,node2) 
                                            end
                                            if !in(node2_2, node_list)
                                                    push!(node_list,node2_2) 
                                            end

                                        end


                                        if occursin(".2", string(pin2)) # ACq

                                            ACpin=replace(string(pin2), ".2" => ".1") # Replace .2 with .1 to search for the other AC node 
                                            ACpin=Symbol(ACpin)
                                            node2_1=PowerImpedance.netname(network, (designator2,ACpin)) # ACd
                                            # Add the nodes to the list [ACd, ACq]
                                        if !in(node2_1, node_list)
                                                push!(node_list,node2_1) 
                                        end
                                        if !in(node2, node_list)
                                                push!(node_list,node2) 
                                        end 

                                        end

                                    end

                                end
                            end
                        end
                    end

                end
                if is_converter(element)
                    ordered_nodes = _converter_nodes_in_order(network, designator, element)
                    dc_nodes = collect(ordered_nodes[1:1]) # [dc]
                    ac_nodes = collect(ordered_nodes[2:3]) # [d, q]

                    dc_nodes = [
                        node for node in dc_nodes
                        if node != Symbol("") &&
                           !_is_source_connected_node(network, node; exclude = designator)
                    ]
                    ac_nodes = [node for node in ac_nodes if node != Symbol("")]
                    isempty(ac_nodes) && continue

                    ac_index = nothing
                    for ac_node in ac_nodes
                        idx = findfirst(==(ac_node), node_list)
                        if idx !== nothing
                            ac_index = idx
                            break
                        end
                    end

                    if ac_index === nothing
                        for dc_node in dc_nodes
                            dc_node ∉ node_list && push!(node_list, dc_node)
                        end
                        for ac_node in ac_nodes
                            ac_node ∉ node_list && push!(node_list, ac_node)
                        end
                    else
                        insert_idx = ac_index
                        for dc_node in dc_nodes
                            if dc_node ∉ node_list
                                insert!(node_list, insert_idx, dc_node)
                                insert_idx += 1
                            end
                        end
                        for ac_node in ac_nodes
                            ac_node ∉ node_list && push!(node_list, ac_node)
                        end
                    end
                end




            end


    end


else

    # If the node list is given, use it
    node_list = nodelist

end

# 2. Element list creation
# Iterate over all active elements in the network
# Skip sources but include the connected source impedance!
# TODO: Warning if not source connected to single element!

for (designator, element) in network.elements

    if is_passive(element) 
        continue # Skip passives 
    end

    # If not passive then SG, converter or source
    # If source, add passives (everything that is connected to the source to the element list)
    # This assumes that the elements connected to the source are connected together at the same node (grid connection point)
    # If the connected element is a converter, such in case of an ideal DC source, do not add it to the list
    if is_source(element) 
        for (pin,element_node) in element.pins # Search for the impedance 

            if occursin("gnd", string(element_node)) # Skip elements connected to ground
                continue
            end

            for net in netfor!(network,element_node)

                designator=net[1]
                if designator == element.symbol # Source itself
                    continue
                else
                    if !in(designator, element_list)

                        if is_passive(network.elements[designator] ) # Only add to the element list when it is a passive element
                            push!(element_list, designator) # Add the source to the list
                        end

                    end

                end
            end

        end

        
    else # Converters, SGs


        push!(element_list, designator) # Add the element to the list

    end


   
   

end

# Initialize dict to hold the nodes and elements for the admittance matrix
dict= Dict{Symbol, Array{Union{Symbol,Int}}}(:node_list => Symbol[], :element_list => Symbol[])
dict[:node_list]=node_list
dict[:element_list]=element_list


(min_f, max_f, n_f) = freq_range
if !isa(n_f,Int)
    n_f = parse(Int, n_f) #Make Int to work with range (error when 1e4)
end
omegas= 2*pi* 10 .^range(log10(min_f), log10(max_f), length= n_f) 




Ynode=[] # Preallocate the admittance matrix for each frequency

for omega in omegas

    Y = make_y(network, dict, omega*1im)
    push!(Ynode,Y)


end

return Ynode,node_list,omegas


end
