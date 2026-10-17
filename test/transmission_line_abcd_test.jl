module TransmissionLineABCDTests
using Test, LinearAlgebra, PowerImpedance
const PI = PowerImpedance

# Untransposed flat OHL and unequal-depth cable, with the repository's
# conductor/layer/earth data. Short sections keep the chain reference conditioned.
function line_models()
    ohl = overhead_line(length = 1000.0,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1,
            Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30, Δxᵇᶜ = 10, dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062,
            Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100)).element_model
    ugc = cable(length = 1000.0,
        positions = [(-0.5, 1.0), (0.0, 1.3), (0.7, 1.1)],
        C1 = Conductor(rₒ = 30e-3, ρ = 2.82e-8),
        I1 = Insulator(rᵢ = 30e-3, rₒ = 51.5e-3, ϵᵣ = 2.5),
        C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
        I2 = Insulator(rᵢ = 55.4e-3, rₒ = 61.2e-3, ϵᵣ = 2.3),
        earth_parameters = (1, 1, 100), eliminate = false).element_model
    return (ohl, ugc)
end

function old_chain(Z, Y, length)
    gamma = sqrt(ComplexF64.(Z * Y))
    yc = Z \ gamma
    a, h = cosh(gamma * length), sinh(gamma * length)
    return [a yc \ h; yc * h a]
end

include("data/ohl_untransposed_reference.jl")

function overhead_models()
    ac = first(line_models())
    bundled = deepcopy(ac)
    bundled.conductors.nˢᵇ = 2
    bundled.conductors.dˢᵇ = 0.45
    dc = overhead_line(length = 75e3,
        conductors = Conductors(organization = :flat, nᵇ = 2, nˢᵇ = 1,
            Rᵈᶜ = 0.0266, rᶜ = 0.0224, yᵇᶜ = 18.0, Δxᵇᶜ = 7.3, dˢᵃᵍ = 6.0),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062,
            Δxᵍ = 7.3, Δyᵍ = 7.0, dᵍˢᵃᵍ = 6.0),
        earth_parameters = (1, 1, 100)).element_model
    dc_bundle = deepcopy(dc)
    dc_bundle.conductors.nˢᵇ = 2
    dc_bundle.conductors.dˢᵇ = 0.45
    dc_bundle.conductors.Rᵈᶜ = 0.0598
    dc_bundle.conductors.rᶜ = 30.42e-3 / 2
    return (ac, bundled, dc, dc_bundle)
end

@testset "Overhead-line transposition" begin
    @testset "Untransposed parameter preservation" begin
        for model in overhead_models(), frequency in (1.0, 50.0, 137.0, 1e3, 1e4, 1e6)
            s = ComplexF64(2π * frequency * im)
            @test model.transposition == :none
            Z, Y = PI.eval_parameters(model, s)
            Z0, Y0 = untransposed_reference(model, s)
            @test isequal(Z, Z0)
            @test isequal(Y, Y0)
            explicit = deepcopy(model)
            explicit.transposition = :none
            @test isequal(PI.eval_parameters(explicit, s), (Z, Y))
        end
    end
    @testset "Cyclic phase averages and sequence decoupling" begin
        R = [0.0 1 0; 0 0 1; 1 0 0]
        q = ComplexF64[1, cis(-2π / 3), cis(2π / 3)]
        sequence = [ones(ComplexF64, 3) q conj(q)] / sqrt(3)
        for model in overhead_models()[1:2], frequency in (1.0, 50.0, 137.0, 1e3, 1e4, 1e6)
            s = ComplexF64(2π * frequency * im)
            Z0, Y0 = untransposed_reference(model, s)
            # Recover reduced potential coefficients before averaging. Averaging
            # Y instead would give different positive-sequence capacitance.
            P0 = inv((Y0 - model.conductors.gᶜ * I) / s)
            Zt = (Z0 + R * Z0 * R' + R^2 * Z0 * (R^2)') / 3
            Pt = (P0 + R * P0 * R' + R^2 * P0 * (R^2)') / 3
            Yt = s * inv(Pt) + model.conductors.gᶜ * I
            transposed = deepcopy(model)
            transposed.transposition = :ideal
            Z, Y = PI.eval_parameters(transposed, s)
            @test Z ≈ Zt rtol = 1e-13
            @test Y ≈ Yt rtol = 1e-13
            for M in (Z, Y)
                @test diag(M) ≈ fill(M[1, 1], 3) rtol = 1e-13
                @test [M[i, j] for i in 1:3 for j in 1:3 if i != j] ≈
                    fill(M[1, 2], 6) rtol = 1e-13
                transformed = sequence' * M * sequence
                @test norm(transformed - Diagonal(diag(transformed))) <= 1e-13norm(M)
            end
            @test dot(q, Z * q) / 3 ≈ dot(q, Zt * q) / 3 rtol = 1e-13
            @test dot(q, Y * q) / 3 ≈ dot(q, Yt * q) / 3 rtol = 1e-13
            zero = zeros(ComplexF64, 3, 3)
            forward = exp(transposed.length * [zero -Zt; -Yt zero])
            signs = Diagonal([ones(3); -ones(3)])
            reference = signs * forward * signs
            chain = PI.eval_abcd(transposed, s)
            for rows in (1:3, 4:6), columns in (1:3, 4:6)
                @test chain[rows, columns] ≈ reference[rows, columns] rtol = 1e-10
            end
        end
    end
    @testset "Transposition input validation" begin
        @test overhead_line(conductors = Conductors(nᵇ = 3),
            transposition = :ideal).element_model.transposition == :ideal
        for value in (:unknown, :Ideal, Symbol(), "ideal", 1, nothing, missing)
            @test_throws ArgumentError overhead_line(transposition = value)
            @test_throws ArgumentError Overhead_line(transposition = value)
        end
        for n in (1, 2, 4, 6)
            @test_throws ArgumentError overhead_line(conductors = Conductors(nᵇ = n),
                transposition = :ideal)
            @test_throws ArgumentError Overhead_line(conductors = Conductors(nᵇ = n),
                transposition = :ideal)
        end
        mutated = first(overhead_models())
        mutated.transposition = :unknown
        @test_throws ArgumentError PI.eval_parameters(mutated, ComplexF64(50im))
        mutated.transposition = :ideal
        mutated.conductors.nᵇ = 2
        @test_throws ArgumentError PI.eval_parameters(mutated, ComplexF64(50im))
    end
