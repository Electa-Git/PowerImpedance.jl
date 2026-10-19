module InductionMachinePowerFlowTests
using Test, LinearAlgebra, PowerImpedance
const PI = PowerImpedance
const NB = PI.NetworkBuilder
const POWER_FLOW_ATOL = 1e-5
const DYNAMIC_ATOL = 1e-6

include("pscad/fixtures.jl")

@testset "Induction machine power flow and dynamic steady state" begin
    for (sbase, rt, lt) in ((1000.0, 0.0, 0.0), (2000.0, 0.0, 0.0),
            (1000.0, 0.017, 0.0), (1000.0, 0.0, 0.04), (2000.0, 0.017, 0.04))
        pair = PSCADFixtures.im_network(elec = ElectricalIM(S_base = sbase,
            r_s = 0.01, rt = rt, lt = lt))
        for representation in (:classic, :builder)
            @testset "$representation S_base=$sbase rt=$rt lt=$lt" begin
                if representation === :classic
                    network = pair.classic
                    result, data = power_flow(network)
                else
                    solved = NB.solve(pair.state)
                    network = solved.network
                    result, data = solved.powerflow.result, solved.powerflow.data
                end
                @test result["termination_status"] == PI.MOI.LOCALLY_SOLVED
                element = network.elements[:im1]
                m = element.element_model
                state = PI._steady_state(element)
                x = NamedTuple{PI.statenames(m)}(state)
                inputs, pu = PI.pftoinputs(m, element.setpoint)
                current = zeros(2)
                PI.outputequations!(current, x, inputs, nothing, m)
                power = complex(inputs.vd, -inputs.vq) *
                        conj(complex(current[1], -current[2])) *
                        m.elec.S_base / data["baseMVA"]
                flow = only(values(result["solution"]["im"]))
                @test real(power) ≈ flow["pg"] atol = POWER_FLOW_ATOL rtol = 0
                @test imag(power) ≈ flow["qg"] atol = POWER_FLOW_ATOL rtol = 0
                @test 1 - x.ω_r ≈ flow["slip"] atol = POWER_FLOW_ATOL rtol = 0
                residual = zeros(PI.n_states(m))
                PI._state_space!(residual, state, collect(values(inputs)), pu, m, PI.Equil())
                @test norm(residual, Inf) <= DYNAMIC_ATOL
                converted = only(values(data["im"]))
                torque = sbase == 2000.0 ? 1.8 : 0.9
                @test converted["torque"]["T_0"] == torque
                @test converted["P_ag"] == torque
                @test converted["Pacmin"] == 0.9torque
                @test converted["Pacmax"] == 1.1torque
                @test converted["Pacrated"] == torque
            end
        end
    end
end
end
