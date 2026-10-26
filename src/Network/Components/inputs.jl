export Input, inputs, inputvalues, withinputs, component

"""
$(TYPEDEF)

Describe a configurable input value, its declared type, unit and description.

$(TYPEDFIELDS)
"""
struct Input{V, T}
    "Declared default value, independent of the configured model."
    default::V
    "Physical unit, or an empty string for an unspecified unit."
    unit::String
    "Declared Julia type."
    type::Type{T}
    "Description of the input quantity."
    description::String
end

"""
$(TYPEDSIGNATURES)

Construct an input declaration from a default value.

# Arguments

- `default`: Declared default value.
- `unit`: Unit label. Default: `""`.
- `type`: Declared Julia type. Default: `typeof(default)`.
- `description`: Description of the input. Default: `""`.

# Returns

- An `Input` instance.

# Examples

```julia
Input(1.0; unit = "pu", description = "AC-voltage reference")
```
"""
Input(default; unit = "", type = typeof(default), description = "") =
    Input(default, unit, type, description)

const _CONVERTER_POWERFLOW_INPUTS = (
    p_ac = Input(0.0; unit = "pu", description = "AC active-power setpoint"),
    q_ac = Input(0.0; unit = "pu", description = "AC reactive-power setpoint"),
    v_ac = Input(1.0; unit = "pu", description = "AC-voltage power-flow setpoint"),
    p_dc = Input(0.0; unit = "pu",
        description = "DC power into the converter on its base. " *
            "603 MW in gives p_dc = 603/Sbase."),
    v_dc = Input(1.0; unit = "pu", description = "DC-voltage power-flow setpoint"),
)

const _MACHINE_POWERFLOW_INPUTS = (
    p = Input(0.0; unit = "pu", description = "machine active-power setpoint"),
    q = Input(0.0; unit = "pu", description = "machine reactive-power setpoint"),
    v = Input(1.0; unit = "pu", description = "machine voltage setpoint"),
)

"""
$(TYPEDSIGNATURES)

Return the nested input declarations of a model or control block.

# Arguments

- `model`: Component model or control block.

# Returns

- NamedTuple with `Input` leaves and composition field names, retaining empty subtrees.
  Leaf defaults, units and descriptions are independent of configured values.
  Subtrees follow the selected block types. Models without configurable inputs return
  an empty NamedTuple.
"""
inputs(model) = (;)

"""
$(TYPEDSIGNATURES)

Return the current values of the declared inputs.

# Arguments

- `model`: Component model or control block.

# Returns

- NamedTuple with the same tree as `inputs(model)` and stored values at its leaves.
"""
inputvalues(model) = inputvalues(model, inputs(model))
function inputvalues(model, declarations::NamedTuple)
    values = map(keys(declarations)) do key
        inputvalues(getfield(model, key), declarations[key])
    end
    return NamedTuple{keys(declarations)}(values)
end
inputvalues(value, ::Input) = value

function _withinputs(value, declaration::Input, changed, path)
    try
        return convert(declaration.type, changed)
    catch error
        error isa InterruptException && rethrow()
        throw(ArgumentError("Input $path requires $(declaration.type)."))
    end
end

function _withinputs(model, declarations::NamedTuple, changes, path)
    changes isa NamedTuple || throw(ArgumentError("Input $path requires a NamedTuple."))
    for key in keys(changes)
        fullpath = isempty(path) ? string(key) : string(path, '.', key)
        haskey(declarations, key) || throw(ArgumentError("Unknown input $fullpath."))
    end
    replacements = map(keys(changes)) do key
        fullpath = isempty(path) ? string(key) : string(path, '.', key)
        _withinputs(getfield(model, key), declarations[key], changes[key], fullpath)
    end
    return Parameters.reconstruct(model, pairs(NamedTuple{keys(changes)}(replacements)))
end

_powerflow_references(model) = (;)

"""
$(TYPEDSIGNATURES)

Return a copy with the supplied nested input values.

# Arguments

- `model`: Component model or control block.
- `nested...`: Partial NamedTuples following the field names in `inputs(model)`.
  Values are converted to their declared types. Untouched blocks are reused by identity.

# Returns

- Configured model or block. The original is unchanged.

# Notes

Setting a converter `powerflow` quantity owned by a control loop emits a warning.
The setpoint is stored. `powerflow_targets` selects the loop reference for that quantity.

# Errors

- Throws `ArgumentError` naming the full input path for an unknown key or a value
  that cannot be converted.

# Examples

```julia
withinputs(OuterActivePowerControl(); p_ref = 1)  # Stores 1.0.
```
"""
function withinputs(model; nested...)
    changes = (; nested...)
    configured = _withinputs(model, inputs(model), changes, "")
    if haskey(changes, :powerflow)
        owned = _powerflow_references(model)
        for key in keys(changes.powerflow)
            if haskey(owned, key)
                @warn "$(nameof(typeof(model))) powerflow.$key is owned by a control loop."
            end
        end
    end
    return configured
end

"""
$(TYPEDSIGNATURES)

Configure model inputs and optionally replace its stored limits.

# Arguments

- `model`: Component model.
- `limits`: Replacement `Limits`, or `nothing` to retain the current value.
- `inputs...`: Nested input changes accepted by `withinputs`.

# Returns

- Configured model, retaining unchanged sub-blocks by identity.

# Errors

- Throws `ArgumentError` for invalid input paths or types, or when limits are supplied
  for a model without a `limits` field.

# Examples

```julia
component(ac_source(); v = 130.0)
```
"""
function component(model; limits = nothing, inputs...)
    if limits !== nothing
        hasfield(typeof(model), :limits) ||
            throw(ArgumentError("$(typeof(model)) has no limits field."))
        limits isa Limits || throw(ArgumentError("limits requires Limits."))
    end
    configured = withinputs(model; inputs...)
    return limits === nothing ? configured :
        Parameters.reconstruct(configured; limits)
end

"""
$(TYPEDSIGNATURES)

Select converter power-flow targets from loop references and stored setpoints.

# Arguments

- `model`: MMC or TLC model.

# Returns

- NamedTuple `(p_ac, q_ac, v_ac, p_dc, v_dc)` on converter bases
  \\[dimensionless\\]. Loop references replace owned quantities. `p_dc` uses its setpoint
  for power flowing into the converter through its DC port.
"""
function powerflow_targets end
