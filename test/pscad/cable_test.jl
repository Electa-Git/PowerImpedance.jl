module PSCADCableTests
using Test, PowerImpedance
using ..PSCADFixtures: dc_cable_network, small_ac_network
using ..PSCADPlanTests: plan_shape, counts, check_layout
const P = PowerImpedance.PSCAD

@testset "PSCAD short cable warning" begin
    state = dc_cable_network()
    state.elements[:line].length = 100.0
    settings = P.SimulationSettings(time_step = 10e-6)
    @test_logs (:warn, r"cable :line, length 100.0 m, time step 1.0e-5 s: PSCAD aborts if the travel time is below the step") begin
        P.build_plan(P.netlist(state, nothing); settings)
    end
end

@testset "PSCAD cable row and DC interfaces" begin
    state = dc_cable_network()
    builder = state
    list = P.netlist(state, nothing)
    plan = P.build_plan(list; name = "dc_cable")
    @test length(plan.lines) == length(plan.wrappers) == 1
    row, wrapper = only(plan.lines), only(plan.wrappers)
    @test row isa P.CableDefinitionPlan
    @test wrapper isa P.CableWrapperPlan
    @test row.name == wrapper.row == "line_row"
    @test length(row.cables) == 2
    @test Dict(wrapper.params) == Dict("Name" => "line", "Freq" => "0.0 [Hz]",
        "Length" => "50.0 [km]", "Dim" => "0", "Mode" => "0", "CoupleEnab" => "0",
        "CoupleName" => "row", "CoupleOffset" => "0.0 [m]", "CoupleRef" => "0",
        "gen_cnst" => "1", "const_path" => "", "Date" => "0", "R" => "", "X" => "", "B" => "",
        "tname" => "tandem_segment", "sfault" => "0", "linc" => "10.0 [km]", "steps" => "3")
    # Independent expected material slots copied from the example, including
    # the absent fourth pair. The outer-layer inner radii have no extra slots.
    material = Dict("Name" => "line", "OHC" => "0", "Y" => "1 [m]", "Y2" => "0.0 [m]",
        "ShuntA" => "1.0E-38 [mho/m]", "FLT" => "50.0 [Hz]", "RorT" => "0",
        "LL" => "5", "SHRad" => "1", "LC" => "2", "CROSSBOND" => "0",
        "SemiCL" => "0", "SL1" => "0.0 [m]", "SL2" => "0.0 [m]",
        "CONNAM1" => "C1", "R1" => "0 [m]", "R2" => "0.02622 [m]",
        "RHOC" => "2.354E-8 [ohm*m]", "PERMC" => "1.035", "R3" => "0.06006 [m]",
        "EPS1" => "2.67", "PERM1" => "1.469", "LT1" => "0.0",
        "CONNAM2" => "C2", "R4" => "0.06336 [m]", "RHOS" => "2.14E-7 [ohm*m]",
        "PERMS" => "1.0", "R5" => "0.06636 [m]", "EPS2" => "2.3", "PERM2" => "1.0",
        "LT2" => "0.0", "elim1" => "1", "CONNAM3" => "C3", "R6" => "0.06651 [m]",
        "RHOA" => "2.826E-8 [ohm*m]", "PERMA" => "1.0", "R7" => "0.07256 [m]",
        "EPS3" => "2.3", "PERM3" => "1.0", "LT3" => "0.0", "elim2" => "1",
        "CONNAM4" => "none", "R8" => "0.0 [m]", "RHOO" => "0.0 [ohm*m]",
        "PERMO" => "0.0", "R9" => "0.0 [m]", "EPS4" => "0.0", "PERM4" => "0.0",
        "LT4" => "0.0", "elim3" => "0")
    for (i, cable) in enumerate(row.cables)
        @test cable.defn == "master:Cable_Coax"
        @test (cable.x, cable.y, cable.orient) == (396 + 396 * (i - 1), 522, 0)
        @test length(unique(first.(cable.params))) == length(cable.params)
        @test Dict(cable.params) == merge(material, Dict("CABNUM" => string(i),
            "X" => i == 1 ? "-0.5 [m]" : "0.5 [m]"))
    end
    @test Dict(row.ground) ==
          Dict("EarthForm2" => "0", "EarthForm" => "2", "EarthForm3" => "2",
        "GrRho" => "0", "GRRES" => "100.0 [ohm*m]", "GPERM" => "1", "GRP" => "1")
    @test Dict(row.frephase) == Dict("Interp1" => "1", "Output" => "0", "Inflen" => "0",
        "FS" => "0.001 [Hz]", "FE" => "1000000.0 [Hz]", "Numf" => "100",
        "YMaxP" => "20", "YMaxE" => "0.02 [%]", "AMaxP" => "20", "AMaxE" => "0.02 [%]",
        "MaxRPtol" => "2000000.0", "CPASS" => "0", "DCenab" => "0", "DCCOR" => "1", "enablf" => "1")
    @test Dict(row.outdisp) == Dict("DataF" => "50.0 [Hz]")
    altered = only(P.build_plan(list;
        line_options = (; GRRES = 250.0, GPERM = 1.2,
            GRP = 5.0, FS = 2.0, Numf = 200, YMaxE = 0.3, AMaxE = "0.4 [%]", DCenab = 1)).lines)
    @test Dict(altered.ground)["GRRES"] == "250.0 [ohm*m]"
    @test Dict(altered.ground)["GPERM"] == "1.2"
    @test Dict(altered.ground)["GRP"] == "5.0"
    @test Dict(altered.frephase)["FS"] == "2.0 [Hz]"
    @test Dict(altered.frephase)["Numf"] == "200"
    @test Dict(altered.frephase)["DCenab"] == "1"
    @test Dict(altered.frephase)["YMaxE"] == "0.3 [%]"
    @test Dict(altered.frephase)["AMaxE"] == "0.4 [%]"
    interfaces = filter(c -> c.defn == "master:cable_interface", plan.main.components)
    @test length(interfaces) == 2
    @test [c.orient for c in interfaces] == [0, 4]
    for (side, interface) in enumerate(interfaces)
        expected = Dict(
            "Name" => "line", "NCAB" => "2", "pipe" => "0", "dim_s" => "0", "dim_r" => "0",
            "GroundS" => "0", "GroundA" => "0", "GroundOC" => "0", "ResS" => "0.001 [ohm]",
            "ResA" => "0.001 [ohm]", "ResOC" => "0.001 [ohm]", "send_recv" => "0",
            "recv_default_type" => "0", "recv_default" => "0")
        merge!(expected, Dict("C$(i)T" => "1" for i in 1:12))
        @test Dict(interface.params) == expected
        direction = side == 1 ? -1 : 1
        for (i, pole) in enumerate(("P", "N"))
            port = (interface.x + 18direction, interface.y + 54 * (i - 1))
            endpoint = (
                port[1] + direction * (i == 1 ? 72 : 36), port[2] - (i == 1 ? 36 : 0))
            label = only(filter(
                c -> c.defn == "master:nodelabel" && (c.x, c.y) == endpoint,
                plan.main.components))
            @test Dict(label.params)["Name"] == "D$(side)_$pole"
            if i == 1
                meter = only(filter(
                    c -> c.defn == "master:ammeter" &&
                         Dict(c.params)["Name"] == "I_line_side$side",
                    plan.main.components))
                @test (meter.x, meter.y) ==
                      (port[1] + 36direction, port[2] - 36)
            end
        end
    end
    probes = filter(c -> c.element == "line", plan.probes.channels)
    @test [(c.name, c.port, c.dim, c.unit) for c in probes] ==
          [("I_line_side1", :side1, 1, "kA"), ("I_line_side2", :side2, 1, "kA")]
    check_layout(plan, 10)
    cable = state.elements[:line]
    cable.eliminate = false
    caught = try
        P.build_plan(P.netlist(state, nothing))
    catch e
        e
    end
    @test caught isa ArgumentError
    @test occursin(":line", sprint(showerror, caught))
    @test occursin("eliminate=false", sprint(showerror, caught))
    cable.eliminate = true
    # The fourth donor slot exercises material pairs beyond the first three layers.
    cable.conductors[:C4] = Conductor(rᵢ = 0.07256, rₒ = 0.074, ρ = 1.8e-7, μᵣ = 400.0)
    cable.insulators[:I4] = Insulator(rᵢ = 0.074, rₒ = 0.08, ϵᵣ = 4.0, μᵣ = 2.0)
    fourth = Dict(first(only(P.build_plan(P.netlist(state, nothing)).lines).cables).params)
    @test all(fourth[k] == v
    for (k, v) in Dict("LL" => "7", "CONNAM4" => "C4", "R8" => "0.074 [m]",
        "R9" => "0.08 [m]", "RHOO" => "1.8E-7 [ohm*m]", "PERMO" => "400.0", "EPS4" => "4.0",
        "PERM4" => "2.0", "LT4" => "0.0", "elim3" => "1"))
