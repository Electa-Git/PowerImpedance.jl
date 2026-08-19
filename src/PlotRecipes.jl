export HarmonicImpedancePlotSpec
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
struct HarmonicImpedancePlotSpec <: PlotBuilder.AbstractPlotSpec end

const _IMPEDANCE_ENTRY = Union{Integer, Symbol}

PlotBuilder.dispatch_on(::Type{HarmonicImpedancePlotSpec}) = FrequencyResponseResult
PlotBuilder.input_kwargs(::Type{HarmonicImpedancePlotSpec}) = (:entries, :grouping, :xscale)
PlotBuilder.renderer_kwargs(::Type{HarmonicImpedancePlotSpec}) = (:title, :figure_size)
function PlotBuilder.input_defaults(::Type{HarmonicImpedancePlotSpec}, result)
    return (; entries = :diagonal, grouping = :overlay, xscale = :log10)
end
function PlotBuilder.renderer_defaults(::Type{HarmonicImpedancePlotSpec}, result)
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
        ::Type{HarmonicImpedancePlotSpec}, recipe::PlotBuilder.PlotRecipe
)
    recipe.input.grouping in (:overlay, :panels, :pages) || throw(
        ArgumentError("grouping must be :overlay, :panels, or :pages"),
    )
    recipe.input.xscale in (:linear, :log10) || throw(
        ArgumentError("xscale must be :linear or :log10"),
    )
    recipe.renderer.title isa AbstractString ||
        throw(ArgumentError("title must be a string"))
    data = _validate_harmonic_response(recipe.object, recipe.input.entries)
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
    input = merge(recipe.input, (; data))
    renderer = merge(
        recipe.renderer,
        (; title = String(recipe.renderer.title), figure_size)
    )
    return PlotBuilder.PlotRecipe(recipe.object, input, renderer)
end

function PlotBuilder.grouping_mode(
        ::Type{HarmonicImpedancePlotSpec}, mode::Val, recipe::PlotBuilder.PlotRecipe
)
    return Val(recipe.input.grouping)
end

function PlotBuilder.group_facets(
        ::Type{HarmonicImpedancePlotSpec}, mode::Val,
        recipe::PlotBuilder.PlotRecipe, page_key
)
    return Tuple(recipe.input.data.selected)
end

function PlotBuilder.axis_quantity(
        ::Type{HarmonicImpedancePlotSpec}, ::Val{:x}, recipe::PlotBuilder.PlotRecipe
)
    return UnitHandler.QuantityTag{:frequency}()
end
function PlotBuilder.axis_quantity(
        ::Type{HarmonicImpedancePlotSpec}, ::Val{:y}, recipe::PlotBuilder.PlotRecipe
)
    return UnitHandler.QuantityTag{:impedance_db}()
end

function PlotBuilder.axis_scale(
        ::Type{HarmonicImpedancePlotSpec}, ::Val{:x}, recipe::PlotBuilder.PlotRecipe
)
    return recipe.input.xscale
end
function PlotBuilder.axis_scales(
        ::Type{HarmonicImpedancePlotSpec}, ::Val{:x},
        recipe::PlotBuilder.PlotRecipe, series::Vector{PlotBuilder.SeriesSpec}
)
    return (:linear, :log10)
end

function PlotBuilder.series_data(
        ::Type{HarmonicImpedancePlotSpec}, ::Val{:x},
        recipe::PlotBuilder.PlotRecipe, entry
)
    return recipe.input.data.frequencies
end
function PlotBuilder.series_data(
        ::Type{HarmonicImpedancePlotSpec}, ::Val{:y},
        recipe::PlotBuilder.PlotRecipe, entry
)
    row, column = entry
    impedance = @view recipe.input.data.values[row, column, :]
    return 20 .* log10.(abs.(impedance))
end

function _impedance_entry_label(recipe::PlotBuilder.PlotRecipe, entry)
    row, column = entry
    nodes = recipe.input.data.nodes
    return "Z[$(nodes[row]), $(nodes[column])]"
end

function PlotBuilder.legend_label(
        ::Type{HarmonicImpedancePlotSpec}, recipe::PlotBuilder.PlotRecipe, entry
)
    return _impedance_entry_label(recipe, entry)
end

function PlotBuilder.series_group(
        ::Type{HarmonicImpedancePlotSpec}, recipe::PlotBuilder.PlotRecipe, entry
)
    row, column = entry
    return Symbol("z_$(row)_$(column)")
end

function PlotBuilder.view_key(
        ::Type{HarmonicImpedancePlotSpec}, mode::Val,
        recipe::PlotBuilder.PlotRecipe, page_key, entry
)
    key = entry === nothing ? page_key : entry
    key === nothing && return (; response = :nodal_impedance)
    return (; response = :nodal_impedance, row = first(key), column = last(key))
end

function PlotBuilder.default_title(
        ::Type{HarmonicImpedancePlotSpec}, mode::Val,
        recipe::PlotBuilder.PlotRecipe, page_key, entry
)
    key = entry === nothing ? page_key : entry
    key === nothing && return recipe.renderer.title
    return recipe.input.grouping === :overlay ? recipe.renderer.title :
           _impedance_entry_label(recipe, key)
end

function PlotBuilder.default_figsize(
        ::Type{HarmonicImpedancePlotSpec}, recipe::PlotBuilder.PlotRecipe
)
    return recipe.renderer.figure_size
end

function PlotBuilder.layout_spec(
        ::Type{HarmonicImpedancePlotSpec}, recipe::PlotBuilder.PlotRecipe
)
    return recipe.input.grouping === :panels ? :grid : :single
end

function PlotBuilder.legend_spec(
        ::Type{HarmonicImpedancePlotSpec}, recipe::PlotBuilder.PlotRecipe
)
    return PlotBuilder.LegendSpec(
        enabled = recipe.input.grouping === :overlay,
        interactive = true,
        overflow = :ellipsis
    )
end

function PlotBuilder.export_spec(
        ::Type{HarmonicImpedancePlotSpec}, recipe::PlotBuilder.PlotRecipe,
        title::AbstractString
)
    return PlotBuilder.ExportSpec(
        theme = recipe.renderer.export_theme,
        name = isempty(title) ? "harmonic_impedance" : title,
        open_file = recipe.renderer.open_export
    )
end
