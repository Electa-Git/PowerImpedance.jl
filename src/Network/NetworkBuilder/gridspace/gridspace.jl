"Typed blueprint interface for staged construction of a concrete `Target`."
abstract type AbstractSpec{Target} end

target_type(::Type{<:AbstractSpec{Target}}) where {Target} = Target
target_type(spec::AbstractSpec) = target_type(typeof(spec))

struct ConstantAxis{T}
    value::T
end

Base.iterate(axis::ConstantAxis) = (axis.value, nothing)
Base.iterate(::ConstantAxis, ::Nothing) = nothing
Base.length(::ConstantAxis) = 1
Base.getindex(axis::ConstantAxis, index::Integer) =
    index == 1 ? axis.value : throw(BoundsError(axis, index))

struct GridBinding{K}
    key::K
    index::Int
    cardinality::Int
end

"""
$(TYPEDEF)

Represent one resolved deterministic choice while retaining uncertainty
descriptors for later materialization or sampling.

$(TYPEDFIELDS)
"""
struct Configuration{Target,F,V<:Tuple,N<:Tuple,B<:Tuple}
    "Callable that constructs `Target` from the resolved axis values."
    target::F

    "Resolved values supplied to `target`."
    values::V

    "Parameter names corresponding to `values`."
    names::N

    "Selections retained for coupled axes."
    bindings::B
end


target_type(::Type{<:Configuration{Target}}) where {Target} = Target
target_type(configuration::Configuration) = target_type(typeof(configuration))

function Configuration{Target}(target::F, values::V, names::N, bindings::B) where {
    Target,F,V<:Tuple,N<:Tuple,B<:Tuple
}
    return Configuration{Target,F,V,N,B}(target, values, names, bindings)
end

"""
$(TYPEDEF)

Represent a lazy space of complete `Target` configurations. `combine` is local
to this space and is either `:product` or `:zip`.

$(TYPEDFIELDS)
"""
struct Gridspace{Target,F,A<:Tuple,N<:Tuple,C} <: AbstractSpec{Target}
    "Callable that constructs `Target` from one selection of the direct axes."
    target::F

    "Direct parameter or object-valued axes."
    axes::A

    "Parameter names corresponding to `axes`."
    names::N

    "Local composition rule represented by `Val{:product}` or `Val{:zip}`."
    combine::C
end


function Gridspace{Target}(
    target::F,
    axes::A,
    names::N=();
    combine::Symbol=:product,
) where {Target,F,A<:Tuple,N<:Tuple}
    combine in (:product, :zip) || throw(ArgumentError(
        "combine must be :product or :zip; got :$combine",
    ))
    isempty(names) || length(names) == length(axes) || throw(DimensionMismatch(
        "Gridspace names and axes must have equal lengths",
    ))
    normalized_axes = map(_gridspace_axis, axes)
    normalized_names = isempty(names) ?
        ntuple(index -> Symbol(:arg, index), length(axes)) : names
    return Gridspace{
        Target,
        F,
        typeof(normalized_axes),
        typeof(normalized_names),
        Val{combine},
    }(
        target,
        normalized_axes,
        normalized_names,
        Val(combine),
    )
end

Gridspace{Target}(axes::Tuple; combine::Symbol=:product) where {Target} =
    Gridspace{Target}(Target, axes; combine)

Grid(space::Gridspace; key=nothing) = key === nothing ? space :
    throw(ArgumentError("Gridspace coupling is defined by its child Grids"))

_gridspace_axis(value::ConstantAxis) = value
_gridspace_axis(value::Union{AbstractGrid,AbstractSpec}) = value
_gridspace_axis(value) = ConstantAxis(value)

# Retained for internal constructor code while the Gridspace implementation is
# owned by Grammar.
_axis(value) = _gridspace_axis(value)

struct AxisSelection{V,K}
    value::V
    key::K
    index::Int
    cardinality::Int
end

"A resolved axis value retaining its coupling identity for realization."
struct ResolvedGridValue{V,K}
    value::V
    key::K
end

_axis_cases(axis::ConstantAxis) = axis

function _axis_cases(grid::AbstractGrid)
    return (
        AxisSelection(value, grid.key, index, length(grid))
        for (index, value) in enumerate(grid)
    )
end

_axis_cases(spec::AbstractSpec) = configurations(spec)

_axis_value(selection::AxisSelection) = ResolvedGridValue(selection.value, selection.key)
_axis_value(configuration::Configuration) = configuration
_axis_value(value) = value

