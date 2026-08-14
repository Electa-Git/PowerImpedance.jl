# using JLD2
using PowerImpedanceACDC
using Test
using LinearAlgebra
import PowerImpedanceACDC.NetworkBuilder
const NB = PowerImpedanceACDC.NetworkBuilder

const PIACDC = PowerImpedanceACDC # Alias for easier access in tests

# CI can set PIACDC_TEST_LOG_LEVEL=error; local runs retain warning output.
using Logging
const TEST_LOG_LEVEL =
    lowercase(get(ENV, "PIACDC_TEST_LOG_LEVEL", "warn")) == "error" ?
    Logging.Error : Logging.Warn
Logging.global_logger(ConsoleLogger(stderr, TEST_LOG_LEVEL))
TEST_LOG_LEVEL == Logging.Error && PowerImpedanceACDC._PMACDC.silence()

# Alternatively, you can set the logging level to debug for the PIACDC package only (to avoid vscode debug logging) via an environment variable:
# ENV["JULIA_DEBUG"]=PowerImpedanceACDC # Warning: this will unfortunanelty not enable the debug logging for the ipopt solver.


@time @testset "PowerImpedanceACDC" begin
        
        include("imp_test.jl")
        include("adm_MMC_test.jl")
        include("adm_MMC_compensated_test.jl")
        include("solvers_test.jl")
        include("adm_OHL_test.jl")
        include("adm_DC_cable_test.jl")
        include("adm_TLC_test.jl")
        include("adm_SM_test.jl")
        include("adm_IM_test.jl")
        include("Impedance_test.jl")
        include("Source_test.jl")
        include("NetworkBuilder_test.jl")
        include("ConnectionRegistry_test.jl")
        include("convert_pmacdc_test.jl")
        include("make_y_node_test.jl")
        include("Transformer_test.jl")
        include("logging_test.jl")
        include("Gridspace_test.jl")
        include("small_signal_gridspace_test.jl")
        
end;
