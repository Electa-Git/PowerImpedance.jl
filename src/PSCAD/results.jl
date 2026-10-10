function _pscad_number(text::AbstractString)
    value = replace(strip(text), 'D' => 'E', 'd' => 'e')
    value = replace(value, r"^([+-])\." => s"\g<1>0.")
    value = replace(value, r"^\." => "0.")
    value = replace(
        value,
        r"^([+-]?(?:\d+(?:\.\d*)?|\.\d+))([+-]\d+)$" => s"\g<1>E\g<2>"
    )
    parsed = tryparse(Float64, value)
    parsed === nothing && throw(ArgumentError("invalid PSCAD numeric field $(repr(text))"))
    return parsed
end

"Relative change threshold between the two halves of a steady-state window."
const STEADY_STATE_SETTLING_RTOL = 1e-3

function _warn_unsettled_channel(name, first_half, second_half)
    if any(abs.(first_half .- second_half) .>
           STEADY_STATE_SETTLING_RTOL .* max.(abs.(first_half), abs.(second_half)))
        @warn "channel not settled within the steady-state window; lengthen simulation_time" channel = name first_half second_half
    end
    return nothing
end

function _window_phasors(result, group, dim, window)
    weights = cis.(-2π * result.settings.frequency .* result.time[window])
    return [2 / length(window) * sum(result.channels[group[index]][window] .* weights)
            for index in 1:dim]
end

function _sequence_phasor(phasors)
    length(phasors) == 3 || return phasors
    a = cis(2π / 3)
    return (phasors[1] + a * phasors[2] + a^2 * phasors[3]) / 3
end

function _probe_present(channel::ProbeChannel, channels)
    return channel.dim == 1 ? haskey(channels, channel.name) :
           all(index -> haskey(channels, "$(channel.name):$index"), 1:channel.dim)
end

function _steady_window(result::PSCADResult, window_cycles)
    window_cycles isa Integer && !(window_cycles isa Bool) && window_cycles >= 1 ||
        throw(ArgumentError("window_cycles must be a positive integer"))
    times = result.time
    length(times) >= 2 && all(isfinite, times) ||
        throw(ArgumentError("steady_state requires finite sample times and at least one full cycle"))
    intervals = diff(times)
    step = (last(times) - first(times)) / (length(times) - 1)
    step > 0 && all(dt -> isapprox(dt, step; rtol = 1e-9, atol = 0), intervals) ||
        throw(ArgumentError("steady_state requires uniformly increasing sample times"))
    samples_per_cycle = inv(result.settings.frequency * step)
    isfinite(samples_per_cycle) && samples_per_cycle >= 2 ||
        throw(ArgumentError("steady_state requires at least two samples per cycle"))
    count = round(Int, samples_per_cycle)
    isapprox(samples_per_cycle, count; rtol = 1e-9, atol = 0) ||
        throw(ArgumentError("steady_state requires an integer number of samples per cycle"))
    available = (length(times) - 1) ÷ count
    available >= 1 || throw(ArgumentError("steady_state requires at least one full cycle"))
    samples = min(window_cycles, available) * count
    return (length(times) - samples + 1):length(times)
end

