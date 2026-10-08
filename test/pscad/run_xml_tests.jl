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
    pyimport("mhi.xml.pscad")
    include("fixtures.jl")
    P = PowerImpedance.PSCAD
    classic, state = PSCADFixtures.small_ac_network()
    settings = P.SimulationSettings(simulation_time = 0.3, time_step = 50e-6,
        sample_step = 250e-6, snapshot_time = 0.2)
    @testset "PSCAD mhi-xml export round trip" begin
        models = PSCADModel[]
        for (name, input) in (("small_ac_classic", classic), ("small_ac_builder", state))
            path = joinpath(only(ARGS), name * ".pscx")
            model = export_pscad(input; path, settings)
            push!(models, model)
            plan = P.build_plan(model.netlist; settings, name, description = "PowerImpedance.jl: $name")
            summary = P.read_project_summary(path)
            counts = Dict{String, Int}()
            for component in plan.main.components
                counts[component.defn] = get(counts, component.defn, 0) + 1
            end
            @test summary.version == "5.0.2"
            @test summary.components_per_defn == counts
            @test all(>=(2), values(summary.nodelabels))
            @test summary.nodelabels == Dict("B1" => 3, "B2" => 3)
            @test Set(summary.pgbs) == Set(c.name for c in plan.probes.channels)
            @test all(summary.settings[k] == v for (k, v) in plan.settings.params)
            @test model.project_path == path
            @test model.project_name == name
            @test model.provenance.source == :export
            @test model.provenance.powerimpedance_version ==
                  string(Base.pkgversion(PowerImpedance))
            @test model.provenance.mhi_xml_version == "1.3.0"
            @test model.provenance.resolved_powerflow == (input isa Network)
            root = etree.parse(path).getroot()
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
            for bus in model.netlist.buses
                @test pyconvert(Int,
                    root.xpath("count(.//User[@defn='master:nodelabel']/paramlist/param[@name='Name'][@value='$(bus.name)'])")) >=
                      2
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
            wires = root.xpath("./definitions/Definition[@name='Main']/schematic/Wire")
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
            println("Exported ", path)
        end
        @test !isempty(models[1].operating_point.bus_states)
        @test isempty(models[2].operating_point.bus_states)
        # Supplied classic evidence avoids setpoint mutation and records R17.
        supplied = power_flow(classic)
        original = classic.elements[:source].setpoint
        mktempdir() do temporary
            model = export_pscad(classic; path = joinpath(temporary, "supplied.pscx"), powerflow = supplied)
            @test !model.provenance.resolved_powerflow
            @test classic.elements[:source].setpoint === original
        end
    end
end
