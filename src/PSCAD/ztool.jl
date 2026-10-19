const ZTOOL_VERSION = "v0.1.52"
const ZTOOL_URL = "https://raw.githubusercontent.com/Electa-Git/Z-tool/$ZTOOL_VERSION/Source/ztoolacdc/Scan/Z_tool.pslx"
const ZTOOL_SHA256 = "5924f4fbb112a110457b531016a9bd5c8f61125903044eb78d331feb607151ed"

"""
$(TYPEDEF)

Request a Z-tool scan block in a PSCAD export. Use `element` and `side` for a
series connection, or `bus` for an open shunt. `kind` is `:ac` or `:dc`.
Names are case-insensitively unique ASCII PSCAD identifiers, at most 30 characters.

The `voltage` keyword overrides the solved voltage in \\[kV\\]: AC peak
line-to-ground, or DC pole-to-pole. An unsolved bus requires this keyword.
`perturbation` is the per-unit injection amplitude (default `0.01`).
`vac_control`, `f_control` and `vdc_control` are Boolean flags (default `false`);
only the flags for the selected electrical domain are accepted.
Injection and decoupling times retain the library default of `1e8` \\[s\\].
The request leaves the network unchanged.

$(TYPEDFIELDS)
"""
struct ZToolProbe
    "Electrical domain, `:ac` or `:dc`."
    kind::Symbol
    "Scan instance identifier."
    name::String
    "Optional element designator for series placement."
    element::Union{Nothing, Symbol}
    "Optional element side for series placement."
    side::Union{Nothing, Int}
    "Optional PSCAD bus name or topology key for shunt placement."
    bus::Union{Nothing, String, BusKey}
    "Optional AC phase peak or DC pole-to-pole voltage \\[kV\\]."
    voltage::Union{Nothing, Float64}
    "Injection amplitude \\[pu\\]."
    perturbation::Float64
    "AC voltage control flag."
    vac_control::Bool
    "AC frequency control flag."
    f_control::Bool
    "DC voltage control flag."
    vdc_control::Bool

    function ZToolProbe(kind, name; element = nothing, side = nothing, bus = nothing,
            voltage = nothing, perturbation = 0.01, vac_control = nothing,
            f_control = nothing, vdc_control = nothing)
        kind isa Symbol && kind in (:ac, :dc) ||
            throw(ArgumentError("Z-tool probe $name: kind must be :ac or :dc"))
        name isa AbstractString && name == pscad_name(name) ||
            throw(ArgumentError("Z-tool probe $name: invalid PSCAD name"))
        series = element !== nothing && side !== nothing && bus === nothing
        shunt = element === nothing && side === nothing && bus !== nothing
        series || shunt || throw(ArgumentError(
            "Z-tool probe $name: specify element and side, or bus alone"))
        element === nothing || element isa Union{Symbol, AbstractString} ||
            throw(ArgumentError("Z-tool probe $name: element must be a designator"))
        side === nothing || (side isa Integer && !(side isa Bool) && 0 < side <= typemax(Int)) ||
            throw(ArgumentError("Z-tool probe $name: invalid side $side for element $element"))
        bus === nothing || bus isa Union{Symbol, AbstractString, BusKey} ||
            throw(ArgumentError("Z-tool probe $name: invalid bus $bus"))
        for (field, value) in ((:voltage, voltage), (:perturbation, perturbation))
            field == :voltage && value === nothing && continue
            value isa Real && !(value isa Bool) && isfinite(value) &&
                (field == :voltage ? value > 0 : value >= 0) && isfinite(Float64(value)) &&
                (field != :voltage || Float64(value) > 0) ||
                throw(ArgumentError("Z-tool probe $name: invalid $field $value"))
        end
        for (field, value) in ((:vac_control, vac_control), (:f_control, f_control),
            (:vdc_control, vdc_control))
            value === nothing && continue
            value isa Bool || throw(ArgumentError("Z-tool probe $name: $field must be Bool"))
            (kind == :ac ? field != :vdc_control : field == :vdc_control) ||
                throw(ArgumentError("Z-tool probe $name: $field does not apply to $kind"))
        end
        return new(kind, String(name), element === nothing ? nothing : Symbol(element),
            side, bus isa Union{Symbol, AbstractString} ? string(bus) : bus,
            voltage === nothing ? nothing : Float64(voltage), Float64(perturbation),
            something(vac_control, false), something(f_control, false),
            something(vdc_control, false))
    end
end

