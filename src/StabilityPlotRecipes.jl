import Statistics

export NyquistPlotDefinition, BodePlotDefinition, PassivityPlotDefinition
export SmallGainPlotDefinition, EigenvaluePlotDefinition
export UnstableFrequencyPlotDefinition

const _CompletedStabilityResult = Union{
    StabilityResult,
    AbstractParametricResult{<:StabilityResult},
    AbstractUncertaintyResult{<:StabilityResult},
}

"Select a generalized-Nyquist plot from completed stability calculations."
struct NyquistPlotDefinition <: PlotBuilder.AbstractPlotDefinition end

"Select magnitude and phase plots from completed Bode calculations."
struct BodePlotDefinition <: PlotBuilder.AbstractPlotDefinition end

"Select a passivity-index plot from completed passivity calculations."
struct PassivityPlotDefinition <: PlotBuilder.AbstractPlotDefinition end

"Select a singular-value plot from completed small-gain calculations."
struct SmallGainPlotDefinition <: PlotBuilder.AbstractPlotDefinition end

"Select modal plots from completed eigenvalue calculations."
struct EigenvaluePlotDefinition <: PlotBuilder.AbstractPlotDefinition end

"Select complementary-sensitivity plots from completed frequency detection."
struct UnstableFrequencyPlotDefinition <: PlotBuilder.AbstractPlotDefinition end

for Definition in (
    NyquistPlotDefinition,
    BodePlotDefinition,
    PassivityPlotDefinition,
    SmallGainPlotDefinition,
    EigenvaluePlotDefinition,
    UnstableFrequencyPlotDefinition,
)
    @eval PlotBuilder.dispatch_on(::Type{$Definition}) = _CompletedStabilityResult
end

_stability_values(result::StabilityResult) = StabilityResult[result]
_stability_values(result::AbstractParametricResult{<:StabilityResult}) = result.values
function _stability_values(result::AbstractUncertaintyResult{<:StabilityResult})
    hasproperty(result.details, :plot_data) || throw(ArgumentError(
        "the uncertainty result does not retain completed plot trajectories",
    ))
    grouped = result.details.plot_data.values
    return reduce(vcat, grouped; init=StabilityResult[])
end

function _validate_stability_recipe(recipe, analysis::Symbol)
    values = _stability_values(recipe.object)
    isempty(values) && throw(ArgumentError("the result contains no completed calculations"))
    all(value -> value.analysis === analysis, values) || throw(ArgumentError(
        "the plot definition requires analysis :$analysis",
    ))
    spread = recipe.input.spread
    spread isa Tuple && length(spread) == 2 || throw(ArgumentError(
        "spread must be a two-value probability tuple",
    ))
    lower, upper = spread
    0 <= lower < 0.5 < upper <= 1 || throw(ArgumentError(
        "spread must satisfy 0 ≤ lower < 0.5 < upper ≤ 1",
    ))
    recipe.input.ensemble isa Integer && recipe.input.ensemble >= 0 || throw(
        ArgumentError("ensemble must be a nonnegative integer"),
    )
    recipe.renderer.title isa AbstractString || throw(ArgumentError("title must be a string"))
    size = recipe.renderer.figure_size
    size isa Tuple && length(size) == 2 &&
        all(value -> value isa Integer && value > 0, size) || throw(ArgumentError(
        "figure_size must contain two positive integers",
    ))
    return PlotBuilder.PlotRecipe(
        recipe.object,
        merge(recipe.input, (; values)),
        merge(recipe.renderer, (; title=String(recipe.renderer.title), figure_size=Tuple(Int.(size)))),
    )
end

function _curve_statistics(curves, spread)
    isempty(curves) && throw(ArgumentError("at least one trajectory is required"))
    length(first(curves)) > 0 || throw(ArgumentError("plot trajectories cannot be empty"))
    all(curve -> length(curve) == length(first(curves)), curves) || throw(
        DimensionMismatch("plot trajectories must have equal lengths"),
    )
    lower_probability, upper_probability = spread
    count = length(first(curves))
    center = Vector{Float64}(undef, count)
    lower = similar(center)
    upper = similar(center)
    for index in 1:count
        samples = Float64[curve[index] for curve in curves]
        center[index] = Statistics.median(samples)
        lower[index] = Statistics.quantile(samples, lower_probability)
        upper[index] = Statistics.quantile(samples, upper_probability)
    end
    return (; center, lower, upper)