end

@testset "PSCAD cable AC phase connections" begin
    state = small_ac_network()
    dc = dc_cable_network()
    model = deepcopy(dc.elements[:line])
    model.positions = [(-0.5, 1.0), (0.0, 1.0), (0.5, 1.0)]
    state = NetworkBuilder.NetworkState(merge(state.elements, (; line = model)),
        state.topology, state.options)
    plan = P.build_plan(P.netlist(state, nothing))
    @test length(only(plan.lines).cables) == 3
    @test Dict(only(plan.lines).frephase)["FS"] == "0.5 [Hz]"
    @test Dict(only(plan.wrappers).params)["Freq"] == "50.0 [Hz]"
    @test counts(plan)["master:breakout"] == 2
    @test all(c -> c.dim == 3, filter(c -> c.element == "line", plan.probes.channels))
    for side in 1:2, phase in ("A", "B", "C")

        @test count(
            c -> c.defn == "master:nodelabel" &&
                 Dict(c.params)["Name"] == "line_$(side)_$phase",
            plan.main.components) == 2
    end
    check_layout(plan, 9)
    model.type = :aerial
    aerial = Dict(first(only(P.build_plan(P.netlist(state, nothing)).lines).cables).params)
    @test aerial["OHC"] == "1"
    @test aerial["Y"] == "0.0 [m]"
    @test aerial["Y2"] == "1.0 [m]"
end
end
