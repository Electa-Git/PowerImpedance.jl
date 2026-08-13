import Random
import Mmap

mutable struct _BuilderResponseStudy
    gridspace::Any
    plans::Vector{_ValuePlan}
    master_seed::UInt64
    distribution::Symbol
    trials::Vector{Int}
    confidence::Float64
    tolerance::Float64
    study_id::UInt64
    node_keys::Vector{Any}
end

struct _BuilderResponseReplay
    plan::_ValuePlan
    kind::Any
    nodes::Vector{Symbol}
    node_keys::Any
    freq_range::Tuple
    seed::UInt64
    distribution::Symbol
    trials::Int
    zero_uncertainty::Bool
    study_id::UInt64
end

struct _ImpedanceReplay
    plan::_ValuePlan
    keywords::NamedTuple
    seed::UInt64
    distribution::Symbol
    trials::Int
    zero_uncertainty::Bool
    study_id::UInt64
end

struct _EmpiricalResponseReplay
    samples::Any
    trial_ids::Vector{Int}
    study_id::UInt64
end

struct _CallbackResponseReplay{F}
    sampler::F
    seed::UInt64
    trials::Int
    study_id::UInt64
end

struct _DerivedResponseReplay
    left::FrequencyResponseCase
    right::FrequencyResponseCase
    pairing::Symbol
    seed::UInt64
    trials::Int
    study_id::UInt64
end

struct _InverseFrequencyResponse
    response::ParametricFrequencyResponse
end

struct _CheckStabilitySpec
    element::Symbol
    direction::Symbol
end

mutable struct _SmallSignalRunner
    cache::Any
    kind::Any
    nodes::Vector{Symbol}
    node_keys::Any
    freq_range::Tuple
end

_is_anonymous_node(node::Symbol) = startswith(String(node), "##")

function _node_key(builder::BuilderState, node::Symbol)
    rows = filter(row -> row.net == node, builder.connections.registry)
    isempty(rows) && throw(ArgumentError(
        "node :$node is absent from the BuilderState connection registry",
    ))
    terminals = sort!(collect(Set(
        (row.elem, row.side, row.terminal, row.elecdomain) for row in rows
    )))
    return (
        name = _is_anonymous_node(node) ? nothing : node,
        terminals = terminals
    )
end

_node_keys(builder::BuilderState, nodes) = [_node_key(builder, node) for node in nodes]

function _resolve_node_keys(builder::BuilderState, keys)
    candidates = unique(Symbol.(builder.connections.registry.net))
    candidate_keys = Dict(node => _node_key(builder, node) for node in candidates)
    resolved = Symbol[]
    for key in keys
        matches = filter(candidates) do candidate
            candidate_key = candidate_keys[candidate]
            key.name === nothing ?
            candidate_key.name === nothing && candidate_key.terminals == key.terminals :
            candidate_key == key
        end
        length(matches) == 1 || throw(ArgumentError(
            "the ordered node schema changed: expected one node connected to " *
            "$(key.terminals), found $(length(matches))",
        ))
        push!(resolved, only(matches))
    end
    return resolved
end

function _check_stability_nodes(builder::BuilderState, spec::_CheckStabilitySpec)
    haskey(builder.elements, spec.element) || throw(ArgumentError(
        "element :$(spec.element) is not present in the BuilderState",
    ))
    element = builder.elements[spec.element]
    P.is_active(element) || throw(ArgumentError(
        "check_stability requires an active element; :$(spec.element) is passive",
    ))
    P.is_source(element) && throw(ArgumentError(
        "check_stability cannot partition an ideal source",
    ))
    element.connection || throw(ArgumentError(
        "element :$(spec.element) is disconnected",
    ))
    domain = spec.direction === :ac ? 1 :
             spec.direction === :dc ? 2 :
             throw(ArgumentError("direction must be :ac or :dc"))
    connections = filter(
        row -> row.elem == spec.element && row.elecdomain == domain && row.bus != 0,
        builder.connections.registry
    )
    isempty(connections) && throw(ArgumentError(
        "element :$(spec.element) has no connected $(uppercase(string(spec.direction))) terminals",
    ))
    sort!(connections; by = row -> (row.side, row.terminal))
    return unique(Symbol.(connections.net))
end

function _device_admittance(
        network::LinearizedAdmittanceNetwork,
        element_index::Int,
        selected_identifiers::Vector{Int},
        complex_frequencies
)
    indices = network.admittances.indices[element_index]
    order = size(indices, 1)
    local_response = Array{ComplexF64}(undef, order, order, length(complex_frequencies))
    network.admittances.Y![element_index](local_response, complex_frequencies)
    global_identifiers = Int[indices[index, index][1] for index in 1:order]
    keep = findall(identifier -> identifier ∉ network.groundednets, global_identifiers)
    reduced_response = local_response[keep, keep, :]
    kept_identifiers = global_identifiers[keep]
    selected_positions = Int[]
    for identifier in selected_identifiers
        position = findfirst(==(identifier), kept_identifiers)
        position === nothing && throw(ArgumentError(
            "the selected terminal is absent from the active element admittance",
        ))
        push!(selected_positions, position)
    end
    result = Array{ComplexF64}(
        undef,
        length(selected_positions),
        length(selected_positions),
        length(complex_frequencies)
    )
    for frequency_index in eachindex(complex_frequencies)
        result[:, :, frequency_index] = P.kron(
            reduced_response[:, :, frequency_index], selected_positions
        )
    end
    return result
end

