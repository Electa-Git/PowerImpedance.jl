module PSCADValidation

using PowerImpedance, LinearAlgebra, Statistics, Dates, SHA, TOML, Printf
using PowerImpedance: TYPEDSIGNATURES, eval_abcd

const P = PowerImpedance.PSCAD
const ROOT = @__DIR__
const REPOSITORY = normpath(joinpath(ROOT, "../../../.."))
include("../../../pscad/fixtures.jl")
include("../../../pscad/networks.jl")
include("fixtures.jl")
include("stability.jl")
include("settling.jl")
include("frequency.jl")
include("injection.jl")
include("records.jl")
include("coverage.jl")
include("induction_machine.jl")
include("phase.jl")
include("resonance.jl")
include("ports.jl")
include("execution.jl")
include("scan.jl")
include("interface_step.jl")
include("residual_step.jl")
include("timing.jl")
include("queue.jl")
include("composed_network.jl")
include("composed_measurement.jl")
include("composed_execution.jl")
include("time_domain.jl")
include("time_domain_offline.jl")
include("line_chain.jl")
include("system_factories.jl")
include("system_measurement.jl")
include("system_screens.jl")
include("growth.jl")
include("systems.jl")
include("ztool.jl")

end
