abstract type AbstractComponentPlan end

"""
$(TYPEDEF)

Describe one master-library instance in pixel coordinates.

$(TYPEDFIELDS)
"""
struct ComponentPlan <: AbstractComponentPlan
    "Library definition name, including its prefix."
    defn::String
    "String-valued master parameters in emission order."
    params::Vector{Pair{String, String}}
    "Horizontal location in pixels."
    x::Int
    "Vertical location in pixels."
    y::Int
    "PSCAD orientation code."
    orient::Int
end

"""
$(TYPEDEF)

Place an instance of a module defined in the project in pixel coordinates.

$(TYPEDFIELDS)
"""
struct ModuleInstancePlan <: AbstractComponentPlan
    "Project definition name, including its prefix."
    defn::String
    "Instance parameter values in emission order."
    params::Vector{Pair{String, String}}
    "Horizontal location in pixels."
    x::Int
    "Vertical location in pixels."
    y::Int
    "PSCAD orientation code."
    orient::Int
end

"""
$(TYPEDEF)

Describe one nonzero, axis-aligned wire with exactly two pixel vertices on
the 18-pixel PSCAD grid.

$(TYPEDFIELDS)
"""
struct WirePlan
    "Wire endpoint coordinates in pixels."
    vertices::Vector{NTuple{2, Int}}
    function WirePlan(vertices::Vector{NTuple{2, Int}})
        length(vertices) == 2 ||
            throw(ArgumentError("PSCAD wires require exactly two vertices"))
        a, b = vertices
        a != b && (a[1] == b[1] || a[2] == b[2]) ||
            throw(ArgumentError("PSCAD wires must be nonzero and axis-aligned"))
        all(point -> all(value -> value % 18 == 0, point), vertices) ||
            throw(ArgumentError("PSCAD wire coordinates must be multiples of 18 pixels"))
        return new(vertices)
    end
end

"""
$(TYPEDEF)

Store the component instances and wires of one schematic.

$(TYPEDFIELDS)
"""
struct CanvasPlan
    "Instances in emission order."
    components::Vector{AbstractComponentPlan}
    "Wire segments in emission order."
    wires::Vector{WirePlan}
    "Internal names reserved within this canvas."
    used::_NameReservations
    "Electrical node aliases for an empty series path."
    aliases::Dict{String, Union{Nothing, String}}
end
function CanvasPlan(components, wires)
    names = [value for c in components
             for (key, value) in c.params
             if key == "Name" && !isempty(value)]
    return CanvasPlan(components, wires, _NameReservations(names),
        Dict{String, Union{Nothing, String}}())
end
CanvasPlan() = CanvasPlan(AbstractComponentPlan[], WirePlan[])

"""
$(TYPEDEF)

Describe a module parameter with a real, integer or text default.

$(TYPEDFIELDS)
"""
struct ModuleParameterPlan{T <: Union{Float64, Int, String}}
    "Parameter identifier."
    name::String
    "Default value in the declared unit."
    default::T
    "PSCAD unit, or an empty string for dimensionless values and text."
    unit::String
end

"""
$(TYPEDEF)

Describe a module port on the 18-pixel grid.

$(TYPEDFIELDS)
"""
struct ModulePortPlan
    "Module signal or electrical node identifier."
    name::String
    "Port kind: `:input`, `:output`, or `:electrical`."
    kind::Symbol
    "Horizontal offset from the instance origin in pixels."
    x::Int
    "Vertical offset from the instance origin in pixels."
    y::Int
    "Signal or conductor count."
    dim::Int
    "PSCAD signal type code (3=real, 2=integer, 0=electrical)."
    datatype::Int
    function ModulePortPlan(name, kind, x, y, dim = 1, datatype = 3)
        kind in (:input, :output, :electrical) ||
            throw(ArgumentError("invalid module port kind: $kind"))
        x % 18 == y % 18 == 0 && dim > 0 ||
            throw(ArgumentError("module ports require grid coordinates and positive dimension"))
        return new(name, kind, x, y, dim, kind == :electrical ? 0 : datatype)
    end
end

"""
$(TYPEDEF)

Store a module's typed parameters, ports and schematic. Copy the canvas and
add parameter imports so each declared input has a schematic name.
Reuse existing signal imports.

$(TYPEDFIELDS)
"""
struct ModuleDefinitionPlan
    "Definition name without a project prefix."
    name::String
    "Typed parameters in form order."
    parameters::Vector{ModuleParameterPlan}
    "Module ports in graphics order."
    ports::Vector{ModulePortPlan}
    "Control schematic."
    canvas::CanvasPlan
    function ModuleDefinitionPlan(name, parameters, ports, canvas)
        schematic = CanvasPlan(copy(canvas.components), copy(canvas.wires))
        lower!(schematic, parameters)
        return new(name, parameters, ports, schematic)
    end