function _evaluate_response(
        network::LinearizedAdmittanceNetwork,
        spec::_CheckStabilitySpec,
        requested_nodes::Vector{Symbol},
        freq_range
)
    frequencies, complex_frequencies = _frequency_axis(freq_range)
    nodes = _node_names(network, requested_nodes)
    selected_identifiers = Int[network.interface.net[node] for node in nodes]
    haskey(network.interface.elem, spec.element) || throw(ArgumentError(
        "active element :$(spec.element) was not included in the linearized network",
    ))
    element_index = network.interface.elem[spec.element]
    device_admittance = _device_admittance(
        network,
        element_index,
        selected_identifiers,
        complex_frequencies
    )
    remainder_elements = setdiff(collect(1:length(network.admittances)), [element_index])
    remainder_admittance = make_y(
        network,
        remainder_elements,
        complex_frequencies,
        selected_identifiers
    )
    loopgain = similar(device_admittance)
    for frequency_index in eachindex(complex_frequencies)
        remainder_impedance = inv(remainder_admittance[:, :, frequency_index])
        device_impedance = inv(device_admittance[:, :, frequency_index])
        loopgain[:, :, frequency_index] = remainder_impedance * inv(device_impedance)
    end
    return loopgain, nodes, frequencies
end

function _frequency_axis(freq_range)
    length(freq_range) == 3 || throw(ArgumentError(
        "freq_range must be a three-tuple (minimum_hz, maximum_hz, count)",
    ))
    minimum_frequency, maximum_frequency, count = freq_range
    minimum_frequency isa Real && isfinite(minimum_frequency) && minimum_frequency > 0 ||
        throw(ArgumentError("the minimum frequency must be finite and positive"))
    maximum_frequency isa Real && isfinite(maximum_frequency) &&
    maximum_frequency > minimum_frequency || throw(ArgumentError(
        "the maximum frequency must be finite and greater than the minimum frequency",
    ))
    count = Int(count)
    count >= 2 || throw(ArgumentError("a frequency response requires at least two points"))
    frequencies = Float64.(
        2pi .*
        10 .^ range(
        log10(minimum_frequency), log10(maximum_frequency); length = count
    ),
    )
    return frequencies, im .* frequencies
end

function _validate_frequencies(frequencies)
    supplied = collect(frequencies)
    all(value -> value isa Real, supplied) || throw(ArgumentError(
        "frequencies must be real angular frequencies in rad/s",
    ))
    result = Float64.(supplied)
    length(result) >= 2 || throw(ArgumentError(
        "a frequency response requires at least two frequency points",
    ))
    all(isfinite, result) || throw(ArgumentError("frequencies must be finite"))
    all(>(0), result) || throw(ArgumentError("frequencies must be strictly positive"))
    all(result[index] < result[index + 1] for index in 1:(length(result) - 1)) ||
        throw(ArgumentError("frequencies must be strictly increasing"))
    return result
end

function _response_tensor(response, frequencies)
    if response isa AbstractArray{<:Number, 3}
        tensor = ComplexF64.(response)
    elseif response isa AbstractVector && all(item -> item isa AbstractMatrix, response)
        isempty(response) && throw(ArgumentError("a frequency response cannot be empty"))
        dimensions = size(first(response))
        all(item -> size(item) == dimensions, response) || throw(DimensionMismatch(
            "frequency-response matrix dimensions differ across frequencies",
        ))
        tensor = cat((ComplexF64.(item) for item in response)...; dims = 3)
    else
        throw(ArgumentError(
            "expected an n×n×nf numeric tensor or a vector of numeric matrices; " *
            "received $(typeof(response))",
        ))
    end
    size(tensor, 1) == size(tensor, 2) || throw(DimensionMismatch(
        "small-signal frequency-response matrices must be square",
    ))
    size(tensor, 3) == length(frequencies) || throw(DimensionMismatch(
        "the response frequency dimension does not match the frequency vector",
    ))
    all(value -> isfinite(real(value)) && isfinite(imag(value)), tensor) ||
        throw(ArgumentError("frequency responses must contain only finite values"))
    return tensor
end

function _node_names(network::LinearizedAdmittanceNetwork, requested::Vector{Symbol})
    inverse_names = Dict{Int, Symbol}()
    for (name, identifier) in network.interface.net
        get!(inverse_names, identifier, name)
    end

    if isempty(requested)
        identifiers = unique(filter(
            identifier -> identifier ∉ network.groundednets,
            network.activenets
        ))
        isempty(identifiers) && throw(ArgumentError(
            "the network has no nongrounded active nodes; provide an explicit nodelist",
        ))
        return Symbol[inverse_names[identifier] for identifier in identifiers]
    end

    length(unique(requested)) == length(requested) || throw(ArgumentError(
        "nodelist contains duplicate node names",
    ))
    for node in requested
        haskey(network.interface.net, node) || throw(ArgumentError(
            "node :$node is not present in the linearized network",
        ))
        network.interface.net[node] ∉ network.groundednets || throw(ArgumentError(
            "grounded node :$node cannot be retained in a small-signal response",
        ))
    end
    return copy(requested)
end

