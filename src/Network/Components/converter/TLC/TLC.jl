#=
Top-level modular two-level converter (TLC) assembly.

This file wires the TLC electrical plant, measurement, synchronization, outer
loops, inner loops, modulation, equilibrium handling, and power-flow adapter.
Reusable control loops and primitives live in `converter/common`; TLC-specific
plant and modulation behavior remains in this folder.
=#

export tlc,
       TLC,
       AbstractTLC

"""
$(TYPEDEF)

Abstract supertype for modular TLC state-space models.
"""
abstract type AbstractTLC <: AbstractConverter end

include("electrical.jl")
include("modulation.jl")

"""
$(TYPEDEF)

Composite modular TLC model.

$(TYPEDFIELDS)

# Notes

State order follows measurement, synchronization, outer active and reactive
controls, inner voltage and current controls, modulation, and the electrical
plant. `state_space!` evaluates the blocks in this dependency order.
"""
@with_kw struct TLC{
    E<:ElectricalTLC,
    Meas<:Measurement,
    Sync<:AbstractSynchronization,
    Active<:AbstractOuterActiveControl,
    Reactive<:AbstractOuterReactiveControl,
    IV<:AbstractInnerVoltage,
    IC<:AbstractInnerCurrentControl,
    Mod<:AbstractModulationTLC} <: AbstractTLC

    "Electrical reactor model and physical bases."
    elec::E
    "Signal measurement and filtering assembly."
    meas::Meas
    "Synchronization block."
    sync::Sync
    "Active-power or DC-voltage outer controller."
    outerActive::Active
    "Reactive-power or AC-voltage outer controller."
    outerReactive::Reactive
    "Inner-voltage or current-reference forwarding block."
    innerVoltage::IV
    "Inner-current controller."
    innerCurrent::IC
    "Modulation and delay block."
    mod::Mod
    "Active-power limits \\[MW\\] and reactive-power limits \\[MVAr\\]."
    limits::Limits
    "Power-flow seeds on converter bases \\[dimensionless\\]."
    powerflow::NamedTuple
    "Retained terminal values, converged state and linearization matrices."
    cache::LinearizationCache = LinearizationCache()
end

statenames(c::TLC) = (
    statenames(c.meas)...,
    statenames(c.sync)...,
    statenames(c.outerActive)...,
    statenames(c.outerReactive)...,
    statenames(c.innerVoltage)...,
    statenames(c.innerCurrent)...,
    statenames(c.mod)...,
    statenames(c.elec)...
)

function initialvalues(c::TLC; inputs, terminal_pu=TerminalValuesPU())
    elec_init = initialvalues(c.elec; inputs, terminal_pu)

    meas_inputs = (
        vG_d = inputs.vG_d,
        vG_q = inputs.vG_q,
        v_dc = inputs.v_dc,
        i_d = elec_init.i_d,
        i_q = elec_init.i_q,
        i_dc = 0.0,             #TODO improve this initialization?
        θ   = terminal_pu.θ_ac
    )
    return (;
        elec_init...,
        initialvalues(c.meas, inputs=meas_inputs)..., 
        initialvalues(c.sync; terminal_pu)...,
        initialvalues(c.outerActive; terminal_pu)...,
        initialvalues(c.outerReactive; terminal_pu)...,
        initialvalues(c.innerVoltage; inputs, conv=c)...,
        initialvalues(c.innerCurrent; inputs, conv=c)...,
        initialvalues(c.mod; inputs, terminal_pu)...
    )
end

"""
$(TYPEDSIGNATURES)

Return TLC external input names.

# Arguments

- `::TLC`: Concrete instance of `TLC`.

# Returns

- Tuple of external input-name symbols in column order.

# Notes

Names define the ordering used when vectors are mapped to named signals. Composite
models specialize this interface for their external terminals.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
names = P.inputnames(model)
```
"""
inputnames(::TLC) = (:v_dc, :vG_d, :vG_q)

"""
$(TYPEDSIGNATURES)

Return TLC external output names.

# Arguments

- `::TLC`: Concrete instance of `TLC`.

# Returns

- Tuple of external output-name symbols in row order.

# Notes

Names define the ordering used when vectors are mapped to named signals. Composite
models specialize this interface for their external terminals.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
names = P.outputnames(model)
```
"""
outputnames(::TLC) = (:i_dc, :i_d, :i_q)

