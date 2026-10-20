"""
$(TYPEDEF)

Store Z-tool admittances and execution records from a PSCAD sweep.
Every entry in `results` represents one Z-tool result file. Its `admittance`
array uses row, column, frequency order and units of siemens.
Rows and columns follow that file's `axes` header, including mixed AC/DC files.
The values use Z-tool's current signs and coordinate frame.

$(TYPEDFIELDS)
"""
struct ZToolResult{F, R} <: AbstractProblemResult
    "Sweep formulation used for this result."
    formulation::F
    "Frequencies in the result files, in \\[Hz\\]."
    frequencies::Vector{Float64}
    "Parsed result files, with names, axes and admittance arrays \\[S\\]."
    results::Vector{R}
    "Model simulation settings used to resolve sweep defaults."
    settings::SimulationSettings
    "Execution timing, reuse status, solver identity and Z-tool arguments."
    diagnostics::NamedTuple
    "Run directory, outputs, console, build messages and Z-tool metadata paths."
    paths::NamedTuple
end

function _ztool_complex(field, path, line; finite = true)
    value = tryparse(ComplexF64, strip(field, ('(', ')')))
    value !== nothing && (!finite || isfinite(value)) ||
        throw(ArgumentError("invalid Z-tool complex value at $path:$line: $field"))
    return value
end

"""
$(TYPEDSIGNATURES)

Read a Z-tool AC, DC or mixed AC/DC admittance file.
Z-tool writes the matrix entries in row order after the frequency column.
This reader keeps that order without conjugation or unit conversion.
The ratio of kA to kV gives siemens.

# Arguments

- `path`: Z-tool file named `<prefix>#Y_<type>#<block>-<side>[#...]#.txt`.
  Types are `AC`, `DC` and `ACDC`. Sides are 1 and 2.

# Returns

- A named tuple with `path`, parsed `name` (`type`, `blocks`, `sides`), `axes`,
  `frequencies` \\[Hz\\] and `admittance` \\[S\\].
  `admittance[row, column, frequency_index]` follows the header axis order.
  The filename's block order can differ from the header axis order.
  Repeated frequencies remain in their original rows.
  Nonfinite matrix entries keep the numerical outcome of a diverged simulation.

# Errors

Malformed names, headers, matrix sizes, nonfinite frequencies, nonpositive
frequencies and decreasing frequencies raise `ArgumentError`.
"""
function read_ztool_admittance(path::AbstractString)
    isfile(path) || throw(ArgumentError("Z-tool admittance file does not exist: $path"))
    matched = match(r"^(.+)#Y_(AC|DC|ACDC)#(.+)#\.txt$", basename(path))
    matched === nothing && throw(ArgumentError("invalid Z-tool admittance filename: $path"))
    blocks, sides = String[], Int[]
    for port in split(matched[3], '#')
        side = match(r"^(.*)-([12])$", port)
        side === nothing && throw(ArgumentError("invalid Z-tool block side in $path: $port"))
        push!(blocks, side[1])
        push!(sides, parse(Int, side[2]))
    end
    lines = readlines(path)
    length(lines) >= 2 || throw(ArgumentError("Z-tool admittance file has no data: $path"))
    header = split(strip(first(lines)))
    length(header) >= 2 && first(header) == "f" ||
        throw(ArgumentError("invalid Z-tool admittance header: $path"))
    axes = String.(header[2:end])
    length(unique(axes)) == length(axes) ||
        throw(ArgumentError("Z-tool admittance header repeats an axis: $path"))
    kind = Symbol(matched[2])
    ports = Set(block * "-" * string(side) for (block, side) in zip(blocks, sides))
    length(ports) == length(blocks) ||
        throw(ArgumentError("Z-tool filename repeats a block side: $path"))
    for axis in axes
        entry = match(r"^(.*)_(d|q|dc)$", axis)
        entry !== nothing && entry[1] in ports ||
            throw(ArgumentError("Z-tool header axis does not match its filename: $path: $axis"))
        (kind == :AC && entry[2] == "dc" || kind == :DC && entry[2] != "dc") &&
            throw(ArgumentError("Z-tool header axis does not match its scan type: $path: $axis"))
    end
    for port in ports
        present = filter(axis -> startswith(axis, port * "_"), axes)
        Set(present) in (Set([port * "_d", port * "_q"]), Set([port * "_dc"])) ||
            throw(ArgumentError("Z-tool header has incomplete axes for $port: $path"))
    end
    kind == :ACDC && !(any(axis -> endswith(axis, "_dc"), axes) && any(axis -> endswith(axis, "_d"), axes)) &&
        throw(ArgumentError("Z-tool ACDC header must contain AC and DC axes: $path"))
    n = length(axes)
    rows = [(index + 1, split(strip(line))) for (index, line) in enumerate(lines[2:end])
            if !isempty(strip(line))]
    isempty(rows) && throw(ArgumentError("Z-tool admittance file has no numeric rows: $path"))
    frequencies = Vector{Float64}(undef, length(rows))
    admittance = Array{ComplexF64}(undef, n, n, length(rows))
    for (k, (line, fields)) in enumerate(rows)
        length(fields) == 1 + n^2 ||
            throw(ArgumentError("Z-tool matrix row has the wrong number of entries at $path:$line"))
        frequency = _ztool_complex(first(fields), path, line)
        isreal(frequency) && real(frequency) > 0 ||
            throw(ArgumentError("Z-tool frequency must be positive and real at $path:$line"))
        frequencies[k] = real(frequency)
        for row in 1:n, column in 1:n
            admittance[row, column, k] = _ztool_complex(fields[1 + (row - 1) * n + column], path, line; finite = false)
        end
    end
    issorted(frequencies) || throw(ArgumentError("Z-tool frequencies decrease in $path"))
    return (; path = abspath(path), name = (; type = kind, blocks, sides), axes,
        frequencies, admittance)