function _evaluate_response(
        network::LinearizedAdmittanceNetwork,
        kind::Symbol,
        requested_nodes::Vector{Symbol},
        freq_range
)
    frequencies, complex_frequencies = _frequency_axis(freq_range)
    nodes = _node_names(network, requested_nodes)
    identifiers = Int[network.interface.net[node] for node in nodes]

    if kind === :node_admittance
        response = make_y(network, network.actives, complex_frequencies, identifiers)
    elseif kind === :edge_admittance
        response = make_y(network, network.passives, complex_frequencies, identifiers)
    elseif kind === :loopgain
        node_response = make_y(network, network.actives, complex_frequencies, identifiers)
        edge_response = make_y(network, network.passives, complex_frequencies, identifiers)
        response = _loopgain_tensor(edge_response, node_response)
    else
        throw(ArgumentError("unsupported response kind :$kind"))
    end
    return response, nodes, frequencies
end

function (runner::_SmallSignalRunner)(builder::BuilderState)
    requested_nodes = if runner.node_keys === nothing
        runner.kind isa _CheckStabilitySpec ?
        _check_stability_nodes(builder, runner.kind) : runner.nodes
    else
        _resolve_node_keys(builder, runner.node_keys)
    end
    decision = _linearization_decision(builder, runner.cache)
    network, runner.cache = _linearize(builder, decision)
    response, nodes, frequencies = _evaluate_response(network, runner.kind, requested_nodes, runner.freq_range)
    canonical_nodes = runner.node_keys === nothing ? nodes : runner.nodes
    return response, canonical_nodes, frequencies
end

function _new_response_study(
        gridspace::Gridspace{BuilderState},
        trials,
        distribution,
        seed,
        confidence,
        tolerance
)
    selected_distribution = something(distribution, :normal)
    _validate_study_keywords(trials, selected_distribution, confidence, tolerance)
    snapshot = deepcopy(gridspace)
    plans = _gridspace_plans(snapshot)
    any(plan -> plan.uncertain, plans) && !_measurement_extension_loaded() &&
        throw(ArgumentError(
            "uncertain studies require Measurements.jl; load it with `using Measurements`",
        ))
    master_seed = _master_seed(seed)
    return _BuilderResponseStudy(
        snapshot,
        plans,
        master_seed,
        selected_distribution,
        fill(something(trials, 0), length(plans)),
        Float64(confidence),
        Float64(tolerance),
        master_seed ⊻ 0xd1b54a32d192ed03,
        fill(nothing, length(plans))
    )
end

function _inherited_response_study(
        gridspace::Gridspace{BuilderState},
        schema::ParametricNodeSchema,
        trials,
        distribution,
        seed,
        confidence,
        tolerance
)
    study = schema._study
    study isa _BuilderResponseStudy || throw(ArgumentError(
        "the supplied ParametricNodeSchema does not contain replayable study provenance",
    ))
    _same_study_value(study.gridspace, gridspace) || throw(ArgumentError(
        "the supplied ParametricNodeSchema belongs to a different BuilderState Gridspace",
    ))
    trials === nothing || all(value -> value == trials, study.trials) ||
        throw(ArgumentError(
            "trials conflicts with the trial count carried by the node schema",
        ))
    distribution === nothing || distribution == study.distribution ||
        throw(ArgumentError(
            "distribution conflicts with the distribution carried by the node schema",
        ))
    seed === nothing || UInt64(seed) == study.master_seed ||
        throw(ArgumentError(
            "seed conflicts with the seed carried by the node schema",
        ))
    confidence == study.confidence || throw(ArgumentError(
        "confidence conflicts with the value carried by the node schema",
    ))
    tolerance == study.tolerance || throw(ArgumentError(
        "tolerance conflicts with the value carried by the node schema",
    ))
    return study
end

function _case_samples(
        runner::_SmallSignalRunner,
        plan::_ValuePlan,
        rng,
        distribution,
        first_response,
        first_nodes,
        first_frequencies,
        trials,
        case_index,
        case_seed
)
    if plan.zero_uncertainty
        return _repeat_samples(first_response, trials)
    end

    samples = Any[first_response]
    for trial_index in 2:trials
        response, nodes, frequencies = try
            runner(plan.sample(rng, distribution))
        catch error
            throw(_trial_error(error, plan, case_index, trial_index, case_seed))
        end
        nodes == first_nodes || throw(_trial_error(
            ArgumentError("the ordered node schema differs across trials"),
            plan,
            case_index,
            trial_index,
            case_seed
        ))
        frequencies == first_frequencies || throw(_trial_error(
            ArgumentError("frequency vectors differ across trials"),
            plan,
            case_index,
            trial_index,
            case_seed
        ))
        size(response) == size(first_response) || throw(_trial_error(
            DimensionMismatch("frequency-response dimensions differ across trials"),
            plan,
            case_index,
            trial_index,
            case_seed
        ))
        push!(samples, response)
    end
    return samples
end

function _validate_response_trial(
        response,
        nodes,
        frequencies,
        first_response,
        first_nodes,
        first_frequencies
)
    nodes == first_nodes || throw(ArgumentError(
        "the ordered node schema differs across trials",
    ))
    frequencies == first_frequencies || throw(ArgumentError(
        "frequency vectors differ across trials",
    ))
    size(response) == size(first_response) || throw(DimensionMismatch(
        "frequency-response dimensions differ across trials",
    ))
    return nothing
end

function _constant_statistics(value::Real, trials::Int)
    converted = float(value)
    return (
        mean = converted,
        std = zero(converted),
        min = converted,
        q05 = converted,
        median = converted,
        q95 = converted,
        max = converted,
        n = trials
    )
end

