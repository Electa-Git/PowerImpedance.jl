export make_loopgain

const _NB = NetworkBuilder

make_y_node(builder::_NB.BuilderState; kwargs...) = _NB.make_y_node(builder; kwargs...)
function make_y_node(gridspace::_NB.Gridspace{_NB.BuilderState}; kwargs...)
    _NB.make_y_node(gridspace; kwargs...)
end
make_y_edge(builder::_NB.BuilderState; kwargs...) = _NB.make_y_edge(builder; kwargs...)
function make_y_edge(gridspace::_NB.Gridspace{_NB.BuilderState}; kwargs...)
    _NB.make_y_edge(gridspace; kwargs...)
end
make_loopgain(builder::_NB.BuilderState; kwargs...) = _NB.make_loopgain(builder; kwargs...)
function make_loopgain(gridspace::_NB.Gridspace{_NB.BuilderState}; kwargs...)
    _NB.make_loopgain(gridspace; kwargs...)
end
function make_loopgain(
        edge::_NB.ParametricFrequencyResponse,
        node::_NB.ParametricFrequencyResponse;
        kwargs...
)
    _NB.make_loopgain(edge, node; kwargs...)
end
function make_loopgain(
        edge::AbstractArray{<:Number, 3},
        node::AbstractArray{<:Number, 3};
        kwargs...
)
    _NB.make_loopgain(edge, node; kwargs...)
end

function make_loopgain(
        edge::AbstractVector,
        node::AbstractVector;
        pairing::Symbol = :auto
)
    pairing in (:auto, :aligned) || throw(ArgumentError(
        "deterministic matrix vectors only support pairing=:auto or pairing=:aligned",
    ))
    length(edge) == length(node) || throw(DimensionMismatch(
        "edge and node responses must have the same frequency count",
    ))
    all(item -> item isa AbstractMatrix, edge) &&
    all(item -> item isa AbstractMatrix, node) || throw(ArgumentError(
        "edge and node responses must contain matrices",
    ))
    return [inv(edge[index]) * node[index] for index in eachindex(edge)]
end

function _as_frequency_response(result::_NB.ParametricFrequencyResponse)
    return result
end

function _as_frequency_response(result::_NB.ParametricImpedance)
    cases = _NB.FrequencyResponseCase[]
    study_id = UInt64(0)
    for source in result
        order = size(source.impedance, 1)
        nodes = [Symbol("port", index) for index in 1:order]
        frequencies = Float64.(real.(source.frequencies))
        provenance = source._provenance
        if provenance !== nothing && hasproperty(provenance, :study_id)
            study_id = getproperty(provenance, :study_id)
        end
        uncertainty_source = source.statistics === nothing ? :deterministic : :monte_carlo
        output = (
            response = source.impedance,
            frequencies = frequencies,
            nodes = nodes
        )
        push!(cases,
            _NB.FrequencyResponseCase(
                source.coordinates,
                source.trials,
                source.seed,
                source.distribution,
                :impedance,
                output,
                source.impedance,
                frequencies,
                nodes,
                source.statistics,
                source.samples,
                uncertainty_source,
                provenance
            ))
    end
    return _NB.ParametricFrequencyResponse(:impedance, cases, study_id)
end

function _validated_case_frequencies(case, supplied)
    supplied === nothing && return case.frequencies
    frequencies = _NB._validate_frequencies(supplied)
    frequencies == case.frequencies || throw(ArgumentError(
        "the supplied frequency vector differs from the response frequencies",
    ))
    return frequencies
end

function _trajectory_eigenvalues(response)
    frequency_count = size(response, 3)
    order = size(response, 1)
    loci = Matrix{ComplexF64}(undef, frequency_count, order)
    loci[1, :] = eigvals(response[:, :, 1])
    for frequency_index in 2:frequency_count
        current = eigvals(response[:, :, frequency_index])
        distances = [abs(loci[frequency_index - 1, left] - current[right])
                     for left in 1:order, right in 1:order]
        loci[frequency_index, :] = current[munkres(distances)]
    end
    return loci
end

function _match_loci(loci, reference)
    size(loci) == size(reference) || throw(DimensionMismatch(
        "eigenlocus dimensions differ from the nominal reference",
    ))
    order = size(loci, 2)
    distances = Matrix{Float64}(undef, order, order)
    for nominal_mode in 1:order, trial_mode in 1:order

        distances[nominal_mode, trial_mode] = sqrt(
            sum(abs2, reference[:, nominal_mode] .- loci[:, trial_mode]) /
            size(loci, 1),
        )
    end
    permutation = munkres(distances)
    return loci[:, permutation], permutation
end

function _matched_eigenloci(samples)
    reference_response = reduce(+, samples) ./ length(samples)
    reference = _trajectory_eigenvalues(reference_response)
    matched = Matrix{ComplexF64}[]
    permutations = Vector{Int}[]
    for response in samples
        loci, permutation = _match_loci(_trajectory_eigenvalues(response), reference)
        push!(matched, loci)
        push!(permutations, permutation)
    end
    return matched, reference, permutations
end

function _margin_records(locus, frequencies)
    magnitude = abs.(locus)
    phase = rad2deg.(angle.(locus))
    phase = [value > 0 ? value - 360 : value for value in phase]
    phase_margins = NamedTuple[]
    gain_margins = NamedTuple[]
    for index in 2:length(locus)
        if (magnitude[index - 1] - 1) * (magnitude[index] - 1) < 0
            margin = phase[index] + 180
            margin > 180 && (margin -= 360)
            push!(phase_margins, (
                margin = margin,
                frequency = frequencies[index] / (2pi)
            ))
        end
        if (phase[index - 1] + 180) * (phase[index] + 180) < 0 &&
           real(locus[index]) < 0
            push!(gain_margins, (
                margin = -20log10(magnitude[index]),
                frequency = frequencies[index] / (2pi)
            ))
        end
    end
    vector_distances = abs.(locus .+ 1)
    vector_index = argmin(vector_distances)
    vector_margin = (
        margin = 100vector_distances[vector_index],
        frequency = frequencies[vector_index] / (2pi)
    )
    return (
        phase = phase_margins,
        gain = gain_margins,
        vector = vector_margin
    )
end

function _nyquist_trial(loci, frequencies; order_maxima = 5)
    clockwise = zeros(Int, size(loci, 2))
    counterclockwise = zeros(Int, size(loci, 2))
    unstable_frequencies = Float64[]
    margins = Vector{Any}(undef, size(loci, 2))
    for mode in axes(loci, 2)
        for index in 2:size(loci, 1)
            previous = loci[index - 1, mode]
            current = loci[index, mode]
            if imag(previous) < 0 && imag(current) > 0 && real(current) < -1
                clockwise[mode] += 1
            elseif imag(previous) > 0 && imag(current) < 0 && real(previous) < -1
                counterclockwise[mode] += 1
            end
        end
        if clockwise[mode] != counterclockwise[mode]
            append!(unstable_frequencies,
                unstable_frequency(
                    loci[:, mode],
                    frequencies;
                    order_maxima,
                    make_plot = false
                ))
        end
        margins[mode] = _margin_records(loci[:, mode], frequencies)
    end
    net = sum(clockwise) - sum(counterclockwise)
    assessment = net > 0 ? :unstable_system :
                 net < 0 ? :unstable_subsystem : :stable_if_subsystems_stable
    return (;
        clockwise,
        counterclockwise,
        net,
        assessment,
        margins,
        unstable_frequencies
    )
end

