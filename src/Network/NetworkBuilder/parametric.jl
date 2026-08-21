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
(::_NamedTupleMaterializer{Names})(values...) where {Names} = NamedTuple{Names}(values)

function _namedtuple_gridspace(values::NamedTuple{Names}) where {Names}
    axes = map(_axis, Base.values(values))
    return Gridspace{NamedTuple}(_NamedTupleMaterializer{Names}(), axes, Names)
end

struct _BuilderMaterializer{Connections}
    connections::Connections
end

function (target::_BuilderMaterializer)(elements, options)
    return define(elements, target.connections; options)
end

"""
    define(elements, connections, keyword options)

Compose element Gridspaces into a `Gridspace{NetworkState}`. Raw containers
remain atomic. Only explicit Gridspace axes introduce configurations.
"""
function define(
    elements::NamedTuple{Names,Types},
    connections::Union{Tuple,AbstractVector};
    options=(;),
) where {Names,Types<:Tuple{Vararg{Gridspace}}}
    element_space = _namedtuple_gridspace(elements)
    option_space = _namedtuple_gridspace(options)
    return Gridspace{NetworkState}(
        _BuilderMaterializer(connections),
        (element_space, option_space),
        (:elements, :options),
    )
end
