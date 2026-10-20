# Manual smoke test; never included by Pkg.test(). `julia --project
# test/manual/pscad/run_station.jl [--identify]`
using PowerImpedance
const PSCAD = PowerImpedance.PSCAD

remote = RemoteConfig() # Requires POWERIMPEDANCE_PSCAD_CONFIG.
"--identify" in ARGS && println("Station identity: ", PSCAD.identify(remote))
path = PSCAD.fetch_station_file(remote,
    raw"C:\Users\Public\Documents\PSCAD\5.1.0\Examples\tutorial\vdiv.pscx",
    joinpath(remote.local_root, "inputs", "vdiv.pscx"))
result = compute(PSCADModel(path),
    PSCADRun();
    options = (;
        remote, simulation_time = 0.5, time_step = 50e-6, sample_step = 250e-6, verbosity = 2))
println("Channels: ", collect(keys(result.channels)))
println("Rows: ", length(result.time))
println("Elapsed project.run() [s]: ", result.diagnostics.elapsed_seconds)
println("solver.toml:\n", read(joinpath(result.paths.outputs, "solver.toml"), String))
println("Paths: ", result.paths)
