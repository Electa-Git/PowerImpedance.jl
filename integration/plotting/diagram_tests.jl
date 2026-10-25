@testset "GraphMakie diagram projection and Cairo rendering" begin
    @test DiagramExtension !== nothing

    network = diagram_hybrid_network()
    topology_model = DiagramExtension.project_diagram(network)
    enriched = diagram_powerflow_fixture(network)
    data_before = deepcopy(enriched.data)
    result_before = deepcopy(enriched.result)
    model = DiagramExtension.project_diagram(network, enriched)

    ac_one = DiagramExtension.BusKey(1, 1)
    dc_one = DiagramExtension.BusKey(2, 1)
    @test ac_one != dc_one
    @test model.key_to_vertex[ac_one] != model.key_to_vertex[dc_one]
    @test length(model.buses) == 4
    @test enriched.nodes2bus == Dict(
        :ac_1_d => (:ac, 1), :ac_1_q => (:ac, 1),
        :ac_2_d => (:ac, 2), :ac_2_q => (:ac, 2),
        :dc_1 => (:dc, 1), :dc_2 => (:dc, 2),
        :gnd_dc => (:ground, 0), :gnd_ac_d => (:ground, 0),
        :gnd_ac_q => (:ground, 0)
    )
    @test Set(only(bus.nodes for bus in model.buses if bus.key == ac_one)) ==
          Set((:ac_1_d, :ac_1_q))

    ac_line = DiagramExtension.ComponentKey(:ac_line)
    ac_parallel = DiagramExtension.ComponentKey(:ac_parallel)
    @test model.key_to_vertex[ac_line] != model.key_to_vertex[ac_parallel]
    @test count(incidence -> incidence.component == ac_line, model.incidences) == 2
    @test count(incidence -> incidence.component == ac_parallel, model.incidences) == 2

    converter = only(component
    for component in model.components
    if component.key.element == :converter)
    @test converter.role == :converter
    @test converter.model_type === typeof(network.elements.converter)
    @test converter.terminal_rows == Tuple(
        row for row in network.topology.connections if row.component == :converter
    )
    @test Set(connection.port for connection in converter.connected_buses) ==
          Set((:ac, :dc))
    @test Set(incidence.port for incidence in model.incidences
    if incidence.component == converter.key) == Set((:ac, :dc))
    @test Set(connection.bus.domain for connection in converter.connected_buses) ==
          Set((1, 2))

    @test all(bus -> bus.key.bus > 0, model.buses)
    dc_load = only(component
    for component in topology_model.components
    if component.key.element == :dc_load)
    @test dc_load.grounded_ports == (:side2,)
    @test dc_load.role == :shunt

    roles = Dict(component.key.element => component.role
    for component in topology_model.components)
    @test roles[:ac_grid] == :source
    @test roles[:machine] == :machine
    @test roles[:dc_load] == :shunt
    @test roles[:ac_shunt] == :shunt
    for element in (:ac_grid, :machine, :dc_load, :ac_shunt)
        @test haskey(
            topology_model.key_to_vertex,
            DiagramExtension.ComponentKey(element)
        )
    end
    @test Dict(component.key.element => component.role
    for component in model.components)[:ac_shunt] == :load

    repeated = DiagramExtension.project_diagram(network, enriched)
    @test repeated.vertex_keys == model.vertex_keys
    @test repeated.incidences == model.incidences
    @test repeated.key_to_vertex == model.key_to_vertex

    mapped_line = only(component
    for component in model.components
    if component.key.element == :ac_line)
    @test mapped_line.input === enriched.data["branch"]["1"]
    @test mapped_line.solution === enriched.result["solution"]["branch"]["1"]
    @test enriched.data == data_before
    @test enriched.result == result_before

    linear_result = PowerFlowResult(
        PowerImpedance.NetworkBuilder.ACDCPowerFlow(),
        nothing,
        nothing,
        diagram_nodes2bus(network),
        Dict{Symbol, Any}(),
        OperatingPoint(),
        (termination_status = :not_required,)
    )
    linear_model = DiagramExtension.project_diagram(network, linear_result)
    @test all(component -> component.input === nothing, linear_model.components)
    @test linear_model.powerflow_diagnostics.termination_status == :not_required
    @test diagram(network, linear_result; interactive = false).figure isa Makie.Figure

    mismatched_nodes = copy(enriched.nodes2bus)
    mismatched_nodes[:ac_1_d] = (:ac, 99)
    mismatched = PowerFlowResult(
        enriched.formulation,
        enriched.result,
        enriched.data,
        mismatched_nodes,
        enriched.elem2comp,
        enriched.operating_point,
        enriched.diagnostics
    )
    mismatch_error = try
        DiagramExtension.project_diagram(network, mismatched)
        nothing
    catch caught
        caught
    end
    @test mismatch_error isa ArgumentError
    @test occursin("does not belong", sprint(showerror, mismatch_error))

    missing_data = deepcopy(enriched.data)
    delete!(missing_data["branch"], "1")
    missing_result = PowerFlowResult(
        enriched.formulation,
        enriched.result,
        missing_data,
        enriched.nodes2bus,
        enriched.elem2comp,
        enriched.operating_point,
        enriched.diagnostics
    )
    missing_error = try
        DiagramExtension.project_diagram(network, missing_result)
        nothing
    catch caught
        caught
    end
    @test missing_error isa ArgumentError
    @test occursin(":ac_line", sprint(showerror, missing_error))
    @test occursin("branch[1]", sprint(showerror, missing_error))

    invalid_mapping = Dict{Symbol, Any}(pairs(enriched.elem2comp))
    invalid_mapping[:ac_line] = Dict("pmtype" => "branch")
    invalid_result = PowerFlowResult(
        enriched.formulation,
        enriched.result,
        enriched.data,
        enriched.nodes2bus,
        invalid_mapping,
        enriched.operating_point,
        enriched.diagnostics
    )
    invalid_error = try
        DiagramExtension.project_diagram(network, invalid_result)
        nothing
    catch caught
        caught
    end
    @test invalid_error isa ArgumentError
    @test occursin(":ac_line", sprint(showerror, invalid_error))

    view = diagram(network, enriched; interactive = false)
    @test view.figure isa Makie.Figure
    @test view.axis isa Makie.Axis
    @test view.plots.legend isa Makie.Legend
    @test diagram_legend_labels(view) == [
        "AC bus", "DC bus", "AC branch", "DC branch", "Converter", "Source",
        "Machine", "Load", "Out of service"
    ]
    axis_cell = view.axis.layoutobservables.gridcontent[]
    legend_cell = view.plots.legend.layoutobservables.gridcontent[]
    @test legend_cell.parent === axis_cell.parent
    @test legend_cell.span.rows == axis_cell.span.rows
    legend_column = last(axis_cell.span.cols) + 1
    @test legend_cell.span.cols == legend_column:legend_column
    @test view.plots.legend.scene in DiagramExtension._diagram_plots(view)
    @test size(view.figure.scene, 1) > DiagramExtension._DEFAULT_STYLE.figure_size[1]
    @test size(view.figure.scene, 2) >= DiagramExtension._DEFAULT_STYLE.figure_size[2]
    Makie.update_state_before_display!(view.figure)
    axis_box = view.axis.layoutobservables.computedbbox[]
    legend_box = view.plots.legend.layoutobservables.computedbbox[]
    @test axis_box.origin[1] + axis_box.widths[1] < legend_box.origin[1]
    entries = last(only(view.plots.legend.entrygroups[]))
    @test length(entries[1].elements) == 1
    @test length(entries[2].elements) == 2
    @test all(element -> element isa Makie.LineElement, entries[2].elements)
    for (label, element_name) in (
        ("Converter", :converter), ("Source", :ac_grid), ("Machine", :machine),
        ("Load", :ac_shunt), ("Out of service", :ac_parallel)
    )
        entry = only(entry for entry in entries if entry.label[] == label)
        element = only(entry.elements)
        index = findfirst(item -> item.key.element == element_name, view.model.components)
        glyph = view.plots.components[index]
        @test element isa Makie.MarkerElement
        @test Makie.to_spritemarker(element.marker[]) == glyph.marker[]
        @test Makie.Vec2f(element.markersize[]) == glyph.markersize[]
        @test Makie.to_color(element.markercolor[]) == glyph.color[]
        @test Makie.to_color(element.markerstrokecolor[]) == glyph.strokecolor[]
        @test element.markerstrokewidth[] == glyph.strokewidth[]
    end
    @test length(view.plots.buses) == length(view.model.buses)
    @test length(view.plots.components) == length(view.model.components)
    @test Graphs.nv(view.model.graph) ==
          length(view.model.buses) + length(view.model.components)
    @test length(view.positions) == Graphs.nv(view.model.graph)
    @test only(component
    for component in view.model.components
    if component.key.element == :ac_parallel).active === false
    repeated_view = diagram(network, enriched; interactive = false)
    @test repeated_view.positions == view.positions

    original_positions = copy(view.positions)
    original_graph = view.model.graph
    original_graph_plot = view.plots.graph
    DiagramExtension.select!(view, ac_one)
    @test view.selected[] == ac_one
    @test view.details[].kind == :bus
    @test view.details[].nodes == (:ac_1_d, :ac_1_q)
    @test length(view.highlight[]) == 1
    DiagramExtension.select!(view, DiagramExtension.ComponentKey(:converter))
    @test view.selected[] == DiagramExtension.ComponentKey(:converter)
    @test view.details[].kind == :component
    @test view.details[].role == :converter
    @test view.details[].grounded_ports == converter.grounded_ports
    @test view.details[].operating_point ===
          get(enriched.operating_point, :converter, nothing)
    @test view.positions == original_positions
    @test view.model.graph === original_graph
    @test view.plots.graph === original_graph_plot
    @test enriched.data == data_before
    @test enriched.result == result_before

    explicit = Dict{Any, Any}()
    for (index, key) in enumerate(view.model.vertex_keys)
        external_key = key isa DiagramExtension.BusKey ? (key.domain, key.bus) : key.element
        explicit[external_key] = (index, isodd(index) ? 0.0 : 1.0)
    end
    explicit_before = deepcopy(explicit)
    explicit_view = diagram(
        network;
        positions = explicit,
        interactive = false
    )
    @test explicit == explicit_before
    @test length(explicit_view.positions) == length(explicit)
    incomplete = copy(explicit)
    delete!(incomplete, first(keys(incomplete)))
    @test_throws ArgumentError diagram(
        network;
        positions = incomplete,
        interactive = false
    )

    output = joinpath(mktempdir(), "network-diagram.svg")
    Makie.save(output, view.figure)
    @test isfile(output)
    @test filesize(output) > 100