"""
$(TYPEDSIGNATURES)

Extract settled channel values using the actual sample times \\[s\\] over
the last `window_cycles` complete cycles at `result.settings.frequency` \\[Hz\\].
Use all available complete cycles when fewer than requested are recorded.
Group contiguous `name:1` through `name:k` channels; retain other names as scalars.

# Returns

- An ordered dictionary keyed by probe name. Scalars contain `(dim = 1, mean)`
  in the recorded unit. Arrays contain `dim`, complex phase `phasors`, `peak`,
  `rms`, and `angle` \\[rad\\] in the cosine reference. Three-phase arrays
  contain positive-sequence peak/RMS magnitudes and angle; other arrays retain
  per-component magnitudes and angles. Units follow the original channels.

# Notes

For ``N`` samples at times ``t_n``, the peak phasor and positive sequence are

```math
X = \\frac{2}{N}\\sum_n x(t_n)e^{-\\mathrm{j}2\\pi f t_n},\\qquad
X_+ = \\frac{X_a + aX_b + a^2X_c}{3},\\quad a=e^{\\mathrm{j}2\\pi/3}.
```

RMS magnitude is peak magnitude divided by ``\\sqrt{2}``.
Compare scalar means or array phasor RMS magnitudes over the two halves of
the window. Warn once per channel when the change exceeds
`STEADY_STATE_SETTLING_RTOL = 1e-3` relative to the larger magnitude.

# Errors

- Throws `ArgumentError` for incomplete array groups, invalid channel data,
  less than one full cycle, nonuniform times, or a noninteger number of samples
  per cycle (relative tolerance `1e-9`).
"""
function steady_state(result::PSCADResult; window_cycles = 10)
    window = _steady_window(result, window_cycles)
    groups = OrderedDict{String, Dict{Int, String}}()
    for (name, values) in result.channels
        length(values) == length(result.time) && all(isfinite, values) ||
            throw(ArgumentError("invalid sample data for PSCAD channel $name"))
        matched = match(r"^(.*):([1-9][0-9]*)$", name)
        base, index = matched === nothing ? (name, 0) :
                      (String(matched[1]), parse(Int, matched[2]))
        group = get!(Dict{Int, String}, groups, base)
        group[index] = name
    end
    settled = OrderedDict{String, NamedTuple}()
    midpoint = first(window) + length(window) ÷ 2
    halves = (first(window):(midpoint - 1), midpoint:last(window))
    for (name, group) in groups
        if haskey(group, 0)
            length(group) == 1 ||
                throw(ArgumentError("PSCAD channel $name mixes scalar and array entries"))
            settled[name] = (dim = 1, mean = mean(result.channels[group[0]][window]))
            values = map(half -> mean(result.channels[group[0]][half]), halves)
            _warn_unsettled_channel(name, values...)
            continue
        end
        dim = length(group)
        Set(keys(group)) == Set(1:dim) ||
            throw(ArgumentError("PSCAD array channel $name has incomplete component indices"))
        if dim == 1
            settled[name] = (dim = 1, mean = mean(result.channels[group[1]][window]))
            values = map(half -> mean(result.channels[group[1]][half]), halves)
            _warn_unsettled_channel(name, values...)
            continue
        end
        phasors = _window_phasors(result, group, dim, window)
        phasor = _sequence_phasor(phasors)
        values = map(
            half -> abs.(_sequence_phasor(_window_phasors(result, group, dim, half))) ./
                    sqrt(2),
            halves)
        _warn_unsettled_channel(name, values...)
        settled[name] = (dim = dim, phasors = phasors, peak = abs.(phasor),
            rms = abs.(phasor) ./ sqrt(2), angle = angle.(phasor))
    end
    return settled
end

function _comparison_bus(model, name)
    index = findfirst(bus -> bus.name == name, model.netlist.buses)
    index === nothing && throw(ArgumentError("missing power-flow bus for $name"))
    bus = model.netlist.buses[index]
    point = get(model.operating_point.bus_states, bus.key, nothing)
    point !== nothing && point.vm_pu !== nothing &&
    (bus.kind == :dc || point.va_rad !== nothing) ||
        throw(ArgumentError("missing power-flow voltage for bus $name"))
    return bus, point
end

function _dc_converter_current_bases(netlist)
    # DC connectivity excludes AC terminals and the shared ground. Each
    # element joins only its nongrounded DC buses, including cable ends.
    parents = Dict(bus.key => bus.key for bus in netlist.buses if bus.key.domain == 2)
    function root(key)
        parent = parents[key]
        if parent != key
            parents[key] = root(parent)
        end
        return parents[key]
    end
    for element in netlist.elements
        buses = [terminal.bus
                 for terminal in element.terminals
                 if !terminal.grounded && terminal.bus !== nothing &&
                        terminal.bus.domain == 2]
        isempty(buses) && continue
        first_root = root(first(buses))
        for bus in buses[2:end]
            parents[root(bus)] = first_root
        end
    end
    bases = Dict{BusKey, Float64}()
    for element in netlist.elements
        element.model isa Union{PowerImpedance.TLC, PowerImpedance.MMC} || continue
        for terminal in element.terminals
            terminal.grounded && continue
            bus = terminal.bus
            (bus === nothing || bus.domain != 2) && continue
            key = root(bus)
            base = element.model isa PowerImpedance.MMC ?
                   element.model.elec.Sbase / element.model.elec.vDC_base :
                   element.model.elec.iDCbase
            if haskey(bases, key) && bases[key] != base
                throw(ArgumentError("DC current comparison for :$(element.name) is not yet supported in a DC network with different converter current bases"))
            end
            bases[key] = base
        end
    end
    return Dict(bus => bases[root(bus)]
    for bus in keys(parents) if haskey(bases, root(bus)))
