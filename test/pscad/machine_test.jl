module PSCADMachineTests
using Test, PowerImpedance
using ..PSCADFixtures: sm_network
const P = PowerImpedance.PSCAD

components(canvas, defn) = filter(c -> c.defn == "master:" * defn, canvas.components)
parameters(canvas, defn) = Dict(only(components(canvas, defn)).params)
function parameter_import(canvas, name)
    only(filter(
        c -> Dict(c.params)["Name"] == name, components(canvas, "import")))
end

function pin_signal(canvas, point)
    wire = only(filter(w -> point in w.vertices, canvas.wires))
    endpoint = only(filter(!=(point), wire.vertices))
    label = only(filter(
        c -> c.defn == "master:datalabel" &&
             (c.x, c.y) == endpoint, canvas.components))
    return Dict(label.params)["Name"]
end

@testset "PSCAD scalar block lowering" begin
    a, b, c, d = P.Signal.(["a", "b", "c", "d"])
    graph = P.BlockGraph(P.ControlBlock[
        P.Import("input", a), P.Const(b, 2.0), P.Sum([a, b], [1, -1], c),
        P.Gain(c, d, "K"), P.RealPole(d, a, 1.5, 0.2, 0.3),
        P.LeadLag(a, b, 0.1, 1.0, 0.5), P.Limit(b, c, -2.0, 3.0),
        P.Export("output", c), P.TimeStep(d), P.Compare(d, a, 0.5)])
    canvas = P.lower!(P.CanvasPlan(), graph)
    blocks = filter(c -> c.defn != "master:datalabel", canvas.components)
    @test [(c.x, c.y) for c in blocks] ==
          [(72 + 108 * ((i - 1) ÷ 4), 72 + 72 * ((i - 1) % 4)) for i in 1:10]
    @test all(w -> sum(abs.(w.vertices[2] .- w.vertices[1])) == 36, canvas.wires)
    @test parameters(canvas, "gain") == Dict("G" => "K", "Dim" => "1", "DPath" => "1")
    pole = parameters(canvas, "realpole")
    @test pole["G"] == "1.5"
    @test pole["T"] == "0.2 [s]"
    @test pole["YO"] == "0.3"
    @test pole["Reset"] == "2"
    @test pole["Limit"] == "0"
    lead = parameters(canvas, "leadlag")
    @test (lead["T1"], lead["T2"], lead["YO"]) == ("0.1 [s]", "1.0 [s]", "0.5")
    junction = parameters(canvas, "sumjct")
    @test [junction[string(pin)] for pin in 'A':'G'] == ["0", "0", "0", "1", "0", "-1", "0"]
    @test parameters(canvas, "hardlimit") ==
          Dict("UL" => "3.0", "LL" => "-2.0", "Dim" => "1")
    @test parameters(canvas, "compare") == Dict("X" => "0.5", "OL" => "0", "OH" => "1",
        "INTR" => "0", "Dim" => "1", "conv" => "1")
    @test parameters(canvas, "import")["Name"] == "input"
    @test parameters(canvas, "export")["Name"] == "output"
    @test isempty(only(components(canvas, "time-sig")).params)
    @test_throws ArgumentError P.Signal("bad signal")
    @test_throws ArgumentError P.Sum([a, b], [1, 0], c)
    @test_throws ArgumentError P.ModulePortPlan("x", :unknown, 0, 0)
    @test_throws ArgumentError P.ModulePortPlan("x", :input, 1, 0)
    for value in ("vref", "Tm0", "1.0")
        @test_throws MethodError P.Const(b, value)
    end
    for expression in ("vref-Vt0", "K_A*(vref-Vt0)", "1/R")
        @test_throws ArgumentError P.lower!(P.CanvasPlan(),
            P.BlockGraph(P.ControlBlock[P.Gain(a, b, expression)]))
    end
end

