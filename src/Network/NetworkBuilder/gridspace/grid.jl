import Base: eltype, extrema, getindex, iterate, length, rand, size
import Random
import Distributions

abstract type AbstractGrid end
abstract type AbstractUncertainGrid <: AbstractGrid end

"""A finite, explicitly enumerated parameter axis."""
struct DeterministicGrid{V<:Tuple} <: AbstractGrid
    vals::V
end

"""A Cartesian axis of nominal values and relative standard deviations (percent)."""
struct RelativeGrid{V<:Tuple,P<:Tuple} <: AbstractUncertainGrid
    vals::V
    rel_err::P

    function RelativeGrid(vals::V, rel_err::P) where {V<:Tuple,P<:Tuple}
        _validate_uncertainty(vals, rel_err, "relative")
        return new{V,P}(vals, rel_err)
    end
end

"""A Cartesian axis of nominal values and absolute standard deviations."""
struct AbsoluteGrid{V<:Tuple,P<:Tuple} <: AbstractUncertainGrid
    vals::V
    abs_err::P

    function AbsoluteGrid(vals::V, abs_err::P) where {V<:Tuple,P<:Tuple}
        _validate_uncertainty(vals, abs_err, "absolute")
        return new{V,P}(vals, abs_err)
    end
end

"""Mark an uncertainty argument as an absolute standard deviation."""
struct AbsoluteError{T<:Tuple}
    vals::T

    function AbsoluteError(vals::T) where {T<:Tuple}
        _validate_errors(vals, "absolute")
        return new{T}(vals)
    end
end

_grid_values(x::Tuple) = x
_grid_values(x::AbstractArray) = Tuple(x)
_grid_values(x) = (x,)

function _validate_errors(errors::Tuple, kind::AbstractString)
    for error in errors
        error isa Real || throw(ArgumentError("$kind errors must be real numbers; got $(typeof(error))"))
        isfinite(error) || throw(ArgumentError("$kind errors must be finite; got $error"))
        error >= zero(error) || throw(ArgumentError("$kind errors must be nonnegative; got $error"))
    end
    return nothing
end

function _validate_uncertainty(vals::Tuple, errors::Tuple, kind::AbstractString)
    _validate_errors(errors, kind)
    for nominal in vals
        nominal isa Real || throw(ArgumentError("$kind uncertainty requires real nominal values; got $(typeof(nominal))"))
        isfinite(nominal) || throw(ArgumentError("$kind nominal values must be finite; got $nominal"))
    end
    return nothing
end

AbsoluteError(x) = AbsoluteError(_grid_values(x))

"""
    Grid(values)
    Grid(values, relative_errors)
    Grid(values, AbsoluteError(errors))

Create an explicit deterministic or uncertain parameter axis. Collections passed
directly to `Grid` are expanded; component shadow constructors deliberately wrap
ordinary collections as one atomic value.
"""
Grid(g::AbstractGrid) = g
Grid(v) = DeterministicGrid(_grid_values(v))
Grid(v, p) = RelativeGrid(_grid_values(v), _grid_values(p))
Grid(v, error::AbsoluteError) = AbsoluteGrid(_grid_values(v), error.vals)

iterate(g::DeterministicGrid, state...) = iterate(g.vals, state...)
length(g::DeterministicGrid) = length(g.vals)
size(g::DeterministicGrid) = (length(g),)
getindex(g::DeterministicGrid, i::Integer) = g.vals[i]
eltype(::Type{<:DeterministicGrid{V}}) where {V} = eltype(V)
Base.IteratorSize(::Type{<:DeterministicGrid}) = Base.HasShape{1}()

length(g::RelativeGrid) = length(g.vals) * length(g.rel_err)
length(g::AbsoluteGrid) = length(g.vals) * length(g.abs_err)
size(g::AbstractUncertainGrid) = (length(g),)
Base.IteratorSize(::Type{<:AbstractUncertainGrid}) = Base.HasShape{1}()

function iterate(::AbstractUncertainGrid, state...)
    throw(ArgumentError(
        "uncertain grid iteration requires Measurements.jl; load it with `using Measurements`",
    ))
end

function getindex(g::AbstractUncertainGrid, i::Integer)
    i < 1 && throw(BoundsError(g, i))
    item = iterate(g)
    item === nothing && throw(BoundsError(g, i))
    for _ in 2:i
        item = iterate(g, item[2])
        item === nothing && throw(BoundsError(g, i))
    end
    return item[1]
