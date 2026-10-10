using Logging
include("legacy_mmc_reference.jl")

@testset "Legacy converter setpoint references" begin
    for (kind, adapter) in ((:mmc, NB._legacy_mmc), (:tlc, NB._legacy_tlc))
        for (control, field, reference, expected) in (
                (:p, :Pac, kind === :mmc ? 100.0 : 0.2, 100.0),
                (:q, :Qac, kind === :mmc ? 25.0 : 0.05, 25.0),
                (:dc, :Vdc, 1.05, 672.0),
                (:vac, :Vac, 180.0, 180.0),
                (:vac_supp, :Vac, 180.0, 180.0))
            controller = PI_control(Kₚ = 0.2, Kᵢ = 5.0, ref = [reference], ω_f = 2.0)
            kwargs = (; Sbase = 500.0, controls = Dict(control => controller))
            element = @test_logs min_level=Logging.Warn adapter(kwargs, :c1)
            @test getfield(element.setpoint, field) == expected
            @test controller.ref == [reference] # The adapter never mutates controls.
            fixed = expected + 10.0
            point = Setpoint(; field => fixed)
            element = @test_logs (:warn, Regex("converter :c1: legacy :$control reference $expected differs from setpoint $fixed")) adapter((; kwargs..., setpoint = point), :c1)
            @test getfield(element.setpoint, field) == fixed
            element = @test_logs min_level=Logging.Warn adapter((; kwargs..., setpoint = Setpoint(; field => expected)), :c1)
            @test getfield(element.setpoint, field) == expected
        end
        p = PI_control(Kₚ = 0.2, Kᵢ = 5.0, ref = [kind === :mmc ? 100.0 : 0.2])
        element = @test_logs (:warn, r"converter :c2: legacy :p reference 100.0 differs from setpoint 75.0") adapter((; Sbase = 500.0, P = 75.0, p), :c2)
        @test element.setpoint.Pac == 75.0
        @test adapter((; Sbase = 500.0, P = missing, p), :c2).setpoint.Pac == 100.0
        @test adapter((; P = 75.0, p = PI_control(ref = [0]))).setpoint.Pac == 75.0
    end
    # Network names are available when the lazy converter is materialized.
    space = NB.define((; station = mmc(Grid; P = 75.0,
        p = PI_control(ref = [100.0]))), [
        (node = :dc, element = :station, side = 1, terminal = 1),
        (node = :d, element = :station, side = 2, terminal = 1),
        (node = :q, element = :station, side = 2, terminal = 2)])
    state = @test_logs (:warn, r"converter :station: legacy :p reference 100.0 differs from setpoint 75.0") materialize(first(configurations(space)))
    @test state.elements.station.setpoint.Pac == 75.0
    @test_throws ArgumentError mmc(Grid; P = 75.0, elec = ElectricalMMC())
    @test_throws ArgumentError tlc(Grid; P = 75.0, elec = ElectricalTLC())
end

@testset "Legacy Butterworth transfer functions" begin
    for order in 1:6
        old_A, old_B, old_C, old_D = LegacyMMCReference.butterworthMatrices(order, 120.0, 1)
        filter = PI.measurement_filter_ss(PI.Butterworth(order = order, ωc = 120.0))
        for ω in (1.0, 120.0, 1000.0)
            s = im * ω
            old = only(old_C * ((s*I - old_A) \ old_B)) + old_D
            new = only(filter.C * ((s*I - filter.A) \ filter.B) + filter.D)
            @test new ≈ old
        end
    end
end

