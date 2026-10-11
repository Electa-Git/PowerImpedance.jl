abstract type AbstractComponentPlan end

"""
$(TYPEDEF)

Describe one master-library instance in pixel coordinates.

$(TYPEDFIELDS)
"""
struct ComponentPlan <: AbstractComponentPlan
    "Qualified library definition."
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

Place an instance of a project-owned module in pixel coordinates.

$(TYPEDFIELDS)
"""
struct ModuleInstancePlan <: AbstractComponentPlan
    "Qualified project definition."
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
    "Two endpoint coordinates in pixels."
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

Retain the component instances and wires of one schematic.

$(TYPEDFIELDS)
"""
struct CanvasPlan
    "Instances in emission order."
    components::Vector{AbstractComponentPlan}
    "Wire segments in emission order."
    wires::Vector{WirePlan}
    "Canvas-owned internal name reservations."
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

Describe a module boundary port on the 18-pixel grid.

$(TYPEDFIELDS)
"""
struct ModulePortPlan
    "Boundary signal or electrical node identifier."
    name::String
    "Port kind: `:input`, `:output`, or `:electrical`."
    kind::Symbol
    "Horizontal offset from the instance origin in pixels."
    x::Int
    "Vertical offset from the instance origin in pixels."
    y::Int
    "Signal or conductor count."
    dim::Int
    "PSCAD signal type: 3 for real, 2 for integer, 0 for electrical."
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

Retain a project-owned module's typed form, graphics ports and schematic.
Copy the supplied canvas and lower its parameter imports so each declared
input parameter has a schematic binding. Existing signal imports are reused.

$(TYPEDFIELDS)
"""
struct ModuleDefinitionPlan
    "Unqualified definition identifier."
    name::String
    "Typed parameters in form order."
    parameters::Vector{ModuleParameterPlan}
    "Boundary ports in graphics order."
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

Retain project settings as file parameter strings.

$(TYPEDFIELDS)
"""
struct SettingsPlan
    "Settings in emission order."
    params::Vector{Pair{String, String}}
end

abstract type AbstractLineDefinitionPlan end

"""
$(TYPEDEF)

Retain one transmission-line row definition with tower coordinates before
sag correction. Parameter values use PSCAD field names and unit strings.

$(TYPEDFIELDS)
"""
struct LineDefinitionPlan <: AbstractLineDefinitionPlan
    "Unqualified row-definition identifier."
    name::String
    "Row kind; `:tline` for an overhead line."
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

Retain one cable row with a coaxial component per physical position and
shared earth-return and frequency/phase parameters.

$(TYPEDFIELDS)
"""
struct CableDefinitionPlan <: AbstractLineDefinitionPlan
    "Unqualified row-definition identifier."
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
    "Unqualified row-definition identifier."
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
belong to the paired cable interfaces; wrapper vertices are graphical.

$(TYPEDFIELDS)
"""
struct CableWrapperPlan <: AbstractLineWrapperPlan
    "Unqualified row-definition identifier."
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
    "Detached-run settings."
    settings::SettingsPlan
    "Main schematic."
    main::CanvasPlan
    "Transmission-line row definitions in emission order."
    lines::Vector{AbstractLineDefinitionPlan}
    "Transmission-line wrappers on Main in emission order."
    wrappers::Vector{AbstractLineWrapperPlan}
    "Project-owned control module definitions in emission order."
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
    "Instance counts keyed by qualified definition."
    components_per_defn::Dict{String, Int}
    "Node-label occurrence counts."
    nodelabels::Dict{String, Int}
    "PGB names in schematic order."
    pgbs::Vector{String}
    "Component counts per unqualified row-definition name."
    row_definitions::Dict{String, Dict{String, Int}}
    "Main wrapper counts keyed by qualified row-definition name."
    wrappers_per_defn::Dict{String, Int}
    "Boundary ports keyed by unqualified module definition name."
    modules_and_ports::Dict{String, Vector{ModulePortPlan}}
    "Project setting strings."
    settings::Dict{String, String}
    "Project file schema version."
    version::String
end

"""
$(TYPEDEF)

Allocate 432-by-216-pixel cells, six per row, starting at grid coordinate
`(4, 4)`. Each cell holds a group of element instances or probes.

$(TYPEDFIELDS)
"""
mutable struct GridLayout
    "Index of the next cell, starting at zero."
    next::Int
end
GridLayout() = GridLayout(0)

"""
$(TYPEDSIGNATURES)

