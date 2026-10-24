export transformer

"""
$(TYPEDEF)

Store a per-phase transformer T-model. For three phases, `n` is the
primary-to-secondary line-to-line voltage ratio for both `:YY` and `:ΔY`.
Equivalent-circuit parameters use the `:YY` Y-equivalent values:
`Rₚ` and `Lₚ` use primary-side values, while `Rₛ` and `Lₛ` use secondary-side
values. `Rₘ` and `Lₘ` form the primary excitation branch, and `Cₜ` and `Cₛ`
specify per-phase capacitive paths. Zero `Rₘ` or `Lₘ` omits that excitation term.
`hasRω` and `k` give the same winding-resistance scaling in both organizations.

`:ΔY` denotes Dyn11 (delta primary, grounded-Y secondary): positive-sequence
secondary voltage leads the primary by 30°, and negative sequence has the
opposite shift. It applies this rotation to the complete `:YY` T-model,
including its capacitive paths. Its internal zero-sequence block is an identity
placeholder decoupled from both other sequences, discarded by the supported
dq transformation. It does not represent physical zero-sequence transfer.
Construct three-phase `:ΔY` elements with `transformation=true`.

$(TYPEDFIELDS)
"""
@with_kw mutable struct Transformer <: AbstractLinFreqDomain
	"Number of phase-domain terminals per side: one or three."
	pins::Int = 1                     # marks single or three phase
	"Winding organization: `:YY` or `:ΔY` (Dyn11)."
	organization::Symbol = :YY        # three phase organization (:YY or :ΔY)

	"Rated electrical angular frequency \\[rad/s\\]."
	ω::Union{Int, Float64}      = 2*π*50   # rated frequency in [rad/s]
	"Open-circuit primary voltage \\[V\\]."
	V₁ᵒ::Union{Int, Float64} = 0      # open circuit primary voltage [V]
	"Short-circuit primary voltage \\[V\\]."
	V₁ˢ::Union{Int, Float64}  = 0      # short circuit primary voltage [V]
	"Open-circuit primary current \\[A\\]."
	I₁ᵒ::Union{Int, Float64} = 0      # open circuit primary current [A]
	"Short-circuit primary current \\[A\\]."
	I₁ˢ::Union{Int, Float64}  = 0      # short circuit primary current [A]
	"Open-circuit primary loss \\[W\\]."
	P₁ᵒ::Union{Int, Float64} = 0      # open circuit losses on primary side [W]
	"Short-circuit primary loss \\[W\\]."
	P₁ˢ::Union{Int, Float64}  = 0      # short circuit losses on primary side [W]
	"Open-circuit secondary voltage \\[V\\]."
	V₂ᵒ::Union{Int, Float64} = 0      # open circuit secondary voltage [V]
	"Stored short-circuit secondary voltage \\[V\\]."
	V₂ˢ::Union{Int, Float64}  = 0      # short circuit secondary voltage [V]

	"Primary-to-secondary voltage ratio; line-to-line for three phases \\[dimensionless\\]."
	n::Union{Int, Float64}    = 0        # voltage ratio (line-to-line for three phases)
	"Primary winding inductance \\[H\\]."
	Lₚ::Union{Int, Float64} = 0       # primary side inductance [H]
	"Primary winding resistance \\[Ω\\]."
	Rₚ::Union{Int, Float64} = 0       # primary side resistance [Ω]
	"Secondary winding resistance \\[Ω\\]."
	Rₛ::Union{Int, Float64} = 0       # secondary side resistance [Ω]
	"Secondary winding inductance \\[H\\]."
	Lₛ::Union{Int, Float64} = 0       # secondary side inductance [H]
	"Primary excitation inductance; zero omits this term \\[H\\]."
	Lₘ::Union{Int, Float64} = 0      # magnetising inductance [H]
	"Primary excitation resistance; zero omits this term \\[Ω\\]."
	Rₘ::Union{Int, Float64} = 0      # magnetising resistance [Ω]
	"Per-phase turn-to-turn capacitance \\[F\\]."
	Cₜ::Union{Int, Float64} = 0       # turn-to-turn capacitance [F]
	"Per-phase stray capacitance \\[F\\]."
	Cₛ::Union{Int, Float64} = 0       # stray capacitance [F] 
	"Whether winding resistances are scaled with absolute complex frequency."
	hasRω::Bool              = false              # Boolean to set frequency-dependent winding resistance [-]
	"Exponent of winding-resistance frequency scaling \\[dimensionless\\]."
	k::Union{Int, Float64}    = 0        # Exponent for frequency-dependent winding resistance [-]