@testset "Legacy MMC steady state and admittance" begin
    for order in (0, 2)
        controls = PI.OrderedDict{Symbol,PI.Controller}(
            :pll => PI_control(Kₚ = 0.085, Kᵢ = 32.0),
            :p => PI_control(Kₚ = 0.2, Kᵢ = 10.0, n_f = order, ω_f = 80.0),
            :q => PI_control(Kₚ = 0.2, Kᵢ = 10.0, ref = [25.0], n_f = order, ω_f = 120.0),
            :ccc => PI_control(Kₚ = 0.1, Kᵢ = 43.0, ref = [0.02, -0.01]),
            :energy => PI_control(Kₚ = 1.4, Kᵢ = 30.0, ref = [1.1]),
            :occ => PI_control(Kₚ = 0.1, Kᵢ = 43.0),
            :zcc => PI_control(Kₚ = 0.1, Kᵢ = 43.0))
        old = LegacyMMCReference.MMC(; Sbase = 500.0, controls = deepcopy(controls))
        LegacyMMCReference.update!(old, 380sqrt(2/3), 0.0, 50.0, -25.0, 640.0, 50.0)
        e = NB._legacy_mmc((; Sbase = 500.0, controls = deepcopy(controls),
            P = 50.0, Vₘ = 380/sqrt(3), Vᵈᶜ = 640.0, P_dc = 50.0))
        PI.update!(e, e.setpoint)
        m = e.element_model
        inputs, sp = PI.pftoinputs(m, e.setpoint)
        seed = PI.orderedinitialvalues(m; inputs, setpoint_pu = sp)
        f!(F, x, p) = PI._state_space!(F, x, p.inputs, p.sp, p.m, PI.Equil())
        solution = PI.solve(PI.NonlinearProblem(f!, collect(promote(values(seed)...)),
            (; inputs = collect(values(inputs)), sp, m)); maxiters = 20, abstol = 1e-6, reltol = 1e-6)
        @test PI.SciMLBase.successful_retcode(solution)
        @test solution.u[end-11:end] ≈ old.equilibrium[1:12]
        for ω in (2π, 100π, 1000π)
            reference = LegacyMMCReference.eval_parameters(old, ComplexF64(im*ω))
            reference[2:3, :] .*= -1 # Convert generation to terminal load-current sign.
            @test PI.eval_y(e, ComplexF64(im*ω)) ≈ reference
        end
    end
end

