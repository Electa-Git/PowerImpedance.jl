############################  common/loops/outer_reactive.jl  ############################

#=
Shared reactive-power and AC-voltage outer-loop blocks.

These blocks compute the q-axis current reference used by downstream loops.
Optional voltage support is represented as a nested state-space block.
=#

export AbstractOuterReactiveControl,
       AbstractVoltageSupportTLC,
       NoOuterReactiveControl,
       NoVoltageSupport,
       OuterReactiveQControl,
       OuterReactiveVacControl,
       VoltageSupportLag

"""
$(TYPEDEF)

Abstract supertype for reactive-power outer-loop controllers.
"""
abstract type AbstractOuterReactiveControl <: AbstractStateSpace end

"""
$(TYPEDEF)

Abstract supertype for reactive-power support terms.
"""
abstract type AbstractVoltageSupportTLC <: AbstractStateSpace end

"""
$(TYPEDEF)

No reactive-power outer-loop control.

$(TYPEDFIELDS)
"""
struct NoOuterReactiveControl <: AbstractOuterReactiveControl end

statenames(::NoOuterReactiveControl) = ()

state_space!(F, x, inputs, block::NoOuterReactiveControl, conv::AbstractConverter) =
    (; q_ctrl_ref = 0.0)

"""
$(TYPEDEF)

No voltage-support contribution.

$(TYPEDFIELDS)
"""
struct NoVoltageSupport <: AbstractVoltageSupportTLC end

statenames(::NoVoltageSupport) = ()

function state_space!(F, x, meas, terminal_pu::TerminalValuesPU, ::NoVoltageSupport,
        conv::Union{AbstractConverter, Nothing} = nothing)
    (; Q_ac_support = 0.0)
end

const _VOLTAGE_SUPPORT_INPUT =
    Input(1.0; unit = "pu", description = "AC-voltage support reference")

"""
$(TYPEDEF)

Lagged AC-voltage support contribution to reactive-power reference.

$(TYPEDFIELDS)
"""
@with_kw struct VoltageSupportLag <: AbstractVoltageSupportTLC
    "Reactive-power gain per normalized AC-voltage deviation \\[dimensionless\\]."
    K::Float64 = 0.0
    "Support low-pass angular cutoff \\[rad/s\\]."
    ωc::Float64 = 0.0
    "AC-voltage reference on converter bases \\[dimensionless\\]."
    v_ac_ref::Float64 = _VOLTAGE_SUPPORT_INPUT.default
end

statenames(::VoltageSupportLag) = (:ξ_vac_supp,)

"""
$(TYPEDSIGNATURES)

Evaluate the voltage-support lag equation.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `meas`: Filtered measurement signals on converter bases \\[dimensionless\\]; angle
  signals use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]; its voltage
  angle uses \\[rad\\].
- `block`: The `VoltageSupportLag` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization. Default:
  `nothing`.

# Returns

- `Q_ac_support`: Reactive-power support \\[dimensionless\\].

# Notes

```math
v=\\sqrt{v_d^2+v_q^2},\\quad \\dot{\\xi}=\\omega_c[K(v_{ref}-v)-\\xi],\\quad Q_{supp}=\\xi.
```

The reference includes the parent converter voltage-filter ratio. Voltage and power use
converter bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = VoltageSupportLag(K=5.0, ωc=2π*10)
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
function state_space!(F, x, meas, terminal_pu::TerminalValuesPU, block::VoltageSupportLag,
        conv::Union{AbstractConverter, Nothing} = nothing)
    v_ac = sqrt(meas.vG_d_f^2 + meas.vG_q_f^2)
    v_ac_ref = terminal_pu.v_ac * voltage_filter_ratio(conv)
    Δq_unf = block.K * (v_ac_ref - v_ac)
    F[1] = block.ωc * (Δq_unf - x.ξ_vac_supp)
    return (; Q_ac_support = x.ξ_vac_supp)
end

const _OUTER_REACTIVE_Q_INPUT =
    Input(0.0; unit = "pu", description = "reactive-power reference")

"""
$(TYPEDEF)

Reactive-power PI controller with optional voltage support.

