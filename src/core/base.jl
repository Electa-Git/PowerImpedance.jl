## Types for results
using FunctionWrappers: FunctionWrapper
using LinearAlgebra
# import Base: length
"""
Stores the p-port admittances of N elements in a given network and where they connect to the network (connections).
- All shunts have the same output dimension. 
- The connection stores the ids of the network connections (Tuple (N elments) of Tuple(p ports) 
- The nb. of ports p is in power system terms the multiplication of busses it connects to and the number of phases
- e.g. Shunt dq-admittances will have 2 ports, Network abc-admittance will be 6 ports


If you want to have a single-phase connection, you can :
1) define a new collection in the network for single-phase elements
2) Modify its admittance to correspond for a 3 phase (no reaction to other phase perturbations)
"""
const AdmFunc{T} = FunctionWrapper{Nothing, Tuple{AbstractArray{T,3}, AbstractVector{<:Complex}}} #Shortened expression

struct LinearizedAdmittanceCollection{T<:Number} 
    Y!::Vector{AdmFunc{T}} #inplace modifier
    indices::Vector{Matrix{Tuple{Int, Int}}} #Indices of the nets in the order of the pins. Cannot be 3D array bcs nb. of pins not the same
end

Base.length(coll::LinearizedAdmittanceCollection) = length(coll.Y!)

# LinearizedAdmittance(
#                      Y!::FunctionWrapper{Nothing, Tuple{Matrix{T}, ComplexF64}},
#                      indices::Matrix{Tuple{Int, Int}}) where {T<:Number} =
#     LinearizedAdmittance{T}(Y, Y!, indices)

#Helper function for wrapping
# fwrap(f,  T::Type{<:Number}) = FunctionWrapper{Matrix{T}, Tuple{ComplexF64}}(f)
fwrap(f, T::Type{<:Number}) = AdmFunc{T}(f)

# function LinearizedAdmittance(elem, args...; kwargs...)
#     throw(ArgumentError("LinearizedAdmittance not defined for element type $(typeof(elem))."))
# end


function LinearizedAdmittance(elem::P.Element{<:P.AbstractStateSpace},elemkey, iv_sp, conn, netids)
    
    # Get ABCD => Should be state-space with voltage as input and current as output, in order of side and then terminal.
    A,B,C,D = P.update(elem, iv_sp)

    p = size(B,2) #Nb of ports is the number of columns of B (should be the same as C; cannot trust nb of pins due to legacy implementation of singleports

    Yresp = P.freqresp_cache(A, B, C, D; scale=P.SI_scale(elem)) #
    # Ywrap = fwrap(Yresp, ComplexF64)
    Y!wrap = fwrap(Yresp, ComplexF64)


    return LinearizedAdmittance(Y!wrap, elemkey, conn, netids)

end

function LinearizedAdmittance(elem::P.Element{<:P.AbstractMultiport}, elemkey, conn, netids)
    # For passive elements, we can directly define the admittance function based on the element type and parameters. No need for state-space representation.
    # This is a placeholder implementation and should be updated based on the actual types of passive elements and their parameters.

    p = length(elem.pins) #Nb of ports is the number of pins
    T = ComplexF64 #TODO: Update with measurement and other uncertainties when time is due

    
    Y(s) = Matrix{T}(P.get_y(elem, s)) #Define the admittance function based on the element type and parameters
    function Y!(out, s)

        @simd for i in eachindex(s)
            outi = @view out[:,:,i]
            copyto!(outi, P.get_y(elem, s[i]))
        end
    end
    # Ywrap = fwrap(Y, p, T)
    Y!wrap = fwrap(Y!, T)

   
    return LinearizedAdmittance(Y!wrap, elemkey, conn, netids)

end


function LinearizedAdmittance(Y!::AdmFunc{T}, elemkey::Symbol, conn, netids) where {T<:Number}
    
    # Nets of elements
    elemnets = sortedcomponentconnections(conn, elemkey;withground=true, acfirst=false).net #Sorted from sides and then terminals (with grounds)

    # @assert !any(startswith.(string.(elemnets), ("gnd",))) "Element $(elemkey) is connected to ground, cannot linearize active element"

    # Get net ids & indices of the nets in the order of the ports
    netids_elem = [netids[net] for net in elemnets]
    indices = Matrix{Tuple{Int, Int}}([(i, j) for i in netids_elem, j in netids_elem]) #Assuming all ports are connected to different nets. Otherwise, need to check for duplicates and assign same net id to those ports



    return Y!, indices
end

struct LinearizedInterface{E<:NamedTuple, N<:NamedTuple}
    elem::E#Dict{Symbol, @NamedTuple{type::Symbol, id::Int}}
    net::N#@NamedTuple{net::Int}
    groundednets::Vector{Int}
    activenets::Vector{Int} # Store the nets of active elements to do kron-reduction on non-active nets
end

Base.show(io::IO, intf::LinearizedInterface) = println(io, 	"\n Grounded nets: $([key for (key,netid) in pairs(intf.net) if netid in intf.groundednets]) \n",
                                                            "Active nets: $([key  for (key,netid) in pairs(intf.net) if netid in intf.activenets])")



