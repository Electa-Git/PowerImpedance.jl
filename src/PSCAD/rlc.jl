"""
$(TYPEDEF)

Represent a series or parallel R/L/C circuit.
`nothing` denotes an absent element. Fits to impedance functions require
positive component values. Numeric inputs preserve signed resistance and
equivalent inductance at 50 \\[Hz\\].

$(TYPEDFIELDS)
"""
struct RLCForm
    "Circuit topology, `:series` or `:parallel`."
    topology::Symbol
    "Resistance \\[Ω\\], when present."
    R::Union{Nothing, Float64}
    "Inductance \\[H\\], when present."
    L::Union{Nothing, Float64}
    "Capacitance \\[F\\], when present."
    C::Union{Nothing, Float64}

    function RLCForm(topology::Symbol, R, L, C)
        topology in (:series, :parallel) ||
            throw(ArgumentError("invalid RLC topology: $topology"))
        return new(topology, R, L, C)
    end
end

function _rlc_error(name)
    return ArgumentError("impedance :$name: z(s) is not a canonical series/parallel R, L, C combination with positive finite values")
end

function _fit_rlc(impedances, omega, rtol, atol, name)
    subsets = ((:R,), (:L,), (:C,), (:R, :L), (:R, :C), (:L, :C), (:R, :L, :C))
    for count in 1:3, topology in (:series, :parallel), subset in subsets
        length(subset) == count || continue
        target = topology == :series ? impedances : inv.(impedances)
        all(isfinite, target) || continue
        resistance = :R in subset ? sum(real, target) / length(target) : nothing
        reactive = filter(!=(:R), subset)
        # Scale columns separately: omega and 1/omega span twelve orders of
        # magnitude on the default grid, but their coefficients are independent.
        columns = [part == (topology == :series ? :L : :C) ? omega : -inv.(omega)
                   for part in reactive]
        scales = [maximum(abs, column) for column in columns]
        coefficients = if isempty(columns)
            Float64[]
        else
            basis = hcat(columns...)
            basis ./= transpose(scales)
            (basis \ imag.(target)) ./ scales
        end
        parameters = Dict{Symbol, Float64}()
        resistance === nothing ||
            (parameters[:R] = topology == :series ? resistance : inv(resistance))
        for (part, coefficient) in zip(reactive, coefficients)
            parameters[part] = (topology == :series && part == :L) ||
                               (topology == :parallel && part == :C) ? coefficient :
                               inv(coefficient)
        end
        all(value -> isfinite(value) && value > 0, values(parameters)) || continue
        R = get(parameters, :R, nothing)
        L = get(parameters, :L, nothing)
        C = get(parameters, :C, nothing)
        fitted = if topology == :series
            (R === nothing ? 0.0 : R) .+
            im .* (L === nothing ? zeros(length(omega)) : omega .* L) .-
            im .* (C === nothing ? zeros(length(omega)) : inv.(omega .* C))
        else
            inv.((R === nothing ? 0.0 : inv(R)) .+
                 im .* (C === nothing ? zeros(length(omega)) : omega .* C) .-
                 im .* (L === nothing ? zeros(length(omega)) : inv.(omega .* L)))
        end
        maximum(abs.(fitted .- impedances) ./ max.(abs.(impedances), atol)) <= rtol &&
            return RLCForm(topology, R, L, C)
    end
    throw(_rlc_error(name))
end

function _constant_rlc(value, name)
    isfinite(value) || throw(_rlc_error(name))
    R = iszero(real(value)) ? nothing : Float64(real(value))
    L = iszero(imag(value)) ? nothing : Float64(imag(value) / (2π * 50))
    return RLCForm(:series, R, L, nothing)
end

function _diagonal_samples(samples, rtol, atol)
    first_sample = first(samples)
    first_sample isa Number && return [ComplexF64.(samples)]
    first_sample isa AbstractMatrix ||
        throw(ArgumentError("impedance must be numeric or matrix-valued"))
    n, m = size(first_sample)
    n == m && n > 0 || throw(ArgumentError("impedance matrix must be nonempty and square"))
    for sample in samples
        sample isa AbstractMatrix && size(sample) == (n, n) ||
            throw(ArgumentError("impedance matrix dimensions change with frequency"))
        diagonal_scale = max(maximum(abs(sample[i, i]) for i in 1:n), atol)
        for j in 1:n, i in 1:n

            i == j && continue
            abs(sample[i, j]) <= rtol * diagonal_scale ||
                throw(ArgumentError("coupled impedance matrix"))
        end
    end
    return [ComplexF64[sample[i, i] for sample in samples] for i in 1:n]