function _aggregate_constant_response(response, trials::Int)
    first_value = response[firstindex(response)]
    result_type = typeof(complex(
        _make_measurement(real(first_value), 0.0),
        _make_measurement(imag(first_value), 0.0)
    ))
    averaged = Array{result_type}(undef, size(response))
    real_statistics = Array{Any}(undef, size(response))
    imag_statistics = Array{Any}(undef, size(response))
    for index in eachindex(response)
        value = response[index]
        real_statistic = _constant_statistics(real(value), trials)
        imag_statistic = _constant_statistics(imag(value), trials)
        averaged[index] = complex(
            _make_measurement(real_statistic.mean, 0.0),
            _make_measurement(imag_statistic.mean, 0.0)
        )
        real_statistics[index] = real_statistic
        imag_statistics[index] = imag_statistic
    end
    return averaged, (real = real_statistics, imag = imag_statistics)
end

function _aggregate_stacked_response(samples::AbstractArray{<:Complex, 4})
    response_dimensions = size(samples)[1:3]
    first_values = @view samples[1, 1, 1, :]
    first_output, first_statistics = _aggregate_numbers(first_values)
    averaged = Array{typeof(first_output)}(undef, response_dimensions)
    real_statistics = Array{Any}(undef, response_dimensions)
    imag_statistics = Array{Any}(undef, response_dimensions)
    for index in CartesianIndices(response_dimensions)
        values = @view samples[index[1], index[2], index[3], :]
        output, statistics = index == first(CartesianIndices(response_dimensions)) ?
                             (first_output, first_statistics) : _aggregate_numbers(values)
        averaged[index] = output
        real_statistics[index] = statistics.real
        imag_statistics[index] = statistics.imag
    end
    return averaged, (real = real_statistics, imag = imag_statistics)
end

function _fill_response_trials!(
        storage,
        runner,
        plan,
        rng,
        distribution,
        first_response,
        first_nodes,
        first_frequencies,
        trials,
        case_index,
        case_seed
)
    storage[:, :, :, 1] = first_response
    if plan.zero_uncertainty
        for trial_index in 2:trials
            storage[:, :, :, trial_index] = first_response
        end
        return storage
    end
    for trial_index in 2:trials
        response, nodes, frequencies = try
            runner(plan.sample(rng, distribution))
        catch error
            throw(_trial_error(error, plan, case_index, trial_index, case_seed))
        end
        try
            _validate_response_trial(
                response,
                nodes,
                frequencies,
                first_response,
                first_nodes,
                first_frequencies
            )
        catch error
            throw(_trial_error(error, plan, case_index, trial_index, case_seed))
        end
        storage[:, :, :, trial_index] = response
    end
    return storage
end

function _aggregate_response_trials(
        runner,
        plan,
        rng,
        distribution,
        first_response,
        first_nodes,
        first_frequencies,
        trials,
        case_index,
        case_seed;
        return_samples
)
    if plan.zero_uncertainty && !return_samples
        averaged, statistics = _aggregate_constant_response(first_response, trials)
        return averaged, statistics, nothing
    end

    dimensions = (size(first_response)..., trials)
    if return_samples
        storage = Array{ComplexF64}(undef, dimensions)
        _fill_response_trials!(
            storage,
            runner,
            plan,
            rng,
            distribution,
            first_response,
            first_nodes,
            first_frequencies,
            trials,
            case_index,
            case_seed
        )
        averaged, statistics = _aggregate_stacked_response(storage)
        return averaged, statistics, storage
    end

    return mktemp() do _, io
        storage = Mmap.mmap(io, Array{ComplexF64, 4}, dimensions; grow = true)
        try
            _fill_response_trials!(
                storage,
                runner,
                plan,
                rng,
                distribution,
                first_response,
                first_nodes,
                first_frequencies,
                trials,
                case_index,
                case_seed
            )
            averaged, statistics = _aggregate_stacked_response(storage)
            return averaged, statistics, nothing
        finally
            Mmap.sync!(storage)
        end
    end
end

