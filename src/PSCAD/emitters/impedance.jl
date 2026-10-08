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
    left_bus = _ac_bus(e, left, context)
    right_bus = _ac_bus(e, right, context)
    record = identify_rlc(e.element; name = e.name)
    record isa AbstractVector &&
        throw(ArgumentError("impedance :$(e.name) has distinct per-conductor diagonal groups; PSCAD export is not implemented yet"))
    record.constant &&
        @info "PSCAD impedance :$(e.name) uses constant R and equivalent L at 50 Hz"
    form = record.form
    parts = Tuple{String, String, Float64, String}[]
    form.R === nothing || push!(parts, ("resistor", "R", form.R, "ohm"))
    form.L === nothing || push!(parts, ("inductor", "L", form.L, "H"))
    form.C === nothing || push!(parts, ("capacitor", "C", form.C * 1e6, "uF"))
    x, y = allocate_cell!(state.layout)
    first_probe = current_probe!(state, e, left, context)
    second_probe = right.grounded ? nothing : current_probe!(state, e, right, context)
    right_name = right.grounded ? nothing : right_bus.name
    if form.topology == :series
        start = (x + 90, y + 54)
        finish = component_chain!(state.main, parts, start, e.pscad, state.used)
        ammeter_stub!(state.main, start, left_bus.name, first_probe; direction = -1)
        if second_probe === nothing
            stub!(state.main, finish, nothing)
        else
            ammeter_stub!(state.main, finish, right_name, second_probe)
        end
        output_probe!(state.main, first_probe, "branch", "kA", (x + 144, y + 126))
        second_probe === nothing ||
            output_probe!(state.main, second_probe, "branch", "kA", (x + 144, y + 162))
    else
        # Internal labels join the parallel rows behind one total-current meter
        # per terminal. These labels have no network-bus ownership.
        inner_left = pscad_name(e.pscad * "_parallel_1"; used = state.used)
        inner_right = pscad_name(e.pscad * "_parallel_2"; used = state.used)
        ammeter_stub!(
            state.main, (x + 90, y + 36), left_bus.name, first_probe; direction = -1)
        stub!(state.main, (x + 90, y + 36), inner_left)
        label!(state.main, inner_right, (x + 162, y + 36))
        if second_probe === nothing
            stub!(state.main, (x + 162, y + 36), nothing)
        else
            ammeter_stub!(state.main, (x + 198, y + 36), right_name, second_probe)
            wire!(state.main, (x + 162, y + 36), (x + 198, y + 36))
        end
        for (index, part) in enumerate(parts)
            start = (x + 126, y + 36 + 36 * index)
            finish = component_chain!(state.main, [part], start, e.pscad, state.used)
            stub!(state.main, start, inner_left; direction = -1)
            stub!(state.main, finish, inner_right)
        end
        output_probe!(state.main, first_probe, "branch", "kA", (x + 18, y + 180))
        second_probe === nothing ||
            output_probe!(state.main, second_probe, "branch", "kA", (x + 162, y + 180))
    end
    return nothing
end
