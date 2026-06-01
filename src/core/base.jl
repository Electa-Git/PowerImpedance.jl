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

struct LinearizedAdmittance{T<:Number} 
    Y!::FunctionWrapper{Nothing, Tuple{Matrix{T}, ComplexF64}} #inplace modifier
    indices::Matrix{Tuple{Int, Int}} #Indices of the nets in the order of the ports. Tuple (N elments) of Tuple(p ports)
end

# LinearizedAdmittance(
#                      Y!::FunctionWrapper{Nothing, Tuple{Matrix{T}, ComplexF64}},
#                      indices::Matrix{Tuple{Int, Int}}) where {T<:Number} =
#     LinearizedAdmittance{T}(Y, Y!, indices)

#Helper function for wrapping
# fwrap(f,  T::Type{<:Number}) = FunctionWrapper{Matrix{T}, Tuple{ComplexF64}}(f)
fwrap(f, T::Type{<:Number}) = FunctionWrapper{Nothing, Tuple{Matrix{T}, ComplexF64}}(f)

# function LinearizedAdmittance(elem, args...; kwargs...)
#     throw(ArgumentError("LinearizedAdmittance not defined for element type $(typeof(elem))."))
# end


function LinearizedAdmittance(elem::P.Element{<:P.AbstractStateSpace},elemkey, iv_sp, conn, netids)
    
    # Get ABCD => Should be state-space with voltage as input and current as output, in order of side and then terminal.
    A,B,C,D = P.update(elem, iv_sp)

    p = size(B,2) #Nb of ports is the number of columns of B (should be the same as C; cannot trust nb of pins due to legacy implementation of singleports

    Yresp = P.freqresp_cache(A, B, C, D)
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
    Y!(out, s) = copyto!(out, P.get_y(elem, s))
    # Ywrap = fwrap(Y, p, T)
    Y!wrap = fwrap(Y!, T)

   
    return LinearizedAdmittance(Y!wrap, elemkey, conn, netids)

end


function LinearizedAdmittance(Y!::FunctionWrapper{Nothing, Tuple{Matrix{T}, T}}, elemkey::Symbol, conn, netids) where {T<:Number}
    
    # Nets of elements
    elemnets = sortedcomponentconnections(conn, elemkey;withground=true).net #Sorted from AC to DC and with terminal

    # @assert !any(startswith.(string.(elemnets), ("gnd",))) "Element $(elemkey) is connected to ground, cannot linearize active element"

    # Get net ids & indices of the nets in the order of the ports
    netids_elem = [netids[net] for net in elemnets]
    indices = Matrix{Tuple{Int, Int}}([(i, j) for i in netids_elem, j in netids_elem]) #Assuming all ports are connected to different nets. Otherwise, need to check for duplicates and assign same net id to those ports



    return LinearizedAdmittance(Y!, indices)
end

struct LinearizedInterface{E<:NamedTuple, N<:NamedTuple}
    elem::E#Dict{Symbol, @NamedTuple{type::Symbol, id::Int}}
    net::N#@NamedTuple{net::Int}
    groundednets::Vector{Int}
end



"""

Allow for multiple nb of ports inside collection

"""
# const AnyLinearizedAdmittance{T} = LinearizedAdmittance{p, T} where p

struct LinearizedAdmittanceNetwork{T<:Number, E, N}
    passives::Vector{LinearizedAdmittance{T}}
    actives::Vector{LinearizedAdmittance{T}}
    interface::LinearizedInterface{E,N}
end
# "Constructor to handle case where all admittances have same number of ports"
# LinearizedAdmittanceNetwork(passives::AbstractVector{<:AnyLinearizedAdmittance{T}},
#                             actives::AbstractVector{<:AnyLinearizedAdmittance{T}}) where {T<:Number} =
#     LinearizedAdmittanceNetwork{T}(collect(passives), collect(actives))


function LinearizedAdmittanceNetwork(bs::BuilderState, sp)
    
    # Pre-find actives and passives for faster looping

    actives = filter(x-> x isa P.Element{<:P.AbstractStateSpace}, bs.elements)
    passives =  filter(x-> (x isa P.Element{<:P.AbstractMultiport})&& !(P.is_source(x)), bs.elements) #TODO: Update the abstract name for this type
    sources = filter(x-> P.is_source(x), bs.elements)
    actives_adm = Vector{LinearizedAdmittance{ComplexF64}}(undef, length(actives))
    passives_adm = Vector{LinearizedAdmittance{ComplexF64}}(undef, length(passives))
    
    activeslut = NamedTuple{keys(actives)}((type=:actives, id=i) for i in 1:length(actives))
    passiveslut = NamedTuple{keys(passives)}((type=:passives, id=i) for i in 1:length(passives))
    lut = merge(activeslut, passiveslut)

    conn = bs.connections.registry
    nets = unique(conn.net)
    netids = (; (nets .=> [i for i in eachindex(nets)])...) #Assign Int to every net -> index in matrix

    
    for (i,(key,elem)) in enumerate(pairs(actives))
        iv_sp = sp[key]
        actives_adm[i] = LinearizedAdmittance(elem,key,iv_sp, conn, netids)
    end

    for (i,(key,elem)) in enumerate(pairs(passives))
        passives_adm[i] = LinearizedAdmittance(elem,key, conn, netids)
    end

    groundednets = Int[]
    for (key, elem) in pairs(sources)
       nets = filter(row -> row.elem == key, conn).net
       push!(groundednets, [netids[net] for net in nets]...)
    end

    return LinearizedAdmittanceNetwork(passives_adm, actives_adm, LinearizedInterface(lut, netids, groundednets))

end

function get_y(lnw::LinearizedAdmittanceNetwork{T,E, N}, key::Symbol, s::Complex) where {T,E, N}

    (type::Symbol, id::Int) = lnw.interface.elem[key]
    elemadm = getfield(lnw, type)[id]::LinearizedAdmittance
    Yout = Matrix{T}(undef, size(elemadm.indices)...)
    return get_y!(Yout, lnw, key, s)

end

function get_y!(Yout::AbstractMatrix{T}, lnw::LinearizedAdmittanceNetwork{T,E, N}, key::Symbol, s::Complex) where {T,E, N}

    (type, id) = lnw.interface.elem[key]
    elemadm = (getfield(lnw, type)::Vector{LinearizedAdmittance{T}})[id] 
    elemadm.Y!(Yout, s)
    return Yout

end