end

"""
$(TYPEDEF)

Store project settings as file parameter strings.

$(TYPEDFIELDS)
"""
struct SettingsPlan
    "Settings in emission order."
    params::Vector{Pair{String, String}}
end

abstract type AbstractLineDefinitionPlan end

"""
$(TYPEDEF)

Store one transmission-line row definition with tower coordinates before
sag correction. Parameter values use PSCAD field names and unit strings.

$(TYPEDFIELDS)
"""
struct LineDefinitionPlan <: AbstractLineDefinitionPlan
    "Row-definition name without a project prefix."
    name::String
    "Row kind, `:tline` for an overhead line."
    kind::Symbol
    "Universal-tower keyword parameters."
    tower::Vector{Pair{String, String}}
    "Phase bundle-centre tower coordinates \\[m\\], in physical order."
    conductors::Vector{NTuple{2, Float64}}
    "Ground-wire tower coordinates \\[m\\], in physical order."
    ground_wires::Vector{NTuple{2, Float64}}
    "Earth-return parameters."
    ground::Vector{Pair{String, String}}
    "Frequency/phase model and fitting parameters."
    frephase::Vector{Pair{String, String}}
    "Additional display parameters."
    outdisp::Vector{Pair{String, String}}
end

"""
$(TYPEDEF)

Store one cable row with a coaxial component per physical position and
shared earth-return and frequency/phase parameters.

$(TYPEDFIELDS)
"""
struct CableDefinitionPlan <: AbstractLineDefinitionPlan
    "Row-definition name without a project prefix."
    name::String
    "Coaxial cable instances in physical position order."
    cables::Vector{ComponentPlan}
    "Earth-return parameters."
    ground::Vector{Pair{String, String}}
    "Frequency/phase model and fitting parameters."
    frephase::Vector{Pair{String, String}}
    "Additional display parameters."
    outdisp::Vector{Pair{String, String}}
end

abstract type AbstractLineWrapperPlan end

"""
$(TYPEDEF)

Place one direct-connection transmission-line wrapper on Main. Its sending
and receiving terminals are at offsets `(-54, 18)` and `(54, 72)` pixels.

$(TYPEDFIELDS)
"""
struct TLineWrapperPlan <: AbstractLineWrapperPlan
    "Row-definition name without a project prefix."
    row::String
    "Horizontal origin in pixels."
    x::Int
    "Vertical origin in pixels."
    y::Int
    "Wrapper instance parameters."
    params::Vector{Pair{String, String}}
end

"""
$(TYPEDEF)

Place one cable wrapper on Main in remote-ends mode. Electrical terminals
belong to the paired cable interfaces. Wrapper vertices are graphical.

$(TYPEDFIELDS)
"""
struct CableWrapperPlan <: AbstractLineWrapperPlan
    "Row-definition name without a project prefix."
    row::String
    "Horizontal origin in pixels."
    x::Int
    "Vertical origin in pixels."
    y::Int
    "Wrapper instance parameters."
    params::Vector{Pair{String, String}}
end

"""
$(TYPEDEF)

Describe a passive, single-subsystem PSCAD project without Python resources.

$(TYPEDFIELDS)
"""
struct ProjectPlan
    "Project identifier."
    name::String
    "Project description."
    description::String
    "Simulation settings."
    settings::SettingsPlan
    "Main schematic."
    main::CanvasPlan
    "Transmission-line row definitions in emission order."
    lines::Vector{AbstractLineDefinitionPlan}
    "Transmission-line wrappers on Main in emission order."
    wrappers::Vector{AbstractLineWrapperPlan}
    "Control modules defined in the project, in emission order."
    modules::Vector{ModuleDefinitionPlan}
    "Emitted output channels and reference bus."
    probes::ProbeManifest
end

"""
$(TYPEDEF)

Summarize a written project for XML round-trip verification.

$(TYPEDFIELDS)
"""
struct ProjectSummary
    "Instance counts indexed by definition name with library or project prefix."
    components_per_defn::Dict{String, Int}
    "Node-label occurrence counts."
    nodelabels::Dict{String, Int}
    "PGB names in schematic order."
    pgbs::Vector{String}
    "Component counts per row-definition name without a project prefix."
    row_definitions::Dict{String, Dict{String, Int}}
    "Wrapper counts on Main, indexed by row-definition name with project prefix."
    wrappers_per_defn::Dict{String, Int}
    "Module ports indexed by module definition name without project prefix."
    modules_and_ports::Dict{String, Vector{ModulePortPlan}}
    "Project setting strings."
    settings::Dict{String, String}
    "Project file schema version."
    version::String