function _run_builder_response(
        gridspace::Gridspace{BuilderState},
        kind;
        nodelist = Symbol[],
        freq_range = (1.0, 1.0e3, 1000),
        trials::Union{Nothing, Int} = nothing,
        distribution::Union{Nothing, Symbol} = nothing,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false
)
    schema = nodelist isa ParametricNodeSchema ? nodelist : nothing
    study = schema === nothing ?
            _new_response_study(
        gridspace, trials, distribution, seed, confidence, tolerance
    ) :
            _inherited_response_study(
        gridspace, schema, trials, distribution, seed, confidence, tolerance
    )

    length(study.plans) == length(gridspace) || throw(DimensionMismatch(
        "the supplied node schema and Gridspace have different case counts",
    ))
    requested_schema = schema === nothing ? Symbol.(collect(nodelist)) : Symbol[]
    cases = FrequencyResponseCase[]
    case_nodes = Vector{Symbol}[]
    case_coordinates = Vector{Pair{Tuple, Any}}[]
    common_frequencies = nothing
    result_kind = kind isa Symbol ? kind : :check_stability_loopgain
    runner = _SmallSignalRunner(nothing, kind, requested_schema, nothing, freq_range)

    for (case_index, plan) in enumerate(study.plans)
        nodes_for_case = schema === nothing ? requested_schema : schema[case_index]
        runner.nodes = nodes_for_case
        runner.node_keys = schema === nothing ? nothing : study.node_keys[case_index]
        schema !== nothing && runner.node_keys === nothing &&
            throw(ArgumentError(
                "the supplied ParametricNodeSchema lacks stable node provenance for case $case_index",
            ))
        case_seed = _case_seed(study.master_seed, case_index)
        rng = Random.Xoshiro(case_seed)
        first_builder = try
            plan.sample(rng, study.distribution)
        catch error
            throw(_trial_error(error, plan, case_index, 1, case_seed))
        end
        first_response, nodes, frequencies = try
            runner(first_builder)
        catch error
            throw(_trial_error(error, plan, case_index, 1, case_seed))
        end
        if schema === nothing
            runner.nodes = nodes
            runner.node_keys = _node_keys(first_builder, nodes)
            study.node_keys[case_index] = runner.node_keys
        end
        common_frequencies === nothing && (common_frequencies = frequencies)
        frequencies == common_frequencies || throw(ArgumentError(
            "frequency vectors differ across deterministic cases",
        ))

        if !plan.uncertain
            study.trials[case_index] = 1
            output = (response = first_response, frequencies = frequencies, nodes = nodes)
            provenance = _BuilderResponseReplay(
                plan,
                kind,
                nodes,
                runner.node_keys,
                freq_range,
                case_seed,
                study.distribution,
                1,
                true,
                study.study_id
            )
            push!(cases,
                FrequencyResponseCase(
                    plan.coordinates,
                    1,
                    case_seed,
                    study.distribution,
                    result_kind,
                    output,
                    first_response,
                    frequencies,
                    nodes,
                    nothing,
                    nothing,
                    :deterministic,
                    provenance
                ))
        else
            requested_trials = study.trials[case_index]
            requested_trials == 0 && (requested_trials = _dkw_trials(
                2 * length(first_response), study.confidence, study.tolerance
            ))
            study.trials[case_index] = requested_trials
            averaged, statistics, retained = _aggregate_response_trials(
                runner,
                plan,
                rng,
                study.distribution,
                first_response,
                nodes,
                frequencies,
                requested_trials,
                case_index,
                case_seed;
                return_samples
            )
            output = (response = averaged, frequencies = frequencies, nodes = nodes)
            provenance = _BuilderResponseReplay(
                plan,
                kind,
                nodes,
                runner.node_keys,
                freq_range,
                case_seed,
                study.distribution,
                requested_trials,
                plan.zero_uncertainty,
                study.study_id
            )
            push!(cases,
                FrequencyResponseCase(
                    plan.coordinates,
                    requested_trials,
                    case_seed,
                    study.distribution,
                    result_kind,
                    output,
                    averaged,
                    frequencies,
                    nodes,
                    statistics,
                    retained,
                    :monte_carlo,
                    provenance
                ))
        end
        push!(case_nodes, nodes)
        push!(case_coordinates, plan.coordinates)
    end

    response = ParametricFrequencyResponse(result_kind, cases, study.study_id)
    node_schema = ParametricNodeSchema(
        case_nodes, case_coordinates, study.study_id, study
    )
    return response, node_schema, something(common_frequencies, Float64[])
end

function _check_stability_response(
        gridspace::Gridspace{BuilderState},
        element::Symbol;
        direction::Symbol = :dc,
        kwargs...
)
    return _run_builder_response(
        gridspace,
        _CheckStabilitySpec(element, direction);
        kwargs...
    )
end

function _singleton_builder_space(builder::BuilderState)
    return Gridspace{BuilderState}(
        identity,
        (_axis(deepcopy(builder)),),
        (:builder,)
    )
end

"""
    make_y_node(builder::BuilderState; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000))
    make_y_node(gridspace::Gridspace{BuilderState}; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000), uq_kwargs...)

Evaluate the active-element nodal admittance on a logarithmic frequency grid.

# Arguments

- `builder`: One constructed power system.
- `gridspace`: A deterministic or uncertain collection of constructed systems.
- `nodelist`: Ordered retained nodes. An empty vector selects active nodes automatically.
- `freq_range`: Minimum frequency \\[Hz\\], maximum frequency \\[Hz\\], and point count.
- `uq_kwargs`: Monte Carlo controls `trials`, `distribution`, `seed`, `confidence`,
  `tolerance`, and `return_samples`.

# Returns

- For `BuilderState`, `(Ynode, nodes, omega)`, where `Ynode` has layout
  `n × n × nf` and `omega` is in \\[rad/s\\].
- For `Gridspace`, `(responses, node_schema, omega)`, where `responses` is a
  `ParametricFrequencyResponse` and `node_schema` preserves case and trial order.

# Notes

Converter, source, topology, option, or other active changes repeat the operating
point and linearization. Passive-only changes may reuse the active linearization.

# Errors

Throws an error when frequencies are invalid, requested nodes are absent or
grounded, or a stochastic trial changes its ordered node schema.
"""
function make_y_node(
        builder::BuilderState;
        nodelist = Symbol[],
        freq_range = (1.0, 1.0e3, 1000)
)
    network = convert(builder, LinearizedAdmittanceNetwork)
    return _evaluate_response(
        network, :node_admittance, Symbol.(collect(nodelist)), freq_range
    )
end

