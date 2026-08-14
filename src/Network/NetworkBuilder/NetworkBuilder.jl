module NetworkBuilder

### Set up module and imports
import TypedTables: Table

export pin, ⟷, ↔
export BuilderState, Pin, ConnectionDef, define, update!, solve
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
            Meta.isexpr(a, :(::)) ||throw(ArgumentError("@Table specification must contain name::type expressions"))
            var = (a.args[1])
            el = esc(a.args[2])
            push!(nt_elements.args[3].args,:($var::$el))
            push!(nt_vectors.args[3].args,:($var::Vector{$el}))
        end
    end
    return :(Table{$nt_elements,1, $nt_vectors})
end

### Import relevant files

include("connections.jl")
include("options.jl")
include("legacy.jl")





##### Builder state

"""
    BuilderState

Store one materialized NetworkBuilder system: ordinary numeric elements, its
connection registry, builder options, and an optional cached power-flow result.

Construct systems with [`define`](@ref) rather than calling this type directly.
"""
mutable struct BuilderState
	elements::NamedTuple
	connections::ConnectionsRegistry
	options::NamedTuple
	powerflow::Any
end

Base.show(io::IO, bs::BuilderState) = println(io, 	"\n Network implemented via BuilderState \n",
													"----------------------------------- \n",
													" Nb. of elements: $(length(bs.elements)) \n",
													" Nb. of connections: $(length(bs.connections.registry)) \n",
													" With following options: $(bs.options)" )



"""
    define(elements, connections; options=(;))

Construct a scalar [`BuilderState`](@ref) from ordinary elements and fixed
connections.

# Arguments

- `elements`: Named tuple of scalar PowerImpedance elements.
- `connections`: Tuple of [`ConnectionDef`](@ref) values.
- `options`: Builder and power-flow options.

# Returns

- A `BuilderState`. If the element values are Gridspaces, more-specific
  dispatch returns a `Gridspace{BuilderState}`.
"""
function define(elements::NamedTuple, connections::Tuple{Vararg{ConnectionDef}}; options = (;))

	connected_elements = (; filter(p -> p.second.connection, pairs(elements))...) #Filter out non-connected elements
	nonconnectedid = setdiff(keys(elements), keys(connected_elements))
	if !isempty(nonconnectedid)
		@info "The following elements are not connected according to their definition and will be ignored: $(nonconnectedid). If you want to include them, set connection=true in their definition."
	end
	connectionregistry = ConnectionsRegistry(elements, connections, nonconnectedid)


	### New changes wrt legacy version:1) add pins to elements again (necesarry for legacy) 2) filter out ground for singleport in connections
	updateelempins!(elements, connectionregistry)

	# Check that single port devices(synchronous machine, ideal voltage sources) are not connected to ground (after legacy network definition)
	groundedsingleports = filter(row -> P.isgroundnet(row.net) && P.issingleport(elements[row.elem]), connectionregistry.registry)
	
	if !isempty(groundedsingleports) 
		@warn "The following single-port elements are connected to ground, for legacy reasons allowed: $(groundedsingleports.elem). These ground connections will be removed from the connection list"
		registry = filter(row -> row ∉ groundedsingleports, connectionregistry.registry)
		connectionregistry = ConnectionsRegistry(registry)
	end
	
	return BuilderState(connected_elements, connectionregistry, options, nothing)
end



"""
    update!(builder; elements=builder.elements,
            connections=builder.connections, options=builder.options,
            powerflow=nothing)

Replace fields of an existing [`BuilderState`](@ref).

# Arguments

- `builder`: Mutable system definition to update.
- `elements`: Replacement named tuple of scalar elements.
- `connections`: Replacement connection registry.
- `options`: Replacement builder options.
- `powerflow`: Optional compatible cached power-flow result.

# Returns

- A named tuple containing the resulting `powerflow` cache.

# Notes

Changing the builder clears its previous power-flow cache. Supplying
`powerflow` applies and caches the provided active-element setpoints.
"""
function update!(
	builder::BuilderState;
	elements = builder.elements,
	connections = builder.connections,
	options = builder.options,
	powerflow = nothing,
)
	builder.elements = elements
	builder.connections = connections
	builder.options = options
	builder.powerflow = nothing

	if powerflow !== nothing
		set_point!(builder; powerflow)
	end

	return (;powerflow = builder.powerflow,)
end




"""
    solve(builder::BuilderState)

Build and solve one ordinary numeric NetworkBuilder system.

# Arguments

- `builder`: Materialized system definition.

# Returns

- A named tuple containing `powerflow` and the constructed scalar `network`.

# Notes

The `Gridspace{BuilderState}` overload applies this scalar pipeline to every
deterministic case and numeric Monte Carlo trial.
"""
function solve(builder::BuilderState)
	buildernetwork = build_network(builder.elements, builder.connections, builder.options)
	powerflow = solve_powerflow(buildernetwork, builder.options)

	if powerflow !== nothing
		apply_powerflow_setpoints!(buildernetwork, powerflow)
		powerflow = cache_active_setpoint_values(buildernetwork, powerflow)
	end

	builder.powerflow = powerflow
	return (;powerflow = builder.powerflow,network=buildernetwork)
end









include("../../core/base.jl")
include("powerflow.jl")
include("../../core/convert.jl")
include("cachesetpoints.jl")
include("../Solvers/make_adm_NB.jl")
include("../Solvers/determine_impedance_NB.jl")
include("uquant.jl")
include("parametric.jl")
include("small_signal.jl")

end
