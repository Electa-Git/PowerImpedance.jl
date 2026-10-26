module PSCADZToolTests
import ..PSCADFixtures
using Test, PowerImpedance, SHA
using ..PSCADFixtures: small_ac_network, dc_network, passive_ohl_network,
                       dc_cable_network, transformer_network, mmc_pq_network,
                       sm_network, tlc_case1_network
using ..PSCADTopology
const P = PowerImpedance.PSCAD
const LIBRARY = joinpath(@__DIR__, "fixtures/ztool/Z_tool.pslx")

# Remove scan blocks and identify their A1/A2 nets. The remaining graph must
# retain every original component parameter and ordered electrical pin.
function scan_free_graph(graph)
    graph = deepcopy(graph)
    components, nets = graph["components"], graph["nets"]
    scans = findall(c -> startswith(c["definition"], "Z_tool:"), components)
    for i in scans
        a = only(findall(n -> [i, 1] in n["ports"], nets))
        b = only(findall(n -> [i, 2] in n["ports"], nets))
        a == b && continue
        append!(nets[a]["ports"], nets[b]["ports"])
        nets[a]["ground"] |= nets[b]["ground"]
        nets[a]["probe"] |= nets[b]["probe"]
        deleteat!(nets, b)
    end
    keep = setdiff(eachindex(components), scans)
    indices = Dict(old => new for (new, old) in enumerate(keep))
    for net in nets
        filter!(pin -> haskey(indices, pin[1]), net["ports"])
        for pin in net["ports"]
            pin[1] = indices[pin[1]]
        end
    end
    filter!(n -> !isempty(n["ports"]) || n["ground"], nets)
    graph["components"] = components[keep]
    return graph
end

channel_values(plan) = [Tuple(getfield(c, f) for f in fieldnames(P.ProbeChannel))
                       for c in plan.probes.channels]

@testset "Z-tool probe arguments" begin
    @test ZToolProbe(:ac, "scan"; bus = :B1).perturbation == 0.01
    @test ZToolProbe(:dc, "scan"; element = :line, port = :side1).kind == :dc
    for name in ("", "1scan", "scan-point", "scan point", "é", "a"^31)
        @test_throws ArgumentError ZToolProbe(:ac, name; bus = :B1)
    end
    for kwargs in ((;), (; element = :line), (; port = :side1),
        (; bus = :B1, element = :line, port = :side1), (; element = :line, port = 0),
        (; element = :line, port = true), (; element = 4, port = :side1), (; bus = 1),
        (; bus = :B1, voltage = NaN), (; bus = :B1, voltage = Inf),
        (; bus = :B1, voltage = 0), (; bus = :B1, voltage = -1),
        (; bus = :B1, voltage = true), (; bus = :B1, perturbation = -0.01),
        (; bus = :B1, perturbation = Inf), (; bus = :B1, vac_control = 1),
        (; bus = :B1, vdc_control = false))
        @test_throws ArgumentError ZToolProbe(:ac, "scan"; kwargs...)
    end
    @test_throws ArgumentError ZToolProbe(:other, "scan"; bus = :B1)
    @test_throws ArgumentError ZToolProbe(missing, "scan"; bus = :B1)
    @test_throws ArgumentError ZToolProbe(:dc, "scan"; bus = :D1, vac_control = false)
    @test_throws ArgumentError ZToolProbe(:dc, "scan"; bus = :D1, f_control = true)
end

