"""
$(TYPEDSIGNATURES)

Recover MMC circuit values from per-unit constructor parameters.
Subtract half the arm impedance from the AC equivalent to recover the reactor.

# Arguments

- `e`: MMC electrical parameters and bases.

# Returns

- `L_arm`, `L_r`: Arm and reactor inductances \\[H\\].
- `R_arm`, `R_r`: Arm and reactor resistances \\[Ω\\].
- `C_SM`: Submodule capacitance \\[F\\].
- `N`: Number of submodules per arm.
- `turnsRatio`: Transformer turns ratio \\[dimensionless\\].
- `Sbase`: Three-phase apparent-power base \\[MVA\\].
- `vAC_base_LL_RMS`: AC line-to-line RMS voltage base \\[kV\\].
- `vDC_base`: Pole-to-pole DC voltage base \\[kV\\].
- `ωbase`: Angular frequency base \\[rad/s\\].

# Notes

The DC impedance, inductance and capacitance bases are

```math
Z_{DC} = \\frac{V_{DC}^2}{S_b},\\qquad
L_{DC} = \\frac{Z_{DC}}{\\omega_b},\\qquad
C_{DC} = \\frac{1}{\\omega_b Z_{DC}},
```

where ``V_{DC}`` is `vDC_base`, ``S_b`` is `Sbase` and ``\\omega_b`` is `ωbase`.
The resulting bases use \\[Ω\\], \\[H\\] and \\[F\\], respectively.
"""
function mmc_si(e::PowerImpedance.ElectricalMMC)
    zDC = e.vDC_base^2 / e.Sbase
    lDC = zDC / e.ωbase
    cDC = 1 / (e.ωbase * zDC)
    L_arm = e.Lₐᵣₘ * lDC
    R_arm = e.Rₐᵣₘ * zDC
    return (; L_arm, R_arm, C_SM = e.Cₐᵣₘ * cDC,
        L_r = e.Lₑ * e.lAC_base - L_arm / 2,
        R_r = e.Rₑ * e.zAC_base - R_arm / 2,
        e.N, e.turnsRatio, e.Sbase, vAC_base_LL_RMS = e.vAC_base * sqrt(3 / 2),
        e.vDC_base, e.ωbase)
end

"""
$(TYPEDSIGNATURES)

Recover TLC reactor values from the constructor's AC per-unit bases.

# Arguments

- `e`: TLC electrical parameters and bases.

# Returns

- `L_r`: Reactor inductance, `e.Lᵣ * e.lACbase` \\[H\\].
- `R_r`: Reactor resistance, `e.Rᵣ * e.zACbase` \\[Ω\\].
- `Sbase`: Three-phase apparent-power base \\[MVA\\].
- `vAC_base_LL_RMS`: AC line-to-line RMS voltage base \\[kV\\].
- `vDC_base`: Pole-to-pole DC voltage base \\[kV\\].
- `ωbase`: Angular frequency base \\[rad/s\\].
- `l_f_pu`, `r_f_pu`: Unchanged reactor parameters \\[dimensionless\\].
"""
function tlc_si(e::PowerImpedance.ElectricalTLC)
    return (L_r = e.Lᵣ * e.lACbase, R_r = e.Rᵣ * e.zACbase,
        Sbase = e.Sbase, vAC_base_LL_RMS = e.vACbase * sqrt(3 / 2),
        vDC_base = e.vDCbase, ωbase = e.ωbase, l_f_pu = e.Lᵣ, r_f_pu = e.Rᵣ)
end

