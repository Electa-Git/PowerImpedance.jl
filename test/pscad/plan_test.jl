module PSCADPlanTests
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures: small_ac_network, passive_ohl_network
const P = PowerImpedance.PSCAD

function plan_shape(plan)
    return (
        name = plan.name, description = plan.description, settings = plan.settings.params,
        components = [(c.defn, c.params, c.x, c.y, c.orient) for c in plan.main.components],
        wires = [w.vertices for w in plan.main.wires],
        lines = [(l.name, l.kind, l.tower, l.conductors, l.ground_wires,
                     l.ground, l.frephase, l.outdisp) for l in plan.lines],
        wrappers = [(w.row, w.x, w.y, w.params) for w in plan.wrappers],
        channels = [(c.name, c.kind, c.bus, c.element, c.side, c.dim, c.unit)
                    for c in plan.probes.channels],
        reference_bus = plan.probes.reference_bus)
end

function counts(plan)
    result = Dict{String, Int}()
    for component in plan.main.components
        result[component.defn] = get(result, component.defn, 0) + 1
    end
    return result
end

function check_layout(plan, number_of_cells)
    for wire in plan.main.wires
        @test length(wire.vertices) == 2
        a, b = wire.vertices
        @test a != b && (a[1] == b[1] || a[2] == b[2])
        @test all(point -> all(v -> v % 18 == 0, point), wire.vertices)
    end
    owners = Set{Tuple{Int, Int}}()
    anchors = Set{Tuple{Int, Int}}()
    for component in plan.main.components
        @test component.x % 18 == component.y % 18 == 0
        cell = ((component.x - 72) ÷ 288, (component.y - 72) ÷ 216)
        @test 0 <= cell[1] < 6 && cell[2] >= 0
        index = cell[1] + 6 * cell[2]
        @test index < number_of_cells
        x, y = 72 + 288 * cell[1], 72 + 216 * cell[2]
        @test x < component.x < x + 288 && y < component.y < y + 216
        @test (component.x, component.y) ∉ anchors
        push!(anchors, (component.x, component.y))
        push!(owners, cell)
    end
    @test length(owners) == number_of_cells
    # Known electrical ports must meet another component port or a wire.
    ports = Tuple{Int, Int}[]
    for wrapper in plan.wrappers
        @test wrapper.x % 18 == wrapper.y % 18 == 0
        append!(ports, [(wrapper.x - 54, wrapper.y + 18),
            (wrapper.x + 54, wrapper.y + 72)])
    end
    for c in plan.main.components
        c.defn in ("master:datalabel", "master:pgb") && continue
        if c.defn == "master:source_3"
            push!(ports, (c.x + 36, c.y))
            @test Dict(c.params)["Grnd"] == "1"
        elseif c.defn in
               ("master:resistor", "master:inductor", "master:capacitor", "master:ammeter")
            append!(ports, [(c.x, c.y), (c.x + 36, c.y)])
        else
            push!(ports, (c.x, c.y))
        end
    end
    endpoints = Set(v for w in plan.main.wires for v in w.vertices)
    for port in ports
        @test count(==(port), ports) > 1 || port in endpoints
    end
    for wire in plan.main.wires
        a, b = wire.vertices
        @test ((a[1] - 72) ÷ 288, (a[2] - 72) ÷ 216) ==
              ((b[1] - 72) ÷ 288, (b[2] - 72) ÷ 216)
    end
end

