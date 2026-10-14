module PSCADMMCTests
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures
using ..PSCADTLCTests: evaluate
using ..PSCADResultsTests: synthetic_result, add_three_phase!
using ..PSCADTopology
const P = PowerImpedance.PSCAD
const PI = PowerImpedance
const SETTINGS = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 250e-6, source_ramp = 0.0)

function converter_element(e, m)
    element = PI.Element(; element_model = m, input_pins = 1, output_pins = 2,
        transformation = false, setpoint = e.setpoint, limits = e.element.limits)
    return P.NetlistElement(e.name, e.pscad, element, m, e.terminals, e.role, e.setpoint)
end
function with_modulation(m, modulation)
    return PI.MMC(; m.meas, m.sync, m.delta_control, m.sigma_control, modulation, m.elec)
end

@testset "MMC live feedback and DC-divisor handover" begin
    fixture = PSCADFixtures.mmc_pq_network()
    list = P.netlist(fixture.classic, power_flow(fixture.classic))
    e = only(filter(e -> e.model isa PI.MMC, list.elements))
    eq = P.converter_equilibrium(e)
    plan = P.build_plan(list; settings = SETTINGS)
    modules = Dict(m.name => m for m in plan.modules)
    @test P._CONVERTER_STARTUP_RELEASE == 0.2
    selectors = [(m.name, c) for m in plan.modules for c in m.canvas.components
                 if c.defn == "master:compare"]
    @test length(selectors) == 1
    name, selector = only(selectors)
    @test name == "MEAS_DUT"
    parameters = Dict(selector.params)
    @test parameters["X"] == "0.2"
    @test parameters["OH"] == "v_dc_f"
    @test parameters["INTR"] == parameters["conv"] == "0"
    @test parameters["Dim"] == "1"
    @test P._pscad_number(parameters["OL"]) ≈ eq.outputs.meas.v_dc_f
    @test all(!occursin("divisor", c.name) for c in plan.probes.channels)

    # The plant's zero meter inputs must reach every feedback loop immediately;
    # only the shared denominator is solved until the saved TLC release time.
    for sample_time in (0.0, 250e-6, 0.05, 0.2 - SETTINGS.time_step)
        signals = Dict{String, Any}("v_abc" => zeros(3), "i_abc" => zeros(3),
            "v_dc" => 0.0, "i_dc_si" => 0.0, "theta_c" => 0.0, "theta_rel" => 0.0,
            "iS_abc" => zeros(3))
        for half in ("u", "l"), phase in ("a", "b", "c")
            signals["v_Ctot_" * half * "_" * phase] = e.model.elec.vDC_base
        end
        merge!(signals, evaluate(modules["MEAS_DUT"], signals, sample_time))
        for n in ("vG_d_f", "vG_q_f", "i_d_f", "i_q_f", "v_dc_f", "P_ac_f", "Q_ac_f")
            @test signals[n] == 0.0
        end
        @test signals["v_dc_divisor"] ≈ eq.outputs.meas.v_dc_f
        for name in ("PLL_DUT", "PCTRL_DUT", "QCTRL_DUT", "OCC_DUT", "SIGMA_DUT", "MOD_DUT")
            outputs = evaluate(modules[name], signals, sample_time)
            @test all(isfinite, values(outputs))
            merge!(signals, outputs)
        end
        @test signals["iS_z"] == 0.0
        live_meas = NamedTuple{keys(eq.outputs.meas)}(ntuple(_ -> 0.0, length(eq.outputs.meas)))
        delta = PI.state_space!(zeros(PI.n_states(e.model.delta_control)), eq.states,
            (; meas = live_meas, sync = eq.outputs.sync), eq.setpoint_pu,
            e.model.delta_control, e.model)
        @test signals["vM_d_ref"] ≈ delta.vMΔ_d_ref_c
        @test signals["vM_q_ref"] ≈ delta.vMΔ_q_ref_c
        live_states = merge(eq.states, (; iΣ_d = 0.0, iΣ_q = 0.0, iΣ_z = 0.0,
            vCΔ_d = 0.0, vCΔ_q = 0.0, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0,
            vCΣ_d = 0.0, vCΣ_q = 0.0, vCΣ_z = 1.0))
        # The owned equation uses one Vdc. Separate its protected division
        # from the live half-DC feedforward in the emitted realization.
        sigma = PI.state_space!(zeros(4), live_states,
            (; meas = merge(live_meas, (; v_dc_f = signals["v_dc_divisor"])),
                power = (; P_ac_f = 0.0), sync = eq.outputs.sync),
            eq.setpoint_pu, e.model.sigma_control, e.model)
        @test signals["vMS_z_ref"] ≈ sigma.vMΣ_z_ref - signals["v_dc_divisor"] / 2 atol=1e-6
    end

    # Independent changes in energy and current must reach TEC and its inner
    # controller before release. A held current would fail these equations.
    for sample_time in (0.0, 0.05, 0.2 - SETTINGS.time_step), level in (0.94, 1.08), current in (0.0, 0.31)
        live_states = merge(eq.states, (; iΣ_d = 0.0, iΣ_q = 0.0, iΣ_z = current,
            vCΔ_d = 0.0, vCΔ_q = 0.0, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0,
            vCΣ_d = 0.0, vCΣ_q = 0.0, vCΣ_z = level))
        signals = Dict{String, Any}("iS_abc" => fill(current * e.model.elec.Sbase / e.model.elec.vDC_base, 3),
            "theta_c" => 0.0, "P_ac_f" => 0.43, "v_dc_f" => 0.27,
            "v_dc_divisor" => eq.outputs.meas.v_dc_f)
        for half in ("u", "l"), phase in ("a", "b", "c")
            signals["v_Ctot_" * half * "_" * phase] = level * e.model.elec.vDC_base
        end
        expected = PI.state_space!(zeros(4), live_states,
            (; meas = merge(eq.outputs.meas, (; P_ac_f = 0.43)), power = (; P_ac_f = 0.43), sync = eq.outputs.sync),
            eq.setpoint_pu, e.model.sigma_control, e.model)
        measured = evaluate(modules["SIGMA_DUT"], signals, sample_time)
        @test measured["vMS_z_ref"] ≈ expected.vMΣ_z_ref + (0.27 - eq.outputs.meas.v_dc_f) / 2 atol=1e-6
        @test measured["iS_z"] ≈ current
    end

    # All measurement filters consume live inputs, on either side of release.
    # The divisor follows that filtered DC value at exactly 0.2 s, including zero.
    phases = (0.0, -2π / 3, 2π / 3)
    for sample_time in (0.0, 0.05, 0.2 - SETTINGS.time_step, 0.2, 0.2 + SETTINGS.time_step, 9.8), voltage in (0.0, 0.94)
        signals = Dict{String, Any}(
            "v_abc" => e.model.elec.vAC_base .* (0.91 .* cos.(phases)),
            "i_abc" => (2e.model.elec.Sbase / (3e.model.elec.vAC_base)) .*
                       (0.43 .* cos.(phases) .- 0.17 .* sin.(phases)),
            "v_dc" => voltage * 800, "i_dc_si" => 0.35,
            "theta_c" => 0.0, "theta_rel" => 0.14)
        measured = evaluate(modules["MEAS_DUT"], signals, sample_time)
        @test measured["v_dc_f"] ≈ voltage
        @test measured["v_dc_divisor"] ≈ (sample_time < 0.2 ? eq.outputs.meas.v_dc_f : voltage)
        @test measured["P_ac_f"] ≈ 0.91 * 0.43
        @test measured["Q_ac_f"] ≈ -0.91 * 0.17
    end

    # All ten measurement quantities and supported Butterworth orders 1–6
    # retain solved initial states but respond to live input from the first step.
    for (field, u) in pairs(eq.outputs.meas), order in 0:6
        filter = order == 0 ? PI.NoFilter() :
                 PI.measurement_filter_ss(PI.Butterworth(; order, ωc = 500.0))
        names = PI.filter_statenames(field, filter)
        states = PI.filter_initialvalues(filter, names, u)
        graph = P.BlockGraph(P.ControlBlock[P.Import("raw", P.Signal("raw"))])
        parameters = P.ModuleParameterPlan[]
        P.converter_filter!(graph, parameters, P.Signal("raw"), P.Signal("filtered"),
            filter, names, states, u, e)
        push!(graph.nodes, P.Export("filtered", P.Signal("filtered")))
        outputs = [("filtered", 1)]
        if field == :v_dc_f
            append!(graph.nodes, P.ControlBlock[P.TimeStep(P.Signal("filter_clock_s")),
                P._ConverterStartupHold(P.Signal("filter_clock_s"), P.Signal("filtered"), P.Signal("divisor"), u),
                P.Export("divisor", P.Signal("divisor"))])
            push!(outputs, ("divisor", 1))
        end
        definition = P.converter_definition("LIVE_FILTER", parameters, graph,
            [("raw", 1)], outputs)
        @test P.check_connectivity(definition.canvas, definition.name,
            Dict(definition.name => definition)) === nothing
        @test PSCADTopology.check_degrees(PSCADTopology.electrical_graph(
            definition.canvas, Dict(definition.name => definition)), definition.name) === nothing
        @test count(c -> c.defn == "master:compare", definition.canvas.components) == (field == :v_dc_f ? 1 : 0)
        for sample_time in (0.0, 0.1, 0.2 - SETTINGS.time_step, 0.2, 0.2 + SETTINGS.time_step)
            raw = u + 0.37
            measured = evaluate(definition, Dict("raw" => raw), sample_time)
            @test measured["filtered"] ≈ (order == 0 ? raw : u) atol=1e-6
            if field == :v_dc_f
                @test measured["divisor"] ≈ (sample_time < 0.2 ? u : measured["filtered"]) atol=1e-6
            end
            if order > 0
                derivatives = zeros(length(names))
                PI.filter_step!(derivatives, 1, states, filter, names, raw)
                @test maximum(abs, derivatives) > 0.0
            end
        end
        @test all(Dict(c.params)["Reset"] == "0"
        for c in definition.canvas.components if c.defn == "master:integral")
    end
