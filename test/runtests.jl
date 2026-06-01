# using JLD2
using PowerImpedanceACDC
using Test
using LinearAlgebra

const PIACDC = PowerImpedanceACDC # Alias for easier access in tests

# Uncomment the following line to change logging level:
# using Logging
# Logging.global_logger(ConsoleLogger(stderr, Logging.Warn)) # possible values: Logging.Debug, Logging.Info, Logging.Warn, Logging.Error

# Alternatively, you can set the logging level to debug for the PIACDC package only (to avoid vscode debug logging) via an environment variable:
# ENV["JULIA_DEBUG"]=PowerImpedanceACDC # Warning: this will unfortunanelty not enable the debug logging for the ipopt solver.


@time @testset "PowerImpedanceACDC" begin
        
        include("imp_test.jl")
        include("adm_MMC_test.jl")
        include("adm_MMC_compensated_test.jl")
        include("bipolar_mmc_test.jl")
        include("solvers_test.jl")
        include("adm_OHL_test.jl")
        include("adm_DC_cable_test.jl")
        include("adm_TLC_test.jl")
        include("Impedance_test.jl")
        include("Source_test.jl")
        include("NetworkBuilder_test.jl")
        include("ConnectionRegistry_test.jl")
        include("make_y_node_test.jl")
        include("Transformer_test.jl")
        #include("power_flow_test.jl")
        
end;
