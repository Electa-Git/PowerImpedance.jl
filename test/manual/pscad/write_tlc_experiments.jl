# Local experiment generation only. Run in an environment with PythonCall.
using PowerImpedance, PythonCall
include("../../pscad/fixtures.jl")
const P = PowerImpedance.PSCAD
const EXPERIMENTS = mkpath("/tmp/pscad-tlc-experiments")
const SETTINGS = P.SimulationSettings(simulation_time = 10.0,
    time_step = 10e-6, sample_step = 40e-6)

for (case, factory) in (("tlc_case1", PSCADFixtures.tlc_case1_network),
    ("tlc_case2", PSCADFixtures.tlc_case2_network))
    fixture = factory()
    for (representation, network) in (("builder", fixture),)
        name = case * "_" * representation
        model = export_pscad(network; path = joinpath(EXPERIMENTS, name * ".pscx"),
            settings = SETTINGS, dc_reference = :none)
        converter = only(filter(e -> e.model isa PowerImpedance.TLC, model.netlist.elements))
        equilibrium = P.converter_equilibrium(converter)
        flow = model.operating_point.branch_flows[converter.name]
        open(joinpath(EXPERIMENTS, name * "_reference.tsv"), "w") do io
            println(io, "quantity\tvalue\tunit")
            println(io, "P_network\t", flow.pt, "\tMW")
            println(io, "Q_network\t", flow.qt, "\tMVAr")
            println(io, "P_ac_f\t", flow.pt / converter.model.bases.S, "\tpu")
            println(io, "Q_ac_f\t", flow.qt / converter.model.bases.S, "\tpu")
            println(io, "v_dc_f\t", equilibrium.outputs.meas.v_dc_f, "\tpu")
            println(io, "omega_c\t", equilibrium.outputs.sync.ω_c, "\tpu")
            for (state, value) in pairs(equilibrium.states)
                println(io, state, '\t', value, "\tstate")
            end
        end
    end
end

# Primitive experiment with only the established converter channel suffixes.
# Each prefix identifies the primitive under test; there are no electrical ports.
name = "tlc_primitives"
abc = P.abc_to_dq_module("ABC_DQ")
dq = P.dq_to_abc_module("DQ_ABC")
graph = P.BlockGraph(P.ControlBlock[
    P.Const(P.Signal("one"), 1.0), P.Const(P.Signal("two"), 2.0),
    P.Const(P.Signal("three"), 3.0),
    P.Integrator(P.Signal("two"), P.Signal("Integral_P_ac_f"), 1.0, 0.5, -1.0, 1.0),
    P.Mult(P.Signal("two"), P.Signal("three"), P.Signal("Product_P_ac_f")),
    P.Div(P.Signal("three"), P.Signal("two"), P.Signal("Divide_P_ac_f")),
    P.Const(P.Signal("angle"), π / 6),
    P.Trig(P.Signal("angle"), P.Signal("Trig_P_ac_f"), :sin),
    P.Trig(P.Signal("angle"), P.Signal("Trig_Q_ac_f"), :cos),
    P.Square(P.Signal("three"), P.Signal("Square_P_ac_f")),
    P.Sqrt(P.Signal("Square_P_ac_f"), P.Signal("Square_Q_ac_f")),
    P.RealPole(P.Signal("one"), P.Signal("Pole_P_ac_f"), 1.0, 0.01, 0.4),
    P.SecondOrder(
        P.Signal("one"), P.Signal("Filter_P_ac_f"), 10000.0, 100sqrt(2), 0.4, 0.2),
    P.TimeStep(P.Signal("experiment_clock_s")),
    P.Delay(P.Signal("experiment_clock_s"), P.Signal("Delay_P_ac_f"), 200e-6, 21, 0.7),
    P.ArrayMerge(P.Signal.(["two", "three"]), P.Signal("array")),
    P.ArraySplit(P.Signal("array"), P.Signal("Array_P_ac_f"), 1),
    P.ArraySplit(P.Signal("array"), P.Signal("Array_Q_ac_f"), 2),
    P.Const(P.Signal("zero"), 0.0)])
# Independent balanced phase constants at a known 0.37 rad cosine phase.
for (i, phase) in enumerate((0.0, -2π / 3, 2π / 3))
    push!(graph.nodes, P.Const(P.Signal("phase$i"), cos(0.37 + phase)))
end
append!(graph.nodes,
    P.ControlBlock[
        P.ArrayMerge(P.Signal.(["phase1", "phase2", "phase3"]), P.Signal("phases")),
        P.AbcToDq(P.Signal("phases"), P.Signal("zero"), P.Signal("dq"), name * ":ABC_DQ"),
        P.ArraySplit(P.Signal("dq"), P.Signal("Frame_P_ac_f"), 1),
        P.ArraySplit(P.Signal("dq"), P.Signal("Frame_Q_ac_f"), 2),
        P.DqToAbc(P.Signal("dq"), P.Signal("zero"), P.Signal("inverse"), name * ":DQ_ABC"),
        P.ArraySplit(P.Signal("inverse"), P.Signal("Frame_v_dc_f"), 1)])
