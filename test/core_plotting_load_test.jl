using Test
using PowerImpedance

loaded_package_names = Set(nameof(module_value)
for module_value in values(Base.loaded_modules))

@testset "Core load excludes plotting backends" begin
    @test NetworkDiagramDefinition <: PlotBuilder.AbstractPlotDefinition
    @test :Makie ∉ loaded_package_names
    @test :CairoMakie ∉ loaded_package_names
    @test :GLMakie ∉ loaded_package_names
    @test :WGLMakie ∉ loaded_package_names
    @test :GraphMakie ∉ loaded_package_names
    @test :NetworkLayout ∉ loaded_package_names
    @test Base.get_extension(PowerImpedance, :PowerImpedanceMakieExt) === nothing
    @test Base.get_extension(PowerImpedance, :PowerImpedanceGraphMakieExt) === nothing
end
