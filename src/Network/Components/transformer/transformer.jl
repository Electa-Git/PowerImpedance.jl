export transformer

@with_kw mutable struct Transformer
	pins::Int = 1                     # marks single or three phase
	organization::Symbol = :YY        # three phase organization (:YY or :ΔY)

	ω::Union{Int, Float64}      = 2*π*50   # rated frequency in [rad/s]
	V₁ᵒ::Union{Int, Float64} = 0      # open circuit primary voltage [V]
	V₁ˢ::Union{Int, Float64}  = 0      # short circuit primary voltage [V]
	I₁ᵒ::Union{Int, Float64} = 0      # open circuit primary current [V]
	I₁ˢ::Union{Int, Float64}  = 0      # short circuit primary current [V]
	P₁ᵒ::Union{Int, Float64} = 0      # open circuit losses on primary side [W]
	P₁ˢ::Union{Int, Float64}  = 0      # short circuit losses on primary side [W]
	V₂ᵒ::Union{Int, Float64} = 0      # open circuit secondary voltage [V]
	V₂ˢ::Union{Int, Float64}  = 0      # short circuit secondary voltage [V]

	n::Union{Int, Float64}    = 0        # turn ratio
	Lₚ::Union{Int, Float64} = 0       # primary side inductance [H]
	Rₚ::Union{Int, Float64} = 0       # primary side resistance [Ω]
	Rₛ::Union{Int, Float64} = 0       # secondary side resistance [Ω]
	Lₛ::Union{Int, Float64} = 0       # secondary side inductance [H]
	Lₘ::Union{Int, Float64} = 0      # magnetising inductance [H]
	Rₘ::Union{Int, Float64} = 0      # magnetising resistance [Ω]
	Cₜ::Union{Int, Float64} = 0       # turn-to-turn capacitance [F]
	Cₛ::Union{Int, Float64} = 0       # stray capacitance [F] 
	hasRω::Bool              = false              # Boolean to set frequency-dependent winding resistance [-]
	k::Union{Int, Float64}    = 0        # Exponent for frequency-dependent winding resistance [-]
end

"""
	function transformer(;args...)
Creates a dc or a single phase transfromer, or a three-phase transformer in YY
or ΔY configuration.

```julia
@with_kw mutable struct Transformer

	pins :: Int = 1                     # marks single or three phase
	organization :: Symbol = :YY        # three phase organization (:YY or :ΔY)

	ω :: Union{Int, Float64} = 2*π*50   # rated frequency in [Hz]
	V₁ᵒ :: Union{Int, Float64} = 0      # open circuit primary voltage [V]
	V₁ˢ :: Union{Int, Float64} = 0      # short circuit primary voltage [V]
	I₁ᵒ :: Union{Int, Float64} = 0      # open circuit primary current [V]
	I₁ˢ :: Union{Int, Float64} = 0      # short circuit primary current [V]
	P₁ᵒ :: Union{Int, Float64} = 0      # open circuit losses on primary side [W]
	P₁ˢ :: Union{Int, Float64} = 0      # short circuit losses on primary side [W]
	V₂ᵒ :: Union{Int, Float64} = 0      # open circuit secondary voltage [V]
	V₂ˢ :: Union{Int, Float64} = 0      # short circuit secondary voltage [V]

	n :: Union{Int, Float64} = 0        # turn ratio
	Lₚ :: Union{Int, Float64} = 0       # primary side inductance [H]
	Rₚ :: Union{Int, Float64} = 0       # primary side resistance [Ω]
	Rₛ :: Union{Int, Float64} = 0       # secondary side resistance [Ω]
	Lₛ :: Union{Int, Float64} = 0       # secondary side inductance [H]
	Lₘ :: Union{Int, Float64} = 0      # magnetising inductance [H]
	Rₘ :: Union{Int, Float64} = 0      # magnetising resistance [Ω]
	Cₜ :: Union{Int, Float64} = 0       # turn-to-turn capacitance [F]
	Cₛ :: Union{Int, Float64} = 0       # stray capacitance [F]
end
```

Pins: `1.1`, `2.1` for single phase transformer and `1.1`, `1.2`, `1.3`, `2.1`,
`2.2`, `2.3` for a three-phase transformer.
"""

function transformer(; args...)
	t = Transformer()
	transformation = false
	connection = true
	for (key, val) in pairs(args)
		if in(key, propertynames(t))
			setfield!(t, key, val)
		elseif key == :transformation
			transformation = val
		else
			throw(ArgumentError("Transformer does not have a property $(key)."))
		end
	end

	# compute equivalent circuit parameters from OC/SC tests
	if (t.V₁ᵒ != 0)
		t.n = t.V₁ᵒ / t.V₂ᵒ

		R = t.P₁ˢ / (t.I₁ˢ)^2
		L = sqrt((t.V₁ˢ*t.I₁ˢ)^2 - t.P₁ˢ^2) / t.ω / (t.I₁ˢ)^2

		t.Rₚ = R / 2
		t.Rₛ = R / 2 / t.n^2
		t.Lₚ = L / 2
		t.Lₛ = L / 2 / t.n^2

		t.Rₘ = (t.V₁ᵒ)^2 / t.P₁ᵒ
		t.Lₘ = (t.V₁ᵒ)^2 / sqrt((t.V₁ᵒ*t.I₁ᵒ)^2 - t.P₁ᵒ^2) / t.ω
	end

	# DO NOT build t.ABCD here anymore (no symbolics)
	return Element(input_pins = t.pins, output_pins = t.pins,
		element_value = t, transformation = transformation, connection = connection)
end

