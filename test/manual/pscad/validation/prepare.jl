# Local generation only; this script never constructs RemoteConfig or computes PSCADRun.
using PythonCall
include("validation.jl")
length(ARGS) == 1 || error("usage: prepare.jl <fixture>")
for id in (only(ARGS) == "L1" ? [entry.id for entry in PSCADValidation.REGISTRY] :
           [only(ARGS)])
    PSCADValidation.prepare_fixture(id)
end
