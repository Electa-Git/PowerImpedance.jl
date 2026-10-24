module PSCADIEEE9Tests
import ..PSCADFixtures
using Test, PowerImpedance
using ..PSCADFixtures: ieee9_network
const P = PowerImpedance.PSCAD

@testset "IEEE9 physical fixture and power-flow dispatch" begin
    classic = ieee9_network()
    net = PSCADFixtures.state_from_classic(classic)
    @test length(net.elements) == 15
    @test net.options.voltageBase == 220 / sqrt(3)
    for (name, voltage) in ((:g1, 16.5), (:g2, 18.0), (:g3, 13.8))
        @test classic.elements[name].setpoint.Vac ≈ voltage * sqrt(2 / 3)
        @test ismissing(classic.elements[name].setpoint.θac)
        @test ismissing(classic.elements[name].setpoint.Pac)
        @test ismissing(classic.elements[name].setpoint.Qac)
    end
    for (name, distance) in ((:tl78, 76e3), (:tl89, 106e3), (:tl75, 170e3),
        (:tl96, 179e3), (:tl54, 89e3), (:tl64, 97e3))
        @test net.elements[name].length == distance
    end
    for (name, ratio, primary, secondary) in ((:t1, 16.5 / 230, 4.9916e-4 / 2, 0.097 / 2),
        (:t2, 18 / 230, 6.4458e-4 / 2, 0.1052 / 2),
        (:t3, 13.8 / 230, 3.5523e-4 / 2, 0.0987 / 2))
        t = net.elements[name]
        @test (t.n, t.Lₚ, t.Lₛ, t.Rₚ, t.Rₛ, t.Cₜ, t.Cₛ) ==
            (ratio, primary, secondary, 0, 0, 7e-9, 12e-9)
    end
    for (name, resistance, inductance) in ((:l5, 1269.6, 10.1),
        (:l6, 1763.3, 16.84), (:l8, 1587.16, 14.43))
        form = P.identify_rlc(net.elements[name]).form
        @test form.R ≈ resistance
        @test form.L ≈ inductance
    end
    pf = PSCADFixtures.solved_powerflow(net)
    @test count(bus -> bus["bus_type"] == 3, values(pf.data["bus"])) == 3
    list = P.netlist(net, pf)
    @test length(list.buses) == 9
    @test all(bus -> bus.kind != :dc, list.buses)
    for element in list.elements
        element.model isa PowerImpedance.Source || continue
        terminal = only(t for t in element.terminals if !t.grounded)
        @test list.operating_point.bus_states[terminal.bus].va_rad ≈ 0 atol = 1e-12
    end
    plan = P.build_plan(list; name = "ieee9_classic",
        settings = P.SimulationSettings(simulation_time = 3.0))
    @test P.check_connectivity(plan) === nothing
    @test length(plan.lines) == 6
    @test count(c -> c.defn == "master:xfmr-3p2w", plan.main.components) == 3
    @test count(c -> c.defn == "master:capacitor", plan.main.components) == 9
    @test count(c -> c.defn == "master:capacitor" &&
        Dict(c.params)["C"] == "0.007 [uF]", plan.main.components) == 6
    @test count(c -> c.defn == "master:capacitor" &&
        Dict(c.params)["C"] == "0.012 [uF]", plan.main.components) == 3
end
end
