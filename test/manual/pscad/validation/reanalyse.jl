# Stored-output analysis only. This entry point never calls native compute.
using PowerImpedance, TOML
include("validation.jl")
refresh = "--refresh-reference" in ARGS
fixtures = filter(!=("--refresh-reference"), ARGS)
length(fixtures) == 1 || error("usage: reanalyse.jl <fixture|passive> [--refresh-reference]")
ids = only(fixtures) == "passive" ?
      [entry.id for entry in PSCADValidation.REGISTRY if entry.category == :passive] : fixtures
for id in ids
    if refresh
        PSCADValidation.refresh_references(id)
    else
        PSCADValidation.reanalyse_fixture(id)
    end
end
