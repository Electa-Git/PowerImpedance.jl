"""
    AbstractPlotDefinition

Supertype for backend-neutral PlotBuilder recipe identifiers.
"""
abstract type AbstractPlotDefinition end

"""
    PlotRecipe(object, input, renderer)

Store a domain object together with typed semantic and renderer options.
"""
struct PlotRecipe{O, I <: NamedTuple, R <: NamedTuple}
    "Domain object being plotted."
    object::O
    "Validated semantic recipe options."
    input::I
    "Validated renderer options."
    renderer::R
end

"Abstract supertype for backend-neutral grid track sizes."
abstract type AbstractTrackSize end

"""
    FixedTrack(value)

Define a nonnegative fixed-size grid track in pixels.
"""
struct FixedTrack <: AbstractTrackSize
    "Track size in pixels."
    value::Float64
    @doc """
        FixedTrack(value)

    Construct a fixed grid track of `value` pixels.

    # Arguments

    - `value`: finite, nonnegative track size in px.

    # Returns

    - A validated [`FixedTrack`](@ref).

    # Errors

    - Throws `ArgumentError` when `value` is negative or non-finite.
    """ function FixedTrack(value::Real)
        isfinite(value) && value >= 0 || throw(
            ArgumentError("fixed track size must be finite and nonnegative"),
        )
        return new(Float64(value))
    end
end

"""
    RelativeTrack([weight])

Define a grid track that receives a positive share of available space.
"""
struct RelativeTrack <: AbstractTrackSize
    "Relative share of available space."
    weight::Float64
    @doc """
        RelativeTrack([weight])

    Construct a grid track receiving `weight` shares of available space.

    # Arguments

    - `weight`: finite, positive dimensionless share. Default: `1`.

    # Returns

    - A validated [`RelativeTrack`](@ref).

    # Errors

    - Throws `ArgumentError` when `weight` is nonpositive or non-finite.
    """ function RelativeTrack(weight::Real = 1)
        isfinite(weight) && weight > 0 || throw(
            ArgumentError("relative track weight must be finite and positive"),
        )
        return new(Float64(weight))
    end
end

"Define a grid track sized from its rendered content."
struct ContentTrack <: AbstractTrackSize end

"""
    GridArea(rows, columns)

Select positive, one-based row and column spans in a named grid.
"""
struct GridArea
    "Inclusive row span."
    rows::UnitRange{Int}
    "Inclusive column span."
    columns::UnitRange{Int}
    @doc """
        GridArea(rows, columns)

    Construct an area from inclusive one-based row and column spans.

    # Arguments

    - `rows`: nonempty range of positive row indices.
    - `columns`: nonempty range of positive column indices.

    # Returns

    - A validated [`GridArea`](@ref).

    # Errors

    - Throws `ArgumentError` for empty or nonpositive spans.
    """ function GridArea(
            rows::UnitRange{<:Integer}, columns::UnitRange{<:Integer}
    )
        !isempty(rows) && !isempty(columns) || throw(
            ArgumentError("grid area spans cannot be empty"),
        )
        first(rows) > 0 && first(columns) > 0 || throw(
            ArgumentError("grid areas use positive one-based indices"),
        )
        return new(Int(first(rows)):Int(last(rows)), Int(first(columns)):Int(last(columns)))
    end
end

function GridArea(row::Integer, column::Integer)
    GridArea(Int(row):Int(row), Int(column):Int(column))
end
function GridArea(rows::UnitRange{<:Integer}, column::Integer)
    GridArea(rows, Int(column):Int(column))
end
GridArea(row::Integer, columns::UnitRange{<:Integer}) = GridArea(Int(row):Int(row), columns)

"""
    GridDefinition(name; parent, area, rows, columns, rowgap, columngap, padding)

Declare one grid in a backend-neutral named layout tree.
"""
struct GridDefinition
    "Unique grid name."
    name::Symbol
    "Parent grid name, or `nothing` for the root."
    parent::Union{Nothing, Symbol}
    "Area occupied in the parent grid."
    area::Union{Nothing, GridArea}
    "Row track declarations."
    rows::Vector{AbstractTrackSize}
    "Column track declarations."
    columns::Vector{AbstractTrackSize}
    "Gap between rows in pixels."
    rowgap::Float64
    "Gap between columns in pixels."
    columngap::Float64
    "Left, right, bottom, and top padding in pixels."
    padding::NTuple{4, Float64}
end

