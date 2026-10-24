############################  common/loops/synchronization.jl  ############################

#=
Shared synchronization blocks for converter control models.

Synchronization blocks provide the control-frame angle and frequency deviation
used by downstream outer and inner loops. The current implementations cover a
no-synchronization pass-through and a filtered PLL.
=#

export AbstractSynchronization,
       NoSynchronization,
       PLLSynchronization,
       VSEWithDamping

"""
$(TYPEDEF)

Abstract supertype for modular-converter synchronization blocks.
"""
abstract type AbstractSynchronization <: AbstractStateSpace end

"""
$(TYPEDEF)

Synchronization block with zero angle offset from the nominal grid dq frame and
unit normalized angular frequency.

$(TYPEDFIELDS)
"""
struct NoSynchronization <: AbstractSynchronization end

statenames(::NoSynchronization) = ()

syncangle(::NoSynchronization, x) = 0.0

state_space!(F, x, meas, setpoint_pu::SetpointPU, block::NoSynchronization, conv::AbstractConverter) = (ω_c = 1.0,)

"""
$(TYPEDEF)

Phase-locked-loop synchronization block.

$(TYPEDFIELDS)
"""
struct PLLSynchronization{Filter<:AbstractMeasurementFilter} <: AbstractSynchronization
    "PI gains for normalized signals; proportional gain is \\[dimensionless\\] and integral gain is \\[s⁻¹\\]."
    pi_ctrl::PIControl
    "Measurement filter with a scalar state-space realization."
    filter::Filter
end

"""
$(TYPEDSIGNATURES)

Construct a PLL synchronization block.

# Arguments

- `pi_ctrl`: PI gains for normalized signals; proportional gain is \\[dimensionless\\] and
  integral gain is \\[s⁻¹\\]. Default: `PIControl()`.
- `filter`: Measurement filter with a scalar state-space realization. Default:
  `NoFilter()`.

# Returns

- A `PLLSynchronization` instance.

# Notes

The `filter` argument filters the measured q-axis voltage before the PI
controller computes the frequency deviation.

# Examples

```julia
using PowerImpedance
component = PLLSynchronization()
```
"""
function PLLSynchronization(; pi_ctrl::PIControl = PIControl(), filter::AbstractMeasurementFilter = NoFilter())
    filter = measurement_filter_ss(filter)

    return PLLSynchronization{typeof(filter)}(
        pi_ctrl,
        filter,
    )
end

syncangle(::PLLSynchronization, x) = x.Δθ_pll

function statenames(block::PLLSynchronization)
    return (
        filter_statenames(:v_q_pll_f, block.filter)...,
        :ξ_pll,
        :Δθ_pll,
    )
end

"""
$(TYPEDSIGNATURES)

Evaluate PLL filter, PI integrator, and angle state equations.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `meas`: Filtered measurement signals on converter bases \\[dimensionless\\]; angle
  signals use \\[rad\\].
- `::SetpointPU`: Operating-point argument accepted for the common interface and unused
  by this PLL method.
- `block`: The `PLLSynchronization` parameters.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- `ω_c`: Normalized synchronization angular frequency \\[dimensionless\\].

# Notes

```math
\\Delta\\omega=-K_p v_{q,f}+\\xi,\\quad \\dot{\\xi}=-K_i v_{q,f},\\quad \\dot{\\theta}=\\omega_b\\Delta\\omega,\\quad \\omega_c=1+\\Delta\\omega.
```

The q voltage is rotated into the PLL frame and filtered before the PI calculation.
``θ`` uses \\[rad\\] and ``ω_b`` \\[rad/s\\]. Other quantities are normalized
\\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
block = PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = meas
outputs = P.state_space!(F, x, signals, point, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, meas, ::SetpointPU, block::PLLSynchronization, conv::AbstractConverter)
    _, vG_q_pll_f = frame_transform(meas.vG_d_f, meas.vG_q_f, (x.Δθ_pll - syncangle(conv.sync, x))) # Ensuring that voltage is in PLL reference frame (it is not the converter reference frame in GFM)
    v_pll, i = filter_step!(F, 1, x, block.filter, filter_statenames(:v_q_pll_f, block.filter), vG_q_pll_f)
    Δω = -block.pi_ctrl.Kp * v_pll + x.ξ_pll

    F[i] = -block.pi_ctrl.Ki * v_pll
    F[i + 1] = conv.elec.ωbase * Δω

    return (ω_c = Δω + 1,)
end


const _VSE_POWER_INPUT =
    Input(0.0; unit = "pu", description = "active-power reference")

"""
$(TYPEDEF)

Synchronize a grid-forming converter with a virtual swing equation, PLL-referenced
damping, and frequency droop.