end

struct DiagramUnknownModel <: PowerImpedance.AbstractLinFreqDomain end

function PowerImpedance.electricalconnections(::DiagramUnknownModel)
    return (side1 = Port(DC_CM), side2 = Port(DC_CM))
end

@testset "GraphMakie diagram generic component fallback" begin
    unknown = DiagramUnknownModel()
    network = PowerImpedance.NetworkBuilder.define(
        (; unknown),
        (
            PowerImpedance.NetworkBuilder.Bus(:unknown_left;
                ports = ((:unknown, :side1),)),
            PowerImpedance.NetworkBuilder.Bus(:unknown_right;
                ports = ((:unknown, :side2),))
        )
    )
    model = DiagramExtension.project_diagram(network)
    @test only(model.components).role == :generic
    @test haskey(model.key_to_vertex, DiagramExtension.ComponentKey(:unknown))
    view = diagram(network; interactive = false)
    @test diagram_legend_labels(view) == ["DC bus", "Other component"]
end

@testset "GraphMakie diagram transformer and omission roles" begin
    elements = (
        source = ac_source(),
        transformer = transformer(
            conductors = 3,
            n = 1.0,
            Rₚ = 0.1,
            Lₚ = 1.0e-3,
            Rₛ = 0.1,
            Lₛ = 1.0e-3
        )
    )
    connections = (
        PowerImpedance.NetworkBuilder.Bus(:primary_; ports = (
            (:source, :ac), (:transformer, :side1)
        ), domain = ACDQ),
        PowerImpedance.NetworkBuilder.Bus(:secondary_;
            ports = ((:transformer, :side2),), domain = ACDQ)
    )
    network = PowerImpedance.NetworkBuilder.define(elements, connections)
    isolated = PowerImpedance.NetworkBuilder.define(
        (; isolated = impedance(z = 2.0, conductors = 1)),
        (PowerImpedance.NetworkBuilder.Bus(:isolated; ports = ((:isolated, :side1),)),)
    ).elements.isolated
    disconnected = PowerImpedance.NetworkBuilder.NetworkState(
        merge(network.elements, (; isolated)),
        network.topology,
        network.options,
        network.powerflow_start
    )
    view = diagram(network; interactive = false)
    @test diagram_legend_labels(view) == ["AC bus", "Transformer", "Source"]
    model = DiagramExtension.project_diagram(disconnected)
    @test only(component.role
    for component in model.components
    if component.key.element == :transformer) == :transformer
    @test any(
        diagnostic -> diagnostic.kind == :disconnected &&
                      diagnostic.entity == DiagramExtension.ComponentKey(:isolated),
        model.diagnostics)
