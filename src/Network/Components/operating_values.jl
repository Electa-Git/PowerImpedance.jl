export ACPortValues, DCPortValues

"""
$(TYPEDEF)

Store physical terminal values at an AC port. Power flowing into the component is
positive, as for the current in `Y = I_in / V`. A source or synchronous machine
delivering 900 MW has `p = -900`. An induction motor drawing 916 MW has `p = 916`.
A converter delivering 600 MW to AC has `p = -600`. Reactive power follows the same rule.
Real arguments are converted to `Float64`. Use `NaN` for unknown reactive power.

$(TYPEDFIELDS)

# Examples

```julia
ACPortValues(380sqrt(2/3), 0.0, 100.0, 0.0)
```
"""
struct ACPortValues
    "Phase-peak voltage \\[kV\\]."
    v::Float64
    "Voltage angle \\[rad\\]."
    theta::Float64
    "Active power flowing into the component \\[MW\\]."
    p::Float64
    "Reactive power flowing into the component \\[MVAr\\], or `NaN` when unknown."
    q::Float64
end

"""
$(TYPEDEF)

Store physical terminal values at a DC port. Power flowing into the component is
positive, as for the current in `Y = I_in / V`. A source delivering 900 MW has
`p = -900`. A converter taking 603 MW from DC has `p = 603`.
Real arguments are converted to `Float64`.

$(TYPEDFIELDS)

# Examples

```julia
DCPortValues(640.0, 100.0)
```
"""
struct DCPortValues
    "Pole-to-pole voltage \\[kV\\]."
    v::Float64
    "Active power flowing into the component \\[MW\\]."
    p::Float64
end

"""
$(TYPEDSIGNATURES)

Return the AC peak-current magnitude from terminal power and voltage.
Port powers are positive into the component. The magnitude is unsigned.
A source delivering 900 MW has `p = -900`. A motor drawing 916 MW has `p = 916`.

# Arguments

- `values`: AC port values in \\[kV\\], \\[rad\\], \\[MW\\] and \\[MVAr\\].

# Returns

- Peak-current magnitude \\[kA\\]. Unknown reactive power gives `NaN`.

# Notes

```math
I = \\frac{2\\sqrt{p^2 + q^2}}{3v}.
```
"""
current(values::ACPortValues) = 2hypot(values.p, values.q) / (3values.v)

"""
$(TYPEDSIGNATURES)

Return the DC current from terminal power and voltage, positive into the component.
A converter taking 603 MW from DC has `p = 603` and positive current.

# Arguments

- `values`: DC port voltage \\[kV\\] and power flowing into the component \\[MW\\].

# Returns

- Current flowing into the component \\[kA\\].

# Notes

```math
I = \\frac{p}{v}.
```
"""
current(values::DCPortValues) = values.p / values.v

"""
$(TYPEDEF)

Store an internal AC/DC operating point normalized by the component bases
\\[dimensionless\\]. Angles remain in \\[rad\\].

$(TYPEDFIELDS)
"""
@with_kw struct TerminalValuesPU # Per-unitized terminal values used internally
    "AC active power on the component base \\[dimensionless\\]."
    p_ac::Float64 = 0
    "AC reactive power on the component base \\[dimensionless\\]."
    q_ac::Float64 = 0
    "AC voltage angle \\[rad\\]."
    θ_ac::Float64 = 0
    "AC phase-voltage amplitude on the component base \\[dimensionless\\]."
    v_ac::Float64 = 1

    "DC active power on the component base \\[dimensionless\\]."
    p_dc::Float64 = 0
    "Pole-to-pole DC voltage on the component base \\[dimensionless\\]."
    v_dc::Float64 = 1
end

"""
$(TYPEDEF)

Retain the terminal values, converged state and matrices of the last linearization.
Fields default to `nothing`.

$(TYPEDFIELDS)
"""
@with_kw mutable struct LinearizationCache
    "Last terminal values, keyed by port name, in physical units."
    values::Union{Nothing, NamedTuple} = nothing
    "Converged state vector in the model's state coordinates."
    state::Union{Nothing, Vector{Float64}} = nothing
    "State matrix in the model's state coordinates."
    A::Union{Nothing, Matrix{Float64}} = nothing
    "Electrical-input matrix in the model's input and state coordinates."
    B::Union{Nothing, Matrix{Float64}} = nothing
    "Output matrix in the model's state and output coordinates."
    C::Union{Nothing, Matrix{Float64}} = nothing
    "Electrical feedthrough matrix in the model's input and output coordinates."
    D::Union{Nothing, Matrix{Float64}} = nothing
end