function _finite_summary(values)
    finite_values = Float64[value for value in values if isfinite(value)]
    isempty(finite_values) && return (
        value = nothing,
        statistics = nothing,
        probability_infinite = 1.0,
        count = 0
    )
    statistics = _NB._scalar_statistics(finite_values)
    return (
        value = length(finite_values) == 1 ? first(finite_values) :
                _NB._make_measurement(statistics.mean, statistics.std),
        statistics,
        probability_infinite = 1 - length(finite_values) / length(values),
        count = length(finite_values)
    )
end

function _crossing_summary(records_by_trial)
    critical = [isempty(records) ? nothing :
                records[argmin(getproperty.(records, :margin))]
                for records in records_by_trial]
    margins = [record === nothing ? Inf : record.margin for record in critical]
    frequencies = [record === nothing ? Inf : record.frequency for record in critical]
    pooled = reduce(vcat, records_by_trial; init = NamedTuple[])
    return (
        margin = _finite_summary(margins),
        frequency = _finite_summary(frequencies),
        probability_detected = sum(!isnothing, critical) / length(critical),
        probability_no_crossing = sum(isnothing, critical) / length(critical),
        count = length(pooled),
        pooled_margin = isempty(pooled) ? nothing :
                        _NB._scalar_statistics(Float64.(getproperty.(pooled, :margin))),
        pooled_frequency = isempty(pooled) ? nothing :
                           _NB._scalar_statistics(Float64.(getproperty.(pooled, :frequency)))
    )
end

function _margin_summary(metrics)
    modes = length(first(metrics).margins)
    phase = Vector{Any}(undef, modes)
    gain = Vector{Any}(undef, modes)
    vector = Vector{Any}(undef, modes)
    for mode in 1:modes
        phase[mode] = _crossing_summary([metric.margins[mode].phase for metric in metrics])
        gain[mode] = _crossing_summary([metric.margins[mode].gain for metric in metrics])
        vector_values = [metric.margins[mode].vector.margin for metric in metrics]
        vector_frequencies = [metric.margins[mode].vector.frequency for metric in metrics]
        vector[mode] = (
            margin = _finite_summary(vector_values),
            frequency = _finite_summary(vector_frequencies),
            probability_detected = 1.0,
            probability_no_crossing = 0.0,
            count = length(metrics)
        )
    end
    return (; phase, gain, vector)
end

function _categorical_probabilities(values)
    count = length(values)
    labels = unique(values)
    return Dict(label => sum(==(label), values) / count for label in labels)
end

function _nyquist_plot(
        loci_samples,
        statistics,
        frequencies;
        zoom,
        title,
        indentations,
        ensemble,
        spread_points
)
    median_loci = complex.(
        getproperty.(statistics.real, :median),
        getproperty.(statistics.imag, :median)
    )
    theta = range(0, 2pi; length = 629)
    result = plot(
        cos.(theta),
        sin.(theta);
        color = :red,
        linewidth = 2,
        linestyle = :dash,
        label = :none,
        xlabel = "Real axis",
        ylabel = "Imaginary axis",
        title,
        framestyle = :box,
        legend = :topleft,
        size = (1000, 1000)
    )
    hline!(result, [0]; color = :black, linestyle = :dash, label = :none)
    vline!(result, [0]; color = :black, linestyle = :dash, label = :none)
    scatter!(result, [-1], [0];
        markercolor = :red,
        markershape = :xcross,
        markersize = 10,
        label = :none
    )
    colors = palette(:default, size(median_loci, 2))
    selected_trials = unique(round.(
        Int, range(
            1, length(loci_samples); length = min(ensemble, length(loci_samples))
        )))
    indentation_indices = Int[]
    for indentation in indentations
        first(frequencies) < indentation < last(frequencies) || continue
        push!(indentation_indices, searchsortedfirst(frequencies, indentation))
    end
    anchors = unique(round.(Int,
        range(
            1, length(frequencies); length = min(spread_points, length(frequencies))
        )))

    for mode in axes(median_loci, 2)
        for trial_index in selected_trials
            locus = copy(loci_samples[trial_index][:, mode])
            locus[indentation_indices] .= ComplexF64(NaN, NaN)
            plot!(result, real.(locus), imag.(locus);
                color = colors[mode], alpha = 0.08, linewidth = 1, label = :none
            )
        end
        locus = copy(median_loci[:, mode])
        locus[indentation_indices] .= ComplexF64(NaN, NaN)
        plot!(result, real.(locus), imag.(locus);
            color = colors[mode], linewidth = 3, label = "Lambda $mode"
        )
        plot!(result, real.(locus), -imag.(locus);
            color = colors[mode], linewidth = 2, linestyle = :dash, label = :none
        )
        for frequency_index in anchors
            real_stats = statistics.real[frequency_index, mode]
            imag_stats = statistics.imag[frequency_index, mode]
            plot!(result, [real_stats.q05, real_stats.q95],
                [imag_stats.median, imag_stats.median];
                color = colors[mode], alpha = 0.45, linewidth = 1, label = :none
            )
            plot!(result, [real_stats.median, real_stats.median],
                [imag_stats.q05, imag_stats.q95];
                color = colors[mode], alpha = 0.45, linewidth = 1, label = :none
            )
        end
    end
    if zoom == "yes"
        plot!(result; xlims = (-2.6, 0.6), ylims = (-1.6, 1.6))
    end
    return result
end

function _nyquist_case(
        case::_NB.FrequencyResponseCase,
        frequencies;
        zoom,
        title,
        indentations,
        order_maxima,
        return_samples,
        display_plot,
        ensemble,
        spread_points
)
    response_samples = _NB._frequency_response_samples(case)
    loci_samples, _, _ = _matched_eigenloci(response_samples)
    eigenloci, eigen_statistics = length(loci_samples) == 1 ?
                                  (first(loci_samples), nothing) :
                                  _NB._aggregate_impedance(loci_samples)
    metrics = [_nyquist_trial(loci, frequencies; order_maxima) for loci in loci_samples]
    assessment_probabilities = _categorical_probabilities(
        getproperty.(metrics, :assessment),
    )
    clockwise, clockwise_statistics = length(metrics) == 1 ?
                                      (first(metrics).clockwise, nothing) :
                                      _NB._aggregate_tree([metric.clockwise
                                                           for metric in metrics])
    counterclockwise, counterclockwise_statistics = length(metrics) == 1 ?
                                                    (
        first(metrics).counterclockwise, nothing) :
                                                    _NB._aggregate_tree([metric.counterclockwise
                                                                         for metric in metrics])
    net_values = getproperty.(metrics, :net)
    net, net_statistics = length(metrics) == 1 ?
                          (first(net_values), nothing) : _NB._aggregate_tree(net_values)
    margins = _margin_summary(metrics)
    unstable_records = getproperty.(metrics, :unstable_frequencies)
    unstable_values = reduce(vcat, unstable_records; init = Float64[])
    unstable_counts = length.(unstable_records)
    unstable_summary = (
        probability_detected = sum(!isempty, unstable_records) /
                               length(metrics),
        probability_not_detected = sum(isempty, unstable_records) / length(metrics),
        count = length(unstable_values),
        count_statistics = _NB._scalar_statistics(Float64.(unstable_counts)),
        count_probabilities = _categorical_probabilities(unstable_counts),
        frequencies = isempty(unstable_values) ? nothing :
                      _NB._scalar_statistics(unstable_values)
    )
    statistics = (
        eigenloci = eigen_statistics,
        clockwise = clockwise_statistics,
        counterclockwise = counterclockwise_statistics,
        net = net_statistics,
        margins
    )
    if eigen_statistics === nothing
        plot_statistics = (
            real = map(
                value -> (
                    mean = real(value), std = 0.0, min = real(value), q05 = real(value),
                    median = real(value), q95 = real(value), max = real(value), n = 1
                ),
                eigenloci),
            imag = map(
                value -> (
                    mean = imag(value), std = 0.0, min = imag(value), q05 = imag(value),
                    median = imag(value), q95 = imag(value), max = imag(value), n = 1
                ),
                eigenloci)
        )
    else
        plot_statistics = eigen_statistics
    end
    nyquist_plot = _nyquist_plot(
        loci_samples,
        plot_statistics,
        frequencies;
        zoom,
        title,
        indentations,
        ensemble,
        spread_points
    )
    display_plot && display(nyquist_plot)
    output = (
        eigenloci,
        encirclements = (; clockwise, counterclockwise, net),
        assessment_probabilities,
        margins,
        unstable_frequencies = unstable_summary
    )
    retained = return_samples ?
               (;
        eigenloci = _NB._stack_impedance_samples(loci_samples),
        metrics,
        responses = _NB._stack_impedance_samples(response_samples)
    ) : nothing
    return _NB.StabilityCase(
        case.coordinates,
        case.trials,
        case.seed,
        case.distribution,
        :nyquist,
        output,
        statistics,
        retained,
        (nyquist = nyquist_plot,),
        case.uncertainty_source
    )
