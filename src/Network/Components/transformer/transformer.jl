export transformer

"""
$(TYPEDEF)

Store a per-phase transformer T-model. For three phases, `n` is the
primary-to-secondary line-to-line voltage ratio for both `:YY` and `:ΔY`.
All equivalent-circuit parameters have the `:YY` Y-equivalent meaning:
`Rₚ`, `Lₚ` and `Rₛ`, `Lₛ` are referred to their own winding sides;
`Rₘ`, `Lₘ` form the primary excitation branch; `Cₜ`, `Cₛ` retain the same
per-phase capacitive paths. Zero `Rₘ` or `Lₘ` omits that excitation term.
`hasRω` and `k` retain the same winding-resistance scaling in both organizations.

`:ΔY` denotes Dyn11 (delta primary, grounded-Y secondary): positive-sequence
secondary voltage leads the primary by 30°, and negative sequence has the
opposite shift. It applies this rotation to the complete `:YY` T-model,
including its capacitive paths. Its internal zero-sequence block is an identity
placeholder decoupled from both other sequences, discarded by the supported
dq transformation. It does not represent physical zero-sequence transfer.
Construct three-phase `:ΔY` elements with `transformation=true`.
"""
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

	n::Union{Int, Float64}    = 0        # voltage ratio (line-to-line for three phases)
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
- `organization`: Three-phase winding organization, `:YY` or `:ΔY` (Dyn11:
  delta primary, grounded-Y secondary, secondary positive sequence leading by 30°).
- `ω`: Rated angular frequency `\\[rad/s\\]`.
- `V₁ᵒ`, `V₁ˢ`, `V₂ᵒ`, `V₂ˢ`: Open- and short-circuit voltages
  `\\[V\\]` used by `def=:tests`.
- `I₁ᵒ`, `I₁ˢ`: Open- and short-circuit primary currents `\\[A\\]`.
- `P₁ᵒ`, `P₁ˢ`: Open- and short-circuit losses `\\[W\\]`.
- `n`: Primary-to-secondary voltage ratio (line-to-line for three phases) `\\[dimensionless\\]`.
- `Lₚ`, `Lₛ`, `Lₘ`: Primary, secondary, and magnetizing inductances
  `\\[H\\]`; winding leakage is referred to its own side, excitation to the primary.
- `Rₚ`, `Rₛ`, `Rₘ`: Primary, secondary, and magnetizing resistances
  `\\[Ω\\]`, with the same side references as the inductances.
- `Cₜ`, `Cₛ`: Turn-to-turn and stray capacitances `\\[F\\]`.
- `hasRω`: Whether winding resistance is frequency dependent.
- `k`: Winding-resistance frequency exponent `\\[dimensionless\\]`.
- `transformation`: Whether to expose dq coordinates, discarding zero sequence.
  Required for three-phase `:ΔY`; default: `false`.

All T-model parameters are per-phase Y-equivalent values for both organizations.
`:ΔY` applies the Dyn11 rotation to the complete `:YY` model, including `Cₜ` and
`Cₛ`, without rescaling impedances or `n`. `hasRω` and `k` use the same 50 Hz
winding-resistance reference as `:YY`. Zero `Rₘ` or `Lₘ` omits that excitation
term. The internal identity zero-sequence block is only a decoupled placeholder
for dq conversion; delta-to-Y zero-sequence isolation has no phase-domain ABCD.

# Returns

- An `Element` containing the detailed transformer model.

# Errors

- Throws `ArgumentError` for an unknown transformer keyword or an untransformed
  three-phase `:ΔY` element. Invalid or zero
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

    if t.pins == 3 && t.organization == :ΔY && !transformation
        throw(ArgumentError(
            "An untransformed :ΔY transformer cannot represent delta-to-Y zero-sequence isolation in phase-domain ABCD; use transformation=true for the supported Dyn11 dq model.",
        ))
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

	# stray capacitance as a parallel path in the per-phase Y-equivalent model
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
        # Dyn11: V1 = r*V2, I1 = I2/conj(r), so
        # V1*conj(I1) = r*V2*conj(I2)/r = V2*conj(I2).
        # For r± = n*exp(∓jπ/6), N± = exp(∓jπ/6)*diag(n, 1/n).
        # This scalar factor commutes through the T cascade. Apply it to
        # the complete per-phase model so the capacitive paths share the
        # secondary frame rotation and retain exactly their YY meaning.
        Z_positive = cis(-π / 6) * Z
        Z_negative = cis(π / 6) * Z

        # Sequence order: [V0, V+, V-, I0, I+, I-]. Zero sequence has
        # no physical ABCD for delta-to-Y isolation. Identity is only an
        # exactly decoupled placeholder removed by transformation_dq.
        Z_sequence = zeros(ComplexF64, 6, 6)
        Z_sequence[1, 1] = Z_sequence[4, 4] = 1
        Z_sequence[[2, 5], [2, 5]] = Z_positive
        Z_sequence[[3, 6], [3, 6]] = Z_negative

        # Fortescue columns [zero, positive, negative]; apply the same
        # basis to voltages and currents, with phase order [a, b, c].
        a = cis(2π / 3)
        T = ComplexF64[1 1 1; 1 a^2 a; 1 a a^2]
        T_vi = LinearAlgebra.kron(Matrix{ComplexF64}(I, 2, 2), T)
        return T_vi * Z_sequence * (adjoint(T_vi) / 3)
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
    # PowerModels uses t = tap*exp(j*shift), with V_to = V_from/t
    # (core/data.jl:15-22, core/admittance_matrix.jl:55-59).
    branch["shift"] = t.pins == 3 && t.organization == :ΔY ? -π / 6 : 0
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
	

    # Dyn11 has the same balanced tap, series and shunt parameters as YY.
    # Remove only its frame rotation before the exact YY conversion.
    balanced_t = t.organization == :ΔY ? Transformer(t; organization = :YY) : t
    abcd = eval_abcd(balanced_t, global_dict["omega"] * 1im)
	n = 3
	(a, b, c, d) = (
		abcd[1:n, 1:n],
		abcd[1:n, (n+1):end],
		abcd[(n+1):end, 1:n],
		abcd[(n+1):end, (n+1):end],
	)
	y = [d * inv(b) c - d * inv(b) * a; -inv(b) inv(b) * a] * global_dict["Z"]

    # Exact pi equivalent of the unshifted two-port. PowerModels scales the
    # primary shunt by tap^2 (core/admittance_matrix.jl:55-59).
    tap = t.n
    ys = -y[1, n + 1] * tap
    yfr = y[1, 1] * tap^2 - ys
    yto = y[n + 1, n + 1] - ys

    branch["tap"] = tap
    branch["br_r"] = real(1 / ys)
    branch["br_x"] = imag(1 / ys)
    branch["g_fr"] = real(yfr)
    branch["b_fr"] = imag(yfr)
    branch["g_to"] = real(yto)
    branch["b_to"] = imag(yto)
	return nothing
end
