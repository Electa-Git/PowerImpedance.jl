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

Construct an ideal DC voltage-source model with physical operating targets.

# Arguments

- `v`: Pole-to-pole voltage \\[kV\\]. Default: `240.0`.
- `p`: Active power \\[MW\\]. Default: `0.0`.

# Returns

- An immutable `Source` with one conductor, a `DC_CM` port and an ideal ABCD matrix.

# Notes

Set source limits with `component(source; limits = Limits(...))`.

# Examples

```julia
source = dc_source(v = 640.0, p = 100.0)
```
"""
function dc_source(; v = _DC_SOURCE_INPUTS.v.default, p = _DC_SOURCE_INPUTS.p.default)
    return Source(; v, p, conductors = 1, domain = DC_CM)
end