$(TYPEDFIELDS)
"""
struct VSEWithDamping <: AbstractSynchronization   # VSE = Virtual Swing Equation
    "Inertia constant \\[s\\]."
    H::Float64          # Virtual Inertia [s]
    "Active-power damping gain per normalized frequency difference \\[dimensionless\\]."
    K_d::Float64        # Damping coefficient [-]
    "Active-power droop gain per normalized frequency difference \\[dimensionless\\]."
    K_ω::Float64        # Droop coefficient [-]
    "Angular-frequency reference on the nominal-frequency base \\[dimensionless\\]."
    ω_ref::Float64      # Angular frequency reference [pu]
    "PLL used to estimate grid frequency for the damping term."
    pll::PLLSynchronization # PLL
    "Active-power reference on converter bases \\[dimensionless\\]."
    p_ref::Float64
end

"""
$(TYPEDSIGNATURES)

Construct a `VSEWithDamping` component from the supplied parameters.

# Arguments

- `H`: Inertia constant \\[s\\]. Default: `5`.
- `K_d`: Active-power damping gain per normalized frequency difference
  \\[dimensionless\\]. Default: `100`.
- `K_ω`: Active-power droop gain per normalized frequency difference \\[dimensionless\\].
  Default: `10`.
- `ω_ref`: Angular-frequency reference on the nominal-frequency base \\[dimensionless\\].
  Default: `1`.
- `pll`: PLL used to estimate grid frequency for the damping term.
- `p_ref`: Active-power reference on converter bases \\[dimensionless\\]. Default: `0.0`.

# Returns

- A `VSEWithDamping` instance.

# Examples

```julia
using PowerImpedance
component = VSEWithDamping(pll=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)))
```
"""
function VSEWithDamping(;
    H::Real = 5,
    K_d::Real = 100,
    K_ω::Real = 10,
    ω_ref::Real = 1,
    pll::PLLSynchronization,
    p_ref::Real = _VSE_POWER_INPUT.default,
)
    return VSEWithDamping(
        Float64(H),
        Float64(K_d),
        Float64(K_ω),
        Float64(ω_ref),
        pll,
        Float64(p_ref),
    )
end

function statenames(b::VSEWithDamping)
    return (statenames(b.pll)..., :ω_VSM, :Δθ_VSM)
end

function initialvalues(b::VSEWithDamping; setpoint_pu)
    return (; initialvalues(b.pll)..., ω_VSM=1, Δθ_VSM=setpoint_pu.θ_ac)
end

"""
$(TYPEDSIGNATURES)

Evaluate virtual-swing synchronization with damping, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `meas`: Filtered measurement signals on converter bases \\[dimensionless\\]; angle
  signals use \\[rad\\].
- `setpoint_pu`: Operating point on the component bases \\[dimensionless\\]; its voltage
  angle uses \\[rad\\].
- `b`: The `VSEWithDamping` parameters.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- `ω_c`: Normalized synchronization angular frequency \\[dimensionless\\].
- `P_ac_f`: Filtered AC active power \\[dimensionless\\].

# Notes

```math
2H\\dot{\\omega}=p_{ref}-p_f-K_d(\\omega-\\omega_{PLL})-K_\\omega(\\omega-\\omega_{ref}),\\quad \\dot{\\theta}=\\omega_b(\\omega-1).
```

Power and angular frequencies are normalized \\[dimensionless\\]; inertia ``H`` uses \\[s\\]
and ``θ`` \\[rad\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
block = VSEWithDamping(pll=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
x = merge(x, (ω_VSM=1.0,))
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = meas
outputs = P.state_space!(F, x, signals, point, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, meas, setpoint_pu::SetpointPU, b::VSEWithDamping, conv::AbstractConverter)
    out_pll, i = state_space_block!(F, x, meas, setpoint_pu, b.pll, conv, 1)

    ω_PLL = out_pll.ω_c

    P_ac_f = meas.P_ac_f

    ω_VSM = x.ω_VSM
    
    # dω_VSM / dt = ...
    F[i] = (setpoint_pu.p_ac - P_ac_f - b.K_d * (ω_VSM-ω_PLL) - b.K_ω * (ω_VSM-b.ω_ref)) / (2*b.H) 

    # dΔθ_VSM/dt
    F[i+1] = conv.elec.ωbase * (ω_VSM-1)
    
    return (; ω_c = ω_VSM, P_ac_f = P_ac_f)
end

syncangle(::VSEWithDamping, x) = x.Δθ_VSM

inputs(block::VSEWithDamping) = (
    p_ref = _VSE_POWER_INPUT, pll = inputs(block.pll),
)
_powerflow_references(block::VSEWithDamping) = (p_ac = block.p_ref,)
