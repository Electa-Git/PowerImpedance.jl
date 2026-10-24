#=
Shared inner-current control blocks for modular converters.

The inner-current layer converts current references into modulation commands for
converter models that dispatch through the TLC control interface. The file lives
under `common/loops` so the same API can be reused by other converter
implementations as they adopt the modular loop structure.
=#

export AbstractInnerCurrentControl,
       NoInnerCurrentControl,
       InnerCurrentPIControl

"""
$(TYPEDEF)

Abstract supertype for modular-converter inner-current controllers.
"""
abstract type AbstractInnerCurrentControl <: AbstractStateSpace end

"""
$(TYPEDEF)

No inner-current control.

$(TYPEDFIELDS)
"""
struct NoInnerCurrentControl <: AbstractInnerCurrentControl end

statenames(::NoInnerCurrentControl) = ()

state_space!(F, x, inputs, block::NoInnerCurrentControl, conv::AbstractConverter) =
    (; vMΔ_d_ref_c = 0.0, vMΔ_q_ref_c = 0.0)

"""
$(TYPEDEF)

PI inner-current controller supplying voltage references to modular TLC and MMC
modulation blocks.

$(TYPEDFIELDS)
"""
struct InnerCurrentPIControl{F<:AbstractMeasurementFilter} <: AbstractInnerCurrentControl
    "PI gains for normalized signals; proportional gain is \\[dimensionless\\] and integral gain is \\[s⁻¹\\]."
    pi_ctrl::PIControl
    "Measurement filter with a scalar state-space realization."
    filter::F
    "Whether inductive decoupling uses the synchronization frequency instead of nominal frequency."
    activate_ω_c_multiplication::Bool
end

"""
$(TYPEDSIGNATURES)

Construct a `InnerCurrentPIControl` component from the supplied parameters.

# Arguments

- `pi_ctrl`: PI gains for normalized signals; proportional gain is \\[dimensionless\\] and
  integral gain is \\[s⁻¹\\]. Default: `PIControl()`.
- `filter`: Measurement filter with a scalar state-space realization. Default:
  `NoFilter()`.
- `activate_ω_c_multiplication`: Whether inductive decoupling uses the synchronization
  frequency instead of nominal frequency. Default: `true`.

# Returns

- An `InnerCurrentPIControl` instance.

# Notes

The PI parameter container is also accepted as the first positional argument.

# Examples

```julia
using PowerImpedance
component = InnerCurrentPIControl()
```
"""
function InnerCurrentPIControl(;
    pi_ctrl::PIControl = PIControl(),
    filter::AbstractMeasurementFilter = NoFilter(),
    activate_ω_c_multiplication::Bool = true
)
    filter = measurement_filter_ss(filter)
    return InnerCurrentPIControl{typeof(filter)}(pi_ctrl, filter, activate_ω_c_multiplication)
end

InnerCurrentPIControl(pi_ctrl::PIControl) = InnerCurrentPIControl(pi_ctrl = pi_ctrl)

function statenames(block::InnerCurrentPIControl)
    return (filter_statenames(:vG_d_occ_f, block.filter)..., filter_statenames(:vG_q_occ_f, block.filter)..., :ξ_id, :ξ_iq)
end

function initialvalues(block::InnerCurrentPIControl; inputs, conv::AbstractConverter)
    ratio = voltage_filter_ratio(conv)
    vG_d0 = inputs.vG_d * ratio
    vG_q0 = inputs.vG_q * ratio
    dnames = filter_statenames(:vG_d_occ_f, block.filter)
    qnames = filter_statenames(:vG_q_occ_f, block.filter)

    return (;
        filter_initialvalues(block.filter, dnames, vG_d0)...,
        filter_initialvalues(block.filter, qnames, vG_q0)...,
        ξ_id = 0,
        ξ_iq = 0,
    )
end

"""
$(TYPEDSIGNATURES)

Evaluate modular-converter inner-current PI control in the synchronization frame.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `block`: The `InnerCurrentPIControl` parameters.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- `vMΔ_d_ref_c`: Synchronization-frame d-axis voltage reference \\[dimensionless\\].
- `vMΔ_q_ref_c`: Synchronization-frame q-axis voltage reference \\[dimensionless\\].

# Notes

```math
\\dot{\\xi}_{d,q}=K_i(i_{d,q}^{ref}-i_{d,q}),\\quad v_d^{ref}=\\xi_d+K_p e_d+L\\omega i_q+v_d,\\quad v_q^{ref}=\\xi_q+K_p e_q-L\\omega i_d+v_q.
```

All electrical quantities are normalized \\[dimensionless\\]. The optional frequency
factor uses synchronization frequency or unity. Local voltage filters supply the
feedforward terms.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = InnerCurrentPIControl(pi_ctrl=PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, sync=sync, vloop=(iΔ_d_ref=0.1, iΔ_q_ref=0.0))
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, block::InnerCurrentPIControl, conv::AbstractConverter)
    (; meas, sync, vloop) = inputs
    i_d_ref = vloop.iΔ_d_ref
    i_q_ref = vloop.iΔ_q_ref

    i_d = meas.i_d_f
    i_q = meas.i_q_f
    v_d, i = filter_step!(F, 1, x, block.filter, filter_statenames(:vG_d_occ_f, block.filter), meas.vG_d_f)
    v_q, i = filter_step!(F, i, x, block.filter, filter_statenames(:vG_q_occ_f, block.filter), meas.vG_q_f)

    Lᵣ = elec_inductance(conv.elec)

    e_d = i_d_ref - i_d
    e_q = i_q_ref - i_q
    F[i] = block.pi_ctrl.Ki * e_d
    F[i + 1] = block.pi_ctrl.Ki * e_q

    multiplication_factor = block.activate_ω_c_multiplication ? sync.ω_c : 1

    vMΔ_d_ref_c = x.ξ_id + block.pi_ctrl.Kp * e_d + Lᵣ * multiplication_factor * i_q + v_d
    vMΔ_q_ref_c = x.ξ_iq + block.pi_ctrl.Kp * e_q - Lᵣ * multiplication_factor * i_d + v_q

    return (; vMΔ_d_ref_c, vMΔ_q_ref_c)
end