end

"""
    nyquistplot(response::Union{NetworkBuilder.ParametricFrequencyResponse, NetworkBuilder.ParametricImpedance}, omega=nothing; kwargs...)
    nyquistplot(gridspace::NetworkBuilder.Gridspace{NetworkBuilder.BuilderState}; freq_range, uq_kwargs..., plot_kwargs...)

Analyze and plot matched trial eigenloci for every deterministic case.

# Arguments

- `response`: Parametric loop-gain or impedance responses.
- `gridspace`: Constructed deterministic or uncertain power systems.
- `omega`: Optional angular-frequency vector \\[rad/s\\] that must equal the stored vector.
- `freq_range`: Minimum frequency \\[Hz\\], maximum frequency \\[Hz\\], and point count.
- `return_samples`: Retain response, eigenlocus, crossing, and encirclement records.
- `display_plot`: Display constructed plots when `true`.

# Returns

- A `NetworkBuilder.ParametricStability` whose cases contain matched eigenlocus
  statistics, conditional assessment probabilities, encirclements, stability
  margins, unstable-frequency summaries, and plot objects.

# Notes

A zero net encirclement is reported as `:stable_if_subsystems_stable`; it is not
an unconditional stability claim without open-loop right-half-plane pole data.
"""
function nyquistplot(
        source::Union{_NB.ParametricFrequencyResponse, _NB.ParametricImpedance},
        omega = nothing;
        zoom::String = "",
        SM::String = "no",
        title::String = "Nyquist plot",
        indentations::Vector{Float64} = Float64[],
        order_maxima::Int = 5,
        return_samples::Bool = false,
        display_plot::Bool = true,
        ensemble::Int = 50,
        spread_points::Int = 12
)
    SM in ("no", "PM", "GM", "VM") || throw(ArgumentError(
        "SM must be \"no\", \"PM\", \"GM\", or \"VM\"",
    ))
    response = _as_frequency_response(source)
    cases = _NB.StabilityCase[]
    for (case_index, case) in enumerate(response)
        frequencies = _validated_case_frequencies(case, omega)
        case_title = length(response) == 1 ? title : "$title — case $case_index"
        push!(cases,
            _nyquist_case(
                case,
                frequencies;
                zoom,
                title = case_title,
                indentations,
                order_maxima,
                return_samples,
                display_plot,
                ensemble,
                spread_points
            ))
    end
    return _NB.ParametricStability(:nyquist, cases)
end

function nyquistplot(
        gridspace::_NB.Gridspace{_NB.BuilderState};
        nodelist = Symbol[],
        freq_range = (1.0, 1.0e3, 1000),
        trials::Union{Nothing, Int} = nothing,
        distribution::Union{Nothing, Symbol} = nothing,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false,
        kwargs...
)
    response, _, frequencies = _NB.make_loopgain(
        gridspace;
        nodelist,
        freq_range,
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples
    )
    return nyquistplot(
        response,
        frequencies;
        return_samples,
        kwargs...
    )
end

function _bode_phase(response)
    phase = rad2deg.(angle.(response))
    for row in axes(phase, 1), column in axes(phase, 2)

        unwrap!(@view(phase[row, column, :]), 360)
    end
    return phase
end

function _aligned_bode_samples(samples)
    magnitude_samples = [20 .* log10.(max.(abs.(sample), eps(Float64)))
                         for sample in samples]
    nominal_response = reduce(+, samples) ./ length(samples)
    reference_phase = _bode_phase(nominal_response)
    phase_samples = Array{Float64, 3}[]
    for sample in samples
        phase = _bode_phase(sample)
        for row in axes(phase, 1), column in axes(phase, 2)

            branch = round(Int,
                (phase[row, column, 1] - reference_phase[row, column, 1]) / 360
            )
            phase[row, column, :] .-= 360branch
        end
        push!(phase_samples, phase)
    end
    return magnitude_samples, phase_samples
end

function _bode_label(legend, index, channel_count)
    legend == [""] && return ""
    if legend isa AbstractArray
        length(legend) == channel_count || throw(ArgumentError(
            "the Bode legend must contain one label per response channel",
        ))
        return string(legend[index])
    end
    channel_count == 1 || throw(ArgumentError(
        "a scalar Bode legend is only valid for a single-channel response",
    ))
    return string(legend)
end

function _bode_plots(
        magnitude_samples,
        phase_samples,
        magnitude_statistics,
        phase_statistics,
        frequencies;
        legend,
        plots,
        ensemble
)
    rows, columns = size(first(magnitude_samples))[1:2]
    channel_count = rows * columns
    generated = if isnothing(plots)
        [plot(layout = (2, 1)) for _ in 1:channel_count]
    elseif plots isa AbstractVector
        length(plots) == channel_count || throw(DimensionMismatch(
            "the supplied Bode plot collection does not match the response channels",
        ))
        plots
    elseif channel_count == 1
        [plots]
    else
        throw(DimensionMismatch(
            "a MIMO Bode response requires one supplied plot per channel",
        ))
    end

    selected_trials = unique(round.(Int,
        range(
            1,
            length(magnitude_samples);
            length = min(ensemble, length(magnitude_samples))
        )))
    frequency_hz = frequencies ./ (2pi)
    for row in 1:rows, column in 1:columns

        index = (row - 1) * columns + column
        magnitude_plot = generated[index][1]
        phase_plot = generated[index][2]
        for trial_index in selected_trials
            plot!(
                magnitude_plot,
                frequency_hz,
                magnitude_samples[trial_index][row, column, :];
                color = :steelblue,
                alpha = 0.08,
                linewidth = 1,
                label = :none
            )
            plot!(
                phase_plot,
                frequency_hz,
                phase_samples[trial_index][row, column, :];
                color = :darkorange,
                alpha = 0.08,
                linewidth = 1,
                label = :none
            )
        end

        if magnitude_statistics === nothing
            magnitude_median = first(magnitude_samples)[row, column, :]
            magnitude_ribbon = nothing
            phase_median = first(phase_samples)[row, column, :]
            phase_ribbon = nothing
        else
            magnitude_channel = magnitude_statistics[row, column, :]
            magnitude_median = getproperty.(magnitude_channel, :median)
            magnitude_ribbon = (
                magnitude_median .- getproperty.(magnitude_channel, :q05),
                getproperty.(magnitude_channel, :q95) .- magnitude_median
            )
            phase_channel = phase_statistics[row, column, :]
            phase_median = getproperty.(phase_channel, :median)
            phase_ribbon = (
                phase_median .- getproperty.(phase_channel, :q05),
                getproperty.(phase_channel, :q95) .- phase_median
            )
        end
        label = _bode_label(legend, index, channel_count)
        plot!(
            magnitude_plot,
            frequency_hz,
            magnitude_median;
            ribbon = magnitude_ribbon,
            fillalpha = 0.18,
            color = :steelblue,
            linewidth = 3,
            label = isempty(label) ? :none : label,
            legend = isempty(label) ? :none : _BODE_LEGEND_POSITION,
            xaxis = :log10,
            ylabel = "Magnitude [dB]",
            framestyle = :box,
            minorgrid = true
        )
        plot!(
            phase_plot,
            frequency_hz,
            phase_median;
            ribbon = phase_ribbon,
            fillalpha = 0.18,
            color = :darkorange,
            linewidth = 3,
            label = :none,
            legend = :none,
            xaxis = :log10,
            xlabel = "Frequency [Hz]",
            ylabel = "Phase [deg]",
            framestyle = :box,
            minorgrid = true
        )
        plot!(magnitude_plot; xlims = extrema(frequency_hz))
        plot!(phase_plot; xlims = extrema(frequency_hz), yticks = -720:90:720)
    end
    return generated