end

"""
$(TYPEDEF)

Allocate 432-by-216-pixel cells, six per row, starting at grid coordinate
`(4, 4)`. Each cell contains element instances or probes.

$(TYPEDFIELDS)
"""
mutable struct GridLayout
    "Index of the next cell, starting at zero."
    next::Int
end
GridLayout() = GridLayout(0)

"""
$(TYPEDSIGNATURES)

Reserve the next layout cell.

# Arguments

- `layout`: Grid with the next cell index.

# Returns

- `(x, y)`: Upper-left coordinates in pixels.
"""
function allocate_cell!(layout::GridLayout)
    index = layout.next
    layout.next += 1
    return (72 + 432 * (index % 6), 72 + 216 * (index ÷ 6))
end

struct PlanState
    main::CanvasPlan
    lines::Vector{AbstractLineDefinitionPlan}
    wrappers::Vector{AbstractLineWrapperPlan}
    modules::Vector{ModuleDefinitionPlan}
    layout::GridLayout
    channels::Vector{ProbeChannel}
    used::_NameReservations
end

function component!(canvas::CanvasPlan, defn, point, params = Pair{String, String}[])
    for (key, value) in params
        key == "Name" && !isempty(value) && push!(canvas.used, value)
    end
    push!(canvas.components, ComponentPlan("master:" * defn, params, point..., 0))
    return nothing
end
wire!(canvas::CanvasPlan, a, b) = push!(canvas.wires, WirePlan([a, b]))
function label!(canvas::CanvasPlan, name, point)
    name = get(canvas.aliases, lowercase(name), name)
    name === nothing ? component!(canvas, "ground", point) :
    component!(canvas, "nodelabel", point, ["Name" => name])
end

# An empty series path makes its endpoint labels denote the same node.
function join_node_labels!(canvas, left, right)
    left = left === nothing ? nothing : get(canvas.aliases, lowercase(left), left)
    right = right === nothing ? nothing : get(canvas.aliases, lowercase(right), right)
    left == right && return nothing
    keep, remove = left === nothing ? (left, right) :
                   right === nothing ? (right, left) : (left, right)
    for (key, value) in canvas.aliases
        value == remove && (canvas.aliases[key] = keep)
    end
    canvas.aliases[lowercase(remove)] = keep
    for (i, c) in enumerate(canvas.components)
        c.defn == "master:nodelabel" || continue
        lowercase(Dict(c.params)["Name"]) == lowercase(remove) || continue
        canvas.components[i] = keep === nothing ?
                               ComponentPlan(
            "master:ground", Pair{String, String}[], c.x, c.y, 0) :
                               ComponentPlan(c.defn, ["Name" => keep], c.x, c.y, c.orient)
    end
    return nothing
end

# A 36-pixel stub separates each orient-0 port from its label or ground.
function stub!(canvas::CanvasPlan, port, name; direction = 1)
    endpoint = (port[1] + 36 * direction, port[2])
    wire!(canvas, port, endpoint)
    name === nothing ? component!(canvas, "ground", endpoint) :
    label!(canvas, name, endpoint)
    return endpoint
end

function ammeter_stub!(canvas::CanvasPlan, port, bus, name; direction = 1)
    junction = pscad_name(name * "_node"; used = canvas.used)
    stub!(canvas, port, junction; direction)
    location = (port[1] + (direction == 1 ? 0 : -36), port[2] - 36)
    component!(canvas, "ammeter", location, ["Name" => name])
    inner = (port[1], location[2])
    endpoint = (inner[1], inner[2] - 36)
    wire!(canvas, inner, endpoint)
    label!(canvas, junction, endpoint)
    outer = (port[1] + 36 * direction, location[2])
    return stub!(canvas, outer, bus; direction)
end

function component_chain!(canvas::CanvasPlan, parts, start, stem, used)
    point = start
    for (i, (defn, parameter, value, unit)) in enumerate(parts)
        name = pscad_name(stem * "_" * parameter; used)
        component!(canvas, defn, point,
            ["Name" => name, parameter => pscad_value(value; unit)])
        if i < length(parts)
            junction = pscad_name(stem * "_junction_$i"; used)
            for pin in ((point[1] + 36, point[2]), (point[1] + 72, point[2]))
                endpoint = (pin[1], pin[2] + 36)
                wire!(canvas, pin, endpoint)
                label!(canvas, junction, endpoint)
            end
            point = (point[1] + 72, point[2])
        else
            point = (point[1] + 36, point[2])
        end
    end
    return point
end

