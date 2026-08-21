import Random
import Statistics

export nyquistplot, bodeplot, passivity, small_gain, EVD, unstable_frequency

const _OwnedProblem = Union{
    PowerFlowProblem,
    LinearizationProblem,
    PowerImpedanceProblem,
    StabilityProblem,
}

function _scalar_statistics(values::AbstractVector{<:Real})
    sorted = sort(collect(values))
    standard_deviation = length(values) == 1 || all(isequal(first(values)), values) ?
        zero(float(first(values))) : Statistics.std(values; corrected=true)
    return (
        mean=Statistics.mean(values),
        std=standard_deviation,
        min=first(sorted),
        q05=Statistics.quantile(sorted, 0.05),
        median=Statistics.median(sorted),
        q95=Statistics.quantile(sorted, 0.95),
        max=last(sorted),
        n=length(values),
    )
end

function _dkw_trials(output_entries::Integer, confidence::Real, tolerance::Real)
    output_entries > 0 || return 1
    return ceil(Int, log(2 * output_entries / (1 - confidence)) / (2 * tolerance^2))
end

_master_seed(seed::Nothing) = rand(Random.RandomDevice(), UInt64)
_master_seed(seed::Integer) = UInt64(seed)
_case_seed(master::UInt64, index::Integer) =
    master ⊻ (UInt64(index) * 0x9e3779b97f4a7c15)

_formulation_backend(formulation) = getproperty(formulation, :backend)

function _require_backend(formulation, backend::Type)
    _formulation_backend(formulation) === backend || throw(ArgumentError(
        "unsupported backend $(_formulation_backend(formulation)) for $(typeof(formulation)); " *
        "expected $backend",
    ))
    return formulation
end

function _linearized_model(network::NetworkBuilder.NetworkModel, options)
    return network, nothing
end

function _linearized_model(network::NetworkBuilder.NetworkState, options)
    result = compute(
        LinearizationProblem(network),
        AdmittanceLinearization();
        options,
    )
    return result.network_model, result
end

function _frequency_response(
    problem::PowerImpedanceProblem,
    formulation::AbstractPowerImpedanceFormulation,
    kind::Symbol,
    options,
)
    _require_backend(formulation, PIACDC)
    model, linearization = _linearized_model(problem.network, options)
    response, nodes, frequencies = NetworkBuilder._evaluate_response(
        model,
        kind,
        problem.nodes,
        problem.frequency_range,
    )
    return FrequencyResponseResult(
        formulation,
        kind,
        response,
        frequencies,
        nodes,
        model,
        (
            linearization=linearization,
            eliminated_elements=copy(problem.eliminated_elements),
        ),
    )
end

function compute(
    problem::PowerImpedanceProblem,
    formulation::NodeAdmittance;
    options::NamedTuple=(;),
)
    return _frequency_response(problem, formulation, :node_admittance, options)
end

function compute(
    problem::PowerImpedanceProblem,
    formulation::EdgeAdmittance;
    options::NamedTuple=(;),
)
    return _frequency_response(problem, formulation, :edge_admittance, options)
end

function compute(
    problem::PowerImpedanceProblem,
    formulation::LoopGain;
    options::NamedTuple=(;),
)
    return _frequency_response(problem, formulation, :loopgain, options)
end

function compute(
    problem::PowerImpedanceProblem,
    formulation::NodalImpedance;
    options::NamedTuple=(;),
)
    _require_backend(formulation, PIACDC)
    model, linearization = _linearized_model(problem.network, options)
    response, frequencies = determine_impedance(
        model;
        nets=problem.nodes,
        elim_elements=problem.eliminated_elements,
        freq_range=problem.frequency_range,
    )
    return FrequencyResponseResult(
        formulation,
        :nodal_impedance,
        response,
        frequencies,
        copy(problem.nodes),
        model,
        (linearization=linearization,),
    )
end

