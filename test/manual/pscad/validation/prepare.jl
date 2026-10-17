# Local generation only; this script never constructs RemoteConfig or computes PSCADRun.
using PythonCall
include("validation.jl")
resonance = "--resonance" in ARGS
fixtures = filter(!=("--resonance"), ARGS)
length(fixtures) == 1 || error("usage: prepare.jl <fixture> [--resonance]")
for id in (only(fixtures) == "passive" ? [entry.id for entry in PSCADValidation.REGISTRY if entry.category == :passive] :
           [only(fixtures)])
    if resonance
        id == "ieee9_bus_impedance" || error("resonance preparation is restricted to ieee9_bus_impedance")
        PSCADValidation.prepare_resonance_fixture()
    else
        PSCADValidation.prepare_fixture(id)
    end
end