equilibriumnames(::TLC) = ()

"""
$(TYPEDSIGNATURES)

Convert physical terminal values into normalized TLC inputs.
Port powers are positive into the converter. Taking 603 MW from DC and delivering
600 MW to AC gives `dc.p = 603` and `ac.p = -600`.

# Arguments

- `c`: TLC assembly and electrical bases.
- `values`: NamedTuple with `ac` and `dc` port values in
  \\[kV\\], \\[rad\\], \\[MW\\] and \\[MVAr\\].

# Returns

- `inputs`: Named tuple of DC voltage `v_dc` and grid-frame AC voltages `vG_d`, `vG_q`,
  on converter bases \\[dimensionless\\].
- `terminal_pu`: Normalized operating point; powers and voltages use \\[dimensionless\\]
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
model = tlc().element_model
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),
    dc = DCPortValues(640.0, 100.0))
inputs, point_pu = P.pftoinputs(model, values)
```
"""
function pftoinputs(c::TLC, values::NamedTuple)
    vACbase = c.elec.vACbase
    v_ac = values.ac.v / vACbase
    v_bus_d = v_ac * cos(values.ac.theta)
    v_bus_q = -v_ac * sin(values.ac.theta)
    v_dc = values.dc.v / c.elec.vDCbase

    p_ac = -values.ac.p / c.elec.Sbase
    q_ac = -values.ac.q / c.elec.Sbase
    p_dc = values.dc.p / c.elec.Sbase
    
    return (; v_dc, vG_d = v_bus_d, vG_q = v_bus_q),
        TerminalValuesPU(p_ac, q_ac, values.ac.theta, v_ac, p_dc, v_dc)
end

# transitional
pftoinputs(c::TLC, setpoint::Setpoint) =
    pftoinputs(c, _terminal_values(c, setpoint))

"""
$(TYPEDSIGNATURES)

Build the raw internal signals seen by the measurement block.

# Arguments

- `c`: TLC assembly and electrical bases.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].

# Returns

- `vG_d`: Grid-voltage d component in the synchronization frame \\[dimensionless\\].
- `vG_q`: Grid-voltage q component in the synchronization frame \\[dimensionless\\].
- `vG_d_g`: Grid-voltage d component in the electrical grid frame \\[dimensionless\\].
- `vG_q_g`: Grid-voltage q component in the electrical grid frame \\[dimensionless\\].
- `v_dc`: DC input voltage \\[dimensionless\\].
- `i_d`: AC current d component in the synchronization frame \\[dimensionless\\].
- `i_q`: AC current q component in the synchronization frame \\[dimensionless\\].
- `i_dc`: DC measurement signal; zero in this TLC input adapter \\[dimensionless\\].
- `θ`: Synchronization angle \\[rad\\].

# Notes

The AC quantities are rotated into the synchronization frame before filtering.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
signals = P.input_signals(model, x, inputs)
```
"""
function input_signals(c::TLC, x, inputs)
    θ = syncangle(c.sync, x)
    v = frame_transform(inputs.vG_d, inputs.vG_q, θ)
    i = frame_transform(x.i_d, x.i_q, θ)

    return (
        vG_d = v.d,
        vG_q = v.q,
        vG_d_g = inputs.vG_d, # grid reference frame
        vG_q_g = inputs.vG_q, # grid reference frame
        v_dc = inputs.v_dc,
        i_d = i.d,
        i_q = i.q,
        i_dc = 0.0,
        θ   = θ
    )
end

function outputequations!(F, x, inputs, y, ::TLC)
    F[1] = y.elec.i_dc
    F[2] = -y.elec.i_d
    F[3] = -y.elec.i_q
    return nothing
end

function equilibriumequations!(F, x, inputs, terminal_pu::TerminalValuesPU, y, c::TLC)
    result = equilibriumequations!(F, x, inputs, terminal_pu, y, c, c.outerActive)
    equilibriumequations!(F, x, inputs, terminal_pu, y, c, c.outerReactive)
    return result
end