@testset "Legacy converter controls and filters" begin
    ctrl = PI_control(Kₚ = 0.3, Kᵢ = 7.0, n_f = 2, ω_f = 120.0)
    for adapter in (NB._legacy_mmc, NB._legacy_tlc)
        e = adapter((; P = 50.0, Q = 0.0, Vᵈᶜ = 640.0,
            p = ctrl, q = ctrl, dc = ctrl, vac = ctrl, pll = ctrl,
            v_meas_filt = ctrl, i_meas_filt = ctrl, occ = ctrl,
            f_supp = PI_control(Kₚ = 5.0, ω_f = 2.0)))
        m = e.element_model
        active = m isa MMC ? m.delta_control.outer_active : m.outerActive
        reactive = m isa MMC ? m.delta_control.outer_reactive : m.outerReactive
        occ = m isa MMC ? m.delta_control.occ : m.innerCurrent
        @test active isa OuterActivePowerControl
        @test reactive isa OuterReactiveQControl
        @test active.pi_ctrl == PIControl(Kp = 0.3, Ki = 7.0)
        @test active.support == FrequencySupportLag(Kω = 5.0, ωc = 2.0)
        @test m.sync.pi_ctrl == PIControl(Kp = 0.3, Ki = 7.0)
        @test length(PI.statenames(m.sync)) == 4
        @test size(m.meas.vG_d.filter.A) == (2, 2)
        @test size(m.meas.i_d.filter.A) == (2, 2)
        @test m.meas.v_dc.filter isa PI.NoFilter
        @test occ.pi_ctrl == PIControl(Kp = 0.3, Ki = 7.0)
        if m isa MMC
            @test size(m.meas.P_ac.filter.A) == (2, 2)
            @test size(m.meas.Q_ac.filter.A) == (2, 2)
            @test size(occ.filter.A) == (2, 2)
            @test !occ.activate_ω_c_multiplication
        else
            @test m.meas.P_ac.filter isa PI.NoFilter
            @test m.meas.Q_ac.filter isa PI.NoFilter
            @test occ.filter isa PI.NoFilter # Historical TLC occ filter fields are unused.
            @test occ.activate_ω_c_multiplication
        end
        e = adapter((; dc = ctrl, vac = ctrl, Vᵈᶜ = 640.0))
        m = e.element_model
        active = m isa MMC ? m.delta_control.outer_active : m.outerActive
        reactive = m isa MMC ? m.delta_control.outer_reactive : m.outerReactive
        @test active isa OuterActiveVdcControl
        @test PI.n_states(active) == 3
        @test size(active.filter.A) == (2, 2)
        @test reactive isa OuterReactiveVacControl
        @test reactive.pi_ctrl == PIControl(Kp = 0.3, Ki = 7.0)
        @test PI.n_states(reactive) == 3
    end
    e = NB._legacy_tlc((; q = ctrl, vac_supp = PI_control(Kₚ = 4.0, ω_f = 3.0)))
    @test e.element_model.outerReactive.support == VoltageSupportLag(K = 4.0, ωc = 3.0)
    e = NB._legacy_mmc((; q = ctrl, vac_supp = PI_control(Kₚ = 4.0, n_f = 1, ω_f = 3.0)))
    @test e.element_model.delta_control.outer_reactive.support == VoltageSupportLag(K = 4.0, ωc = 3.0)
    old_A, old_B, old_C, old_D = LegacyMMCReference.butterworthMatrices(1, 3.0, 1)
    for ω in (1.0, 3.0, 100.0)
        # Independent legacy magnitude-filter transfer to reactive support.
        reference = -4.0 * (only(old_C * ((im*ω*I - old_A) \ old_B)) + old_D)
        @test reference ≈ -e.element_model.delta_control.outer_reactive.support.K *
            e.element_model.delta_control.outer_reactive.support.ωc/(im*ω+e.element_model.delta_control.outer_reactive.support.ωc)
    end
    e = NB._legacy_mmc((; energy = PI_control(Kₚ = 1.4, Kᵢ = 30.0, ref = [1.1], n_f = 4, ω_f = 12.0),
        zcc = ctrl, ccc = PI_control(Kₚ = 0.1, Kᵢ = 43.0, ref = [0.02, -0.01], n_f = 3, ω_f = 15.0), q = ctrl))
    sigma = e.element_model.sigma_control
    @test sigma.tec.pi_control == PIControl(Kp = 1.4, Ki = 30.0)
    @test sigma.tec.ref == 1.1
    @test sigma.tec.power_filter.ωc == 120.0
    @test PI.n_states(sigma.tec) == 3 # q filter, not the energy filter.
    @test sigma.zscc.pi_control == PIControl(Kp = 0.3, Ki = 7.0)
    @test sigma.ccsc.ref == (0.02, -0.01)
    @test PI.n_states(sigma.ccsc) == 2 # ccc filter fields are unused.
    sigma = NB._legacy_mmc((; energy = PI_control(), ccc = PI_control())).element_model.sigma_control
    @test sigma.tec.ref == 1.0
    @test sigma.ccsc.ref == (0.0, 0.0)
end

