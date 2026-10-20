module PSCADMMCModeTests
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures, ..PSCADTopology
using ..PSCADTLCTests: evaluate
using ..PSCADResultsTests: synthetic_result, add_three_phase!
const PI = PowerImpedance
const P = PI.PSCAD
const SETTINGS = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 250e-6, source_ramp = 0.0)

function diagnostic(definition, names)
    canvas = deepcopy(definition.canvas)
    P.lower!(canvas, P.BlockGraph(P.ControlBlock[P.Export(n, P.Signal(n)) for n in names]);
        origin = (15984, 108))
    return P.ModuleDefinitionPlan(definition.name, definition.parameters, definition.ports, canvas)
end

@testset "converter-control MMC modes and TLC VAC" begin
    for factory in (PSCADFixtures.mmc_vdc_network, PSCADFixtures.mmc_pf_network,
        PSCADFixtures.mmc_qv_network, PSCADFixtures.mmc_vac_network, PSCADFixtures.tlc_vac_network)
        fixture = factory()
        pairs_of_parameters = []
        for network in (fixture.classic, fixture.state)
            pf = network isa Network ? power_flow(network) :
                 NetworkBuilder.solve(network).powerflow
            list = P.netlist(network, pf)
            plan = P.build_plan(list; settings = SETTINGS)
            @test P.check_connectivity(plan) === nothing
            modules = Dict(m.name => m for m in plan.modules)
            for (name, graph) in [("Main",
                                      PSCADTopology.electrical_graph(plan.main, modules));
                                  [(d.name,
                                       PSCADTopology.electrical_graph(d.canvas, modules))
                                   for d in plan.modules]]
                @test PSCADTopology.check_degrees(graph, name) === nothing
            end
            @test length(unique(lowercase(c.name) for c in plan.probes.channels)) ==
                  length(plan.probes.channels)
            e = only(filter(e -> e.name == :DUT, list.elements))
            m = e.model
            eq = P.converter_equilibrium(e)
            residual = zeros(length(eq.states))
            PI._state_space!(residual, collect(values(eq.states)),
                collect(values(eq.inputs)), eq.setpoint_pu, m, PI.Equil())
            @test maximum(abs, residual) <= 1e-6
            @test eq.outputs.meas.Q_ac_f ≈ eq.setpoint_pu.q_ac atol=1e-6
            active = m isa PI.MMC ? m.delta_control.outer_active : m.outerActive
            reactive = m isa PI.MMC ? m.delta_control.outer_reactive : m.outerReactive
            active_name = active isa PI.OuterActiveVdcControl ? "VDCCTRL_DUT" : "PCTRL_DUT"
            parameters = Dict(p.name => p.default for p in modules["QCTRL_DUT"].parameters)
            push!(pairs_of_parameters,
                [(d.name, [(p.name, p.default) for p in d.parameters])
                 for d in plan.modules])
            if reactive isa PI.OuterReactiveVacControl
                @test parameters["vacI0"] == eq.states.ξ_v_ac
                @test parameters["vac_reference"] ==
                      eq.setpoint_pu.v_ac * PI.voltage_filter_ratio(m)
                @test abs(eq.states.ξ_v_ac) > 0
            elseif reactive.support isa PI.VoltageSupportLag
                @test parameters["vac_reference"] ==
                      eq.setpoint_pu.v_ac * PI.voltage_filter_ratio(m)
                @test parameters["support0"] == eq.states.ξ_vac_supp
            end
            if active isa PI.OuterActiveVdcControl
                @test !any(
                    e -> e.model isa PI.Source &&
                         any(t -> !t.grounded && t.bus.domain == 2, e.terminals),
                    list.elements)
                @test count(e -> e.model isa PI.MMC, list.elements) == 2
                @test Dict(p.name => p.default for p in modules[active_name].parameters)["vdcI0"] ==
                      eq.states.ξ_v_dc
            end
            # Both outer loops receive meter inputs equal to zero immediately, including
            # VAC Q and Vdc feedback; only the measured-DC divisor retains its solved
            # value.
            if m isa PI.MMC
                measured = evaluate(modules["MEAS_DUT"],
                    Dict{String, Any}(
                        "v_abc" => zeros(3), "i_abc" => zeros(3), "v_dc" => 0.0,
                        "i_dc_si" => 0.0, "theta_c" => 0.0, "theta_rel" => 0.0),
                    0.1)
                @test measured["Q_ac_f"] == measured["P_ac_f"] == measured["v_dc_f"] == 0.0
                @test measured["v_dc_divisor"] ≈ eq.outputs.meas.v_dc_f atol=1e-6
                live_meas = NamedTuple{keys(eq.outputs.meas)}(ntuple(_ -> 0.0, length(eq.outputs.meas)))
                @test evaluate(modules[active_name], merge(measured, Dict("omega_c" => 1.0)))["i_d_ref"] ≈
                      PI.state_space!(zeros(PI.n_states(active)), eq.states,
                    (; meas = live_meas, sync = (; ω_c = 1.0)), eq.setpoint_pu, active, m).iΔ_d_ref atol=1e-6
                @test evaluate(modules["QCTRL_DUT"], measured)["i_q_ref"] ≈
                      PI.state_space!(zeros(PI.n_states(reactive)), eq.states,
                    (; meas = live_meas), eq.setpoint_pu, reactive, m).q_ctrl_ref atol=1e-6
            end
            # Every converter accepts the same source-ramp setting. Only Main
            # source Tc changes; control initial states and the hold are fixed.
            for ramp in (P.SimulationSettings().source_ramp, 0.1)
                ramp_settings = P.SimulationSettings(simulation_time = 10.0,
                    time_step = 10e-6, sample_step = 250e-6, source_ramp = ramp)
                ramp_plan = P.build_plan(list; settings = ramp_settings)
                @test P.check_connectivity(ramp_plan) === nothing
                @test all(Dict(c.params)["Tc"] ==
                    (startswith(get(Dict(c.params), "Name", ""), "precharge_") ?
                     "0.0 [s]" : P.pscad_value(ramp; unit = "s"))
                for c in ramp_plan.main.components
                if c.defn in ("master:source_1", "master:source_3"))
                @test [(d.name, [(p.name, p.default) for p in d.parameters],
                           [(c.defn, c.params, c.x, c.y, c.orient)
                            for c in d.canvas.components],
                           [w.vertices for w in d.canvas.wires]) for d in ramp_plan.modules] ==
                      [(d.name, [(p.name, p.default) for p in d.parameters],
                           [(c.defn, c.params, c.x, c.y, c.orient)
                            for c in d.canvas.components],
                           [w.vertices for w in d.canvas.wires]) for d in plan.modules]
            end
            # The emitted PI outputs and rates are compared with the native equations at
            # deliberately displaced voltage, power and frequency inputs.
            for factor in (0.91, 1.07)
                meas = merge(eq.outputs.meas,
                    (; vG_d_f = factor * eq.outputs.meas.vG_d_f,
                        vG_q_f = -0.13, v_dc_f = factor, P_ac_f = 0.47, Q_ac_f = -0.18))
                sync = (; ω_c = factor)
                inputs = (; meas, sync)
                signals = Dict{String, Any}(string(k) => v for (k, v) in pairs(meas))
                signals["omega_c"] = factor
                F = zeros(PI.n_states(active))
                owned = PI.state_space!(F, eq.states, inputs, eq.setpoint_pu, active, m)
                rate = active isa PI.OuterActiveVdcControl ? "vdcrate" : "prate"
                emitted = evaluate(diagnostic(modules[active_name], [rate]), signals)
                @test emitted["i_d_ref"] ≈ owned.iΔ_d_ref atol=1e-6
                @test emitted[rate] ≈ F[end] atol=1e-6
                if active isa PI.OuterActivePowerControl &&
                   active.support isa PI.FrequencySupportLag
                    pars = Dict(p.name => p.default
                    for p in modules[active_name].parameters)
                    @test (pars["supportK"] * (factor - 1) - pars["support0"]) /
                          pars["supportT"] ≈ F[1] atol=1e-6
                end
                F = zeros(PI.n_states(reactive))
                owned = PI.state_space!(F, eq.states, inputs, eq.setpoint_pu, reactive, m)
                rate = reactive isa PI.OuterReactiveVacControl ? "vacrate" : "qrate"
                names = reactive isa PI.OuterReactiveQControl &&
                        reactive.support isa PI.VoltageSupportLag ?
                        [rate, "vac_error"] : [rate]
                emitted = evaluate(diagnostic(modules["QCTRL_DUT"], names), signals)
                @test emitted["i_q_ref"] ≈ owned.q_ctrl_ref atol=1e-6
                @test emitted[rate] ≈ F[end] atol=1e-6
                if length(names) == 2
                    @test (parameters["supportK"] * emitted["vac_error"] -
                           parameters["support0"]) / parameters["supportT"] ≈ F[1] atol=1e-6
                end
            end
            # The existing comparison rows must use each mode's solved Q/Vdc.
            probes = P.ProbeManifest(
                filter(c -> c.element == "DUT" && c.kind != :converter_diagnostic,
                    plan.probes.channels),
                plan.probes.reference_bus)
            append!(probes.channels, filter(c -> c.kind == :voltage && c.dim == 3, plan.probes.channels))
            model = PSCADModel("synthetic.pscx", "synthetic", list, probes, SETTINGS,
                list.operating_point, (; source = :fixture))
            times = collect(0.0:250e-6:0.3)
            channels = PI.OrderedDict{String, Vector{Float64}}()
            flow = list.operating_point.branch_flows[:DUT]
            dc = only(filter(t -> t.side == 1 && !t.grounded, e.terminals))
            dbus = only(filter(b -> b.key == dc.bus, list.buses))
            vdc = 2dbus.base_kV * list.operating_point.bus_states[dc.bus].vm_pu
            ac = only(filter(t -> t.side == 2, e.terminals))
            abus = only(filter(b -> b.key == ac.bus, list.buses))
            apoint = list.operating_point.bus_states[ac.bus]
            voltage = sqrt(2) * abus.base_kV * apoint.vm_pu * cis(apoint.va_rad)
            for c in probes.channels
                if c.kind == :voltage
                    b = only(filter(b -> b.name == c.bus, list.buses))
                    point = list.operating_point.bus_states[b.key]
                    add_three_phase!(channels, c.name, times, sqrt(2)*b.base_kV*point.vm_pu*cis(point.va_rad))
                elseif c.kind == :current && c.side == "2"
                    add_three_phase!(channels, c.name, times, 2complex(flow.pt, -flow.qt)/(3conj(voltage)))
                else
                    value = c.kind == :converter_p ? flow.pt/m.elec.Sbase :
                            c.kind == :converter_q ? flow.qt/m.elec.Sbase :
                            c.kind == :converter_arm_voltage ? vdc :
                            c.kind == :converter_sum_current ? flow.pf/(3m.elec.Sbase) :
                            flow.pf/vdc
                    channels[c.name] = fill(value, length(times))
                end
            end
            table = compare_operating_point(synthetic_result(times, channels; probes), model)
            @test all(table.within_tolerance)
            @test count(==(:converter_q), table.quantity) == 2
            @test count(==(:converter_p), table.quantity) == 2
        end
        for (a, b) in zip(pairs_of_parameters...)
            @test first(a) == first(b)
            @test first.(last(a)) == first.(last(b))
        end
    end
end
end