end

@testset "Multiconductor chain matrices" begin
    for model in line_models(), frequency in (1.0, 50.0, 1e3, 1e4, 1e5, 1e6)
        @testset "$(nameof(typeof(model))), $frequency Hz" begin
            s = ComplexF64(2π * frequency * im)
            Z, Y = PI.eval_parameters(model, s)
            n = size(Z, 1)
            zero = zeros(ComplexF64, n, n)
            # Forward telegrapher evolution has negative off-diagonal blocks.
            # ABCD maps receiving to sending states, so it is the inverse
            # evolution; changing both current signs gives this inverse directly.
            forward = exp(model.length * [zero -Z; -Y zero])
            signs = Diagonal([ones(n); -ones(n)])
            reference = signs * forward * signs
            chain = PI.eval_abcd(model, s)
            @test norm(Z * Y - Y * Z) / norm(Z * Y) > 1e-5
            # Check each block so the units/scale of B cannot hide C or D errors.
            for rows in (1:n, (n+1):2n), columns in (1:n, (n+1):2n)
                @test chain[rows, columns] ≈ reference[rows, columns] rtol = 1e-10
            end
            terminal = PI.abcd_to_y(chain)
            @test terminal ≈ transpose(terminal) rtol = 1e-10
            half = deepcopy(model)
            half.length /= 2
            half_chain = PI.eval_abcd(half, s)
            @test half_chain * half_chain ≈ chain rtol = 1e-10
            # Both imported per-metre Z/Y paths use the same physical length.
            for kind in (:PSCAD, :LCMjl)
                imported = PI.Blackbox_line(n = n, length = model.length,
                    data_type = kind, f = [frequency / 2, frequency, 2frequency],
                    Z = [copy(Z), copy(Z), copy(Z)], Y = [copy(Y), copy(Y), copy(Y)])
                @test PI.eval_abcd(imported, s) ≈ chain rtol = 1e-12
                @test PI.eval_abcd(imported, 1.5s) ≈ chain rtol = 1e-12
            end
        end
    end
    @testset "Scalar and commuting symmetric limits" begin
        for frequency in (1.0, 50.0, 1e3, 1e6), n in (1, 3)
            # Equal diagonal/mutual entries represent a transposed line.
            s = ComplexF64(2π * frequency * im)
            Z = (0.01 + 1e-6s) * Matrix{Float64}(I, n, n) .+ 2e-7s
            Y = (1e-9s) * Matrix{Float64}(I, n, n) .+ 1e-10s
            imported = PI.Blackbox_line(n = n, length = 1000.0,
                data_type = :PSCAD, f = [frequency], Z = [Z], Y = [Y])
            @test PI.eval_abcd(imported, s) ≈ old_chain(Z, Y, imported.length) rtol = 1e-12
        end
        # Symmetric two-pole OHL and reduced cable geometries also commute.
        ohl, ugc = line_models()
        ohl.conductors.nᵇ = 2
        ugc.positions = [(0.0, 1.0), (0.5, 1.0)]
        ugc.eliminate = true
        for model in (ohl, ugc), frequency in (1.0, 50.0, 1e3, 1e6)
            s = ComplexF64(2π * frequency * im)
            Z, Y = PI.eval_parameters(model, s)
            @test PI.eval_abcd(model, s) ≈ old_chain(Z, Y, model.length) rtol = 1e-12
        end
    end
end
end
