module PSCADConverterTimingTests
import ..PSCADFixtures
using Test, PowerImpedance
using ..PSCADFixtures
using ..PSCADTLCTests: evaluate
const P = PowerImpedance.PSCAD

function wire_signal(canvas, pin)
    labels = Dict((c.x, c.y) => Dict(c.params)["Name"]
        for c in canvas.components if c.defn == "master:datalabel")
    wire = only(filter(w -> pin in w.vertices, canvas.wires))
    return labels[only(filter(!=(pin), wire.vertices))]
end

@testset "Converter phase boundaries and coherent angle snapshots" begin
    for factory in (PSCADFixtures.tlc_case2_network, PSCADFixtures.mmc_pq_network,
        PSCADFixtures.mmc_gfm_network, PSCADFixtures.mmc_compensated_network)
        network = factory()
        list = P.netlist(network, compute(PowerFlowProblem(network), ACDCPowerFlow()))
        e = only(filter(e -> e.name == :DUT, list.elements))
        eq = P.converter_equilibrium(e)
        gfm = e.model.sync isa PowerImpedance.VSEWithDamping
        # Deliberately displace both frame angles. A fresh synchronization
        # output must not change this evaluation's acquisition/inverse frame.
        states = gfm ? merge(eq.states, (; Δθ_VSM = -0.17, Δθ_pll = 0.31)) :
                 merge(eq.states, (; Δθ_pll = 0.31))
        canvas = P.CanvasPlan()
        P.converter_angle_snapshot!(canvas, e, merge(eq, (; states)); origin = (72, 72))
        outputs = gfm ? ["theta_c", "theta_rel", "theta_pll_rel"] : ["theta_c", "theta_rel"]
        P.lower!(canvas, P.BlockGraph(P.ControlBlock[P.Export(n, P.Signal(n)) for n in outputs]);
            origin = (864, 72))
        definition = P.ModuleDefinitionPlan("ANGLE", P.ModuleParameterPlan[], P.ModulePortPlan[], canvas)
        for time in (0.0, 0.001, 0.2)
            measured = evaluate(definition,
                Dict("theta_rel_next" => 1.23, "theta_pll_rel_next" => -2.34), time)
            relative = gfm ? -0.17 : 0.31
            @test measured["theta_rel"] == relative
            @test measured["theta_c"] ≈ time * e.model.bases.omega + relative
            gfm && @test measured["theta_pll_rel"] == 0.31
        end
        plan = P.build_plan(list)
        parent = only(filter(d -> startswith(d.name, "MMC_") || startswith(d.name, "VSC_"), plan.modules))
        selectors = filter(c -> c.defn == "master:zminusone", parent.canvas.components)
        @test length(selectors) == (gfm ? 2 : 1) + (e.model isa PowerImpedance.MMC ? 6 : 0)
        for selector in selectors
            @test P.component_ports(selector, Dict()) ==
                [((selector.x - 36, selector.y), :signal, :input),
                    ((selector.x + 36, selector.y), :signal, :output)]
            @test Dict(selector.params)["Type"] == "2"
            @test Dict(selector.params)["Init"] == "1"
        end
        e.model isa PowerImpedance.MMC || continue
        @test all(!startswith(d.name, "ARM_") for d in plan.modules)
        transfers = Dict(wire_signal(parent.canvas, (c.x + 36, c.y)) =>
            (c.defn, wire_signal(parent.canvas, (c.x - 36, c.y)))
            for c in parent.canvas.components
            if c.defn in ("master:force_dsout", "master:force_dsdyn"))
        @test transfers["iS_abc"] == ("master:force_dsdyn", "iS_solved_abc")
        @test transfers["i_dc_si"] == ("master:force_dsdyn", "i_dc_solved_si")
        # Evaluate the actual aggregate subgraph with unequal phase/arm
        # currents; an asymmetric time-level or missing half factor is visible.
        components = filter(parent.canvas.components) do c
            c.defn == "master:datalabel" && return true
            c.defn in ("master:force_dsout", "master:force_dsdyn", "master:sumjct",
                "master:gain", "master:datamerge") || return false
            pin = c.defn == "master:datamerge" ?
                (c.x, c.y + 18 * (parse(Int, Dict(c.params)["N"]) - 3)) : (c.x + 36, c.y)
            name = wire_signal(parent.canvas, pin)
            return startswith(name, "iS_") || startswith(name, "i_dc_") ||
                startswith(name, "i_u_solved_") || startswith(name, "i_l_solved_")
        end
        aggregate = P.CanvasPlan(components, copy(parent.canvas.wires))
        P.lower!(aggregate, P.BlockGraph(P.ControlBlock[P.Export(n, P.Signal(n))
            for n in ("iS_abc", "i_dc_si")]); origin = (9000, 72))
        definition = P.ModuleDefinitionPlan("CURRENTS", P.ModuleParameterPlan[], P.ModulePortPlan[], aggregate)
        result = evaluate(definition, Dict("i_u_a" => 12.0, "i_l_a" => -2.0,
            "i_u_b" => 9.0, "i_l_b" => 3.0, "i_u_c" => -4.0, "i_l_c" => 8.0))
        @test result["iS_abc"] == [5.0, 6.0, 2.0]
        @test result["i_dc_si"] == 13.0
        # Explicit state-history cuts publish the physical capacitor level held during the
        # preceding solve instead of a prior copy of that measurement. Phase transfers
        # alone allow the compiler to cut selected reconstructions after SIGMA/compensated
        # MOD.
        outputs = ["v_Cmeas_" * half * "_" * phase
            for half in ("u", "l") for phase in ("a", "b", "c")]
        cap_selectors = filter(selectors) do c
            startswith(wire_signal(parent.canvas, (c.x + 36, c.y)), "v_Cmeas_")
        end
        @test length(cap_selectors) == 6
        components = filter(parent.canvas.components) do c
            c.defn == "master:datalabel" || c in cap_selectors
        end
        acquired = P.CanvasPlan(components, copy(parent.canvas.wires))
        P.lower!(acquired, P.BlockGraph(P.ControlBlock[P.Export(n, P.Signal(n)) for n in outputs]);
            origin = (9000, 504))
        definition = P.ModuleDefinitionPlan("CAPACITORS", P.ModuleParameterPlan[], P.ModulePortPlan[], acquired)
        initial = Dict(wire_signal(acquired, (c.x + 36, c.y)) =>
            parse(Float64, Dict(c.params)["InitR"]) for c in cap_selectors)
        held = copy(initial)
        completed = Dict(replace(n, "v_Cmeas_" => "v_Ctot_") => v for (n, v) in initial)
        for (step, deviation) in enumerate((0.0, -11.0, 7.5, -3.0))
            # A later DSDYN state update must not leak into any consumer in
            # this pass. Unequal arms expose both a mixed set and a second hold.
            future = Dict(n => v + i * deviation
                for (i, (n, v)) in enumerate(sort!(collect(completed))))
            result = evaluate(definition, future; snapshots = held)
            for n in outputs
                @test result[n] == completed[replace(n, "v_Cmeas_" => "v_Ctot_")]
            end
            for c in cap_selectors
                input = wire_signal(acquired, (c.x - 36, c.y))
                output = wire_signal(acquired, (c.x + 36, c.y))
                # The master selector commits the applied physical state at
                # the end of DSDYN. DSOUT observes that same unchanged state.
                held[output] = future[input]
            end
            completed = copy(future)
        end
        for definition in plan.modules
            instance = findfirst(c -> c.defn == plan.name * ":" * definition.name,
                parent.canvas.components)
            instance === nothing && continue
            c = parent.canvas.components[instance]
            for port in definition.ports
                port.kind == :input && startswith(port.name, "v_Ctot_") || continue
                @test wire_signal(parent.canvas, (c.x + port.x, c.y + port.y)) ==
                    replace(port.name, "v_Ctot_" => "v_Cmeas_")
            end
        end
        for half in ("u", "l"), phase in ("a", "b", "c")
            stem = half * "_" * phase
            pairs = Dict(wire_signal(parent.canvas, (c.x + 36, c.y)) =>
                (c.defn, wire_signal(parent.canvas, (c.x - 36, c.y)))
                for c in parent.canvas.components
                if c.defn in ("master:force_dsout", "master:force_dsdyn"))
            @test pairs[stem * "_applied_insertion"] == ("master:force_dsout", "m_" * stem)
            @test pairs[stem * "_solved_current"] == ("master:force_dsout", "i_" * stem)
            snapshot = only(filter(c -> wire_signal(parent.canvas, (c.x + 36, c.y)) ==
                "v_Cmeas_" * stem, cap_selectors))
            @test wire_signal(parent.canvas, (snapshot.x - 36, snapshot.y)) == "v_Ctot_" * stem
            integrator = only(filter(c -> c.defn == "master:integral" &&
                wire_signal(parent.canvas, (c.x + 36, c.y)) == "v_Ctot_" * stem,
                parent.canvas.components))
            @test Dict(snapshot.params)["InitR"] == Dict(integrator.params)["Yo"]
            @test pairs[stem * "_cap_rate"] == ("master:force_dsdyn", stem * "_cap_rate_out")
            @test pairs["i_" * half * "_solved_" * phase] == ("master:force_dsout", "i_" * stem)
            source = only(filter(c -> c.defn == "master:source_1" &&
                Dict(c.params)["Name"] == stem * "_arm_source", parent.canvas.components))
            @test wire_signal(parent.canvas, (source.x, source.y + 36)) == stem * "_arm_voltage"
            product = only(filter(c -> c.defn == "master:mult" &&
                wire_signal(parent.canvas, (c.x + 36, c.y)) == stem * "_arm_voltage", parent.canvas.components))
            @test wire_signal(parent.canvas, (product.x - 36, product.y)) == "m_" * stem
            @test wire_signal(parent.canvas, (product.x, product.y + 36)) == "v_Ctot_" * stem
        end
    end
end
end
