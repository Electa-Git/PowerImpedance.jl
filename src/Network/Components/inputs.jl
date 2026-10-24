export Input, inputs, inputvalues, withinputs, component

"""
$(TYPEDEF)

Describe a configurable input value, its accepted type, unit and description.

$(TYPEDFIELDS)
"""
struct Input{V, T}
    "Declared default value, independent of the configured model."
    default::V
    "Physical unit, or an empty string for an unspecified unit."
    unit::String
    "Accepted Julia type."
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
- `type`: Accepted Julia type. Default: `typeof(default)`.
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
    p_ac = Input(0.0; unit = "pu", description = "AC active-power seed"),
    q_ac = Input(0.0; unit = "pu", description = "AC reactive-power seed"),
    v_ac = Input(1.0; unit = "pu", description = "AC-voltage power-flow seed"),
    p_dc = Input(0.0; unit = "pu", description = "DC active-power seed"),
    v_dc = Input(1.0; unit = "pu", description = "DC-voltage power-flow seed"),
)

const _MACHINE_POWERFLOW_INPUTS = (
    p = Input(0.0; unit = "pu", description = "machine active-power seed"),
    q = Input(0.0; unit = "pu", description = "machine reactive-power seed"),
    v = Input(1.0; unit = "pu", description = "machine voltage seed"),
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
    changed isa declaration.type ||
        throw(ArgumentError("Input $path requires $(declaration.type)."))
    return changed
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
  Input types must match their declarations. Untouched blocks are reused by identity.

# Returns

- Configured model or block. The original is unchanged.

# Notes

Setting a converter `powerflow` quantity owned by a control loop emits a warning.
The seed is stored. `powerflow_targets` selects the loop reference for that quantity.

# Errors

- Throws `ArgumentError` naming the full input path for an unknown key or wrong type.

# Examples

```julia
withinputs(OuterActivePowerControl(); p_ref = 0.2)
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
component(ac_source().element_model; v = 130.0)
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

Select converter power-flow targets from loop references and stored seeds.

# Arguments

- `model`: MMC or TLC model.

# Returns

- NamedTuple `(p_ac, q_ac, v_ac, p_dc, v_dc)` on converter bases
  \\[dimensionless\\]. Loop references replace owned quantities. `p_dc` uses its seed.
"""
function powerflow_targets end
