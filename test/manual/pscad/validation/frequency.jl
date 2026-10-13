const C_PASSIVE = (epsilon = 0.02, entry_floor_pu = 0.02,
    frobenius_floor_pu = 0.1, phase_limit_deg = 2.0)
const C_ACTIVE = merge(C_PASSIVE, (epsilon = 0.05, phase_limit_deg = 3.0))

"""
$(TYPEDSIGNATURES)

Evaluate a coherent cosine multi-tone with Schroeder phases.

# Arguments
- `times`: absolute simulation times \\[s\\].
- `frequencies`: distinct positive frequencies \\[Hz\\].
- `phases`: one fixed phase per frequency \\[rad\\].
- `amplitude`: peak amplitude of each tone, in the caller's signal unit.
- `onset`: injection start time \\[s\\]; values below it are zero.

# Returns
- A real signal vector in the amplitude unit. Phases refer to absolute time.
"""
function multitone(times, frequencies, phases; amplitude, onset = 0.0)
    length(frequencies) == length(phases) > 0 || throw(ArgumentError("tone dimensions"))
    all(f -> isfinite(f) && f > 0, frequencies) && all(isfinite, phases) ||
        throw(ArgumentError("invalid tones"))
    length(unique(frequencies)) == length(frequencies) ||
        throw(ArgumentError("duplicate tones"))
    isfinite(amplitude) && amplitude >= 0 && isfinite(onset) ||
        throw(ArgumentError("amplitude/onset"))
    return [t < onset ? 0.0 :
            amplitude * sum(cos(2π * f * t + phase)
            for (f, phase) in zip(frequencies, phases)) for t in times]
end

"""
$(TYPEDSIGNATURES)

Project phase-ordered abc samples onto the fixed nominal grid frame.
Use `d=(2/3)sum(x*cos(theta))`, `q=(2/3)sum(x*sin(theta))`, matching
`PSCAD.abc_to_dq_module` with `qaxis=1`, not a following PLL.

# Arguments
- `times`: absolute sample times \\[s\\].
- `abc`: sample-by-phase matrix in a common physical unit, order a/b/c.
- `frequency`: nominal grid frequency \\[Hz\\].

# Returns
- Sample-by-(d,q) matrix in the input unit (phase-peak normalization).
"""
function fixed_dq(times, abc; frequency = 50.0)
    size(abc) == (length(times), 3) || throw(ArgumentError("abc dimensions"))
    result = zeros(length(times), 2)
    for phase in 1:3
        angle = 2π .* frequency .* times .+ (0.0, -2π / 3, 2π / 3)[phase]
        result[:, 1] .+= (2 / 3) .* abc[:, phase] .* cos.(angle)
        result[:, 2] .+= (2 / 3) .* abc[:, phase] .* sin.(angle)
    end
    return result
end

"""
$(TYPEDSIGNATURES)

Extract peak complex phasors by direct DFT at the selected coherent bins.
Use absolute sample times and a rectangular window without the repeated endpoint.

# Arguments
- `times`: uniformly increasing sample times \\[s\\].
- `signals`: sample-by-channel real matrix in physical signal units.
- `frequencies`: positive coherent frequencies \\[Hz\\].
- `start`: exact left window boundary \\[s\\].
- `duration`: window length \\[s\\].

# Returns
- Channel-by-frequency complex peak phasors in the input units.

# Errors
- Throw `ArgumentError` for incoherent bins, incomplete/nonuniform samples,
  nonfinite data, or frequencies at/above Nyquist.
"""
function dft_phasors(times, signals, frequencies; start, duration)
    length(times) >= 2 && size(signals, 1) == length(times) ||
        throw(ArgumentError("sample dimensions"))
    all(isfinite, times) && all(isfinite, signals) ||
        throw(ArgumentError("nonfinite samples"))
    step = (last(times) - first(times)) / (length(times) - 1)
    step > 0 && all(dt -> isapprox(dt, step; rtol = 1e-8, atol = 1e-12), diff(times)) ||
        throw(ArgumentError("nonuniform sample times"))
    count = round(Int, duration / step)
    count >= 2 && isapprox(count * step, duration; rtol = 1e-9) ||
        throw(ArgumentError("incoherent window duration"))
    first_index = searchsortedfirst(times, start - step * 1e-6)
    first_index <= length(times) &&
    isapprox(times[first_index], start; atol = step * 1e-6, rtol = 0) ||
        throw(ArgumentError("window start not sampled"))
    last_index = first_index + count - 1
    last_index <= length(times) || throw(ArgumentError("incomplete DFT window"))
    bins = round.(Int, frequencies .* duration)
    all(>(0), bins) && all(b -> b < count / 2, bins) &&
    all(isapprox.(bins, frequencies .* duration; rtol = 1e-10, atol = 1e-10)) &&
    length(unique(bins)) == length(bins) ||
        throw(ArgumentError("incoherent/aliased DFT bins"))
    window_times = @view times[first_index:last_index]
    window_signals = @view signals[first_index:last_index, :]
    phasors = Matrix{ComplexF64}(undef, size(signals, 2), length(frequencies))
    for (k, frequency) in enumerate(frequencies)
        weights = cis.(-2π .* frequency .* window_times)
        for channel in axes(signals, 2)
            phasors[channel, k] = (2 / count) *
                                  sum(window_signals[j, channel] * weights[j]
            for j in 1:count)
        end
    end
    return phasors
