import Base: eltype, extrema, getindex, iterate, length, rand, size
import Random
abstract type AbstractGrid end
abstract type AbstractUncertainGrid <: AbstractGrid end

abstract type AbstractUncertainty end

struct RelativeUncertainty{T <: Real} <: AbstractUncertainty
    percent::T
end

struct AbsoluteUncertainty <: AbstractUncertainty end

"""
$(TYPEDEF)

Store a dependency-free uncertainty descriptor. `sigma` is an absolute
standard uncertainty in the same physical unit as `nominal`.

$(TYPEDFIELDS)
"""
struct UncertainValue{T, S <: AbstractUncertainty, E}
    "Nominal parameter value."
    nominal::T

    "Absolute standard uncertainty in the same physical unit as `nominal`."
    sigma::E

    "Origin of the uncertainty declaration."
    style::S

    function UncertainValue(nominal::T, sigma::E, style::S) where {
            T, S <: AbstractUncertainty, E
    }
        if nominal isa Real && sigma isa Real
            isfinite(nominal) || throw(ArgumentError(
                "uncertain nominal values must be finite; got $nominal",
            ))
            isfinite(sigma) || throw(ArgumentError(
                "uncertainty must be finite; got $sigma",
            ))
            sigma >= zero(sigma) || throw(ArgumentError(
                "uncertainty must be nonnegative; got $sigma",
            ))
        end
        return new{T, S, E}(nominal, sigma, style)
    end
end

nominal(value::UncertainValue) = value.nominal
standard_uncertainty(value::UncertainValue) = value.sigma
uncertainty_style(value::UncertainValue) = value.style

struct AutomaticGridKey
    token::Base.RefValue{Nothing}
end

Base.:(==)(left::AutomaticGridKey, right::AutomaticGridKey) = left.token === right.token
Base.isequal(left::AutomaticGridKey, right::AutomaticGridKey) = left == right
Base.hash(key::AutomaticGridKey, seed::UInt) = hash(objectid(key.token), seed)

struct NamedGridKey{K}
    value::K
end

_grid_key(::Nothing) = AutomaticGridKey(Ref(nothing))
_grid_key(key) = NamedGridKey(key)

"""
    DeterministicGrid

Represent a finite, explicitly enumerated parameter axis.

Use [`Grid`](@ref) to construct this type from one value or a collection of
alternatives.
"""
struct DeterministicGrid{V <: Tuple, K} <: AbstractGrid
    vals::V
    key::K
end

"""
    RelativeGrid

Represent the Cartesian product of nominal values and relative standard
deviations expressed in percent.

Monte Carlo entry points sample each case with `distribution=:normal` or with
the variance-equivalent `distribution=:uniform` law.
"""
struct RelativeGrid{V <: Tuple, P <: Tuple, K} <: AbstractUncertainGrid
    vals::V
    rel_err::P
    key::K

    @doc """
        RelativeGrid(vals::V, rel_err::P) where {V<:Tuple,P<:Tuple}

    Construct a relative-uncertainty axis from tuple-valued nominal values and
    percentage standard deviations.

    # Errors

    - Throws `ArgumentError` for non-real or non-finite nominal values, or for
      non-real, non-finite, or negative uncertainty values.
    """
    function RelativeGrid(vals::V, rel_err::P, key::K) where {V <: Tuple, P <: Tuple, K}
        _validate_uncertainty(vals, rel_err, "relative")
        return new{V, P, K}(vals, rel_err, key)
    end
end

"""
    AbsoluteGrid

Represent the Cartesian product of nominal values and absolute standard
deviations in the same physical unit as the nominal value.

Monte Carlo entry points sample each case with `distribution=:normal` or with
the variance-equivalent `distribution=:uniform` law.
"""
struct AbsoluteGrid{V <: Tuple, P <: Tuple, K} <: AbstractUncertainGrid
    vals::V
    abs_err::P
    key::K

    @doc """
        AbsoluteGrid(vals::V, abs_err::P) where {V<:Tuple,P<:Tuple}

    Construct an absolute-uncertainty axis from tuple-valued nominal values and
    standard deviations expressed in the same physical units.

    # Errors

    - Throws `ArgumentError` for non-real or non-finite nominal values, or for
      non-real, non-finite, or negative uncertainty values.
    """
    function AbsoluteGrid(vals::V, abs_err::P, key::K) where {V <: Tuple, P <: Tuple, K}
        _validate_uncertainty(vals, abs_err, "absolute")
        return new{V, P, K}(vals, abs_err, key)
    end
end

"""
    AbsoluteError(errors)

Mark nonnegative `errors` as absolute standard deviations in the same physical
unit as the corresponding nominal values.
"""
struct AbsoluteError{T <: Tuple}
    vals::T

    @doc """
        AbsoluteError(vals::T) where {T<:Tuple}

    Construct an absolute-error marker from tuple-valued standard deviations.

    # Errors

    - Throws `ArgumentError` for non-real, non-finite, or negative values.
    """
    function AbsoluteError(vals::T) where {T <: Tuple}
        _validate_errors(vals, "absolute")
        return new{T}(vals)
    end
end

_grid_values(x::Tuple) = x
_grid_values(x::AbstractArray) = Tuple(x)
_grid_values(x) = (x,)

function _validate_errors(errors::Tuple, kind::AbstractString)
    for error in errors
        error isa Real ||
            throw(ArgumentError("$kind errors must be real numbers; got $(typeof(error))"))
        isfinite(error) || throw(ArgumentError("$kind errors must be finite; got $error"))
        error >= zero(error) ||
            throw(ArgumentError("$kind errors must be nonnegative; got $error"))
    end
    return nothing
end

