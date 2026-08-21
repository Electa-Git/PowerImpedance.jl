export make_loopgain, unwrap!

function make_loopgain(
    edge::AbstractVector,
    node::AbstractVector;
    pairing::Symbol=:auto,
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

"""
    unwrap!(values[, period])

Unwrap an angular sequence in place by selecting the nearest branch of
`period` at each sample.
"""
function unwrap!(values, period=2pi)
    converted_period = convert(eltype(values), period)
    previous = first(values)
    @inbounds for index in eachindex(values)
        values[index] = previous = previous + rem(
            values[index] - previous,
            converted_period,
            RoundNearest,
        )
    end
    return values
end

function _trajectory_eigenvalues(response)
    frequency_count = size(response, 3)
    order = size(response, 1)
    loci = Matrix{ComplexF64}(undef, frequency_count, order)
    loci[1, :] = eigvals(response[:, :, 1])
    for frequency_index in 2:frequency_count
        current = eigvals(response[:, :, frequency_index])
        distances = [
            abs(loci[frequency_index - 1, left] - current[right])
            for left in 1:order, right in 1:order
        ]
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
                margin=margin,
                frequency=frequencies[index] / 2pi,
            ))
        end
        if (phase[index - 1] + 180) * (phase[index] + 180) < 0 &&
            real(locus[index]) < 0
            push!(gain_margins, (
                margin=-20log10(magnitude[index]),
                frequency=frequencies[index] / 2pi,
            ))
        end
    end
    vector_distances = abs.(locus .+ 1)
    vector_index = argmin(vector_distances)
    return (
        phase=phase_margins,
        gain=gain_margins,
        vector=(
            margin=100vector_distances[vector_index],
            frequency=frequencies[vector_index] / 2pi,
        ),
    )
end

function _unstable_frequency_analysis(locus, frequencies; order_maxima::Int=5)
    length(locus) == length(frequencies) || throw(DimensionMismatch(
        "the eigenlocus and frequency vectors must have the same length",
    ))
    complementary_sensitivity = 1 ./ (ones(ComplexF64, length(locus)) .+ locus)
    magnitude = abs.(complementary_sensitivity)
    phase = angle.(complementary_sensitivity)
    unwrapped_phase = unwrap!(copy(phase))
    detected_frequencies = Float64[]
    detected_indices = Int[]
    for point in argmaxima(magnitude, order_maxima)
        point == firstindex(frequencies) && continue
        point == lastindex(frequencies) && continue
        first_step = frequencies[point] - frequencies[point - 1]
        second_step = frequencies[point + 1] - frequencies[point]
        first_step == 0 && continue
        second_step == 0 && continue
        derivative =
            (-second_step / (first_step * (first_step + second_step))) *
            unwrapped_phase[point - 1] +
            ((second_step - first_step) / (first_step * second_step)) *
            unwrapped_phase[point] +
            (first_step / (second_step * (first_step + second_step))) *
            unwrapped_phase[point + 1]
        if derivative > 0
            push!(detected_indices, point)
            push!(detected_frequencies, real(frequencies[point]) / 2pi)
        end
    end
    return (
        complementary_sensitivity=complementary_sensitivity,
        magnitude_db=20 .* log10.(max.(magnitude, eps(Float64))),
        phase_deg=rad2deg.(phase),
        detected_indices=detected_indices,
        detected_frequencies=detected_frequencies,
    )
end

function _nyquist_trial(loci, frequencies; order_maxima=5)
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
            analysis = _unstable_frequency_analysis(
                loci[:, mode],
                frequencies;
                order_maxima,
            )
            append!(unstable_frequencies, analysis.detected_frequencies)
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
        unstable_frequencies,
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
    magnitude_samples = [
        20 .* log10.(max.(abs.(sample), eps(Float64))) for sample in samples
    ]
    nominal_response = reduce(+, samples) ./ length(samples)
    reference_phase = _bode_phase(nominal_response)
    phase_samples = Array{Float64,3}[]
    for sample in samples
        phase = _bode_phase(sample)
        for row in axes(phase, 1), column in axes(phase, 2)
            branch = round(
                Int,
                (phase[row, column, 1] - reference_phase[row, column, 1]) / 360,
            )
            phase[row, column, :] .-= 360branch
        end
        push!(phase_samples, phase)
    end
    return magnitude_samples, phase_samples
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
        distances = [
            abs(eigenvalues[frequency_index - 1, left] - decomposition.values[right])
            for left in 1:order, right in 1:order
        ]
        permutation = munkres(distances)
        eigenvalues[frequency_index, :] = decomposition.values[permutation]
        eigenvectors[frequency_index] = decomposition.vectors[:, permutation]
    end

    frequencies_hz = frequencies ./ 2pi
    first_index = argmin(abs.(frequencies_hz .- fmin))
    last_index = argmin(abs.(frequencies_hz .- fmax))
    first_index <= last_index || ((first_index, last_index) = (last_index, first_index))
    frequency_indices = first_index:last_index
    magnitude = abs.(eigenvalues)
    maximum_by_mode = [
        maximum(@view magnitude[frequency_indices, mode]) for mode in 1:order
    ]
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
                frequency=frequencies_hz[index],
            ))
            if real_part <= 0
                pnd_unstable = true
                push!(pnd_modes[mode], frequencies_hz[index])
            end
        end
    end
    pnd_critical = isempty(pnd_candidates) ? nothing :
        pnd_candidates[argmin(getproperty.(pnd_candidates, :real_part))]
    determinant_index = abs.(inv.(det.([
        response[:, :, index] for index in axes(response, 3)
    ])))
    return (;
        eigenvalues,
        eigenvectors,
        observability,
        controllability,
        participation,
        dominant_mode,
        critical_frequency=frequencies_hz[critical_index],
        pmd_unstable,
        pmd_modes,
        pnd_unstable,
        pnd_modes,
        pnd_critical,
        determinant_index,
    )
end