@testset "Legacy control equations" begin
    conv = NB._legacy_mmc((; pll = PI_control(Kₚ = 0.1, Kᵢ = 5.0))).element_model
    sp = PI.SetpointPU(0.2, 0.1, 0.0, 1.05, 0.2, 1.1)
    meas = (; vG_d_f = 0.8, vG_q_f = 0.2, i_d_f = 0.3, i_q_f = -0.1,
        P_ac_f = 0.19, Q_ac_f = 0.09, v_dc_f = 1.02)
    inputs = (; meas, sync = (; ω_c = 1.03))
    active = OuterActivePowerControl(pi_ctrl = PIControl(Kp = 0.3, Ki = 7.0),
        support = FrequencySupportLag(Kω = 5.0, ωc = 2.0))
    F = zeros(2)
    y = PI.state_space!(F, (; ξ_f_supp = -0.02, ξ_P_ac = 0.07), inputs, sp, active, conv)
    @test F ≈ [2.0 * (-5.0 * (1.03 - 1.0) + 0.02), 7.0 * (0.2 - 0.02 - 0.19)]
    @test y.iΔ_d_ref ≈ 0.3 * (0.2 - 0.02 - 0.19) + 0.07
    reactive = OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.3, Ki = 7.0),
        support = VoltageSupportLag(K = 4.0, ωc = 3.0))
    y = PI.state_space!(F, (; ξ_vac_supp = 0.02, ξ_Q_ac = 0.07), inputs, sp, reactive, conv)
    @test F ≈ [3.0 * (4.0 * (1.05 - hypot(0.8, 0.2)) - 0.02), 7.0 * (0.1 + 0.02 - 0.09)]
    @test y.q_ctrl_ref ≈ 0.3 * (0.1 + 0.02 - 0.09) + 0.07
    F = zeros(1)
    y = PI.state_space!(F, (; ξ_v_dc = 0.07), inputs, sp,
        OuterActiveVdcControl(pi_ctrl = PIControl(Kp = 0.3, Ki = 7.0)), conv)
    @test F[1] ≈ 7.0 * (1.1 - 1.02)
    @test y.iΔ_d_ref ≈ -(0.3 * (1.1 - 1.02) + 0.07)

    ccc = CirculatingCurrentSuppressionControl(PIControl(Kp = 0.1, Ki = 43.0); ref = (0.02, -0.01))
    x = (; Δθ_pll = 0.2, iΣ_d = 0.07, iΣ_q = -0.04, ξ_iΣ_d = 0.01, ξ_iΣ_q = -0.02)
    d, q = [cos(-0.4) -sin(-0.4); sin(-0.4) cos(-0.4)] * [0.07, -0.04]
    F = zeros(2)
    y = PI.state_space!(F, x, meas, ccc, conv)
    @test F ≈ 43.0 .* [0.02 - d, -0.01 - q]
    @test y.vMΣ_d_ref_c ≈ -0.01 - 0.1 * (0.02 - d) + 2conv.elec.Lₐᵣₘ * q
    @test y.vMΣ_q_ref_c ≈ 0.02 - 0.1 * (-0.01 - q) - 2conv.elec.Lₐᵣₘ * d

    physical = (; vCΔ_d = 0.03, vCΔ_q = -0.02, vCΔ_Zd = 0.01, vCΔ_Zq = 0.02,
        vCΣ_d = 0.01, vCΣ_q = -0.03, vCΣ_z = 1.0, ξ_Wtot = 0.04)
    W = (0.03^2 + (-0.02)^2 + 0.01^2 + 0.02^2 + 0.01^2 + (-0.03)^2 + 2.0)/2
    for order in (0, 1, 2)
        filter = order == 0 ? PI.NoFilter() : PI.measurement_filter_ss(PI.Butterworth(order = order, ωc = 120.0))
        energy = TotalEnergyControl{typeof(filter)}(PIControl(Kp = 1.4, Ki = 30.0), 1.1, filter, true)
        raw_power = 0.8 * 0.3 + 0.2 * -0.1
        x = (; PI.initialvalues(energy; setpoint_pu = PI.SetpointPU(p_ac = raw_power))..., physical...)
        F = zeros(PI.n_states(energy))
        y = PI.state_space!(F, x, meas, energy, conv)
        @test F[end] ≈ 30.0 * (1.1 - W)
        @test all(abs.(F[1:end-1]) .< 1e-8)
        @test y.iΣ_z_ref ≈ (1.4 * (1.1 - W) + 0.04 + raw_power)/3/1.02
        Fz = zeros(1)
        yz = PI.state_space!(Fz, (; iΣ_z = 0.1, ξ_iΣ_z = 0.03), (; meas, out_Wtot = y),
            ZeroSequenceCurrentControl(PIControl(Kp = 0.3, Ki = 7.0)), conv)
        @test Fz[1] ≈ 7.0 * (y.iΣ_z_ref - 0.1)
        @test yz.vMΣ_z_ref ≈ 1.02/2 - 0.3 * (y.iΣ_z_ref - 0.1) - 0.03
    end
    # The default retains an existing modular power measurement exactly.
    energy = TotalEnergyControl(pi_control = PIControl(Kp = 1.4, Ki = 30.0), ref = 1.1)
    y = PI.state_space!(zeros(1), physical, meas, energy, conv)
    @test y.iΣ_z_ref == (1.4 * (1.1 - W) + 0.04 + 0.19)/3/1.02
    @test PI.statenames(energy) == (:ξ_Wtot,)
    energy = TotalEnergyControl(pi_control = PIControl(Kp = 1.4, Ki = 30.0),
        ref = 1.1, power_filter = PI.Butterworth(order = 2, ωc = 120.0))
    @test PI.n_states(energy) == 3
    x = (; PI.initialvalues(energy; setpoint_pu = PI.SetpointPU(p_ac = 0.22))..., physical...)
    y = PI.state_space!(zeros(3), x, meas, energy, conv)
    @test y.iΣ_z_ref ≈ (1.4 * (1.1 - W) + 0.04 + 0.22)/3/1.02
