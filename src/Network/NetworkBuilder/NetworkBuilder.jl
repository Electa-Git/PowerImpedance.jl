module NetworkBuilder

### Set up module and imports
import TypedTables: Table
using DocStringExtensions: TYPEDEF, TYPEDFIELDS

export NetworkState, NetworkTopology, AdmittanceLookup, NetworkLookup, NetworkModel
export define, update!, solve
export AbsoluteError, AbsoluteGrid, DeterministicGrid, Grid, Gridspace, RelativeGrid
export @gridspace, @relax
export ImpedanceCase, ParametricImpedance, SolveCase, ParametricSolve
export FrequencyResponseCase, ParametricFrequencyResponse, ParametricNodeSchema
export StabilityCase, ParametricStability, make_loopgain, sampled_frequency_response

const P = parentmodule(@__MODULE__)

include("gridspace/grid.jl")
include("gridspace/gridspace.jl")
include("gridspace/macros.jl")

#convenience macro to create typedtable types
macro Table(ex)
    Meta.isexpr(ex, :braces) || throw(ArgumentError("@Table expects {...}"))
    nt_elements = :(@NamedTuple{})
    nt_vectors = :(@NamedTuple{})

    for a in ex.args
        if !(a isa LineNumberNode)
            Meta.isexpr(a, :(::)) ||
                throw(ArgumentError("@Table specification must contain name::type expressions"))
            var = (a.args[1])
            el = esc(a.args[2])
            push!(nt_elements.args[3].args, :($var::$el))
            push!(nt_vectors.args[3].args, :($var::Vector{$el}))
        end
    end
    return :(Table{$nt_elements, 1, $nt_vectors})
end

### Import relevant files

include("connections.jl")
include("options.jl")
include("legacy.jl")

##### Builder state

"""
$(TYPEDEF)

Store one materialized NetworkBuilder system: ordinary numeric elements, its
topology, numerical options, and an optional calculated operating point.

Construct systems with [`define`](@ref) rather than calling this type directly.

$(TYPEDFIELDS)
"""
mutable struct NetworkState
    "Materialized PowerImpedance elements indexed by name."
    elements::NamedTuple
    "Node–element incidence relation."
    topology::NetworkTopology
    "Numerical and power-flow options."
    options::NamedTuple
    "Cached steady-state point for active-element linearization."
    operating_point::Union{Nothing, P.OperatingPoint}
end

function Base.show(io::IO, bs::NetworkState)
    println(io, "\n Network implemented via NetworkState \n",
        "----------------------------------- \n",
        " Nb. of elements: $(length(bs.elements)) \n",
        " Nb. of connections: $(length(bs.topology.connections)) \n",
        " With following options: $(bs.options)")
end

"""
    define(elements, connections; options=(;))

Construct a scalar [`NetworkState`](@ref) from ordinary elements and fixed
connections.

# Arguments

- `elements`: Named tuple of scalar PowerImpedance elements.
- `connections`: Tuple or vector of named topology rows.
- `options`: Builder and power-flow options.

# Returns

- A `NetworkState`. If the element values are Gridspaces, more-specific
  dispatch returns a `Gridspace{NetworkState}`.
"""
function define(
        elements::NamedTuple,
        connections::Union{Tuple, AbstractVector};
        options = (;)
)
    connected_names = Tuple(
        name for name in keys(elements) if elements[name].connection
    )
    connected_elements = NamedTuple{connected_names}(
        Tuple(elements[name] for name in connected_names),
    )
    nonconnectedid = setdiff(keys(elements), keys(connected_elements))
    if !isempty(nonconnectedid)
        @info "The following elements are not connected according to their definition and will be ignored: $(nonconnectedid). If you want to include them, set connection=true in their definition."
    end
    topology = NetworkTopology(elements, connections)
    return NetworkState(connected_elements, topology, options, nothing)
end

"""
    update!(network; elements=network.elements,
            topology=network.topology, options=network.options,
            operating_point=nothing)

Replace fields of an existing [`NetworkState`](@ref).

# Arguments

- `builder`: Mutable system definition to update.
- `elements`: Replacement named tuple of scalar elements.
- `topology`: Replacement node–element incidence relation.
- `options`: Replacement builder options.
- `operating_point`: Optional compatible steady-state operating point.

# Returns

- A named tuple containing the resulting `operating_point`.

# Notes

Changing the state clears its previous operating point.
"""
function update!(
        builder::NetworkState;
        elements = builder.elements,
        topology = builder.topology,
        options = builder.options,
        operating_point = nothing
)
    builder.elements = elements
    builder.topology = topology
    builder.options = options
    builder.operating_point = operating_point
    return (; operating_point = builder.operating_point)
end

"""
    solve(builder::NetworkState)

Build and solve one ordinary numeric NetworkBuilder system.

# Arguments

- `builder`: Materialized system definition.

# Returns

- A named tuple containing `powerflow` and the constructed scalar `network`.

# Notes

The `Gridspace{NetworkState}` overload applies this scalar pipeline to every
deterministic case and numeric Monte Carlo trial.
"""
function solve(builder::NetworkState)
    return _solve(builder)
end

function _apply_operating_point!(network::P.Network, point::P.OperatingPoint)
    for (name, setpoint) in point.setpoints
        haskey(network.elements, name) || throw(
            ArgumentError("operating point references missing element :$name"),
        )
        element = network.elements[name]
        if element.element_model isa P.AbstractStateSpace
            P.update!(element, setpoint)
        elseif P.is_converter(element)
            P.update!(
                element.element_model,
                setpoint.Vac,
                setpoint.θac,
                setpoint.Pac,
                setpoint.Qac,
                setpoint.Vdc,
                setpoint.Pdc
            )
            element.setpoint = setpoint
        else
            P.update!(element, setpoint)
        end
    end
    return network
end

function _solve(builder::NetworkState)
    network = build_network(builder.elements, builder.topology, builder.options)
    if islinear(builder.elements)
        builder.operating_point = P.OperatingPoint()
        @info "Network only consists of linear elements. Skipping power flow."
        return (; powerflow = nothing, network)
    end

    powerflow = P.compute(PowerFlowProblem(builder), ACDCPowerFlow())
    _apply_operating_point!(network, powerflow.operating_point)
    return (; powerflow, network)
end

include("../../core/base.jl")
include("powerflow.jl")
include("../../core/convert.jl")
include("../Solvers/make_adm_NB.jl")
include("../Solvers/determine_impedance_NB.jl")
include("uquant.jl")
include("parametric.jl")
include("small_signal.jl")
include("../../retired.jl")

end