function determine_impedance(
    network::NetworkBuilder.NetworkState;
    nets::AbstractVector{Symbol},
    elim_elements::AbstractVector{Symbol}=Symbol[],
    freq_range=(0.001, 10_000.0, 2_000),
)
    result = compute(
        PowerImpedanceProblem(
            network;
            nodes=nets,
            eliminated_elements=elim_elements,
            frequency_range=freq_range,
        ),
        NodalImpedance(),
    )
    return result.response, result.frequencies
end

function PowerFlowProblem(space::Gridspace{<:NetworkBuilder.NetworkState})
    return Gridspace{PowerFlowProblem}(
        network -> PowerFlowProblem(network),
        (space,),
        (:network,),
    )
end

function LinearizationProblem(
    space::Gridspace{<:NetworkBuilder.NetworkState};
    powerflow=nothing,
)
    return Gridspace{LinearizationProblem}(
        network -> LinearizationProblem(network, powerflow),
        (space,),
        (:network,),
    )
end

function PowerImpedanceProblem(
    space::Gridspace{<:NetworkBuilder.NetworkState};
    nodes=Symbol[],
    eliminated_elements=Symbol[],
    frequency_range=(0.001, 10_000.0, 2_000),
)
    target = network -> PowerImpedanceProblem(
        network;
        nodes,
        eliminated_elements,
        frequency_range,
    )
    return Gridspace{PowerImpedanceProblem}(target, (space,), (:network,))
end

function _stability_input(response::FrequencyResponseResult)
    return response.response, Float64.(real.(response.frequencies)), response.nodes
end

function _stability_input(response)
    throw(ArgumentError(
        "StabilityProblem requires a completed FrequencyResponseResult; got $(typeof(response))",
    ))
end

function compute(
    problem::StabilityProblem{<:FrequencyResponseResult},
    formulation::GeneralizedNyquist;
    options::NamedTuple=(;),
)
    _require_backend(formulation, PIACDC)
    response, frequencies, _ = _stability_input(problem.response)
    loci_samples, _, _ = _matched_eigenloci([response])
    eigenloci = first(loci_samples)
    metrics = _nyquist_trial(
        eigenloci,
        frequencies;
        order_maxima=get(options, :order_maxima, formulation.order_maxima),
    )
    output = (
        frequencies=frequencies,
        eigenloci=eigenloci,
        encirclements=(
            clockwise=metrics.clockwise,
            counterclockwise=metrics.counterclockwise,
            net=metrics.net,
        ),
        assessment=metrics.assessment,
        margins=metrics.margins,
        unstable_frequencies=metrics.unstable_frequencies,
    )
    return StabilityResult(formulation, :nyquist, output, (;))
end

function compute(
    problem::StabilityProblem{<:FrequencyResponseResult},
    formulation::BodeAnalysis;
    options::NamedTuple=(;),
)
    _require_backend(formulation, PIACDC)
    response, frequencies, nodes = _stability_input(problem.response)
    magnitude, phase = _aligned_bode_samples([response])
    output = (
        frequencies=frequencies,
        magnitude_db=first(magnitude),
        phase_deg=first(phase),
        nodes=nodes,
    )
    return StabilityResult(formulation, :bode, output, (;))
end

function compute(
    problem::StabilityProblem{<:FrequencyResponseResult},
    formulation::PassivityAnalysis;
    options::NamedTuple=(;),
)
    _require_backend(formulation, PIACDC)
    response, frequencies, _ = _stability_input(problem.response)
    indices = [
        minimum(real.(eigvals(
            response[:, :, index] + adjoint(response[:, :, index]),
        ))) for index in axes(response, 3)
    ]
    minimum_index = argmin(indices)
    output = (
        frequencies=frequencies,
        index=indices,
        probability_by_frequency=Float64.(indices .>= 0),
        probability_complete_scan=all(>=(0), indices) ? 1.0 : 0.0,
        minimum=(value=indices[minimum_index], frequency=frequencies[minimum_index] / 2pi),
    )
    return StabilityResult(formulation, :passivity, output, (;))
end

