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

function _keyword_gridspace(
    ::Type{Target},
    constructor;
    kwargs...,
) where {Target}
    inputs = (; kwargs...)
    names = keys(inputs)
    materializer = _KeywordMaterializer{typeof(constructor),names}(constructor)
    return _lift_gridspace(Target, materializer, inputs, Val(:product))
end

macro gridconstructor(constructor, target_type)
    constructor_name = constructor isa Expr ? constructor.args[end] : constructor
    grid_doc = """
        $(constructor_name)(Grid; kwargs...)

    Construct a typed `Gridspace` for `$(constructor_name)`. Only explicit
    `Grid` values or nested Gridspaces introduce parameter axes. Other keyword
    values remain atomic. The keyword-only method remains the scalar constructor.
    """
    return esc(quote
        @doc $grid_doc function $(constructor)(
            ::typeof(Grid);
            kwargs...,
        )
            return _keyword_gridspace($(target_type), $(constructor); kwargs...)
        end
    end)
end