function GridDefinition(
        name::Symbol;
        parent::Union{Nothing, Symbol} = nothing,
        area::Union{Nothing, GridArea} = nothing,
        rows::AbstractVector{<:AbstractTrackSize} = AbstractTrackSize[RelativeTrack()],
        columns::AbstractVector{<:AbstractTrackSize} = AbstractTrackSize[RelativeTrack()],
        rowgap::Real = 0,
        columngap::Real = 0,
        padding::NTuple{4, <:Real} = (0, 0, 0, 0)
)
    isempty(rows) && throw(ArgumentError("grid rows cannot be empty"))
    isempty(columns) && throw(ArgumentError("grid columns cannot be empty"))
    isfinite(rowgap) && rowgap >= 0 || throw(
        ArgumentError("grid row gap must be finite and nonnegative"),
    )
    isfinite(columngap) && columngap >= 0 || throw(
        ArgumentError("grid column gap must be finite and nonnegative"),
    )
    all(value -> isfinite(value) && value >= 0, padding) || throw(
        ArgumentError("grid padding must be finite and nonnegative"),
    )
    return GridDefinition(
        name,
        parent,
        area,
        AbstractTrackSize[rows...],
        AbstractTrackSize[columns...],
        Float64(rowgap),
        Float64(columngap),
        Tuple(Float64.(padding))
    )
end

"""
    SlotDefinition(name, parent, area; halign, valign)

Declare a named content destination inside a grid.
"""
struct SlotDefinition
    "Unique slot name."
    name::Symbol
    "Parent grid name."
    parent::Symbol
    "Area occupied in the parent grid."
    area::GridArea
    "Horizontal content alignment."
    halign::Symbol
    "Vertical content alignment."
    valign::Symbol
end

function SlotDefinition(
        name::Symbol,
        parent::Symbol,
        area::GridArea;
        halign::Symbol = :center,
        valign::Symbol = :center
)
    halign in (:left, :center, :right, :stretch) || throw(
        ArgumentError("slot horizontal alignment must be :left, :center, :right, or :stretch"),
    )
    valign in (:top, :center, :bottom, :stretch) || throw(
        ArgumentError("slot vertical alignment must be :top, :center, :bottom, or :stretch"),
    )
    return SlotDefinition(name, parent, area, halign, valign)
end

"""
    LayoutDefinition(name, grids, slots)

Define and validate a backend-neutral named grid tree.
"""
struct LayoutDefinition
    "Layout identity."
    name::Symbol
    "Named root and nested grids."
    grids::Vector{GridDefinition}
    "Named content destinations."
    slots::Vector{SlotDefinition}
    @doc """
        LayoutDefinition(name, grids, slots)

    Construct and validate a named grid layout.

    # Arguments

    - `name`: layout identity.
    - `grids`: root and nested [`GridDefinition`](@ref) declarations.
    - `slots`: named [`SlotDefinition`](@ref) destinations.

    # Returns

    - A validated [`LayoutDefinition`](@ref).

    # Errors

    - Throws the validation errors documented by [`validate`](@ref).
    """ function LayoutDefinition(
            name::Symbol, grids::AbstractVector, slots::AbstractVector
    )
        layout = new(name, GridDefinition[grids...], SlotDefinition[slots...])
        validate(layout)
        return layout
    end
end

"""
    PlacementDefinition([slot], [area])

Assign a view to a named slot with automatic or explicit grid placement.
"""
struct PlacementDefinition
    "Destination slot name."
    slot::Symbol
    "Explicit area inside the slot, or `nothing` for automatic placement."
    area::Union{Nothing, GridArea}
end

PlacementDefinition(slot::Symbol = :canvas) = PlacementDefinition(slot, nothing)

"Declare page-level reset and SVG controls and their destination slot."
struct ControlDefinition
    "Whether to show the reset control."
    reset::Bool
    "Whether to show the SVG export control."
    export_svg::Bool
    "Destination toolbar slot."
    slot::Symbol
end

function ControlDefinition(; reset::Bool = true, export_svg::Bool = true, slot::Symbol = :toolbar)
    ControlDefinition(reset, export_svg, slot)
end

const LEGEND_OVERFLOW_MODES = (:ellipsis, :show_all)

"""
$(TYPEDEF)

Declare legend visibility, interactivity, destination slot, and overflow mode.

$(TYPEDFIELDS)
"""
struct LegendDefinition
    "Whether to render a legend."
    enabled::Bool
    "Whether legend entries control series visibility."
    interactive::Bool
    "Destination legend slot."
    slot::Symbol
    "Overflow mode, either `:ellipsis` or `:show_all`."
    overflow::Symbol
end