function compute(
    problem::StabilityProblem{<:Tuple},
    formulation::SmallGainAnalysis;
    options::NamedTuple=(;),
)
    _require_backend(formulation, PIACDC)
    length(problem.response) == 2 || throw(ArgumentError(
        "SmallGainAnalysis requires exactly two FrequencyResponseResult values",
    ))
    first_result, second_result = problem.response
    first_result isa FrequencyResponseResult && second_result isa FrequencyResponseResult ||
        throw(ArgumentError("SmallGainAnalysis requires completed frequency responses"))
    first_response, first_frequencies, _ = _stability_input(first_result)
    second_response, second_frequencies, _ = _stability_input(second_result)
    first_frequencies == second_frequencies || throw(ArgumentError(
        "small-gain response frequencies differ",
    ))
    gains = _small_gain_trial(first_response, second_response)
    peak_index = argmax(gains.product_gain)
    output = merge(gains, (
        frequencies=first_frequencies,
        probability_by_frequency=Float64.(gains.product_gain .< 1),
        probability_complete_scan=all(<(1), gains.product_gain) ? 1.0 : 0.0,
        peak=(
            value=gains.product_gain[peak_index],
            index=peak_index,
            frequency=first_frequencies[peak_index] / 2pi,
        ),
    ))
    return StabilityResult(formulation, :small_gain, output, (;))
end

function compute(
    problem::StabilityProblem{<:FrequencyResponseResult},
    formulation::EigenvalueAnalysis;
    options::NamedTuple=(;),
)
    _require_backend(formulation, PIACDC)
    response, frequencies, _ = _stability_input(problem.response)
    fmin = Float64(get(options, :fmin, formulation.fmin))
    fmax = Float64(get(options, :fmax, formulation.fmax))
    determinant = Bool(get(options, :determinant, formulation.determinant))
    trial = _evd_trial(response, frequencies, fmin, fmax)
    output = merge(trial, (
        frequencies=frequencies,
        determinant_index=determinant ? trial.determinant_index : nothing,
        fmin=fmin,
        fmax=fmax,
    ))
    return StabilityResult(formulation, :eigenvalue, output, (;))
end

function compute(
    problem::StabilityProblem{<:FrequencyResponseResult},
    formulation::UnstableFrequencyAnalysis;
    options::NamedTuple=(;),
)
    _require_backend(formulation, PIACDC)
    response, frequencies, _ = _stability_input(problem.response)
    loci = _trajectory_eigenvalues(response)
    order_maxima = Int(get(options, :order_maxima, formulation.order_maxima))
    analyses = [
        _unstable_frequency_analysis(loci[:, mode], frequencies; order_maxima)
        for mode in axes(loci, 2)
    ]
    detected_frequencies = reduce(
        vcat,
        getproperty.(analyses, :detected_frequencies);
        init=Float64[],
    )
    output = (
        frequencies=frequencies,
        eigenloci=loci,
        complementary_sensitivity=[
            analysis.complementary_sensitivity for analysis in analyses
        ],
        magnitude_db=[analysis.magnitude_db for analysis in analyses],
        phase_deg=[analysis.phase_deg for analysis in analyses],
        detected_indices=[analysis.detected_indices for analysis in analyses],
        detected_frequencies=detected_frequencies,
        summary=(
            detected=!isempty(detected_frequencies),
            count=length(detected_frequencies),
            median=isempty(detected_frequencies) ? nothing :
                Statistics.median(detected_frequencies),
        ),
    )
    return StabilityResult(formulation, :unstable_frequency, output, (;))
end

function preprocess(
    result::FrequencyResponseResult,
    ::AbstractPowerImpedanceFormulation;
    options::NamedTuple=(;),
)
    return StabilityProblem(result)
end

function preprocess(
    result::ParametricResult{<:FrequencyResponseResult},
    ::AbstractPowerImpedanceFormulation;
    options::NamedTuple=(;),
)
    responses = Grid(result.values)
    space = Gridspace{StabilityProblem}(StabilityProblem, (responses,), (:response,))
    return ParametricProblem(space, (
        checkpoint_space=result.space,
        checkpoint_details=result.details,
    ))
end

function preprocess(
    result::MonteCarloResult{<:FrequencyResponseResult},
    ::AbstractPowerImpedanceFormulation;
    options::NamedTuple=(;),
)
    return StabilityProblem(result)
end

