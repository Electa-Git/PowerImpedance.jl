export overhead_line
export Overhead_line, Conductors, Groundwires

@with_kw mutable struct Conductors
	nᵇ::Int = 1                       # number of bundles (phases)
	nˢᵇ::Int = 1                      # number of subconductors per bundle
	yᵇᶜ::Union{Int, Float64} = 0     # height above the ground of the lowest bundle  [m]
	Δyᵇᶜ::Union{Int, Float64} = 0     # vertical offset between the bundles   [m]
	Δxᵇᶜ::Union{Int, Float64} = 0     # horizontal offset between the lowest bundles  [m]
	Δ̃xᵇᶜ::Union{Int, Float64} = 0     # horizontal offset in group of bundles    [m]
	dˢᵃᵍ::Union{Int, Float64} = 0     # sag offset    [m]
	dˢᵇ::Union{Int, Float64} = 0      # subconductor spacing (symmetric)  [m]
	rᶜ::Union{Int, Float64} = 0       # conductor radius  [m]
	Rᵈᶜ::Union{Int, Float64} = 0      # DC resistance for the entire conductor [Ω/m]
	gᶜ::Union{Int, Float64} = 1e-11   # shunt conductance
	μᵣᶜ::Union{Int, Float64} = 1      # relative conductor permeability
	positions::Tuple{Vector{Union{Int, Float64}}, Vector{Union{Int, Float64}}} = ([], [])   # add absolute positions manually
	organization::Symbol = Symbol()
end

@with_kw mutable struct Groundwires
	nᵍ::Int = 0                        # number of groundwires (typically 0 or 2)
	Δxᵍ::Union{Int, Float64} = 0       # horizontal offset between groundwires [m]
	Δyᵍ::Union{Int, Float64} = 0       # vertical offset between the lowest conductor and groundwires  [m]
	rᵍ::Union{Int, Float64} = 0        # ground wire radius  [m]
	dᵍˢᵃᵍ::Union{Int, Float64} = 0    # sag offset [m]
	Rᵍᵈᶜ::Union{Int, Float64} = 0      # groundwire DC resistance [Ω/m]
	μᵣᵍ::Union{Int, Float64} = 1       # relative groundwire permeability
	positions::Tuple{Vector{Union{Int, Float64}}, Vector{Union{Int, Float64}}} = ([], [])    # add absolute positions manually
end

@with_kw mutable struct Overhead_line <: Transmission_line
	length::Union{Int, Float64} = 0       # line length [m]
	conductors::Conductors = Conductors()
	groundwires::Groundwires = Groundwires()
	earth_parameters::NTuple{N, Union{Int, Float64}} where N = (1, 1, 1) # (μᵣ_earth, ϵᵣ_earth, ρ_earth) in units ([], [], [Ωm])




end

