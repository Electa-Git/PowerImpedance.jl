export make_y_edge

function make_y_edge(network::Network; nodelist = [], freq_range = (1,1e3, 1000))

node_list= Symbol[] #Node list to generate passive Y matrix
element_list= Symbol[] #Element list generate passive Y matrix

# 1. Create node list for passive Y matrix
for node in keys(network.nets)

        if occursin("gnd", string(node))
            continue # Skip ground nodes
        end
        # All nodes need to be included in passive Y matrix, except when it is an internal source node

        nets=PowerImpedance.netfor!(network, node) # Get nets (designator, pin) connected to the node


        # Check whether the node is connected to a source
        # If it is, skip the node since it is an "internal" source node.
        isSourceNode= false # Flag to skip the node if it is connected to a source
        for net in nets # Iterate over all elements connected to the node

            element=network.elements[net[1]] # Get the element, via the designator net[1]
            
            if PowerImpedance.is_source(element)
                
                isSourceNode = true # Skip the node if it is connected to a source
                break
            end

        end

        if isSourceNode
            continue # Skip the node if it is connected to a source
        end
        


        if !in(node, node_list)
        push!(node_list,node) 
        end



end

# 2.Create element list for passive Y matrix
# Elements weed out all active elements, i.e. MMC, sources, SG, TLC
for (designator, element) in network.elements
    isSourceNode=false
    if PowerImpedance.is_passive(element) # Check whether the element is passive
        
        # Check whether the element is connected to a source and hence not part Y matrix
       
        for (pin,element_node) in element.pins


            if occursin("gnd", string(element_node)) # Skip elements connected to ground
                continue
            end

            for net in PowerImpedance.netfor!(network,element_node)

                if PowerImpedance.is_source(network.elements[net[1]])# Get the element, via the designator net[1]
                    
                    isSourceNode=true
                    break # Break the loop if a source is found
                end
            end


        end

        if isSourceNode # Skip elements connected to a source
            continue
        else

            if !in(designator, element_list)
                push!(element_list, designator)
            end
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

Ymatrix=[] # Preallocate the admittance matrix for each frequency

for omega in omegas

    # Get the admittance matrix of the passives for the current frequency
    Y = PowerImpedance.make_y(network, dict, omega*1im)
    push!(Ymatrix,Y)

end

# Reodering of the Ymatrix to match the nodelist from the make_y_node function

for (i,node) in enumerate(nodelist)

    j=findfirst(==(node),node_list)
    
    # Swapping nodes in the nodelist


    node1=node_list[j]
    node2=node_list[i]

    node_list[i]=node1
    node_list[j]=node2
    
    for k in eachindex(Ymatrix)
        
        # columns
        clm2=Ymatrix[k][:,i] 
        clm1=Ymatrix[k][:,j]
        
        # Swap columns
        Ymatrix[k][:,i]=clm1
        Ymatrix[k][:,j]=clm2


        row2=Ymatrix[k][i,:]
        row1=Ymatrix[k][j,:]

        # Swap rows
        Ymatrix[k][i,:]=row1
        Ymatrix[k][j,:]=row2



    end


end

#Apply Kron reduction eliminate the non-source nodes of Ymatrix to get Yedge
Yedge=[]
no_elim = [i for i in 1:length(nodelist)]
for i in eachindex(Ymatrix)

    push!(Yedge,PowerImpedance.kron(Ymatrix[i],no_elim))

end

node_list=node_list[1:length(nodelist)]

return Yedge, node_list, omegas




end
