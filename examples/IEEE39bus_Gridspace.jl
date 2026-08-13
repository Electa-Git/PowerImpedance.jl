# # IEEE39 Gridspace soil-resistivity study
#
# This example reuses the NetworkBuilder model exercised by the IEEE39 parity
# tests and applies one shared soil-resistivity grid to every overhead line and
# cable. Driving-point harmonic impedances at three representative buses are
# overlaid for direct comparison.

using Plots
using PowerImpedanceACDC
using PowerImpedanceACDC.NetworkBuilder: BuilderState, Grid, Gridspace, define, solve

# The parity fixture is the authoritative NetworkBuilder version of this
# system. Skip its top-level testsets while retaining its model functions and
# constants. This keeps the example synchronized with the parity test rather
# than maintaining a second thousand-line copy of the system.
function include_ieee39_networkbuilder_fixture()
    isdefined(@__MODULE__, :ieee39bus_elements) && return nothing

    skip_testsets(expression) =
        if expression isa Expr &&
           expression.head === :macrocall &&
           expression.args[1] === Symbol("@testset")
            :(nothing)
        else
            expression
        end

    path = joinpath(pkgdir(PowerImpedanceACDC), "test", "NetworkBuilder_test.jl")
    Base.include(skip_testsets, @__MODULE__, path)
    return nothing
end;

include_ieee39_networkbuilder_fixture();

# The requested input repeats 1000 Ωm. Duplicate values produce identical
# solves and curves, so the grid retains its three unique physical cases.
const IEEE39_REQUESTED_SOIL_RESISTIVITY = (10.0, 100.0, 1000.0, 1000.0)
const IEEE39_SOIL_RESISTIVITY = Tuple(unique(IEEE39_REQUESTED_SOIL_RESISTIVITY))
const IEEE39_REPRESENTATIVE_BUSES = (9, 16, 29)

const IEEE39_BUILDER_OPTIONS = (;
    voltageBase = Vm1,
    power_flow = (; is_bounded = (; bus_voltage = true))
);

# ## Apply one resistivity value everywhere

function element_at_soil_resistivity(element, soil_resistivity)
    model = element.element_model

    if model isa PowerImpedanceACDC.Overhead_line
        return overhead_line(
            length = model.length,
            conductors = deepcopy(model.conductors),
            groundwires = deepcopy(model.groundwires),
            earth_parameters = (
                model.earth_parameters[1],
                model.earth_parameters[2],
                soil_resistivity
            ),
            transformation = element.transformation,
            connection = element.connection
        )
    elseif model isa PowerImpedanceACDC.Cable
        conductors = NamedTuple{Tuple(keys(model.conductors))}(
            Tuple(deepcopy(value) for value in values(model.conductors)),
        )
        insulators = NamedTuple{Tuple(keys(model.insulators))}(
            Tuple(deepcopy(value) for value in values(model.insulators)),
        )
        return cable(;
            length = model.length,
            positions = deepcopy(model.positions),
            earth_parameters = (
                model.earth_parameters[1],
                model.earth_parameters[2],
                soil_resistivity
            ),
            configuration = model.configuration,
            type = model.type,
            eliminate = model.eliminate,
            transformation = element.transformation,
            connection = element.connection,
            conductors...,
            insulators...
        )
    end

    return deepcopy(element)
end;

function ieee39_elements_at_soil_resistivity(base_elements, soil_resistivity)
    names = keys(base_elements)
    elements = map(values(base_elements)) do element
        element_at_soil_resistivity(element, soil_resistivity)
    end
    return NamedTuple{names}(Tuple(elements))
end;

# One `Grid` axis changes all line models together. The resulting coordinates
# identify each case as `soil_resistivity = 10`, `100`, or `1000` Ωm.
function ieee39_soil_builder_space(
        soil_resistivities = IEEE39_SOIL_RESISTIVITY;
        base_elements = ieee39bus_elements(),
        cached_powerflow = nothing
)
    connections = ieee39bus_connections()
    function materialize(soil_resistivity)
        builder = define(
            ieee39_elements_at_soil_resistivity(base_elements, soil_resistivity),
            connections;
            options = IEEE39_BUILDER_OPTIONS
        )
        builder.powerflow = cached_powerflow
        return builder
    end

    return Gridspace{BuilderState}(
        materialize,
        (Grid(soil_resistivities),),
        (:soil_resistivity,)
    )