@testset "Z-tool placement and current orientation" begin
    for (factory, kind, element, port) in ((small_ac_network, :ac, :line, :side1),
        (dc_network, :dc, :line, :side1), (passive_ohl_network, :ac, :line, :side2),
        (dc_cable_network, :dc, :line, :side2), (transformer_network, :ac, :line, :side1))
        state = factory()
        for input in (state,)
            n = P.netlist(input, nothing)
            e = only(filter(e -> e.name == element, n.elements))
            terminal = only(filter(t -> t.port == port, e.terminals))
            bus = only(filter(b -> b.key == terminal.bus, n.buses))
            baseline = P.build_plan(n)
            probes = [ZToolProbe(kind, "series_scan"; element, port, voltage = 300),
                ZToolProbe(kind, "shunt_scan"; bus = bus.name, voltage = 300)]
            plan = P.build_plan(n; ztool_probes = probes)
            @test P.check_connectivity(plan) === nothing
            @test channel_values(plan) == channel_values(baseline)
            modules = Dict(m.name => m for m in plan.modules)
            before = PSCADTopology.electrical_graph(baseline.main, modules)
            after = PSCADTopology.electrical_graph(plan.main, modules)
            @test PSCADTopology.equivalent(before, scan_free_graph(after))
            scans = filter(c -> startswith(c.defn, "Z_tool:"), plan.main.components)
            @test length(scans) == 2
            for c in scans
                p = Dict(c.params)
                @test c.defn == (kind == :ac ? "Z_tool:ACscan" : "Z_tool:DCscan")
                @test p["V0_peak"] == "300.0"
                @test p["f0"] == "50.0"
                @test p["T_inj"] == p["Tdecoupling"] == "1e8"
                @test p["selector"] == p["block_id"] == "0"
                @test p["single_frequency"] == "1"
                a2 = (c.x + (kind == :ac ? 54 : 36), c.y)
                @test count(w -> a2 in w.vertices, plan.main.wires) ==
                      (p["Name"] == "series_scan" ? 1 : 0)
            end
        end
    end
end

@testset "Z-tool active terminals preserve electrical paths" begin
    for (factory, terminals) in (
        (sm_network, ((:ac, :sg1, :ac), (:ac, :g2, :ac))),
        (mmc_pq_network, ((:ac, :DUT, :ac), (:dc, :DUT, :dc), (:dc, :G_DC, :dc))),
        (tlc_case1_network, ((:ac, :DUT, :ac), (:dc, :DUT, :dc))))
        network = factory()
        list = P.netlist(network, compute(PowerFlowProblem(network), ACDCPowerFlow()))
        baseline = P.build_plan(list)
        probes = [ZToolProbe(kind, "scan_$i"; element, port)
                  for (i, (kind, element, port)) in enumerate(terminals)]
        plan = P.build_plan(list; ztool_probes = probes)
        modules = Dict(m.name => m for m in plan.modules)
        before = PSCADTopology.electrical_graph(baseline.main, modules)
        after = PSCADTopology.electrical_graph(plan.main, modules)
        @test PSCADTopology.equivalent(before, scan_free_graph(after))
        @test channel_values(plan) == channel_values(baseline)
        @test P.check_connectivity(plan) === nothing
    end
end

@testset "Z-tool placement errors and solved voltage" begin
    classic = small_ac_network()
    n = P.netlist(classic, nothing)
    build(probes) = P.build_plan(n; ztool_probes = probes)
    for (probe, message) in (
        (ZToolProbe(:ac, "s"; element = :absent, port = :side1), "unknown element :absent"),
        (ZToolProbe(:ac, "s"; element = :line, port = :absent),
            "unknown port :absent on element :line"),
        (ZToolProbe(:ac, "s"; element = :load, port = :side2),
            "element :load port :side2 is grounded"),
        (ZToolProbe(:ac, "s"; bus = :absent), "unknown bus absent"),
        (ZToolProbe(:dc, "s"; element = :line, port = :side1),
            "at element :line port :side1"),
        (ZToolProbe(:ac, "s"; bus = :B1), "specify voltage in kV"))
        @test_throws message build([probe])
    end
    @test_throws ArgumentError build([1])
    for name in ("a"^30, "scan")
        plan = build([ZToolProbe(:ac, name; element = :line, port = :side1, voltage = 300),
            ZToolProbe(:ac, name == "scan" ? "scan_terminal" : "other"; bus = :B2, voltage = 300)])
        @test P.check_connectivity(plan) === nothing
    end
    @test_throws r"duplicate PSCAD name" build([
        ZToolProbe(:ac, "scan"; bus = :B1, voltage = 300),
        ZToolProbe(:ac, "SCAN"; bus = :B2, voltage = 300)])
    @test_throws r"already has a scan probe" build([
        ZToolProbe(:ac, "scan"; element = :line, port = :side1, voltage = 300),
        ZToolProbe(:ac, "other"; element = :line, port = :side1, voltage = 300)])
    for name in ("B1", "line", "I_line_side1", "V_B1")
        @test_throws r"name is already used" build([ZToolProbe(:ac, name; bus = :B1, voltage = 300)])
    end
    dc = dc_network()
    @test_throws r"ac probe on dc bus D1" P.build_plan(P.netlist(dc, nothing);
        ztool_probes = [ZToolProbe(:ac, "s"; bus = :D1)])
    for (network, kind, name, scale) in ((classic, :ac, "B1", sqrt(2)), (dc, :dc, "D1", 2))
        solved = P.netlist(network, compute(PowerFlowProblem(network), ACDCPowerFlow()))
        bus = only(filter(b -> b.name == name, solved.buses))
        plan = P.build_plan(solved; ztool_probes = [ZToolProbe(kind, "s"; bus = bus.key)])
        scan = only(filter(c -> startswith(c.defn, "Z_tool:"), plan.main.components))
        @test parse(Float64, Dict(scan.params)["V0_peak"]) ≈ bus.vm_pu * bus.base_kV * scale rtol=1e-8
    end
