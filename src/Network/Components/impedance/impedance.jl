export impedance

@with_kw mutable struct Impedance
	value::Any = nothing      # either Matrix{ComplexF64} or a function s::Complex -> Matrix{ComplexF64}
	ABCD::Any  = nothing      # cached Matrix{ComplexF64} for constant impedances, otherwise nothing
end


"""
	impedance(;z :: Union{Int, Float64,  Array{Int}} = 0, pins :: Int = 0)
Creates impedance with specified number of input/output pins `pins`. The impedance expression
 `exp` has to be given in Ω and can have both numerical and symbolic value (example: `z = s-2`).

Pins are named: `1.1`, `1.2`, ..., `1.pins` and `2.1`, `2.2`, ..., `2.pins`

In the case of 1×1 impedance, parameter `z` has only one value.
Example: `impedance(z = 1000, pins = 1)`

If the impedance is multiport, then its value
is given as an array `[val]` with one, `pins` or `pins × pins` number of elements. In the case of one element,
then the impedance has only diagonal nonzero values equal to `val`. In the case of `pins` number of elements,
the impedance has only diagonal nonzero values equal to the values in an array `val`. If the array has the size
`pin × pin`, impedance matrix has the size `pin × pin` and all its values defined.
Examples:
```julia
impedance(z = [s], pins = 3)    # 3×3 impedance with diagonal values equal s
impedance(z = [2,s,s/2], pins = 3) # 3×3 impedance with diagonal values equal 2, s, 0.5s, respectively
impedance(z = [1,s,3,4], pins = 2) # 2×2 impedance with all values defined
```

"""

# Normalize user z into a pins×pins matrix (ComplexF64)
function _z_matrix(z, pins::Int)
	if pins == 0
		# infer pins from array length
		if z isa Number
			return ComplexF64[z;;]   # 1×1
		elseif z isa AbstractArray
			L = length(z)
			pins = Int(round(sqrt(L)))
			pins*pins == L || throw(
				ArgumentError(
					"Cannot infer pins from length(z)=$L (not a perfect square).",
				),
			)
			Z = reshape(z, pins, pins)
			return ComplexF64.(Z)
		else
			throw(ArgumentError("Invalid z specification."))
		end
	end

	# pins known
	if z isa Number
		return Diagonal(fill(ComplexF64(z), pins)) |> Matrix
	elseif z isa AbstractArray
		L = length(z)
		if L == pins
			return Diagonal(ComplexF64.(z)) |> Matrix
		elseif L == 1
			return Diagonal(fill(ComplexF64(z[1]), pins)) |> Matrix
		elseif L == pins*pins
			return ComplexF64.(reshape(z, pins, pins))
		else
			throw(
				ArgumentError(
					"Invalid element specification: number of impedance parameters must be 1, $pins or $(pins*pins).",
				),
			)
		end
	else
		throw(ArgumentError("Invalid z specification."))
	end
end

# Build ABCD (2pins×2pins) from an impedance matrix Z (pins×pins)
function _abcd_from_z(Z::AbstractMatrix{<:Complex}, pins::Int)
	m1 = zeros(ComplexF64, 2pins, 2pins)
	m2 = zeros(ComplexF64, 2pins, 2pins)

	for i in 1:pins
		for j in 1:pins
			zij = Z[i, j]
			if zij != 0
				y             = 1 / zij
				m1[i, i]      += y
				m1[pins+j, i] -= y
				m2[i, j]      += y
				m2[pins+j, j] -= y
			end
		end
		m1[i, pins+i] = -1
		m2[pins+i, pins+i] = -1
	end

	return m1 \ m2
end

function impedance(; z = 0, pins::Int = 0, transformation = false)
	imp = Impedance()
	connection = true
	if z isa Function
		# z(s) must return Number or array-like; we normalize it to a matrix every call.
		imp.value = (s::Complex) -> begin
			Zs = z(s)
			_z_matrix(Zs, pins)
		end
		imp.ABCD = nothing
		inferred_pins = pins == 0 ? 1 : pins
		element = Element(element_value = imp, input_pins = inferred_pins,
			output_pins = inferred_pins,
			transformation = transformation, connection = connection)
		return element
	end

	# constant z: normalize once and cache ABCD
	Z = _z_matrix(z, pins)
	pins_eff = size(Z, 1)

	imp.value = Z
	imp.ABCD  = _abcd_from_z(Z, pins_eff)

	element = Element(element_value = imp, input_pins = pins_eff, output_pins = pins_eff,
		transformation = transformation,connection = connection)
	return element
end

function eval_abcd(imp::Impedance, s::Complex)
	if imp.ABCD !== nothing
		return imp.ABCD
	end
	Z = imp.value(s)                 # pins×pins
	pins = size(Z, 1)
	return _abcd_from_z(Z, pins)
end


function eval_y(imp::Impedance, s::Complex)
	return abcd_to_y(eval_abcd(imp, s))
end

# POWER FLOW


function make_power_flow!(
	imp::Impedance,
	data,
	nodes2bus,
	bus2nodes,
	elem2comp,
	comp2elem,
	elem,
	global_dict,
)

	if is_three_phase(elem)
		if is_load(elem) #This means it's a ground connected impedance --> shunt impedance
			### MAKE BUSES OUT OF THE NODES
			# Find the nodes not connected to the ground
			ac_nodes = make_non_ground_node(elem, bus2nodes)

			ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)
			key = comp_elem_interface!(data, elem2comp, comp2elem, elem, "shunt")

			(data["shunt"])[string(key)] = Dict{String, Any}()
			((data["shunt"])[string(key)])["source_id"] = Any["bus", ac_bus]
			((data["shunt"])[string(key)])["index"] = key
			((data["shunt"])[string(key)])["shunt_bus"] = ac_bus
			data["shunt"][string(key)]["status"] = 1

			abcd = eval_abcd(imp, global_dict["omega"] * 1im)
			n = 3
			Z = (abcd[1:n, (n+1):end])[1, 1] / global_dict["Z"]
			data["shunt"][string(key)]["gs"] = real(1/Z)
			data["shunt"][string(key)]["bs"] = imag(1/Z)
		else
			# Initialize an AC branch between both nodes
			key = branch_ac!(
				data,
				nodes2bus,
				bus2nodes,
				elem2comp,
				comp2elem,
				elem,
				global_dict,
			)
			((data["branch"])[string(key)])["transformer"] = false
			((data["branch"])[string(key)])["tap"] = 1
			((data["branch"])[string(key)])["shift"] = 0
			((data["branch"])[string(key)])["c_rating_a"] = 1

			abcd = eval_abcd(imp, global_dict["omega"] * 1im)
			n = 3
			Z = (abcd[1:n, (n+1):end])[1, 1] / global_dict["Z"] # Assuming impedance with equal values for all phases 
			((data["branch"])[string(key)])["br_r"] = real(Z)
			((data["branch"])[string(key)])["br_x"] = imag(Z)
			((data["branch"])[string(key)])["g_fr"] = 0
			((data["branch"])[string(key)])["b_fr"] = 0
			((data["branch"])[string(key)])["g_to"] = 0
			((data["branch"])[string(key)])["b_to"] = 0
		end
	else
		## DC impedance
		#TODO: Add two pin impedance case here as well --> Transformation from 2 --> 1 pin
		key =
			branch_dc!(data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
		abcd = eval_abcd(imp, 1e-6*1im)
		Z = abcd[1, 2] * global_dict["S"] / global_dict["V"]^2 # To DC per unit system
		((data["branchdc"])[string(key)])["r"] = real(Z)
	end

end
