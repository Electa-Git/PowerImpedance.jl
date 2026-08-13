struct _KeywordMaterializer{F, N}
    constructor::F
end

function _construct_keywords(constructor, names::Tuple, values::Tuple)
    kwargs = NamedTuple{names}(values)
    try
        return constructor(; kwargs...)
    catch error
        is_type_constructor = constructor isa Type || constructor isa UnionAll
        error isa MethodError && is_type_constructor || rethrow()

        wrapped = Base.unwrap_unionall(constructor)
        fields = fieldnames(wrapped)
        all(name -> name in names, fields) || rethrow()
        all(name -> name in fields, names) || rethrow()
        positional = map(name -> getproperty(kwargs, name), fields)
        return constructor(positional...)
    end
end

function (target::_KeywordMaterializer{F, N})(values...) where {F, N}
    _construct_keywords(target.constructor, N, values)
end

function _keyword_gridspace(::Type{T}, constructor; kwargs...) where {T}
    names = keys(kwargs)
    axes = map(_axis, Tuple(values(kwargs)))
    target = _KeywordMaterializer{typeof(constructor), names}(constructor)
    return Gridspace{T}(target, axes, names)
end

function _keyword_gridspace(constructor; kwargs...)
    return _keyword_gridspace(Any, constructor; kwargs...)
end

const SHADOW_CONSTRUCTOR_MANIFEST = Pair{Symbol, Symbol}[]
const SHADOW_CONSTRUCTOR_EXCLUSIONS = (
    AbstractElementModel = :abstract_type,
    AbstractLinFreqDomain = :abstract_type,
    AbstractStateSpace = :abstract_type,
    AbstractMMC = :abstract_type,
    AbstractTLC = :abstract_type,
    Controller = :abstract_type,
    Network = :legacy_network_container,
    determine_impedance = :computational_function,
    power_flow = :computational_function,
    eval_abcd = :computational_function
)

function _register_shadow!(name::Symbol, category::Symbol)
    any(first(entry) == name for entry in SHADOW_CONSTRUCTOR_MANIFEST) ||
        push!(SHADOW_CONSTRUCTOR_MANIFEST, name => category)
    return nothing
end

macro shadow(category, name, target = name)
    category_value = category isa QuoteNode ? category : QuoteNode(category)
    name_value = name isa QuoteNode ? name : QuoteNode(name)
    grid_doc = """
        $(name)(Grid; kwargs...)

    Construct a lazy `Gridspace` through positional dispatch while preserving
    `$(name)(; kwargs...)` as the ordinary scalar constructor. Only explicit
    `Grid` values or nested Gridspaces introduce parameter axes; other keyword
    values remain atomic.
    """
    return esc(quote
        _register_shadow!($name_value, $category_value)
		@doc $grid_doc function $(name)(; kwargs...)
            return _keyword_gridspace($(target); kwargs...)
        end
        function $(target)(::typeof(Grid); kwargs...)
            return $(name)(; kwargs...)
        end
    end)
end