"""
$(TYPEDSIGNATURES)

Construct a [`LegendDefinition`](@ref).

# Keywords

- `enabled`: render the legend. Default: `true`.
- `interactive`: let legend entries control series visibility. Default: `true`.
- `slot`: destination layout slot. Default: `:legend`.
- `overflow`: use `:ellipsis` to show the largest fitting entry prefix followed
  by `(...)`, or `:show_all` to render every entry. Default: `:ellipsis`.

# Returns

- A validated [`LegendDefinition`](@ref).

# Errors

- Throws `ArgumentError` when `overflow` is unsupported.
"""
function LegendDefinition(;
        enabled::Bool = true,
        interactive::Bool = true,
        slot::Symbol = :legend,
        overflow::Symbol = :ellipsis
)
    overflow in LEGEND_OVERFLOW_MODES || throw(
        ArgumentError("legend overflow must be :ellipsis or :show_all"),
    )
    return LegendDefinition(enabled, interactive, slot, overflow)
end

"""
    ColorbarDefinition(label, colormap, limits, ticks; slot=:colorbars)

Declare one backend-neutral colorbar and its destination slot.
"""
struct ColorbarDefinition{C, T}
    "Displayed colorbar label."
    label::String
    "Backend-neutral colormap value."
    colormap::C
    "Finite, strictly increasing color limits."
    limits::Tuple{Float64, Float64}
    "Tick positions and labels."
    ticks::T
    "Destination colorbar slot."
    slot::Symbol
end

function ColorbarDefinition(
        label::AbstractString,
        colormap,
        limits::Tuple{<:Real, <:Real},
        ticks;
        slot::Symbol = :colorbars
)
    lower, upper = Float64.(limits)
    isfinite(lower) && isfinite(upper) && lower < upper || throw(
        ArgumentError("colorbar limits must be finite and strictly increasing"),
    )
    ticks isa Tuple && length(ticks) == 2 || throw(
        ArgumentError("colorbar ticks must be a tuple of positions and labels"),
    )
    positions, labels = ticks
    applicable(length, positions) && applicable(length, labels) || throw(
        ArgumentError("colorbar tick positions and labels must be collections"),
    )
    length(positions) == length(labels) || throw(
        DimensionMismatch("colorbar tick positions and labels must have equal lengths"),
    )
    all(position -> position isa Real && isfinite(position), positions) || throw(
        ArgumentError("colorbar tick positions must be finite real values"),
    )
    all(position -> lower <= position <= upper, positions) || throw(
        ArgumentError("colorbar tick positions must lie within the color limits"),
    )
    return ColorbarDefinition(String(label), colormap, (lower, upper), ticks, slot)
end

"Declare status-line visibility, initial text, and destination slot."
struct StatusDefinition
    "Whether to render a status line."
    enabled::Bool
    "Initial status message."
    initial::String
    "Destination status slot."
    slot::Symbol
end

function StatusDefinition(; enabled::Bool = true, initial::AbstractString = "Ready.", slot::Symbol = :status)
    StatusDefinition(enabled, String(initial), slot)
end

"Declare the SVG theme, base filename, and automatic-open behavior."
struct ExportDefinition
    "Export theme, either `:default` or `:publication`."
    theme::Symbol
    "Unsanitized base filename."
    name::String
    "Whether to ask the operating system to open the exported file."
    open_file::Bool
end

function ExportDefinition(;
        theme::Symbol = :default,
        name::AbstractString = "powerimpedance_plot",
        open_file::Bool = true
)
    _validate_export_theme(theme)
    isempty(strip(name)) && throw(ArgumentError("export name cannot be empty"))
    return ExportDefinition(theme, String(name), open_file)
end

const AXIS_SCALES = (:linear, :log10)
const AXIS_RESERVED_ATTRIBUTES = (
    :scale,
    :allowed_scales,
    :exponent,
    :label,
    :xlabel,
    :ylabel,
    :zlabel,
    :xscale,
    :yscale,
    :zscale,
    :xticks,
    :yticks,
    :zticks,
    :xtickformat,
    :ytickformat,
    :ztickformat,
    :title,
    :aspect
)
const SERIES_RESERVED_ATTRIBUTES = (:group, :visible, :label)
const VIEW_RESERVED_ATTRIBUTES = (
    :placement,
    :aspect,
    :limits,
    :xlabel,
    :ylabel,
    :zlabel,
    :xscale,
    :yscale,
    :zscale,
    :xticks,
    :yticks,
    :zticks,
    :xtickformat,
    :ytickformat,
    :ztickformat,
    :title
)

function _reject_reserved(attributes::NamedTuple, reserved::Tuple, owner::AbstractString)
    collisions = Tuple(key for key in keys(attributes) if key in reserved)
    isempty(collisions) || throw(
        ArgumentError("$owner attributes contain reserved semantic keys: $(join(collisions, ", "))"),
    )
    return attributes
end