end

"""
    bodeplot(response::Union{NetworkBuilder.ParametricFrequencyResponse, NetworkBuilder.ParametricImpedance}, omega=nothing; kwargs...)

Aggregate and plot trial-wise Bode magnitude and phase for every matrix channel.

# Arguments

- `response`: Parametric matrix frequency responses.
- `omega`: Optional angular-frequency vector \\[rad/s\\].
- `legend`: One label per matrix channel, or one scalar label for SISO data.
- `plots`: Optional existing plot object or channel plot collection.
- `return_samples`: Retain magnitude \\[dB\\] and phase \\[deg\\] trial tensors.
- `display_plot`: Display constructed plots when `true`.
- `ensemble`: Maximum number of low-opacity trial trajectories.

# Returns

- A `NetworkBuilder.ParametricStability` with median responses, q05–q95
  statistics, optional samples, and one two-panel plot per channel.

# Notes

Phase is unwrapped within each trial and aligned to the nominal response before
statistics are calculated.
"""
function bodeplot(
        source::Union{_NB.ParametricFrequencyResponse, _NB.ParametricImpedance},
        omega = nothing;
        legend = [""],
        plots = nothing,
        return_samples::Bool = false,
        display_plot::Bool = true,
        ensemble::Int = 50
)
    ensemble > 0 || throw(ArgumentError("ensemble must be positive"))
    response = _as_frequency_response(source)
    cases = _NB.StabilityCase[]
    for case in response
        frequencies = _validated_case_frequencies(case, omega)
        samples = _NB._frequency_response_samples(case)
        magnitude_samples, phase_samples = _aligned_bode_samples(samples)
        if length(samples) == 1
            magnitude, magnitude_statistics = first(magnitude_samples), nothing
            phase, phase_statistics = first(phase_samples), nothing
        else
            magnitude, magnitude_statistics = _NB._aggregate_tree(magnitude_samples)
            phase, phase_statistics = _NB._aggregate_tree(phase_samples)
        end
        generated_plots = _bode_plots(
            magnitude_samples,
            phase_samples,
            magnitude_statistics,
            phase_statistics,
            frequencies;
            legend,
            plots,
            ensemble
        )
        display_plot && foreach(display, generated_plots)
        output = (; magnitude_db = magnitude, phase_deg = phase)
        statistics = (; magnitude_db = magnitude_statistics, phase_deg = phase_statistics)
        retained = return_samples ?
                   (;
            magnitude_db = _NB._stack_impedance_samples(magnitude_samples),
            phase_deg = _NB._stack_impedance_samples(phase_samples)
        ) : nothing
        push!(cases,
            _NB.StabilityCase(
                case.coordinates,
                case.trials,
                case.seed,
                case.distribution,
                :bode,
                output,
                statistics,
                retained,
                generated_plots,
                case.uncertainty_source
            ))
    end
    return _NB.ParametricStability(:bode, cases)
end

function _small_gain_trial(first_response, second_response)
    frequency_count = size(first_response, 3)
    first_gain = Vector{Float64}(undef, frequency_count)
    second_gain = similar(first_gain)
    product_gain = similar(first_gain)
    for index in 1:frequency_count
        first_matrix = first_response[:, :, index]
        second_matrix = second_response[:, :, index]
        first_gain[index] = maximum(svdvals(first_matrix))
        second_gain[index] = maximum(svdvals(second_matrix))
        product_gain[index] = maximum(svdvals(first_matrix * second_matrix))
    end
    return (; first_gain, second_gain, product_gain)
end

function _response_case_pairs(first, second, pairing)
    shared = first._study_id != 0 && first._study_id == second._study_id
    if pairing === :auto
        if shared ||
           all(case -> case.uncertainty_source === :deterministic, first.cases) &&
           all(case -> case.uncertainty_source === :deterministic, second.cases)
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
        length(first) == length(second) || throw(DimensionMismatch(
            "shared studies have different deterministic case counts",
        ))
        for case_index in eachindex(first.cases)
            first[case_index].coordinates == second[case_index].coordinates ||
                throw(ArgumentError(
                    "shared response coordinates differ at case $case_index",
                ))
        end
        collect(zip(first.cases, second.cases))
    else
        collect(Iterators.product(first.cases, second.cases))
    end
    return pairs, pairing, shared
end

