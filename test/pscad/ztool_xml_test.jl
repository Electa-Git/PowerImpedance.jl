module PSCADZToolXMLTests
import ..PSCADFixtures
using Test, PowerImpedance, PythonCall, SHA
using ..PSCADFixtures, ..PSCADTopology
const P = PowerImpedance.PSCAD
const LIBRARY = joinpath(@__DIR__, "fixtures/ztool/Z_tool.pslx")
const etree = pyimport("lxml.etree")
const mhixml = pyimport("mhi.xml.pscad")
str(x) = pyconvert(String, x)
params(node) = Dict(str(p.get("name")) => str(p.get("value"))
                   for p in node.xpath("./paramlist/param"))

function port_labels(canvas)
    labels = Dict((parse(Int, str(n.get("x"))), parse(Int, str(n.get("y")))) =>
        params(n)["Name"] for n in canvas.xpath("./User[@defn='master:nodelabel']"))
    stubs = Dict{Tuple{Int, Int}, String}()
    for w in canvas.xpath("./Wire[@classid='WireOrthogonal']")
        x, y = parse(Int, str(w.get("x"))), parse(Int, str(w.get("y")))
        a, b = [(x + parse(Int, str(v.get("x"))), y + parse(Int, str(v.get("y"))))
                for v in w.xpath("./vertex")]
        haskey(labels, a) && (stubs[b] = labels[a])
        haskey(labels, b) && (stubs[a] = labels[b])
    end
    return stubs
end

@testset "Z-tool instance XML and workspace" begin
    library = etree.parse(LIBRARY).getroot()
    for (factory, kind, busname) in ((PSCADFixtures.small_ac_network, :ac, "B2"),
        (PSCADFixtures.dc_network, :dc, "D2"))
        for input in (factory(),)
            mktempdir() do directory
                ac = kind == :ac
                series = ac ?
                         ZToolProbe(kind, "series_scan"; element = :line, port = :side1,
                    voltage = 300, perturbation = 0.02, vac_control = true, f_control = true) :
                    ZToolProbe(kind, "series_scan"; element = :line, port = :side1,
                        voltage = 640, perturbation = 0.02, vdc_control = true)
                probes = [series, ZToolProbe(kind, "shunt_scan"; bus = busname, voltage = ac ? 300 : 636)]
                path = joinpath(directory, "scanned.pscx")
                model = export_pscad(input; path, ztool_probes = probes, ztool_library = LIBRARY)
                @test model.ztool_library.path == joinpath(directory, "Z_tool.pslx")
                @test model.ztool_library.sha256 == P.ZTOOL_SHA256
                @test read(model.ztool_library.path) == read(LIBRARY)
                tables = P._ztool_frequency_tables(model.settings.frequency)
                @test readdir(joinpath(directory, "Scan_options")) ==
                      sort([basename(name) for (name, _) in tables])
                for (name, contents) in tables
                    @test read(joinpath(directory, name)) == collect(codeunits(contents))
                end
                @test P.check_connectivity(path) === nothing
                @test P.check_geometry(path) === nothing
                # Read the saved instances through mhi-xml, including their wire coordinates.
                reread = mhixml.ProjectFile(path)
                canvas = reread.canvas("Main")
                defn = ac ? "Z_tool:ACscan" : "Z_tool:DCscan"
                instances = collect(canvas.xpath("./User[@defn='$defn']"))
                @test length(instances) == 2
                stubs = port_labels(canvas)
                definition = only(library.xpath("./definitions/Definition[@name='$(last(split(defn, ':')))']"))
                form = Dict(str(p.get("name")) => (str(p.get("type")), str(p.findtext("value", "")))
                            for p in definition.xpath("./form/category/parameter"))
                @test form["Name"][1] == "Text"
                @test form["f0"][1] == form["V0_peak"][1] == form["V_perturb_mag"][1] == "Real"
                @test form["selector"][1] == form["single_frequency"][1] == "Integer"
                for instance in instances
                    values = params(instance)
                    @test Set(keys(values)) == Set(keys(form))
                    @test str(instance.get("classid")) == "UserCmp"
                    @test parse(Float64, values["f0"]) == model.settings.frequency
                    series_instance = values["Name"] == "series_scan"
                    @test parse(Float64, values["V0_peak"]) == (ac ? 300 : series_instance ? 640 : 636)
                    @test parse(Float64, values["V_perturb_mag"]) == (series_instance ? 0.02 : 0.01)
                    for field in ("T_inj", "Tdecoupling", "selector", "single_frequency", "block_id")
                        @test parse(Float64, values[field]) == parse(Float64, form[field][2])
                    end
                    for field in (ac ? ("Vac_control", "f_control") : ("Vdc_control",))
                        @test values[field] == (series_instance ? "1" : "0")
                        @test form[field][1] == "Choice"
                    end
                    x, y = parse(Int, str(instance.get("x"))), parse(Int, str(instance.get("y")))
                    offsets = [(parse(Int, str(p.get("x"))), parse(Int, str(p.get("y"))))
                               for p in definition.xpath("./graphics/Port")]
                    @test offsets == (ac ? [(-54, 0), (54, 0)] : [(-36, 0), (36, 0), (0, 36)])
                    for p in definition.xpath("./graphics/Port")
                        @test params(p)["dim"] == (ac ? "3" : "1")
                    end
                    a1, a2 = [(x + dx, y + dy) for (dx, dy) in offsets[1:2]]
                    @test stubs[a1] == (ac ? (series_instance ? "B1" : "B2") :
                                                (series_instance ? "D1_P" : "D2_P"))
                    @test haskey(stubs, a2) == series_instance
                    series_instance && @test stubs[a2] == "series_scan_terminal"
                    ac || @test stubs[(x, y + 36)] == (series_instance ? "D1_N" : "D2_N")
                end
                workspace = etree.parse(model.workspace_path).getroot()
                projects = collect(workspace.xpath("./projects/project"))
                @test [str(p.get("type")) for p in projects] == ["library", "project"]
                @test [str(p.get("name")) for p in projects] == ["Z_tool", "scanned"]
                @test [str(p.get("filepath")) for p in projects] == [".\\Z_tool.pslx", ".\\scanned.pscx"]
                @test pylen(canvas.getroottree().getroot().xpath(
                    "./definitions/Definition[@name='ACscan' or @name='DCscan']")) == 0
                # Geometry checks use the external library ports even at the sheet edge.
                text = read(path, String)
                first_instance = first(instances)
                first_instance.set("x", "14382")
                reread.save()
                @test_throws ArgumentError P.check_geometry(path)
                @test_throws ArgumentError P.check_connectivity(path)
                write(path, text)
                # A second project may reuse the identical library beside it.
                sweep_file = joinpath(directory, "Scan_options", "frequencies.txt")
                write(sweep_file, "sweep-owned data")
                other = export_pscad(deepcopy(input); path = joinpath(directory, "other.pscx"),
                    ztool_probes = probes, ztool_library = LIBRARY)
                @test other.ztool_library == model.ztool_library
                @test read(sweep_file, String) == "sweep-owned data"
                write(model.ztool_library.path, "different library")
                @test_throws r"export library differs" export_pscad(deepcopy(input);
                    path = joinpath(directory, "collision.pscx"), ztool_probes = probes, ztool_library = LIBRARY)
                @test !isfile(joinpath(directory, "collision.pscx"))
            end
        end
    end
