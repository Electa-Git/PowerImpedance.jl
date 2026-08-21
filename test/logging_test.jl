using Logging

@testset "portable log source paths" begin
    package_root = pkgdir(PowerImpedance)
    package_file = joinpath(package_root, "src", "Network", "power_flow.jl")
    @test PowerImpedance._display_log_path(package_file, package_root) ==
          "src/Network/power_flow.jl"
    @test PowerImpedance._display_log_path(
        "/builds/electa/controlgroup/PowerImpedance.jl/src/Network/NetworkBuilder/powerflow.jl",
        package_root
    ) == "src/Network/NetworkBuilder/powerflow.jl"

    buffer = IOBuffer()
    logger = PowerImpedance._relative_path_logger(SimpleLogger(buffer, Logging.Debug))
    Logging.handle_message(
        logger,
        Logging.Warn,
        "constraint warning",
        PowerImpedance,
        :logging_test,
        :portable_path,
        "/builds/runner/project/src/Network/NetworkBuilder/powerflow.jl",
        408
    )
    output = String(take!(buffer))
    @test occursin("src/Network/NetworkBuilder/powerflow.jl:408", output)
    @test !occursin("/builds/runner", output)
end
