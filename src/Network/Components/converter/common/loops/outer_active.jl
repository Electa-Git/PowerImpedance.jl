# Active-power outer loops

#=
Shared active-power outer-loop blocks.

These blocks compute the d-axis current reference used by downstream voltage or
current loops. Optional active-power support is represented as a nested state-space
block so the outer loop remains composable.
=#

export AbstractOuterActiveControl,
       AbstractFrequencySupport,
       NoOuterActiveControl,
       NoFrequencySupport,
       OuterActivePowerControl,
       FrequencySupportLag,
       DCVoltageSupportLag,
       OuterActiveVdcControl

"""
$(TYPEDEF)

Abstract supertype for active-power outer-loop controllers.
"""
abstract type AbstractOuterActiveControl <: AbstractStateSpace end

"""
$(TYPEDEF)

Abstract supertype for active-power support terms.
"""
abstract type AbstractFrequencySupport <: AbstractStateSpace end

"""
$(TYPEDEF)

No active-power outer-loop control.

$(TYPEDFIELDS)
"""
struct NoOuterActiveControl <: AbstractOuterActiveControl end

statenames(::NoOuterActiveControl) = ()

state_space!(F, x, inputs, block::NoOuterActiveControl, conv::AbstractConverter) =
    (; iΔ_d_ref = 0.0)

"""
$(TYPEDEF)

No frequency-support contribution.

$(TYPEDFIELDS)
"""
struct NoFrequencySupport <: AbstractFrequencySupport end

statenames(::NoFrequencySupport) = ()

state_space!(F, x, sync, ::NoFrequencySupport) = (; P_ac_support = 0.0)

"""
$(TYPEDEF)

Lagged frequency-support active-power contribution.

$(TYPEDFIELDS)
"""
@with_kw struct FrequencySupportLag <: AbstractFrequencySupport
    "Active-power gain per normalized frequency deviation \\[dimensionless\\]."
    Kω::Float64 = 0.0
    "Support low-pass angular cutoff \\[rad/s\\]."
    ωc::Float64 = 0.0
end

statenames(::FrequencySupportLag) = (:ξ_f_supp,)

"""
$(TYPEDSIGNATURES)

Evaluate the frequency-support lag equation.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `sync`: Synchronization output with normalized angular frequency `ω_c`
  \\[dimensionless\\].
- `block`: The `FrequencySupportLag` parameters.

# Returns

- `P_ac_support`: Active-power support \\[dimensionless\\].

# Notes

```math
\\dot{\\xi}=\\omega_c[-K_\\omega(\\omega-1)-\\xi],\\qquad P_{supp}=\\xi.
```

The frequency and support power are normalized \\[dimensionless\\]. ``ω_c`` is the lag
cutoff \\[rad/s\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = FrequencySupportLag(Kω=5.0, ωc=2π*10)
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
outputs = P.state_space!(F, x, sync, block)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, sync, block::FrequencySupportLag)
    F[1] = block.ωc * (-block.Kω * (sync.ω_c - 1) - x.ξ_f_supp)
    return (; P_ac_support = x.ξ_f_supp)
end

const _DC_VOLTAGE_SUPPORT_INPUT =
    Input(1.0; unit = "pu", description = "DC-voltage support reference")

"""
$(TYPEDEF)

Subtract lagged DC-voltage support from the active-power reference.
Measured voltage and the solved reference use the declared DC-voltage base.

$(TYPEDFIELDS)

# Notes

```math
\\dot{\\xi}_{vdc,supp}=\\omega_c[K(v_{dc,ref}-v_{dc,f})-\\xi_{vdc,supp}],
\\qquad p_{ref,eff}=p_{ref}-\\xi_{vdc,supp}.
```

Here ``v_{dc,ref}`` denotes the solved DC-voltage reference, ``v_{dc,f}``
the filtered DC voltage and ``\\xi_{vdc,supp}`` the lag state. The effective
active-power reference ``p_{ref,eff}`` uses the converter's pu base, as do
voltages and the lag state. The cutoff ``\\omega_c`` has units \\[rad/s\\]
and ``K`` is droop gain in pu power per pu voltage.
"""
@with_kw struct DCVoltageSupportLag <: AbstractFrequencySupport
    "Droop gain in normalized active power per normalized DC voltage \\[dimensionless\\]."
    K::Float64 = 0.0
    "First-order low-pass cutoff in \\[rad/s\\]."
    ωc::Float64 = 0.0
    "DC-voltage reference on converter bases \\[dimensionless\\]."
    v_dc_ref::Float64 = _DC_VOLTAGE_SUPPORT_INPUT.default
end

statenames(::DCVoltageSupportLag) = (:ξ_vdc_supp,)
initialvalues(::DCVoltageSupportLag; kwargs...) = (; ξ_vdc_supp = 0.0)

"""
$(TYPEDSIGNATURES)

Evaluate DC-voltage support lag, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]. Its voltage
  angle uses \\[rad\\].
