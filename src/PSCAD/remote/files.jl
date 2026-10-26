function _output_matches(roots, filename)
    matches = String[]
    for root in unique(filter(isdir, roots))
        for (directory, _, files) in walkdir(root), file in files

            lowercase(file) == lowercase(filename) &&
                push!(matches, realpath(joinpath(directory, file)))
        end
    end
    return sort!(unique!(matches))
end

function _data_rows(path::AbstractString)
    return count(eachline(path)) do line
        fields = split(strip(line))
        length(fields) >= 2 || return false
        return all(
            field -> tryparse(Float64, replace(field, 'D' => 'E', 'd' => 'e')) !== nothing,
            fields[1:2])
    end
end

# Legacy INF files are Windows-1252.
function _inf_text(path::AbstractString)
    bytes = read(path)
    special = ('€', '\u0081', '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹',
        'Œ', '\u008d', 'Ž', '\u008f', '\u0090', '‘', '’', '“', '”', '•', '–', '—',
        '˜', '™', 'š', '›', 'œ', '\u009d', 'ž', 'Ÿ')
    return join(byte in 0x80:0x9f ? special[Int(byte) - 0x7f] : Char(byte)
    for byte in bytes)
end

function _inf_entries(path::AbstractString)
    entries = NamedTuple{(:index, :desc, :group), Tuple{Int, String, String}}[]
    for line in split(_inf_text(path), '\n')
        desc = match(r"\bDesc=\"([^\"]*)\"", line)
        desc === nothing && continue
        isempty(desc[1]) &&
            throw(ArgumentError("PSCAD INF contains an empty channel name: $path"))
        pgb = match(r"PGB\((\d+)\)", line)
        group = match(r"\bGroup=\"([^\"]*)\"", line)
        push!(entries,
            (index = pgb === nothing ? length(entries) + 1 : parse(Int, pgb[1]),
                desc = String(desc[1]), group = group === nothing ? "" : String(group[1])))
    end
    isempty(entries) && throw(ArgumentError("PSCAD INF contains no channels: $path"))
    sort!(entries; by = entry -> entry.index)
    [entry.index for entry in entries] == collect(1:length(entries)) ||
        throw(ArgumentError("PSCAD INF channel indices must be consecutive from 1: $path"))
    return entries
end

"""
```text
_wait_outputs(roots, stem::AbstractString, expected_rows::Integer;
              timeout::Real = 60, poll_interval::Real = 0.25)
```

Wait for one INF file and all corresponding OUT files to stop changing size
across two polls. Check row counts only after the sizes stabilize.

# Arguments

- `roots`: Directories to search.
- `stem`: Output filename stem.
- `expected_rows`: Required numeric row count per OUT file.
- `timeout`: File stability timeout \\[s\\]. Default: `60`.
- `poll_interval`: Time between file checks \\[s\\]. Default: `0.25`.

# Returns

- `inf`: INF path.
- `outs`: Numbered OUT paths.

# Notes

Row counting runs outside the file stability timeout.
"""
function _wait_outputs(roots, stem::AbstractString, expected_rows::Integer;
        timeout::Real = 60, poll_interval::Real = 0.25)
    expected_rows > 0 || throw(ArgumentError("expected_rows must be positive"))
    isfinite(timeout) && timeout > 0 ||
        throw(ArgumentError("timeout must be positive and finite"))
    isfinite(poll_interval) && poll_interval > 0 ||
        throw(ArgumentError("poll_interval must be positive and finite"))
    deadline = time() + timeout
    previous = nothing
    counted = Set{Tuple}()
    rows = Int[]
    found = String[]
    observed = "INF files found: []; rows per file: []"
    while time() < deadline
        matches = _output_matches(roots, stem * ".inf")
        length(matches) <= 1 ||
            throw(ArgumentError("PSCAD emitted multiple $(stem).inf files: $matches"))
        observed = "INF files found: $matches; rows per file: $rows"
        if length(matches) == 1
            inf = only(matches)
            # Incomplete INF metadata can be observed while PSCAD is still writing it.
            count = try
                length(_inf_entries(inf))
            catch error
                error isa ArgumentError || rethrow()
                0
            end
            outs = [joinpath(dirname(inf), stem * "_" * lpad(string(index), 2, '0') *
                                           ".out")
                    for index in 1:cld(count, 10)]
            found = filter(isfile, outs)
            observed = "INF files found: $matches; OUT files found: $found; rows per file: $rows; expected $expected_rows"
            state = (inf, count, filesize(inf), found, filesize.(found))
            if count > 0 && length(found) == length(outs) && state == previous &&
               state ∉ counted
                # Row counts run once per stable file state to avoid repeated full-file scans.
                push!(counted, state)
                rows = [_data_rows(path) for path in outs]
                observed = "INF files found: $matches; OUT files found: $found; rows per file: $rows; expected $expected_rows"
                any(>(expected_rows), rows) && throw(ArgumentError(
                    "PSCAD outputs did not become complete within $timeout seconds; last observed $observed"))
                if state[3] == filesize(inf) && state[5] == filesize.(outs) &&
                   all(==(expected_rows), rows)
                    return (; inf, outs)
                end
                previous = nothing
                sleep(poll_interval)
                continue
            end
            previous = state
        end
        sleep(poll_interval)
    end
    if isempty(counted)
        uncounted = "rows per file: $rows"
        rows = [_data_rows(path) for path in found]
        observed = replace(observed, uncounted => "rows per file: $rows")
    end
    throw(ArgumentError("PSCAD outputs did not become complete within $timeout seconds; last observed $observed"))
end

# The package and standalone runner use the same PSCAD parameter names
# and readback checks.
function _project_parameters(settings::AbstractDict)
    stem = settings["output_stem"]
    return Dict{String, Any}(
        "time_duration" => settings["time_duration"],
        "time_step" => settings["time_step_us"],
        "sample_step" => settings["sample_step_us"],
        "PlotType" => settings["plot_type"],
        "output_filename" => stem * ".out",
        "StartType" => "STANDARD",
        "SnapType" => haskey(settings, "snapshot_time") ? "ONLY_ONCE" : "NONE",
        "SnapTime" => get(settings, "snapshot_time", 0.0),
        "snapshot_filename" => stem * ".snp",
        "MrunType" => "STANDALONE",
        "Mruns" => 1)
end

function _verify_settings_readback(readback::AbstractDict, settings::AbstractDict)
    requested = _project_parameters(settings)
    Set(keys(readback)) == Set(keys(requested)) ||
        throw(ArgumentError("PSCAD settings readback has different parameter keys"))
    for (key, value) in requested
        record = readback[key]
        record isa AbstractDict && haskey(record, "requested") &&
        haskey(record, "observed") ||
            throw(ArgumentError("PSCAD settings readback is incomplete for $key"))
        for field in ("requested", "observed")
            observed = record[field]
            matches = if value isa AbstractFloat
                observed isa Real && !(observed isa Bool) && isfinite(observed) &&
                    isapprox(observed, value; rtol = 1e-9, atol = 0)
            else
                observed == value
            end
            matches || throw(ArgumentError(
                "PSCAD settings readback mismatch for $key ($field): expected $(repr(value)), found $(repr(observed))"))
        end
    end
    return readback
end