@testset "PSCAD passive AC plan" begin
    classic, state = small_ac_network()
    pf = power_flow(classic)
    classic_list = P.netlist(classic, pf)
    builder_list = P.netlist(state, NetworkBuilder.solve(state).powerflow)
    classic_plan = P.build_plan(classic_list; name = "small_ac")
    builder_plan = P.build_plan(builder_list; name = "small_ac")
    @test plan_shape(classic_plan) == plan_shape(builder_plan)
    @test counts(classic_plan) == Dict("master:source_3" => 1,
        "master:resistor" => 2, "master:inductor" => 1, "master:ground" => 1,
        "master:ammeter" => 4, "master:voltmetergnd" => 2, "master:nodelabel" => 6,
        "master:datalabel" => 6, "master:pgb" => 6)
    source = only(filter(c -> c.defn == "master:source_3", classic_plan.main.components))
    params = Dict(source.params)
    bus = classic_list.buses[1]
    @test params["Vm"] == P.pscad_value(bus.vm_pu * bus.base_kV * sqrt(3); unit = "kV")
    @test params["Ph"] == P.pscad_value(rad2deg(bus.va_rad) + 90; unit = "deg")
    @test params["Vm"] == "380.0 [kV]"
    @test params["Ph"] == "90.0 [deg]"
    @test params["Type"] == "6"
    @test params["Tc"] == "0.05 [s]"
    @test classic_plan.probes.reference_bus == "B1"
    probe_names = [p.name for p in classic_plan.probes.channels]
    @test probe_names == ["I_source_1", "I_line_1", "I_line_2", "I_load_1", "V_B1", "V_B2"]
    @test length(unique(probe_names)) == length(probe_names)
    @test all(p -> p.dim == 3, classic_plan.probes.channels)
    labels = [Dict(c.params)["Name"]
              for c in classic_plan.main.components if c.defn == "master:nodelabel"]
    @test count(==("B1"), labels) == 3
    @test count(==("B2"), labels) == 3
    check_layout(classic_plan, 5)
    # Source magnitude and sine-reference phase come from the supplied PF,
    # even when those differ from the element's declared setpoint.
    shifted = deepcopy(pf)
    shifted[1]["solution"]["bus"]["1"]["vm"] = 1.02
    shifted[1]["solution"]["bus"]["1"]["va"] = 0.31
    shifted_plan = P.build_plan(P.netlist(classic, shifted))
    shifted_params = Dict(only(filter(c -> c.defn == "master:source_3", shifted_plan.main.components)).params)
    @test shifted_params["Vm"] == "387.6 [kV]"
    @test shifted_params["Ph"] == P.pscad_value(rad2deg(0.31) + 90; unit = "deg")
    settings = P.SimulationSettings(snapshot_time = 0.2)
    recorded = Dict(P.build_plan(builder_list; settings).settings.params)
    @test recorded["time_duration"] == "2.0"
    @test recorded["time_step"] == "10.0"
    @test recorded["sample_step"] == "100.0"
    @test recorded["SnapType"] == "1"
    @test recorded["SnapTime"] == "0.2"
    @test recorded["PlotType"] == "1"
    @test recorded["StartType"] == recorded["MrunType"] == "0"
    @test recorded["Mruns"] == "1"
    @test_throws ArgumentError P.build_plan(builder_list; settings = P.SimulationSettings(frequency = 60))
    layout = P.GridLayout()
    @test [P.allocate_cell!(layout) for _ in 1:7] ==
          [(72, 72), (360, 72), (648, 72), (936, 72), (1224, 72), (1512, 72), (72, 288)]
    for vertices in ([(0, 0)], [(0, 0), (18, 18)], [(0, 0), (0, 0)], [(0, 0), (1, 0)])
        @test_throws ArgumentError P.WirePlan(vertices)
    end
end

@testset "PSCAD impedance topologies and rejection" begin
    R, L, C = 10.0, 0.012, 2e-6
    for (z, topology) in ((s -> R + s * L + inv(s * C), :series),
        (s -> inv(inv(R) + inv(s * L) + s * C), :parallel))
        classic, _ = small_ac_network()
        classic.elements[:line].element_model.value = z
        plan = P.build_plan(P.netlist(classic, nothing))
        check_layout(plan, 5)
        capacitor = only(filter(c -> c.defn == "master:capacitor", plan.main.components))
        @test Dict(capacitor.params)["C"] == "2.0 [uF]"
        @test counts(plan)["master:resistor"] == 2
        @test counts(plan)["master:inductor"] == 1
        @test counts(plan)["master:ammeter"] == 4
        labels = [Dict(c.params)["Name"]
                  for c in plan.main.components if c.defn == "master:nodelabel"]
        @test all(name -> count(==(name), labels) >= 2, unique(labels))
        @test P.identify_rlc(z).form.topology == topology
    end
    # A parallel shunt has one meter measuring the sum of all row currents.
    classic, _ = small_ac_network()
    classic.elements[:load].element_model.value = s -> inv(inv(R) + s * C)
    plan = P.build_plan(P.netlist(classic, nothing))
    check_layout(plan, 5)
    @test counts(plan)["master:ground"] == 1
    @test counts(plan)["master:ammeter"] == 4
    _, builder = small_ac_network()
    reversed_rows = [merge((; row.node, row.element, row.side, row.terminal),
                         (; side = row.element == :load ? 3 - row.side : row.side))
                     for row in builder.topology.connections]
    reversed = NetworkBuilder.define(builder.elements, reversed_rows; options = builder.options)
    reversed_plan = P.build_plan(P.netlist(reversed, nothing))
    check_layout(reversed_plan, 5)
    @test only(filter(c -> c.element == "load", reversed_plan.probes.channels)).side == "2"
    @test counts(reversed_plan)["master:ground"] == 1
    classic, _ = small_ac_network()
    classic.elements[:line].element_model.value = 0.19 + 2π * 50 * 0.0122im
    @test_logs (:info, r"line.*50 Hz") P.build_plan(P.netlist(classic, nothing))
    classic.elements[:line].element_model.value = Diagonal(ComplexF64[1, 2, 3])
    caught = try
        P.build_plan(P.netlist(classic, nothing))
    catch e
        e
    end
    @test caught isa ArgumentError
    @test occursin(":line", sprint(showerror, caught))
    @test occursin("distinct per-conductor", sprint(showerror, caught))
    # A supported netlist model with no emitter fails at the dispatch fallback.
    e = transformer(; pins = 3)
    e.symbol = :future_transformer
    unsupported = P.NetlistElement(:future_transformer, "future_transformer", e,
        e.element_model, P.Terminal[], :transformer, e.setpoint)
    state = P.PlanState(P.CanvasPlan(), P.LineDefinitionPlan[], P.TLineWrapperPlan[],
        P.GridLayout(), P.ProbeChannel[], Set{String}())
    caught = try
        P.emit!(state, unsupported, (;))
    catch e
        e
    end
    @test caught isa ArgumentError
    @test occursin("PSCAD export of :future_transformer", sprint(showerror, caught))
    @test occursin("is not implemented yet", sprint(showerror, caught))
