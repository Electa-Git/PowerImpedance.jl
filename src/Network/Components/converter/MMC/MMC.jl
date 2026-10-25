export mmc, MMC, AbstractMMC,       # MMC
    ΔdqControlGFL, ΔdqControlGFM,   # High level structures
    ΣdqzControlTEC, ΣdqzControlLEC


# Abstract types
"""
$(TYPEDEF)

Define the interface for modular multilevel converter assemblies.
"""
abstract type AbstractMMC                       <: AbstractConverter end
"""
$(TYPEDEF)

Define the differential-current control assembly of an MMC.
"""
abstract type AbstractΔdqControl                <: AbstractStateSpace end
"""
$(TYPEDEF)

Define the sum-current and internal-energy control assembly of an MMC.
"""
abstract type AbstractΣdqzControl               <: AbstractStateSpace end
voltage_filter_ratio(conv::AbstractMMC) = conv.elec.turnsRatio

# Include files
include("electrical.jl")
include("energy.jl")
include("inner_current.jl")
include("modulation.jl")


# Structs

# MMC
"""
$(TYPEDEF)

Combine the measurement, synchronization, differential-current control,
internal-current control, modulation, and electrical submodels of a modular
multilevel converter.

$(TYPEDFIELDS)
"""
@with_kw struct MMC{S<:AbstractSynchronization, Δ<:AbstractΔdqControl, Σ<:AbstractΣdqzControl, Mod<:AbstractModulationMMC} <: AbstractMMC
    #### Blocks composing the MMC model:
    "Measurement and signal-filtering block."
    meas::Measurement
    "Synchronization block."
    sync::S
    "Differential-current AC-side control structure."
    delta_control::Δ
    "Sum/circulating-current internal control structure."
    sigma_control::Σ
    "Modulation and delay block."
    modulation::Mod                      
    "MMC electrical plant and physical bases."
    elec::ElectricalMMC
    "Active- and reactive-power limits on converter bases \\[dimensionless\\]."
    limits::Limits = Limits()
    "Power-flow seeds on converter bases \\[dimensionless\\]."
    powerflow::NamedTuple = map(input -> input.default, _CONVERTER_POWERFLOW_INPUTS)
    "Retained terminal values, converged state and linearization matrices."
    cache::LinearizationCache = LinearizationCache()
end

statenames(c::MMC) = (statenames(c.meas)..., statenames(c.sync)..., statenames(c.delta_control)..., statenames(c.sigma_control)..., statenames(c.modulation)..., statenames(c.elec)...) 
initialvalues(c::MMC; inputs, terminal_pu)  = (;
    initialvalues(c.meas; inputs)...,
    initialvalues(c.sync; terminal_pu)...,
    initialvalues(c.delta_control; inputs, terminal_pu, conv=c)...,
    initialvalues(c.sigma_control; terminal_pu)...,
    initialvalues(c.elec; inputs, terminal_pu)...,)
inputnames(::MMC)                           = (:v_dc, :vG_d, :vG_q)
outputnames(::MMC)                          = (:i_dc, :iΔ_d, :iΔ_q) 

# High level structures
"""
$(TYPEDEF)

Assemble grid-following active-power, reactive-power, and output-current controls.

$(TYPEDFIELDS)
"""
@with_kw struct ΔdqControlGFL{A<:AbstractOuterActiveControl, R<:AbstractOuterReactiveControl, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    "Active-power or DC-voltage outer controller."
    outer_active::A
    "Reactive-power or AC-voltage outer controller."
    outer_reactive::R
    "Output-current controller."
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFL) = (statenames(c.outer_active)..., statenames(c.outer_reactive)..., statenames(c.occ)...)
initialvalues(c::ΔdqControlGFL; inputs, terminal_pu, conv) = (;
    initialvalues(c.outer_active; terminal_pu)...,
    initialvalues(c.outer_reactive; terminal_pu, conv)...,
    initialvalues(c.occ; inputs, conv)...)