function _resolve_ztool_probes(netlist, probes)
    all(p -> p isa ZToolProbe, probes) ||
        throw(ArgumentError("ztool_probes must contain ZToolProbe values"))
    names = _NameReservations()
    terminals = Set{Tuple{Symbol, Int}}()
    return map(probes) do probe
        fail(reason) = throw(ArgumentError("Z-tool probe $(probe.name): $reason"))
        probe.name in names && fail("duplicate PSCAD name")
        push!(names, probe.name)
        terminal = if probe.element === nothing
            nothing
        else
            index = findfirst(e -> e.name == probe.element, netlist.elements)
            index === nothing && fail("unknown element :$(probe.element)")
            e = netlist.elements[index]
            index = findfirst(t -> t.side == probe.side, e.terminals)
            index === nothing && fail("unknown side $(probe.side) on element :$(e.name)")
            t = e.terminals[index]
            t.grounded && fail("element :$(e.name) side $(t.side) is grounded")
            key = (e.name, t.side)
            key in terminals && fail("element :$(e.name) side $(t.side) already has a scan probe")
            push!(terminals, key)
            t
        end
        index = findfirst(netlist.buses) do bus
            terminal === nothing ?
                (probe.bus isa BusKey ? bus.key == probe.bus : bus.name == probe.bus) :
                bus.key == terminal.bus
        end
        index === nothing && fail("unknown bus $(probe.bus)")
        bus = netlist.buses[index]
        (probe.kind == :dc) == (bus.kind == :dc) || fail(
            "$(probe.kind) probe on $(bus.kind) bus $(bus.name)" *
            (terminal === nothing ? "" : " at element :$(probe.element) side $(probe.side)"))
        voltage = if probe.voltage !== nothing
            probe.voltage
        elseif bus.vm_pu !== nothing
            bus.vm_pu * bus.base_kV * (probe.kind == :dc ? 2 : sqrt(2))
        else
            fail("bus $(bus.name) has no solved voltage; specify voltage in kV")
        end
        isfinite(voltage) && voltage > 0 || fail("bus $(bus.name) has invalid voltage $voltage")
        (; probe, bus, terminal, voltage)
    end
end

function _terminal_labels(e, terminal, context)
    terminal.grounded && return (nothing,)
    replacement = get(context.ztool_terminals, (e.name, terminal.side), nothing)
    replacement === nothing || return replacement
    bus = context.buses[terminal.bus]
    return bus.kind == :dc ? context.dc_labels[bus.key] : (bus.name,)
end

function _emit_ztool_probe!(state, scan, context)
    (; probe, bus, terminal, voltage) = scan
    probe.name in state.used && throw(ArgumentError(
        "Z-tool probe $(probe.name): PSCAD name is already used in this project"))
    push!(state.used, probe.name)
    params = ["Name" => probe.name, "f0" => pscad_value(context.settings.frequency),
        "V0_peak" => pscad_value(voltage), "V_perturb_mag" => pscad_value(probe.perturbation),
        "T_inj" => "1e8", "selector" => "0", "single_frequency" => "1",
        "Tdecoupling" => "1e8", "block_id" => "0"]
    append!(params, probe.kind == :ac ?
        ["Vac_control" => string(Int(probe.vac_control)), "f_control" => string(Int(probe.f_control))] :
        ["Vdc_control" => string(Int(probe.vdc_control))])
    x, y = allocate_cell!(state.layout)
    point = (x + 144, y + 72)
    dc = probe.kind == :dc
    push!(state.main.components, ComponentPlan(dc ? "Z_tool:DCscan" : "Z_tool:ACscan",
        params, point..., 0))
    width = dc ? 36 : 54
    labels = dc ? context.dc_labels[bus.key] : (bus.name,)
    stub!(state.main, (point[1] - width, point[2]), first(labels); direction = -1)
    if terminal !== nothing
        inner = context.ztool_terminals[(probe.element, probe.side)]
        stub!(state.main, (point[1] + width, point[2]), first(inner))
    end
    dc && stub!(state.main, (point[1], point[2] + 36), last(labels))
    return nothing
end

function _ztool_library(local_path = nothing; depot = first(DEPOT_PATH),
        url = ZTOOL_URL, expected_sha256 = ZTOOL_SHA256)
    if local_path !== nothing
        local_path isa AbstractString && isfile(local_path) ||
            throw(ArgumentError("Z-tool library does not exist: $local_path"))
        return (; path = abspath(local_path), sha256 = bytes2hex(open(sha256, local_path)))
    end
    path = joinpath(depot, "artifacts", "ztool", ZTOOL_VERSION, "Z_tool.pslx")
    if !isfile(path)
        mkpath(dirname(path))
        temporary = tempname(dirname(path))
        try
            Downloads.download(url, temporary)
            bytes2hex(open(sha256, temporary)) == expected_sha256 ||
                throw(ArgumentError("Z-tool library SHA-256 does not match $expected_sha256"))
            mv(temporary, path; force = true)
        finally
            isfile(temporary) && rm(temporary)
        end
    end
    digest = bytes2hex(open(sha256, path))
    digest == expected_sha256 || throw(ArgumentError("Z-tool cached library SHA-256 does not match $expected_sha256: $path"))
    return (; path, sha256 = digest)
end

function _ztool_frequency_tables(frequency)
    return ntuple(9) do index
        suffix = index == 1 ? "" : string(index - 1)
        sweep = index == 1 ? "frequency" : "multi-frequency"
        "Scan_options/frequencies$suffix.txt" =>
            "! This file stores the $sweep sweep values in Hz \n1\t$frequency\n2\t$frequency\nENDFILE:"
    end
end

function _write_ztool_frequency_tables(directory, tables)
    mkpath(joinpath(directory, "Scan_options"))
    for (name, contents) in tables
        path = joinpath(directory, name)
        ispath(path) || islink(path) || write(path, contents)
    end
    return nothing
end

function _ztool_workspace(project_name, project_file)
    # All three names are generated ASCII identifiers or fixed bundle filenames.
    return """<workspace name="$project_name" version="$PROJECT_FILE_VERSION" crc="0">
  <projects>
    <project type="library" name="Z_tool" filepath=".\\Z_tool.pslx" />
    <project type="project" name="$project_name" filepath=".\\$project_file" />
  </projects>
  <simulations />
  <pmr />
</workspace>
"""
end
