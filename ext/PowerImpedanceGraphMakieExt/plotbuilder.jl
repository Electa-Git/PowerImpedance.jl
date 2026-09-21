const NetworkDiagramDefinition = PowerImpedance.NetworkDiagramDefinition
const _NETWORK_DIAGRAM_GROUP = :network_diagram
const _NETWORK_DIAGRAM_TOOLBAR_HEIGHT = 36
const _NETWORK_DIAGRAM_STATUS_HEIGHT = 20
const _NETWORK_DIAGRAM_ROW_GAP = 6
const _NETWORK_DIAGRAM_PADDING = (20, 20, 28, 28)
const _NETWORK_DIAGRAM_TARGET_EXTENT = 760
const _NETWORK_DIAGRAM_MINIMUM_SIZE = (480, 420)

"Retain one resolved network projection for PlotBuilder materialization."
struct DiagramPrimitive{M, P, S}
    model::M
    positions::P
    interactive::Bool
    style::S
end

PlotBuilder.dispatch_on(::Type{NetworkDiagramDefinition}) = NetworkBuilder.NetworkState
PlotBuilder.input_kwargs(::Type{NetworkDiagramDefinition}) = (:powerflow,)
function PlotBuilder.renderer_kwargs(::Type{NetworkDiagramDefinition})
    return (
        :graph_layout,
        :positions,
        :interactive,
        :style,
        :title,
        :figure_size
    )
end

function PlotBuilder.input_defaults(::Type{NetworkDiagramDefinition}, network)
    return (; powerflow = nothing)
end

function PlotBuilder.renderer_defaults(::Type{NetworkDiagramDefinition}, network)
    return (;
        graph_layout = NetworkLayout.Stress(; seed = 1),
        positions = nothing,
        interactive = true,
        style = (;),
        title = "Network diagram",
        figure_size = :auto
    )
end

function _network_diagram_figure_size(positions)
    isempty(positions) && return (640, 520)
    xcoordinates = first.(values(positions))
    ycoordinates = last.(values(positions))
    xspan = Float64(maximum(xcoordinates) - minimum(xcoordinates))
    yspan = Float64(maximum(ycoordinates) - minimum(ycoordinates))
    aspect = if iszero(xspan) && iszero(yspan)
        1.0
    elseif iszero(yspan)
        4.0
    elseif iszero(xspan)
        0.25
    else
        clamp(xspan / yspan, 0.25, 4.0)
    end
    diagram_width, diagram_height = if aspect >= 1
        (_NETWORK_DIAGRAM_TARGET_EXTENT, _NETWORK_DIAGRAM_TARGET_EXTENT / aspect)
    else
        (_NETWORK_DIAGRAM_TARGET_EXTENT * aspect, _NETWORK_DIAGRAM_TARGET_EXTENT)
    end
    horizontal_chrome = _NETWORK_DIAGRAM_PADDING[1] + _NETWORK_DIAGRAM_PADDING[2]
    vertical_chrome = _NETWORK_DIAGRAM_TOOLBAR_HEIGHT +
                      _NETWORK_DIAGRAM_STATUS_HEIGHT +
                      2 * _NETWORK_DIAGRAM_ROW_GAP +
                      _NETWORK_DIAGRAM_PADDING[3] +
                      _NETWORK_DIAGRAM_PADDING[4]
    return (
        max(_NETWORK_DIAGRAM_MINIMUM_SIZE[1], round(Int, diagram_width + horizontal_chrome)),
        max(_NETWORK_DIAGRAM_MINIMUM_SIZE[2], round(Int, diagram_height + vertical_chrome))
    )
end

