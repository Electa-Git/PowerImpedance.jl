using PowerImpedance
using Test
using LinearAlgebra

function transformer_dq(model, s)
    return PowerImpedance.transformation_dq(
        PowerImpedance.eval_abcd(model, s + 100π * im),
        PowerImpedance.eval_abcd(model, s - 100π * im))
end

@testset "Dyn11 transformer" begin
    parameters = (; n = 380 / 150, Rₚ = 0.5, Lₚ = 0.01,
        Rₛ = 0.1, Lₛ = 0.002, Lₘ = 50, Rₘ = 1e5)
    frequencies = (ComplexF64(100π * im), ComplexF64(7 + 2000π * im))
    capacitive = (; Cₜ = 2e-8, Cₛ = 1e-9, hasRω = true, k = 0.7)

    @testset "YY and one-phase bit regression" begin
        # Independent stored matrices from Julia 1.12.7 fix the reference arithmetic,
        # including capacitive paths.
        expected = (
            reshape(
                ComplexF64[
                2.5338526666666668 - 1.051490608952202e-6im,
                2.5333333333333334e-5 - 0.00016127700899978728im,
                0.45075434839033274 + 2.8321688426858493im,
                0.39484070877192984 - 2.1029812179044075e-7im
        ],
                2,
                2),
            reshape(
                ComplexF64[
                2.5338544444919 + 0.0015877083575981908im,
                2.534231713379907e-5 - 8.0638404412756e-6im,
                0.4939076750229823 + 56.64358229626174im,
                0.3948410643369765 + 0.0003175416715196382im
        ],
                2,
                2),
            reshape(
                ComplexF64[
                2.5338362363592144 + 1.5634793947694648e-6im,
                2.533332443246545e-5 - 0.00014258398162773713im,
                0.45075515051063497 + 2.8321712987853314im,
                0.3948223752726012 + 2.707575775676267e-6im
        ],
                2,
                2),
            reshape(
                ComplexF64[
                2.527370758338872 + 0.0019979688023335704im,
                2.5463042723336252e-5 + 0.00036496212157743094im,
                3.7162120278378876 + 56.66590821552659im,
                0.3875234029287883 + 0.0008011896916402185im
        ],
                2,
                2)
        )
        for (j, extra) in enumerate(((;), capacitive)), (i, s) in enumerate(frequencies)

            reference = expected[2(j - 1) + i]
            for organization in (:YY, :ΔY)
                single = transformer(; parameters..., extra..., organization)
                actual = PowerImpedance.eval_abcd(single, s)
                @test reinterpret(UInt64, vec(actual)) ==
                      reinterpret(UInt64, vec(reference))
            end
            yy = transformer(; parameters..., extra..., conductors = 3)
            phase = PowerImpedance.eval_abcd(yy, s)
            reference_phase = zeros(ComplexF64, 6, 6)
            for k in 1:3
                reference_phase[[k, k + 3], [k, k + 3]] = reference
            end
            @test reinterpret(UInt64, vec(phase)) ==
                  reinterpret(UInt64, vec(reference_phase))
        end
    end

    a = cis(2π / 3)
    fortescue = ComplexF64[1 1 1; 1 a^2 a; 1 a a^2]
    basis = kron(Matrix{ComplexF64}(I, 2, 2), fortescue)
    ideal = transformer(conductors = 3, organization = :ΔY,
        n = parameters.n)
    s50 = frequencies[1]
    phase_ideal = PowerImpedance.eval_abcd(ideal, s50)
    sequence_ideal = (basis \ phase_ideal) * basis
    ratios = (parameters.n * cis(-π / 6), parameters.n * cis(π / 6))

    @testset "Sequence ratios, zero placeholder and ideal power" begin
        for (index, ratio) in zip((2, 3), ratios)
            # Drive a pure sequence through the phase-domain open-circuit model.
            v1 = fortescue[:, index]
            v2 = phase_ideal[1:3, 1:3] \ v1
            measured = (fortescue \ v1)[index] / (fortescue \ v2)[index]
            @test measured ≈ ratio rtol = 1e-12
            @test abs(measured) ≈ parameters.n rtol = 1e-12
            @test sequence_ideal[[index, index+3], [
                index, index+3]]≈
            ComplexF64[ratio 0; 0 1/conj(ratio)] rtol=1e-12 atol=1e-13
        end
        @test sequence_ideal[[1, 4], [1, 4]] ≈ Matrix{ComplexF64}(I, 2, 2) atol = 1e-13
        @test sequence_ideal[[1, 4], [2, 3, 5, 6]] ≈ zeros(2, 4) atol = 1e-13
        @test sequence_ideal[[2, 3, 5, 6], [1, 4]] ≈ zeros(4, 2) atol = 1e-13
        @test phase_ideal * ComplexF64[2, 2, 2, 3, 3, 3] ≈
              ComplexF64[2, 2, 2, 3, 3, 3] atol = 1e-13

        # Complex power equality across the ideal block, in positive sequence.
        v2 = (230 + 17im) * fortescue[:, 2]
        i2 = (2 - 0.7im) * fortescue[:, 2]
        primary = phase_ideal * [v2; i2]
        @test sum(primary[1:3] .* conj.(primary[4:6])) ≈ sum(v2 .* conj.(i2)) rtol = 1e-12
    end

    @testset "Loaded phase model retains the complete YY circuit" begin
        for extra in ((;), capacitive), s in frequencies

            yy = transformer(; parameters..., extra...)
            dy = transformer(; parameters..., extra..., conductors = 3,
                organization = :ΔY)
            yy_abcd = PowerImpedance.eval_abcd(yy, s)
            dy_abcd = PowerImpedance.eval_abcd(dy, s)
            sequence = (basis \ dy_abcd) * basis
            @test sequence[[2, 5], [2, 5]]≈cis(-π/6)*yy_abcd rtol=1e-12 atol=1e-13
            @test sequence[[3, 6], [3, 6]]≈cis(π/6)*yy_abcd rtol=1e-12 atol=1e-13
            @test sequence[[1, 4], [2, 3, 5, 6]] ≈ zeros(2, 4) atol = 1e-12
            @test sequence[[2, 3, 5, 6], [1, 4]] ≈ zeros(4, 2) atol = 1e-12
            for load in (Inf, 100.0)
                yy_ratio = yy_abcd[1, 1] + yy_abcd[1, 2] / load
                v1 = fortescue[:, 2]
                v2 = (dy_abcd[1:3, 1:3] + dy_abcd[1:3, 4:6] / load) \ v1
                dy_ratio = (fortescue \ v1)[2] / (fortescue \ v2)[2]
                @test abs(dy_ratio) ≈ abs(yy_ratio) rtol = 1e-12
                @test -angle(dy_ratio) ≈ -angle(yy_ratio) + π / 6 atol = 1e-12
            end
        end
    end

    @testset "Lossless model conserves active power" begin
        dy = transformer(conductors = 3, organization = :ΔY,
            n = parameters.n, Lₚ = 0.01, Lₛ = 0.002, Lₘ = 50, Cₜ = 2e-8)
        v2 = 150.0 * fortescue[:, 2]
        i2 = (2 - 0.7im) * fortescue[:, 2]
        primary = PowerImpedance.eval_abcd(dy, s50) * [v2; i2]
        @test real(sum(primary[1:3] .* conj.(primary[4:6]))) ≈
              real(sum(v2 .* conj.(i2))) rtol = 1e-12
    end

    @testset "dq frame rotation" begin
        # The repository uses dq-lagging: [d,q] = [V*cos(θ), -V*sin(θ)].
        rotation = [cos(π / 6) -sin(π / 6); sin(π / 6) cos(π / 6)]
        frame = kron(Matrix{Float64}(I, 2, 2), rotation)
        # Nonzero s avoids evaluating the magnetizing term at zero frequency.
        for extra in ((;), capacitive), s in (ComplexF64(3 + 70im), ComplexF64(5 + 2000im))

            yy = transformer(; parameters..., extra..., conductors = 3)
            dy = transformer(; parameters..., extra..., conductors = 3,
                organization = :ΔY)
            explicit_dq = PowerImpedance.transformation_dq(
                PowerImpedance.eval_abcd(dy, s + 100π * im),
                PowerImpedance.eval_abcd(dy, s - 100π * im))
            @test transformer_dq(dy, s)≈explicit_dq rtol=1e-12 atol=1e-13
            @test explicit_dq≈transformer_dq(yy, s)*frame rtol=1e-12 atol=1e-13
        end
        ideal_dq = transformer_dq(ideal, ComplexF64(1))
        @test ideal_dq[1:2, 1:2]≈parameters.n*rotation rtol=1e-12 atol=1e-13
        @test ideal_dq[3:4, 3:4]≈rotation/parameters.n rtol=1e-12 atol=1e-13
        secondary_dq = ideal_dq[1:2, 1:2] \ [parameters.n, 0]
        @test secondary_dq ≈ [cos(π / 6), -sin(π / 6)] rtol = 1e-12
    end

    @testset "Dyn11 power flow" begin
        function network(organization; extra...)
            elements = (; source = ac_source(v = 380sqrt(2 / 3), theta = 0.0),
                transformer = transformer(; parameters..., extra..., conductors = 3,
                    organization, V₁ᵒ = 380e3 / sqrt(3), V₂ᵒ = 150e3 / sqrt(3)),
                load = impedance(z = 100.0, conductors = 3))
            topology = (
                NetworkBuilder.Bus(
                    :primary_; ports = ((:source, :ac),
                        (:transformer, :side1)),
                    domain = ACDQ),
                NetworkBuilder.Bus(
                    :secondary_; ports = ((:transformer, :side2),
                        (:load, :side1)),
                    domain = ACDQ),
                NetworkBuilder.Bus(:gnd; ports = ((:load, :side2),), domain = ACDQ))
            return NetworkBuilder.define(elements, topology;
                options = (; voltageBase = 380 / sqrt(3)))
        end
        # Exercise that public path, then solve its returned model at tighter
        # test-only tolerances to measure the requested 1e-6 angle agreement.
        precise_optimizer = PowerImpedance.JuMP.optimizer_with_attributes(
            PowerImpedance.Ipopt.Optimizer,
            "tol" => 1e-10, "constr_viol_tol" => 1e-10, "print_level" => 0)
        for extra in ((;), capacitive)
            yy_powerflow = compute(PowerFlowProblem(network(:YY; extra...)),
                ACDCPowerFlow())
            yy_result, yy_data = yy_powerflow.result, yy_powerflow.data
            yy_components = yy_powerflow.elem2comp
            dy_powerflow = compute(PowerFlowProblem(network(:ΔY; extra...)),
                ACDCPowerFlow())
            dy_result, dy_data = dy_powerflow.result, dy_powerflow.data
            dy_components = dy_powerflow.elem2comp
            @test yy_result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
            @test dy_result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
            yy_index = yy_components[:transformer].compkey
            dy_index = dy_components[:transformer].compkey
            yy_branch = yy_data["branch"][string(yy_index)]
            dy_branch = dy_data["branch"][string(dy_index)]
            @test yy_branch["shift"] === 0
            @test dy_branch["shift"] == -π / 6
            for key in ("tap", "br_r", "br_x", "g_fr", "b_fr", "g_to", "b_to")
                @test isequal(dy_branch[key], yy_branch[key])
            end
            # Reconstruct the branch stamp, including tap and frame rotation,
            # and compare it with the T-model's positive-sequence two-port at 50 Hz.
            base_z = PowerImpedance.PowerModelsACDC._get_pu_bases(1000, 380 / sqrt(3))["Z"]
            for (organization, branch) in ((:YY, yy_branch), (:ΔY, dy_branch))
                model = transformer(; parameters..., extra..., conductors = 3,
                    organization)
                phase_abcd = PowerImpedance.eval_abcd(model, s50)
                sequence_abcd = (basis \ phase_abcd) * basis
                A, B,
                C,
                D = sequence_abcd[2, 2], sequence_abcd[2, 5],
                sequence_abcd[5, 2], sequence_abcd[5, 5]
                t_y = ComplexF64[D / B C - D * A / B; -1 / B A / B] * base_z
                series = inv(branch["br_r"] + im * branch["br_x"])
                tap = branch["tap"] * cis(branch["shift"])
                from_shunt = branch["g_fr"] + im * branch["b_fr"]
                to_shunt = branch["g_to"] + im * branch["b_to"]
                branch_y = ComplexF64[(series + from_shunt) / abs2(tap) -series / conj(tap);
                                      -series / tap series + to_shunt]
                @test branch_y ≈ t_y rtol = 1e-12
            end
            yy_result = NetworkBuilder.solve_acdcpf(
                yy_data, PowerImpedance._PM.ACPPowerModel, precise_optimizer, (;))
            dy_result = NetworkBuilder.solve_acdcpf(
                dy_data, PowerImpedance._PM.ACPPowerModel, precise_optimizer, (;))
            @test yy_result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
            @test dy_result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
            for bus_key in ("f_bus", "t_bus")
                yy_bus = yy_result["solution"]["bus"][string(yy_branch[bus_key])]
                dy_bus = dy_result["solution"]["bus"][string(dy_branch[bus_key])]
                @test dy_bus["vm"] ≈ yy_bus["vm"] rtol = 1e-10
                shift = bus_key == "t_bus" ? π / 6 : 0.0
                @test dy_bus["va"] ≈ yy_bus["va"] + shift atol = 1e-6
            end
        end
    end
end