end

function _selected_trajectories(values, count)
    count == 0 && return Int[]
    return unique(round.(Int, range(1, length(values); length=min(count, length(values)))))
end

function _quantity_axis(dim, label; scale=:linear, allowed_scales=(scale,))
    quantity = UnitHandler.QuantityTag{:dimensionless}()
    return PlotBuilder.AxisDefinition(
        dim,
        quantity,
        UnitHandler.display_unit(quantity),
        label,
        scale;
        allowed_scales,
    )
end

function _frequency_axis(; scale=:log10)
    quantity = UnitHandler.QuantityTag{:frequency}()
    return PlotBuilder.AxisDefinition(
        :x,
        quantity,
        UnitHandler.display_unit(quantity),
        "Frequency [Hz]",
        scale;
        allowed_scales=(:linear, :log10),
    )
end

function _plot_layout(renderer, view_count)
    selected = something(renderer.layout, :grid)
    selected isa PlotBuilder.LayoutDefinition && return selected
    selected isa Symbol || throw(ArgumentError(
        "layout must be a PlotBuilder layout name or LayoutDefinition",
    ))
    return PlotBuilder.layout_preset(Val(selected), view_count)
end

function _stability_page(
    ::Type{Definition},
    recipe,
    title,
    views;
    key=(;),
    legend=true,
    status="Ready.",
) where {Definition<:PlotBuilder.AbstractPlotDefinition}
    return PlotBuilder.PageDefinition(
        title,
        recipe.renderer.figure_size,
        key,
        _plot_layout(recipe.renderer, length(views)),
        views;
        controls=PlotBuilder.ControlDefinition(),
        legend=PlotBuilder.LegendDefinition(
            enabled=legend,
            interactive=true,
            overflow=:ellipsis,
        ),
        status=PlotBuilder.StatusDefinition(initial=status),
        export_definition=PlotBuilder.ExportDefinition(
            theme=recipe.renderer.export_theme,
            name=isempty(strip(title)) ? String(nameof(Definition)) : title,
            open_file=recipe.renderer.open_export,
        ),
    )
end

function _line!(series, x, y, label, group; attributes=(;), visible=true)
    push!(series, PlotBuilder.SeriesDefinition(
        :line,
        x,
        y,
        nothing,
        label;
        group,
        visible,
        attributes,
    ))
    return series
end

const _SERIES_COLORS = (
    :blue,
    :orange,
    :green,
    :purple,
    :brown,
    :pink,
    :gray,
    :olive,
    :cyan,
)

_series_color(index::Integer) = _SERIES_COLORS[mod1(index, length(_SERIES_COLORS))]

function _band!(series, x, statistics, group; color=nothing)
    attributes = color === nothing ? (; alpha=0.18) : (; color, alpha=0.18)
    push!(series, PlotBuilder.SeriesDefinition(
        :band,
        x,
        statistics.lower,
        statistics.upper,
        nothing;
        group,
        attributes,
    ))
    return series
end

const _ENSEMBLE_INPUTS = (:ensemble, :spread)
const _STANDARD_RENDERER = (:title, :figure_size)

PlotBuilder.input_kwargs(::Type{NyquistPlotDefinition}) =
    (:indentations, :direction, :zoom, _ENSEMBLE_INPUTS...)
PlotBuilder.renderer_kwargs(::Type{NyquistPlotDefinition}) = _STANDARD_RENDERER
function PlotBuilder.input_defaults(::Type{NyquistPlotDefinition}, result)
    return (; indentations=Float64[], direction=true, zoom=false, ensemble=20, spread=(0.05, 0.95))
