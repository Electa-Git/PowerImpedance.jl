include("gs_components.jl")
include("gs_passives.jl")
include("gs_machines.jl")
include("gs_controls.jl")
include("gs_converters.jl")

function NetworkModel(
    admittances::AdmittanceLookup{T},
    ::Vector{Union{}},
    passive_elements::Vector{Int64},
    grounded_nodes::Vector{Int},
    retained_nodes::Vector{Int},
    indices::NetworkLookup,
) where {T<:Number}
    return NetworkModel(
        admittances,
        Int64[],
        passive_elements,
        grounded_nodes,
        retained_nodes,
        indices,
    )
end

struct _NamedTupleMaterializer{Names} end
function (::_NamedTupleMaterializer{Names})(values...)::NamedTuple{Names} where {Names}
    return NamedTuple{Names}(values)
end

function _namedtuple_gridspace(values::NamedTuple{Names}) where {Names}
    return _lift_gridspace(
        NamedTuple{Names},
        _NamedTupleMaterializer{Names}(),
        values,
        Val(:product),
    )
end

struct _BuilderMaterializer{Connections}
    connections::Connections
end

function (target::_BuilderMaterializer)(elements, options)::NetworkState
    return define(elements, target.connections; options)
end

"""
    define(elements, connections, keyword options)

Compose element Gridspaces into a `Gridspace{NetworkState}`. Raw containers
remain atomic. Only explicit Gridspace axes introduce configurations.
"""
function _define_network(
    ::Val{true},
    elements::NamedTuple,
    connections::Union{Tuple,AbstractVector},
    options::NamedTuple,
)
    element_space = _namedtuple_gridspace(elements)
    option_space = _namedtuple_gridspace(options)
    return _lift_gridspace(
        NetworkState,
        _BuilderMaterializer(connections),
        (; elements=element_space, options=option_space),
        Val(:product),
    )
end
