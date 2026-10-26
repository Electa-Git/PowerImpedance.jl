module PSCADComputeTests
using Test, PowerImpedance, TOML, SHA, Logging
const P = PowerImpedance.PSCAD
const LAUNCHES = Ref(0)
const IDENTIFICATIONS = Ref(0)
const MODE = Ref(:success)
const IDENTITY = Dict("schema" => "2", "version" => "5.1.0",
    "pscad_sha256" => repeat("1", 64), "master_library_sha256" => repeat("2", 64),
    "fortran_version" => "fixture-fortran")

# Only local Julia child processes are executed. No Python, network or station.
function P.remote_command(::Val{:fixture}, config::RemoteConfig, command::AbstractString)
    if occursin("-SharedCase", command)
        LAUNCHES[] += 1
        root = replace(only(match(r"-SharedCase '([^']+)'", command).captures), '\\' => '/')
        channel_names = MODE[] === :array ?
                        ["Voltage:1", "Voltage:2", "Voltage:3", "Current"] :
                        MODE[] === :missing_array ? ["Voltage:1", "Voltage:2", "Current"] :
                        ["Voltage", "Current"]
        metadata = join(["PGB($index) Output Desc=\"$name\" Group=\"main\" Units=\"$(name == "Current" ? "kA" : "kV")\"\n"
                         for (index, name) in enumerate(channel_names)])
        row_values = join(fill("2.0D+0", length(channel_names) - 1), " ") * " 3.0d-1"
        script = """
        using TOML
        root = $(repr(root))
        input = TOML.parsefile(joinpath(root, "computation.toml"))
        settings = input["settings"]
        stem = settings["output_stem"]
        output = joinpath(root, "outputs")
        identity = TOML.parse($(repr(sprint(TOML.print, IDENTITY))))
        write(joinpath(output, "pscad-console.txt"), "offline fixture console\\nlast diagnostic: synthetic EMTDC failure\\n")
        $(MODE[] === :transport_failure) && (println(stderr, "synthetic transport failure"); exit(9))
        get(input, "expected_solver", identity) == identity || error("expected solver mismatch")
        parameters = Dict{String,Any}(
            "time_duration" => settings["time_duration"], "time_step" => settings["time_step_us"],
            "sample_step" => settings["sample_step_us"], "PlotType" => "OUT", "output_filename" => stem * ".out",
            "StartType" => "STANDARD", "SnapType" => haskey(settings, "snapshot_time") ? "ONLY_ONCE" : "NONE",
            "SnapTime" => get(settings, "snapshot_time", 0.0), "snapshot_filename" => stem * ".snp",
            "MrunType" => "STANDALONE", "Mruns" => 1)
        readback = Dict(key => Dict("requested" => value, "observed" => value) for (key,value) in parameters)
        $(MODE[] === :readback_failure) && (readback["time_step"]["observed"] = -1.0)
        open(io -> TOML.print(io, readback), joinpath(output, "settings-readback.toml"), "w")
        open(io -> TOML.print(io, identity), joinpath(output, "solver.toml"), "w")
        write(joinpath(output, "timing.txt"), "3.25")
        write(joinpath(output, "build-messages.txt"), "normal\\tBuild\\tgenerated\\tOK\\nwarning\\tBuild\\tgenerated\\tfixture warning\\n")
        if haskey(input, "ztool")
            arguments = copy(input["ztool"]["arguments"])
            haskey(arguments, "topology") &&
                (arguments["topology"] = replace(joinpath(root, arguments["topology"]), '/' => Char(92)))
            merge!(arguments, Dict("fortran_ext" => ".gf81", "working_dir" => root,
                "results_folder" => joinpath(root, "ztool_results")))
            files = String[]
            frequencies = get!(arguments, "freq", collect(1.0:8.0))
            $(MODE[] === :ztool_frequencies) && (frequencies = [1.0, 3.0])
            for port_index in (1, 2)
                name = stem * "#Y_AC#scan-" * string(port_index) * "#.txt"
                push!(files, name)
                open(joinpath(output, name), "w") do io
                    println(io, "f\tscan-", port_index, "_d\tscan-", port_index, "_q")
                    actual = $(MODE[] === :ztool_grid_mismatch) && port_index == 2 ?
                        [1.0, 3.0] : frequencies
                    for frequency in actual
                        println(io, "(", frequency, "+0j) (1+2j) (3+4j) (5+6j) (7+8j)")
                    end
                end
            end
            for suffix in ("_power_flow.txt", "_angles.txt")
                name = stem * suffix
                push!(files, name)
                write(joinpath(output, name), "fixture data")
            end
            $(MODE[] === :ztool_arguments) && (arguments["t_step"] = -1.0)
            $(MODE[] === :ztool_no_files) && filter!(name -> !occursin("#Y_", name), files)
            version = $(MODE[] === :ztool_version) ? "0.1.51" : "0.1.52"
            record = Dict("version" => version, "arguments" => arguments, "files" => files)
            open(io -> TOML.print(io, record; sorted = true), joinpath(output, "ztool.toml"), "w")
        else
            write(joinpath(output, stem * ".inf"), $(repr(metadata)))
            rows = round(Int, settings["time_duration"] / (settings["sample_step_us"] * 1e-6)) + 1
            $(MODE[] === :incomplete) && (rows -= 1)
            open(joinpath(output, stem * "_01.out"), "w") do io
                println(io, "TIME Voltage Current")
                for index in 0:rows-1
                    println(io, index * settings["sample_step_us"] * 1e-6, " ", $(repr(row_values)))
                end
            end
            haskey(settings, "snapshot_time") && write(joinpath(output, stem * ".snp"), "snapshot fixture")
        end
        """
    elseif occursin("identify.py", command)
        IDENTIFICATIONS[] += 1
        script = "print(" * repr(sprint(TOML.print, IDENTITY)) * ")"
    else
        script = "write(" * repr(joinpath(config.local_root, "canceled")) *
                 ", \"canceled\")"
    end
    return `$(Base.julia_cmd()) --startup-file=no --project=@stdlib -e $script`
