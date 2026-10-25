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
export Bus, Net, define, update!, solve
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

include("topology.jl")
include("options.jl")
include("roles.jl")

##### Builder state

include("powerflow.jl")

function Base.show(io::IO, bs::NetworkState)
    println(io, "\n Network implemented via NetworkState \n",
        "----------------------------------- \n",
        " Nb. of elements: $(length(bs.elements)) \n",
        " Nb. of connections: $(length(bs.topology.connections)) \n",
        " With following options: $(bs.options)")
end

"""
$(TYPEDSIGNATURES)

Construct a [`NetworkState`](@ref) or a lazy space of network states.

# Arguments

- `elements`: Named tuple of component models or component Gridspaces.
- `connections`: Tuple or vector of `Bus` and `Net` declarations.
- `options`: Builder and power-flow options. Default: `(;)`.
- `exclude`: Component names to omit, with an informational message. Default: `()`.

# Returns

- A `NetworkState` when every input is scalar.
- A `Gridspace{NetworkState}` when an element or direct option is parametric.

# Errors

- Throws `ArgumentError` for invalid topology, an unreferenced included element, or
  a model without NetworkBuilder power-flow support.
"""
function define(
        elements::NamedTuple,
        connections::Union{Tuple, AbstractVector};
        options = (;),
        exclude = ()
)
    inputs = (Tuple(values(elements))..., Tuple(values(options))...)
    style = _network_input_style(inputs)
    return _define_network(style, elements, connections, options, exclude)
end

_network_input_style(::Tuple{}) = Val(false)
_network_input_style(::Tuple{<:Union{AbstractGrid,Gridspace},Vararg}) = Val(true)
_network_input_style(inputs::Tuple) = _network_input_style(Base.tail(inputs))

function _define_network(
        ::Val{false},
        elements::NamedTuple,
        connections::Union{Tuple, AbstractVector},
        options::NamedTuple,
        exclude
)
    excluded = _excluded_names(elements, exclude)
    isempty(excluded) || @info "Excluded elements: $excluded."
    topology = NetworkTopology(elements, connections; exclude = excluded)
    names = Tuple(name for name in keys(elements) if name ∉ excluded)
    referenced = Set(topology.connections.component)
    models = map(names) do name
        name ∈ referenced ||
            throw(ArgumentError("element :$name is not referenced by the topology"))
        model = _element_call(name) do
            elements[name]::P.AbstractElementModel
        end
        model
    end
    return NetworkState(NamedTuple{names}(models), topology, options)
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

- A `PowerFlowResult` with the solved per-port operating point.

"""
function solve(builder::NetworkState)
    return P.compute(PowerFlowProblem(builder), ACDCPowerFlow())
end

include("model.jl")
include("results.jl")
include("../Solvers/admittance.jl")
include("../Solvers/impedance.jl")
include("uquant.jl")
include("parametric.jl")
include("small_signal.jl")

end
