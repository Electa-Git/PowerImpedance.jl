export BaseValues, bases, limits

"""
$(TYPEDEF)

Store power, voltage and angular-frequency bases of a component.

$(TYPEDFIELDS)
"""
@with_kw struct BaseValues
    "Three-phase apparent-power base \\[MVA\\]."
    S::Float64
    "AC phase-peak voltage base \\[kV\\]."
    v_ac::Float64
    "DC pole-to-pole voltage base \\[kV\\], or `nothing` for an AC-only model."
    v_dc::Union{Float64, Nothing} = nothing
    "Electrical angular-frequency base \\[rad/s\\]."
    omega::Float64
end

"""
$(TYPEDSIGNATURES)

Return the AC peak-current base.

# Arguments

- `b`: Component base values.

# Returns

- AC peak-current base \\[kA\\].

# Notes

```math
I_{ac,b} = \\frac{2 S_b}{3 V_{ac,b}}.
```
"""
i_ac(b::BaseValues) = 2b.S / (3b.v_ac)

"""
$(TYPEDSIGNATURES)

Return the DC current base for a model with a DC voltage base.

# Arguments

- `b`: Component base values with `v_dc` supplied.

# Returns

- DC current base \\[kA\\].

# Notes

```math
I_{dc,b} = S_b / V_{dc,b}.
```
"""
i_dc(b::BaseValues) = b.S / b.v_dc

"""
$(TYPEDSIGNATURES)

Return the AC impedance base.

# Arguments

- `b`: Component base values.

# Returns

- AC impedance base \\[Ω\\].

# Notes

```math
Z_{ac,b} = \\frac{3 V_{ac,b}^2}{2 S_b}.
```
"""
z_ac(b::BaseValues) = 3b.v_ac^2 / (2b.S)

"""
$(TYPEDSIGNATURES)

Return a component's power, voltage and angular-frequency bases.

# Arguments

- `model`: Component model.

# Returns

- `BaseValues` for MMC, TLC and machine models, or `nothing` for passives, sources
  and the black-box MMC.
  Machine line-to-line RMS voltage bases are multiplied by `sqrt(2/3)` to give
  phase-peak voltage \\[kV\\].
"""
function bases end

"""
$(TYPEDSIGNATURES)

Return the component's stored operating limits.

# Arguments

- `model`: Component model.

# Returns

- Stored `Limits`. MMC power limits use converter bases \\[dimensionless\\]. TLC,
  black-box MMC, synchronous-machine and source limits use \\[MW\\] and \\[MVAr\\].
  These conventions match the existing model calculations. Models without stored
  limits, including passives and induction machines, return `nothing`.
"""
limits(::Any) = nothing