"""
	overhead_line(;args...)
Generates the element `elem` with the  `element_value` of the type `Transmission_line`. Arguments should be given in the
form of struct `Transmission_line` fields:
...
- length - line length [m]
- conductors - defined in the
```julia
struct Conductors
	nᵇ :: Int = 1                       # number of bundles (phases)
	nˢᵇ :: Int = 1                      # number of subconductors per bundle
	yᵇᶜ :: Union{Int, Float64}  = 0     # height above the ground of the lowest bundle  [m]
	Δyᵇᶜ :: Union{Int, Float64} = 0     # vertical offset between the bundles   [m]
	Δxᵇᶜ :: Union{Int, Float64} = 0     # horizontal offset between the lowest bundles  [m]
	Δ̃xᵇᶜ :: Union{Int, Float64} = 0     # horizontal offset in group of bundles    [m]
	dˢᵃᵍ :: Union{Int, Float64} = 0     # sag offset    [m]
	dˢᵇ :: Union{Int, Float64} = 0      # subconductor spacing (symmetric)  [m]
	rᶜ :: Union{Int, Float64} = 0       # conductor radius  [m]
	Rᵈᶜ :: Union{Int, Float64} = 0      # DC resistance for the entire conductor [Ω/m]
	gᶜ :: Union{Int, Float64} = 1e-11   # shunt conductance
	μᵣᶜ :: Union{Int, Float64} = 1      # relative conductor permeability
	positions :: Tuple{Vector{Union{Int, Float64}}, Vector{Union{Int, Float64}}} = ([],[])   # add absolute positions manually
	organization :: Symbol = Symbol()
end
```
- groundwires - defined in the
```julia
struct Groundwires
	nᵍ :: Int = 0                        # number of groundwires (typically 0 or 2)
	Δxᵍ :: Union{Int, Float64} = 0       # horizontal ofsset between groundwires [m]
	Δyᵍ :: Union{Int, Float64} = 0       # vertical offset between the lowest conductor and groundwires  [m]
	rᵍ :: Union{Int, Float64} = 0        # ground wire radius  [m]
	dᵍˢᵃᵍ ::  Union{Int, Float64} = 0    # sag offset [m]
	Rᵍᵈᶜ :: Union{Int, Float64} = 0      # groundwire DC resistance [Ω/m]
	μᵣᵍ :: Union{Int, Float64} = 1       # relative groundwire permeability
	positions :: Tuple{Vector{Union{Int, Float64}}, Vector{Union{Int, Float64}}} = ([],[])    # add absolute positions manually

end
```
- earth\\_parameters - with default value `(1,1,1)` and meaning (μᵣ\\_earth, ϵᵣ\\_earth, ρ\\_earth) in units ([], [], [Ωm])

Example:
```
transmission_line(length = 227e3, conductors = Conductors(nᵇ = 2, nˢᵇ = 2, organization = :flat,
Rᵈᶜ = 0.06266, rᶜ = 0.01436, yᵇᶜ = 27.5, Δxᵇᶜ = 11.8, dˢᵇ = 0.4572, dˢᵃᵍ = 10),
earth_parameters = (1,1,100),
groundwires = Groundwires(nᵍ = 2, Δxᵍ = 6.5, Δyᵍ = 7.5, Rᵍᵈᶜ = 0.9196, rᵍ = 0.0062, dᵍˢᵃᵍ = 10))
```
"""


function overhead_line(; args...)
	tl = Overhead_line()
	transformation = false
	connection = true
	for (key, val) in pairs(args)
		if in(key, propertynames(tl))
			setfield!(tl, key, val)
		elseif key == :transformation
			transformation = val
		elseif key == :connection
			connection = val
		else
			throw(ArgumentError("Unknown property $(key) of the overhead line."))
		end
	end

	# No P/Z assembly here anymore (no symbolics).
	# P and Z fields remain in the struct (architecture unchanged), but are unused.

	return Element(
		input_pins = tl.conductors.nᵇ,
		output_pins = tl.conductors.nᵇ,
		element_value = tl,
		transformation = transformation,
		connection = connection,
	)
end