end
function PlotBuilder.renderer_defaults(::Type{NyquistPlotDefinition}, result)
    return (; title="Nyquist plot", figure_size=(900, 720))
end
function PlotBuilder.resolve_input(
    ::Type{NyquistPlotDefinition},
    recipe::PlotBuilder.PlotRecipe,
)
    resolved = _validate_stability_recipe(recipe, :nyquist)
    resolved.input.direction isa Bool || throw(ArgumentError("direction must be Bool"))
    zoom = resolved.input.zoom
    zoom isa Bool || zoom in ("yes", "no", "") || throw(ArgumentError(
        "zoom must be Bool, \"yes\", \"no\", or an empty string",
    ))
    all(value -> value isa Real, resolved.input.indentations) || throw(ArgumentError(
        "indentations must contain angular frequencies",
    ))
    return resolved
end

function _indented_locus(locus, frequencies, indentations)
    isempty(indentations) && return copy(locus)
    copied = copy(locus)
    for frequency in indentations
        first(frequencies) < frequency < last(frequencies) || continue
        right = searchsortedfirst(frequencies, frequency)
        for index in unique((max(firstindex(copied), right - 1), min(lastindex(copied), right)))
            copied[index] = ComplexF64(NaN, NaN)
        end
    end
    return copied
end

function PlotBuilder.make_pages(
    ::Type{NyquistPlotDefinition},
    ::Val,
    ::Val,
    recipe::PlotBuilder.PlotRecipe,
)
    values = recipe.input.values
    frequencies = first(values).output.frequencies
    reference = first(values).output.eigenloci
    loci = Matrix{ComplexF64}[]
    for value in values
        value.output.frequencies == frequencies || throw(DimensionMismatch(
            "Nyquist result frequencies differ",
        ))
        matched, _ = _match_loci(value.output.eigenloci, reference)
        push!(loci, matched)
    end
    series = PlotBuilder.SeriesDefinition[]
    theta = range(0, 2pi; length=721)
    _line!(series, cos.(theta), sin.(theta), nothing, nothing;
        attributes=(; color=:red, linestyle=:dash, linewidth=2))
    push!(series, PlotBuilder.SeriesDefinition(
        :hline, nothing, [0.0], nothing, nothing;
        attributes=(; color=:black, linestyle=:dash),
    ))
    push!(series, PlotBuilder.SeriesDefinition(
        :vline, [0.0], nothing, nothing, nothing;
        attributes=(; color=:black, linestyle=:dash),
    ))
    push!(series, PlotBuilder.SeriesDefinition(
        :scatter, [-1.0], [0.0], nothing, "Critical point";
        group=:critical_point,
        attributes=(; color=:red, marker=:xcross, markersize=14),
    ))
    selected = _selected_trajectories(loci, recipe.input.ensemble)
    for mode in axes(reference, 2)
        group = Symbol("mode_$mode")
        color = _series_color(mode)
        curves = [_indented_locus(value[:, mode], frequencies, recipe.input.indentations)
            for value in loci]
        real_statistics = _curve_statistics(real.(curves), recipe.input.spread)
        imaginary_statistics = _curve_statistics(imag.(curves), recipe.input.spread)
        for trial in selected
            _line!(series, real.(curves[trial]), imag.(curves[trial]), nothing, group;
                attributes=(; color, alpha=0.12, linewidth=1))
        end
        _band!(series, real_statistics.center, imaginary_statistics, group; color)
        _line!(series, real_statistics.center, imaginary_statistics.center,
            "Mode $mode", group; attributes=(; color, linewidth=3))
        _line!(series, real_statistics.center, -imaginary_statistics.center,
            nothing, group; attributes=(; color, linewidth=2, linestyle=:dash))
        if recipe.input.direction
            index = argmax(abs.(imaginary_statistics.center))
            marker = index < length(real_statistics.center) &&
                real_statistics.center[index + 1] < real_statistics.center[index] ?
                :ltriangle : :rtriangle
            push!(series, PlotBuilder.SeriesDefinition(
                :scatter,
                [real_statistics.center[index]],
                [imaginary_statistics.center[index]],
                nothing,
                nothing;
                group,
                attributes=(; color, marker, markersize=12),
            ))
        end
    end
    zoom = recipe.input.zoom === true || recipe.input.zoom == "yes"
    limits = zoom ? ((-2.6, 0.6), (-1.6, 1.6)) : nothing
    view = PlotBuilder.ViewDefinition(
        _quantity_axis(:x, "Real axis"),
        _quantity_axis(:y, "Imaginary axis"),
        nothing,
        recipe.renderer.title,
        series,
        (; analysis=:nyquist);
        aspect=:data,
        limits,
    )
    status = string("Assessment: ", first(values).output.assessment)
    return [_stability_page(
        NyquistPlotDefinition,
        recipe,
        recipe.renderer.title,
        [view];
        key=(; analysis=:nyquist),
        status,
    )]