end

"""
$(TYPEDSIGNATURES)

Compare settled AC/DC bus voltages, branch-terminal currents and
machine/converter operating points with a retained power flow.
Compare only the channels in `model.probes`; require solved data
and complete three-phase AC or scalar DC measurements for those channels.

# Arguments

- `result`: PSCAD time-domain output in manifest units.
- `model`: Exported model retaining netlist and operating-point evidence.

# Keywords

- `rtol_v`: Relative voltage tolerance, including MMC arm capacitor cycle
  means, default `0.01`.
- `atol_angle_deg`: Absolute relative-bus angle tolerance \\[deg\\], default `1.0`.
- `rtol_i`: Current magnitude tolerance, default `0.02`. AC currents and
  converter-free DC networks use relative error; converter-connected DC
  networks use the larger of the reference and converter DC current base.

# Returns

- A `TypedTables.Table` with `quantity`, probe `name`, `pscad`, `powerflow`,
  nonnegative `error`, and `within_tolerance` columns. Magnitudes use kV/kA,
  powers MW/MVAr (filtered converter powers in pu), and relative magnitude errors.
  All machine/converter power errors are normalized by the device rating \\[MVA\\],
  so filtered converter power errors are absolute pu differences.
  Speed uses pu and absolute error; angles use degrees and absolute wrapped errors. Omit the
  reference bus's own angle row. A zero magnitude reference without a converter
  DC current base uses zero error for a zero measurement and infinite error otherwise.
  MMC `:converter_arm_voltage` rows contain capacitor cycle means and solved
  pole-to-pole DC voltage in kV. `:converter_dc_current_identity` rows contain
  signed DC terminal current and `3*mean(iS_z)*Sbase/vDC_base` in kA; their
  `powerflow` column holds that measured identity reference, rather than a
  power-flow current. Both use their MMC signal probe names.

# Notes

The terminal-current reference is ``|S|/(3V_{LN})`` with power in MW/MVAr and
phase RMS voltage in kV. Series sides use `(pf, qf)` and `(pt, qt)` respectively;
sources use `(pg, qg)`. Shunt powers are retained from the solved bus voltage
and the power-flow input admittance. AC angles are relative to the manifest's reference bus.
DC bus voltage is the window mean of V_P - V_N, compared with twice the
pole-to-ground bus voltage. DC current magnitudes use the P-pole window mean
and the reference |P|/V_pp. Omit a DC current row when no solved terminal power
exists (for example a source without a gendc solution record).
For a DC network containing a TLC or MMC, current error is
`abs(measured-reference)/max(abs(reference), elec.Sbase/elec.vDCbase)` in kA,
using the converter's pole-to-pole DC voltage base (`elec.vDC_base` for MMC).
A DC network is the
connected component of nongrounded DC buses joined by an element's DC
terminals; AC terminals and shared ground do not join networks. This base
applies to converter terminals, DC branches and DC sources throughout that
component. Converter-free components retain relative error. Multiple
converters with the same current base are supported; differing bases require
a normalization decision and raise an error.
Machine P/Q use the three-phase fundamental power at the public bus,
``S = \\sum_k V_k I_k^*/2``, with peak phasors in kV/kA and current directed
from the machine to the bus. Compare with the retained `pf/qf` at that same
end of the rt/lt branch, using `abs(measured-reference)/elec.S_base <= 0.01`.
Reconstruct machine terminal phase RMS voltage from ``V_t = V_{bus} + ZI``,
where ``Z = R_{export} + \\mathrm{j}2\\pi f L_{export}`` \\[Ω\\] uses the
same formatted resistance and inductance as the emitter, and compare
its positive-sequence magnitude with the solved terminal voltage using
`rtol_v`. These rows use the current probe's name. Internal machine P/Q/Vt
and initialization/field channels remain diagnostics. Speed uses the scalar
mean and an absolute tolerance of `1e-3` pu around 1.
TLC/MMC terminal P/Q follow the same fundamental-phasor calculation, with current
from the converter to its AC bus and references `-pgrid/-qgrid` at side 2.
Their errors use `elec.Sbase` and tolerance `0.01`. Internal `P_ac_f/Q_ac_f`
means are pu on `elec.Sbase`, compared to those solved terminal powers divided
by `Sbase` with `abs(measured_pu-reference_pu) <= 0.01`, equivalently
`abs(diff_MW)/Sbase <= 0.01` (MVAr for Q). Julia's Q measurement uses a sine q basis:
`Q_ac = -v_q*i_d + v_d*i_q`, equal to standard injected reactive power.
Consequently its reference is `setpoint.Qac/Sbase`, also `-qgrid/Sbase`.
Converter DC voltage, frequency and angle channels remain diagnostics.
For each MMC arm capacitor probe, compare its settled cycle mean with the
solved DC bus pole-to-pole voltage using `abs(mean-reference)/abs(reference)`
and `rtol_v`. For each MMC `iS_z` probe (pu of `Sbase/vDC_base`), compare the
signed DC side-1 current mean with `3*mean(iS_z)*Sbase/vDC_base` in kA, using
`abs(diff)/max(abs(reference), Sbase/vDC_base)` and `rtol_i`. The `iS_z` mean
itself is diagnostic and is not asserted against its solved equilibrium value.
"""
function compare_operating_point(result::PSCADResult, model::PSCADModel;
        rtol_v = 0.01, atol_angle_deg = 1.0, rtol_i = 0.02)
    for tolerance in (rtol_v, atol_angle_deg, rtol_i)
        tolerance isa Real && isfinite(tolerance) && tolerance >= 0 ||
            throw(ArgumentError("comparison tolerances must be finite and nonnegative"))
    end
    model.netlist isa Netlist && model.operating_point isa OperatingPointRecord &&
    !isempty(model.operating_point.bus_states) ||
        throw(ArgumentError("model has no solved power-flow data for comparison"))
    settled = steady_state(result)
    dc_current_bases = _dc_converter_current_bases(model.netlist)
    quantities, names = Symbol[], String[]
    measured, expected, errors, passed = Float64[], Float64[], Float64[], Bool[]
    function add_row(
            quantity, name, actual, reference, tolerance, base = reference; angular = false,
            absolute = false)
        error = angular ? abs(rem2pi(deg2rad(actual - reference), RoundNearest)) * 180 / π :
                absolute ? abs(actual - reference) :
                iszero(base) ? (iszero(actual) ? 0.0 : Inf) :
                abs(actual - reference) / abs(base)
        push!(quantities, quantity)
        push!(names, name)
        push!(measured, actual)
        push!(expected, reference)
        push!(errors, error)
        push!(passed, error <= tolerance)
    end
    for channel in model.probes.channels
        if channel.kind in (:converter_arm_voltage, :converter_sum_current)
            channel.dim == 1 && _probe_present(channel, result.channels) ||
                throw(ArgumentError("missing PSCAD scalar MMC probe $(channel.name)"))
            e = only(filter(e -> string(e.name) == channel.element, model.netlist.elements))
            e.model isa PowerImpedance.MMC ||
                throw(ArgumentError("MMC probe $(channel.name) belongs to another model"))
            dc = only(filter(t -> t.side == 1 && !t.grounded, e.terminals))
            if channel.kind == :converter_arm_voltage
                bus = only(filter(b -> b.key == dc.bus, model.netlist.buses))
                _, point = _comparison_bus(model, bus.name)
                channel.unit == "kV" ||
                    throw(ArgumentError("MMC arm voltage probe $(channel.name) must use kV"))
                reference = 2point.vm_pu * bus.base_kV
                add_row(:converter_arm_voltage, channel.name, settled[channel.name].mean,
                    reference, rtol_v)
            else
                channel.unit == "pu" ||
                    throw(ArgumentError("MMC circulating current probe $(channel.name) must use pu"))
                current = only(filter(
                    c -> c.kind == :current && c.element == channel.element &&
                         c.side == "1",
                    model.probes.channels))
                current.dim == 1 && _probe_present(current, result.channels) ||
                    throw(ArgumentError("missing PSCAD MMC DC current probe $(current.name)"))
                current.unit == "kA" ||
                    throw(ArgumentError("MMC DC current probe $(current.name) must use kA"))
                base = e.model.elec.Sbase / e.model.elec.vDC_base
                reference = 3settled[channel.name].mean * base
                add_row(:converter_dc_current_identity,
                    channel.name, settled[current.name].mean,
                    reference, rtol_i, max(abs(reference), base))
            end
            continue
        end
        if channel.kind in (:converter_p, :converter_q)
            channel.dim == 1 && _probe_present(channel, result.channels) ||
                throw(ArgumentError("missing PSCAD scalar converter probe $(channel.name)"))
            index = findfirst(e -> string(e.name) == channel.element, model.netlist.elements)
            index === nothing &&
                throw(ArgumentError("missing power-flow converter $(channel.element)"))
            e = model.netlist.elements[index]
            flow = get(model.operating_point.branch_flows, e.name, nothing)
            field = channel.kind == :converter_p ? :pt : :qt
            flow !== nothing && haskey(flow, field) ||
                throw(ArgumentError("missing solved converter terminal data for :$(e.name)"))
            # Filtered powers use the native AC-injection Q convention and pu.
            # Both references are solved terminal flows divided by the rating.
            reference = flow[field] / e.model.elec.Sbase
            add_row(
                channel.kind, channel.name, settled[channel.name].mean, reference, 0.01;
                absolute = true)
            continue
        end
        if channel.kind == :machine_speed
            channel.dim == 1 && _probe_present(channel, result.channels) ||
                throw(ArgumentError("missing PSCAD scalar machine probe $(channel.name)"))
            element_index = findfirst(e -> string(e.name) == channel.element, model.netlist.elements)
            element_index === nothing &&
                throw(ArgumentError("missing power-flow machine $(channel.element)"))
            e = model.netlist.elements[element_index]
            flow = get(model.operating_point.branch_flows, e.name, nothing)
            flow !== nothing && haskey(flow, :terminal_voltage_kV) ||
                throw(ArgumentError("missing solved machine terminal data for :$(e.name)"))
            actual = settled[channel.name].mean
            add_row(:machine_speed, channel.name, actual, 1.0, 1e-3; absolute = true)
            continue
        end
        channel.kind in (:voltage, :current) || continue
        _probe_present(channel, result.channels) ||
            throw(ArgumentError("missing PSCAD probe $(channel.name)"))
        value = settled[channel.name]
        bus, point = _comparison_bus(model, channel.bus)
        voltage = point.vm_pu * bus.base_kV
        dc = bus.kind == :dc
        channel.dim == (dc ? 1 : 3) ||
            throw(ArgumentError("$(dc ? "DC comparison requires scalar" : "AC comparison requires three-phase") probe $(channel.name)"))
        if channel.kind == :voltage
            if dc
                channel.side in ("P", "N") ||
                    throw(ArgumentError("DC voltage probe $(channel.name) must identify its pole"))
                partner = findfirst(
                    c -> c.kind == :voltage && c.bus == bus.name &&
                         c.side == (channel.side == "P" ? "N" : "P"),
                    model.probes.channels)
                partner === nothing &&
                    throw(ArgumentError("missing opposite-pole voltage probe at $(bus.name)"))
                other = model.probes.channels[partner]
                other.dim == 1 && _probe_present(other, result.channels) ||
                    throw(ArgumentError("missing PSCAD scalar probe $(other.name)"))
                channel.side == "N" && continue
                actual = value.mean - settled[other.name].mean
                add_row(:voltage_dc, voltage_probe_name(bus.name), actual, 2voltage, rtol_v)
                continue
            end
            add_row(:voltage_rms, channel.name, value.rms, voltage, rtol_v)
            reference_name = model.probes.reference_bus
            reference_name === nothing &&
                throw(ArgumentError("voltage-angle comparison requires a reference bus"))
            if bus.name != reference_name
                probe = findfirst(c -> c.kind == :voltage && c.bus == reference_name, model.probes.channels)
                probe === nothing &&
                    throw(ArgumentError("missing reference-bus voltage probe $reference_name"))
                reference_probe = model.probes.channels[probe]
                _probe_present(reference_probe, result.channels) ||
                    throw(ArgumentError("missing PSCAD reference-bus voltage $reference_name"))
                _, reference_point = _comparison_bus(model, reference_name)
                actual = rad2deg(rem2pi(value.angle - settled[reference_probe.name].angle, RoundNearest))
                reference = rad2deg(rem2pi(point.va_rad - reference_point.va_rad, RoundNearest))
                add_row(:voltage_angle, channel.name, actual,
                    reference, atol_angle_deg; angular = true)
            end
        else
            element_index = findfirst(e -> string(e.name) == channel.element, model.netlist.elements)
            element_index === nothing &&
                throw(ArgumentError("missing power-flow element $(channel.element)"))
            e = model.netlist.elements[element_index]
            any(t -> string(t.side) == channel.side && t.bus == bus.key, e.terminals) ||
                throw(ArgumentError("missing terminal $(channel.element) side $(channel.side) at $(bus.name)"))
            flow = get(model.operating_point.branch_flows, e.name, nothing)
            if dc
                field = e.model isa PowerImpedance.Source ? :pgdc :
                        channel.side == "1" ? :pf : :pt
                (flow === nothing || !haskey(flow, field)) && continue
                voltage > 0 ||
                    throw(ArgumentError("current comparison requires positive bus voltage"))
                reference = abs(flow[field]) / (2voltage)
                base = max(reference, get(dc_current_bases, bus.key, 0.0))
                add_row(:current_dc, channel.name, abs(value.mean), reference, rtol_i, base)
                continue
            end
            flow === nothing &&
                throw(ArgumentError("missing power-flow current data for :$(e.name) side $(channel.side)"))
            fields = e.model isa PowerImpedance.Source ? (:pg, :qg) :
                     channel.side == "1" ? (:pf, :qf) : (:pt, :qt)
            all(field -> haskey(flow, field), fields) ||
                throw(ArgumentError("missing power-flow terminal powers for :$(e.name) side $(channel.side)"))
            voltage > 0 ||
                throw(ArgumentError("current comparison requires positive bus voltage"))
            current = hypot(flow[fields[1]], flow[fields[2]]) / (3 * voltage)
            add_row(:current_rms, channel.name, value.rms, current, rtol_i)
            if e.model isa Union{
                PowerImpedance.SynchronousMachine, PowerImpedance.TLC, PowerImpedance.MMC}
                machine = e.model isa PowerImpedance.SynchronousMachine
                machine && !haskey(flow, :terminal_voltage_kV) &&
                    throw(ArgumentError("missing solved machine terminal data for :$(e.name)"))
                index = findfirst(c -> c.kind == :voltage && c.bus == bus.name,
                    model.probes.channels)
                index === nothing &&
                    throw(ArgumentError("missing PSCAD voltage probe at $(bus.name)"))
                probe = model.probes.channels[index]
                probe.dim == 3 && _probe_present(probe, result.channels) ||
                    throw(ArgumentError("terminal power comparison requires three-phase voltage probe $(probe.name)"))
                v = settled[probe.name].phasors
                i = value.phasors
                power = sum(v .* conj.(i)) / 2
                elec = e.model.elec
                rating = machine ? elec.S_base : elec.Sbase
                add_row(machine ? :machine_p : :converter_p, channel.name, real(power),
                    flow[fields[1]], 0.01, rating)
                add_row(machine ? :machine_q : :converter_q, channel.name, imag(power),
                    flow[fields[2]], 0.01, rating)
                machine || continue
                zbase = elec.Vᵃᶜ_base^2 / elec.S_base
                r = _pscad_number(pscad_value(elec.rt * zbase))
                l = _pscad_number(pscad_value(elec.lt * zbase / elec.ωn))
                z = complex(r, 2π * result.settings.frequency * l)
                terminal_voltage = abs(_sequence_phasor(v .+ z .* i)) / sqrt(2)
                add_row(:machine_voltage, channel.name, terminal_voltage,
                    flow.terminal_voltage_kV, rtol_v)
            end
        end
    end
    return Table(quantity = quantities, name = names, pscad = measured,
        powerflow = expected, error = errors, within_tolerance = passed)
