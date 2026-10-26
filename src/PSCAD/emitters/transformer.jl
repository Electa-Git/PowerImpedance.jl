"Near-ideal YY leakage reactance on the master base \\[dimensionless\\]."
const YY_LEAKAGE_PU = 1e-4
# At the floating star point, 1e-4 % gives a "very small diagonal" warning.
# A value of 1e-3 % avoids it with a measured turns-ratio error of 7e-10.
"Near-ideal YY exciting current at rated voltage \\[%\\]."
const YY_MAGNETIZING_CURRENT_PERCENT = 1e-3
"Master transformer apparent-power base \\[MVA\\]."
const TRANSFORMER_BASE_MVA = 1000

function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.Transformer}, context)
    length(e.terminals) == 2 && [t.port for t in e.terminals] == [:side1, :side2] &&
    all(t -> !t.grounded, e.terminals) ||
        throw(ArgumentError("transformer :$(e.name) requires two connected AC sides"))
    t = transformer_si(e.model)
    e.ports.side1.domain === PowerImpedance.ACABC && t.organization in (:YY, :ΔY) ||
        throw(ArgumentError("transformer :$(e.name) supports only three-phase YY or ΔY"))
    for field in (:R_p, :L_p, :R_s, :L_s, :C_t, :C_s)
        value = getproperty(t, field)
        isfinite(value) && value >= 0 ||
            throw(ArgumentError("transformer :$(e.name) $field must be finite and nonnegative"))
    end
    for field in (:R_m, :L_m)
        value = getproperty(t, field)
        !isnan(value) && value >= 0 ||
            throw(ArgumentError("transformer :$(e.name) $field must be nonnegative"))
    end
    primary, secondary = e.terminals
    primary_bus = _ac_bus(e, primary, context)
    secondary_bus = _ac_bus(e, secondary, context)
    inner_primary = pscad_name(e.pscad * "_primary"; used = state.used)
    inner_secondary = pscad_name(e.pscad * "_secondary"; used = state.used)
    terminal_primary = pscad_name(e.pscad * "_terminal_1"; used = state.used)
    terminal_secondary = pscad_name(e.pscad * "_terminal_2"; used = state.used)
    primary_probe = current_probe!(state, e, primary, context; orientation = :into)
    secondary_probe = current_probe!(state, e, secondary, context; orientation = :into)
    impedance_path!(state, [], :series, only(_terminal_labels(e, primary, context)), terminal_primary,
        e.pscad * "_meter_1"; first_probe = primary_probe)
    primary_parts = Tuple{String, String, Float64, String}[]
    t.R_p == 0 || push!(primary_parts, ("resistor", "R", t.R_p, "ohm"))
    t.L_p == 0 || push!(primary_parts, ("inductor", "L", t.L_p, "H"))
    impedance_path!(state, primary_parts, :series, terminal_primary, inner_primary,
        e.pscad * "_primary")
    x, y = allocate_cell!(state.layout)
    v1 = something(primary_bus.vm_pu, 1.0) * primary_bus.base_kV * sqrt(3)
    component!(state.main,
        "xfmr-3p2w",
        (x + 144, y + 54),
        [
            "Name" => e.pscad, "Tmva" => pscad_value(TRANSFORMER_BASE_MVA; unit = "MVA"),
            "f" => pscad_value(context.settings.frequency; unit = "Hz"),
            "YD1" => t.organization == :ΔY ? "1" : "0", "YD2" => "0", "Lead" => "1",
            "Ideal" => t.organization == :YY ? "0" : "1",
            "Xl" => pscad_value(YY_LEAKAGE_PU; unit = "pu"),
            "Im1" => pscad_value(YY_MAGNETIZING_CURRENT_PERCENT; unit = "%"),
            "NLL" => "0.0 [pu]", "CuL" => "0.0 [pu]", "Tap" => "0", "View" => "1",
            "Dtls" => "0", "V1" => pscad_value(v1; unit = "kV"),
            "V2" => pscad_value(v1 / t.n; unit = "kV"), "Enab" => "0"])
    stub!(state.main, (x + 90, y + 54), inner_primary; direction = -1)
    stub!(state.main, (x + 180, y + 54), inner_secondary)
    secondary_parts = Tuple{String, String, Float64, String}[]
    t.R_s == 0 || push!(secondary_parts, ("resistor", "R", t.R_s, "ohm"))
    t.L_s == 0 || push!(secondary_parts, ("inductor", "L", t.L_s, "H"))
    impedance_path!(state, secondary_parts, :series, inner_secondary, terminal_secondary,
        e.pscad * "_secondary")
    impedance_path!(state, [], :series, terminal_secondary, only(_terminal_labels(e, secondary, context)),
        e.pscad * "_meter_2"; second_probe = secondary_probe)
    for (field, defn, parameter, unit) in ((:L_m, "inductor", "L", "H"), (
        :R_m, "resistor", "R", "ohm"))
        value = getproperty(t, field)
        if isfinite(value) && value > 0
            impedance_path!(state, [(defn, parameter, value, unit)], :series,
                inner_primary, nothing, e.pscad * "_magnetizing")
        end
    end
    if t.C_t > 0
        for (side, bus) in ((1, terminal_primary), (2, terminal_secondary))
            impedance_path!(state, [("capacitor", "C", t.C_t * 1e6, "uF")], :series,
                bus, nothing, e.pscad * "_turn_$side")
        end
    end
    if t.C_s > 0
        impedance_path!(state, [("capacitor", "C", t.C_s * 1e6, "uF")], :series,
            terminal_primary, terminal_secondary, e.pscad * "_stray")
    end
    return nothing
end
