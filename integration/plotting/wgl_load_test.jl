using Test
using PowerImpedance
using WGLMakie

@testset "WGLMakie extension load" begin
    @test Base.get_extension(PowerImpedance, :PowerImpedanceMakieExt) !== nothing
    @test Base.get_extension(PowerImpedance, :PowerImpedanceWGLMakieExt) !== nothing
    @test PowerImpedance.PlotBuilder.BackendHandler.backend_available(:wgl)
    @test set_backend!(:wgl) === :wgl
    @test PowerImpedance.PlotBuilder.BackendHandler.current_backend_symbol() === :wgl
end
