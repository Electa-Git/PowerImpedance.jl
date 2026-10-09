# Reserved EMTDC intrinsic identifiers (array indices omitted), from PSCAD
# 5.1 "Include Files": emtstor.h, rtconfig.h, s0.h, s1.h, branches.h,
# emtconst.h, fnames.h and warn.h. Fortran identifiers ignore letter case.
# https://www.pscad.com/webhelp-pscad-v5.1.0-ol/EMTDC/Custom_Model_Design/include_files.htm
const _EMTDC_RESERVED_SIGNALS = Set([
    "storl", "stori", "storf", "storc", "nstorc", "nstorf", "nstori", "nstorl",
    "this",
    "rtcl", "rtci", "rtcf", "rtcc", "nrtcl", "nrtci", "nrtcf", "nrtcc",
    "tfdata", "umecwdgdata", "umectfdata", "umecsatdata",
    "rdc", "ccin", "vdc", "gm", "ccgm", "ccli", "ggin", "ca",
    "cdctr", "mbus", "idealss", "enabccin",
    "time", "delt", "print", "fintim", "timezero", "firststep", "laststep", "onstep",
    "cbr", "ccbr", "ccbrd", "ebr", "ebrd", "ebron", "ebrof", "swlevl",
    "geq", "geqon", "geqof", "geqd", "rlg", "rcg", "rcl", "rsc",
    "rsl", "ccl", "ccld", "ccc", "cccd", "g2l", "g2c", "v12l",
    "v20l", "nsw", "brnsw", "ief", "iet", "thisbr", "resistor", "inductor",
    "capacitr", "source", "switch", "idealbr", "openbr", "defrdbr", "flipidlbr", "geqchange",
    "ec_diode", "ec_thyristor", "ec_gto", "ec_igbt", "ec_mosfet",
    "ec_transistor", "ec_vzno", "ec_vsrc",
    "ec_csrc1p", "ec_csrc3p",
    "pi_", "two_pi", "pi_by3", "pi2_by3", "pi_by2", "pi_by180", "by180_pi", "by_pi",
    "by_2pi", "sqrt_2", "sqrt_3", "sqrt_1by2", "sqrt_1by3",
    "dumlin", "section", "filename", "mapname", "netdata", "inam", "tnam", "inam1",
    "onam", "snam", "rtsnam", "mnam", "iunit", "iunitout",
    "comp_id1", "comp_id2"
])

"""
$(TYPEDEF)

Identify a scalar or array control signal by its canvas-local datalabel name.

$(TYPEDFIELDS)
"""
struct Signal
    "ASCII signal identifier."
    name::String
    function Signal(name::AbstractString)
        name == pscad_name(name) || throw(ArgumentError("invalid PSCAD signal name: $name"))
        lowercase(name) in _EMTDC_RESERVED_SIGNALS &&
            throw(ArgumentError("reserved EMTDC signal name: $name"))
        return new(name)
    end
end

abstract type ControlBlock end
const BlockValue = Union{Float64, String}
block_value(value::Real; unit = nothing) = pscad_value(value; unit)
function block_value(value::AbstractString; unit = nothing)
    occursin(r"^[A-Za-z][A-Za-z0-9_]*$", value) ||
        throw(ArgumentError("control values require a number or plain module parameter name: $value"))
    return String(value)
end

"""
$(TYPEDEF)

Multiply a scalar signal by a dimensionless gain or named module parameter.

$(TYPEDFIELDS)
"""
struct Gain <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
    "Multiplying gain."
    g::BlockValue
end

"""
$(TYPEDEF)

Add or subtract up to three scalar inputs using the D, F and B master pins.
Unused A through G pins remain disabled.

$(TYPEDFIELDS)
"""
struct Sum <: ControlBlock
    "Inputs in D, F, B order."
    inputs::Vector{Signal}
    "Each input's sign, either +1 or -1."
    signs::Vector{Int}
    "Output signal."
    output::Signal
    function Sum(inputs, signs, output)
        1 <= length(inputs) <= 3 && length(inputs) == length(signs) &&
        all(sign -> sign in (-1, 1), signs) ||
            throw(ArgumentError("Sum requires one to three inputs with signs +1 or -1"))
        return new(inputs, signs, output)
    end
end

"""
$(TYPEDEF)

Represent the scalar transfer function `g/(1 + s*t)` with a time-zero output.

$(TYPEDFIELDS)
"""
struct RealPole <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
    "Dimensionless gain or module parameter name."
    g::BlockValue
    "Time constant \\[s\\] or module parameter name."
    t::BlockValue
    "Initial output in signal units or module parameter name."
    y0::BlockValue
end

"""
$(TYPEDEF)

Represent the scalar transfer function `(1 + s*t1)/(1 + s*t2)`.

$(TYPEDFIELDS)
"""
struct LeadLag <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
    "Lead time constant \\[s\\] or module parameter name."
    t1::BlockValue
    "Lag time constant \\[s\\] or module parameter name."
    t2::BlockValue
    "Initial output in signal units or module parameter name."
    y0::BlockValue
end