end

@testset "Legacy measured signals and current decoupling" begin
    ctrl = PI_control(Kₚ = 0.3, Kᵢ = 7.0, n_f = 2, ω_f = 120.0)
    for (kind, adapter) in ((:mmc, NB._legacy_mmc), (:tlc, NB._legacy_tlc))
        conv = adapter((; pll = ctrl, occ = ctrl, p = ctrl, q = ctrl, dc = ctrl,
            v_meas_filt = ctrl, i_meas_filt = ctrl)).element_model
        for signal in (conv.meas.vG_d, conv.meas.i_d, conv.meas.v_dc,
                conv.meas.P_ac, conv.meas.Q_ac)
            input = 0.37
            names = PI.statenames(signal)
            x = NamedTuple{names}(ntuple(i -> 0.001i, length(names)))
            F = zeros(length(names))
            y = PI.state_space!(F, x, NamedTuple{(signal.signal,)}((input,)), signal)
            if isempty(names)
                @test only(values(y)) == input
            else
                A, B, C, D = LegacyMMCReference.butterworthMatrices(2, 120.0, 1)
                T = hcat(B, A*B) / hcat(signal.filter.B, signal.filter.A*signal.filter.B)
                old_x = T * collect(values(x))
                @test T * F ≈ A * old_x + vec(B) * input
                @test only(values(y)) ≈ only(C * old_x) + D * input
            end
        end
        pll = conv.sync
        names = PI.filter_statenames(:v_q_pll_f, pll.filter)
        xf = ntuple(i -> 0.001i, length(names))
        x = (; NamedTuple{names}(xf)..., ξ_pll = 0.04, Δθ_pll = 0.2)
        F = zeros(PI.n_states(pll))
        y = PI.state_space!(F, x, (; vG_d_f = 0.8, vG_q_f = 0.2), PI.SetpointPU(), pll, conv)
        A, B, C, D = LegacyMMCReference.butterworthMatrices(2, 120.0, 1)
        T = hcat(B, A*B) / hcat(pll.filter.B, pll.filter.A*pll.filter.B)
        old_x = T * collect(xf)
        voltage = only(C * old_x) + D * 0.2
        @test T * F[1:2] ≈ A * old_x + vec(B) * 0.2
        @test F[3:4] ≈ [-7.0 * voltage, conv.elec.ωbase * (-0.3 * voltage + 0.04)]
        @test y.ω_c ≈ 1.0 - 0.3 * voltage + 0.04
        occ = kind === :mmc ? conv.delta_control.occ : conv.innerCurrent
        names = (PI.filter_statenames(:vG_d_occ_f, occ.filter)...,
            PI.filter_statenames(:vG_q_occ_f, occ.filter)...)
        seed = PI.initialvalues(occ; inputs = (; vG_d = 0.8, vG_q = 0.2), conv)
        x = (; seed..., ξ_id = 0.04, ξ_iq = -0.03)
        meas = (; vG_d_f = 0.8, vG_q_f = 0.2, i_d_f = 0.3, i_q_f = -0.1)
        F = zeros(PI.n_states(occ))
        y = PI.state_space!(F, x, (; meas, sync = (; ω_c = 1.03),
            vloop = (; iΔ_d_ref = 0.4, iΔ_q_ref = -0.2)), occ, conv)
        @test all(abs.(F[1:length(names)]) .< 1e-8)
        @test F[end-1:end] ≈ [7.0 * 0.1, -7.0 * 0.1]
        inductance = PI.elec_inductance(conv.elec)
        frequency = kind === :mmc ? 1.0 : 1.03
        @test y.vMΔ_d_ref_c ≈ 0.04 + 0.3 * 0.1 + inductance * frequency * -0.1 + 0.8
        @test y.vMΔ_q_ref_c ≈ -0.03 - 0.3 * 0.1 - inductance * frequency * 0.3 + 0.2
    end