function _typed_results(values::Vector{Any})
    isempty(values) && throw(ArgumentError("calculation produced no successful results"))
    result_type = typeof(first(values))
    all(value -> value isa result_type, values) || throw(ArgumentError(
        "calculation returned inconsistent primitive result types",
    ))
    return result_type[values...]
end

function _failure_record(configuration, trial, seed, stage, error)
    return (
        configuration=configuration,
        trial=trial,
        seed=seed,
        stage=stage,
        exception=typeof(error),
        message=sprint(showerror, error),
    )
end

function _calculation_manifest(method, options, manifests)
    return (
        version=1,
        package=:PowerImpedance,
        formulation=typeof(method.inner),
        backend=method.backend,
        options=options,
        configurations=manifests,
    )
end

function _deterministic_compute(problem, method, options, result_constructor)
    method.backend === PIACDC || throw(ArgumentError(
        "unsupported higher-order backend $(method.backend)",
    ))
    values = Any[]
    manifests = Any[]
    failures = Any[]
    for configuration in configurations(problem.space)
        manifest = configuration_manifest(configuration)
        try
            primitive_problem = materialize(configuration)
            push!(values, compute(primitive_problem, method.inner; options))
            push!(manifests, manifest)
        catch error
            method.failure_policy === :error && rethrow()
            push!(failures, _failure_record(manifest, nothing, nothing, :compute, error))
        end
    end
    typed = _typed_results(values)
    details = (
        manifest=_calculation_manifest(method, options, manifests),
        failures=(items=failures,),
    )
    return result_constructor(method, typed, manifests, details)
end

function compute(
    problem::ParametricProblem{S},
    method::Combinatorial;
    options::NamedTuple=(;),
) where {T<:_OwnedProblem,S<:Gridspace{T}}
    has_uncertainty(problem.space) && throw(ArgumentError(
        "Combinatorial accepts deterministic Gridspace axes; use LinearError or MonteCarlo",
    ))
    merged_options = merge(problem.options, options)
    return _deterministic_compute(problem, method, merged_options, ParametricResult)
end

function compute(
    problem::ParametricProblem{S},
    method::LinearError;
    options::NamedTuple=(;),
) where {T<:PowerImpedanceProblem,S<:Gridspace{T}}
    merged_options = merge(problem.options, options)
    method.backend === PIACDC || throw(ArgumentError(
        "unsupported higher-order backend $(method.backend)",
    ))
    applicable(_linear_error_configuration, first(configurations(problem.space)),
        method.inner, merged_options) || throw(ArgumentError(
        "LinearError frequency-response propagation requires Measurements.jl",
    ))
    values = Any[]
    manifests = Any[]
    failures = Any[]
    for configuration in configurations(problem.space)
        manifest = configuration_manifest(configuration)
        try
            push!(values, _linear_error_configuration(
                configuration,
                method.inner,
                merged_options,
            ))
            push!(manifests, manifest)
        catch error
            method.failure_policy === :error && rethrow()
            push!(failures, _failure_record(manifest, nothing, nothing, :linear_error, error))
        end
    end
    typed = _typed_results(values)
    details = (
        manifest=_calculation_manifest(method, merged_options, manifests),
        failures=(items=failures,),
        propagation=:first_order,
    )
    return LinearErrorResult(method, typed, manifests, details)
end

function _linear_error_configuration end