function equilibriumequations!(F, x, inputs, terminal_pu::TerminalValuesPU, y, c::TLC,
        block::OuterActiveVdcControl)
    idx_ξvdc = findfirst(==(:ξ_v_dc), statenames(c))
    @assert !isnothing(idx_ξvdc)
    i_dc_ref = terminal_pu.p_dc / inputs.v_dc
    F[idx_ξvdc] = i_dc_ref - y.elec.i_dc
    return y
end

"""
$(TYPEDSIGNATURES)

Evaluate the full TLC state-space model.

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
- `c`: TLC assembly and electrical bases.

# Returns

- `sig_in`: Raw electrical input signals.
- `meas`: Filtered measurement signals.
- `sync`: Synchronization outputs.
- `pact`: Active-control outputs.
- `qact`: Reactive-control outputs.
- `vloop`: Inner-voltage-loop outputs.
- `iloop`: Inner-current-loop outputs.
- `mod`: Modulation commands.
- `elec`: Electrical terminal currents. Electrical quantities use converter bases
  \\[dimensionless\\]; angles use \\[rad\\].

# Notes

Subblocks are evaluated explicitly in dependency order. Electrical dynamics are
written into the electrical block state slice after modulation commands are available.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
F = zeros(P.n_states(model))
outputs = P.state_space!(F, x, inputs, point, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, terminal_pu::TerminalValuesPU, c::TLC)
    sig_in = input_signals(c, x, inputs)

    meas, i = state_space_block!(F, x, sig_in, terminal_pu, c.meas, c, 1)
    sync, i = state_space_block!(F, x, meas, terminal_pu, c.sync, c, i)
    pact, i = state_space_block!(F, x, (; meas, sync), terminal_pu, c.outerActive, c, i)
    qact, i = state_space_block!(F, x, (; meas, sync), terminal_pu, c.outerReactive, c, i)
    vloop, i = state_space_block!(F, x, (; meas, sync, pact, qact), terminal_pu,
        c.innerVoltage, c, i)
    iloop, i = state_space_block!(F, x, (; meas, sync, vloop), terminal_pu, c.innerCurrent,
        c, i)
    mod, i = state_space_block!(F, x, (; meas, iloop), terminal_pu, c.mod, c, i)

    elec_in = (
        v_dc = sig_in.v_dc,
        vG_d = inputs.vG_d,
        vG_q = inputs.vG_q,
    )
    elec, _ = state_space_block!(F, x, (inputs = elec_in, mod = mod), terminal_pu, c.elec,
        c, i)

    return (;
        sig_in,
        meas,
        sync,
        pact,
        qact,
        vloop,
        iloop,
        mod,
        elec
    )
end

"""
$(TYPEDSIGNATURES)

Construct a two-level voltage-source converter from composable plant, signal,
control, and modulation blocks.

# Arguments

- `elec`: Electrical subsystem and its physical base quantities. Default:
  `ElectricalTLC()`.
- `meas`: Measurement and signal-filtering block. Default: `Measurement()`.
- `sync`: Synchronization block supplying the converter control frame. Default:
  `NoSynchronization()`.
- `outerActive`: Active-power or DC-voltage outer controller. Default:
  `NoOuterActiveControl()`.
- `outerReactive`: Reactive-power or AC-voltage outer controller. Default:
  `NoOuterReactiveControl()`.
- `innerVoltage`: Inner-voltage block producing current references. Default:
  `NoInnerVoltageControl()`.
- `innerCurrent`: Inner-current controller producing voltage references. Default:
  `NoInnerCurrentControl()`.
- `mod`: TLC modulation and delay block. Default: `NoModulation()`.
- `setpoint`: Physical operating point; powers use \\[MW\\] or \\[MVAr\\], voltages \\[kV\\],
  and angles \\[rad\\]. Default: `Setpoint()`.
- `limits`: Active-power limits \\[MW\\] and reactive-power limits \\[MVAr\\],
  passed directly to the TLC power-flow adapter. Default: `Limits()`.
- `powerflow`: Partial power-flow seeds on converter bases \\[dimensionless\\].
  Default: `(;)`.
- `connection`: Whether the element participates in network construction. Default:
  `true`.

# Returns