Reserve the next cell and return its upper-left pixel coordinates.
"""
function allocate_cell!(layout::GridLayout)
    index = layout.next
    layout.next += 1
    return (72 + 432 * (index % 6), 72 + 216 * (index ÷ 6))
end

# Only the builder owns these mutable arrays and identifier reservations.
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

# An empty series path identifies nodes; it introduces no electrical device.
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

# Known orient-0 ports only: every label/ground stub is 36 pixels long.
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

# Offsets are the pins used by the saved canvases and the primitive lowering.
# Electrical witnesses: local/OHL/DUT_2.pscx:1689–1779 (transformer/passives),
# local/TLC/Simple_2L_VSC_RL.pscx:3377–3529,5589–5630 (breakout, source, xnode,
# meters). Control witnesses: the complete saved abc/dq canvases at 1851–3234;
# local/SG/SG_Project.pscx supplies the M3 primitives and machine pins (see doc).
function component_ports(c::ComponentPlan, modules)
    p = Dict(c.params)
    d = c.defn
    electrical = true
    directions = Symbol[]
    offsets = if d in ("master:nodelabel", "master:datalabel", "master:ground")
        NTuple{2, Int}[]
    elseif d in ("master:resistor", "master:inductor", "master:capacitor", "master:ammeter")
        [(0, 0), (36, 0)]
    elseif d in ("master:voltmetergnd", "master:xnode")
        [(0, 0)]
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
            # Saved orient-4 pins are already in canvas coordinates:
            # local/TLC/Simple_2L_VSC_RL.pscx:2214–2238,2857–2891,2937–2961.
            # For N=2 the inputs are (-18,-72), (-18,-54), output (0,-18).
            return [[((c.x - 18, c.y + 18 * (i - 5)), :signal, :input) for i in 1:n];
                    [((c.x, c.y + 18 * (n - 3)), :signal, :output)]]
        elseif d == "master:datatap" && c.orient == 0
            [(0, -18), (0, 0)]
        elseif d in ("master:gain", "master:integral", "master:trig", "master:sqrt",
            "master:square", "master:realpole", "master:tdelay", "master:trans_filt",
            "master:pi_ctl", "master:hardlimit", "master:compare", "master:leadlag")
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

Reject port abutment and every connection except a separate straight stub
between a known component port and a label or ground. Require every input and
electrical port to have a stub, and every signal input to have exactly one
driver on the same canvas. Reject isolated ideal-meter grounding chains.
Coordinates are pixels.
"""
function check_connectivity(canvas::CanvasPlan, name, modules = Dict())
    fail(point, reason) = throw(ArgumentError("PSCAD canvas $name at $point: $reason"))
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
            # Meter names and machine P/Q are implicit signal outputs, as saved
            # in local/TLC/Simple_2L_VSC_RL.pscx:4317–4337,5618–5630 and
            # local/SG/SG_Project.pscx:998–1198 (POut/QOut).
            implicit_keys = c.defn in
                            ("master:ammeter", "master:voltmeter", "master:voltmetergnd") ?
                            ("Name",) :
                            c.defn == "master:sync_machine" ? ("POut", "QOut") : ()
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
    # Sorted coordinate indices avoid scanning every canvas point per stub.
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
    _check_meter_grounding(canvas, name, modules)
    return nothing
end

# Native evidence: local/pscad-exchange/diag/yy_named-report/Main.dta:22–27
# contains two separate ideal A branches around B2; the load-return variant
# runs with the same passive parameters. Source-grounded chains remain valid.
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
            nets = [stubs[p] for p in pins]
            if c isa ModuleInstancePlan
                definition = modules[last(split(c.defn, ':'))]
                if isempty(definition.canvas.components)
                    # Transmission-line wrappers have known sending/receiving
                    # terminals (local/OHL/DUT_2.pscx:1798–1839).
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
            if c.defn == "master:ammeter"
                push!(meters, (nets[1], nets[2], Dict(c.params)["Name"], scope, pins[1]))
                for n in nets
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
                # Transformer ports are distinct galvanic islands; do not
                # connect the two windings (local/OHL/DUT_2.pscx:1707–1741).
            end
        end
        return nothing
    end
    collect_canvas(canvas, String(name), Dict{String, String}())
    # Canonicalize xnode bindings and ordinary branches before counting meter
    # junctions, including chains crossing an electrical module boundary.
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
    # A source anywhere in a galvanic island anchors that island, including
    # source-side meter chains. Ground is a boundary, not a route for joining
    # otherwise isolated islands through their separate shunts.
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
        # An alternate direct/source path anchors both endpoints and makes
        # this harmless, as on the passing small-AC/source-side constructions.
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
    # Literal electrical values: local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx:
    # 11345–11359. Symbolic arm L/R failed station compilation (M5 round 1).
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
    # A transmission-line wrapper is a component whose first/last vertices
    # are terminals, not an ordinary connecting wire. See OHL mapping doc.
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
    # Row definitions carry material/geometry records only, with no electrical
    # ports or connecting wires: local/Cable/DUT_2.pscx and local/OHL/DUT_2.pscx.
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
