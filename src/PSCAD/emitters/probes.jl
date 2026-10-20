function _terminal_bus(e, terminal, context)
    terminal.grounded && return nothing
    bus = context.buses[terminal.bus]
    expected = bus.kind == :dc ? 1 : bus.kind == :ac3_dq ? 2 : 3
    terminal.terminals == collect(1:expected) ||
        throw(ArgumentError("element :$(e.name) side $(terminal.side) has incomplete $(bus.kind) terminals"))
    return bus
end

function _ac_bus(e, terminal, context)
    bus = _terminal_bus(e, terminal, context)
    bus === nothing && return nothing
    bus.kind in (:ac3_dq, :ac3_abc) ||
        throw(ArgumentError("PSCAD export of :$(e.name) ($(typeof(e.model))) is not implemented yet for DC terminals"))
    return bus
end

function current_probe!(state::PlanState, e, terminal, context; orientation)
    bus = _terminal_bus(e, terminal, context)
    bus === nothing &&
        throw(ArgumentError("element :$(e.name) has a grounded measurement terminal"))
    name = pscad_name(current_probe_name(e.pscad, terminal.side); used = state.used)
    push!(state.channels,
        ProbeChannel(name, :current, bus.name, string(e.name),
            string(terminal.side), bus.kind == :dc ? 1 : 3, "kA", orientation))
    return name
end

function output_probe!(canvas::CanvasPlan, name, group, unit, point)
    component!(canvas, "datalabel", point, ["Name" => name])
    endpoint = (point[1] + 36, point[2])
    wire!(canvas, point, endpoint)
    component!(canvas,
        "pgb",
        endpoint,
        ["Name" => name, "Group" => group,
            "Units" => unit, "UseSignalName" => "0", "enab" => "1"])
    return nothing
end

function voltage_probe!(state::PlanState, bus::Bus, labels = (bus.name,);
        at_conducting_node = false)
    x, y = allocate_cell!(state.layout)
    for (index, label) in enumerate(labels)
        row = y + 72 + 54 * (index - 1)
        name = pscad_name(voltage_probe_name(label); used = state.used)
        if at_conducting_node
            # Both MeasV=1 on a node label and voltmetergnd call EMTDC_VVDC.
            # Measure at a conducting branch to avoid a separate voltage meter,
            # which PSCAD can relocate on load while its wire remains in place.
            target = get(state.main.aliases, lowercase(label), label)
            target === nothing && throw(ArgumentError("grounded voltage tap for $label"))
            tap_index = findfirst(state.main.components) do c
                c.defn == "master:nodelabel" &&
                    lowercase(Dict(c.params)["Name"]) == lowercase(target) &&
                    get(Dict(c.params), "MeasV", "0") != "1"
            end
            tap_index === nothing && throw(ArgumentError("no conducting voltage tap for $label"))
            c = state.main.components[tap_index]
            params = [c.params; ["MeasV" => "1", "PU" => "0", "VName" => name]]
            state.main.components[tap_index] = ComponentPlan(c.defn, params, c.x, c.y, c.orient)
        else
            label!(state.main, label, (x + 54, row))
            wire!(state.main, (x + 54, row), (x + 90, row))
            component!(state.main, "voltmetergnd", (x + 90, row), ["Name" => name])
        end
        output_probe!(state.main, name, "bus", "kV", (x + 180, row))
        side = bus.kind == :dc ? (index == 1 ? "P" : "N") : nothing
        push!(state.channels,
            ProbeChannel(name, :voltage, bus.name, nothing, side,
                bus.kind == :dc ? 1 : 3, "kV"))
    end
    return nothing
end
