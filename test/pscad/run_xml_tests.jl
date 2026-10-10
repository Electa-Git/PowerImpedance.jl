# Local XML verification only; never contacts PSCAD.
# julia --startup-file=no --project test/pscad/run_xml_tests.jl [export_directory]
using Pkg
using Test

if get(ENV, "POWERIMPEDANCE_PSCAD_XML_CHILD", "0") != "1"
    repository = normpath(joinpath(@__DIR__, "../.."))
    exports = isempty(ARGS) ? mktempdir(; prefix = "pscad-xml-exports-") :
              abspath(only(ARGS))
    mkpath(exports)
    mktempdir(; prefix = "powerimpedance-pscad-xml-") do environment
        Pkg.activate(environment)
        withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
            Pkg.develop(Pkg.PackageSpec(path = repository))
            Pkg.add([Pkg.PackageSpec(name = "PythonCall", version = "0.9"),
                Pkg.PackageSpec(name = "CondaPkg", version = "0.2"),
                Pkg.PackageSpec(name = "Test")])
        end
        # CondaPkg discovers the developed package's CondaPkg.toml. Keep its
        # environment in this temporary Julia project, outside the repository.
        withenv("POWERIMPEDANCE_PSCAD_XML_CHILD" => "1",
            "JULIA_CONDAPKG_BACKEND" => "Pixi",
            "JULIA_CONDAPKG_ENV" => nothing,
            "JULIA_CONDAPKG_OFFLINE" => "no",
            "JULIA_PYTHONCALL_EXE" => nothing) do
            run(`$(Base.julia_cmd()) --startup-file=no --project=$environment $(@__FILE__) $exports`)
        end
    end
