# Offline XML readback through the same existing reader as exporter tests.
using PythonCall, Test, PowerImpedance, TOML
include("validation.jl")
const V = PSCADValidation
const P = PowerImpedance.PSCAD
@testset "All validation written project XML" begin
    for entry in (isempty(ARGS) ? V.REGISTRY : V.fixture.(ARGS))
        directory = joinpath(V.ROOT, "data", entry.id)
        if !isfile(joinpath(directory,"manifest.toml")) && isfile(joinpath(directory,"stability_rejected.toml"))
            rejected=TOML.parsefile(joinpath(directory,"stability_rejected.toml"))
            @test rejected["gate"]["status"]=="failed"
            println("Skipped ",entry.id,": complete-network stability gate failed")
            continue
        end
        record = TOML.parsefile(joinpath(directory, "manifest.toml"))
        baseline = read(
            joinpath(directory, only(filter(p->p["axis"]==(isempty(get(record["tier_c"], "protocol", "")) ? "baseline" : record["tier_c"]["protocol"] * "_baseline"), record["projects"]))["path"]),
            String)
        for project in record["projects"]
            path = joinpath(directory, project["path"])
            summary = P.read_project_summary(path)
            @test parse(Float64, summary.settings["time_step"]) ==
                  project["settings"]["time_step_us"]
            @test summary.settings["sample_step"] == P.pscad_value(project["settings"]["sample_step_us"])
            if startswith(project["axis"],"abc_resonance_")
                @test length(summary.pgbs)==2
                @test sum(c["components"] for c in project["probes"])==6
                @test parse(Float64,summary.settings["sample_step"])≈64.0
            end
            @test length(summary.pgbs) >= length(project["probes"])
            @test V.digest(path) == project["sha256"]
            # Every non-baseline project is an exact clone with only amplitude
            # instance values changed; physical components and IDs are identical.
            actual = read(path, String)
            normalized = replace(actual,
                r"(<param name=\"(?:[abcdq]_amplitude_pu|amplitude_pu)\" value=\")[^\"]+(\"/>)"=>s"\g<1>0.0\g<2>")
            baseline_axis = get(project, "baseline_axis", "")
            matching_baseline = !isempty(baseline_axis) ? read(joinpath(directory, baseline_axis,
                lowercase(replace(entry.id, '-'=>'_')) * ".pscx"), String) :
                                startswith(project["axis"], "half_step_") ?
                                read(
                joinpath(directory, first(split(project["axis"], "__")) * "__baseline",
                    lowercase(replace(entry.id, '-'=>'_')) * ".pscx"),
                String) : baseline
            @test normalized == matching_baseline
        end
    end
end