"""
    make_y_edge(builder::BuilderState; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000))
    make_y_edge(gridspace::Gridspace{BuilderState}; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000), uq_kwargs...)

Evaluate the passive-network nodal admittance on a logarithmic frequency grid.

# Arguments

- `builder`: One constructed power system.
- `gridspace`: A deterministic or uncertain collection of constructed systems.
- `nodelist`: Ordered retained nodes or a `ParametricNodeSchema` returned by
  `make_y_node`.
- `freq_range`: Minimum frequency \\[Hz\\], maximum frequency \\[Hz\\], and point count.
- `uq_kwargs`: Monte Carlo controls `trials`, `distribution`, `seed`, `confidence`,
  `tolerance`, and `return_samples`.

# Returns

- For `BuilderState`, `(Yedge, nodes, omega)`, where `Yedge` has layout
  `n × n × nf` and `omega` is in \\[rad/s\\].
- For `Gridspace`, `(responses, node_schema, omega)`.

# Notes

Passing the `ParametricNodeSchema` from `make_y_node` replays the same sampled
builder states and proves aligned trial provenance for loop-gain composition.

# Errors

Throws an error when a supplied schema belongs to another study or conflicts
with explicit Monte Carlo settings.
"""
function make_y_edge(
        builder::BuilderState;
        nodelist = Symbol[],
        freq_range = (1.0, 1.0e3, 1000)
)
    network = convert(builder, LinearizedAdmittanceNetwork)
    return _evaluate_response(
        network, :edge_admittance, Symbol.(collect(nodelist)), freq_range
    )
end

"""
    make_loopgain(builder::BuilderState; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000))
    make_loopgain(gridspace::Gridspace{BuilderState}; nodelist=Symbol[], freq_range=(1.0, 1.0e3, 1000), uq_kwargs...)
    make_loopgain(Yedge, Ynode; pairing=:auto, trials=nothing, seed=nothing)

Evaluate or compose the return-ratio matrix at every frequency and trial.

# Arguments

- `builder`: One constructed power system.
- `gridspace`: A deterministic or uncertain collection of constructed systems.
- `nodelist`: Ordered retained nodes.
- `freq_range`: Minimum frequency \\[Hz\\], maximum frequency \\[Hz\\], and point count.
- `Yedge`: Passive-network admittance response.
- `Ynode`: Active-element admittance response.
- `pairing`: `:auto`, `:aligned`, or `:independent` trial pairing.
- `trials`: Optional output trial count for independent pairing.
- `seed`: Optional local random seed.

# Returns

- `(loopgain, nodes, omega)` for builder inputs.
- A `ParametricFrequencyResponse` for parametric response inputs.
- An `n × n × nf` numeric tensor for deterministic tensor inputs.

# Notes

For every numeric frequency slice, the implemented return ratio is:

```math
L(j\\omega) = Y_{edge}(j\\omega)^{-1}Y_{node}(j\\omega).
```

The fused Gridspace overload constructs `Yedge` and `Ynode` from one sampled
`BuilderState` and one active-device linearization per trial.

# Errors

`pairing=:auto` rejects uncertain inputs without proven shared provenance.
"""
function make_loopgain(
        builder::BuilderState;
        nodelist = Symbol[],
        freq_range = (1.0, 1.0e3, 1000)
)
    network = convert(builder, LinearizedAdmittanceNetwork)
    return _evaluate_response(
        network, :loopgain, Symbol.(collect(nodelist)), freq_range
    )
end

function make_y_node(gridspace::Gridspace{BuilderState}; kwargs...)
    _run_builder_response(gridspace, :node_admittance; kwargs...)
end
function make_y_edge(gridspace::Gridspace{BuilderState}; kwargs...)
    _run_builder_response(gridspace, :edge_admittance; kwargs...)
end
function make_loopgain(gridspace::Gridspace{BuilderState}; kwargs...)
    _run_builder_response(gridspace, :loopgain; kwargs...)
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

function _replay_response(replay::_BuilderResponseReplay)
    runner = _SmallSignalRunner(
        nothing,
        replay.kind,
        replay.nodes,
        replay.node_keys,
        replay.freq_range
    )
    rng = Random.Xoshiro(replay.seed)
    first_response, nodes, frequencies = runner(
        replay.plan.sample(rng, replay.distribution),
    )
    samples = replay.zero_uncertainty ?
              _repeat_samples(first_response, replay.trials) :
              _case_samples(
        runner,
        replay.plan,
        rng,
        replay.distribution,
        first_response,
        nodes,
        frequencies,
        replay.trials,
        1,
        replay.seed
    )
    return samples
end

function _replay_response(replay::_ImpedanceReplay)
    runner = _ParametricImpedanceRunner(nothing, replay.keywords)
    rng = Random.Xoshiro(replay.seed)
    first_response, _ = runner(replay.plan.sample(rng, replay.distribution))
    replay.zero_uncertainty && return _repeat_samples(first_response, replay.trials)
    samples = Any[first_response]
    for _ in 2:replay.trials
        response, _ = runner(replay.plan.sample(rng, replay.distribution))
        push!(samples, response)
    end
    return samples
end

function _replay_response(replay::_EmpiricalResponseReplay)
    return [copy(selectdim(replay.samples, 4, index)) for index in axes(replay.samples, 4)]
end

function _replay_response(replay::_CallbackResponseReplay)
    return [replay.sampler(Random.Xoshiro(_case_seed(replay.seed, index)), index)
            for index in 1:replay.trials]
end

function _replay_response(replay::_DerivedResponseReplay)
    left_samples = _frequency_response_samples(replay.left)
    right_samples = _frequency_response_samples(replay.right)
    left_indices, right_indices = _paired_indices(
        length(left_samples),
        length(right_samples),
        replay.pairing,
        replay.seed,
        replay.trials
    )
    return [_loopgain_tensor(left_samples[left_index], right_samples[right_index])
            for (left_index, right_index) in zip(left_indices, right_indices)]
end

function _frequency_response_samples(case::FrequencyResponseCase)
    if case.samples !== nothing
        return [copy(selectdim(case.samples, 4, index)) for index in axes(case.samples, 4)]
    elseif case.uncertainty_source === :deterministic
        return Any[ComplexF64.(case.response)]
    elseif case._provenance !== nothing
        return _replay_response(case._provenance)
    end
    return Any[case.response]
