# Manual real-station acceptance; never included in the automatic test suite.
# Use a Julia environment containing PowerImpedance and PythonCall, and set
# POWERIMPEDANCE_PSCAD_CONFIG to the station configuration TOML.
using PowerImpedance, PythonCall
include("../../pscad/fixtures.jl")

remote = RemoteConfig()
exports = mktempdir(mkpath(joinpath(remote.local_root, "exports"));
    prefix = "m1-", cleanup = false)
classic, state = PSCADFixtures.small_ac_network()
classic_model = export_pscad(classic; path = joinpath(exports, "small_ac_classic.pscx"))
builder_model = export_pscad(state; path = joinpath(exports, "small_ac_builder.pscx"))

for model in (classic_model, builder_model)
    result = compute(model,
        PSCADRun();
        options = (;
            remote, simulation_time = 0.3, time_step = 50e-6,
            sample_step = 250e-6, verbosity = 1))
    # NB.solve skips power flow for this linear fixture. Both representations
    # therefore compare against the equivalent classic circuit's solved record.
    reference = isempty(model.operating_point.bus_states) ? classic_model : model
    comparison = compare_operating_point(result, reference)
    println(model.project_name)
    show(stdout, MIME("text/plain"), comparison)
    println()
    all(comparison.within_tolerance) ||
        error("PSCAD acceptance failed for $(model.project_name)")
end