end

@testset "PSCAD offline compute, completion and explicit reuse" begin
    LAUNCHES[] = 0
    IDENTIFICATIONS[] = 0
    mktempdir() do root
        project = joinpath(root, "handbuilt.pscx")
        write(project, "<project fixture=\"offline\"/>")
        remote = RemoteConfig("fixture", root, "unused", "julia", "python";
            local_root = root, transport = :fixture)
        settings = P.SimulationSettings(simulation_time = 0.0005, sample_step = 0.00025, time_step = 0.00005)
        probes = P.ProbeManifest(
            [P.ProbeChannel("Voltage", :voltage, "B1", nothing, nothing, 1, "kV")], nothing)
        model = PSCADModel(project; settings, probes)
        options = (; remote, timing = true, work_root = joinpath(root, "runs"))
        for invalid in ((unknown = 1,), (verbosity = 3,), (verbosity = true,), (timing = 1,),
            (resume_run_directory = :invalid,), (resume_run_directory = "",),
            (solver_identity = 1,), (solver_identity = Dict("version" => "changed"),),
            (work_root = dirname(root),), (sample_step = 1e-9,), (remote = 1,))
            @test_throws ArgumentError compute(model, PSCADRun(); options = merge(options, invalid))
        end
        @test_throws ArgumentError compute(model, PSCADRun(backend = PowerImpedance.PIACDC); options)
        @test LAUNCHES[] == 0
        quiet_log = Test.TestLogger()
        first_result = with_logger(quiet_log) do
            compute(model, PSCADRun(); options = merge(options, (resume_run_directory = :latest,)))
        end
        @test isempty(quiet_log.logs)
        @test first_result isa PSCADResult
        @test first_result isa AbstractProblemResult
        @test first_result.settings === settings || first_result.settings == settings
        @test !first_result.diagnostics.reused
        @test first_result.diagnostics.elapsed_seconds == 3.25
        @test first_result.diagnostics.timing.wall_seconds > 0
        @test first_result.diagnostics.solver_identity == IDENTITY
        @test length(first_result.diagnostics.build_warnings) == 1
        @test first_result.time ≈ [0, 0.00025, 0.0005]
        @test first_result.channels["Voltage"] == fill(2.0, 3)
        @test first_result.probes === probes
        @test LAUNCHES[] == 1
        @test IDENTIFICATIONS[] == 0
        source = first_result.paths.run_directory
        @test dirname(source) == options.work_root
        @test startswith(basename(source), "run-")
        @test sort(readdir(source)) ==
              ["complete.toml", "computation.toml", "generated.pscx", "outputs", "toolkit"]
        @test read(joinpath(source, "generated.pscx"), String) == read(project, String)
        input = TOML.parsefile(joinpath(source, "computation.toml"))
        @test input["schema_version"] == 1
        @test Set(keys(input)) == Set(["schema_version", "project_name", "project_sha256",
            "settings", "probes", "toolkit"])
        @test !haskey(input, "ztool")
        @test input["project_name"] == "generated"
        @test input["project_sha256"] == bytes2hex(sha256(read(project)))
        @test input["probes"]["names"] == ["Voltage"]
        @test input["settings"]["time_step_us"] ≈ 50.0
        @test input["settings"]["sample_step_us"] ≈ 250.0
        @test input["settings"]["plot_type"] == "OUT"
        @test !haskey(input["settings"], "snapshot_time")
        @test Set(keys(input["toolkit"])) == Set(keys(P.PSCAD_REMOTE_SOURCES))
        @test !haskey(input, "pscad_port")
        @test !haskey(input, "resources")
        complete = TOML.parsefile(joinpath(source, "complete.toml"))
        @test complete["schema_version"] == 1
        @test complete["observed_solver"] == IDENTITY
        @test haskey(complete["outputs"], "pi.inf")
        @test haskey(complete["outputs"], "pi_01.out")
        files = [joinpath(directory, name) for (directory, _, names) in walkdir(source)
                 for name in names]
        original = Dict(path => (bytes2hex(open(sha256, path)), mtime(path))
        for path in files)
        reused = compute(model, PSCADRun(); options = merge(options, (resume_run_directory = :latest,)))
        @test reused.diagnostics.reused
        @test isempty(reused.diagnostics.timing)
        @test reused.paths == first_result.paths
        @test reused.time == first_result.time
        @test reused.channels == first_result.channels
        @test reused.channels["Voltage"] !== first_result.channels["Voltage"]
        @test LAUNCHES[] == 1
        @test IDENTIFICATIONS[] == 1
        with_port = RemoteConfig("fixture", root, "unused", "julia", "python";
            local_root = root, transport = :fixture, pscad_port = 50000)
        @test compute(model, PSCADRun();
            options = merge(options,
                (remote = with_port, resume_run_directory = source))).diagnostics.reused
        @test LAUNCHES[] == 1
        @test original ==
              Dict(path => (bytes2hex(open(sha256, path)), mtime(path)) for path in files)
        @test compute(model,
            PSCADRun();
            options = merge(options,
                (resume_run_directory = source, solver_identity = IDENTITY))).diagnostics.reused
        @test_throws ArgumentError compute(model,
            PSCADRun();
            options = merge(options,
                (resume_run_directory = source, simulation_time = 0.001)))
        mktempdir() do outside
            copied = joinpath(outside, "completed-run")
            cp(source, copied)
            archived = compute(model, PSCADRun(); options = merge(options, (resume_run_directory = copied,)))
            @test archived.diagnostics.reused
            @test archived.paths.run_directory == copied
            @test archived.channels == first_result.channels
        end
        partial = mktempdir(root)
        @test_throws ArgumentError compute(
            model, PSCADRun(); options = merge(options, (resume_run_directory = partial,)))
        for path in (joinpath(source, "computation.toml"), joinpath(source, "generated.pscx"),
            joinpath(source, "toolkit", "runner.jl"), joinpath(source, "outputs", "pi_01.out"))
            saved = read(path)
            if basename(path) == "computation.toml"
                damaged = TOML.parsefile(path)
                damaged["project_name"] = "damaged"
                open(io -> TOML.print(io, damaged), path, "w")
            else
                open(io -> write(io, "\n# damaged\n"), path, "a")
            end
            @test_throws ArgumentError compute(model, PSCADRun();
                options = merge(options, (resume_run_directory = source,)))
            write(path, saved)
        end
        IDENTITY["fortran_version"] = "other-fixture-fortran"
        @test_throws ArgumentError compute(
            model, PSCADRun(); options = merge(options, (resume_run_directory = source,)))
        changed = compute(model, PSCADRun(); options = merge(options, (resume_run_directory = :latest,)))
        @test !changed.diagnostics.reused
        @test LAUNCHES[] == 2
        IDENTITY["fortran_version"] = "fixture-fortran"
        fresh = compute(model, PSCADRun(); options)
        @test !fresh.diagnostics.reused
        @test fresh.paths.run_directory != source
        @test LAUNCHES[] == 3
        snapshot = compute(model,
            PSCADRun();
            options = merge(options,
                (snapshot_time = 0.00025, output_stem = "snap", solver_identity = IDENTITY)))
        @test snapshot.settings.snapshot_time == 0.00025
        @test isfile(joinpath(snapshot.paths.outputs, "snap.snp"))
        @test TOML.parsefile(joinpath(snapshot.paths.run_directory, "computation.toml"))["expected_solver"] ==
              IDENTITY
        for mode in (:readback_failure, :incomplete, :transport_failure)
            MODE[] = mode
            before = Set(readdir(options.work_root; join = true))
            caught = try
                compute(model, PSCADRun(); options)
            catch error
                error
            end
            @test caught isa (mode === :readback_failure ? ArgumentError : ErrorException)
            failed = only(setdiff(Set(readdir(options.work_root; join = true)), before))
            @test !isfile(joinpath(failed, "complete.toml"))
            if mode !== :readback_failure
                @test occursin("synthetic EMTDC failure", sprint(showerror, caught))
                @test occursin("Full PSCAD diagnostics", sprint(showerror, caught))
            end
        end
        MODE[] = :success
        @test isfile(joinpath(root, "canceled"))
        missing_model = PSCADModel(project;
            settings,
            probes = P.ProbeManifest(
                [P.ProbeChannel("Missing", :voltage, nothing, nothing, nothing, 1, "kV")], nothing))
        @test_throws ErrorException compute(missing_model, PSCADRun(); options)
        # Empty manifests work for arbitrary hand-built projects.
        @test length(compute(PSCADModel(project; settings), PSCADRun(); options).channels) ==
              2
        array_model = PSCADModel(project;
            settings,
            probes = P.ProbeManifest(
                [P.ProbeChannel("Voltage", :voltage, "B1", nothing, nothing, 3, "kV")], "B1"))
        try
            MODE[] = :array
            array_result = compute(array_model, PSCADRun(); options)
            @test collect(keys(array_result.channels)) ==
                  ["Voltage:1", "Voltage:2", "Voltage:3", "Current"]
            @test isfile(joinpath(array_result.paths.run_directory, "complete.toml"))
            MODE[] = :missing_array
            @test_throws ErrorException compute(array_model, PSCADRun(); options)
        finally
            MODE[] = :success
        end
    end