"""
$(TYPEDEF)

Assemble grid-forming reactive-power, virtual-impedance, and output-current controls.

$(TYPEDFIELDS)
"""
@with_kw struct ΔdqControlGFM{R<:AbstractOuterReactiveControl, V<:AbstractVirtualImpedance, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    "Reactive-power or AC-voltage outer controller."
    outer_reactive::R
    "Virtual-impedance block producing current references."
    vi::V               # Virtual Impedance
    "Output-current controller."
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFM) = (statenames(c.outer_reactive)..., statenames(c.vi)..., statenames(c.occ)...)
initialvalues(c::ΔdqControlGFM; inputs, terminal_pu, conv) = (;
    initialvalues(c.outer_reactive; terminal_pu, conv)...,
    initialvalues(c.vi; inputs, conv)...,
    initialvalues(c.occ; inputs, conv)...)

"""
$(TYPEDEF)

Assemble total-energy, zero-sequence-current, and circulating-current-suppression
controls.

$(TYPEDFIELDS)
"""
@with_kw struct ΣdqzControlTEC{E<:AbstractEnergyControl, I1<:AbstractInnerCurrentControl, I2<:AbstractInnerCurrentControl} <: AbstractΣdqzControl
    "Total arm-energy controller."
    tec::E = NoTotalEnergyControl()                     # Total Energy Control
    "Zero-sequence circulating-current controller."
    zscc::I1 = NoZeroSequenceCurrentControl()           # Zero-Sequence Current Control
    "d/q circulating-current-suppression controller."
    ccsc::I2 = NoCirculatingCurrentSuppressionControl() # Circulating Current Suppression Control
end
statenames(c::ΣdqzControlTEC) = (statenames(c.tec)..., statenames(c.zscc)..., statenames(c.ccsc)...)
initialvalues(c::ΣdqzControlTEC; terminal_pu=TerminalValuesPU()) = (;
    initialvalues(c.tec; terminal_pu)...,
    initialvalues(c.zscc)...,
    initialvalues(c.ccsc)...)

"""
$(TYPEDEF)

Assemble sum-energy, difference-energy, and circulating-current controls.

$(TYPEDFIELDS)
"""
@with_kw struct ΣdqzControlLEC{E1<:AbstractEnergyControl, E2<:AbstractEnergyControl, I<:AbstractInnerCurrentControl} <: AbstractΣdqzControl
    "Sum arm-energy controller."
    wsigma::E1      # Sum Energy Control
    "Difference arm-energy controller."
    wdelta::E2      # Delta Energy Control
    "Three-component circulating-current controller."
    ccc::I          # Circulating Current Control
end
statenames(c::ΣdqzControlLEC) = (statenames(c.wsigma)..., statenames(c.wdelta)..., statenames(c.ccc)...)
initialvalues(c::ΣdqzControlLEC; terminal_pu=TerminalValuesPU()) = (;
    initialvalues(c.wsigma)...,
    initialvalues(c.wdelta)...,
    initialvalues(c.ccc)...)


# State-space equations

# MMC
"""
$(TYPEDSIGNATURES)

Evaluate MMC measurement, synchronization, control, modulation, and plant dynamics,
writing state derivatives into `F`.

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
- `c`: MMC assembly and electrical bases.

# Returns

- `meas`: Named tuple of filtered measurements on converter bases
  \\[dimensionless\\], with synchronization angle `θ_f` in \\[rad\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
F = zeros(P.n_states(model))
outputs = P.state_space!(F, x, inputs, point, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, terminal_pu::TerminalValuesPU, c::MMC)
    # Signal processing
    sig_in = input_signals(c, x, inputs)

    meas, i = state_space_block!(F, x, sig_in, terminal_pu, c.meas, c, 1)
    sync_out, i = state_space_block!(F, x, meas, terminal_pu, c.sync, c, i)

    # Delta and Sigma control
    out_delta, i = state_space_block!(F, x, (; meas, sync = sync_out), terminal_pu,
        c.delta_control, c, i)
    out_sigma, i = state_space_block!(F, x,
        (meas = meas, power = (P_ac_f = meas.P_ac_f,), sync = sync_out), terminal_pu,
        c.sigma_control, c, i)

    # Modulation
    out_modulation, i = state_space_block!(F, x, (; meas, out_delta, out_sigma),
        terminal_pu, c.modulation, c, i)

    # Electrical model
    state_space_block!(F, x, (; out_modulation, sig_in, inputs), terminal_pu, c.elec, c, i)

    return (; meas)
end


# Higher level structures

"""
$(TYPEDSIGNATURES)