"""
$(TYPEDSIGNATURES)

Map synchronous-machine equivalent-circuit parameters to PSCAD field names.

# Arguments

- `e`: Synchronous-machine electrical parameters.

# Returns

- An ordered dictionary of stator resistance, leakage reactance, magnetizing
  reactances and rotor branch parameters on the machine's per-unit bases
  \\[dimensionless\\].
"""
function sm_equivalent_circuit(e::PowerImpedance.ElectricalSM)
    return OrderedDict{String, Float64}(
        "Rs1" => e.Ra, "XS1" => e.Ll, "XMD0" => e.La_d,
        "R2D" => e.Rf_d, "X2D" => e.Lf_d, "R3D" => e.R1_d,
        "X3D" => e.L1_d, "X230" => e.L23_d, "XMQ" => e.La_q,
        "R2Q" => e.R1_q, "X2Q" => e.L1_q, "R3Q" => e.R2_q,
        "X3Q" => e.L2_q, "X231" => e.L23_q)
end

"""
$(TYPEDSIGNATURES)

Read transformer T-model circuit values and winding connections.

# Arguments

- `t`: Transformer model.

# Returns

- `L_p`, `L_s`, `L_m`: Primary, secondary and magnetizing inductances \\[H\\].
- `R_p`, `R_s`, `R_m`: Primary, secondary and magnetizing resistances \\[Ω\\].
- `C_t`, `C_s`: Turn-to-turn and stray capacitances \\[F\\].
- `n`: Turns ratio \\[dimensionless\\].
- `organization`: Winding connection.
- `ω`: Angular frequency \\[rad/s\\].

# Errors

- Throws `ArgumentError` for frequency-dependent winding resistance or a
  nonpositive or nonfinite turns ratio.
"""
function transformer_si(t::PowerImpedance.Transformer)
    t.hasRω &&
        throw(ArgumentError("frequency-dependent transformer winding resistance is not exportable"))
    isfinite(t.n) && t.n > 0 ||
        throw(ArgumentError("transformer turns ratio n must be positive"))
    return (L_p = Float64(t.Lₚ), R_p = Float64(t.Rₚ),
        L_s = Float64(t.Lₛ), R_s = Float64(t.Rₛ),
        L_m = Float64(t.Lₘ), R_m = Float64(t.Rₘ),
        C_t = Float64(t.Cₜ), C_s = Float64(t.Cₛ),
        n = Float64(t.n), organization = t.organization, ω = Float64(t.ω))
end

"""
$(TYPEDSIGNATURES)

Format a finite real PSCAD parameter as a decimal or uppercase `E` string.

# Arguments

- `x`: Numeric parameter value.
- `unit`: Optional unit suffix. Default: `nothing`.
- `sigdigits`: Number of significant digits. Default: `9`.

# Returns

- A parameter string with optional ` [unit]` suffix. Use decimal notation for
  zero and rounded magnitudes from `1e-4` up to, but excluding, `1e7`.
  Other values use `E` notation. Integer inputs use integer notation within
  the decimal range.

# Errors

- Throws `ArgumentError` for nonfinite values or nonpositive `sigdigits`.
"""
function pscad_value(x::Real; unit = nothing, sigdigits::Integer = 9)
    isfinite(x) || throw(ArgumentError("PSCAD parameter must be finite"))
    sigdigits > 0 || throw(ArgumentError("sigdigits must be positive"))
    rounded = round(x; sigdigits)
    value = if iszero(rounded) || 1e-4 <= abs(rounded) < 1e7
        if x isa Integer
            @sprintf("%.0f", rounded)
        else
            places = iszero(rounded) ? 1 :
                     max(1, sigdigits - 1 - floor(Int, log10(abs(rounded))))
            decimal = @sprintf("%.*f", places, rounded)
            replace(decimal, r"(?<=\d)0+$" => "") |> s -> endswith(s, ".") ? s * "0" : s
        end
    else
        mantissa, exponent = split(@sprintf("%.*E", sigdigits - 1, rounded), 'E')
        mantissa = replace(mantissa, r"(?<=\d)0+$" => "")
        endswith(mantissa, ".") && (mantissa *= "0")
        mantissa * "E" * string(parse(Int, exponent))
    end
    return unit === nothing ? value : "$value [$unit]"
end
