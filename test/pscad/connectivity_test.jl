module PSCADConnectivityTests
import ..PSCADFixtures
using Test, PowerImpedance
using ..PSCADFixtures
const P = PowerImpedance.PSCAD

function rejects(canvas, coordinates)
    err = try
        P.check_connectivity(canvas, "test_canvas")
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("test_canvas", sprint(showerror, err))
    @test occursin(string(coordinates), sprint(showerror, err))
end

function remove_pin!(canvas, pin)
    wire = only(filter(w -> pin in w.vertices, canvas.wires))
    label = only(filter(!=(pin), wire.vertices))
    filter!(w -> w !== wire, canvas.wires)
    filter!(c -> (c.x, c.y) != label, canvas.components)
    return nothing
end

@testset "PSCAD input completeness and signal drivers" begin
    # Independent pin locations come from the saved canvas rather than the rewiring table:
    # local/TLC/Simple_2L_VSC_RL.pscx:2214–2238 (orient-4 N=2 merge), 2937–2961 (ABC
    # merge), 2164–2184,2384–2398 (N=3 merge/dot), and the abutted trig/sum/gain pins in
    # the complete canvases at 1851–3234.
    merge = P.ComponentPlan("master:datamerge", ["N" => "2"], 612, 162, 4)
    @test P.component_ports(merge, Dict()) ==
          [((594, 90), :signal, :input), ((594, 108), :signal, :input),
        ((612, 144), :signal, :output)]
    merge3 = P.ComponentPlan("master:datamerge", ["N" => "3"], 702, 342, 4)
    @test P.component_ports(merge3, Dict()) ==
          [((684, 270), :signal, :input), ((684, 288), :signal, :input),
        ((684, 306), :signal, :input), ((702, 342), :signal, :output)]
    trig = P.ComponentPlan("master:trig", Pair{String, String}[], 324, 216, 0)
    @test P.component_ports(trig, Dict()) ==
          [((288, 216), :signal, :input), ((360, 216), :signal, :output)]

    # These independently recorded nets correspond to six station messages. The last
    # message identifies the output label on the middle dot product; its reader is A2 of
    # the three-input merge. A missing driver is rejected even when the label and reader
    # wire remain geometrically valid.
    cases = ((:abc, (90, 702), (1224, 108), "transform_node_10"),
        (:abc, (720, 756), (1224, 324), "transform_node_16"),
        (:dq, (306, 468), (1224, 324), "transform_node_16"),
        (:dq, (288, 756), (1224, 540), "transform_node_24"),
        (:dq, (504, 972), (1224, 108), "transform_node_9"),
        (:dq, (954, 270), (1224, 756), "transform_node_15"))
    for (kind, reader, writer, signal) in cases
        module_plan = kind == :abc ? P.abc_to_dq_module("ABC_DQ") :
                      P.dq_to_abc_module("DQ_ABC")
        canvas = module_plan.canvas
        @test P.check_connectivity(canvas, module_plan.name) === nothing
        label_names = Dict((c.x, c.y) => Dict(c.params)["Name"]
        for c in canvas.components if c.defn == "master:datalabel")
        for pin in (reader, writer)
            wire = only(filter(w -> pin in w.vertices, canvas.wires))
            @test label_names[only(filter(!=(pin), wire.vertices))] == signal
        end
        missing_input = deepcopy(canvas)
        remove_pin!(missing_input, reader)
        rejects(missing_input, reader)

        undriven = deepcopy(canvas)
        remove_pin!(undriven, writer)
        rejects(undriven, reader)

        multiple = deepcopy(canvas)
        # Signal names and driver identity are case-insensitive, as in Fortran.
        P.lower!(multiple, P.Const(P.Signal(uppercase(signal)), 1.0), (1512, 1188))
        rejects(multiple, reader)
    end

    dangling = P.CanvasPlan()
    P.component!(dangling, "datalabel", (108, 108), ["Name" => "undriven"])
    rejects(dangling, (108, 108))
    electrical = P.CanvasPlan()
    P.component!(electrical, "resistor", (108, 108))
    rejects(electrical, (108, 108))

    # Coefficient-only imports use names in block fields, as in saved AVR/GOV canvases.
    # Module signal imports have wired output stubs.
    coefficients = P.CanvasPlan()
    P.component!(coefficients, "import", (108, 108), ["Name" => "gain_parameter"])
    @test P.check_connectivity(coefficients, "coefficient") === nothing
    input = P.CanvasPlan()
    P.lower!(input, P.Import("module_input", P.Signal("input_signal")), (108, 108))
    P.lower!(input, P.Export("module_output", P.Signal("INPUT_SIGNAL")), (324, 108))
    @test P.check_connectivity(input, "module_input") === nothing
end

