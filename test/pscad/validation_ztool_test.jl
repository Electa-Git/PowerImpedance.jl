module PSCADValidationZToolTests
using Test, PowerImpedance, LinearAlgebra, TOML, PythonCall
using ..PSCADValidationTests: V
include("topology.jl")
const P = PowerImpedance.PSCAD
const RUN_CASE = Ref("")
const RUN_FAIL = Ref(false)
const RUN_NAN = Ref(false)
const RUN_LAUNCHES = Ref(0)
const RUN_IDENTITY = Dict("schema" => "2", "version" => "5.1.0",
    "pscad_sha256" => repeat("1", 64), "master_library_sha256" => repeat("2", 64),
    "fortran_version" => "GFortran 8.1")

# The transport executes local Julia children and reads saved references. It has no station access.
function P.remote_command(::Val{:component_ztool}, config::RemoteConfig, command::AbstractString)
    if occursin("identify.py", command)
        script = "print(" * repr(sprint(TOML.print, RUN_IDENTITY)) * ")"
    elseif occursin("-SharedCase", command)
        RUN_LAUNCHES[] += 1
        root = replace(only(match(r"-SharedCase '([^']+)'", command).captures), '\\' => '/')
        script = """
        using TOML
        root, directory = $(repr(root)), $(repr(RUN_CASE[]))
        input = TOML.parsefile(joinpath(root, "computation.toml"))
        output = joinpath(root, "outputs")
        write(joinpath(output, "pscad-console.txt"), "local component fixture")
        $(RUN_FAIL[]) && (println(stderr, "synthetic sweep failure"); exit(9))
        s = input["settings"]
        parameters = Dict{String, Any}("time_duration" => s["time_duration"],
            "time_step" => s["time_step_us"], "sample_step" => s["sample_step_us"],
            "PlotType" => "OUT", "output_filename" => s["output_stem"] * ".out",
            "StartType" => "STANDARD", "SnapType" => "NONE", "SnapTime" => 0.0,
            "snapshot_filename" => s["output_stem"] * ".snp", "MrunType" => "STANDALONE", "Mruns" => 1)
        readback = Dict(k => Dict("requested" => v, "observed" => v) for (k,v) in parameters)
        open(io -> TOML.print(io, readback), joinpath(output, "settings-readback.toml"), "w")
        write(joinpath(output, "solver.toml"), $(repr(sprint(TOML.print, RUN_IDENTITY))))
        write(joinpath(output, "timing.txt"), "3.25")
        write(joinpath(output, "build-messages.txt"), "normal\\tBuild\\tgenerated\\tThe total number of live nodes: 80\\n")
        record = TOML.parsefile(joinpath(directory, "manifest.toml"))
        axes = record["axes"]
        n = length(axes)
        arguments = copy(input["ztool"]["arguments"])
        haskey(arguments, "topology") && (arguments["topology"] = joinpath(root, arguments["topology"]))
        entries = split.(readlines(joinpath(directory, "reference.tsv"))[2:end], '\\t')
        matrix = reshape([complex(parse(Float64, r[4]), parse(Float64, r[5])) for r in entries], n, n, :)
        $(RUN_NAN[]) && (matrix .= ComplexF64(NaN, NaN))
        kind = n == 3 ? "ACDC" : "AC"
        ports = unique([replace(axis, r"_(dc|d|q)\$" => "") for axis in axes])
        name = s["output_stem"] * "#Y_" * kind * "#" * join(ports, '#') * "#.txt"
        text(z) = replace(string(z), "im" => "j", " " => "", "*" => "")
        open(joinpath(output, name), "w") do io
            println(io, join(["f"; axes], '\\t'))
            for (k, f) in enumerate(arguments["freq"])
                println(io, join([string(f); [text(matrix[r,c,k]) for r in 1:n for c in 1:n]], '\\t'))
            end
        end
        sample = arguments["sample_step"] * 1e-6
        sample_time = round(ceil((arguments["t_snap"] + arguments["dt_injections"]) / sample) * sample; digits = 6)
        phase = 2pi * rem(record["settings"]["frequency_Hz"] * sample_time, 1)
        angles = s["output_stem"] * "_angles.txt"
        open(joinpath(output, angles), "w") do io
            println(io, "Bus\\tArea\\tAngle [rad]")
            for port in record["ports"]
                port["kind"] == "ac" && println(io, port["name"], "\\t0\\t", phase)
            end
        end
        power = s["output_stem"] * "_power_flow.txt"
        write(joinpath(output, power), "fixture")
        metadata = Dict("version" => "0.1.52", "arguments" => arguments, "files" => [name, angles, power])
        open(io -> TOML.print(io, metadata), joinpath(output, "ztool.toml"), "w")
        """
    else
        script = "nothing"
    end
    return `$(Base.julia_cmd()) --startup-file=no --project=@stdlib -e $script`