function PlotBuilder.resolve_input(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    powerflow = recipe.input.powerflow
    powerflow === nothing || powerflow isa PowerFlowResult ||
        throw(
            ArgumentError("powerflow must be nothing or a PowerFlowResult"),
        )
    recipe.renderer.interactive isa Bool || throw(
        ArgumentError("interactive must be Bool"),
    )
    recipe.renderer.style isa NamedTuple || throw(
        ArgumentError("style must be a NamedTuple"),
    )
    recipe.renderer.title isa AbstractString || throw(
        ArgumentError("title must be a string"),
    )
    figure_size = recipe.renderer.figure_size
    explicit_size = figure_size isa Tuple && length(figure_size) == 2 &&
                    all(value -> value isa Integer && value > 0, figure_size)
    figure_size === :auto || explicit_size || throw(
        ArgumentError("figure_size must be :auto or contain two positive integers"),
    )

    model = project_diagram(recipe.object, powerflow)
    positions = _resolve_positions(
        model,
        recipe.renderer.graph_layout,
        recipe.renderer.positions
    )
    resolved_figure_size = figure_size === :auto ?
                           _network_diagram_figure_size(positions) :
                           Tuple(Int.(figure_size))
    style = _diagram_style(recipe.renderer.style)
    primitive = DiagramPrimitive(
        model,
        positions,
        recipe.renderer.interactive,
        style
    )
    input = merge(recipe.input, (; model, positions, primitive))
    renderer = merge(
        recipe.renderer,
        (;
            style,
            title = String(recipe.renderer.title),
            figure_size = resolved_figure_size
        )
    )
    return PlotBuilder.PlotRecipe(recipe.object, input, renderer)
end

function PlotBuilder.axis_label(
        ::Type{NetworkDiagramDefinition},
        dim::Val,
        quantity::PowerImpedance.UnitHandler.QuantityTag,
        unit::PowerImpedance.UnitHandler.Units,
        recipe::PlotBuilder.PlotRecipe
)
    return ""
end

function PlotBuilder.plot_kind(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe, series_key
)
    return :network_diagram
end

function PlotBuilder.series_data(
        ::Type{NetworkDiagramDefinition}, ::Val{:x}, recipe::PlotBuilder.PlotRecipe,
        series_key
)
    primitive = recipe.input.primitive
    return [primitive.positions[key][1] for key in primitive.model.vertex_keys]
end

function PlotBuilder.series_data(
        ::Type{NetworkDiagramDefinition}, ::Val{:y}, recipe::PlotBuilder.PlotRecipe,
        series_key
)
    primitive = recipe.input.primitive
    return [primitive.positions[key][2] for key in primitive.model.vertex_keys]
end

function PlotBuilder.series_data(
        ::Type{NetworkDiagramDefinition}, ::Val{:z}, recipe::PlotBuilder.PlotRecipe,
        series_key
)
    return recipe.input.primitive
end

function PlotBuilder.series_group(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe, series_key
)
    return _NETWORK_DIAGRAM_GROUP
end

function PlotBuilder.view_key(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return (; kind = :network_diagram)
end

function PlotBuilder.view_aspect(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return :data
end

function PlotBuilder.view_attributes(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return (;
        titlevisible = false,
        xautolimitmargin = (0.12, 0.12),
        yautolimitmargin = (0.12, 0.12),
        backgroundcolor = recipe.renderer.style.background
    )
end

function PlotBuilder.default_title(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return recipe.renderer.title
end

function PlotBuilder.default_figsize(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return recipe.renderer.figure_size
end

function _network_diagram_ui_layout()
    root = PlotBuilder.GridDefinition(
        :root;
        rows = PlotBuilder.AbstractTrackSize[
            PlotBuilder.FixedTrack(_NETWORK_DIAGRAM_TOOLBAR_HEIGHT),
            PlotBuilder.RelativeTrack(),
            PlotBuilder.FixedTrack(_NETWORK_DIAGRAM_STATUS_HEIGHT)
        ],
        columns = PlotBuilder.AbstractTrackSize[PlotBuilder.RelativeTrack()],
        rowgap = _NETWORK_DIAGRAM_ROW_GAP,
        padding = _NETWORK_DIAGRAM_PADDING
    )
    slots = [
        PlotBuilder.SlotDefinition(
            :toolbar,
            :root,
            PlotBuilder.GridArea(1, 1);
            halign = :left,
            valign = :bottom
        ),
        PlotBuilder.SlotDefinition(
            :canvas,
            :root,
            PlotBuilder.GridArea(2, 1);
            halign = :stretch,
            valign = :stretch
        ),
        PlotBuilder.SlotDefinition(
            :status,
            :root,
            PlotBuilder.GridArea(3, 1);
            halign = :left,
            valign = :center
        )
    ]
    return PlotBuilder.LayoutDefinition(:network_diagram, [root], slots)
end

function PlotBuilder.layout_definition(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return _network_diagram_ui_layout()
end

function PlotBuilder.control_definition(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return PlotBuilder.ControlDefinition(; reset = true, export_svg = true)
end

function PlotBuilder.legend_definition(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return PlotBuilder.LegendDefinition(; enabled = false, interactive = false)
end

function PlotBuilder.status_definition(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe
)
    return PlotBuilder.StatusDefinition(; initial = "Network diagram ready.")
end

function PlotBuilder.export_definition(
        ::Type{NetworkDiagramDefinition}, recipe::PlotBuilder.PlotRecipe,
        title::AbstractString
)
    return PlotBuilder.ExportDefinition(
        theme = recipe.renderer.export_theme,
        name = isempty(strip(title)) ? "network_diagram" : title,
        open_file = recipe.renderer.open_export
    )
end

function PlotBuilder.render_primitive!(
        axis,
        ::Val{:network_diagram},
        series::PlotBuilder.SeriesDefinition
)
    primitive = series.zdata
    primitive isa DiagramPrimitive || throw(
        ArgumentError("network diagram series contains an invalid render payload"),
    )
    figure = Makie.get_figure(axis.parent)
    figure isa Makie.Figure ||
        error("network diagram axis is not attached to a Makie Figure")
    view = _render_diagram_on_axis!(
        figure,
        axis,
        primitive.model,
        primitive.positions;
        interactive = primitive.interactive,
        style = primitive.style
    )
    plots = _diagram_plots(view)
    foreach(plot -> (plot.visible[] = series.visible), plots)
    return PlotBuilder.PrimitiveRender(plots, view)
end

"""
$(TYPEDSIGNATURES)

Render a materialized network through [`NetworkDiagramDefinition`](@ref) and
the PlotBuilder UI.

# Arguments

- `network`: Network topology to project.
- `powerflow`: Optional completed result used only for solved-state enrichment.

# Keywords

- `backend`: Makie backend selector accepted by PlotBuilder.
- `display_plot`: display the built figure. Default: `true`.
- `controls`: include reset, SVG export, and status UI. Default: `true`.
- `figure_size`: `:auto` fits the window to the resolved layout; pass `(width,
  height)` to override it. Default: `:auto`.
- Additional keywords are validated by `NetworkDiagramDefinition`.

# Returns

- A one-element vector of `UIPlot` handles. The exact `NetworkDiagram` state is
  available as `only(result).artifacts[:network_diagram]`.
"""
function plot(
        network::NetworkBuilder.NetworkState;
        backend = nothing,
        display_plot::Bool = true,
        controls::Bool = true,
        kwargs...
)
    render = PlotBuilder.make_render(NetworkDiagramDefinition, network; kwargs...)
    return PlotBuilder.build(render; backend, display = display_plot, controls)
end

function plot(
        network::NetworkBuilder.NetworkState,
        powerflow::PowerFlowResult;
        kwargs...
)
    return plot(network; powerflow, kwargs...)
end

function Makie.plot(network::NetworkBuilder.NetworkState; kwargs...)
    return plot(network; kwargs...)
end

function Makie.plot(
        network::NetworkBuilder.NetworkState,
        powerflow::PowerFlowResult;
        kwargs...
)
    return plot(network, powerflow; kwargs...)
end
