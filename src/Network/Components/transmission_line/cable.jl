export cable #function row 81 -> possible up to 4 conducting and insultating layers. Cable group of n cables possible.
export Insulator, Conductor #mutable structures row 4, 13 and 23
# first letter of the variable: Capital -> Mutable Structure (e.g. Cable, Insulator, Conductor), lowercase -> function (e.g. cable)
"""
$(TYPEDEF)

Describe one conducting layer of a coaxial cable.

$(TYPEDFIELDS)
"""
@with_kw mutable struct Conductor #conducting layer //macro @with_kw which decorates a type definition and allow default values and a keyword construct
	"Inner radius `\\[m\\]`."
	rᵢ::Union{Int, Float64} = 0              # inner radius
	"Outer radius `\\[m\\]`."
	rₒ::Union{Int, Float64} = 0              # outer radius
	"Electrical resistivity `\\[Ω·m\\]`."
	ρ::Union{Int, Float64} = 0              # conductor resistivity [Ωm]
	"Relative permeability `\\[dimensionless\\]`."
	μᵣ::Union{Int, Float64} = 1             # relative permeability

	"Optional nominal conducting area `\\[m²\\]`."
	A::Union{Int, Float64} = 0               # nominal area
end

"""
$(TYPEDEF)

Describe one insulating layer and its optional semiconducting screens.

$(TYPEDFIELDS)
"""
@with_kw mutable struct Insulator #insulating layer
	"Inner radius `\\[m\\]`."
	rᵢ::Union{Int, Float64}  = 0               # inner radius
	"Outer radius `\\[m\\]`."
	rₒ::Union{Int, Float64}  = 0               # outer radius #Insulator defined between rᵢ < r < rₒ
	"Relative permittivity `\\[dimensionless\\]`."
	ϵᵣ::Union{Int, Float64} = 1               # relative permittivity
	"Relative permeability `\\[dimensionless\\]`."
	μᵣ::Union{Int, Float64} = 1               # relative permeability
	# If a semiconductor is present, in an insulator, we have: rᵢ < semiconductor < a + a < insulator < b + b < semiconductor < rₒ
	"Inner semiconducting-screen thickness `\\[m\\]`."
	a::Union{Int, Float64} = 0                # inner semiconductor thickness
	"Outer semiconducting-screen thickness `\\[m\\]`."
	b::Union{Int, Float64} = 0                # outer semiconductor thickness
	# From PSCAD manual:
	# A = outer radius of inner conductor + thickness of inner semiconducting screen
	# B = outer radius of inner conductor + thickness of inner semiconducting screen + thickness of insulator layer
	# rₒ = outer radius of inner conductor + thickness of inner semiconducting screen + thickness of insulator layer + thickness of outer semiconducting screen
	# rᵢ = outer radius of inner conductor
end

"""
$(TYPEDEF)

Store the native cable-group geometry, layers, earth properties, and reduction
options used by frequency-domain evaluation.

$(TYPEDFIELDS)
"""
@with_kw mutable struct Cable <: Transmission_line #indicates that the mutable struct Cable is a subtype (<:) of abstract type Transmission_line
	"Physical cable length `\\[m\\]`."
	length::Union{Int, Float64} = 0                    # line length [m]. Union -> it could be both Int or Float64
	"Ordered conducting layers."
	conductors::OrderedDict{Symbol, Conductor} = OrderedDict{Symbol, Conductor}() #OrderedDict -> dictionary with a particular order. Key: Symbol-> C1, C2, C3 and C4. Value: Conductor-> Mutable Struct Conductor, defined above
	"Ordered insulating layers."
	insulators::OrderedDict{Symbol, Insulator} = OrderedDict{Symbol, Insulator}() #OrderedDict -> dictionary with a particular order. Key: Symbol-> I1, I2, I3 and I4. Value: Insulator-> Mutable Struct Insulator, defined above
	"Cable-center coordinates `\\[m\\]`."
	positions::Vector{Tuple{Real, Real}} = [] #Real -> indicates all variables are real number, vector composed by tuple of real numbers. e.g. positions=[(0,0),(1,1)]. Cables positions 1st:x=0, y=0. 2nd: x=1, y=1.
	"Earth relative permeability, relative permittivity, and resistivity `\\[Ω·m\\]`."
	earth_parameters::NTuple{N, Union{Int, Float64}} where N = (1, 1, 1) # (μᵣ, ϵᵣ, ρ) in units ([], [], [Ωm]) compact way of representing the type for a tuple of length N where all elements are of type Int or Float64.
	"Cable geometry identifier."
	configuration::Symbol = :coaxial #Configuration is a datatype symbol with value coaxial Symbol -> Type of data. Symbols can be entered using the quote operator ":"
	"Installation identifier, such as `:underground` or `:aerial`."
	type::Symbol = :underground   # or aerial. for the description, see above.



	"Whether grounded internal conducting layers are Kron-reduced."
	eliminate::Bool = true #eliminate-> variable with Bool datatype and value TRUE (Bool variable can be true or false)-> predifined with true value. If not specified elsewhere in the code, eliminate=true
