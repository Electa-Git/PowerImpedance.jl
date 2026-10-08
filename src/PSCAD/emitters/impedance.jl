function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.Impedance}, context)
    length(e.terminals) == 2 && [t.side for t in e.terminals] == [1, 2] ||
        throw(ArgumentError("impedance :$(e.name) must have two fully connected sides"))
    left, right = e.terminals
    left.grounded && right.grounded &&
        throw(ArgumentError("impedance :$(e.name) has no nongrounded terminal"))
    if left.grounded
        left, right = right, left
    end
    right.terminals == left.terminals ||
        throw(ArgumentError("impedance :$(e.name) has incomplete terminal groups"))
    left_bus = _terminal_bus(e, left, context)
    right_bus = _terminal_bus(e, right, context)
    right_bus === nothing || right_bus.kind == left_bus.kind ||
        throw(ArgumentError("impedance :$(e.name) mixes AC and DC terminal representations"))
    record = identify_rlc(e.element; name = e.name)
    record isa AbstractVector &&
        throw(ArgumentError("impedance :$(e.name) has distinct per-conductor diagonal groups; PSCAD export is not implemented yet"))
    record.constant &&
        @info "PSCAD impedance :$(e.name) uses constant R and equivalent L at 50 Hz"
    form = record.form
    dc = left_bus.kind == :dc
    # Multiplying Z by 1/2 divides R and L, and doubles C in either topology.
    parts = impedance_parts(form; scale = dc ? 0.5 : 1.0)
    first_probe = current_probe!(state, e, left, context)
    second_probe = right.grounded ? nothing : current_probe!(state, e, right, context)
    left_labels = dc ? context.dc_labels[left_bus.key] : (left_bus.name,)
    right_labels = right.grounded ? ntuple(_ -> nothing, length(left_labels)) :
                   dc ? context.dc_labels[right_bus.key] : (right_bus.name,)
    for index in eachindex(left_labels)
        stem = dc ? e.pscad * (index == 1 ? "_P" : "_N") : e.pscad
        impedance_path!(
            state, parts, form.topology, left_labels[index], right_labels[index],
            stem; first_probe = index == 1 ? first_probe : nothing,
            second_probe = index == 1 ? second_probe : nothing)
    end
    return nothing
end

function impedance_parts(form; scale = 1.0)
    parts = Tuple{String, String, Float64, String}[]
    form.R === nothing || push!(parts, ("resistor", "R", form.R * scale, "ohm"))
    form.L === nothing || push!(parts, ("inductor", "L", form.L * scale, "H"))
    form.C === nothing || push!(parts, ("capacitor", "C", form.C * 1e6 / scale, "uF"))
    return parts
end

# One labelled circuit path per cell. Reused by winding and magnetizing passives.
function impedance_path!(state, parts, topology, left_name, right_name, stem;
        first_probe = nothing, second_probe = nothing)
    x, y = allocate_cell!(state.layout)
    if topology == :series
        start = (x + 90, y + 54)
        finish = component_chain!(state.main, parts, start, stem, state.used)
        if isempty(parts)
            finish = (start[1] + 36, start[2])
            wire!(state.main, start, finish)
        end
        if first_probe === nothing
            stub!(state.main, start, left_name; direction = -1)
        else
            ammeter_stub!(state.main, start, left_name, first_probe; direction = -1)
        end
        if second_probe === nothing
            stub!(state.main, finish, right_name)
        else
            ammeter_stub!(state.main, finish, right_name, second_probe)
        end
        first_probe === nothing ||
            output_probe!(state.main, first_probe, "branch", "kA", (x + 144, y + 126))
        second_probe === nothing ||
            output_probe!(state.main, second_probe, "branch", "kA", (x + 144, y + 162))
    else
        # Internal labels join the parallel rows behind one total-current meter
        # per terminal. These labels have no network-bus ownership.
        inner_left = pscad_name(stem * "_parallel_1"; used = state.used)
        inner_right = pscad_name(stem * "_parallel_2"; used = state.used)
        if first_probe === nothing
            stub!(state.main, (x + 90, y + 36), left_name; direction = -1)
        else
            ammeter_stub!(
                state.main, (x + 90, y + 36), left_name, first_probe; direction = -1)
        end
        stub!(state.main, (x + 90, y + 36), inner_left)
        label!(state.main, inner_right, (x + 162, y + 36))
        if second_probe === nothing
            stub!(state.main, (x + 162, y + 36), right_name)
        else
            ammeter_stub!(state.main, (x + 198, y + 36), right_name, second_probe)
            wire!(state.main, (x + 162, y + 36), (x + 198, y + 36))
        end
        for (index, part) in enumerate(parts)
            start = (x + 126, y + 36 + 36 * index)
            finish = component_chain!(state.main, [part], start, stem, state.used)
            stub!(state.main, start, inner_left; direction = -1)
            stub!(state.main, finish, inner_right)
        end
        first_probe === nothing ||
            output_probe!(state.main, first_probe, "branch", "kA", (x + 18, y + 180))
        second_probe === nothing ||
            output_probe!(state.main, second_probe, "branch", "kA", (x + 162, y + 180))
    end
    return nothing
end

"Resistance of each optional DC pole-to-ground reference \\[Ω\\]."
const DC_REFERENCE_RESISTANCE = 1e7

function dc_reference!(state, bus, labels)
    for (pole, label) in zip(("P", "N"), labels)
        impedance_path!(state,
            [("resistor", "R", DC_REFERENCE_RESISTANCE, "ohm")], :series,
            label, nothing, bus.name * "_reference_" * pole)
    end
    return nothing
end