- An `Element` with one DC terminal group and one transformed AC terminal group.

# Notes

The selected synchronization and outer-control blocks determine the converter's
AC and DC power-flow modes. Construction does not solve an equilibrium or populate linearization matrices.
`update!` solves and linearizes the numeric model at a supplied operating point;
frequency-domain evaluation then uses those stored matrices.

# Examples

```julia
converter = tlc(
    sync = PLLSynchronization(),
    outerActive = OuterActivePowerControl(),
    outerReactive = OuterReactiveQControl(),
    innerCurrent = InnerCurrentPIControl(),
    setpoint = Setpoint(Pac = 100.0, Qac = 0.0, Vac = 220.0, Vdc = 640.0),
)
```
"""
function tlc(;
    elec::ElectricalTLC = ElectricalTLC(),
    meas::Measurement = Measurement(),
    sync::AbstractSynchronization = NoSynchronization(),
    outerActive::AbstractOuterActiveControl = NoOuterActiveControl(),
    outerReactive::AbstractOuterReactiveControl = NoOuterReactiveControl(),
    innerVoltage::AbstractInnerVoltage = NoInnerVoltageControl(),
    innerCurrent::AbstractInnerCurrentControl = NoInnerCurrentControl(),
    mod::AbstractModulationTLC = NoModulation(),
    setpoint::Setpoint = Setpoint(),
    limits::Limits = Limits(),
    powerflow::NamedTuple = (;),
    connection::Bool = true
)
    defaults = map(input -> input.default, _CONVERTER_POWERFLOW_INPUTS)
    seeds = _withinputs(defaults, _CONVERTER_POWERFLOW_INPUTS,
        powerflow, "powerflow")
    conv = TLC(elec, meas, sync, outerActive, outerReactive, innerVoltage, innerCurrent,
        mod, limits, seeds, LinearizationCache())

    return Element(
        input_pins = 1,
        output_pins = 2,
        element_model = conv,
        transformation = false;
        connection,
        setpoint,
        limits,
    )
end

##################### SI Scaling ######################################
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

Base currents in \\[kA\\] divided by base voltages in \\[kV\\] give \\[S\\].
Rows follow `(:i_dc, :i_d, :i_q)` and columns follow `(:v_dc, :vG_d, :vG_q)`.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
scale = P.SI_scale(model)
```
"""
function SI_scale(model::TLC)
    elec = model.elec

    vACbase = elec.vACbase
    iACbase = 2 * elec.Sbase / (3 * vACbase)
    iDCbase = elec.Sbase / elec.vDCbase

    scale = ones(3,3)

    # row scaling = output current bases
    scale[1, :]   .*= iDCbase
    scale[2:3, :] .*= iACbase

    # column scaling = input voltage bases
    scale[:, 1]   ./= elec.vDCbase
    scale[:, 2:3] ./= vACbase

    return scale
end

# transitional
SI_scale(elem::Element{<:TLC}) = SI_scale(elem.element_model)
############################  Power-flow integration TLC ############################


pf_type_ac(::NoOuterReactiveControl) = 1
pf_type_ac(::OuterReactiveVacControl) = 2
pf_type_ac(block::OuterReactiveQControl) = block.support isa NoVoltageSupport ? 1 : 2

pf_type_dc(::NoOuterActiveControl) = 1
pf_type_dc(::OuterActivePowerControl) = 1
pf_type_dc(::OuterActivePowerControl{DCVoltageSupportLag}) = 4
pf_type_dc(::OuterActiveVdcControl) = 2

pf_acq_droop(::NoOuterReactiveControl) = (enabled = 0, kq = 0.0)
pf_acq_droop(::OuterReactiveVacControl) = (enabled = 0, kq = 0.0)
pf_acq_droop(block::OuterReactiveQControl) =
    block.support isa VoltageSupportLag ? (
        enabled = 1,
        kq = block.support.K,
    ) : (enabled = 0, kq = 0.0)

function pf_vdcset_pu(conv::TLC, elem::Element, global_dict, data)
    return elem.setpoint.Vdc / (data["dcpol"] * global_dict["V"] / 1e3)
end

function pf_pacset_mw(conv::TLC, elem::Element)
    return elem.setpoint.Pac