end

@testset "MMC plans, topology and solved initialization" begin
    fixture = PSCADFixtures.mmc_pq_network()
    plans = P.ProjectPlan[]
    for network in (fixture.classic, fixture.state)
        pf = network isa Network ? power_flow(network) :
             NetworkBuilder.solve(network).powerflow
        list = P.netlist(network, pf)
        e = only(filter(e -> e.model isa PI.MMC, list.elements))
        equilibrium = P.converter_equilibrium(e)
        residual = zeros(length(equilibrium.states))
        PI._state_space!(residual, collect(values(equilibrium.states)),
            collect(values(equilibrium.inputs)),
            equilibrium.setpoint_pu, e.model, PI.Equil())
        @test maximum(abs, residual) <= 1e-6
        @test equilibrium.outputs.meas.P_ac_f ≈ 0.6
        @test equilibrium.outputs.meas.Q_ac_f ≈ 0.2
        plan = P.build_plan(list; settings = SETTINGS)
        push!(plans, plan)
        @test P.check_connectivity(plan) === nothing
        @test length(plan.modules) == 10
        modules = Dict(m.name => m for m in plan.modules)
        for (name, canvas) in [("Main", plan.main);
                               [(m.name, m.canvas) for m in plan.modules]]
            @test P.check_connectivity(canvas, name, modules) === nothing
            graph = PSCADTopology.electrical_graph(canvas, modules)
            @test PSCADTopology.check_degrees(graph, name) === nothing
        end
        @test length(unique(c.name for c in plan.probes.channels)) ==
              length(plan.probes.channels)
        @test Set(c.name
        for c in plan.probes.channels if c.element == "DUT" && c.kind != :current) ==
              Set("DUT_" * n
        for n in ["P_ac_f", "Q_ac_f", "v_dc_f", "omega_c", "theta_c", "iS_z",
            ["v_Ctot_" * half * "_" * phase for half in ("u", "l")
             for phase in ("a", "b", "c")]...])
        parent = modules["MMC_DUT"]
        @test !haskey(modules, "ARM_DUT")
        @test count(c -> c.defn == "master:xfmr-3p2w", parent.canvas.components) == 1
        @test count(c -> c.defn == "master:ammeter", parent.canvas.components) == 7
        for kind in ("source_1", "inductor", "resistor", "integral")
            @test count(c -> c.defn == "master:" * kind &&
                (kind == "integral" || occursin("_arm_", get(Dict(c.params), "Name", ""))), parent.canvas.components) == 6
        end
        inductors = filter(c -> c.defn == "master:inductor" &&
            endswith(get(Dict(c.params), "Name", ""), "_arm_inductance"), parent.canvas.components)
        resistors = filter(c -> c.defn == "master:resistor" &&
            endswith(get(Dict(c.params), "Name", ""), "_arm_resistance"), parent.canvas.components)
        @test all(Dict(c.params)["L"] == "0.05 [H]" for c in inductors)
        @test all(Dict(c.params)["R"] == "1.07 [ohm]" for c in resistors)
        caps = P.mmc_arm_capacitors(equilibrium.states, 800.0)
        integrators = filter(c -> c.defn == "master:integral", parent.canvas.components)
        @test [P._pscad_number(Dict(c.params)["Yo"]) for c in integrators] ≈
              collect(Iterators.flatten(zip(caps.upper, caps.lower)))
        gains = filter(c -> c.defn == "master:gain" &&
            P._pscad_number(Dict(c.params)["G"]) == 400 / 0.01, parent.canvas.components)
        @test length(gains) == 6
        transformer = only(filter(c -> c.defn == "master:xfmr-3p2w", parent.canvas.components))
        @test Dict(transformer.params)["Ideal"] == "0"
        @test P._pscad_number(replace(Dict(transformer.params)["V2"], " [kV]" => "")) ≈
              380.0
        @test Dict(transformer.params)["Im1"] == "0.001 [%]"
        @test all(Dict(c.params)["Tc"] == "0.0 [s]"
        for c in plan.main.components
        if c.defn in ("master:source_1", "master:source_3"))
        default_plan = P.build_plan(list)
        @test all(Dict(c.params)["Tc"] == "0.05 [s]"
        for c in default_plan.main.components
        if c.defn in ("master:source_1", "master:source_3"))
        for m in (PI.MMC(; e.model.meas, sync = PI.NoSynchronization(), e.model.delta_control,
            e.model.sigma_control, e.model.modulation, e.model.elec),
            PI.MMC(; e.model.meas, e.model.sync,
            delta_control = PI.ΔdqControlGFL(;
                e.model.delta_control.outer_active, e.model.delta_control.outer_reactive,
                occ = PI.NoInnerCurrentControl()),
            e.model.sigma_control, e.model.modulation, e.model.elec))
            future = P.Netlist(list.buses,
                [converter_element(e, m); filter(x -> x.name != e.name, list.elements)],
                list.operating_point, list.voltageBase, list.frequency)
            @test_throws r"not yet exportable" P.build_plan(future; settings = SETTINGS)
        end
        unity_si = P.mmc_si(e.model.elec)
        unity = merge(unity_si, (; turnsRatio = 1.0))
        unity_canvas = P.mmc_electrical_canvas(e, equilibrium, unity)
        P.converter_angle_snapshot!(unity_canvas, e, equilibrium; origin = (5400, 2160))
        capacitor_measurements = (; (Symbol("v_Ctot_" * half * "_" * phase) =>
            "v_Cmeas_" * half * "_" * phase for half in ("u", "l") for phase in ("a", "b", "c"))...)
        for (i, definition) in enumerate(plan.modules[3:9])
            P.converter_instance!(unity_canvas, definition, "network",
                (5400 + 540 * ((i - 1) ÷ 3), 108 + 540 * ((i - 1) % 3)),
                merge(capacitor_measurements,
                    i == 2 ? (; theta_c = "theta_next", theta_rel = "theta_rel_next") : (;)))
        end
        @test count(c -> c.defn == "master:xfmr-3p2w", unity_canvas.components) == 0
        @test P.check_connectivity(unity_canvas, "unity", modules) === nothing
        @test PSCADTopology.check_degrees(
            PSCADTopology.electrical_graph(unity_canvas, modules), "unity") === nothing
        meas = modules["MEAS_DUT"]
        phases = (0.0, -2π / 3, 2π / 3)
        x, y = equilibrium.states, equilibrium.outputs
        signals = Dict{String, Any}(
            "v_abc" =>
                e.model.elec.vAC_base .*
                collect(y.sig_in.vG_d_g .* cos.(phases) .+ y.sig_in.vG_q_g .* sin.(phases)),
            "i_abc" =>
                (2e.model.elec.Sbase / (3e.model.elec.vAC_base)) .*
                collect(x.iΔ_d .* cos.(phases) .+ x.iΔ_q .* sin.(phases)),
            "v_dc" => 800.0, "i_dc_si" => y.sig_in.i_dc * e.model.elec.Sbase / 800.0,
            "theta_c" => x.Δθ_pll, "theta_rel" => x.Δθ_pll)
        merge!(signals, evaluate(meas, signals))
        for signal in ("P_ac_f", "Q_ac_f", "v_dc_f", "i_d_f", "i_q_f", "vG_d_f", "vG_q_f")
            @test isapprox(signals[signal], getproperty(y.meas, Symbol(signal)); atol = 1e-6, rtol = 1e-6)
        end
        merge!(signals, evaluate(modules["PLL_DUT"], signals))
        merge!(signals, evaluate(modules["PCTRL_DUT"], signals))
        merge!(signals, evaluate(modules["QCTRL_DUT"], signals))
        merge!(signals, evaluate(modules["OCC_DUT"], signals))
        @test signals["i_d_ref"] ≈ y.delta.iΔ_d_ref
        @test signals["vM_d_ref"] ≈ y.delta.vMΔ_d_ref_c
        @test signals["vM_q_ref"] ≈ y.delta.vMΔ_q_ref_c
    end
    for (a, b) in zip(plans[1].modules, plans[2].modules)
        @test a.name == b.name
        @test Float64[p.default for p in a.parameters] ≈
              Float64[p.default for p in b.parameters]
    end