end

@testset "Failed project write leaves no Z-tool companion files" begin
    classic = PSCADFixtures.small_ac_network()
    netlist = P.netlist(classic, nothing)
    probes = [ZToolProbe(:ac, "scan"; bus = :B1, voltage = 300)]
    mktempdir() do directory
        path = joinpath(directory, "existing.pscx")
        write(path, "existing project")
        before = Dict(name => read(joinpath(directory, name)) for name in readdir(directory))
        @test_throws r"Target already exists" P._export_project(netlist, path, "existing",
            P.SimulationSettings(), false, (;), :midpoint_resistors, probes, LIBRARY)
        after = Dict(name => read(joinpath(directory, name)) for name in readdir(directory))
        @test before == after
    end
end

@testset "Empty Z-tool option preserves project bytes" begin
    os, clock, random = pyimport("os"), pyimport("time"), pyimport("random")
    old_login, old_time = os.getlogin, clock.time
    globals = pydict()
    pyexec("def login(): return 'fixture'\ndef timestamp(): return 1700000000", globals)
    os.getlogin, clock.time = globals["login"], globals["timestamp"]
    try
        for factory in (PSCADFixtures.small_ac_network, PSCADFixtures.dc_network)
            for input in (factory(),)
                mktempdir() do directory
                    models = map(("default", "empty")) do option
                        path = joinpath(mkpath(joinpath(directory, option)), "network.pscx")
                        random.seed(42)
                        option == "default" ? export_pscad(deepcopy(input); path) :
                            export_pscad(deepcopy(input); path, ztool_probes = ZToolProbe[],
                                ztool_library = "/absent/unused.pslx")
                    end
                    @test read(models[1].project_path) == read(models[2].project_path)
                    for model in models
                        @test model.ztool_library === nothing
                        @test model.workspace_path === nothing
                        @test readdir(dirname(model.project_path)) == ["network.pscx"]
                    end
                end
            end
        end
    finally
        os.getlogin, clock.time = old_login, old_time
    end
end
end