end

PlotBuilder.input_kwargs(::Type{BodePlotDefinition}) =
    (:channels, :legend, :xscale, _ENSEMBLE_INPUTS...)
PlotBuilder.renderer_kwargs(::Type{BodePlotDefinition}) = _STANDARD_RENDERER
function PlotBuilder.input_defaults(::Type{BodePlotDefinition}, result)
    return (; channels=:all, legend=nothing, xscale=:log10, ensemble=20, spread=(0.05, 0.95))
end
function PlotBuilder.renderer_defaults(::Type{BodePlotDefinition}, result)
    return (; title="Bode plot", figure_size=(900, 720))
end

function _selected_channels(selection, rows, columns)
    all_channels = [(row, column) for row in 1:rows for column in 1:columns]
    selection === :all && return all_channels
    selection isa Tuple && length(selection) == 2 &&
        all(item -> item isa Integer, selection) && (selection = [selection])
    selection isa AbstractVector || throw(ArgumentError(
        "channels must be :all, one `(row, column)` tuple, or a vector of tuples",
    ))
    channels = Tuple{Int,Int}[]
    for channel in selection
        channel isa Tuple && length(channel) == 2 || throw(ArgumentError(
            "each Bode channel must be a `(row, column)` tuple",
        ))
        row, column = Int.(channel)
        1 <= row <= rows && 1 <= column <= columns || throw(BoundsError(
            "Bode channel ($row, $column) lies outside the response",
        ))
        push!(channels, (row, column))
    end
    allunique(channels) || throw(ArgumentError("Bode channels must be unique"))
    return channels
end

function PlotBuilder.resolve_input(
    ::Type{BodePlotDefinition},
    recipe::PlotBuilder.PlotRecipe,
)
    resolved = _validate_stability_recipe(recipe, :bode)
    resolved.input.xscale in (:linear, :log10) || throw(ArgumentError(
        "xscale must be :linear or :log10",
    ))
    first_output = first(resolved.input.values).output
    rows, columns = size(first_output.magnitude_db)[1:2]
    channels = _selected_channels(resolved.input.channels, rows, columns)
    legend = resolved.input.legend
    if legend isa AbstractVector
        length(legend) == length(channels) || throw(DimensionMismatch(
            "the Bode legend must contain one label per selected channel",
        ))
    elseif legend isa AbstractString
        length(channels) == 1 || throw(DimensionMismatch(
            "a scalar Bode legend requires one selected channel",
        ))
    elseif legend !== nothing
        throw(ArgumentError("legend must be nothing, a string, or a vector of strings"))
    end
    return PlotBuilder.PlotRecipe(
        resolved.object,
        merge(resolved.input, (; channels)),
        resolved.renderer,
    )
end

function _channel_label(recipe, channel, index)
    legend = recipe.input.legend
    legend === nothing && return "Channel [$(channel[1]), $(channel[2])]"
    legend isa AbstractString && return String(legend)
    return String(legend[index])
end

