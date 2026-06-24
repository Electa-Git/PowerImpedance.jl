export dc_source

"""
	dc_source(;args...)
Creates dc voltage in Volts.

Internal impedance can be added with a command impedance after
the equality sign.

Pins: `1.x` and `2.x` for x ∈ {1, ..., pins}

Plus pin is connected to `1.x` and minus to `2.x`. To ground the source,
connect the pin to the ground while constructing the network.

Parameters:
```julia
	V :: Union{Float64, Int} = 0        # DC voltage or voltage magnitude [kV]

	P   :: Union{Float64, Int} = 0      # active power output [MW]
	Q   :: Union{Float64, Int} = 0      # reactive power output [MVAr]
	P_min :: Union{Float64, Int} = 0    # min active power output [MW]
	P_max :: Union{Float64, Int} = 0    # max active power output [MW]
	Q_min :: Union{Float64, Int} = 0    # min reactive power output [MVA]
	Q_max :: Union{Float64, Int} = 0    # max reactive power output [MVA]

	# pins :: Int = 1
	ABCD :: Matrix{ComplexF64} = zeros(ComplexF64, 0, 0)
```
"""
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
