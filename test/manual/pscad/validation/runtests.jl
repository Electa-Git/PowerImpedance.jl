# Tests of the Julia–PSCAD validation harness. They do not contact a station.
# From the repository root:
#   julia --project=test/manual/pscad/validation test/manual/pscad/validation/runtests.jl
using Test, PowerImpedance

const PSCAD_TESTS = normpath(joinpath(@__DIR__, "..", "..", "..", "pscad"))

@testset "PSCAD validation harness" begin
    include(joinpath(PSCAD_TESTS, "fixtures.jl"))
    include(joinpath(PSCAD_TESTS, "validation_test.jl"))
    include(joinpath(PSCAD_TESTS, "validation_induction_machine_test.jl"))
    include(joinpath(PSCAD_TESTS, "orientation_test.jl"))
end
