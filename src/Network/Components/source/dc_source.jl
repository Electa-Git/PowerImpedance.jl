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
    dc_source(; pins=1, setpoint=Setpoint(Vdc=240),
              transformation=false, connection=true, source_kwargs...)

Construct an ideal DC voltage-source element and its power-flow data.

# Arguments

- `pins`: Number of DC conductors represented on each legacy element side.
- `setpoint`: DC voltage and power operating point. See [`Setpoint`](@ref).
- `transformation`: Whether to expose a supported transformed representation.
- `connection`: Whether NetworkBuilder includes the element in the system.
- `source_kwargs`: Legacy fields of the internal `Source` model.

# Returns

- An `Element` whose model is a DC `Source`.

# Errors

- Throws `ArgumentError` when `source_kwargs` contains an unknown field.

# Examples

```julia
source = dc_source(setpoint = Setpoint(Vdc = 320.0, Pdc = 100.0))
```
"""
function dc_source(; pins=1, setpoint=Setpoint(Vdc=240),transformation=false, connection=true, args...)
    source = Source()

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
