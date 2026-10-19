# Cable_Coax slots follow the radial order of the physical cable layers.
function _cable_parameters(cable, name, position, index, frequency)
    radii = (("R1", "R2", "R3"), ("R4", "R4", "R5"),
        ("R6", "R6", "R7"), ("R8", "R8", "R9"))
    resistivities = ("RHOC", "RHOS", "RHOA", "RHOO")
    permeabilities = ("PERMC", "PERMS", "PERMA", "PERMO")
    underground = cable.type == :underground
    x, y = position
    params = ["CABNUM" => string(index), "Name" => name,
        "X" => pscad_value(x; unit = "m"), "OHC" => underground ? "0" : "1",
        "Y" => pscad_value(underground ? y : 0.0; unit = "m"),
        "Y2" => pscad_value(underground ? 0.0 : y; unit = "m"),
        "ShuntA" => "1.0E-38 [mho/m]", "FLT" => pscad_value(frequency; unit = "Hz"),
        "RorT" => "0", "LL" => string(2length(cable.conductors) - 1),
        "SHRad" => "1", "LC" => "2", "CROSSBOND" => "0",
        "SemiCL" => "0", "SL1" => "0.0 [m]", "SL2" => "0.0 [m]"]
    for layer in 1:4
        inner, outer, insulation = radii[layer]
        present = layer <= length(cable.conductors)
        conductor = present ? cable.conductors[Symbol("C$layer")] : nothing
        dielectric = present ? cable.insulators[Symbol("I$layer")] : nothing
        layer == 1 && push!(params, inner => pscad_value(conductor.rᵢ; unit = "m"))
        append!(params,
            ["CONNAM$layer" => present ? "C$layer" : "none",
                outer => pscad_value(present ? conductor.rₒ : 0.0; unit = "m"),
                resistivities[layer] =>
                    pscad_value(present ? conductor.ρ : 0.0; unit = "ohm*m"),
                permeabilities[layer] => pscad_value(present ? conductor.μᵣ : 0.0),
                insulation => pscad_value(present ? dielectric.rₒ : 0.0; unit = "m"),
                "EPS$layer" => pscad_value(present ? dielectric.ϵᵣ : 0.0),
                "PERM$layer" => pscad_value(present ? dielectric.μᵣ : 0.0),
                "LT$layer" => "0.0"])
        layer > 1 && push!(params, "elim$(layer - 1)" => present ? "1" : "0")
    end
    return params
end

function _cable_interface_parameters(name, positions)
    params = ["Name" => name, "NCAB" => string(positions)]
    append!(params, ["C$(i)T" => "1" for i in 1:12])
    append!(params,
        ["pipe" => "0", "dim_s" => "0", "dim_r" => "0",
            "GroundS" => "0", "GroundA" => "0", "GroundOC" => "0",
            "ResS" => "0.001 [ohm]", "ResA" => "0.001 [ohm]", "ResOC" => "0.001 [ohm]",
            "send_recv" => "0", "recv_default_type" => "0", "recv_default" => "0"])
    return params
end

# The breakout joins scalar core labels to the three-phase bus, so the
# bus-side ammeter measures the phases in their physical order.
function _cable_ac_connection!(state, bus_label, labels, probe, side)
    x, y = allocate_cell!(state.layout)
    point = (x + 144, y + 90)
    component!(state.main, "breakout", point)
    outer = ammeter_stub!(state.main, point, bus_label, probe; direction = -1)
    if side == 2
        # Exchange the meter node labels to reverse its sign and preserve the
        # breakout wires. Side 2 measures current from element to bus.
        bus_index = findlast(c -> c.defn == "master:nodelabel" &&
                                 (c.x, c.y) == outer, state.main.components)
        inner_index = findlast(c -> c.defn == "master:nodelabel" &&
                                   (c.x, c.y) == (point[1], point[2] - 72),
            state.main.components)
        bus_label, inner_label = state.main.components[bus_index], state.main.components[inner_index]
        state.main.components[bus_index] = ComponentPlan(bus_label.defn,
            inner_label.params, bus_label.x, bus_label.y, bus_label.orient)
        state.main.components[inner_index] = ComponentPlan(inner_label.defn,
            bus_label.params, inner_label.x, inner_label.y, inner_label.orient)
    end
    for (index, label) in enumerate(labels)
        stub!(state.main, (point[1] + 36, point[2] + 36 * (index - 2)), label)
    end
    output_probe!(state.main, probe, "branch", "kA", (x + 144, y + 180))
    return nothing
end