end

extrema(g::DeterministicGrid) = extrema(g.vals)

function extrema(g::RelativeGrid)
    isempty(g.vals) && throw(ArgumentError("an empty grid has no extrema"))
    isempty(g.rel_err) && throw(ArgumentError("an empty grid has no extrema"))
    bounds = map(Iterators.product(g.vals, g.rel_err)) do (v, p)
        delta = abs(v) * p / 100
        (v - delta, v + delta)
    end
    return minimum(first, bounds), maximum(last, bounds)
end

function extrema(g::AbsoluteGrid)
    isempty(g.vals) && throw(ArgumentError("an empty grid has no extrema"))
    isempty(g.abs_err) && throw(ArgumentError("an empty grid has no extrema"))
    bounds = map(Iterators.product(g.vals, g.abs_err)) do (v, error)
        (v - error, v + error)
    end
    return minimum(first, bounds), maximum(last, bounds)
end

_distribution(::Val{:normal}, nominal, sigma) = Distributions.Normal(nominal, sigma)
_distribution(::Val{:uniform}, nominal, sigma) =
    Distributions.Uniform(nominal - sqrt(3) * sigma, nominal + sqrt(3) * sigma)

function _distribution(distribution::Symbol, nominal, sigma)
    distribution in (:normal, :uniform) || throw(ArgumentError(
        "unsupported distribution :$distribution; expected :normal or :uniform",
    ))
    return _distribution(Val(distribution), nominal, sigma)
end

_distribution_symbol(::Type{<:Distributions.Normal}) = :normal
_distribution_symbol(::Type{<:Distributions.Uniform}) = :uniform
_distribution_symbol(distribution::Symbol) = distribution

function rand(
    rng::Random.AbstractRNG,
    g::DeterministicGrid;
    distribution::Symbol = :normal,
    dist = nothing,
)
    return rand(rng, g.vals)
end
rand(g::DeterministicGrid; kwargs...) = rand(Random.default_rng(), g; kwargs...)
rand(rng::Random.AbstractRNG, g::DeterministicGrid, ::Type) = rand(rng, g)
rand(g::DeterministicGrid, distribution::Type) =
    rand(Random.default_rng(), g, distribution)

function rand(
    rng::Random.AbstractRNG,
    g::RelativeGrid;
    distribution::Symbol = :normal,
    dist = nothing,
)
    dist === nothing || (distribution = _distribution_symbol(dist))
    nominal = rand(rng, g.vals)
    relative_error = rand(rng, g.rel_err)
    sigma = abs(nominal) * relative_error / 100
    return iszero(sigma) ? float(nominal) : rand(rng, _distribution(distribution, nominal, sigma))
end

function rand(
    rng::Random.AbstractRNG,
    g::AbsoluteGrid;
    distribution::Symbol = :normal,
    dist = nothing,
)
    dist === nothing || (distribution = _distribution_symbol(dist))
    nominal = rand(rng, g.vals)
    sigma = rand(rng, g.abs_err)
    return iszero(sigma) ? float(nominal) : rand(rng, _distribution(distribution, nominal, sigma))
end

rand(g::AbstractUncertainGrid; kwargs...) = rand(Random.default_rng(), g; kwargs...)
rand(rng::Random.AbstractRNG, g::AbstractUncertainGrid, distribution::Type) =
    rand(rng, g; distribution = _distribution_symbol(distribution))
rand(g::AbstractUncertainGrid, distribution::Type) =
    rand(Random.default_rng(), g, distribution)

"""Convert numeric leaves to `T` while retaining container structure."""
recast(::Type{T}, x::Number) where {T<:Real} = convert(T, x)
recast(::Type{T}, x::AbstractArray) where {T<:Real} = map(value -> recast(T, value), x)
recast(::Type{T}, x::Tuple) where {T<:Real} = map(value -> recast(T, value), x)
recast(::Type{T}, x::NamedTuple) where {T<:Real} = map(value -> recast(T, value), x)
recast(::Type{<:Real}, x) = x

_relax_eltype(x::Number) = typeof(x)
_relax_eltype(x::AbstractArray) = eltype(x) <: Number ? eltype(x) : Union{}
_relax_eltype(x::Tuple) = isempty(x) ? Union{} : promote_type(map(_relax_eltype, x)...)
_relax_eltype(x) = try
    T = eltype(typeof(x))
    T <: Number ? T : Union{}
catch
    Union{}
end
