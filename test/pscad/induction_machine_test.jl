module PSCADInductionMachineTests
import ..PSCADFixtures
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures: im_network
using ..PSCADMachineTests: components, parameters, pin_signal, parameter_import
using ..PSCADResultsTests: synthetic_result, add_three_phase!
const P = PowerImpedance.PSCAD

function torque_from_blocks(definition, speed)
    values = Dict(p.name => p.default for p in definition.parameters)
    signals = Dict{String, Float64}()
    for c in definition.canvas.components
        p = Dict(c.params)
        if c.defn == "master:import"
            any(w -> (c.x + 36, c.y) in w.vertices, definition.canvas.wires) || continue
            signals[pin_signal(definition.canvas, (c.x + 36, c.y))] =
                p["Name"] == "speed" ? speed : values[p["Name"]]
        elseif c.defn == "master:const"
            signals[pin_signal(definition.canvas, (c.x + 36, c.y))] = parse(Float64, p["Value"])
        elseif c.defn in ("master:gain", "master:square", "master:mult", "master:div", "master:sumjct")
            input = signals[pin_signal(definition.canvas, (c.x - 36, c.y))]
            result = if c.defn == "master:gain"
                input * values[p["G"]]
            elseif c.defn == "master:square"
                input^2
            elseif c.defn == "master:mult"
                input * signals[pin_signal(definition.canvas, (c.x, c.y + 36))]
            elseif c.defn == "master:div"
                input / signals[pin_signal(definition.canvas, (c.x, c.y + 36))]
            else
                input + signals[pin_signal(definition.canvas, (c.x, c.y + 36))] +
                    signals[pin_signal(definition.canvas, (c.x, c.y - 36))]
            end
            signals[pin_signal(definition.canvas, (c.x + 36, c.y))] = result
        end
    end
    export_block = only(components(definition.canvas, "export"))
    return signals[pin_signal(definition.canvas, (export_block.x + 36, export_block.y))]
end

@testset "PSCAD induction-machine load torque" begin
    for m in (-5, -2, -1, 0, 1, 2, 3, 8)
        mech = MechanicalIM(T_0 = 0.73, A = 0.27, B = -0.13, C = 0.84, m = m)
        definition = P.induction_load_torque("LOAD_test", mech)
        for speed in (0.72, 0.99, 1.12)
            @test torque_from_blocks(definition, speed) ≈
                  0.73 * (0.27 * speed^m - 0.13 * speed + 0.84)
        end
        @test P.check_connectivity(definition.canvas, "LOAD_test") === nothing
        for name in ("T_0", "A", "B", "C")
            @test Dict(parameter_import(definition.canvas, name).params)["Name"] == name
        end
    end
    constant = P.induction_load_torque("LOAD_constant",
        MechanicalIM(T_0 = 0.9, A = 0.0, B = 0.0, C = 1.0, m = 0))
    @test torque_from_blocks(constant, 0.0) == 0.9
    @test torque_from_blocks(constant, 1.2) == 0.9
end

