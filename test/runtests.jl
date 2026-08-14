# using JLD2
using PowerImpedance
using Test
using LinearAlgebra
import PowerImpedance.NetworkBuilder
const NB = PowerImpedance.NetworkBuilder

const PI = PowerImpedance # Alias for easier access in tests

# CI can set POWERIMPEDANCE_TEST_LOG_LEVEL=error; the former variable remains supported.
using Logging
const TEST_LOG_LEVEL =
    lowercase(get(
        ENV,
        "POWERIMPEDANCE_TEST_LOG_LEVEL",
        get(ENV, "PIACDC_TEST_LOG_LEVEL", "warn"),
    )) == "error" ?
    Logging.Error : Logging.Warn
Logging.global_logger(ConsoleLogger(stderr, TEST_LOG_LEVEL))
TEST_LOG_LEVEL == Logging.Error && PowerImpedance._PMACDC.silence()

# Alternatively, set the package-only logging level to debug through an environment variable to avoid VS Code debug logging:
# ENV["JULIA_DEBUG"]=PowerImpedance # Warning: this will unfortunanelty not enable the debug logging for the ipopt solver.

@testset "Package name compatibility" begin
    @test nameof(PowerImpedance) === :PowerImpedance
    @test PowerImpedanceACDC === PowerImpedance
    @test PowerImpedance.PowerImpedanceACDC === PowerImpedance
end

@time @testset "PowerImpedance" begin
        
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