end

@testset "Z-tool offline staging and completed-run resources" begin
    MODE[] = :success
    mktempdir() do root
        project = joinpath(root, "scanned.pscx")
        write(project, "<project fixture=\"offline\"/>")
        library = joinpath(root, "Z_tool.pslx")
        cp(joinpath(@__DIR__, "fixtures/ztool/Z_tool.pslx"), library)
        settings = P.SimulationSettings(simulation_time = 0.0005,
            sample_step = 0.00025, time_step = 0.00005, frequency = 60.0)
        export_tables = mkpath(joinpath(root, "Scan_options"))
        for suffix in ("", string.(1:8)...)
            write(joinpath(export_tables, "frequencies$suffix.txt"), "sweep-owned data")
        end
        model = PSCADModel(project; settings, ztool_library = library)
        remote = RemoteConfig("fixture", root, "unused", "julia", "python";
            local_root = root, transport = :fixture)
        options = (; remote, work_root = joinpath(root, "runs"))
        result = compute(model, PSCADRun(); options)
        directory = result.paths.run_directory
        input = TOML.parsefile(joinpath(directory, "computation.toml"))
        table_names = ["Scan_options/frequencies.txt";
            ["Scan_options/frequencies$i.txt" for i in 1:8]]
        @test !haskey(input, "ztool")
        @test Set(keys(input["resources"])) == Set(["Z_tool.pslx", "generated.pswx", table_names...])
        @test readdir(joinpath(directory, "Scan_options")) == basename.(table_names)
        for (index, name) in enumerate(table_names)
            header = index == 1 ? "! This file stores the frequency sweep values in Hz " :
                     "! This file stores the multi-frequency sweep values in Hz "
            expected = header * "\n1\t60.0\n2\t60.0\nENDFILE:"
            @test read(joinpath(directory, name)) == collect(codeunits(expected))
            @test input["resources"][name] == bytes2hex(sha256(expected))
            @test read(joinpath(root, name), String) == "sweep-owned data"
        end
        @test read(joinpath(directory, "Z_tool.pslx")) == read(library)
        @test read(joinpath(directory, "generated.pswx"), String) ==
              P._ztool_workspace("generated", "generated.pscx")
        for (name, digest) in input["resources"]
            @test P._file_digest(joinpath(directory, name)) == digest
        end
        reuse = merge(options, (; resume_run_directory = directory))
        @test compute(model, PSCADRun(); options = reuse).diagnostics.reused
        for name in keys(input["resources"])
            path = joinpath(directory, name)
            original = read(path)
            write(path, "changed resource")
            @test_throws r"resource changed" compute(model, PSCADRun(); options = reuse)
            write(path, original)
        end
        write(library, "changed source")
        launches = LAUNCHES[]
        @test_throws r"model library changed" compute(model, PSCADRun(); options)
        @test LAUNCHES[] == launches
    end
