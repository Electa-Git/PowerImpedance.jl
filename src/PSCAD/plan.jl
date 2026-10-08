"""
$(TYPEDEF)

Describe one master-library instance in pixel coordinates.

$(TYPEDFIELDS)
"""
struct ComponentPlan
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
    components::Vector{ComponentPlan}
    "Wire segments in emission order."
    wires::Vector{WirePlan}
end
CanvasPlan() = CanvasPlan(ComponentPlan[], WirePlan[])

"""
$(TYPEDEF)

Retain project settings as file parameter strings.

$(TYPEDFIELDS)
"""
struct SettingsPlan
    "Settings in emission order."
    params::Vector{Pair{String, String}}
end

"""
$(TYPEDEF)

Retain one transmission-line row definition with tower coordinates before
sag correction. Parameter values use PSCAD field names and unit strings.

$(TYPEDFIELDS)
"""
struct LineDefinitionPlan
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

Place one direct-connection transmission-line wrapper on Main. Its sending
and receiving terminals are at offsets `(-54, 18)` and `(54, 72)` pixels.

$(TYPEDFIELDS)
"""
struct TLineWrapperPlan
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
    lines::Vector{LineDefinitionPlan}
    "Transmission-line wrappers on Main in emission order."
    wrappers::Vector{TLineWrapperPlan}
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
    "Project setting strings."
    settings::Dict{String, String}
    "Project file schema version."
    version::String
end

"""
$(TYPEDEF)

Allocate 288-by-216-pixel cells, six per row, starting at grid coordinate
`(4, 4)`. Each cell holds one network element or one bus probe.

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
    return (72 + 288 * (index % 6), 72 + 216 * (index ÷ 6))
end

# Only the builder owns these mutable arrays and identifier reservations.
struct PlanState
    main::CanvasPlan
    lines::Vector{LineDefinitionPlan}
    wrappers::Vector{TLineWrapperPlan}
    layout::GridLayout
    channels::Vector{ProbeChannel}
    used::Set{String}
end

function component!(canvas::CanvasPlan, defn, point, params = Pair{String, String}[])
    push!(canvas.components, ComponentPlan("master:" * defn, params, point..., 0))
    return nothing
end
wire!(canvas::CanvasPlan, a, b) = push!(canvas.wires, WirePlan([a, b]))
function label!(canvas::CanvasPlan, name, point)
    component!(canvas, "nodelabel", point, ["Name" => name])
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
    location = (port[1] + (direction == 1 ? 0 : -36), port[2])
    component!(canvas, "ammeter", location, ["Name" => name])
    outer = (port[1] + 36 * direction, port[2])
    return stub!(canvas, outer, bus; direction)
end

function component_chain!(canvas::CanvasPlan, parts, start, stem, used)
    point = start
    for (defn, parameter, value, unit) in parts
        name = pscad_name(stem * "_" * parameter; used)
        component!(canvas, defn, point,
            ["Name" => name, parameter => pscad_value(value; unit)])
        # Consecutive orient-0 passive ports meet directly.
        point = (point[1] + 36, point[2])
    end
    return point
end

function emit!(state::PlanState, e::NetlistElement, context)
    throw(ArgumentError("PSCAD export of :$(e.name) ($(typeof(e.model))) is not implemented yet"))
end