end

@testset "GraphMakie diagram passive and empty legends" begin
    network = PowerImpedance.NetworkBuilder.define(
        (; branch = impedance(z = 2.0, conductors = 1),
            shunt = impedance(z = 10.0, conductors = 1)),
        (
            PowerImpedance.NetworkBuilder.Bus(:left; ports = ((:branch, :side1),)),
            PowerImpedance.NetworkBuilder.Bus(:right; ports = (
                (:branch, :side2), (:shunt, :side1)
            )),
            PowerImpedance.NetworkBuilder.Bus(:gnd; ports = ((:shunt, :side2),))
        )
    )
    view = diagram(network; interactive = false, style = (; dc_bus_color = :red))
    @test diagram_legend_labels(view) == ["DC bus", "DC branch", "Shunt"]
    entries = last(only(view.plots.legend.entrygroups[]))
    @test all(element -> element.linecolor[] == :red, first(entries).elements)
    @test only(entries[2].elements).linecolor[] == :red

    hybrid = diagram_hybrid_network()
    active_view = diagram(hybrid; interactive = false)
    @test diagram_legend_labels(active_view) == [
        "AC bus", "DC bus", "AC branch", "DC branch", "Converter", "Source",
        "Machine", "Shunt"
    ]
    inactive = diagram_powerflow_fixture(hybrid)
    inactive.data["convdc"]["1"]["status"] = 0
    inactive_view = diagram(hybrid, inactive; interactive = false)
    @test "Converter" ∉ diagram_legend_labels(inactive_view)
    @test count(==("Out of service"), diagram_legend_labels(inactive_view)) == 1

    empty_network = PowerImpedance.NetworkBuilder.define((;), ())
    empty_view = diagram(empty_network; interactive = false)
    @test empty_view.plots.legend === nothing
    @test !any(content -> content isa Makie.Legend, empty_view.figure.content)
    @test size(empty_view.figure.scene) == DiagramExtension._DEFAULT_STYLE.figure_size
end