end

@testset "VAC magnitude filter and equilibrium" begin
    for kind in (:mmc, :tlc), order in (0, 1, 2)
        adapter = kind === :mmc ? NB._legacy_mmc : NB._legacy_tlc
        e = adapter((; Vₘ = 220/sqrt(3), Vᵈᶜ = 640.0, turnsRatio = 0.8,
            vac = PI_control(Kₚ = 0.3, Kᵢ = 7.0, n_f = order, ω_f = 120.0)))
        conv = e.element_model
        block = kind === :mmc ? conv.delta_control.outer_reactive : conv.outerReactive
        sp = PI.SetpointPU(q_ac = 0.1, v_ac = 1.05)
        reference = 1.05 * (kind === :mmc ? 0.8 : 1.0)
        seed = PI.initialvalues(block; setpoint_pu = sp, conv)
        names = PI.filter_statenames(:vac_mag_f, block.filter)
        @test PI.n_states(block) == order + 1
        if order > 0
            xf = collect(values(seed))
            @test block.filter.A * xf + block.filter.B * [reference] ≈ zeros(order) atol=1e-8
            @test only(block.filter.C * xf + block.filter.D * [reference]) ≈ reference
        end
        voltage = hypot(0.8, 0.2)
        x = (; PI.filter_initialvalues(block.filter, names, voltage)..., ξ_v_ac = 0.07)
        F = zeros(PI.n_states(block))
        y = PI.state_space!(F, x, (; meas = (; vG_d_f = 0.8, vG_q_f = 0.2)), sp, block, conv)
        @test F[end] ≈ 7.0 * (reference - voltage)
        @test y.q_ctrl_ref ≈ 0.3 * (reference - voltage) + 0.07
        @test all(abs.(F[1:end-1]) .< 1e-8)
        full = fill(123.0, PI.n_states(conv))
        PI.equilibriumequations!(full, nothing, nothing, sp,
            (; meas = (; Q_ac_f = 0.07)), conv, block)
        idx = findfirst(==(:ξ_v_ac), PI.statenames(conv))
        @test full[idx] ≈ 0.03
        @test all(full[i] == 123.0 for i in eachindex(full) if i != idx)
        if order > 0
            exporter = PI.PSCAD
            @test_throws r"not yet exportable" exporter.converter_reactive("VAC", (; name = :c1), nothing, block)
            @test_throws r"not yet exportable" exporter.converter_equilibrium((; name = :c1, model = conv))
        end
    end
end