end;

function ieee39_reference_powerflow(base_elements = ieee39bus_elements())
    builder = define(
        deepcopy(base_elements),
        ieee39bus_connections();
        options = IEEE39_BUILDER_OPTIONS
    )
    return solve(builder).powerflow
end;

# Soil resistivity changes only passive frequency-domain models. The topology,
# converter parameters, and operating point are unchanged, so all cases reuse
# this single cached power flow and its active-device linearizations.

function ieee39_bus_nets(buses)
    return reduce(vcat, ([Symbol("Bus$(bus)d"), Symbol("Bus$(bus)q")] for bus in buses))
end;

function run_ieee39_soil_study(;
        soil_resistivities = IEEE39_SOIL_RESISTIVITY,
        buses = IEEE39_REPRESENTATIVE_BUSES,
        freq_range = (1.0, 5e3, 400)
)
    base_elements = ieee39bus_elements()
    cached_powerflow = ieee39_reference_powerflow(base_elements)
    result = determine_impedance(
        ieee39_soil_builder_space(
            soil_resistivities;
            base_elements,
            cached_powerflow
        );
        nets = ieee39_bus_nets(buses),
        elim_elements = IEEE39_ELIM_ELEMENTS,
        freq_range
    )
    return (;
        soil_resistivities = collect(soil_resistivities), buses = collect(buses), result)
end;

# ## Overlay the harmonic impedances
#
# The d-axis diagonal entry is used as the driving-point impedance at each bus.
# `maximum_spread_db` quantifies whether soil resistivity visibly separates the
# curves and makes the sensitivity check reproducible. A reduced validation
# scan gave maximum separations of about 0.97 dB at Bus 9, 0.82 dB at Bus 16,
# and 1.08 dB at Bus 29, so soil resistivity remains a visible KPI and no
# fallback parameter scan is needed.

function ieee39_impedance_db(case, bus_index)
    net_index = 2bus_index - 1
    return 20 .* log10.(abs.(vec(case.impedance[net_index, net_index, :])))
end;

function maximum_spread_db(study, bus_index)
    curves = hcat((ieee39_impedance_db(case, bus_index) for case in study.result)...)
    return maximum(maximum(curves; dims = 2) .- minimum(curves; dims = 2))
end;

function plot_ieee39_soil_study(study)
    panels = map(eachindex(study.buses)) do bus_index
        panel = plot(
            xscale = :log10,
            xlabel = "Frequency [Hz]",
            ylabel = "|Zdd| [dBΩ]",
            title = "Bus $(study.buses[bus_index])",
            framestyle = :box,
            minorgrid = true,
            legend = :outerright
        )

        for (case, soil_resistivity) in zip(study.result, study.soil_resistivities)
            frequency = real.(case.frequencies) ./ (2π)
            plot!(
                panel,
                frequency,
                ieee39_impedance_db(case, bus_index);
                label = "ρsoil = $(soil_resistivity) Ωm",
                linewidth = 2
            )
        end

        spread = maximum_spread_db(study, bus_index)
        x_min, x_max = xlims(panel)
        y_min, y_max = ylims(panel)
        annotation_x = 10^(log10(x_min) + 0.03 * log10(x_max / x_min))
        annotation_y = y_max - 0.06 * (y_max - y_min)
        annotate!(panel, annotation_x, annotation_y,
            text("max spread = $(round(spread; digits = 2)) dB", 8, :left))
        return panel
    end

    return plot(
        panels...;
        layout = (length(panels), 1),
        size = (1150, 1050),
        plot_title = "IEEE39 harmonic impedance versus common soil resistivity"
    )
end;

# The documentation evaluates the same three physical cases with a reduced
# frequency grid. Running this source file directly uses the full defaults.
#md ieee39_docs_study = run_ieee39_soil_study(; freq_range = (1.0, 5e3, 160))
#md plot_ieee39_soil_study(ieee39_docs_study)

if abspath(PROGRAM_FILE) == @__FILE__ #src
    study = run_ieee39_soil_study() #src
    display(plot_ieee39_soil_study(study)) #src
    println( #src
        "Maximum soil-resistivity spreads [dB]: ", #src
        Dict(bus => maximum_spread_db(study, index) for (index, bus) in pairs(study.buses)) #src
    ) #src
end #src
