## Types for results
import StaticArrays: SMatrix
import FunctionWrappers: FunctionWrapper
import Base: length
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

struct NpPortAdmittanceCollection{N,p, T<:Real}
    elem::NTuple{N, FunctionWrapper{SMatrix{p,p,T}}}
    connections::NTuple{N, NTuple{p, Int}}
end

struct LinearizedInterface
    elem::Dict{Symbol, @NamedTuple{type::Symbol, id::Int}}
    net::Dict{Symbol, Int}
end


"""

We cannot do multiple of types in definiton. So enforce it via constructor

"""
struct LinearizedAdmittanceNetwork{N, p, twop}
    shunt::NpPortAdmittanceCollection{N, p}
    networkelements::NpPortAdmittanceCollection{N, twop}
end



    

