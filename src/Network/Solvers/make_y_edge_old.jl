export make_y_edge_old
"""


"""
# Function returns the suitable Yedge matrix for the network, ie. nodes match the Ynode matrix.
# First the general Y matrix of the network is created only considering passive elements.
# Then the nodes where no source is connected are removed via Kron reduction.
function make_y_edge_old(network::Network; nodelist = [], freq_range = (1,1e3, 1000))
    
node_list= Symbol[] #Node list to generate Yedge
element_list= Symbol[] #Element list to generate Yedge

if nodelist == []



        # Create node list for Yedge
        for node in keys(network.nets)

        if occursin("gnd", string(node))
            continue # Skip ground nodes
        end

        # Check whether node is already part of the node list of Yedge
        if in(node, node_list)
            continue # Skip nodes that are already in the list
        end

        # Check whether the current node is part of Yedge

        nets=PowerImpedance.netfor!(network, node) # Get nets (designator, pin) connected to the node


        # Check whether the node is connected to a source
        # If it is, skip the node.
        # This assumes that AC & DC sources are only connected to an impedance 
        # TODO: Make this more general
        isSourceNode= false # Flag to skip the node if it is connected to a source
        for net in nets # Iterate over all elements connected to the node

            element=network.elements[net[1]] # Get the element, via the designator net[1]
            
            if is_source(element) 
                
                isSourceNode = true # Skip the node if it is connected to a source
                break
            end

        end

        if isSourceNode
            continue # Skip the node if it is connected to a source
        end

        isDCnode= false # Flag to check whether the node is a DC node
        isACnode= false # Flag to check whether the node is an AC node

        # Identify DC or AC node by checking the pins connected to node:
        # If DC node: Only one pin for each port, e.g. 1.1, 2.1 etc.
        # If AC node: Two pins for each port, e.g. 1.1, 1.2, 2.1, 2.2 etc.

        # Get the pin of one of the element connected to the node
        pin = string(nets[1][2]) # Get the pin name

        if occursin(".2", pin) # Check whether the pin is a AC pin
            
            isACnode=true # Set the flag to true

        end
        if occursin(".1", pin) 
            
            ACpin=replace(pin, ".1" => ".2") # Replace .1 with .2 to search for the other AC pin if existent

            designator = nets[1][1] # Get the designator of the element
            ACpin=Symbol(ACpin)

            if PowerImpedance.netname(network, (designator,ACpin)) === Symbol("") # Check whether this net (designator, pin) exists
            
                isDCnode= true

            else
                
                isACnode=true
            end

        end


        if isACnode 

            # Get the other AC node
            if occursin(".2", pin)
                ACpin=replace(pin, ".2" => ".1") # Replace .2 with .1 to search for the other AC pin 
            else
                ACpin=replace(pin, ".1" => ".2") # Replace .1 with .2 to search for the other AC pin 

            end

            designator = nets[1][1] # Get the designator of the element
            ACpin=Symbol(ACpin)
            node2=PowerImpedance.netname(network, (designator,ACpin))

            # Proper node ordering required to match 2x2 admittance matrix of elements [ACd, ACq]
            if occursin(".1", string(ACpin)) # Node 2 is a d node


                push!(node_list,node2) # Add the node to the list [ACd, ACq]
                push!(node_list,node)

            else  # Node 2 is a q node

                push!(node_list,node) # Add the node to the list [ACd, ACq]
                push!(node_list,node2)

            end



        end


        isConverternode = false # Flag to check whether the node is a converter node
        if isDCnode
            

            # Check whether the DC node is a MMC node

            for net in nets # Iterate over all elements connected to the node

            element=network.elements[net[1]] # Get the element, via the designator net[1]
            
            if is_converter(element) 
                
                isConverternode=true
                break # Break the loop if a converter node is found

            end

            end

            if isConverternode # Proper node ordering required to match 3x3 admittance matrix of converter [DC, ACd, ACq]

                triplet=Array{Union{Symbol}}(undef,3)
                triplet[1]=node # Add the node to the triplet 
            
                for net in nets # Iterate over all elements connected to the node

                    element=network.elements[net[1]] # Get the element, via the designator net[1]
            

                    if is_converter(element) 
                    
                        for (element_pin,element_node) in element.pins

                            if element_node == node # Check whether the element pin is connected to the current node
                                continue # Skip the current node
                            else # AC node

                                if occursin(".1", string(element_pin)) # Check whether the pin is a d pin
                                    triplet[2]=element_node # Add the other node to the triplet
                                end
                                if occursin(".2", string(element_pin)) # Check whether the pin is a q pin
                                    triplet[3]=element_node # Add the other node to the triplet
                                end

                            end

                        end
                        break

                    end
                end
                # Check whether the AC nodes are already in the node list
                # 
                index = findfirst(p -> p == triplet[2], node_list) 
                if index === nothing # AC nodes are not in the list add the entire triplet :) 
                    push!(node_list, triplet[1])
                    push!(node_list, triplet[2])
                    push!(node_list, triplet[3])
                else # AC nodes are in the list, place the DC node at the correction position
                    
                    insert!(node_list, index, triplet[1]) # Insert the DC node at the correct position
                end

            # If not a converter node, then it is a DC node
            # No restriction regarding ordering
            
            else
            
                # Add the node to the list
                push!(node_list, node)


            end


        end

        end

else

    # If the node list is given, use it
    node_list = nodelist

end


# Create element list for Yedge 
# Elements weed out all active elements, i.e. MMC, sources, SG, TLC
for (designator, element) in network.elements
    isSourceNode=false
    if is_passive(element) # Check whether the element is passive
        
        # Check whether the element is connected to a source and hence not part of Yedge 
        # Then it is part of Ynode!
       
        for (pin,element_node) in element.pins


            if occursin("gnd", string(element_node)) # Skip elements connected to ground
                continue
            end

            for net in netfor!(network,element_node)

                if is_source(network.elements[net[1]])# Get the element, via the designator net[1]
                    
                    isSourceNode=true
                    break # Break the loop if a source is found
                end
            end


        end

        if isSourceNode # Skip elements connected to a source
            continue
        else
            push!(element_list, designator)
        end
    
    end

    # Rid element when part of source :)
end


# Initialize dict to hold the nodes and elements for the admittance matrix
dict= Dict{Symbol, Array{Union{Symbol,Int}}}(:node_list => Symbol[], :element_list => Symbol[])
dict[:node_list]=node_list
dict[:element_list]=element_list



# make frequency range
(min_f, max_f, n_f) = freq_range
if !isa(n_f,Int)
    n_f = parse(Int, n_f) #Make Int to work with range (error when 1e4)
end
omegas= 2*pi* 10 .^range(log10(min_f), log10(max_f), length= n_f) 




Yedge=[] # Preallocate the admittance matrix for each frequency

for omega in omegas

    # Get the admittance matrix of the passives for the current frequency
    Y = make_y(network, dict, omega*1im)
    push!(Yedge,Y)

end

# The returned Yedge contains all the buses of the network
# In order to match Ynode, the buses where no source is connected need to be removed
# This is done with Kron reduction

# First get the source nodes
source_nodes= Symbol[] # List to hold the source nodes, to be kept in Yedge

# Implement here the new code from make_y_node to get the source nodes

# Apply Kron reduction to Yedge for each frequency








# Return Yedge and the node list
return Yedge, node_list

end