end

"""
$(TYPEDSIGNATURES)

Recover a full response matrix from one independent run per input coordinate
and an unperturbed baseline, using actual measured input phasors.
Voltage-to-current gives Y; current-to-voltage gives Z directly.

# Arguments
- `times`: common absolute sample times \\[s\\].
- `voltages`, `currents`: two sample-by-dq matrices per quantity \\[kV\\], \\[kA\\].
- `baseline_voltage`, `baseline_current`: corresponding unperturbed matrices.
- `frequencies`: coherent comparison frequencies \\[Hz\\].
- `starts`, `duration`: predeclared DFT window boundaries and duration \\[s\\].

# Returns
- `matrices`: vector of 2×2×frequency complex tensors \\[S\\], one per window.
- `conditions`: injection-matrix condition numbers \\[dimensionless\\].

# Notes
Currents point into the measured branch at the driven port; the opposite
branch port is voltage-clamped. This measures its native `Y[1:2,1:2]` block.
"""
function extract_response(times, voltages, currents, baseline_voltage, baseline_current,
        frequencies; starts, duration, input_bases = nothing)
    length(voltages) == length(currents) == size(baseline_voltage, 2) ||
        throw(ArgumentError("one independent run per input coordinate required"))
    size(baseline_voltage) == size(baseline_current) &&
    size(baseline_voltage, 1) == length(times) ||
        throw(ArgumentError("baseline dimensions"))
    dimension = size(baseline_voltage, 2)
    dimension > 0 || throw(ArgumentError("empty response"))
    matrices, conditions = Array{ComplexF64, 3}[],
    Matrix{Float64}(undef, length(starts), length(frequencies))
    for (window, start) in enumerate(starts)
        v = zeros(ComplexF64, dimension, dimension, length(frequencies))
        i = similar(v)
        for axis in 1:dimension
            size(voltages[axis]) == size(currents[axis]) == size(baseline_voltage) ||
                throw(ArgumentError("injection dimensions"))
            v[:, axis, :] = dft_phasors(times, voltages[axis] - baseline_voltage,
                frequencies; start, duration)
            i[:, axis, :] = dft_phasors(times, currents[axis] - baseline_current,
                frequencies; start, duration)
        end
        y = similar(v)
        for k in eachindex(frequencies)
            conditions[window, k] = cond(input_bases === nothing ? v[:, :, k] :
                                         v[:, :, k] ./ input_bases)
            isfinite(conditions[window, k]) && conditions[window, k] <= 100 ||
                throw(ArgumentError("singular/ill-conditioned input at $(frequencies[k]) Hz"))
            y[:, :, k] = i[:, :, k] / v[:, :, k]
        end
        push!(matrices, y)
    end
    return (; matrices, conditions)
end

function comparison_rows(frequencies, measured, reference; active = false,
        model_mismatch = "", valid = true)
    size(measured) == size(reference) && size(reference, 3) == length(frequencies) &&
    size(reference, 1) > 0 && size(reference, 2) > 0 ||
        throw(ArgumentError("comparison dimensions"))
    all(isfinite, measured) && all(isfinite, reference) ||
        throw(ArgumentError("nonfinite matrices"))
    rule = active ? C_ACTIVE : C_PASSIVE
    epsilon, phase_limit = rule.epsilon, rule.phase_limit_deg
    rows = NamedTuple[]
    for k in eachindex(frequencies)
        frobenius_error = norm(measured[:, :, k] - reference[:, :, k]) /
                          max(norm(reference[:, :, k]), rule.frobenius_floor_pu)
        for column in axes(reference, 2), row in axes(reference, 1)

            actual, expected = measured[row, column, k], reference[row, column, k]
            complex_error = abs(actual - expected)
            entry_limit = epsilon * max(abs(expected), rule.entry_floor_pu)
            phase_scored = abs(expected) >= rule.entry_floor_pu
            magnitude_error = phase_scored ?
                              abs(abs(actual) - abs(expected)) / abs(expected) : 0.0
            phase_error_deg = phase_scored ? abs(rad2deg(angle(actual * conj(expected)))) :
                              0.0
            passed = complex_error <= entry_limit && frobenius_error <= epsilon &&
                     (!phase_scored ||
                      (magnitude_error <= epsilon && phase_error_deg <= phase_limit))
            status = !isempty(model_mismatch) ? "model_mismatch" :
                     !valid ? "invalid_measurement" : passed ? "passed" : "failed"
            push!(rows,
                (; frequency_Hz = frequencies[k], row, column,
                    actual_real_pu = real(actual), actual_imag_pu = imag(actual),
                    reference_real_pu = real(expected), reference_imag_pu = imag(expected),
                    complex_error_pu = complex_error, entry_limit_pu = entry_limit,
                    frobenius_error, frobenius_limit = epsilon, phase_scored,
                    magnitude_error, phase_error_deg, phase_limit_deg = phase_limit,
                    within_tolerance = status == "passed", status, model_mismatch))
        end
    end
    return rows
end