# Port offsets follow the master components and the abc/dq transforms.
# Each port needs its own label stub for the connectivity check.
function component_ports(c::ComponentPlan, modules)
    p = Dict(c.params)
    d = c.defn
    electrical = true
    directions = Symbol[]
    offsets = if d in ("Z_tool:ACscan", "Z_tool:DCscan")
        pins = d == "Z_tool:ACscan" ? [(-54, 0), (54, 0)] :
               [(-36, 0), (36, 0), (0, 36)]
        return _placed_ports(c, pins, fill(:electrical, length(pins)),
            [:electrical, :optional_electrical, fill(:electrical, length(pins) - 2)...])
    elseif d in ("master:nodelabel", "master:datalabel", "master:ground")
        NTuple{2, Int}[]
    elseif d in ("master:resistor", "master:inductor", "master:capacitor", "master:ammeter")
        [(0, 0), (36, 0)]
    elseif d in ("master:voltmetergnd", "master:xnode")
        [(0, 0)]
    elseif d == "master:breaker1"
        [(-36, 0), (36, 0)]
    elseif d == "master:voltmeter"
        [(0, 0), (0, 36)]
    elseif d == "master:source_3"
        get(p, "Grnd", "1") == "1" || throw(ArgumentError("unsupported source_3 ports"))
        [(36, 0)]
    elseif d == "master:source_1"
        pins = get(p, "Grnd", "0") == "1" ? [(-36, 0)] : [(-36, 0), (36, 0)]
        get(p, "Cntrl", "0") == "1" && push!(pins, (0, 36))
        return _placed_ports(c, pins,
            [fill(:electrical, length(pins) - (get(p, "Cntrl", "0") == "1"));
             get(p, "Cntrl", "0") == "1" ? [:signal] : Symbol[]],
            [fill(:electrical, length(pins) - (get(p, "Cntrl", "0") == "1"));
             get(p, "Cntrl", "0") == "1" ? [:input] : Symbol[]])
    elseif d == "master:src_ccin_1"
        return _placed_ports(c, [(0, 0), (36, 0), (0, 36)],
            [:electrical, :electrical, :signal], [:electrical, :electrical, :input])
    elseif d == "master:breakout"
        [(0, 0), (36, -36), (36, 0), (36, 36)]
    elseif d == "master:cable_interface"
        [(-18, 54 * (i - 1)) for i in 1:parse(Int, p["NCAB"])]
    elseif d == "master:tline_interface"
        p["NC"] == "2" && p["View"] == "0" &&
            p["dim_s"] == p["dim_r"] == "0" ||
            throw(ArgumentError("unsupported tline_interface ports"))
        [(-18, -18), (-18, 18)]
    elseif d == "master:xfmr-3p2w"
        [(-54, 0), (36, 0)]
    elseif d == "master:sync_machine"
        return _placed_ports(c,
            [(36, 0), (-36, -72), (0, 72), (-36, 72), (36, -72), (-72, -72), (36, 72)],
            [:electrical; fill(:signal, 6)],
            [:electrical, :input, :input, :output, :output, :output, :output])
    elseif d == "master:wound_rotor"
        (p["View"], p["ERC"], p["MM"], p["SNP"]) == ("1", "0", "0", "1") ||
            throw(ArgumentError("unsupported wound_rotor ports"))
        return _placed_ports(c, [(54, 0), (-54, -36), (-54, 0), (-54, 36)],
            [:electrical, :signal, :signal, :signal],
            [:electrical, :input, :input, :input])
    else
        electrical = false
        if d in ("master:import", "master:export", "master:const",
            "master:emtconst", "master:time-sig")
            directions = [d == "master:export" ? :input : :output]
            [(36, 0)]
        elseif d == "master:pgb"
            directions = [:input]
            [(0, 0)]
        elseif d == "master:sumjct"
            any(k -> get(p, k, "0") != "0", ("A", "C", "E", "G")) &&
                throw(ArgumentError("unsupported sumjct ports"))
            pins = [point
                    for (key, point) in (("D", (-36, 0)), ("F", (0, 36)), ("B", (0, -36)))
                    if get(p, key, "0") != "0"]
            [pins; [(36, 0)]]
        elseif d in ("master:mult", "master:div", "master:dot_product")
            [(-36, 0), (0, 36), (36, 0)]
        elseif d == "master:datamerge" && c.orient == 4
            n = parse(Int, p["N"])
            # The orient-4 merge inputs already use canvas coordinates. For N=2,
            # the inputs are (-18,-72), (-18,-54) and the output is (0,-18).
            return [[((c.x - 18, c.y + 18 * (i - 5)), :signal, :input) for i in 1:n];
                    [((c.x, c.y + 18 * (n - 3)), :signal, :output)]]
        elseif d == "master:datatap" && c.orient == 0
            [(0, -18), (0, 0)]
        elseif d in ("master:gain", "master:integral", "master:trig", "master:sqrt",
            "master:square", "master:realpole", "master:tdelay", "master:trans_filt",
            "master:pi_ctl", "master:hardlimit", "master:compare", "master:leadlag",
            "master:force_dsout", "master:force_dsdyn", "master:zminusone")
            [(-36, 0), (36, 0)]
        else
            throw(ArgumentError("unknown ports for $(c.defn) at ($(c.x), $(c.y))"))
        end
    end
    if isempty(directions)
        directions = electrical ? fill(:electrical, length(offsets)) :
                     [fill(:input, length(offsets) - 1); :output]
    end
    return _placed_ports(
        c, offsets, fill(electrical ? :electrical : :signal, length(offsets)),
        directions)
