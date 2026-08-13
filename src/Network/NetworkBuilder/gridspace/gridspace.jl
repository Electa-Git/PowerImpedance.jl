"""
    Gridspace{T}

Represent a lazily materialized Cartesian product whose members have result
type `T`.

Deterministic iteration follows `Iterators.product`. Monte Carlo entry points
sample uncertain axes into ordinary numeric values before invoking `target`.
"""
struct Gridspace{T,Args<:Tuple,F,Names<:Tuple}
    target::F
    grids::Args
    names::Names
end

Gridspace{T}(grids::Args) where {T,Args<:Tuple} =
    Gridspace{T,Args,typeof(T),Tuple{}}(T, grids, ())

Gridspace{T}(target::F, grids::Args, names::Names = ()) where {T,F,Args<:Tuple,Names<:Tuple} =
    Gridspace{T,Args,F,Names}(target, grids, names)

Grid(g::Gridspace) = g

"""Normalize one shadow-constructor argument, keeping raw containers atomic."""
_axis(value::Union{AbstractGrid,Gridspace}) = value
_axis(value) = DeterministicGrid((value,))

_materialize(g::Gridspace, args::Tuple) = g.target(args...)

function Base.iterate(g::Gridspace)
    item = iterate(Iterators.product(g.grids...))
    item === nothing && return nothing
    args, state = item
    return _materialize(g, args), state
end

function Base.iterate(g::Gridspace, state)
    item = iterate(Iterators.product(g.grids...), state)
    item === nothing && return nothing
    args, next_state = item
    return _materialize(g, args), next_state
end

Base.IteratorSize(::Type{<:Gridspace}) = Base.HasShape{1}()
Base.length(g::Gridspace) = isempty(g.grids) ? 1 : prod(length, g.grids)
Base.size(g::Gridspace) = (length(g),)
Base.eltype(::Type{<:Gridspace{T}}) where {T} = T

function Base.getindex(g::Gridspace, i::Integer)
    1 <= i <= length(g) || throw(BoundsError(g, i))
    return first(Iterators.drop(g, i - 1))
end

function Base.rand(
    rng::Random.AbstractRNG,
    g::Gridspace;
    distribution::Symbol = :normal,
    dist = nothing,
)
    dist === nothing || (distribution = _distribution_symbol(dist))
    values = map(g.grids) do axis
        if axis isa Gridspace
            rand(rng, axis; distribution)
        elseif axis isa AbstractUncertainGrid
            rand(rng, axis; distribution)
        else
            rand(rng, axis)
        end
    end
    return _materialize(g, values)
end

Base.rand(g::Gridspace; kwargs...) = rand(Random.default_rng(), g; kwargs...)
Base.rand(rng::Random.AbstractRNG, g::Gridspace, distribution::Type) =
    rand(rng, g; distribution = _distribution_symbol(distribution))
Base.rand(g::Gridspace, distribution::Type) = rand(Random.default_rng(), g, distribution)
