export HarmonicImpedancePlotDefinition
export response_kind, response_values, angular_frequencies, response_nodes

"""$(TYPEDSIGNATURES)

Return the physical response represented by a frequency-response result.
"""
response_kind(result::FrequencyResponseResult) = result.kind

"""$(TYPEDSIGNATURES)

Return the response tensor. Its dimensions are node, node, and frequency.
"""
response_values(result::FrequencyResponseResult) = result.response

"""$(TYPEDSIGNATURES)

Return the strictly increasing angular-frequency coordinates in rad/s.
"""
angular_frequencies(result::FrequencyResponseResult) = result.frequencies

"""$(TYPEDSIGNATURES)

Return the ordered node labels associated with the response matrix.
"""
response_nodes(result::FrequencyResponseResult) = result.nodes

"""
$(TYPEDEF)

Select the declarative harmonic-impedance magnitude recipe for a scalar
[`FrequencyResponseResult`](@ref).
"""
struct HarmonicImpedancePlotDefinition <: PlotBuilder.AbstractPlotDefinition end

const _IMPEDANCE_ENTRY = Union{Integer, Symbol}
const _CompletedFrequencyResponseResult = Union{
    FrequencyResponseResult,
    AbstractParametricResult{<:FrequencyResponseResult},
    AbstractUncertaintyResult{<:FrequencyResponseResult},
}

_frequency_response_values(result::FrequencyResponseResult) = FrequencyResponseResult[result]
_frequency_response_values(result::AbstractParametricResult{<:FrequencyResponseResult}) =
    result.values
function _frequency_response_values(
    result::AbstractUncertaintyResult{<:FrequencyResponseResult},
)
    hasproperty(result, :values) && return result.values
    hasproperty(result.details, :plot_data) || throw(ArgumentError(
        "the uncertainty result does not retain completed frequency-response trajectories",
    ))
    return reduce(vcat, result.details.plot_data.values; init=FrequencyResponseResult[])
end

PlotBuilder.dispatch_on(::Type{HarmonicImpedancePlotDefinition}) =
    _CompletedFrequencyResponseResult
PlotBuilder.input_kwargs(::Type{HarmonicImpedancePlotDefinition}) =
    (:entries, :grouping, :xscale, :labels, :series_groups)
PlotBuilder.renderer_kwargs(::Type{HarmonicImpedancePlotDefinition}) = (:title, :figure_size)
function PlotBuilder.input_defaults(::Type{HarmonicImpedancePlotDefinition}, result)
    return (;
        entries=:diagonal,
        grouping=:overlay,
        xscale=:log10,
        labels=nothing,
        series_groups=nothing,
    )
end
function PlotBuilder.renderer_defaults(::Type{HarmonicImpedancePlotDefinition}, result)
    return (; title = "Harmonic nodal impedance", figure_size = :auto)
end

function _harmonic_figure_size(grouping::Symbol, entry_count::Int)
    grouping === :panels || return (900, 560)
    columns = max(1, ceil(Int, sqrt(entry_count)))
    rows = cld(entry_count, columns)
    return (
        max(900, 360columns + 60),
        max(560, 270rows + 100)
    )
end

function _response_node_labels(result::FrequencyResponseResult, order::Int)
    nodes = collect(response_nodes(result))
    isempty(nodes) && return [Symbol("node_$index") for index in 1:order]
    length(nodes) == order || throw(
        DimensionMismatch(
        "the response contains $order nodes but $(length(nodes)) node labels were supplied",
    ),
    )
    allunique(nodes) || throw(ArgumentError("response node labels must be unique"))
    return nodes
end

function _entry_coordinate(value::_IMPEDANCE_ENTRY, nodes, dimension::Int)
    if value isa Integer
        1 <= value <= dimension || throw(
            ArgumentError("impedance entry index $value lies outside 1:$dimension"),
        )
        return Int(value)
    end
    index = findfirst(isequal(value), nodes)
    index === nothing && throw(
        ArgumentError("response node :$value is not present in $(collect(nodes))"),
    )
    return index
end

