using CairoMakie
using CSV
using DataFrames
using Downloads
using GeoMakie

const PACKAGE_UUID = "8bb8d9d3-c57e-5130-a7c9-cb214ef560ae"
const LOG_URL = "https://julialang-logs.s3.amazonaws.com/public_outputs/current/package_requests_by_region.csv.gz"
const DEFAULT_OUTPUT = joinpath(@__DIR__, "src", "assets", "user-statistics.svg")

# Julia package-server regions are operational regions, not user countries.
const REGION_LOCATION = Dict(
    "us-east" => (
        label = "US East",
        longitude = -77.0,
        latitude = 38.0,
        offset = (12, 14),
        align = (:left, :bottom),
    ),
    "us-west" => (
        label = "US West",
        longitude = -122.0,
        latitude = 38.0,
        offset = (-12, 14),
        align = (:right, :bottom),
    ),
    "eu-central" => (
        label = "EU Central",
        longitude = 10.0,
        latitude = 50.0,
        offset = (0, 18),
        align = (:center, :bottom),
    ),
    "eu-north" => (
        label = "EU North",
        longitude = 18.0,
        latitude = 60.0,
        offset = (0, 18),
        align = (:center, :bottom),
    ),
    "au" => (
        label = "Australia",
        longitude = 151.0,
        latitude = -33.0,
        offset = (0, 18),
        align = (:center, :bottom),
    ),
    "jp" => (
        label = "Japan",
        longitude = 139.7,
        latitude = 35.7,
        offset = (12, 14),
        align = (:left, :bottom),
    ),
    "in" => (
        label = "India",
        longitude = 77.2,
        latitude = 28.6,
        offset = (0, 18),
        align = (:center, :bottom),
    ),
    "kr" => (
        label = "Korea",
        longitude = 127.0,
        latitude = 37.5,
        offset = (-12, 14),
        align = (:right, :bottom),
    ),
    "sa" => (
        label = "South America",
        longitude = -46.6,
        latitude = -23.5,
        offset = (0, 18),
        align = (:center, :bottom),
    ),
    "sg" => (
        label = "Singapore",
        longitude = 103.8,
        latitude = 1.3,
        offset = (0, -18),
        align = (:center, :top),
    ),
    "cn-east" => (
        label = "China East",
        longitude = 121.5,
        latitude = 31.2,
        offset = (-12, 14),
        align = (:right, :bottom),
    ),
    "cn-northeast" => (
        label = "China Northeast",
        longitude = 123.4,
        latitude = 41.8,
        offset = (12, 14),
        align = (:left, :bottom),
    ),
    "cn-southeast" => (
        label = "China Southeast",
        longitude = 113.3,
        latitude = 23.1,
        offset = (0, -18),
        align = (:center, :top),
    ),
)

function package_regions(path::AbstractString)
    frame = CSV.read(path, DataFrame)
    selected = filter(frame) do row
        row.package_uuid == PACKAGE_UUID &&
            !ismissing(row.client_type) &&
            row.client_type == "user" &&
            !ismissing(row.region) &&
            haskey(REGION_LOCATION, String(row.region))
    end
    if isempty(selected)
        return (
            DataFrame(region = String[], request_addrs = Float64[]),
            (minimum = nothing, maximum = nothing),
        )
    end
    grouped = combine(
        groupby(selected, :region),
        :request_addrs => (values -> sum(skipmissing(values))) => :request_addrs,
    )
    sort!(grouped, :request_addrs; rev = true)
    dates = (
        minimum = minimum(skipmissing(selected.date_min)),
        maximum = maximum(skipmissing(selected.date_max)),
    )
    return first(grouped, min(10, nrow(grouped))), dates
end

function draw_statistics(rows, dates, output::AbstractString)
    figure = Figure(
        size = (1050, 460),
        figure_padding = 8,
        backgroundcolor = RGBf(0.95, 0.97, 0.99),
    )
    axis = GeoAxis(
        figure[2, 1];
        dest = "+proj=eqearth",
        width = 1000,
        height = 360,
        xticklabelsvisible = false,
        yticklabelsvisible = false,
        xgridvisible = false,
        ygridvisible = false,
    )
    axis.scene.backgroundcolor[] = RGBf(0.68, 0.86, 0.97)
    poly!(
        axis,
        GeoMakie.land();
        color = RGBf(0.96, 0.96, 0.93),
        strokecolor = RGBf(0.68, 0.72, 0.73),
        strokewidth = 0.5,
    )
    xlims!(axis, -180, 180)
    ylims!(axis, -60, 88)

    if isempty(rows)
        text!(
            axis,
            0,
            5;
            text = "No public package-server usage recorded yet",
            align = (:center, :center),
            fontsize = 24,
            color = RGBf(0.12, 0.18, 0.24),
        )
        period = "awaiting the first registered-package requests"
    else
        maximum_count = maximum(rows.request_addrs)
        for row in eachrow(rows)
            location = REGION_LOCATION[String(row.region)]
            size = 14 + 32sqrt(row.request_addrs / maximum_count)
            scatter!(
                axis,
                [location.longitude],
                [location.latitude];
                markersize = size,
                color = RGBAf(0.05, 0.29, 0.53, 0.78),
                strokecolor = :white,
                strokewidth = 1.5,
            )
            text!(
                axis,
                location.longitude,
                location.latitude;
                text = "$(location.label) · $(round(Int, row.request_addrs))",
                offset = location.offset,
                align = location.align,
                fontsize = 13,
                color = RGBf(0.05, 0.10, 0.15),
            )
        end
        period = "$(dates.minimum) to $(dates.maximum)"
    end

    Label(
        figure[1, 1],
        "PowerImpedance.jl package clients";
        fontsize = 25,
        font = :bold,
        color = RGBf(0.05, 0.10, 0.15),
    )
    Label(
        figure[3, 1],
        "Top Julia package-server regions · summed request addresses · $period";
        fontsize = 13,
        color = RGBf(0.22, 0.28, 0.34),
    )
    rowgap!(figure.layout, 3)
    mkpath(dirname(output))
    save(output, figure)
    return output
end

function main(args = ARGS)
    source = isempty(args) ? Downloads.download(LOG_URL) : abspath(args[1])
    output = length(args) < 2 ? DEFAULT_OUTPUT : abspath(args[2])
    rows, dates = package_regions(source)
    result = draw_statistics(rows, dates, output)
    @info "Generated package-server usage map" result regions = nrow(rows)
    return result
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
