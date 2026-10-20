module OHLGeometryTests
using Test, PowerImpedance, LinearAlgebra
const PI = PowerImpedance

@testset "Lifted OHL tower geometry" begin
    # These coordinates retain the local builders' physical order, including the
    # three-phase vertical layout's first vertical offset.
    cases = (
        (:flat, 2, [-5.0, 5.0], [30.0, 30.0]),
        (:flat, 3, [-10.0, 0.0, 10.0], [30.0, 30.0, 30.0]),
        (:flat, 6, [-10.0, 0.0, 10.0, -10.0, 0.0, 10.0],
            [30.0, 30.0, 30.0, 38.0, 38.0, 38.0]),
        (:vertical, 3, [5.0, 5.0, 5.0], [38.0, 46.0, 54.0]),
        (:vertical, 6, [5.0, 5.0, 5.0, -5.0, -5.0, -5.0],
            [30.0, 38.0, 46.0, 30.0, 38.0, 46.0]),
        (:delta, 3, [-5.0, 5.0, 0.0], [30.0, 38.0, 30.0]),
        (:delta, 6, [-8.0, -6.5, -5.0, 5.0, 6.5, 8.0],
            [30.0, 38.0, 30.0, 30.0, 38.0, 30.0]),
        (:concentric, 3, [-3.0, 0.0, 0.0], [38.0, 30.0, 46.0]),
        (:concentric, 6, [-8.0, -5.0, -5.0, 5.0, 5.0, 8.0],
            [38.0, 30.0, 46.0, 30.0, 46.0, 38.0]),
        (:offset, 3, [-3.0, 0.0, 0.0], [38.0, 30.0, 46.0]),
        (:offset, 6, [-8.0, -5.0, -5.0, 5.0, 5.0, 8.0],
            [38.0, 30.0, 46.0, 30.0, 46.0, 38.0]))
    for (organization, n, x, y) in cases
        c = Conductors(; organization, nᵇ = n, yᵇᶜ = 30, Δxᵇᶜ = 10,
            Δyᵇᶜ = 8, Δ̃xᵇᶜ = 3, dˢᵃᵍ = 10)
        @test PI._ohl_conductor_coordinates(c) == (x, y)
        c.dˢᵃᵍ = 0
        @test PI._ohl_conductor_coordinates(c) == (x, y)
    end
    for organization in (:flat, :vertical, :delta, :concentric, :offset)
        @test_throws ArgumentError PI._ohl_conductor_coordinates(
            Conductors(; organization, nᵇ = 1))
    end
    @test_throws ArgumentError PI._ohl_conductor_coordinates(Conductors())
    explicit = Conductors(nᵇ = 3, positions = ([-11, 1, 9], [28, 35, 31]), dˢᵃᵍ = 10)
    @test PI._ohl_conductor_coordinates(explicit) == ([-11.0, 1.0, 9.0], [28.0, 35.0, 31.0])
    @test_throws ArgumentError PI._ohl_conductor_coordinates(
        Conductors(nᵇ = 3, positions = ([1, 2], [30, 30, 30])))
    for (n, x) in ((0, Float64[]), (1, [0.0]), (2, [-3.25, 3.25]))
        tl = Overhead_line(; conductors = Conductors(yᵇᶜ = 30),
            groundwires = Groundwires(nᵍ = n, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10))
        @test PI._ohl_groundwire_coordinates(tl) == (x, fill(37.5, n))
    end
end

@testset "Lifted OHL regular bundles" begin
    @test PI._ohl_bundle_position(1, 0) == ([0.0], [0.0])
    for n in 2:15
        x, y = PI._ohl_bundle_position(n, 0.45)
        @test length(x) == length(y) == n
        @test hypot.(x, y) ≈ fill(0.45 / (2sin(π / n)), n)
        # Every adjacent pair, including the closing pair, has spacing dˢᵇ.
        @test all(
            i -> isapprox(hypot(x[i] - x[mod1(i + 1, n)],
                    y[i] - y[mod1(i + 1, n)]), 0.45), 1:n)
    end
    # At two subconductors the existing ordering starts on the negative x axis.
    x, y = PI._ohl_bundle_position(2, 0.45)
    @test x ≈ [-0.225, 0.225]
    @test all(abs.(y) .< 1e-15)
end
end
