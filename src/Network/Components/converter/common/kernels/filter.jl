############################  filter.jl  ############################

#=
Measurement filter specifications and state-space realization helpers.

This file defines reusable low-pass measurement filters for converter control
models. Filter specification objects are converted to state-space matrices by
[`measurement_filter_ss`](@ref).
=#

############################  Filter types  ############################

"""
$(TYPEDEF)

Abstract supertype for measurement filter specifications.
"""
abstract type AbstractMeasurementFilter end

"""
$(TYPEDEF)

Static pass-through measurement filter.

$(TYPEDFIELDS)
"""
@with_kw mutable struct NoFilter <: AbstractMeasurementFilter
    "State matrix; its coefficients depend on the realization coordinates."
    A::Matrix{Float64} = zeros(0, 0)
    "Input matrix; its coefficients depend on the realization coordinates."
    B::Matrix{Float64} = zeros(0, 1)
    "Output matrix; its coefficients depend on the realization coordinates."
    C::Matrix{Float64} = zeros(1, 0)
    "Direct input-to-output gain matrix \\[dimensionless\\]."
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

############################  Coefficient tables  ############################
# The floating point values were taken from SciPy.
# Each entry corresponds to one overall filter order.
# The stored tuples are the cascade sections:
#   (aᵢ, bᵢ)
# where
#   bᵢ = 0      -> first-order section    1 / (aᵢ*S + 1)
#   bᵢ ≠ 0      -> second-order section   1 / (bᵢ*S^2 + aᵢ*S + 1)
# with S = s / ω_f

"Normalized Butterworth section coefficients indexed by filter order \\[dimensionless\\]."
const BUTTERWORTH_TABLE = (
    ((1.0000, 0.0000),),
    ((1.4142135623730951, 1.0000000000000000),),
    ((1.0000, 0.0000), (1.0000, 1.0000)),
    ((1.8477590650225735, 1.0000000000000000), (0.7653668647301796, 1.0000000000000000)),
    ((1.0000000000000000, 0.0000000000000000), (1.6180339887498949, 1.0000000000000000), (0.6180339887498949, 1.0000000000000000)),
    ((1.9318516525781366, 1.0000000000000000), (1.4142135623730951, 1.0000000000000000), (0.5176380902050415, 1.0000000000000000))
)

"Normalized Chebyshev section coefficients indexed by filter order \\[dimensionless\\]."
const CHEBYSHEV_TABLE = (
    ((0.9976283451109836, 0.0000000000000000),),
    ((0.9109424019787794, 1.4125335626068893),),
    ((0.3558501550650937, 1.1916479367750799), (3.3487351903980445, 0.0000000000000000)),
    ((0.1886206299189319, 1.1073132983403204), (2.0983726255243650, 5.1025615414320170)),
    ((0.1172187536782796, 1.0683469690235923), (0.7619191964227391, 2.6524600893969073), (5.6328421682993770, 0.0000000000000000)),
    ((0.0800760434214973, 1.0473066248992997), (0.4003122538427246, 1.9163787969084394), (3.2132155032005600, 11.2606523445589170))
)

"Normalized Bessel section coefficients indexed by filter order \\[dimensionless\\]."
const BESSEL_TABLE = (
    ((1.0000000000000007, 0.0000000000000000),),
    ((1.3616541287161310, 0.6180339887498953),),
    ((0.7560431664869864, 0.0000000000000000), (0.9996292021942250, 0.4771913591204964)),
    ((1.3396637000153104, 0.4889041513645733), (0.7742539748889071, 0.3889907337152438)),
    ((0.6656387999023018, 0.0000000000000000), (1.1401766958285258, 0.4128450349918194), (0.6215952064218018, 0.3245329581029818)),
    ((1.2217343796721554, 0.3887183710638390), (0.9686070259812813, 0.3504726815531784), (0.5130536555494885, 0.2756407132488260))
)

"Normalized critically damped section coefficients indexed by filter order \\[dimensionless\\]."
const CRITICAL_DAMPING_TABLE = (
    ((1.0000000000000000, 0.0000000000000000),),
    ((1.2871885058111654, 0.4142135623730951),),
    ((0.5098245285339587, 0.0000000000000000), (1.0196490570679173, 0.2599210498948732)),
    ((0.8699588840921645, 0.1892071150027210), (0.8699588840921645, 0.1892071150027210)),
    ((0.3856142567346740, 0.0000000000000000), (0.7712285134693481, 0.1486983549970351), (0.7712285134693481, 0.1486983549970351)),
    ((0.6998915581984769, 0.1224620483093730), (0.6998915581984769, 0.1224620483093730), (0.6998915581984769, 0.1224620483093730))
)