function _statistics_tree(values::AbstractVector)
    first_value = first(values)
    if first_value isa Real && all(value -> value isa Real, values)
        return _scalar_statistics(Real[values...])
    elseif first_value isa Complex && all(value -> value isa Complex, values)
        return (
            real=_scalar_statistics(real.(Complex[values...])),
            imag=_scalar_statistics(imag.(Complex[values...])),
        )
    elseif first_value isa NamedTuple
        names = keys(first_value)
        all(value -> keys(value) == names, values) || throw(ArgumentError(
            "named result schemas differ across trials",
        ))
        return NamedTuple{names}(map(
            name -> _statistics_tree([getproperty(value, name) for value in values]),
            names,
        ))
    elseif first_value isa AbstractArray
        all(value -> axes(value) == axes(first_value), values) || throw(ArgumentError(
            "array dimensions differ across trials",
        ))
        mapped = map(eachindex(first_value)) do index
            _statistics_tree([value[index] for value in values])
        end
        return reshape(mapped, size(first_value))
    elseif first_value isa AbstractDict
        names = collect(keys(first_value))
        all(value -> Set(keys(value)) == Set(names), values) || throw(ArgumentError(
            "dictionary schemas differ across trials",
        ))
        return Dict(
            name => _statistics_tree([value[name] for value in values])
            for name in names
        )
    elseif first_value isa Tuple
        all(value -> length(value) == length(first_value), values) || throw(ArgumentError(
            "tuple schemas differ across trials",
        ))
        return ntuple(
            index -> _statistics_tree([value[index] for value in values]),
            length(first_value),
        )
    end
    return all(isequal(first_value), values) ? nothing :
        (categorical=Dict(value => count(isequal(value), values) / length(values)
            for value in unique(values)), n=length(values))
end

function _primitive_statistics(values::AbstractVector{<:PowerFlowResult})
    return (
        result=_statistics_tree([value.result for value in values]),
        data=_statistics_tree([value.data for value in values]),
        operating_point=_statistics_tree([value.operating_point.setpoints for value in values]),
        bus_measurements=_powerflow_bus_measurements(values),
    )
end

function _measurement_tree(values::AbstractVector)
    first_value = first(values)
    if first_value isa Real && all(value -> value isa Real, values)
        statistics = _scalar_statistics(Real[values...])
        return NetworkBuilder._make_measurement(statistics.mean, statistics.std)
    elseif first_value isa Complex && all(value -> value isa Complex, values)
        return complex(
            _measurement_tree(real.(Complex[values...])),
            _measurement_tree(imag.(Complex[values...])),
        )
    elseif first_value isa AbstractDict
        names = collect(keys(first_value))
        all(value -> Set(keys(value)) == Set(names), values) || throw(ArgumentError(
            "power-flow bus schemas differ across local Monte Carlo trials",
        ))
        return Dict(
            name => _measurement_tree([value[name] for value in values])
            for name in names
        )
    elseif first_value isa AbstractArray
        all(value -> axes(value) == axes(first_value), values) || throw(ArgumentError(
            "power-flow bus arrays differ across local Monte Carlo trials",
        ))
        mapped = map(eachindex(first_value)) do index
            _measurement_tree([value[index] for value in values])
        end
        return reshape(mapped, size(first_value))
    elseif first_value isa NamedTuple
        names = keys(first_value)
        return NamedTuple{names}(map(
            name -> _measurement_tree([getproperty(value, name) for value in values]),
            names,
        ))
    elseif first_value isa Tuple
        return ntuple(
            index -> _measurement_tree([value[index] for value in values]),
            length(first_value),
        )
    end
    all(isequal(first_value), values) || throw(ArgumentError(
        "nonnumeric power-flow bus outputs differ across local Monte Carlo trials",
    ))
    return first_value
end

function _powerflow_bus_measurements(values::AbstractVector{<:PowerFlowResult})
    NetworkBuilder._measurement_extension_loaded() || return nothing
    all(value -> value.result isa AbstractDict, values) || return nothing
    solutions = [get(value.result, "solution", nothing) for value in values]
    all(solution -> solution isa AbstractDict, solutions) || return nothing
    reconstructed = Dict{String,Any}()
    for bus_kind in ("bus", "busdc")
        all(solution -> haskey(solution, bus_kind), solutions) || continue
        reconstructed[bus_kind] = _measurement_tree([
            solution[bus_kind] for solution in solutions
        ])
    end
    return reconstructed
end

function _primitive_statistics(values::AbstractVector{<:FrequencyResponseResult})
    return (
        response=_statistics_tree([value.response for value in values]),
        frequencies=first(values).frequencies,
        nodes=first(values).nodes,
        kind=first(values).kind,
    )
end

function _primitive_statistics(values::AbstractVector{<:StabilityResult})
    return (
        output=_statistics_tree([value.output for value in values]),
        analysis=first(values).analysis,
    )
