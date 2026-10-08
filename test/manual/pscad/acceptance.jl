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
ohl_classic, ohl_state = PSCADFixtures.passive_ohl_network()
ohl_classic_model = export_pscad(ohl_classic;
    path = joinpath(exports, "passive_ohl_classic.pscx"))
ohl_builder_model = export_pscad(ohl_state;
    path = joinpath(exports, "passive_ohl_builder.pscx"))

for (model, classic_reference, rtol_v) in (
    (classic_model, classic_model, 0.01), (builder_model, classic_model, 0.01),
    (ohl_classic_model, ohl_classic_model, 0.02),
    (ohl_builder_model, ohl_classic_model, 0.02))
    result = compute(model,
        PSCADRun();
        options = (;
            remote, simulation_time = 0.3, time_step = 50e-6,
            sample_step = 250e-6, verbosity = 1))
    # NB.solve skips power flow for this linear fixture. Both representations
    # therefore compare against the equivalent classic circuit's solved record.
    reference = isempty(model.operating_point.bus_states) ? classic_reference : model
    comparison = compare_operating_point(result, reference; rtol_v)
    println(model.project_name)
    show(stdout, MIME("text/plain"), comparison)
    println()
    # Retain all measured errors, including the OHL case's 2% voltage check.
    open(joinpath(exports, model.project_name * "_comparison.tsv"), "w") do io
        println(io, "quantity\tname\tpscad\tpowerflow\terror\twithin_tolerance")
        for row in comparison
            println(io, join(values(row), '\t'))
        end
    end
    all(comparison.within_tolerance) ||
        error("PSCAD acceptance failed for $(model.project_name)")
end
