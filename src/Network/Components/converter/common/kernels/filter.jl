############################  filter.jl  ############################

#=
Measurement filter specifications and state-space realization helpers.

This file defines reusable low-pass measurement filters for converter control
models. Filter specification objects are converted to state-space matrices by
[`measurement_filter_ss`](@ref).
=#

############################  Filter types  ############################

"""
Abstract supertype for measurement filter specifications.
"""
abstract type AbstractMeasurementFilter end

"""
Static pass-through measurement filter.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw mutable struct NoFilter <: AbstractMeasurementFilter
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
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

"""
Normalized Butterworth section coefficients indexed by filter order.
"""
const BUTTERWORTH_TABLE = (
    ((1.0000, 0.0000),),
    ((1.4142135623730951, 1.0000000000000000),),
    ((1.0000, 0.0000), (1.0000, 1.0000)),
    ((1.8477590650225735, 1.0000000000000000), (0.7653668647301796, 1.0000000000000000)),
    ((1.0000000000000000, 0.0000000000000000), (1.6180339887498949, 1.0000000000000000), (0.6180339887498949, 1.0000000000000000)),
    ((1.9318516525781366, 1.0000000000000000), (1.4142135623730951, 1.0000000000000000), (0.5176380902050415, 1.0000000000000000))
)

"""
Normalized Chebyshev section coefficients indexed by filter order.
"""
const CHEBYSHEV_TABLE = (
    ((0.9976283451109836, 0.0000000000000000),),
    ((0.9109424019787794, 1.4125335626068893),),
    ((0.3558501550650937, 1.1916479367750799), (3.3487351903980445, 0.0000000000000000)),
    ((0.1886206299189319, 1.1073132983403204), (2.0983726255243650, 5.1025615414320170)),
    ((0.1172187536782796, 1.0683469690235923), (0.7619191964227391, 2.6524600893969073), (5.6328421682993770, 0.0000000000000000)),
    ((0.0800760434214973, 1.0473066248992997), (0.4003122538427246, 1.9163787969084394), (3.2132155032005600, 11.2606523445589170))
)

"""
Normalized Bessel section coefficients indexed by filter order.
"""
const BESSEL_TABLE = (
    ((1.0000000000000007, 0.0000000000000000),),
    ((1.3616541287161310, 0.6180339887498953),),
    ((0.7560431664869864, 0.0000000000000000), (0.9996292021942250, 0.4771913591204964)),
    ((1.3396637000153104, 0.4889041513645733), (0.7742539748889071, 0.3889907337152438)),
    ((0.6656387999023018, 0.0000000000000000), (1.1401766958285258, 0.4128450349918194), (0.6215952064218018, 0.3245329581029818)),
    ((1.2217343796721554, 0.3887183710638390), (0.9686070259812813, 0.3504726815531784), (0.5130536555494885, 0.2756407132488260))
)

"""
Normalized critically damped section coefficients indexed by filter order.
"""
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
Butterworth low-pass measurement filter specification.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw mutable struct Butterworth <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = BUTTERWORTH_TABLE
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

"""
Chebyshev low-pass measurement filter specification.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw mutable struct Chebyshev <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = CHEBYSHEV_TABLE
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

"""
Bessel low-pass measurement filter specification.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw mutable struct Bessel <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = BESSEL_TABLE
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

"""
Critically damped low-pass measurement filter specification.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw mutable struct CriticalDamping <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = CRITICAL_DAMPING_TABLE
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end


##############################################  Implemenation of the Filter State Space  ###############################################
"""
Build the state-space realization of a measurement filter.

$(SIGNATURES)

# Details

`NoFilter()` gives a static pass-through. Table-based filters are assembled from
normalized sections `G(S) = ∏ 1 / (bᵢ S² + aᵢ S + 1)`, with `S = s / ωf`.
The filter object is updated in-place and returned.
"""
function measurement_filter_ss(filter::NoFilter)
    filter.A = zeros(Float64, 0, 0)
    filter.B = zeros(Float64, 0, 1)
    filter.C = zeros(Float64, 1, 0)
    filter.D = Matrix{Float64}(I, 1, 1)

    return filter
end

"""
Build the state-space realization of a table-based measurement filter.

$(SIGNATURES)
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
