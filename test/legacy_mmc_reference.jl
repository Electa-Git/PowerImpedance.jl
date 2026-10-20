# Independent MMC formulas run in a separate namespace with their generated- expression
# callbacks. The nested callback has out-of-scope variables. Equations, controller
# parameters and MMC solver settings remain unchanged.
module LegacyMMCReference
using PowerImpedance: Controller, PI_control, CCQSEM, FFVI
using PowerImpedance.Parameters: @with_kw
using LinearAlgebra
import PowerImpedance
const Converter = PowerImpedance.Converter
const VSE = PowerImpedance.VSE_old
const OrderedDict = PowerImpedance.OrderedDict
const NonlinearProblem = PowerImpedance.NonlinearProblem
const solve = PowerImpedance.solve
const TrustRegion = PowerImpedance.NonlinearSolve.TrustRegion
const SciMLBase = PowerImpedance.SciMLBase
const ForwardDiff = PowerImpedance.ForwardDiff

source = read(joinpath(pkgdir(PowerImpedance), "src/Network/Components/converter/MMC_legacy.jl"), String)
source = first(split(source, "function state_space!(F,x,inputs;converter, solver)")) * "\n" *
    last(split(source, "#######################################################Creating function call and inputs"))
source = replace(source,
    "g!(du,u,p) = state_space!(du,u, p[1];converter=p[2], solver=p[3])" =>
    "g!(du,u,p) = f!(exp_steadyState, du, u, p[1])",
    "h(F,x) = state_space!(F, x[1:end-3], x[end-2:end];converter, solver=:jacobian)" =>
    "h(F,x) = f!(exp, F, x[1:end-3], x[end-2:end])")
Base.include_string(@__MODULE__, source, "legacy_mmc_reference_equations.jl")
filter_source = read(joinpath(pkgdir(PowerImpedance), "src/Network/Components/converter/filter.jl"), String)
Base.include_string(@__MODULE__, "function butterworthMatrices" *
    last(split(filter_source, "function butterworthMatrices")), "legacy_butterworth_reference.jl")
end