end

function _ztool_output_names(record, stem)
    files = get(record, "files", nothing)
    files isa AbstractVector && !isempty(files) &&
        all(name -> name isa AbstractString && basename(name) == name, files) &&
        length(unique(files)) == length(files) ||
        throw(ArgumentError("Z-tool output record must list unique filenames"))
    for suffix in ("_power_flow.txt", "_angles.txt")
        stem * suffix in files || throw(ArgumentError("Z-tool output record is missing $stem$suffix"))
    end
    admittances = filter(name -> startswith(name, stem * "#Y_") && endswith(name, "#.txt"), files)
    isempty(admittances) && throw(ArgumentError("Z-tool sweep produced no admittance files"))
    return String.(admittances)
end

function _read_computation_result(model, scan::ZToolScan, settings, root, input, diagnostics)
    output = joinpath(root, "outputs")
    metadata = joinpath(output, "ztool.toml")
    record = TOML.parsefile(metadata)
    get(record, "version", nothing) == input["ztool"]["version"] ||
        throw(ArgumentError("Z-tool output has a different package version"))
    arguments = record["arguments"]
    for (key, value) in input["ztool"]["arguments"]
        observed = get(arguments, key, nothing)
        matches = key == "topology" ? observed isa AbstractString &&
                  basename(replace(observed, '\\' => '/')) == value :
                  observed == value
        matches || throw(ArgumentError("Z-tool argument readback differs for $key"))
    end
    names = _ztool_output_names(record, settings.output_stem)
    results = [read_ztool_admittance(joinpath(output, name)) for name in names]
    frequencies = first(results).frequencies
    all(result -> result.frequencies == frequencies, results) ||
        throw(ArgumentError("Z-tool result files have different frequency lists"))
    unique(frequencies) == arguments["freq"] ||
        throw(ArgumentError("Z-tool result frequencies differ from the resolved list"))
    return ZToolResult(scan, copy(frequencies), results, settings,
        merge(diagnostics, (; ztool = record)),
        (; run_directory = root, outputs = output, console = joinpath(output, "pscad-console.txt"),
            build_messages = joinpath(output, "build-messages.txt"), metadata))
end