"""
    small_gain(first_response, second_response, omega=nothing, title="Small gain theorem evaluation via SVD"; pairing=:auto, kwargs...)

Evaluate the small-gain condition jointly for every paired numeric trial.

# Arguments

- `first_response`: First parametric matrix response.
- `second_response`: Second parametric matrix response.
- `omega`: Optional angular-frequency vector \\[rad/s\\].
- `title`: Plot title.
- `pairing`: `:auto`, `:aligned`, or `:independent` trial policy.
- `trials`: Optional trial count for independent pairing.
- `seed`: Optional local random seed for independent pairing.
- `return_samples`: Retain all trial-level singular-value records.
- `display_plot`: Display the constructed plot when `true`.

# Returns

- A `NetworkBuilder.ParametricStability` containing singular-value statistics,
  frequency-wise satisfaction probabilities, whole-scan probability, and peak
  index and frequency summaries.

# Notes

For each trial and frequency, the evaluated product condition is:

```math
\\sigma_{max}(G_1(j\\omega)G_2(j\\omega)) < 1.
```

# Errors

`pairing=:auto` rejects uncertain responses without proven shared provenance.
"""
function small_gain(
        first_source::Union{_NB.ParametricFrequencyResponse, _NB.ParametricImpedance},
        second_source::Union{_NB.ParametricFrequencyResponse, _NB.ParametricImpedance},
        omega = nothing,
        title::String = "Small gain theorem evaluation via SVD";
        pairing::Symbol = :auto,
        trials::Union{Nothing, Int} = nothing,
        seed = nothing,
        return_samples::Bool = false,
        display_plot::Bool = true
)
    first_response = _as_frequency_response(first_source)
    second_response = _as_frequency_response(second_source)
    pairs, selected_pairing, shared = _response_case_pairs(
        first_response, second_response, pairing
    )
    master_seed = _NB._master_seed(seed)
    cases = _NB.StabilityCase[]
    for (case_index, (first_case, second_case)) in enumerate(pairs)
        frequencies = _validated_case_frequencies(first_case, omega)
        frequencies == second_case.frequencies || throw(ArgumentError(
            "small-gain response frequencies differ",
        ))
        first_samples = _NB._frequency_response_samples(first_case)
        second_samples = _NB._frequency_response_samples(second_case)
        first_indices, second_indices = _NB._paired_indices(
            length(first_samples),
            length(second_samples),
            selected_pairing,
            _NB._case_seed(master_seed, case_index),
            trials
        )
        trial_outputs = [_small_gain_trial(first_samples[left], second_samples[right])
                         for (left, right) in zip(first_indices, second_indices)]
        if length(trial_outputs) == 1
            output_values, statistics = first(trial_outputs), nothing
        else
            output_values, statistics = _NB._aggregate_tree(trial_outputs)
        end
        product_samples = getproperty.(trial_outputs, :product_gain)
        probability_by_frequency = [sum(sample[index] < 1 for sample in product_samples) /
                                    length(product_samples)
                                    for index in eachindex(first(product_samples))]
        probability_complete_scan = sum(all(<(1), sample) for sample in product_samples) /
                                    length(product_samples)
        peaks = maximum.(product_samples)
        peak_indices = argmax.(product_samples)
        peak_frequencies = [frequencies[argmax(sample)] / (2pi)
                            for sample in product_samples]
        peak_summary = length(peaks) == 1 ?
                       (
            value = first(peaks),
            index = first(peak_indices),
            frequency = first(peak_frequencies)
        ) :
                       (
            value = _NB._aggregate_numbers(peaks)[1],
            index = _categorical_probabilities(peak_indices),
            frequency = _NB._aggregate_numbers(peak_frequencies)[1]
        )
        output = merge(output_values,
            (;
                probability_by_frequency,
                probability_complete_scan,
                peak = peak_summary
            ))
        frequency_hz = frequencies ./ (2pi)
        first_median = statistics === nothing ? first(trial_outputs).first_gain :
                       getproperty.(statistics.first_gain, :median)
        second_median = statistics === nothing ? first(trial_outputs).second_gain :
                        getproperty.(statistics.second_gain, :median)
        product_median = statistics === nothing ? first(product_samples) :
                         getproperty.(statistics.product_gain, :median)
        plot_object = plot(
            frequency_hz,
            product_median;
            xaxis = :log10,
            yaxis = :log10,
            linewidth = 3,
            color = :black,
            label = "max(sigma(G1*G2))",
            xlabel = "Frequency [Hz]",
            ylabel = "Singular values",
            title,
            framestyle = :box
        )
        plot!(plot_object, frequency_hz, 1 ./ first_median;
            linewidth = 2, linestyle = :dash, color = :blue,
            label = "1/max(sigma(G1))")
        plot!(plot_object, frequency_hz, second_median;
            linewidth = 2, linestyle = :dash, color = :red,
            label = "max(sigma(G2))")
        hline!(plot_object, [1]; linestyle = :dash, color = :green, label = :none)
        display_plot && display(plot_object)
        retained = return_samples ? trial_outputs : nothing
        uncertainty_source = if length(trial_outputs) == 1
            :deterministic
        elseif selected_pairing === :independent
            :monte_carlo
        elseif first_case.uncertainty_source === second_case.uncertainty_source
            first_case.uncertainty_source
        else
            :monte_carlo
        end
        push!(cases,
            _NB.StabilityCase(
                shared ? first_case.coordinates :
                vcat(first_case.coordinates, second_case.coordinates),
                length(trial_outputs),
                _NB._case_seed(master_seed, case_index),
                first_case.distribution === second_case.distribution ?
                first_case.distribution : :mixed,
                :small_gain,
                output,
                statistics,
                retained,
                (small_gain = plot_object,),
                uncertainty_source
            ))
    end
    return _NB.ParametricStability(:small_gain, cases)
end

"""
    passivity(response::Union{NetworkBuilder.ParametricFrequencyResponse, NetworkBuilder.ParametricImpedance}, omega=nothing, title="Passivity assessment"; kwargs...)

Evaluate the existing passivity index independently for every numeric trial.

# Arguments

- `response`: Parametric matrix frequency responses.
- `omega`: Optional angular-frequency vector \\[rad/s\\].
- `title`: Plot title.
- `return_samples`: Retain each trial's passivity-index vector.
- `display_plot`: Display the constructed plot when `true`.

# Returns

- A `NetworkBuilder.ParametricStability` containing the frequency-wise index,
  passivity probabilities, whole-scan probability, and minimum-index summary.

# Notes

The scalar implementation is preserved and applied per trial:

```math
\\nu(j\\omega) = \\min \\operatorname{Re} \\lambda\\left(G(j\\omega) + G(j\\omega)^H\\right).
```
"""
function passivity(
        source::Union{_NB.ParametricFrequencyResponse, _NB.ParametricImpedance},
        omega = nothing,
        title::String = "Passivity assessment";
        return_samples::Bool = false,
        display_plot::Bool = true
)
    response = _as_frequency_response(source)
    cases = _NB.StabilityCase[]
    for case in response
        frequencies = _validated_case_frequencies(case, omega)
        samples = _NB._frequency_response_samples(case)
        indices = [[minimum(real.(eigvals(
                        sample[:, :, frequency] + adjoint(sample[:, :, frequency]),
                    ))) for frequency in axes(sample, 3)]
                   for sample in samples]
        if length(indices) == 1
            index, statistics = first(indices), nothing
        else
            index, statistics = _NB._aggregate_tree(indices)
        end
        probability_by_frequency = [sum(sample[frequency] >= 0 for sample in indices) /
                                    length(indices)
                                    for frequency in eachindex(first(indices))]
        probability_complete_scan = sum(all(>=(0), sample) for sample in indices) /
                                    length(indices)
        minima = minimum.(indices)
        minimum_frequencies = [frequencies[argmin(sample)] / (2pi) for sample in indices]
        minimum_summary = length(indices) == 1 ?
                          (value = first(minima), frequency = first(minimum_frequencies)) :
                          (
            value = _NB._aggregate_numbers(minima)[1],
            frequency = _NB._aggregate_numbers(minimum_frequencies)[1]
        )
        output = (;
            index,
            probability_by_frequency,
            probability_complete_scan,
            minimum = minimum_summary
        )
        frequency_hz = frequencies ./ (2pi)
        median_index = statistics === nothing ? first(indices) :
                       getproperty.(statistics, :median)
        plot_object = plot(
            frequency_hz,
            median_index;
            ribbon = statistics === nothing ? nothing :
                     (
                median_index .- getproperty.(statistics, :q05),
                getproperty.(statistics, :q95) .- median_index
            ),
            fillalpha = 0.18,
            xaxis = :log10,
            linewidth = 3,
            color = :blue,
            label = "G(s)",
            xlabel = "Frequency [Hz]",
            ylabel = "Re(lambda(.))",
            title,
            framestyle = :box
        )
        hline!(plot_object, [0]; color = :red, linestyle = :dash, label = "Zero")
        display_plot && display(plot_object)
        push!(cases,
            _NB.StabilityCase(
                case.coordinates,
                case.trials,
                case.seed,
                case.distribution,
                :passivity,
                output,
                statistics,
                return_samples ? indices : nothing,
                (passivity = plot_object,),
                case.uncertainty_source
            ))
    end
    return _NB.ParametricStability(:passivity, cases)