function _bode_view(recipe, channel, index, field, ylabel, title)
    values = recipe.input.values
    frequencies = first(values).output.frequencies ./ 2pi
    curves = [vec(@view getproperty(value.output, field)[channel[1], channel[2], :])
        for value in values]
    statistics = _curve_statistics(curves, recipe.input.spread)
    group = Symbol("channel_$(channel[1])_$(channel[2])")
    color = _series_color(index)
    series = PlotBuilder.SeriesDefinition[]
    _band!(series, frequencies, statistics, group)
    for trial in _selected_trajectories(curves, recipe.input.ensemble)
        _line!(series, frequencies, curves[trial], nothing, group;
            attributes=(; color, alpha=0.12, linewidth=1))
    end
    _line!(series, frequencies, statistics.center, _channel_label(recipe, channel, index), group;
        attributes=(; color, linewidth=3))
    return PlotBuilder.ViewDefinition(
        _frequency_axis(scale=recipe.input.xscale),
        _quantity_axis(:y, ylabel),
        nothing,
        title,
        series,
        (; field, row=channel[1], column=channel[2]),
    )
end

function PlotBuilder.make_pages(
    ::Type{BodePlotDefinition},
    ::Val,
    ::Val,
    recipe::PlotBuilder.PlotRecipe,
)
    pages = PlotBuilder.PageDefinition[]
    for (index, channel) in enumerate(recipe.input.channels)
        label = _channel_label(recipe, channel, index)
        title = length(recipe.input.channels) == 1 ? recipe.renderer.title :
            string(recipe.renderer.title, ": ", label)
        views = [
            _bode_view(recipe, channel, index, :magnitude_db, "Magnitude [dB]", "Magnitude"),
            _bode_view(recipe, channel, index, :phase_deg, "Phase [deg]", "Phase"),
        ]
        push!(pages, _stability_page(
            BodePlotDefinition,
            recipe,
            title,
            views;
            key=(; analysis=:bode, row=channel[1], column=channel[2]),
        ))
    end
    return pages
end

PlotBuilder.input_kwargs(::Type{PassivityPlotDefinition}) = _ENSEMBLE_INPUTS
PlotBuilder.renderer_kwargs(::Type{PassivityPlotDefinition}) = _STANDARD_RENDERER
PlotBuilder.input_defaults(::Type{PassivityPlotDefinition}, result) =
    (; ensemble=20, spread=(0.05, 0.95))
PlotBuilder.renderer_defaults(::Type{PassivityPlotDefinition}, result) =
    (; title="Passivity assessment", figure_size=(900, 560))
PlotBuilder.resolve_input(
    ::Type{PassivityPlotDefinition},
    recipe::PlotBuilder.PlotRecipe,
) =
    _validate_stability_recipe(recipe, :passivity)

function PlotBuilder.make_pages(
    ::Type{PassivityPlotDefinition},
    ::Val,
    ::Val,
    recipe::PlotBuilder.PlotRecipe,
)
    values = recipe.input.values
    frequencies = first(values).output.frequencies ./ 2pi
    curves = [value.output.index for value in values]
    statistics = _curve_statistics(curves, recipe.input.spread)
    series = PlotBuilder.SeriesDefinition[]
    _band!(series, frequencies, statistics, :passivity)
    for trial in _selected_trajectories(curves, recipe.input.ensemble)
        _line!(series, frequencies, curves[trial], nothing, :passivity;
            attributes=(; color=:blue, alpha=0.12, linewidth=1))
    end
    _line!(series, frequencies, statistics.center, "Passivity index", :passivity;
        attributes=(; color=:blue, linewidth=3))
    push!(series, PlotBuilder.SeriesDefinition(
        :hline, nothing, [0.0], nothing, "Zero";
        group=:zero,
        attributes=(; color=:red, linestyle=:dash),
    ))
    view = PlotBuilder.ViewDefinition(
        _frequency_axis(),
        _quantity_axis(:y, "Passivity index"),
        nothing,
        recipe.renderer.title,
        series,
        (; analysis=:passivity),
    )
    return [_stability_page(
        PassivityPlotDefinition,
        recipe,
        recipe.renderer.title,
        [view];
        key=(; analysis=:passivity),
    )]
end