end

function pf_pdcset_mw(conv::TLC, elem::Element)
    return !iszero(elem.setpoint.Pdc) ? elem.setpoint.Pdc : -elem.setpoint.Pac
end

function convert!(data,elem::Element{<:TLC},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)

    dc_node = make_node(elem, 1)
    ac_nodes = make_node(elem, 2)
    dc_bus = add_bus_dc!(data, nodes2bus, bus2nodes, dc_node, global_dict)
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)

    key = comp_elem_interface!(data, elem2comp, comp2elem, elem, pmtype(elem))
    return convert!(data, elem, PMACDC, key, (ac_bus, dc_bus), global_dict)
end

function convert!(data, elem::Element{<:TLC}, ::Type{PMACDC}, key, buses, global_dict)
    conv = elem.element_model
    ac_bus = buses[1]
    dc_bus = buses[2]
    key_str = string(key)

    data["convdc"][key_str] = Dict{String, Any}()
    convdc = data["convdc"][key_str]

    convdc["busdc_i"] = dc_bus
    convdc["busac_i"] = ac_bus
    convdc["source_id"] = Any["convdc", key]
    convdc["status"] = 1
    convdc["index"] = key
    convdc["basekVac"] = global_dict["V"] / 1e3

    convdc["type_ac"] = pf_type_ac(conv.outerReactive)
    convdc["Vtar"] = (elem.setpoint.Vac/sqrt(2)) / ( global_dict["V"] / 1e3) # division by sqrt(2) --> for base voltages, PowerModelsACDC uses RMS voltages, PowerImpedance uses amplitude
    if convdc["type_ac"] == 2
        data["bus"][string(ac_bus)] = set_bus_type(data["bus"][string(ac_bus)], 2)
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
    end

    convdc["type_dc"] = pf_type_dc(conv.outerActive)

    droop = pf_acq_droop(conv.outerReactive)
    convdc["acq_droop"] = droop.enabled
    convdc["kq_droop"] = droop.kq * (conv.elec.Sbase / (global_dict["S"] * 1e-6))

    convdc["droop"] = pf_dc_droop(conv.outerActive, conv.elec.vDCbase, conv.elec.Sbase, global_dict, data)
    convdc["Vdcset"] = pf_vdcset_pu(conv, elem, global_dict, data)
    convdc["Pacset"] = -pf_pacset_mw(conv, elem)
    convdc["Pdcset"] = pf_pdcset_mw(conv, elem)
    convdc["dVdcSet"] = 0.0

    convdc["islcc"] = 0
    convdc["transformer"] = 0
    convdc["rtf"] = 0.0
    convdc["xtf"] = 0.0
    convdc["tm"] = 1.0
    convdc["filter"] = 0
    convdc["bf"] = 0.0
    convdc["reactor"] = 1

    zbase = global_dict["Z"]
    convdc["rc"] = (conv.elec.Rᵣ*conv.elec.zACbase) / zbase
    convdc["xc"] = (conv.elec.Lᵣ*conv.elec.lACbase) * global_dict["omega"] / zbase

    convdc["Vmmax"] = 1.1 * convdc["Vtar"]
    convdc["Vmmin"] = 0.9 * convdc["Vtar"]
    convdc["Imax"] = 1.1 * max(abs(elem.limits.P_min), abs(elem.limits.P_max), abs(elem.setpoint.Pac)) / max(elem.setpoint.Vac / sqrt(2), eps())

    convdc["P_g"] = elem.setpoint.Pac
    convdc["Q_g"] = elem.setpoint.Qac

    convdc["LossA"] = 0.0
    convdc["LossB"] = 0.0
    convdc["LossCrec"] = 0.0
    convdc["LossCinv"] = 0.0

    convdc["Qacmax"] = elem.limits.Q_max
    convdc["Qacmin"] = elem.limits.Q_min
    convdc["Pacmax"] = elem.limits.P_max
    convdc["Pacmin"] = elem.limits.P_min

    if data["bus"][string(ac_bus)]["bus_type"] == 1
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
        data["bus"][string(ac_bus)]["vmin"] = 0.9 * data["bus"][string(ac_bus)]["vm"]
        data["bus"][string(ac_bus)]["vmax"] = 1.1 * data["bus"][string(ac_bus)]["vm"]
    end

    data["busdc"][string(dc_bus)]["Vdc"] = elem.setpoint.Vdc / (data["dcpol"] * global_dict["V"] / 1e3)
    data["busdc"][string(dc_bus)]["Vdcmax"] = 1.1 * data["busdc"][string(dc_bus)]["Vdc"]
    data["busdc"][string(dc_bus)]["Vdcmin"] = 0.9 * data["busdc"][string(dc_bus)]["Vdc"]
    data["busdc"][string(dc_bus)] = set_bus_type_dc(data["busdc"][string(dc_bus)], convdc["type_dc"])

    return nothing