canvas = P.lower!(P.CanvasPlan(), graph)
probes = P.ProbeChannel[]
for (i, signal) in enumerate((
    "Integral_P_ac_f", "Product_P_ac_f", "Divide_P_ac_f", "Trig_P_ac_f", "Trig_Q_ac_f",
    "Square_P_ac_f", "Square_Q_ac_f", "Pole_P_ac_f", "Filter_P_ac_f",
    "Delay_P_ac_f", "Array_P_ac_f", "Array_Q_ac_f",
    "Frame_P_ac_f", "Frame_Q_ac_f", "Frame_v_dc_f"))
    P.output_probe!(canvas, signal, "experiment", "pu", (4320, 108 + 144 * (i - 1)))
    push!(probes, P.ProbeChannel(
        signal, :converter_diagnostic, nothing, nothing, nothing, 1, "pu"))
end
settings = P.SimulationSettings(simulation_time = 1.0, time_step = 10e-6, sample_step = 40e-6)
plan = P.ProjectPlan(name, "TLC primitive station checks",
    P._project_settings(settings, "TLC primitive station checks"),
    canvas, P.AbstractLineDefinitionPlan[], P.AbstractLineWrapperPlan[],
    [abc, dq], P.ProbeManifest(probes, nothing))
P._write_project(plan, joinpath(EXPERIMENTS, name * ".pscx"))

# Isolate division by zero so a build/run error does not hide other checks.
name = "tlc_startup_divider"
canvas = P.lower!(P.CanvasPlan(),
    P.BlockGraph(P.ControlBlock[
        P.Const(P.Signal("quarter"), 0.25), P.TimeStep(P.Signal("experiment_clock_s")),
        P.Div(P.Signal("quarter"), P.Signal("experiment_clock_s"), P.Signal("Startup_P_ac_f"))]))
P.output_probe!(canvas, "Startup_P_ac_f", "experiment", "pu", (720, 108))
manifest = P.ProbeManifest(
    [P.ProbeChannel("Startup_P_ac_f", :converter_diagnostic,
        nothing, nothing, nothing, 1, "pu")],
    nothing)
plan = P.ProjectPlan(name, "Native divider startup check",
    P._project_settings(settings, "Native divider startup check"),
    canvas, P.AbstractLineDefinitionPlan[], P.AbstractLineWrapperPlan[],
    P.ModuleDefinitionPlan[], manifest)
P._write_project(plan, joinpath(EXPERIMENTS, name * ".pscx"))

# Confirm current-source direction independently of converter feedback.
name = "tlc_dc_injection"
canvas = P.CanvasPlan()
push!(canvas.components,
    P.ComponentPlan("master:src_ccin_1",
        ["Name" => "injection", "Cntrl" => "1", "Tc" => "0.0 [s]"], 180, 108, 1))
positive = P.pscad_name("injection_positive"; used = canvas.used)
P.stub!(canvas, (180, 108), positive)
P.stub!(canvas, (180, 144), nothing)
P.component!(canvas, "resistor", (324, 108), ["Name" => "load", "R" => "10000.0 [ohm]"])
P.stub!(canvas, (324, 108), positive; direction = -1)
P.stub!(canvas, (360, 108), nothing)
P.component!(canvas, "voltmetergnd", (324, 180), ["Name" => "V_DC_P"])
P.stub!(canvas, (324, 180), positive; direction = -1)
P.component!(canvas, "voltmetergnd", (432, 180), ["Name" => "V_DC_N"])
P.stub!(canvas, (432, 180), nothing)
P.lower!(canvas, P.Const(P.Signal("command"), 0.01), (72, 216))
P.module_signal_stub!(canvas, (144, 108), "command", -1)
for (i, signal) in enumerate(("V_DC_P", "V_DC_N"))
    P.output_probe!(canvas, signal, "bus", "kV", (576, 108 + 72 * (i - 1)))
end
manifest = P.ProbeManifest(
    [P.ProbeChannel(n, :voltage, "DC", nothing, side, 1, "kV")
     for (n, side) in (("V_DC_P", "P"), ("V_DC_N", "N"))],
    nothing)
plan = P.ProjectPlan(name, "DC current source direction check",
    P._project_settings(settings, "DC current source direction check"),
    canvas, P.AbstractLineDefinitionPlan[], P.AbstractLineWrapperPlan[],
    P.ModuleDefinitionPlan[], manifest)
P._write_project(plan, joinpath(EXPERIMENTS, name * ".pscx"))