"""
    AxisDefinition(dim, quantity, units, label[, scale]; allowed_scales, exponent, attributes)

Describe one backend-neutral plot axis.
"""
struct AxisDefinition{A <: NamedTuple}
    "Axis dimension, one of `:x`, `:y`, or `:z`."
    dim::Symbol
    "Semantic quantity tag."
    quantity::QuantityTag
    "Display units."
    units::Units
    "Displayed axis label."
    label::String
    "Current scale."
    scale::Symbol
    "Scales that interactive controls may select."
    allowed_scales::Tuple{Vararg{Symbol}}
    "Base-ten display exponent for linear tick labels."
    exponent::Int
    "Validated visual axis attributes."
    attributes::A
end

function AxisDefinition(
        dim::Symbol,
        quantity::QuantityTag,
        units::Units,
        label::AbstractString,
        scale::Symbol = :linear;
        allowed_scales = (scale,),
        exponent::Integer = 0,
        attributes::NamedTuple = (;)
)
    dim in (:x, :y, :z) || throw(ArgumentError("axis dimension must be :x, :y, or :z"))
    allowed_scales isa Tuple && !isempty(allowed_scales) || throw(
        ArgumentError("allowed axis scales must be a nonempty tuple"),
    )
    all(item -> item isa Symbol && item in AXIS_SCALES, allowed_scales) || throw(
        ArgumentError("axis scales must be :linear or :log10"),
    )
    length(unique(allowed_scales)) == length(allowed_scales) || throw(
        ArgumentError("allowed axis scales cannot contain duplicates"),
    )
    scale in allowed_scales || throw(
        ArgumentError("current axis scale :$scale is not allowed"),
    )
    _reject_reserved(attributes, AXIS_RESERVED_ATTRIBUTES, "AxisDefinition")
    return AxisDefinition(
        dim,
        quantity,
        units,
        String(label),
        scale,
        allowed_scales,
        Int(exponent),
        attributes
    )
end

"""
    SeriesDefinition(kind, xdata, ydata, zdata, label; group, visible, attributes)

Describe one backend-neutral plotting primitive and its data.
"""
struct SeriesDefinition{X, Y, Z, A <: NamedTuple}
    "Primitive symbol rendered through `Val` dispatch."
    kind::Symbol
    "Data associated with the x dimension."
    xdata::X
    "Data associated with the y dimension."
    ydata::Y
    "Data associated with the z dimension or geometry."
    zdata::Z
    "Legend label, or `nothing`."
    label::Union{Nothing, String}
    "Visibility-group identity, or `nothing`."
    group::Union{Nothing, Symbol}
    "Initial series visibility."
    visible::Bool
    "Validated visual primitive attributes."
    attributes::A
end

function SeriesDefinition(
        kind::Symbol,
        xdata,
        ydata,
        zdata,
        label;
        group::Union{Nothing, Symbol} = nothing,
        visible::Bool = true,
        attributes::NamedTuple = (;)
)
    _reject_reserved(attributes, SERIES_RESERVED_ATTRIBUTES, "SeriesDefinition")
    resolved_label = label === nothing ? nothing : String(label)
    return SeriesDefinition(kind, xdata, ydata, zdata, resolved_label, group, visible, attributes)
end

"""
    ViewDefinition(xaxis, yaxis, zaxis, title, series, key; placement, aspect, limits, attributes)

Describe one plot panel and its placement.
"""
struct ViewDefinition{A <: NamedTuple}
    "Definition for the x axis, or `nothing`."
    xaxis::Union{Nothing, AxisDefinition}
    "Definition for the y axis, or `nothing`."
    yaxis::Union{Nothing, AxisDefinition}
    "Definition for the z axis, or `nothing`."
    zaxis::Union{Nothing, AxisDefinition}
    "Displayed panel title."
    title::String
    "Backend-neutral series declarations."
    series::Vector{SeriesDefinition}
    "Semantic panel identity."
    key::NamedTuple
    "Named-slot placement."
    placement::PlacementDefinition
    "Renderer-independent aspect declaration."
    aspect::Any
    "Explicit axis limits, or `nothing`."
    limits::Any
    "Validated visual panel attributes."
    attributes::A
end

function ViewDefinition(
        xaxis,
        yaxis,
        zaxis,
        title,
        series,
        key::NamedTuple;
        placement::PlacementDefinition = PlacementDefinition(),
        aspect = nothing,
        limits = nothing,
        attributes::NamedTuple = (;)
)
    _reject_reserved(attributes, VIEW_RESERVED_ATTRIBUTES, "ViewDefinition")
    return ViewDefinition(
        xaxis,
        yaxis,
        zaxis,
        String(title),
        SeriesDefinition[series...],
        key,
        placement,
        aspect,
        limits,
        attributes
    )
end