end

@testset "Module electrical parameters require finite literals" begin
    fixture = PSCADFixtures.mmc_pq_network()
    list = P.netlist(fixture.classic, power_flow(fixture.classic))
    plan = P.build_plan(list; settings = SETTINGS)
    for (module_name, defn, field, invalid) in (
        ("MMC_DUT", "inductor", "L", "armL"),
        ("MMC_DUT", "resistor", "R", "armR"),
        ("MMC_DUT", "source_1", "Tc", "source_ramp [s]"),
        ("MMC_DUT", "xfmr-3p2w", "Xl", "leakage"),
        ("MMC_DUT", "inductor", "L", "NaN [H]"),
        ("MMC_DUT", "resistor", "R", "Inf [ohm]"),
        ("MMC_DUT", "inductor", "L", "1e999 [H]"),
        ("MMC_DUT", "resistor", "R", "1 + 0.07 [ohm]"))
        invalid_plan = deepcopy(plan)
        definition = only(filter(m -> m.name == module_name, invalid_plan.modules))
        component = first(filter(c -> c.defn == "master:" * defn, definition.canvas.components))
        index = findfirst(p -> first(p) == field, component.params)
        component.params[index] = field => invalid
        @test_throws r"requires a finite numeric literal" P.check_connectivity(invalid_plan)
    end
    # The saved arm's unit-bearing scientific notation is accepted, as are
    # control-module parameters capGain/capInitial and electrical Name labels.
    arm = only(filter(m -> m.name == "MMC_DUT", plan.modules))
    inductor = first(filter(c -> c.defn == "master:inductor", arm.canvas.components))
    index = findfirst(p -> first(p) == "L", inductor.params)
    inductor.params[index] = "L" => "50e-3 [H]"
    @test P.check_connectivity(plan) === nothing