"""
$(TYPEDEF)

Produce a literal scalar constant. Use `Import` for a module parameter value.

$(TYPEDFIELDS)
"""
struct Const <: ControlBlock
    "Output signal."
    output::Signal
    "Literal constant in signal units."
    value::Float64
end

"""
$(TYPEDEF)

Clamp a scalar signal to fixed lower and upper bounds.

$(TYPEDFIELDS)
"""
struct Limit <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
    "Lower bound in signal units or module parameter name."
    lo::BlockValue
    "Upper bound in signal units or module parameter name."
    hi::BlockValue
end

"""
$(TYPEDEF)

Import a module input port or parameter into its control schematic.

$(TYPEDFIELDS)
"""
struct Import <: ControlBlock
    "Boundary port or parameter name."
    name::String
    "Local output signal."
    output::Signal
end

"""
$(TYPEDEF)

Export a local control signal through a module output port.

$(TYPEDFIELDS)
"""
struct Export <: ControlBlock
    "Boundary output port name."
    name::String
    "Local input signal."
    input::Signal
end

"""
$(TYPEDEF)

Produce the current simulation time \\[s\\] for start-up comparisons.

$(TYPEDFIELDS)
"""
struct TimeStep <: ControlBlock
    "Simulation-time output signal."
    output::Signal
end

"""
$(TYPEDEF)

Produce integer 0 below a scalar threshold and 1 above it. Equality follows
the master's `INTR=0` comparison, as in the validation start-up circuit.

$(TYPEDFIELDS)
"""
struct Compare <: ControlBlock
    "Compared input signal."
    input::Signal
    "Integer output signal."
    output::Signal
    "Threshold in input units or module parameter name."
    threshold::BlockValue
end

"""
$(TYPEDEF)

Retain control blocks in visible lowering order. Signals join blocks by name;
blocks contain their own parameters and input/output identities.

$(TYPEDFIELDS)
"""
struct BlockGraph
    "Blocks in schematic order."
    nodes::Vector{ControlBlock}
end
BlockGraph() = BlockGraph(ControlBlock[])

function signal_stub!(canvas::CanvasPlan, point, signal::Signal; direction = 1)
    endpoint = (point[1], point[2] + 36 * direction)
    wire!(canvas, point, endpoint)
    component!(canvas, "datalabel", endpoint, ["Name" => signal.name])
    return nothing
end

function unary_block!(canvas, defn, point, params, input, output)
    component!(canvas, defn, point, params)
    signal_stub!(canvas, (point[1] - 36, point[2]), input)
    signal_stub!(canvas, (point[1] + 36, point[2]), output; direction = -1)
    return nothing
end

function lower!(canvas::CanvasPlan, node::Gain, point)
    unary_block!(canvas, "gain", point,
        ["G" => block_value(node.g), "Dim" => "1", "DPath" => "1"],
        node.input, node.output)
end

function lower!(canvas::CanvasPlan, node::Sum, point)
    params = [string(pin) => "0" for pin in 'A':'G']
    pins = (("D", -36, 0, 1), ("F", 0, 36, 1), ("B", 0, -36, -1))
    for (input, sign, (pin, dx, dy, direction)) in zip(node.inputs, node.signs, pins)
        params[Int(only(pin) - 'A') + 1] = pin => string(sign)
        signal_stub!(canvas, (point[1] + dx, point[2] + dy), input; direction)
    end
    append!(params, ["Dim" => "1", "DPath" => "1"])
    component!(canvas, "sumjct", point, params)
    signal_stub!(canvas, (point[1] + 36, point[2]), node.output; direction = -1)
    return nothing
end

function lower!(canvas::CanvasPlan, node::RealPole, point)
    unary_block!(canvas, "realpole", point,
        ["G" => block_value(node.g), "T" => block_value(node.t; unit = "s"),
            "YO" => block_value(node.y0), "Limit" => "0", "Reset" => "2", "Dim" => "1"],
        node.input, node.output)
end

function lower!(canvas::CanvasPlan, node::LeadLag, point)
    unary_block!(canvas, "leadlag", point,
        ["G" => "1.0", "T1" => block_value(node.t1; unit = "s"),
            "T2" => block_value(node.t2; unit = "s"), "YO" => block_value(node.y0),
            "Limit" => "0", "Reset" => "2", "Dim" => "1"], node.input, node.output)
end

function lower!(canvas::CanvasPlan, node::Limit, point)
    unary_block!(canvas, "hardlimit", point,
        ["UL" => block_value(node.hi), "LL" => block_value(node.lo), "Dim" => "1"],
        node.input, node.output)
end

function lower!(canvas::CanvasPlan, node::Const, point)
    component!(canvas, "const", point, ["Value" => block_value(node.value), "Dim" => "1"])
    signal_stub!(canvas, (point[1] + 36, point[2]), node.output; direction = -1)
end

function lower!(canvas::CanvasPlan, node::Import, point)
    component!(canvas, "import", point, ["Name" => node.name])
    signal_stub!(canvas, (point[1] + 36, point[2]), node.output; direction = -1)
end

function lower!(canvas::CanvasPlan, node::Export, point)
    component!(canvas, "export", point, ["Name" => node.name])
    signal_stub!(canvas, (point[1] + 36, point[2]), node.input; direction = -1)