end

"""
$(TYPEDSIGNATURES)

Construct a one-phase or balanced three-phase transformer element.

# Arguments

- `def`: Parameterization mode. `:explicit` uses the supplied equivalent-circuit
  values. `:tests` derives them from the open- and short-circuit test fields.
  Default: `:explicit`.
- `pins`: Number of phase-domain terminals. Default: `1`.
- `organization`: Three-phase winding organization, `:YY` or `:ΔY` (Dyn11:
  delta primary, grounded-Y secondary, secondary positive sequence leading by 30°).
- `ω`: Rated angular frequency `\\[rad/s\\]`.
- `V₁ᵒ`, `V₁ˢ`, `V₂ᵒ`: Open- and short-circuit voltages
  `\\[V\\]` used by `def=:tests`; `V₁ᵒ` and `V₂ᵒ` also specify power-flow voltage ratings.
- `V₂ˢ`: Stored secondary short-circuit voltage `\\[V\\]`, unused by the implemented
  parameter conversion.
- `I₁ᵒ`, `I₁ˢ`: Open- and short-circuit primary currents `\\[A\\]`.
- `P₁ᵒ`, `P₁ˢ`: Open- and short-circuit losses `\\[W\\]`.
- `n`: Primary-to-secondary voltage ratio (line-to-line for three phases)
  `\\[dimensionless\\]`.
- `Lₚ`, `Lₛ`, `Lₘ`: Primary, secondary, and magnetizing inductances
  `\\[H\\]`; winding leakage is referred to its own side, excitation to the primary.
- `Rₚ`, `Rₛ`, `Rₘ`: Primary, secondary, and magnetizing resistances
  `\\[Ω\\]`, with the same side references as the inductances.
- `Cₜ`, `Cₛ`: Turn-to-turn and stray capacitances `\\[F\\]`.
- `hasRω`: Whether winding resistance is frequency dependent.
- `k`: Winding-resistance frequency exponent `\\[dimensionless\\]`.
- `transformation`: Whether to expose dq coordinates, discarding zero sequence.
  Required for three-phase `:ΔY`; default: `false`.

For three phases, test data is per phase: phase-RMS voltages, phase currents,
and per-phase losses. Power-flow voltage ratings use the same phase-RMS
convention and impose ±10 % bounds. With `V₁ᵒ == V₂ᵒ == 0`, nominal bus
levels are inferred from finite, positive AC source voltage setpoints outside
±10 % of the network base. They propagate in both directions through transformer
voltage ratios and unchanged through AC branches joining two non-ground buses.
Shunts and converters do not propagate levels. In element order, each unreached
transformer primary is assigned the base and its level propagated in the same way.
Sources within the base band do not redefine the nominal level. Conflicting
levels differing by more than 1 % warn and retain the first level.

All T-model parameters are per-phase Y-equivalent values for both organizations.
`:ΔY` applies the Dyn11 rotation to the complete `:YY` model, including `Cₜ` and
`Cₛ`, without rescaling impedances or `n`. `hasRω` and `k` use the same 50 Hz
winding-resistance reference as `:YY`. Zero `Rₘ` or `Lₘ` omits that excitation
term. The internal identity zero-sequence block is only a decoupled placeholder
for dq conversion; delta-to-Y zero-sequence isolation has no phase-domain ABCD.
- `args...`: Remaining component-field keywords described above.

# Returns

- An `Element` containing the detailed transformer model.

# Notes

```math
n=V_1^o/V_2^o,\\quad R=P_1^s/(I_1^s)^2,\\quad L=\\frac{\\sqrt{(V_1^sI_1^s)^2-(P_1^s)^2}}{\\omega(I_1^s)^2},\\quad R_m=(V_1^o)^2/P_1^o.
```

In `:tests` mode the primary winding receives half of ``R,L`` and the secondary receives
the other half divided by ``n²``. The excitation inductance is derived from the
open-circuit reactive power. The stored test values are interpreted per the implemented
formulas; no three-phase test-data conversion is applied.

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

"""
$(TYPEDSIGNATURES)

Evaluate the component ABCD representation at complex frequency `s`.

# Arguments

- `t`: Transformer T-model and winding organization.
- `s`: Complex Laplace frequency \\[s⁻¹\\]; sinusoidal evaluation uses `s = 2π * im * f`
  for frequency `f` \\[Hz\\].

# Returns

- ABCD matrix with A/D blocks \\[dimensionless\\], B block \\[Ω\\], and C block \\[S\\].

