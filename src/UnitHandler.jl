"""
    UnitHandler

Define physical-quantity tags, display units, metric scaling, and numeric
presentation independently of a plotting backend.
"""
module UnitHandler

using Base: @kwdef
using DocStringExtensions: TYPEDEF, TYPEDFIELDS, TYPEDSIGNATURES

export Unit, Units, units, QuantityTag, quantity
export METRIC_PREFIX_EXPONENT, METRIC_PREFIX_SYMBOL, UNIT_SYMBOL
export get_label, get_symbol, get_exp, default_unit, display_unit, scale_factor
export nominal, standard_uncertainty, format_value

"Metric-prefix exponents used when scaling physical quantities."
const METRIC_PREFIX_EXPONENT = Dict(
    :yocto => -24, :zepto => -21, :atto => -18, :femto => -15,
    :pico => -12, :nano => -9, :micro => -6, :milli => -3,
    :centi => -2, :deci => -1, :base => 0, :deca => 1,
    :hecto => 2, :kilo => 3, :mega => 6, :giga => 9,
    :tera => 12, :peta => 15, :exa => 18, :zetta => 21, :yotta => 24
)

"Display symbols for the supported metric prefixes."
const METRIC_PREFIX_SYMBOL = Dict(
    :yocto => "y", :zepto => "z", :atto => "a", :femto => "f",
    :pico => "p", :nano => "n", :micro => "μ", :milli => "m",
    :centi => "c", :deci => "d", :base => "", :deca => "da",
    :hecto => "h", :kilo => "k", :mega => "M", :giga => "G",
    :tera => "T", :peta => "P", :exa => "E", :zetta => "Z", :yotta => "Y"
)

"Display symbols for the supported unit names."
const UNIT_SYMBOL = Dict(
    :ohm => "Ω", :db_ohm => "dBΩ", :henry => "H", :farad => "F",
    :siemens => "S", :meter => "m", :hertz => "Hz", :radian => "rad",
    :second => "s", :degree => "°", :dimensionless => ""
)

@inline function _prefix_exp(prefix::Symbol)
    return get(METRIC_PREFIX_EXPONENT, prefix) do
        throw(ArgumentError("unsupported metric prefix :$prefix"))
    end
end

@inline function _prefix_symbol(prefix::Symbol)
    return get(METRIC_PREFIX_SYMBOL, prefix) do
        throw(ArgumentError("unsupported metric prefix :$prefix"))
    end
end

"""
$(TYPEDEF)

Represent one physical unit and its metric prefix.

$(TYPEDFIELDS)
"""
@kwdef struct Unit
    "Unit name, such as `:ohm`, `:hertz`, or `:db_ohm`."
    name::Symbol = :dimensionless
    "Metric prefix, such as `:base`, `:milli`, or `:kilo`."
    prefix::Symbol = :base

    @doc """
        Unit(name=:dimensionless, prefix=:base)

    Construct a physical unit after validating its metric prefix.
    """ function Unit(name::Symbol, prefix::Symbol)
        _prefix_exp(prefix)
        new(name, prefix)
    end
end

"""
$(TYPEDEF)

Represent a composite physical unit. Numerator and denominator factors are
stored separately.

$(TYPEDFIELDS)
"""
@kwdef struct Units
    "Numerator units."
    base::Vector{Unit} = [Unit()]
    "Denominator units."
    per::Vector{Unit} = Unit[]
end

"""
$(TYPEDSIGNATURES)

Construct a simple unit with an optional denominator. For example,
`units(:base, :ohm; per=(:kilo, :meter))` represents Ω/km.
"""
function units(
        prefix::Symbol,
        name::Symbol;
        per::Union{Nothing, Tuple{Symbol, Symbol}} = nothing
)
    numerator = Unit(name = name, prefix = prefix)
    per === nothing && return Units(base = [numerator], per = Unit[])
    denominator = Unit(name = last(per), prefix = first(per))
    return Units(base = [numerator], per = [denominator])
end

"""$(TYPEDSIGNATURES)

Return the display label for one unit.
"""
function get_label(unit::Unit)
    return string(_prefix_symbol(unit.prefix), get(UNIT_SYMBOL, unit.name, String(unit.name)))
end

"""$(TYPEDSIGNATURES)

Return the display label for a composite unit.
"""
function get_label(unit::Units)
    numerator = filter(item -> item.name != :dimensionless, unit.base)
    denominator = filter(item -> item.name != :dimensionless, unit.per)
    num_label = join(get_label.(numerator), ".")
    isempty(denominator) && return num_label
    isempty(num_label) && (num_label = "1")
    den_labels = get_label.(denominator)
    den_label = length(den_labels) == 1 ? only(den_labels) :
                "(" * join(den_labels, ".") * ")"
    return "$num_label/$den_label"
end

