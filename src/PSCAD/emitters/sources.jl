function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.Source}, context)
    connected = filter(t -> !t.grounded, e.terminals)
    length(connected) == 1 ||
        throw(ArgumentError("element :$(e.name) must have one connected source terminal"))
    terminal = only(connected)
    bus = _terminal_bus(e, terminal, context)
    bus.kind == :dc && return dc_source!(state, e, terminal, bus, context)
    # Solved bus voltages set source magnitudes. Linear builder networks
    # use source inputs because they have no solved power flow.
    magnitude, angle = if bus.vm_pu === nothing
        values = PowerImpedance.inputvalues(e.model)
        values.v * sqrt(3 / 2), values.theta
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
    name = current_probe!(state, e, terminal, context; orientation = :into)
    ammeter_stub!(state.main, (x + 108, y + 54),
        only(_terminal_labels(e, terminal, context)), name; reverse = true)
    output_probe!(state.main, name, "branch", "kA", (x + 144, y + 126))
    return nothing
end

# The orient-0 source terminal NA (-36, 0) has positive polarity.
function dc_source!(state, e, terminal, bus, context)
    magnitude = if bus.vm_pu === nothing
        PowerImpedance.inputvalues(e.model).v / 2
    else
        bus.vm_pu * bus.base_kV
    end
    isfinite(magnitude) && magnitude > 0 ||
        throw(ArgumentError("element :$(e.name) requires positive pole-to-ground Vdc"))
    x, y = allocate_cell!(state.layout)
    labels = _terminal_labels(e, terminal, context)
    probe = current_probe!(state, e, terminal, context; orientation = :into)
    for (index, pole) in enumerate(("P", "N"))
        row = y + 54 + 72 * (index - 1)
        name = pscad_name(e.pscad * "_" * pole; used = state.used)
        component!(state.main,
            "source_1",
            (x + 126, row),
            [
                "Name" => name, "AC" => "0", "Type" => "6", "Cntrl" => "0",
                "Grnd" => "0", "Vm" => pscad_value(magnitude; unit = "kV"),
                "Tc" => pscad_value(context.settings.source_ramp; unit = "s"),
                "Ph" => "0.0 [deg]", "f" =>
                    pscad_value(context.settings.frequency; unit = "Hz")])
        if pole == "P"
            ammeter_stub!(state.main, (x + 90, row), labels[1], probe; direction = -1)
            stub!(state.main, (x + 162, row), nothing)
        else
            stub!(state.main, (x + 90, row), nothing; direction = -1)
            stub!(state.main, (x + 162, row), labels[2])
        end
    end
    output_probe!(state.main, probe, "branch", "kA", (x + 144, y + 180))
    return nothing
end