Evaluate MMC total-energy and circulating-current control, writing state derivatives
into `F`.

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
- `b`: The `ΣdqzControlTEC` parameters.
- `c`: MMC assembly and electrical bases.

# Returns

- `vMΣ_d_ref_c`: Sum d-axis voltage reference \\[dimensionless\\].
- `vMΣ_q_ref_c`: Sum q-axis voltage reference \\[dimensionless\\].
- `vMΣ_z_ref`: Sum zero-sequence voltage reference \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = model.sigma_control
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, power=(P_ac_f=0.1,), sync=sync)
outputs = P.state_space!(F, x, signals, point, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs::NamedTuple{(:meas, :power, :sync)},
        terminal_pu::TerminalValuesPU, b::ΣdqzControlTEC, c::MMC)
    (; meas) = inputs
    # Outer loop
    out_Wtot, i = state_space_block!(F, x, meas, terminal_pu, b.tec, c, 1)

    # Inner loop
    out_zscc, i = state_space_block!(F, x, (; meas, out_Wtot), terminal_pu, b.zscc, c, i)
    out_ccsc, i = state_space_block!(F, x, meas, terminal_pu, b.ccsc, c, i)

    return merge(out_ccsc, out_zscc)
end

"""
$(TYPEDSIGNATURES)

Evaluate MMC summed- and differential-energy control, writing state derivatives into
`F`.

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
- `b`: The `ΣdqzControlLEC` parameters.
- `c`: MMC assembly and electrical bases.

# Returns

- `vMΣ_d_ref_c`: Sum d-axis voltage reference \\[dimensionless\\].
- `vMΣ_q_ref_c`: Sum q-axis voltage reference \\[dimensionless\\].
- `vMΣ_z_ref`: Sum zero-sequence voltage reference \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = ΣdqzControlLEC(wsigma=ΣEnergyControl(pi_control=PIControl(Kp=0.1, Ki=1.0)), wdelta=ΔEnergyControl(pi_control=PIControl(Kp=0.1, Ki=1.0)), ccc=CirculatingCurrentControl(PIControl(Kp=0.1, Ki=1.0)))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, power=(P_ac_f=0.1,), sync=sync)
outputs = P.state_space!(F, x, signals, point, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs::NamedTuple{(:meas, :power, :sync)},
        terminal_pu::TerminalValuesPU, b::ΣdqzControlLEC, c::MMC)
    (; meas, power, sync) = inputs
    # Outer loop
    out_wsigma, i = state_space_block!(F, x, (; meas, power, sync), terminal_pu, b.wsigma,
        c, 1)
    out_wdelta, i = state_space_block!(F, x, (; meas, power, sync), terminal_pu, b.wdelta,
        c, i)

    # Inner loop
    out_ccc, _ = state_space_block!(F, x,
        (; meas, sync, out_wΣ = out_wsigma, out_wΔ = out_wdelta), terminal_pu, b.ccc, c, i)

    return out_ccc
end

"""
$(TYPEDSIGNATURES)

Evaluate MMC grid-following outer and inner control loops, writing state derivatives
into `F`.

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
- `b`: The `ΔdqControlGFL` parameters.
- `c`: MMC assembly and electrical bases.

# Returns

- `iΔ_d_ref`: Active-loop d-axis current reference \\[dimensionless\\].
- `P_ac_f`: Filtered active power when supplied by an `OuterActivePowerControl`
  \\[dimensionless\\].