end

function _trial_count(method::MonteCarlo)
    return something(
        method.trials,
        _dkw_trials(1, method.confidence, method.tolerance),
    )
end

function compute(
    problem::ParametricProblem{S},
    method::MonteCarlo;
    options::NamedTuple=(;),
) where {T<:Union{PowerFlowProblem,PowerImpedanceProblem,StabilityProblem},S<:Gridspace{T}}
    method.backend === PIACDC || throw(ArgumentError(
        "unsupported higher-order backend $(method.backend)",
    ))
    merged_options = merge(problem.options, options)
    master_seed = _master_seed(method.seed)
    trials = _trial_count(method)
    all_values = Any[]
    successful_space = Any[]
    failures = Any[]
    groups = Any[]
    grouped_statistics = Any[]
    grouped_plot_data = Any[]
    for (case_index, configuration) in enumerate(configurations(problem.space))
        manifest = configuration_manifest(configuration)
        first_index = length(all_values) + 1
        case_values = Any[]
        for trial in 1:trials
            seed = _case_seed(master_seed, (case_index - 1) * trials + trial)
            rng = Random.Xoshiro(seed)
            try
                primitive_problem = rand(rng, configuration; distribution=method.distribution)
                value = compute(primitive_problem, method.inner; options=merged_options)
                push!(case_values, value)
                push!(all_values, value)
                push!(successful_space, (configuration=manifest, trial=trial, seed=seed))
            catch error
                method.failure_policy === :error && rethrow()
                push!(failures, _failure_record(manifest, trial, seed, :compute, error))
            end
        end
        isempty(case_values) && continue
        typed_case = _typed_results(case_values)
        push!(grouped_statistics, _primitive_statistics(typed_case))
        push!(grouped_plot_data, typed_case)
        push!(groups, (
            configuration=manifest,
            range=first_index:length(all_values),
            n=length(case_values),
        ))
    end
    typed_values = _typed_results(all_values)
    result_type = eltype(typed_values)
    stats = (n=length(typed_values), groups=grouped_statistics)
    details = (
        manifest=_calculation_manifest(method, merged_options, successful_space),
        groups=(items=groups,),
        failures=(items=failures,),
        samples=method.return_samples ? (values=typed_values, coordinates=successful_space) : nothing,
        plot_data=(values=grouped_plot_data,),
        replay=(
            version=1,
            source_space=problem.space,
            master_seed=master_seed,
            case_seeds=[_case_seed(master_seed, index) for index in 1:length(groups)],
            trial_counts=getproperty.(groups, :n),
            distribution=method.distribution,
            study_id=hash((master_seed, typeof(method.inner))),
        ),
        coupling=result_type <: PowerFlowResult ? (
            method=:local_monte_carlo,
            solver_inputs=:numeric_realizations,
            reconstructed=:bus_measurements,
        ) : nothing,
    )
    return MonteCarloResult{result_type}(method, stats, successful_space, details)
end

