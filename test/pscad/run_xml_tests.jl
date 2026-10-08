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
    P = PowerImpedance.PSCAD
    classic, state = PSCADFixtures.small_ac_network()
    ohl_classic, ohl_state = PSCADFixtures.passive_ohl_network()
    yy_classic, yy_state = PSCADFixtures.transformer_network()
    dy_classic, dy_state = PSCADFixtures.transformer_network(; organization = :ΔY)
    dc_classic, dc_state = PSCADFixtures.dc_network()
    settings = P.SimulationSettings(simulation_time = 0.3, time_step = 50e-6,
        sample_step = 250e-6, snapshot_time = 0.2)
    @testset "PSCAD mhi-xml export round trip" begin
        models = PSCADModel[]
        for (name, input) in (("small_ac_classic", classic), ("small_ac_builder", state),
            ("passive_ohl_classic", ohl_classic), ("passive_ohl_builder", ohl_state),
            ("transformer_yy_classic", yy_classic), ("transformer_yy_builder", yy_state),
            ("transformer_dy_classic", dy_classic), ("transformer_dy_builder", dy_state),
            ("dc_classic", dc_classic), ("dc_builder", dc_state))
            path = joinpath(only(ARGS), name * ".pscx")
            # ΔY XML checks exercise the selected station realization with no
            # legacy power-flow evidence; native comparison waits for dy-fix.
            model = startswith(name, "transformer_dy") ?
                    P._export_project(P.netlist(input, nothing), path, name, settings,
                false, (;), :midpoint_resistors) : export_pscad(input; path, settings)
            push!(models, model)
            plan = P.build_plan(model.netlist; settings, name, description = "PowerImpedance.jl: $name")
            summary = P.read_project_summary(path)
            counts = Dict{String, Int}()
            for component in plan.main.components
                counts[component.defn] = get(counts, component.defn, 0) + 1
            end
            @test summary.version == "5.0.2"
            @test summary.components_per_defn == counts
            expected_rows = Dict(l.name => Dict("master:Line_Tower_Universal" => 1,
                                     "master:Line_Ground" => 1, "master:Line_FrePhase_Options" =>
                                         1,
                                     "master:Line_Out_Disp" => 1) for l in plan.lines)
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
                @test summary.nodelabels == Dict("B1" => 3, "B2" => 3)
            end
            @test Set(summary.pgbs) == Set(c.name for c in plan.probes.channels)
            @test all(summary.settings[k] == v for (k, v) in plan.settings.params)
            @test model.project_path == path
            @test model.project_name == name
            @test model.provenance.source == :export
            @test model.provenance.powerimpedance_version ==
                  string(Base.pkgversion(PowerImpedance))
            @test model.provenance.mhi_xml_version == "1.3.0"
            @test model.provenance.resolved_powerflow ==
                  (input isa Network && !startswith(name, "transformer_dy"))
            root = etree.parse(path).getroot()
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
            @test pyconvert(Int, root.xpath("count(./definitions/Definition[@classid='RowDefn'])")) ==
                  length(plan.lines)
            for line in plan.lines
                rows = root.xpath("./definitions/Definition[@classid='RowDefn'][@name='$(line.name)']")
                @test pylen(rows) == 1
                row = only(rows)
                @test pyconvert(String, row.xpath("string(./paramlist/param[@name='type']/@value)")) ==
                      "TLine"
                # Access the row through mhi-xml too; counts alone would not
                # establish that its typed RowDefn can be read again.
                @test pyconvert(String, reread.definition[line.name].type) == "TLine"
                for (defn, params) in (("Line_Tower_Universal", line.tower),
                    ("Line_Ground", line.ground), ("Line_FrePhase_Options", line.frephase),
                    ("Line_Out_Disp", line.outdisp))
                    nodes = row.xpath("./schematic/User[@defn='master:$defn']")
                    @test pylen(nodes) == 1
                    node = only(nodes)
                    for (key, value) in params
                        @test pyconvert(String, node.xpath("string(./paramlist/param[@name='$key']/@value)")) ==
                              value
                    end
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
                nodes = root.xpath("./definitions/Definition[@name='Main']/schematic/Wire[@classid='TLine']")
                @test pylen(nodes) == 1
                node = only(nodes)
                for (key, value) in (("defn", qualified), ("name", qualified),
                    ("x", string(wrapper.x)), ("y", string(wrapper.y)), ("w", "121"), (
                    "h", "68"),
                    ("orient", "0"), ("disable", "false"), ("recv", "-1"), ("send", "-1"),
                    ("back", "-1"), ("crc", "0"))
                    @test pyconvert(String, node.get(key)) == value
                end
                vertices = [(parse(Int, pyconvert(String, v.get("x"))),
                                parse(Int, pyconvert(String, v.get("y"))))
                            for v in node.xpath("./vertex")]
                @test vertices == [(-54, 18), (-54, 36), (54, 54), (54, 72)]
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