end

@testset "PSCAD overhead-line plan" begin
    classic, builder = passive_ohl_network()
    list = P.netlist(classic, nothing)
    plan = P.build_plan(list; name = "ohl")
    @test plan_shape(plan) ==
          plan_shape(P.build_plan(P.netlist(builder, nothing); name = "ohl"))
    @test length(plan.lines) == length(plan.wrappers) == 1
    row, wrapper = only(plan.lines), only(plan.wrappers)
    @test row.name == wrapper.row == "line_row"
    @test row.kind == :tline
    @test row.conductors == [(-10.0, 30.0), (0.0, 30.0), (10.0, 30.0)]
    @test row.ground_wires == [(-3.25, 37.5), (3.25, 37.5)]
    @test Dict(row.tower) == Dict(
        "TName" => "line_row", "Transp" => "0", "CDataType" => "1", "Hollow" => "0",
        "RadiusC" => "0.015 [m]", "DCResC" => "0.063 [ohm/km]", "PERMC" => "1",
        "SAGC" => "10 [m]", "NCondB" => "1", "BSP" => "0 [m]", "BundSym" => "0",
        "ShuntG" => "1.0E-11 [mho/m]", "GDataType" => "1", "GWSame" => "1",
        "ElimGW" => "1", "RadiusG" => "0.0062 [m]", "DCResG" => "0.92 [ohm/km]",
        "PERMG" => "1", "SAGG" => "10 [m]")
    @test Dict(row.ground) == Dict("EarthForm2" => "0", "EarthForm" => "2",
        "EarthForm3" => "2", "GrRho" => "0", "GRRES" => "100 [ohm*m]",
        "GPERM" => "1", "GRP" => "1")
    @test Dict(row.frephase) == Dict("Interp1" => "1", "Output" => "0", "Inflen" => "0",
        "FS" => "0.5 [Hz]", "FE" => "1000000.0 [Hz]", "Numf" => "100",
        "YMaxP" => "20", "YMaxE" => "0.2 [%]", "AMaxP" => "20", "AMaxE" => "0.2 [%]",
        "MaxRPtol" => "2000000.0", "CPASS" => "0", "DCenab" => "0", "DCCOR" => "1",
        "enablf" => "1")
    @test Dict(row.outdisp) == Dict("DataF" => "50.0 [Hz]")
    @test Dict(wrapper.params) == Dict("Name" => "line", "Freq" => "50.0 [Hz]",
        "Length" => "25.0 [km]", "Dim" => "3", "Mode" => "1", "CoupleEnab" => "0",
        "CoupleName" => "row", "CoupleOffset" => "0.0 [m]", "CoupleRef" => "0",
        "tname" => "tandem_segment", "sfault" => "0", "linc" => "10.0 [km]", "steps" => "3")
    @test counts(plan)["master:ammeter"] == 4
    @test counts(plan)["master:resistor"] == 1
    @test !haskey(counts(plan), "master:inductor")
    check_layout(plan, 5)
    @test [c.name for c in plan.probes.channels] ==
          ["I_source_1", "I_line_1", "I_line_2", "I_load_1", "V_B1", "V_B2"]
    # Both wrapper endpoints meet the inner port of a series ammeter. The
    # outer ports have 36-pixel wire stubs to the correct bus labels.
    for (port, direction, bus, probe) in (
        ((wrapper.x - 54, wrapper.y + 18), -1, "B1", "I_line_1"),
        ((wrapper.x + 54, wrapper.y + 72), 1, "B2", "I_line_2"))
        meter = only(filter(
            c -> c.defn == "master:ammeter" &&
                 Dict(c.params)["Name"] == probe,
            plan.main.components))
        @test (meter.x, meter.y) == (port[1] + (direction == -1 ? -36 : 0), port[2])
        outer = (port[1] + direction * 36, port[2])
        endpoint = (outer[1] + direction * 36, outer[2])
        @test any(w -> Set(w.vertices) == Set([outer, endpoint]), plan.main.wires)
        @test any(
            c -> c.defn == "master:nodelabel" && (c.x, c.y) == endpoint &&
                 Dict(c.params)["Name"] == bus,
            plan.main.components)
    end
    overrides = (; FS = 2.0, FE = "2.0E5 [Hz]", Numf = 200, CPASS = 1,
        EarthForm2 = 2, GRRES = 250.0, GPERM = 1.2, GRP = 5.0, W2 = 1000.0)
    altered = only(P.build_plan(list; line_options = overrides).lines)
    @test Dict(altered.frephase)["FS"] == "2.0 [Hz]"
    @test Dict(altered.frephase)["FE"] == "2.0E5 [Hz]"
    @test Dict(altered.frephase)["Numf"] == "200"
    @test Dict(altered.frephase)["CPASS"] == "1"
    @test Dict(altered.frephase)["W2"] == "1000.0"
    @test Dict(altered.ground)["EarthForm2"] == "2"
    @test Dict(altered.ground)["GRRES"] == "250.0 [ohm*m]"
    @test Dict(altered.ground)["GPERM"] == "1.2"
    @test Dict(altered.ground)["GRP"] == "5.0"
    @test row.frephase != altered.frephase
    for options in ((; UnknownField = 1), (; Numf = :unsupported), (; FS = Inf), Dict())
        @test_throws ArgumentError P.build_plan(list; line_options = options)
    end
    # Mapping follows native physical coordinates and preserves material data
    # when the line is bundled, vertical or has no ground wires.
    tl = classic.elements[:line].element_model
    tl.conductors.organization = :vertical
    tl.conductors.Δyᵇᶜ = 8
    tl.conductors.nˢᵇ = 4
    tl.conductors.dˢᵇ = 0.45
    tl.conductors.μᵣᶜ = 1.5
    tl.groundwires.μᵣᵍ = 2.0
    tl.earth_parameters = (1.3, 8.0, 350.0)
    vertical = only(P.build_plan(P.netlist(classic, nothing)).lines)
    @test vertical.conductors == [(5.0, 38.0), (5.0, 46.0), (5.0, 54.0)]
    @test Dict(vertical.tower)["NCondB"] == "4"
    @test Dict(vertical.tower)["BSP"] == "0.45 [m]"
    @test Dict(vertical.tower)["PERMC"] == "1.5"
    @test Dict(vertical.tower)["PERMG"] == "2.0"
    @test Dict(vertical.ground)["GPERM"] == "1.3"
    @test Dict(vertical.ground)["GRP"] == "8.0"
    @test Dict(vertical.ground)["GRRES"] == "350.0 [ohm*m]"
    tl.groundwires.nᵍ = 0
    @test isempty(only(P.build_plan(P.netlist(classic, nothing)).lines).ground_wires)
    tl.conductors.organization = Symbol()
    tl.conductors.positions = ([-11, 1, 9], [28, 35, 31])
    @test only(P.build_plan(P.netlist(classic, nothing)).lines).conductors ==
          [(-11.0, 28.0), (1.0, 35.0), (9.0, 31.0)]
    # Reject a 2-conductor line before any AC-terminal mapping.
    tl.conductors.nᵇ = 2
    caught = try
        P.build_plan(P.netlist(classic, nothing))
    catch error
        error
    end
    @test caught isa ArgumentError
    @test occursin("not implemented yet", sprint(showerror, caught))