- `vMΔ_d_ref_c`: Synchronization-frame d-axis voltage reference \\[dimensionless\\].
- `vMΔ_q_ref_c`: Synchronization-frame q-axis voltage reference \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = model.delta_control
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
function state_space!(F, x, inputs, terminal_pu::TerminalValuesPU, b::ΔdqControlGFL, c::MMC)
    (; meas, sync) = inputs
    # Outer loop
    out_active, i = state_space_block!(F, x, (; meas, sync), terminal_pu, b.outer_active, c,
        1)
    out_reactive, i = state_space_block!(F, x, (; meas, sync), terminal_pu,
        b.outer_reactive, c, i)

    # Inner loop
    
    out_occ, _= state_space_block!(F, x,
        (; meas, sync, vloop = (; out_active..., iΔ_q_ref = out_reactive.q_ctrl_ref)),
        terminal_pu, b.occ, c, i)

    return merge(out_active, out_occ)
end

"""
$(TYPEDSIGNATURES)

Evaluate MMC grid-forming voltage and current control loops, writing state derivatives
into `F`.

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
- `b`: The `ΔdqControlGFM` parameters.
- `c`: MMC assembly and electrical bases.

# Returns

- `vMΔ_d_ref_c`: Synchronization-frame differential d-axis voltage reference
  \\[dimensionless\\].
- `vMΔ_q_ref_c`: Synchronization-frame differential q-axis voltage reference
  \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = ΔdqControlGFM(outer_reactive=OuterReactiveVacControl(), vi=CCVI(), occ=InnerCurrentPIControl())
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
function state_space!(F, x, inputs, terminal_pu::TerminalValuesPU, b::ΔdqControlGFM, c::MMC)
    (; meas, sync) = inputs
    # Outer loop
    out_reactive, i = state_space_block!(F, x, (; meas, sync), terminal_pu,
        b.outer_reactive, c, 1)

    # Inner loop
    out_vi, i = state_space_block!(F, x, (; meas, sync, out_reactive), terminal_pu, b.vi, c,
        i)

    out_occ, _= state_space_block!(F, x, (; meas, sync, vloop = out_vi), terminal_pu, b.occ,
        c, i)

    return out_occ
end


# Handling of inputs and outputs

"""
$(TYPEDSIGNATURES)

Convert physical terminal values to normalized external inputs and internal
terminal data.
Port powers are positive into the converter. Taking 603 MW from DC and delivering
600 MW to AC gives `dc.p = 603` and `ac.p = -600`.

# Arguments

- `c`: MMC assembly and electrical bases.
- `values`: NamedTuple with `ac` and `dc` port values in
  \\[kV\\], \\[rad\\], \\[MW\\] and \\[MVAr\\].

# Returns

- `inputs`: Named tuple of DC voltage `v_dc` and grid-frame AC voltages `vG_d`, `vG_q`,
  on converter bases \\[dimensionless\\].
- `terminal_pu`: Normalized operating point. Powers and voltages use \\[dimensionless\\]
  and the angle uses \\[rad\\].

# Notes

```math
v_d=(V/V_b)\\cos\\theta,\\qquad v_q=-(V/V_b)\\sin\\theta.
```

Here ``V`` is the physical AC phase-peak voltage \\[kV\\], ``V_b`` is its base \\[kV\\], and
``\\theta`` is the operating-point angle \\[rad\\]. Powers are divided by the component
power base, with AC powers negated to get the powers delivered to the AC bus.
DC voltage is divided by the pole-to-pole DC base.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
values = (ac = ACPortValues(380sqrt(2/3), 0.0, -100.0, 0.0),
    dc = DCPortValues(640.0, 100.0))