end

function lower!(canvas::CanvasPlan, node::TimeStep, point)
    component!(canvas, "time-sig", point)
    signal_stub!(canvas, (point[1] + 36, point[2]), node.output; direction = -1)
end

function lower!(canvas::CanvasPlan, node::Compare, point)
    unary_block!(canvas, "compare", point,
        ["X" => block_value(node.threshold), "OL" => "0", "OH" => "1",
            "INTR" => "0", "Dim" => "1", "conv" => "1"], node.input, node.output)
end

"""
$(TYPEDSIGNATURES)

Lower a scalar control graph into `canvas`, four rows per column. Columns are
six grid units apart and rows four grid units apart for the original scalar
blocks. Converter primitives reserve larger cells for their additional pins
and expanded second-order sections. The default origin is `(72, 72)` pixels.
Return the mutated canvas.
"""
function lower!(canvas::CanvasPlan, graph::BlockGraph; origin = (72, 72))
    width = maximum(node -> first(block_pitch(node)), graph.nodes; init = 108)
    height = maximum(node -> last(block_pitch(node)), graph.nodes; init = 72)
    for (index, node) in enumerate(graph.nodes)
        offset = index - 1
        point = (origin[1] + width * (offset ÷ 4), origin[2] + height * (offset % 4))
        lower!(canvas, node, point)
    end
    return canvas
end

"""
$(TYPEDSIGNATURES)

Bind declared module input parameters using `master:import` components with
only their `Name` field, including coefficients referenced by block fields.
Reuse connected imports already present in `canvas`. Place the remaining
imports four rows per column, six grid units apart horizontally and four
vertically, starting at `(540, 72)` pixels or beyond a wider control graph.
Coefficient imports need no output wire. Return the mutated canvas.
"""
function lower!(canvas::CanvasPlan, parameters::AbstractVector{<:ModuleParameterPlan})
    imported = Set(Dict(c.params)["Name"]
    for c in canvas.components
    if c.defn == "master:import")
    origin = max(540, maximum(c -> c.x, canvas.components; init = 0) + 108)
    index = 0
    for parameter in parameters
        parameter.name in imported && continue
        point = (origin + 108 * (index ÷ 4), 72 + 72 * (index % 4))
        component!(canvas, "import", point, ["Name" => parameter.name])
        push!(imported, parameter.name)
        index += 1
    end
    return canvas
end

"""
$(TYPEDEF)

Multiply two signals elementwise.

$(TYPEDFIELDS)
"""
struct Mult <: ControlBlock
    "First input."
    left::Signal
    "Second input."
    right::Signal
    "Output signal."
    output::Signal
end

"""
$(TYPEDEF)

Divide a numerator by a denominator elementwise.

$(TYPEDFIELDS)
"""
struct Div <: ControlBlock
    "Numerator."
    left::Signal
    "Denominator."
    right::Signal
    "Output signal."
    output::Signal
end

"""
$(TYPEDEF)

Integrate the input with gain `1/t` and bounded output.

$(TYPEDFIELDS)
"""
struct Integrator <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
    "Integration time constant \\[s\\]."
    t::BlockValue
    "Initial output."
    y0::BlockValue
    "Lower output limit."
    lo::BlockValue
    "Upper output limit."
    hi::BlockValue
end

"""
$(TYPEDEF)

Represent `w2/(s^2 + damping*s + w2)` using two integrators.

$(TYPEDFIELDS)
"""
struct SecondOrder <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
    "Squared natural frequency \\[rad^2/s^2\\]."
    w2::BlockValue
    "Derivative coefficient \\[1/s\\]."
    damping::BlockValue
    "Initial output."
    y0::BlockValue
    "Initial output derivative \\[1/s\\]."
    dy0::BlockValue
end

"""
$(TYPEDEF)

Delay a scalar signal by an exact time interval.

$(TYPEDFIELDS)
"""
struct Delay <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
    "Delay \\[s\\]."
    t::BlockValue
    "History buffer length."
    n::Int
    "Initial history value."
    x0::BlockValue
end

"""
$(TYPEDEF)

Evaluate sine or cosine with a radian argument.

$(TYPEDFIELDS)
"""
struct Trig <: ControlBlock
    "Angle input \\[rad\\]."
    input::Signal
    "Output signal."
    output::Signal
    "Either `:sin` or `:cos`."
    kind::Symbol
end

"""
$(TYPEDEF)

Take the square root of a nonnegative signal.

$(TYPEDFIELDS)
"""
struct Sqrt <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
end

"""
$(TYPEDEF)

Square a signal.

$(TYPEDFIELDS)
"""
struct Square <: ControlBlock
    "Input signal."
    input::Signal
    "Output signal."
    output::Signal
end

"""
$(TYPEDEF)

Merge two or three scalar signals into an ordered array.

$(TYPEDFIELDS)
"""
struct ArrayMerge <: ControlBlock
    "Ordered inputs."
    inputs::Vector{Signal}
    "Array output."
    output::Signal
end

