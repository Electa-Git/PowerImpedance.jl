export make_y_node



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
                                node2=PowerImpedanceACDC.netname(network, (designator,ACpin)) # ACq
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
                                node2=PowerImpedanceACDC.netname(network, (designator,ACpin)) # ACd
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
                                            node2_2=PowerImpedanceACDC.netname(network, (designator2,ACpin)) # ACq
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
                                            node2_1=PowerImpedanceACDC.netname(network, (designator2,ACpin)) # ACd
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
                    triplet=Array{Union{Symbol}}(undef,3) # [DC, ACd, ACq]
                    for (pin,node) in element.pins


                        if occursin(".2", string(pin)) # Check whether the pin is a AC pin
                            
                            triplet[3]=node 

                        end


                        if occursin(".1", string(pin)) 
                            
                            ACpin=replace(string(pin), ".1" => ".2") # Replace .1 with .2 to search for the other AC pin if existent


                            ACpin=Symbol(ACpin)

                            if PowerImpedanceACDC.netname(network, (designator,ACpin)) === Symbol("") # Check whether this net (designator, pin) exists
                            
                                triplet[1]=node
                            else
                                triplet[2]=node
                            end

                        end


                    end
                    # Double-check whether DC source is connected to DC node
                    for (designator2,pin) in netfor!(network,triplet[1])

                        if is_source(network.elements[designator2])
                            triplet[1]=Symbol("") # No DC node needed
                        end


                    end

                    # Check whether the AC nodes are already in the node list
                    # TODO: Generalize for DC source as well
                    index = findfirst(p -> p == triplet[2], node_list) 
                    if index === nothing # AC nodes are not in the list add the entire triplet :) 
                        triplet[1]!=Symbol("") && push!(node_list, triplet[1]) # If DC node is not needed
                        push!(node_list, triplet[2])
                        push!(node_list, triplet[3])
                    else # AC nodes are in the list, place the DC node at the correction position
                        
                        triplet[1]!=Symbol("") && insert!(node_list, index, triplet[1]) # Insert the DC node at the correct position (when DC node needed)
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