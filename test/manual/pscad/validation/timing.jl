# Isolated electrical DSOUT -> next DSDYN -> residual queue -> source witness.
const TIMING_DELAYS = (("zero", 0.0), ("one", 10e-6), ("four", 40e-6), ("fractional", 25e-6))

function timing_plan()
    settings = P.SimulationSettings(simulation_time = 0.02, time_step = 10e-6,
        sample_step = 10e-6, source_ramp = 0.0)
    canvas = P.CanvasPlan()
    graph = P.BlockGraph(P.ControlBlock[
        P.TimeStep(P.Signal("clock_s")),
        P.Compare(P.Signal("clock_s"), P.Signal("step_on"), 0.002),
        P.Gain(P.Signal("clock_s"), P.Signal("wave_angle"), 2pi*1000),
        P.Trig(P.Signal("wave_angle"), P.Signal("wave"), :sin),
        P.Gain(P.Signal("wave"), P.Signal("small_wave"), 0.1),
        P.Sum(P.Signal.(["step_on", "small_wave"]), [1, 1], P.Signal("input_command")),
        P._ConverterPhaseTransfer(P.Signal("V_input"), P.Signal("acquired"), :dsdyn, 1)])
    commands = [("input", "input_command")]
    for (name, tau) in TIMING_DELAYS
        residual = P._converter_export_delay(tau, settings.time_step; converter = Symbol("timing_" * name))
        output = P.Signal("command_" * name)
        push!(graph.nodes, iszero(residual) ? P.Gain(P.Signal("acquired"), output, 1.0) :
            P.Delay(P.Signal("acquired"), output, residual,
                ceil(Int, residual/settings.time_step)+1, 0.0))
        push!(commands, (name, output.name))
    end
    P.lower!(canvas, graph; origin = (900, 72))
    channels = P.ProbeChannel[]
    for (i, (name, command)) in enumerate(commands)
        y = 108 + 144*(i-1)
        params = ["Name" => "source_"*name, "Type"=>"6", "Grnd"=>"1", "Spec"=>"0",
            "Cntrl"=>"1", "AC"=>"0", "Tc"=>"0.0 [s]"]
        push!(canvas.components, P.ComponentPlan("master:source_1", params, 180, y, 4))
        P.stub!(canvas, (216, y), "node_"*name)
        P.module_signal_stub!(canvas, (180, y+36), command, -1)
        P.component!(canvas, "voltmetergnd", (360, y), ["Name"=>"V_"*name])
        P.stub!(canvas, (360, y), "node_"*name; direction = -1)
        P.output_probe!(canvas, "V_"*name, "timing", "kV", (540, y))
        push!(channels, P.ProbeChannel("V_"*name, :voltage, nothing, nothing, nothing, 1, "kV"))
    end
    probes = P.ProbeManifest(channels, nothing)
    plan = P.ProjectPlan("converter_timing", "One-step interface and residual delay timing",
        P._project_settings(settings, "Residual modulation timing"), canvas,
        P.AbstractLineDefinitionPlan[], P.AbstractLineWrapperPlan[], P.ModuleDefinitionPlan[], probes)
    return plan, settings
end

function prepare_timing(directory = joinpath(ROOT, "data", "m9c2", "timing"))
    plan, settings = timing_plan()
    path = joinpath(mkpath(directory), plan.name*".pscx")
    isfile(path) || P._write_project(plan, path)
    record = Dict{String, Any}("fixture_id"=>"M9c2-Timing", "source_files"=>source_record(),
        "expected_total_delays_s" => Dict("zero" => 10e-6, "one" => 10e-6,
            "four" => 40e-6, "fractional" => 30e-6),
        "rounding" => "nearest residual step; half-step ties upward (425e9b0)",
        "projects"=>[Dict("axis"=>"timing", "sha256"=>digest(path),
            "probes"=>probe_record.(plan.probes.channels))], "run_records"=>Dict{String, Any}[])
    isfile(joinpath(directory, "manifest.toml")) || write_manifest(directory, record)
    return P.PSCADModel(path; probes = plan.probes, settings), directory
end

function timing_comparison(time, channels, dt)
    input = channels["V_input"]
    rows = NamedTuple[]
    for (name, tau) in TIMING_DELAYS
        steps = iszero(tau) ? 1 : 1 + round(Int, (tau-dt)/dt, RoundNearestTiesUp)
        total = steps * dt
        # Ignore initial prehistory; nearest-step residual, half-step ties upward.
        indices = findall(t -> 0.001 <= t <= 0.018, time)
        reference = [input[i-steps] for i in indices]
        error = maximum(abs, channels["V_"*name][indices] - reference)
        push!(rows, (; name, model_delay_s = tau, expected_total_delay_s = total,
            max_voltage_error_kV = error, passed = error <= 1e-6))
    end
    return rows
end

function run_timing(remote, deadline; directory = joinpath(ROOT, "data", "m9c2", "timing"))
    model, directory = prepare_timing(directory)
    record = manifest_lists!(TOML.parsefile(joinpath(directory, "manifest.toml")))
    record["source_files"] == source_record() || error("timing witness source hashes changed")
    digest(model.project_path) == only(record["projects"])["sha256"] || error("timing project changed")
    result = execute_axis!(record, "timing", model, directory, remote, deadline)
    rows = timing_comparison(result.time, result.channels, model.settings.time_step)
    write_table(joinpath(directory, "comparison.tsv"), rows)
    all(row.passed for row in rows) || error("Residual-delay timing witness failed")
    return rows
end