end

function _placed_ports(c, offsets, kinds, directions)
    transform = if c.orient == 0
        (x, y) -> (x, y)
    elseif c.orient == 1
        (x, y) -> (-y, x)
    elseif c.orient == 3
        (x, y) -> (y, -x)
    elseif c.orient == 4
        (x, y) -> (-x, y)
    elseif c.orient == 6
        (x, y) -> (x, -y)
    else
        throw(ArgumentError("unknown orientation $(c.orient) for $(c.defn)"))
    end
    return [((c.x + dx, c.y + dy), kind, direction)
            for ((x, y), kind, direction) in zip(offsets, kinds, directions)
            for (dx, dy) in (transform(x, y),)]
end

function component_ports(c::ModuleInstancePlan, modules)
    c.orient == 0 || throw(ArgumentError("unknown module orientation $(c.orient)"))
    name = last(split(c.defn, ':'))
    haskey(modules, name) || throw(ArgumentError("unknown module ports for $(c.defn)"))
    return [((c.x + p.x, c.y + p.y), p.kind == :electrical ? :electrical : :signal, p.kind)
            for p in modules[name].ports]
end

"""
$(TYPEDSIGNATURES)

Check component ports, label stubs and signal drivers on one canvas.
Require a separate straight wire from each input or electrical port to a label
or ground. Each signal input requires exactly one driver on the same canvas.
Check isolated ideal-meter chains for a solvable ground connection.

# Arguments

- `canvas`: Components and wires to check, with coordinates in pixels.
- `name`: Canvas identifier for error messages.
- `modules`: Module definitions indexed by name. Default: an empty dictionary.

# Returns

- `nothing` if the connections satisfy the checks.

# Notes

With `PythonCall` loaded, `check_connectivity(path::AbstractString)` applies
the same checks to a saved project. PSCAD can relocate a component on load
without moving its wire endpoint.

# Errors

- Throws `ArgumentError` for abutting ports, missing or intersecting stubs,
  invalid coordinates, missing signal drivers or unsolvable ideal-meter chains.
"""
function check_connectivity(canvas::CanvasPlan, name, modules = Dict())
    fail(point, reason) = throw(ArgumentError("PSCAD canvas $name at $point: $reason"))
    for c in canvas.components
        _check_coordinate((c.x, c.y), name)
    end
    for w in canvas.wires, point in w.vertices
        _check_coordinate(point, name)
    end
    ports = Dict{NTuple{2, Int}, Symbol}()
    directions = Dict{NTuple{2, Int}, Symbol}()
    labels = Dict{NTuple{2, Int}, Symbol}()
    signal_names = Dict{NTuple{2, Int}, String}()
    drivers = Dict{String, Vector{NTuple{2, Int}}}()
    for c in canvas.components
        if c.defn in ("master:nodelabel", "master:datalabel", "master:ground")
            point = (c.x, c.y)
            haskey(labels, point) && fail(point, "coincident labels")
            labels[point] = c.defn == "master:datalabel" ? :signal : :electrical
            c.defn == "master:datalabel" &&
                (signal_names[point] = lowercase(Dict(c.params)["Name"]))
            if c.defn == "master:nodelabel" && get(Dict(c.params), "MeasV", "0") == "1"
                signal = get(Dict(c.params), "VName", "")
                isempty(signal) && fail(point, "measuring node label requires VName")
                push!(get!(drivers, lowercase(signal), NTuple{2, Int}[]), point)
            end
        else
            known_ports = try
                component_ports(c, modules)
            catch err
                err isa ArgumentError || rethrow()
                fail((c.x, c.y), sprint(showerror, err))
            end
            for (point, kind, direction) in known_ports
                haskey(ports, point) && fail(point, "coincident component ports")
                ports[point] = kind
                directions[point] = direction
            end
            # Meters and machine P/Q outputs publish signals by name without
            # explicit output ports.
            implicit_keys = c.defn in
                            ("master:ammeter", "master:voltmeter", "master:voltmetergnd") ?
                            ("Name",) :
                            c.defn == "master:sync_machine" ? ("POut", "QOut") :
                            c.defn == "master:wound_rotor" ?
                            ("MSF", "LSF", "Spd", "Tel", "TmOp", "ThetaR") : ()
            for key in implicit_keys
                value = get(Dict(c.params), key, "")
                isempty(value) || push!(get!(drivers, lowercase(value), NTuple{2, Int}[]),
                    (c.x, c.y))
            end
        end
    end
    for point in keys(labels)
        haskey(ports, point) && fail(point, "label abuts a component port")
    end
    ends = Set{NTuple{2, Int}}()
    points = union(Set(keys(ports)), Set(keys(labels)))
    connected_labels = Dict{NTuple{2, Int}, NTuple{2, Int}}()
    for w in canvas.wires
        length(w.vertices) == 2 || fail(first(w.vertices), "multi-segment wire")
        a, b = w.vertices
        a != b && (a[1] == b[1] || a[2] == b[2]) || fail(a, "wire is not straight")
        valid = (haskey(ports, a) && haskey(labels, b)) ||
                (haskey(labels, a) && haskey(ports, b))
        valid || fail(a, "wire $a → $b must join one component port and one label")
        port, label = haskey(ports, a) ? (a, b) : (b, a)
        ports[port] == labels[label] || fail(port, "electrical/control label mismatch")
        connected_labels[port] = label
        if directions[port] == :output
            push!(get!(drivers, signal_names[label], NTuple{2, Int}[]), port)
        end
        for point in (a, b)
            point in ends && fail(point, "shared wire endpoint")
            push!(ends, point)
            push!(points, point)
        end
    end
    # breaker1 reads NAME as a real-valued command through NINT(1-NAME),
    # so a symbolic command requires a timed signal driver.
    for c in canvas.components
        c isa ComponentPlan && c.defn == "master:breaker1" || continue
        command = get(Dict(c.params), "NAME", "")
        tryparse(Float64, command) === nothing || continue
        length(get(drivers, lowercase(command), NTuple{2, Int}[])) == 1 ||
            fail((c.x, c.y), "breaker1 NAME must have one signal driver")
    end
    # Sorted coordinates restrict each stub intersection search to its row or column.
    rows, columns = Dict{Int, Vector{Int}}(), Dict{Int, Vector{Int}}()
    for (x, y) in points
        push!(get!(rows, y, Int[]), x)
        push!(get!(columns, x, Int[]), y)
    end
    foreach(sort!, values(rows))
    foreach(sort!, values(columns))
    for w in canvas.wires
        a, b = w.vertices
        horizontal = a[2] == b[2]
        positions = horizontal ? rows[a[2]] : columns[a[1]]
        lo, hi = minmax(horizontal ? a[1] : a[2], horizontal ? b[1] : b[2])
        i = searchsortedlast(positions, lo) + 1
        if i <= length(positions) && positions[i] < hi
            point = horizontal ? (positions[i], a[2]) : (a[1], positions[i])
            fail(point, "wire passes through another port or label (junction)")
        end
    end
    occupied = Set{NTuple{2, Int}}()
    for w in canvas.wires
        a, b = w.vertices
        horizontal = a[2] == b[2]
        lo, hi = minmax(horizontal ? a[1] : a[2], horizontal ? b[1] : b[2])
        for position in lo:18:hi
            point = horizontal ? (position, a[2]) : (a[1], position)
            point in occupied && fail(point, "intersecting wires (junction)")
            push!(occupied, point)
        end
    end
    for c in canvas.components, (point, _, direction) in component_ports(c, modules)

        direction in (:input, :electrical) || continue
        haskey(connected_labels, point) ||
            fail(point, "$(c.defn) $direction port has no label stub")
        direction == :input || continue
        signal = signal_names[connected_labels[point]]
        writers = get(drivers, signal, NTuple{2, Int}[])
        length(writers) == 1 ||
            fail(point, "$(c.defn) input signal $signal has $(length(writers)) drivers; expected exactly one")
    end
    for point in keys(labels)
        point in ends || fail(point, "label has no component port stub")
    end
    for c in canvas.components
        c.defn == "master:nodelabel" && get(Dict(c.params), "MeasV", "0") == "1" || continue
        point = (c.x, c.y)
        port = only(p for (p, label) in connected_labels if label == point)
        owner = only(filter(canvas.components) do candidate
            any(p -> first(p) == port, component_ports(candidate, modules))
        end)
        owner.defn in ("master:voltmeter", "master:voltmetergnd") &&
            fail(point, "measuring node label must tap a conducting branch, not a voltage-only stub")
    end
    _check_meter_grounding(canvas, name, modules)
    return nothing