"""
    PageDefinition(title, size, key, layout, views; controls, legend, colorbars, status, export_definition)

Describe one complete render page using typed backend-neutral components.
"""
struct PageDefinition
    "Displayed page title."
    title::String
    "Figure width and height in pixels."
    size::Tuple{Int, Int}
    "Semantic page identity."
    key::NamedTuple
    "Named layout tree."
    layout::LayoutDefinition
    "Plot panels on the page."
    views::Vector{ViewDefinition}
    "Interactive control declaration."
    controls::ControlDefinition
    "Legend declaration."
    legend::LegendDefinition
    "Colorbar declarations."
    colorbars::Vector{ColorbarDefinition}
    "Status-line declaration."
    status::StatusDefinition
    "SVG export declaration."
    export_definition::ExportDefinition
end

function PageDefinition(
        title::AbstractString,
        size::Tuple{<:Integer, <:Integer},
        key::NamedTuple,
        layout::LayoutDefinition,
        views::AbstractVector;
        controls::ControlDefinition = ControlDefinition(),
        legend::LegendDefinition = LegendDefinition(),
        colorbars::AbstractVector = ColorbarDefinition[],
        status::StatusDefinition = StatusDefinition(),
        export_definition::ExportDefinition = ExportDefinition(name = title)
)
    all(>(0), size) || throw(ArgumentError("page dimensions must be positive"))
    page = PageDefinition(
        String(title),
        Tuple(Int.(size)),
        key,
        layout,
        ViewDefinition[views...],
        controls,
        legend,
        ColorbarDefinition[colorbars...],
        status,
        export_definition
    )
    validate(page)
    return page
end

"""
    RenderDefinition(definition, figures)

Store validated pages produced for one plot definition type.
"""
struct RenderDefinition{S <: AbstractPlotDefinition}
    "Plot definition type."
    definition::Type{S}
    "Validated render pages."
    figures::Vector{PageDefinition}
end

function RenderDefinition(definition::Type{S}, figures::AbstractVector) where {S <: AbstractPlotDefinition}
    render = RenderDefinition(definition, PageDefinition[figures...])
    validate(render)
    return render
end

const SUPPORTED_PRIMITIVES = (
    :line, :scatter, :histogram, :stairs, :heatmap, :polygon, :hline, :vline, :band)

function _overlaps(first::GridArea, second::GridArea)
    !isempty(intersect(first.rows, second.rows)) &&
        !isempty(intersect(first.columns, second.columns))
end

function _validate_area(area::GridArea, rows::Int, columns::Int, owner::AbstractString)
    last(area.rows) <= rows && last(area.columns) <= columns || throw(
        ArgumentError("$owner area exceeds its parent grid tracks"),
    )
    return area
end

function _check_sibling_overlap(children)
    length(children) < 2 && return nothing
    for first_index in 1:(length(children) - 1)
        for second_index in (first_index + 1):length(children)
            first_area = children[first_index].area
            second_area = children[second_index].area
            _overlaps(first_area, second_area) && throw(
                ArgumentError("sibling layout areas $first_index and $second_index overlap"),
            )
        end
    end
    return nothing
end

"""
    validate(definition)

Validate a layout, page, or complete render definition and return it.

# Errors

- `ArgumentError`, `DimensionMismatch`, or `DomainError` when semantic fields,
  data shapes, layout relationships, placements, or logarithmic data are invalid.
"""
function validate(layout::LayoutDefinition)
    isempty(layout.grids) && throw(ArgumentError("a layout requires at least one grid"))
    grid_names = getfield.(layout.grids, :name)
    slot_names = getfield.(layout.slots, :name)
    length(unique(grid_names)) == length(grid_names) || throw(
        ArgumentError("layout grid names must be unique"),
    )
    length(unique(slot_names)) == length(slot_names) || throw(
        ArgumentError("layout slot names must be unique"),
    )
    isempty(intersect(grid_names, slot_names)) || throw(
        ArgumentError("layout grid and slot names must be globally unique"),
    )
    roots = filter(grid -> grid.parent === nothing, layout.grids)
    length(roots) == 1 || throw(ArgumentError("a layout requires exactly one root grid"))
    only(roots).area === nothing ||
        throw(ArgumentError("the root grid cannot have an area"))
    grids = Dict(grid.name => grid for grid in layout.grids)
    for grid in layout.grids
        grid.parent === nothing && continue
        haskey(grids, grid.parent) || throw(
            ArgumentError("grid :$(grid.name) references missing parent :$(grid.parent)"),
        )
        grid.area === nothing && throw(
            ArgumentError("nested grid :$(grid.name) requires an area"),
        )
        parent = grids[grid.parent]
        _validate_area(grid.area, length(parent.rows), length(parent.columns), "grid :$(grid.name)")
        visited = Set{Symbol}((grid.name,))
        ancestor = grid.parent
        while ancestor !== nothing
            ancestor in visited &&
                throw(ArgumentError("layout grid hierarchy contains a cycle"))
            push!(visited, ancestor)
            ancestor = grids[ancestor].parent
        end
    end
    for slot in layout.slots
        haskey(grids, slot.parent) || throw(
            ArgumentError("slot :$(slot.name) references missing grid :$(slot.parent)"),
        )
        parent = grids[slot.parent]
        _validate_area(slot.area, length(parent.rows), length(parent.columns), "slot :$(slot.name)")
    end
    for parent in layout.grids
        children = Any[grid for grid in layout.grids if grid.parent === parent.name]
        append!(children, [slot for slot in layout.slots if slot.parent === parent.name])
        _check_sibling_overlap(children)
    end
    return layout