end

"""
    cable(; length=0, positions=[], earth_parameters=(1, 1, 1),
          configuration=:coaxial, type=:underground, eliminate=true,
          transformation=false, connection=true, layers...)

Construct a frequency-dependent group of coaxial power cables.

# Arguments

- `length`: Physical cable length `\\[m\\]`.
- `positions`: Cable-center coordinates `(x, y)` `\\[m\\]`; one pair per cable.
- `earth_parameters`: Earth relative permeability `\\[dimensionless\\]`,
  relative permittivity `\\[dimensionless\\]`, and resistivity `\\[Ω·m\\]`.
- `configuration`: Cable geometry identifier. Default: `:coaxial`.
- `type`: Installation identifier. Default: `:underground`.
- `eliminate`: Whether grounded internal conducting layers are Kron-reduced.
- `transformation`: Whether to expose a supported transformed representation.
- `connection`: Whether NetworkBuilder includes the element in the system.
- `layers`: Named `Conductor` values (`C1`, `C2`, ...) and `Insulator`
  values (`I1`, `I2`, ...). A metallic screen may be supplied as `SC` together
  with sheath `C2`.

# Returns

- An `Element` with one input and output terminal per cable position.

# Notes

`Conductor` radii and insulator radii are in metres. Conductor resistivity is
in `\\[Ω·m\\]`; relative permeability and permittivity are dimensionless.
The complete phase-domain self and mutual parameter matrices are evaluated at
the requested frequency before optional internal-layer elimination.

# Errors

- Throws `ArgumentError` for an unknown property or layer, or when a metallic
  screen is supplied without sheath `C2`.

# Examples

```julia
cable_element = cable(
    length = 100e3,
    positions = [(-0.5, 1.0), (0.5, 1.0)],
    C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
    I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67),
    C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7),
    earth_parameters = (1.0, 1.0, 100.0),
)
```
"""
function cable(; args...)
	c = Cable()
	transformation = false
	connection = true
	for (key, val) in pairs(args)
		if key == :positions
			for v in val
				push!(c.positions, v)
			end
		elseif in(key, propertynames(c))
			setfield!(c, key, val)
		elseif isa(val, Conductor)
			c.conductors[key] = val
		elseif isa(val, Insulator)
			c.insulators[key] = val
		elseif key == :transformation
			transformation = val
		elseif key == :connection
			connection = val	
		else
			throw(ArgumentError("Unknown cable property name."))
		end
	end

	# conversion procedure
	(c.conductors[:C1].A != 0 && c.conductors[:C1].A != 0.0) ?
	c.conductors[:C1].ρ =
		c.conductors[:C1].ρ * π * c.conductors[:C1].rₒ^2 / c.conductors[:C1].A :
	nothing

	# metallic screen conversions, equivalent sheath layer
	if in(:SC, keys(c.conductors))
		!in(:C2, keys(c.conductors)) &&
			throw(ArgumentError("There must be present sheath together with screen layer."))

		if (c.conductors[:SC].A != 0 && c.conductors[:SC].A != 0.0)
			c.conductors[:C2].rᵢ = sqrt(c.conductors[:SC].rₒ^2 - c.conductors[:SC].A / π)
		else
			c.conductors[:C2].rᵢ = c.conductors[:SC].rᵢ
		end

		c.conductors[:C2].rₒ = sqrt(
			(c.conductors[:C2].rₒ^2 - c.conductors[:SC].rₒ^2) *
			c.conductors[:SC].ρ / c.conductors[:C2].ρ + c.conductors[:SC].rₒ^2,
		)
		delete!(c.conductors, :SC)

		# change Insulator 1
		c.insulators[:I1].rₒ = c.conductors[:C2].rᵢ

		# change Insulator 2
		if in(:I2, keys(c.insulators))
			x =
				log(c.insulators[:I2].rₒ / c.conductors[:C2].rₒ) /
				log(c.insulators[:I2].rₒ / c.insulators[:I2].rᵢ)
			c.insulators[:I2].rᵢ = c.conductors[:C2].rₒ
			c.insulators[:I2].ϵᵣ *= x
			c.insulators[:I2].μᵣ /= x
		end
	end

	# semiconductor configuration
	if in(:I1, keys(c.insulators)) && (c.insulators[:I1].a != 0) &&
	   (c.insulators[:I1].a != 0.0)
		A = c.insulators[:I1].rᵢ + c.insulators[:I1].a
		B = c.insulators[:I1].rₒ - c.insulators[:I1].b
		x = log(c.insulators[:I1].rₒ / c.insulators[:I1].rᵢ) / log(B / A)
		c.insulators[:I1].ϵᵣ *= x
	end

	n = length(c.positions)

	elem = Element(
		input_pins = n,
		output_pins = n,
		element_value = c,
		transformation = transformation,
		connection = connection,
	)
