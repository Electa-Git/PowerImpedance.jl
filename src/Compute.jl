function _linearized_model(network::NetworkBuilder.NetworkModel)
    return network, nothing
end

function _linearized_model(network::NetworkBuilder.NetworkState)
    result = compute(
        NetworkBuilder.LinearizationProblem(network),
        NetworkBuilder.AdmittanceLinearization()
    )
    return result.network_model, result
end

function _frequency_response(problem::PowerImpedanceProblem, kind::Symbol)
    model, linearization = _linearized_model(problem.network)
    response, nodes, frequencies = NetworkBuilder._evaluate_response(
        model,
        kind,
        problem.nodes,
        problem.frequency_range
    )
    return FrequencyResponseResult(
        kind,
        response,
        frequencies,
        nodes,
        model,
        (
            linearization = linearization,
            eliminated_elements = copy(problem.eliminated_elements)
        )
    )
end

function compute(problem::PowerImpedanceProblem, ::NodeAdmittance)
    _frequency_response(problem, :node_admittance)
end

function compute(problem::PowerImpedanceProblem, ::EdgeAdmittance)
    _frequency_response(problem, :edge_admittance)
end

function compute(problem::PowerImpedanceProblem, ::LoopGain)
    _frequency_response(problem, :loopgain)
end

function compute(problem::PowerImpedanceProblem, ::NodalImpedance)
    model, linearization = _linearized_model(problem.network)
    response, frequencies = determine_impedance(
        model;
        nets = problem.nodes,
        elim_elements = problem.eliminated_elements,
        freq_range = problem.frequency_range
    )
    return FrequencyResponseResult(
        :nodal_impedance,
        response,
        frequencies,
        copy(problem.nodes),
        model,
        (linearization = linearization,)
    )
end

function determine_impedance(
        network::NetworkBuilder.NetworkState;
        nets::AbstractVector{Symbol},
        elim_elements::AbstractVector{Symbol} = Symbol[],
        freq_range = (0.001, 10_000.0, 2_000)
)
    result = compute(
        PowerImpedanceProblem(
            network;
            nodes = nets,
            eliminated_elements = elim_elements,
            frequency_range = freq_range
        ),
        NodalImpedance()
    )
    return result.response, result.frequencies
end

function _gridspace_compute(space, formulation, options)
    if formulation isa NodalImpedance
        return determine_impedance(space; options...)
    elseif formulation isa NodeAdmittance
        return first(NetworkBuilder.make_y_node(space; options...))
    elseif formulation isa EdgeAdmittance
        return first(NetworkBuilder.make_y_edge(space; options...))
    elseif formulation isa LoopGain
        return first(NetworkBuilder.make_loopgain(space; options...))
    end
    throw(ArgumentError("unsupported Gridspace formulation $(typeof(formulation))"))
end

function compute(problem::ParametricProblem, ::Combinatorial)
    plans = NetworkBuilder._gridspace_plans(deepcopy(problem.space))
    any(plan -> plan.uncertain, plans) && throw(ArgumentError(
        "Combinatorial evaluation accepts deterministic Gridspace axes only; " *
        "use UQuantProblem and MonteCarlo for uncertain axes",
    ))
    return _gridspace_compute(problem.space, problem.formulation, problem.options)
end

function compute(problem::UQuantProblem, method::MonteCarlo)
    options = merge(
        problem.options,
        (
            trials = method.trials,
            distribution = method.distribution,
            seed = method.seed,
            confidence = method.confidence,
            tolerance = method.tolerance,
            return_samples = method.return_samples
        )
    )
    return _gridspace_compute(problem.space, problem.formulation, options)
end

function _stability_input(response)
    if response isa FrequencyResponseResult
        return response.response, response.frequencies
    elseif response isa Tuple && length(response) == 2
        return response
    end
    throw(ArgumentError(
        "StabilityProblem requires a FrequencyResponseResult or (response, frequencies)",
    ))
end

_stability_input(problem::StabilityProblem) = _stability_input(problem.response)

function compute(problem::StabilityProblem, ::GeneralizedNyquist)
    if problem.response isa Union{
        NetworkBuilder.ParametricFrequencyResponse,
        NetworkBuilder.ParametricImpedance
    }
        options = problem.options
        omega = get(options, :omega, nothing)
        keywords = Base.structdiff(options, NamedTuple{(:omega,)})
        return nyquistplot(problem.response, omega; keywords...)
    end
    response, frequencies = _stability_input(problem)
    output = nyquistplot(response, frequencies; problem.options...)
    return StabilityResult(:nyquist, output, output, (;))
end

