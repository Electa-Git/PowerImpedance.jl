module PSCADTLCTests
import ..PSCADFixtures
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures
const P = PowerImpedance.PSCAD
const PI = PowerImpedance

function value(v, parameters)
    v isa Real && return v
    haskey(parameters, v) && return parameters[v]
    return P._pscad_number(v)
end

# Evaluate the emitted network at its declared dynamic initial state and
# supplied time. The core state-space model supplies controller references.
function evaluate(definition, inputs, sample_time = 0.0; snapshots = Dict{String, Any}())
    canvas = definition.canvas
    parameters = Dict(p.name => p.default for p in definition.parameters)
    signals = Dict{String, Any}(inputs)
    labels = Dict((c.x, c.y) => Dict(c.params)["Name"]
    for c in canvas.components if c.defn == "master:datalabel")
    function signal(pin)
        for wire in canvas.wires
            pin in wire.vertices || continue
            other = only(filter(!=(pin), wire.vertices))
            haskey(labels, other) && return labels[other]
        end
        error("No signal at $pin")
    end
    function output(c)
        p = Dict(c.params)
        if c.defn == "master:datatap"
            return signal((c.x, c.y))
        elseif c.defn == "master:datamerge"
            return signal((c.x, c.y + 18 * (parse(Int, p["N"]) - 3)))
        else
            return signal((c.x + 36, c.y))
        end
    end
    for c in canvas.components
        p = Dict(c.params)
        if c.defn == "master:zminusone"
            signals[output(c)] = get(snapshots, output(c), value(p["InitR"], parameters))
        elseif c.defn == "master:integral"
            signals[output(c)] = value(p["Yo"], parameters)
        elseif c.defn == "master:realpole"
            signals[output(c)] = value(p["YO"], parameters)
        elseif c.defn == "master:tdelay"
            signals[output(c)] = value(p["X0"], parameters)
        end
    end
    for _ in 1:length(canvas.components)
        for c in canvas.components
            p = Dict(c.params)
            c.defn in ("master:datalabel", "master:export", "master:integral",
                "master:realpole", "master:tdelay", "master:zminusone") && continue
            c.defn == "master:import" && begin
                name = p["Name"]
                haskey(signals, name) || haskey(parameters, name) || continue
                # Coefficient-only imports have no wire.
                any(w -> (c.x + 36, c.y) in w.vertices, canvas.wires) || continue
                signals[output(c)] = haskey(parameters, name) ? parameters[name] :
                                     signals[name]
                continue
            end
            c.defn == "master:const" &&
                (signals[output(c)] = value(p["Value"], parameters); continue)
            c.defn == "master:time-sig" && (signals[output(c)] = sample_time; continue)
            if c isa P.ModuleInstancePlan
                a = signal((c.x - 36, c.y - 18))
                t = signal((c.x - 36, c.y + 18))
                all(haskey(signals, n) for n in (a, t)) || continue
                angle = signals[t]
                phases = angle .+ (0.0, -2π / 3, 2π / 3)
                if occursin("ABC_DQ", c.defn)
                    signals[output(c)] = [(2 / 3) * sum(signals[a] .* cos.(phases)),
                        (2 / 3) * sum(signals[a] .* sin.(phases))]
                else
                    d, q = signals[a]
                    signals[output(c)] = collect(d .* cos.(phases) .+ q .* sin.(phases))
                end
                continue
            end
            if c.defn == "master:sumjct"
                entries = [
                    ("D", (c.x - 36, c.y)), ("F", (c.x, c.y + 36)), ("B", (c.x, c.y - 36))]
                selected = [(parse(Int, p[k]), signal(pin))
                            for (k, pin) in entries if p[k] != "0"]
                all(haskey(signals, n) for (_, n) in selected) || continue
                signals[output(c)] = sum(sign * signals[n] for (sign, n) in selected)
            elseif c.defn in ("master:mult", "master:div")
                a, b = signal((c.x - 36, c.y)), signal((c.x, c.y + 36))
                all(haskey(signals, n) for n in (a, b)) || continue
                signals[output(c)] = c.defn == "master:mult" ? signals[a] * signals[b] :
                                     signals[a] / signals[b]
            elseif c.defn == "master:datamerge"
                n = parse(Int, p["N"])
                entries = [signal((c.x - 18, c.y + 18 * (i - 5))) for i in 1:n]
                all(haskey(signals, n) for n in entries) || continue
                signals[output(c)] = [signals[n] for n in entries]
            elseif c.defn == "master:datatap"
                n = signal((c.x, c.y - 18))
                haskey(signals, n) || continue
                signals[output(c)] = signals[n][parse(Int, p["Index"])]
            else
                n = signal((c.x - 36, c.y))
                haskey(signals, n) || continue
                u = signals[n]
                if c.defn == "master:compare"
                    selected = p[u < value(p["X"], parameters) ? "OL" : "OH"]
                    signals[output(c)] = haskey(signals, selected) ? signals[selected] :
                                         value(selected, parameters)
                    continue
                end
                signals[output(c)] = c.defn in ("master:force_dsout", "master:force_dsdyn") ? u :
                                     c.defn == "master:gain" ?
                                     value(p["G"], parameters) * u :
                                     c.defn == "master:trig" ?
                                     (p["Type"] == "1" ? sin(u) : cos(u)) :
                                     c.defn == "master:square" ? u^2 :
                                     c.defn == "master:sqrt" ? sqrt(u) :
                                     error("Unsupported $(c.defn)")
            end
        end
    end
    outputs = Dict{String, Any}()
    for c in canvas.components
        c.defn == "master:export" || continue
        outputs[Dict(c.params)["Name"]] = signals[signal((c.x + 36, c.y))]
    end
    return outputs