############################  Table-based filter specs  ############################

"""
$(TYPEDEF)

Butterworth low-pass measurement filter specification.

$(TYPEDFIELDS)
"""
@with_kw mutable struct Butterworth <: AbstractMeasurementFilter
    "Filter order; the supplied coefficient tables cover orders one through six."
    order::Int = 1
    "Angular cutoff frequency \\[rad/s\\]."
    ωc::Float64 = 100 * π
    "Normalized cascade-section coefficients indexed by filter order \\[dimensionless\\]."
    table::Tuple = BUTTERWORTH_TABLE
    "State matrix; its coefficients depend on the realization coordinates."
    A::Matrix{Float64} = zeros(0, 0)
    "Input matrix; its coefficients depend on the realization coordinates."
    B::Matrix{Float64} = zeros(0, 1)
    "Output matrix; its coefficients depend on the realization coordinates."
    C::Matrix{Float64} = zeros(1, 0)
    "Direct input-to-output gain matrix \\[dimensionless\\]."
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

"""
$(TYPEDEF)

Chebyshev low-pass measurement filter specification.

$(TYPEDFIELDS)
"""
@with_kw mutable struct Chebyshev <: AbstractMeasurementFilter
    "Filter order; the supplied coefficient tables cover orders one through six."
    order::Int = 1
    "Angular cutoff frequency \\[rad/s\\]."
    ωc::Float64 = 100 * π
    "Normalized cascade-section coefficients indexed by filter order \\[dimensionless\\]."
    table::Tuple = CHEBYSHEV_TABLE
    "State matrix; its coefficients depend on the realization coordinates."
    A::Matrix{Float64} = zeros(0, 0)
    "Input matrix; its coefficients depend on the realization coordinates."
    B::Matrix{Float64} = zeros(0, 1)
    "Output matrix; its coefficients depend on the realization coordinates."
    C::Matrix{Float64} = zeros(1, 0)
    "Direct input-to-output gain matrix \\[dimensionless\\]."
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

"""
$(TYPEDEF)

Bessel low-pass measurement filter specification.

$(TYPEDFIELDS)
"""
@with_kw mutable struct Bessel <: AbstractMeasurementFilter
    "Filter order; the supplied coefficient tables cover orders one through six."
    order::Int = 1
    "Angular cutoff frequency \\[rad/s\\]."
    ωc::Float64 = 100 * π
    "Normalized cascade-section coefficients indexed by filter order \\[dimensionless\\]."
    table::Tuple = BESSEL_TABLE
    "State matrix; its coefficients depend on the realization coordinates."
    A::Matrix{Float64} = zeros(0, 0)
    "Input matrix; its coefficients depend on the realization coordinates."
    B::Matrix{Float64} = zeros(0, 1)
    "Output matrix; its coefficients depend on the realization coordinates."
    C::Matrix{Float64} = zeros(1, 0)
    "Direct input-to-output gain matrix \\[dimensionless\\]."
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

"""
$(TYPEDEF)

Critically damped low-pass measurement filter specification.

$(TYPEDFIELDS)
"""
@with_kw mutable struct CriticalDamping <: AbstractMeasurementFilter
    "Filter order; the supplied coefficient tables cover orders one through six."
    order::Int = 1
    "Angular cutoff frequency \\[rad/s\\]."
    ωc::Float64 = 100 * π
    "Normalized cascade-section coefficients indexed by filter order \\[dimensionless\\]."
    table::Tuple = CRITICAL_DAMPING_TABLE
    "State matrix; its coefficients depend on the realization coordinates."
    A::Matrix{Float64} = zeros(0, 0)
    "Input matrix; its coefficients depend on the realization coordinates."
    B::Matrix{Float64} = zeros(0, 1)
    "Output matrix; its coefficients depend on the realization coordinates."
    C::Matrix{Float64} = zeros(1, 0)
    "Direct input-to-output gain matrix \\[dimensionless\\]."
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end


##############################################  Implemenation of the Filter State Space  ###############################################
function measurement_filter_ss(filter::NoFilter)
    filter.A = zeros(Float64, 0, 0)
    filter.B = zeros(Float64, 0, 1)
    filter.C = zeros(Float64, 1, 0)
    filter.D = Matrix{Float64}(I, 1, 1)

    return filter
end