end

function eval_parameters(c::Cable, s::Complex)
	(μᵣᵍ, ϵᵣᵍ, ρᵍ) = c.earth_parameters

	μ₀ = 4π*1e-7
	ϵ₀ = 8.85e-12
	μᵍ = μᵣᵍ * μ₀
	# ϵᵍ = ϵᵣᵍ * ϵ₀   # not used in the original assembly
	# σᵍ = 1/ρᵍ        # not used in the original assembly
	γE = 0.5772156649

	nₗ = length(c.conductors)
	n = length(c.positions)

	Z = zeros(ComplexF64, n*nₗ, n*nₗ)
	P = zeros(ComplexF64, n*nₗ, n*nₗ)

	# ---- Base (single-cable) layer matrices: fill only [1:nₗ, 1:nₗ] then replicate ----
	Zb = zeros(ComplexF64, nₗ, nₗ)
	Pb = zeros(ComplexF64, nₗ, nₗ)

	# series impedance of conductors (eq 39/40/44 logic, same as original)
	max_r = max(
		isempty(c.conductors) ? 0.0 : maximum(r.rₒ for r in values(c.conductors)),
		isempty(c.insulators) ? 0.0 : maximum(r.rₒ for r in values(c.insulators)),
	)

	i = 1
	for key in keys(c.conductors)
		rᵢ = c.conductors[key].rᵢ
		rₒ = c.conductors[key].rₒ
		μ = c.conductors[key].μᵣ * μ₀
		ρ = c.conductors[key].ρ

		m = sqrt(s * μ / ρ)
		Δr = rₒ - rᵢ

		if rᵢ != 0
			Zᵃᵃ = ρ*m/(2π*rᵢ) * coth(m*Δr) - ρ/(2π*rᵢ*(rᵢ+rₒ))
			Zᵇᵇ = ρ*m/(2π*rₒ) * coth(m*Δr) + ρ/(2π*rₒ*(rᵢ+rₒ))
		else
			Zᵇᵇ = ρ*m/(2π*rₒ) * coth(0.733*m*rₒ) + 0.3179*ρ/(π*rₒ^2)
		end
		Zᵃᵇ = ρ*m/(π*(rₒ+rᵢ)) * csch(m*Δr)

		Zb[i, i] += Zᵇᵇ
		if i > 1
			Zb[i, i-1]   += -Zᵃᵇ
			Zb[i-1, i]   += -Zᵃᵇ
			Zb[i-1, i-1] += Zᵃᵃ
		end

		if i == nₗ
			mᵍ = sqrt(s * μᵍ / ρᵍ)
			H = 2 * c.positions[1][2]  # keep original behavior (uses positions[1] for self term)
			d = max_r
			Zᵍ = s*μᵍ/(2π) * (-log(γE*mᵍ*d/2) + 0.5 - 2*mᵍ*H/3)
			Zb[i, i] += Zᵍ
		end

		i += 1
	end

	# shunt "P" build from insulators (same indexing logic as original)
	i = 1
	for key in keys(c.insulators)
		rᵢ = c.insulators[key].rᵢ
		rₒ = c.insulators[key].rₒ
		μ = c.insulators[key].μᵣ * μ₀
		ϵ = c.insulators[key].ϵᵣ * ϵ₀

		Zⁱ = s*μ/(2π) * log(rₒ/rᵢ)
		Pⁱ = log(rₒ/rᵢ) / (2π*ϵ)

		Zb[i, i] += Zⁱ
		Pb[1:i, 1:i] .+= ones(ComplexF64, i, i) .* Pⁱ

		i += 1
	end

	# replicate base blocks to all cables (same as original copy/translate)
	for k in 1:n
		idx = ((k-1)*nₗ+1):(k*nₗ)
		Z[idx, idx] .= Zb
		P[idx, idx] .= Pb
	end

	# mutual earth-return impedance between cables (only at outer layer index, same as original)
	mᵍ = sqrt(s * μᵍ / ρᵍ)
	for i in 1:n
		for j in (i+1):n
			H = c.positions[i][2] + c.positions[j][2]
			d = sqrt(
				(c.positions[i][1] - c.positions[j][1])^2 +
				(c.positions[i][2] - c.positions[j][2])^2,
			)
			Zᵍ = s*μᵍ/(2π) * (-log(γE*mᵍ*d/2) + 0.5 - 2*mᵍ*H/3)
			Z[i*nₗ, j*nₗ] += Zᵍ
			Z[j*nₗ, i*nₗ] += Zᵍ
		end
	end

	# reduction for representation core, sheath and armor (same algebra, now with valid indexing)
	for k in 1:n, l in 1:n
		rows_l = ((l-1)*nₗ+1):(l*nₗ)

		for i in (nₗ-1):-1:1, j in 1:i
			col_j = (k-1)*nₗ + j
			col_ip = (k-1)*nₗ + (i+1)
			Z[rows_l, col_j] .+= Z[rows_l, col_ip]
		end

		cols_l = ((l-1)*nₗ+1):(l*nₗ)
		for i in (nₗ-1):-1:1, j in 1:i
			row_j = (k-1)*nₗ + j
			row_ip = (k-1)*nₗ + (i+1)
			Z[row_j, cols_l] .+= Z[row_ip, cols_l]
		end
	end

	# underground potential coefficients (same as original)
	if c.type == :underground
		for i in 1:n, j in 1:n
			H  = c.positions[i][2] + c.positions[j][2]
			dx = abs(c.positions[i][1] - c.positions[j][1])
			dy = abs(c.positions[i][2] - c.positions[j][2])

			if i == j
				D₁ = max_r
				D₂ = H
			else
				D₁ = sqrt(dx^2 + dy^2)
				D₂ = sqrt(dx^2 + H^2)
			end

			Pᵢⱼ = log(D₂ / D₁) / (2π*ϵ₀)

			idx_i = ((i-1)*nₗ+1):(i*nₗ)
			idx_j = ((j-1)*nₗ+1):(j*nₗ)
			P[idx_i, idx_j] .+= ones(ComplexF64, nₗ, nₗ) .* Pᵢⱼ
		end
	end

	# Kron elimination (unchanged intent, same call)
	if c.eliminate
		cond_noElim = [(i-1)*nₗ + 1 for i in 1:n]
		Z = PowerImpedanceACDC.kron(Z, cond_noElim)
		P = PowerImpedanceACDC.kron(P, cond_noElim)
	end

	Y = s * inv(P)
	return (Z, Y)
