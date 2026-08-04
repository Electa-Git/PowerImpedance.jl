## Types for results
using FunctionWrappers: FunctionWrapper
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

Base.getindex(coll::LinearizedAdmittanceCollection, id) = LinearizedAdmittanceCollection(getindex(coll.Y!, collect(id)), getindex(coll.indices, collect(id)))

Base.length(coll::LinearizedAdmittanceCollection) = length(coll.Y!)

# LinearizedAdmittance(
#                      Y!::FunctionWrapper{Nothing, Tuple{Matrix{T}, ComplexF64}},
#                      indices::Matrix{Tuple{Int, Int}}) where {T<:Number} =
#     LinearizedAdmittance{T}(Y, Y!, indices)
2
#Helper function for wrapping
# fwrap(f,  T::Type{<:Number}) = FunctionWrapper{Matrix{T}, Tuple{ComplexF64}}(f)
fwrap(f, T::Type{<:Number}) = AdmFunc{T}(f)

# function LinearizedAdmittance(elem, args...; kwargs...)
#     throw(ArgumentError("LinearizedAdmittance not defined for element type $(typeof(elem))."))
# end


function build(elem::P.Element, iv_sp)
    
    if P.is_statespace(elem)
        # Get ABCD => Should be state-space with voltage as input and current as output, in order of side and then terminal.
        A,B,C,D = P.update(elem, iv_sp)
        Y! = P.freqresp_cache(A, B, C, D; scale=P.SI_scale(elem)) #
    elseif P.is_linfreqdomain(elem)
        
        Y(s) = Matrix{T}(P.get_y(elem, s)) #Define the admittance function based on the element type and parameters
        function Y!(out, s)

            @simd for i in eachindex(s)
                outi = @view out[:,:,i]
                copyto!(outi, P.get_y(elem, s[i]))
            end
        end  
    else
        throw(ArgumentError("Element $(typeof(elem)) is not a state-space or frequency-domain element."))
    end
    Y!wrap = fwrap(Y!, ComplexF64)


    return Y!wrap

end

# function build(elem::P.Element{<:P.AbstractLinFreqDomain}, iv_sp)
#     # For passive elements, we can directly define the admittance function based on the element type and parameters. No need for state-space representation.
#     # This is a placeholder implementation and should be updated based on the actual types of passive elements and their parameters.
8
#     p = length(elem.pins) #Nb of ports is the number of pins
#     T = ComplexF64 #TODO: Update with measurement and other uncertainties when time is due

    
   
    
#     Y!wrap = fwrap(Y!, T)

   
#     return Y!wrap

# end


function LinearizedAdmittance(Y!::AdmFunc{T}, elemkey::Symbol, conn, netids) where {T<:Number}
    
    # Nets of elements
    elemnets = sortedcomponentconnections(conn, elemkey;withground=true, acfirst=false).net #Sorted from sides and then terminals (with grounds)

    # @assert !any(startswith.(string.(elemnets), ("gnd",))) "Element $(elemkey) is connected to ground, cannot linearize active element"

    # Get net ids & indices of the nets in the order of the ports
    netids_elem = [netids[net] for net in elemnets]
    indices = Matrix{Tuple{Int, Int}}([(i, j) for i in netids_elem, j in netids_elem]) #Assuming all ports are connected to different nets. Otherwise, need to check for duplicates and assign same net id to those ports



    return Y!, indices
end

struct LinearizedInterface
    elem::Dict{Symbol, Int64} # Maps id onto int LinAdmittCollection
    net::Dict{Symbol, Int64} # Maps net name onto int LinAdmittCollection
end

# Base.show(io::IO, intf::LinearizedInterface) = println(io, 	"\n Grounded nets: $([key for (key,netid) in pairs(intf.net) if netid in intf.groundednets]) \n",
#                                                             "Active nets: $([key  for (key,netid) in pairs(intf.net) if netid in intf.activenets])")



"""

Allow for multiple nb of ports inside collection

"""
# const AnyLinearizedAdmittance{T} = LinearizedAdmittance{p, T} where p

struct LinearizedAdmittanceNetwork{T<:Number}
    admittances::LinearizedAdmittanceCollection{T}
    actives::Vector{Int64}
    passives::Vector{Int64}
    groundednets::Vector{Int}
    activenets::Vector{Int}

    interface::LinearizedInterface
end

Base.show(io::IO, bs::LinearizedAdmittanceNetwork) = (println(io, 	"\n LinearizedAdmittance implemented via BuilderState \n",
													"----------------------------------- \n",
													" Nb. of passives: $(length(bs.passives)) \n",
													" Nb. of actives: $(length(bs.actives)) \n",
                                                    "Grounded nets: $([key for (key,netid) in pairs(bs.interface.net) if netid in bs.groundednets]) \n",
                                                    "Active nets: $([key  for (key,netid) in pairs(bs.interface.net) if netid in bs.activenets]) \n"))




