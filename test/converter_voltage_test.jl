module ConverterVoltageTests
using PowerImpedance, Test, LinearAlgebra
const PI=PowerImpedance
const NB=PI.NetworkBuilder
include("pscad/fixtures.jl")
function voltage_fixture(reactive)
    fixture=PSCADFixtures.mmc_pq_network()
    state=fixture
    circuit = PSCADFixtures._mmc_circuit(:pq)
    original, rows = circuit.elements, circuit.rows
    e=deepcopy(original.DUT)
    m=e.element_model
    e=PI.mmc(; m.elec, m.meas, m.sync, m.sigma_control, m.modulation,
        delta_control = PI.ΔdqControlGFL(outer_active = m.delta_control.outer_active,
            outer_reactive = reactive, occ = m.delta_control.occ), setpoint = e.setpoint, limits = e.limits)
    e.setpoint=Setpoint(
        Pac = 600.0, Qac = 200.0, Vac = 1.01*380sqrt(2/3), θac = 0.0,
        Vdc = 800.0, Pdc = 600.0)
    branch=impedance(z = s->0.19+s*0.0122, pins = 3, transformation = true)
    elements=merge(original, (; DUT = e, branch))
    rows=[(; node = r.element==:G_AC ? Symbol("source_", r.terminal) : r.node,
              r.element, r.side, r.terminal) for r in rows]
    append!(rows, [(node = Symbol("source_", t), element = :branch, side = 1, terminal = t)
                   for t in 1:2])
    append!(rows,
        [(node = Symbol("AC", t==1 ? "d" : "q"), element = :branch, side = 2, terminal = t)
         for t in 1:2])
    return PI.NetworkBuilder.define(elements, rows; options = state.options)
end

function equilibrium(m, terminal_values)
    inputs, sp=PI.pftoinputs(m, terminal_values)
    seed=PI.orderedinitialvalues(m; inputs, setpoint_pu = sp)
    f!(F, x, p) = PI._state_space!(F, x, p.inputs, p.sp, p.m, PI.Equil())
    p=(; inputs = collect(values(inputs)), sp, m)
    sol=PI.solve(PI.NonlinearProblem(f!, collect(promote(values(seed)...)), p);
        maxiters = 20, abstol = 1e-6, reltol = 1e-6)
    F=zeros(length(sol.u))
    f!(F, sol.u, p)
    return sol, F, inputs, sp
end

function vac_grid(fixture, converter)
    state = fixture
    (; elements, rows) = PSCADFixtures._tlc_circuit(false)
    # Keep the original plant and give VAC a separate converter bus. This is
    # the 0.1 H grid reactor used by PSCADFixtures.tlc_vac_network.
    grid = impedance(z = s -> 0.1s, pins = 3, transformation = true)
    rows = [(; node = r.element == :G3 ? Symbol("Grid" * string(r.terminal)) : r.node,
                r.element, r.side, r.terminal) for r in rows]
    append!(rows, [(node = Symbol("Grid" * string(t)),
                       element = :Grid, side = 1, terminal = t)
                   for t in 1:2])
    append!(rows,
        [(node = Symbol("AC" * axis), element = :Grid, side = 2, terminal = t)
         for (t, axis) in enumerate(("d", "q"))])
    return NB.define(merge(elements, (; DUT = converter, Grid = grid)), rows;
        options = state.options)
end