end

# A series chain of ideal meters can make an isolated winding unsolvable.
# A source in that circuit supplies a voltage reference.
function _check_meter_grounding(canvas, name, modules)
    parent = Dict{String, String}()
    root(n) = get!(parent, n, n) == n ? n : (parent[n] = root(parent[n]))
    join(a, b) = (parent[root(a)] = root(b))
    attachments = Dict{String, Vector{Int}}()
    anchors = Set(["\0ground"])
    sources = Set{String}()
    meters = Tuple{String, String, String, String, NTuple{2, Int}}[]
    cables = Dict{Tuple{String, Int}, String}()
    function collect_canvas(current, scope, bindings)
        labels = Dict((c.x, c.y) => (c.defn == "master:ground" ? "\0ground" :
                       scope * ":" * lowercase(Dict(c.params)["Name"]))
        for c in current.components if c.defn in ("master:nodelabel", "master:ground"))
        stubs = Dict{NTuple{2, Int}, String}()
        for w in current.wires
            a, b = w.vertices
            haskey(labels, a) && (stubs[b] = labels[a])
            haskey(labels, b) && (stubs[a] = labels[b])
        end
        for c in current.components
            c.defn == "master:xnode" || continue
            internal = stubs[(c.x, c.y)]
            port = Dict(c.params)["Name"]
            haskey(bindings, port) ? join(internal, bindings[port]) :
            push!(anchors, internal)
        end
        for c in current.components
            pins = [point
                    for (point, kind) in component_ports(c, modules)
                    if kind == :electrical]
            isempty(pins) && continue
            nets = [get(stubs, p, scope * ":open:$p") for p in pins]
            if c isa ModuleInstancePlan
                definition = modules[last(split(c.defn, ':'))]
                if isempty(definition.canvas.components)
                    # The sending and receiving terminals connect the line to both circuits.
                    join(first(nets), last(nets))
                    for n in nets
                        push!(get!(attachments, n, Int[]), 0)
                    end
                else
                    ports = filter(p -> p.kind == :electrical, definition.ports)
                    collect_canvas(definition.canvas, scope * "/$(c.x),$(c.y)",
                        Dict(p.name => n for (p, n) in zip(ports, nets)))
                end
                continue
            end
            c.defn in ("master:voltmeter", "master:voltmetergnd", "master:xnode") &&
                continue
            if c.defn in ("master:ammeter", "Z_tool:ACscan", "Z_tool:DCscan")
                push!(meters, (nets[1], nets[2], Dict(c.params)["Name"], scope, pins[1]))
                for n in nets[1:2]
                    push!(get!(attachments, n, Int[]), length(meters))
                end
            else
                for n in nets
                    push!(get!(attachments, n, Int[]), 0)
                end
                if c.defn in ("master:resistor", "master:inductor",
                    "master:capacitor", "master:breakout")
                    for n in nets[2:end]
                        if "\0ground" in (first(nets), n)
                            push!(anchors, first(nets) == "\0ground" ? n : first(nets))
                        else
                            join(first(nets), n)
                        end
                    end
                elseif c.defn in ("master:source_1", "master:source_3",
                    "master:src_ccin_1", "master:sync_machine")
                    union!(anchors, nets)
                    union!(sources, nets)
                elseif c.defn in ("master:cable_interface", "master:tline_interface")
                    for (i, n) in enumerate(nets)
                        key = (scope * ":" * lowercase(Dict(c.params)["Name"]), i)
                        haskey(cables, key) ? join(n, cables[key]) : (cables[key] = n)
                    end
                end
                # The transformer windings are separate galvanic circuits.
            end
        end
        return nothing
    end
    collect_canvas(canvas, String(name), Dict{String, String}())
    # Resolve module-port bindings and conducting branches before counting
    # meter junctions across module connections.
    grouped = Dict{String, Vector{Int}}()
    for (n, branches) in attachments
        append!(get!(grouped, root(n), Int[]), branches)
    end
    attachments = grouped
    meters = [(root(a), root(b), signal, scope, point)
              for (a, b, signal, scope, point) in meters]
    anchors, sources = Set(root.(collect(anchors))), Set(root.(collect(sources)))
    bare(n) = n ∉ anchors && length(get(attachments, n, Int[])) == 2 &&
              all(!=(0), attachments[n])
    # A source supplies the voltage reference for its connected circuit.
    # Separate shunts to ground do not connect otherwise isolated circuits.
    adjacent = Dict{String, Vector{String}}()
    for (a, b, _, _, _) in meters
        a, b = root(a), root(b)
        root("\0ground") in (a, b) && continue
        push!(get!(adjacent, a, String[]), b)
        push!(get!(adjacent, b, String[]), a)
    end
    source_islands = Set(root.(collect(sources)))
    pending = collect(source_islands)
    while !isempty(pending)
        for n in get(adjacent, pop!(pending), String[])
            n in source_islands && continue
            push!(source_islands, n)
            push!(pending, n)
        end
    end
    visited = Set{Int}()
    blocked = Tuple{String, String, Vector{Int}}[]
    for (i, meter) in enumerate(meters)
        i in visited && continue
        a, b = meter[1:2]
        bare(a) && bare(b) && continue
        bare(a) && ((a, b) = (b, a))
        chain = [i]
        push!(visited, i)
        while bare(b)
            j = only(filter(!=(last(chain)), attachments[b]))
            j in visited && break
            push!(chain, j)
            push!(visited, j)
            m = meters[j]
            b = m[1] == b ? m[2] : m[1]
        end
        if length(chain) == 1
            join(a, b)
        else
            push!(blocked, (a, b, chain))
        end
    end
    anchored = union(Set(root.(collect(anchors))), Set(root.(collect(source_islands))))
    for (a, b, chain) in blocked
        # A direct branch or a source connection at both endpoints supplies
        # the voltage references needed by the ideal-meter chain.
        root(a) in anchored && root(b) in anchored && continue
        root(a) == root(b) && continue
        root(a) in anchored || root(b) in anchored || continue
        m = meters[first(chain)]
        names = Base.join([meters[i][3] for i in chain], ", ")
        throw(ArgumentError("PSCAD canvas $(m[4]) at $(m[5]): isolated part reaches ground/source only through series ideal meters $names; intermediate nodes have no other conducting branch"))
    end
    return nothing