end

@testset "Z-tool idle frequency tables" begin
    for frequency in (50.0, 60.0)
        tables = P._ztool_frequency_tables(frequency)
        names = ["frequencies.txt"; ["frequencies$i.txt" for i in 1:8]]
        @test first.(tables) == Tuple("Scan_options/" .* names)
        for (index, (_, contents)) in enumerate(tables)
            header = index == 1 ? "! This file stores the frequency sweep values in Hz " :
                     "! This file stores the multi-frequency sweep values in Hz "
            expected = header * "\n1\t$(frequency)\n2\t$(frequency)\nENDFILE:"
            @test collect(codeunits(contents)) == collect(codeunits(expected))
            @test !endswith(contents, '\n')
        end
        mktempdir() do directory
            scan_options = mkpath(joinpath(directory, "Scan_options"))
            existing = joinpath(scan_options, "frequencies3.txt")
            write(existing, "sweep-owned data\n")
            stamp = mtime(existing)
            P._write_ztool_frequency_tables(directory, tables)
            @test readdir(scan_options) == names
            @test read(existing, String) == "sweep-owned data\n"
            @test mtime(existing) == stamp
            for (name, contents) in tables
                path = joinpath(directory, name)
                path == existing || @test read(path) == collect(codeunits(contents))
            end
        end
    end
end

@testset "Z-tool library hash and offline cache" begin
    @test bytes2hex(open(sha256, LIBRARY)) == P.ZTOOL_SHA256
    @test P._ztool_library(LIBRARY) == (; path = LIBRARY, sha256 = P.ZTOOL_SHA256)
    @test_throws ArgumentError P._ztool_library(LIBRARY * ".absent")
    @test_throws ArgumentError P._ztool_library(4)
    mktempdir() do directory
        path = joinpath(directory, "local.pslx")
        write(path, "local library fixture")
        @test P._ztool_library(path) == (; path, sha256 = bytes2hex(open(sha256, path)))
    end
    mktempdir() do depot
        cached = P._ztool_library(; depot, url = "file://" * LIBRARY)
        @test read(cached.path) == read(LIBRARY)
        stamp = stat(cached.path).mtime
        @test P._ztool_library(; depot, url = "file:///absent") == cached
        @test stat(cached.path).mtime == stamp
        write(cached.path, "changed library")
        @test_throws r"cached library SHA-256" P._ztool_library(; depot)
    end
    mktempdir() do depot
        @test_throws r"library SHA-256" P._ztool_library(; depot, url = "file://" * LIBRARY,
            expected_sha256 = "0"^64)
        @test isempty(readdir(joinpath(depot, "artifacts/ztool", P.ZTOOL_VERSION)))
    end
end
end
