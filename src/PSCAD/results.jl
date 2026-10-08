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