end

function _check_module_electrical_parameters(m, modules)
    # PSCAD requires numeric literals for electrical parameters such as arm L/R.
    # Symbolic values fail compilation.
    for c in m.canvas.components
        c isa ComponentPlan || continue
        any(p -> p[2] == :electrical, component_ports(c, modules)) || continue
        for (field, value) in c.params
            field == "Name" && continue # Component/probe identifiers are metadata.
            literal = match(
                r"^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*(?:\[[^\[\]\r\n]+\])?\s*$",
                value)
            number = isnothing(literal) ? nothing : tryparse(Float64, literal[1])
            if isnothing(number) || !isfinite(number)
                throw(ArgumentError("PSCAD module $(m.name) at ($(c.x), $(c.y)): $(c.defn) electrical parameter $field=$value requires a finite numeric literal; symbolic electrical parameters require saved station evidence"))
            end
        end
    end
    return nothing
end

function check_connectivity(plan::ProjectPlan)
    modules = Dict(m.name => m for m in plan.modules)
    # A direct transmission-line wrapper has electrical terminals at its first
    # and last vertices and must be checked as a component.
    main = CanvasPlan(copy(plan.main.components), copy(plan.main.wires))
    for w in plan.wrappers
        w isa TLineWrapperPlan || continue # Cable wrappers have no electrical terminals.
        Dict(w.params)["Mode"] == "1" || continue # Remote interfaces own the terminals.
        ports = [ModulePortPlan("sending", :electrical, -54, 18),
            ModulePortPlan("receiving", :electrical, 54, 72)]
        modules[w.row] = ModuleDefinitionPlan(w.row, ModuleParameterPlan[], ports, CanvasPlan())
        push!(main.components, ModuleInstancePlan(plan.name * ":" * w.row,
            Pair{String, String}[], w.x, w.y, 0))
    end
    check_connectivity(main, "Main", modules)
    for m in plan.modules
        _check_module_electrical_parameters(m, modules)
        check_connectivity(m.canvas, m.name, modules)
    end
    # Line-row definitions contain material and geometry data without
    # electrical ports or wires.
    for row in plan.lines
        if row isa CableDefinitionPlan
            seen = Set{NTuple{2, Int}}()
            for c in row.cables
                point = (c.x, c.y)
                c.defn == "master:Cable_Coax" && c.orient == 0 ||
                    throw(ArgumentError("PSCAD canvas $(row.name) at $point: unknown row record ports for $(c.defn)"))
                point in seen &&
                    throw(ArgumentError("PSCAD canvas $(row.name) at $point: coincident row records"))
                push!(seen, point)
            end
        end
    end
    return nothing
end

function emit!(state::PlanState, e::NetlistElement, context)
    throw(ArgumentError("PSCAD export of :$(e.name) ($(typeof(e.model))) is not implemented yet"))
end

function check_geometry end

function _check_coordinate(point, name)
    all(value -> 0 <= value <= 14382, point) || throw(ArgumentError(
        "PSCAD canvas $name at $point: coordinates must lie in [0, 14382]"))
    return nothing
end