PlotBuilder.input_kwargs(::Type{SmallGainPlotDefinition}) = _ENSEMBLE_INPUTS
PlotBuilder.renderer_kwargs(::Type{SmallGainPlotDefinition}) = _STANDARD_RENDERER
PlotBuilder.input_defaults(::Type{SmallGainPlotDefinition}, result) =
    (; ensemble=20, spread=(0.05, 0.95))
PlotBuilder.renderer_defaults(::Type{SmallGainPlotDefinition}, result) =
    (; title="Small-gain assessment", figure_size=(900, 560))
PlotBuilder.resolve_input(
    ::Type{SmallGainPlotDefinition},
    recipe::PlotBuilder.PlotRecipe,
) =
    _validate_stability_recipe(recipe, :small_gain)

function PlotBuilder.make_pages(
    ::Type{SmallGainPlotDefinition},
    ::Val,
    ::Val,
    recipe::PlotBuilder.PlotRecipe,
)
    values = recipe.input.values
    frequencies = first(values).output.frequencies ./ 2pi
    definitions = (
        (:product_gain, "max σ(G₁G₂)", :black, identity),
        (:first_gain, "1/max σ(G₁)", :blue, values -> 1 ./ values),
        (:second_gain, "max σ(G₂)", :red, identity),
    )
    series = PlotBuilder.SeriesDefinition[]
    for (field, label, color, transform) in definitions
        curves = [transform(getproperty(value.output, field)) for value in values]
        statistics = _curve_statistics(curves, recipe.input.spread)
        group = field
        field === :product_gain && _band!(series, frequencies, statistics, group; color)
        for trial in _selected_trajectories(curves, recipe.input.ensemble)
            _line!(series, frequencies, curves[trial], nothing, group;
                attributes=(; color, alpha=0.1, linewidth=1))
        end
        _line!(series, frequencies, statistics.center, label, group;
            attributes=(; color, linewidth=3))
    end
    push!(series, PlotBuilder.SeriesDefinition(
        :hline, nothing, [1.0], nothing, "Unity";
        group=:unity,
        attributes=(; color=:green, linestyle=:dash),
    ))
    view = PlotBuilder.ViewDefinition(
        _frequency_axis(),
        _quantity_axis(:y, "Singular values"; scale=:log10, allowed_scales=(:linear, :log10)),
        nothing,
        recipe.renderer.title,
        series,
        (; analysis=:small_gain),
    )
    return [_stability_page(
        SmallGainPlotDefinition,
        recipe,
        recipe.renderer.title,
        [view];
        key=(; analysis=:small_gain),
    )]
end

PlotBuilder.input_kwargs(::Type{EigenvaluePlotDefinition}) =
    (:determinant, :frequency_limits, _ENSEMBLE_INPUTS...)
PlotBuilder.renderer_kwargs(::Type{EigenvaluePlotDefinition}) = _STANDARD_RENDERER
function PlotBuilder.input_defaults(::Type{EigenvaluePlotDefinition}, result)
    values = _stability_values(result)
    output = first(values).output
    return (;
        determinant=output.determinant_index !== nothing,
        frequency_limits=(output.fmin, output.fmax),
        ensemble=20,
        spread=(0.05, 0.95),
    )
end
PlotBuilder.renderer_defaults(::Type{EigenvaluePlotDefinition}, result) =
    (; title="Eigenvalue analysis", figure_size=(1000, 900))
function PlotBuilder.resolve_input(
    ::Type{EigenvaluePlotDefinition},
    recipe::PlotBuilder.PlotRecipe,
)
    resolved = _validate_stability_recipe(recipe, :eigenvalue)
    resolved.input.determinant isa Bool || throw(ArgumentError("determinant must be Bool"))
    limits = resolved.input.frequency_limits
    limits isa Tuple && length(limits) == 2 && all(value -> value isa Real, limits) &&
        0 < first(limits) < last(limits) || throw(ArgumentError(
        "frequency_limits must satisfy 0 < lower < upper",
    ))
    return resolved
end