- `block`: The `DCVoltageSupportLag` parameters.

# Returns

- `P_ac_support`: Active-power support \\[dimensionless\\].

# Notes

```math
\\dot{\\xi}=\\omega_c[K(v_{dc,ref}-v_{dc,f})-\\xi],\\qquad P_{supp}=-\\xi.
```

Voltages and support power are normalized \\[dimensionless\\]. ``ω_c`` uses \\[rad/s\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = DCVoltageSupportLag(K=5.0, ωc=2π*10)
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, sync=sync)
outputs = P.state_space!(F, x, signals, point, block)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, terminal_pu::TerminalValuesPU,
        block::DCVoltageSupportLag)
    F[1] = block.ωc * (block.K * (terminal_pu.v_dc - inputs.meas.v_dc_f) - x.ξ_vdc_supp)
    return (; P_ac_support = -x.ξ_vdc_supp)
end

"""
$(TYPEDSIGNATURES)

Evaluate frequency-support response, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]. Its voltage
  angle uses \\[rad\\].
- `block`: Component block whose equations or metadata are evaluated.

# Returns

- `P_ac_support`: Active-power support returned by the delegated support block
  \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = FrequencySupportLag(Kω=5.0, ωc=2π*10)
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, sync=sync)
outputs = P.state_space!(F, x, signals, point, block)
@assert all(isfinite, F)
```
"""
state_space!(F, x, inputs, terminal_pu::TerminalValuesPU, block::AbstractFrequencySupport) =
    state_space!(F, x, inputs.sync, block)

pf_dc_droop(::AbstractOuterActiveControl, dcbase, powerbase, global_dict, data) = 0.0

const _OUTER_ACTIVE_POWER_INPUT =
    Input(0.0; unit = "pu", description = "active-power reference")

"""
$(TYPEDEF)

Regulate active power with PI control and optional frequency or DC-voltage support.

$(TYPEDFIELDS)
"""
struct OuterActivePowerControl{S<:AbstractFrequencySupport} <: AbstractOuterActiveControl
    "PI gains for normalized signals. Proportional gain is \\[dimensionless\\] and integral
    gain is \\[s⁻¹\\]."
    pi_ctrl::PIControl
    "Active-power support block driven by frequency or DC voltage."
    support::S
    "Active-power reference on converter bases \\[dimensionless\\]."
    p_ref::Float64
end

"""
$(TYPEDSIGNATURES)

Construct an active-power PI controller.

# Arguments

- `pi_ctrl`: PI gains for normalized signals. Proportional gain is \\[dimensionless\\] and
  integral gain is \\[s⁻¹\\]. Default: `PIControl()`.
- `support`: Active-power support block driven by frequency or DC voltage. Default:
  `NoFrequencySupport()`.
- `p_ref`: Active-power reference on converter bases \\[dimensionless\\]. Default: `0.0`.

# Returns

- An `OuterActivePowerControl` instance.

# Examples

```julia
using PowerImpedance
component = OuterActivePowerControl()
```
"""
function OuterActivePowerControl(;
    pi_ctrl::PIControl = PIControl(),
    support::AbstractFrequencySupport = NoFrequencySupport(),
    p_ref::Real = _OUTER_ACTIVE_POWER_INPUT.default,
)
    return OuterActivePowerControl{typeof(support)}(pi_ctrl, support, Float64(p_ref))
end

function pf_dc_droop(block::OuterActivePowerControl{DCVoltageSupportLag}, dcbase, powerbase, global_dict, data)
    return (1 / block.support.K) * (dcbase / (data["dcpol"] * global_dict["V"] / 1e3)) /
        (powerbase / (global_dict["S"] * 1e-6))
end

function statenames(block::OuterActivePowerControl)
    return (statenames(block.support)..., :ξ_P_ac)
end

function initialvalues(block::OuterActivePowerControl;
        terminal_pu=TerminalValuesPU(0, 0, 0, 0))
    return (; initialvalues(block.support)...)
end


"""
$(TYPEDSIGNATURES)

Evaluate active-power control and its support dynamics.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]. Its voltage
  angle uses \\[rad\\].
- `block`: The `OuterActivePowerControl` parameters.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- `iΔ_d_ref`: Current reference \\[dimensionless\\].
- `P_ac_f`: Filtered AC active power \\[dimensionless\\].

# Notes

```math
e=p_{ref}+p_{supp}-p_f,\\quad \\dot{\\xi}=K_i e,\\quad i_{d,ref}=K_p e+\\xi.
```

Power and current use converter bases \\[dimensionless\\]. Support dynamics precede the PI
integrator.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = OuterActivePowerControl(pi_ctrl=PIControl(Kp=0.1, Ki=1.0))
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
        block::OuterActivePowerControl, conv::AbstractConverter)
    (; meas) = inputs
    ns = n_states(block.support)
    support = state_space!(@view(F[1:ns]), x, inputs, terminal_pu, block.support)
    P_ac_f = meas.P_ac_f

    Peff_ref = terminal_pu.p_ac + support.P_ac_support

    F[ns + 1] = block.pi_ctrl.Ki * (Peff_ref - P_ac_f)

    return (iΔ_d_ref = block.pi_ctrl.Kp * (Peff_ref - P_ac_f) + x.ξ_P_ac, P_ac_f = P_ac_f)
end

const _OUTER_ACTIVE_VDC_INPUT =
    Input(1.0; unit = "pu", description = "DC-voltage reference")

"""
$(TYPEDEF)

