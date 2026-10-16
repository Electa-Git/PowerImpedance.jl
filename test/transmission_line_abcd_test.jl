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
            # Both imported per-metre Z/Y paths use the same length semantics.
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