function compute(problem::StabilityProblem, ::BodeAnalysis)
    if problem.response isa Union{
        NetworkBuilder.ParametricFrequencyResponse,
        NetworkBuilder.ParametricImpedance
    }
        options = problem.options
        omega = get(options, :omega, nothing)
        keywords = Base.structdiff(options, NamedTuple{(:omega,)})
        return bodeplot(problem.response, omega; keywords...)
    end
    response, frequencies = _stability_input(problem)
    output = bodeplot(response, frequencies; problem.options...)
    return StabilityResult(:bode, output, output, (;))
end

function compute(problem::StabilityProblem, ::PassivityAnalysis)
    if problem.response isa Union{
        NetworkBuilder.ParametricFrequencyResponse,
        NetworkBuilder.ParametricImpedance
    }
        options = problem.options
        omega = get(options, :omega, nothing)
        title = get(options, :title, "Passivity assessment")
        keywords = Base.structdiff(options, NamedTuple{(:omega, :title)})
        return passivity(problem.response, omega, title; keywords...)
    end
    response, frequencies = _stability_input(problem)
    title = get(problem.options, :title, "Passivity assessment")
    output = passivity(response, frequencies, title)
    return StabilityResult(:passivity, output, output, (;))
end

function compute(problem::StabilityProblem, ::EigenvalueAnalysis)
    options = problem.options
    hasproperty(options, :fmin) || throw(ArgumentError("EigenvalueAnalysis requires fmin"))
    hasproperty(options, :fmax) || throw(ArgumentError("EigenvalueAnalysis requires fmax"))
    if problem.response isa Union{
        NetworkBuilder.ParametricFrequencyResponse,
        NetworkBuilder.ParametricImpedance
    }
        omega = get(options, :omega, nothing)
        determinant = get(options, :determinant, false)
        keywords = Base.structdiff(
            options,
            NamedTuple{(:omega, :fmin, :fmax, :determinant)}
        )
        return EVD(
            problem.response,
            omega,
            options.fmin,
            options.fmax,
            determinant;
            keywords...
        )
    end
    response, frequencies = _stability_input(problem)
    output = EVD(
        response,
        frequencies,
        options.fmin,
        options.fmax,
        get(options, :determinant, false)
    )
    return StabilityResult(:eigenvalue, output, output, (;))
end

function compute(problem::StabilityProblem, ::SmallGainAnalysis)
    responses = problem.response
    responses isa Tuple && length(responses) == 2 || throw(ArgumentError(
        "SmallGainAnalysis requires a tuple containing two frequency responses",
    ))
    if all(
        response -> response isa Union{
            NetworkBuilder.ParametricFrequencyResponse,
            NetworkBuilder.ParametricImpedance
        },
        responses)
        options = problem.options
        omega = get(options, :omega, nothing)
        title = get(
            options,
            :title,
            "Small gain theorem evaluation via SVD"
        )
        keywords = Base.structdiff(options, NamedTuple{(:omega, :title)})
        return small_gain(
            responses[1],
            responses[2],
            omega,
            title;
            keywords...
        )
    end
    first_response, first_frequencies = _stability_input(responses[1])
    second_response, second_frequencies = _stability_input(responses[2])
    first_frequencies == second_frequencies || throw(ArgumentError(
        "small-gain response frequencies differ",
    ))
    title = get(
        problem.options,
        :title,
        "Small gain theorem evaluation via SVD"
    )
    output = small_gain(
        first_response,
        second_response,
        first_frequencies,
        title
    )
    return StabilityResult(:small_gain, output, output, (;))
end

function nyquistplot(response::FrequencyResponseResult; kwargs...)
    return compute(
        StabilityProblem(response; options = (; kwargs...)),
        GeneralizedNyquist()
    ).output
end

function bodeplot(response::FrequencyResponseResult; kwargs...)
    return compute(
        StabilityProblem(response; options = (; kwargs...)),
        BodeAnalysis()
    ).output
end

function passivity(response::FrequencyResponseResult; kwargs...)
    return compute(
        StabilityProblem(response; options = (; kwargs...)),
        PassivityAnalysis()
    ).output
end

function passivity(response::FrequencyResponseResult, title::AbstractString; kwargs...)
    options = merge((; title = String(title)), (; kwargs...))
    return compute(StabilityProblem(response; options), PassivityAnalysis()).output
end

function small_gain(
        first::FrequencyResponseResult,
        second::FrequencyResponseResult;
        kwargs...
)
    return compute(
        StabilityProblem((first, second); options = (; kwargs...)),
        SmallGainAnalysis()
    ).output
end

function small_gain(
        first::FrequencyResponseResult,
        second::FrequencyResponseResult,
        title::AbstractString;
        kwargs...
)
    options = merge((; title = String(title)), (; kwargs...))
    return compute(
        StabilityProblem((first, second); options),
        SmallGainAnalysis()
    ).output
end

function EVD(
        response::FrequencyResponseResult,
        fmin,
        fmax,
        determinant::Bool = false
)
    return compute(
        StabilityProblem(response; options = (; fmin, fmax, determinant)),
        EigenvalueAnalysis()
    ).output
end