function _entry_pair(value, nodes, dimension::Int)
    coordinates = if value isa Pair
        (first(value), last(value))
    elseif value isa Tuple && length(value) == 2
        value
    else
        throw(
            ArgumentError(
            "each impedance entry must be `row => column` or a two-value tuple",
        ),
        )
    end
    all(item -> item isa _IMPEDANCE_ENTRY, coordinates) || throw(
        ArgumentError("impedance entry coordinates must be integer indices or node names"),
    )
    return (
        _entry_coordinate(first(coordinates), nodes, dimension),
        _entry_coordinate(last(coordinates), nodes, dimension)
    )
end

function _selected_entries(selection, nodes, dimension::Int)
    selected = if selection === :diagonal
        [(index, index) for index in 1:dimension]
    elseif selection === :all
        [(row, column) for row in 1:dimension for column in 1:dimension]
    elseif selection isa Pair ||
           (selection isa Tuple && length(selection) == 2 &&
            all(item -> item isa _IMPEDANCE_ENTRY, selection))
        [_entry_pair(selection, nodes, dimension)]
    elseif selection isa Tuple || selection isa AbstractVector
        [_entry_pair(item, nodes, dimension) for item in selection]
    else
        throw(
            ArgumentError(
            "entries must be :diagonal, :all, or an ordered collection of entry pairs",
        ),
        )
    end
    isempty(selected) && throw(ArgumentError("at least one impedance entry is required"))
    allunique(selected) || throw(ArgumentError("impedance entry selections must be unique"))
    return selected
end

function _validate_harmonic_response(result::FrequencyResponseResult, entries)
    response_kind(result) === :nodal_impedance || throw(
        ArgumentError(
        "harmonic-impedance plotting requires response kind :nodal_impedance; " *
        "received :$(response_kind(result))",
    ),
    )
    values = response_values(result)
    ndims(values) == 3 || throw(
        DimensionMismatch("the response must be an n×n×nf tensor"),
    )
    rows, columns, count = size(values)
    rows == columns || throw(DimensionMismatch("the response matrices must be square"))
    stored_frequencies = collect(angular_frequencies(result))
    length(stored_frequencies) == count || throw(
        DimensionMismatch(
        "the response has $count frequency slices but $(length(stored_frequencies)) coordinates",
    ),
    )
    # The classic impedance calculation stores its physically real angular-frequency
    # axis in a ComplexF64 vector. Accept that representation only when every
    # imaginary part is exactly zero, then normalize at the plotting boundary.
    all(
        value -> value isa Number && isfinite(value) && isreal(value),
        stored_frequencies
    ) || throw(
        ArgumentError(
        "angular frequencies must be finite real-valued numbers; " *
        "complex storage is accepted only when every imaginary part is zero",
    ),
    )
    frequencies = Float64.(real.(stored_frequencies))
    all(>(0), frequencies) || throw(
        DomainError(frequencies, "angular frequencies must be strictly positive"),
    )
    all(diff(frequencies) .> 0) || throw(
        ArgumentError("angular frequencies must be strictly increasing"),
    )
    all(isfinite, values) || throw(ArgumentError("impedance values must be finite"))
    nodes = _response_node_labels(result, rows)
    selected = _selected_entries(entries, nodes, rows)
    for (row, column) in selected
        all(!iszero, @view(values[row, column, :])) || throw(
            DomainError(
            (nodes[row], nodes[column]),
            "selected impedance magnitudes must be nonzero before conversion to dBΩ"
        ),
        )
    end
    return (; values, frequencies = frequencies ./ (2π), nodes, selected)
end