end


function eval_abcd(c::Cable, s::Complex)
	(Z, Y) = eval_parameters(c, s) #function eval_parameters receives in input variables c and s and gives in output the series impedance matrix Z and the shunt admittance matrix Y
	γ = sqrt(convert(Array{ComplexF64}, Z*Y)) # conversion of arrays product Z*Y and then Γ=sqrt(Z*Y) -> Simulator tutorial pag 19, bottom page (Calculations same as transmission line case)
	# γ = sqrt(Z*Y) #TODO: This line is added to replace the one on the top, which was giving problems for single DC cables (no transformation). Need to see if this will cause any issue with other components, but so far so good.
	Yc = Z \ γ #Always ottom page 19 simulator_tutorial
	n = Int(size(Yc, 1)) #Saves in n the number of rows present in the vector Yc
	abcd = zeros(Complex, 2n, 2n) #Creation of the ABCD matrix-> zeros matrix with dimension 2n*2n

	abcd[1:n, 1:n] = cosh(γ*c.length) #Eq 33 pag 19 simulator_tutorial. Matrix A[n*n]=cosh(Γl)
	abcd[1:n, (n+1):end] = Yc \ sinh(γ*c.length) #Eq 33 pag 19 simulator_tutorial. Matrix B[n*n]=Yc^-1sinh(Γl)
	abcd[(n+1):end, 1:n] = Yc * sinh(γ*c.length) #Eq 33 pag 19 simulator_tutorial. Matrix C[n*n]=Ycsinh(Γl)
	abcd[(n+1):end, (n+1):end] = cosh(γ*c.length) #Eq 33 pag 19 simulator_tutorial. Matrix D[n*n]=cosh(Γl)
	return abcd
end