"""
$(TYPEDEF)

Select one scalar entry from an array.

$(TYPEDFIELDS)
"""
struct ArraySplit <: ControlBlock
    "Array input."
    input::Signal
    "Scalar output."
    output::Signal
    "One-based entry index."
    index::Int
end

"""
$(TYPEDEF)

Use the saved amplitude-invariant abc/dq module with q proportional to sine.

$(TYPEDFIELDS)
"""
struct AbcToDq <: ControlBlock
    "Three-phase input array."
    input::Signal
    "Transform angle \\[rad\\]."
    angle::Signal
    "Two-component dq output."
    output::Signal
    "Qualified copied transform module."
    definition::String
end

"""
$(TYPEDEF)

Use the saved inverse dq/abc transform module.

$(TYPEDFIELDS)
"""
struct DqToAbc <: ControlBlock
    "Two-component dq input."
    input::Signal
    "Transform angle \\[rad\\]."
    angle::Signal
    "Three-phase output array."
    output::Signal
    "Qualified copied transform module."
    definition::String
end

# Saved primitive fields and pins: local/TLC/Simple_2L_VSC_RL.pscx,
# div 2100–2106, mult 3001–3007, integral 3530–3545, trig 2113–2122
# (Type=1 sine, Type=2 cosine in the copied transforms), sqrt 1223–1230,
# square 1210–1217, delay 5037–5050, merge 2164–2185 / 2214–2235,
# tap 4498–4517. Primitive behavior remains subject to the M4 station checks.
function binary_block!(canvas, defn, point, left, right, output)
    component!(canvas, defn, point, ["Dim" => "1", "DPath" => "1"])
    signal_stub!(canvas, (point[1] - 36, point[2]), left)
    signal_stub!(canvas, (point[1], point[2] + 36), right)
    signal_stub!(canvas, (point[1] + 36, point[2]), output; direction = -1)
    return nothing
end
function lower!(canvas::CanvasPlan, node::Mult, point)
    binary_block!(canvas, "mult", point, node.left, node.right, node.output)
end
function lower!(canvas::CanvasPlan, node::Div, point)
    binary_block!(canvas, "div", point, node.left, node.right, node.output)
end

function lower!(canvas::CanvasPlan, node::Integrator, point)
    unary_block!(canvas, "integral", point,
        ["T" => block_value(node.t; unit = "s"), "Yo" => block_value(node.y0),
            "YLo" => block_value(node.lo), "YHi" => block_value(node.hi),
            "Extrn" => "0", "Reset" => "0", "Mthd" => "0"], node.input, node.output)
end

function lower!(canvas::CanvasPlan, node::SecondOrder, point)
    # y'' = w2*(u-y) - damping*y'. Initial coordinates are y and y'.
    error, force, velocity, drag, acceleration = Signal.(
        [pscad_name(node.output.name * suffix)
         for suffix in ("_err", "_force", "_dy", "_drag", "_ddy")])
    nodes = ControlBlock[Sum([node.input, node.output], [1, -1], error),
        Gain(error, force, node.w2), Gain(velocity, drag, node.damping),
        Sum([force, drag], [1, -1], acceleration),
        Integrator(acceleration, velocity, 1.0, node.dy0, -1e8, 1e8),
        Integrator(velocity, node.output, 1.0, node.y0, -1e8, 1e8)]
    for (i, block) in enumerate(nodes)
        lower!(canvas, block, (point[1] + 180 * ((i - 1) ÷ 3),
            point[2] + 144 * ((i - 1) % 3)))
    end
    return nothing
end

function lower!(canvas::CanvasPlan, node::Delay, point)
    node.n > 1 || throw(ArgumentError("delay history requires at least two entries"))
    unary_block!(canvas, "tdelay", point,
        ["T" => block_value(node.t; unit = "s"), "N" => string(node.n),
            "Intp" => "0", "Dim" => "1", "Init" => "1", "X0" => block_value(node.x0)],
        node.input, node.output)
end
function lower!(canvas::CanvasPlan, node::Trig, point)
    node.kind in (:sin, :cos) || throw(ArgumentError("unsupported trig function"))
    unary_block!(canvas, "trig", point,
        ["Type" => node.kind == :sin ? "1" : "2", "Mode" => "0", "Dim" => "1"],
        node.input, node.output)
end
function lower!(canvas::CanvasPlan, node::Sqrt, point)
    unary_block!(
        canvas, "sqrt", point, ["Dim" => "1", "DPath" => "1"], node.input, node.output)
end
function lower!(canvas::CanvasPlan, node::Square, point)
    unary_block!(
        canvas, "square", point, ["Dim" => "1", "DPath" => "1"], node.input, node.output)
end

function lower!(canvas::CanvasPlan, node::ArrayMerge, point)
    n = length(node.inputs)
    n in (2, 3) || throw(ArgumentError("array merge supports two or three scalar inputs"))
    params = ["N" => string(n), "Type" => "2", "Disp" => "1", "View" => "0"]
    append!(params, ["Dim$i" => "1" for i in 1:n])
    push!(canvas.components, ComponentPlan("master:datamerge", params, point..., 4))
    for (i, input) in enumerate(node.inputs)
        pin = (point[1] - 18, point[2] + 18 * (i - 5))
        endpoint = (pin[1] - 36, pin[2])
        wire!(canvas, pin, endpoint)
        component!(canvas, "datalabel", endpoint, ["Name" => input.name])
    end
    pin = (point[1], point[2] + 18 * (n - 3))
    endpoint = (pin[1] + 36, pin[2])
    wire!(canvas, pin, endpoint)
    component!(canvas, "datalabel", endpoint, ["Name" => node.output.name])
    return nothing
