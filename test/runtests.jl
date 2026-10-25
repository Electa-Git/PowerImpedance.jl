# using JLD2
ENV["GKSwstype"] = "100"
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
if TEST_LOG_LEVEL == Logging.Error && isdefined(PowerImpedance._PMACDC, :silence)
    PowerImpedance._PMACDC.silence()
end

# Alternatively, set the package-only logging level to debug through an environment variable to avoid VS Code debug logging:
# ENV["JULIA_DEBUG"]=PowerImpedance # Warning: this will unfortunanelty not enable the debug logging for the ipopt solver.

@test nameof(PowerImpedance) === :PowerImpedance

@time @testset "PowerImpedance" begin
    @testset "api_guard_test.jl" begin
        include("api_guard_test.jl")
    end
    @testset "aqua.jl" begin
        include("aqua.jl")
    end
    @testset "docstring_examples_test.jl" begin
        include("docstring_examples_test.jl")
    end
    @testset "plotbuilder_test.jl" begin
        include("plotbuilder_test.jl")
    end
    @testset "imp_test.jl" begin
        include("imp_test.jl")
    end
    @testset "adm_MMC_test.jl" begin
        include("adm_MMC_test.jl")
    end
    @testset "adm_MMC_compensated_test.jl" begin
        include("adm_MMC_compensated_test.jl")
    end
    @testset "mmc_triplen_frame_test.jl" begin
        include("mmc_triplen_frame_test.jl")
    end
    @testset "mmc_scaling_test.jl" begin
        include("mmc_scaling_test.jl")
    end
    @testset "solvers_test.jl" begin
        include("solvers_test.jl")
    end
    @testset "transmission_line_abcd_test.jl" begin
        include("transmission_line_abcd_test.jl")
    end
    @testset "adm_OHL_test.jl" begin
        include("adm_OHL_test.jl")
    end
    @testset "adm_DC_cable_test.jl" begin
        include("adm_DC_cable_test.jl")
    end
    @testset "adm_TLC_test.jl" begin
        include("adm_TLC_test.jl")
    end
    @testset "converter_voltage_test.jl" begin
        include("converter_voltage_test.jl")
    end
    @testset "power_flow_fallback_test.jl" begin
        include("power_flow_fallback_test.jl")
    end
    @testset "power_flow_start_test.jl" begin
        include("power_flow_start_test.jl")
    end
    @testset "power_flow_idempotence_test.jl" begin
        include("power_flow_idempotence_test.jl")
    end
    @testset "pscad/power_flow_idempotence_test.jl" begin
        include("pscad/power_flow_idempotence_test.jl")
    end
    @testset "tlc_initialization_test.jl" begin
        include("tlc_initialization_test.jl")
    end
    @testset "dc_voltage_support_test.jl" begin
        include("dc_voltage_support_test.jl")
    end
    @testset "blackbox_mmc_test.jl" begin
        include("blackbox_mmc_test.jl")
    end
    @testset "model_declarations_test.jl" begin
        include("model_declarations_test.jl")
    end
    @testset "model_predicates_test.jl" begin
        include("model_predicates_test.jl")
    end
    @testset "terminal_values_test.jl" begin
        include("terminal_values_test.jl")
    end
    @testset "adm_SM_test.jl" begin
        include("adm_SM_test.jl")
    end
    @testset "synchronous_machine_operating_point_test.jl" begin
        include("synchronous_machine_operating_point_test.jl")
    end
    @testset "adm_IM_test.jl" begin
        include("adm_IM_test.jl")
    end
    @testset "induction_machine_power_flow_test.jl" begin
        include("induction_machine_power_flow_test.jl")
    end
    @testset "Impedance_test.jl" begin
        include("Impedance_test.jl")
    end
    @testset "Source_test.jl" begin
        include("Source_test.jl")
    end
    @testset "NetworkBuilder_test.jl" begin
        include("NetworkBuilder_test.jl")
    end
    @testset "ConnectionRegistry_test.jl" begin
        include("ConnectionRegistry_test.jl")
    end
    @testset "calculation_model_test.jl" begin
        include("calculation_model_test.jl")
    end
    @testset "network_model_test.jl" begin
        include("network_model_test.jl")
    end
    @testset "parity_test.jl" begin
        include("parity_test.jl")
    end
    @testset "convert_pmacdc_test.jl" begin
        include("convert_pmacdc_test.jl")
    end
    @testset "make_y_node_test.jl" begin
        include("make_y_node_test.jl")
    end
    @testset "Transformer_test.jl" begin
        include("Transformer_test.jl")
    end
    @testset "transformer_dy_test.jl" begin
        include("transformer_dy_test.jl")
    end
    @testset "regressions_test.jl" begin
        include("regressions_test.jl")
    end
    @testset "logging_test.jl" begin
        include("logging_test.jl")
    end
    @testset "Gridspace_test.jl" begin
        include("Gridspace_test.jl")
    end
    @testset "stability_plot_recipes_test.jl" begin
        include("stability_plot_recipes_test.jl")
    end
    @testset "pscad/runtests.jl" begin
        include("pscad/runtests.jl")
    end
    @testset "steady_state_test.jl" begin
        include("steady_state_test.jl")
    end
end;
