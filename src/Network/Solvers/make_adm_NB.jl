### This file contains the solvers based on the LinearizedAdmittance representation of the network. It includes the functions to build the admittance matrix of the network and to solve for the voltages and currents in the network.

make_y_node(lanw::LinearizedAdmittanceNetwork, s::AbstractVector{<:Complex}) = make_y(lanw, lanw.actives, s)
make_y_edge(lanw::LinearizedAdmittanceNetwork, s::AbstractVector{<:Complex}) = make_y(lanw, lanw.passives, s)


### Input nodes and output nodes as input arguments. Then can be used for determine impedance
function make_y(lanw::LinearizedAdmittanceNetwork, elemidvec::Vector{Int}, s::AbstractVector{<:Complex}, netidvec::AbstractVector{Int}=lanw.activenets) 

    Y = initY(lanw,s) #Zeroes of size nets
    

    consideredadm = getindex(lanw.admittances, elemidvec)
    # Add active device admittances
    fill!(Y, consideredadm, s)

    # Eliminate grounded nodes & update indices of active nets (will be shifted due to elimination)
    Yred, newnetidvec = eliminategrounds(Y, lanw,netidvec)

    # Kron reduction
    
    N = length(newnetidvec)
    Yfinal = Array{ComplexF64,3}(undef, N,N,length(s))

    for i in eachindex(s)
        Yfinal[:,:,i] = P.kron(@view(Yred[:,:,i]), newnetidvec)
    end

    return Yfinal
end


function Base.fill!(Y::Array{ComplexF64, 3}, admcoll::LinearizedAdmittanceCollection{ComplexF64}, s :: AbstractVector{<:Complex})
    
    #Y array of size (N, N, length(s)) where N is the number of nodes in the network
    # Allocate matrix to store temporary results (inplace operation)
    maxsize = maximum(size.(admcoll.indices))
    Ytemp = zeros(ComplexF64, maxsize..., length(s)) # Size should be sufficient to hold the largest admittance matrix in admvec

    any(iszero,Y) || (Y .= complex(0)) # Initialize Y to zero. (Checking = 100ns, assignment=30ms) -> only when necessary
    Y!vec = admcoll.Y!
    indicvec = admcoll.indices

    for i in eachindex(Y!vec)
        # Ytemp .= complex(0) # Reset Ytemp for the next admittance -> Not necessary, Ytemp gets overwritten by D inside Y!
        Y! = Y!vec[i]
        indici = indicvec[i]
        # admsize = size(indici)
        Ytempi = @view(Ytemp[axes(indici,1), axes(indici,2), :])
        Y!(Ytempi, s) # Fill Ytemp with the admittance values for this element
        # Now add Ytempi to the correct location in Y based on adm.indices
        #TODO: Try out with @simd if increased speed (probably not, bcs clear to compiler)
        for (I, place) in pairs(indicvec[i])
            for j in eachindex(s) 
                Y[place[1], place[2], j] += Ytempi[I,j]
            end   
        end
    end
   
end

function initY(lanw::LinearizedAdmittanceNetwork, s::AbstractVector)
    N = maximum(values(lanw.interface.net)) #Max Net ID is size of initial matrix
    return Array{ComplexF64, 3}(zeros(N,N, length(s)))
end

function eliminategrounds(Y::Array{ComplexF64,3}, lanw::LinearizedAdmittanceNetwork, netidvec::Vector{Int})
    groundnets = lanw.groundednets
    keep = setdiff(axes(Y,1), groundnets)

    newnetidvec = setdiff(netidvec, groundnets)
    newnetidvec == netidvec || @info("Some input nets are grounded.")
    newnetidvec = [findfirst(isequal(net), keep) for net in newnetidvec] # Find the index of each net in the new keep -> new index in matrix

    return Y[keep, keep, :], newnetidvec #Only non-grounded nodes are kept
end

