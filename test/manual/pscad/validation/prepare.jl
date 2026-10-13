# Local generation only; this script never constructs RemoteConfig or computes PSCADRun.
using PythonCall
include("validation.jl")
resonance = "--resonance" in ARGS
fixtures = filter(!=("--resonance"), ARGS)
length(fixtures) == 1 || error("usage: prepare.jl <fixture> [--resonance]")
for id in (only(fixtures) == "L1" ? [entry.id for entry in PSCADValidation.REGISTRY if startswith(entry.id,"L1-")] :
           [only(fixtures)])
    if resonance
        id == "L1-08" || error("resonance preparation is restricted to L1-08")
        PSCADValidation.prepare_resonance_fixture()
    else
        PSCADValidation.prepare_fixture(id)
    end
end
