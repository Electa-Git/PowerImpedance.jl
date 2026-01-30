using JLD2
using PowerImpedanceACDC
using Test
using LinearAlgebra


@testset "PowerImpedanceACDC" begin
        
        include("imp_test.jl")
        include("adm_MMC_test.jl")
        include("solvers_test.jl")
        include("adm_OHL_test.jl")
        include("adm_DC_cable_test.jl")
        include("adm_TLC_test.jl")
        include("Impedance_test.jl")
        include("Source_test.jl")
        include("Transformer_test.jl")
        include("power_flow_test.jl")

end

