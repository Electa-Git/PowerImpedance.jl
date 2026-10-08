using PowerImpedance
using Test
using LinearAlgebra

@testset "Dyn11 transformer" begin
    parameters = (; n = 380 / 150, Rₚ = 0.5, Lₚ = 0.01,
        Rₛ = 0.1, Lₛ = 0.002, Lₘ = 50, Rₘ = 1e5)
    frequencies = (ComplexF64(100π * im), ComplexF64(7 + 2000π * im))
    capacitive = (; Cₜ = 2e-8, Cₛ = 1e-9, hasRω = true, k = 0.7)

    @testset "YY and one-phase bit regression" begin
        # Captured from the unchanged implementation using Julia 1.12.7,
        # before this fix. Preserve arithmetic, including capacitive paths.
        expected = (
            ComplexF64[2.5338526666666668 - 1.051490608952202e-6im 0.45075434839033274 + 2.8321688426858493im;
                       2.5333333333333334e-5 - 0.00016127700899978728im 0.39484070877192984 - 2.1029812179044075e-7im],
            ComplexF64[2.5338544444919 + 0.0015877083575981908im 0.4939076750229823 + 56.64358229626174im;
                       2.534231713379907e-5 - 8.0638404412756e-6im 0.3948410643369765 + 0.0003175416715196382im],
            ComplexF64[2.5338362363592144 + 1.5634793947694648e-6im 0.45075515051063497 + 2.8321712987853314im;
                       2.533332443246545e-5 - 0.00014258398162773713im 0.3948223752726012 + 2.707575775676267e-6im],
            ComplexF64[2.527370758338872 + 0.0019979688023335704im 3.7162120278378876 + 56.66590821552659im;
                       2.5463042723336252e-5 + 0.00036496212157743094im 0.3875234029287883 + 0.0008011896916402185im]
        )
        for (j, extra) in enumerate(((;), capacitive)), (i, s) in enumerate(frequencies)

            reference = expected[2(j - 1) + i]
            for organization in (:YY, :ΔY)
                single = transformer(; parameters..., extra..., organization)
                actual = PowerImpedance.eval_abcd(single.element_model, s)
                @test reinterpret(UInt64, vec(actual)) ==
                      reinterpret(UInt64, vec(reference))
            end
            yy = transformer(; parameters..., extra..., pins = 3)
            phase = PowerImpedance.eval_abcd(yy.element_model, s)
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
    ideal = transformer(pins = 3, organization = :ΔY, transformation = true,
        n = parameters.n)
    s50 = frequencies[1]
    phase_ideal = PowerImpedance.eval_abcd(ideal.element_model, s50)
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
            @test sequence_ideal[[index, index+3], [index, index+3]]≈
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
            dy = transformer(; parameters..., extra..., pins = 3,
                organization = :ΔY, transformation = true)
            yy_abcd = PowerImpedance.eval_abcd(yy.element_model, s)
            dy_abcd = PowerImpedance.eval_abcd(dy.element_model, s)
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
        dy = transformer(pins = 3, organization = :ΔY, transformation = true,
            n = parameters.n, Lₚ = 0.01, Lₛ = 0.002, Lₘ = 50, Cₜ = 2e-8)
        v2 = 150.0 * fortescue[:, 2]
        i2 = (2 - 0.7im) * fortescue[:, 2]
        primary = PowerImpedance.eval_abcd(dy.element_model, s50) * [v2; i2]
        @test real(sum(primary[1:3] .* conj.(primary[4:6]))) ≈
              real(sum(v2 .* conj.(i2))) rtol = 1e-12
    end

    @testset "dq frame rotation" begin
        # The repository uses dq-lagging: [d,q] = [V*cos(θ), -V*sin(θ)].
        rotation = [cos(π / 6) -sin(π / 6); sin(π / 6) cos(π / 6)]
        frame = kron(Matrix{Float64}(I, 2, 2), rotation)
        # Nonzero s avoids evaluating the magnetizing term at zero frequency.
        for extra in ((;), capacitive), s in (ComplexF64(3 + 70im), ComplexF64(5 + 2000im))

            yy = transformer(; parameters..., extra..., pins = 3, transformation = true)
            dy = transformer(; parameters..., extra..., pins = 3,
                organization = :ΔY, transformation = true)
            explicit_dq = PowerImpedance.transformation_dq(
                PowerImpedance.eval_abcd(dy.element_model, s + 100π * im),
                PowerImpedance.eval_abcd(dy.element_model, s - 100π * im))
            @test PowerImpedance.get_abcd(dy, s)≈explicit_dq rtol=1e-12 atol=1e-13
            @test explicit_dq≈PowerImpedance.get_abcd(yy, s)*frame rtol=1e-12 atol=1e-13
        end
        ideal_dq = PowerImpedance.get_abcd(ideal, ComplexF64(1))
        @test ideal_dq[1:2, 1:2]≈parameters.n*rotation rtol=1e-12 atol=1e-13
        @test ideal_dq[3:4, 3:4]≈rotation/parameters.n rtol=1e-12 atol=1e-13
        secondary_dq = ideal_dq[1:2, 1:2] \ [parameters.n, 0]
        @test secondary_dq ≈ [cos(π / 6), -sin(π / 6)] rtol = 1e-12
    end

    @testset "Untransformed Delta-Y is rejected" begin
        @test_throws ArgumentError transformer(pins = 3, organization = :ΔY, n = parameters.n)
        @test_throws ArgumentError transformer(pins = 3, organization = :ΔY,
            n = parameters.n, transformation = false)
        @test ideal.input_pins == ideal.output_pins == 2
    end

    @testset "Dyn11 power flow" begin
        function network(organization; extra...)
            net = Network()
            # Classic power flow uses a phase-RMS voltage base [kV].
            net.voltageBase[1] = 380 / sqrt(3)
            add!(net,
                :source,
                ac_source(pins = 3, transformation = true,
                    setpoint = Setpoint(Vac = 380sqrt(2 / 3), θac = 0.0)))
            add!(net,
                :transformer,
                transformer(; parameters..., extra..., pins = 3,
                    organization, transformation = true, V₁ᵒ = 380 / sqrt(3), V₂ᵒ = 150 /
                                                                                    sqrt(3)))
            add!(net, :load, impedance(z = 100.0, pins = 3, transformation = true))
            for k in 1:2
                primary = Symbol("primary_$k")
                secondary = Symbol("secondary_$k")
                ground = Symbol("gnd_$k")
                connect!(net, (:source, Symbol("1.$k")), primary)
                connect!(net, (:source, Symbol("2.$k")), ground)
                connect!(net, (:transformer, Symbol("1.$k")), primary)
                connect!(net, (:transformer, Symbol("2.$k")), secondary)
                connect!(net, (:load, Symbol("1.$k")), secondary)
                connect!(net, (:load, Symbol("2.$k")), ground)
            end
            connect!(net)
            return net
        end
        # Captured by running the saved before-fix YY conversion definitions.
        reference_branch = (
            (; tap = 2.5332597217069175, br_r = 0.0012322335064503466,
                br_x = 0.007742339827324561, g_fr = 0.0023201884068715373,
                b_fr = -0.01474657529274026, g_to = 0.0023201884068715373,
                b_to = -0.01474657529274026),
            (; tap = 2.533310323243148, br_r = 0.001232211085960381,
                br_x = 0.007742191892313735, g_fr = 0.002119953992924195,
                b_fr = -0.013069600279727922, g_to = 0.002119953992924195,
                b_to = -0.013069600279727922))
        # Classic power_flow fixes tol=1e2 and constr_viol_tol=1e-3.
        # Exercise that public path, then solve its returned model at tighter
        # test-only tolerances to measure the requested 1e-6 angle agreement.
        precise_optimizer = PowerImpedance.JuMP.optimizer_with_attributes(
            PowerImpedance.Ipopt.Optimizer,
            "tol" => 1e-10, "constr_viol_tol" => 1e-10, "print_level" => 0)
        for (case, extra) in enumerate(((;), capacitive))
            yy_result, yy_data, _, yy_components = power_flow(network(:YY; extra...))
            dy_result, dy_data, _, dy_components = power_flow(network(:ΔY; extra...))
            @test yy_result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
            @test dy_result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
            _, yy_index = yy_components[:transformer]
            _, dy_index = dy_components[:transformer]
            yy_branch = yy_data["branch"][string(yy_index)]
            dy_branch = dy_data["branch"][string(dy_index)]
            @test yy_branch["shift"] === 0
            @test dy_branch["shift"] == -π / 6
            for key in ("tap", "br_r", "br_x", "g_fr", "b_fr", "g_to", "b_to")
                @test isequal(yy_branch[key], getproperty(reference_branch[case], Symbol(key)))
                @test isequal(dy_branch[key], yy_branch[key])
            end
            yy_result = PowerImpedance.solve_acdcpf(
                yy_data, PowerImpedance._PM.ACPPowerModel, precise_optimizer)
            dy_result = PowerImpedance.solve_acdcpf(
                dy_data, PowerImpedance._PM.ACPPowerModel, precise_optimizer)
            @test yy_result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
            @test dy_result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
            for side in ("f_bus", "t_bus")
                yy_bus = yy_result["solution"]["bus"][string(yy_branch[side])]
                dy_bus = dy_result["solution"]["bus"][string(dy_branch[side])]
                @test dy_bus["vm"] ≈ yy_bus["vm"] rtol = 1e-10
                shift = side == "t_bus" ? π / 6 : 0.0
                @test dy_bus["va"] ≈ yy_bus["va"] + shift atol = 1e-6
            end
        end
    end
end