function _validate_uncertainty(vals::Tuple, errors::Tuple, kind::AbstractString)
    _validate_errors(errors, kind)
    for nominal in vals
        nominal isa Real ||
            throw(ArgumentError("$kind uncertainty requires real nominal values; got $(typeof(nominal))"))
        isfinite(nominal) ||
            throw(ArgumentError("$kind nominal values must be finite; got $nominal"))
    end
    return nothing
end

AbsoluteError(x) = AbsoluteError(_grid_values(x))

"""
    Grid(values)
    Grid(values, relative_errors)
    Grid(values, AbsoluteError(errors))
    component(Grid, keyword arguments...)

Create an explicit deterministic or uncertain parameter axis. Collections passed directly to `Grid` are expanded. Component Gridspace constructors retain ordinary collections as one atomic value.

# Arguments

- `values`: one nominal value or a collection of explicitly enumerated values.
- `relative_errors`: relative standard deviations in percent.
- `errors`: an [`AbsoluteError`](@ref) containing standard deviations in the
  physical unit of `values`.

# Returns

- A [`DeterministicGrid`](@ref), [`RelativeGrid`](@ref), or
  [`AbsoluteGrid`](@ref).

Passing the `Grid` function itself as the first positional argument to any
component or configuration constructor selects its lazy NetworkBuilder method.
The call `impedance(Grid, z=Grid([1.0, 2.0]), pins=1)` returns a Gridspace.
Calling `impedance(z=1.0, pins=1)` uses the scalar constructor. Julia does not
dispatch on keyword argument types, so the positional marker selects the lazy
method.

# Notes

The sampling law is selected by the Monte Carlo entry point. `:normal` uses
`Normal(nominal, standard_deviation)`. `:uniform` uses the interval
`nominal ± √3 standard_deviation`, which has the same variance. Separate
Gridspace axes are sampled independently unless a purpose-built object provides
specialized joint-sampling dispatch.
"""
function Grid(grid::AbstractGrid; key = nothing)
    key === nothing ? grid :
    throw(ArgumentError("cannot replace the coupling key of an existing Grid"))
end
Grid(value; key = nothing) = DeterministicGrid(_grid_values(value), _grid_key(key))
function Grid(value, relative_error; key = nothing)
    RelativeGrid(_grid_values(value), _grid_values(relative_error), _grid_key(key))
end
function Grid(value, error::AbsoluteError; key = nothing)
    AbsoluteGrid(_grid_values(value), error.vals, _grid_key(key))
end

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

function iterate(grid::RelativeGrid, state...)
    item = iterate(Iterators.product(grid.vals, grid.rel_err), state...)
    item === nothing && return nothing
    (value, percent), next_state = item
    sigma = abs(value) * percent / 100
    return UncertainValue(value, sigma, RelativeUncertainty(percent)), next_state
end

function iterate(grid::AbsoluteGrid, state...)
    item = iterate(Iterators.product(grid.vals, grid.abs_err), state...)
    item === nothing && return nothing
    (value, error), next_state = item
    return UncertainValue(value, error, AbsoluteUncertainty()), next_state
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

function _sample_uncertainty(
        rng::Random.AbstractRNG,
        value::UncertainValue{<:Real, <:AbstractUncertainty, <:Real},
        distribution::Symbol
)
    distribution === :normal && return value.nominal + value.sigma * randn(rng)
    distribution === :uniform &&
        return value.nominal + sqrt(3) * value.sigma * (2 * rand(rng) - 1)
    throw(ArgumentError(
        "unsupported distribution :$distribution; expected :normal or :uniform",
    ))
end

function _standard_uncertainty_draw(rng::Random.AbstractRNG, distribution::Symbol)
    distribution === :normal && return randn(rng)
    distribution === :uniform && return sqrt(3) * (2 * rand(rng) - 1)
    throw(ArgumentError(
        "unsupported distribution :$distribution; expected :normal or :uniform",
    ))
end

function _realize_uncertainty(value::UncertainValue, standardized::Real)
    value.nominal + value.sigma * standardized
end

function rand(
        rng::Random.AbstractRNG,
        value::UncertainValue{<:Real};
        distribution = :normal
)
    iszero(value.sigma) && return float(value.nominal)
    return _realize_uncertainty(value, _standard_uncertainty_draw(rng, distribution))
end

rand(value::UncertainValue; kwargs...) = rand(Random.default_rng(), value; kwargs...)

function rand(rng::Random.AbstractRNG, grid::AbstractGrid; distribution = :normal)
    length(grid) == 1 || throw(ArgumentError(
        "rand(Grid) requires one configuration; select a configuration before sampling",
    ))
    value = first(grid)
    return value isa UncertainValue ? rand(rng, value; distribution) : value
end

rand(grid::AbstractGrid; kwargs...) = rand(Random.default_rng(), grid; kwargs...)

"""Convert numeric leaves to `T` while retaining container structure."""
recast(::Type{T}, x::Number) where {T <: Real} = convert(T, x)
recast(::Type{T}, x::AbstractArray) where {T <: Real} = map(value -> recast(T, value), x)
recast(::Type{T}, x::Tuple) where {T <: Real} = map(value -> recast(T, value), x)
recast(::Type{T}, x::NamedTuple) where {T <: Real} = map(value -> recast(T, value), x)
recast(::Type{<:Real}, x) = x

_relax_eltype(x::Number) = typeof(x)
_relax_eltype(x::AbstractArray) = eltype(x) <: Number ? eltype(x) : Union{}
_relax_eltype(x::Tuple) = isempty(x) ? Union{} : promote_type(map(_relax_eltype, x)...)
_relax_eltype(x) =
    try
        T = eltype(typeof(x))
        T <: Number ? T : Union{}
    catch
        Union{}
    end
