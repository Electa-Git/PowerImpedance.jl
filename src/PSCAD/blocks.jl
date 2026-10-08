"""
$(TYPEDEF)

Identify a scalar control signal by its canvas-local datalabel name.

$(TYPEDFIELDS)
"""
struct Signal
    "ASCII signal identifier."
    name::String
    function Signal(name::AbstractString)
        name == pscad_name(name) || throw(ArgumentError("invalid PSCAD signal name: $name"))
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
six grid units apart and rows four grid units apart. The default origin is
`(72, 72)` pixels. Vertical 36-pixel pin stubs avoid joining neighboring blocks
with different signal names. Return the mutated canvas.
"""
function lower!(canvas::CanvasPlan, graph::BlockGraph; origin = (72, 72))
    for (index, node) in enumerate(graph.nodes)
        offset = index - 1
        point = (origin[1] + 108 * (offset ÷ 4), origin[2] + 72 * (offset % 4))
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