end

"""
$(TYPEDSIGNATURES)

Read channel names in PGB index order from legacy PSCAD INF metadata.
The first description keeps its name; later occurrences receive `group:desc`
names as in the MHI reader. Remaining collisions receive
`:2`, `:3`, … suffixes, retaining every scalar or array element distinctly.
Metadata is decoded as Windows-1252.
"""
function parse_inf(path::AbstractString)
    entries = _inf_entries(path)
    names = String[]
    used = Set{String}()
    descriptions = Set{String}()
    for entry in entries
        base = entry.desc in descriptions ? entry.group * ":" * entry.desc : entry.desc
        push!(descriptions, entry.desc)
        name = base
        index = 2
        while name in used
            name = base * ":" * string(index)
            index += 1
        end
        push!(names, name)
        push!(used, name)
    end
    return names
end

function _read_output_file(path::AbstractString, channels::Integer)
    times = Float64[]
    values = [Float64[] for _ in 1:channels]
    for (line_number, line) in enumerate(eachline(path))
        fields = split(strip(line))
        isempty(fields) && continue
        # Headers are optional. A numeric first field starts a data row, whose
        # remaining fields must all parse rather than being silently skipped.
        first_value = try
            _pscad_number(first(fields))
        catch error
            error isa ArgumentError || rethrow()
            continue
        end
        length(fields) == channels + 1 || throw(ArgumentError(
            "PSCAD output $path:$line_number has $(length(fields)) columns; expected $(channels + 1)"))
        row = _pscad_number.(fields)
        all(isfinite, row) ||
            throw(ArgumentError("PSCAD output contains nonfinite values: $path:$line_number"))
        push!(times, first_value)
        for index in eachindex(values)
            push!(values[index], row[index + 1])
        end
    end
    isempty(times) && throw(ArgumentError("PSCAD output contains no numeric rows: $path"))
    all(>(0), diff(times)) ||
        throw(ArgumentError("PSCAD output time must be strictly increasing: $path"))
    return times, values
