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
$(TYPEDSIGNATURES)

Construct an ideal AC voltage-source element and its power-flow data.

# Arguments

- `setpoint`: Physical operating point; powers use \\[MW\\] or \\[MVAr\\], voltages \\[kV\\],
  and angles \\[rad\\]. Default: `Setpoint(; Vac = 220 / sqrt(3))`.
- `pins`: Number of terminals per side. Used directly without inference. Default: `1`.
- `limits`: Accepted legacy limits keyword; currently not forwarded to the returned
  element, which retains default `Limits()`. Default: `Limits()`.
- `transformation`: Whether the element exposes transformed external coordinates.
  Default: `false`.
- `connection`: Whether the element participates in network construction. Default:
  `true`.
- `args...`: Additional `Source` field values, such as legacy voltage and power data.

# Returns

- An `Element` whose model is a `Source` and whose ABCD representation is an
  ideal voltage source.

# Errors

- Throws `ArgumentError` when an additional keyword is not a `Source` field.

# Examples

```julia
source = ac_source(
    setpoint = Setpoint(Vac = 220 / sqrt(3), Pac = 100.0, Qac = 0.0),
    pins = 3,
    transformation = true,
)
```
"""
function ac_source(; setpoint = Setpoint(; Vac = _AC_SOURCE_INPUTS.v.default),
        pins=1, limits=Limits(), transformation=false, connection=true, args...)
    source = Source()

    if haskey(args, :V)
        @warn "The legacy `V` field of `ac_source` is not used for power flow and was defined as phase RMS voltage; `setpoint.Vac` is phase peak voltage. Pass the converted voltage through `setpoint=Setpoint(Vac=...)` instead."
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
    source.domain = ACABC
    source.limits = Limits()
    source.v = ismissing(setpoint.Vac) ? _AC_SOURCE_INPUTS.v.default : setpoint.Vac
    source.theta = ismissing(setpoint.θac) ? _AC_SOURCE_INPUTS.theta.default : setpoint.θac
    source.p = ismissing(setpoint.Pac) ? _AC_SOURCE_INPUTS.p.default : setpoint.Pac
    source.q = ismissing(setpoint.Qac) ? _AC_SOURCE_INPUTS.q.default : setpoint.Qac

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
