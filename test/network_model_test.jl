module NetworkModelTests
using Test, PowerImpedance
const PI = PowerImpedance
const NB = PI.NetworkBuilder
include("pscad/fixtures.jl")

@testset "Active elements on ideal sources" begin
    for name in (:mmc_pq, :sm)
        @testset "$name" begin
            state = getfield(PSCADFixtures, Symbol(name, "_network"))().state
            powerflow = compute(PowerFlowProblem(state), ACDCPowerFlow())
            @test powerflow.result["termination_status"] == PI.MOI.LOCALLY_SOLVED
            model = NB.NetworkModel(state, powerflow.operating_point)
            @test length(model.active_elements) == 1
            @test model.passive_elements == Int[]
            @test isempty(setdiff(model.retained_nodes, model.grounded_nodes))
            @test all(index -> index in model.grounded_nodes,
                values(model.indices.nodes))
        end
    end
end

@testset "Back-to-back converters without passive elements" begin
    original = PSCADFixtures.mmc_vdc_network().state
    elements = Base.structdiff(original.elements, (; CableDC = original.elements.CableDC))
    connections = [(;
        node = row.node == :DC_SEND ? :DC : row.node,
        row.element, row.side, row.terminal)
        for row in original.topology.connections if row.element != :CableDC]
    state = NB.define(elements, connections; options = original.options)
    powerflow = compute(PowerFlowProblem(state), ACDCPowerFlow())
    status = powerflow.result["termination_status"]
    status == PI.MOI.LOCALLY_SOLVED ||
        error("Back-to-back power flow did not converge: $status")
    @test status == PI.MOI.LOCALLY_SOLVED
    model = NB.NetworkModel(state, powerflow.operating_point)
    @test length(model.active_elements) == 2
    @test model.passive_elements == Int[]
    @test setdiff(model.retained_nodes, model.grounded_nodes) == [model.indices.nodes[:DC]]

    frequencies = ComplexF64.(2π * im .* (1e-3, 1, 5, 49, 150, 500, 1500, 5000))
    s = collect(frequencies)
    actual = NB.make_y_node(model, s)
    for element in (:DUT, :SEND)
        nodes = NB.sortedcomponentconnections(state.topology, element;
            withground = true, acfirst = false).node
        @test first(nodes) == :DC
        @test all(node -> model.indices.nodes[node] in model.grounded_nodes, nodes[2:end])
    end
    expected = NB.get_y(model, :DUT, s)[1:1, 1:1, :] +
               NB.get_y(model, :SEND, s)[1:1, 1:1, :]
    @test size(actual) == (1, 1, length(s))
    for index in eachindex(s)
        @test actual[:, :, index] ≈ expected[:, :, index] rtol = 1e-12
    end
    difference = maximum(abs.(actual .- expected) ./ abs.(expected))
    println("Back-to-back admittance maximum relative difference: ", difference)
end
end
