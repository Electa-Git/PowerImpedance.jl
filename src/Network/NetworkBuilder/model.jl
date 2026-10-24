using FunctionWrappers: FunctionWrapper

"In-place element admittance function over a vector of complex frequencies."
const AdmFunc{T} = FunctionWrapper{
    Nothing,
    Tuple{AbstractArray{T, 3}, AbstractVector{<:Complex}}
}

"""
$(TYPEDEF)

Store element admittance functions and their positions in the complete nodal
admittance matrix.

$(TYPEDFIELDS)
"""
struct AdmittanceLookup{T <: Number}
    "In-place element admittance functions."
    Y!::Vector{AdmFunc{T}}
    "Nodal-matrix position of every local admittance entry."
    indices::Vector{Matrix{Tuple{Int, Int}}}
end

function Base.getindex(lookup::AdmittanceLookup, selection)
    indices = collect(selection)
    return AdmittanceLookup(lookup.Y![indices], lookup.indices[indices])
end

Base.length(lookup::AdmittanceLookup) = length(lookup.Y!)
Base.isempty(lookup::AdmittanceLookup) = isempty(lookup.Y!)

fwrap(f, ::Type{T}) where {T <: Number} = AdmFunc{T}(f)

const FUNDAMENTAL_ANGULAR_FREQUENCY = 100π

function build(model::P.AbstractStateSpace, values::NamedTuple, frame::Symbol)
    A, B, C, D = P.linearize(model, values)
    return P.freqresp_cache(A, B, C, D; scale = P.SI_scale(model))
end

function build(model::P.AbstractLinFreqDomain, values::NamedTuple, frame::Symbol)
    function admittance!(output, complex_frequencies)
        @simd for index in eachindex(complex_frequencies)
            copyto!(@view(output[:, :, index]),
                admittance(model, complex_frequencies[index], frame))
        end
    end
    return admittance!
end

"""
$(TYPEDSIGNATURES)

Store solved MMC port values and construct its frequency-admittance function.

# Arguments

- `model`: Scan-based MMC model.
- `values`: AC/DC terminal values in phase-peak or pole-to-pole \\[kV\\],
  angles in \\[rad\\], active power in \\[MW\\] and reactive power in \\[MVAr\\].
  Powers are positive into the component.
- `frame`: Network coordinate frame.

# Returns

- In-place admittance function returning terminal matrices in \\[S\\].
"""
function build(model::P.Blackbox_MMC, values::NamedTuple, frame::Symbol)
    model.cache.values = values
    return invoke(build, Tuple{P.AbstractLinFreqDomain, NamedTuple, Symbol},
        model, values, frame)
end

"""
$(TYPEDSIGNATURES)

Return the MMC scan admittance in \\[S\\] at frequency `s` \\[s⁻¹\\].
The cached voltage angle supplies its d/q rotation. `frame` is the network frame.
"""
admittance(model::P.Blackbox_MMC, s::Complex, frame::Symbol) = P.eval_parameters(model, s)

function admittance(model::P.AbstractLinFreqDomain, s::Complex, frame::Symbol)
    domain = first(P.electricalconnections(model)).domain
    return admittance(model, s, domain, Val(frame))
end

admittance(model, s, ::P.AbstractDomain, ::Val) = P.abcd_to_y(P.eval_abcd(model, s))

function admittance(model, s, ::P.ACABCDomain, ::Val{:dq})
    ω₀ = FUNDAMENTAL_ANGULAR_FREQUENCY
    return P.abcd_to_y(P.transformation_dq(
        P.eval_abcd(model, s + 1im * ω₀), P.eval_abcd(model, s - 1im * ω₀)))
end

function admittance(model, s, ::P.DCDomain, ::Val{:dc})
    abcd = P.eval_abcd(model, s)
    size(abcd, 1) == 4 && (abcd = P.transformation_dc(abcd))
    return P.abcd_to_y(abcd)
end

function _component_frame(rows)
    ac = filter(row -> row.domain == 1, rows)
    return isempty(ac) ? :dc : first(ac).frame
end

"""
$(TYPEDEF)

Map element and node names to integer frequency-model indices.

$(TYPEDFIELDS)
"""
struct NetworkLookup
    "Element name to admittance index."
    elements::Dict{Symbol, Int}
    "Node name to nodal-matrix index."
    nodes::Dict{Symbol, Int}
end

"""
$(TYPEDEF)

Store the linearized frequency-domain representation of one network.

$(TYPEDFIELDS)
"""
struct NetworkModel{T <: Number}
    "Element admittance functions and their nodal positions."
    element_admittances::AdmittanceLookup{T}
    "Indices of active elements."
    active_elements::Vector{Int}
    "Indices of passive elements."
    passive_elements::Vector{Int}
    "Indices eliminated as grounded or ideal-source nodes."
    grounded_nodes::Vector{Int}
    "Default retained-node indices for active-network responses."
    retained_nodes::Vector{Int}
    "Element and node name lookup tables."
    indices::NetworkLookup