end

function lower!(canvas::CanvasPlan, node::ArraySplit, point)
    node.index > 0 || throw(ArgumentError("array index must be positive"))
    component!(canvas, "datatap", point,
        ["Index" => string(node.index), "Dim" => "1", "Type" => "2",
            "Style" => "0", "Disp" => "1"])
    for (pin, offset, signal) in (((point[1], point[2] - 18), -36, node.input),
        (point, 36, node.output))
        endpoint = (pin[1] + offset, pin[2])
        wire!(canvas, pin, endpoint)
        component!(canvas, "datalabel", endpoint, ["Name" => signal.name])
    end
    return nothing
end

function lower!(canvas::CanvasPlan, node::Union{AbcToDq, DqToAbc}, point)
    push!(canvas.components, ModuleInstancePlan(node.definition,
        ["Xb" => "1.0", "qaxis" => "1"], point..., 0))
    signal_stub!(canvas, (point[1] - 36, point[2] - 18), node.input; direction = -1)
    signal_stub!(canvas, (point[1] - 36, point[2] + 18), node.angle)
    signal_stub!(canvas, (point[1] + 36, point[2]), node.output; direction = -1)
    return nothing
end

# Preserve the saved transform's pin nets, including abutments and branches,
# while placing each block separately and replacing each net by datalabel stubs.
# Only the copied abc/dq canvases use this lowering; ordinary plans are checked,
# not repaired. All block fields and orientations remain identical.
function named_transform_canvas(canvas)
    for c in canvas.components, (key, value) in c.params

        key == "Name" && !isempty(value) && push!(canvas.used, value)
    end
    parent = Dict{NTuple{2, Int}, NTuple{2, Int}}()
    root(p) = get!(parent, p, p) == p ? p : (parent[p] = root(parent[p]))
    join(a, b) = (parent[root(a)] = root(b))
    pins = [component_ports(c, Dict()) for c in canvas.components]
    points = Set(point for ports in pins for (point, _) in ports)
    for c in canvas.components
        c.defn == "master:datalabel" && push!(points, (c.x, c.y))
    end
    for w in canvas.wires
        union!(points, w.vertices)
    end
    for w in canvas.wires
        a, b = w.vertices
        join(a, b)
        for p in points
            (a[1] == b[1] == p[1] && min(a[2], b[2]) <= p[2] <= max(a[2], b[2])) ||
                (a[2] == b[2] == p[2] && min(a[1], b[1]) <= p[1] <= max(a[1], b[1])) ||
                continue
            join(a, p)
        end
    end
    label_points = Dict{String, NTuple{2, Int}}()
    for c in canvas.components
        c.defn == "master:datalabel" || continue
        n = Dict(c.params)["Name"]
        p = (c.x, c.y)
        haskey(label_points, lowercase(n)) ? join(p, label_points[lowercase(n)]) :
        (label_points[lowercase(n)] = p)
    end
    names = Dict(root(p) => Dict(c.params)["Name"]
    for c in canvas.components if c.defn == "master:datalabel" for p in ((c.x, c.y),))
    counts = Dict{NTuple{2, Int}, Int}()
    for ports in pins, (point, _) in ports

        r = root(point)
        counts[r] = get(counts, r, 0) + 1
    end
    result = CanvasPlan(AbstractComponentPlan[], WirePlan[], canvas.used,
        Dict{String, Union{Nothing, String}}())
    index = 0
    for (c, ports) in zip(canvas.components, pins)
        c.defn == "master:datalabel" && continue
        x, y = 108 + 216 * (index % 6), 108 + 216 * (index ÷ 6)
        index += 1
        placed = ComponentPlan(c.defn, c.params, x, y, c.orient)
        push!(result.components, placed)
        for ((old, _), (pin, _)) in zip(ports, component_ports(placed, Dict()))
            r = root(old)
            get(counts, r, 0) > 1 || haskey(names, r) || continue
            name = get!(names, r) do
                pscad_name("transform_node_$(length(names) + 1)"; used = result.used)
            end
            dx, dy = pin .- (x, y)
            endpoint = dx != 0 ? (pin[1] + 36sign(dx), pin[2]) :
                       (pin[1], pin[2] + 36 * (dy < 0 ? -1 : 1))
            wire!(result, pin, endpoint)
            component!(result, "datalabel", endpoint, ["Name" => name])
        end
    end
    return result
end