# Notes

```math
Z_p=R_p w_k+sL_p,\\quad Z_s=R_s w_k+sL_s,\\quad Y_m=R_m^{-1}+(sL_m)^{-1},\\quad w_k=(|s|/(2\\pi\\,50))^k.
```

The resistance multiplier is unity unless `hasRω` is enabled. Zero magnetizing
resistance or inductance omits its term. Series-winding, excitation, ideal-ratio, and
capacitive two-ports are cascaded in implementation order. For Dyn11, the complete
positive/negative-sequence models are multiplied by ``e^{∓jπ/6}``; the internal
zero-sequence identity is a placeholder removed by the supported dq transformation.

# Examples

```julia
using PowerImpedance
model = transformer(n=2.0, Rₚ=0.1, Lₚ=1e-3).element_model
PowerImpedance.eval_abcd(model, 2π*im*50)
```
"""
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
		@warn ("Transformer has no open-circuit voltage ratings; voltage limits will use inferred bus voltage levels.")
		levels = get(global_dict, "transformer_voltage_levels", nothing)
		Vbase = global_dict["V"] / 1e3
		Vprim, Vsec = levels === nothing ? (Vbase, Vbase / t.n) : levels[elem.symbol]
	else	
		Vprim = t.V₁ᵒ / 1e3
		Vsec = t.V₂ᵒ / 1e3
		((Vprim != global_dict["V"]/1e3) && (Vsec != global_dict["V"]/1e3)) && @warn ("Transformer voltage ratings do not match system base voltage.")
	end

	Vbase_global = global_dict["V"] / 1e3
	bounded_buses = get(global_dict, "transformer_voltage_bounded_buses", nothing)
	for (bus, voltage) in ((bus1, Vprim), (bus2, Vsec))
		bounded_buses !== nothing && bus in bounded_buses && continue
		data["bus"][string(bus)]["vmax"] = (voltage/Vbase_global)*1.1
		data["bus"][string(bus)]["vmin"] = (voltage/Vbase_global)*0.9
		bounded_buses === nothing || push!(bounded_buses, bus)
	end
	

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

function electricalconnections(model::Transformer)
    n = model.pins
    n in (1, 2, 3) ||
        throw(ArgumentError("Transformer ports do not support $n conductors."))
    domain = n == 3 ? ACABC : DC_CM
    return (side1 = Port(domain), side2 = Port(domain))
end

bases(::Transformer) = nothing


pmtype(::Transformer, rows) = "branch"

function convert!(data, t::Transformer, ::Type{PMACDC}, component_key,
        ports::NamedTuple, global_dict)
    key_branch = component_key.index
    bus1, bus2 = ports.side1, ports.side2
    branch_ac!(data, key_branch, (bus1, bus2), global_dict)
    branch = data["branch"][string(key_branch)]
    branch["transformer"] = true
    # PowerModels uses t = tap*exp(j*shift), with V_to = V_from/t
    # (core/data.jl:15-22, core/admittance_matrix.jl:55-59).
    branch["shift"] = t.pins == 3 && t.organization == :ΔY ? -π / 6 : 0
    branch["c_rating_a"] = 1

    ## Update voltage limits to match the transformer voltage ratings
    if t.V₁ᵒ == t.V₂ᵒ == 0
        @warn ("Transformer has no open-circuit voltage ratings; " *
            "voltage limits will use inferred bus voltage levels.")
        levels = get(global_dict, "transformer_voltage_levels", nothing)
        Vbase = global_dict["V"] / 1e3
        Vprim, Vsec = levels === nothing ? (Vbase, Vbase / t.n) : levels[component_key.name]
    else
        Vprim = t.V₁ᵒ / 1e3
        Vsec = t.V₂ᵒ / 1e3
        ((Vprim != global_dict["V"]/1e3) && (Vsec != global_dict["V"]/1e3)) &&
            @warn ("Transformer voltage ratings do not match system base voltage.")
    end

    Vbase_global = global_dict["V"] / 1e3
    bounded_buses = get(global_dict, "transformer_voltage_bounded_buses", nothing)
    for (bus, voltage) in ((bus1, Vprim), (bus2, Vsec))
        bounded_buses !== nothing && bus in bounded_buses && continue
        data["bus"][string(bus)]["vmax"] = (voltage/Vbase_global)*1.1
        data["bus"][string(bus)]["vmin"] = (voltage/Vbase_global)*0.9
        bounded_buses === nothing || push!(bounded_buses, bus)
    end


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
