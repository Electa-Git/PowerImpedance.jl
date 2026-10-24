module PSCADMMCGFMTests
import ..PSCADFixtures
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures, ..PSCADTopology
using ..PSCADTLCTests: evaluate
using ..PSCADMMCModeTests: diagnostic
using ..PSCADMMCTests: converter_element
using ..PSCADResultsTests: synthetic_result, add_three_phase!
const PI = PowerImpedance
const P = PI.PSCAD
const SETTINGS = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 250e-6, source_ramp = 0.0)

@testset "GFM MMC plans and equations" begin
    fixture = PSCADFixtures.mmc_gfm_network()
    for network in (fixture,)
        pf = NetworkBuilder.solve(network)
        list = P.netlist(network, pf)
        plan = P.build_plan(list; settings = SETTINGS)
        e = only(filter(e -> e.name == :DUT, list.elements))
        m, eq = e.model, P.converter_equilibrium(e)
        modules = Dict(d.name => d for d in plan.modules)
        @test P.check_connectivity(plan) === nothing
        @test Set(keys(modules)) == Set(["ABC_DQ", "DQ_ABC", "MEAS_DUT", "PLL_DUT",
            "VSM_DUT", "QCTRL_DUT", "CCVI_DUT", "OCC_DUT", "SIGMA_DUT", "MOD_DUT", "MMC_DUT"])
        for (name, canvas) in [("Main", plan.main); [(d.name, d.canvas) for d in plan.modules]]
            @test PSCADTopology.check_degrees(PSCADTopology.electrical_graph(canvas, modules), name) === nothing
        end
        @test length(unique(lowercase(c.name) for c in plan.probes.channels)) == length(plan.probes.channels)
        @test Set(c.name for c in plan.probes.channels if startswith(c.name, "DUT_")) ==
              Set("DUT_" * n for n in ("P_ac_f", "Q_ac_f", "v_dc_f", "omega_c", "theta_c",
                  ["v_Ctot_" * arm * "_" * phase for arm in ("u", "l") for phase in ("a", "b", "c")]..., "iS_z"))
        @test m.elec.Sbase == 1060.0
        @test P.mmc_si(m.elec).vAC_base_LL_RMS ≈ 320.0
        @test m.elec.turnsRatio == 320 / 400
        @test m.elec.vDC_base == 640.0
        @test m.sync.H == 5.0 && m.sync.K_d == 100.0 && m.sync.K_ω == 10.0
        @test m.modulation.delay1.timeDelay == 200e-6
        residual = zeros(length(eq.states))
        PI._state_space!(residual, collect(values(eq.states)), collect(values(eq.inputs)),
            eq.terminal_pu, m, PI.Equil())
        @test maximum(abs, residual) <= 1e-6
        @test eq.outputs.sync.ω_c == eq.states.ω_VSM
        @test Dict(p.name => p.default for p in modules["VSM_DUT"].parameters)["theta0"] == eq.states.Δθ_VSM

        # The parent has separate PLL/VSM frequencies and angles. Reactive voltage
        # correction feeds CCVI, whose two current references are inputs to OCC.
        parent = modules["MMC_DUT"]
        @test any(c -> c.defn == plan.name * ":VSM_DUT", parent.canvas.components)
        @test count(c -> c.defn == "master:compare", modules["MEAS_DUT"].canvas.components) == 1
        @test count(c -> c.defn == "master:compare", modules["SIGMA_DUT"].canvas.components) == 0
        measured = evaluate(diagnostic(modules["MEAS_DUT"], ["P_ac", "Q_ac", "P_ac_f_ddy"]), Dict{String, Any}("v_abc" => zeros(3),
            "i_abc" => zeros(3), "v_dc" => 0.0, "i_dc_si" => 0.0,
            "theta_c" => 0.0, "theta_rel" => 0.0), 0.1)
        @test measured["P_ac"] == measured["Q_ac"] == measured["v_dc_f"] == 0.0
        # The dynamic power filter starts solved, but live zero input changes
        # its acceleration immediately rather than preserving its equilibrium.
        @test measured["P_ac_f"] ≈ eq.outputs.meas.P_ac_f atol=1e-6
        w2 = Dict(p.name => p.default for p in modules["MEAS_DUT"].parameters)["P_ac_f_s1W2"]
        @test measured["P_ac_f_ddy"] ≈ -w2 * eq.outputs.meas.P_ac_f atol=1e-6
        measured["theta_vsm_rel"] = eq.states.Δθ_VSM
        measured["theta_pll_rel"] = eq.states.Δθ_pll
        pll = evaluate(modules["PLL_DUT"], measured)
        sync = evaluate(modules["VSM_DUT"], merge(measured, Dict("omega_pll" => pll["omega_c"])))
        reactive = evaluate(modules["QCTRL_DUT"], measured)
        vi = evaluate(modules["CCVI_DUT"], merge(measured, sync, Dict("q_voltage_ref" => reactive["i_q_ref"])))
        occ = evaluate(modules["OCC_DUT"], merge(measured, sync, vi))
        @test measured["v_dc_divisor"] ≈ eq.outputs.meas.v_dc_f atol=1e-6
        @test sync["omega_c"] ≈ 1.0 atol=1e-6
        @test all(isfinite, values(occ))

        # Initial coordinates are rebuilt from displaced states; emitted rates and outputs
        # are compared directly with the native Julia equations.
        for (omega, pll_angle, vsm_angle, power) in ((0.97, 0.31, -0.17, 0.47), (1.04, -0.23, 0.19, 0.81))
            x = merge(eq.states, (; ω_VSM = omega, Δθ_pll = pll_angle, Δθ_VSM = vsm_angle, ξ_pll = 0.014))
            meas = merge(eq.outputs.meas, (; vG_d_f = 0.91, vG_q_f = -0.13, P_ac_f = power))
            displaced = merge(eq, (; states = x, outputs = merge(eq.outputs, (; meas))))
            swing = omega < 1 ? m.sync : PI.VSEWithDamping(H = 3.0, K_d = 47.0,
                K_ω = 12.0, ω_ref = 1.015, pll = m.sync.pll)
            F = zeros(PI.n_states(swing))
            owned = PI.state_space!(F, x, meas, eq.terminal_pu, swing, m)
            pll_def = P.converter_pll("PLL_EQ", e, displaced, m.sync.pll)
            pll_signals = Dict{String, Any}("vG_d_f" => meas.vG_d_f, "vG_q_f" => meas.vG_q_f,
                "theta_vsm_rel" => vsm_angle, "theta_pll_rel" => pll_angle)
            pll_out = evaluate(diagnostic(pll_def, ["pllrate", "w_rad", "vG_q_pll", "v_pll"]), pll_signals)
            rotated = PI.frame_transform(meas.vG_d_f, meas.vG_q_f, pll_angle - vsm_angle)
            @test pll_out["vG_q_pll"] ≈ rotated.q atol=1e-6
            @test pll_out["pllrate"] ≈ F[PI.n_states(m.sync.pll) - 1] atol=1e-6
            @test pll_out["w_rad"] - m.elec.ωbase ≈ F[PI.n_states(m.sync.pll)] atol=1e-6
            filter = m.sync.pll.filter
            filter_names = PI.filter_statenames(:v_q_pll_f, filter)
            filter_states = [getproperty(x, n) for n in filter_names]
            filter_rate = only(filter.C * (filter.A * filter_states + filter.B * [rotated.q]))
            pars = Dict(p.name => p.default for p in pll_def.parameters)
            @test (rotated.q - pll_out["v_pll"]) / pars["v_pll_s1T"] ≈ filter_rate atol=1e-6
            vsm_def = P.converter_vsm("VSM_EQ", e, displaced, swing)
            emitted = evaluate(diagnostic(vsm_def, ["omega_rate", "angle_rate"]),
                Dict("P_ac_f" => power, "omega_pll" => pll_out["omega_c"]))
            @test emitted["omega_c"] == owned.ω_c
            @test emitted["omega_rate"] ≈ F[end - 1] atol=1e-6
            @test emitted["angle_rate"] - m.elec.ωbase ≈ F[end] atol=1e-6
            @test emitted["theta_rel"] ≈ x.Δθ_VSM atol=1e-6
        end

        for filter in (PI.NoFilter(), PI.Butterworth(order = 1, ωc = 200.0), PI.Butterworth(order = 2, ωc = 200.0))
            vi_block = PI.CCVI(R_v = 0.037, L_v = 0.21, V_d_ref = 1.03, V_q_ref = -0.08, filter = filter)
            dnames = PI.filter_statenames(:vG_d_vi_f, vi_block.filter)
            qnames = PI.filter_statenames(:vG_q_vi_f, vi_block.filter)
            x = merge(eq.states, PI.filter_initialvalues(vi_block.filter, dnames, 0.93),
                PI.filter_initialvalues(vi_block.filter, qnames, 0.11))
            meas = merge(eq.outputs.meas, (; vG_d_f = 0.87, vG_q_f = -0.16))
            displaced = merge(eq, (; states = x, outputs = merge(eq.outputs, (; meas))))
            def = P.converter_ccvi("CCVI_EQ", e, displaced, vi_block)
            for omega in (0.96, 1.06), correction in (-0.07, 0.12)
                inputs = (; meas, sync = (; ω_c = omega), out_reactive = (; q_ctrl_ref = correction))
                F = zeros(PI.n_states(vi_block))
                owned = PI.state_space!(F, x, inputs, vi_block, m)
                names = vi_block.filter isa PI.Butterworth && vi_block.filter.order == 2 ?
                        ["vi_vd", "vi_vq", "vi_vd_dy", "vi_vq_dy", "vi_vd_ddy", "vi_vq_ddy"] : ["vi_vd", "vi_vq"]
                emitted = evaluate(diagnostic(def, names), Dict("vG_d_f" => meas.vG_d_f,
                    "vG_q_f" => meas.vG_q_f, "omega_c" => omega, "q_voltage_ref" => correction))
                @test emitted["i_d_ref"] ≈ owned.iΔ_d_ref atol=1e-6
                @test emitted["i_q_ref"] ≈ owned.iΔ_q_ref atol=1e-6
                if vi_block.filter isa PI.Butterworth
                    f = vi_block.filter
                    for (axis, ns, offset) in (("d", dnames, 0), ("q", qnames, length(dnames)))
                        rate = only(f.C * F[(offset + 1):(offset + length(ns))])
                        if f.order == 1
                            @test (getproperty(meas, Symbol("vG_" * axis * "_f")) - emitted["vi_v" * axis]) * f.ωc ≈ rate atol=1e-6
                        else
                            @test emitted["vi_v" * axis * "_dy"] ≈ rate atol=1e-6
                            # A*F is the second output derivative at this point
                            # with a constant supplied voltage input.
                            @test emitted["vi_v" * axis * "_ddy"] ≈ only(f.C * f.A * F[(offset + 1):(offset + length(ns))]) atol=1e-6
                        end
                    end
                end
            end
        end

        # The complete GFM Δ composition uses the existing reactive/OCC blocks.
        meas = merge(eq.outputs.meas, (; Q_ac_f = -0.18, i_d_f = 0.51, i_q_f = -0.12))
        inputs = (; meas, sync = (; ω_c = 1.02))
        F = zeros(PI.n_states(m.delta_control))
        owned = PI.state_space!(F, eq.states, inputs, eq.terminal_pu, m.delta_control, m)
        signals = Dict{String, Any}(string(k) => v for (k, v) in pairs(meas))
        signals["omega_c"] = 1.02
        qout = evaluate(diagnostic(modules["QCTRL_DUT"], ["qrate"]), signals)
        @test qout["qrate"] ≈ F[1] atol=1e-6
        signals["q_voltage_ref"] = qout["i_q_ref"]
        merge!(signals, evaluate(modules["CCVI_DUT"], signals))
        out = evaluate(diagnostic(modules["OCC_DUT"], ["drate", "qrate"]), signals)
        @test out["vM_d_ref"] ≈ owned.vMΔ_d_ref_c atol=1e-6
        @test out["vM_q_ref"] ≈ owned.vMΔ_q_ref_c atol=1e-6
        @test out["drate"] ≈ F[end - 1] atol=1e-6
        @test out["qrate"] ≈ F[end] atol=1e-6

        # Circulating currents are live from t=0 in the synchronization frame, even when
        # the PLL and VSM angles differ.
        circulating = PI.frame_transform(0.11, -0.07, -2eq.states.Δθ_VSM)
        phases = (0.0, -2π/3, 2π/3)
        caps = P.mmc_arm_capacitors(eq.states, m.elec.vDC_base)
        signals = Dict{String, Any}("iS_abc" =>
            (m.elec.Sbase / m.elec.vDC_base) .* collect(0.24 .+ 0.11 .* cos.(-2 .* phases) .- 0.07 .* sin.(-2 .* phases)),
            "theta_c" => eq.states.Δθ_VSM, "P_ac_f" => 0.7,
            "v_dc_f" => 0.3, "v_dc_divisor" => eq.outputs.meas.v_dc_f)
        for (arm, voltages) in (("u", caps.upper), ("l", caps.lower)), (phase, voltage) in zip(("a", "b", "c"), voltages)
            signals["v_Ctot_" * arm * "_" * phase] = voltage
        end
        for time in (0.0, 0.05, 0.2 - SETTINGS.time_step, 0.2)
            live = evaluate(diagnostic(modules["SIGMA_DUT"], ["iS_d", "iS_q"]), signals, time)
            @test live["iS_d"] ≈ circulating.d atol=1e-6
            @test live["iS_q"] ≈ circulating.q atol=1e-6
            @test live["iS_z"] ≈ 0.24 atol=1e-6
        end

        # Reuse the existing speed kind/rule with the converter probe name.
        # Exercise both sides of the bound and missing/invalid probes.
        channel = only(filter(c -> c.name == "DUT_omega_c", plan.probes.channels))
        @test channel.kind == :machine_speed
        probes = P.ProbeManifest([channel], nothing)
        model = PSCADModel("synthetic.pscx", "synthetic", list, probes, SETTINGS, list.operating_point, (;))
        times = collect(0.0:250e-6:0.3)
        for frequency in (1.0, 1.0009, 1.0011, 0.9989)
            channels = PI.OrderedDict("DUT_omega_c" => fill(frequency, length(times)))
            table = compare_operating_point(synthetic_result(times, channels; probes), model)
            @test only(table.quantity) == :machine_speed
            @test only(table.name) == "DUT_omega_c"
            @test only(table.error) ≈ abs(frequency - 1)
            @test only(table.within_tolerance) == (abs(frequency - 1) <= 1e-3)
        end
        empty_channels = PI.OrderedDict{String, Vector{Float64}}()
        @test_throws ArgumentError compare_operating_point(
            synthetic_result(times, empty_channels; probes), model)
        bad = P.ProbeChannel(channel.name, channel.kind, channel.bus,
            channel.element, channel.port, 1, "rad")
        bad_probes = P.ProbeManifest([bad], nothing)
        bad_model = PSCADModel("synthetic.pscx", "synthetic", list, bad_probes, SETTINGS, list.operating_point, (;))
        channels = PI.OrderedDict("DUT_omega_c" => ones(length(times)))
        @test_throws ArgumentError compare_operating_point(synthetic_result(times, channels; probes = bad_probes), bad_model)

        # Every converter row applies to the GFM fixture, with its solved terminal values,
        # capacitor means and signed current identity.
        probes = P.ProbeManifest(filter(c -> c.element == "DUT" || c.kind == :voltage,
            plan.probes.channels), plan.probes.reference_bus)
        model = PSCADModel("synthetic.pscx", "synthetic", list, probes, SETTINGS, list.operating_point, (;))
        channels = PI.OrderedDict{String, Vector{Float64}}()
        flow = list.operating_point.branch_flows[:DUT]
        ac = only(filter(t -> t.port == :ac && !t.grounded, e.terminals))
        bus = only(filter(b -> b.key == ac.bus, list.buses))
        point = list.operating_point.bus_states[ac.bus]
        voltage = sqrt(2) * bus.base_kV * point.vm_pu * cis(point.va_rad)
        dc = only(filter(t -> t.port == :dc && !t.grounded, e.terminals))
        dbus = only(filter(b -> b.key == dc.bus, list.buses))
        vdc = 2dbus.base_kV * list.operating_point.bus_states[dc.bus].vm_pu
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
                        c.kind == :converter_sum_current ? flow.pf*m.elec.vDC_base/(3m.elec.Sbase*vdc) :
                        c.kind == :machine_speed ? 1.0 :
                        c.kind == :current ? flow.pf/vdc :
                        c.kind == :voltage ? (c.pole == "P" ? vdc/2 : -vdc/2) : 1.0
                channels[c.name] = fill(value, length(times))
            end
        end
        table = compare_operating_point(synthetic_result(times, channels; probes), model)
        @test all(table.within_tolerance)
        @test count(==(:converter_p), table.quantity) == 2
        @test count(==(:converter_q), table.quantity) == 2
        @test count(==(:converter_arm_voltage), table.quantity) == 6
        @test count(==(:converter_dc_current_identity), table.quantity) == 1
        @test count(==(:machine_speed), table.quantity) == 1
    end
end
end