@testset "PSCAD named-node connectivity" begin
    canvas = P.CanvasPlan()
    P.component!(canvas, "resistor", (108, 108), ["R" => "1.0 [ohm]"])
    P.stub!(canvas, (108, 108), "left"; direction = -1)
    P.stub!(canvas, (144, 108), nothing)
    @test P.check_connectivity(canvas, "valid") === nothing

    segmented = P.CanvasPlan(copy(canvas.components), deepcopy(canvas.wires))
    push!(segmented.wires[1].vertices, (72, 144))
    rejects(segmented, (108, 108))

    abutted = P.CanvasPlan(copy(canvas.components), copy(canvas.wires))
    P.component!(abutted, "inductor", (144, 108), ["L" => "1.0 [H]"])
    rejects(abutted, (144, 108))

    joined = P.CanvasPlan()
    P.component!(joined, "resistor", (108, 108))
    P.component!(joined, "resistor", (216, 108))
    P.wire!(joined, (144, 108), (216, 108))
    rejects(joined, (144, 108))

    label_wire = P.CanvasPlan()
    P.label!(label_wire, "a", (108, 108))
    P.label!(label_wire, "b", (144, 108))
    P.wire!(label_wire, (108, 108), (144, 108))
    rejects(label_wire, (108, 108))

    junction = P.CanvasPlan()
    P.component!(junction, "voltmetergnd", (108, 108))
    P.label!(junction, "bus", (180, 108))
    P.wire!(junction, (108, 108), (180, 108))
    P.component!(junction, "voltmetergnd", (144, 144))
    P.label!(junction, "bus", (144, 108))
    P.wire!(junction, (144, 144), (144, 108))
    rejects(junction, (144, 108))

    crossing = P.CanvasPlan()
    P.component!(crossing, "voltmetergnd", (108, 108))
    P.label!(crossing, "horizontal", (180, 108))
    P.wire!(crossing, (108, 108), (180, 108))
    P.component!(crossing, "voltmetergnd", (144, 72))
    P.label!(crossing, "vertical", (144, 144))
    P.wire!(crossing, (144, 72), (144, 144))
    rejects(crossing, (144, 108))

    shared = P.CanvasPlan(copy(canvas.components), copy(canvas.wires))
    P.component!(shared, "voltmetergnd", (72, 144))
    P.wire!(shared, (72, 144), (72, 108))
    rejects(shared, (72, 108))

    unknown = P.CanvasPlan()
    P.component!(unknown, "unknown", (108, 108))
    rejects(unknown, (108, 108))

    wrong_kind = P.CanvasPlan()
    P.component!(wrong_kind, "gain", (108, 108), ["G" => "1"])
    P.stub!(wrong_kind, (72, 108), "bus"; direction = -1)
    rejects(wrong_kind, (72, 108))

    # Case-insensitive reservations also protect internal meter junctions.
    collision = P.CanvasPlan()
    P.component!(collision, "voltmetergnd", (108, 108), ["Name" => "I_BRANCH_NODE"])
    P.ammeter_stub!(collision, (108, 108), "bus", "I_branch")
    @test "I_branch_node_2" in
          [get(Dict(c.params), "Name", "") for c in collision.components]
    @test P.check_connectivity(collision, "reserved") === nothing

    # The xnode is explicitly wired, as in the saved VSC2L canvas at
    # local/TLC/Simple_2L_VSC_RL.pscx:3377–3382,5604–5613. Its internal node label
    # deliberately differs from the module port name.
    boundary = P.CanvasPlan()
    P.component!(boundary, "xnode", (108, 108), ["Name" => "AC"])
    P.stub!(boundary, (108, 108), "internal_ac"; direction = -1)
    @test P.check_connectivity(boundary, "boundary") === nothing

    for factory in (PSCADFixtures.small_ac_network, PSCADFixtures.passive_ohl_network,
        PSCADFixtures.transformer_network, () -> PSCADFixtures.transformer_network(;
        organization = :ΔY),
        PSCADFixtures.dc_network, PSCADFixtures.dc_cable_network,
        PSCADFixtures.sm_network, PSCADFixtures.tlc_case1_network, PSCADFixtures.tlc_case2_network)
        builder = factory()
        for network in (builder,)
            nonlinear = any(
                e -> e isa
                     Union{PowerImpedance.SynchronousMachine, PowerImpedance.TLC},
                values(builder.elements))
            pf = nonlinear ? compute(PowerFlowProblem(network), ACDCPowerFlow()) : nothing
            plan = P.build_plan(P.netlist(network, pf))
            @test P.check_connectivity(plan) === nothing
        end
    end