inputs, point_pu = P.pftoinputs(model, values)
```
"""
function pftoinputs(c::MMC, values::NamedTuple)
    v_ac = values.ac.v / c.elec.vAC_base       # Grid side voltage (peak,phase) perunitized by converter-side base voltage (peak,phase) #TODO check why this choice and how it impacts the rest
    v_dc = values.dc.v / c.elec.vDC_base
    p_ac = -values.ac.p / c.elec.Sbase
    q_ac = -values.ac.q / c.elec.Sbase
    p_dc = values.dc.p / c.elec.Sbase
    
    vG_d = v_ac * cos(values.ac.theta)   # d component of the grid voltage in the grid frame
    vG_q = -v_ac * sin(values.ac.theta)  # q component of the grid voltage in the grid frame

    return (v_dc = v_dc, vG_d = vG_d, vG_q = vG_q), 
        TerminalValuesPU(p_ac, q_ac, values.ac.theta, v_ac, p_dc, v_dc)
end


"""
$(TYPEDSIGNATURES)

Build the electrical signals passed to converter measurement and plant blocks.

# Arguments

- `c`: MMC assembly and electrical bases.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].

# Returns

- `vG_d`: Converter-side grid-voltage d component in the synchronization frame \\[dimensionless\\].
- `vG_q`: Converter-side grid-voltage q component in the synchronization frame \\[dimensionless\\].
- `vG_d_g`: Converter-side grid-voltage d component in the nominal grid dq frame \\[dimensionless\\].
- `vG_q_g`: Converter-side grid-voltage q component in the nominal grid dq frame \\[dimensionless\\].
- `v_dc`: DC input voltage \\[dimensionless\\].
- `i_d`: AC current d component in the synchronization frame \\[dimensionless\\].
- `i_q`: AC current q component in the synchronization frame \\[dimensionless\\].
- `i_dc`: DC current, equal to three times `x.iΣ_z` \\[dimensionless\\].
- `θ`: Synchronization angle \\[rad\\].

# Notes

All four returned AC-voltage components are multiplied by `c.elec.turnsRatio`
before being supplied to measurement and electrical blocks. Current components
are rotated without this voltage multiplier.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
signals = P.input_signals(model, x, inputs)
```
"""
function input_signals(c::MMC, x, inputs)
    θ = syncangle(c.sync, x)
    v = frame_transform(inputs.vG_d, inputs.vG_q, θ)
    i = frame_transform(x.iΔ_d, x.iΔ_q, θ)

    return ( # Fields use the converter reference frame unless specified otherwise.
        vG_d = v.d * c.elec.turnsRatio,
        vG_q = v.q * c.elec.turnsRatio,
        vG_d_g = inputs.vG_d * c.elec.turnsRatio, # grid reference frame
        vG_q_g = inputs.vG_q * c.elec.turnsRatio, # grid reference frame
        v_dc = inputs.v_dc,
        i_d = i.d,
        i_q = i.q,
        i_dc = 3 * x.iΣ_z,
        θ = θ
    )
end


# Convention: every current enters its terminal, as the nodal admittance
# formulation requires.
function outputequations!(F, x, y, inputs, c::MMC)
    # Electrical state variables are in the grid dq frame.
    F[1:3] = [3*x.iΣ_z, -x.iΔ_d, -x.iΔ_q]
end


# Constructor

"""
$(TYPEDSIGNATURES)

Construct a modular multilevel converter from composable electrical, signal,
control, and modulation blocks.

# Arguments

- `elec`: Electrical subsystem and its physical base quantities. Default:
  `ElectricalMMC()`.
- `meas`: Measurement and signal-filtering block. Default: `Measurement()`.
- `sync`: Synchronization block supplying the converter control frame.
- `delta_control`: MMC differential-current control assembly.
- `sigma_control`: MMC sum-current and energy-control assembly.
- `modulation`: MMC insertion-index calculation and delay block. Default:
  `UncompensatedModulation()`.
- `limits`: Operating limits on the component power base \\[dimensionless\\]. Default:
  `Limits()`.
- `powerflow`: Partial power-flow seeds on converter bases \\[dimensionless\\].
  Default: `(;)`.

# Returns

- An immutable `MMC` with `ac` and `dc` ports.

# Notes

Set control references and power-flow seeds with `component` or `withinputs`.
References and seeds use the converter bases.

The selected synchronization and outer-control blocks determine the AC and DC
power-flow control modes. The power bounds multiply `limits` by `Sbase`. The
current-limit estimate compares their unscaled values with physical `Pac`.
`linearize` solves the equilibrium and populates the linearization matrices at
a supplied operating point.
Frequency-domain evaluation then uses those stored matrices.

# Examples

