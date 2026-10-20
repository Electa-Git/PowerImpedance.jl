const PASSIVE_FREQUENCY_LIMITS = (epsilon = 0.02, entry_floor_pu = 0.02,
    frobenius_floor_pu = 0.1, phase_limit_deg = 2.0)
const ACTIVE_FREQUENCY_LIMITS = merge(PASSIVE_FREQUENCY_LIMITS, (epsilon = 0.05, phase_limit_deg = 3.0))

"""
$(TYPEDSIGNATURES)

Evaluate a sum of cosines with the supplied fixed phases.

# Arguments

- `times`: Absolute simulation times \\[s\\].
- `frequencies`: Distinct positive tone frequencies \\[Hz\\].
- `phases`: Fixed phases, one per frequency \\[rad\\].
- `amplitude`: Peak amplitude per tone in the output signal's physical unit.
- `onset`: Injection start time \\[s\\]. Default: `0.0`.

# Returns

- Real signal vector in the amplitude unit, equal to zero before `onset`.

# Notes

For ``t ≥ onset``, the signal is

```math
x(t) = A \\sum_k \\cos(2\\pi f_k t + \\phi_k),
```

where ``A`` is `amplitude`, ``f_k`` is a tone frequency and ``\\phi_k`` is
its phase. Phases refer to absolute simulation time.
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
The positive-sine q convention matches `PSCAD.abc_to_dq_module` with `qaxis=1`.

# Arguments

- `times`: Absolute sample times \\[s\\].
- `abc`: Sample-by-phase matrix in a common physical unit, ordered a/b/c.
- `frequency`: Nominal grid frequency \\[Hz\\]. Default: `50.0`.

# Returns

- Sample-by-(d,q) matrix in the input unit with phase-peak normalization.

# Notes

The frame follows the nominal frequency independently of the PLL:

```math
d(t) = \\frac{2}{3}\\sum_{p=1}^{3}x_p(t)\\cos\\theta_p(t),\\qquad
q(t) = \\frac{2}{3}\\sum_{p=1}^{3}x_p(t)\\sin\\theta_p(t),
```

where ``\\theta_p(t) = 2\\pi f_0t + \\phi_p``, ``f_0`` is `frequency`
and ``\\phi_p`` is 0, −2π/3 or 2π/3 for phases a, b or c, respectively.
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

Extract peak complex phasors by direct DFT at coherent frequency bins.
Use absolute sample times and a rectangular window without its repeated endpoint.

# Arguments

- `times`: Uniformly increasing sample times \\[s\\].
- `signals`: Sample-by-channel real matrix in physical signal units.
- `frequencies`: Distinct positive coherent frequencies \\[Hz\\].
- `start`: Sampled window start \\[s\\].
- `duration`: Window length \\[s\\].

# Returns

- Channel-by-frequency complex peak phasors in the input units.

# Notes

For each channel, the phasor at frequency ``f`` is

```math
X(f) = \\frac{2}{N}\\sum_{n=1}^{N}x(t_n)\\exp(-\\mathrm{j}2\\pi ft_n),
```

where ``N`` is the sample count in the window and ``t_n`` is absolute sample time.

# Errors

- Throws `ArgumentError` for incoherent or duplicate bins, incomplete or nonuniform
  samples, nonfinite data, or frequencies at or above Nyquist.
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

Recover a response matrix from independent input-coordinate runs and an
unperturbed baseline using measured phasors. Voltage-to-current identification
gives Y; supplying currents as inputs and voltages as outputs gives Z directly.

# Arguments

- `times`: Common absolute sample times \\[s\\].
- `voltages`: Input sample matrices, one run per input coordinate; \\[kV\\] for Y
  or \\[kA\\] for direct Z.
- `currents`: Corresponding output matrices; \\[kA\\] for Y or \\[kV\\] for Z.
- `baseline_voltage`: Unperturbed input matrix in the input unit.
- `baseline_current`: Unperturbed output matrix in the output unit.
- `frequencies`: Coherent comparison frequencies \\[Hz\\].
- `starts`: DFT window starts \\[s\\].
- `duration`: Duration of each window \\[s\\].
- `input_bases`: Row scales for input-matrix conditioning in the input unit.
  Default: `nothing`, which uses the unscaled matrix.

# Returns

- `matrices`: Vector of output-by-input-by-frequency tensors, one per window,
  in \\[S\\] for Y or \\[Ω\\] for direct Z.
- `conditions`: Window-by-frequency input-matrix condition numbers
  \\[dimensionless\\].

# Notes

Subtract baseline phasors before solving at each frequency:

```math
H(f) = O(f)U(f)^{-1},
```

where columns of ``U`` and ``O`` contain measured input and output phasors
from independent drives. For branch Y, currents point into the driven port
and the opposite port is voltage-clamped, giving its `Y[1:2,1:2]` block.

# Errors

- Throws `ArgumentError` for incompatible sample dimensions or an input-matrix
  condition number above 100, and propagates DFT sampling errors.
"""
function extract_response(times, voltages, currents, baseline_voltage, baseline_current,
        frequencies; starts, duration, input_bases = nothing)
    length(voltages) == length(currents) == size(baseline_voltage, 2) ||
        throw(ArgumentError("one independent run per input coordinate required"))
    size(baseline_voltage,1) == size(baseline_current,1) &&
    size(baseline_voltage, 1) == length(times) ||
        throw(ArgumentError("baseline dimensions"))
    dimension = size(baseline_voltage, 2)
    dimension > 0 || throw(ArgumentError("empty response"))
    matrices, conditions = Array{ComplexF64, 3}[],
    Matrix{Float64}(undef, length(starts), length(frequencies))
    for (window, start) in enumerate(starts)
        v = zeros(ComplexF64, dimension, dimension, length(frequencies))
        i = zeros(ComplexF64,size(baseline_current,2),dimension,length(frequencies))
        for axis in 1:dimension
            size(voltages[axis]) == size(baseline_voltage) && size(currents[axis]) == size(baseline_current) ||
                throw(ArgumentError("injection dimensions"))
            v[:, axis, :] = dft_phasors(times, voltages[axis] - baseline_voltage,
                frequencies; start, duration)
            i[:, axis, :] = dft_phasors(times, currents[axis] - baseline_current,
                frequencies; start, duration)
        end
        y = similar(i)
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
    rule = active ? ACTIVE_FREQUENCY_LIMITS : PASSIVE_FREQUENCY_LIMITS
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
