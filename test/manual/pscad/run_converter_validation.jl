# One resumable station queue runs isolated timing first, then the fifteen converters.
using PowerImpedance, PythonCall
include("validation/validation.jl")
const V = PSCADValidation
length(ARGS) <= 1 || error("usage: run_converter_validation.jl [--timeout=seconds]")
seconds = isempty(ARGS) ? 43200.0 :
    startswith(only(ARGS), "--timeout=") ? parse(Float64, last(split(only(ARGS), '='))) :
    error("expected --timeout=seconds")
isfinite(seconds) && seconds > 0 || error("timeout must be finite and positive")
deadline = time() + seconds
remote = RemoteConfig()
V.run_timing(remote, deadline)
for id in ["tlc_pq_freq_support", "tlc_pf_q", "tlc_p_qv", "tlc_p_vac", "tlc_vdc_q", "tlc_pq_weak_grid", "mmc_pq", "mmc_pf_q", "mmc_p_qv", "mmc_p_vac", "mmc_vdc_q", "mmc_pq_weak_grid", "mmc_gfm_vsm", "mmc_gfm_lec_compensated", "mmc_pq_no_energy_control"]
    V.run_fixture(id; deadline)
end