function compute(
    problem::StabilityProblem{<:MonteCarloResult{<:FrequencyResponseResult}},
    method::MonteCarlo;
    options::NamedTuple=(;),
)
    method.backend === PIACDC || throw(ArgumentError(
        "unsupported higher-order backend $(method.backend)",
    ))
    source = problem.response
    source_groups = source.details.plot_data.values
    requested_trials = method.trials
    requested_trials === nothing || requested_trials == source.stats.n || throw(ArgumentError(
        "preprocessed stability reuses $(source.stats.n) completed response trials; " *
        "trials=$requested_trials conflicts with the checkpoint",
    ))
    grouped_values = Any[]
    grouped_statistics = Any[]
    all_values = Any[]
    failures = Any[]
    for (group_index, responses) in enumerate(source_groups)
        completed = Any[]
        for (trial_index, response) in enumerate(responses)
            try
                value = compute(StabilityProblem(response), method.inner; options)
                push!(completed, value)
                push!(all_values, value)
            catch error
                method.failure_policy === :error && rethrow()
                push!(failures, _failure_record(
                    (source_group=group_index,),
                    trial_index,
                    nothing,
                    :preprocess,
                    error,
                ))
            end
        end
        isempty(completed) && continue
        typed = _typed_results(completed)
        push!(grouped_values, typed)
        push!(grouped_statistics, _primitive_statistics(typed))
    end
    typed_values = _typed_results(all_values)
    result_type = eltype(typed_values)
    details = (
        manifest=(
            version=1,
            package=:PowerImpedance,
            source=source.details.manifest,
            formulation=typeof(method.inner),
            options=options,
        ),
        groups=source.details.groups,
        failures=(items=vcat(source.details.failures.items, failures),),
        seeds=hasproperty(source.details, :replay) ? source.details.replay : nothing,
        replay=hasproperty(source.details, :replay) ? source.details.replay : nothing,
        samples=method.return_samples ? (values=typed_values, coordinates=source.space) : nothing,
        plot_data=(values=grouped_values,),
        pairing=hasproperty(source.details, :pairing) ? source.details.pairing : nothing,
        categorical=(analysis=first(typed_values).analysis,),
    )
    stats=(n=length(typed_values), groups=grouped_statistics)
    return MonteCarloResult{result_type}(method, stats, source.space, details)
end

function _response_cube(response, frequencies)
    count = length(frequencies)
    if response isa AbstractArray{<:Number,3}
        size(response, 3) == count || throw(DimensionMismatch(
            "the response and frequency counts differ",
        ))
        size(response, 1) == size(response, 2) || throw(DimensionMismatch(
            "frequency-response matrices must be square",
        ))
        return response
    end
    response isa AbstractVector || throw(ArgumentError(
        "the response must be a vector or an n×n×nf tensor",
    ))
    length(response) == count || throw(DimensionMismatch(
        "the response and frequency counts differ",
    ))
    isempty(response) && throw(ArgumentError("the response cannot be empty"))
    if first(response) isa Number
        return reshape(ComplexF64.(response), 1, 1, count)
    end
    all(value -> value isa AbstractMatrix, response) || throw(ArgumentError(
        "vector responses must contain only numbers or only matrices",
    ))
    order = size(first(response), 1)
    all(value -> size(value) == (order, order), response) || throw(DimensionMismatch(
        "all response matrices must have the same square dimensions",
    ))
    return cat(response...; dims=3)
end

function _completed_response(response, frequencies, formulation, kind)
    cube = _response_cube(response, frequencies)
    nodes = [Symbol("node_$index") for index in axes(cube, 1)]
    return FrequencyResponseResult(
        formulation,
        kind,
        cube,
        Float64.(real.(frequencies)),
        nodes,
        nothing,
        (; source=:compatibility_entrypoint),
    )
end

function nyquistplot(
    response::FrequencyResponseResult;
    zoom=false,
    SM="no",
    title="Nyquist plot",
    indentations=Float64[],
    order_maxima::Integer=5,
    display_plot::Bool=true,
    kwargs...,
)
    SM in ("no", "PM", "GM", "VM") || throw(ArgumentError(
        "SM must be \"no\", \"PM\", \"GM\", or \"VM\"",
    ))
    completed = compute(
        StabilityProblem(response),
        GeneralizedNyquist(; order_maxima),
    )
    return plot(
        completed;
        zoom,
        title,
        indentations,
        display_plot,
        kwargs...,
    )
end

function nyquistplot(response, frequencies; kwargs...)
    completed = _completed_response(response, frequencies, LoopGain(), :loopgain)
    return nyquistplot(completed; kwargs...)
end

function bodeplot(
    response::FrequencyResponseResult;
    legend=nothing,
    plots=nothing,
    title="Bode plot",
    display_plot::Bool=true,
    kwargs...,
)
    normalized_legend = legend == [""] ? nothing : legend
    completed = compute(StabilityProblem(response), BodeAnalysis())
    return plot(
        completed;
        legend=normalized_legend,
        plots,
        title,
        display_plot,
        kwargs...,
    )
end

function bodeplot(response, frequencies; kwargs...)
    completed = _completed_response(response, frequencies, LoopGain(), :loopgain)
    return bodeplot(completed; kwargs...)