end

"""
$(TYPEDSIGNATURES)

Read legacy PSCAD time-domain output from `dir` using filename `stem`.
The INF defines channel order; each numbered OUT contains time \\[s\\] and at
most ten channels. Optional headers and Fortran `D` exponents are accepted.
Require finite values, strictly increasing time, equal row counts, and identical
time columns across files. Return `(time, channels, inf, outs)` with channels in
an `OrderedDict` and output paths in file-number order.
"""
function read_pscad_output(dir::AbstractString; stem::AbstractString)
    occursin(r"^[A-Za-z][A-Za-z0-9_]{0,19}$", stem) ||
        throw(ArgumentError("invalid PSCAD output stem $stem"))
    inf = joinpath(abspath(dir), stem * ".inf")
    isfile(inf) || throw(ArgumentError("PSCAD INF file is missing: $inf"))
    names = parse_inf(inf)
    outs = [joinpath(abspath(dir), stem * "_" * lpad(string(index), 2, '0') * ".out")
            for index in 1:cld(length(names), 10)]
    channels = OrderedDict{String, Vector{Float64}}()
    time = Float64[]
    for (file_index, path) in enumerate(outs)
        isfile(path) || throw(ArgumentError("PSCAD OUT file is missing: $path"))
        offset = 10 * (file_index - 1)
        count = min(10, length(names) - offset)
        times, values = _read_output_file(path, count)
        if file_index == 1
            time = times
        else
            length(times) == length(time) ||
                throw(ArgumentError("PSCAD OUT files have unequal row counts: $path"))
            times == time ||
                throw(ArgumentError("PSCAD OUT files have different time columns: $path"))
        end
        for index in 1:count
            channels[names[offset + index]] = values[index]
        end
    end
    return (; time, channels, inf, outs)
end
