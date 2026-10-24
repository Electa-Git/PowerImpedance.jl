export dc_source

#= function dc_source(; args...)
	source = Source()
	transformation = false
	connection = true
	elem_args = (;transformation, connection)
	for (key, val) in pairs(args)
		if in(key, propertynames(source))
			setfield!(source, key, val)
		elseif in(key, fieldnames(Element))
			merge(elem_args, NamedTuple{key}(val))
		else
			throw(ArgumentError("Source does not have a property $(key)."))
		end
	end
	make_abcd(source)

	return Element(input_pins = source.pins, output_pins = source.pins,
		element_value = source,
		transformation = transformation, connection = connection)
end =#
"""
$(TYPEDSIGNATURES)

Construct an ideal DC voltage-source element and its power-flow data.

# Arguments

- `pins`: Number of terminals per side. Used directly without inference. Default: `1`.
- `setpoint`: Physical operating point; powers use \\[MW\\] or \\[MVAr\\], voltages \\[kV\\],
  and angles \\[rad\\]. Default: `Setpoint(Vdc = 240)`.
- `transformation`: Whether the element exposes transformed external coordinates.
  Default: `false`.
- `connection`: Whether the element participates in network construction. Default:
  `true`.
- `args...`: Additional `Source` field values, such as legacy voltage and power data.

# Returns

- An `Element` whose model is a DC `Source`.

# Errors

- Throws `ArgumentError` when an additional keyword is not a `Source` field.

# Examples

```julia
source = dc_source(setpoint = Setpoint(Vdc = 640.0, Pdc = 100.0))
```
"""
function dc_source(; pins=1, setpoint=Setpoint(Vdc=_DC_SOURCE_INPUTS.v.default),
        transformation=false, connection=true, args...)
    source = Source()

    if haskey(args, :V)
        @warn "Pass the pole-to-pole voltage through `setpoint=Setpoint(Vdc=...)` for power-flow voltage control; legacy `V` only initializes the DC bus voltage."
    end

    for (key, val) in pairs(args)
        if key in propertynames(source)
            setfield!(source, key, val)
        elseif key == :transformation
            transformation = val
        elseif key == :connection
            connection = val
        else
            throw(ArgumentError("Source does not have a property $(key)."))
        end
    end

    source.conductors = pins
    source.domain = DC_CM
    source.limits = Limits()
    source.v = ismissing(setpoint.Vdc) ? _DC_SOURCE_INPUTS.v.default : setpoint.Vdc
    source.p = ismissing(setpoint.Pdc) ? _DC_SOURCE_INPUTS.p.default : setpoint.Pdc

    A, B, C, D = make_abcd(source, pins)

    return Element(;
        input_pins = pins,
        output_pins = pins, # DC sources are one-port, kept for legacy
        element_model = source,
        A = A,
        B = B,
        C = C,
        D = D,
		setpoint,
        transformation,
        connection,
    )
end