@testset "PSCAD induction-machine plan and equilibrium" begin
    state = im_network()
    solved = NetworkBuilder.solve(state)
    state_nl = P.netlist(state, solved)
    list = state_nl
    xml = read(joinpath(@__DIR__, "fixtures/im_saved_fragments.xml"), String)
    reference = Dict(m.captures[1] => m.captures[2]
        for m in eachmatch(r"<param name=\"([^\"]+)\" value=\"([^\"]*)\"", xml))
    @test length(reference) == 81
    for nl in (state_nl,)
        plan = P.build_plan(nl)
        e = only(filter(e -> e.name == :im1, nl.elements))
        flow = nl.operating_point.branch_flows[:im1]
        states = NamedTuple{PowerImpedance.statenames(e.model)}(
            Tuple(steady_state(e.model, e.values)))
        @test flow.pf ≈ e.values.ac.p
        @test flow.qf ≈ e.values.ac.q
        @test abs(flow.pf - 915.754) / e.model.elec.S_base < 0.01
        @test abs(flow.qf - 881.512) / e.model.elec.S_base < 0.01
        @test 0.97 < flow.speed_pu == states.ω_r < 1.0
        machine = parameters(plan.main, "wound_rotor")
        @test Set(keys(machine)) == Set(keys(reference))
        @test machine["Pbase"] == "1000.0 [MVA]"
        @test machine["Vbase"] == "220.0 [kV]"
        @test machine["OMEG"] == P.pscad_value(100π; unit = "rad/s")
        @test machine["J"] == "8.0 [s]"
        @test (machine["R1"], machine["R2"], machine["Xmd"], machine["Xa"], machine["Xkd1"]) ==
              ("0.01 [pu]", "0.01 [pu]", "1.66 [pu]", "0.15 [pu]", "0.165 [pu]")
        @test (machine["Spd"], machine["Tel"], machine["TmOp"]) ==
              ("im1_speed", "im1_Te", "im1_Tm")
        # Compare all other numerical fields with the independently saved instance.
        mapped = Set(["Name", "Pbase", "Vbase", "OMEG", "J", "Spd", "Tel", "TmOp"])
        for key in setdiff(Set(keys(reference)), mapped)
            if isempty(reference[key])
                @test isempty(machine[key])
            else
                @test parse(Float64, first(split(machine[key]))) ==
                      parse(Float64, first(split(reference[key])))
            end
        end
        initial = only(filter(c -> pin_signal(plan.main, (c.x + 36, c.y)) == "im1_speed0",
            components(plan.main, "const")))
        @test Dict(initial.params)["Value"] == P.pscad_value(states.ω_r)
        transfer = parameters(plan.main, "compare")
        @test transfer == Dict("X" => "0.2", "OL" => "1", "OH" => "0", "INTR" => "0",
            "Dim" => "1", "conv" => "1")
        component = only(components(plan.main, "wound_rotor"))
        @test P.component_ports(component, Dict()) == [
            ((component.x + 54, component.y), :electrical, :electrical),
            ((component.x - 54, component.y - 36), :signal, :input),
            ((component.x - 54, component.y), :signal, :input),
            ((component.x - 54, component.y + 36), :signal, :input)]
        @test pin_signal(plan.main, (component.x - 54, component.y - 36)) == "im1_speed0"
        @test pin_signal(plan.main, (component.x - 54, component.y)) == "im1_speed_control"
        @test pin_signal(plan.main, (component.x - 54, component.y + 36)) == "im1_load_torque"
        current = only(filter(c -> c.name == "I_im1_ac", plan.probes.channels))
        @test current.orientation == :into
        load = only(plan.modules)
        @test torque_from_blocks(load, states.ω_r) == 0.9
        @test states.Ψ_df * states.i_q - states.Ψ_qf * states.i_d ≈ 0.9
        @test P.check_connectivity(plan) === nothing
        @test Set(c.kind for c in plan.probes.channels if c.element == "im1") ==
              Set([:current, :machine_speed, :machine_diagnostic])
    end
    @test_throws r"requires solved operating-point data" P.build_plan(P.netlist(state, nothing))
    # Series transformer terms enter the same stator coefficients in Julia's equations.
    e = only(filter(e -> e.name == :im1, list.elements))
    modified = InductionMachine(;
        elec = ElectricalIM(r_s = 0.023, rt = 0.017, l_sl = 0.21,
            lt = 0.04, r_r = 0.031, l_rl = 0.19, l_m = 1.72),
        mech = MechanicalIM(H = 5.0))
    changed = copy(list.elements)
    changed[findfirst(x -> x.name == :im1, changed)] = P.NetlistElement(e.name, e.pscad,
        modified, electricalconnections(modified), e.terminals, e.role, e.values)
    nl = P.Netlist(list.buses, changed, list.operating_point,
        list.voltageBase, list.frequency)
    fields = parameters(P.build_plan(nl).main, "wound_rotor")
    @test (fields["R1"], fields["Xa"], fields["R2"], fields["Xkd1"], fields["Xmd"], fields["J"]) ==
          ("0.04 [pu]", "0.25 [pu]", "0.031 [pu]", "0.19 [pu]", "1.72 [pu]", "10.0 [s]")
end

