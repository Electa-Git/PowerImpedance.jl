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
for n in 1:15
    V.run_fixture("L2-"*lpad(n, 2, '0'); deadline)
end
