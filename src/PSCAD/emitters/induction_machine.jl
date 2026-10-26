function induction_load_torque(name, mech)
    parameters = [ModuleParameterPlan(string(key), getproperty(mech, key), "")
                  for key in (:T_0, :A, :B, :C)]
    speed, one, nonlinear, linear, constant, total, torque = Signal.([
        "speed", "one", "nonlinear", "linear", "constant", "total", "torque"])
    graph = BlockGraph(ControlBlock[Import("speed", speed), Const(one, 1.0)])
    # Integer powers use the existing product, square and division primitives.
    power, factor = one, speed
    exponent = mech.m < 0 ? -unsigned(mech.m) : unsigned(mech.m)
    index = 0
    while exponent > 0
        index += 1
        if isodd(exponent)
            if power === one
                power = factor
            else
                product = Signal("product_" * string(index))
                push!(graph.nodes, Mult(power, factor, product))
                power = product
            end
        end
        exponent >>= 1
        if exponent > 0
            squared = Signal("power_" * string(index))
            push!(graph.nodes, Square(factor, squared))
            factor = squared
        end
    end
    if mech.m < 0
        reciprocal = Signal("reciprocal")
        push!(graph.nodes, Div(one, power, reciprocal))
        power = reciprocal
    end
    append!(graph.nodes, ControlBlock[
        Gain(power, nonlinear, "A"), Gain(speed, linear, "B"),
        Import("C", constant), Sum([nonlinear, linear, constant], [1, 1, 1], total),
        Gain(total, torque, "T_0"), Export("Tm", torque)])
    ports = [ModulePortPlan("speed", :input, -54, 0),
        ModulePortPlan("Tm", :output, 54, 0)]
    return ModuleDefinitionPlan(name, parameters, ports, lower!(CanvasPlan(), graph))
end

function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.InductionMachine}, context)
    connected = filter(t -> !t.grounded, e.terminals)
    length(connected) == 1 ||
        throw(ArgumentError("induction machine :$(e.name) requires one connected AC terminal"))
    terminal = only(connected)
    bus = _ac_bus(e, terminal, context)
    machine, elec = e.model, e.model.elec
    isapprox(machine.bases.omega, 2π * context.settings.frequency; rtol = 1e-12) ||
        throw(ArgumentError("induction machine :$(e.name) frequency differs from the network frame"))
    flow = get(context.netlist.operating_point.branch_flows, e.name, nothing)
    flow !== nothing && haskey(flow, :speed_pu) ||
        throw(ArgumentError("induction machine :$(e.name) requires solved operating-point data"))
    speed = machine_probe!(state, e, bus, :machine_speed, "speed", "pu")
    electrical = machine_probe!(state, e, bus, :machine_diagnostic, "Te", "pu")
    mechanical = machine_probe!(state, e, bus, :machine_diagnostic, "Tm", "pu")
    initial, demand, transfer, time = Signal.([
        pscad_name(e.pscad * suffix; used = state.used)
        for suffix in ("_speed0", "_load_torque", "_speed_control", "_time")])
    params = ["Name" => e.pscad,
        "Pbase" => pscad_value(machine.bases.S; unit = "MVA"),
        "Vbase" => pscad_value(machine.Vac_base; unit = "kV"),
        "OMEG" => pscad_value(machine.bases.omega; unit = "rad/s"),
        # TRN is passed to INDUCMC2_CFG even with ERC=0. Retain the tested ratio.
        "TRN" => "1", "J" => pscad_value(2machine.mech.H; unit = "s"),
        "D" => "0.0 [pu]", "View" => "1", "ERC" => "0", "MM" => "0",
        "SNP" => "1", "Cage" => "0", "NCW" => "1", "Msat" => "0", "Lsat" => "0",
        # Julia includes rt/lt in its stator series impedance.
        "R1" => pscad_value(elec.r_s + elec.rt; unit = "pu"),
        "R2" => pscad_value(elec.r_r; unit = "pu"),
        "R3" => "0.298 [pu]", "R4" => "0.018 [pu]", "R5" => "0.018 [pu]",
        "Xmd" => pscad_value(elec.l_m; unit = "pu"),
        "Xa" => pscad_value(elec.l_sl + elec.lt; unit = "pu"),
        "Xkd1" => pscad_value(elec.l_rl; unit = "pu")]
    append!(params, [key => "0.05 [pu]" for key in ("Xkd2", "Xkd3", "Xkd4")])
    append!(params, [key => "0.02 [pu]"
                     for key in ("Xkd12", "Xkd13", "Xkd14", "Xkd23", "Xkd24", "Xkd34")])
    for (suffix, currents, voltages) in (
        ("M", (0.0, 0.5, 0.8, 1.0, 1.2, 1.5, 1.8, 2.2, 3.2, 4.2),
            (0.0, 0.5, 0.79, 0.947, 1.076, 1.2, 1.26, 1.32, 1.42, 1.5)),
        ("", (0.0, 1.196, 1.82, 2.861, 5.882, -1.0, -1.0, -1.0, -1.0, -1.0),
            (0.0, 0.286, 0.4, 0.564, 0.981, -1.0, -1.0, -1.0, -1.0, -1.0)))
        for i in eachindex(currents)
            push!(params, "I$(i)$suffix" => pscad_value(currents[i]; unit = "pu"),
                "V$(i)$suffix" => pscad_value(voltages[i]; unit = "pu"))
        end
    end
    append!(params, ["MSF" => "", "LSF" => "", "Spd" => speed.name,
        "Tel" => electrical.name, "TmOp" => mechanical.name, "ThetaR" => "",
        "Vwdg" => "0.3983 [kV]", "NpntsM" => "10", "NpntsL" => "10"])
    x, y = allocate_cell!(state.layout)
    point = (x + 144, y + 108)
    component!(state.main, "wound_rotor", point, params)
    inner = pscad_name(e.pscad * "_terminal"; used = state.used)
    stub!(state.main, (point[1] + 54, point[2]), inner)
    # Inputs are 36 pixels apart. Horizontal stubs keep them separate.
    for (dy, signal) in ((-36, initial), (0, transfer), (36, demand))
        port, label = (point[1] - 54, point[2] + dy), (point[1] - 90, point[2] + dy)
        wire!(state.main, port, label)
        component!(state.main, "datalabel", label, ["Name" => signal.name])
    end
    x, y = allocate_cell!(state.layout)
    current = current_probe!(state, e, terminal, context; orientation = :into)
    meter = (x + 126, y + 72)
    component!(state.main, "ammeter", meter, ["Name" => current])
    stub!(state.main, meter, only(_terminal_labels(e, terminal, context)); direction = -1)
    stub!(state.main, (meter[1] + 36, meter[2]), inner)
    output_probe!(state.main, current, "branch", "kA", (x + 126, y + 144))
    for block in ControlBlock[Const(initial, flow.speed_pu), TimeStep(time)]
        x, y = allocate_cell!(state.layout)
        lower!(state.main, block, (x + 126, y + 72))
    end
    x, y = allocate_cell!(state.layout)
    unary_block!(state.main, "compare", (x + 126, y + 72),
        ["X" => "0.2", "OL" => "1", "OH" => "0", "INTR" => "0", "Dim" => "1", "conv" => "1"],
        time, transfer)
    definition = induction_load_torque(pscad_name("LOAD_" * e.pscad; used = state.used), machine.mech)
    machine_module!(state, definition, context, speed, demand)
    for signal in (speed, electrical, mechanical)
        x, y = allocate_cell!(state.layout)
        output_probe!(state.main, signal.name, "machine", "pu", (x + 126, y + 72))
    end
    return nothing
end
