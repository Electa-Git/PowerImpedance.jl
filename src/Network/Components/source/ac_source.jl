export ac_source

"""
	ac_source(; args...)

Creates an `n`-phase AC voltage source with configurable amplitude, phase shift, active and reactive power settings, 
and optional series impedance. The source is defined with input and output pins that can be connected to a network.

## Description
The AC source model provides:
- A configurable voltage magnitude `V` (in kV).
- Phase shift `θ` (in radians).
- Active and reactive power reference values (`P`, `Q` in MW/MVAr).
- Limits on generated power (`P_min`, `P_max`, `Q_min`, `Q_max`).
- Series impedance `Z` (in Ω).
- Connection pins (`1.x` and `2.x` for x ∈ {1, ..., `pins`}).

To ground the source, connect a pin to the ground when constructing the network.

## Parameters
```julia
Z     :: Union{Float64, Int} = 0  # Source series impedance [Ω]
V     :: Union{Float64, Int} = 0        # Voltage magnitude (or DC voltage) [kV]
P     :: Union{Float64, Int} = 0        # Reference active power output [MW]
Q     :: Union{Float64, Int} = 0        # Reference reactive power output [MVAr]
P_min :: Union{Float64, Int} = 0        # Minimum active power output [MW]
P_max :: Union{Float64, Int} = 0        # Maximum active power output [MW]
Q_min :: Union{Float64, Int} = 0        # Minimum reactive power output [MVAr]
Q_max :: Union{Float64, Int} = 0        # Maximum reactive power output [MVAr]
pins  :: Int = 1                        # Number of pins for multiphase systems
ABCD :: Matrix{ComplexF64} = zeros(ComplexF64, 0, 0)
```

## Returns
- `Element`: An `Element` instance representing the AC source with specified parameters.

## Example Usage
```julia
# Define a single-phase AC source with 1kV voltage, 50 MW active power, and 20 MVAr reactive power
source = ac_source(V = 1.0, P = 50, Q = 20, P_min = 10, P_max = 100, Q_min = 5, Q_max = 50)

# Define a three-phase AC source with impedance
three_phase_source = ac_source(V = 1.0, P = 50, Q = 20, Z = 0.1, pins = 3)
```

## Notes
- The `ac_source` function initializes a `Source` object and assigns parameter values.
- `transformation` is an internal parameter used in element construction.
- Throws an `ArgumentError` if an unknown parameter is passed.
"""
function ac_source(; pins=1, args...)
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
