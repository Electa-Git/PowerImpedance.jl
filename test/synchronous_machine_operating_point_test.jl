module SynchronousMachineOperatingPointTests
using Test, LinearAlgebra, PowerImpedance
const PI = PowerImpedance
const NB = PI.NetworkBuilder

# These are the unchanged production solve accuracies, in per unit.
const DYNAMIC_ATOL = 1e-6
const POWER_FLOW_ATOL = 1e-3

function terminal_quantities(m, inputs, state)
    x = NamedTuple{PI.statenames(m)}(state)
    Vbus = complex(inputs.vd, -inputs.vq)
    Igen = conj(cis(-x.θ_sg) * complex(x.i_d, x.i_q))
    Vterminal = Vbus + complex(m.elec.rt, m.elec.lt) * Igen
    return (; x, Igen, Vterminal, Sterminal=Vterminal * conj(Igen),
        Ef=m.elec.La_d * x.v_df / m.elec.Rf_d)
end

@testset "Synchronous machine references and phasor initialization" begin
    for (vbase, sbase, θ, Ra, rt, lt, p, q, v, gain) in (
            (380.0, 1000.0, 0.0, 0.0015, 0.0026, 0.065, 0.9, -0.01, 1.0002, 200.0),
            (220.0, 500.0, 0.37, 0.004, 0.012, 0.09, 0.65, 0.18, 1.04, 123.0),
            (110.0, 100.0, -0.28, 0.0, 0.0, 0.0, 0.3, -0.12, 0.98, 150.0),
            (220.0, 1000.0, -0.1, 0.0015, 1e-10, 1e-10, 24.2, 0.0, 1/sqrt(2), 200.0))
        electrical = ElectricalSM(Vᵃᶜ_base=vbase, S_base=sbase, Ra=Ra, rt=rt, lt=lt,
            L23_d=0.01, L23_q=0.02)
        m = SynchronousMachine(electrical, MechanicalSM(), AVRSM(v_ref=1.2, K_A=gain),
            GovernorSM(), PI.Limits(), (p = 0.0, q = 0.0, v = 1.0),
            PI.LinearizationCache())
        # Independent fixture starts at the machine terminal, not the bus.
        Vterminal = v * cis(θ)
        Igen = conj(complex(p, q) / Vterminal)
        Vbus = Vterminal - complex(rt, lt) * Igen
        sp = Setpoint(Pac=p*sbase, Qac=q*sbase,
            Vac=abs(Vbus)*vbase*sqrt(2/3), θac=angle(Vbus))
        inputs, pu = PI.pftoinputs(m, sp)
        @test inputs.Tm0 ≈ p + Ra*abs2(Igen)
        @test pu.p_ac == p
        @test pu.q_ac ≈ q
        @test m.avr.v_ref == 1.2
        seed = PI.orderedinitialvalues(m; inputs, setpoint_pu=pu)
        quantities = terminal_quantities(m, inputs, collect(values(seed)))
        @test quantities.Igen ≈ Igen atol=DYNAMIC_ATOL
        @test quantities.Vterminal ≈ Vterminal atol=DYNAMIC_ATOL
        @test seed.ω_pu == 1.0
        @test (seed.i_d1, seed.i_q1, seed.i_q2, seed.δω_filt) == (0.0, 0.0, 0.0, 0.0)
        @test (seed.flow, seed.TchHP, seed.TreIP, seed.TcrLP) == ntuple(_ -> inputs.Tm0, 4)
        # Salient-machine field voltage, independently in the terminal frame.
        E_q = Vterminal + complex(Ra, electrical.La_q + electrical.Ll) * Igen
        i_d = real(cis(angle(E_q) - π/2) * conj(Igen))
        Ef = abs(E_q) + (electrical.La_d - electrical.La_q)*i_d
        @test inputs.vref_SG ≈ abs(Vterminal) + Ef/gain
        @test quantities.Ef ≈ Ef
        F = zeros(PI.n_states(m))
        PI._state_space!(F, collect(values(seed)), collect(values(inputs)), pu, m, PI.Equil())
        @test norm(F, Inf) <= DYNAMIC_ATOL
        element = synchronousmachine(elec=electrical, avr=m.avr, setpoint=sp)
        PI.update!(element, sp)
        state = PI._steady_state(element)
        actual = terminal_quantities(m, inputs, state)
        @test actual.Sterminal ≈ complex(p, q) atol=DYNAMIC_ATOL rtol=0
        @test actual.Vterminal ≈ Vterminal atol=DYNAMIC_ATOL rtol=0
        @test inputs.Tm0 ≈ real(actual.Sterminal) + Ra*abs2(actual.Igen) atol=DYNAMIC_ATOL
        @test actual.Ef ≈ gain*(inputs.vref_SG-abs(actual.Vterminal)) atol=DYNAMIC_ATOL
        @test size(element.B) == (16, 2)
        @test size(element.D) == (2, 2)
        # Perturb the electrical inputs with commands held fixed, as in the
        # linearization; reference conversion must not become feedback.
        perturbed = collect(values(inputs))
        perturbed[1] += 0.01
        PI._state_space!(F, state, perturbed, pu, m, PI.Equil())
        @test norm(F, Inf) > DYNAMIC_ATOL
        @test abs(F[7]) <= DYNAMIC_ATOL # Fixed turbine torque.
        @test abs(F[15]) <= DYNAMIC_ATOL # Fixed AVR error at held states.
        @test abs(F[16]) <= DYNAMIC_ATOL
    end