function LinearizedAdmittanceNetwork(bs::BuilderState, sp)
    
    # Filter out sources (short circuit in small-signal)
    filterelem = filter(x-> !(P.is_source(x)), bs.elements)

    # Intialize admittance collection arrays
    admittances = Vector{AdmFunc{ComplexF64}}(undef, length(filterelem))
    indices = Vector{Matrix{Tuple{Int64,Int64}}}(undef, length(filterelem))
    elemlut = Dict{Symbol, Int64}()
    
    # Pre-find statespaces and freqdomains for faster looping (not faster according to tests)
    # statespaces = filter(x-> x isa P.Element{<:P.AbstractStateSpace}, bs.elements)
    # freqdomains =  filter(x-> (x isa P.Element{<:P.AbstractLinFreqDomain})&& !(P.is_source(x)), bs.elements) #TODO: Update the abstract name for this type
    # others = filter(x-> !(x isa P.Element{<:P.AbstractStateSpace}) && !(x isa P.Element{<:P.AbstractLinFreqDomain}), bs.elements) # Other user-defined, custom elements.

    
    # Assign integer id to every net
    conn = bs.connections.registry
    nets = unique(conn.net)
    netids = Dict(nets .=> [i for i in eachindex(nets)]) #Assign Int to every net -> index in matrix

    # Function barriers adding admittances (This works even if empty, bcs negative indexing just return empty array)
    # n = 1
    # nend = length(statespaces)
    add!(admittances, elemlut, filterelem, sp)

    # add!(@view(admittances[n:nend]), elemlut, values(statespaces), keys(statespaces), sp, n)
    # n = nend + 1
    # nend += length(freqdomains) 
    # add!(@view(admittances[n:nend]), elemlut, values(freqdomains),keys(freqdomains), n)
    # n = nend + 1
    # nend = n + length(others)
    # add!(@view(admittances[n:nend]), elemlut, values(others), keys(others),n)

    ### Creating indices
    add!(indices, conn, netids, elemlut)

    ## Create collection
    collection = LinearizedAdmittanceCollection(admittances, indices)

    ### Create bookkeeping for active and passive elements (for now the same as statespaces and freqdomains, but can be different in the future)
    actives = filter(x-> P.is_active(x),filterelem)
    activeids = [elemlut[key] for key in keys(actives)]
    passives = filter(x-> P.is_passive(x), filterelem)
    passiveids = [elemlut[key] for key in keys(passives)]

    ### Grounded nets
    groundednets = getgroundednets(netids, keys(filter(x-> P.is_source(x), bs.elements)), bs.connections.registry)

    ### Active nets
    activenets = filter(row->row.elem in keys(actives), conn).net
    activenetids = [netids[net] for net in activenets]



    return LinearizedAdmittanceNetwork(collection, activeids, passiveids, groundednets, activenetids, LinearizedInterface(elemlut, netids))

end

function add!(admittances, elemlut, elements, sp)
    for (i, (key,elem)) in enumerate(pairs(elements))
        iv_sp = get(sp, key, P.Setpoint()) # Get initial values for this element, if any
        admittances[i] = build(elem, iv_sp)
        elemlut[key] = i
    end
    return nothing
end


function add!(admittances, elemlut, statespaces::Tuple{Vararg{T}}, keys,sp, n) where {T <: P.Element{<:P.AbstractStateSpace}}
    
    for i in eachindex(statespaces)
        elem = statespaces[i]
        key=keys[i]
        iv_sp = sp[key]
        admittances[i] = build(elem, iv_sp)
        elemlut[key] = i+n-1
    end
    return nothing
end

function add!(admittances, elemlut, freqdomains::Tuple{Vararg{T}}, keys, n) where {T <: P.Element{<:Union{P.AbstractLinFreqDomain}}} # Can be AbstractFreqDomain or custom linear component, same procedure
    
    for i in eachindex(freqdomains)
        elem = freqdomains[i]
        key=keys[i]
        admittances[i] = build(elem)
        elemlut[key] = i+n-1
    end

    return nothing
end

function add!(indices::Vector{Matrix{Tuple{Int,Int}}}, conn, netids, elemlut)

    # Nets of elements
    for (elemkey, id) in pairs(elemlut)

        elemnets = sortedcomponentconnections(conn, elemkey;withground=true, acfirst=false).net #Sorted from sides and then terminals (with grounds)

        # Get net ids & indices of the nets in the order of the ports
        netids_elem = [netids[net] for net in elemnets]
        indices[id] = Matrix{Tuple{Int, Int}}([(i, j) for i in netids_elem, j in netids_elem]) #Assuming all ports are connected to different nets. Otherwise, need to check for duplicates and assign same net id to those ports
    end

end

function getgroundednets(netids::Dict{Symbol, Int64}, sourcekeys::Tuple{Vararg{Symbol}},conn)
    
    groundednets = [id for (net,id) in pairs(netids) if occursin("gnd", lowercase(string(net)))]
    
    for (key) in (sourcekeys)
       nets = filter(row -> row.elem == key, conn).net
       push!(groundednets, [netids[net] for net in nets]...)
    end
    
    return groundednets
end 


function getelem(lnw::LinearizedAdmittanceNetwork{T}, key::Symbol) where {T}
    return lnw.interface.elem[key]
end
function get_elemadm(lnw::LinearizedAdmittanceNetwork{T}, key::Symbol) where {T}

    id = getelem(lnw,key) 
    return lnw.admittances.Y![id] 

end

function get_elemind(lnw::LinearizedAdmittanceNetwork{T}, key::Symbol) where {T}
    
    id = getelem(lnw,key) 
    return lnw.admittances.indices[id] 
end



function get_y(lnw::LinearizedAdmittanceNetwork{T}, key::Symbol, s::AbstractVector{<:Complex}) where {T}

    elemind = get_elemind(lnw, key)
    Yout = Array{T,3}(undef, size(elemind)..., length(s))
    return get_y!(Yout, lnw, key, s)

end

function get_y!(Yout::AbstractArray{T,3}, lnw::LinearizedAdmittanceNetwork{T}, key::Symbol, s::AbstractVector{<:Complex}) where {T}

  
    Y! = get_elemadm(lnw, key)
    Y!(Yout, s)
    return Yout

end