end

function _paired_indices(left_count, right_count, pairing, seed, trials)
    if pairing === :aligned
        left_count == right_count || throw(DimensionMismatch(
            "aligned responses must contain the same number of trials",
        ))
        trials === nothing || trials == left_count ||
            throw(ArgumentError(
                "trials must match the retained trial count when pairing=:aligned",
            ))
        return collect(1:left_count), collect(1:right_count)
    elseif pairing === :independent
        count = something(trials, max(left_count, right_count))
        count > 0 || throw(ArgumentError("trials must be positive"))
        rng = Random.Xoshiro(seed)
        return rand(rng, 1:left_count, count), rand(rng, 1:right_count, count)
    end
    throw(ArgumentError("unsupported pairing :$pairing"))
end

function _compose_response_case(
        left,
        right,
        pairing,
        seed;
        trials = nothing,
        shared::Bool = false
)
    left.frequencies == right.frequencies || throw(ArgumentError(
        "frequency vectors differ between the two responses",
    ))
    left.nodes == right.nodes || throw(ArgumentError(
        "ordered node schemas differ between the two responses",
    ))
    size(left.response) == size(right.response) || throw(DimensionMismatch(
        "response dimensions differ between the two responses",
    ))

    left_samples = _frequency_response_samples(left)
    right_samples = _frequency_response_samples(right)
    left_indices, right_indices = _paired_indices(
        length(left_samples), length(right_samples), pairing, seed, trials
    )
    samples = [_loopgain_tensor(left_samples[left_index], right_samples[right_index])
               for (left_index, right_index) in zip(left_indices, right_indices)]
    uncertain = length(samples) > 1 || left.uncertainty_source != :deterministic ||
                right.uncertainty_source != :deterministic
    if uncertain
        averaged, statistics = _aggregate_impedance(samples)
    else
        averaged, statistics = first(samples), nothing
    end
    coordinates = shared ? copy(left.coordinates) :
                  vcat(left.coordinates, right.coordinates)
    source = if !uncertain
        :deterministic
    elseif pairing === :independent
        :monte_carlo
    elseif left.uncertainty_source === right.uncertainty_source
        left.uncertainty_source
    else
        :monte_carlo
    end
    output = (
        response = averaged,
        frequencies = left.frequencies,
        nodes = left.nodes
    )
    study_id = seed ⊻ 0x8cb92baa98f273e1
    provenance = _DerivedResponseReplay(
        left,
        right,
        pairing,
        seed,
        length(samples),
        study_id
    )
    return FrequencyResponseCase(
        coordinates,
        length(samples),
        seed,
        left.distribution === right.distribution ? left.distribution : :mixed,
        :loopgain,
        output,
        averaged,
        left.frequencies,
        left.nodes,
        statistics,
        nothing,
        source,
        provenance
    )
end

function make_loopgain(
        edge::ParametricFrequencyResponse,
        node::ParametricFrequencyResponse;
        pairing::Symbol = :auto,
        trials::Union{Nothing, Int} = nothing,
        seed = nothing
)
    edge.kind in (:edge_admittance, :external) || throw(ArgumentError(
        "the first response must be an edge admittance or an external response",
    ))
    node.kind in (:node_admittance, :external) || throw(ArgumentError(
        "the second response must be a node admittance or an external response",
    ))
    shared = edge._study_id != 0 && edge._study_id == node._study_id
    if pairing === :auto
        if shared ||
           all(case -> case.uncertainty_source === :deterministic, edge.cases) &&
           all(case -> case.uncertainty_source === :deterministic, node.cases)
            pairing = :aligned
        else
            throw(ArgumentError(
                "uncertain responses do not have proven shared trials; pass " *
                "pairing=:aligned or pairing=:independent",
            ))
        end
    end
    pairing in (:aligned, :independent) || throw(ArgumentError(
        "pairing must be :auto, :aligned, or :independent",
    ))

    pairs = if shared
        length(edge) == length(node) || throw(DimensionMismatch(
            "shared studies have different deterministic case counts",
        ))
        collect(zip(edge.cases, node.cases))
    else
        collect(Iterators.product(edge.cases, node.cases))
    end
    master_seed = _master_seed(seed)
    cases = FrequencyResponseCase[]
    for (case_index, (edge_case, node_case)) in enumerate(pairs)
        edge_case.coordinates == node_case.coordinates || !shared ||
            throw(ArgumentError(
                "shared response coordinates differ at case $case_index",
            ))
        composition_seed = shared && pairing === :aligned ?
                           something(edge_case.seed, _case_seed(master_seed, case_index)) :
                           _case_seed(master_seed, case_index)
        push!(cases,
            _compose_response_case(
                edge_case,
                node_case,
                pairing,
                composition_seed;
                trials,
                shared
            ))
    end
    study_id = shared && pairing === :aligned ? edge._study_id :
               master_seed ⊻ 0x94d049bb133111eb
    return ParametricFrequencyResponse(:loopgain, cases, study_id)
end

function Base.Broadcast.broadcasted(
        ::typeof(inv), response::ParametricFrequencyResponse
)
    _InverseFrequencyResponse(response)
end
function Base.Broadcast.broadcasted(
        ::typeof(*), inverse::_InverseFrequencyResponse, node::ParametricFrequencyResponse
)
    make_loopgain(inverse.response, node)
end