else
    using Test, PowerImpedance
    using CondaPkg
    started = time_ns()
    CondaPkg.resolve()
    println("CondaPkg resolution wall_seconds=", (time_ns() - started) * 1e-9)
    using PythonCall
    etree = pyimport("lxml.etree")
    mhixml = pyimport("mhi.xml.pscad")
    include("fixtures.jl")
    include("topology.jl")
    using TOML
    P = PowerImpedance.PSCAD
    # Compare actual pin connectivity against the independent saved fragments,
    # including their original abutments, multi-segment wires and T-junctions.
    function pin_partition(schematic)
        nodes = schematic.xpath("./User")
        components = P.AbstractComponentPlan[]
        labels = Tuple{Tuple{Int, Int}, String}[]
        for node in nodes
            defn = pyconvert(String, node.get("defn"))
            x, y = parse.(Int, pyconvert.(String, (node.get("x"), node.get("y"))))
            params = [pyconvert(String, p.get("name")) => pyconvert(String, p.get("value"))
                      for p in node.xpath("./paramlist/param")]
            if defn == "master:datalabel"
                push!(labels, ((x, y), lowercase(Dict(params)["Name"])))
            else
                push!(components,
                    P.ComponentPlan(defn, params, x, y,
                        parse(Int, pyconvert(String, node.get("orient")))))
            end
        end
        ports = [P.component_ports(c, Dict()) for c in components]
        parent = Dict{Tuple{Int, Int}, Tuple{Int, Int}}()
        root(p) = get!(parent, p, p) == p ? p : (parent[p] = root(parent[p]))
        join(a, b) = (parent[root(a)] = root(b))
        points = Set(p for pins in ports for (p, _) in pins)
        union!(points, first.(labels))
        segments = Tuple{Tuple{Int, Int}, Tuple{Int, Int}}[]
        for w in schematic.xpath("./Wire[@classid='WireOrthogonal']")
            x = parse(Int, pyconvert(String, w.get("x")))
            y = parse(Int, pyconvert(String, w.get("y")))
            vertices = [(x + parse(Int, pyconvert(String, v.get("x"))),
                            y + parse(Int, pyconvert(String, v.get("y"))))
                        for v in w.xpath("./vertex")]
            union!(points, vertices)
            append!(segments, zip(vertices[1:(end - 1)], vertices[2:end]))
        end
        for (a, b) in segments, p in points

            (a[1] == b[1] == p[1] && min(a[2], b[2]) <= p[2] <= max(a[2], b[2])) ||
                (a[2] == b[2] == p[2] && min(a[1], b[1]) <= p[1] <= max(a[1], b[1])) ||
                continue
            join(a, p)
        end
        named = Dict{String, Tuple{Int, Int}}()
        for (p, name) in labels
            haskey(named, name) ? join(p, named[name]) : (named[name] = p)
        end
        groups = Dict{Tuple{Int, Int}, Set{Tuple{Int, Int}}}()
        for (i, pins) in enumerate(ports), (j, (p, _)) in enumerate(pins)

            push!(get!(Set{Tuple{Int, Int}}, groups, root(p)), (i, j))
        end
        return Set(values(groups))
    end
    shunt_moves = TOML.parsefile(joinpath(@__DIR__, "fixtures/shunt_meter_moves.toml"))
    native_phasors = TOML.parsefile(joinpath(@__DIR__, "fixtures/yy_load_return_phasors.toml"))
    probe_names = Dict{String, Set{String}}()
    for line in readlines(joinpath(@__DIR__, "fixtures/export_probe_names.tsv"))
        startswith(line, "#") && continue
        line == "fixture\tprobe" && continue
        fixture, probe = split(line, '\t')
        push!(get!(Set{String}, probe_names, fixture), probe)
    end
    classic, state = PSCADFixtures.small_ac_network()
    ohl_classic, ohl_state = PSCADFixtures.passive_ohl_network()
    yy_classic, yy_state = PSCADFixtures.transformer_network()
    dy_classic, dy_state = PSCADFixtures.transformer_network(; organization = :ΔY)
    dc_classic, dc_state = PSCADFixtures.dc_network()
    cable_classic, cable_state = PSCADFixtures.dc_cable_network()
    sm_classic, sm_state = PSCADFixtures.sm_network()
    tlc1_classic, tlc1_state = PSCADFixtures.tlc_case1_network()
    tlc2_classic, tlc2_state = PSCADFixtures.tlc_case2_network()
    mmc_classic, mmc_state = PSCADFixtures.mmc_pq_network()
    modes = []
    for (stem, factory) in (("mmc_vdc", PSCADFixtures.mmc_vdc_network),
        ("mmc_pf", PSCADFixtures.mmc_pf_network), ("mmc_qv", PSCADFixtures.mmc_qv_network),
        ("mmc_vac", PSCADFixtures.mmc_vac_network), (
        "tlc_vac", PSCADFixtures.tlc_vac_network))
        fixture = factory()
        append!(modes, [
            (stem * "_classic", fixture.classic), (stem * "_builder", fixture.state)])
    end
    append!(modes, [("mmc_pq_default_ramp", mmc_classic),
        ("tlc_case2_zero_ramp", tlc2_classic)])
    modes_reference = etree.parse(joinpath(@__DIR__, "fixtures/mmc_modes_saved_fragments.xml")).getroot()
    reference_root = etree.parse(joinpath(@__DIR__,
        "fixtures/user_module_pscad5.xml")).getroot()
    reference_parameter = only(reference_root.xpath(
        "./definitions/Definition[@name='SG']/form/category/parameter[@name='kp_f']"))
    reference_svg = only(reference_root.xpath("./definitions/Definition[@name='SG']/svg"))
    reference_import = first(reference_root.xpath(
        "./definitions/Definition[@name='Untitled_6']/schematic/User[@defn='master:import']"))
    tlc_reference = etree.parse(joinpath(@__DIR__, "fixtures/tlc_saved_fragments.xml")).getroot()
    saved_fields = Dict{String, Set{String}}()
    for component in tlc_reference.xpath(".//User")
        defn = pyconvert(String, component.get("defn"))
        fields = get!(Set{String}, saved_fields, defn)
        union!(fields, [pyconvert(String, p.get("name"))
                        for p in component.xpath("./paramlist/param")])
    end
    mmc_reference = etree.parse(joinpath(@__DIR__, "fixtures/mmc_saved_fragments.xml")).getroot()
    for component in mmc_reference.xpath(".//User")
        defn = pyconvert(String, component.get("defn"))
        union!(get!(Set{String}, saved_fields, defn),
            [pyconvert(String, p.get("name")) for p in component.xpath("./paramlist/param")])
    end
    settings = P.SimulationSettings(simulation_time = 0.3, time_step = 50e-6,
        sample_step = 250e-6, snapshot_time = 0.2)
    @testset "PSCAD mhi-xml export round trip" begin
        models = PSCADModel[]
        for (name, input) in (("small_ac_classic", classic), ("small_ac_builder", state),
            ("passive_ohl_classic", ohl_classic), ("passive_ohl_builder", ohl_state),
            ("transformer_yy_classic", yy_classic), ("transformer_yy_builder", yy_state),
            ("transformer_dy_classic", dy_classic), ("transformer_dy_builder", dy_state),
            ("dc_classic", dc_classic), ("dc_builder", dc_state),
            ("dc_cable_classic", cable_classic), ("dc_cable_builder", cable_state),
            ("sm_classic", sm_classic), ("sm_builder", sm_state),
            ("tlc_case1_classic", tlc1_classic), ("tlc_case1_builder", tlc1_state),
            ("tlc_case2_classic", tlc2_classic), ("tlc_case2_builder", tlc2_state),
            ("mmc_pq_classic", mmc_classic), ("mmc_pq_builder", mmc_state), modes...)
            path = joinpath(only(ARGS), name * ".pscx")
            case_settings = startswith(name, "sm_") ?
                            P.SimulationSettings(simulation_time = 5.0) :
                            startswith(name, "tlc_") ?
                            P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
                sample_step = 40e-6, source_ramp = 0.05) :
                            startswith(name, "mmc_") ?
                            P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
                sample_step = 250e-6, source_ramp = 0.0) : settings
            if name == "mmc_pq_default_ramp"
                case_settings = P.SimulationSettings(simulation_time = 10.0,
                    time_step = 10e-6, sample_step = 250e-6)
            elseif name == "tlc_case2_zero_ramp"
                case_settings = P.SimulationSettings(simulation_time = 10.0,
                    time_step = 10e-6, sample_step = 40e-6, source_ramp = 0.0)
            end
            dc_reference = startswith(name, "mmc_vdc") ? :midpoint_resistors :
                           startswith(name, "tlc_") || startswith(name, "mmc_") ? :none :
                           :midpoint_resistors
            # ΔY XML checks exercise the selected station realization with no
            # legacy power-flow evidence; native comparison waits for dy-fix.
            model = startswith(name, "transformer_dy") ?
                    P._export_project(P.netlist(input, nothing), path, name, settings,
                false, (;), :midpoint_resistors) :
                    export_pscad(input; path, settings = case_settings, dc_reference)
            push!(models, model)
            plan = P.build_plan(model.netlist; settings = case_settings, name,
                description = "PowerImpedance.jl: $name", dc_reference)
            @test P.check_connectivity(plan) === nothing
            summary = P.read_project_summary(path)
            counts = Dict{String, Int}()
            for component in plan.main.components
                counts[component.defn] = get(counts, component.defn, 0) + 1
            end
            @test summary.version == "5.0.2"
            @test summary.components_per_defn == counts
            expected_rows = Dict(l.name => merge(
                                     Dict("master:Line_Ground" => 1,
                                         "master:Line_FrePhase_Options" => 1,
                                         "master:Line_Out_Disp" => 1),
                                     l isa P.CableDefinitionPlan ?
                                     Dict("master:Cable_Coax" => length(l.cables)) :
                                     Dict("master:Line_Tower_Universal" => 1))
            for l in plan.lines)
            @test summary.row_definitions == expected_rows
            @test summary.wrappers_per_defn ==
                  Dict(name * ":" * w.row => 1 for w in plan.wrappers)
            @test all(>=(2), values(summary.nodelabels))
            expected_labels = Dict{String, Int}()
            for component in plan.main.components
                component.defn == "master:nodelabel" || continue
                label = Dict(component.params)["Name"]
                expected_labels[label] = get(expected_labels, label, 0) + 1
            end
            @test summary.nodelabels == expected_labels
            if startswith(name, "small_ac") || startswith(name, "passive_ohl")
                @test summary.nodelabels["B1"] == summary.nodelabels["B2"] == 3
            end
            @test Set(summary.pgbs) == Set(c.name for c in plan.probes.channels)
            @test Set(summary.pgbs) == probe_names[name]
            @test Set(c.name for c in model.probes.channels) == probe_names[name]
            @test all(summary.settings[k] == v for (k, v) in plan.settings.params)
            @test model.project_path == path
            @test model.project_name == name
            @test model.provenance.source == :export
            @test model.provenance.powerimpedance_version ==
                  string(Base.pkgversion(PowerImpedance))
            @test model.provenance.mhi_xml_version == "1.3.0"
            @test model.provenance.resolved_powerflow ==
                  ((input isa Network && !startswith(name, "transformer_dy")) ||
                   (name == "sm_builder" || startswith(name, "tlc_") ||
                    startswith(name, "mmc_")))
            root = etree.parse(path).getroot()
            @testset "Electrical topology: $name" begin
                graphs = PSCADTopology.xml_graphs(root, x -> pyconvert(String, x); check_named = true)
                for (canvas, graph) in graphs
                    @test PSCADTopology.check_degrees(graph, "$name/$canvas") === nothing
                end
                if startswith(name, "mmc_") || startswith(name, "tlc_vac_")
                    modules = Dict(m.name => m for m in plan.modules)
                    canvases = Dict("Main" => plan.main, [m.name => m.canvas
                                                          for m in plan.modules]...)
                    @test Set(keys(graphs)) == union(Set(keys(canvases)),
                        Set(line.name for line in plan.lines))
                    for (canvas, schematic) in canvases
                        expected = PSCADTopology.electrical_graph(schematic, modules)
                        if canvas == "Main"
                            # Cable interfaces own the terminals. The graphical
                            # wrapper retains its physical length and row fields.
                            for wrapper in plan.wrappers
                                @test wrapper isa P.CableWrapperPlan
                                push!(expected["components"],
                                    Dict(
                                        "definition" => name * ":" * wrapper.row,
                                        "parameters" => Dict(wrapper.params)))
                            end
                        end
                        @test PSCADTopology.equivalent(graphs[canvas], expected)
                    end
                    for line in plan.lines
                        @test line isa P.CableDefinitionPlan
                        row = graphs[line.name]
                        @test isempty(row["nets"])
                        expected = [(c.defn, Dict(c.params)) for c in line.cables]
                        append!(expected,
                            [("master:Line_Ground", Dict(line.ground)),
                                ("master:Line_FrePhase_Options", Dict(line.frephase)),
                                ("master:Line_Out_Disp", Dict(line.outdisp))])
                        @test length(row["components"]) == length(expected)
                        for (definition, parameters) in expected
                            actual = only(filter(
                                c -> c["definition"] == definition &&
                                     (definition != "master:Cable_Coax" ||
                                      c["parameters"]["CABNUM"] == parameters["CABNUM"]),
                                row["components"]))
                            # MHI also serializes its defaults; every physical
                            # value supplied by the plan must survive unchanged.
                            @test all(get(actual["parameters"], k, nothing) == v
                            for (k, v) in parameters)
                        end
                    end
                elseif !startswith(name, "tlc_")
                    reference = TOML.parsefile(joinpath(@__DIR__,
                        "fixtures/topology_8be21ee", name * ".toml"))["canvases"]
                    @test Set(keys(graphs)) == Set(keys(reference))
                    for (canvas, graph) in graphs
                        expected = canvas == "Main" ?
                                   PSCADTopology.shunt_meter_returns(reference[canvas], shunt_moves[name]) :
                                   reference[canvas]
                        @test PSCADTopology.equivalent(expected, graph)
                        if canvas == "Main" && !isempty(shunt_moves[name])
                            println("Approved topology difference: ",
                                name, " ", shunt_moves[name],
                                " bus -> element -> meter -> ground; ordered current pins preserved")
                            @test !PSCADTopology.equivalent(reference[canvas], graph)
                        end
                    end
                end
                if name == "transformer_yy_classic"
                    # The exact station failure must fail the production check,
                    # even though its raw graph matches the old abutted export.
                    saved_broken = etree.parse(joinpath(@__DIR__, "fixtures/yy_named_broken.pscx")).getroot()
                    failure = try
                        PSCADTopology.xml_graphs(saved_broken, x -> pyconvert(String, x); check_named = true)
                        nothing
                    catch e
                        e
                    end
                    @test failure isa ArgumentError
                    @test occursin("isolated part", sprint(showerror, failure))
                    @test occursin("I_load_1", sprint(showerror, failure))
                    @test occursin("I_line_2", sprint(showerror, failure))
                    println("Rejected saved m4-bz1oQX YY: ", sprint(showerror, failure))
                    direction = PSCADTopology.shunt_meter_direction(graphs["Main"], "I_load_1", "load_R")
                    @test direction == 1
                    measured = direction .* complex.(
                        native_phasors["yy_named_load_return"]["peak_real_kA"],
                        native_phasors["yy_named_load_return"]["peak_imag_kA"])
                    expected = complex.(native_phasors["yy_ref"]["peak_real_kA"],
                        native_phasors["yy_ref"]["peak_imag_kA"])
                    for (value, reference_value) in zip(measured, expected)
                        @test isapprox(value, reference_value; rtol = 0.02)
                        @test abs(rad2deg(angle(value / reference_value))) <= 1.0
                    end
                    # Junction and ground loss are independent topology defects.
                    for defect in (:junction, :ground)
                        changed = pyimport("copy").deepcopy(root)
                        schematic = only(changed.xpath("./definitions/Definition[@name='Main']/schematic"))
                        if defect == :junction
                            label = first(schematic.xpath("./User[@defn='master:nodelabel']/paramlist/param[@name='Name'][@value='line_primary_junction_1']"))
                            label.set("value", "disconnected_junction")
                        else
                            ground = first(schematic.xpath("./User[@defn='master:ground']"))
                            ground.set("defn", "master:nodelabel")
                            etree.SubElement(only(ground.xpath("./paramlist")), "param";
                                name = "Name", value = "disconnected_ground")
                        end
                        broken = PSCADTopology.xml_graphs(changed, x -> pyconvert(String, x))["Main"]
                        @test !PSCADTopology.equivalent(graphs["Main"], broken)
                        @test_throws ArgumentError PSCADTopology.check_degrees(broken, "Main")
                    end
                    # Arbitrary renaming of all internal labels changes neither
                    # circuit parameters nor the electrical net partition.
                    renamed = pyimport("copy").deepcopy(root)
                    for label in renamed.xpath(".//User[@defn='master:nodelabel']/paramlist/param[@name='Name']")
                        label.set("value", "renamed_" *
                                           pyconvert(String, label.get("value")))
                    end
                    renamed_graph = PSCADTopology.xml_graphs(renamed, x -> pyconvert(String, x))["Main"]
                    @test PSCADTopology.equivalent(graphs["Main"], renamed_graph)
                end
            end
            reread = mhixml.ProjectFile(path)
            @test pylen(reread.canvas("Main").xpath("./User")) ==
                  length(plan.main.components)
            @test pyconvert(String, root.get("version")) == "5.0.2"
            @test pyconvert(Int, root.xpath("count(./definitions/Definition[@name='Main'])")) ==
                  1
            @test pyconvert(Int, root.xpath("count(./definitions/Definition[@classid='StationDefn'])")) ==
                  1
            @test pyconvert(Int, root.xpath("count(./definitions/Definition[@name='Main']/schematic/User)")) ==
                  length(plan.main.components)
            for (defn, count) in counts
                @test pyconvert(Int,
                    root.xpath("count(./definitions/Definition[@name='Main']/schematic/User[@defn='$defn'])")) ==
                      count
            end
            for (label, count) in expected_labels
                @test pyconvert(Int,
                    root.xpath("count(.//User[@defn='master:nodelabel']/paramlist/param[@name='Name'][@value='$label'])")) ==
                      count
            end
            for channel in model.probes.channels
                @test pyconvert(Int,
                    root.xpath("count(.//User[@defn='master:pgb']/paramlist/param[@name='Name'][@value='$(channel.name)'])")) ==
                      1
            end
            # Verify every coordinate, parameter and two-vertex wire survived
            # Python conversion; counts alone cannot detect pixel/grid mistakes.
            nodes = root.xpath("./definitions/Definition[@name='Main']/schematic/User")
            for (component, node) in zip(plan.main.components, nodes)
                @test pyconvert(String, node.get("defn")) == component.defn
                @test parse(Int, pyconvert(String, node.get("x"))) == component.x
                @test parse(Int, pyconvert(String, node.get("y"))) == component.y
                @test parse(Int, pyconvert(String, node.get("orient"))) == component.orient
                if component.defn == "master:sync_machine"
                    iron_loss = node.xpath("./paramlist/param[@name='Ri']")
                    @test pylen(iron_loss) == 1
                    @test pyconvert(String, only(iron_loss).get("value")) ==
                          "1000000.0 [pu]"
                end
                for (key, value) in component.params
                    @test pyconvert(String, node.xpath("string(./paramlist/param[@name='$key']/@value)")) ==
                          value
                end
            end
            wires = root.xpath("./definitions/Definition[@name='Main']/schematic/Wire[@classid='WireOrthogonal']")
            @test pylen(wires) == length(plan.main.wires)
            for (wire, node) in zip(plan.main.wires, wires)
                vertices = node.xpath("./vertex")
                @test pylen(vertices) == 2
                # mhi-xml stores vertex coordinates relative to the wire origin.
                origin = (parse(Int, pyconvert(String, node.get("x"))),
                    parse(Int, pyconvert(String, node.get("y"))))
                actual = [(origin[1] + parse(Int, pyconvert(String, v.get("x"))),
                              origin[2] + parse(Int, pyconvert(String, v.get("y"))))
                          for v in vertices]
                @test Set(actual) == Set(wire.vertices)
            end
            if startswith(name, "tlc_")
                saved_guard = only(tlc_reference.xpath("./User[@defn='master:compare']"))
                parent = only(filter(m -> startswith(m.name, "VSC_"), plan.modules))
                guarded = only(root.xpath("./definitions/Definition[@name='$(parent.name)']/schematic/User[@defn='master:compare']"))
                @test pyconvert(String, guarded.get("orient")) ==
                      pyconvert(String, saved_guard.get("orient"))
                for field in ("X", "OH", "INTR", "Dim", "conv")
                    @test pyconvert(String,
                        guarded.xpath("string(./paramlist/param[@name='$field']/@value)")) ==
                          pyconvert(String,
                        saved_guard.xpath("string(./paramlist/param[@name='$field']/@value)"))
                end
                converter = only(filter(e -> e.model isa PowerImpedance.TLC, model.netlist.elements))
                @test parse(Float64,
                    pyconvert(String, guarded.xpath("string(./paramlist/param[@name='OL']/@value)"))) ==
                      converter.model.elec.vDCbase
                @test pylen(root.xpath("./definitions/Definition[@name='$(parent.name)']/schematic/User[@defn='master:voltmeter'][paramlist/param[@name='Name'][@value='v_dc_m']]")) ==
                      1
                for label in root.xpath(".//User[@defn='master:datalabel']/paramlist/param[@name='Name']")
                    @test !(lowercase(pyconvert(String, label.get("value"))) in
                            P._EMTDC_RESERVED_SIGNALS)
                end
                # Every emitted master field must have a saved-project witness;
                # the fixture comments retain the exact source file and line.
                for definition in plan.modules, component in definition.canvas.components

                    component isa P.ComponentPlan || continue
                    @test haskey(saved_fields, component.defn)
                    @test Set(first.(component.params)) ⊆ saved_fields[component.defn]
                end
                for (saved_name, generated_name) in (("abc2dq_1", "ABC_DQ"), (
                    "dq2abc", "DQ_ABC"))
                    original = only(tlc_reference.xpath("./Definition[@name='$saved_name']"))
                    actual = only(root.xpath("./definitions/Definition[@name='$generated_name']"))
                    saved = original.xpath("./schematic/User[@defn!='master:datalabel']")
                    emitted = actual.xpath("./schematic/User[@defn!='master:datalabel']")
                    @test pylen(saved) == pylen(emitted)
                    for (a, b) in zip(saved, emitted)
                        for key in ("defn", "orient")
                            @test pyconvert(String, a.get(key)) ==
                                  pyconvert(String, b.get(key))
                        end
                        parameters_a = Dict(pyconvert(String, p.get("name")) =>
                                                pyconvert(String, p.get("value"))
                        for p in a.xpath("./paramlist/param"))
                        parameters_b = Dict(pyconvert(String, p.get("name")) =>
                                                pyconvert(String, p.get("value"))
                        for p in b.xpath("./paramlist/param"))
                        @test parameters_a == parameters_b
                    end
                    @test pin_partition(only(original.xpath("./schematic"))) ==
                          pin_partition(only(actual.xpath("./schematic")))
                end
            end
            if startswith(name, "mmc_")
                saved_guard = only(tlc_reference.xpath("./User[@defn='master:compare']"))
                for (module_name, count) in (("MEAS_DUT", 10), ("SIGMA_DUT", 4))
                    guards = root.xpath("./definitions/Definition[@name='$module_name']/schematic/User[@defn='master:compare']")
                    @test pylen(guards) == count
                    for guard in guards
                        @test pyconvert(String, guard.get("orient")) ==
                              pyconvert(String, saved_guard.get("orient"))
                        for field in ("X", "INTR", "Dim", "conv")
                            @test pyconvert(String,
                                guard.xpath("string(./paramlist/param[@name='$field']/@value)")) ==
                                  pyconvert(String,
                                saved_guard.xpath("string(./paramlist/param[@name='$field']/@value)"))
                        end
                        @test isfinite(P._pscad_number(pyconvert(String,
                            guard.xpath("string(./paramlist/param[@name='OL']/@value)"))))
                    end
                end
                for definition in plan.modules, component in definition.canvas.components

                    component isa P.ComponentPlan || continue
                    @test haskey(saved_fields, component.defn)
                    @test Set(first.(component.params)) ⊆ saved_fields[component.defn]
                end
                arm = only(root.xpath("./definitions/Definition[@name='ARM_DUT']"))
                for (defn, fields) in ((
                    "master:source_1", ("Type", "Grnd", "Spec", "Cntrl", "AC")),
                    ("master:integral", ("Extrn", "Reset", "Mthd")))
                    saved = only(mmc_reference.xpath("./User[@defn='$defn']"))
                    emitted = only(arm.xpath("./schematic/User[@defn='$defn']"))
                    for field in fields
                        @test pyconvert(String,
                            emitted.xpath("string(./paramlist/param[@name='$field']/@value)")) ==
                              pyconvert(String, saved.xpath("string(./paramlist/param[@name='$field']/@value)"))
                    end
                end
                for (defn, field, unit) in (("master:inductor", "L", "H"),
                    ("master:resistor", "R", "ohm"))
                    saved = only(mmc_reference.xpath("./User[@defn='$defn']"))
                    emitted = only(arm.xpath("./schematic/User[@defn='$defn']"))
                    values = [pyconvert(String,
                                  c.xpath("string(./paramlist/param[@name='$field']/@value)"))
                              for c in (saved, emitted)]
                    @test all(endswith(value, " [$unit]") for value in values)
                    @test P._pscad_number(replace(values[1], " [$unit]" => "")) ==
                          P._pscad_number(replace(values[2], " [$unit]" => ""))
                end
                source = only(mmc_reference.xpath("./User[@defn='master:source_1']"))
                params = [pyconvert(String, p.get("name")) =>
                              pyconvert(String, p.get("value"))
                          for p in source.xpath("./paramlist/param")]
                ports = P.component_ports(
                    P.ComponentPlan(
                        "master:source_1", params, 828, 450, 1), Dict())
                @test first.(ports) == [(828, 414), (828, 486), (792, 450)]
                @test pylen(root.xpath("./definitions/Definition[@name='MMC_DUT']/schematic/User[@defn='$name:ARM_DUT']")) ==
                      6
                @test pylen(root.xpath("./definitions/Definition[@name='ARM_DUT']/schematic/User[@defn='master:integral']")) ==
                      1
            end
            if startswith(name, "mmc_vdc") || startswith(name, "mmc_qv")
                vdc = startswith(name, "mmc_vdc")
                control = only(filter(m -> m.name == (vdc ? "VDCCTRL_DUT" : "QCTRL_DUT"), plan.modules))
                params = Dict(p.name => p.default for p in control.parameters)
                witness = only(modes_reference.xpath(vdc ?
                                                     "./Mode[@name='DVC-Mode']/User[@id='99546287']" :
                                                     "./Mode[@name='Q-V_Droop']/User[@id='961326560']"))
                for (generated, saved) in (vdc ? (("vdcKp", "Kpv"), ("vdcKi", "KiV")) :
                                           (("supportK", "Kd"), ("supportT", "wf")))
                    value = parse(Float64,
                        pyconvert(String,
                            witness.xpath("string(./paramlist/param[@name='$saved']/@value)")))
                    @test params[generated] == (saved == "wf" ? 1/value : value)
                end
            end
            if startswith(name, "mmc_vac") || startswith(name, "tlc_vac")
                control = only(filter(m -> m.name == "QCTRL_DUT", plan.modules))
                params = Dict(p.name => p.default for p in control.parameters)
                saved = only(modes_reference.xpath("./Mode[@name='VAC_Control']/User[@id='436923558']"))
                @test params["vacKp"] == parse(Float64,
                    pyconvert(String,
                        saved.xpath("string(./paramlist/param[@name='KpAC']/@value)")))
                @test params["vacKi"] == parse(Float64,
                    pyconvert(String,
                        saved.xpath("string(./paramlist/param[@name='KiAC']/@value)")))
                converter = only(filter(e -> e.name == :DUT, model.netlist.elements))
                equilibrium = P.converter_equilibrium(converter)
                @test params["vacI0"] == equilibrium.states.ξ_v_ac
                @test params["vac_reference"] ==
                      equilibrium.setpoint_pu.v_ac *
                      PowerImpedance.voltage_filter_ratio(converter.model)
                integrator = only(root.xpath("./definitions/Definition[@name='QCTRL_DUT']/schematic/User[@defn='master:integral']"))
                witness = only(modes_reference.xpath("./Mode[@name='VAC_Control']/User[@id='1112328997']"))
                for field in ("Extrn", "Reset", "Mthd")
                    @test pyconvert(String,
                        integrator.xpath("string(./paramlist/param[@name='$field']/@value)")) ==
                          pyconvert(String, witness.xpath("string(./paramlist/param[@name='$field']/@value)"))
                end
                @test pyconvert(String, integrator.xpath("string(./paramlist/param[@name='Yo']/@value)")) ==
                      "vacI0"
            end
            @test Set(keys(summary.modules_and_ports)) == Set(m.name for m in plan.modules)
            for definition in plan.modules
                ports = summary.modules_and_ports[definition.name]
                @test [(p.name, p.kind, p.x, p.y, p.dim, p.datatype) for p in ports] ==
                      [(p.name, p.kind, p.x, p.y, p.dim, p.datatype)
                       for p in definition.ports]
                reread_defn = reread.definition[definition.name]
                @test pyconvert(Bool, reread_defn.module)
                # Module canvas settings are explicit, with the independent
                # saved dq2abc witness at local/TLC/Simple_2L_VSC_RL.pscx:2069–2083.
                @test pylen(root.xpath("./definitions/Definition[@name='$(definition.name)']/schematic/paramlist")) ==
                      1
                canvas_settings = Dict(pyconvert(String, p.get("name")) =>
                                           pyconvert(String, p.get("value"))
                for p in root.xpath("./definitions/Definition[@name='$(definition.name)']/schematic/paramlist/param"))
                saved_settings = Dict(pyconvert(String, p.get("name")) =>
                                          pyconvert(String, p.get("value"))
                for p in tlc_reference.xpath("./Definition[@name='dq2abc']/schematic/paramlist/param"))
                @test canvas_settings == saved_settings
                xml = only(root.xpath("./definitions/Definition[@name='$(definition.name)']"))
                @test pylen(xml.xpath("./graphics")) == 0
                svg = only(xml.xpath("./svg"))
                @test pyconvert(String, svg.get("viewBox")) ==
                      pyconvert(String, reference_svg.get("viewBox"))
                @test pyconvert(String, svg.get("size")) ==
                      pyconvert(String, reference_svg.get("size"))
                @test pylen(svg.xpath("./port")) == length(definition.ports)
                for (port, node) in zip(definition.ports, svg.xpath("./port"))
                    mode = port.kind == :electrical ? "Electrical" :
                           port.kind == :input ? "Input" : "Output"
                    reference = first(reference_root.xpath(".//svg/port[@mode='$mode']"))
                    for key in ("model", "mode", "type", "internal")
                        @test pyconvert(String, node.get(key)) ==
                              pyconvert(String, reference.get(key))
                    end
                    @test pyconvert(String, node.text) == "true"
                end
                for parameter in definition.parameters
                    node = only(xml.xpath("./form/category/parameter[@name='$(parameter.name)']"))
                    @test pyconvert(String, node.get("type")) == "Real"
                    @test pyconvert(String, node.get("unit")) == parameter.unit
                    @test pyconvert(String, node.get("content_type")) == "Constant"
                    for key in ("intent", "dim", "helpmode", "group", "animate")
                        @test pyconvert(String, node.get(key)) ==
                              pyconvert(String, reference_parameter.get(key))
                    end
                    for key in ("min", "max")
                        @test parse(Float64, pyconvert(String, node.get(key))) ==
                              parse(Float64, pyconvert(String, reference_parameter.get(key)))
                    end
                    @test pylen(node.xpath("./cond")) == 1
                    @test pylen(node.xpath("./help")) == 1
                    @test pylen(node.xpath("./vis")) == 1
                    @test pyconvert(String, node.get("help_mode", "")) == ""
                    @test parse(Float64, pyconvert(String, node.find("value").text)) ==
                          parameter.default
                end
                nodes = xml.xpath("./schematic/User")
                import_nodes = xml.xpath("./schematic/User[@defn='master:import']")
                for parameter in definition.parameters
                    node = only(xml.xpath(
                        "./schematic/User[@defn='master:import'][paramlist/param[@name='Name'][@value='$(parameter.name)']]"))
                    saved_import = if definition.name in ("ABC_DQ", "DQ_ABC")
                        source = definition.name == "ABC_DQ" ? "abc2dq_1" : "dq2abc"
                        only(tlc_reference.xpath("./Definition[@name='$source']/schematic/User[@defn='master:import'][paramlist/param[@name='Name'][@value='$(parameter.name)']]"))
                    else
                        reference_import
                    end
                    for key in ("defn", "classid", "orient")
                        @test pyconvert(String, node.get(key)) ==
                              pyconvert(String, saved_import.get(key))
                    end
                    @test pylen(node.xpath("./paramlist/param")) ==
                          pylen(reference_import.xpath("./paramlist/param")) == 1
                    @test pyconvert(String,
                        only(node.xpath("./paramlist/param")).get("name")) == "Name"
                end
                @test pylen(import_nodes) ==
                      length(definition.parameters) +
                      count(p -> p.kind == :input, definition.ports)
                for node in xml.xpath("./schematic/User[@defn='master:const']")
                    value = pyconvert(String,
                        node.xpath("string(./paramlist/param[@name='Value']/@value)"))
                    @test tryparse(Float64, value) !== nothing
                end
                @test pylen(nodes) == length(definition.canvas.components)
                for (component, node) in zip(definition.canvas.components, nodes)
                    @test pyconvert(String, node.get("defn")) == component.defn
                    @test parse(Int, pyconvert(String, node.get("x"))) == component.x
                    @test parse(Int, pyconvert(String, node.get("y"))) == component.y
                    @test parse(Int, pyconvert(String, node.get("orient"))) ==
                          component.orient
                    for (key, value) in component.params
                        @test pyconvert(String, node.xpath("string(./paramlist/param[@name='$key']/@value)")) ==
                              value
                    end
                end
                wires = xml.xpath("./schematic/Wire[@classid='WireOrthogonal']")
                @test pylen(wires) == length(definition.canvas.wires)
                for (wire, node) in zip(definition.canvas.wires, wires)
                    origin = (parse(Int, pyconvert(String, node.get("x"))),
                        parse(Int, pyconvert(String, node.get("y"))))
                    actual = [(origin[1] + parse(Int, pyconvert(String, v.get("x"))),
                                  origin[2] + parse(Int, pyconvert(String, v.get("y"))))
                              for v in node.xpath("./vertex")]
                    @test Set(actual) == Set(wire.vertices)
                end
            end
            @test pyconvert(Int, root.xpath("count(./definitions/Definition[@classid='RowDefn'])")) ==
                  length(plan.lines)
            for line in plan.lines
                rows = root.xpath("./definitions/Definition[@classid='RowDefn'][@name='$(line.name)']")
                @test pylen(rows) == 1
                row = only(rows)
                @test pyconvert(String, row.xpath("string(./paramlist/param[@name='type']/@value)")) ==
                      (line isa P.CableDefinitionPlan ? "Cable" : "TLine")
                # Access the row through mhi-xml too; counts alone would not
                # establish that its typed RowDefn can be read again.
                @test pyconvert(String, reread.definition[line.name].type) ==
                      (line isa P.CableDefinitionPlan ? "Cable" : "TLine")
                row_components = [
                    ("Line_Ground", line.ground), ("Line_FrePhase_Options", line.frephase),
                    ("Line_Out_Disp", line.outdisp)]
                if line isa P.LineDefinitionPlan
                    pushfirst!(row_components, ("Line_Tower_Universal", line.tower))
                end
                for (defn, params) in row_components
                    nodes = row.xpath("./schematic/User[@defn='master:$defn']")
                    @test pylen(nodes) == 1
                    node = only(nodes)
                    for (key, value) in params
                        @test pyconvert(String, node.xpath("string(./paramlist/param[@name='$key']/@value)")) ==
                              value
                    end
                end
                if line isa P.CableDefinitionPlan
                    cables = row.xpath("./schematic/User[@defn='master:Cable_Coax']")
                    @test pylen(cables) == length(line.cables)
                    for (component, node) in zip(line.cables, cables)
                        @test parse(Int, pyconvert(String, node.get("x"))) == component.x
                        @test parse(Int, pyconvert(String, node.get("y"))) == component.y
                        for (key, value) in component.params
                            @test pyconvert(String,
                                node.xpath("string(./paramlist/param[@name='$key']/@value)")) ==
                                  value
                        end
                    end
                    continue
                end
                tower = only(row.xpath("./schematic/User[@defn='master:Line_Tower_Universal']"))
                @test pyconvert(String, tower.xpath("string(./paramlist/param[@name='Nc']/@value)")) ==
                      "3"
                @test pyconvert(String, tower.xpath("string(./paramlist/param[@name='NG']/@value)")) ==
                      "2"
                @test pyconvert(String, tower.xpath("string(./paramlist/param[@name='X']/@value)")) ==
                      "0.0 [m]"
                for (prefix, coords) in (("C", line.conductors), ("G", line.ground_wires))
                    for (i, (x, y)) in enumerate(coords),
                        (axis, value) in (("X", x), ("Y", y))

                        key = axis * prefix * string(i)
                        @test pyconvert(String,
                            tower.xpath("string(./paramlist/param[@name='$key']/@value)")) ==
                              P.pscad_value(value; unit = "m")
                    end
                end
            end
            for wrapper in plan.wrappers
                qualified = name * ":" * wrapper.row
                cable = wrapper isa P.CableWrapperPlan
                classid = cable ? "Cable" : "TLine"
                nodes = root.xpath("./definitions/Definition[@name='Main']/schematic/Wire[@classid='$classid'][@defn='$qualified']")
                @test pylen(nodes) == 1
                node = only(nodes)
                for (key, value) in (("defn", qualified), ("name", qualified),
                    ("x", string(wrapper.x)), ("y", string(wrapper.y)), (
                    "w", cable ? "107" : "121"),
                    (
                    "h", cable ? "120" : "68"),
                    ("orient", "0"), ("disable", "false"), ("recv", "-1"), ("send", "-1"),
                    ("back", "-1"), ("crc", "0"))
                    @test pyconvert(String, node.get(key)) == value
                end
                vertices = [(parse(Int, pyconvert(String, v.get("x"))),
                                parse(Int, pyconvert(String, v.get("y"))))
                            for v in node.xpath("./vertex")]
                @test vertices == (cable ? [(0, 0), (-36, 0), (-54, -54), (-54, -72)] :
                       [(-54, 18), (-54, 36), (54, 54), (54, 72)])
                user = only(node.xpath("./User"))
                @test pyconvert(String, user.get("defn")) == qualified
                @test pyconvert(String, user.get("classid")) == "UserCmp"
                @test pyconvert(String, user.xpath("string(./paramlist/@crc)")) == "0"
                for (key, value) in wrapper.params
                    @test pyconvert(String, user.xpath("string(./paramlist/param[@name='$key']/@value)")) ==
                          value
                end
                for item in (node, user)
                    @test 100_000_000 <= parse(Int, pyconvert(String, item.get("id"))) <
                          1_000_000_000
                end
            end
            println("Exported ", path)
        end
        @test !isempty(models[1].operating_point.bus_states)
        @test isempty(models[2].operating_point.bus_states)
        @test !isempty(models[3].operating_point.bus_states)
        @test isempty(models[4].operating_point.bus_states)
        @test !isempty(models[5].operating_point.bus_states)
        @test isempty(models[6].operating_point.bus_states)
        @test isempty(models[7].operating_point.bus_states)
        @test isempty(models[8].operating_point.bus_states)
        @test !isempty(models[9].operating_point.bus_states)
        @test isempty(models[10].operating_point.bus_states)
        @test !isempty(models[11].operating_point.bus_states)
        @test isempty(models[12].operating_point.bus_states)
        @test !isempty(models[13].operating_point.bus_states)
        @test !isempty(models[14].operating_point.bus_states)
        @test all(m -> !isempty(m.operating_point.bus_states), models[15:18])
        # The module writer also preserves integer/text parameters and
        # electrical ports, independently of the all-real M3 controller forms.
        mktempdir() do temporary
            name = "typed_module"
            definition = P.ModuleDefinitionPlan("Typed",
                P.ModuleParameterPlan[P.ModuleParameterPlan("Gain", 2.0, ""),
                    P.ModuleParameterPlan("Count", 3, ""),
                    P.ModuleParameterPlan("Caption", "test module", "")],
                [P.ModulePortPlan("in", :input, -54, 0),
                    P.ModulePortPlan("out", :output, 54, 0),
                    P.ModulePortPlan("AC", :electrical, 0, 54, 3)], P.CanvasPlan())
            main = P.CanvasPlan()
            push!(main.components,
                P.ModuleInstancePlan(name * ":Typed",
                    ["Gain" => "4.0", "Count" => "5", "Caption" => "instance"], 180, 216, 0))
            P.lower!(main, P.Const(P.Signal("typed_input"), 1.0), (108, 108))
            P.signal_stub!(main, (126, 216), P.Signal("typed_input"))
            P.signal_stub!(main, (234, 216), P.Signal("typed_output"))
            P.stub!(main, (180, 270), nothing)
            plan = P.ProjectPlan(name, name, P._project_settings(settings, name), main,
                P.AbstractLineDefinitionPlan[], P.AbstractLineWrapperPlan[],
                [definition], P.ProbeManifest())
            path = joinpath(temporary, name * ".pscx")
            P._write_project(plan, path)
            root = etree.parse(path).getroot()
            for (parameter, type) in (("Gain", "Real"), ("Count", "Integer"), (
                "Caption", "Text"))
                @test pyconvert(String,
                    root.xpath("string(.//form/category/parameter[@name='$parameter']/@type)")) ==
                      type
                node = only(root.xpath(".//form/category/parameter[@name='$parameter']"))
                @test pyconvert(String, node.get("intent")) == "Input"
                @test pyconvert(String, node.get("dim")) == "1"
                @test pyconvert(String, node.get("helpmode")) == "Append"
                @test pylen(node.xpath("./cond | ./help | ./vis")) == 3
            end
            @test pyconvert(String, root.xpath("string(.//parameter[@name='Count']/value)")) ==
                  "3"
            @test pyconvert(String, root.xpath("string(.//parameter[@name='Caption']/value)")) ==
                  "test module"
            summary = P.read_project_summary(path)
            for parameter in definition.parameters
                @test pyconvert(Int,
                    root.xpath(
                        "count(.//Definition[@name='Typed']/schematic/User[@defn='master:import']/paramlist/param[@name='Name'][@value='$(parameter.name)'])")) ==
                      1
            end
            ports = summary.modules_and_ports["Typed"]
            @test [(p.name, p.kind, p.dim, p.datatype) for p in ports] ==
                  [("in", :input, 1, 3), ("out", :output, 1, 3), ("AC", :electrical, 3, 0)]
            port = only(root.xpath(".//Definition[@name='Typed']/svg/port[@name='AC']"))
            reference = only(reference_svg.xpath("./port"))
            for key in ("model", "mode", "type", "internal")
                @test pyconvert(String, port.get(key)) ==
                      pyconvert(String, reference.get(key))
            end
            @test summary.components_per_defn == Dict("typed_module:Typed" => 1,
                "master:const" => 1, "master:datalabel" => 3, "master:ground" => 1)
            @test pyconvert(String, root.xpath("string(.//Definition[@name='Main']/schematic/User/@x)")) ==
                  "180"
            @test pyconvert(String, root.xpath("string(.//Definition[@name='Main']/schematic/User/@y)")) ==
                  "216"
            @test pyconvert(String,
                root.xpath("string(.//Definition[@name='Main']/schematic/User/paramlist/param[@name='Count']/@value)")) ==
                  "5"
        end
        # Exercise dc_reference through the public exporter, including no extra
        # references at the source bus and no power flow for the linear builder.
        elements = (; ac = dc_state.elements.ac, from = dc_state.elements.from,
            line = dc_state.elements.line, ac_load = dc_state.elements.ac_load)
        rows = [(; r.node, r.element, r.side, r.terminal)
                for r in dc_state.topology.connections if r.element != :to]
        # A second branch gives the receiving bus two owned terminals, as
        # required by NetworkBuilder's classic-network materialization.
        elements = merge(elements, (; parallel = impedance(; z = s -> 400.0, pins = 1)))
        append!(rows,
            [(node = :D1, element = :parallel, side = 1, terminal = 1),
                (node = :D2, element = :parallel, side = 2, terminal = 1)])
        floating = NetworkBuilder.define(elements, rows; options = dc_state.options)
        mktempdir() do temporary
            for reference in (:midpoint_resistors, :none)
                path = joinpath(temporary, string(reference) * ".pscx")
                model = export_pscad(floating; path, settings, dc_reference = reference)
                root = etree.parse(path).getroot()
                @test pyconvert(Int,
                    root.xpath("count(.//User[@defn='master:resistor']/paramlist/param[@name='R'][@value='1.0E7 [ohm]'])")) ==
                      (reference == :midpoint_resistors ? 2 : 0)
                @test !model.provenance.resolved_powerflow
            end
        end
        # Supplied classic evidence avoids setpoint mutation and records R17.
        supplied = power_flow(classic)
        original = classic.elements[:source].setpoint
        mktempdir() do temporary
            model = export_pscad(classic; path = joinpath(temporary, "supplied.pscx"), powerflow = supplied)
            @test !model.provenance.resolved_powerflow
            @test classic.elements[:source].setpoint === original
        end
        # Exercise typed choice decoding and option units through the actual
        # writer, rather than establishing override behaviour only in the IR.
        mktempdir() do temporary
            path = joinpath(temporary, "ohl_options.pscx")
            export_pscad(ohl_classic; path,
                line_options = (; Numf = 200, CPASS = 1, EarthForm2 = 2,
                    FS = 2.0, FE = "2.0E5 [Hz]", GRRES = 250.0, GPERM = 1.2, W2 = 1000.0))
            root = etree.parse(path).getroot()
            for (defn, params) in (
                ("Line_Ground",
                ["EarthForm2" => "2", "GRRES" => "250.0 [ohm*m]", "GPERM" => "1.2"]),
                ("Line_FrePhase_Options",
                ["Numf" => "200", "CPASS" => "1",
                    "FS" => "2.0 [Hz]", "FE" => "2.0E5 [Hz]", "W2" => "1000.0"]))
                node = only(root.xpath(".//User[@defn='master:$defn']"))
                for (key, value) in params
                    @test pyconvert(String, node.xpath("string(./paramlist/param[@name='$key']/@value)")) ==
                          value
                end
            end
        end
    end
end
