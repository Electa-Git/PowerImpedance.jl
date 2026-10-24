module ModelPredicatesTests
using Test, PowerImpedance
const PI = PowerImpedance
include("parity/fixtures.jl")

const PREDICATES = (PI.is_source, PI.is_converter, PI.is_generator,
    PI.is_inductionmachine, PI.is_passive, PI.is_active, PI.issingleport,
    PI.is_three_phase)

@testset "Model predicates and admittance coordinates" begin
    for fixture in ParityFixtures.FIXTURES
        state = fixture.build()
        for (name, element) in pairs(state.elements)
            model = element.element_model
            model isa PI.Blackbox_MMC && continue
            @testset "$(fixture.name).$name" begin
                for predicate in PREDICATES
                    @testset "$(nameof(predicate))" begin
                        if predicate === PI.is_three_phase &&
                           model isa Union{SynchronousMachine, InductionMachine}
                            @test predicate(model)
                            println("is_three_phase fixture=$(fixture.name) element=$name ",
                                "model=$(predicate(model)) Element=$(predicate(element))")
                        else
                            @test predicate(model) == predicate(element)
                        end
                    end
                end
                order = PI.admittance_order(model)
                @testset "admittance_order" begin
                    if model isa Union{MMC, TLC}
                        @test order === ((:dc, :dc), (:ac, :d), (:ac, :q))
                    elseif model isa Union{SynchronousMachine, InductionMachine}
                        @test order === ((:ac, :d), (:ac, :q))
                    elseif PI.is_source(model)
                        expected = model.domain === ACABC ?
                            ((:ac, :a), (:ac, :b), (:ac, :c)) : ((:dc, :dc),)
                        @test order === expected
                    end
                    if !element.transformation && !PI.is_source(model)
                        if model isa PI.AbstractStateSpace
                            b = bases(model)
                            point = Setpoint(Pac = 0.0, Qac = 0.0, θac = 0.0,
                                Vac = b.v_ac, Pdc = 0.0, Vdc = something(b.v_dc, missing))
                            PI.update!(element, point)
                        end
                        @test length(order) == size(PI.get_y(element, 2π * im * 100), 1)
                    end
                end
                if model isa Union{MMC, TLC, SynchronousMachine, InductionMachine}
                    @testset "SI_scale" begin
                        wrapped, direct = PI.SI_scale(element), PI.SI_scale(model)
                        @test size(wrapped) == size(direct)
                        @test all(wrapped .=== direct)
                    end
                end
            end
        end
    end
    @test PI.admittance_order(impedance(z = 1.0).element_model) ===
        ((:side1, :dc), (:side2, :dc))
    @test all(predicate -> nameof(predicate) ∉ names(PI), PREDICATES)
    @test :admittance_order ∉ names(PI)
end
end