end

@testset "Z-tool sweep staging, readback and completed-run reuse" begin
    MODE[] = :success
    mktempdir() do root
        project = joinpath(root, "scanned.pscx")
        write(project, "<project fixture=\"offline\"/>")
        library = joinpath(root, "Z_tool.pslx")
        cp(joinpath(@__DIR__, "fixtures/ztool/Z_tool.pslx"), library)
        settings = P.SimulationSettings(simulation_time = 0.0005,
            sample_step = 0.00025, time_step = 0.00005)
        model = PSCADModel(project; settings, ztool_library = library)
        remote = RemoteConfig("fixture", root, "unused", "julia", "python";
            local_root = root, transport = :fixture)
        options = (; remote, work_root = joinpath(root, "runs"), timing = true)
        plain = PSCADModel(project; settings)
        launches = LAUNCHES[]
        @test_throws r"Z-tool library" compute(plain, ZToolScan(); options)
        @test LAUNCHES[] == launches
        @test_throws ArgumentError compute(model, ZToolScan(backend = PowerImpedance.PIACDC); options)
        for topology in (nothing, joinpath(root, "local_topology.txt")), logarithmic in (false, true)
            topology === nothing || write(topology, "scan-1 scan-2\n1 0\n0 1\n")
            grid = logarithmic ? (; f_min = 1, f_max = 8, f_points = 8) : (; frequencies = collect(1:8))
            scan = ZToolScan(; grid..., time_step = 1e-6, sample_step = 25e-6, topology)
            result = compute(model, scan; options)
            directory = result.paths.run_directory
            input = TOML.parsefile(joinpath(directory, "computation.toml"))
            @test result isa ZToolResult
            @test result isa AbstractProblemResult
            @test result.formulation === scan
            @test result.frequencies == collect(1.0:8.0)
            @test length(result.results) == 2
            @test [entry.name.sides for entry in result.results] == [[1], [2]]
            @test all(entry -> entry.admittance[:, :, 1] == [1+2im 3+4im; 5+6im 7+8im], result.results)
            @test result.diagnostics.elapsed_seconds == 3.25
            @test !result.diagnostics.reused
            @test result.diagnostics.timing.wall_seconds > 0
            @test result.diagnostics.solver_identity == IDENTITY
            @test result.diagnostics.ztool["version"] == "0.1.52"
            @test result.diagnostics.ztool["arguments"]["t_step"] == 1.0
            @test result.diagnostics.ztool["arguments"]["sample_step"] == 25.0
            @test input["ztool"]["arguments"][logarithmic ? "f_points" : "freq"] ==
                  (logarithmic ? 8 : collect(1.0:8.0))
            @test input["ztool"]["version"] == "0.1.52"
            @test !isfile(joinpath(directory, "outputs", "pi.inf"))
            if topology !== nothing
                @test read(joinpath(directory, "ztool_topology.txt")) == read(topology)
                @test input["resources"]["ztool_topology.txt"] == bytes2hex(open(sha256, topology))
                @test input["ztool"]["arguments"]["topology"] == "ztool_topology.txt"
                @test occursin('\\', result.diagnostics.ztool["arguments"]["topology"])
            end
            launches = LAUNCHES[]
            reused = compute(model, scan; options = merge(options, (; resume_run_directory = directory)))
            @test reused.diagnostics.reused
            @test isempty(reused.diagnostics.timing)
            @test LAUNCHES[] == launches
            @test reused.frequencies == result.frequencies
            @test all(a.admittance == b.admittance for (a, b) in zip(reused.results, result.results))
            @test compute(model, scan; options = merge(options, (; resume_run_directory = :latest))).diagnostics.reused
            changed = ZToolScan(frequencies = [1, 2, 3, 4, 5, 6, 7, 9]; topology)
            @test_throws r"different inputs" compute(model, changed;
                options = merge(options, (; resume_run_directory = directory)))
            for name in ("ztool.toml", "pi#Y_AC#scan-1#.txt", "pi_angles.txt", "pi_power_flow.txt")
                path = joinpath(directory, "outputs", name)
                original = read(path)
                write(path, "changed sweep output")
                @test_throws r"output integrity" compute(model, scan;
                    options = merge(options, (; resume_run_directory = directory)))
                write(path, original)
            end
        end
        try
            scan = ZToolScan(frequencies = collect(1:8))
            for mode in (:ztool_version, :ztool_arguments, :ztool_frequencies, :ztool_grid_mismatch, :ztool_no_files)
                MODE[] = mode
                @test_throws ErrorException compute(model, scan; options)
                @test !isfile(joinpath(last(sort(readdir(options.work_root; join = true); by = mtime)), "complete.toml"))
            end
        finally
            MODE[] = :success
        end
    end
end

end