@testset "PSCAD shared module parameter bindings" begin
    input, reference, sum, scaled, output = P.Signal.([
        "input", "reference_signal", "sum", "scaled", "output"])
    graph = P.BlockGraph(P.ControlBlock[
        P.Import("input", input), P.Import("reference", reference),
        P.Sum([input, reference], [1, 1], sum), P.Gain(sum, scaled, "K"),
        P.RealPole(scaled, output, "K", "T", "Y0"), P.Export("output", output)])
    canvas = P.lower!(P.CanvasPlan(), graph)
    original = copy(canvas.components)
    parameters = P.ModuleParameterPlan[
        P.ModuleParameterPlan("reference", 0.7, ""),
        P.ModuleParameterPlan("K", 3.5, ""),
        P.ModuleParameterPlan("T", 0.2, "s"),
        P.ModuleParameterPlan("Y0", -0.4, ""),
        P.ModuleParameterPlan("unused", 4.0, ""),
        P.ModuleParameterPlan("Count", 2, ""),
        P.ModuleParameterPlan("Caption", "control", "")]
    definition = P.ModuleDefinitionPlan("Control", parameters,
        [P.ModulePortPlan("input", :input, -54, 0),
            P.ModulePortPlan("output", :output, 54, 0)], canvas)
    # Construction leaves the source canvas intact and binds all Input form
    # parameters, including repeated coefficients and an existing signal import.
    @test canvas.components == original
    @test definition.canvas !== canvas
    imports = components(definition.canvas, "import")
    @test Set(Dict(c.params)["Name"] for c in imports) ==
          Set(vcat("input", [p.name for p in parameters]))
    @test length(imports) == length(parameters) + 1
    for parameter in parameters
        @test parameter_import(definition.canvas, parameter.name).params ==
              ["Name" => parameter.name]
    end
    source = parameter_import(definition.canvas, "reference")
    @test (source.x, source.y, source.orient) == (72, 144, 0)
    @test pin_signal(definition.canvas, (source.x + 36, source.y)) == "reference_signal"
    coefficients = imports[3:end]
    @test [(c.x, c.y, c.orient) for c in coefficients] ==
          [(540 + 108 * ((i - 1) ÷ 4), 72 + 72 * ((i - 1) % 4), 0)
           for i in eachindex(coefficients)]
    @test all(
        c -> !any(w -> (c.x + 36, c.y) in w.vertices,
            definition.canvas.wires), coefficients)
    @test length(definition.canvas.wires) == length(canvas.wires)
    before = copy(definition.canvas.components)
    P.lower!(definition.canvas, parameters)
    @test definition.canvas.components == before
    # Place imports beyond wider converter graphs without changing the spacing.
    wide = P.lower!(P.CanvasPlan(),
        P.BlockGraph(P.ControlBlock[P.Gain(input, output, "K")]); origin = (720, 72))
    wide = P.ModuleDefinitionPlan("Wide", parameters, P.ModulePortPlan[], wide).canvas
    @test parameter_import(wide, "reference").x == 864
end