function _eigenvalue_view(recipe, matched, field, ylabel, title)
    frequencies = first(recipe.input.values).output.frequencies ./ 2pi
    order = size(first(matched), 2)
    series = PlotBuilder.SeriesDefinition[]
    for mode in 1:order
        raw = [value[:, mode] for value in matched]
        curves = field === :magnitude ?
            [20 .* log10.(max.(abs.(value), eps(Float64))) for value in raw] :
            field === :real ? real.(raw) : imag.(raw)
        statistics = _curve_statistics(curves, recipe.input.spread)
        group = Symbol("mode_$mode")
        color = _series_color(mode)
        _band!(series, frequencies, statistics, group; color)
        for trial in _selected_trajectories(curves, recipe.input.ensemble)
            _line!(series, frequencies, curves[trial], nothing, group;
                attributes=(; color, alpha=0.1, linewidth=1))
        end
        _line!(series, frequencies, statistics.center, "Mode $mode", group;
            attributes=(; color, linewidth=3))
    end
    return PlotBuilder.ViewDefinition(
        _frequency_axis(),
        _quantity_axis(:y, ylabel),
        nothing,
        title,
        series,
        (; field);
        limits=(recipe.input.frequency_limits, (-1.0, 1.0)),
    )
end

function _finite_view_limits(view)
    values = Float64[]
    for series in view.series
        series.kind in (:line, :band) || continue
        series.ydata === nothing || append!(values, filter(isfinite, Float64.(series.ydata)))
        series.kind === :band && append!(values, filter(isfinite, Float64.(series.zdata)))
    end
    isempty(values) && return view
    lower, upper = extrema(values)
    lower == upper && ((lower, upper) = (lower - 1, upper + 1))
    padding = 0.05 * (upper - lower)
    return PlotBuilder.ViewDefinition(
        view.xaxis, view.yaxis, view.zaxis, view.title, view.series, view.key;
        placement=view.placement,
        aspect=view.aspect,
        limits=(view.limits[1], (lower - padding, upper + padding)),
        attributes=view.attributes,
    )
end

function PlotBuilder.make_pages(
    ::Type{EigenvaluePlotDefinition},
    ::Val,
    ::Val,
    recipe::PlotBuilder.PlotRecipe,
)
    values = recipe.input.values
    reference = first(values).output.eigenvalues
    matched = Matrix{ComplexF64}[]
    for value in values
        eigenvalues, _ = _match_loci(value.output.eigenvalues, reference)
        push!(matched, eigenvalues)
    end
    views = [
        _finite_view_limits(_eigenvalue_view(recipe, matched, :magnitude, "|λ| [dB]", "Magnitude")),
        _finite_view_limits(_eigenvalue_view(recipe, matched, :real, "Re(λ)", "Real part")),
        _finite_view_limits(_eigenvalue_view(recipe, matched, :imaginary, "Im(λ)", "Imaginary part")),
    ]
    pages = [_stability_page(
        EigenvaluePlotDefinition,
        recipe,
        recipe.renderer.title,
        views;
        key=(; analysis=:eigenvalue),
    )]
    if recipe.input.determinant
        all(value -> value.output.determinant_index !== nothing, values) || throw(ArgumentError(
            "determinant data was not calculated; recompute with determinant=true",
        ))
        frequencies = first(values).output.frequencies ./ 2pi
        curves = [value.output.determinant_index for value in values]
        statistics = _curve_statistics(curves, recipe.input.spread)
        series = PlotBuilder.SeriesDefinition[]
        _band!(series, frequencies, statistics, :determinant)
        _line!(series, frequencies, statistics.center, "|det(Z)⁻¹|", :determinant;
            attributes=(; color=:blue, linewidth=3))
        view = PlotBuilder.ViewDefinition(
            _frequency_axis(),
            _quantity_axis(:y, "Inverse determinant"; scale=:log10,
                allowed_scales=(:linear, :log10)),
            nothing,
            "Inverse determinant",
            series,
            (; field=:determinant);
            limits=(recipe.input.frequency_limits, extrema(statistics.center)),
        )
        push!(pages, _stability_page(
            EigenvaluePlotDefinition,
            recipe,
            string(recipe.renderer.title, ": determinant"),
            [view];
            key=(; analysis=:eigenvalue, page=:determinant),
        ))
    end
    return pages