end

@testset "Synchronous machine without a complete power-flow point" begin
    m = SynchronousMachine(ElectricalSM(), MechanicalSM(), AVRSM(v_ref=1.03),
        GovernorSM(), PI.Limits(), (p = 0.0, q = 0.0, v = 1.0),
        PI.LinearizationCache())
    sp = Setpoint(Pac=50.0, Vac=220sqrt(2/3), θac=0.12)
    inputs, pu = PI.pftoinputs(m, sp)
    @test pu === nothing
    @test inputs.Tm0 == 0.05
    @test inputs.vref_SG == 1.03
    seed = PI.orderedinitialvalues(m; inputs, setpoint_pu=pu)
    @test seed.i_d == seed.i_q == seed.i_df == seed.θ_sg == seed.v_f == seed.v_df == 0.0
    @test seed.ω_pu == 1.0
    @test seed.flow == seed.TchHP == seed.TreIP == seed.TcrLP == inputs.Tm0
    F = zeros(16)
    PI.state_space!(F, seed, inputs, m)
    Fraw = zeros(16)
    # The standalone equations also retain the configured AVR reference.
    PI.state_space!(Fraw, seed, (; inputs.vd, inputs.vq, inputs.Tm0), m)
    @test F == Fraw
    raw = synchronousmachine(avr=m.avr)
    @test raw.element_model.avr.v_ref == 1.03
    @test isempty(raw.A)
end

include("pscad/fixtures.jl")
@testset "Synchronous machine power-flow and dynamic equilibrium agree" begin
    fixture = PSCADFixtures.sm_network()
    pf_classic = power_flow(fixture.classic)
    solved_builder = NB.solve(fixture.state)
    classic_list = PI.PSCAD.netlist(fixture.classic, pf_classic)
    builder_list = PI.PSCAD.netlist(fixture.state, solved_builder.powerflow)
    for (net, netlist) in ((fixture.classic, classic_list), (solved_builder.network, builder_list))
        element = net.elements[:sg1]
        m = element.element_model
        inputs, pu = PI.pftoinputs(m, element.setpoint)
        state = PI._steady_state(element)
        actual = terminal_quantities(m, inputs, state)
        flow = netlist.operating_point.branch_flows[:sg1]
        Vt_pf = flow.terminal_voltage_kV*sqrt(3)/m.elec.Vᵃᶜ_base * cis(flow.terminal_angle_rad)
        @test real(actual.Sterminal) ≈ flow.pg/m.elec.S_base atol=DYNAMIC_ATOL rtol=0
        @test imag(actual.Sterminal) ≈ flow.qg/m.elec.S_base atol=DYNAMIC_ATOL rtol=0
        @test actual.Vterminal ≈ Vt_pf atol=POWER_FLOW_ATOL rtol=0
        @test abs(actual.Vterminal) ≈ abs(Vt_pf) atol=POWER_FLOW_ATOL rtol=0
        @test inputs.vref_SG != m.avr.v_ref
        @test inputs.Tm0 > element.setpoint.Pac/m.elec.S_base
        F = zeros(16)
        PI._state_space!(F, state, collect(values(inputs)), pu, m, PI.Equil())
        @test norm(F, Inf) <= DYNAMIC_ATOL
        @test state ≈ collect(values(PI.orderedinitialvalues(m; inputs, setpoint_pu=pu))) atol=DYNAMIC_ATOL
        # A changed operating point recomputes references from its own phasors.
        next_sp = Setpoint(Pac=700.0, Qac=40.0, Vac=element.setpoint.Vac, θac=0.2)
        PI.update!(element, next_sp)
        next_inputs, _ = PI.pftoinputs(m, next_sp)
        next_actual = terminal_quantities(m, next_inputs, PI._steady_state(element))
        @test next_actual.Sterminal ≈ complex(0.7, 0.04) atol=DYNAMIC_ATOL rtol=0
        @test next_inputs.vref_SG != inputs.vref_SG
        @test m.avr.v_ref == 1.01
    end
end
end