end

@testset "MMC Σ control against owned equations" begin
    fixture = PSCADFixtures.mmc_pq_network()
    list = P.netlist(fixture.classic, power_flow(fixture.classic))
    e = only(filter(e -> e.model isa PI.MMC, list.elements))
    eq = P.converter_equilibrium(e)
    transforms = (; abc = "network:ABC_DQ", dq = "network:DQ_ABC")
    base = e.model.elec.Sbase / e.model.elec.vDC_base
    for phase_angle in (0.0, 0.37, 1.4), relative_angle in (0.0, -0.21, 0.49)

        x = merge(eq.states,
            (; Δθ_pll = relative_angle, iΣ_d = 0.023, iΣ_q = -0.017,
                iΣ_z = 0.21, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0))
        caps = P.mmc_arm_capacitors(x, 800.0, phase_angle)
        phases = phase_angle .+ (0.0, -2π / 3, 2π / 3)
        currents = base .* collect(x.iΣ_z .+ x.iΣ_d .* cos.(-2 .* phases) .+
                           x.iΣ_q .* sin.(-2 .* phases))
        signals = Dict{String, Any}(
            "iS_abc" => currents, "theta_c" => phase_angle + relative_angle,
            "P_ac_f" => 0.6, "v_dc_f" => 1.0, "v_dc_divisor" => 1.0)
        for (half, values) in (("u", caps.upper), ("l", caps.lower)),
            (phase, value) in zip(("a", "b", "c"), values)

            signals["v_Ctot_" * half * "_" * phase] = value
        end
        definition = P.mmc_sigma("SIGMA", e, (; states = x), transforms)
        measured = evaluate(definition, signals)
        expected = PI.state_space!(zeros(4), x,
            (; meas = eq.outputs.meas, power = (; P_ac_f = 0.6), sync = eq.outputs.sync), eq.setpoint_pu,
            e.model.sigma_control, e.model)
        @test measured["iS_z"] ≈ x.iΣ_z
        @test measured["vMS_d_ref"] ≈ expected.vMΣ_d_ref_c
        @test measured["vMS_q_ref"] ≈ expected.vMΣ_q_ref_c
        @test measured["vMS_z_ref"] ≈ expected.vMΣ_z_ref
    end
    # The triplen pair has a 6ω energy ripple in the six-arm plant. A full
    # cycle average recovers the current harmonic model's energy exactly.
    x = eq.states
    energy = sum(0:255) do i
        caps = P.mmc_arm_capacitors(x, 800.0, 2π * i / 256)
        (sum(abs2, caps.upper) + sum(abs2, caps.lower)) / (6 * 800.0^2)
    end / 256
    expected = (x.vCΔ_d^2 + x.vCΔ_q^2 + x.vCΔ_Zd^2 + x.vCΔ_Zq^2 + x.vCΣ_d^2 + x.vCΣ_q^2 +
                2x.vCΣ_z^2) / 2
    @test energy ≈ expected
