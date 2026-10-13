# Stored-output analysis only. This entry point never calls native compute.
using PowerImpedance, TOML
include("validation.jl")
length(ARGS) == 1 || error("usage: reanalyse.jl <fixture|L1>")
ids = only(ARGS) == "L1" ? [entry.id for entry in PSCADValidation.REGISTRY] : ARGS
for id in ids
    PSCADValidation.reanalyse_fixture(id)
end
