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

Construct an ideal three-phase AC voltage-source model with physical operating targets.

# Arguments

- `v`: Phase-peak voltage \\[kV\\]. Default: `220 / sqrt(3)`.
- `theta`: Voltage angle \\[rad\\]. Default: `0.0`.
- `p`: Active power \\[MW\\]. Default: `0.0`.
- `q`: Reactive power \\[MVAr\\]. Default: `0.0`.

# Returns

- An immutable `Source` with three conductors, an `ACABC` port and an ideal ABCD matrix.

# Notes

Set source limits with `component(source; limits = Limits(...))`.

# Examples

```julia
source = ac_source(v = 220 / sqrt(3), p = 100.0, q = 0.0)
limited = component(source; limits = PowerImpedance.Limits(P_max = 200.0))
```
"""
function ac_source(; v = _AC_SOURCE_INPUTS.v.default,
        theta = _AC_SOURCE_INPUTS.theta.default, p = _AC_SOURCE_INPUTS.p.default,
        q = _AC_SOURCE_INPUTS.q.default)
    return Source(; v, theta, p, q, conductors = 3, domain = ACABC)
end