```julia
converter = mmc(
    sync = PLLSynchronization(),
    delta_control = ΔdqControlGFL(
        outer_active = OuterActivePowerControl(),
        outer_reactive = OuterReactiveQControl(),
        occ = InnerCurrentPIControl(),
    ),
    sigma_control = ΣdqzControlTEC(),
)

b = bases(converter)
converter = component(converter;
    delta_control = (outer_active = (p_ref = 100.0 / b.S,),
        outer_reactive = (q_ref = 0.0 / b.S,)),
    powerflow = (v_ac = 220.0 / b.v_ac, v_dc = 640.0 / b.v_dc))
```
"""
function mmc(;
    elec::ElectricalMMC = ElectricalMMC(),
    meas::Measurement = Measurement(),
    sync::AbstractSynchronization,
    delta_control::AbstractΔdqControl,
    sigma_control::AbstractΣdqzControl,
    modulation::AbstractModulationMMC = UncompensatedModulation(),
    limits::Limits = Limits(),
    powerflow::NamedTuple = (;))

    defaults = map(input -> input.default, _CONVERTER_POWERFLOW_INPUTS)
    seeds = _withinputs(defaults, _CONVERTER_POWERFLOW_INPUTS,
        powerflow, "powerflow")
    return MMC(meas, sync, delta_control, sigma_control, modulation, elec,
        limits, seeds, LinearizationCache())
end

# SI scaling
function _mmc_si_scale!(Y, elec::ElectricalMMC)
    iACbase = 2 * elec.Sbase / (3 * elec.vAC_base)
    iDCbase = elec.Sbase / elec.vDC_base

    Y[1:1, 1:1] .*= iDCbase
    Y[1:1, 1:1] ./= elec.vDC_base
    Y[1:1, 2:3] .*= iDCbase
    Y[1:1, 2:3] ./= elec.vAC_base
    Y[2:3, 1:1] .*= iACbase * elec.turnsRatio
    Y[2:3, 1:1] ./= elec.vDC_base

    # Equivalent AC-current/AC-voltage scaling preserves the rounding of the AC-AC block.
    # The physical cross terms use the winding current base.
    Y[2:3, 2:3] .*= iACbase
    Y[2:3, 2:3] ./= elec.vAC_base / elec.turnsRatio
    return Y
end

"""
$(TYPEDSIGNATURES)

Return the factors that convert normalized model admittance to physical terminal
admittance.

# Arguments

- `model`: Component model with electrical base quantities.

# Returns

- Matrix of output-current-base to input-voltage-base ratios \\[S\\].

# Notes

```math
Y_{ij}^{SI}=Y_{ij}^{pu}\\frac{I_{b,i}}{V_{b,j}}.
```

The row current bases are `(I_dc, n*I_ac, n*I_ac)` and the column voltage bases are
`(V_dc, V_ac, V_ac)`, where `n=turnsRatio`, `I_ac=2Sbase/(3vAC_base)`,
`I_dc=Sbase/vDC_base`, `V_ac=vAC_base`, and `V_dc=vDC_base`. Currents use
\\[kA\\] and voltages \\[kV\\]. Their ratios use \\[S\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync = PLLSynchronization(),
    delta_control = ΔdqControlGFL(outer_active = OuterActivePowerControl(),
        outer_reactive = OuterReactiveQControl(), occ = InnerCurrentPIControl()),
    sigma_control = ΣdqzControlTEC())
