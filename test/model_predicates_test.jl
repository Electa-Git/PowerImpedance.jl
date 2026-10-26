module ModelPredicatesTests
using Test, PowerImpedance
const PI = PowerImpedance
include("parity/fixtures.jl")
const NB = PI.NetworkBuilder

const PREDICATES = (PI.is_source, PI.is_converter, PI.is_generator,
    PI.is_inductionmachine, PI.is_passive, PI.is_active, PI.issingleport,
    PI.is_three_phase)

@testset "Model predicates and admittance coordinates" begin
    for fixture in ParityFixtures.FIXTURES
        state = fixture.build()
        for (name, model) in pairs(state.elements)
            @testset "$(fixture.name).$name" begin
                ports = electricalconnections(model)
                expected = (model isa PI.Source,
                    model isa Union{MMC, TLC, PI.Blackbox_MMC},
                    model isa SynchronousMachine, model isa InductionMachine,
                    model isa Union{PI.Impedance, PI.Transformer, PI.Transmission_line},
                    model isa Union{PI.Source, MMC, TLC, PI.Blackbox_MMC,
                        SynchronousMachine, InductionMachine},
                    length(ports) == 1,
                    all(port -> port.domain in (ACABC, ACDQ), ports))
                for (predicate, value) in zip(PREDICATES, expected)
                    @testset "$(nameof(predicate))" begin
                        @test predicate(model) == value
                    end
                end
                order = PI.admittance_order(model)
                @testset "admittance_order" begin
                    if model isa Union{MMC, TLC, PI.Blackbox_MMC}
                        @test order === ((:dc, :dc), (:ac, :d), (:ac, :q))
                    elseif model isa Union{SynchronousMachine, InductionMachine}
                        @test order === ((:ac, :d), (:ac, :q))
                    elseif PI.is_source(model)
                        expected_order = model.domain === ACABC ?
                                         ((:ac, :a), (:ac, :b), (:ac, :c)) : ((:dc, :dc),)
                        @test order === expected_order
                    end
                    if model isa PI.AbstractStateSpace || PI.is_passive(model)
                        rows = if model isa PI.AbstractStateSpace
                            PI.n_outputs(model)
                        else
                            frame = first(ports).domain === ACABC ? :abc : :dc
                            size(NB.admittance(model, 2π * im * 100, frame), 1)
                        end
                        @test length(order) == rows
                    end
                end
                if model isa Union{MMC, TLC, SynchronousMachine, InductionMachine}
                    @testset "SI_scale" begin
                        b = bases(model)
                        currents = model isa Union{MMC, TLC} ?
                                   [b.S / b.v_dc, 2b.S / (3b.v_ac), 2b.S / (3b.v_ac)] :
                                   fill(2b.S / (3b.v_ac), 2)
                        voltages = model isa Union{MMC, TLC} ?
                                   [b.v_dc, b.v_ac, b.v_ac] : fill(b.v_ac, 2)
                        if model isa MMC
                            currents[2:3] .*= model.elec.turnsRatio
                        end
                        reference = currents ./ transpose(voltages)
                        scale = PI.SI_scale(model)
                        @test size(scale) == size(reference)
                        @test scale ≈ reference rtol = 1e-14
                    end
                end
            end
        end
    end
    @test PI.admittance_order(impedance(z = 1.0)) ===
          ((:side1, :dc), (:side2, :dc))
    @test all(predicate -> nameof(predicate) ∉ names(PI), PREDICATES)
    @test :admittance_order ∉ names(PI)
end
end
