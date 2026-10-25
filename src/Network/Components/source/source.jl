const _AC_SOURCE_INPUTS = (
    v = Input(220 / sqrt(3); unit = "kV",
        description = "source voltage magnitude, AC phase peak"),
    theta = Input(0.0; unit = "rad", description = "source AC voltage angle"),
    p = Input(0.0; unit = "MW", description = "source AC active power"),
    q = Input(0.0; unit = "MVAr", description = "source reactive power"),
)
const _DC_SOURCE_INPUTS = (
    v = Input(240.0; unit = "kV", description = "source DC pole-to-pole voltage"),
    p = Input(0.0; unit = "MW", description = "source DC active power"),
)

"""
$(TYPEDEF)

Store an ideal voltage source with physical operating targets and its ideal ABCD matrix.

$(TYPEDFIELDS)
"""
@with_kw struct Source <: AbstractLinFreqDomain
    "Number of physical conductors supplied to the source constructor."
    conductors::Int = 3
    "Electrical coordinate domain selected by the source constructor."
    domain::AbstractDomain = ACABC
    "Voltage magnitude \\[kV\\], AC phase peak or DC pole to pole."
    v::Float64 = domain === ACABC ? _AC_SOURCE_INPUTS.v.default :
        _DC_SOURCE_INPUTS.v.default
    "AC voltage angle \\[rad\\]."
    theta::Float64 = _AC_SOURCE_INPUTS.theta.default
    "Active power \\[MW\\]."
    p::Float64 = domain === ACABC ? _AC_SOURCE_INPUTS.p.default :
        _DC_SOURCE_INPUTS.p.default
    "Reactive power \\[MVAr\\]."
    q::Float64 = _AC_SOURCE_INPUTS.q.default
    "Operating limits in \\[MW\\] and \\[MVAr\\]."
    limits::Limits = Limits()
    "Ideal ABCD matrix; A/D are \\[dimensionless\\], B is \\[Ω\\], and C is \\[S\\]."
    ABCD::Matrix{ComplexF64} = _source_abcd(conductors)
end

"""
$(TYPEDSIGNATURES)

Compute the ideal-source ABCD matrix for the requested conductor count.

# Arguments

- `p`: Number of physical conductors.

# Returns

- Block matrix `[A B; C D]`: A/D are identity \\[dimensionless\\], B is zero
  series impedance \\[Ω\\], and C is zero shunt admittance \\[S\\].

# Notes

```math
A=D=I_p,\\qquad B=C=0.
```

The source constructor stores the complete matrix.

# Examples

```julia
using PowerImpedance
PowerImpedance._source_abcd(3)
```
"""
function _source_abcd(p)
    A = Matrix{ComplexF64}(I, p, p)
    B = zeros(ComplexF64, p, p)
    C = zeros(ComplexF64, p, p)
    D = Matrix{ComplexF64}(I, p, p)

    return [A B; C D]
end

function eval_abcd(source::Source, s::Complex)
    return source.ABCD
end

"""
$(TYPEDSIGNATURES)

Evaluate the component terminal admittance at complex frequency `s`.

# Arguments

- `source`: Ideal-source parameters and cached ABCD matrix.
- `s`: Complex Laplace frequency \\[s⁻¹\\]; sinusoidal evaluation uses `s = 2π * im * f`
  for frequency `f` \\[Hz\\].

# Returns

- Complex terminal admittance matrix \\[S\\].

# Notes

The source is regularized for admittance conversion by replacing its series B block with
a diagonal \\[Ω\\] value of `1e-6`; the cached ideal ABCD matrix remains unchanged.
The frequency argument is unused by this ideal-source model.

# Examples

```julia
using PowerImpedance
model = ac_source()
PowerImpedance.eval_y(model, 2π*im*50)
```
"""
function eval_y(source::Source, s::Complex)
    abcd = eval_abcd(source, s)
    p = source.conductors

	abcd = copy(abcd)
	abcd[1:p, (p+1):end] .= 1e-6 .* Matrix{ComplexF64}(I, p, p)

    return abcd_to_y(abcd)
end


electricalconnections(model::Source) = electricalconnections(model, model.domain)
electricalconnections(::Source, ::ACABCDomain) = (ac = Port(ACABC),)
electricalconnections(::Source, ::DCDomain) = (dc = Port(DC_CM),)

is_source(::Source) = true
is_passive(::Source) = false

inputs(model::Source) = inputs(model, model.domain)
inputs(::Source, ::ACABCDomain) = _AC_SOURCE_INPUTS
inputs(::Source, ::DCDomain) = _DC_SOURCE_INPUTS

bases(::Source) = nothing

limits(model::Source) = model.limits


