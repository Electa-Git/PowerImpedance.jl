module PSCADValidation

using PowerImpedance, LinearAlgebra, Statistics, Dates, SHA, TOML, Printf
using PowerImpedance: TYPEDSIGNATURES

const P = PowerImpedance.PSCAD
const ROOT = @__DIR__
const REPOSITORY = normpath(joinpath(ROOT, "../../../.."))
include("../../../pscad/fixtures.jl")
include("../../../pscad/m7_networks.jl")
include("fixtures.jl")
include("stability.jl")
include("settling.jl")
include("frequency.jl")
include("injection.jl")
include("records.jl")
include("coverage.jl")
include("phase.jl")
include("resonance.jl")
include("ports.jl")
include("execution.jl")
include("scan.jl")
include("interface_step.jl")
include("residual_step.jl")
include("timing.jl")
include("queue.jl")

end
