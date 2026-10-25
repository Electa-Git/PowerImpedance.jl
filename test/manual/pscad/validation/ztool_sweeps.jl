# Local preparation and analysis are separate from explicit station execution.
using PythonCall
include("validation.jl")
const V = PSCADValidation

function main(arguments)
    length(arguments) >= 2 || error("usage: ztool_sweeps.jl <prepare|run|reanalyse|estimates> <case> [<case> ...] [--timeout=seconds]")
    action = first(arguments)
    timeouts = filter(arg -> startswith(arg, "--timeout="), arguments[2:end])
    length(timeouts) <= 1 || error("supply --timeout once")
    ids = filter(arg -> !startswith(arg, "--timeout="), arguments[2:end])
    ids == ["components"] && (ids = V.ztool_component_ids())
    all(id -> id in V.ztool_component_ids(), ids) || error("select component case ids from the registry")
    seconds = isempty(timeouts) ? 14400.0 : parse(Float64, split(only(timeouts), '='; limit = 2)[2])
    isfinite(seconds) && seconds > 0 || error("timeout must be finite and positive")
    deadline = time() + seconds
    action in ("prepare", "run", "reanalyse", "estimates") || error("unknown action $action")
    remote = action == "run" ? V.RemoteConfig() : nothing
    failures = String[]
    for id in ids
        if action == "prepare"
            V.prepare_ztool(id)
        elseif action in ("run", "reanalyse")
            try
                record = action == "run" ? V.run_ztool(id; remote, deadline) : V.reanalyse_ztool(id)
                println(id, ": ", record["status"])
            catch failure
                failure isa InterruptException && rethrow()
                push!(failures, id)
                println(id, ": analysis_or_run_failed: ", sprint(showerror, failure))
            end
        else
            net = V.fixture(id).factory()
            list = V.fixture_netlist(net, V.compute(PowerFlowProblem(net), ACDCPowerFlow()))
            definition = V.ztool_definition(id, net, list)
            estimate = V.ztool_estimate(definition)
            println(id, '\t', estimate.estimated_minutes, '\t', estimate.low_minutes,
                '\t', estimate.high_minutes, '\t', estimate.simulations,
                '\t', estimate.simulated_seconds, '\t', definition.settings.time_step,
                '\t', definition.scan.snapshot_time, '\t', definition.scan.start_fft)
        end
    end
    isempty(failures) || error("Z-tool runs did not complete: " * join(failures, ", "))
end

main(ARGS)
