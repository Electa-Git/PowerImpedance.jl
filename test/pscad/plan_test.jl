module PSCADPlanTests
import ..PSCADFixtures
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures: small_ac_network, passive_ohl_network, transformer_network,
                       dc_network
const P = PowerImpedance.PSCAD

@testset "PSCAD overhead-line transposition" begin
    state = passive_ohl_network()
    model = state.elements[:line]
    for (transposition, expected) in ((:none, "0"), (:ideal, "1"))
        model.transposition = transposition
        plan = P.build_plan(P.netlist(state, nothing))
        @test Dict(only(plan.lines).tower)["Transp"] == expected
    end
end

@testset "PSCAD short overhead line warning" begin
    state = passive_ohl_network()
    state.elements[:line].length = 100.0
    settings = P.SimulationSettings(time_step = 10e-6)
    @test_logs (:warn, r"overhead line :line, length 100.0 m, time step 1.0e-5 s: PSCAD aborts if the travel time is below the step") begin
        P.build_plan(P.netlist(state, nothing); settings)
    end
end

function plan_shape(plan)
    return (
        name = plan.name, description = plan.description, settings = plan.settings.params,
        components = [(c.defn, c.params, c.x, c.y, c.orient) for c in plan.main.components],
        wires = [w.vertices for w in plan.main.wires],
        lines = [l isa P.CableDefinitionPlan ?
                 (l.name, [(c.defn, c.params, c.x, c.y, c.orient) for c in l.cables],
                     l.ground, l.frephase, l.outdisp) :
                 (l.name, l.kind, l.tower, l.conductors, l.ground_wires,
                     l.ground, l.frephase, l.outdisp) for l in plan.lines],
        wrappers = [(w.row, w.x, w.y, w.params) for w in plan.wrappers],
        channels = [(c.name, c.kind, c.bus, c.element, c.port, c.dim, c.unit)
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

function check_layout(plan, number_of_cells; empty_cells = ())
    @test P.check_connectivity(plan) === nothing
    # Named meter stubs extend 18 pixels above the allocation origin. The 432 × 216
    # placement tiles are shifted up 18 pixels without overlap.
    cell(point) = (fld(point[1] - 72, 432), fld(point[2] - 54, 216))
    owners = Set{Tuple{Int, Int}}()
    anchors = Set{Tuple{Int, Int}}()
    function check_location(component)
        point = (component.x, component.y)
        @test all(v -> v % 18 == 0, point)
        owner = cell(point)
        @test 0 <= owner[1] < 6 && owner[2] >= 0
        index = owner[1] + 6 * owner[2]
        @test index < number_of_cells && index ∉ empty_cells
        x, y = 72 + 432 * owner[1], 72 + 216 * owner[2]
        @test x < component.x < x + 432 && y - 18 <= component.y < y + 198
        @test point ∉ anchors
        push!(anchors, point)
        push!(owners, owner)
    end
    endpoints = Set(v for w in plan.main.wires for v in w.vertices)
    for wire in plan.main.wires
        @test length(wire.vertices) == 2
        a, b = wire.vertices
        @test a != b && (a[1] == b[1] || a[2] == b[2])
        @test all(point -> all(v -> v % 18 == 0, point), wire.vertices)
        @test cell(a) == cell(b)
    end
    modules = Dict(m.name => m for m in plan.modules)
    for component in plan.main.components
        check_location(component)
        if component.defn == "master:source_3"
            @test Dict(component.params)["Grnd"] == "1"
        end
        for (port, _) in P.component_ports(component, modules)
            @test port in endpoints
            @test count(w -> port in w.vertices, plan.main.wires) == 1
        end
        if component.defn in ("master:nodelabel", "master:datalabel", "master:ground")
            @test (component.x, component.y) in endpoints
        end
    end
    for wrapper in plan.wrappers
        check_location(wrapper)
        if wrapper isa P.TLineWrapperPlan
            for port in ((wrapper.x - 54, wrapper.y + 18),
                (wrapper.x + 54, wrapper.y + 72))
                @test port in endpoints
                @test count(w -> port in w.vertices, plan.main.wires) == 1
            end
        end
    end
    @test length(owners) + length(empty_cells) == number_of_cells
    @test Set(x + 6y for (x, y) in owners) ==
          setdiff(Set(0:(number_of_cells - 1)), empty_cells)
end

@testset "PSCAD passive AC plan" begin
    state = small_ac_network()
    pf = PSCADFixtures.solved_powerflow(state)
    list = P.netlist(state, pf)
    builder_list = list
    plan = P.build_plan(list; name = "small_ac")
    @test counts(plan) == Dict("master:source_3" => 1,
        "master:resistor" => 2, "master:inductor" => 1, "master:ground" => 1,
        "master:ammeter" => 4, "master:voltmetergnd" => 2, "master:nodelabel" => 16,
        "master:datalabel" => 6, "master:pgb" => 6)
    source = only(filter(c -> c.defn == "master:source_3", plan.main.components))
    params = Dict(source.params)
    bus = list.buses[1]
    @test params["Vm"] == P.pscad_value(bus.vm_pu * bus.base_kV * sqrt(3); unit = "kV")
    @test params["Ph"] == P.pscad_value(rad2deg(bus.va_rad) + 90; unit = "deg")
    @test params["Vm"] == "380.0 [kV]"
    @test params["Ph"] == "90.0 [deg]"
    @test params["Type"] == "6"
    @test params["Tc"] == "0.05 [s]"
    @test plan.probes.reference_bus == "B1"
    probe_names = [p.name for p in plan.probes.channels]
    @test probe_names ==
          ["I_source_ac", "I_line_side1", "I_line_side2", "I_load_side1", "V_B1", "V_B2"]
    @test length(unique(probe_names)) == length(probe_names)
    @test all(p -> p.dim == 3, plan.probes.channels)
    labels = [Dict(c.params)["Name"]
              for c in plan.main.components if c.defn == "master:nodelabel"]
    @test count(==("B1"), labels) == 3
    @test count(==("B2"), labels) == 3
    check_layout(plan, 5)
    # Source magnitude and sine-reference phase come from the supplied PF,
    # even when those differ from the element's declared setpoint.
    shifted = deepcopy(pf)
    shifted.result["solution"]["bus"]["1"]["vm"] = 1.02
    shifted.result["solution"]["bus"]["1"]["va"] = 0.31
    shifted_plan = P.build_plan(P.netlist(state, shifted))
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
          [(72, 72), (504, 72), (936, 72), (1368, 72), (1800, 72), (2232, 72), (72, 288)]
    for vertices in ([(0, 0)], [(0, 0), (18, 18)], [(0, 0), (0, 0)], [(0, 0), (1, 0)])
        @test_throws ArgumentError P.WirePlan(vertices)
    end
end

@testset "PSCAD impedance topologies and rejection" begin
    R, L, C = 10.0, 0.012, 2e-6
    for (z, topology) in ((s -> R + s * L + inv(s * C), :series),
        (s -> inv(inv(R) + inv(s * L) + s * C), :parallel))
        state = small_ac_network()
        state.elements[:line].value = z
        plan = P.build_plan(P.netlist(state, nothing))
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
    state = small_ac_network()
    state.elements[:load].value = s -> inv(inv(R) + s * C)
    plan = P.build_plan(P.netlist(state, nothing))
    check_layout(plan, 5)
    @test counts(plan)["master:ground"] == 1
    @test counts(plan)["master:ammeter"] == 4
    # Both parallel rows share the return node before the total-current meter. Only its
    # output is grounded; its arrow retains bus-to-element polarity.
    shunt_parts = filter(c -> get(Dict(c.params), "Name", "") in ("load_R", "load_C"),
        plan.main.components)
    @test length(shunt_parts) == 2
    grounds = Set((c.x, c.y) for c in plan.main.components if c.defn == "master:ground")
    meter = only(filter(
        c -> c.defn == "master:ammeter" &&
             Dict(c.params)["Name"] == "I_load_side1",
        plan.main.components))
    labels = Dict((c.x, c.y) => Dict(c.params)["Name"]
    for c in plan.main.components if c.defn == "master:nodelabel")
    for part in shunt_parts
        port = (part.x + 36, part.y)
        wire = only(filter(w -> port in w.vertices, plan.main.wires))
        @test labels[only(filter(!=(port), wire.vertices))] == "load_parallel_2"
    end
    @test any(
        w -> (meter.x + 36, meter.y) in w.vertices &&
             any(p -> p in grounds, w.vertices), plan.main.wires)
    builder = small_ac_network()
    topology = deepcopy(builder.topology)
    for i in eachindex(topology.connections.port)
        topology.connections.component[i] == :load || continue
        topology.connections.port[i] =
            topology.connections.port[i] == :side1 ? :side2 : :side1
    end
    reversed = NetworkBuilder.NetworkState(builder.elements, topology, builder.options)
    reversed_plan = P.build_plan(P.netlist(reversed, nothing))
    check_layout(reversed_plan, 5)
    @test only(filter(c -> c.element == "load", reversed_plan.probes.channels)).port ==
          :side2
    @test counts(reversed_plan)["master:ground"] == 1
    state = small_ac_network()
    state.elements[:line].value = 0.19 + 2π * 50 * 0.0122im
    @test_logs (:info, r"line.*50 Hz") P.build_plan(P.netlist(state, nothing))
    state.elements[:line].value = Diagonal(ComplexF64[1, 2, 3])
    caught = try
        P.build_plan(P.netlist(state, nothing))
    catch e
        e
    end
    @test caught isa ArgumentError
    @test occursin(":line", sprint(showerror, caught))
    @test occursin("distinct per-conductor", sprint(showerror, caught))
    # The fallback is exercised directly, independently of emitter methods.
    model = PSCADFixtures.dc_cable_network().elements.line
    unsupported = P.NetlistElement(:future_cable, "future_cable", model,
        electricalconnections(model), P.Terminal[], :transformer, nothing)
    state = P.PlanState(
        P.CanvasPlan(), P.AbstractLineDefinitionPlan[], P.AbstractLineWrapperPlan[],
        P.ModuleDefinitionPlan[], P.GridLayout(), P.ProbeChannel[], P._NameReservations())
    caught = try
        invoke(P.emit!, Tuple{P.PlanState, P.NetlistElement, Any}, state, unsupported, (;))
    catch e
        e
    end
    @test caught isa ArgumentError
    @test occursin("PSCAD export of :future_cable", sprint(showerror, caught))
    @test occursin("is not implemented yet", sprint(showerror, caught))
end

@testset "PSCAD overhead-line plan" begin
    state = passive_ohl_network()
    builder = state
    list = P.netlist(state, nothing)
    plan = P.build_plan(list; name = "ohl")
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
        "YMaxP" => "20", "YMaxE" => "0.02 [%]", "AMaxP" => "20", "AMaxE" => "0.02 [%]",
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
          ["I_source_ac", "I_line_side1", "I_line_side2", "I_load_side1", "V_B1", "V_B2"]
    # Wrapper and meter inner ports have distinct stubs to one internal node.
    # Outer meter ports have separate stubs to the bus labels.
    for (port, direction, bus, probe) in (
        ((wrapper.x - 54, wrapper.y + 18), -1, "B1", "I_line_side1"),
        ((wrapper.x + 54, wrapper.y + 72), 1, "B2", "I_line_side2"))
        meter = only(filter(
            c -> c.defn == "master:ammeter" &&
                 Dict(c.params)["Name"] == probe,
            plan.main.components))
        @test (meter.x, meter.y) == (port[1] + 36direction, port[2] - 36)
        outer = (port[1] + direction * 36, port[2] - 36)
        endpoint = (outer[1] + direction * 36, outer[2])
        @test any(w -> Set(w.vertices) == Set([outer, endpoint]), plan.main.wires)
        @test any(
            c -> c.defn == "master:nodelabel" && (c.x, c.y) == endpoint &&
                 Dict(c.params)["Name"] == bus,
            plan.main.components)
    end
    overrides = (; FS = 2.0, FE = "2.0E5 [Hz]", Numf = 200, YMaxE = 0.3, AMaxE = "0.4 [%]", CPASS = 1,
        EarthForm2 = 2, GRRES = 250.0, GPERM = 1.2, GRP = 5.0, W2 = 1000.0)
    altered = only(P.build_plan(list; line_options = overrides).lines)
    @test Dict(altered.frephase)["FS"] == "2.0 [Hz]"
    @test Dict(altered.frephase)["FE"] == "2.0E5 [Hz]"
    @test Dict(altered.frephase)["Numf"] == "200"
    @test Dict(altered.frephase)["CPASS"] == "1"
    @test Dict(altered.frephase)["YMaxE"] == "0.3 [%]"
    @test Dict(altered.frephase)["AMaxE"] == "0.4 [%]"
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
    tl = state.elements[:line]
    tl.conductors.organization = :vertical
    tl.conductors.Δyᵇᶜ = 8
    tl.conductors.nˢᵇ = 4
    tl.conductors.dˢᵇ = 0.45
    tl.conductors.μᵣᶜ = 1.5
    tl.groundwires.μᵣᵍ = 2.0
    tl.earth_parameters = (1.3, 8.0, 350.0)
    vertical = only(P.build_plan(P.netlist(state, nothing)).lines)
    @test vertical.conductors == [(5.0, 38.0), (5.0, 46.0), (5.0, 54.0)]
    @test Dict(vertical.tower)["NCondB"] == "4"
    @test Dict(vertical.tower)["BSP"] == "0.45 [m]"
    @test Dict(vertical.tower)["PERMC"] == "1.5"
    @test Dict(vertical.tower)["PERMG"] == "2.0"
    @test Dict(vertical.ground)["GPERM"] == "1.3"
    @test Dict(vertical.ground)["GRP"] == "8.0"
    @test Dict(vertical.ground)["GRRES"] == "350.0 [ohm*m]"
    tl.groundwires.nᵍ = 0
    @test isempty(only(P.build_plan(P.netlist(state, nothing)).lines).ground_wires)
    tl.conductors.organization = Symbol()
    tl.conductors.positions = ([-11, 1, 9], [28, 35, 31])
    @test only(P.build_plan(P.netlist(state, nothing)).lines).conductors ==
          [(-11.0, 28.0), (1.0, 35.0), (9.0, 31.0)]
    # A two-conductor line remains invalid on AC buses.
    tl.conductors.nᵇ = 2
    caught = try
        P.build_plan(P.netlist(state, nothing))
    catch error
        error
    end
    @test caught isa ArgumentError
    @test occursin("requires 3 conductors for AC export", sprint(showerror, caught))
end

# Resolve labels, wires and touching component ports without treating a
# two-terminal device as a wire. Used to check the actual emitted circuit.
function electrical_nodes(plan)
    parent = Dict{Tuple{Int, Int}, Tuple{Int, Int}}()
    function root(p)
        get!(parent, p, p)
        parent[p] == p ? p : (parent[p] = root(parent[p]))
    end
    function join(a, b)
        parent[root(a)] = root(b)
    end
    for w in plan.main.wires
        join(w.vertices...)
    end
    labels = Dict{String, Tuple{Int, Int}}()
    for c in plan.main.components
        if c.defn == "master:nodelabel"
            name = Dict(c.params)["Name"]
            point = (c.x, c.y)
            haskey(labels, name) ? join(labels[name], point) : (labels[name] = point)
        elseif c.defn == "master:ground"
            point = (c.x, c.y)
            haskey(labels, "ground") ? join(labels["ground"], point) :
            (labels["ground"] = point)
        end
    end
    return (; root, labels)
end

@testset "PSCAD transformer plans" begin
    for organization in (:YY, :ΔY)
        state = transformer_network(; organization)
        state = state
        plan = P.build_plan(P.netlist(state, nothing); name = "transformer")
        @test plan_shape(plan) ==
              plan_shape(P.build_plan(P.netlist(state, nothing); name = "transformer"))
        @test counts(plan)["master:xfmr-3p2w"] == 1
        @test counts(plan)["master:resistor"] == 4
        @test counts(plan)["master:inductor"] == 3
        @test counts(plan)["master:ammeter"] == 4
        @test counts(plan)["master:ground"] == 3
        check_layout(plan, 11)
        winding = only(filter(c -> c.defn == "master:xfmr-3p2w", plan.main.components))
        @test Dict(winding.params) == Dict("Name" => "line", "Tmva" => "1000 [MVA]",
            "f" => "50.0 [Hz]", "YD1" => organization == :ΔY ? "1" : "0",
            "YD2" => "0", "Lead" => "1", "Ideal" => organization == :YY ? "0" : "1",
            "Xl" => P.pscad_value(P.YY_LEAKAGE_PU; unit = "pu"),
            "Im1" => P.pscad_value(P.YY_MAGNETIZING_CURRENT_PERCENT; unit = "%"),
            "NLL" => "0.0 [pu]", "CuL" => "0.0 [pu]", "Tap" => "0", "View" => "1",
            "Dtls" => "0", "V1" => "380.0 [kV]", "V2" => "150.0 [kV]", "Enab" => "0")
        for (name, field, value) in (("line_primary_R", "R", "10.0 [ohm]"),
            ("line_primary_L", "L", "0.1 [H]"), ("line_secondary_R", "R", "1.0 [ohm]"),
            ("line_secondary_L", "L", "0.05 [H]"),
            ("line_magnetizing_R", "R", "1000000.0 [ohm]"), (
            "line_magnetizing_L", "L", "1000.0 [H]"))
            part = only(filter(c -> get(Dict(c.params), "Name", "") == name, plan.main.components))
            @test Dict(part.params)[field] == value
        end
        @test [c.name for c in plan.probes.channels] ==
              [
            "I_source_ac", "I_line_side1", "I_line_side2", "I_load_side1", "V_B1", "V_B2"]
        circuit = electrical_nodes(plan)
        for parameter in ("R", "L")
            part = only(filter(
                c -> get(Dict(c.params), "Name", "") == "line_magnetizing_$parameter",
                plan.main.components))
            @test circuit.root((part.x, part.y)) ==
                  circuit.root((winding.x - 54, winding.y))
            @test circuit.root((part.x + 36, part.y)) ==
                  circuit.root(circuit.labels["ground"])
        end
        # Turn and stray capacitances lie behind the terminal current meters.
        t = state.elements[:line]
        t.Cₜ = 1e-8
        t.Cₛ = 2e-8
        capacitive = P.build_plan(P.netlist(state, nothing))
        check_layout(capacitive, 14)
        circuit = electrical_nodes(capacitive)
        for (name, left, right, value) in (
            ("line_turn_1_C", "line_terminal_1", "ground", "0.01 [uF]"),
            ("line_turn_2_C", "line_terminal_2", "ground", "0.01 [uF]"),
            ("line_stray_C", "line_terminal_1", "line_terminal_2", "0.02 [uF]"))
            part = only(filter(c -> get(Dict(c.params), "Name", "") == name, capacitive.main.components))
            @test Dict(part.params)["C"] == value
            @test circuit.root((part.x, part.y)) == circuit.root(circuit.labels[left])
            @test circuit.root((part.x + 36, part.y)) == circuit.root(circuit.labels[right])
        end
        for field in (:Rₚ, :Lₚ, :Rₛ, :Lₛ, :Lₘ, :Rₘ, :Cₜ, :Cₛ)
            setproperty!(t, field, 0.0)
        end
        empty = P.build_plan(P.netlist(state, nothing))
        check_layout(empty, 9; empty_cells = (2, 4))
        @test counts(empty)["master:resistor"] == 1 # load only
        @test !haskey(counts(empty), "master:inductor")
        t.Rₘ = t.Lₘ = Inf
        @test plan_shape(empty) == plan_shape(P.build_plan(P.netlist(state, nothing)))
        t.hasRω = true
        @test_throws ArgumentError P.build_plan(P.netlist(state, nothing))
        t.hasRω = false
        for (field, value) in ((:Rₚ, -1.0), (:Cₜ, NaN), (:n, Inf), (
            :organization, :unsupported))
            previous = getproperty(t, field)
            setproperty!(t, field, value)
            @test_throws ArgumentError P.build_plan(P.netlist(state, nothing))
            setproperty!(t, field, previous)
        end
    end
end

@testset "PSCAD transformer solved winding ratings" begin
    for organization in (:YY, :ΔY)
        state = transformer_network(; organization, Rₘ = Inf, Lₘ = Inf)
        state = NetworkBuilder.NetworkState(state.elements, state.topology,
            merge(state.options, (; voltageBase = 220 / sqrt(3))))
        source = withinputs(state.elements.source; v = 16.5 * sqrt(2 / 3), theta = 0.0)
        state = NetworkBuilder.NetworkState(merge(state.elements, (; source)),
            state.topology, state.options)
        t = state.elements[:line]
        # IEEE9 t1 winding parameters, on a common base far above its primary.
        t.n = 16.5 / 230
        t.Rₚ = t.Rₛ = 0.0
        t.Lₚ = 4.9916e-4 / 2
        t.Lₛ = 0.097 / 2
        t.V₁ᵒ = 16.5e3 / sqrt(3)
        t.V₂ᵒ = 230e3 / sqrt(3)
        pf = PSCADFixtures.solved_powerflow(state)
        @test string(pf.result["termination_status"]) == "LOCALLY_SOLVED"
        # Open-circuit metadata must not supply the exported winding ratings.
        t.V₁ᵒ = t.V₂ᵒ = 0.0
        plan = P.build_plan(P.netlist(state, pf))
        winding = only(filter(c -> c.defn == "master:xfmr-3p2w", plan.main.components))
        params = Dict(winding.params)
        @test params["V1"] == "16.5 [kV]"
        @test params["V2"] == "230.0 [kV]"
        @test params["Ideal"] == (organization == :YY ? "0" : "1")
        @test params["Tmva"] == "1000 [MVA]"
        @test params["Xl"] == "0.0001 [pu]"
        @test params["Im1"] == "0.001 [%]"
    end
end

@testset "PSCAD DC sources, paths and references" begin
    state = dc_network()
    plan = P.build_plan(P.netlist(state, nothing); name = "dc")
    @test plan_shape(plan) ==
          plan_shape(P.build_plan(P.netlist(state, nothing); name = "dc"))
    check_layout(plan, 9)
    @test counts(plan)["master:source_1"] == 4
    @test counts(plan)["master:resistor"] == 3
    @test counts(plan)["master:inductor"] == 2
    @test counts(plan)["master:ground"] == 5
    @test counts(plan)["master:ammeter"] == 6
    @test [c.name for c in plan.probes.channels] ==
          ["I_ac_ac", "I_from_dc", "I_to_dc", "I_line_side1", "I_line_side2",
        "I_ac_load_side1", "V_BUS1", "V_D1_P", "V_D1_N", "V_D2_P", "V_D2_N"]
    @test all(c -> c.dim == 1, filter(c -> c.bus != "BUS1", plan.probes.channels))
    @test plan_shape(plan) ==
          plan_shape(P.build_plan(P.netlist(state, nothing); name = "dc",
              dc_reference = :none))
    circuit = electrical_nodes(plan)
    for (name, bus, magnitude) in (("from", "D1", "320.0 [kV]"), ("to", "D2", "318.0 [kV]")),
        pole in ("P", "N")

        source = only(filter(
            c -> c.defn == "master:source_1" && Dict(c.params)["Name"] == name * "_" * pole,
            plan.main.components))
        @test Dict(source.params) == Dict("Name" => name * "_" * pole,
            "AC" => "0", "Type" => "6", "Grnd" => "0", "Cntrl" => "0",
            "Vm" => magnitude, "Tc" => "0.05 [s]", "Ph" => "0.0 [deg]", "f" => "50.0 [Hz]")
        # Positive NA of the P source faces its series meter; the N source's
        # positive NA is grounded, its negative NB faces the negative bus.
        if pole == "P"
            meter = only(filter(
                c -> c.defn == "master:ammeter" && Dict(c.params)["Name"] == "I_$(name)_dc",
                plan.main.components))
            @test circuit.root((source.x - 36, source.y)) ==
                  circuit.root((meter.x + 36, meter.y))
            @test circuit.root((meter.x, meter.y)) ==
                  circuit.root(circuit.labels[bus * "_P"])
            @test circuit.root((source.x + 36, source.y)) ==
                  circuit.root(circuit.labels["ground"])
        else
            @test circuit.root((source.x - 36, source.y)) ==
                  circuit.root(circuit.labels["ground"])
            @test circuit.root((source.x + 36, source.y)) ==
                  circuit.root(circuit.labels[bus * "_N"])
        end
    end
    @test count(c -> c.defn == "master:resistor" && Dict(c.params)["R"] == "1.0 [ohm]", plan.main.components) ==
          2
    @test all(c -> Dict(c.params)["L"] == "0.025 [H]",
        filter(c -> c.defn == "master:inductor", plan.main.components))
    # Solved voltages override source setpoints without changing the input.
    solved = PSCADFixtures.solved_powerflow(deepcopy(state))
    shifted = deepcopy(solved)
    shifted.result["solution"]["busdc"]["1"]["vm"] = 1.02
    shifted_plan = P.build_plan(P.netlist(state, shifted))
    @test all(c -> Dict(c.params)["Vm"] == "326.4 [kV]",
        filter(
            c -> c.defn == "master:source_1" && startswith(Dict(c.params)["Name"], "from"),
            shifted_plan.main.components))
    # Remove the receiving source: the receiving bus gets two local references.
    elements = (; ac = state.elements.ac, from = state.elements.from,
        line = state.elements.line, ac_load = state.elements.ac_load)
    NB = NetworkBuilder
    rows = (NB.Bus(:AC; ports = ((:ac, :ac), (:ac_load, :side1)), domain = ACDQ),
        NB.Bus(:gnd; ports = ((:ac_load, :side2),), domain = ACDQ),
        NB.Bus(:D1; ports = ((:from, :dc), (:line, :side1))),
        NB.Bus(:D2; ports = ((:line, :side2),)))
    floating = NB.define(elements, rows; options = state.options)
    reference = P.build_plan(P.netlist(floating, nothing))
    no_reference = P.build_plan(P.netlist(floating, nothing); dc_reference = :none)
    check_layout(reference, 10)
    @test counts(reference)["master:resistor"] ==
          counts(no_reference)["master:resistor"] + 2
    resistors = filter(
        c -> c.defn == "master:resistor" && occursin("reference", Dict(c.params)["Name"]),
        reference.main.components)
    @test length(resistors) == 2
    @test all(c -> Dict(c.params)["R"] == "1.0E7 [ohm]", resistors)
    @test_throws ArgumentError P.build_plan(P.netlist(floating, nothing); dc_reference = :invalid)
    # Add a grounded parallel RC shunt. It suppresses local references and
    # doubles C / halves R in both poles without invoking unsupported PF.
    load = impedance(; z = s -> inv(inv(400.0) + s * 1e-6), pins = 1)
    shunt_elements = merge(elements, (; load))
    shunt_rows = (rows..., NB.Net(:D2; terminals = ((:load, :side1, :dc),)),
        NB.Net(:gnd_dc; terminals = ((:load, :side2, :dc),)))
    shunt = NetworkBuilder.define(shunt_elements, shunt_rows; options = state.options)
    shunt_plan = P.build_plan(P.netlist(shunt, nothing))
    check_layout(shunt_plan, 10)
    @test !any(c -> occursin("reference", get(Dict(c.params), "Name", "")), shunt_plan.main.components)
    @test count(c -> c.defn == "master:resistor" && Dict(c.params)["R"] == "200.0 [ohm]",
        shunt_plan.main.components) == 2
    @test count(c -> c.defn == "master:capacitor" && Dict(c.params)["C"] == "2.0 [uF]",
        shunt_plan.main.components) == 2
    @test only(filter(c -> c.element == "load", shunt_plan.probes.channels)).dim == 1
end

@testset "PSCAD export requires extension before power flow" begin
    @test Base.get_extension(PowerImpedance, :PowerImpedancePSCADExt) === nothing
    state = small_ac_network()
    initial = inputvalues(state.elements.source)
    mktempdir() do root
        path = joinpath(root, "fixture.pscx")
        for net in (state,)
            caught = try
                export_pscad(net; path)
            catch e
                e
            end
            @test caught isa ArgumentError
            @test occursin("export_pscad requires PythonCall", sprint(showerror, caught))
            @test !isfile(path)
        end
        @test inputvalues(state.elements.source) === initial
        @test_throws ArgumentError export_pscad(state; path, dc_reference = :other)
        @test_throws ArgumentError export_pscad(state; path, line_options = Dict())
        @test_throws ArgumentError export_pscad(state; path, line_options = (;
            UnknownField = 1))
        @test_throws ArgumentError export_pscad(state; path = joinpath(root, "fixture.xml"))
        @test_throws ArgumentError export_pscad(state; path = joinpath(root, "missing",
            "fixture.pscx"))
        @test_throws ArgumentError export_pscad(state; path, name = "different")
        write(path, "existing project")
        @test_throws ArgumentError export_pscad(state; path)
        @test inputvalues(state.elements.source) === initial
        @test read(path, String) == "existing project"
    end
end
end