end

function passivity(
    response::FrequencyResponseResult;
    title="Passivity assessment",
    display_plot::Bool=true,
    kwargs...,
)
    completed = compute(StabilityProblem(response), PassivityAnalysis())
    plot(completed; title, display_plot, kwargs...)
    return completed.output.index
end

function passivity(response::FrequencyResponseResult, title::AbstractString; kwargs...)
    return passivity(response; title, kwargs...)
end

function passivity(response, frequencies, title::AbstractString="Passivity assessment"; kwargs...)
    completed = _completed_response(response, frequencies, NodeAdmittance(), :node_admittance)
    return passivity(completed; title, kwargs...)
end

function small_gain(
    first::FrequencyResponseResult,
    second::FrequencyResponseResult;
    title="Small-gain assessment",
    display_plot::Bool=true,
    kwargs...,
)
    completed = compute(
        StabilityProblem((first, second)),
        SmallGainAnalysis(),
    )
    plot(completed; title, display_plot, kwargs...)
    return completed.output.product_gain
end

function small_gain(
    first::FrequencyResponseResult,
    second::FrequencyResponseResult,
    title::AbstractString;
    kwargs...,
)
    return small_gain(first, second; title, kwargs...)
end

function small_gain(
    first,
    second,
    frequencies,
    title::AbstractString="Small-gain assessment";
    kwargs...,
)
    first_result = _completed_response(first, frequencies, LoopGain(), :first_gain)
    second_result = _completed_response(second, frequencies, LoopGain(), :second_gain)
    return small_gain(first_result, second_result; title, kwargs...)
end

function EVD(
    response::FrequencyResponseResult,
    fmin,
    fmax,
    determinant::Bool=false;
    title="Eigenvalue analysis",
    display_plot::Bool=true,
    kwargs...,
)
    completed = compute(
        StabilityProblem(response),
        EigenvalueAnalysis(; fmin, fmax, determinant),
    )
    plot(completed; title, display_plot, kwargs...)
    return completed.output
end

function EVD(response, frequencies, fmin, fmax, determinant::Bool=false; kwargs...)
    completed = _completed_response(response, frequencies, NodalImpedance(), :nodal_impedance)
    return EVD(completed, fmin, fmax, determinant; kwargs...)
end

function unstable_frequency(
    response::FrequencyResponseResult;
    order_maxima::Integer=5,
    title="Unstable-frequency analysis",
    display_plot::Bool=true,
    make_plot::Bool=true,
    kwargs...,
)
    completed = compute(
        StabilityProblem(response),
        UnstableFrequencyAnalysis(; order_maxima),
    )
    make_plot && plot(completed; title, display_plot, kwargs...)
    return completed.output.detected_frequencies
end

function unstable_frequency(
    locus::AbstractVector{<:Number},
    frequencies;
    order_maxima::Integer=5,
    make_plot::Bool=true,
    kwargs...,
)
    cube = reshape(ComplexF64.(locus), 1, 1, length(locus))
    completed = _completed_response(cube, frequencies, LoopGain(), :loopgain)
    return unstable_frequency(completed; order_maxima, make_plot, kwargs...)
end

function check_stability(
    builder::NetworkBuilder.NetworkState,
    element::Symbol;
    direction::Symbol=:dc,
    freq_range=(1.0, 1.0e3, 1000),
    order_maxima::Integer=5,
    title="Nyquist plot",
    display_plot::Bool=true,
    kwargs...,
)
    response, nodes, frequencies, model = NetworkBuilder._check_stability_response(
        builder,
        element;
        direction,
        freq_range,
    )
    checkpoint = FrequencyResponseResult(
        LoopGain(),
        :loopgain,
        response,
        frequencies,
        nodes,
        model,
        (; element, direction),
    )
    calculated = compute(
        StabilityProblem(checkpoint),
        GeneralizedNyquist(; order_maxima),
    )
    completed = StabilityResult(
        calculated.formulation,
        calculated.analysis,
        calculated.output,
        (; element, direction),
    )
    plot(completed; title, display_plot, kwargs...)
    return completed
end