end

@testset "EMTDC reserved signal names" begin
    # Each documented include-file group has an independent representative.
    for name in ("time", "delt", "print", "fintim", "timezero", "firststep",
        "laststep", "onstep", "nstorf", "rtcf", "vdc", "ccbr", "two_pi",
        "filename", "comp_id1")
        for spelling in (name, uppercase(name), uppercasefirst(name))
            @test_throws ArgumentError P.Signal(spelling)
        end
    end
    @test P.Signal("pll_clock_s").name == "pll_clock_s"
    @test P.Signal("mod_clock_s").name == "mod_clock_s"
    @test P.Signal("experiment_clock_s").name == "experiment_clock_s"
    @test P.Signal("DUT_time").name == "DUT_time"
end

@testset "TLC primitives" begin
    a, b, c = P.Signal.(["a", "b", "c"])
    nodes = P.ControlBlock[P.Integrator(a, b, 0.5, 1.2, -1e8, 1e8), P.Mult(a, b, c),
        P.Div(a, b, c), P.Trig(a, b, :sin), P.Trig(a, b, :cos), P.Sqrt(a, b), P.Square(a, b),
        P.Delay(a, b, 200e-6, 21, 0.7), P.ArrayMerge([a, b], c), P.ArraySplit(a, b, 2)]
    canvas = P.lower!(P.CanvasPlan(), P.BlockGraph(nodes))
    primitive = filter(c -> c.defn != "master:datalabel", canvas.components)
    @test getfield.(primitive, :defn) == ["master:integral", "master:mult", "master:div",
        "master:trig", "master:trig", "master:sqrt", "master:square",
        "master:tdelay", "master:datamerge", "master:datatap"]
    @test Dict(primitive[1].params)["Yo"] == "1.2"
    @test Dict(primitive[1].params)["T"] == "0.5 [s]"
    @test Dict(primitive[8].params)["X0"] == "0.7"
    @test Dict(primitive[8].params)["Init"] == "1"
    @test Dict(primitive[9].params)["N"] == "2"
    @test Dict(primitive[10].params)["Index"] == "2"
    @test_throws ArgumentError P.lower!(P.CanvasPlan(), P.Trig(a, b, :tan), (72, 72))
    @test_throws ArgumentError P.lower!(P.CanvasPlan(), P.ArrayMerge([a], b), (72, 72))
    @test_throws ArgumentError P.lower!(P.CanvasPlan(), P.ArraySplit(a, b, 0), (72, 72))
    @test_throws ArgumentError P.lower!(
        P.CanvasPlan(), P.Integrator(
            a, b, "1/Ki", 0.0, -1e8, 1e8), (72, 72))
end

@testset "Butterworth decomposition" begin
    for order in 1:6
        filter = PI.measurement_filter_ss(PI.Butterworth(order = order, ωc = 500.0))
        for omega in (0.0, 10.0, 50.0, 500.0, 5000.0)
            s = im * omega
            cascade = prod(iszero(b) ? 1 / (1 + a * s / filter.ωc) :
                           (filter.ωc^2 / b) /
                           (s^2 + (a * filter.ωc / b) * s + filter.ωc^2 / b)
            for (a, b) in PI.BUTTERWORTH_TABLE[order])
            expected = only(filter.C * ((s * I - filter.A) \ filter.B) + filter.D)
            @test cascade ≈ expected
        end
    end