end
@testset "PSCAD isolated ideal-meter ground paths" begin
    classic = PSCADFixtures.transformer_network()
    plan = P.build_plan(P.netlist(classic, nothing))
    @test P.check_connectivity(plan) === nothing
    broken = deepcopy(plan.main)
    part = only(filter(c -> get(Dict(c.params), "Name", "") == "load_R", broken.components))
    meter = only(filter(
        c -> c.defn == "master:ammeter" && Dict(c.params)["Name"] == "I_load_side1",
        broken.components))
    function replace_end!(pin, node)
        wire = only(filter(w -> pin in w.vertices, broken.wires))
        point = only(filter(!=(pin), wire.vertices))
        i = only(findall(c -> (c.x, c.y) == point, broken.components))
        old = broken.components[i]
        broken.components[i] = P.ComponentPlan(
            node === nothing ? "master:ground" : "master:nodelabel",
            node === nothing ? Pair{String, String}[] : ["Name" => node], old.x, old.y, old.orient)
    end
    replace_end!((part.x, part.y), "I_load_side1_node")
    replace_end!((part.x + 36, part.y), nothing)
    replace_end!((meter.x, meter.y), "B2")
    replace_end!((meter.x + 36, meter.y), "I_load_side1_node")
    line_meter = only(filter(
        c -> c.defn == "master:ammeter" && Dict(c.params)["Name"] == "I_line_side2",
        broken.components))
    rejects(broken, (line_meter.x, line_meter.y))
    err = try
        P.check_connectivity(broken, "isolated_secondary")
        nothing
    catch e
        e
    end
    @test occursin("I_line_side2", sprint(showerror, err))
    @test occursin("I_load_side1", sprint(showerror, err))
    @test occursin("isolated part", sprint(showerror, err))

    three = deepcopy(broken)
    pin = (part.x, part.y)
    wire = only(filter(w -> pin in w.vertices, three.wires))
    point = only(filter(!=(pin), wire.vertices))
    i = only(findall(c -> (c.x, c.y) == point, three.components))
    label = three.components[i]
    three.components[i] = P.ComponentPlan(label.defn, ["Name" => "extra_meter_node"],
        label.x, label.y, label.orient)
    P.component!(three, "ammeter", (2808, 180), ["Name" => "I_return_1"])
    P.stub!(three, (2808, 180), "I_load_side1_node"; direction = -1)
    P.stub!(three, (2844, 180), "extra_meter_node")
    rejects(three, (line_meter.x, line_meter.y))
    @test_throws ArgumentError P.check_connectivity(three, "three_meters")

    single = deepcopy(broken)
    P.component!(single, "ammeter", (2808, 108), ["Name" => "I_return_1"])
    P.stub!(single, (2808, 108), "B2"; direction = -1)
    P.stub!(single, (2844, 108), nothing)
    @test P.check_connectivity(single, "alternate_single_meter_ground") === nothing

    # A direct return on that island, or a source on it, removes the trigger.
    direct = deepcopy(broken)
    P.component!(direct, "resistor", (2808, 108), ["R" => "1.0 [ohm]"])
    P.stub!(direct, (2808, 108), "B2"; direction = -1)
    P.stub!(direct, (2844, 108), nothing)
    @test P.check_connectivity(direct, "direct_ground") === nothing
    sourced = deepcopy(broken)
    P.component!(sourced, "source_3", (2808, 108), ["Grnd" => "1"])
    P.stub!(sourced, (2844, 108), "B2")
    @test P.check_connectivity(sourced, "grounded_source") === nothing

    # Source islands are identified before a single return meter is reduced to ground;
    # merging ground first could hide a source behind a meter chain.
    source_return = P.CanvasPlan()
    P.component!(source_return, "source_3", (108, 108), ["Grnd" => "1"])
    P.stub!(source_return, (144, 108), "source")
    P.component!(source_return, "resistor", (324, 108), ["R" => "400.0 [ohm]"])
    P.stub!(source_return, (324, 108), "source"; direction = -1)
    P.stub!(source_return, (360, 108), "return")
    for (x, left, right, signal) in ((540, "return", nothing, "I_return_1"),
        (756, "source", "middle", "I_branch_side1"), (
            972, "middle", "island", "I_branch_side2"))
        P.component!(source_return, "ammeter", (x, 108), ["Name" => signal])
        P.stub!(source_return, (x, 108), left; direction = -1)
        P.stub!(source_return, (x + 36, 108), right)
    end
    P.component!(source_return, "resistor", (1188, 108), ["R" => "1.0 [ohm]"])
    P.stub!(source_return, (1188, 108), "island"; direction = -1)
    P.stub!(source_return, (1224, 108), "end")
    @test P.check_connectivity(source_return, "source_return") === nothing

    # Voltage probes do not conduct; B2's existing V_B2 must not hide the chain.
    @test any(
        c -> c.defn == "master:voltmetergnd" &&
             get(Dict(c.params), "Name", "") == "V_B2",
        broken.components)
end

@testset "PSCAD coordinate bounds" begin
    canvas = P.CanvasPlan()
    push!(canvas.components, P.ComponentPlan("master:const", ["Name" => "edge", "Value" => "1"], 14382, 0, 0))
    @test P.check_connectivity(canvas, "edge") === nothing
    canvas.components[1] = P.ComponentPlan("master:const", ["Name" => "edge", "Value" => "1"], 14383, 0, 0)
    @test_throws r"coordinates must lie" P.check_connectivity(canvas, "edge")
    empty!(canvas.components)
    push!(canvas.wires, P.WirePlan([(0, 0), (0, -18)]))
    @test_throws r"coordinates must lie" P.check_connectivity(canvas, "edge")
end

end
