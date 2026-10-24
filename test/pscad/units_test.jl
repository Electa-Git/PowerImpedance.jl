using Test
using PowerImpedance

@testset "PSCAD SI parameters and names" begin
    pscad = PowerImpedance.PSCAD
    mmc = ElectricalMMC(; Lₐᵣₘ = 0.037, Rₐᵣₘ = 0.82, Cₐᵣₘ = 0.006,
        Lᵣ = 0.045, Rᵣ = 0.37, N = 260, turnsRatio = 0.8,
        Sbase = 730, vACbase_LL_RMS = 275, vDC_base = 810, ωbase = 2π * 60)
    recovered = pscad.mmc_si(mmc)
    @test recovered.L_arm ≈ 0.037
    @test recovered.R_arm ≈ 0.82
    @test recovered.C_SM ≈ 0.006
    @test recovered.L_r ≈ 0.045
    @test recovered.R_r ≈ 0.37
    @test recovered.N == 260
    @test recovered.turnsRatio == 0.8
    @test recovered.Sbase == 730
    @test recovered.vAC_base_LL_RMS ≈ 275
    @test recovered.vDC_base == 810
    @test recovered.ωbase == 2π * 60

    tlc = ElectricalTLC(; Lᵣ = 0.017, Rᵣ = 0.24,
        Sbase = 340, vACbase_LL_RMS = 165, vDCbase = 470, ωbase = 2π * 60)
    recovered_tlc = pscad.tlc_si(tlc)
    @test recovered_tlc.L_r ≈ 0.017
    @test recovered_tlc.R_r ≈ 0.24
    @test recovered_tlc.Sbase == 340
    @test recovered_tlc.vAC_base_LL_RMS ≈ 165
    @test recovered_tlc.vDC_base == 470
    @test recovered_tlc.ωbase == 2π * 60
    @test recovered_tlc.l_f_pu == tlc.Lᵣ
    @test recovered_tlc.r_f_pu == tlc.Rᵣ

    machine = ElectricalSM(; Ra = 0.007, Ll = 0.18, La_d = 1.7, Rf_d = 0.002,
        Lf_d = 0.23, R1_d = 0.031, L1_d = 0.19, L23_d = 0.011,
        La_q = 1.5, R1_q = 0.008, L1_q = 0.65, R2_q = 0.015,
        L2_q = 0.13, L23_q = 0.012)
    table = pscad.sm_equivalent_circuit(machine)
    @test table isa PowerImpedance.OrderedDict{String, Float64}
    @test collect(keys(table)) == ["Rs1", "XS1", "XMD0", "R2D", "X2D", "R3D",
        "X3D", "X230", "XMQ", "R2Q", "X2Q", "R3Q", "X3Q", "X231"]
    @test collect(values(table)) == [0.007, 0.18, 1.7, 0.002, 0.23, 0.031, 0.19,
        0.011, 1.5, 0.008, 0.65, 0.015, 0.13, 0.012]

    transformer = PowerImpedance.Transformer(; n = 2.0, organization = :ΔY,
        Lₚ = 0.001, Rₚ = 0.2, Lₛ = 0.002, Rₛ = 0.3, Lₘ = 2.0, Rₘ = 300,
        Cₜ = 1e-9, Cₛ = 2e-9, ω = 2π * 60)
    @test pscad.transformer_si(transformer) == (L_p = 0.001, R_p = 0.2,
        L_s = 0.002, R_s = 0.3, L_m = 2.0, R_m = 300.0,
        C_t = 1e-9, C_s = 2e-9, n = 2.0, organization = :ΔY, ω = 2π * 60)
    transformer.hasRω = true
    @test_throws ArgumentError pscad.transformer_si(transformer)
    transformer.hasRω = false
    for ratio in (0.0, -1.0)
        transformer.n = ratio
        @test_throws ArgumentError pscad.transformer_si(transformer)
    end

    @test pscad.pscad_value(1.23456789123) == "1.23456789"
    @test pscad.pscad_value(1.23456789123; unit = "H") == "1.23456789 [H]"
    @test pscad.pscad_value(1.23456789123; sigdigits = 4) == "1.235"
    @test pscad.pscad_value(2) == "2"
    @test pscad.pscad_value(2.0) == "2.0"
    @test pscad.pscad_value(-0.25; unit = "Ohm") == "-0.25 [Ohm]"
    @test pscad.pscad_value(1e-12) == "1.0E-12"
    @test pscad.pscad_value(1.23e-6) == "1.23E-6"
    @test pscad.pscad_value(1.23e8) == "1.23E8"
    @test pscad.pscad_value(1e-4) == "0.0001"
    @test pscad.pscad_value(1e6) == "1000000.0"
    @test pscad.pscad_value(1e7) == "1.0E7"
    @test pscad.pscad_value(0.0) == "0.0"
    @test pscad.pscad_value(-1e-5; unit = "H") == "-1.0E-5 [H]"
    @test pscad.pscad_value(1e-300) == "1.0E-300"
    @test pscad.pscad_value(1e300) == "1.0E300"
    for value in (Inf, -Inf, NaN)
        @test_throws ArgumentError pscad.pscad_value(value)
    end
    @test_throws ArgumentError pscad.pscad_value(1.2; sigdigits = 0)

    @test pscad.pscad_name(:Lₐᵣₘ) == "Larm"
    @test pscad.pscad_name(:ΔΣθω) == "DSthetaomega"
    @test pscad.pscad_name(:αβΓΩ) == "alphabetaGammaOmega"
    @test pscad.pscad_name(Symbol("v₀₁²³ᵉᶻᴬ")) == "v0123ezA"
    @test pscad.pscad_name(Symbol("1-load")) == "X1_load"
    @test pscad.pscad_name(Symbol("_x")) == "X_x"
    @test pscad.pscad_name(Symbol("汉字")) == "X"
    @test pscad.pscad_name(Symbol("A汉B")) == "AB"
    @test pscad.pscad_name(Symbol("source with.dot")) == "source_with_dot"
    used = pscad._NameReservations()
    @test pscad.pscad_name(:x; used) == "x"
    @test pscad.pscad_name(:x; used) == "x_2"
    @test pscad.pscad_name(:x; used) == "x_3"
    long = "A"^35
    @test pscad.pscad_name(long; used) == "A"^30
    @test pscad.pscad_name(long; used) == "A"^28 * "_2"
    for _ in 1:12
        @test length(pscad.pscad_name(long; used)) <= 30
    end
    @test length(used) == 17
    @test all(name -> occursin(r"^[A-Za-z][A-Za-z0-9_]{0,29}$", name), used)
    # Reservations retain their spelling but compare as Fortran identifiers.
    case_used = pscad._NameReservations(["Bus", "BUS_2", "Probe"])
    @test pscad.pscad_name("bus"; used = case_used) == "bus_3"
    @test pscad.pscad_name("probe"; used = case_used) == "probe_2"
    @test pscad.pscad_name("PROBE"; used = case_used) == "PROBE_3"
    @test Set(["Bus", "BUS_2", "Probe"]) ⊆ case_used
    @test length(unique(lowercase.(collect(case_used)))) == length(case_used)
    long_used = pscad._NameReservations(["A"^30])
    @test pscad.pscad_name("a"^35; used = long_used) == "a"^28 * "_2"
    @test pscad.pscad_name("A"^35; used = long_used) == "A"^28 * "_3"
    seeded = pscad._NameReservations(["Seed", "SEED"])
    @test "seed" in seeded
    @test length(seeded) == 1
    @test only(seeded) == "Seed"
    push!(seeded, "sEeD")
    @test only(seeded) == "Seed"
    @test pscad.pscad_name("SEED"; used = seeded) == "SEED_2"
    @test pscad.bus_name([:B3d, :B3q]) == "B3"
    @test pscad.bus_name([:B1c, :B1a, :B1b]) == "B1"
    @test pscad.bus_name([:DC₁]) == "DC1"
    @test pscad.bus_name([:B1d, :B2q]) === nothing
    @test pscad.bus_name([:B1a, :B1b]) === nothing
    @test pscad.bus_name([:d, :q]) === nothing
    @test pscad.bus_name(Symbol[]) === nothing
    @test pscad.voltage_probe_name("B1") == "V_B1"
    @test pscad.current_probe_name("line1", :side2) == "I_line1_side2"
end
