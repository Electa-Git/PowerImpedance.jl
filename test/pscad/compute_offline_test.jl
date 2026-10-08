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
        write(joinpath(output, stem * ".inf"), "PGB(1) Output Desc=\\\"Voltage\\\" Group=\\\"main\\\" Units=\\\"kV\\\"\\nPGB(2) Output Desc=\\\"Current\\\" Group=\\\"main\\\" Units=\\\"kA\\\"\\n")
        rows = round(Int, settings["time_duration"] / (settings["sample_step_us"] * 1e-6)) + 1
        $(MODE[] === :incomplete) && (rows -= 1)
        open(joinpath(output, stem * "_01.out"), "w") do io
            println(io, "TIME Voltage Current")
            for index in 0:rows-1
                println(io, index * settings["sample_step_us"] * 1e-6, " 2.0D+0 3.0d-1")
            end
        end
        haskey(settings, "snapshot_time") && write(joinpath(output, stem * ".snp"), "snapshot fixture")
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
        @test input["project_name"] == "generated"
        @test input["project_sha256"] == bytes2hex(sha256(read(project)))
        @test input["probes"]["names"] == ["Voltage"]
        @test input["settings"]["time_step_us"] ≈ 50.0
        @test input["settings"]["sample_step_us"] ≈ 250.0
        @test input["settings"]["plot_type"] == "OUT"
        @test !haskey(input["settings"], "snapshot_time")
        @test Set(keys(input["toolkit"])) == Set(keys(P.PSCAD_REMOTE_SOURCES))
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
    end
end
end