end

function _validate_series(series::SeriesDefinition)
    series.kind in SUPPORTED_PRIMITIVES || throw(
        ArgumentError("unsupported PlotBuilder primitive :$(series.kind)"),
    )
    if series.kind in (:line, :scatter, :stairs)
        series.xdata === nothing && throw(ArgumentError(":$(series.kind) requires x data"))
        series.ydata === nothing && throw(ArgumentError(":$(series.kind) requires y data"))
        length(series.xdata) == length(series.ydata) || throw(
            DimensionMismatch(":$(series.kind) x and y data must have equal lengths"),
        )
    elseif series.kind === :histogram
        series.xdata === nothing && throw(ArgumentError(":histogram requires sample data"))
    elseif series.kind === :heatmap
        any(isnothing, (series.xdata, series.ydata, series.zdata)) && throw(
            ArgumentError(":heatmap requires x, y, and z data"),
        )
        size(series.zdata) == (length(series.xdata), length(series.ydata)) || throw(
            DimensionMismatch(":heatmap z data must match x and y dimensions"),
        )
    elseif series.kind === :polygon
        series.zdata === nothing && throw(ArgumentError(":polygon requires geometry data"))
    elseif series.kind === :hline
        series.ydata === nothing && throw(ArgumentError(":hline requires y data"))
    elseif series.kind === :vline
        series.xdata === nothing && throw(ArgumentError(":vline requires x data"))
    elseif series.kind === :band
        any(isnothing, (series.xdata, series.ydata, series.zdata)) && throw(
            ArgumentError(":band requires x, lower-y, and upper-y data"),
        )
        length(series.xdata) == length(series.ydata) == length(series.zdata) || throw(
            DimensionMismatch(":band x, lower-y, and upper-y data must have equal lengths"),
        )
    end
    return series
end

function _validate_log_axis(view::ViewDefinition, axis::AxisDefinition)
    :log10 in axis.allowed_scales || return axis
    found = false
    for series in view.series
        samples = axis.dim === :x ? series.xdata :
                  axis.dim === :y ? series.ydata : series.zdata
        samples === nothing && continue
        for sample in samples
            nominal_value = nominal(sample)
            nominal_value isa Real || continue
            found = true
            lower = nominal_value - abs(standard_uncertainty(sample))
            isfinite(nominal_value) && isfinite(lower) && lower > 0 || throw(
                DomainError(sample, "logarithmic axes require positive finite data and uncertainty bounds"),
            )
        end
    end
    found || throw(
        ArgumentError("axis :$(axis.dim) declares logarithmic scale without plottable data"),
    )
    return axis
end

function _validate_view_limits(view::ViewDefinition)
    view.limits === nothing && return view
    view.limits isa Tuple && length(view.limits) == 2 || throw(
        ArgumentError("view limits must be `(xlimits, ylimits)` or `nothing`"),
    )
    for (axis, limits) in zip((view.xaxis, view.yaxis), view.limits)
        axis === nothing && throw(
            ArgumentError("view limits require both x and y axes"),
        )
        limits isa Tuple && length(limits) == 2 || throw(
            ArgumentError("each view limit must be a two-value tuple"),
        )
        lower, upper = limits
        lower isa Real && upper isa Real && isfinite(lower) && isfinite(upper) || throw(
            ArgumentError("view limits must contain finite real values"),
        )
        lower < upper || throw(
            ArgumentError("view limits must be strictly increasing"),
        )
        axis.scale === :log10 && lower <= 0 &&
            throw(
                DomainError(limits, "logarithmic view limits must be positive"),
            )
    end
    return view
end

function _validate_view_aspect(view::ViewDefinition)
    view.aspect === nothing && return view
    view.aspect === :data && return view
    view.aspect isa Real && isfinite(view.aspect) && view.aspect > 0 && return view
    throw(ArgumentError("view aspect must be nothing, :data, or a positive finite number"))