end

@testset "TLC solved-state modules and controller equations" begin
    for factory in (PSCADFixtures.tlc_case1_network, PSCADFixtures.tlc_case2_network)
        fixture = factory()
        pf = compute(PowerFlowProblem(fixture), ACDCPowerFlow())
        netlist = P.netlist(fixture, pf)
        e = only(filter(e -> e.model isa PI.TLC, netlist.elements))
        equilibrium = P.converter_equilibrium(e)
        residual = zeros(length(equilibrium.states))
        PI._state_space!(residual, collect(values(equilibrium.states)),
            collect(values(equilibrium.inputs)),
            equilibrium.terminal_pu, e.model, PI.Equil())
        @test maximum(abs, residual) <= 1e-6
        settings = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
            sample_step = 40e-6, source_ramp = 0.05)
        plan = P.build_plan(netlist; settings)
        @test length(plan.modules) == 9
        @test length(plan.lines) == 1
        @test length(unique(c.name for c in plan.probes.channels)) ==
              length(plan.probes.channels)
        @test Set(c.name for c in plan.probes.channels if startswith(c.name, "DUT_")) ==
              Set("DUT_" * n for n in ("P_ac_f", "Q_ac_f", "v_dc_f", "omega_c", "theta_c"))
        parent = only(filter(m -> startswith(m.name, "VSC_"), plan.modules))
        @test [(p.name, p.dim) for p in parent.ports if p.kind == :electrical] ==
              [("AC", 3), ("DC_P", 1), ("DC_N", 1)]
        @test Set(p.name for p in parent.ports if p.kind == :output) ==
              Set(("P_ac_f", "Q_ac_f", "v_dc_f", "omega_c", "theta_c"))
        @test count(c -> c.defn == "master:source_1", parent.canvas.components) == 3
        @test count(c -> c.defn == "master:resistor", parent.canvas.components) == 3
        @test count(c -> c.defn == "master:inductor", parent.canvas.components) == 3
        @test count(c -> c.defn == "master:src_ccin_1", parent.canvas.components) == 1
        @test Dict(only(filter(c -> c.defn == "master:voltmeter",
            parent.canvas.components)).params)["Name"] == "v_dc_m"
        @test count(c -> c.defn == "master:capacitor", parent.canvas.components) == 0
        clock_labels = Set((c.x, c.y) for c in parent.canvas.components
            if c.defn == "master:datalabel" && Dict(c.params)["Name"] == "dc_start_clock_s")
        guard_components = filter(parent.canvas.components) do c
            c.defn == "master:compare" ||
                (c.defn == "master:time-sig" && any(w ->
                    (c.x + 36, c.y) in w.vertices && any(p -> p in clock_labels, w.vertices),
                    parent.canvas.wires)) ||
                (c.defn == "master:datalabel" &&
                 Dict(c.params)["Name"] in ("dc_start_clock_s", "v_dc"))
        end
        guard_points = Set((c.x, c.y)
        for c in guard_components if c.defn == "master:datalabel")
        for c in guard_components
            c.defn == "master:datalabel" && continue
            union!(guard_points, first.(P.component_ports(c, Dict())))
        end
        guard_canvas = P.CanvasPlan(guard_components,
            filter(w -> all(p -> p in guard_points, w.vertices), parent.canvas.wires))
        guard = only(filter(c -> c.defn == "master:compare", guard_canvas.components))
        @test Dict(guard.params) ==
              Dict("X" => "0.2", "OL" => P.block_value(e.model.bases.v_dc),
            "OH" => "v_dc_m", "INTR" => "0", "Dim" => "1", "conv" => "0")
        @test count(c -> c.defn == "master:time-sig", guard_canvas.components) == 1
        guard_export = P.lower!(P.CanvasPlan(),
            P.BlockGraph(P.ControlBlock[P.Export("v_dc", P.Signal("v_dc"))]);
            origin = (1188, 396))
        append!(guard_canvas.components, guard_export.components)
        append!(guard_canvas.wires, guard_export.wires)
        startup = P.ModuleDefinitionPlan("DC_STARTUP", P.ModuleParameterPlan[],
            P.ModulePortPlan[], guard_canvas)
        for measured in (-20.0, 0.0, 0.8 * e.model.bases.v_dc,
            equilibrium.inputs.v_dc * e.model.bases.v_dc)
            for sample_time in (0.0, 0.05, 0.2 - settings.time_step)
                @test evaluate(startup, Dict("v_dc_m" => measured), sample_time)["v_dc"] ==
                      e.model.bases.v_dc
            end
            # The saved handover is timed, not a persistent voltage limiter.
            for sample_time in (0.2 + settings.time_step, 9.8)
                @test evaluate(startup, Dict("v_dc_m" => measured), sample_time)["v_dc"] ==
                      measured
            end
        end
        for definition in plan.modules
            imports = [Dict(c.params)["Name"]
                       for c in definition.canvas.components if c.defn == "master:import"]
            for parameter in definition.parameters
                @test count(==(parameter.name), imports) == 1
            end
            for c in definition.canvas.components
                if c.defn in ("master:datalabel", "master:import", "master:export")
                    @test !(lowercase(Dict(c.params)["Name"]) in P._EMTDC_RESERVED_SIGNALS)
                end
                if c.defn == "master:const"
                    @test tryparse(Float64, Dict(c.params)["Value"]) !== nothing
                end
                for (k, v) in c.params
                    k in ("G", "T", "T1", "T2", "Yo", "YO", "X0", "YHi", "YLo") || continue
                    @test v in [p.name for p in definition.parameters] || try
                        isfinite(P._pscad_number(replace(v, r"\s*\[[^\]]*\]\s*$" => "")))
                    catch
                        false
                    end
                end
            end
        end
        states, inputs, y = equilibrium.states, equilibrium.inputs, equilibrium.outputs
        phases = (0.0, -2π / 3, 2π / 3)
        signals = Dict{String, Any}(
            "v_abc" =>
                e.model.bases.v_ac .*
                collect(inputs.vG_d .* cos.(phases) .+ inputs.vG_q .* sin.(phases)),
            "i_abc" =>
                PowerImpedance.perunit(e.model.elec, e.model.bases).iACbase .*
                collect(states.i_d .* cos.(phases) .+ states.i_q .* sin.(phases)),
            "v_dc" => inputs.v_dc * e.model.bases.v_dc,
            "theta_c" => states.Δθ_pll, "theta_rel" => states.Δθ_pll)
        @test evaluate(startup, Dict("v_dc_m" => signals["v_dc"]),
            0.2 + settings.time_step)["v_dc"] == signals["v_dc"]
        meas = only(filter(d -> startswith(d.name, "MEAS_"), plan.modules))
        merge!(signals, evaluate(meas, signals))
        for n in ("vG_d_f", "vG_q_f", "i_d_f", "i_q_f", "P_ac_f", "Q_ac_f", "v_dc_f")
            @test isapprox(signals[n], getproperty(y.meas, Symbol(n)); atol = 1e-6, rtol = 1e-6)
        end
        pll = only(filter(d -> startswith(d.name, "PLL_"), plan.modules))
        merge!(signals, evaluate(pll, signals))
        @test signals["omega_c"] ≈ y.sync.ω_c
        @test signals["theta_c"] ≈ states.Δθ_pll
        active = only(filter(
            d -> startswith(d.name, "PCTRL_") ||
                 startswith(d.name, "VDCCTRL_"), plan.modules))
        merge!(signals, evaluate(active, signals))
        @test signals["i_d_ref"] ≈ y.pact.iΔ_d_ref
        reactive = only(filter(d -> startswith(d.name, "QCTRL_"), plan.modules))
        merge!(signals, evaluate(reactive, signals))
        @test signals["i_q_ref"] ≈ y.qact.q_ctrl_ref
        occ = only(filter(d -> startswith(d.name, "OCC_"), plan.modules))
        merge!(signals, evaluate(occ, signals))
        @test signals["vM_d_ref"] ≈ y.iloop.vMΔ_d_ref_c
        @test signals["vM_q_ref"] ≈ y.iloop.vMΔ_q_ref_c
        mod = only(filter(d -> startswith(d.name, "MOD_"), plan.modules))
        merge!(signals, evaluate(mod, signals))
        expected = 0.5inputs.v_dc * e.model.bases.v_ac .*
                   collect(y.mod.m_d .* cos.(phases) .+ y.mod.m_q .* sin.(phases))
        @test signals["vM_abc"] ≈ expected
        # A plant starting from rest still has finite control inputs/outputs:
        # both voltage divisions use the saved nominal-voltage start-up path.
        rest = Dict{String, Any}("v_abc" => zeros(3), "i_abc" => zeros(3),
            "v_dc" => evaluate(startup, Dict("v_dc_m" => 0.0))["v_dc"],
            "theta_c" => states.Δθ_pll, "theta_rel" => states.Δθ_pll)
        for definition in (meas, pll, active, reactive, occ, mod)
            outputs = evaluate(definition, rest)
            @test all(v -> v isa Number ? isfinite(v) : all(isfinite, v), values(outputs))
            merge!(rest, outputs)
        end
        @test rest["v_dc_f"] == 1.0
        # Isolate the electrical power calculation from its circuit components
        # and nested control instances. Station polarity is injection at DC_P;
        # the core electrical output is positive absorption from that pole.
        electrical = P.CanvasPlan(
            filter(c -> c.y >= 432 && c.x < 720, parent.canvas.components),
            filter(
                w -> all(p -> p[2] >= 432, w.vertices) &&
                     all(p -> p[1] < 720, w.vertices),
                parent.canvas.wires))
        export_canvas = P.lower!(P.CanvasPlan(),
            P.BlockGraph(P.ControlBlock[P.Export("dc_command", P.Signal("i_dc_cmd"))]);
            origin = (1800, 1728))
        append!(electrical.components, export_canvas.components)
        append!(electrical.wires, export_canvas.wires)
        dc_definition = P.ModuleDefinitionPlan("DC_BALANCE", P.ModuleParameterPlan[],
            P.ModulePortPlan[], electrical)
        startup_dc = P.ModuleDefinitionPlan("START_DC_BALANCE", P.ModuleParameterPlan[],
            P.ModulePortPlan[], P.CanvasPlan(
                vcat(startup.canvas.components, dc_definition.canvas.components),
                vcat(startup.canvas.wires, dc_definition.canvas.wires)))
        @test evaluate(startup_dc, Dict("v_dc_m" => 0.0,
            "vM_abc" => rest["vM_abc"], "i_abc" => zeros(3)))["dc_command"] == 0.0
        for direction in (1.0, -1.0)
            current_dq = (; i_d = direction * 0.4, i_q = direction * 0.1)
            physical_current = PowerImpedance.perunit(e.model.elec,
                e.model.bases).iACbase .* collect(
                current_dq.i_d .* cos.(phases) .+ current_dq.i_q .* sin.(phases))
            command = evaluate(dc_definition,
                Dict("vM_abc" => signals["vM_abc"],
                    "i_abc" => physical_current, "v_dc" => signals["v_dc"]))["dc_command"]
            core = PI.state_space!(zeros(2), current_dq,
                (; inputs, mod = y.mod), e.model.elec, e.model)
            absorption = core.i_dc * PowerImpedance.perunit(e.model.elec,
                e.model.bases).iDCbase
            @test command ≈ -absorption
            @test -signals["v_dc"] * command ≈
                  sum(signals["vM_abc"] .* physical_current)
        end
        # Directly verify the solved state identities used by PI and support
        # block initial values; they are generally nonzero at this operating point.
        params = Dict(p.name => p.default for p in occ.parameters)
        @test params["dI0"] == states.ξ_id
        @test params["qI0"] == states.ξ_iq
        @test Dict(p.name => p.default for p in pll.parameters)["pllI0"] == states.ξ_pll
        @test Dict(p.name => p.default for p in reactive.parameters)["qI0"] == states.ξ_Q_ac
        @test_throws ArgumentError P.converter_filter!(
            P.BlockGraph(), P.ModuleParameterPlan[], P.Signal("a"), P.Signal("b"),
            PI.Chebyshev(), (), states, 0.0, e)
        @test_throws ArgumentError P.converter_active("unsupported", e, equilibrium, PI.NoOuterActiveControl())
        # Both representations retain the same converter rating and flow signs.
        solved = NetworkBuilder.solve(fixture)
        builder = P.netlist(fixture, solved)
        # Independent power-flow solves agree at the existing equilibrium
        # solver's absolute tolerance, including the near-zero case-1 P.
        @test abs(builder.operating_point.branch_flows[:DUT].pt -
                  netlist.operating_point.branch_flows[:DUT].pt) <= 1e-6
        @test abs(builder.operating_point.branch_flows[:DUT].qt -
                  netlist.operating_point.branch_flows[:DUT].qt) <= 1e-6
    end
end
end