scale = P.SI_scale(model)
```
"""
function SI_scale(model::MMC)
    return _mmc_si_scale!(ones(3, 3), model.elec)
end



# Power-flow integration MMC



equilibriumequations!(F, x, inputs, terminal_pu::TerminalValuesPU, y, c::MMC) =
    equilibriumequations!(F, x, inputs, terminal_pu, y, c, c.delta_control)

function equilibriumequations!(
        F, x, inputs, terminal_pu::TerminalValuesPU, y, c::MMC, b::ΔdqControlGFL)
    result = equilibriumequations!(F, x, inputs, terminal_pu, y, c, b.outer_active)
    equilibriumequations!(F, x, inputs, terminal_pu, y, c, b.outer_reactive)
    return result
end

function equilibriumequations!(
        F, x, inputs, terminal_pu::TerminalValuesPU, y, c::MMC, b::ΔdqControlGFM)
    equilibriumequations!(F, x, inputs, terminal_pu, y, c, b.outer_reactive)
end

function equilibriumequations!(F, x, inputs, terminal_pu::TerminalValuesPU, y, c::MMC,
        ::OuterActiveVdcControl)
    idx_ξvdc = findfirst(==(:ξ_v_dc), statenames(c))
    @assert !isnothing(idx_ξvdc)
    i_dc_ref = terminal_pu.p_dc / inputs.v_dc
    F[idx_ξvdc] = i_dc_ref - 3*x.iΣ_z
    return y
end

pf_type_ac(block::ΔdqControlGFL) = pf_type_ac(block.outer_reactive)
pf_type_ac(block::ΔdqControlGFM) = pf_type_ac(block.outer_reactive)

pf_type_dc(::VSEWithDamping) = 1
pf_type_dc(::NoSynchronization) = 1
pf_type_dc(::PLLSynchronization) = 1
pf_type_dc(block::ΔdqControlGFL, sync::AbstractSynchronization) = pf_type_dc(block.outer_active)
pf_type_dc(::ΔdqControlGFM, sync::AbstractSynchronization) = pf_type_dc(sync)

pf_dc_droop(block::ΔdqControlGFL, dcbase, powerbase, global_dict, data) =
    pf_dc_droop(block.outer_active, dcbase, powerbase, global_dict, data)
pf_dc_droop(::ΔdqControlGFM, dcbase, powerbase, global_dict, data) = 0.0


electricalconnections(::MMC) = (ac = Port(ACDQ), dc = Port(DC_CM))

is_passive(::MMC) = false
admittance_order(::MMC) = ((:dc, :dc), (:ac, :d), (:ac, :q))

inputs(model::MMC) = (
    delta_control = inputs(model.delta_control),
    sigma_control = inputs(model.sigma_control),
    sync = inputs(model.sync),
    powerflow = _CONVERTER_POWERFLOW_INPUTS,
)
inputs(block::ΔdqControlGFL) = (
    outer_active = inputs(block.outer_active),
    outer_reactive = inputs(block.outer_reactive),
    occ = inputs(block.occ),
)
inputs(block::ΔdqControlGFM) = (
    outer_reactive = inputs(block.outer_reactive),
    vi = inputs(block.vi),
    occ = inputs(block.occ),
)
inputs(block::ΣdqzControlTEC) = (
    tec = inputs(block.tec), zscc = inputs(block.zscc), ccsc = inputs(block.ccsc),
)
inputs(block::ΣdqzControlLEC) = (
    wsigma = inputs(block.wsigma), wdelta = inputs(block.wdelta), ccc = inputs(block.ccc),
)

_powerflow_references(block::ΔdqControlGFL) = merge(
    _powerflow_references(block.outer_active), _powerflow_references(block.outer_reactive))
_powerflow_references(block::ΔdqControlGFM) = _powerflow_references(block.outer_reactive)
_powerflow_references(model::MMC) = merge(
    _powerflow_references(model.sync), _powerflow_references(model.delta_control))
powerflow_targets(model::MMC) = merge(model.powerflow, _powerflow_references(model))

bases(model::MMC) = BaseValues(S = model.elec.Sbase, v_ac = model.elec.vAC_base,
    v_dc = model.elec.vDC_base, omega = model.elec.ωbase)

limits(model::MMC) = model.limits

function _withinputs(model::MMC, declarations::NamedTuple, changes, path)
    configured = invoke(_withinputs, Tuple{Any, NamedTuple, Any, Any},
        model, declarations, changes, path)
    return Parameters.reconstruct(configured; cache = LinearizationCache())
end


pmtype(::MMC, rows) = "convdc"

function convert!(data, conv::MMC, ::Type{PMACDC}, component_key,
        ports::NamedTuple, global_dict)

    key = component_key.index
    target = powerflow_targets(conv)
    b = bases(conv)
    p_ac = target.p_ac * b.S
    q_ac = target.q_ac * b.S
    v_ac = target.v_ac * b.v_ac
    p_dc = target.p_dc * b.S
    v_dc = target.v_dc * b.v_dc
    lm = limits(conv)
    ac_bus = ports.ac
    dc_bus = ports.dc

    key_str = string(key)


    data["convdc"][key_str] = Dict{String, Any}()
    convdc = data["convdc"][key_str]

    convdc["busdc_i"] = dc_bus
    convdc["busac_i"] = ac_bus
    convdc["source_id"] = Any["convdc", key]
    convdc["status"] = 1
    convdc["index"] = key
    convdc["basekVac"] = global_dict["V"] / 1e3

    convdc["type_ac"] = pf_type_ac(conv.delta_control)
    # Divide by sqrt(2). PowerModelsACDC uses RMS base voltages,
    # PowerImpedance uses amplitude
    convdc["Vtar"] = (v_ac/sqrt(2)) / (global_dict["V"] / 1e3)
    if convdc["type_ac"] == 2
        data["bus"][string(ac_bus)] = set_bus_type(data["bus"][string(ac_bus)], 2)
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
    end
    convdc["type_dc"] = pf_type_dc(conv.delta_control, conv.sync)
    droop = pf_acq_droop(conv.delta_control.outer_reactive)
    convdc["acq_droop"] = droop.enabled
    convdc["kq_droop"] = droop.kq * (conv.elec.Sbase / (global_dict["S"] * 1e-6))
    convdc["droop"] = pf_dc_droop(conv.delta_control,
        conv.elec.vDC_base, conv.elec.Sbase, global_dict, data)
    convdc["Vdcset"] = v_dc / (data["dcpol"] * global_dict["V"] / 1e3)
    convdc["Pacset"] = -p_ac
    convdc["Pdcset"] = (!ismissing(p_dc) && !iszero(p_dc)) ? p_dc : p_ac
    convdc["dVdcSet"] = 0.0

    convdc["islcc"] = 0
    convdc["transformer"] = 0
    convdc["rtf"] = 0.0
    convdc["xtf"] = 0.0
    convdc["tm"] = 1.0
    convdc["filter"] = 0
    convdc["bf"] = 0.0
    convdc["reactor"] = 1

    convdc["rc"] = conv.elec.turnsRatio^(-2) *
        (conv.elec.Rₑ * conv.elec.zAC_base) / global_dict["Z"]
    convdc["xc"] = conv.elec.turnsRatio^(-2) *
        (conv.elec.Lₑ * conv.elec.lAC_base) * global_dict["omega"] / global_dict["Z"]

    convdc["Vmmax"] = 1.1 * convdc["Vtar"]
    convdc["Vmmin"] = 0.9 * convdc["Vtar"]
    convdc["Imax"] = 1.1 * max(abs(lm.P_min), abs(lm.P_max), abs(p_ac)) /
        max(v_ac / sqrt(2), eps())

    convdc["P_g"] = p_ac
    convdc["Q_g"] = q_ac
    convdc["LossA"] = 0.0
    convdc["LossB"] = 0.0
    convdc["LossCrec"] = 0.0
    convdc["LossCinv"] = 0.0
    convdc["Qacmax"] = lm.Q_max*conv.elec.Sbase
    convdc["Qacmin"] = lm.Q_min*conv.elec.Sbase
    convdc["Pacmax"] = lm.P_max*conv.elec.Sbase
    convdc["Pacmin"] = lm.P_min*conv.elec.Sbase

    if data["bus"][string(ac_bus)]["bus_type"] == 1
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
        data["bus"][string(ac_bus)]["vmin"] = 0.9 * data["bus"][string(ac_bus)]["vm"]
        data["bus"][string(ac_bus)]["vmax"] = 1.1 * data["bus"][string(ac_bus)]["vm"]
    end

    data["busdc"][string(dc_bus)]["Vdc"] = v_dc / (data["dcpol"] * global_dict["V"] / 1e3)
    data["busdc"][string(dc_bus)]["Vdcmax"] = 1.1 * data["busdc"][string(dc_bus)]["Vdc"]
    data["busdc"][string(dc_bus)]["Vdcmin"] = 0.9 * data["busdc"][string(dc_bus)]["Vdc"]
    data["busdc"][string(dc_bus)] = set_bus_type_dc(
        data["busdc"][string(dc_bus)], convdc["type_dc"])

    return nothing
end
