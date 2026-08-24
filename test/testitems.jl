using TestItems

@testitem "Gridspace smoke" begin
    using PowerImpedance
    NB = PowerImpedance.NetworkBuilder

    @test collect(NB.Grid([1, 2])) == [1, 2]
    @test length(impedance(Grid; z=Grid([1, 2]), pins=1)) == 2
end
