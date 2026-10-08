function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.Source}, context)
    connected = filter(t -> !t.grounded, e.terminals)
    length(connected) == 1 ||
        throw(ArgumentError("element :$(e.name) must have one connected AC source terminal"))
    terminal = only(connected)
    bus = _ac_bus(e, terminal, context)
    # A solved bus owns the source voltage; linear NB networks retain setpoints.
    magnitude, angle = if bus.vm_pu === nothing
        ismissing(e.setpoint.Vac) &&
            throw(ArgumentError("element :$(e.name) is missing setpoint.Vac"))
        ismissing(e.setpoint.θac) &&
            throw(ArgumentError("element :$(e.name) is missing setpoint.θac"))
        e.setpoint.Vac * sqrt(3 / 2), e.setpoint.θac
    else
        bus.vm_pu * bus.base_kV * sqrt(3), bus.va_rad
    end
    x, y = allocate_cell!(state.layout)
    settings = context.settings
    component!(state.main,
        "source_3",
        (x + 72, y + 54),
        [
            "Name" => e.pscad, "Type" => "6", "Grnd" => "1", "View" => "1",
            "Spec" => "0", "VCtrl" => "0", "FCtrl" => "0",
            "Vm" => pscad_value(magnitude; unit = "kV"),
            "f" => pscad_value(settings.frequency; unit = "Hz"),
            "Ph" => pscad_value(rad2deg(angle) + 90; unit = "deg"),
            "Tc" => pscad_value(settings.source_ramp; unit = "s")])
    name = current_probe!(state, e, terminal, context)
    ammeter_stub!(state.main, (x + 108, y + 54), bus.name, name)
    output_probe!(state.main, name, "branch", "kA", (x + 144, y + 126))
    return nothing
end
