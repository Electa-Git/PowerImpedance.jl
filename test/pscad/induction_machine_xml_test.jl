@testset "Induction-machine XML fields and connections" begin
    reference = etree.parse(joinpath(@__DIR__, "fixtures/im_saved_fragments.xml")).getroot()
    form = only(reference.xpath("./Definition/form"))
    fields = Dict(pyconvert(String, p.get("name")) => p
        for p in form.xpath("./category/parameter"))
    saved = Dict(pyconvert(String, p.get("name")) => pyconvert(String, p.get("value"))
        for p in reference.xpath("./User/paramlist/param"))
    @test length(fields) == length(saved) == 81
    for (key, unit) in (("Pbase", "MVA"), ("Vbase", "kV"), ("Vwdg", "kV"),
        ("OMEG", "rad/s"), ("J", "s"), ("D", "pu"), ("R1", "pu"),
        ("R2", "pu"), ("Xmd", "pu"), ("Xa", "pu"), ("Xkd1", "pu"))
        @test pyconvert(String, fields[key].get("unit")) == unit
    end
    @test occursin("J=2H", pyconvert(String, fields["J"].get("desc")))
    @test pyconvert(String, fields["Vwdg"].find("cond").text) == "View==2"
    @test pyconvert(String, fields["NCW"].find("cond").text) == "Cage==1"
    @test pyconvert(String, fields["R3"].find("cond").text) == "NCW*Cage>=1"
    script = pyconvert(String, reference.xpath("string(./Definition/script/segment[@name='Dsdyn'])"))
    computations = pyconvert(String,
        reference.xpath("string(./Definition/script/segment[@name='Computations'])"))
    @test occursin("INTEGER NCW1=NCW*Cage", computations)
    @test occursin("#IF NCW1>0", script)
    @test occursin("#IF Lsat>0", script)
    @test occursin("#IF Msat==1", script)
    @test occursin("\$OMEG,\$J,\$D,\$TRN", script)
    @test occursin("#OUTPUT  REAL  TmOp", script)
    ports = Dict(pyconvert(String, p.get("name")) =>
        (parse(Int, pyconvert(String, p.get("x"))), parse(Int, pyconvert(String, p.get("y"))))
        for p in reference.xpath("./Definition/svg/port[@name='NS' or @name='SPI' or @name='SW' or @name='TMI']"))
    @test ports == Dict("NS" => (54, 0), "SPI" => (-54, -36),
        "SW" => (-54, 0), "TMI" => (-54, 36))
    @test pyconvert(String, only(reference.xpath("./Definition/svg/port[@name='SW']")).get("type")) == "Integer"
    pair = PSCADFixtures.im_network()
    settings = P.SimulationSettings(simulation_time = 10.0, time_step = 1e-6,
        sample_step = 250e-6, source_ramp = 0.05)
    for (kind, network) in pairs(pair)
        name = "im_" * string(kind)
        path = joinpath(only(ARGS), name * ".pscx")
        model = export_pscad(network; path, settings)
        plan = P.build_plan(model.netlist; name, settings)
        # Read every instance field through mhi-xml's component parameter API.
        project = mhixml.ProjectFile(path)
        machine = only(collect(project.canvas("Main").components(; defn = "master:wound_rotor")))
        expected = Dict(only(filter(c -> c.defn == "master:wound_rotor", plan.main.components)).params)
        @test Set(expected |> keys) == Set(keys(saved))
        for (key, value) in expected
            @test pyconvert(String, machine.params.get_param(key)) == value
        end
        @test pyconvert(String, machine.params.get_param("Spd")) == "im1_speed"
        @test pyconvert(String, machine.params.get_param("TmOp")) == "im1_Tm"
        @test pyconvert(String, machine.params.get_param("J")) == "8.0 [s]"
        @test pyconvert(String, machine.params.get_param("D")) == "0.0 [pu]"
        transfer = only(collect(project.canvas("Main").components(; defn = "master:compare")))
        for (key, value) in (("X", "0.2"), ("OL", "1"), ("OH", "0"),
            ("INTR", "0"), ("Dim", "1"), ("conv", "1"))
            @test pyconvert(String, transfer.params.get_param(key)) == value
        end
        root = etree.parse(path).getroot()
        flow = model.operating_point.branch_flows[:im1]
        initial = only(collect(project.canvas("Main").components(; defn = "master:const")))
        @test pyconvert(String, initial.params.get_param("Value")) == P.pscad_value(flow.speed_pu)
        @test flow.speed_pu != 1.0
        @test pyconvert(Float64, project.parameters.time_step) == 1.0
        @test pyconvert(Float64, project.parameters.time_duration) == 10.0
        @test P.check_connectivity(path) === nothing
        @test P.check_geometry(path) === nothing
        @test P.check_connectivity(plan) === nothing
        summary = P.read_project_summary(path)
        @test Set(summary.pgbs) == Set(["V_machine_", "V_grid_", "I_g1_1", "I_im1_1",
            "I_imp_1", "I_imp_2", "im1_speed", "im1_Te", "im1_Tm"])
        load = only(root.xpath("./definitions/Definition[@name='LOAD_im1']"))
        for (key, value) in (("T_0", "0.9"), ("A", "0.0"), ("B", "0.0"), ("C", "1.0"))
            @test pyconvert(String, load.xpath("string(./form/category/parameter[@name='$key']/value)")) == value
            @test pylen(load.xpath("./schematic/User[@defn='master:import'][paramlist/param[@name='Name'][@value='$key']]")) == 1
        end
        # Remove the native speed output name; its controller input loses its driver.
        machine_node = only(root.xpath(".//User[@defn='master:wound_rotor']/paramlist/param[@name='Spd']"))
        machine_node.set("value", "")
        mktempdir() do directory
            broken = joinpath(directory, "missing_speed.pscx")
            root.getroottree().write(broken)
            @test_throws r"input signal im1_speed has 0 drivers" P.check_connectivity(broken)
        end
    end
end