"""
$(TYPEDSIGNATURES)

Build the state-space realization of a table-based measurement filter.

# Arguments

- `filter`: Scalar measurement filter specification or realized filter.

# Returns

- The supplied filter, updated with state-space realization matrices.

# Notes

```math
G(s)=\\prod_k\\frac{1}{b_k(s/\\omega_c)^2+a_k(s/\\omega_c)+1}.
```

The order-indexed coefficient table supplies ``a_k,b_k`` \\[dimensionless\\]; a zero
``b_k`` gives a first-order section. The cutoff ``ω_c`` uses \\[rad/s\\]. `NoFilter` is a
zero-state unity-gain realization.

# Errors

- Throws `ArgumentError` when the order lies outside the coefficient table.

# Examples

```julia
using PowerImpedance
PowerImpedance.measurement_filter_ss(PowerImpedance.Butterworth(order=2, ωc=2π*100))
```
"""
function measurement_filter_ss(filter::AbstractMeasurementFilter)
    1 <= filter.order <= length(filter.table) || throw(ArgumentError(
        "Unsupported filter order $(filter.order). Supported orders are 1:$(length(filter.table))"
    ))

    ωf = filter.ωc
    sections = filter.table[filter.order]

    G = tf([1.0], [1.0])

    for (a, b) in sections
        G *= iszero(b) ?
            tf([ωf],   [a, ωf]) :
            tf([ωf^2], [b, a * ωf, ωf^2])
    end

    sys = ss(G)
    filter.A, filter.B, filter.C, filter.D = Matrix(sys.A), Matrix(sys.B), Matrix(sys.C), Matrix(sys.D)

    return filter
end

filter_statenames(prefix::Symbol, filter::AbstractMeasurementFilter) =
    ntuple(i -> Symbol("$(prefix)_x$i"), size(filter.A, 1))

voltage_filter_ratio(::Nothing) = 1.0
voltage_filter_ratio(::AbstractConverter) = 1.0

function filter_initialvalues(filter::NoFilter, names::NTuple{N, Symbol}, u0) where {N}
    return NamedTuple{names}(())
end

"""
$(TYPEDSIGNATURES)

Initialize the filter at a constant input by solving its equilibrium equation.

# Arguments

- `filter`: Scalar measurement filter specification or realized filter.
- `names`: State names in the filter realization order.
- `u0`: Constant filter input in the units of the measured signal.

# Returns

- Named tuple of equilibrium filter-state values in realization coordinates.

# Notes

```math
x_0=-A^{-1}Bu_0.
```

The returned coordinates are internal realization states. `NoFilter` has no states and
returns an empty named tuple. Singular state matrices propagate a linear-solve error.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
filter = P.measurement_filter_ss(P.Butterworth(order=2, ωc=2π*100))
names = P.filter_statenames(:voltage, filter)
x = P.filter_initialvalues(filter, names, 1.0)
@assert length(x) == 2
```
"""
function filter_initialvalues(filter::AbstractMeasurementFilter, names::NTuple{N, Symbol}, u0) where {N}
    x0 = Tuple(vec(-(filter.A \ (filter.B * [u0]))))
    return NamedTuple{names}(x0)
end

function filter_step!(F, offset::Integer, x, filter::NoFilter, names::NTuple{N, Symbol}, u) where {N}
    return u, offset
end

"""
$(TYPEDSIGNATURES)

Evaluate a scalar filter and write its state derivatives at the requested offset.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `offset`: First destination index for the filter derivatives.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `filter`: Scalar measurement filter specification or realized filter.
- `names`: State names in the filter realization order.
- `u`: Filter input in the units of the measured signal.

# Returns

- `y`: Filter output in the units of the input signal.
- `offset_next`: First unused derivative index.

# Notes

```math
\\dot{x}=Ax+Bu,\\qquad y=Cx+Du.
```

Time uses \\[s\\]. Realization-state units depend on the matrices; input and output have
the same physical signal units. A realization without states returns its direct output.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
filter = P.measurement_filter_ss(P.Butterworth(order=2, ωc=2π*100))
names = P.filter_statenames(:voltage, filter)
x = P.filter_initialvalues(filter, names, 1.0)
F = zeros(length(names))
output, next_index = P.filter_step!(F, 1, x, filter, names, 1.0)
@assert isapprox(output, 1.0)
```
"""
function filter_step!(F, offset::Integer, x, filter::AbstractMeasurementFilter, names::NTuple{N, Symbol}, u) where {N}
    xf = ntuple(i -> getfield(x, names[i]), Val(N))

    y = filter.D[1, 1] * u
    @inbounds for col in 1:N
        y += filter.C[1, col] * xf[col]
    end

    @inbounds for row in 1:N
        dx = filter.B[row, 1] * u
        for col in 1:N
            dx += filter.A[row, col] * xf[col]
        end
        F[offset + row - 1] = dx
    end

    return y, offset + N
end