end

@testset "MMC modulation and R12 arm assembly" begin
    fixture = PSCADFixtures.mmc_pq_network()
    list = P.netlist(fixture.classic, power_flow(fixture.classic))
    e = only(filter(e -> e.model isa PI.MMC, list.elements))
    transforms = (; abc = "network:ABC_DQ", dq = "network:DQ_ABC")
    for delay in (0.0, 200e-6)
        m = with_modulation(e.model,
            PI.UncompensatedModulation(timeDelay = delay,
                padeOrderNum = 3, padeOrderDen = 3))
        altered = converter_element(e, m)
        eq = P.converter_equilibrium(altered)
        definition = P.mmc_modulation("MOD", altered, eq, transforms, SETTINGS)
        @test count(c -> c.defn == "master:tdelay", definition.canvas.components) ==
              (iszero(delay) ? 0 : 5)
        for sample_time in (0.0, 0.0037, 0.011)
            signals = Dict{String, Any}("vM_d_ref" => eq.outputs.delta.vMΔ_d_ref_c,
                "vM_q_ref" => eq.outputs.delta.vMΔ_q_ref_c, "vMS_d_ref" =>
                    eq.outputs.sigma.vMΣ_d_ref_c,
                "vMS_q_ref" => eq.outputs.sigma.vMΣ_q_ref_c, "vMS_z_ref" =>
                    eq.outputs.sigma.vMΣ_z_ref,
                "v_dc_divisor" => eq.outputs.meas.v_dc_f, "theta_rel" => eq.states.Δθ_pll)
            measured = evaluate(definition, signals, sample_time)
            mod = eq.outputs.mod
            for (i, phase) in enumerate(("a", "b", "c"))
                angle = m.elec.ωbase * sample_time - 2π * (i - 1) / 3
                delta = mod.mΔd * cos(angle) + mod.mΔq * sin(angle)
                sigma = mod.mΣd * cos(-2angle) + mod.mΣq * sin(-2angle) + mod.mΣz
                @test measured["m_u_" * phase] ≈ (sigma + delta) / 2
                @test measured["m_l_" * phase] ≈ (sigma - delta) / 2
            end
        end
    end
    eq = P.converter_equilibrium(e)
    definition = P.mmc_modulation("R12", e, eq, transforms, SETTINGS)
    for relative_angle in (-0.31, 0.47), sample_time in (0.0037, 0.011)

        x = merge(eq.states, (; Δθ_pll = relative_angle))
        delta = (; vMΔ_d_ref_c = 0.24, vMΔ_q_ref_c = -0.1)
        sigma = (; vMΣ_d_ref_c = 0.05, vMΣ_q_ref_c = -0.02, vMΣ_z_ref = 0.48)
        meas = merge(eq.outputs.meas, (; v_dc_f = 1.01))
        expected = PI.state_space!(
            Float64[], x, (; meas, out_delta = delta, out_sigma = sigma),
            e.model.modulation, e.model)
        measured = evaluate(definition,
            Dict("vM_d_ref" => delta.vMΔ_d_ref_c,
                "vM_q_ref" => delta.vMΔ_q_ref_c, "vMS_d_ref" => sigma.vMΣ_d_ref_c,
                "vMS_q_ref" => sigma.vMΣ_q_ref_c, "vMS_z_ref" => sigma.vMΣ_z_ref,
                "v_dc_divisor" => meas.v_dc_f, "theta_rel" => relative_angle),
            sample_time)
        for (i, phase) in enumerate(("a", "b", "c"))
            angle = e.model.elec.ωbase * sample_time - 2π * (i - 1) / 3
            md = expected.mΔd * cos(angle) + expected.mΔq * sin(angle)
            ms = expected.mΣd * cos(-2angle) + expected.mΣq * sin(-2angle) + expected.mΣz
            @test measured["m_u_" * phase] ≈ (ms + md) / 2
            @test measured["m_l_" * phase] ≈ (ms - md) / 2
        end
    end
    for direction in (-1.0, 1.0)
        delta = direction * 80.0
        measured = evaluate(definition,
            Dict("vM_d_ref" => delta / e.model.elec.vAC_base,
                "vM_q_ref" => 0.0, "vMS_d_ref" => 0.0, "vMS_q_ref" => 0.0,
                "vMS_z_ref" => 0.5, "v_dc_divisor" => 1.0, "theta_rel" => 0.0))
        @test 800measured["m_u_a"] ≈ 400 - delta
        @test 800measured["m_l_a"] ≈ 400 + delta
    end
