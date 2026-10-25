export ac_source

"""
$(TYPEDSIGNATURES)

Construct an ideal three-phase AC voltage-source model with physical operating targets.

# Arguments

- `v`: Phase-peak voltage \\[kV\\]. Default: `220 / sqrt(3)`.
- `theta`: Voltage angle \\[rad\\]. Default: `0.0`.
- `p`: Active power \\[MW\\]. Default: `0.0`.
- `q`: Reactive power \\[MVAr\\]. Default: `0.0`.

# Returns

- An immutable `Source` with three conductors, an `ACABC` port and an ideal ABCD matrix.

# Notes

Set source limits with `component(source; limits = Limits(...))`.

# Examples

```julia
source = ac_source(v = 220 / sqrt(3), p = 100.0, q = 0.0)
limited = component(source; limits = PowerImpedance.Limits(P_max = 200.0))
```
"""
function ac_source(; v = _AC_SOURCE_INPUTS.v.default,
        theta = _AC_SOURCE_INPUTS.theta.default, p = _AC_SOURCE_INPUTS.p.default,
        q = _AC_SOURCE_INPUTS.q.default)
    return Source(; v, theta, p, q, conductors = 3, domain = ACABC)
end