@testset "PSCAD controller parameter ownership" begin
    @test P.SM_AVR_FIELD_VOLTAGE_SCALE == 1.0
    machine = SynchronousMachine(ElectricalSM(),
        MechanicalSM(
            T_CH = 0.7, T_RH = 3.1, T_CO = 0.4, F_HP = 0.2, F_IP = 0.5, F_LP = 0.3),
        AVRSM(vref_SG = 1.02, T_R = 0.03, T_B = 0.8, T_C = 0.12, T_A = 0.04, K_A = 123.0),
        GovernorSM(T_w = 0.15, T_G = 0.25, R = 0.04))
    avr = P.machine_avr("AVR_custom", machine, 0.99)
    gov = P.machine_governor("GOV_custom", machine, 0.72)
    @test Dict(p.name => p.default for p in avr.parameters) == Dict(
        "vref" => 1.02, "T_R" => 0.03, "T_B" => 0.8, "T_C" => 0.12,
        "T_A" => 0.04, "K_A" => 123.0, "Vt0" => 0.99,
        "Verror0" => 1.02 - 0.99, "Vreg0" => 123.0 * (1.02 - 0.99),
        "Ef_scale" => P.SM_AVR_FIELD_VOLTAGE_SCALE)
    @test Dict(p.name => p.default for p in gov.parameters) == Dict(
        "T_w" => 0.15, "T_G" => 0.25, "R" => 0.04, "inv_R" => 25.0, "T_CH" => 0.7,
        "T_RH" => 3.1, "T_CO" => 0.4, "F_HP" => 0.2, "F_IP" => 0.5,
        "F_LP" => 0.3, "Tm0" => 0.72)
    @test only(filter(p -> p.name == "Verror0", avr.parameters)).default ≈ 0.03
    @test only(filter(p -> p.name == "Vreg0", avr.parameters)).default ≈ 3.69
    @test parameters(avr.canvas, "leadlag")["YO"] == "Verror0"
    @test [Dict(c.params)["YO"] for c in components(avr.canvas, "realpole")] ==
          ["Vt0", "Vreg0"]
    @test Dict(first(components(gov.canvas, "gain")).params)["G"] == "inv_R"
    # Every scalar block value must be numeric or a declared module parameter.
    for definition in (avr, gov)
        names = Set(p.name for p in definition.parameters)
        imports = components(definition.canvas, "import")
        @test Set(Dict(c.params)["Name"] for c in imports) ==
              union(names, Set(p.name for p in definition.ports if p.kind == :input))
        @test length(imports) == length(names) + 1
        for name in names
            @test parameter_import(definition.canvas, name).params == ["Name" => name]
        end
        for component in definition.canvas.components, (key, value) in component.params

            key == "Name" && continue
            literal = first(split(value))
            @test tryparse(Float64, literal) !== nothing || value in names
        end
    end
end

