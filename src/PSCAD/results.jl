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
    weights = cis.(-2π * result.settings.frequency .* result.time[window])
    for (name, group) in groups
        if haskey(group, 0)
            length(group) == 1 ||
                throw(ArgumentError("PSCAD channel $name mixes scalar and array entries"))
            settled[name] = (dim = 1, mean = mean(result.channels[group[0]][window]))
            continue
        end
        dim = length(group)
        Set(keys(group)) == Set(1:dim) ||
            throw(ArgumentError("PSCAD array channel $name has incomplete component indices"))
        if dim == 1
            settled[name] = (dim = 1, mean = mean(result.channels[group[1]][window]))
            continue
        end
        phasors = [2 / length(window) *
                   sum(result.channels[group[index]][window] .* weights)
                   for index in 1:dim]
        phasor = if dim == 3
            a = cis(2π / 3)
            (phasors[1] + a * phasors[2] + a^2 * phasors[3]) / 3
        else
            phasors
        end
        settled[name] = (dim = dim, phasors = phasors, peak = abs.(phasor),
            rms = abs.(phasor) ./ sqrt(2), angle = angle.(phasor))
    end
    return settled
end

function _comparison_bus(model, name)
    index = findfirst(bus -> bus.name == name, model.netlist.buses)
    index === nothing && throw(ArgumentError("missing power-flow bus for $name"))
    bus = model.netlist.buses[index]
    bus.kind in (:ac3_dq, :ac3_abc) ||
        throw(ArgumentError("comparison of DC bus $name is not implemented yet"))
    point = get(model.operating_point.bus_states, bus.key, nothing)
    point !== nothing && point.vm_pu !== nothing && point.va_rad !== nothing ||
        throw(ArgumentError("missing power-flow voltage for bus $name"))
    return bus, point
end

"""
$(TYPEDSIGNATURES)

Compare settled AC bus voltages and branch-terminal currents with a retained
power flow. Compare only the channels in `model.probes`; require solved data
and complete three-phase measurements for those channels.

# Arguments

- `result`: PSCAD time-domain output in kV and kA.
- `model`: Exported model retaining netlist and operating-point evidence.
- `rtol_v`: Relative phase RMS voltage tolerance, default `0.01`.
- `atol_angle_deg`: Absolute relative-bus angle tolerance \\[deg\\], default `1.0`.
- `rtol_i`: Relative current RMS tolerance, default `0.02`.

# Returns

- A `TypedTables.Table` with `quantity`, probe `name`, `pscad`, `powerflow`,
  nonnegative `error`, and `within_tolerance` columns. Magnitudes use kV/kA and
  relative errors; angles use degrees and absolute wrapped errors. Omit the
  reference bus's own angle row. A zero magnitude reference uses zero error
  for a zero measurement and infinite error otherwise.

# Notes

The terminal-current reference is ``|S|/(3V_{LN})`` with power in MW/MVAr and
phase RMS voltage in kV. Series sides use `(pf, qf)` and `(pt, qt)` respectively;
sources use `(pg, qg)`. Shunt powers are retained from the solved bus voltage
and the power-flow input admittance. Angles are relative to the manifest's
reference bus in each domain.
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
    quantities, names = Symbol[], String[]
    measured, expected, errors, passed = Float64[], Float64[], Float64[], Bool[]
    function add_row(quantity, name, actual, reference, tolerance; angular = false)
        error = angular ? abs(rem2pi(deg2rad(actual - reference), RoundNearest)) * 180 / π :
                iszero(reference) ? (iszero(actual) ? 0.0 : Inf) :
                abs(actual - reference) / abs(reference)
        push!(quantities, quantity)
        push!(names, name)
        push!(measured, actual)
        push!(expected, reference)
        push!(errors, error)
        push!(passed, error <= tolerance)
    end
    for channel in model.probes.channels
        channel.kind in (:voltage, :current) || continue
        _probe_present(channel, result.channels) ||
            throw(ArgumentError("missing PSCAD probe $(channel.name)"))
        channel.dim == 3 ||
            throw(ArgumentError("AC comparison requires three-phase probe $(channel.name)"))
        value = settled[channel.name]
        bus, point = _comparison_bus(model, channel.bus)
        voltage = point.vm_pu * bus.base_kV
        if channel.kind == :voltage
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
            terminal_index = findfirst(
                t -> string(t.side) == channel.side &&
                     t.bus == bus.key, e.terminals)
            terminal_index === nothing &&
                throw(ArgumentError("missing terminal $(channel.element) side $(channel.side) at $(bus.name)"))
            flow = get(model.operating_point.branch_flows, e.name, nothing)
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