$(TYPEDFIELDS)
"""
struct OuterReactiveQControl{S<:AbstractVoltageSupportTLC} <: AbstractOuterReactiveControl
    "PI gains for normalized signals; proportional gain is \\[dimensionless\\] and integral gain is \\[s⁻¹\\]."
    pi_ctrl::PIControl
    "Reactive-power support block driven by AC voltage."
    support::S
    "Reactive-power reference on converter bases \\[dimensionless\\]."
    q_ref::Float64
end

"""
$(TYPEDSIGNATURES)

Construct a reactive-power PI controller.

# Arguments

- `pi_ctrl`: PI gains for normalized signals; proportional gain is \\[dimensionless\\] and
  integral gain is \\[s⁻¹\\]. Default: `PIControl()`.
- `support`: Reactive-power support block driven by AC voltage. Default:
  `NoVoltageSupport()`.
- `q_ref`: Reactive-power reference on converter bases \\[dimensionless\\]. Default: `0.0`.

# Returns

- An `OuterReactiveQControl` instance.

# Examples

```julia
using PowerImpedance
component = OuterReactiveQControl()
```
"""
function OuterReactiveQControl(;
    pi_ctrl::PIControl = PIControl(),
    support::AbstractVoltageSupportTLC = NoVoltageSupport(),
    q_ref::Real = _OUTER_REACTIVE_Q_INPUT.default,
)
    return OuterReactiveQControl{typeof(support)}(pi_ctrl, support, Float64(q_ref))
end

function statenames(block::OuterReactiveQControl)
    return (statenames(block.support)..., :ξ_Q_ac)
end

function initialvalues(block::OuterReactiveQControl; terminal_pu=TerminalValuesPU(),
        conv=nothing)
    return (; initialvalues(block.support)...)
end

"""
$(TYPEDSIGNATURES)

Evaluate reactive-power control and support dynamics.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]; its voltage
  angle uses \\[rad\\].
- `block`: The `OuterReactiveQControl` parameters.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- `q_ctrl_ref`: Control output \\[dimensionless\\].

# Notes

```math
e=q_{ref}+q_{supp}-q_f,\\quad \\dot{\\xi}=K_i e,\\quad i_{q,ref}=K_p e+\\xi.
```

Reactive power and current use converter bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = OuterReactiveQControl(pi_ctrl=PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, sync=sync)
outputs = P.state_space!(F, x, signals, point, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, terminal_pu::TerminalValuesPU,
        block::OuterReactiveQControl, conv::AbstractConverter)
    (; meas) = inputs
    ns = n_states(block.support)
    support = state_space!(@view(F[1:ns]), x, meas, terminal_pu, block.support, conv)
    Q_ac_f = meas.Q_ac_f

    Q_ac_ref_eff = terminal_pu.q_ac + support.Q_ac_support
    F[ns + 1] = block.pi_ctrl.Ki * (Q_ac_ref_eff - Q_ac_f)
    
    return (q_ctrl_ref = block.pi_ctrl.Kp * (Q_ac_ref_eff - Q_ac_f) + x.ξ_Q_ac,)
end

const _OUTER_REACTIVE_VAC_INPUT =
    Input(1.0; unit = "pu", description = "AC-voltage reference")

"""
$(TYPEDEF)

AC-voltage outer-loop PI controller returning the scalar `q_ctrl_ref`.
The TLC pass-through and MMC grid-following assemblies use it as a q-axis current
reference; the MMC grid-forming virtual-impedance block uses it as a d-axis voltage
correction. These signals use their converter bases \\[dimensionless\\].
The filter acts on measured voltage magnitude before calculation of the PI
error. `NoFilter()` preserves the zero-state magnitude measurement.

$(TYPEDFIELDS)
"""
struct OuterReactiveVacControl{F<:AbstractMeasurementFilter} <: AbstractOuterReactiveControl
    "Voltage PI gains in the converter per-unit system."
    pi_ctrl::PIControl
    "Filter for measured voltage magnitude. Cutoff in \\[rad/s\\]."
    filter::F
    "AC-voltage reference on converter bases \\[dimensionless\\]."
    v_ac_ref::Float64