end

function Base.show(io::IO, model::NetworkModel)
    grounded = [name
                for (name, index) in pairs(model.indices.nodes)
                if index in model.grounded_nodes]
    retained = [name
                for (name, index) in pairs(model.indices.nodes)
                if index in model.retained_nodes]
    println(
        io,
        "NetworkModel\n",
        "------------\n",
        "Passive elements: $(length(model.passive_elements))\n",
        "Active elements: $(length(model.active_elements))\n",
        "Grounded nodes: $grounded\n",
        "Retained nodes: $retained"
    )
end

"""
    NetworkModel(network::NetworkState, operating_point)

Construct the frequency-domain network model at a calculated operating point.
Ideal sources are omitted from the element admittance lookup and their external
nodes are included in the grounded-node selection. Every active non-source element
requires terminal values in `operating_point`. A missing entry raises `ArgumentError`
with the element name.
"""
function NetworkModel(network::NetworkState, operating_point)::NetworkModel{ComplexF64}
    elements = filter(element -> !P.is_source(element), network.elements)
    admittances = Vector{AdmFunc{ComplexF64}}(undef, length(elements))
    positions = Vector{Matrix{Tuple{Int, Int}}}(undef, length(elements))
    element_indices = Dict{Symbol, Int}()

    connections = network.topology.connections
    node_names = unique(connections.net)
    node_indices = Dict(node_names .=> collect(eachindex(node_names)))

    _build_admittances!(admittances, element_indices, elements, operating_point,
        network.topology)
    _build_positions!(positions, network.topology, node_indices, element_indices)
    lookup = AdmittanceLookup(admittances, positions)

    active = filter(P.is_active, elements)
    active_indices = Int[element_indices[name] for name in keys(active)]
    passive = filter(P.is_passive, elements)
    passive_indices = Int[element_indices[name] for name in keys(passive)]
    grounded_nodes = _grounded_nodes(
        node_indices,
        keys(filter(P.is_source, network.elements)),
        connections
    )
    active_node_names = filter(row -> row.component in keys(active), connections).net
    retained_nodes = unique(node_indices[node] for node in active_node_names)

    return NetworkModel(
        lookup,
        active_indices,
        passive_indices,
        grounded_nodes,
        collect(retained_nodes),
        NetworkLookup(element_indices, node_indices)
    )
end

function _build_admittances!(admittances, indices, elements, operating_point, topology)
    for (index, (name, model)) in enumerate(pairs(elements))
        values = get(operating_point, name, nothing)
        P.is_active(model) && values === nothing && throw(ArgumentError(
            "operating point is missing active element :$name"))
        rows = sortedcomponentconnections(topology, name; withground = true)
        response! = _element_call(name) do
            build(model, values === nothing ? (;) : values, _component_frame(rows))
        end
        function admittance!(output, frequencies)
            return _element_call(name) do
                response!(output, frequencies)
            end
        end
        admittances[index] = fwrap(admittance!, ComplexF64)
        indices[name] = index
    end
    return nothing
end

function _build_positions!(positions, topology, node_indices, element_indices)
    for (element, index) in pairs(element_indices)
        nodes = sortedcomponentconnections(topology, element; withground = true).net
        local_indices = [node_indices[node] for node in nodes]
        positions[index] = [(row, column) for row in local_indices, column in local_indices]
    end
    return nothing
end

function _grounded_nodes(node_indices, source_names, connections)
    grounded = Int[node_indices[row.net] for row in connections if row.bus == 0]
    for source in source_names
        for row in filter(row -> row.component == source, connections)
            push!(grounded, node_indices[row.net])
        end
    end
    return unique(grounded)
end

getelem(model::NetworkModel, key::Symbol) = model.indices.elements[key]

function get_elemadm(model::NetworkModel, key::Symbol)
    return model.element_admittances.Y![getelem(model, key)]
end

function get_elemind(model::NetworkModel, key::Symbol)
    return model.element_admittances.indices[getelem(model, key)]
end

function get_y(
        model::NetworkModel{T},
        key::Symbol,
        complex_frequencies::AbstractVector{<:Complex}
) where {T}
    positions = get_elemind(model, key)
    output = Array{T, 3}(undef, size(positions)..., length(complex_frequencies))
    return get_y!(output, model, key, complex_frequencies)
end

function get_y!(
        output::AbstractArray{T, 3},
        model::NetworkModel{T},
        key::Symbol,
        complex_frequencies::AbstractVector{<:Complex}
) where {T}
    get_elemadm(model, key)(output, complex_frequencies)
    return output
end