@testset "Local DC filter, legacy signal ownership and equilibrium" begin
    pi = PIControl(Kp = 0.3, Ki = 7.0)
    default = OuterActiveVdcControl(; pi_ctrl = pi)
    @test default.filter isa PI.NoFilter
    @test OuterActiveVdcControl(pi).pi_ctrl == pi
    @test PI.statenames(default) == (:ξ_v_dc,)
    @test isempty(PI.initialvalues(default))
    for kind in (:mmc, :tlc), order in (0, 1, 2)
        adapter = kind === :mmc ? NB._legacy_mmc : NB._legacy_tlc
        e = adapter((; dc = PI_control(Kₚ = 0.3, Kᵢ = 7.0, n_f = order, ω_f = 120.0),
            energy = PI_control(Kₚ = 1.4, Kᵢ = 30.0),
            zcc = PI_control(Kₚ = 0.1, Kᵢ = 43.0)))
        conv = e.element_model
        block = kind === :mmc ? conv.delta_control.outer_active : conv.outerActive
        sp = PI.SetpointPU(v_dc = 1.05, p_dc = 0.2)
        names = PI.filter_statenames(:v_dc_ctrl_f, block.filter)
        seed = PI.initialvalues(block; setpoint_pu = sp)
        @test PI.n_states(block) == order + 1
        @test conv.meas.v_dc.filter isa PI.NoFilter
        if order > 0
            xf = collect(values(seed))
            @test block.filter.A * xf + block.filter.B * [sp.v_dc] ≈ zeros(order) atol=1e-8
            @test only(block.filter.C * xf + block.filter.D * [sp.v_dc]) ≈ sp.v_dc
        end
        raw = 1.1
        raw_inputs = (; vG_d = 0.8, vG_q = 0.2, v_dc = raw,
            i_d = 0.3, i_q = -0.1, i_dc = 0.2, θ = 0.0)
        meas = PI.state_space!(zeros(PI.n_states(conv.meas)), (;), raw_inputs, conv.meas, conv)
        @test meas.v_dc_f == raw
        x = (; NamedTuple{names}(ntuple(i -> 0.001i, order))..., ξ_v_dc = 0.07)
        F = zeros(PI.n_states(block))
        y = PI.state_space!(F, x, (; meas), sp, block, conv)
        voltage = raw
        if order > 0
            A, B, C, D = LegacyMMCReference.butterworthMatrices(order, 120.0, 1)
            controllability(A, B) = hcat((A^i * B for i in 0:order-1)...)
            T = controllability(A, B) / controllability(block.filter.A, block.filter.B)
            old_x = T * collect(x[n] for n in names)
            voltage = only(C * old_x) + D * raw
            @test T * F[1:order] ≈ A * old_x + vec(B) * raw
        end
        @test F[end] ≈ 7.0 * (sp.v_dc - voltage)
        @test y.iΔ_d_ref ≈ -1 * (0.3 * (sp.v_dc - voltage) + 0.07)
        full = fill(123.0, PI.n_states(conv))
        PI.equilibriumequations!(full, (; iΣ_z = 0.04), (; v_dc = raw), sp,
            (; elec = (; i_dc = 0.12)), conv, block)
        idx = findfirst(==(:ξ_v_dc), PI.statenames(conv))
        @test full[idx] ≈ sp.p_dc/raw - 0.12
        @test all(full[i] == 123.0 for i in eachindex(full) if i != idx)
        if kind === :mmc
            modulation_inputs = (; meas,
                out_delta = (; vMΔ_d_ref_c = 0.1, vMΔ_q_ref_c = 0.2),
                out_sigma = (; vMΣ_d_ref_c = 0.3, vMΣ_q_ref_c = 0.4, vMΣ_z_ref = 0.5))
            modulation = PI.state_space!(Float64[], (;), modulation_inputs, conv.modulation, conv)
            @test modulation.mΔd ≈ -conv.elec.baseConv1 * 2/raw * 0.1
            physical = (; vCΔ_d = 0.0, vCΔ_q = 0.0, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0,
                vCΣ_d = 0.0, vCΣ_q = 0.0, vCΣ_z = 1.0, ξ_Wtot = 0.04,
                iΣ_z = 0.03, ξ_iΣ_z = 0.02)
            energy = PI.state_space!(zeros(1), physical, meas, conv.sigma_control.tec, conv)
            @test energy.iΣ_z_ref ≈ (0.04 + 0.8*0.3 + 0.2*(-0.1))/3/raw
            zcc = PI.state_space!(zeros(1), physical, (; meas, out_Wtot = energy),
                conv.sigma_control.zscc, conv)
            @test zcc.vMΣ_z_ref ≈ raw/2 - 0.1*(energy.iΣ_z_ref-0.03) - 0.02
        else
            modulation_inputs = (; meas, iloop = (; vMΔ_d_ref_c = 0.1, vMΔ_q_ref_c = 0.2))
            modulation = PI.state_space!(Float64[], (;), modulation_inputs, conv.mod, conv)
            @test modulation.m_d == 2/raw * 0.1
        end
        if order > 0
            @test_throws r"not yet exportable" PI.PSCAD.converter_active("DC", (; name = :c1), nothing, block)
            @test_throws r"not yet exportable" PI.PSCAD.converter_equilibrium((; name = :c1, model = conv))
        end
    end
    conv = NB._legacy_tlc((; pll = PI_control(Kₚ = 0.3, Kᵢ = 7.0),
        v_meas_filt = PI_control(n_f = 2, ω_f = 120.0))).element_model
    @test conv.sync.filter isa PI.NoFilter
    names = PI.statenames(conv.meas.vG_q)
    x = PI.filter_initialvalues(conv.meas.vG_q.filter, names, 0.1)
    measured = PI.state_space!(zeros(length(names)), x, (; vG_q = 0.2), conv.meas.vG_q)
    F = zeros(PI.n_states(conv.sync))
    y = PI.state_space!(F, (; ξ_pll = 0.0, Δθ_pll = 0.0),
        (; vG_d_f = 0.8, measured...), PI.SetpointPU(), conv.sync, conv)
    @test F[1] ≈ -7.0*0.1
    @test y.ω_c ≈ 1.0-0.3*0.1
    @test !isapprox(F[1], -7.0*0.2) # Approved filtered convention, rather than historical bypass.