bits(x::AbstractArray{Float64}) = reinterpret(UInt64, vec(x))
@testset "Converter AC voltage base and power flow" begin
    for reactive in (OuterReactiveVacControl(pi_ctrl = PIControl(Kp = 0.0, Ki = 100.0)),
        OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159),
        support = VoltageSupportLag(K = 20.0, ωc = 100.0)))
        state=voltage_fixture(reactive)
        model=state.elements.DUT
        @test model.elec.turnsRatio != 1.0
        @test PI.pf_type_ac(PI.ΔdqControlGFM(outer_reactive = reactive,
            vi = PI.CCVI(), occ = model.delta_control.occ))==2
        declared = (ac = ACPortValues(1.01*380sqrt(2/3), 0.0, 600.0, 200.0),
            dc = DCPortValues(800.0, -600.0))
        inputs, sp=PI.pftoinputs(model, declared)
        signals=PI.input_signals(
            model, (;
                Δθ_pll = 0.0, iΔ_d = 0.0, iΔ_q = 0.0, iΣ_z = 0.0), inputs)
        meas=(; vG_d_f = signals.vG_d, vG_q_f = signals.vG_q, Q_ac_f = sp.q_ac)
        rates=zeros(PI.n_states(reactive))
        PI.state_space!(rates, (; ξ_v_ac = 0.0, ξ_Q_ac = 0.0, ξ_vac_supp = 0.0),
            (; meas), sp, reactive, model)
        @test norm(rates, Inf)<=1e-6

        data, bases, mapping=convert(state, PI.PMACDC)
        c=data["convdc"][string(mapping[:DUT].compkey)]
        bus=data["bus"][string(c["busac_i"])]
        @test c["type_ac"]==2
        @test bus["bus_type"]==2
        @test c["Vtar"]==(declared.ac.v/sqrt(2))/(bases["V"]/1e3)
        @test bus["vm"]==c["Vtar"]
        @test c["acq_droop"]==(reactive isa OuterReactiveVacControl ? 0 : 1)
        @test c["kq_droop"]==(reactive isa OuterReactiveVacControl ? 0.0 :
                              reactive.support.K*(model.elec.Sbase/(bases["S"]*1e-6)))
        alternate_bases=PI.PowerModelsACDC._get_pu_bases(250.0, state.options.voltageBase)
        alternate_bases["omega"]=100π
        alternate=deepcopy(data)
        PI.convert!(alternate, model, PI.PMACDC,
            (; name = :DUT, index = c["index"], pmtype = "convdc"),
            (ac = c["busac_i"], dc = c["busdc_i"]), alternate_bases)
        @test alternate["convdc"][string(c["index"])]["kq_droop"]==(reactive isa
                                                                    OuterReactiveVacControl ?
                                                                    0.0 :
                                                                    4.0*reactive.support.K)
        solved=NB.solve(state)
        element=state.elements.DUT
        solution=solved.result["solution"]
        record=solved.data["convdc"][string(solved.elem2comp[:DUT].compkey)]
        values=solved.operating_point[:DUT]
        sol, F, inputs, sp=equilibrium(element, values)
        @test PI.SciMLBase.successful_retcode(sol)
        @test norm(F, Inf)<=1e-6 # The existing converter equilibrium tolerance.
        @test values.ac.v≈sqrt(2)*state.options.voltageBase*
            solution["bus"][string(record["busac_i"])]["vm"]
        x=NamedTuple{PI.statenames(model)}(Tuple(sol.u[1:PI.n_states(model)]))
        signals=PI.input_signals(model, x, inputs)
        measured=PI.state_space!(zeros(PI.n_states(model.meas)), x, signals,
            model.meas, model)
        @test abs(measured.P_ac_f-sp.p_ac)<=1e-6
        @test abs(measured.Q_ac_f-sp.q_ac)<=1e-6
        if reactive isa OuterReactiveQControl
            flow=solution["convdc"][string(record["index"])]
            vm=solution["bus"][string(record["busac_i"])]["vm"]
            # PowerModelsACDC 0.10.1 formconv/acp.jl:154-159:
            # qgrid = -Q_g - kq_droop*(Vtar-vm).
            @test flow["qgrid"]≈
                -record["Q_g"]-record["kq_droop"]*(record["Vtar"]-vm) atol=1e-6
        end
    end
    @testset "TLC shared semantics and unchanged arithmetic" begin
        for reactive in (NoOuterReactiveControl(),
            OuterReactiveVacControl(pi_ctrl = PIControl(Kp = 0.04, Ki = 40.0)),
            OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.04, Ki = 40.0)),
            OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.04, Ki = 40.0),
            support = VoltageSupportLag(K = 5.0, ωc = 2.0)))
            fixture=PSCADFixtures.tlc_network(false)
            state=fixture
            (; elements, rows) = PSCADFixtures._tlc_circuit(false)
            e=deepcopy(elements.DUT)
            m=e.element_model
            e=PI.tlc(elec = m.elec, meas = m.meas, sync = m.sync,
                outerActive = m.outerActive, outerReactive = reactive,
                innerVoltage = m.innerVoltage, innerCurrent = m.innerCurrent,
                mod = m.mod, setpoint = e.setpoint, limits = e.limits)
            state=reactive isa OuterReactiveVacControl ? vac_grid(fixture, e) :
                  NB.define(merge(elements, (; DUT = e)), rows; options = state.options)
            data, bases, mapping=convert(state, PI.PMACDC)
            c=data["convdc"][string(mapping[:DUT].compkey)]
            controlled=reactive isa OuterReactiveVacControl ||
                       (reactive isa OuterReactiveQControl &&
                        reactive.support isa VoltageSupportLag)
            @test c["type_ac"]==(controlled ? 2 : 1)
            @test data["bus"][string(c["busac_i"])]["bus_type"]==(reactive isa
                                                                  OuterReactiveVacControl ?
                                                                  2 : 3)
            @test c["Vtar"]==(e.setpoint.Vac/sqrt(2))/(bases["V"]/1e3)
            @test c["acq_droop"]==(reactive isa OuterReactiveQControl &&
                                   reactive.support isa VoltageSupportLag ? 1 : 0)
            @test c["kq_droop"]==(reactive isa OuterReactiveQControl &&
                                  reactive.support isa VoltageSupportLag ?
                                  5.0*(m.elec.Sbase/(bases["S"]*1e-6)) : 0.0)
            sp=PI.SetpointPU(v_ac = 0.973, q_ac = -0.217)
            meas=(; vG_d_f = 0.891, vG_q_f = -0.133, Q_ac_f = -0.178)
            x=(; ξ_v_ac = 0.071, ξ_Q_ac = -0.087, ξ_vac_supp = 0.013)
            F=zeros(PI.n_states(reactive))
            expected=similar(F)
            result=reactive isa NoOuterReactiveControl ?
                   PI.state_space!(F, x, (; meas), reactive, e.element_model) :
                   PI.state_space!(F, x, (; meas), sp, reactive, e.element_model)
            voltage=sqrt(meas.vG_d_f^2+meas.vG_q_f^2)
            if reactive isa OuterReactiveVacControl
                expected[1]=reactive.pi_ctrl.Ki*(sp.v_ac-voltage)
                qref=reactive.pi_ctrl.Kp*(sp.v_ac-voltage)+x.ξ_v_ac
            elseif reactive isa OuterReactiveQControl
                support=0.0
                if reactive.support isa VoltageSupportLag
                    expected[1]=reactive.support.ωc*(reactive.support.K*(sp.v_ac-voltage)-x.ξ_vac_supp)
                    support=x.ξ_vac_supp
                end
                error=sp.q_ac+support-meas.Q_ac_f
                expected[end]=reactive.pi_ctrl.Ki*error
                qref=reactive.pi_ctrl.Kp*error+x.ξ_Q_ac
            else
                qref=0.0
            end
            @test bits(F)==bits(expected)
            @test reinterpret(UInt64, result.q_ctrl_ref)==reinterpret(UInt64, qref)
        end
    end
    @testset "TLC VAC operating points with P and Vdc control" begin
        for vdc_control in (false, true)
            fixture = PSCADFixtures.tlc_network(vdc_control)
            state = fixture
            original = PSCADFixtures._tlc_circuit(vdc_control).elements.DUT
            m = original.element_model
            element = PI.tlc(elec = m.elec, meas = m.meas, sync = m.sync,
                outerActive = m.outerActive,
                outerReactive = OuterReactiveVacControl(pi_ctrl = PIControl(Kp = 0.04, Ki = 40.0)),
                innerVoltage = m.innerVoltage, innerCurrent = m.innerCurrent,
                mod = m.mod, setpoint = original.setpoint, limits = original.limits)
            state = vac_grid(fixture, element)
            solved = NB.solve(state)
            element = state.elements.DUT
            sol, F, inputs, sp = equilibrium(element, solved.operating_point[:DUT])
            @test PI.SciMLBase.successful_retcode(sol)
            @test norm(F, Inf) <= 1e-6
            m = element
            x = NamedTuple{PI.statenames(m)}(Tuple(sol.u[1:PI.n_states(m)]))
            signals = PI.input_signals(m, x, inputs)
            measured = PI.state_space!(zeros(PI.n_states(m.meas)), x, signals, m.meas, m)
            # Vdc control constrains DC current, so AC power agrees only to the
            # PF accuracy, not the nonlinear equilibrium residual tolerance.
            # constr_viol_tol=0.001 on 1000 MVA means 1 MW; convert to model pu.
            tolerance = only(p.second
            for p in NB.powerflow_optimizer(state.options).params
            if p.first == PI.JuMP.MOI.RawOptimizerAttribute("constr_viol_tol"))
            power_tolerance = vdc_control ?
                              tolerance * solved.data["baseMVA"] / m.elec.Sbase :
                              1e-6
            @test abs(measured.P_ac_f - sp.p_ac) <= power_tolerance
            @test abs(measured.Q_ac_f - sp.q_ac) <= 1e-6
        end
    end
    @testset "MMC without voltage support" begin
        fixture=PSCADFixtures.mmc_pq_network()
        model=fixture.elements.DUT
        reactive=model.delta_control.outer_reactive
        F=zeros(1)
        sp=PI.SetpointPU(v_ac = 1.2, q_ac = -0.217)
        meas=(; vG_d_f = 0.891, vG_q_f = -0.133, Q_ac_f = -0.178)
        x=(; ξ_Q_ac = -0.087)
        result=PI.state_space!(F, x, (; meas), sp, reactive, model)
        error=sp.q_ac+0.0-meas.Q_ac_f
        @test bits(F)==bits([reactive.pi_ctrl.Ki*error])
        @test reinterpret(UInt64, result.q_ctrl_ref)==reinterpret(UInt64, reactive.pi_ctrl.Kp*error+x.ξ_Q_ac)
        @test PI.pf_type_ac(model.delta_control)==1
        @test PI.pf_acq_droop(reactive)==(enabled = 0, kq = 0.0)
    end
end
end