end

@testset "PSCAD export requires extension before power flow" begin
    @test Base.get_extension(PowerImpedance, :PowerImpedancePSCADExt) === nothing
    classic, state = small_ac_network()
    initial = classic.elements[:source].setpoint
    mktempdir() do root
        path = joinpath(root, "fixture.pscx")
        for net in (classic, state)
            caught = try
                export_pscad(net; path)
            catch e
                e
            end
            @test caught isa ArgumentError
            @test occursin("export_pscad requires PythonCall", sprint(showerror, caught))
            @test !isfile(path)
        end
        @test classic.elements[:source].setpoint === initial
        @test_throws ArgumentError export_pscad(classic; path, dc_reference = :other)
        @test_throws ArgumentError export_pscad(classic; path, line_options = Dict())
        @test_throws ArgumentError export_pscad(classic; path, line_options = (;
            UnknownField = 1))
        @test_throws ArgumentError export_pscad(classic; path = joinpath(root, "fixture.xml"))
        @test_throws ArgumentError export_pscad(classic; path = joinpath(root, "missing", "fixture.pscx"))
        @test_throws ArgumentError export_pscad(classic; path, name = "different")
        write(path, "existing project")
        @test_throws ArgumentError export_pscad(classic; path)
        @test classic.elements[:source].setpoint === initial
        @test read(path, String) == "existing project"
    end
end
end
