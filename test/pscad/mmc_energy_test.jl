module PSCADMMCEnergyTests
import ..PSCADFixtures
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures, ..PSCADTopology
using ..PSCADTLCTests: evaluate
using ..PSCADMMCTests: converter_element, with_modulation
using ..PSCADResultsTests: synthetic_result, add_three_phase!
const PI = PowerImpedance
const P = PI.PSCAD
const SETTINGS = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 250e-6, source_ramp = 0.0)

function diagnostic(definition, names)
    canvas = deepcopy(definition.canvas)
    origin = (maximum(c -> c.x, canvas.components) + 216, 108)
    P.lower!(canvas, P.BlockGraph(P.ControlBlock[P.Export(n, P.Signal(n)) for n in names]); origin)
    return P.ModuleDefinitionPlan(definition.name, definition.parameters, definition.ports, canvas)
end

function arm_signals(x, m, angle)
    caps = P.mmc_arm_capacitors(x, m.elec.vDC_base, angle)
    return Dict{String, Any}("v_Ctot_" * arm * "_" * phase => voltage
    for (arm, values) in (("u", caps.upper), ("l", caps.lower))
    for (phase, voltage) in zip(("a", "b", "c"), values))
end

@testset "compensated MMC LEC, CCC and physical compensated modulation" begin
    fixture = PSCADFixtures.mmc_compensated_network()
    for network in (fixture,)
        pf = NetworkBuilder.solve(network)
        list = P.netlist(network, pf)
        plan = P.build_plan(list; settings = SETTINGS)
        e = only(filter(e -> e.name == :DUT, list.elements))
        m, eq = e.model, P.converter_equilibrium(e)
        modules = Dict(d.name => d for d in plan.modules)
        transforms = (; abc = plan.name * ":ABC_DQ", dq = plan.name * ":DQ_ABC")
        @test P.check_connectivity(plan) === nothing
        @test Set(keys(modules)) == Set(["ABC_DQ", "DQ_ABC", "MEAS_DUT", "PLL_DUT",
            "VSM_DUT", "QCTRL_DUT", "CCVI_DUT", "OCC_DUT",
            "SIGMA_DUT", "MOD_DUT", "MMC_DUT"])
        for (name, canvas) in [("Main", plan.main);
                               [(d.name, d.canvas) for d in plan.modules]]
            @test PSCADTopology.check_degrees(PSCADTopology.electrical_graph(canvas, modules), name) ===
                  nothing
        end
        @test length(eq.states) == 89
        @test m.elec.Sbase == 1060.0 && m.elec.vDC_base == 640.0
        @test P.mmc_si(m.elec).vAC_base_LL_RMS ≈ 320.0
        @test m.elec.turnsRatio == 320/400
        @test m.sigma_control.wsigma.pi_control.Kp == 0.4*1.386
        @test m.sigma_control.wdelta.pi_control.Ki == 0.2*29.70
        @test m.sigma_control.ccc.pi_control.Ki == 42.9719
        @test Set(c.name for c in plan.probes.channels if startswith(c.name, "DUT_")) ==
              Set("DUT_" * n
        for n in ("P_ac_f", "Q_ac_f", "v_dc_f", "omega_c", "theta_c",
            ["v_Ctot_" * arm * "_" * phase for arm in ("u", "l")
             for phase in ("a", "b", "c")]..., "iS_z"))
        @test count(c -> c.defn == "master:integral", modules["SIGMA_DUT"].canvas.components) ==
              24
        @test count(c -> c.defn == "master:compare", modules["MEAS_DUT"].canvas.components) ==
              1
        @test count(c -> c.defn == "master:compare", modules["SIGMA_DUT"].canvas.components) ==
              0
        @test count(c -> c.defn == "master:div", modules["MOD_DUT"].canvas.components) == 6
        @test count(c -> c.defn == "master:tdelay", modules["MOD_DUT"].canvas.components) ==
              6
        residual = zeros(length(eq.states))
        PI._state_space!(residual, collect(values(eq.states)), collect(values(eq.inputs)),
            eq.terminal_pu, m, PI.Equil())
        @test maximum(abs, residual) <= 1e-6

        # Every rate, including the notch's two states and rotating PI states, is compared
        # to the native Julia equations at displaced states. With fundamental-only Δ
        # capacitors, instantaneous projections equal the seven harmonic coordinates. The
        # general cycle projection is evaluated separately.
        rates = ["wsdqfirstrate1", "wsdqfirstrate2", "wszfirstrate1",
            "wsdqsecondrate1", "wsdqsecondrate2", "wszsecondrate1",
            "wsdqpirate1", "wsdqpirate2", "wszpirate1",
            "wddqfirstrate1", "wddqfirstrate2", "wdZfirstrate1", "wdZfirstrate2",
            "wddqsecondrate1", "wddqsecondrate2", "wdZsecondrate1", "wdZsecondrate2",
            "wddqpirate1", "wddqpirate2", "wdZpirate1", "wdZpirate2",
            "cccdqrate1", "cccdqrate2", "ccczrate1"]
        ns = PI.statenames(m.sigma_control)
        for offset in (-0.019, 0.027), frequency in (0.96, 1.04)

            perturbation = NamedTuple{ns}(Tuple(getproperty(eq.states, n) + offset*sin(i)
            for (i, n) in enumerate(ns)))
            x = merge(eq.states,
                perturbation,
                (; iΣ_d = 0.021, iΣ_q = -0.016, iΣ_z = 0.23,
                    vCΣ_d = 0.0, vCΣ_q = 0.0, vCΣ_z = 1.0,
                    vCΔ_d = 0.04, vCΔ_q = 0.05, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0))
            meas = merge(eq.outputs.meas, (; P_ac_f = 0.63, v_dc_f = 1.07))
            displaced = merge(eq, (; states = x, outputs = merge(eq.outputs, (; meas))))
            inputs = (; meas, power = (; P_ac_f = meas.P_ac_f), sync = (; ω_c = frequency))
            F = zeros(PI.n_states(m.sigma_control))
            owned = PI.state_space!(F, x, inputs, eq.terminal_pu, m.sigma_control, m)
            def = P.mmc_sigma("LEC_EQ", e, displaced, transforms)
            signals = merge(arm_signals(x, m, 0.0),
                Dict(
                    "iS_abc" =>
                        (m.elec.Sbase / m.elec.vDC_base) .* collect(
                            x.iΣ_z .+ x.iΣ_d .* cos.((0.0, -2π/3, 2π/3)) .+
                            x.iΣ_q .* sin.((0.0, -2π/3, 2π/3))),
                    "P_ac_f" => meas.P_ac_f, "v_dc_f" => meas.v_dc_f, "v_dc_divisor" =>
                        meas.v_dc_f))
            emitted = evaluate(diagnostic(def, rates), signals, 0.1)
            @test emitted["vMS_d_ref"] ≈ owned.vMΣ_d_ref_c atol=1e-6
            @test emitted["vMS_q_ref"] ≈ owned.vMΣ_q_ref_c atol=1e-6
            @test emitted["vMS_z_ref"] ≈ owned.vMΣ_z_ref atol=1e-6
            for (n, rate) in zip(rates, F)
                @test emitted[n] ≈ rate atol=1e-6
            end
            @test emitted["iS_z"] ≈ x.iΣ_z atol=1e-6
        end

        # Physical energy projection must retain Julia's factors, signs and
        # triplen quadratures. Its extra EMT harmonics remain in the live input.
        x = merge(eq.states, NamedTuple{ns}(ntuple(_ -> 0.0, length(ns))),
            (; vCΣ_d = 0.08, vCΣ_q = -0.03, vCΣ_z = 1.0,
                vCΔ_d = 0.04, vCΔ_q = 0.05, vCΔ_Zd = -0.015, vCΔ_Zq = 0.01))
        input = (; meas = (; v_dc_f = 1.0), power = (; P_ac_f = 0.0), sync = (; ω_c = 1.0))
        fs, fd = zeros(9), zeros(12)
        PI.state_space!(fs, x, input, m.sigma_control.wsigma, m)
        PI.state_space!(fd, x, input, m.sigma_control.wdelta, m)
        expected_energy = [-fs[1:3] ./ (sqrt(2)*2m.elec.ωbase);
                           -fd[1:4] ./ (sqrt(2)*m.elec.ωbase)]
        energy_names = ["lec_sum_" * axis * "_measured" for axis in ("d", "q", "z")]
        append!(energy_names, ["lec_delta_" * axis * "_measured"
                               for axis in ("d", "q", "Zd", "Zq")])
        # Evaluate the actual measurement prefix for the cycle projection.
        # The complete notch/CCC graph is checked separately at every state.
        canvas = deepcopy(modules["SIGMA_DUT"].canvas)
        boundary = findfirst(c -> c.defn == "master:integral", canvas.components)
        resize!(canvas.components, boundary-1)
        labels = Set((c.x, c.y) for c in canvas.components if c.defn == "master:datalabel")
        filter!(w -> any(p -> p in labels, w.vertices), canvas.wires)
        measurements = P.ModuleDefinitionPlan("LEC_MEAS", modules["SIGMA_DUT"].parameters,
            modules["SIGMA_DUT"].ports, canvas)
        live_names = replace.(energy_names, "_measured" => "")
        def = diagnostic(measurements, [energy_names; live_names])
        # Capacitor-derived signals and arm-current feedback are live from t=0. Direct
        # physical projections are independent of the emitted primitive graph.
        phases = (0.0, -2π/3, 2π/3)
        for time in (0.0, 0.05, 0.2 - SETTINGS.time_step, 0.2)
            signals = Dict{String, Any}("iS_abc" => fill(25.0, 3),
                "P_ac_f" => 0.0, "v_dc_f" => 1.0)
            upper, lower = [0.93, 1.07, 1.12], [1.04, 0.96, 1.09]
            for (arm, values) in (("u", upper), ("l", lower)),
                (phase, value) in zip(("a", "b", "c"), values)

                signals["v_Ctot_" * arm * "_" * phase] = value * m.elec.vDC_base
            end
            angle = m.elec.ωbase * time
            sigma, delta = upper .^ 2 + lower .^ 2, lower .^ 2 - upper .^ 2
            project(values, theta) = [2/3 * sum(values .* cos.(theta .+ phases)),
                2/3 * sum(values .* sin.(theta .+ phases))]
            energy = [project(sigma, -2angle); sum(sigma)/3;
                      project(delta, angle); 2sum(delta)/3 .* [cos(3angle), sin(3angle)]]
            measured = evaluate(def, signals, time)
            @test [measured[n] for n in live_names] ≈ energy atol=1e-6
            @test [measured[n] for n in energy_names] ≈ energy atol=1e-6
        end
        # Rising capacitors must reach the energy/CCC feedback during the hold.
        for time in (0.0, 0.05, 0.2 - SETTINGS.time_step)
            signals = merge(arm_signals(eq.states, m, m.elec.ωbase*time),
                Dict("iS_abc" => fill(25.0, 3), "P_ac_f" => eq.outputs.meas.P_ac_f,
                    "v_dc_f" => eq.outputs.meas.v_dc_f, "v_dc_divisor" =>
                        eq.outputs.meas.v_dc_f))
            before = evaluate(modules["SIGMA_DUT"], signals, time)
            energy_before = evaluate(def, signals, time)["lec_sum_z"]
            for name in keys(signals)
                startswith(name, "v_Ctot_") && (signals[name] *= 1.02)
            end
            after = evaluate(modules["SIGMA_DUT"], signals, time)
            energy_after = evaluate(def, signals, time)["lec_sum_z"]
            expected_change = m.sigma_control.ccc.pi_control.Kp *
                              m.sigma_control.wsigma.pi_control.Kp *
                              (energy_after - energy_before) / eq.outputs.meas.v_dc_f
            @test after["vMS_z_ref"] - before["vMS_z_ref"] ≈ expected_change atol=1e-6
            @test after["iS_z"] == before["iS_z"] &&
                  after["iS_z"] ≈ 25.0 * m.elec.vDC_base / m.elec.Sbase
        end
        averaged = zeros(7)
        for i in 0:63
            time = 0.3 + i/(64*50)
            signals = merge(arm_signals(x, m, m.elec.ωbase*time),
                Dict("iS_abc" => zeros(3),
                    "P_ac_f" => 0.0, "v_dc_f" => 1.0))
            measured = evaluate(def, signals, time)
            averaged .+= [measured[n] for n in energy_names] ./ 64
        end
        @test averaged ≈ expected_energy atol=1e-6

        # Current feedback uses the live grid -2ω frame from t=0. The native rates use the
        # protected divisor; only half-DC feedforward is live.
        live_states = merge(eq.states,
            (; iΣ_d = 0.11, iΣ_q = -0.07, iΣ_z = 0.24,
                vCΣ_d = 0.0, vCΣ_q = 0.0, vCΣ_z = 1.02,
                vCΔ_d = 0.0, vCΔ_q = 0.0, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0))
        F = zeros(PI.n_states(m.sigma_control))
        owned = PI.state_space!(F, live_states,
            (; meas = (; v_dc_f = 1.0), power = (; P_ac_f = 0.7), sync = eq.outputs.sync),
            eq.terminal_pu, m.sigma_control, m)
        for time in (0.0, 0.05, 0.2 - SETTINGS.time_step, 0.2)
            phases = (-2m.elec.ωbase*time) .+ (0.0, -2π/3, 2π/3)
            currents = (0.11 .* cos.(phases) .- 0.07 .* sin.(phases) .+ 0.24) .*
                       (m.elec.Sbase/m.elec.vDC_base)
            signals = merge(arm_signals(live_states, m, m.elec.ωbase*time),
                Dict("iS_abc" => collect(currents), "P_ac_f" => 0.7, "v_dc_f" => 0.3, "v_dc_divisor" =>
                    1.0))
            measured = evaluate(diagnostic(modules["SIGMA_DUT"], [["iS_d", "iS_q"]; rates]), signals, time)
            @test measured["iS_d"] ≈ 0.11 atol=1e-6
            @test measured["iS_q"] ≈ -0.07 atol=1e-6
            @test measured["iS_z"] ≈ 0.24 atol=1e-6
            @test measured["vMS_d_ref"] ≈ owned.vMΣ_d_ref_c atol=1e-6
            @test measured["vMS_q_ref"] ≈ owned.vMΣ_q_ref_c atol=1e-6
            @test measured["vMS_z_ref"] ≈ owned.vMΣ_z_ref + (0.3 - 1.0) / 2 atol=1e-6
            for (n, rate) in zip(rates, F)
                @test measured[n] ≈ rate atol=1e-6
            end
        end

        # The EMT law requires exact pointwise arm voltage identity. Unequal capacitors
        # prevent accidentally sharing a DC denominator.
        zero_model = with_modulation(m, PI.CompensatedModulation())
        zero_element = converter_element(e, zero_model)
        def = P.mmc_modulation("COMP_EQ", zero_element, eq, transforms, SETTINGS)
        for time in (0.0, 0.317), theta in (-0.23, 0.41)

            signals = Dict{String, Any}("vM_d_ref" => 0.93, "vM_q_ref" => -0.12,
                "vMS_d_ref" => 0.021, "vMS_q_ref" => -0.017, "vMS_z_ref" => 0.49, "theta_c" =>
                    theta)
            phases = (0.0, -2π/3, 2π/3)
            for (i, phase) in enumerate(("a", "b", "c")), (j, arm) in enumerate(("u", "l"))

                signals["v_Ctot_" * arm * "_" * phase] = 510.0 + 29i + 17j
            end
            emitted = evaluate(def, signals, time)
            for (i, phase) in enumerate(("a", "b", "c")),
                (arm, sign) in (("u", -1), ("l", 1))

                vs = m.elec.vDC_base *
                     (0.49 + 0.021*cos(-2*(m.elec.ωbase*time + phases[i])) -
                      0.017*sin(-2*(m.elec.ωbase*time + phases[i])))
                vd = m.elec.vAC_base *
                     (0.93*cos(theta + phases[i]) - 0.12*sin(theta + phases[i]))
                stem = arm * "_" * phase
                @test emitted["m_" * stem] * signals["v_Ctot_" * stem] ≈ vs + sign*vd atol=1e-6
            end
        end
        # Balanced-capacitor limit agrees with Julia's seven-coordinate law.
        balanced = merge(eq.states,
            (; vCΣ_z = 1.0, vCΣ_d = 0.0, vCΣ_q = 0.0,
                vCΔ_d = 0.0, vCΔ_q = 0.0, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0, Δθ_VSM = 0.19))
        refs = (; meas = (; v_dc_f = 1.0),
            out_delta = (; vMΔ_d_ref_c = 0.93, vMΔ_q_ref_c = -0.12),
            out_sigma = (; vMΣ_d_ref_c = 0.021, vMΣ_q_ref_c = -0.017, vMΣ_z_ref = 0.49))
        owned = PI.state_space!(
            Float64[], balanced, refs, zero_model.modulation, zero_model)
        signals = merge(arm_signals(balanced, m, 0.0),
            Dict("vM_d_ref" => 0.93,
                "vM_q_ref" => -0.12, "vMS_d_ref" => 0.021, "vMS_q_ref" => -0.017,
                "vMS_z_ref" => 0.49, "theta_c" => 0.19))
        emitted = evaluate(def, signals)
        @test owned.mΔZd == owned.mΔZq == 0.0
        for (phase, angle) in zip(("a", "b", "c"), (0.0, -2π/3, 2π/3)),
            (arm, sign) in (("u", 1), ("l", -1))

            sigma = owned.mΣz + owned.mΣd*cos(-2angle) + owned.mΣq*sin(-2angle)
            delta = owned.mΔd*cos(angle) + owned.mΔq*sin(angle)
            @test emitted["m_" * arm * "_" * phase] ≈ (sigma + sign*delta)/2 atol=1e-6
        end
        # A 2ω capacitor ripple generates the triplen modulation implicitly.
        # Fourier coefficients of 1/(1+ε*cos(2θ)) give an independent reference
        # for both mΔZ quadratures of the physical upper-minus-lower waveform.
        ripple = 0.1
        x = merge(balanced, (; vCΣ_d = ripple, Δθ_VSM = 0.0))
        third = zeros(2)
        for i in 0:63
            time = 0.3 + i/(64*50)
            angle = m.elec.ωbase*time
            signals = merge(arm_signals(x, m, angle),
                Dict("vM_d_ref" => 0.93,
                    "vM_q_ref" => -0.12, "vMS_d_ref" => 0.0, "vMS_q_ref" => 0.0,
                    "vMS_z_ref" => 0.49, "theta_c" => angle))
            out = evaluate(def, signals, time)
            delta = out["m_u_a"] - out["m_l_a"]
            third .+= 2delta .* [cos(3angle), sin(3angle)] ./ 64
        end
        denominator = sqrt(1-ripple^2)
        ratio = -ripple/(1+denominator)
        expected_third = -2m.elec.baseConv1/denominator .*
                         [0.93*(ratio+ratio^2), -0.12*(ratio-ratio^2)]
        @test third ≈ expected_third atol=1e-6
        @test all(!iszero, third)

        # The exact tdelay primitive and buffer sizing apply to each physical arm. Each
        # history is initialized from its own solved arm ratio.
        params = Dict(p.name => p.default for p in modules["MOD_DUT"].parameters)
        caps = P.mmc_arm_capacitors(eq.states, m.elec.vDC_base)
        initial_signals = merge(arm_signals(eq.states, m, 0.0),
            Dict(
                "vM_d_ref" => eq.outputs.delta.vMΔ_d_ref_c, "vM_q_ref" =>
                    eq.outputs.delta.vMΔ_q_ref_c,
                "vMS_d_ref" => eq.outputs.sigma.vMΣ_d_ref_c, "vMS_q_ref" =>
                    eq.outputs.sigma.vMΣ_q_ref_c,
                "vMS_z_ref" => eq.outputs.sigma.vMΣ_z_ref, "theta_c" =>
                    PI.syncangle(m.sync, eq.states)))
        initial_outputs = evaluate(def, initial_signals)
        for c in modules["MOD_DUT"].canvas.components
            c.defn == "master:tdelay" || continue
            fields = Dict(c.params)
            residual = 200e-6 - SETTINGS.time_step
            @test params[fields["T"]] == residual
            @test fields["N"] == string(ceil(Int, residual/SETTINGS.time_step) + 1)
            @test fields["Intp"] == "0" && fields["Init"] == "1"
            stem = replace(fields["X0"], "arm" => "", "Y0" => "")
            @test params[fields["X0"]] ≈ initial_outputs["m_" * stem] atol=1e-6
        end

        # Converter comparison rows include six capacitor means and the VSM speed row.
        # Insertion indices are excluded from these channels.
        probes = P.ProbeManifest(
            filter(c -> c.element == "DUT" || c.kind == :voltage,
                plan.probes.channels),
            plan.probes.reference_bus)
        model = PSCADModel("synthetic.pscx", "synthetic", list, probes,
            SETTINGS, list.operating_point, (;))
        times = collect(0.0:250e-6:0.3)
        channels = PI.OrderedDict{String, Vector{Float64}}()
        flow = list.operating_point.branch_flows[:DUT]
        ac = only(filter(t -> t.port == :ac && !t.grounded, e.terminals))
        bus = only(filter(b -> b.key == ac.bus, list.buses))
        point = list.operating_point.bus_states[ac.bus]
        voltage = sqrt(2)*bus.base_kV*point.vm_pu*cis(point.va_rad)
        dc = only(filter(t -> t.port == :dc && !t.grounded, e.terminals))
        dbus = only(filter(b -> b.key == dc.bus, list.buses))
        vdc = 2dbus.base_kV*list.operating_point.bus_states[dc.bus].vm_pu
        for c in probes.channels
            if c.kind == :voltage && c.dim == 3
                add_three_phase!(channels, c.name, times, voltage)
            elseif c.kind == :current && c.port in (:side2, :ac)
                add_three_phase!(channels, c.name, times,
                        2complex(flow.pgrid, -flow.qgrid)/(3conj(voltage)))
            else
                value = c.kind == :converter_p ? flow.pt/m.elec.Sbase :
                        c.kind == :converter_q ? flow.qt/m.elec.Sbase :
                        c.kind == :converter_arm_voltage ? vdc :
                        c.kind == :converter_sum_current ?
                        flow.pf*m.elec.vDC_base/(3m.elec.Sbase*vdc) :
                        c.kind == :machine_speed ? 1.0 :
                        c.kind == :current ? flow.pf/vdc :
                        c.kind == :voltage ? (c.pole == "P" ? vdc/2 : -vdc/2) : 1.0
                channels[c.name] = fill(value, length(times))
            end
        end
        table = compare_operating_point(synthetic_result(times, channels; probes), model)
        @test all(table.within_tolerance)
        @test count(==(:converter_arm_voltage), table.quantity) == 6
        @test count(==(:converter_dc_current_identity), table.quantity) == 1
        @test count(==(:machine_speed), table.quantity) == 1
    end
end
end