DC-voltage outer-loop controller that produces a d-axis current reference.
Its local filter affects only this voltage-control path. Shared measurement,
modulation and energy feedforward use their own signals.
`NoFilter()` preserves the zero-state measurement and PI equations.

$(TYPEDFIELDS)
"""
struct OuterActiveVdcControl{F<:AbstractMeasurementFilter} <: AbstractOuterActiveControl
    "Voltage PI gains in the converter per-unit system."
    pi_ctrl::PIControl
    "Local filter for measured DC voltage. Cutoff in \\[rad/s\\]."
    filter::F
    "DC-voltage reference on converter bases \\[dimensionless\\]."
    v_dc_ref::Float64
end

"""
$(TYPEDSIGNATURES)

Construct a DC-voltage PI controller with a local measurement filter.

# Arguments

- `pi_ctrl`: PI gains for normalized signals. `Kp` is \\[dimensionless\\] and `Ki` is
  \\[s⁻¹\\]. Default: `PIControl()`.
- `filter`: Scalar measurement filter specification or realized filter. Default:
  `NoFilter()`.
- `v_dc_ref`: DC-voltage reference on converter bases \\[dimensionless\\]. Default: `1.0`.

# Returns

- `OuterActiveVdcControl` with a state-space realization of the supplied filter.

# Notes

The PI parameter container is also accepted as the first positional argument.

# Examples

```julia
using PowerImpedance
component = OuterActiveVdcControl()
```
"""
function OuterActiveVdcControl(; pi_ctrl::PIControl = PIControl(),
        filter::AbstractMeasurementFilter = NoFilter(),
        v_dc_ref::Real = _OUTER_ACTIVE_VDC_INPUT.default)
    realized = measurement_filter_ss(filter)
    return OuterActiveVdcControl{typeof(realized)}(pi_ctrl, realized, Float64(v_dc_ref))
end
OuterActiveVdcControl(pi_ctrl::PIControl) = OuterActiveVdcControl(; pi_ctrl)

statenames(block::OuterActiveVdcControl) =
    (filter_statenames(:v_dc_ctrl_f, block.filter)..., :ξ_v_dc)

function initialvalues(block::OuterActiveVdcControl; terminal_pu=TerminalValuesPU())
    return filter_initialvalues(block.filter,
        filter_statenames(:v_dc_ctrl_f, block.filter), terminal_pu.v_dc)
end

"""
$(TYPEDSIGNATURES)

Evaluate DC-voltage PI control.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]. Its voltage
  angle uses \\[rad\\].
- `block`: The `OuterActiveVdcControl` parameters.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- `iΔ_d_ref`: Current reference \\[dimensionless\\].

# Notes

```math
\\dot{\\xi}_{vdc}=K_i(v_{dc,ref}-v_f),\\qquad
i_{d,ref}=-[K_p(v_{dc,ref}-v_f)+\\xi_{vdc}],
```

where ``v_f`` is the locally filtered measured DC voltage and ``v_{dc,ref}``
is the solved reference in pu.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = OuterActiveVdcControl(pi_ctrl=PIControl(Kp=0.1, Ki=1.0))
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
        block::OuterActiveVdcControl, conv::AbstractConverter)
    (; meas) = inputs
    v_dc, idx = filter_step!(F, 1, x, block.filter,
        filter_statenames(:v_dc_ctrl_f, block.filter), meas.v_dc_f)
    F[idx] = block.pi_ctrl.Ki * (terminal_pu.v_dc - v_dc)

    return (iΔ_d_ref = -1 * (block.pi_ctrl.Kp * (terminal_pu.v_dc - v_dc) + x.ξ_v_dc), )
end

inputs(block::OuterActivePowerControl) = (
    p_ref = _OUTER_ACTIVE_POWER_INPUT, support = inputs(block.support),
)
inputs(::OuterActiveVdcControl) = (v_dc_ref = _OUTER_ACTIVE_VDC_INPUT,)
inputs(::DCVoltageSupportLag) = (v_dc_ref = _DC_VOLTAGE_SUPPORT_INPUT,)

_powerflow_references(block::OuterActivePowerControl) =
    merge((p_ac = block.p_ref,), _powerflow_references(block.support))
_powerflow_references(block::OuterActiveVdcControl) = (v_dc = block.v_dc_ref,)
_powerflow_references(block::DCVoltageSupportLag) = (v_dc = block.v_dc_ref,)