function PlotBuilder.resolve_input(
        ::Type{HarmonicImpedancePlotDefinition}, recipe::PlotBuilder.PlotRecipe
)
    recipe.input.grouping in (:overlay, :panels, :pages) || throw(
        ArgumentError("grouping must be :overlay, :panels, or :pages"),
    )
    recipe.input.xscale in (:linear, :log10) || throw(
        ArgumentError("xscale must be :linear or :log10"),
    )
    recipe.renderer.title isa AbstractString ||
        throw(ArgumentError("title must be a string"))
    values = _frequency_response_values(recipe.object)
    isempty(values) && throw(ArgumentError("the result contains no completed responses"))
    datasets = [
        _validate_harmonic_response(value, recipe.input.entries)
        for value in values
    ]
    labels = recipe.input.labels
    if labels !== nothing
        labels isa AbstractVector || throw(ArgumentError("labels must be a vector or nothing"))
        length(labels) == length(datasets) || throw(DimensionMismatch(
            "labels must contain one entry per completed response",
        ))
        all(label -> label === nothing || label isa AbstractString, labels) || throw(
            ArgumentError("labels must contain strings or nothing"),
        )
        labels = Union{Nothing,String}[
            label === nothing ? nothing : String(label) for label in labels
        ]
    end
    series_groups = recipe.input.series_groups
    if series_groups !== nothing
        series_groups isa AbstractVector || throw(
            ArgumentError("series_groups must be a vector or nothing"),
        )
        length(series_groups) == length(datasets) || throw(DimensionMismatch(
            "series_groups must contain one entry per completed response",
        ))
        all(group -> group isa Symbol, series_groups) || throw(
            ArgumentError("series_groups must contain symbols"),
        )
        series_groups = Symbol.(series_groups)
    end
    data = first(datasets)
    all(dataset -> dataset.nodes == data.nodes && dataset.selected == data.selected,
        datasets) || throw(DimensionMismatch(
        "harmonic-impedance response nodes or selected entries differ",
    ))
    requested_size = recipe.renderer.figure_size
    requested_size === :auto ||
        requested_size isa Tuple &&
        length(requested_size) == 2 &&
        all(value -> value isa Integer && value > 0, requested_size) ||
        throw(
            ArgumentError("figure_size must be :auto or contain two positive integers"),
        )
    figure_size = requested_size === :auto ?
                  _harmonic_figure_size(recipe.input.grouping, length(data.selected)) :
                  Tuple(Int.(requested_size))
    input = merge(recipe.input, (; data, datasets, labels, series_groups))
    renderer = merge(
        recipe.renderer,
        (; title = String(recipe.renderer.title), figure_size)
    )
    return PlotBuilder.PlotRecipe(recipe.object, input, renderer)
end

function PlotBuilder.grouping_mode(
        ::Type{HarmonicImpedancePlotDefinition}, mode::Val, recipe::PlotBuilder.PlotRecipe
)
    return Val(recipe.input.grouping)
end

function PlotBuilder.group_facets(
        ::Type{HarmonicImpedancePlotDefinition}, mode::Val,
        recipe::PlotBuilder.PlotRecipe, page_key
)
    return Tuple(recipe.input.data.selected)
end

function PlotBuilder.axis_quantity(
        ::Type{HarmonicImpedancePlotDefinition}, ::Val{:x}, recipe::PlotBuilder.PlotRecipe
)
    return UnitHandler.QuantityTag{:frequency}()
end
function PlotBuilder.axis_quantity(
        ::Type{HarmonicImpedancePlotDefinition}, ::Val{:y}, recipe::PlotBuilder.PlotRecipe
)
    return UnitHandler.QuantityTag{:impedance_db}()
end

function PlotBuilder.axis_scale(
        ::Type{HarmonicImpedancePlotDefinition}, ::Val{:x}, recipe::PlotBuilder.PlotRecipe
)
    return recipe.input.xscale
end
function PlotBuilder.axis_scales(
        ::Type{HarmonicImpedancePlotDefinition}, ::Val{:x},
        recipe::PlotBuilder.PlotRecipe, series::Vector{PlotBuilder.SeriesDefinition}
)
    return (:linear, :log10)
end

function PlotBuilder.series_data(
        ::Type{HarmonicImpedancePlotDefinition}, ::Val{:x},
        recipe::PlotBuilder.PlotRecipe, key
)
    case_index, _ = _harmonic_series_key(key)
    return recipe.input.datasets[case_index].frequencies
end
function PlotBuilder.series_data(
        ::Type{HarmonicImpedancePlotDefinition}, ::Val{:y},
        recipe::PlotBuilder.PlotRecipe, key
)
    case_index, entry = _harmonic_series_key(key)
    row, column = entry
    impedance = @view recipe.input.datasets[case_index].values[row, column, :]
    return 20 .* log10.(abs.(impedance))
end

_harmonic_series_key(key::NamedTuple) = (key.case, key.entry)
_harmonic_series_key(entry) = (1, entry)

function PlotBuilder.series_keys(
    ::Type{HarmonicImpedancePlotDefinition},
    mode::Val,
    ::Val{:overlay},
    recipe::PlotBuilder.PlotRecipe,
    page_key,
    view_key,
)
    return tuple((
        (; case=case_index, entry)
        for case_index in eachindex(recipe.input.datasets)
        for entry in recipe.input.data.selected
    )...)
