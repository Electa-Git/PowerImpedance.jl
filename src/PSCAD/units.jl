"""
$(TYPEDSIGNATURES)

Recover MMC arm and reactor inductances \\[H\\], resistances \\[Ω\\], and
submodule capacitance \\[F\\] from the constructor's per-unit parameters.
Return `N`, `turnsRatio`, `Sbase` \\[MVA\\], `vAC_base_LL_RMS` \\[kV\\],
`vDC_base` \\[kV\\], and `ωbase` \\[rad/s\\] with the SI circuit values.
The DC bases are `zDC = vDC_base^2/Sbase`, `lDC = zDC/ωbase`, and
`cDC = 1/(ωbase*zDC)`; the AC lumped impedance contains half an arm.
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

Recover the TLC reactor `L_r` \\[H\\] and `R_r` \\[Ω\\], and return its
`Sbase` \\[MVA\\], `vAC_base_LL_RMS` \\[kV\\], `vDC_base` \\[kV\\],
`ωbase` \\[rad/s\\], and unchanged `l_f_pu`, `r_f_pu` \\[dimensionless\\].
"""
function tlc_si(e::PowerImpedance.ElectricalTLC)
    return (L_r = e.Lᵣ * e.lACbase, R_r = e.Rᵣ * e.zACbase,
        Sbase = e.Sbase, vAC_base_LL_RMS = e.vACbase * sqrt(3 / 2),
        vDC_base = e.vDCbase, ωbase = e.ωbase, l_f_pu = e.Lᵣ, r_f_pu = e.Rᵣ)
end

"""
$(TYPEDSIGNATURES)

Return the synchronous-machine equivalent-circuit fields required by PSCAD.
All values retain the machine's per-unit bases \\[dimensionless\\].
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

Return the transformer T-model inductances `L_p`, `L_s`, `L_m` \\[H\\],
resistances `R_p`, `R_s`, `R_m` \\[Ω\\], capacitances `C_t`, `C_s` \\[F\\],
turns ratio `n` \\[dimensionless\\], winding `organization`, and `ω` \\[rad/s\\].
Reject frequency-dependent winding resistance and nonpositive turns ratios.
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

Format a finite real PSCAD parameter with `sigdigits` significant digits and
an optional ` [unit]` suffix. Use plain decimal for zero and
`1e-4 <= abs(x) < 1e7`, otherwise uppercase `E` notation. Integer inputs
in the decimal range retain integer notation. Reject nonfinite values.
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
