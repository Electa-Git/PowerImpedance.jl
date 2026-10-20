using Test
using PowerImpedance
using LinearAlgebra

@testset "PSCAD RLC identification" begin
    pscad = PowerImpedance.PSCAD
    R, L, C = 12.0, 0.012, 8e-5
    cases = (
        (s -> R, :series, R, nothing, nothing),
        (s -> s * L, :series, nothing, L, nothing),
        (s -> 1 / (s * C), :series, nothing, nothing, C),
        (s -> R + s * L, :series, R, L, nothing),
        (s -> R + 1 / (s * C), :series, R, nothing, C),
        (s -> s * L + 1 / (s * C), :series, nothing, L, C),
        (s -> R + s * L + 1 / (s * C), :series, R, L, C),
        (s -> 1 / (1 / R + s * C), :parallel, R, nothing, C),
        (s -> s * L * R / (R + s * L), :parallel, R, L, nothing),
        (s -> 1 / (s * C + 1 / (s * L)), :parallel, nothing, L, C),
        (s -> 1 / (1 / R + s * C + 1 / (s * L)), :parallel, R, L, C),
        (s -> 0.191736 + s * 0.0122063, :series, 0.191736, 0.0122063, nothing)
    )
    for (z, topology, expected_R, expected_L, expected_C) in cases
        record = pscad.identify_rlc(z)
        @test record.form.topology == topology
        @test record.conductors == [1]
        @test !record.constant
        for (actual, expected) in zip((record.form.R, record.form.L, record.form.C),
            (expected_R, expected_L, expected_C))
            @test expected === nothing ? actual === nothing :
                  isapprox(actual, expected; rtol = 1e-9)
        end
        # Verify at frequencies independent of the identification grid.
        for f in (0.37, 18.3, 377.0, 7300.0)
            s = im * 2π * f
            form = record.form
            fitted = topology == :series ?
                     (form.R === nothing ? 0 : form.R) +
                     (form.L === nothing ? 0 : s * form.L) +
                     (form.C === nothing ? 0 : 1 / (s * form.C)) :
                     1 / ((form.R === nothing ? 0 : 1 / form.R) +
                      (form.L === nothing ? 0 : 1 / (s * form.L)) +
                      (form.C === nothing ? 0 : s * form.C))
            @test isapprox(fitted, z(s); rtol = 1e-9)
        end
    end

    @test_throws ArgumentError pscad.identify_rlc(s -> 1 + 1 / (s + 2) + 1 / (s + 5); name = :bad)
    err = try
        pscad.identify_rlc(s -> -1 + s * L; name = :negative)
    catch exception
        exception
    end
    @test err isa ArgumentError
    @test occursin("impedance :negative", sprint(showerror, err))
    @test_throws ArgumentError pscad.identify_rlc(s -> NaN)
    @test_throws ArgumentError pscad.identify_rlc(s -> s * L; frequencies = [0.0, 1.0])
    @test_throws ArgumentError pscad.identify_rlc(s -> s * L; frequencies = [1.0])
    @test_throws ArgumentError pscad.identify_rlc(s -> s * L; rtol = -1)
    @test_throws ArgumentError pscad.identify_rlc(s -> s * L; atol = 0)

    @test_throws ArgumentError("coupled impedance matrix") pscad.identify_rlc(
        s -> [R + s * L 0.1; 0.1 R + s * L])
    @test_throws ArgumentError("coupled impedance matrix") pscad.identify_rlc([1.0 0.1;
                                                                               0.1 1.0])
    diagonal = pscad.identify_rlc(s -> Diagonal([R + s * L, 1 / (s * C), R + s * L]))
    @test length(diagonal) == 2
    @test diagonal[1].conductors == [1, 3]
    @test diagonal[2].conductors == [2]
    @test diagonal[1].form.R ≈ R
    @test diagonal[1].form.L ≈ L
    @test diagonal[2].form.C ≈ C
    @test pscad.identify_rlc(s -> Diagonal(fill(R + s * L, 3))).conductors == [1, 2, 3]

    transformed = impedance(z = s -> Diagonal([R + s * L, 1 / (s * C), R + s * L]),
        pins = 3, transformation = true)
    @test pscad.identify_rlc(transformed)[1].conductors == [1, 3]
    @test pscad.identify_rlc(transformed)[2].form.C ≈ C
    coupled = impedance(z = s -> [R + s * L 0.1 0; 0.1 R + s * L 0; 0 0 R + s * L],
        pins = 3, transformation = true)
    @test_throws ArgumentError("coupled impedance matrix") pscad.identify_rlc(coupled)

    constant = pscad.identify_rlc(2 + 3im)
    @test constant.constant
    @test constant.form.R == 2.0
    @test constant.form.L == 3 / (2π * 50)
    @test constant.form.C === nothing
    @test pscad.identify_rlc(impedance(z = 2 + 3im, pins = 3, transformation = true)).conductors ==
          [1, 2, 3]
    @test_throws ArgumentError pscad.identify_rlc(Inf)

    # calc_RLC in test/NetworkBuilder_test.jl: preserve the fixture's original
    # three-phase current convention and P/Q/V inputs without loading its suite.
    for (P, Q, V, capacitor) in ((107.3333, 0.8, 345.0, false),
        (166.6667, 61.3333, 345.0, false), (0.0, 100.0, 345.0, true),
        (0.0, 200.0, 345.0, true), (77.93333, 28.0, 345.0, false),
        (174.0, 58.6667, 345.0, false), (2.5, 29.3333, 230.0, false),
        (106.6667, 51.0, 345.0, false), (109.8, 10.7667, 345.0, false),
        (52.6667, 10.0, 345.0, false), (226.6667, 34.3333, 345.0, false),
        (91.3333, 38.3333, 345.0, false), (82.5, 28.2, 345.0, false),
        (102.8667, 30.73333, 345.0, true))
        I = 3 * hypot(P, Q) * 1e6 / (sqrt(3) * V * 1e3)
        load_R = P * 1e6 / I^2
        load_L = Q * 1e6 / (I^2 * 2π * 50)
        load_C = I^2 / (Q * 1e6 * 2π * 50)
        z = capacitor ? s -> load_R + 1 / (s * load_C) : s -> load_R + s * load_L
        identified = pscad.identify_rlc(z)
        @test identified.form.topology == :series
        @test iszero(load_R) ? identified.form.R === nothing : identified.form.R ≈ load_R
        @test capacitor ? identified.form.C ≈ load_C : identified.form.L ≈ load_L
    end
end