"""
$(TYPEDEF)

Identify the physical meaning of plotted or reported numeric values.
"""
struct QuantityTag{Q} end

QuantityTag(::Val{Q}) where {Q} = QuantityTag{Q}()
QuantityTag(::Type{QuantityTag{Q}}) where {Q} = QuantityTag{Q}()

"""$(TYPEDSIGNATURES)

Construct the quantity tag named by `name`.
"""
quantity(name::Symbol) = QuantityTag(Val(name))

"""$(TYPEDSIGNATURES)

Return the native unit of a physical quantity.
"""
default_unit(::QuantityTag) = Units()

"""$(TYPEDSIGNATURES)

Return the preferred display unit of a physical quantity.
"""
display_unit(quantity::QuantityTag) = default_unit(quantity)

"""$(TYPEDSIGNATURES)

Return a human-readable quantity label without units.
"""
get_label(::QuantityTag{Q}) where {Q} = String(Q)

"""$(TYPEDSIGNATURES)

Return the conventional symbol for a physical quantity.
"""
get_symbol(::QuantityTag{Q}) where {Q} = String(Q)

default_unit(::Val{Q}) where {Q} = default_unit(QuantityTag{Q}())
display_unit(::Val{Q}) where {Q} = display_unit(QuantityTag{Q}())
get_label(::Val{Q}) where {Q} = get_label(QuantityTag{Q}())
get_symbol(::Val{Q}) where {Q} = get_symbol(QuantityTag{Q}())
default_unit(name::Symbol) = default_unit(Val(name))
display_unit(name::Symbol) = display_unit(Val(name))
get_label(name::Symbol) = get_label(Val(name))
get_symbol(name::Symbol) = get_symbol(Val(name))

"""$(TYPEDSIGNATURES)

Return the net base-10 prefix exponent of a composite unit.
"""
function get_exp(unit::Units)::Int
    numerator = sum(item -> _prefix_exp(item.prefix), unit.base; init = 0)
    denominator = sum(item -> _prefix_exp(item.prefix), unit.per; init = 0)
    return numerator - denominator
end

"""$(TYPEDSIGNATURES)

Return the factor that converts values from `source` units to `target` units.
"""
scale_factor(source::Units, target::Units) = 10.0^(get_exp(source) - get_exp(target))

"""$(TYPEDSIGNATURES)

Return the factor that converts a quantity from its native unit to `target`.
"""
function scale_factor(quantity::QuantityTag, target::Units)
    scale_factor(default_unit(quantity), target)
end

"""$(TYPEDSIGNATURES)

Return the factor that converts unprefixed values into `target` units.
"""
scale_factor(target::Units) = 10.0^(-get_exp(target))

default_unit(::QuantityTag{:frequency}) = units(:base, :hertz)
display_unit(::QuantityTag{:frequency}) = units(:base, :hertz)
get_label(::QuantityTag{:frequency}) = "Frequency"
get_symbol(::QuantityTag{:frequency}) = "f"

function default_unit(::QuantityTag{:angular_frequency})
    units(:base, :radian; per = (:base, :second))
end
function display_unit(::QuantityTag{:angular_frequency})
    default_unit(QuantityTag{:angular_frequency}())
end
get_label(::QuantityTag{:angular_frequency}) = "Angular frequency"
get_symbol(::QuantityTag{:angular_frequency}) = "ω"

default_unit(::QuantityTag{:impedance}) = units(:base, :ohm)
display_unit(::QuantityTag{:impedance}) = units(:base, :ohm)
get_label(::QuantityTag{:impedance}) = "Impedance"
get_symbol(::QuantityTag{:impedance}) = "Z"

default_unit(::QuantityTag{:impedance_db}) = units(:base, :db_ohm)
display_unit(::QuantityTag{:impedance_db}) = units(:base, :db_ohm)
get_label(::QuantityTag{:impedance_db}) = "Impedance magnitude"
get_symbol(::QuantityTag{:impedance_db}) = "|Z|"

"""$(TYPEDSIGNATURES)

Return the nominal numeric value. Optional uncertainty extensions specialize
this method for their scalar types.
"""
nominal(value::Number) = value

"""$(TYPEDSIGNATURES)

Return the standard uncertainty of a number. Deterministic numbers return
zero. Optional uncertainty extensions specialize this method.
"""
standard_uncertainty(value::Number) = zero(real(value))

"""$(TYPEDSIGNATURES)

Format a deterministic value or a value with standard uncertainty. Values
with nonzero uncertainty are written as `value ± uncertainty`.
"""
function format_value(value::Number; digits::Integer = 6)
    digits >= 0 || throw(ArgumentError("digits must be nonnegative"))
    center = round(nominal(value); digits)
    uncertainty = abs(round(standard_uncertainty(value); digits))
    iszero(uncertainty) && return string(center)
    return string(center, " ± ", uncertainty)
end

end
