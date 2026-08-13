import Base: eltype, extrema, getindex, iterate, length, rand, size
import Random
import Distributions

abstract type AbstractGrid end
abstract type AbstractUncertainGrid <: AbstractGrid end

"""
    DeterministicGrid

Represent a finite, explicitly enumerated parameter axis.

Use [`Grid`](@ref) to construct this type from one value or a collection of
alternatives.
"""
struct DeterministicGrid{V<:Tuple} <: AbstractGrid
    vals::V
end

"""
    RelativeGrid

Represent the Cartesian product of nominal values and relative standard
deviations expressed in percent.

Monte Carlo entry points sample each case with `distribution=:normal` or with
the variance-equivalent `distribution=:uniform` law.
"""
struct RelativeGrid{V<:Tuple,P<:Tuple} <: AbstractUncertainGrid
    vals::V
    rel_err::P

    @doc """
        RelativeGrid(vals::V, rel_err::P) where {V<:Tuple,P<:Tuple}

    Construct a relative-uncertainty axis from tuple-valued nominal values and
    percentage standard deviations.

    # Errors

    - Throws `ArgumentError` for non-real or non-finite nominal values, or for
      non-real, non-finite, or negative uncertainty values.
    """
    function RelativeGrid(vals::V, rel_err::P) where {V<:Tuple,P<:Tuple}
        _validate_uncertainty(vals, rel_err, "relative")
        return new{V,P}(vals, rel_err)
    end
end

"""
    AbsoluteGrid

Represent the Cartesian product of nominal values and absolute standard
deviations in the same physical unit as the nominal value.

Monte Carlo entry points sample each case with `distribution=:normal` or with
the variance-equivalent `distribution=:uniform` law.
"""
struct AbsoluteGrid{V<:Tuple,P<:Tuple} <: AbstractUncertainGrid
    vals::V
    abs_err::P

    @doc """
        AbsoluteGrid(vals::V, abs_err::P) where {V<:Tuple,P<:Tuple}

    Construct an absolute-uncertainty axis from tuple-valued nominal values and
    standard deviations expressed in the same physical units.

    # Errors

    - Throws `ArgumentError` for non-real or non-finite nominal values, or for
      non-real, non-finite, or negative uncertainty values.
    """
    function AbsoluteGrid(vals::V, abs_err::P) where {V<:Tuple,P<:Tuple}
        _validate_uncertainty(vals, abs_err, "absolute")
        return new{V,P}(vals, abs_err)
    end
end

"""
    AbsoluteError(errors)

Mark nonnegative `errors` as absolute standard deviations in the same physical
unit as the corresponding nominal values.
"""
struct AbsoluteError{T<:Tuple}
    vals::T

    @doc """
        AbsoluteError(vals::T) where {T<:Tuple}

    Construct an absolute-error marker from tuple-valued standard deviations.

    # Errors

    - Throws `ArgumentError` for non-real, non-finite, or negative values.
    """
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
    component(Grid; kwargs...)

Create an explicit deterministic or uncertain parameter axis. Collections passed
directly to `Grid` are expanded; component shadow constructors deliberately wrap
ordinary collections as one atomic value.

# Arguments

- `values`: One nominal value or a collection of explicitly enumerated values.
- `relative_errors`: Relative standard deviations in percent.
- `errors`: An [`AbsoluteError`](@ref) containing standard deviations in the
  physical unit of `values`.

# Returns

- A [`DeterministicGrid`](@ref), [`RelativeGrid`](@ref), or
  [`AbsoluteGrid`](@ref).

Passing the `Grid` function itself as the first positional argument to any
component or configuration constructor selects its lazy NetworkBuilder method.
For example, `impedance(Grid; z=Grid([1.0, 2.0]), pins=1)` returns a Gridspace,
whereas `impedance(; z=1.0, pins=1)` remains the scalar constructor. Julia does
not dispatch on keyword argument types, so this marker makes the selection
explicit and uniform.

# Notes

The sampling law is selected by the Monte Carlo entry point. `:normal` uses
`Normal(nominal, standard_deviation)`. `:uniform` uses the interval
`nominal ± √3 standard_deviation`, which has the same variance. Separate
Gridspace axes are sampled independently unless a purpose-built object provides
specialized joint-sampling dispatch.
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