_axis_bindings(selection::AxisSelection) =
    (GridBinding(selection.key, selection.index, selection.cardinality),)
_axis_bindings(configuration::Configuration) = configuration.bindings
_axis_bindings(::Any) = ()

_same_grid_key(left, right) = left == right

function _compatible_bindings(items::Tuple)
    groups = tuple((_axis_bindings(item) for item in items)...)
    bindings = tuple(Iterators.flatten(groups)...)
    for first_index in eachindex(bindings)
        for second_index in (first_index + 1):length(bindings)
            first = bindings[first_index]
            second = bindings[second_index]
            if _same_grid_key(first.key, second.key)
                first.cardinality == second.cardinality || throw(DimensionMismatch(
                    "coupled Grids have incompatible cardinalities " *
                    "$(first.cardinality) and $(second.cardinality)",
                ))
                first.index != second.index && return false
            end
        end
    end
    return true
end

function _merged_bindings(items::Tuple)
    groups = tuple((_axis_bindings(item) for item in items)...)
    all_bindings = tuple(Iterators.flatten(groups)...)
    return tuple((
        binding for (index, binding) in pairs(all_bindings)
        if all(
            previous -> !_same_grid_key(previous.key, binding.key),
            all_bindings[1:(index - 1)],
        )
    )...)
end

function _product_combinations(axes::Tuple)
    isempty(axes) && return ((),)
    return Iterators.product(map(_axis_cases, axes)...)
end

function _nth(iterator, index::Int)
    item = iterate(Iterators.drop(iterator, index - 1))
    item === nothing && throw(BoundsError(iterator, index))
    return item[1]
end

function _zip_combinations(axes::Tuple, names::Tuple)
    isempty(axes) && return ((),)
    iterators = map(_axis_cases, axes)
    counts = map(length, axes)
    target_count = maximum(counts)
    for index in eachindex(counts)
        counts[index] in (1, target_count) || throw(DimensionMismatch(
            "zip axis $(names[index]) has cardinality $(counts[index]); " *
            "expected 1 or $target_count",
        ))
    end
    return (
        map(
            (iterator, count) -> _nth(iterator, count == 1 ? 1 : row),
            iterators,
            counts,
        )
        for row in 1:target_count
    )
end

_combinations(space::Gridspace{<:Any,<:Any,<:Any,<:Any,Val{:product}}) =
    _product_combinations(space.axes)
_combinations(space::Gridspace{<:Any,<:Any,<:Any,<:Any,Val{:zip}}) =
    _zip_combinations(space.axes, space.names)

"Return a lazy iterator over the resolved configurations in `space`."
function configurations(space::Gridspace{Target}) where {Target}
    compatible = Iterators.filter(_compatible_bindings, _combinations(space))
    return (
        Configuration{Target}(
            space.target,
            map(_axis_value, items),
            space.names,
            _merged_bindings(items),
        )
        for items in compatible
    )
end

function gridspace(spec::AbstractSpec)
    throw(MethodError(gridspace, (spec,)))
end

configurations(spec::AbstractSpec) = configurations(gridspace(spec))

function _direct_uncertain end
function _direct_uncertainty_latent end
function _external_has_uncertainty end
function _external_sample end

function _direct_value(value::UncertainValue)
    applicable(_direct_uncertainty_latent) || throw(ArgumentError(
        "direct materialization of uncertain configurations requires Measurements.jl",
    ))
    return _direct_uncertain(value, _direct_uncertainty_latent())
end
_direct_value(configuration::Configuration) = materialize(configuration)
_direct_value(value) = value

function _resolved_direct(value::ResolvedGridValue, cache::Dict)
    if value.value isa UncertainValue
        applicable(_direct_uncertainty_latent) || throw(ArgumentError(
            "direct materialization of uncertain configurations requires Measurements.jl",
        ))
        latent = get!(cache, value.key) do
            _direct_uncertainty_latent()
        end
        return _direct_uncertain(value.value, latent)
    end
    return value.value
end

_resolved_direct(configuration::Configuration, cache::Dict) =
    _materialize(configuration, cache)
_resolved_direct(value, ::Dict) = _direct_value(value)

function _materialize(configuration::Configuration, cache::Dict)
    values = map(value -> _resolved_direct(value, cache), configuration.values)
    return configuration.target(values...)
end