end

@testset "Legacy TLC against independent validation data" begin
    for (build, file, phase_degrees) in ((build_case1_grid, "data_TLC_validation_1.txt", 3),
            (build_case2_grid, "data_TLC_validation_2.txt", 1))
        network = build()
        reference_element = network.elements[:DUT]
        m = reference_element.element_model
        pi_controller(pi; kwargs...) = PI_control(Kₚ = pi.Kp, Kᵢ = pi.Ki; kwargs...)
        controls = Dict{Symbol,PI.Controller}(
            :pll => pi_controller(m.sync.pi_ctrl; n_f = 2, ω_f = 2π*80),
            :v_meas_filt => PI_control(n_f = 2, ω_f = 0.5e4),
            :i_meas_filt => PI_control(n_f = 2, ω_f = 0.5e4),
            :q => pi_controller(m.outerReactive.pi_ctrl),
            :occ => pi_controller(m.innerCurrent.pi_ctrl))
        if m.outerActive isa OuterActiveVdcControl
            controls[:dc] = pi_controller(m.outerActive.pi_ctrl)
            controls[:vac_supp] = PI_control(Kₚ = 5.0, ω_f = 2.0)
        else
            controls[:p] = pi_controller(m.outerActive.pi_ctrl)
            controls[:f_supp] = PI_control(Kₚ = 5.0, ω_f = 2.0)
        end
        e = NB._legacy_tlc((; controls, Sbase = m.elec.Sbase,
            Lᵣ = m.elec.Lᵣ * m.elec.lACbase, Rᵣ = m.elec.Rᵣ * m.elec.zACbase,
            vACbase_LL_RMS = 220.0, vDCbase = 640.0,
            timeDelay = 200e-6, padeOrderNum = 3, padeOrderDen = 3,
            setpoint = reference_element.setpoint))
        PI.update!(e, e.setpoint)
        @test e.A ≈ reference_element.A
        @test e.B ≈ reference_element.B
        @test e.C ≈ reference_element.C
        @test e.D ≈ reference_element.D
        frequencies, data = read_validation_data(joinpath(@__DIR__, "data", file))
        for (ω, reference) in zip(frequencies, data)
            file == "data_TLC_validation_2.txt" && (reference[1, :] .*= -1)
            actual = element_y(e, ComplexF64(im*ω))
            for r in 1:3, c in 1:3
                # Retain the independent fixture's existing acceptance limits.
                @test abs(actual[r,c]) ≈ abs(reference[r,c]) atol=1e-4
                @test angle(actual[r,c]/reference[r,c]) ≈ 0.0 atol=phase_degrees*π/180
            end
        end
    end
end
