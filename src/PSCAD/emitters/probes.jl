function _ac_bus(e, terminal, context)
    terminal.grounded && return nothing
    bus = context.buses[terminal.bus]
    bus.kind in (:ac3_dq, :ac3_abc) ||
        throw(ArgumentError("PSCAD export of :$(e.name) ($(typeof(e.model))) is not implemented yet for DC terminals"))
    expected = bus.kind == :ac3_dq ? 2 : 3
    terminal.terminals == collect(1:expected) ||
        throw(ArgumentError("element :$(e.name) side $(terminal.side) has incomplete AC terminals"))
    return bus
end

function current_probe!(state::PlanState, e, terminal, context)
    bus = _ac_bus(e, terminal, context)
    bus === nothing &&
        throw(ArgumentError("element :$(e.name) has a grounded measurement terminal"))
    name = pscad_name(current_probe_name(e.pscad, terminal.side); used = state.used)
    push!(state.channels,
        ProbeChannel(name, :current, bus.name, string(e.name),
            string(terminal.side), 3, "kA"))
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

function voltage_probe!(state::PlanState, bus::Bus)
    bus.kind in (:ac3_dq, :ac3_abc) ||
        throw(ArgumentError("PSCAD voltage probes for DC bus $(bus.name) are not implemented yet"))
    x, y = allocate_cell!(state.layout)
    name = pscad_name(voltage_probe_name(bus.name); used = state.used)
    label!(state.main, bus.name, (x + 54, y + 72))
    wire!(state.main, (x + 54, y + 72), (x + 90, y + 72))
    component!(state.main, "voltmetergnd", (x + 90, y + 72), ["Name" => name])
    output_probe!(state.main, name, "bus", "kV", (x + 180, y + 72))
    push!(state.channels, ProbeChannel(name, :voltage, bus.name, nothing, nothing, 3, "kV"))
    return nothing
end
