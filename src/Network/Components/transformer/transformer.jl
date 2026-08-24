export transformer

@with_kw mutable struct Transformer <: AbstractLinFreqDomain
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
    transformer(def=:explicit; transformer_kwargs...)

Construct a one-phase or balanced three-phase transformer element.

# Arguments

- `def`: Parameterization mode. `:explicit` uses the supplied equivalent-circuit
  values. `:tests` derives them from the open- and short-circuit test fields.
- `pins`: Number of phase-domain terminals. Default: `1`.
- `organization`: Three-phase winding organization, `:YY` or `:ΔY`.
- `ω`: Rated angular frequency `\\[rad/s\\]`.
- `V₁ᵒ`, `V₁ˢ`, `V₂ᵒ`, `V₂ˢ`: Open- and short-circuit voltages
  `\\[V\\]` used by `def=:tests`.
- `I₁ᵒ`, `I₁ˢ`: Open- and short-circuit primary currents `\\[A\\]`.
- `P₁ᵒ`, `P₁ˢ`: Open- and short-circuit losses `\\[W\\]`.
- `n`: Primary-to-secondary turns ratio `\\[dimensionless\\]`.
- `Lₚ`, `Lₛ`, `Lₘ`: Primary, secondary, and magnetizing inductances
  `\\[H\\]`.
- `Rₚ`, `Rₛ`, `Rₘ`: Primary, secondary, and magnetizing resistances
  `\\[Ω\\]`.
- `Cₜ`, `Cₛ`: Turn-to-turn and stray capacitances `\\[F\\]`.
- `hasRω`: Whether winding resistance is frequency dependent.
- `k`: Winding-resistance frequency exponent `\\[dimensionless\\]`.
- `transformation`: Whether to expose transformed three-phase coordinates.

# Returns

- An `Element` containing the detailed transformer model.

# Errors

- Throws `ArgumentError` for an unknown transformer keyword. Invalid or zero
  test data can also make the `:tests` calculation undefined.

# Examples

```julia
transformer_element = transformer(
    :explicit;
    pins = 3,
    organization = :YY,
    n = 1.1,
    Rₚ = 0.1,
    Lₚ = 1e-3,
    Rₛ = 0.1,
    Lₛ = 1e-3,
)
```
"""
function transformer(def=:explicit; args...)
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
	if def == :tests
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

pmtype(::Element{<:Transformer}) = "branch"

function convert!(data,elem::Element{<:Transformer},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)

	key, bus1, bus2 = branch_ac!(data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
		
	return convert!(data, elem, PMACDC, key, (bus1, bus2), global_dict)
end

function convert!(data, elem::Element{<:Transformer}, ::Type{PMACDC}, key_branch, (bus1, bus2), global_dict)
    t = elem.element_model
	branch_ac!(data, key_branch, (bus1, bus2), global_dict)
	branch = data["branch"][string(key_branch)]
	branch["transformer"] = true
	branch["shift"] = 0
	branch["c_rating_a"] = 1

	## Update voltage limits to match the transformer voltage ratings
	if t.V₁ᵒ == t.V₂ᵒ == 0 
		@warn ("Transformer has no open-circuit voltage ratings, voltage limits will be updated with 1pu assumed at primary.")
		Vprim = global_dict["V"] / 1e3
		Vsec = Vprim / t.n
	else	
		Vprim = t.V₁ᵒ
		Vsec = t.V₂ᵒ
		((Vprim != global_dict["V"]/1e3) && (Vsec != global_dict["V"]/1e3)) && @warn ("Transformer voltage ratings do not match system base voltage.")
	end

	Vbase_global = global_dict["V"] / 1e3
	data["bus"][string(bus1)]["vmax"] = (Vprim/Vbase_global)*1.1
	data["bus"][string(bus2)]["vmax"] = (Vsec/Vbase_global)*1.1
	data["bus"][string(bus1)]["vmin"] = (Vprim/Vbase_global)*0.9
	data["bus"][string(bus2)]["vmin"] = (Vsec/Vbase_global)*0.9
	

	abcd = eval_abcd(t, global_dict["omega"] * 1im)
	n = 3
	(a, b, c, d) = (
		abcd[1:n, 1:n],
		abcd[1:n, (n+1):end],
		abcd[(n+1):end, 1:n],
		abcd[(n+1):end, (n+1):end],
	)
	y = [d * inv(b) c - d * inv(b) * a; -inv(b) inv(b) * a] * global_dict["Z"]

	tap = sqrt(real(y[n+1, n+1] / y[1, 1]))
	ys = -y[1, n+1] * tap
	yc = y[n+1, n+1] - ys

	branch["tap"] = tap
	branch["br_r"] = real(1 / ys)
	branch["br_x"] = imag(1 / ys)
	branch["g_fr"] = real(yc) / 2
	branch["b_fr"] = imag(yc) / 2
	branch["g_to"] = real(yc) / 2
	branch["b_to"] = imag(yc) / 2
	return nothing
end