end

function closed_source_graph(plan, original_count = nothing)
    graph = PSCADTopology.electrical_graph(plan.main, Dict(m.name => m for m in plan.modules))
    components, nets = graph["components"], graph["nets"]
    original_count === nothing && return graph
    switches = collect((original_count + 1):length(components))
    for i in switches
        groups = findall(n -> any(pin -> pin[1] == i, n["ports"]), nets)
        isempty(groups) && continue
        a = first(groups)
        for b in reverse(groups[2:end])
            append!(nets[a]["ports"], nets[b]["ports"])
            nets[a]["ground"] |= nets[b]["ground"]
            nets[a]["probe"] |= nets[b]["probe"]
            deleteat!(nets, b)
        end
    end
    keep = setdiff(eachindex(components), switches)
    indices = Dict(old => new for (new, old) in enumerate(keep))
    for net in nets
        filter!(pin -> haskey(indices, pin[1]), net["ports"])
        for pin in net["ports"]
            pin[1] = indices[pin[1]]
        end
        sort!(net["ports"]; by = Tuple)
    end
    filter!(n -> !isempty(n["ports"]) || n["ground"], nets)
    graph["components"] = components[keep]
    sort!(nets; by = n -> string(n["ports"]))
    return graph
end

@testset "Component sweep ports, topology and source switching" begin
    @test V.ZTOOL_FREQUENCIES == [1, 2, 3, 4, 6, 10, 16, 25, 40, 63, 100, 158, 251, 398, 631, 1000]
    @test length(V.ztool_component_ids()) == 26
    @test all(V.fixture(id).category in (:passive, :device) for id in V.ztool_component_ids())
    for kind in (:ac, :dc)
        canvas = V.ztool_source_switch(kind)
        @test P.check_connectivity(canvas, "source_switch") === nothing
        breakers = filter(c -> c.defn == "master:breaker1", canvas.components)
        @test length(breakers) == (kind == :ac ? 3 : 2)
        @test all(Dict(c.params)["RON"] == "0.0 [ohm]" &&
            parse(Float64, first(split(Dict(c.params)["ROFF"]))) == (kind == :ac ? 1e100 : P.DC_REFERENCE_RESISTANCE) &&
            Dict(c.params)["OPCUR"] == "1" for c in breakers)
        comparison = only(filter(c -> c.defn == "master:compare", canvas.components))
        @test Dict(comparison.params)["X"] == "1.0"
        @test Dict(comparison.params)["INTR"] == "0"
    end
    # Two half-impedance poles reproduce the differential two-port only when
    # neither pole remains stiff. The weak equal references preserve that result.
    resistance = 20.0
    incidence = [1.0 0; 0 1; -1 0; 0 -1]
    y = 2 / resistance * (incidence * incidence')
    voltage = [1.0 0; -1 0; 0 1; 0 -1]
    solution = [y + I / P.DC_REFERENCE_RESISTANCE voltage; voltage' zeros(2, 2)] \
        [zeros(4, 2); Matrix{Float64}(I, 2, 2)]
    @test y[[1, 3], :] * solution[1:4, :] ≈ [1.0 -1; -1 1] / resistance
    @test sum(solution[1:2, :]; dims = 1) ≈ zeros(1, 2) atol = 1e-8
    for (id, expected) in (("induction_machine", 0), ("mmc_gfm_lec_compensated", 1),
            ("passive_ac_rlc", 2), ("passive_dc_rlc", 2),
            ("ac_ohl_untransposed", 1), ("transformer_dyn11", 1), ("ieee9_bus_impedance", 0))
        net = V.fixture(id).factory()
        list = V.fixture_netlist(net, compute(PowerFlowProblem(net), ACDCPowerFlow()))
        spec = V.fixture(id).category == :device ? V.passive_settings() : first(V.scan_definition(id, net, list))
        ports = V.ztool_ports(id, net, list, spec)
        requests = [p.element === nothing ? ZToolProbe(p.kind, p.name; bus = p.bus.name) :
                    ZToolProbe(p.kind, p.name; element = p.element,
                        port = Symbol(p.port)) for p in ports]
        plan,
        replacements = V.ztool_measurement_plan(list, P.SimulationSettings(), requests)
        @test length(replacements) == count(p -> p.element !== nothing, ports)
        before = closed_source_graph(plan)
        scan = ZToolScan(frequencies = V.ZTOOL_FREQUENCIES, multi_frequency = true, snapshot_time = 8)
        openings = V.ztool_disconnect_sources!(plan, list, ports, scan)
        @test length(openings) == expected
        @test all(o["open_threshold_s"] == 8 for o in openings)
        @test closed_source_graph(plan, length(before["components"])) == before
        @test P.check_connectivity(plan) === nothing
        @test all(p.measured_side == (p.element === nothing ? 1 : 2) for p in ports)
        topology = V.ztool_topology(ports)
        if length(ports) == 1
            @test topology === nothing
        else
            mktempdir() do directory
                path = joinpath(directory, "topology.txt")
                write(path, topology)
                @test ZToolScan(frequencies = V.ZTOOL_FREQUENCIES, multi_frequency = true, topology = path).topology == path
                @test first(split(topology, '\n')) == join(["$(p.name)-$side" for p in ports for side in 1:2], ' ')
                rows = split.(split(chomp(topology), '\n')[2:end])
                @test rows[2][4] == rows[4][2] == "1"
                @test rows[1][1] == rows[3][3] == "1"
            end
        end
        id == "mmc_gfm_lec_compensated" && @test V.ztool_axes(ports) == ["DC_scan-2_dc", "AC_scan-2_d", "AC_scan-2_q"]
        id == "ieee9_bus_impedance" && @test only(ports).bus.name == "Bus5"
    end
end

@testset "Pilot settings and complete SI reference" begin
    for id in ("induction_machine", "mmc_gfm_lec_compensated")
        net = V.fixture(id).factory()
        list = V.fixture_netlist(net, compute(PowerFlowProblem(net), ACDCPowerFlow()))
        definition = V.ztool_definition(id, net, list)
        scan = definition.scan
        @test length(scan.frequencies) == 16 && scan.multi_frequency
        @test scan.num_parallel_sim == scan.f_base == 1
        @test definition.settings.time_step == 1e-6
        @test scan.start_fft >= first(definition.spec.window_starts) - definition.spec.injection_time
        @test scan.snapshot_time >= first(definition.spec.window_starts)
        @test scan.perturbation <= 1e-4
        @test definition.decay * scan.start_fft >= definition.declared_decay_times
        @test V.ztool_estimate(definition).simulations == (id == "induction_machine" ? 5 : 7)
        if id == "mmc_gfm_lec_compensated"
            @test size(definition.reference) == (3, 3, 16)
            dut = net.elements[:DUT]
            e = dut.elec
            expected =
                dut.cache.C * ((2π * im * 40I - dut.cache.A) \ dut.cache.B) + dut.cache.D
            expected .*= [dut.bases.S / dut.bases.v_dc, 2dut.bases.S /
                (3dut.bases.v_ac) * e.turnsRatio,
                2dut.bases.S / (3dut.bases.v_ac) * e.turnsRatio]
            expected ./= [dut.bases.v_dc dut.bases.v_ac dut.bases.v_ac]
            @test definition.reference[:, :, 9] ≈ expected rtol = 1e-12
            @test all(!iszero, definition.reference[1, :, 9])
            @test all(!iszero, definition.reference[:, 1, 9])
        else
            @test size(definition.reference) == (2, 2, 16)
            @test definition.reference ≈ V.induction_machine_reference(net, list, V.ZTOOL_FREQUENCIES)
        end
    end
    net = V.fixture("mmc_gfm_weak_grid").factory()
    list = V.fixture_netlist(net, compute(PowerFlowProblem(net), ACDCPowerFlow()))
    definition = V.ztool_definition("mmc_gfm_weak_grid", net, list)
    @test definition.screen["status"] == "failed"
    @test definition.scan.multi_frequency && length(definition.scan.frequencies) == 16
end

@testset "Written measurement copies and ordinary export bytes" begin
    for id in ("induction_machine", "mmc_gfm_lec_compensated")
        mktempdir() do parent
            directory = joinpath(parent, "ztool")
            record = V.prepare_ztool(id; directory)
            @test V.ztool_load(directory; id)["fixture_id"] == id
            @test record["status"] == "prepared_station_pending"
            formulation = V.ztool_formulation(record, directory)
            @test formulation.time_step == record["settings"]["time_step_s"]
            @test formulation.sample_step == record["settings"]["sample_step_s"]
            @test V.prepare_ztool(id; directory)["files"] == record["files"]
            @test P.check_connectivity(joinpath(directory, "scan.pscx")) === nothing
            @test P.check_geometry(joinpath(directory, "scan.pscx")) === nothing
            root = pyimport("lxml.etree").parse(joinpath(directory, "scan.pscx")).getroot()
            scans = root.xpath("./definitions/Definition[@name='Main']/schematic/User[starts-with(@defn,'Z_tool:')]")
            @test pylen(scans) == (id == "induction_machine" ? 1 : 2)
            for component in scans
                value = pyconvert(String, component.xpath("string(./paramlist/param[@name='Tdecoupling']/@value)"))
                @test parse(Float64, value) == record["arguments"]["t_snap"]
            end
            breakers = root.xpath("./definitions/Definition[@name='Main']/schematic/User[@defn='master:breaker1']")
            @test pylen(breakers) == (id == "induction_machine" ? 0 : 2)
            @test length(record["source_openings"]) == (id == "induction_machine" ? 0 : 1)
            @test length(record["replaced_terminal_readouts"]) == (id == "induction_machine" ? 1 : 2)
            id == "mmc_gfm_lec_compensated" && @test read(joinpath(directory, "topology.txt"), String) ==
                "DC_scan-1 DC_scan-2 AC_scan-1 AC_scan-2\n1 0 0 0\n0 0 0 1\n0 0 1 0\n0 1 0 0\n"
        end
    end
    mktempdir() do directory
        net = V.fixture("passive_ac_rlc").factory()
        list = V.fixture_netlist(net, compute(PowerFlowProblem(net), ACDCPowerFlow()))
        settings = P.SimulationSettings()
        before_path = joinpath(mkpath(joinpath(directory, "before")), "scan.pscx")
        after_path = joinpath(mkpath(joinpath(directory, "after")), "scan.pscx")
        os, clock, random = pyimport("os"), pyimport("time"), pyimport("random")
        old_login, old_time = os.getlogin, clock.time
        globals = pydict()
        pyexec("def login(): return 'fixture'\ndef timestamp(): return 1700000000", globals)
        os.getlogin, clock.time = globals["login"], globals["timestamp"]
        try
            random.seed(42)
            P._export_project(list, before_path, "scan", settings, false, (;), :midpoint_resistors, ZToolProbe[], nothing)
            spec = first(V.scan_definition("passive_ac_rlc", net, list))
            ports = V.ztool_ports("passive_ac_rlc", net, list, spec)
            requests = [ZToolProbe(p.kind, p.name; element = p.element,
                            port = Symbol(p.port)) for p in ports]
            plan, _ = V.ztool_measurement_plan(list, settings, requests)
            V.ztool_disconnect_sources!(plan, list, ports, ZToolScan(snapshot_time = 8))
            P._write_project(plan, joinpath(directory, "measurement.pscx"))
            random.seed(42)
            P._export_project(list, after_path, "scan", settings, false, (;), :midpoint_resistors, ZToolProbe[], nothing)
            @test read(before_path) == read(after_path)
        finally
            os.getlogin, clock.time = old_login, old_time
        end
    end
end

function stored_result(directory; active = true, factor = 1.0, permute = false)
    file = joinpath(@__DIR__, "fixtures/ztool/mixed#Y_ACDC#MMC_AC-2#MMC_DC-1#.txt")
    parsed = read_ztool_admittance(file)
    angles = 0.31
    transform = [1.0 0 0; 0 cos(angles) -sin(angles); 0 sin(angles) cos(angles)]
    reference = cat((transform' * parsed.admittance[:, :, k] * transform for k in 1:3)...; dims = 3)
    V.write_response(joinpath(directory, "reference.tsv"), reference, parsed.frequencies)
    output = mkpath(joinpath(directory, "outputs"))
    name = basename(file)
    order = permute ? [2, 3, 1] : [1, 2, 3]
    open(joinpath(output, name), "w") do io
        println(io, join(["f"; parsed.axes[order]], '\t'))
        for (k, f) in enumerate(parsed.frequencies)
            values = [factor * parsed.admittance[r, c, k] for r in order for c in order]
            text(z) = replace(string(z), "im" => "j", " " => "", "*" => "")
            println(io, join([string(f); text.(values)], '\t'))
        end
    end
    arguments = Dict("freq" => parsed.frequencies, "sample_step" => 25.0,
        "t_snap" => 6.0, "dt_injections" => 4.0)
    # frequency_sweep rounds this snapshot to 10.000025 s, one sample after 10 s.
    reported_angle = angles + 2π * rem(50 * 10.000025, 1)
    write(joinpath(output, "sweep_angles.txt"), "Bus\tArea\tAngle [rad]\nMMC_AC\t0\t$reported_angle\n")
    write(joinpath(output, "sweep_power_flow.txt"), "fixture\n")
    metadata = Dict("version" => "0.1.52", "arguments" => arguments,
        "files" => [name, "sweep_angles.txt", "sweep_power_flow.txt"])
    open(io -> TOML.print(io, metadata), joinpath(output, "ztool.toml"), "w")
    record = Dict{String, Any}("fixture_id" => "offline", "ztoolacdc_version" => "0.1.52",
        "axes" => parsed.axes, "arguments" => arguments, "settings" => Dict("frequency_Hz" => 50.0),
        "julia_reference" => "reference.tsv", "voltage_bases_kV" => ones(3),
        "current_bases_kA" => ones(3), "active" => active,
        "ports" => [Dict("name" => "MMC_DC", "kind" => "dc"), Dict("name" => "MMC_AC", "kind" => "ac")],
        "comparison_rule" => Dict("epsilon" => active ? 0.05 : 0.02))
    V.write_manifest(directory, record)
    return record
end

@testset "Stored admittances, header order, frames, limits and hashes" begin
    for active in (false, true), permute in (false, true)
        for factor in (1.0, active ? 1.04 : 1.015, active ? 1.06 : 1.025)
            mktempdir() do directory
                stored_result(directory; active, factor, permute)
                record = V.reanalyse_ztool("offline"; directory)
                @test record["status"] == (factor < (active ? 1.05 : 1.02) ? "passed" : "failed_comparison")
                @test record["maximum_relative_frobenius_error"] ≈ abs(factor - 1) atol = 1e-14
                @test length(readlines(joinpath(directory, "comparison_frequencies.tsv"))) == 4
                @test length(readlines(joinpath(directory, "comparison_entries.tsv"))) == 28
                @test V.reanalyse_ztool("offline"; directory)["status"] == record["status"]
                @test V.ztool_load(directory)["result_file"] == "outputs/mixed#Y_ACDC#MMC_AC-2#MMC_DC-1#.txt"
                open(io -> write(io, "changed"), joinpath(directory, "reference.tsv"), "a")
                @test_throws r"stored file changed" V.reanalyse_ztool("offline"; directory)
            end
        end
    end
end

@testset "Component compute, completed reuse and failed-run records" begin
    for id in ("induction_machine", "mmc_gfm_lec_compensated")
        mktempdir() do root
            directory = joinpath(root, "case", "ztool")
            V.prepare_ztool(id; directory)
            RUN_CASE[] = directory
            remote = RemoteConfig("fixture", root, "unused", "julia", "python";
                local_root = root, transport = :component_ztool)
            launches = RUN_LAUNCHES[]
            result = V.run_ztool(id; directory, remote, deadline = time() + 60)
            @test result["status"] == "passed"
            @test V.ztool_load(directory)["status"] == "passed"
            @test RUN_LAUNCHES[] == launches + 1
            @test length(result["kept_runs"]) == 1
            staged = joinpath(directory, only(result["kept_runs"]))
            @test isfile(joinpath(staged, "computation.toml"))
            @test isfile(joinpath(staged, "complete.toml"))
            @test length(readdir(joinpath(staged, "Scan_options"))) == 9
            again = V.run_ztool(id; directory, remote, deadline = time() + 60)
            @test again["status"] == "passed"
            @test RUN_LAUNCHES[] == launches + 1
            @test again["run_directory"] == result["run_directory"]
            @test V.reanalyse_ztool(id; directory)["maximum_relative_frobenius_error"] < 1e-12
        end
    end
    mktempdir() do root
        id = "induction_machine"
        directory = joinpath(root, "case", "ztool")
        V.prepare_ztool(id; directory)
        RUN_CASE[] = directory
        remote = RemoteConfig("fixture", root, "unused", "julia", "python";
            local_root = root, transport = :component_ztool)
        RUN_FAIL[] = true
        try
            @test_throws r"synthetic sweep failure" V.run_ztool(id; directory, remote, deadline = time() + 60)
        finally
            RUN_FAIL[] = false
        end
        record = V.ztool_load(directory)
        @test record["status"] == "run_or_analysis_failed"
        @test occursin("synthetic sweep failure", record["failure"])
        @test length(record["kept_runs"]) == 1
        @test any(f -> endswith(f["path"], "pscad-console.txt"), record["files"])
    end
end

@testset "Recorded references and diverged or missing results" begin
    mktempdir() do root
        id = "induction_machine"
        directory = joinpath(root, "case", "ztool")
        V.prepare_ztool(id; directory)
        RUN_CASE[] = directory
        remote = RemoteConfig("fixture", root, "unused", "julia", "python";
            local_root = root, transport = :component_ztool)
        launches = RUN_LAUNCHES[]
        RUN_NAN[] = true
        try
            result = V.run_ztool(id; directory, remote, deadline = time() + 60)
            @test result["status"] == "diverged"
            @test result["nonfinite_entries"] == 64
            @test RUN_LAUNCHES[] == launches + 1
            @test V.run_ztool(id; directory, remote, deadline = time() + 60)["status"] == "diverged"
            @test RUN_LAUNCHES[] == launches + 1
        finally
            RUN_NAN[] = false
        end
    end
    mktempdir() do parent
        directory = joinpath(parent, "rerun")
        scan = ZToolScan(frequencies = V.ZTOOL_FREQUENCIES[1:8], f_base = 0.5,
            snapshot_time = 9.0, start_fft = 12.0, injection_interval = 12.0)
        record = V.prepare_ztool("mmc_gfm_lec_compensated"; directory, scan)
        @test record["arguments"]["freq"] == scan.frequencies
        @test record["arguments"]["f_base"] == 0.5
        @test record["arguments"]["start_fft"] == 12.0
        @test record["estimate"]["simulations"] == 25
        @test only(record["source_openings"])["open_threshold_s"] == 9.0
        @test size(V.read_response(joinpath(directory, "reference.tsv"), 3, scan.frequencies)) == (3, 3, 8)
        @test !record["reference_selection"]["one_step_applies"]
        @test V.ztool_formulation(record, directory).snapshot_time == 9.0
        @test P.check_geometry(joinpath(directory, "scan.pscx")) === nothing
    end
    mktempdir() do directory
        record = stored_result(directory; factor = 1.06)
        frequencies = record["arguments"]["freq"]
        reference = V.read_response(joinpath(directory, "reference.tsv"), 3, frequencies)
        V.write_response(joinpath(directory, "reference_one_step.tsv"), 1.06reference, frequencies)
        record["one_step_reference"] = "reference_one_step.tsv"
        record["reference_selection"] = Dict("selected" => "one_step", "one_step_applies" => true)
        V.write_manifest(directory, record)
        result = V.reanalyse_ztool("offline"; directory)
        @test result["status"] == "passed"
        @test result["reference_results"]["continuous"]["status"] == "failed_comparison"
        @test result["reference_results"]["one_step"]["maximum_relative_frobenius_error"] < 1e-12
        @test isfile(joinpath(directory, "comparison_continuous_entries.tsv"))
        @test isfile(joinpath(directory, "comparison_one_step_entries.tsv"))
    end
    mktempdir() do directory
        record = stored_result(directory; factor = NaN)
        archived = mkpath(joinpath(directory, "runs", "run-diverged"))
        mv(joinpath(directory, "outputs"), joinpath(archived, "outputs"))
        record["kept_runs"] = ["runs/run-diverged"]
        record["stability"] = Dict("most_positive_located_real_per_s" => 101.0)
        V.write_manifest(directory, record)
        result = V.reanalyse_ztool("offline"; directory)
        @test result["status"] == "diverged"
        @test result["nonfinite_entries"] == 27
        @test result["stability"]["most_positive_located_real_per_s"] == 101.0
        @test result["recovered_outputs"] == "runs/run-diverged/outputs"
        @test V.reanalyse_ztool("offline"; directory)["status"] == "diverged"
        @test V.ztool_load(directory)["status"] == "diverged"
    end
    mktempdir() do directory
        record = stored_result(directory)
        rm(joinpath(directory, "outputs"); recursive = true)
        V.write_manifest(directory, record)
        @test V.reanalyse_ztool("offline"; directory)["status"] == "no_result"
        @test occursin("missing", V.ztool_load(directory)["analysis_error"])
    end
    mktempdir() do directory
        script = joinpath(directory, "ztool_sweeps.jl")
        cp(joinpath(V.ROOT, "ztool_sweeps.jl"), script)
        source = read(script, String)
        write(script, replace(source, "using PythonCall" => ""))
        write(joinpath(directory, "validation.jl"), """
            module PSCADValidation
            ztool_component_ids() = ["first", "second", "third"]
            RemoteConfig() = error("unexpected station configuration")
            function reanalyse_ztool(id)
                id == "first" && error("missing fixture")
                return Dict("status" => id == "second" ? "diverged" : "passed")
            end
            end
            """)
        output = IOBuffer()
        process = run(pipeline(ignorestatus(`$(Base.julia_cmd()) --startup-file=no --project=@stdlib $script reanalyse components`);
            stdout = output, stderr = output))
        text = String(take!(output))
        @test !success(process)
        @test occursin("first: analysis_or_run_failed", text)
        @test occursin("second: diverged", text)
        @test occursin("third: passed", text)
        @test !occursin("unexpected station configuration", text)
    end
end

@testset "Saved repeat comparisons and measured classifications" begin
    mktempdir() do root
        directory = mkpath(joinpath(root, "case"))
        source = mkpath(joinpath(root, "repeat"))
        stored_result(directory; factor = 1.06)
        stored_result(source; factor = 1.06)
        V.reanalyse_ztool("offline"; directory = source)
        source_hash = V.digest(joinpath(source, "manifest.toml"))
        for name in ("original-step", "half-step")
            archive = mkpath(joinpath(directory, "repeats", name))
            for file in readdir(source)
                (file == "manifest.toml" || startswith(file, "comparison_")) &&
                    cp(joinpath(source, file), joinpath(archive, file))
            end
        end
        record = V.ztool_load(directory)
        for (classification, status) in (("time-step limited", "time_step_limited"),
                ("model difference near 150 Hz", "model_difference_near_150_hz"))
            record["repeat_conclusion"] = Dict("classification" => classification,
                "repeats" => ["original-step", "half-step"])
            V.write_manifest(directory, record)
            record = V.reanalyse_ztool("offline"; directory)
            @test record["classification"] == classification
            @test record["status"] == status
            @test record["comparison_status"] == "failed_comparison"
            @test length(record["repeat_results"]) == 2
            @test all(r -> length(r["comparison_files"]) == 6, record["repeat_results"])
            @test all(r -> r["manifest_sha256"] == source_hash, record["repeat_results"])
            @test any(f -> f["path"] == "repeats/half-step/manifest.toml" &&
                f["sha256"] == source_hash, record["files"])
            @test V.ztool_load(directory)["status"] == status
        end
        @test V.digest(joinpath(source, "manifest.toml")) == source_hash
        comparison = joinpath(directory, "repeats", "half-step", "comparison_entries.tsv")
        open(io -> write(io, "changed"), comparison, "a")
        @test_throws r"repeat comparison changed" V.ztool_repeat_results!(record, directory)
        @test_throws r"stored file changed" V.reanalyse_ztool("offline"; directory)
        cp(joinpath(source, "comparison_entries.tsv"), comparison; force = true)
        record["repeat_conclusion"]["repeats"] = ["missing"]
        V.write_manifest(directory, record)
        @test_throws r"missing evidence" V.reanalyse_ztool("offline"; directory)
    end
end
end