"""
    sampled_frequency_response(samples, omega; nodes, trial_ids, coordinates, kind=:external)
    sampled_frequency_response(sampler, omega; trials, seed, nodes, coordinates, kind=:external)

Wrap exact whole-trial matrix frequency responses for parametric analysis.

# Arguments

- `samples`: Numeric tensor with layout `n × n × nf × ntrials`.
- `sampler`: Callback `(rng, trial_index)` returning one numeric `n × n × nf`
  response.
- `omega`: Finite, positive, strictly increasing angular frequencies \\[rad/s\\].
- `trials`: Positive callback trial count.
- `seed`: Optional local callback seed.
- `nodes`: Ordered response node names.
- `trial_ids`: One integer identifier per trial slice.
- `coordinates`: Optional deterministic-case coordinates.
- `kind`: Response classification used by later composition.

# Returns

- A singleton `ParametricFrequencyResponse` labeled `:empirical_samples` when
  more than one trial is supplied.

# Notes

One trial index selects the complete matrix at every frequency. This preserves
cross-entry and cross-frequency empirical dependence.

# Errors

Throws an error for nonsquare responses, inconsistent frequency dimensions,
invalid frequency vectors, or callback outputs whose dimensions change.
"""
function sampled_frequency_response(
        samples::AbstractArray{<:Number, 4},
        frequencies;
        nodes = Symbol[],
        trial_ids = collect(axes(samples, 4)),
        coordinates = Pair{Tuple, Any}[],
        kind::Symbol = :external
)
    validated_frequencies = _validate_frequencies(frequencies)
    size(samples, 1) == size(samples, 2) || throw(DimensionMismatch(
        "sampled frequency-response matrices must be square",
    ))
    size(samples, 3) == length(validated_frequencies) || throw(DimensionMismatch(
        "the sample frequency dimension does not match the frequency vector",
    ))
    length(trial_ids) == size(samples, 4) || throw(DimensionMismatch(
        "trial_ids must contain one identifier per sample",
    ))
    selected_nodes = isempty(nodes) ?
                     [Symbol("node", index) for index in axes(samples, 1)] : Symbol.(nodes)
    length(selected_nodes) == size(samples, 1) || throw(DimensionMismatch(
        "the node count does not match the response order",
    ))
    numeric_samples = ComplexF64.(samples)
    sample_list = [copy(selectdim(numeric_samples, 4, index)) for index in axes(samples, 4)]
    if length(sample_list) == 1
        response, statistics, source = first(sample_list), nothing, :deterministic
    else
        _measurement_extension_loaded() || throw(ArgumentError(
            "uncertain response aggregation requires Measurements.jl",
        ))
        response, statistics = _aggregate_impedance(sample_list)
        source = :empirical_samples
    end
    study_id = rand(Random.RandomDevice(), UInt64)
    replay = _EmpiricalResponseReplay(numeric_samples, Int.(trial_ids), study_id)
    output = (
        response = response,
        frequencies = validated_frequencies,
        nodes = selected_nodes
    )
    case = FrequencyResponseCase(
        collect(coordinates),
        length(sample_list),
        nothing,
        :empirical,
        kind,
        output,
        response,
        validated_frequencies,
        selected_nodes,
        statistics,
        numeric_samples,
        source,
        replay
    )
    return ParametricFrequencyResponse(kind, [case], study_id)
end

function sampled_frequency_response(
        sampler::F,
        frequencies;
        trials::Int,
        seed = nothing,
        nodes = Symbol[],
        coordinates = Pair{Tuple, Any}[],
        kind::Symbol = :external
) where {F <: Function}
    trials > 0 || throw(ArgumentError("trials must be positive"))
    validated_frequencies = _validate_frequencies(frequencies)
    master_seed = _master_seed(seed)
    replay_sampler = deepcopy(sampler)
    evaluation_sampler = deepcopy(replay_sampler)
    samples = Any[]
    for trial_index in 1:trials
        raw = evaluation_sampler(
            Random.Xoshiro(_case_seed(master_seed, trial_index)),
            trial_index
        )
        push!(samples, _response_tensor(raw, validated_frequencies))
    end
    dimensions = size(first(samples))
    all(sample -> size(sample) == dimensions, samples) || throw(DimensionMismatch(
        "callback response dimensions differ across trials",
    ))
    stacked = _stack_impedance_samples(samples)
    result = sampled_frequency_response(
        stacked,
        validated_frequencies;
        nodes,
        coordinates,
        kind
    )
    replay = _CallbackResponseReplay(
        let frozen_sampler = replay_sampler
            (rng, index) -> _response_tensor(
                frozen_sampler(rng, index),
                validated_frequencies
            )
        end,
        master_seed,
        trials,
        result._study_id
    )
    case = only(result)
    replacement = FrequencyResponseCase(
        case.coordinates,
        case.trials,
        master_seed,
        case.distribution,
        case.kind,
        case.output,
        case.response,
        case.frequencies,
        case.nodes,
        case.statistics,
        case.samples,
        case.uncertainty_source,
        replay
    )
    return ParametricFrequencyResponse(kind, [replacement], result._study_id)
end

function make_loopgain(
        edge::AbstractArray{<:Number, 3},
        node::AbstractArray{<:Number, 3};
        pairing::Symbol = :auto,
        kwargs...
)
    pairing in (:auto, :aligned) || throw(ArgumentError(
        "deterministic tensors only support pairing=:auto or pairing=:aligned",
    ))
    isempty(kwargs) || throw(ArgumentError(
        "trials and seed are only meaningful for uncertain response collections",
    ))
    _loopgain_tensor(edge, node)
end
