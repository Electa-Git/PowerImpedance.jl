export ac_source

#= function ac_source(; pins=1, args...)
	source = Source()
	transformation = false
    connection = true
	for (key, val) in pairs(args)
		if in(key, propertynames(source))
			setfield!(source, key, val)
		elseif (key == :transformation)
			transformation = val
		else
			throw(ArgumentError("Source does not have a property $(key)."))
		end
	end
	A,B,C,D = make_abcd(source, pins)

	return Element(;input_pins = pins, output_pins = pins,
		element_model = source, A,B,C,D, 
		transformation = transformation, connection = connection)
end
 =#
"""
    ac_source(; setpoint=Setpoint(Vac=220/sqrt(3)), pins=1,
              limits=Limits(), transformation=false, connection=true,
              source_kwargs...)

Construct an ideal AC voltage-source element and its power-flow data.

# Arguments

- `setpoint`: AC voltage, angle, and power operating point. See [`Setpoint`](@ref).
- `pins`: Number of phase-domain terminals.
- `limits`: Active- and reactive-power limits in the source power-flow base.
- `transformation`: Whether to expose supported transformed coordinates.
- `connection`: Whether NetworkBuilder includes the element in the system.
- `source_kwargs`: Legacy fields of the internal `Source` model.

# Returns

- An `Element` whose model is a `Source` and whose ABCD representation is an
  ideal voltage source.

# Errors

- Throws `ArgumentError` when `source_kwargs` contains an unknown field.

# Examples

```julia
source = ac_source(
    setpoint = Setpoint(Vac = 220 / sqrt(3), Pac = 100.0, Qac = 0.0),
    pins = 3,
    transformation = true,
)
```
"""
function ac_source(; setpoint = Setpoint(;Vac=220/sqrt(3)), pins=1, limits=Limits(), transformation=false, connection=true, args...)
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
        output_pins = pins, # AC sources one-port, kept for legacy
        element_model = source,
        A = A,
        B = B,
        C = C,
        D = D,
        transformation = transformation,
        setpoint,
        connection = connection,
    )
end