function _materialize_resolved(configuration::Configuration, resolver, cache::Dict)
    values = map(configuration.values) do value
        if value isa ResolvedGridValue
            get!(cache, value.key) do
                resolver(value)
            end
        elseif value isa Configuration
            _materialize_resolved(value, resolver, cache)
        else
            value
        end
    end
    return configuration.target(values...)
end

"Materialize a resolved configuration through its target constructor."
function materialize(configuration::Configuration)
    return _materialize(configuration, Dict{Any,Any}())
end

function _random_value(
    rng::Random.AbstractRNG,
    value::ResolvedGridValue,
    distribution,
    cache::Dict,
)
    if value.value isa UncertainValue
        standardized = get!(cache, value.key) do
            _standard_uncertainty_draw(rng, distribution)
        end
        return _realize_uncertainty(value.value, standardized)
    end
    return applicable(_external_sample, rng, value.value, distribution) ?
        _external_sample(rng, value.value, distribution) : value.value
end

_random_value(
    rng::Random.AbstractRNG,
    configuration::Configuration,
    distribution,
    cache::Dict,
) = _random_materialize(rng, configuration, distribution, cache)
function _random_value(rng::Random.AbstractRNG, value, distribution, ::Dict)
    return applicable(_external_sample, rng, value, distribution) ?
        _external_sample(rng, value, distribution) : value
end

function _random_materialize(rng, configuration, distribution, cache)
    values = map(
        value -> _random_value(rng, value, distribution, cache),
        configuration.values,
    )
    return configuration.target(values...)
end

function Base.rand(
    rng::Random.AbstractRNG,
    configuration::Configuration;
    distribution=:normal,
)
    return _random_materialize(rng, configuration, distribution, Dict{Any,Any}())
end

Base.rand(configuration::Configuration; kwargs...) =
    rand(Random.default_rng(), configuration; kwargs...)

function Base.rand(rng::Random.AbstractRNG, spec::AbstractSpec; distribution=:normal)
    iterator = configurations(spec)
    first_item = iterate(iterator)
    first_item === nothing && throw(ArgumentError("cannot sample an empty Gridspace"))
    configuration, state = first_item
    iterate(iterator, state) === nothing || throw(ArgumentError(
        "rand(Gridspace) requires exactly one outer configuration",
    ))
    return rand(rng, configuration; distribution)
end

Base.rand(spec::AbstractSpec; kwargs...) = rand(Random.default_rng(), spec; kwargs...)

function Base.iterate(spec::AbstractSpec)
    iterator = configurations(spec)
    item = iterate(iterator)
    item === nothing && return nothing
    configuration, state = item
    return materialize(configuration), state
end

function Base.iterate(spec::AbstractSpec, state)
    iterator = configurations(spec)
    item = iterate(iterator, state)
    item === nothing && return nothing
    configuration, next_state = item
    return materialize(configuration), next_state
end

Base.IteratorSize(::Type{<:AbstractSpec}) = Base.HasLength()
Base.IteratorEltype(::Type{<:AbstractSpec}) = Base.HasEltype()
Base.eltype(::Type{<:AbstractSpec{Target}}) where {Target} = Target
Base.length(spec::AbstractSpec) = count(_ -> true, configurations(spec))
Base.size(spec::AbstractSpec) = (length(spec),)
Base.getindex(spec::AbstractSpec, index::Integer) = first(Iterators.drop(spec, index - 1))

has_uncertainty(value::UncertainValue) = true
has_uncertainty(value::ResolvedGridValue) = has_uncertainty(value.value)
has_uncertainty(configuration::Configuration) = any(has_uncertainty, configuration.values)
has_uncertainty(value) = applicable(_external_has_uncertainty, value) &&
    _external_has_uncertainty(value)
has_uncertainty(spec::AbstractSpec) = any(has_uncertainty, configurations(spec))

_manifest_value(value::UncertainValue) = (
    nominal=value.nominal,
    sigma=value.sigma,
    style=value.style isa RelativeUncertainty ? :relative : :absolute,
)
_manifest_value(value::ResolvedGridValue) = _manifest_value(value.value)
_manifest_value(configuration::Configuration) = configuration_manifest(configuration)
_manifest_value(value) = value

"Return the resolved parameterization of `configuration` as a named tuple."
function configuration_manifest(configuration::Configuration)
    values = map(_manifest_value, configuration.values)
    return NamedTuple{configuration.names}(values)
end