end

function _required_slots(page::PageDefinition)
    required = Symbol[]
    append!(required, unique(view.placement.slot for view in page.views))
    scale_controls = any(
        axis -> axis !== nothing && :log10 in axis.allowed_scales,
        (view_axis for view in page.views for view_axis in (view.xaxis, view.yaxis))
    )
    (page.controls.reset || page.controls.export_svg || scale_controls) &&
        push!(required, page.controls.slot)
    page.legend.enabled && push!(required, page.legend.slot)
    page.status.enabled && push!(required, page.status.slot)
    append!(required, unique(colorbar.slot for colorbar in page.colorbars))
    return unique(required)
end

function _validate_legend_slot(page::PageDefinition)
    page.legend.enabled || return page
    page.legend.overflow === :ellipsis || return page
    slot = only(filter(item -> item.name === page.legend.slot, page.layout.slots))
    parent = only(filter(grid -> grid.name === slot.parent, page.layout.grids))
    tracks = parent.rows[slot.area.rows]
    any(track -> track isa ContentTrack, tracks) && throw(
        ArgumentError(
        "responsive legend slot :$(slot.name) must use fixed or relative row tracks; " *
        "use `overflow=:show_all` for a content-sized legend row",
    ),
    )
    return page
end

function validate(page::PageDefinition)
    validate(page.layout)
    slots = Set(getfield.(page.layout.slots, :name))
    missing = setdiff(_required_slots(page), collect(slots))
    isempty(missing) || throw(
        ArgumentError("page content references missing layout slots: $(join(missing, ", "))"),
    )
    _validate_legend_slot(page)
    for view in page.views
        foreach(_validate_series, view.series)
        _validate_view_limits(view)
        _validate_view_aspect(view)
        view.xaxis === nothing || view.xaxis.dim === :x ||
            throw(
                ArgumentError("a view x-axis must declare dimension :x"),
            )
        view.yaxis === nothing || view.yaxis.dim === :y ||
            throw(
                ArgumentError("a view y-axis must declare dimension :y"),
            )
        view.zaxis === nothing || view.zaxis.dim === :z ||
            throw(
                ArgumentError("a view z-axis must declare dimension :z"),
            )
        axes = [axis for axis in (view.xaxis, view.yaxis, view.zaxis) if axis !== nothing]
        foreach(axis -> _validate_log_axis(view, axis), axes)
        length(unique(axis.dim for axis in axes)) == length(axes) || throw(
            ArgumentError("view axes must have unique dimensions"),
        )
    end
    view_keys = [view.key for view in page.views if !isempty(view.key)]
    length(unique(view_keys)) == length(view_keys) || throw(
        ArgumentError("page views must have unique nonempty semantic keys"),
    )
    for slot in unique(view.placement.slot for view in page.views)
        placements = [view.placement for view in page.views if view.placement.slot === slot]
        explicit = map(placement -> placement.area !== nothing, placements)
        all(explicit) || all(!, explicit) ||
            throw(
                ArgumentError("views in slot :$slot cannot mix automatic and explicit placement"),
            )
        all(explicit) && _check_sibling_overlap(placements)
    end
    return page
end

function validate(render::RenderDefinition)
    foreach(validate, render.figures)
    keys = [page.key for page in render.figures if !isempty(page.key)]
    length(unique(keys)) == length(keys) || throw(
        ArgumentError("render pages must have unique nonempty semantic keys"),
    )
    return render
end

"""
    UIPlot

Hold a backend-neutral render definition together with one built figure,
its panels, controls, and backend context. A rendered recipe returns one
`UIPlot` per declarative page.
"""
struct UIPlot{S <: AbstractPlotDefinition, F, P, W, C}
    "Complete backend-neutral render definition."
    render::RenderDefinition{S}
    "Page represented by this handle."
    page::PageDefinition
    "Backend-built figure."
    figure::F
    "Built axes or panels."
    panels::P
    "Interactive control objects keyed by purpose."
    controls::W
    "Active backend and status context."
    context::C
end

function _show_summary(io::IO, name::AbstractString, fields::Pair...)
    print(io, name, "(")
    for (index, (key, value)) in enumerate(fields)
        index == 1 || print(io, ", ")
        print(io, key, "=")
        show(io, value)
    end
    print(io, ")")
end

function _data_shape(data)
    data === nothing ? nothing :
    data isa AbstractArray ? size(data) : nameof(typeof(data))
end

function Base.show(io::IO, value::FixedTrack)
    _show_summary(io, "FixedTrack", :value => value.value)