@testset "PSCAD synchronous machine plan" begin
    @test P.SM_IRON_LOSS_RESISTANCE_PU == 1.0e6
    classic, state = sm_network()
    pf = power_flow(classic)
    solved = NetworkBuilder.solve(state)
    classic_netlist = P.netlist(classic, pf)
    builder_netlist = P.netlist(state, solved.powerflow)
    settings = P.SimulationSettings(simulation_time = 5.0)
    plans = [P.build_plan(n; name = "sm", settings)
             for n in (classic_netlist, builder_netlist)]
    @test !isempty(builder_netlist.operating_point.bus_states)
    @test_throws ArgumentError P.build_plan(P.netlist(state, nothing))
    for plan in plans
        machine = parameters(plan.main, "sync_machine")
        @test machine["Name"] == "sg1"
        @test machine["Cnfg"] == "1"
        @test machine["Nqaxw"] == "2"
        @test (machine["View"], machine["Neut"], machine["Term"]) == ("1", "0", "1")
        @test (machine["IorMVA"], machine["VolTyp"], machine["icTyp"]) == ("1", "1", "1")
        @test machine["MVA"] == "1000.0 [MVA]"
        @test machine["VbaseLL"] == "380.0 [kV]"
        @test machine["OMO"] == P.pscad_value(100π; unit = "rad/s")
        @test machine["H"] == "4.0 [s]"
        @test machine["D"] == "0.0 [pu]"
        @test machine["Ri"] == "1000000.0 [pu]"
        @test count(p -> first(p) == "Ri", only(components(plan.main, "sync_machine")).params) ==
              1
        @test machine["P0"] == "900.0 [MW]"
        @test (machine["Trmpv"], machine["Sysfl"], machine["Ptcon"]) ==
              ("0.01 [s]", "15.0 [pu]", "0.05 [s]")
        @test machine["Iexc"] == machine["Igov"] == "1"
        @test machine["Icsp"] == machine["Icmp"] == "0"
        @test machine["Ts"] == "0.0 [s]"
        @test machine["machsw"] == "sg1_S2M"
        @test machine["Enab"] == "sg1_L2N"
        @test machine["InExc"] == "sg1_InitEx"
        @test machine["InGov"] == "sg1_InitGv"
        @test machine["POut"] == "sg1_P_pu"
        @test machine["QOut"] == "sg1_Q_pu"
        # Independent values from the validated fundamental-circuit fixture.
        for (key, value) in ("Rs1" => 0.0015, "XS1" => 0.15, "XMD0" => 1.66,
            "R2D" => 0.0002, "X2D" => 0.165, "R3D" => 0.02, "X3D" => 0.1713,
            "X230" => 0.0, "XMQ" => 1.61, "R2Q" => 0.005, "X2Q" => 0.7252,
            "R3Q" => 0.01, "X3Q" => 0.125, "X231" => 0.0)
            @test machine[key] == P.pscad_value(value; unit = "pu")
        end
        resistor = parameters(plan.main, "resistor")
        inductor = parameters(plan.main, "inductor")
        @test resistor["R"] == "0.37544 [ohm]"
        @test inductor["L"] == P.pscad_value(9.386 / (100π); unit = "H")
        @test Set(m.name for m in plan.modules) == Set(["AVR_sg1", "GOV_sg1"])
        instances = filter(c -> c isa P.ModuleInstancePlan, plan.main.components)
        @test Set(c.defn for c in instances) == Set(["sm:AVR_sg1", "sm:GOV_sg1"])
        for definition in plan.modules
            @test length(definition.ports) == 2
            @test [(p.kind, p.x, p.y, p.dim, p.datatype) for p in definition.ports] ==
                  [(:input, -54, 0, 1, 3), (:output, 54, 0, 1, 3)]
            instance = only(filter(c -> c.defn == "sm:" * definition.name, instances))
            @test Set(keys(Dict(instance.params))) ==
                  Set(p.name for p in definition.parameters)
            @test Dict(parameter_import(definition.canvas,
                definition.ports[1].name).params)["Name"] == definition.ports[1].name
            @test parameters(definition.canvas, "export")["Name"] ==
                  definition.ports[2].name
            labels = Dict((c.x, c.y) => Dict(c.params)["Name"]
            for c in components(definition.canvas, "datalabel"))
            # Different signals must not be joined by compact-grid stubs,
            # including endpoint contact between neighboring rows.
            for (i, first) in enumerate(definition.canvas.wires),
                second in definition.canvas.wires[(i + 1):end]

                a, b = first.vertices
                c, d = second.vertices
                a[1] == c[1] || continue
                touching = max(min(a[2], b[2]), min(c[2], d[2])) <=
                           min(max(a[2], b[2]), max(c[2], d[2]))
                if touching
                    @test labels[b] == labels[d]
                end
            end
        end
        avr = only(filter(m -> m.name == "AVR_sg1", plan.modules))
        gov = only(filter(m -> m.name == "GOV_sg1", plan.modules))
        @test [(p.name, p.default, p.unit) for p in avr.parameters][1:6] ==
              [("vref", 1.01, ""), ("T_R", 0.05, "s"), ("T_B", 1.0, "s"),
            ("T_C", 0.1, "s"), ("T_A", 0.02, "s"), ("K_A", 200.0, "")]
        @test parameters(avr.canvas, "leadlag")["T1"] == "T_C"
        @test parameters(avr.canvas, "leadlag")["T2"] == "T_B"
        @test parameters(avr.canvas, "gain")["G"] == "Ef_scale"
        @test length(components(avr.canvas, "realpole")) == 2
        @test [Dict(c.params)["T"] for c in components(gov.canvas, "realpole")] ==
              ["T_w", "T_G", "T_CH", "T_RH", "T_CO"]
        @test [Dict(c.params)["YO"] for c in components(gov.canvas, "realpole")] ==
              ["0.0", "Tm0", "Tm0", "Tm0", "Tm0"]
        @test [Dict(c.params)["G"] for c in components(gov.canvas, "gain")] ==
              ["inv_R", "F_HP", "F_IP", "F_LP"]
        @test only(filter(p -> p.name == "Tm0", gov.parameters)).default ≈ 0.9
        @test isempty(components(avr.canvas, "const"))
        @test parameters(gov.canvas, "const")["Value"] == "1.0"
        for definition in plan.modules
            names = Set(p.name for p in definition.parameters)
            references = Set(value for c in definition.canvas.components
            for (key, value) in c.params if key != "Name" && value in names)
            @test !isempty(references)
            for name in references
                @test parameter_import(definition.canvas, name).params == ["Name" => name]
            end
            for c in components(definition.canvas, "const")
                @test tryparse(Float64, Dict(c.params)["Value"]) !== nothing
            end
        end
        # Inspect named connections at the master's actual pins, including the
        # governor error sign and the three turbine fractions.
        sums = components(gov.canvas, "sumjct")
        vref = parameter_import(avr.canvas, "vref")
        @test pin_signal(avr.canvas, (vref.x + 36, vref.y)) == "vref_signal"
        avr_sum = only(components(avr.canvas, "sumjct"))
        @test pin_signal(avr.canvas, (avr_sum.x - 36, avr_sum.y)) == "vref_signal"
        tm0 = parameter_import(gov.canvas, "Tm0")
        @test pin_signal(gov.canvas, (tm0.x + 36, tm0.y)) == "torque_ref"
        @test pin_signal(gov.canvas, (sums[2].x, sums[2].y + 36)) == "torque_ref"
        @test pin_signal(gov.canvas, (sums[1].x - 36, sums[1].y)) == "one"
        @test pin_signal(gov.canvas, (sums[1].x, sums[1].y + 36)) == "speed"
        @test Dict(sums[1].params)["F"] == "-1"
        @test pin_signal(gov.canvas, (sums[3].x - 36, sums[3].y)) == "T_HP"
        @test pin_signal(gov.canvas, (sums[3].x, sums[3].y + 36)) == "T_IP"
        @test pin_signal(gov.canvas, (sums[3].x, sums[3].y - 36)) == "T_LP"
        @test Set(Dict(c.params)["X"] for c in components(plan.main, "compare")) ==
              Set(["0.5", "1.0"])
        @test length(components(plan.main, "time-sig")) == 1
        @test length(plan.probes.channels) ==
              length(unique(c.name for c in plan.probes.channels))
        @test Set(c.name for c in plan.probes.channels) == Set([
            "V_Bus2", "I_g2_1", "I_sg1_1", "sg1_P", "sg1_Q", "sg1_Vt", "sg1_speed",
            "sg1_Ef0", "sg1_Ef", "sg1_Tm_init"])
    end
    flow = classic_netlist.operating_point.branch_flows[:sg1]
    # Terminal and bus voltages differ across rt+j*lt; neither may replace the other.
    terminal_voltage = flow.terminal_voltage_kV * cis(flow.terminal_angle_rad)
    current = conj(complex(flow.pg, flow.qg) / (3terminal_voltage))
    z = complex(0.0026, 0.065) * 380^2 / 1000
    @test terminal_voltage - z * current ≈ 380 / sqrt(3) rtol = 1e-8
    @test flow.pf ≈ flow.pg - 3abs2(current) * real(z) rtol = 1e-8
    # Preserve the raw solved reactive power, including its feasibility
    # residual, rather than replacing it with an analytically balanced value.
    branch_index = string(pf[4][:sg1][2])
    @test flow.qf == -Float64(pf[1]["solution"]["branch"][branch_index]["qt"]) * 1000
    @test flow.terminal_voltage_kV != only(classic_netlist.buses).vm_pu * 380 / sqrt(3)
    machine = parameters(plans[1].main, "sync_machine")
    @test machine["VT"] == P.pscad_value(abs(terminal_voltage) * sqrt(3) / 380; unit = "pu")
    @test machine["Pheta"] == P.pscad_value(angle(terminal_voltage) + π / 2; unit = "rad")
    @test machine["Q0"] == P.pscad_value(flow.qg; unit = "MVAR")
    @test builder_netlist.operating_point.branch_flows[:sg1].pg ≈ flow.pg
    @test builder_netlist.operating_point.branch_flows[:sg1].qg ≈ flow.qg
end

end
