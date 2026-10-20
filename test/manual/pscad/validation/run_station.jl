# Explicit manual entry point; never called by the automated test suite.
using PythonCall
include("validation.jl")
timeouts = filter(arg -> startswith(arg, "--timeout="), ARGS)
length(timeouts) <= 1 || error("supply --timeout only once")
fixtures = filter(arg -> !startswith(arg, "--timeout="), ARGS)
isempty(fixtures) && error("usage: run_station.jl <fixture> [<fixture> ...] [--timeout=seconds]")
seconds = isempty(timeouts) ? (length(fixtures) > 1 ? 3600.0 : 5400.0) :
          parse(Float64, last(split(only(timeouts), '='; limit = 2)))
isfinite(seconds) && seconds > 0 || error("timeout must be finite and positive")
deadline = time() + seconds
if fixtures == ["passive"]
    PSCADValidation.run_passive(; deadline)
else
    "passive" in fixtures && error("passive must be the only fixture argument")
    for id in fixtures
        PSCADValidation.run_fixture(id; deadline)
    end
end
