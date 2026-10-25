#=
Shared inner-voltage-loop slot for modular converters.

The modular TLC implementation provides a pass-through voltage loop. Concrete
voltage-loop implementations extend the shared interface.
=#

export AbstractInnerVoltage,
       NoInnerVoltageControl, 
       CCVI

"""
$(TYPEDEF)

Abstract supertype for modular-converter inner-voltage controllers.
"""
abstract type AbstractInnerVoltage <: AbstractStateSpace end

"""
$(TYPEDEF)

Pass-through inner-voltage controller.

Forwards active and reactive current references to the inner-current loop.

$(TYPEDFIELDS)
"""
struct NoInnerVoltageControl <: AbstractInnerVoltage end

statenames(::NoInnerVoltageControl) = ()

function state_space!(F, x, inputs, block::NoInnerVoltageControl, conv::AbstractConverter)
    (; pact, qact) = inputs
    return (; iΔ_d_ref = pact.iΔ_d_ref, iΔ_q_ref = qact.q_ctrl_ref)
end


"""
$(TYPEDEF)

Define an inner-voltage block that maps voltage errors through a virtual impedance.
"""
abstract type AbstractVirtualImpedance          <: AbstractInnerVoltage end

"""
$(TYPEDEF)

Generate d/q current references from voltage errors through a virtual series RL
impedance. Optional filters act independently on the measured d/q voltages.

$(TYPEDFIELDS)
"""
struct CCVI{F<:AbstractMeasurementFilter} <: AbstractVirtualImpedance
    "Virtual resistance on the converter base \\[dimensionless\\]."
    R_v::Float64     # Virtual Resistance [pu]
    "Virtual inductance on the converter base \\[dimensionless\\]."
    L_v::Float64     # Virtual inductance [pu]
    "d-axis voltage reference on the converter base \\[dimensionless\\]."
    V_d_ref::Float64 # Vd voltage reference [pu]
    "q-axis voltage reference on the converter base \\[dimensionless\\]."
    V_q_ref::Float64 # Vq voltage reference [pu]
    "Measurement filter with a scalar state-space realization."
    filter::F
end

"""
$(TYPEDSIGNATURES)

Construct a `CCVI` component from the supplied parameters.

# Arguments

- `R_v`: Virtual resistance on the converter base \\[dimensionless\\]. Default: `0.01`.
- `L_v`: Virtual inductance on the converter base \\[dimensionless\\]. Default: `0.25`.
- `V_d_ref`: d-axis voltage reference on the converter base \\[dimensionless\\]. Default:
  `1`.
- `V_q_ref`: q-axis voltage reference on the converter base \\[dimensionless\\]. Default:
  `0`.
- `filter`: Measurement filter with a scalar state-space realization. Default:
  `NoFilter()`.

# Returns

- A `CCVI` instance.

# Examples

```julia
using PowerImpedance
component = CCVI()
```
"""
function CCVI(;
    R_v::Real = 0.01,
    L_v::Real = 0.25,
    V_d_ref::Real = 1,
    V_q_ref::Real = 0,
    filter::AbstractMeasurementFilter = NoFilter(),
)
    filter = measurement_filter_ss(filter)
    return CCVI{typeof(filter)}(Float64(R_v), Float64(L_v), Float64(V_d_ref), Float64(V_q_ref), filter)
end

function statenames(b::CCVI)
    return (filter_statenames(:vG_d_vi_f, b.filter)..., filter_statenames(:vG_q_vi_f, b.filter)...)
end

function initialvalues(b::CCVI; inputs, conv=nothing)
    ratio = voltage_filter_ratio(conv)
    vG_d0 = inputs.vG_d * ratio
    vG_q0 = inputs.vG_q * ratio
    dnames = filter_statenames(:vG_d_vi_f, b.filter)
    qnames = filter_statenames(:vG_q_vi_f, b.filter)
    return (; filter_initialvalues(b.filter, dnames, vG_d0)..., filter_initialvalues(b.filter, qnames, vG_q0)...)
end

"""
$(TYPEDSIGNATURES)

Evaluate virtual-impedance voltage control, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `b`: The `CCVI` parameters.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- `iΔ_d_ref`: Current reference \\[dimensionless\\].
- `iΔ_q_ref`: Current reference \\[dimensionless\\].

# Notes

```math
\\Delta v_d=V_d^{ref}+v_{outer}-v_d,\\quad \\Delta v_q=V_q^{ref}-v_q,\\quad i_d^{ref}=\\frac{R_v\\Delta v_d-\\omega L_v\\Delta v_q}{R_v^2+(\\omega L_v)^2},\\quad i_q^{ref}=\\frac{R_v\\Delta v_q+\\omega L_v\\Delta v_d}{R_v^2+(\\omega L_v)^2}.
```

The measured voltages are locally filtered. Voltage, current, impedance, and angular
frequency are on converter bases \\[dimensionless\\]. The denominator is used directly,
including when it is zero.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = CCVI()
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, sync=sync, out_reactive=(q_ctrl_ref=0.0,))
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, b::CCVI, conv::AbstractConverter)
    (; meas, sync, out_reactive) = inputs
    (;R_v, L_v, V_d_ref, V_q_ref) = b
    ω_c = sync.ω_c
    vgfm_d_ref = out_reactive.q_ctrl_ref
    vG_d_f, i = filter_step!(F, 1, x, b.filter, filter_statenames(:vG_d_vi_f, b.filter), meas.vG_d_f)
    vG_q_f, _ = filter_step!(F, i, x, b.filter, filter_statenames(:vG_q_vi_f, b.filter), meas.vG_q_f)

    den = (R_v^2 + ω_c^2*L_v^2)
    return (iΔ_d_ref=(R_v * (V_d_ref+vgfm_d_ref-vG_d_f) + ω_c * L_v * (vG_q_f-V_q_ref)) /den,
            iΔ_q_ref=(R_v * (V_q_ref-vG_q_f) + ω_c * L_v * (-vG_d_f+V_d_ref+vgfm_d_ref)) /den)

end