# Canvas copied from local/TLC/Simple_2L_VSC_RL.pscx:2457 (abc2dq_1).
function abc_to_dq_module(name)
    canvas = CanvasPlan()
    push!(canvas.components, ComponentPlan("master:import", ["Name" => "abc"], 216, 270, 0))
    push!(canvas.components, ComponentPlan(
        "master:import", ["Name" => "angle"], 126, 288, 0))
    push!(canvas.components, ComponentPlan("master:export", ["Name" => "dq"], 540, 306, 4))
    push!(canvas.components,
        ComponentPlan("master:sumjct",
            ["DPath" => "1", "A" => "0", "B" => "0", "C" => "0", "D" => "1",
                "E" => "0", "F" => "-1", "G" => "0", "Name" => "", "Dim" => "1"],
            252,
            432,
            0))
    push!(canvas.components,
        ComponentPlan(
            "master:div", ["Dim" => "3", "Name" => "", "DPath" => "1"], 288, 270, 0))
    push!(canvas.components, ComponentPlan(
        "master:dot_product", ["DPath" => "1", "Name" => ""], 450, 306, 0))
    push!(canvas.components,
        ComponentPlan("master:sumjct",
            ["DPath" => "1", "A" => "0", "B" => "0", "C" => "0", "D" => "1",
                "E" => "0", "F" => "1", "G" => "0", "Name" => "", "Dim" => "1"],
            252,
            504,
            6))
    push!(canvas.components,
        ComponentPlan(
            "master:emtconst", ["Name" => "", "Value" => "3", "Dim" => "1"], 216, 468, 0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "1", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            324,
            504,
            0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "1", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            324,
            432,
            0))
    push!(canvas.components,
        ComponentPlan("master:sumjct",
            ["DPath" => "1", "A" => "0", "B" => "0", "C" => "0", "D" => "1",
                "E" => "0", "F" => "-1", "G" => "0", "Name" => "", "Dim" => "1"],
            252,
            144,
            0))
    push!(canvas.components,
        ComponentPlan("master:sumjct",
            ["DPath" => "1", "A" => "0", "B" => "0", "C" => "0", "D" => "1",
                "E" => "0", "F" => "1", "G" => "0", "Name" => "", "Dim" => "1"],
            252,
            216,
            6))
    push!(canvas.components,
        ComponentPlan(
            "master:emtconst", ["Name" => "", "Value" => "3", "Dim" => "1"], 216, 180, 0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "1", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            324,
            360,
            0))
    push!(canvas.components, ComponentPlan("master:import", ["Name" => "Xb"], 252, 306, 0))
    push!(canvas.components, ComponentPlan(
        "master:dot_product", ["DPath" => "1", "Name" => ""], 450, 252, 6))
    push!(canvas.components,
        ComponentPlan("master:datamerge",
            ["N" => "3", "Type" => "2", "Disp" => "1", "View" => "0", "Dim1" => "1",
                "Dim2" => "1", "Dim3" => "1", "Dim4" => "1", "Dim5" => "1",
                "Dim6" => "1", "Dim7" => "1", "Dim8" => "1", "Dim9" => "1",
                "Dim10" => "1", "Dim11" => "1", "Dim12" => "1", "Name" => ""],
            396,
            198,
            4))
    push!(canvas.components,
        ComponentPlan("master:datamerge",
            ["N" => "3", "Type" => "2", "Disp" => "1", "View" => "0", "Dim1" => "1",
                "Dim2" => "1", "Dim3" => "1", "Dim4" => "1", "Dim5" => "1",
                "Dim6" => "1", "Dim7" => "1", "Dim8" => "1", "Dim9" => "1",
                "Dim10" => "1", "Dim11" => "1", "Dim12" => "1", "Name" => ""],
            396,
            486,
            4))
    push!(canvas.components,
        ComponentPlan("master:datamerge",
            ["N" => "2", "Type" => "2", "Disp" => "1", "View" => "0", "Dim1" => "1",
                "Dim2" => "1", "Dim3" => "1", "Dim4" => "1", "Dim5" => "1",
                "Dim6" => "1", "Dim7" => "1", "Dim8" => "1", "Dim9" => "1",
                "Dim10" => "1", "Dim11" => "1", "Dim12" => "1", "Name" => ""],
            504,
            324,
            4))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "2", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            324,
            72,
            0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "2", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            324,
            144,
            0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "2", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            324,
            216,
            0))
    push!(canvas.components,
        ComponentPlan(
            "master:mult", ["DPath" => "1", "Name" => "", "Dim" => "3"], 450, 378, 3))
    push!(canvas.components, ComponentPlan(
        "master:import", ["Name" => "qaxis"], 522, 378, 4))
    push!(canvas.components,
        ComponentPlan(
            "master:mult", ["DPath" => "1", "Name" => "", "Dim" => "3"], 378, 270, 0))
    push!(canvas.components,
        ComponentPlan(
            "master:emtconst", ["Name" => "", "Value" => "14", "Dim" => "1"], 342, 306, 0))
    wire!(canvas, (216, 504), (162, 504))
    wire!(canvas, (162, 504), (162, 432))
    wire!(canvas, (162, 432), (216, 432))
    wire!(canvas, (162, 432), (162, 360))
    wire!(canvas, (162, 360), (288, 360))
    wire!(canvas, (216, 216), (162, 216))
    wire!(canvas, (162, 216), (162, 144))
    wire!(canvas, (162, 144), (216, 144))
    wire!(canvas, (162, 144), (162, 72))
    wire!(canvas, (162, 72), (288, 72))
    wire!(canvas, (162, 360), (162, 216))
    wire!(canvas, (414, 306), (414, 252))
    wire!(canvas, (360, 216), (378, 216))
    wire!(canvas, (378, 216), (378, 162))
    wire!(canvas, (360, 144), (378, 144))
    wire!(canvas, (378, 126), (378, 72))
    wire!(canvas, (378, 72), (360, 72))
    wire!(canvas, (396, 198), (450, 198))
    wire!(canvas, (450, 198), (450, 216))
    wire!(canvas, (360, 432), (378, 432))
    wire!(canvas, (360, 360), (378, 360))
    wire!(canvas, (378, 360), (378, 414))
    wire!(canvas, (360, 504), (378, 504))
    wire!(canvas, (378, 504), (378, 450))
    wire!(canvas, (396, 486), (450, 486))
    wire!(canvas, (450, 486), (450, 414))
    wire!(canvas, (486, 306), (486, 270))
    wire!(canvas, (324, 270), (342, 270))
    parameters = ModuleParameterPlan[ModuleParameterPlan("Xb", 1.0, ""), ModuleParameterPlan("qaxis", 1.0, "")]
    ports = ModulePortPlan[
        ModulePortPlan("abc", :input, -36, -18, 3), ModulePortPlan(
            "angle", :input, -36, 18, 1), ModulePortPlan("dq", :output, 36, 0, 2)]
    return ModuleDefinitionPlan(name, parameters, ports, named_transform_canvas(canvas))