function eval_parameters(tl::Overhead_line, s::Complex)
	# ---------- local geometry builders (same logic, no symbolics) ----------
	function estimate_flat(c::Conductors)
		if c.nᵇ == 2
			return (Float64[-c.Δxᵇᶜ/2, c.Δxᵇᶜ/2], Float64[c.yᵇᶜ, c.yᵇᶜ])
		elseif c.nᵇ == 3
			return (Float64[-c.Δxᵇᶜ, 0.0, c.Δxᵇᶜ], Float64[c.yᵇᶜ, c.yᵇᶜ, c.yᵇᶜ])
		elseif c.nᵇ == 6
			return (
				Float64[-c.Δxᵇᶜ, 0.0, c.Δxᵇᶜ, -c.Δxᵇᶜ, 0.0, c.Δxᵇᶜ],
				Float64[c.yᵇᶜ, c.yᵇᶜ, c.yᵇᶜ, c.yᵇᶜ+c.Δyᵇᶜ, c.yᵇᶜ+c.Δyᵇᶜ, c.yᵇᶜ+c.Δyᵇᶜ],
			)
		else
			throw(ArgumentError("Invalid definition of flat conductor organization."))
		end
	end

	function estimate_vertical(c::Conductors)
		if c.nᵇ == 3
			return (Float64[c.Δxᵇᶜ/2 for _ in 1:c.nᵇ],
				Float64[c.yᵇᶜ + i*c.Δyᵇᶜ for i in 1:c.nᵇ])
		elseif c.nᵇ == 6
			return (
				Float64[c.Δxᵇᶜ/2, c.Δxᵇᶜ/2, c.Δxᵇᶜ/2, -c.Δxᵇᶜ/2, -c.Δxᵇᶜ/2, -c.Δxᵇᶜ/2],
				Float64[
					c.yᵇᶜ,
					c.yᵇᶜ+c.Δyᵇᶜ,
					c.yᵇᶜ+2c.Δyᵇᶜ,
					c.yᵇᶜ,
					c.yᵇᶜ+c.Δyᵇᶜ,
					c.yᵇᶜ+2c.Δyᵇᶜ,
				],
			)
		else
			throw(ArgumentError("Invalid definition of vertical conductor organization."))
		end
	end

	function estimate_delta(c::Conductors)
		if c.nᵇ % 3 != 0
			throw(ArgumentError("Delta cannot be constructed from $(c.nᵇ) conductors."))
		end
		if c.nᵇ == 3
			return (Float64[-c.Δxᵇᶜ/2, c.Δxᵇᶜ/2, 0.0],
				Float64[c.yᵇᶜ, c.yᵇᶜ+c.Δyᵇᶜ, c.yᵇᶜ])
		elseif c.nᵇ == 6
			return (
				Float64[
					-c.Δxᵇᶜ/2-c.Δ̃xᵇᶜ,
					-c.Δxᵇᶜ/2-c.Δ̃xᵇᶜ/2,
					-c.Δxᵇᶜ/2,
					c.Δxᵇᶜ/2,
					c.Δxᵇᶜ/2+c.Δ̃xᵇᶜ/2,
					c.Δxᵇᶜ/2+c.Δ̃xᵇᶜ,
				],
				Float64[
					c.yᵇᶜ,
					c.yᵇᶜ+c.Δyᵇᶜ,
					c.yᵇᶜ,
					c.yᵇᶜ,
					c.yᵇᶜ+c.Δyᵇᶜ,
					c.yᵇᶜ,
				],
			)
		else
			throw(ArgumentError("Invalid definition of delta conductor organization."))
		end
	end

	function estimate_concentric(c::Conductors)
		if c.nᵇ % 3 != 0
			throw(ArgumentError("Delta cannot be constructed from $(c.nᵇ) conductors."))
		end
		if c.nᵇ == 3
			return (Float64[-c.Δ̃xᵇᶜ, 0.0, 0.0],
				Float64[c.yᵇᶜ+c.Δyᵇᶜ, c.yᵇᶜ, c.yᵇᶜ+2c.Δyᵇᶜ])
		elseif c.nᵇ == 6
			return (
				Float64[
					-c.Δxᵇᶜ/2-c.Δ̃xᵇᶜ,
					-c.Δxᵇᶜ/2,
					-c.Δxᵇᶜ/2,
					c.Δxᵇᶜ/2,
					c.Δxᵇᶜ/2,
					c.Δxᵇᶜ/2+c.Δ̃xᵇᶜ,
				],
				Float64[
					c.yᵇᶜ+c.Δyᵇᶜ,
					c.yᵇᶜ,
					c.yᵇᶜ+2c.Δyᵇᶜ,
					c.yᵇᶜ,
					c.yᵇᶜ+2c.Δyᵇᶜ,
					c.yᵇᶜ+c.Δyᵇᶜ,
				],
			)
		else
			throw(ArgumentError("Invalid definition of concentric conductor organization."))
		end
	end

	estimate_offset = estimate_concentric  # your current code duplicates these anyway

	dict_organization = Dict{Symbol, Function}(
		:flat       => estimate_flat,
		:vertical   => estimate_vertical,
		:delta      => estimate_delta,
		:concentric => estimate_concentric,
		:offset     => estimate_offset,
	)

	function bundle_position(nsub::Int, dsub::Real)
		# Make it always return vectors so indexing never explodes.
		if nsub == 1
			return (Float64[0.0], Float64[0.0])
		end
		ϕ = 2π / nsub
		r = dsub / 2 / sin(ϕ/2)
		ϕₛ = π/2
		if iseven(nsub)
			ϕₛ += ϕ/2
		end
		x_sub = Vector{Float64}(undef, nsub)
		y_sub = Vector{Float64}(undef, nsub)
		for i in 1:nsub
			x_sub[i] = r * cos(ϕₛ)
			y_sub[i] = r * sin(ϕₛ)
			ϕₛ += ϕ
		end
		return (x_sub, y_sub)
	end

	# ---------- constants ----------
	(μᵣ_earth, ϵᵣ_earth, ρ_earth) = tl.earth_parameters
	μ₀ = 4π * 1e-7
	ϵ₀ = 8.85e-12
	μ_earth = μᵣ_earth * μ₀
	ϵ_earth = ϵᵣ_earth * ϵ₀
	σ_earth = 1 / ρ_earth

	# ---------- assemble conductor + groundwire primitives ----------
	x_array = Float64[]
	y_array = Float64[]
	r_array = Float64[]
	ρ_array = Float64[]   # stored as (Rdc per length) [Ω/m] in your original code (via *1e-3)
	μ_array = Float64[]

	# conductors
	if !(
		in(tl.conductors.organization, keys(dict_organization)) ||
		isempty(tl.conductors.positions)
	)
		throw(ArgumentError("Conductor positions are not defined."))
	else
		x = Float64[]
		y = Float64[]
		if in(tl.conductors.organization, keys(dict_organization))
			(x, y) = dict_organization[tl.conductors.organization](tl.conductors)
		else
			(x, y) = tl.conductors.positions
		end

		(xˢᵇ, yˢᵇ) = bundle_position(tl.conductors.nˢᵇ, tl.conductors.dˢᵇ)

		for i in 1:tl.conductors.nᵇ, j in 1:tl.conductors.nˢᵇ
			push!(x_array, Float64(x[i]) + xˢᵇ[j])
			push!(y_array, Float64(y[i]) + yˢᵇ[j] - (2/3) * Float64(tl.conductors.dˢᵃᵍ))
			push!(r_array, Float64(tl.conductors.rᶜ))
			push!(ρ_array, Float64(tl.conductors.Rᵈᶜ) * 1e-3)
			push!(μ_array, Float64(tl.conductors.μᵣᶜ) * μ₀)
		end
	end

	# groundwires
	nG = tl.groundwires.nᵍ
	if nG > 0
		xg = [Float64(tl.groundwires.Δxᵍ) * i for i in (-(nG-1)/2):1:((nG-1)/2)]
		yg = [Float64(tl.conductors.yᵇᶜ + tl.groundwires.Δyᵍ) for _ in 1:nG]
		for i in 1:nG
			push!(x_array, xg[i])
			push!(y_array, yg[i] - (2/3) * Float64(tl.groundwires.dᵍˢᵃᵍ))
			push!(r_array, Float64(tl.groundwires.rᵍ))
			push!(ρ_array, Float64(tl.groundwires.Rᵍᵈᶜ) * 1e-3)
			push!(μ_array, Float64(tl.groundwires.μᵣᵍ) * μ₀)
		end
	end

	Num = tl.conductors.nᵇ * tl.conductors.nˢᵇ + tl.groundwires.nᵍ

	# ---------- numeric P(s), Z(s) ----------
	P = zeros(ComplexF64, Num, Num)
	Z = zeros(ComplexF64, Num, Num)

	dₑ = sqrt(1 / (s * μ_earth * (σ_earth + s * ϵ_earth)))  # penetration depth

	for iPhase in 1:Num
		xᵢ = x_array[iPhase]
		yᵢ = y_array[iPhase]
		rᵢ = r_array[iPhase]

		ρ_line = ρ_array[iPhase]
		μ_cond = μ_array[iPhase]

		ρ = ρ_line * (π * rᵢ^2)       # matches your original algebra
		m = sqrt(s * μ_cond / ρ)

		for jPhase in 1:Num
			xⱼ = x_array[jPhase]
			yⱼ = y_array[jPhase]

			Dᵢⱼ = sqrt((xᵢ - xⱼ)^2 + (yᵢ + yⱼ)^2)
			D̂ᵢⱼ = sqrt((xᵢ - xⱼ)^2 + (yᵢ + yⱼ + 2dₑ)^2)
			dᵢⱼ = sqrt((xᵢ - xⱼ)^2 + (yᵢ - yⱼ)^2)

			if iPhase != jPhase
				Z[iPhase, jPhase] += s * log(D̂ᵢⱼ / dᵢⱼ) * μ₀ / (2π)
				P[iPhase, jPhase] = log(Dᵢⱼ / dᵢⱼ) / (2π * ϵ₀)
			else
				Z[iPhase, jPhase] +=
					s * μ₀ / (2π) * log(D̂ᵢⱼ / rᵢ) +
					(m * ρ) / (2π * rᵢ) * coth(0.733 * m * rᵢ) +
					0.3179 * ρ / (π * rᵢ^2)

				P[iPhase, jPhase] = log(Dᵢⱼ / rᵢ) / (2π * ϵ₀)
			end
		end
	end

	# ---------- bundled subconductor constraint (same block as your current overhead_line) ----------
	# This is lifted verbatim in spirit from the section before `tl.P = P; tl.Z = Z`. :contentReference[oaicite:5]{index=5}
	if tl.conductors.nˢᵇ != 0
		cond_noElim = [(i-1)*tl.conductors.nˢᵇ + 1 for i in 1:tl.conductors.nᵇ]
		for iPhase in 1:tl.conductors.nᵇ
			cond_noElim_curr = cond_noElim[iPhase]
			for iCond in (tl.conductors.nˢᵇ*(iPhase-1)+2):(tl.conductors.nˢᵇ*iPhase)
				Z[:, iCond] .-= Z[:, cond_noElim_curr]
				Z[iCond, :] .-= Z[cond_noElim_curr, :]

				P[:, iCond] .-= P[:, cond_noElim_curr]
				P[iCond, :] .-= P[cond_noElim_curr, :]
			end
		end
	end

	# ---------- Kron elimination ----------
	if (tl.groundwires.nᵍ + tl.conductors.nˢᵇ > 1)
		cond_noElim = [(i-1)*tl.conductors.nˢᵇ + 1 for i in 1:tl.conductors.nᵇ]
		Z = PowerImpedanceACDC.kron(Z, cond_noElim)
		P = PowerImpedanceACDC.kron(P, cond_noElim)
	end

	# ---------- invert P to get Y ----------
	Y = s * pinv(P) + Diagonal([tl.conductors.gᶜ for _ in 1:size(P, 1)])

	return (Z, Y)
end


"""
	eval_abcd(tl::Overhead_line, s :: Complex)
Form ABCD representation from known values for Y and Z and write values in the dictionary
	Γ = √ZY
	Yᶜ = Z⁻¹γ
	ABCD = [cosh(Γl)    Yᶜ⁻¹sinh(Γl)
			Yᶜsinh(Γl)  cosh(Γl)]
"""
function eval_abcd(tl::Overhead_line, s::Complex)
	(Z, Y) = eval_parameters(tl, s)
	γ = sqrt(convert(Array{ComplexF64}, Z*Y))
	Yc = inv(Z) * γ

	n = Int(size(Yc, 1))
	abcd = zeros(Complex, 2n, 2n)

	abcd[1:n, 1:n] = cosh(γ*tl.length)
	abcd[1:n, (n+1):end] = inv(Yc) * sinh(γ*tl.length)
	abcd[(n+1):end, 1:n] = Yc * sinh(γ*tl.length)
	abcd[(n+1):end, (n+1):end] = cosh(γ*tl.length)

	return abcd
end
