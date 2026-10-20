module PSCADDCOverheadLineTests
using Test, PowerImpedance
using ..PSCADFixtures
const P = PowerImpedance.PSCAD

function network()
    classic, state = PSCADFixtures.dc_cable_network()
    line = overhead_line(length = 75e3,
        conductors = Conductors(organization = :flat, nᵇ = 2, nˢᵇ = 1,
            Rᵈᶜ = 0.0266, rᶜ = 0.0224, yᵇᶜ = 18.0, Δxᵇᶜ = 7.3, dˢᵃᵍ = 6.0),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062,
            Δxᵍ = 7.3, Δyᵍ = 7.0, dᵍˢᵃᵍ = 6.0),
        earth_parameters = (1, 1, 100), transformation = true)
    rows = [(; row.node, row.element, row.side, row.terminal)
        for row in state.topology.connections]
    return PowerImpedance.NetworkBuilder.define(merge(state.elements, (; line)),
        rows; options = state.options)
end

@testset "Two-pole overhead line material and terminal order" begin
    state = network()
    list = P.netlist(state, nothing)
    plan = P.build_plan(list)
    row, wrapper = only(plan.lines), only(plan.wrappers)
    @test row.conductors == [(-3.65, 18.0), (3.65, 18.0)]
    @test row.ground_wires == [(-3.65, 25.0), (3.65, 25.0)]
    @test Dict(row.tower)["SAGC"] == "6.0 [m]"
    @test Dict(row.tower)["SAGG"] == "6.0 [m]"
    @test Dict(row.frephase)["FS"] == "0.001 [Hz]"
    @test Dict(row.frephase)["YMaxE"] == "0.02 [%]"
    @test Dict(row.frephase)["AMaxE"] == "0.02 [%]"
    @test Dict(wrapper.params)["Mode"] == "0"
    @test Dict(wrapper.params)["Dim"] == "2"
    @test Dict(wrapper.params)["Freq"] == "0.0 [Hz]"
    interfaces = filter(c -> c.defn == "master:tline_interface", plan.main.components)
    @test length(interfaces) == 2
    @test P.check_connectivity(plan) === nothing
    for (side, interface) in enumerate(interfaces)
        @test Dict(interface.params) == Dict("Name" => "line", "NC" => "2", "View" => "0",
            "send_recv" => "0", "dim_s" => "0", "dim_r" => "0")
        ports = first.(P.component_ports(interface, Dict()))
        direction = side == 1 ? -1 : 1
        @test ports == [(interface.x + 18direction, interface.y - 18),
            (interface.x + 18direction, interface.y + 18)]
        # Follow each saved scalar port's wire to its actual node label.
        node(port) = begin
            wire = only(filter(w -> port in w.vertices, plan.main.wires))
            endpoint = only(filter(!=(port), wire.vertices))
            label = only(filter(c -> c.defn == "master:nodelabel" &&
                (c.x, c.y) == endpoint, plan.main.components))
            Dict(label.params)["Name"]
        end
        @test node(ports[2]) == "D$(side)_N"
        meter = only(filter(c -> c.defn == "master:ammeter" &&
            Dict(c.params)["Name"] == "I_line_$side", plan.main.components))
        meter_ports = first.(P.component_ports(meter, Dict()))
        @test node(ports[1]) == node(meter_ports[side == 1 ? 2 : 1])
        @test node(meter_ports[side == 1 ? 1 : 2]) == "D$(side)_P"
    end
    override = P.build_plan(list; line_options = (; FS = 0.01))
    @test Dict(only(override.lines).frephase)["FS"] == "0.01 [Hz]"
    bad = deepcopy(list)
    only(filter(e -> e.name == :line, bad.elements)).model.conductors.nᵇ = 3
    @test_throws r"requires 2 conductors" P.build_plan(bad)
end
end