end

@testset "MMC arm equations projected onto the current harmonic model" begin
    fixture = PSCADFixtures.mmc_pq_network()
    list = P.netlist(fixture.classic, power_flow(fixture.classic))
    e = only(filter(e -> e.model isa PI.MMC, list.elements))
    eq = P.converter_equilibrium(e)
    b = e.model.elec
    x = merge(eq.states,
        (; iΔ_d = 0.41, iΔ_q = -0.19, iΣ_d = 0.024,
            iΣ_q = -0.013, iΣ_z = 0.17, vCΔ_d = 0.037, vCΔ_q = -0.021,
            vCΔ_Zd = 0.009, vCΔ_Zq = -0.006, vCΣ_d = 0.012, vCΣ_q = -0.008, vCΣ_z = 1.03))
    mod = (; mΔd = -0.64, mΔq = 0.12, mΔZd = 0.0, mΔZq = 0.0,
        mΣd = 0.028, mΣq = -0.017, mΣz = 0.98)
    core = zeros(12)
    PI.state_space!(
        core, x, (; out_modulation = mod, sig_in = eq.outputs.sig_in,
            inputs = eq.inputs),
        b, e.model)
    projection = zeros(12)
    si = P.mmc_si(b)
    cap_gain = (si.N / si.C_SM) * (si.Sbase / si.vDC_base) / si.vDC_base
    samples = 256
    for sample in 0:(samples - 1)
        theta = 2π * sample / samples
        phases = theta .+ (0.0, -2π / 3, 2π / 3)
        caps = P.mmc_arm_capacitors(x, 1.0, theta)
        md = mod.mΔd .* cos.(phases) .+ mod.mΔq .* sin.(phases)
        ms = mod.mΣz .+ mod.mΣd .* cos.(-2 .* phases) .+ mod.mΣq .* sin.(-2 .* phases)
        id = b.baseConv3 .* (x.iΔ_d .* cos.(phases) .+ x.iΔ_q .* sin.(phases))
        is = x.iΣ_z .+ x.iΣ_d .* cos.(-2 .* phases) .+ x.iΣ_q .* sin.(-2 .* phases)
        upper_m, lower_m = (ms .+ md) ./ 2, (ms .- md) ./ 2
        upper_i, lower_i = is .+ id ./ 2, is .- id ./ 2
        vu, vl = upper_m .* caps.upper, lower_m .* caps.lower
        vs, vd = (vu .+ vl) ./ 2, (vl .- vu) ./ 2
        upper_rate, lower_rate = cap_gain .* upper_m .* upper_i,
        cap_gain .* lower_m .* lower_i
        cs, cd = (upper_rate .+ lower_rate) ./ 2, (upper_rate .- lower_rate) ./ 2
        # Fourier projections retain exactly the harmonics represented by the
        # current core, independent of its hard-coded matrix implementation.
        projection[1] += (2 / 3) * sum(vd .* cos.(phases)) / samples * b.baseConv2
        projection[2] += (2 / 3) * sum(vd .* sin.(phases)) / samples * b.baseConv2
        projection[3] += (2 / 3) * sum(vs .* cos.(-2 .* phases)) / samples
        projection[4] += (2 / 3) * sum(vs .* sin.(-2 .* phases)) / samples
        projection[5] += sum(vs) / (3samples)
        projection[6] += (2 / 3) * sum(cd .* cos.(phases)) / samples
        projection[7] += (2 / 3) * sum(cd .* sin.(phases)) / samples
        projection[8] += (2 / 3) * sum(cd) * cos(3theta) / samples
        projection[9] += (2 / 3) * sum(cd) * sin(3theta) / samples
        projection[10] += (2 / 3) * sum(cs .* cos.(-2 .* phases)) / samples
        projection[11] += (2 / 3) * sum(cs .* sin.(-2 .* phases)) / samples
        projection[12] += sum(cs) / (3samples)
    end
    projection[1] = -(eq.outputs.sig_in.vG_d_g - projection[1] + b.Rₑ * x.iΔ_d +
                      b.Lₑ * x.iΔ_q) / b.Lₑ * b.ωbase
    projection[2] = -(eq.outputs.sig_in.vG_q_g - projection[2] + b.Rₑ * x.iΔ_q -
                      b.Lₑ * x.iΔ_d) / b.Lₑ * b.ωbase
    projection[3] = -(projection[3] + b.Rₐᵣₘ * x.iΣ_d - 2b.Lₐᵣₘ * x.iΣ_q) / b.Lₐᵣₘ * b.ωbase
    projection[4] = -(projection[4] + b.Rₐᵣₘ * x.iΣ_q + 2b.Lₐᵣₘ * x.iΣ_d) / b.Lₐᵣₘ * b.ωbase
    projection[5] = -(projection[5] - eq.inputs.v_dc / 2 + b.Rₐᵣₘ * x.iΣ_z) / b.Lₐᵣₘ *
                    b.ωbase
    projection[6:12] .+= b.ωbase .* [-x.vCΔ_q, x.vCΔ_d, -3x.vCΔ_Zq,
        3x.vCΔ_Zd, 2x.vCΣ_q, -2x.vCΣ_d, 0.0]
    @test projection ≈ core
