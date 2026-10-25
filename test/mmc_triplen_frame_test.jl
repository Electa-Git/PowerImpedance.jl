if !isdefined(@__MODULE__, :build_compensated_mmc_grid)
    include("adm_MMC_compensated_test.jl")
end

@testset "Compensated MMC Δ-triplen frame stability" begin
    # The independent compensated-admittance fixture is defined in the
    # preceding test file; keep its original Δ PI gains, Kp=0.5544, Ki=5.94.
    network = build_compensated_mmc_grid()
    element = network.elements[:DUT]
    delta = element.sigma_control.wdelta
    @test delta.pi_control.Kp == 0.4 * 1.386
    @test delta.pi_control.Ki == 0.2 * 29.70
    poles = eigvals(element.cache.A)
    @test all(pole -> real(pole) < 0, poles)
    # Require at least 1 s^-1 damping for the 150 Hz conjugate pair.
    triplen = filter(pole -> abs(abs(imag(pole)) / (2π) - 150) < 5, poles)
    @test !isempty(triplen)
    @test all(pole -> real(pole) <= -1, triplen)
end
