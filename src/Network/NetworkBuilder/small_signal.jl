struct _CheckStabilityDefinition
    element::Symbol
    direction::Symbol
end

function _frequency_axis(freq_range)
    length(freq_range) == 3 || throw(ArgumentError(
        "freq_range must be `(minimum_hz, maximum_hz, count)`",
    ))
    minimum_frequency, maximum_frequency, count = freq_range
    minimum_frequency isa Real && isfinite(minimum_frequency) && minimum_frequency > 0 ||
        throw(ArgumentError("the minimum frequency must be finite and positive"))
    maximum_frequency isa Real && isfinite(maximum_frequency) &&
        maximum_frequency > minimum_frequency || throw(ArgumentError(
        "the maximum frequency must be finite and greater than the minimum",
    ))
    count = Int(count)
    count >= 2 || throw(ArgumentError("a frequency response requires at least two points"))
    frequencies = Float64.(2pi .* exp10.(range(
        log10(minimum_frequency),
        log10(maximum_frequency);
        length=count,
    )))
    return frequencies, im .* frequencies
end

function _validate_frequencies(frequencies)
    supplied = collect(frequencies)
    all(value -> value isa Real, supplied) || throw(ArgumentError(
        "frequencies must be real angular frequencies",
    ))
    result = Float64.(supplied)
    length(result) >= 2 || throw(ArgumentError(
        "a frequency response requires at least two points",
    ))
    all(isfinite, result) && all(>(0), result) || throw(ArgumentError(
        "frequencies must be finite and positive",
    ))
    all(diff(result) .> 0) || throw(ArgumentError(
        "frequencies must be strictly increasing",
    ))
    return result
end

function _node_names(network::NetworkModel, requested::Vector{Symbol})
    inverse_names = Dict(identifier => name for (name, identifier) in network.indices.nodes)
    if isempty(requested)
        identifiers = unique(filter(
            identifier -> identifier ∉ network.grounded_nodes,
            network.retained_nodes,
        ))
        isempty(identifiers) && throw(ArgumentError(
            "the network has no default nongrounded retained nodes",
        ))
        return Symbol[inverse_names[identifier] for identifier in identifiers]
    end
    allunique(requested) || throw(ArgumentError("requested nodes must be unique"))
    for node in requested
        haskey(network.indices.nodes, node) || throw(ArgumentError(
            "node :$node is absent from the linearized network",
        ))
        network.indices.nodes[node] ∉ network.grounded_nodes || throw(ArgumentError(
            "grounded node :$node cannot be retained",
        ))
    end
    return copy(requested)
end

function _loopgain_tensor(edge, node)
    size(edge) == size(node) || throw(DimensionMismatch(
        "edge and node responses must have identical dimensions",
    ))
    result = similar(edge, promote_type(eltype(edge), eltype(node)))
    for index in axes(edge, 3)
        result[:, :, index] = inv(edge[:, :, index]) * node[:, :, index]
    end
    return result
end

function _evaluate_response(
    network::NetworkModel,
    kind::Symbol,
    requested_nodes::Vector{Symbol},
    freq_range,
)
    frequencies, complex_frequencies = _frequency_axis(freq_range)
    nodes = _node_names(network, requested_nodes)
    identifiers = Int[network.indices.nodes[node] for node in nodes]
    if kind === :node_admittance
        response = make_y(network, network.active_elements, complex_frequencies, identifiers)
    elseif kind === :edge_admittance
        response = make_y(network, network.passive_elements, complex_frequencies, identifiers)
    elseif kind === :loopgain
        node = make_y(network, network.active_elements, complex_frequencies, identifiers)
        edge = make_y(network, network.passive_elements, complex_frequencies, identifiers)
        response = _loopgain_tensor(edge, node)
    else
        throw(ArgumentError("unsupported response kind :$kind"))
    end
    return response, nodes, frequencies
end

function _check_stability_nodes(builder::NetworkState, definition::_CheckStabilityDefinition)
    haskey(builder.elements, definition.element) || throw(ArgumentError(
        "element :$(definition.element) is absent from the network",
    ))
    element = builder.elements[definition.element]
    P.is_active(element) || throw(ArgumentError("check_stability requires an active element"))
    P.is_source(element) && throw(ArgumentError("check_stability cannot partition an ideal source"))
    domain = definition.direction === :ac ? 1 : definition.direction === :dc ? 2 :
        throw(ArgumentError("direction must be :ac or :dc"))
    rows = filter(
        row -> row.element == definition.element && row.domain == domain && row.bus != 0,
        builder.topology.connections,
    )
    isempty(rows) && throw(ArgumentError("the selected element has no connected terminals"))
    sort!(rows; by=row -> (row.side, row.terminal))
    return unique(Symbol.(rows.node))
end

function _device_admittance(network, element_index, identifiers, complex_frequencies)
    indices = network.element_admittances.indices[element_index]
    order = size(indices, 1)
    local_response = Array{ComplexF64}(undef, order, order, length(complex_frequencies))
    network.element_admittances.Y![element_index](local_response, complex_frequencies)
    global_identifiers = Int[indices[index, index][1] for index in 1:order]
    keep = findall(identifier -> identifier ∉ network.grounded_nodes, global_identifiers)
    reduced = local_response[keep, keep, :]
    kept_identifiers = global_identifiers[keep]
    positions = [something(findfirst(==(identifier), kept_identifiers)) for identifier in identifiers]
    result = Array{ComplexF64}(undef, length(positions), length(positions), length(complex_frequencies))
    for index in eachindex(complex_frequencies)
        result[:, :, index] = P.kron(reduced[:, :, index], positions)
    end
    return result
end

function _check_stability_response(
    builder::NetworkState,
    element::Symbol;
    direction::Symbol=:dc,
    freq_range=(1.0, 1.0e3, 1000),
)
    definition = _CheckStabilityDefinition(element, direction)
    nodes = _check_stability_nodes(builder, definition)
    linearization = P.compute(P.LinearizationProblem(builder), P.AdmittanceLinearization())
    network = linearization.network_model
    frequencies, complex_frequencies = _frequency_axis(freq_range)
    identifiers = Int[network.indices.nodes[node] for node in nodes]
    element_index = network.indices.elements[element]
    device = _device_admittance(network, element_index, identifiers, complex_frequencies)
    remainder_elements = setdiff(collect(1:length(network.element_admittances)), [element_index])
    remainder = make_y(network, remainder_elements, complex_frequencies, identifiers)
    response = similar(device)
    for index in eachindex(complex_frequencies)
        response[:, :, index] = inv(remainder[:, :, index]) * device[:, :, index]
    end
    return response, nodes, frequencies, network
end

function make_y_node(builder::NetworkState; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000))
    result = P.compute(P.PowerImpedanceProblem(
        builder;
        nodes=nodelist,
        frequency_range=freq_range,
    ), P.NodeAdmittance())
    return result.response, result.nodes, result.frequencies
end

function make_y_edge(builder::NetworkState; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000))
    result = P.compute(P.PowerImpedanceProblem(
        builder;
        nodes=nodelist,
        frequency_range=freq_range,
    ), P.EdgeAdmittance())
    return result.response, result.nodes, result.frequencies
end

function make_loopgain(builder::NetworkState; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000))
    result = P.compute(P.PowerImpedanceProblem(
        builder;
        nodes=nodelist,
        frequency_range=freq_range,
    ), P.LoopGain())
    return result.response, result.nodes, result.frequencies
end