pmtype(model::Source, rows) = is_three_phase(model) ? "gen" : "gendc"

function convert!(data, model::Source, ::Type{PMACDC}, component_key,
        ports::NamedTuple, global_dict)
    key = component_key.index
    point = inputvalues(model)
    lm = limits(model)
    if component_key.pmtype == "gen"
        ac_bus = ports.ac
        key_str = string(key)
        data["gen"][key_str] = Dict{String, Any}()
        gen = data["gen"][key_str]
        gen["mBase"] = global_dict["S"] / 1e6
        gen["gen_bus"] = ac_bus
        gen["pc1"] = 0
        gen["pc2"] = 0
        gen["qc1min"] = 0
        gen["qc1max"] = 0
        gen["qc2min"] = 0
        gen["qc2max"] = 0
        gen["ramp_agc"] = 0
        gen["ramp_q"] = 0
        gen["ramp_10"] = 0
        gen["ramp_30"] = 0
        gen["apf"] = 0
        gen["startup"] = 0
        gen["shutdown"] = 0
        gen["gen_status"] = 1
        gen["source_id"] = Any["gen", key]
        gen["index"] = key

        s_base = global_dict["S"] / 1e6
        v_base = global_dict["V"] / 1e3
        gen["pg"] = point.p / s_base
        gen["qg"] = point.q / s_base
        gen["pmin"] = lm.P_min / s_base
        gen["pmax"] = lm.P_max / s_base
        gen["qmin"] = lm.Q_min / s_base
        gen["qmax"] = lm.Q_max / s_base
        gen["vg"] = point.v / v_base/sqrt(2)
        gen["model"] = 1
        gen["cost"] = 0
        gen["ncost"] = 0
        set_bus = data["bus"][string(ac_bus)]
        gen = data["gen"][string(key)]
        set_bus["vmin"] = 0.9 * gen["vg"]
        set_bus["vmax"] = 1.1 * gen["vg"]
        set_bus["vm"] = gen["vg"]
        data["bus"][string(ac_bus)] = set_bus_type(set_bus, 3)
        return nothing
    end
    dc_bus = ports.dc
    key_str = string(key)
    data["gendc"][key_str] = Dict{String, Any}()
    gendc = data["gendc"][key_str]
    gendc["mBase"] = global_dict["S"] / 1e6
    gendc["gen_bus"] = dc_bus
    gendc["quadratic_cost"] = 0
    gendc["linear_cost"] = 0
    gendc["idle_cost"] = 0
    gendc["control_type"] = 2
    gendc["droop_const"] = 0
    gendc["gen_status"] = 1
    gendc["source_id"] = Any["gen", key]
    gendc["index"] = key

    s_base = global_dict["S"] / 1e6
    v_base = global_dict["V"] / 1e3
    gendc["pgdcset"] = point.p / s_base
    gendc["pmin"] = lm.P_min / s_base
    gendc["pmax"] = lm.P_max / s_base
    gendc["vgdc"] = point.v / (data["dcpol"] * v_base)
    gendc["model"] = 1
    gendc["cost"] = 0
    gendc["ncost"] = 0
    busdc = data["busdc"][string(dc_bus)]
    busdc["Vdc"] = 0.0
    busdc["Vdcmax"] = 1.1 * busdc["Vdc"]
    busdc["Vdcmin"] = 0.9 * busdc["Vdc"]
    data["busdc"][string(dc_bus)] = set_bus_type_dc(busdc, 2)
    return nothing
end


"""
$(TYPEDSIGNATURES)

Return source port powers positive into the source. Delivering 900 MW gives `p = -900`.
Reactive power follows the same rule.
"""
function transform(elemresult, busresult::NamedTuple, global_dict,
        model::Source, ::Type{PMACDC}, ::Type{PIACDC})
    return transform(elemresult, busresult, global_dict, model.domain, PMACDC, PIACDC)
end

function transform(elemresult, busresult, global_dict,
        ::ACABCDomain, ::Type{PMACDC}, ::Type{PIACDC})
    bus = busresult.ac
    p = elemresult["pg"] * global_dict["S"] / 1e6
    q = elemresult["qg"] * global_dict["S"] / 1e6
    v = (bus["vm"] * global_dict["V"] / 1e3) * sqrt(2)
    return (ac = ACPortValues(v, bus["va"], -p, -q),)
end

function transform(elemresult, busresult, global_dict,
        ::DCDomain, ::Type{PMACDC}, ::Type{PIACDC})
    p = elemresult["pgdc"] * global_dict["S"] / 1e6
    v = busresult.dc["vm"] * (dcpol * global_dict["V"] / 1e3)
    return (dc = DCPortValues(v, -p),)
end