end

"""
$(TYPEDSIGNATURES)

Identify a series or parallel R/L/C circuit from samples of `z(im*2π*f)` \\[Ω\\].
Fit the real part by its mean and the imaginary part by least squares on
`(ω, -1/ω)`. Require positive, finite component values for impedance functions.
Try the fewest components first, preferring series at equal component count.

# Arguments

- `z`: Scalar or matrix impedance, or a function of complex frequency \\[s⁻¹\\].
- `frequencies`: Positive sample frequencies \\[Hz\\]. Default: 13 logarithmic
  points from 0.1 to 1e5.
- `rtol`: Maximum relative impedance error at every sample. Default: `1e-6`.
- `atol`: Impedance floor in the error denominator \\[Ω\\]. Default: `1e-12`.
- `name`: Component designator for fit errors. Default: `:unnamed`.

# Returns

- A record `(form, conductors, constant)` for a scalar or equal diagonal matrix.
  `form` is an `RLCForm`, `conductors` gives the conductor indices and `constant`
  indicates numeric input. Distinct diagonal responses produce a vector of
  records, grouped by sampled response in conductor order.

# Notes

For angular frequency ``ω`` \\[rad/s\\], the fitted series impedance and
parallel admittance are

```math
Z_s = R + \\mathrm{j}ωL + \\frac{1}{\\mathrm{j}ωC},\\qquad
Y_p = \\frac{1}{R} + \\frac{1}{\\mathrm{j}ωL} + \\mathrm{j}ωC,
```

where ``R``, ``L`` and ``C`` use \\[Ω\\], \\[H\\] and \\[F\\], respectively.
Omit terms for absent components, and use ``Z_p = 1/Y_p`` for a parallel circuit.

Numeric inputs use `R = real(z)` \\[Ω\\] and `L = imag(z)/(2π*50)` \\[H\\],
retaining signed values and the equivalent inductance at 50 \\[Hz\\].

# Errors

- Throws `ArgumentError` for off-diagonal coupling or failure to fit the circuit.
"""
function identify_rlc(z; frequencies = 10.0 .^ range(-1, 5; length = 13),
        rtol = 1e-6, atol = 1e-12, name = :unnamed)
    isfinite(rtol) && rtol >= 0 ||
        throw(ArgumentError("rtol must be finite and nonnegative"))
    isfinite(atol) && atol > 0 || throw(ArgumentError("atol must be positive and finite"))
    constant = z isa Union{Number, AbstractMatrix}
    freqs = Float64.(collect(frequencies))
    !isempty(freqs) && all(f -> isfinite(f) && f > 0, freqs) ||
        throw(ArgumentError("frequencies must be positive and finite"))
    !constant && length(unique(freqs)) < 2 &&
        throw(ArgumentError("at least two distinct frequencies are required"))
    omega = 2π .* freqs
    samples = constant ? [z] : [z(im * w) for w in omega]
    diagonals = _diagonal_samples(samples, rtol, atol)
    groups = Vector{Int}[]
    for (index, diagonal) in enumerate(diagonals)
        all(isfinite, diagonal) || throw(_rlc_error(name))
        group = findfirst(groups) do indices
            reference = diagonals[first(indices)]
            all(abs.(diagonal .- reference) .<=
                rtol .* max.(abs.(diagonal), abs.(reference), atol))
        end
        group === nothing ? push!(groups, [index]) : push!(groups[group], index)
    end
    records = map(groups) do conductors
        samples = diagonals[first(conductors)]
        form = constant ? _constant_rlc(only(samples), name) :
               _fit_rlc(samples, omega, rtol, atol, name)
        (; form, conductors, constant)
    end
    return length(records) == 1 ? only(records) : records
end

"""
$(TYPEDSIGNATURES)

Identify impedance in its original conductor coordinates from the model's value.

# Arguments

- `model`: Impedance model.
- `name`: Designator for fit errors. Default: `:impedance`.
- `kw`: Additional keywords for [`identify_rlc`](@ref).

# Returns

- The RLC record or grouped records returned by [`identify_rlc`](@ref).
"""
function identify_rlc(model::PowerImpedance.Impedance; name = :impedance, kw...)
    return identify_rlc(model.value; name, kw...)
end