@testset "PSCAD induction-machine terminal comparison" begin
    classic = im_network()
    nl = P.netlist(classic, compute(PowerFlowProblem(classic), ACDCPowerFlow()))
    plan = P.build_plan(nl)
    model = PSCADModel("im.pscx", "im", nl, plan.probes,
        P.SimulationSettings(), nl.operating_point, (;))
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    flow = nl.operating_point.branch_flows[:im1]
    for c in plan.probes.channels
        bus = only(filter(b -> b.name == c.bus, nl.buses))
        voltage = bus.vm_pu * bus.base_kV * cis(bus.va_rad)
        if c.kind == :voltage
            add_three_phase!(channels, c.name, times, sqrt(2) * voltage)
        elseif c.kind == :current
            f = nl.operating_point.branch_flows[Symbol(c.element)]
            power = c.element == "g1" ? complex(f.pg, f.qg) :
                    c.port in (:side1, :ac, :dc) ? complex(f.pf, f.qf) :
                    -complex(f.pt, f.qt)
            add_three_phase!(channels, c.name, times, sqrt(2) * conj(power / (3voltage)))
        else
            channels[c.name] = fill(c.kind == :machine_speed ? flow.speed_pu : -123.0,
                length(times))
        end
    end
    table = compare_operating_point(synthetic_result(times, channels), model)
    @test propertynames(table) ==
          (:quantity, :name, :pscad, :powerflow, :error, :settling, :within_tolerance)
    @test all(table.within_tolerance)
    @test maximum(table.settling) < 1e-10
    @test Set(table.quantity) == Set([:voltage_rms, :voltage_angle, :current_rms,
        :machine_p, :machine_q, :machine_speed])
    for (quantity, expected) in ((:machine_p, flow.pf), (:machine_q, flow.qf))
        row = only(filter(r -> r.quantity == quantity, table))
        @test row.name == "I_im1_ac"
        @test row.pscad ≈ expected
        @test row.powerflow == expected
        @test row.error < 1e-10
    end
    @test only(filter(r -> r.quantity == :machine_speed, table)).powerflow == flow.speed_pu
    # Internal torque outputs cannot change acceptance or become required channels.
    diagnostic_free = copy(channels)
    delete!(diagnostic_free, "im1_Te")
    delete!(diagnostic_free, "im1_Tm")
    @test compare_operating_point(synthetic_result(times, diagnostic_free), model) == table
    bus = only(filter(b -> b.name == "machine_", nl.buses))
    voltage = bus.vm_pu * bus.base_kV * cis(bus.va_rad)
    for offset in (9.0, -9.0, 11.0, -11.0)
        measured = deepcopy(channels)
        power = complex(flow.pf + offset, flow.qf + offset)
        add_three_phase!(measured, "I_im1_ac", times, sqrt(2) * conj(power / (3voltage)))
        changed = compare_operating_point(synthetic_result(times, measured), model)
        for quantity in (:machine_p, :machine_q)
            row = only(filter(r -> r.quantity == quantity, changed))
            @test row.error ≈ abs(offset) / 1000
            @test row.settling < 1e-10
            @test row.within_tolerance == (abs(offset) < 10)
        end
    end
    for offset in (0.0009, -0.0009, 0.0011, -0.0011)
        measured = deepcopy(channels)
        measured["im1_speed"] .= flow.speed_pu + offset
        row = only(filter(r -> r.quantity == :machine_speed,
            compare_operating_point(synthetic_result(times, measured), model)))
        @test row.error ≈ abs(offset)
        @test row.settling < 1e-12
        @test row.within_tolerance == (abs(offset) < 1e-3)
    end
    # Opposite changes in the window halves preserve the full-window reference.
    for (change, accepted) in ((0.0009, true), (0.0011, false))
        measured = deepcopy(channels)
        for (ending, offset) in ((false, -500change), (true, 500change))
            half = findall(t -> (t > 0.2) == ending, times)
            power = complex(flow.pf + offset, flow.qf + offset)
            current = sqrt(2) * conj(power / (3voltage))
            for index in 1:3
                measured["I_im1_ac:$index"][half] =
                    real.(current .* cis.(2π * 50 .* times[half] .- 2π * (index - 1) / 3))
            end
        end
        result = synthetic_result(times, measured)
        changed = compare_operating_point(result, model)
        relaxed = compare_operating_point(result, model; settling_fraction = 0.2)
        for quantity in (:machine_p, :machine_q)
            row = only(filter(r -> r.quantity == quantity, changed))
            @test row.error < 1e-10
            @test row.settling ≈ change
            @test row.within_tolerance == accepted
            @test only(filter(r -> r.quantity == quantity, relaxed)).within_tolerance
        end
    end
    for (change, accepted) in ((0.9e-4, true), (1.1e-4, false))
        measured = deepcopy(channels)
        measured["im1_speed"] = flow.speed_pu .+
                                ifelse.(times .<= 0.2, -change / 2, change / 2)
        result = synthetic_result(times, measured)
        row = only(filter(r -> r.quantity == :machine_speed,
            compare_operating_point(result, model)))
        @test row.powerflow == flow.speed_pu
        @test row.error < 1e-12
        @test row.settling ≈ change
        @test row.within_tolerance == accepted
        @test only(filter(r -> r.quantity == :machine_speed,
            compare_operating_point(result, model; settling_fraction = 0.2))).within_tolerance
    end
    for name in ("im1_speed", "I_im1_ac:3", "V_machine_:2")
        incomplete = copy(channels)
        delete!(incomplete, name)
        @test_throws ArgumentError compare_operating_point(synthetic_result(times, incomplete), model)
    end
end
end