"""

Allow for multiple nb of ports inside collection

"""
# const AnyLinearizedAdmittance{T} = LinearizedAdmittance{p, T} where p

struct LinearizedAdmittanceNetwork{T<:Number, E, N}
    passives::LinearizedAdmittanceCollection{T}
    actives::LinearizedAdmittanceCollection{T}
    interface::LinearizedInterface{E,N}
end

Base.show(io::IO, bs::LinearizedAdmittanceNetwork) = (println(io, 	"\n LinearizedAdmittance implemented via BuilderState \n",
													"----------------------------------- \n",
													" Nb. of passives: $(length(bs.passives)) \n",
													" Nb. of actives: $(length(bs.actives)) \n",); show(io, bs.interface))

# "Constructor to handle case where all admittances have same number of ports"
# LinearizedAdmittanceNetwork(passives::AbstractVector{<:AnyLinearizedAdmittance{T}},
#                             actives::AbstractVector{<:AnyLinearizedAdmittance{T}}) where {T<:Number} =
#     LinearizedAdmittanceNetwork{T}(collect(passives), collect(actives))


function LinearizedAdmittanceNetwork(bs::BuilderState, sp)
    
    # Pre-find actives and passives for faster looping

    actives = filter(x-> x isa P.Element{<:P.AbstractStateSpace}, bs.elements)
    passives =  filter(x-> (x isa P.Element{<:P.AbstractMultiport})&& !(P.is_source(x)), bs.elements) #TODO: Update the abstract name for this type
    sources = filter(x-> P.is_source(x), bs.elements)
    actives_adm = Vector{AdmFunc{ComplexF64}}(undef, length(actives))
    passives_adm = Vector{AdmFunc{ComplexF64}}(undef, length(passives))

    actives_ind = Vector{Matrix{Tuple{Int,Int}}}(undef, length(actives))
    passives_ind = Vector{Matrix{Tuple{Int,Int}}}(undef, length(passives))
    
    activeslut = NamedTuple{keys(actives)}((type=:actives, id=i) for i in 1:length(actives))
    passiveslut = NamedTuple{keys(passives)}((type=:passives, id=i) for i in 1:length(passives))
    lut = merge(activeslut, passiveslut)

    conn = bs.connections.registry
    nets = unique(conn.net)
    netids = (; (nets .=> [i for i in eachindex(nets)])...) #Assign Int to every net -> index in matrix

    # Nets with active elements connected to it
    activenets = filter(row->row.elem in keys(actives), conn).net
    activenetids = [netids[net] for net in activenets]
    
    for (i,(key,elem)) in enumerate(pairs(actives))
        iv_sp = sp[key]
        actives_adm[i], actives_ind[i] = LinearizedAdmittance(elem,key,iv_sp, conn, netids)
    end

    for (i,(key,elem)) in enumerate(pairs(passives))
        passives_adm[i], passives_ind[i] = LinearizedAdmittance(elem,key, conn, netids)
    end
    activescoll = LinearizedAdmittanceCollection(actives_adm, actives_ind)

    groundednets = [id for (net,id) in pairs(netids) if occursin("gnd", lowercase(string(net)))]
    for (key, elem) in pairs(sources)
       nets = filter(row -> row.elem == key, conn).net
       push!(groundednets, [netids[net] for net in nets]...)
    end
    passivescoll = LinearizedAdmittanceCollection(passives_adm, passives_ind)


    return LinearizedAdmittanceNetwork(passivescoll, activescoll, LinearizedInterface(lut, netids, groundednets, activenetids))

end

function getelem(lnw::LinearizedAdmittanceNetwork{T,E,N}, key::Symbol) where {T, E, N}
    return lnw.interface.elem[key]
end
function get_elemadm(lnw::LinearizedAdmittanceNetwork{T,E, N}, key::Symbol) where {T,E, N}

    type,id = getelem(lnw,key) 
    return (getfield(lnw, type)::LinearizedAdmittanceCollection{T}).Y![id] 

end

function get_elemind(lnw::LinearizedAdmittanceNetwork{T,E,N}, key::Symbol) where {T, E, N}
    
    type,id = getelem(lnw,key) 
    return (getfield(lnw, type)::LinearizedAdmittanceCollection{T}).indices[id] 
end



function get_y(lnw::LinearizedAdmittanceNetwork{T,E, N}, key::Symbol, s::Vector{<:Complex}) where {T,E, N}
  
    elemind = get_elemind(lnw, key)
    Yout = Array{T,3}(undef, size(elemind)..., length(s))
    return get_y!(Yout, lnw, key, s)

end

function get_y!(Yout::AbstractArray{T,3}, lnw::LinearizedAdmittanceNetwork{T,E, N}, key::Symbol, s::Vector{<:Complex}) where {T,E, N}

  
    Y! = get_elemadm(lnw, key)
    Y!(Yout, s)
    return Yout

end

