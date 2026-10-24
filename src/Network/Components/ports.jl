export Port, ACDQ, ACABC, DC_CM, electricalconnections

"""
$(TYPEDEF)

Define the electrical coordinates of a port.
"""
abstract type AbstractDomain end

struct ACDQDomain <: AbstractDomain end
struct ACABCDomain <: AbstractDomain end
struct DCDomain <: AbstractDomain end

"AC domain with d- and q-axis terminals."
const ACDQ = ACDQDomain()
"AC domain with a-, b- and c-phase terminals."
const ACABC = ACABCDomain()
"DC domain with one `:dc` terminal."
const DC_CM = DCDomain()

"""
$(TYPEDSIGNATURES)

Return the ordered terminal labels of an electrical domain.

# Arguments

- `domain`: Electrical coordinate domain.

# Returns

- Tuple of terminal symbols.
"""
terminals(::ACDQDomain) = (:d, :q)
terminals(::ACABCDomain) = (:a, :b, :c)
terminals(::DCDomain) = (:dc,)

"""
$(TYPEDSIGNATURES)

Return whether the electrical domain uses AC coordinates.

# Arguments

- `domain`: Electrical coordinate domain.

# Returns

- `true` for `ACDQ` and `ACABC`, otherwise `false`.
"""
isac(::ACDQDomain) = true
isac(::ACABCDomain) = true
isac(::DCDomain) = false

"""
$(TYPEDSIGNATURES)

Return whether the electrical domain uses DC coordinates.

# Arguments

- `domain`: Electrical coordinate domain.

# Returns

- `true` for `DC_CM`, otherwise `false`.
"""
isdc(domain::AbstractDomain) = !isac(domain)

"""
$(TYPEDEF)

Describe an electrical port by its domain and ordered terminal labels.

$(TYPEDFIELDS)
"""
struct Port{D<:AbstractDomain, N}
    "Electrical coordinate domain."
    domain::D
    "Ordered terminal labels."
    terminals::NTuple{N, Symbol}
end

"""
$(TYPEDSIGNATURES)

Construct a port with the domain labels or supplied labels of the same count.

# Arguments

- `domain`: Electrical coordinate domain.
- `terminals`: Tuple of replacement symbols. Default: `nothing`, using domain labels.

# Returns

- A `Port` instance.

# Errors

- Throws `ArgumentError` for labels with an incorrect count or non-symbol entries.

# Examples

```julia
Port(ACDQ; terminals = (:x, :y))
```
"""
function Port(domain::AbstractDomain; terminals = nothing)
    labels = PowerImpedance.terminals(domain)
    terminals === nothing && return Port(domain, labels)
    terminals isa NTuple{length(labels), Symbol} ||
        throw(ArgumentError("Port labels must be $(length(labels)) symbols."))
    return Port(domain, terminals)
end

"""
$(TYPEDSIGNATURES)

Return the electrical ports declared by a component model.

# Arguments

- `model`: Component model.

# Returns

- NamedTuple of `Port` values, in declaration order.

# Errors

- Throws `ArgumentError` when the model has no port declaration or its conductor count
  is unsupported.
"""
function electricalconnections(model)::NamedTuple
    throw(ArgumentError("No electrical ports declared for $(typeof(model))."))
end
