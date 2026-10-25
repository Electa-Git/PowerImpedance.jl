export impedance

"""
$(TYPEDEF)

Store impedances between input/output terminal pairs, or a complex-frequency callback,
and an optional cached ABCD matrix. Array entries specify individual branches rather
than mutual terms of a coupled series-impedance matrix.

$(TYPEDFIELDS)
"""
@with_kw mutable struct Impedance <: AbstractLinFreqDomain
	"Terminal-pair branch impedances \\[Ω\\] or a callback returning them at complex frequency; zero entries omit branches."
	value::Any = nothing      # either Matrix{ComplexF64} or a function s::Complex -> Matrix{ComplexF64}
	"Cached ABCD matrix for constant impedances, or `nothing` for a callback; A/D blocks are \\[dimensionless\\], B is \\[Ω\\], and C is \\[S\\]."
	ABCD::Any  = nothing      # cached Matrix{ComplexF64} for constant impedances, otherwise nothing
    "Number of physical conductors per side."
    conductors::Int = 1
end


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

"""
$(TYPEDSIGNATURES)

Construct a constant or frequency-dependent network of terminal-pair impedances.

# Arguments

- `z`: Branch impedance specification \\[Ω\\]. A scalar repeats on the diagonal; a
  vector with `conductors` entries defines unequal diagonal branches. An array with
  `conductors²` entries defines all input-to-output branches in column-major order.
  A `Function` `z(s)` returns a scalar or compatible array at complex Laplace frequency
  \\[s⁻¹\\]. Default: `0`.
- `conductors`: Number of terminals per side. For constant data, zero infers the matrix
  order from a square entry count, or one for a scalar. For a callback, zero leaves
  the external terminal count at one. Default: `0`.

# Returns

- An `Impedance` containing a dense branch-impedance array or a frequency callback.

# Notes

For each nonzero ``z_{ij}``, a branch of admittance ``1/z_{ij}`` connects input
terminal ``i`` to output terminal ``j``. Zero entries omit branches; they do not
represent ideal shorts. Diagonal specifications give independent series impedances.
An off-diagonal entry adds a cross-terminal branch, rather than a mutual impedance.

# Errors

- Throws `ArgumentError` when the impedance shape is incompatible with `conductors`
  or when `conductors=0` cannot be inferred from the supplied array.
- A singular branch-to-ABCD conversion propagates a linear-solve error; the default
  all-zero specification is one such case.

# Examples

```julia
single = impedance(z = 5.0, conductors = 1)
diagonal = impedance(z = [1.0, 2.0, 3.0], conductors = 3)
cross_connected = impedance(z = [1.0 0.1; 0.1 2.0], conductors = 2)
dynamic = impedance(z = s -> 0.1 + s * 2e-3, conductors = 1)
```
"""
function impedance(; z = 0, conductors::Int = 0)
	imp = Impedance()
	if z isa Function
		# z(s) must return Number or array-like; we normalize it to a matrix every call.
		imp.value = (s::Complex) -> begin
			Zs = z(s)
			_z_matrix(Zs, conductors)
		end
		imp.ABCD = nothing
		inferred_pins = conductors == 0 ? 1 : conductors
        imp.conductors = inferred_pins
		return imp
	end

	# constant z: normalize once and cache ABCD
	Z = _z_matrix(z, conductors)
	pins_eff = size(Z, 1)
    imp.conductors = pins_eff

	imp.value = Z
	imp.ABCD  = _abcd_from_z(Z, pins_eff)

	return imp
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


function electricalconnections(model::Impedance)
    n = model.conductors
    n in (1, 2, 3) ||
        throw(ArgumentError("Impedance ports do not support $n conductors."))
    domain = n == 3 ? ACABC : DC_CM
    return (side1 = Port(domain), side2 = Port(domain))
end

bases(::Impedance) = nothing


pmtype(model::Impedance, rows) = is_three_phase(model) ?
    (any(row -> iszero(row.bus), rows) ? "shunt" : "branch") : "branchdc"

function convert!(data, imp::Impedance, ::Type{PMACDC}, component_key,
        ports::NamedTuple, global_dict)
    key = component_key.index
    buses = (ports.side1, ports.side2)

    if component_key.pmtype == "shunt"
        ac_bus = iszero(ports.side1) ? ports.side2 : ports.side1
        shunt = Dict{String, Any}()
        shunt["source_id"] = Any["bus", ac_bus]
        shunt["index"] = key
        shunt["shunt_bus"] = ac_bus
        shunt["status"] = 1

        abcd = eval_abcd(imp, global_dict["omega"] * 1im)
        n = 3
        z = abcd[1:n, (n+1):end][1, 1] / global_dict["Z"]
        shunt["gs"] = real(1 / z)
        shunt["bs"] = imag(1 / z)
        data["shunt"][string(key)] = shunt
        return nothing
    elseif component_key.pmtype == "branch"
        branch_ac!(data, key, buses, global_dict)
        branch = data["branch"][string(key)]
        branch["transformer"] = false
        branch["tap"] = 1
        branch["shift"] = 0
        branch["c_rating_a"] = 1

        abcd = eval_abcd(imp, global_dict["omega"] * 1im)
        n = 3
        z = abcd[1:n, (n+1):end][1, 1] / global_dict["Z"]
        branch["br_r"] = real(z)
        branch["br_x"] = imag(z)
        branch["g_fr"] = 0
        branch["b_fr"] = 0
        branch["g_to"] = 0
        branch["b_to"] = 0
        return nothing
    end
    branch_dc!(data, key, buses, global_dict)
    branchdc = data["branchdc"][string(key)]
    abcd = eval_abcd(imp, 1e-6 * 1im)
    z = abcd[1, 2] * global_dict["S"] / global_dict["V"]^2
    # A one-terminal DC impedance is the pole-to-pole loop impedance of the differential
    # model (`transformation_dc`). Each pole has impedance z/2. PowerModelsACDC's branchdc
    # resistance is per pole (dcpol = 2).
    branchdc["r"] = real(z) / 2
    return nothing
end