function eval_abcd(t::Transformer, s::ComplexF64)
	# Frequency-dependent winding resistance scaling
	# Keep the original behavior: base = 2π*50 (NOT t.ω), because the legacy code used that constant.
	wk = t.hasRω ? (abs(s) / (2*π*50))^t.k : 1.0

	# ---- 1-phase building blocks (2×2 ABCD) ----
	Zp = (t.Rₚ * wk) + s * t.Lₚ
	Zs = (t.Rₛ * wk) + s * t.Lₛ

	Zᵖ_winding =
		ComplexF64[                                                                                   1  Zp;
			0  1]

	Zˢ_winding =
		ComplexF64[                                                                               1  Zs;
			0  1]

	# turn-to-turn capacitance (2-port shunt-like block in ABCD form)
	Y_turn =
		ComplexF64[                                                                       1  0;
			s*t.Cₜ  1]

	# ideal transformer block
	N_tr =
		ComplexF64[                                                                      t.n  0;
			0   1/t.n]

	# iron branch (magnetizing)
	Yiron = 0.0 + 0.0im
	(t.Lₘ != 0) && (Yiron += 1 / (s * t.Lₘ))
	(t.Rₘ != 0) && (Yiron += 1 / t.Rₘ)

	Y_iron =
		ComplexF64[                                                                       1  0;
			Yiron  1]

	# base 2×2 ABCD (legacy equation(27) structure)
	Z = Y_turn * (Zᵖ_winding * Y_iron * N_tr * Zˢ_winding) * Y_turn

	# stray capacitance as a parallel path (only implemented in legacy for 1φ / YY branch)
	if (t.Cₛ != 0)
		Z_stray =
			ComplexF64[                                                                 1  1/(s*t.Cₛ);
				0  1]
		Z = connect_parallel!(Z, Z_stray)
	end

	# ---- Lift to requested pin count / topology ----
	if (t.pins == 1)
		return Z
	end

	# 3-phase transformer → ABCD is 6×6 (2n × 2n with n=3)
	if (t.organization == :YY)
		Z₃ₚ = zeros(ComplexF64, 6, 6)
		for i in 1:3
			Z₃ₚ[i, i]     = Z[1, 1]
			Z₃ₚ[i, 3+i]   = Z[1, 2]
			Z₃ₚ[3+i, i]   = Z[2, 1]
			Z₃ₚ[3+i, 3+i] = Z[2, 2]
		end
		return Z₃ₚ
	else
		# ΔY branch: replicate the legacy logic (including its quirks: Y_turn and Z_stray are 6×6 identities)
		# Recompute the 2×2 "front" block used for the ΔY inner construction
		M = Zᵖ_winding * Y_iron * N_tr

		# Match legacy destructuring (Matrix iteration is column-major): (A,B,C,D) = M
		A = M[1, 1]
		B = M[2, 1]
		C = M[1, 2]
		D = M[2, 2]

		sqrt3 = sqrt(3.0)

		current_conversion =
			ComplexF64[
				 1/sqrt3   0       -1/sqrt3;
				-1/sqrt3   1/sqrt3  0;
				 0        -1/sqrt3  1/sqrt3
			] .* D

		Z_inner = zeros(ComplexF64, 6, 6)
		for i in 1:3
			Z_inner[i, i]   = A * sqrt3
			Z_inner[i, 3+i] = B / sqrt3
			Z_inner[3+i, i] = C * sqrt3
			for j in 1:3
				Z_inner[3+i, 3+j] = current_conversion[i, j]
			end
		end

		if (t.Cₛ != 0)
			# Legacy code uses a 6×6 identity as Z_stray in ΔY branch. Keep that behavior.
			Z_stray_6 = Matrix{ComplexF64}(I, 6, 6)
			Z_inner = connect_parallel!(Z_inner, Z_stray_6)
		end

		# Legacy: Y_turn is 6×6 identity here, so Y_turn*Z*Y_turn = Z
		return Z_inner
	end
end


function eval_y(t::Transformer, s::ComplexF64)
	return abcd_to_y(eval_abcd(t, s))
end

function make_power_flow!(
	t::Transformer,
	data,
	nodes2bus,
	bus2nodes,
	elem2comp,
	comp2elem,
	elem,
	global_dict,
)

	# Initialize an AC branch between both nodes
	key_branch =
		branch_ac!(data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)

	# Add transformer data)
	((data["branch"])[string(key_branch)])["transformer"] = true

	((data["branch"])[string(key_branch)])["shift"] = 0
	((data["branch"])[string(key_branch)])["c_rating_a"] = 1

	abcd = eval_abcd(t, global_dict["omega"] * 1im)
	n = 3
	(a, b, c, d) = (
		abcd[1:n, 1:n],
		abcd[1:n, (n+1):end],
		abcd[(n+1):end, 1:n],
		abcd[(n+1):end, (n+1):end],
	)
	Y = [d*inv(b) c-d*inv(b)*a; -inv(b) inv(b)*a] * global_dict["Z"]

	tap = sqrt(real(Y[n+1, n+1]/Y[1, 1]))
	ys = -Y[1, n+1]*tap
	yc = Y[n+1, n+1] - ys

	((data["branch"])[string(key_branch)])["tap"] = tap
	((data["branch"])[string(key_branch)])["br_r"] = real(1/ys)
	((data["branch"])[string(key_branch)])["br_x"] = imag(1/ys)
	((data["branch"])[string(key_branch)])["g_fr"] = real(yc)/2
	((data["branch"])[string(key_branch)])["b_fr"] = imag(yc)/2
	((data["branch"])[string(key_branch)])["g_to"] = real(yc)/2
	((data["branch"])[string(key_branch)])["b_to"] = imag(yc)/2
end

