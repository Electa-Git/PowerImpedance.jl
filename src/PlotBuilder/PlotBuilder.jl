"""
    PlotBuilder

Build backend-neutral plotting descriptions from typed completed results.
Optional Makie extensions render the resulting `RenderDefinition` values.
"""
module PlotBuilder

using DocStringExtensions: TYPEDEF, TYPEDFIELDS, TYPEDSIGNATURES

import ..UnitHandler: Units, QuantityTag, display_unit, get_label, nominal,
                      standard_uncertainty

export AbstractPlotDefinition, PlotRecipe
export AbstractTrackSize, FixedTrack, RelativeTrack, ContentTrack
export GridArea, GridDefinition, SlotDefinition, LayoutDefinition, PlacementDefinition
export ControlDefinition, LegendDefinition, ColorbarDefinition, StatusDefinition, ExportDefinition
export AxisDefinition, SeriesDefinition, ViewDefinition, PageDefinition, RenderDefinition, UIPlot
export make_render, export_svg
export dispatch_on, input_kwargs, renderer_kwargs, input_defaults, renderer_defaults
export parse_kwargs, resolve_input, recipe_mode, grouping_mode
export page_facets, group_facets, geom_axes, axis_quantity, axis_unit, axis_label
export axis_scale, axis_scales, axis_exponent, axis_attributes
export plot_kind, series_data, legend_label, series_group, series_visible,
       series_attributes
export default_title, default_figsize, layout_definition, layout_preset, page_identity
export view_key, view_placement, view_aspect, view_limits, view_attributes
export control_definition, legend_definition, colorbar_definitions, status_definition, export_definition
export make_axes, make_series, make_views, make_pages, validate

const EXPORT_THEMES = (:default, :publication)

function _validate_export_theme(value::Symbol)
    value in EXPORT_THEMES || throw(
        ArgumentError("export_theme must be :default or :publication"),
    )
    return value
end

include("BackendHandler.jl")
using .BackendHandler

include("types.jl")
include("grammar.jl")

"""
$(TYPEDSIGNATURES)

Export the current state of a `UIPlot` through an explicitly loaded
CairoMakie extension.
"""
function export_svg end

end
