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

function voltage_probe!(state::PlanState, bus::Bus, labels = (bus.name,))
    x, y = allocate_cell!(state.layout)
    for (index, label) in enumerate(labels)
        row = y + 72 + 54 * (index - 1)
        name = pscad_name(voltage_probe_name(label); used = state.used)
        label!(state.main, label, (x + 54, row))
        wire!(state.main, (x + 54, row), (x + 90, row))
        component!(state.main, "voltmetergnd", (x + 90, row), ["Name" => name])
        output_probe!(state.main, name, "bus", "kV", (x + 180, row))
        side = bus.kind == :dc ? (index == 1 ? "P" : "N") : nothing
        push!(state.channels,
            ProbeChannel(name, :voltage, bus.name, nothing, side,
                bus.kind == :dc ? 1 : 3, "kV"))
    end
    return nothing
end
