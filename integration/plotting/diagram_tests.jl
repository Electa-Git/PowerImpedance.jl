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
    @test Set(connection.bus.domain for connection in converter.connected_buses) ==
          Set((1, 2))

    @test all(bus -> bus.key.bus > 0, model.buses)
    dc_load = only(component
    for component in topology_model.components
    if component.key.element == :dc_load)
    @test dc_load.grounded_sides == (2,)
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

function PowerImpedance.NetworkBuilder._port_descriptions(
        ::PowerImpedance.Element{<:DiagramUnknownModel}
)
    return (
        PowerImpedance.NetworkBuilder._PortDescription(1, 1, 2),
        PowerImpedance.NetworkBuilder._PortDescription(2, 1, 2)
    )
end

@testset "GraphMakie diagram generic component fallback" begin
    unknown = PowerImpedance.Element(
        input_pins = 1,
        output_pins = 1,
        element_model = DiagramUnknownModel()
    )
    network = PowerImpedance.NetworkBuilder.define(
        (; unknown),
        (
            diagram_row(:unknown_left, :unknown, 1, 1),
            diagram_row(:unknown_right, :unknown, 2, 1)
        )
    )
    model = DiagramExtension.project_diagram(network)
    @test only(model.components).role == :generic
    @test haskey(model.key_to_vertex, DiagramExtension.ComponentKey(:unknown))
end

@testset "GraphMakie diagram transformer and omission roles" begin
    elements = (
        source = ac_source(pins = 3, transformation = true),
        transformer = transformer(
            pins = 3,
            n = 1.0,
            Rₚ = 0.1,
            Lₚ = 1.0e-3,
            Rₛ = 0.1,
            Lₛ = 1.0e-3,
            transformation = true
        ),
        isolated = impedance(z = 2.0, pins = 1)
    )
    connections = (
        diagram_row(:primary_d, :source, 1, 1),
        diagram_row(:primary_q, :source, 1, 2),
        diagram_row(:primary_d, :transformer, 1, 1),
        diagram_row(:primary_q, :transformer, 1, 2),
        diagram_row(:secondary_d, :transformer, 2, 1),
        diagram_row(:secondary_q, :transformer, 2, 2)
    )
    model = DiagramExtension.project_diagram(
        PowerImpedance.NetworkBuilder.define(elements, connections)
    )
    @test only(component.role
    for component in model.components
    if component.key.element == :transformer) == :transformer
    @test any(
        diagnostic -> diagnostic.kind == :disconnected &&
                      diagnostic.entity == DiagramExtension.ComponentKey(:isolated),
        model.diagnostics)
end