end

function _evd_trial(response, frequencies, fmin, fmax)
    frequency_count = size(response, 3)
    order = size(response, 1)
    eigenvalues = Matrix{ComplexF64}(undef, frequency_count, order)
    eigenvectors = Vector{Matrix{ComplexF64}}(undef, frequency_count)
    first_decomposition = LinearAlgebra.eigen(response[:, :, 1])
    eigenvalues[1, :] = first_decomposition.values
    eigenvectors[1] = first_decomposition.vectors
    for frequency_index in 2:frequency_count
        decomposition = LinearAlgebra.eigen(response[:, :, frequency_index])
        distances = [abs(eigenvalues[frequency_index - 1, left] -
                         decomposition.values[right])
                     for left in 1:order, right in 1:order]
        permutation = munkres(distances)
        eigenvalues[frequency_index, :] = decomposition.values[permutation]
        eigenvectors[frequency_index] = decomposition.vectors[:, permutation]
    end

    frequencies_hz = frequencies ./ (2pi)
    first_index = argmin(abs.(frequencies_hz .- fmin))
    last_index = argmin(abs.(frequencies_hz .- fmax))
    first_index <= last_index || ((first_index, last_index) = (last_index, first_index))
    frequency_indices = first_index:last_index
    magnitude = abs.(eigenvalues)
    maximum_by_mode = [maximum(@view magnitude[frequency_indices, mode])
                       for mode in 1:order]
    dominant_mode = argmax(maximum_by_mode)
    relative_peak = argmax(@view magnitude[frequency_indices, dominant_mode])
    critical_index = first_index + relative_peak - 1

    observability = Array{Float64}(undef, frequency_count, order, order)
    controllability = similar(observability)
    participation = similar(observability)
    for frequency_index in 1:frequency_count
        right = copy(eigenvectors[frequency_index])
        for mode in 1:order
            right[:, mode] ./= norm(right[:, mode])
        end
        left = inv(right)
        for mode in 1:order
            observable = abs.(right[:, mode])
            controllable = abs.(left[mode, :])
            participated = abs.(right[:, mode] .* vec(left[mode, :]))
            observability[frequency_index, :, mode] = observable ./ sum(observable)
            controllability[frequency_index, :, mode] = controllable ./ sum(controllable)
            participation[frequency_index, :, mode] = participated ./ sum(participated)
        end
        eigenvectors[frequency_index] = right
    end

    pmd_modes = [Float64[] for _ in 1:order]
    pnd_modes = [Float64[] for _ in 1:order]
    pmd_unstable = false
    pnd_unstable = false
    pnd_candidates = NamedTuple[]
    for mode in 1:order
        mode_magnitude = magnitude[frequency_indices, mode]
        for relative_index in argmaxima(mode_magnitude)
            index = first_index + relative_index - 1
            abs(frequencies_hz[index] - 50.0) <= 0.5 && continue
            previous_index = index > firstindex(frequencies_hz) ? index - 1 : index + 1
            slope = imag(eigenvalues[index, mode]) - imag(eigenvalues[previous_index, mode])
            stable = (slope > 0 && real(eigenvalues[index, mode]) < 0) ||
                     (slope < 0 && real(eigenvalues[index, mode]) > 0)
            if !stable
                pmd_unstable = true
                push!(pmd_modes[mode], frequencies_hz[index])
            end
        end
        imaginary = imag.(@view eigenvalues[frequency_indices, mode])
        for relative_index in findall(diff(signbit.(imaginary)) .!= 0)
            index = first_index + relative_index - 1
            abs(frequencies_hz[index] - 50.0) <= 0.5 && continue
            real_part = real(eigenvalues[index, mode])
            push!(pnd_candidates, (;
                real_part,
                mode,
                index,
                frequency = frequencies_hz[index]
            ))
            if real_part <= 0
                pnd_unstable = true
                push!(pnd_modes[mode], frequencies_hz[index])
            end
        end
    end
    pnd_critical = isempty(pnd_candidates) ? nothing :
                   pnd_candidates[argmin(getproperty.(pnd_candidates, :real_part))]
    determinant_index = abs.(inv.(det.([response[:, :, index]
                                        for index in axes(response, 3)])))
    return (;
        eigenvalues,
        eigenvectors,
        observability,
        controllability,
        participation,
        dominant_mode,
        critical_frequency = frequencies_hz[critical_index],
        pmd_unstable,
        pmd_modes,
        pnd_unstable,
        pnd_modes,
        pnd_critical,
        determinant_index
    )
end

function _match_evd_trials(trials, reference)
    matched = Any[]
    for trial in trials
        eigenvalues, permutation = _match_loci(trial.eigenvalues, reference)
        eigenvectors = [matrix[:, permutation] for matrix in trial.eigenvectors]
        dominant_mode = only(findall(==(trial.dominant_mode), permutation))
        pnd_critical = if trial.pnd_critical === nothing
            nothing
        else
            merge(trial.pnd_critical, (;
                mode = only(findall(==(trial.pnd_critical.mode), permutation)),
            ))
        end
        push!(matched,
            merge(trial,
                (;
                    eigenvalues,
                    eigenvectors,
                    observability = trial.observability[:, :, permutation],
                    controllability = trial.controllability[:, :, permutation],
                    participation = trial.participation[:, :, permutation],
                    dominant_mode,
                    pmd_modes = trial.pmd_modes[permutation],
                    pnd_modes = trial.pnd_modes[permutation],
                    pnd_critical
                )))
    end
    return matched
end

function _mode_detection_summary(records_by_trial)
    mode_count = length(first(records_by_trial))
    per_mode = Vector{Any}(undef, mode_count)
    for mode in 1:mode_count
        trial_records = [records[mode] for records in records_by_trial]
        pooled = reduce(vcat, trial_records; init = Float64[])
        per_mode[mode] = (
            probability_detected = sum(!isempty, trial_records) / length(trial_records),
            count = length(pooled),
            frequencies = isempty(pooled) ? nothing : _NB._scalar_statistics(pooled)
        )
    end
    per_trial = [reduce(vcat, records; init = Float64[]) for records in records_by_trial]
    pooled = reduce(vcat, per_trial; init = Float64[])
    return (
        probability_detected = sum(!isempty, per_trial) / length(per_trial),
        count = length(pooled),
        frequencies = isempty(pooled) ? nothing : _NB._scalar_statistics(pooled),
        per_mode
    )
end

function _pnd_critical_summary(records)
    detected = filter(!isnothing, records)
    return (
        probability_detected = length(detected) / length(records),
        probability_not_detected = 1 - length(detected) / length(records),
        mode_probabilities = isempty(detected) ? Dict{Int, Float64}() :
                             _categorical_probabilities(getproperty.(detected, :mode)),
        frequency = isempty(detected) ? nothing :
                    _NB._scalar_statistics(Float64.(getproperty.(detected, :frequency))),
        real_part = isempty(detected) ? nothing :
                    _NB._scalar_statistics(Float64.(getproperty.(detected, :real_part)))
    )
end

