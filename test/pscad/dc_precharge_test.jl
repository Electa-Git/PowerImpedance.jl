module PSCADDCPrechargeTests
using Test, PowerImpedance
using ..PSCADFixtures
const P = PowerImpedance.PSCAD

@testset "DC island pre-charge detection and components" begin
    fixture = PSCADFixtures.mmc_vdc_network()
    list = P.netlist(fixture.classic, power_flow(fixture.classic))
    buses = P._dc_precharge_buses(list)
    @test length(buses) == 2 # Vdc MMC and its remote PQ MMC, joined by the cable
    plan = P.build_plan(list; settings = P.SimulationSettings(source_ramp = 0.0))
    @test P.check_connectivity(plan) === nothing
    breakers = filter(c -> c.defn == "master:breaker1", plan.main.components)
    @test length(breakers) == 4
    taps = filter(c -> c.defn == "master:nodelabel" &&
        get(Dict(c.params), "MeasV", "0") == "1", plan.main.components)
    @test length(taps) == 4
    @test Set(Dict(c.params)["VName"] for c in taps) ==
        Set(("V_DC_P", "V_DC_N", "V_DC_SEND_P", "V_DC_SEND_N"))
    @test all(c -> Dict(c.params)["PU"] == "0", taps)
    for bus in buses
        channels = filter(c -> c.kind == :voltage && c.bus == bus.name, plan.probes.channels)
        @test Set(c.side for c in channels) == Set(("P", "N"))
        @test only(filter(c -> c.side == "P", channels)).name == P.voltage_probe_name(bus.name * "_P")
        @test only(filter(c -> c.side == "N", channels)).name == P.voltage_probe_name(bus.name * "_N")
    end
    dc_probes = P.ProbeManifest(filter(c -> c.kind == :voltage &&
        c.bus in Set(b.name for b in buses), plan.probes.channels), nothing)
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict(c.name => fill(
        (c.side == "P" ? 1 : -1) * only(filter(b -> b.name == c.bus, buses)).vm_pu *
        only(filter(b -> b.name == c.bus, buses)).base_kV, length(times)) for c in dc_probes.channels)
    model = PSCADModel("precharge.pscx", "precharge", list, dc_probes,
        P.SimulationSettings(), list.operating_point, (;))
    result = PSCADResult(PSCADRun(), times, channels, dc_probes,
        model.settings, (;), (;))
    rows = compare_operating_point(result, model)
    @test length(rows) == length(buses)
    @test all(rows.within_tolerance)
    @test !any(c -> c.defn == "master:voltmetergnd" &&
        get(Dict(c.params), "Name", "") in Set(Dict(t.params)["VName"] for t in taps),
        plan.main.components)
    missing_name = deepcopy(plan.main)
    index = findfirst(c -> c.defn == "master:nodelabel" &&
        get(Dict(c.params), "MeasV", "0") == "1", missing_name.components)
    tap = missing_name.components[index]
    missing_name.components[index] = P.ComponentPlan(tap.defn,
        filter(p -> first(p) != "VName", tap.params), tap.x, tap.y, tap.orient)
    @test_throws ArgumentError P.check_connectivity(missing_name, "missing_voltage_name",
        Dict(m.name => m for m in plan.modules))
    floating_tap = P.CanvasPlan()
    P.component!(floating_tap, "nodelabel", (990, 3168),
        ["Name" => "DC_P", "MeasV" => "1", "VName" => "V_DC_P"])
    P.component!(floating_tap, "voltmetergnd", (1026, 3168), ["Name" => "unused"])
    P.wire!(floating_tap, (990, 3168), (1026, 3168))
    @test_throws ArgumentError P.check_connectivity(floating_tap, "voltage_only_tap")
    function signal_at(point)
        wire = only(filter(w -> point in w.vertices, plan.main.wires))
        labelpoint = only(filter(!=(point), wire.vertices))
        label = only(filter(c -> c.defn == "master:datalabel" && (c.x,c.y) == labelpoint, plan.main.components))
        return Dict(label.params)["Name"]
    end
    for breaker in breakers
        command = Dict(breaker.params)["NAME"]
        compare = only(filter(c -> c.defn == "master:compare" &&
            signal_at((c.x + 36, c.y)) == command, plan.main.components))
        params = Dict(compare.params)
        @test params["OL"] == "0" && params["OH"] == "1"
        @test params["X"] == P.pscad_value(0.2)
    end

    @test all(c -> Dict(c.params)["RON"] == "0.0 [ohm]" &&
        Dict(c.params)["ROFF"] == "1.0E100 [ohm]" &&
        Dict(c.params)["OPCUR"] == "1" && Dict(c.params)["ENAB"] == "0", breakers)
    sources = filter(c -> c.defn == "master:source_1" &&
        startswith(get(Dict(c.params), "Name", ""), "precharge_"), plan.main.components)
    @test length(sources) == 4
    @test all(c -> Dict(c.params)["Type"] == "6" &&
        Dict(c.params)["Cntrl"] == "0" && Dict(c.params)["Tc"] == "0.0 [s]", sources)
    @test count(c -> c.defn == "master:compare" && Dict(c.params)["X"] ==
        P.pscad_value(P._CONVERTER_STARTUP_RELEASE), plan.main.components) == 2
    for bus in buses, pole in ("P", "N")
        source = only(filter(c -> Dict(c.params)["Name"] == "precharge_" * bus.name * "_" * pole, sources))
        @test Dict(source.params)["Vm"] == P.pscad_value(bus.vm_pu * bus.base_kV; unit = "kV")
    end
    # Adding a source remotely suppresses the entire connected island, not just
    # the local converter bus. A source on a separate island must not suppress it.
    original = only(filter(e -> e.name == :G_DC,
        P.netlist(PSCADFixtures.mmc_pq_network().classic, nothing).elements))
    remote = last(buses).key
    terminal = P.Terminal(:stiff, 1, [1], [:remote], remote, false)
    stiff = P.NetlistElement(:stiff, "stiff", original.element, original.model,
        [terminal], :source, original.setpoint)
    supplied = P.Netlist(list.buses, [list.elements; stiff], list.operating_point, list.voltageBase, list.frequency)
    @test isempty(P._dc_precharge_buses(supplied))
    isolated_key = P.BusKey(2, maximum(b.key.index for b in buses) + 1)
    isolated = P.Bus(isolated_key, "isolated", [:isolated], :dc, 400., 1., nothing, nothing)
    isolated_source = P.NetlistElement(:stiff, "stiff", original.element, original.model,
        [P.Terminal(:stiff, 1, [1], [:isolated], isolated_key, false)], :source, original.setpoint)
    separated = P.Netlist([list.buses; isolated], [list.elements; isolated_source],
        list.operating_point, list.voltageBase, list.frequency)
    @test P._dc_precharge_buses(separated) == buses
    unsolved = [P.Bus(b.key, b.name, b.nets, b.kind, b.base_kV, nothing, b.va_rad, b.pf_index) for b in list.buses]
    @test_throws ArgumentError P._dc_precharge_buses(P.Netlist(unsolved, list.elements,
        list.operating_point, list.voltageBase, list.frequency))
    # Permanent DC-clamped and PQ-only islands never acquire startup sources.
    clamped = PSCADFixtures.mmc_pq_network().classic
    @test isempty(P._dc_precharge_buses(P.netlist(clamped, nothing)))
    @test !P._sets_dc_voltage(clamped.elements[:DUT].element_model)
    @test P._sets_dc_voltage(fixture.classic.elements[:DUT].element_model)
    @test P._sets_dc_voltage(PSCADFixtures.tlc_case1_network().classic.elements[:DUT].element_model)
    @test !P._sets_dc_voltage(PSCADFixtures.tlc_case2_network().classic.elements[:DUT].element_model)
    passive = filter(e -> !P._sets_dc_voltage(e.model), list.elements)
    @test isempty(P._dc_precharge_buses(P.Netlist(list.buses, passive,
        list.operating_point, list.voltageBase, list.frequency)))