end
"""
$(TYPEDSIGNATURES)

Construct a `OuterReactiveVacControl` component from the supplied parameters.

# Arguments

- `pi_ctrl`: PI gains for normalized signals; `Kp` is \\[dimensionless\\] and `Ki` is
  \\[s⁻¹\\]. Default: `PIControl()`.
- `filter`: Scalar measurement filter specification or realized filter. Default:
  `NoFilter()`.
- `v_ac_ref`: AC-voltage reference on converter bases \\[dimensionless\\]. Default: `1.0`.

# Returns

- An `OuterReactiveVacControl` instance.

# Notes

The PI parameter container is also accepted as the first positional argument.

# Examples

```julia
using PowerImpedance
component = OuterReactiveVacControl()
```
"""
function OuterReactiveVacControl(; pi_ctrl::PIControl = PIControl(),
        filter::AbstractMeasurementFilter = NoFilter(),
        v_ac_ref::Real = _OUTER_REACTIVE_VAC_INPUT.default)
    realized = measurement_filter_ss(filter)
    return OuterReactiveVacControl{typeof(realized)}(pi_ctrl, realized, Float64(v_ac_ref))
end
OuterReactiveVacControl(pi_ctrl::PIControl) = OuterReactiveVacControl(; pi_ctrl)

statenames(block::OuterReactiveVacControl) =
    (filter_statenames(:vac_mag_f, block.filter)..., :ξ_v_ac)

function initialvalues(block::OuterReactiveVacControl; terminal_pu=TerminalValuesPU(),
        conv=nothing)
    block.filter isa NoFilter && return (;)
    return filter_initialvalues(block.filter, filter_statenames(:vac_mag_f, block.filter),
        terminal_pu.v_ac * voltage_filter_ratio(conv))
end

"""
$(TYPEDSIGNATURES)

Evaluate AC-voltage PI control.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]; its voltage
  angle uses \\[rad\\].
- `block`: The `OuterReactiveVacControl` parameters.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- `q_ctrl_ref`: Control output \\[dimensionless\\].

# Notes

```math
e=v_{ref}-\\operatorname{LPF}(\\sqrt{v_d^2+v_q^2}),\\quad \\dot{\\xi}=K_i e,\\quad u_q=K_p e+\\xi.
```

The returned `q_ctrl_ref` is ``u_q``; its interpretation as a current reference or
voltage correction depends on the downstream assembly. Signals use converter bases
\\[dimensionless\\]. The voltage reference includes the parent converter voltage ratio.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = OuterReactiveVacControl(pi_ctrl=PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, sync=sync)
outputs = P.state_space!(F, x, signals, point, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, terminal_pu::TerminalValuesPU,
        block::OuterReactiveVacControl, conv::AbstractConverter)
    (; meas) = inputs
    v_ac = sqrt(meas.vG_d_f^2 + meas.vG_q_f^2)
    v_ac, idx = filter_step!(F, 1, x, block.filter,
        filter_statenames(:vac_mag_f, block.filter), v_ac)
    v_ac_ref = terminal_pu.v_ac * voltage_filter_ratio(conv)

    F[idx] = block.pi_ctrl.Ki * (v_ac_ref - v_ac)
    controller_output = block.pi_ctrl.Kp * (v_ac_ref - v_ac) + x.ξ_v_ac
    return (; q_ctrl_ref = controller_output)
end

function equilibriumequations!(F, x, inputs, terminal_pu::TerminalValuesPU, y,
        conv::AbstractConverter, ::OuterReactiveVacControl)
    idx_ξvac = findfirst(==(:ξ_v_ac), statenames(conv))
    @assert !isnothing(idx_ξvac)
    F[idx_ξvac] = terminal_pu.q_ac - y.meas.Q_ac_f
    return y
end

inputs(block::OuterReactiveQControl) = (
    q_ref = _OUTER_REACTIVE_Q_INPUT, support = inputs(block.support),
)
inputs(::OuterReactiveVacControl) = (v_ac_ref = _OUTER_REACTIVE_VAC_INPUT,)
inputs(::VoltageSupportLag) = (v_ac_ref = _VOLTAGE_SUPPORT_INPUT,)

_powerflow_references(block::OuterReactiveQControl) =
    merge((q_ac = block.q_ref,), _powerflow_references(block.support))
_powerflow_references(block::OuterReactiveVacControl) = (v_ac = block.v_ac_ref,)
_powerflow_references(block::VoltageSupportLag) = (v_ac = block.v_ac_ref,)