end

electricalconnections(::TLC) = (ac = Port(ACDQ), dc = Port(DC_CM))

is_passive(::TLC) = false
admittance_order(::TLC) = ((:dc, :dc), (:ac, :d), (:ac, :q))

inputs(model::TLC) = (
    sync = inputs(model.sync),
    outerActive = inputs(model.outerActive),
    outerReactive = inputs(model.outerReactive),
    innerVoltage = inputs(model.innerVoltage),
    innerCurrent = inputs(model.innerCurrent),
    powerflow = _CONVERTER_POWERFLOW_INPUTS,
)

_powerflow_references(model::TLC) = merge(_powerflow_references(model.sync),
    _powerflow_references(model.outerActive), _powerflow_references(model.outerReactive))
powerflow_targets(model::TLC) = merge(model.powerflow, _powerflow_references(model))

bases(model::TLC) = BaseValues(S = model.elec.Sbase, v_ac = model.elec.vACbase,
    v_dc = model.elec.vDCbase, omega = model.elec.ωbase)

limits(model::TLC) = model.limits

function _withinputs(model::TLC, declarations::NamedTuple, changes, path)
    configured = invoke(_withinputs, Tuple{Any, NamedTuple, Any, Any},
        model, declarations, changes, path)
    return Parameters.reconstruct(configured; cache = LinearizationCache())
end


pmtype(::TLC, rows) = "convdc"

function convert!(data, conv::TLC, ::Type{PMACDC}, component_key,
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

    convdc["type_ac"] = pf_type_ac(conv.outerReactive)
    # division by sqrt(2) --> for base voltages, PowerModelsACDC uses RMS voltages,
    # PowerImpedance uses amplitude
    convdc["Vtar"] = (v_ac/sqrt(2)) / ( global_dict["V"] / 1e3)
    if convdc["type_ac"] == 2
        data["bus"][string(ac_bus)] = set_bus_type(data["bus"][string(ac_bus)], 2)
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
    end

    convdc["type_dc"] = pf_type_dc(conv.outerActive)

    droop = pf_acq_droop(conv.outerReactive)
    convdc["acq_droop"] = droop.enabled
    convdc["kq_droop"] = droop.kq * (conv.elec.Sbase / (global_dict["S"] * 1e-6))

    convdc["droop"] = pf_dc_droop(conv.outerActive,
        conv.elec.vDCbase, conv.elec.Sbase, global_dict, data)
    convdc["Vdcset"] = v_dc / (data["dcpol"] * global_dict["V"] / 1e3)
    convdc["Pacset"] = -p_ac
    convdc["Pdcset"] = !iszero(p_dc) ? p_dc : -p_ac
    convdc["dVdcSet"] = 0.0

    convdc["islcc"] = 0
    convdc["transformer"] = 0
    convdc["rtf"] = 0.0
    convdc["xtf"] = 0.0
    convdc["tm"] = 1.0
    convdc["filter"] = 0
    convdc["bf"] = 0.0
    convdc["reactor"] = 1

    zbase = global_dict["Z"]
    convdc["rc"] = (conv.elec.Rᵣ*conv.elec.zACbase) / zbase
    convdc["xc"] = (conv.elec.Lᵣ*conv.elec.lACbase) * global_dict["omega"] / zbase

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

    convdc["Qacmax"] = lm.Q_max
    convdc["Qacmin"] = lm.Q_min
    convdc["Pacmax"] = lm.P_max
    convdc["Pacmin"] = lm.P_min

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
