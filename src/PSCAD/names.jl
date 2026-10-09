const _NAME_TRANSLITERATIONS = let
    table = Dict{Char, String}()
    for (letters, ascii) in (
        ("₀₁₂₃₄₅₆₇₈₉", "0123456789"), ("⁰¹²³⁴⁵⁶⁷⁸⁹", "0123456789"),
        ("ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ", "aehijklmnoprstuvx"),
        ("ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ", "abcdefghijklmnoprstuvwxyz"),
        ("ᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁⱽᵂ", "ABDEGHIJKLMNOPRTUVW"))
        for (letter, replacement) in zip(letters, ascii)
            table[letter] = string(replacement)
        end
    end
    greek = ("alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta",
        "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron",
        "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega")
    for (letter, replacement) in zip("αβγδεζηθικλμνξοπρστυφχψω", greek)
        table[letter] = replacement
    end
    for (letter, replacement) in zip("ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ", greek)
        table[letter] = uppercasefirst(replacement)
    end
    merge!(table,
        Dict('Δ' => "D", 'Σ' => "S", 'ς' => "sigma", 'ϑ' => "theta",
            'ϕ' => "phi", 'ϖ' => "pi", 'ϵ' => "epsilon", 'ϱ' => "rho",
            'ᵦ' => "beta", 'ᵧ' => "gamma", 'ᵨ' => "rho", 'ᵩ' => "phi", 'ᵪ' => "chi"))
    merge!(table,
        Dict('ᵝ' => "beta", 'ᵞ' => "gamma", 'ᵟ' => "delta", 'ᵠ' => "phi",
            'ᵡ' => "chi", 'ᶿ' => "theta"))
    table
end

function _identifier_text(sym)
    return join(get(_NAME_TRANSLITERATIONS, c, isascii(c) ? string(c) : "")
    for c in string(sym))
end

# Canonical Fortran identifiers are hash keys; values retain their spelling.
# Each netlist or project builder owns its reservations, including seeded names.
struct _NameReservations <: AbstractSet{String}
    names::Dict{String, String}
    function _NameReservations(names = String[])
        used = new(Dict{String, String}())
        for name in names
            push!(used, name)
        end
        return used
    end
end
Base.length(used::_NameReservations) = length(used.names)
Base.iterate(used::_NameReservations, state...) = iterate(values(used.names), state...)
Base.in(name::AbstractString, used::_NameReservations) = haskey(used.names, lowercase(name))
function Base.push!(used::_NameReservations, name::AbstractString)
    get!(used.names, lowercase(name), String(name))
    return used
end

"""
$(TYPEDSIGNATURES)

Convert a name to an ASCII PSCAD identifier of at most 30 characters.
Transliterate Greek and subscript/superscript letters and digits, drop other
non-ASCII characters, and replace ASCII punctuation with underscores. Prefix
`X` when the first character is not a letter. With `used::_NameReservations`,
reserve the result and resolve case-insensitive collisions with `_2`, `_3`,
etc., truncating the stem while retaining the requested letter case.
"""
function pscad_name(sym; used::Union{Nothing, _NameReservations} = nothing)
    name = replace(_identifier_text(sym), r"[^A-Za-z0-9_]" => "_")
    occursin(r"^[A-Za-z]", name) || (name = "X" * name)
    stem = first(name, 30)
    used === nothing && return stem
    candidate = stem
    index = 2
    while candidate in used
        suffix = "_$index"
        candidate = first(stem, 30 - length(suffix)) * suffix
        index += 1
    end
    push!(used, candidate)
    return candidate
end

"""
$(TYPEDSIGNATURES)

Infer a PSCAD bus name from `d/q` or `a/b/c` nets sharing a stem, or from
one DC net. Return `nothing` for other net groups; the caller assigns `BUS<k>`.
"""
function bus_name(nets)
    length(nets) == 1 && return pscad_name(only(nets))
    suffixes = length(nets) == 2 ? Set(['d', 'q']) :
               length(nets) == 3 ? Set(['a', 'b', 'c']) : nothing
    suffixes === nothing && return nothing
    names = _identifier_text.(nets)
    all(name -> length(name) > 1, names) || return nothing
    Set(last.(names)) == suffixes || return nothing
    stems = chop.(names)
    all(==(first(stems)), stems) || return nothing
    return pscad_name(first(stems))
end

"Return the voltage-probe identifier for a named bus."
voltage_probe_name(bus) = "V_$bus"

"Return the current-probe identifier for one named element side."
current_probe_name(element, side) = "I_$(element)_$side"