end

@testset "MMC synthetic comparison rows" begin
    fixture = PSCADFixtures.mmc_pq_network()
    for network in (fixture.classic, fixture.state)
        pf = network isa Network ? power_flow(network) :
             NetworkBuilder.solve(network).powerflow
        list = P.netlist(network, pf)
        plan = P.build_plan(list; settings = SETTINGS)
        e = only(filter(e -> e.model isa PI.MMC, list.elements))
        probes = P.ProbeManifest(
            filter(c -> c.element == "DUT" && c.kind != :converter_diagnostic,
                plan.probes.channels),
            nothing)
        # Terminal-power rows need the ordinary AC bus voltage as well.
        append!(probes.channels, filter(c -> c.kind == :voltage && c.dim == 3, plan.probes.channels))
        probes = P.ProbeManifest(probes.channels, plan.probes.reference_bus)
        model = PSCADModel("synthetic.pscx", "synthetic", list, probes, SETTINGS,
            list.operating_point, (; source = :fixture))
        times = collect(0.0:250e-6:0.3)
        channels = PI.OrderedDict{String, Vector{Float64}}()
        flow = list.operating_point.branch_flows[:DUT]
        arms = filter(c -> c.kind == :converter_arm_voltage, probes.channels)
        dc = only(filter(c -> c.kind == :current && c.side == "1", probes.channels))
        for c in probes.channels
            if c.kind == :voltage
                add_three_phase!(channels, c.name, times, 380sqrt(2 / 3))
            elseif c.kind == :current && c.side == "2"
                v = 380sqrt(2 / 3)
                add_three_phase!(channels, c.name, times, 2complex(flow.pt, -flow.qt) /
                                                          (3v))
            else
                value = c.kind == :converter_p ? flow.pt / 1000 :
                        c.kind == :converter_q ? flow.qt / 1000 :
                        c.kind == :converter_arm_voltage ? 800.0 :
                        c.kind == :converter_sum_current ? flow.pf / 3000 : flow.pf / 800.0
                channels[c.name] = fill(value, length(times))
            end
        end
        for (index, arm) in enumerate(arms)
            channels[arm.name] .+= 41.5 .* cos.(2π * 50 .* times .+ index)
            # A large start-up error must be excluded from the settled window.
            channels[arm.name][times .<= 0.1] .= 1600.0
        end
        table = compare_operating_point(synthetic_result(times, channels; probes), model)
        @test all(table.within_tolerance)
        @test count(==(:converter_arm_voltage), table.quantity) == 6
        @test count(==(:converter_dc_current_identity), table.quantity) == 1
        @test count(==(:converter_p), table.quantity) == 2
        @test count(==(:converter_q), table.quantity) == 2
        @test P._dc_converter_current_bases(list) ==
              Dict(t.bus => 1.25 for t in e.terminals if t.side == 1)
        rows = filter(r -> r.quantity == :converter_arm_voltage, table)
        @test Set(rows.name) == Set(c.name for c in arms)
        @test all(r -> r.pscad ≈ 800.0 && r.powerflow == 800.0, rows)
        identity = only(filter(r -> r.quantity == :converter_dc_current_identity, table))
        @test identity.name == "DUT_iS_z"
        @test identity.pscad ≈ flow.pf / 800.0
        @test identity.powerflow ≈ flow.pf / 800.0

        for arm in arms, (relative_error, accepted) in ((0.005, true), (0.015, false))

            measured = deepcopy(channels)
            measured[arm.name] .+= relative_error * 800.0
            row = only(filter(r -> r.name == arm.name,
                compare_operating_point(synthetic_result(times, measured; probes), model)))
            @test isapprox(row.error, relative_error; atol = 1e-12)
            @test row.within_tolerance == accepted
        end
        measured = deepcopy(channels)
        measured[first(arms).name] .+= 4.0
        for (rtol_v, accepted) in ((0.004, false), (0.006, true))
            row = only(filter(r -> r.name == first(arms).name,
                compare_operating_point(synthetic_result(times, measured; probes), model; rtol_v)))
            @test row.within_tolerance == accepted
        end

        # Capacitors use the solved pole-to-pole bus voltage, not the rated base.
        key = only(t.bus for t in e.terminals if t.side == 1)
        point = list.operating_point
        bus_states = copy(point.bus_states)
        bus_states[key] = merge(bus_states[key], (; vm_pu = 0.9bus_states[key].vm_pu))
        operating_point = P.OperatingPointRecord(bus_states, point.branch_flows,
            point.setpoints, point.slack_bus, point.bases)
        reference = PSCADModel(model.project_path, model.project_name, list, probes,
            SETTINGS, operating_point, model.provenance)
        rows = filter(r -> r.quantity == :converter_arm_voltage,
            compare_operating_point(synthetic_result(times, channels; probes), reference))
        @test all(r -> r.powerflow ≈ 720.0 && !r.within_tolerance, rows)
        measured = deepcopy(channels)
        for arm in arms
            measured[arm.name] .-= 80.0
        end
        rows = filter(r -> r.quantity == :converter_arm_voltage,
            compare_operating_point(synthetic_result(times, measured; probes), reference))
        @test all(r -> r.pscad ≈ 720.0 && r.within_tolerance, rows)

        # The identity uses measured iS_z, including reversed and zero flow.
        # Its error denominator retains the converter-current base at low load.
        for iz in (0.4, -0.4, 0.05, -0.05, 0.0),
            (relative_error, accepted) in ((0.0, true), (0.01, true), (0.03, false))

            measured = deepcopy(channels)
            measured["DUT_iS_z"] .= iz
            expected = 3iz * 1.25
            scale = max(abs(expected), 1.25)
            measured[dc.name] .= expected + relative_error * scale
            row = only(filter(r -> r.quantity == :converter_dc_current_identity,
                compare_operating_point(synthetic_result(times, measured; probes), model)))
            @test row.name == "DUT_iS_z"
            @test row.pscad ≈ expected + relative_error * scale
            @test row.powerflow ≈ expected
            @test isapprox(row.error, relative_error; atol = 1e-12)
            @test row.within_tolerance == accepted
        end
        measured = deepcopy(channels)
        measured["DUT_iS_z"] .= 0.4
        measured[dc.name] .= -1.5
        row = only(filter(r -> r.quantity == :converter_dc_current_identity,
            compare_operating_point(synthetic_result(times, measured; probes), model)))
        @test row.error ≈ 2.0
        @test !row.within_tolerance
        measured[dc.name] .= 1.5 + 0.01 * 1.5
        for (rtol_i, accepted) in ((0.009, false), (0.011, true))
            row = only(filter(r -> r.quantity == :converter_dc_current_identity,
                compare_operating_point(synthetic_result(times, measured; probes), model; rtol_i)))
            @test row.within_tolerance == accepted
        end

        # MVA/kV gives kA directly: neither probe values nor the identity use A.
        measured[dc.name] .= 1500.0
        row = only(filter(r -> r.quantity == :converter_dc_current_identity,
            compare_operating_point(synthetic_result(times, measured; probes), model)))
        @test row.powerflow ≈ 1.5
        @test !row.within_tolerance
        measured = deepcopy(channels)
        measured[first(arms).name] .*= 1000
        row = only(filter(r -> r.name == first(arms).name,
            compare_operating_point(synthetic_result(times, measured; probes), model)))
        @test row.powerflow == 800.0
        @test !row.within_tolerance

        # Recover current units from the particular MMC's electrical bases.
        m = e.model
        changed = converter_element(e,
            PI.MMC(; m.meas, m.sync, m.delta_control,
                m.sigma_control, m.modulation, elec = PI.ElectricalMMC(Sbase = 500.0, vDC_base = 1000.0)))
        netlist = P.Netlist(
            list.buses, [c.name == e.name ? changed : c for c in list.elements],
            point, list.voltageBase, list.frequency)
        reference = PSCADModel(model.project_path, model.project_name, netlist,
            probes, SETTINGS, point, model.provenance)
        measured = deepcopy(channels)
        measured["DUT_iS_z"] .= 0.4
        measured[dc.name] .= 0.6
        row = only(filter(r -> r.quantity == :converter_dc_current_identity,
            compare_operating_point(synthetic_result(times, measured; probes), reference)))
        @test row.powerflow ≈ 3 * 0.4 * 500 / 1000
        @test row.within_tolerance

        for (name, unit) in ((first(arms).name, "V"), ("DUT_iS_z", "kA"), (dc.name, "A"))
            wrong_units = P.ProbeManifest(
                [c.name == name ?
                 P.ProbeChannel(c.name, c.kind, c.bus, c.element,
                     c.side, c.dim, unit, c.orientation) : c for c in probes.channels],
                probes.reference_bus)
            reference = PSCADModel(model.project_path, model.project_name, list,
                wrong_units, SETTINGS, point, model.provenance)
            @test_throws ArgumentError compare_operating_point(
                synthetic_result(times, channels; probes = wrong_units), reference)
        end
        for name in [[c.name for c in arms]; "DUT_iS_z"; dc.name]
            missing = deepcopy(channels)
            delete!(missing, name)
            @test_throws ArgumentError compare_operating_point(synthetic_result(times, missing; probes), model)
        end
    end
end
end