end

PlotBuilder.input_kwargs(::Type{UnstableFrequencyPlotDefinition}) = _ENSEMBLE_INPUTS
PlotBuilder.renderer_kwargs(::Type{UnstableFrequencyPlotDefinition}) = _STANDARD_RENDERER
PlotBuilder.input_defaults(::Type{UnstableFrequencyPlotDefinition}, result) =
    (; ensemble=20, spread=(0.05, 0.95))
PlotBuilder.renderer_defaults(::Type{UnstableFrequencyPlotDefinition}, result) =
    (; title="Unstable-frequency analysis", figure_size=(900, 760))
PlotBuilder.resolve_input(
    ::Type{UnstableFrequencyPlotDefinition},
    recipe::PlotBuilder.PlotRecipe,
) =
    _validate_stability_recipe(recipe, :unstable_frequency)

function _unstable_view(recipe, field, ylabel, title)
    values = recipe.input.values
    frequencies = first(values).output.frequencies ./ 2pi
    mode_count = length(first(values).output.magnitude_db)
    series = PlotBuilder.SeriesDefinition[]
    for mode in 1:mode_count
        curves = [getproperty(value.output, field)[mode] for value in values]
        statistics = _curve_statistics(curves, recipe.input.spread)
        group = Symbol("mode_$mode")
        color = _series_color(mode)
        _band!(series, frequencies, statistics, group; color)
        for trial in _selected_trajectories(curves, recipe.input.ensemble)
            _line!(series, frequencies, curves[trial], nothing, group;
                attributes=(; color, alpha=0.1, linewidth=1))
        end
        _line!(series, frequencies, statistics.center, "Mode $mode", group;
            attributes=(; color, linewidth=3))
    end
    detected = reduce(vcat, [value.output.detected_frequencies for value in values]; init=Float64[])
    isempty(detected) || push!(series, PlotBuilder.SeriesDefinition(
        :vline,
        [Statistics.median(detected)],
        nothing,
        nothing,
        "Median detected frequency";
        group=:detected,
        attributes=(; color=:red, linestyle=:dash),
    ))
    return PlotBuilder.ViewDefinition(
        _frequency_axis(),
        _quantity_axis(:y, ylabel),
        nothing,
        title,
        series,
        (; field),
    )
end

function _detection_probability_view(recipe)
    values = recipe.input.values
    frequencies = first(values).output.frequencies ./ 2pi
    probability = zeros(Float64, length(frequencies))
    for value in values
        detected = unique(reduce(vcat, value.output.detected_indices; init=Int[]))
        probability[detected] .+= 1
    end
    probability ./= length(values)
    series = [PlotBuilder.SeriesDefinition(
        :line,
        frequencies,
        probability,
        nothing,
        "Detection probability";
        group=:probability,
        attributes=(; color=:purple, linewidth=3),
    )]
    return PlotBuilder.ViewDefinition(
        _frequency_axis(),
        _quantity_axis(:y, "Detection probability"),
        nothing,
        "Detection probability",
        series,
        (; field=:probability);
        limits=(extrema(frequencies), (0.0, 1.0)),
    )
end

function PlotBuilder.make_pages(
    ::Type{UnstableFrequencyPlotDefinition},
    ::Val,
    ::Val,
    recipe::PlotBuilder.PlotRecipe,
)
    views = [
        _unstable_view(recipe, :magnitude_db, "Magnitude [dB]", "Complementary sensitivity"),
        _unstable_view(recipe, :phase_deg, "Phase [deg]", "Phase"),
    ]
    length(recipe.input.values) > 1 && push!(views, _detection_probability_view(recipe))
    return [_stability_page(
        UnstableFrequencyPlotDefinition,
        recipe,
        recipe.renderer.title,
        views;
        key=(; analysis=:unstable_frequency),
    )]
end