"""
    EVD(response::Union{NetworkBuilder.ParametricFrequencyResponse, NetworkBuilder.ParametricImpedance}, omega, fmin, fmax, determinant=false; kwargs...)

Perform trial-wise eigenvalue decomposition and modal assessment.

# Arguments

- `response`: Parametric matrix frequency responses.
- `omega`: Angular-frequency vector \\[rad/s\\], or `nothing` to use stored values.
- `fmin`: Lower assessment frequency \\[Hz\\].
- `fmax`: Upper assessment frequency \\[Hz\\].
- `determinant`: Include inverse-determinant statistics and a plot when `true`.
- `return_samples`: Retain complete trial modal records.
- `display_plot`: Display constructed plots when `true`.

# Returns

- A `NetworkBuilder.ParametricStability` containing matched eigenvalues,
  magnitude-normalized observability, controllability, and participation
  factors, PMD and PND assessment probabilities, modal-frequency summaries,
  and optional determinant statistics.

# Notes

Eigenvalue trajectories are matched to a nominal trajectory. Eigenvectors are
reordered consistently, but arbitrary complex eigenvector phase is never
aggregated.
"""
function EVD(
        source::Union{_NB.ParametricFrequencyResponse, _NB.ParametricImpedance},
        omega,
        fmin,
        fmax,
        determinant::Bool = false;
        return_samples::Bool = false,
        display_plot::Bool = true
)
    response = _as_frequency_response(source)
    cases = _NB.StabilityCase[]
    for case in response
        frequencies = _validated_case_frequencies(case, omega)
        samples = _NB._frequency_response_samples(case)
        nominal_response = reduce(+, samples) ./ length(samples)
        nominal = _evd_trial(nominal_response, frequencies, fmin, fmax)
        trials = _match_evd_trials(
            [_evd_trial(sample, frequencies, fmin, fmax) for sample in samples],
            nominal.eigenvalues
        )
        if length(trials) == 1
            eigenvalues, eigenvalue_statistics = first(trials).eigenvalues, nothing
            observability, observability_statistics = first(trials).observability, nothing
            controllability, controllability_statistics = first(trials).controllability,
            nothing
            participation, participation_statistics = first(trials).participation, nothing
            determinant_values, determinant_statistics = first(trials).determinant_index,
            nothing
        else
            eigenvalues, eigenvalue_statistics = _NB._aggregate_impedance(
                getproperty.(trials, :eigenvalues),
            )
            observability, observability_statistics = _NB._aggregate_tree(
                getproperty.(trials, :observability),
            )
            controllability, controllability_statistics = _NB._aggregate_tree(
                getproperty.(trials, :controllability),
            )
            participation, participation_statistics = _NB._aggregate_tree(
                getproperty.(trials, :participation),
            )
            determinant_values, determinant_statistics = _NB._aggregate_tree(
                getproperty.(trials, :determinant_index),
            )
        end
        critical_frequencies = getproperty.(trials, :critical_frequency)
        critical_frequency = length(trials) == 1 ? first(critical_frequencies) :
                             _NB._aggregate_numbers(critical_frequencies)[1]
        critical_frequency_statistics = length(trials) == 1 ? nothing :
                                        _NB._scalar_statistics(Float64.(critical_frequencies))
        dominant_mode_probabilities = _categorical_probabilities(
            getproperty.(trials, :dominant_mode),
        )
        pmd_unstable_probability = sum(getproperty.(trials, :pmd_unstable)) /
                                   length(trials)
        pnd_unstable_probability = sum(getproperty.(trials, :pnd_unstable)) /
                                   length(trials)
        pmd_assessment_probabilities = Dict(
            :unstable => pmd_unstable_probability,
            :stable => 1 - pmd_unstable_probability
        )
        pnd_assessment_probabilities = Dict(
            :unstable => pnd_unstable_probability,
            :stable => 1 - pnd_unstable_probability
        )
        pmd_modes = _mode_detection_summary(getproperty.(trials, :pmd_modes))
        pnd_modes = _mode_detection_summary(getproperty.(trials, :pnd_modes))
        pnd_critical = _pnd_critical_summary(getproperty.(trials, :pnd_critical))
        output = (;
            eigenvalues,
            observability,
            controllability,
            participation,
            critical_frequency,
            dominant_mode_probabilities,
            pmd_unstable_probability,
            pnd_unstable_probability,
            pmd_assessment_probabilities,
            pnd_assessment_probabilities,
            pmd_modes,
            pnd_modes,
            pnd_critical,
            determinant_index = determinant ? determinant_values : nothing
        )
        statistics = (;
            eigenvalues = eigenvalue_statistics,
            observability = observability_statistics,
            controllability = controllability_statistics,
            participation = participation_statistics,
            critical_frequency = critical_frequency_statistics,
            determinant_index = determinant ? determinant_statistics : nothing
        )
        frequency_hz = frequencies ./ (2pi)
        median_eigenvalues = eigenvalue_statistics === nothing ? eigenvalues :
                             complex.(
            getproperty.(eigenvalue_statistics.real, :median),
            getproperty.(eigenvalue_statistics.imag, :median)
        )
        magnitude_plot = plot(; xlabel = "Frequency [Hz]", ylabel = "abs(lambda) [dB]",
            xaxis = :log10, xlims = (fmin, fmax), framestyle = :box)
        real_plot = plot(; xlabel = "Frequency [Hz]", ylabel = "Re(lambda)",
            xaxis = :log10, xlims = (fmin, fmax), framestyle = :box)
        imaginary_plot = plot(; xlabel = "Frequency [Hz]", ylabel = "Im(lambda)",
            xaxis = :log10, xlims = (fmin, fmax), framestyle = :box)
        for mode in axes(median_eigenvalues, 2)
            plot!(magnitude_plot, frequency_hz,
                20log10.(abs.(median_eigenvalues[:, mode]));
                linewidth = 3, label = "Lambda $mode")
            plot!(real_plot, frequency_hz, real.(median_eigenvalues[:, mode]);
                linewidth = 3, label = "Lambda $mode")
            plot!(imaginary_plot, frequency_hz, imag.(median_eigenvalues[:, mode]);
                linewidth = 3, label = "Lambda $mode")
        end
        combined_plot = plot(magnitude_plot, real_plot, imaginary_plot; layout = (3, 1))
        determinant_plot = nothing
        if determinant
            median_determinant = determinant_statistics === nothing ? determinant_values :
                                 getproperty.(determinant_statistics, :median)
            determinant_plot = plot(frequency_hz, median_determinant;
                xaxis = :log10, yaxis = :log10, xlabel = "Frequency [Hz]",
                ylabel = "Magnitude", label = "G^-1", framestyle = :box)
        end
        if display_plot
            display(combined_plot)
            determinant && display(determinant_plot)
        end
        push!(cases,
            _NB.StabilityCase(
                case.coordinates,
                case.trials,
                case.seed,
                case.distribution,
                :evd,
                output,
                statistics,
                return_samples ? trials : nothing,
                (; eigenvalues = combined_plot, determinant = determinant_plot),
                case.uncertainty_source
            ))
    end
    return _NB.ParametricStability(:evd, cases)
end