end

function _harmonic_faceted_series_keys(
    ::Type{HarmonicImpedancePlotDefinition},
    mode::Val,
    recipe::PlotBuilder.PlotRecipe,
    page_key,
    view_key,
)
    entry = something(view_key, page_key)
    return tuple((
        (; case=case_index, entry)
        for case_index in eachindex(recipe.input.datasets)
    )...)
end

function PlotBuilder.series_keys(
    definition::Type{HarmonicImpedancePlotDefinition},
    mode::Val,
    ::Val{:panels},
    recipe::PlotBuilder.PlotRecipe,
    page_key,
    view_key,
)
    return _harmonic_faceted_series_keys(
        definition, mode, recipe, page_key, view_key,
    )
end

function PlotBuilder.series_keys(
    definition::Type{HarmonicImpedancePlotDefinition},
    mode::Val,
    ::Val{:pages},
    recipe::PlotBuilder.PlotRecipe,
    page_key,
    view_key,
)
    return _harmonic_faceted_series_keys(
        definition, mode, recipe, page_key, view_key,
    )
end

function _impedance_entry_label(recipe::PlotBuilder.PlotRecipe, entry)
    row, column = entry
    nodes = recipe.input.data.nodes
    return "Z[$(nodes[row]), $(nodes[column])]"
end

function PlotBuilder.legend_label(
        ::Type{HarmonicImpedancePlotDefinition}, recipe::PlotBuilder.PlotRecipe, key
)
    case_index, entry = _harmonic_series_key(key)
    entry_label = _impedance_entry_label(recipe, entry)
    if recipe.input.labels !== nothing
        label = recipe.input.labels[case_index]
        label === nothing && return nothing
        return length(recipe.input.data.selected) == 1 ? label : "$entry_label, $label"
    end
    return length(recipe.input.datasets) == 1 ? entry_label : "$entry_label, case $case_index"
end

function PlotBuilder.series_group(
        ::Type{HarmonicImpedancePlotDefinition}, recipe::PlotBuilder.PlotRecipe, key
)
    case_index, entry = _harmonic_series_key(key)
    row, column = entry
    if recipe.input.series_groups !== nothing
        group = recipe.input.series_groups[case_index]
        return Symbol("z_$(row)_$(column)_$(group)")
    end
    return Symbol("z_$(row)_$(column)_case_$case_index")
end

function PlotBuilder.series_attributes(
        ::Type{HarmonicImpedancePlotDefinition}, recipe::PlotBuilder.PlotRecipe, key
)
    recipe.object isa AbstractUncertaintyResult || return (; linewidth=2)
    return (; linewidth=1, alpha=0.16)
end

function PlotBuilder.view_key(
        ::Type{HarmonicImpedancePlotDefinition}, mode::Val,
        recipe::PlotBuilder.PlotRecipe, page_key, entry
)
    key = entry === nothing ? page_key : entry
    key === nothing && return (; response = :nodal_impedance)
    return (; response = :nodal_impedance, row = first(key), column = last(key))
end

function PlotBuilder.default_title(
        ::Type{HarmonicImpedancePlotDefinition}, mode::Val,
        recipe::PlotBuilder.PlotRecipe, page_key, entry
)
    key = entry === nothing ? page_key : entry
    key === nothing && return recipe.renderer.title
    return recipe.input.grouping === :overlay ? recipe.renderer.title :
           _impedance_entry_label(recipe, key)
end

function PlotBuilder.default_figsize(
        ::Type{HarmonicImpedancePlotDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return recipe.renderer.figure_size
end

function PlotBuilder.layout_definition(
        ::Type{HarmonicImpedancePlotDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return recipe.input.grouping === :panels ? :grid : :single
end

function PlotBuilder.legend_definition(
        ::Type{HarmonicImpedancePlotDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return PlotBuilder.LegendDefinition(
        enabled = recipe.input.grouping === :overlay,
        interactive = true,
        overflow = :ellipsis
    )
end

function PlotBuilder.export_definition(
        ::Type{HarmonicImpedancePlotDefinition}, recipe::PlotBuilder.PlotRecipe,
        title::AbstractString
)
    return PlotBuilder.ExportDefinition(
        theme = recipe.renderer.export_theme,
        name = isempty(title) ? "harmonic_impedance" : title,
        open_file = recipe.renderer.open_export
    )
end