end
@testset "DC pre-charge clock keeps preceding shunt recorder separate" begin
    # A parallel shunt in column two puts its recorder across the next row's
    # clock-label position. This is the IEEE14 LoadB3/precharge_BusDC1 collision.
    for topology in (:series, :parallel)
        state = P.PlanState(P.CanvasPlan(), P.AbstractLineDefinitionPlan[],
            P.AbstractLineWrapperPlan[], P.ModuleDefinitionPlan[], P.GridLayout(1),
            P.ProbeChannel[], P._NameReservations())
        P.impedance_path!(state,
            [("resistor", "R", 400.0, "ohm"), ("inductor", "L", 0.05, "H")],
            topology, "AC", nothing, "load"; first_probe = "I_load")
        key = P.BusKey(2, 1)
        bus = P.Bus(key, "DC", [:dc], :dc, 400., 1., nothing, nothing)
        context = (; settings = P.SimulationSettings(), dc_labels = Dict(key => ("DC_P", "DC_N")))
        P.dc_precharge!(state, bus, context)
        @test P.check_connectivity(state.main, "shunt_precharge") === nothing
        clock = only(filter(c -> c.defn == "master:time-sig", state.main.components))
        @test (clock.x, clock.y) == (504, topology == :parallel ? 504 : 288)
        recorder = only(filter(c -> c.defn == "master:pgb", state.main.components))
        @test Dict(recorder.params)["Name"] == "I_load"
    end
end

end
