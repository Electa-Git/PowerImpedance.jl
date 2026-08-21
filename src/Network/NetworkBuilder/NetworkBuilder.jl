module NetworkBuilder

### Set up module and imports
import TypedTables: Table
using DocStringExtensions: TYPEDEF, TYPEDFIELDS, TYPEDSIGNATURES

using ..Grammar: AbstractGrid, AbstractUncertainGrid, AbsoluteError, AbsoluteGrid
using ..Grammar: Configuration, DeterministicGrid, Grid, Gridspace, RelativeGrid
using ..Grammar: UncertainValue, configuration_manifest, configurations
using ..Grammar: has_uncertainty, materialize, nominal, standard_uncertainty
using ..Grammar: @gridspace, @relax
using ..Grammar: AbstractProblemDefinition, AbstractFormulation
using ..Grammar: AbstractProblemResult, AbstractParametricResult
using ..Grammar: AbstractUncertaintyResult
using ..Grammar: compute, primitives, preprocess
using ..Grammar: ParametricProblem, Combinatorial, LinearError, MonteCarlo
using ..Grammar: ParametricResult, LinearErrorResult, MonteCarloResult
using ..Grammar: LineParametersInput, EmpiricalSamples, MeasurementsSurrogate
import ..Grammar: _axis, _direct_value, _gridspace_axis, _lift_gridspace, _materialize

export NetworkState, NetworkTopology, AdmittanceLookup, NetworkLookup, NetworkModel
export define, update!, solve
export PowerFlowProblem, ACDCPowerFlow, LinearizationProblem, AdmittanceLinearization
export AbstractGrid, AbstractUncertainGrid, AbsoluteError, AbsoluteGrid
export Configuration, DeterministicGrid, Grid, Gridspace, RelativeGrid, UncertainValue
export configurations, materialize, has_uncertainty, configuration_manifest
export nominal, standard_uncertainty
export @gridspace, @relax
export AbstractProblemDefinition, AbstractFormulation, AbstractProblemResult
export AbstractParametricResult, AbstractUncertaintyResult
export compute, primitives, preprocess
export ParametricProblem, Combinatorial, LinearError, MonteCarlo
export ParametricResult, LinearErrorResult, MonteCarloResult
export LineParametersInput, EmpiricalSamples, MeasurementsSurrogate
export make_y_node, make_y_edge, make_loopgain

const P = parentmodule(@__MODULE__)

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

Store one materialized NetworkBuilder system with ordinary numeric elements,
topology, and numerical options.

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
end

function Base.show(io::IO, bs::NetworkState)
    println(io, "\n Network implemented via NetworkState \n",
        "----------------------------------- \n",
        " Nb. of elements: $(length(bs.elements)) \n",
        " Nb. of connections: $(length(bs.topology.connections)) \n",
        " With following options: $(bs.options)")
end

"""
$(TYPEDSIGNATURES)

Construct a [`NetworkState`](@ref) or a lazy space of network states from scalar and parametric elements.

# Arguments

- `elements`: Named tuple of scalar elements and element Gridspaces.
- `connections`: tuple or vector of named topology rows.
- `options`: builder and power-flow options.

# Returns

- A `NetworkState` when every input is scalar.
- A `Gridspace{NetworkState}` when an element or direct option is parametric.
"""
function define(
        elements::NamedTuple,
        connections::Union{Tuple, AbstractVector};
        options = (;)
)
    inputs = (Tuple(values(elements))..., Tuple(values(options))...)
    style = _network_input_style(inputs)
    return _define_network(style, elements, connections, options)
end

_network_input_style(::Tuple{}) = Val(false)
_network_input_style(::Tuple{<:Union{AbstractGrid,Gridspace},Vararg}) = Val(true)
_network_input_style(inputs::Tuple) = _network_input_style(Base.tail(inputs))

function _define_network(
    ::Val{false},
    elements::NamedTuple,
    connections::Union{Tuple,AbstractVector},
    options::NamedTuple,
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
    return NetworkState(connected_elements, topology, options)
end

"""
$(TYPEDSIGNATURES)

Replace fields of an existing [`NetworkState`](@ref).

# Arguments

- `builder`: mutable system definition to update.
- `elements`: replacement named tuple of scalar elements.
- `topology`: replacement node-element incidence relation.
- `options`: replacement builder options.
# Returns

- The updated network.

# Notes

Calculated operating points are returned by `compute` and are not cached here.
"""
function update!(
        builder::NetworkState;
        elements = builder.elements,
        topology = builder.topology,
        options = builder.options
)
    builder.elements = elements
    builder.topology = topology
    builder.options = options
    return builder
end

"""
    solve(builder::NetworkState)

Build and solve one ordinary numeric NetworkBuilder system.

# Arguments

- `builder`: materialized system definition.

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