end

# Canvas copied from local/TLC/Simple_2L_VSC_RL.pscx:1851 (dq2abc).
function dq_to_abc_module(name)
    canvas = CanvasPlan()
    push!(canvas.components, ComponentPlan("master:import", ["Name" => "dq"], 54, 54, 0))
    push!(canvas.components, ComponentPlan(
        "master:import", ["Name" => "angle"], 270, 54, 0))
    push!(canvas.components, ComponentPlan("master:export", ["Name" => "abc"], 738, 342, 4))
    push!(canvas.components,
        ComponentPlan(
            "master:div", ["Dim" => "2", "Name" => "", "DPath" => "1"], 126, 54, 0))
    push!(canvas.components, ComponentPlan(
        "master:dot_product", ["DPath" => "1", "Name" => ""], 648, 432, 0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "1", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            468,
            252,
            0))
    push!(canvas.components,
        ComponentPlan("master:sumjct",
            ["DPath" => "1", "A" => "0", "B" => "0", "C" => "0", "D" => "1",
                "E" => "0", "F" => "-1", "G" => "0", "Name" => "", "Dim" => "1"],
            396,
            180,
            0))
    push!(canvas.components,
        ComponentPlan(
            "master:emtconst", ["Name" => "", "Value" => "3", "Dim" => "1"], 360, 216, 0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "1", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            468,
            108,
            0))
    push!(canvas.components, ComponentPlan(
        "master:dot_product", ["DPath" => "1", "Name" => ""], 648, 144, 0))
    push!(canvas.components,
        ComponentPlan("master:datamerge",
            ["N" => "3", "Type" => "2", "Disp" => "1", "View" => "0", "Dim1" => "1",
                "Dim2" => "1", "Dim3" => "1", "Dim4" => "1", "Dim5" => "1",
                "Dim6" => "1", "Dim7" => "1", "Dim8" => "1", "Dim9" => "1",
                "Dim10" => "1", "Dim11" => "1", "Dim12" => "1", "Name" => ""],
            702,
            342,
            4))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "2", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            468,
            54,
            0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "2", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            468,
            180,
            0))
    push!(canvas.components,
        ComponentPlan("master:datamerge",
            ["N" => "2", "Type" => "2", "Disp" => "1", "View" => "0", "Dim1" => "1",
                "Dim2" => "1", "Dim3" => "1", "Dim4" => "1", "Dim5" => "1",
                "Dim6" => "1", "Dim7" => "1", "Dim8" => "1", "Dim9" => "1",
                "Dim10" => "1", "Dim11" => "1", "Dim12" => "1", "Name" => ""],
            612,
            162,
            4))
    push!(canvas.components,
        ComponentPlan("master:sumjct",
            ["DPath" => "1", "A" => "0", "B" => "0", "C" => "0", "D" => "1",
                "E" => "0", "F" => "-1", "G" => "0", "Name" => "", "Dim" => "1"],
            396,
            252,
            6))
    push!(canvas.components,
        ComponentPlan("master:datamerge",
            ["N" => "2", "Type" => "2", "Disp" => "1", "View" => "0", "Dim1" => "1",
                "Dim2" => "1", "Dim3" => "1", "Dim4" => "1", "Dim5" => "1",
                "Dim6" => "1", "Dim7" => "1", "Dim8" => "1", "Dim9" => "1",
                "Dim10" => "1", "Dim11" => "1", "Dim12" => "1", "Name" => ""],
            612,
            306,
            4))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "1", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            468,
            396,
            0))
    push!(canvas.components,
        ComponentPlan("master:sumjct",
            ["DPath" => "1", "A" => "0", "B" => "0", "C" => "0", "D" => "1",
                "E" => "0", "F" => "1", "G" => "0", "Name" => "", "Dim" => "1"],
            396,
            324,
            0))
    push!(canvas.components,
        ComponentPlan(
            "master:emtconst", ["Name" => "", "Value" => "3", "Dim" => "1"], 360, 360, 0))
    push!(canvas.components,
        ComponentPlan("master:trig",
            ["Type" => "2", "Mode" => "0",
                "COM" => "Trig-Func", "Dim" => "1", "Name" => ""],
            468,
            324,
            0))
    push!(canvas.components,
        ComponentPlan("master:sumjct",
            ["DPath" => "1", "A" => "0", "B" => "0", "C" => "0", "D" => "1",
                "E" => "0", "F" => "1", "G" => "0", "Name" => "", "Dim" => "1"],
            396,
            396,
            6))
    push!(canvas.components,
        ComponentPlan("master:datamerge",
            ["N" => "2", "Type" => "2", "Disp" => "1", "View" => "0", "Dim1" => "1",
                "Dim2" => "1", "Dim3" => "1", "Dim4" => "1", "Dim5" => "1",
                "Dim6" => "1", "Dim7" => "1", "Dim8" => "1", "Dim9" => "1",
                "Dim10" => "1", "Dim11" => "1", "Dim12" => "1", "Name" => ""],
            612,
            450,
            4))
    push!(canvas.components, ComponentPlan("master:import", ["Name" => "Xb"], 90, 90, 0))
    push!(canvas.components, ComponentPlan(
        "master:dot_product", ["DPath" => "1", "Name" => ""], 648, 288, 0))
    push!(canvas.components, ComponentPlan(
        "master:datalabel", ["Name" => "dq_scaled"], 180, 54, 0))
    push!(canvas.components, ComponentPlan(
        "master:datalabel", ["Name" => "dq_scaled"], 648, 468, 0))
    push!(canvas.components, ComponentPlan(
        "master:datalabel", ["Name" => "dq_scaled"], 648, 324, 0))
    push!(canvas.components, ComponentPlan(
        "master:datalabel", ["Name" => "dq_scaled"], 648, 180, 0))
    push!(canvas.components,
        ComponentPlan("master:gain",
            ["G" => "qaxis", "COM" => "Gain", "Dim" => "1", "Name" => "", "DPath" => "1"],
            540, 396, 0))
    push!(canvas.components, ComponentPlan(
        "master:import", ["Name" => "qaxis"], 90, 126, 0))
    push!(canvas.components,
        ComponentPlan("master:gain",
            ["G" => "qaxis", "COM" => "Gain", "Dim" => "1", "Name" => "", "DPath" => "1"],
            540, 252, 0))
    push!(canvas.components,
        ComponentPlan("master:gain",
            ["G" => "qaxis", "COM" => "Gain", "Dim" => "1", "Name" => "", "DPath" => "1"],
            540, 108, 0))
    wire!(canvas, (360, 252), (306, 252))
    wire!(canvas, (306, 252), (306, 180))
    wire!(canvas, (306, 180), (360, 180))
    wire!(canvas, (594, 90), (594, 54))
    wire!(canvas, (594, 54), (504, 54))
    wire!(canvas, (432, 108), (306, 108))
    wire!(canvas, (306, 108), (306, 54))
    wire!(canvas, (306, 54), (432, 54))
    wire!(canvas, (576, 108), (594, 108))
    wire!(canvas, (576, 252), (594, 252))
    wire!(canvas, (504, 180), (594, 180))
    wire!(canvas, (594, 180), (594, 234))
    wire!(canvas, (360, 396), (306, 396))
    wire!(canvas, (306, 396), (306, 324))
    wire!(canvas, (306, 324), (360, 324))
    wire!(canvas, (576, 396), (594, 396))
    wire!(canvas, (504, 324), (594, 324))
    wire!(canvas, (594, 324), (594, 378))
    wire!(canvas, (306, 180), (306, 108))
    wire!(canvas, (306, 324), (306, 252))
    wire!(canvas, (684, 270), (684, 144))
    wire!(canvas, (684, 432), (684, 306))
    wire!(canvas, (162, 54), (180, 54))
    parameters = ModuleParameterPlan[ModuleParameterPlan("Xb", 1.0, ""), ModuleParameterPlan("qaxis", 1.0, "")]
    ports = ModulePortPlan[
        ModulePortPlan("dq", :input, -36, -18, 2), ModulePortPlan(
            "angle", :input, -36, 18, 1), ModulePortPlan("abc", :output, 36, 0, 3)]
    return ModuleDefinitionPlan(name, parameters, ports, named_transform_canvas(canvas))
end

# A primitive owns the space occupied by its pins and lowered subgraph.
block_pitch(::ControlBlock) = (108, 72)
function block_pitch(::Union{Mult, Div, Integrator, Delay, Trig, Sqrt, Square,
        ArrayMerge, ArraySplit, AbcToDq, DqToAbc})
    (180, 180)
end
block_pitch(::SecondOrder) = (432, 432)