function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.Cable}, context)
    cable = e.model
    if cable.length / 299_792_458 < context.settings.time_step
        @warn "PSCAD cable :$(e.name), length $(cable.length) m, time step $(context.settings.time_step) s: PSCAD aborts if the travel time is below the step; a smaller step or a longer section is needed."
    end
    cable.eliminate || throw(ArgumentError(
        "cable :$(e.name): eliminate=false requires exposed sheath/armour interfaces, which are not implemented"))
    cable.configuration == :coaxial && cable.type in (:underground, :aerial) ||
        throw(ArgumentError("cable :$(e.name) requires coaxial underground or aerial geometry"))
    layers = length(cable.conductors)
    1 <= layers <= 4 &&
    collect(keys(cable.conductors)) == [Symbol("C$i") for i in 1:layers] &&
    collect(keys(cable.insulators)) == [Symbol("I$i") for i in 1:layers] ||
        throw(ArgumentError("cable :$(e.name) requires 1 to 4 ordered C1/I1 through C4/I4 layer pairs"))
    all(p -> isfinite(p[1]) && isfinite(p[2]) && p[2] > 0, cable.positions) ||
        throw(ArgumentError("cable :$(e.name) requires finite positions with positive depth or height"))
    length(e.terminals) == 2 && [t.side for t in e.terminals] == [1, 2] &&
    all(t -> !t.grounded, e.terminals) ||
        throw(ArgumentError("cable :$(e.name) requires two fully connected nongrounded sides"))
    buses = [_terminal_bus(e, t, context) for t in e.terminals]
    dc = first(buses).kind == :dc
    all(b -> (b.kind == :dc) == dc, buses) ||
        throw(ArgumentError("cable :$(e.name) cannot join AC and DC buses"))
    positions = dc ? 2 : 3
    length(cable.positions) == positions ||
        throw(ArgumentError("cable :$(e.name) requires $positions positions for $(dc ? "DC" : "AC") export"))
    row = pscad_name(e.pscad * "_row"; used = state.used)
    components = [ComponentPlan("master:Cable_Coax",
                      _cable_parameters(
                          cable, e.pscad, position, i, context.settings.frequency),
                      396 + 396 * (i - 1), 522, 0)
                  for (i, position) in enumerate(cable.positions)]
    push!(state.lines,
        CableDefinitionPlan(row, components,
            _line_ground_parameters(cable, context.line_options.ground),
            _line_frephase_parameters(context.line_options.frephase, buses),
            ["DataF" => pscad_value(context.settings.frequency; unit = "Hz")]))
    x, y = allocate_cell!(state.layout)
    push!(state.wrappers,
        CableWrapperPlan(row, x + 144, y + 144,
            ["Name" => e.pscad,
                "Freq" => pscad_value(dc ? 0.0 : context.settings.frequency; unit = "Hz"),
                "Length" => pscad_value(cable.length / 1e3; unit = "km"),
                "Dim" => "0", "Mode" => "0", "CoupleEnab" => "0", "CoupleName" => "row",
                "CoupleOffset" => "0.0 [m]", "CoupleRef" => "0", "gen_cnst" => "1",
                "const_path" => "", "Date" => "0", "R" => "", "X" => "", "B" => "",
                "tname" => "tandem_segment", "sfault" => "0", "linc" => "10.0 [km]", "steps" => "3"]))
    for (side, (terminal, bus)) in enumerate(zip(e.terminals, buses))
        x, y = allocate_cell!(state.layout)
        direction = side == 1 ? -1 : 1
        interface = (x + 144, y + 54)
        push!(state.main.components,
            ComponentPlan("master:cable_interface",
                _cable_interface_parameters(e.pscad, positions), interface..., side == 1 ?
                                                                               0 : 4))
        probe = current_probe!(state, e, terminal, context; orientation = side == 1 ? :into : :out)
        labels = dc ? _terminal_labels(e, terminal, context) :
                 [pscad_name(e.pscad * "_$(side)_" * phase; used = state.used)
                  for phase in ("A", "B", "C")]
        for (i, label) in enumerate(labels)
            port = (interface[1] + 18direction, interface[2] + 54 * (i - 1))
            if dc && i == 1
                ammeter_stub!(state.main, port, label, probe; direction)
            else
                stub!(state.main, port, label; direction)
            end
        end
        if dc
            output_probe!(state.main, probe, "branch", "kA", (x + 144, y + 180))
        else
            _cable_ac_connection!(state, only(_terminal_labels(e, terminal, context)), labels, probe, side)
        end
    end
    return nothing
end