"""
    stabilitymargin(response::Union{NetworkBuilder.ParametricFrequencyResponse, NetworkBuilder.ParametricImpedance}, omega=nothing; SM="VM", return_samples=false)

Summarize phase, gain, or vector margins across all numeric trials.

# Arguments

- `response`: Parametric loop-gain or impedance responses.
- `omega`: Optional angular-frequency vector \\[rad/s\\].
- `SM`: Selected margin identifier: `"PM"`, `"GM"`, or `"VM"`.
- `return_samples`: Retain all variable-length crossing records.

# Returns

- A `NetworkBuilder.ParametricStability` containing critical margins, crossing
  frequencies, detection probabilities, and no-crossing probabilities.
"""
function stabilitymargin(
        source::Union{_NB.ParametricFrequencyResponse, _NB.ParametricImpedance},
        omega = nothing;
        SM::String = "VM",
        return_samples::Bool = false
)
    nyquist = nyquistplot(
        source,
        omega;
        SM,
        return_samples,
        display_plot = false
    )
    cases = [_NB.StabilityCase(
                 case.coordinates,
                 case.trials,
                 case.seed,
                 case.distribution,
                 :stabilitymargin,
                 (margins = case.output.margins, selected = Symbol(lowercase(SM))),
                 case.statistics.margins,
                 return_samples && case.samples !== nothing ? case.samples.metrics :
                 nothing,
                 (;),
                 case.uncertainty_source
             ) for case in nyquist]
    return _NB.ParametricStability(:stabilitymargin, cases)
end

"""
    unstable_frequency(response::Union{NetworkBuilder.ParametricFrequencyResponse, NetworkBuilder.ParametricImpedance}, omega=nothing; kwargs...)

Summarize unstable-frequency detections across all numeric trials.

# Arguments

- `response`: Parametric loop-gain or impedance responses.
- `omega`: Optional angular-frequency vector \\[rad/s\\].
- `order_maxima`: Neighbourhood order used by peak detection.
- `make_plot`: Construct an unstable-frequency plot when `true`.
- `title`: Plot title.
- `return_samples`: Retain all trial detection records.
- `display_plot`: Display the constructed plot when `true`.

# Returns

- A `NetworkBuilder.ParametricStability` containing detection and count
  probabilities plus pooled frequency statistics \\[Hz\\].
"""
function unstable_frequency(
        source::Union{_NB.ParametricFrequencyResponse, _NB.ParametricImpedance},
        omega = nothing;
        order_maxima::Int = 5,
        make_plot::Bool = true,
        title::String = "Unstable oscillatory frequency",
        return_samples::Bool = false,
        display_plot::Bool = true
)
    nyquist = nyquistplot(
        source,
        omega;
        order_maxima,
        return_samples,
        display_plot = false
    )
    cases = _NB.StabilityCase[]
    response = _as_frequency_response(source)
    for (case, response_case) in zip(nyquist, response)
        frequencies = response_case.frequencies ./ (2pi)
        summary = case.output.unstable_frequencies
        plot_object = plot(; xlabel = "Frequency [Hz]", ylabel = "Detection probability",
            xaxis = :log10, title, framestyle = :box, xlims = extrema(frequencies))
        if summary.frequencies !== nothing
            vline!(plot_object, [summary.frequencies.median];
                label = "Median unstable frequency", linestyle = :dash)
        end
        make_plot && display_plot && display(plot_object)
        push!(cases,
            _NB.StabilityCase(
                case.coordinates,
                case.trials,
                case.seed,
                case.distribution,
                :unstable_frequency,
                summary,
                case.statistics,
                return_samples && case.samples !== nothing ? case.samples.metrics : nothing,
                (unstable_frequency = make_plot ? plot_object : nothing,),
                case.uncertainty_source
            ))
    end
    return _NB.ParametricStability(:unstable_frequency, cases)
end

"""
    check_stability(builder::NetworkBuilder.BuilderState, element::Symbol; direction=:dc, kwargs...)
    check_stability(gridspace::NetworkBuilder.Gridspace{NetworkBuilder.BuilderState}, element::Symbol; direction=:dc, kwargs...)

Partition one active device from the remaining network and run common Nyquist analysis.

# Arguments

- `builder`: One constructed power system.
- `gridspace`: Deterministic or uncertain constructed systems.
- `element`: Active-device designator.
- `direction`: Selected terminal domain, `:ac` or `:dc`.
- `freq_range`: Minimum frequency \\[Hz\\], maximum frequency \\[Hz\\], and point count.
- `trials`, `distribution`, `seed`, `confidence`, `tolerance`: Monte Carlo controls.
- `return_samples`: Retain exact partition and analysis trial records.

# Returns

- A `NetworkBuilder.ParametricStability` containing device-versus-remainder
  loop-gain Nyquist results.

# Notes

At each frequency, the partitioned return ratio is
`Zrest * inv(Zdevice)`. The selected terminal nodes are resolved from the
connection registry.

# Errors

Throws an error for missing, passive, source, disconnected, singular, or
dimensionally inconsistent selections.
"""
function check_stability(
        gridspace::_NB.Gridspace{_NB.BuilderState},
        element::Symbol;
        direction::Symbol = :dc,
        freq_range = (1.0, 1.0e3, 1000),
        trials::Union{Nothing, Int} = nothing,
        distribution::Union{Nothing, Symbol} = nothing,
        seed = nothing,
        confidence::Real = 0.95,
        tolerance::Real = 0.02,
        return_samples::Bool = false,
        kwargs...
)
    response, _, frequencies = _NB._check_stability_response(
        gridspace,
        element;
        direction,
        freq_range,
        trials,
        distribution,
        seed,
        confidence,
        tolerance,
        return_samples
    )
    nyquist = nyquistplot(
        response,
        frequencies;
        return_samples,
        kwargs...
    )
    cases = [_NB.StabilityCase(
                 case.coordinates,
                 case.trials,
                 case.seed,
                 case.distribution,
                 :check_stability,
                 merge(case.output, (; element, direction)),
                 case.statistics,
                 case.samples,
                 case.plots,
                 case.uncertainty_source
             ) for case in nyquist]
    return _NB.ParametricStability(:check_stability, cases)
end

function check_stability(
        builder::_NB.BuilderState,
        element::Symbol;
        kwargs...
)
    return check_stability(
        _NB._singleton_builder_space(builder),
        element;
        kwargs...
    )
end

# The NetworkBuilder kernels use n×n×nf tensors. These additive adapters make
# those tensors valid scalar inputs without altering the legacy Vector{Matrix}
# methods or their return values.
function _matrix_vector(response::AbstractArray{<:Number, 3})
    [response[:, :, index] for index in axes(response, 3)]
end

function nyquistplot(response::AbstractArray{<:Number, 3}, frequencies; kwargs...)
    nyquistplot(_matrix_vector(response), frequencies; kwargs...)
end
function bodeplot(response::AbstractArray{<:Number, 3}, frequencies; kwargs...)
    bodeplot(_matrix_vector(response), frequencies; kwargs...)
end
function passivity(response::AbstractArray{<:Number, 3}, frequencies, args...; kwargs...)
    passivity(_matrix_vector(response), frequencies, args...; kwargs...)
end
function passivity(
        response::AbstractArray{<:Number, 3},
        frequencies,
        title::String;
        kwargs...
)
    passivity(_matrix_vector(response), frequencies, title; kwargs...)
end
function small_gain(
        first::AbstractArray{<:Number, 3},
        second::AbstractArray{<:Number, 3},
        frequencies,
        args...;
        kwargs...
)
    small_gain(
        _matrix_vector(first),
        _matrix_vector(second),
        frequencies,
        args...;
        kwargs...
    )
end
function small_gain(
        first::AbstractArray{<:Number, 3},
        second::AbstractArray{<:Number, 3},
        frequencies,
        title::String;
        kwargs...
)
    small_gain(
        _matrix_vector(first),
        _matrix_vector(second),
        frequencies,
        title;
        kwargs...
    )
end
function EVD(response::AbstractArray{<:Number, 3}, frequencies, args...; kwargs...)
    EVD(_matrix_vector(response), frequencies, args...; kwargs...)
end