end
function Base.show(io::IO, value::RelativeTrack)
    _show_summary(io, "RelativeTrack", :weight => value.weight)
end
Base.show(io::IO, ::ContentTrack) = print(io, "ContentTrack()")
function Base.show(io::IO, value::GridArea)
    _show_summary(io, "GridArea", :rows => value.rows, :columns => value.columns)
end
function Base.show(io::IO, value::PlotRecipe)
    _show_summary(
        io,
        "PlotRecipe",
        :object => nameof(typeof(value.object)),
        :input => keys(value.input),
        :renderer => keys(value.renderer)
    )
end
function Base.show(io::IO, value::GridDefinition)
    _show_summary(
        io,
        "GridDefinition",
        :name => value.name,
        :rows => length(value.rows),
        :columns => length(value.columns)
    )
end
function Base.show(io::IO, value::SlotDefinition)
    _show_summary(
        io,
        "SlotDefinition",
        :name => value.name,
        :parent => value.parent,
        :area => value.area,
        :alignment => (value.halign, value.valign)
    )
end
function Base.show(io::IO, value::LayoutDefinition)
    _show_summary(
        io,
        "LayoutDefinition",
        :name => value.name,
        :grids => length(value.grids),
        :slots => length(value.slots)
    )
end
function Base.show(io::IO, value::PlacementDefinition)
    _show_summary(io, "PlacementDefinition", :slot => value.slot, :area => value.area)
end
function Base.show(io::IO, value::ControlDefinition)
    _show_summary(
        io,
        "ControlDefinition",
        :reset => value.reset,
        :export_svg => value.export_svg,
        :slot => value.slot
    )
end
function Base.show(io::IO, value::LegendDefinition)
    _show_summary(
        io,
        "LegendDefinition",
        :enabled => value.enabled,
        :interactive => value.interactive,
        :slot => value.slot,
        :overflow => value.overflow
    )
end
function Base.show(io::IO, value::ColorbarDefinition)
    _show_summary(
        io,
        "ColorbarDefinition",
        :label => value.label,
        :limits => value.limits,
        :ticks => length(first(value.ticks)),
        :slot => value.slot
    )
end
function Base.show(io::IO, value::StatusDefinition)
    _show_summary(io, "StatusDefinition", :enabled => value.enabled, :slot => value.slot)
end
function Base.show(io::IO, value::ExportDefinition)
    _show_summary(
        io,
        "ExportDefinition",
        :theme => value.theme,
        :name => value.name,
        :open_file => value.open_file
    )
end
function Base.show(io::IO, value::AxisDefinition)
    _show_summary(
        io,
        "AxisDefinition",
        :dimension => value.dim,
        :label => value.label,
        :scale => value.scale,
        :allowed_scales => value.allowed_scales
    )
end
function Base.show(io::IO, value::SeriesDefinition)
    _show_summary(
        io,
        "SeriesDefinition",
        :kind => value.kind,
        :x => _data_shape(value.xdata),
        :y => _data_shape(value.ydata),
        :z => _data_shape(value.zdata),
        :label => value.label,
        :group => value.group,
        :visible => value.visible
    )
end
function Base.show(io::IO, value::ViewDefinition)
    _show_summary(
        io,
        "ViewDefinition",
        :title => value.title,
        :series => length(value.series),
        :slot => value.placement.slot
    )
end
function Base.show(io::IO, value::PageDefinition)
    _show_summary(
        io,
        "PageDefinition",
        :title => value.title,
        :size => value.size,
        :views => length(value.views),
        :layout => value.layout.name
    )
end
function Base.show(io::IO, value::RenderDefinition)
    _show_summary(
        io,
        "RenderDefinition",
        :definition => nameof(value.definition),
        :pages => length(value.figures)
    )
end
function Base.show(io::IO, value::UIPlot)
    backend = hasproperty(value.context, :backend) ? getproperty(value.context, :backend) :
              :unknown
    return _show_summary(
        io,
        "UIPlot",
        :title => value.page.title,
        :panels => length(value.panels),
        :backend => backend
    )
end

const _CompactPlotBuilderObject = Union{
    PlotRecipe,
    FixedTrack,
    RelativeTrack,
    ContentTrack,
    GridArea,
    GridDefinition,
    SlotDefinition,
    LayoutDefinition,
    PlacementDefinition,
    ControlDefinition,
    LegendDefinition,
    ColorbarDefinition,
    StatusDefinition,
    ExportDefinition,
    AxisDefinition,
    SeriesDefinition,
    ViewDefinition,
    PageDefinition,
    RenderDefinition,
    UIPlot
}

Base.show(io::IO, ::MIME"text/plain", value::_CompactPlotBuilderObject) = show(io, value)
