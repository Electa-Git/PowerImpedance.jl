module NetworkModelTests
using Test, PowerImpedance
const PI = PowerImpedance
const NB = PI.NetworkBuilder
include("pscad/fixtures.jl")

@testset "Active elements on ideal sources" begin
    for name in (:mmc_pq, :sm)
        @testset "$name" begin
            state = getfield(PSCADFixtures, Symbol(name, "_network"))()
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
    original = PSCADFixtures.mmc_vdc_network()
    elements = Base.structdiff(original.elements, (; CableDC = original.elements.CableDC))
    connections = (
        NB.Bus(:AC; ports = ((:DUT, :ac), (:G_AC, :ac))),
        NB.Bus(:SEND; ports = ((:SEND, :ac), (:G_SEND, :ac))),
        NB.Bus(:DC; ports = ((:DUT, :dc), (:SEND, :dc))),
    )
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
            withground = true, acfirst = false).net
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

@testset "Frames select passive admittances" begin
    branch = impedance(z = s -> 1.0 + 0.01s, pins = 3).element_model
    dq = NB.define((; branch), (
        NB.Bus(:from; ports = ((:branch, :side1),), domain = ACDQ),
        NB.Bus(:to; ports = ((:branch, :side2),), domain = ACDQ),
    ))
    abc = NB.define((; branch), (
        NB.Bus(:from; ports = ((:branch, :side1),)),
        NB.Bus(:to; ports = ((:branch, :side2),)),
    ))
    dq_model = NB.NetworkModel(dq, OperatingPoint())
    abc_model = NB.NetworkModel(abc, OperatingPoint())
    cable = PSCADFixtures.dc_cable_network().elements.line
    for s in ComplexF64.(2π * im .* (1.0, 50.0, 1000.0))
        transformed = PI.abcd_to_y(PI.transformation_dq(
            PI.eval_abcd(branch, s + 100π * im), PI.eval_abcd(branch, s - 100π * im)))
        raw = PI.abcd_to_y(PI.eval_abcd(branch, s))
        @test NB.admittance(branch, s, :dq) == transformed
        @test NB.admittance(branch, s, :abc) == raw
        @test NB.get_y(dq_model, :branch, [s])[:, :, 1] == transformed
        @test NB.get_y(abc_model, :branch, [s])[:, :, 1] == raw
        @test NB.admittance(cable, s, :dc) ==
            PI.abcd_to_y(PI.transformation_dc(PI.eval_abcd(cable, s)))
    end
    @test NB.sortedcomponentconnections(dq.topology, :branch).terminal == [:d, :q, :d, :q]
    @test NB.sortedcomponentconnections(abc.topology, :branch).terminal ==
        [:a, :b, :c, :a, :b, :c]
end

@testset "Active models require named terminal values" begin
    state = PSCADFixtures.mmc_pq_network()
    @test_throws r"missing active element :DUT" NB.NetworkModel(state, OperatingPoint())
    invalid = OperatingPoint(Dict(:DUT => (ac = ACPortValues(0.0, 0.0, 0.0, 0.0),)))
    @test_throws r"element :DUT" NB.NetworkModel(state, invalid)
    @test NB.solve(state) isa PowerFlowResult
end

@testset "Admittance errors name the element" begin
    branch = impedance(z = s -> error("invalid impedance"), pins = 1).element_model
    state = NB.define((; branch), (
        NB.Net(:from; terminals = ((:branch, :side1, :dc),)),
        NB.Net(:to; terminals = ((:branch, :side2, :dc),)),
    ))
    model = NB.NetworkModel(state, OperatingPoint())
    @test_throws r"element :branch:.*invalid impedance" NB.get_y(model, :branch, [1.0im])
end

@testset "Component roles" begin
    ac = [(bus = (domain = 1,),)]
    dc = [(bus = (domain = 2,),)]
    z = impedance(z = 1.0).element_model
    @test NB.topology_role(z, ac, ()) == :ac_branch
    @test NB.topology_role(z, dc, ()) == :dc_branch
    @test NB.topology_role(z, ac, (:side2,)) == :shunt
    @test NB.topology_role(ac_source().element_model, ac, ()) == :source
    @test NB.topology_role(
        PSCADFixtures.mmc_pq_network().elements.DUT, ac, ()) == :converter
    @test NB.topology_role(synchronousmachine().element_model, ac, ()) == :machine
    @test NB.topology_role(inductionmachine().element_model, ac, ()) == :machine
    @test NB.topology_role(transformer().element_model, ac, ()) == :transformer
    @test NB.refined_role(:generic, z, "branch", Dict("transformer" => 2)) == :transformer
    @test NB.refined_role(:generic, z, "branchdc", Dict()) == :dc_branch
    @test NB.refined_role(:generic, z, "branch", nothing) == :ac_branch
    @test NB.refined_role(:generic, z, "load", Dict()) == :load
    @test NB.refined_role(:generic, z, "shunt", Dict()) == :shunt
    @test NB.refined_role(:generic, z, nothing, nothing) == :generic
end

end
