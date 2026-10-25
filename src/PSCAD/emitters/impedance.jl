function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.Impedance}, context)
    length(e.terminals) == 2 && [t.port for t in e.terminals] == [:side1, :side2] ||
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
    record = identify_rlc(e.model; name = e.name)
    record isa AbstractVector &&
        throw(ArgumentError("impedance :$(e.name) has distinct per-conductor diagonal groups; PSCAD export is not implemented yet"))
    record.constant &&
        @info "PSCAD impedance :$(e.name) uses constant R and equivalent L at 50 Hz"
    form = record.form
    dc = left_bus.kind == :dc
    # Each DC pole has half the differential impedance, so R and L halve
    # and C doubles in either topology.
    parts = impedance_parts(form; scale = dc ? 0.5 : 1.0)
    first_probe = current_probe!(state, e, left, context; orientation = :into)
    second_probe = right.grounded ? nothing :
                   current_probe!(state, e, right, context; orientation = :into)
    left_labels = _terminal_labels(e, left, context)
    right_labels = right.grounded ? ntuple(_ -> nothing, length(left_labels)) :
                   _terminal_labels(e, right, context)
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

function impedance_path!(state, parts, topology, left_name, right_name, stem;
        first_probe = nothing, second_probe = nothing)
    x, y = allocate_cell!(state.layout)
    # Place the ammeter in the ground return to avoid a chain of ideal meters
    # on an isolated winding. Its orient-0 arrow measures from bus to ground.
    shunt_probe = right_name === nothing ? first_probe : nothing
    if topology == :series
        if isempty(parts)
            # A zero series impedance identifies the two nodes. A requested ammeter
            # provides the ideal branch. Otherwise the labels denote the same node.
            probes = filter(!isnothing, [first_probe, second_probe])
            if isempty(probes)
                join_node_labels!(state.main, left_name, right_name)
            else
                middle = length(probes) == 2 ?
                         pscad_name(stem * "_junction"; used = state.used) : nothing
                for (i, probe) in enumerate(probes)
                    first = i == 1 ? left_name : middle
                    second = i == length(probes) ? right_name : middle
                    reverse = probe == second_probe
                    component!(state.main, "ammeter",
                        (x + 126 + 36reverse, y + 54 + 72 * (i - 1)),
                        ["Name" => probe]; orient = reverse ? 4 : 0)
                    stub!(state.main, (x + 126, y + 54 + 72 * (i - 1)), first;
                        direction = -1)
                    stub!(state.main, (x + 162, y + 54 + 72 * (i - 1)), second)
                end
            end
            first_probe === nothing || output_probe!(state.main, first_probe,
                "branch", "kA", (x + 234, y + 126))
            second_probe === nothing || output_probe!(state.main, second_probe,
                "branch", "kA", (x + 234, y + 162))
            return nothing
        end
        start = (x + 90, y + 54)
        finish = component_chain!(state.main, parts, start, stem, state.used)
        if first_probe === nothing || shunt_probe !== nothing
            stub!(state.main, start, left_name; direction = -1)
        else
            ammeter_stub!(state.main, start, left_name, first_probe; direction = -1)
        end
        if shunt_probe !== nothing
            ammeter_stub!(state.main, finish, nothing, shunt_probe)
        elseif second_probe === nothing
            stub!(state.main, finish, right_name)
        else
            ammeter_stub!(state.main, finish, right_name, second_probe; reverse = true)
        end
        first_probe === nothing ||
            output_probe!(state.main, first_probe, "branch", "kA", (x + 144, y + 126))
        second_probe === nothing ||
            output_probe!(state.main, second_probe, "branch", "kA", (x + 144, y + 162))
    else
        # One meter per terminal measures total current through the parallel
        # branches. Internal labels connect those branches to the meter.
        inner_left = pscad_name(stem * "_parallel_1"; used = state.used)
        inner_right = pscad_name(stem * "_parallel_2"; used = state.used)
        if first_probe === nothing || shunt_probe !== nothing
            join_node_labels!(state.main, left_name, inner_left)
        else
            component!(state.main, "ammeter", (x + 54, y + 36), ["Name" => first_probe])
            stub!(state.main, (x + 54, y + 36), left_name; direction = -1)
            stub!(state.main, (x + 90, y + 36), inner_left)
        end
        if shunt_probe !== nothing
            component!(state.main, "ammeter", (x + 234, y + 36), ["Name" => shunt_probe])
            stub!(state.main, (x + 234, y + 36), inner_right; direction = -1)
            stub!(state.main, (x + 270, y + 36), nothing)
        elseif second_probe === nothing
            join_node_labels!(state.main, right_name, inner_right)
        else
            component!(state.main, "ammeter", (x + 270, y + 36),
                ["Name" => second_probe]; orient = 4)
            stub!(state.main, (x + 234, y + 36), inner_right; direction = -1)
            stub!(state.main, (x + 270, y + 36), right_name)
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
