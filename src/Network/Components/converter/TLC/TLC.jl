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
Abstract supertype for modular TLC state-space models.
"""
abstract type AbstractTLC <: AbstractConverter end

include("electrical.jl")
include("modulation.jl")

"""
Composite modular TLC model.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)

# Details

The field order defines the state ordering used by [`statenames`](@ref) and the
execution order used in [`state_space!`](@ref).
"""
struct TLC{
    E<:ElectricalTLC,
    Meas<:Measurement,
    Sync<:AbstractSynchronization,
    Active<:AbstractOuterActiveControl,
    Reactive<:AbstractOuterReactiveControl,
    IV<:AbstractInnerVoltage,
    IC<:AbstractInnerCurrentControl,
    Mod<:AbstractModulationTLC} <: AbstractTLC

    elec::E
    meas::Meas
    sync::Sync
    outerActive::Active
    outerReactive::Reactive
    innerVoltage::IV
    innerCurrent::IC
    mod::Mod
end

"""
Return all TLC state names in model execution order.

$(SIGNATURES)
"""
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

"""
Return initial values for the full TLC state vector.

$(SIGNATURES)

# Details

Electrical currents are initialized first because measurement and controller
initial conditions depend on the operating-point currents.
"""
function initialvalues(c::TLC; inputs, setpoint_pu=SetpointPU())
    elec_init = initialvalues(c.elec; inputs, setpoint_pu)

    meas_inputs = (
        vG_d = inputs.vG_d,
        vG_q = inputs.vG_q,
        v_dc = inputs.v_dc,
        i_d = elec_init.iΔ_d,
        i_q = elec_init.iΔ_q,
        i_dc = 0.0,             #TODO improve this initialization?
        θ   = setpoint_pu.θ_ac
    )
    return (;
        elec_init...,
        initialvalues(c.meas, inputs=meas_inputs)..., 
        initialvalues(c.sync; setpoint_pu)...,
        initialvalues(c.outerActive; setpoint_pu)...,
        initialvalues(c.outerReactive; setpoint_pu)...,
        initialvalues(c.innerVoltage; inputs, conv=c)...,
        initialvalues(c.innerCurrent; inputs, conv=c)...,
        initialvalues(c.mod; inputs, setpoint_pu)...
    )
end

"""
Return TLC external input names.

$(SIGNATURES)
"""
inputnames(::TLC) = (:v_dc, :vG_d, :vG_q)

"""
Return TLC external output names.

$(SIGNATURES)
"""
outputnames(::TLC) = (:i_dc, :i_d, :i_q)

"""
Return additional equilibrium dummy names.

$(SIGNATURES)
"""
dummynames(::TLC) = ()

"""
Convert a power-flow setpoint into normalized TLC inputs.

$(SIGNATURES)
"""
function pftoinputs(c::TLC, setpoint::Setpoint)
    vACbase = c.elec.vACbase
    v_ac = setpoint.Vac / vACbase
    v_bus_d = v_ac * cos(setpoint.θac)
    v_bus_q = -v_ac * sin(setpoint.θac)
    v_dc = setpoint.Vdc / c.elec.vDCbase

    p_ac = setpoint.Pac / c.elec.Sbase
    q_ac = - setpoint.Qac / c.elec.Sbase  
    p_dc = setpoint.Pdc / c.elec.Sbase
    
    return (; v_dc, vG_d = v_bus_d, vG_q = v_bus_q),
        SetpointPU(p_ac, q_ac, setpoint.θac, v_ac, p_dc, v_dc)
end

"""
Build the raw internal signals seen by the measurement block.

$(SIGNATURES)

# Details

The AC quantities are rotated into the synchronization frame before filtering.
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

"""
Write TLC output equations.
All currents carry load sign convention for compatibility with admittance formulation.

$(SIGNATURES)
"""
function outputequations!(F, x, inputs, y, ::TLC)
    F[1] = y.elec.i_dc
    F[2] = -y.elec.i_d
    F[3] = -y.elec.i_q
    return nothing
end

"""
Evaluate TLC equilibrium equations.

$(SIGNATURES)
"""
equilibriumequations!(F, x, inputs, setpoint_pu::SetpointPU, y, c::TLC) =
    equilibriumequations!(F, x, inputs, setpoint_pu, y, c, c.outerActive)

"""
Evaluate TLC equilibrium equations for DC-voltage control.

$(SIGNATURES)

# Details

The DC-voltage PI state equation is replaced with the DC-current balance used to
solve the operating point.
"""
function equilibriumequations!(F, x, inputs, setpoint_pu::SetpointPU, y, c::TLC, block::OuterActiveVdcControl)
    idx_ξvdc = findfirst(==(:ξ_v_dc), statenames(c))
    @assert !isnothing(idx_ξvdc)
    i_dc_ref = setpoint_pu.p_dc / inputs.v_dc
    F[idx_ξvdc] = i_dc_ref - y.elec.i_dc
    return y
end

"""
Evaluate the full TLC state-space model.

$(SIGNATURES)

# Details

Subblocks are evaluated explicitly in dependency order. Electrical dynamics are
written into the first state slice after modulation commands are available.
"""
function state_space!(F, x, inputs, setpoint_pu::SetpointPU, c::TLC)
    sig_in = input_signals(c, x, inputs)

    meas, i = state_space_block!(F, x, sig_in, setpoint_pu, c.meas, c, 1)
    sync, i = state_space_block!(F, x, meas, setpoint_pu, c.sync, c, i)
    pact, i = state_space_block!(F, x, (; meas, sync), setpoint_pu, c.outerActive, c, i)
    qact, i = state_space_block!(F, x, (; meas, sync), setpoint_pu, c.outerReactive, c, i)
    vloop, i = state_space_block!(F, x, (; meas, sync, pact, qact), setpoint_pu, c.innerVoltage, c, i)
    iloop, i = state_space_block!(F, x, (; meas, sync, vloop), setpoint_pu, c.innerCurrent, c, i)
    mod, i = state_space_block!(F, x, (; meas, iloop), setpoint_pu, c.mod, c, i)

    elec_in = (
        v_dc = sig_in.v_dc,
        vG_d = inputs.vG_d,
        vG_q = inputs.vG_q,
    )
    elec, _ = state_space_block!(F, x, (inputs = elec_in, mod = mod), setpoint_pu, c.elec, c, i)

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
Construct a TLC `Element` with modular subblocks.

$(SIGNATURES)
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
    connection::Bool = true
)
    conv = TLC(elec, meas, sync, outerActive, outerReactive, innerVoltage, innerCurrent, mod)

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
function SI_scale(elem::Element{<:TLC})
    elec = elem.element_model.elec

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
############################  Power-flow integration TLC ############################


"""
Return PowerModelsACDC AC converter type for a reactive outer loop.

$(SIGNATURES)
"""
pf_type_ac(::NoOuterReactiveControl) = 1
pf_type_ac(::OuterReactiveVacControl) = 2
pf_type_ac(block::OuterReactiveQControl) = block.support isa NoVoltageSupport ? 1 : 2

"""
Return PowerModelsACDC DC converter type for an active outer loop.

$(SIGNATURES)
"""
pf_type_dc(::NoOuterActiveControl) = 1
pf_type_dc(::OuterActivePowerControl) = 1
pf_type_dc(::OuterActiveVdcControl) = 2

"""
Return AC voltage droop settings for the power-flow converter entry.

$(SIGNATURES)
"""
pf_acq_droop(::NoOuterReactiveControl) = (enabled = 0, kq = 0.0)
pf_acq_droop(::OuterReactiveVacControl) = (enabled = 0, kq = 0.0)
pf_acq_droop(block::OuterReactiveQControl) =
    block.support isa VoltageSupportLag ? (
        enabled = 1,
        kq = block.support.K,
    ) : (enabled = 0, kq = 0.0)

"""
Return DC voltage setpoint in the PowerModelsACDC per-unit base.

$(SIGNATURES)
"""
function pf_vdcset_pu(conv::TLC, elem::Element, global_dict, data)
    return elem.setpoint.Vdc / (data["dcpol"] * global_dict["V"] / 1e3)
end

"""
Return active-power AC setpoint in MW.

$(SIGNATURES)
"""
function pf_pacset_mw(conv::TLC, elem::Element)
    return elem.setpoint.Pac
end

"""
Return active-power DC setpoint in MW.

$(SIGNATURES)
"""
function pf_pdcset_mw(conv::TLC, elem::Element)
    return !iszero(elem.setpoint.Pdc) ? elem.setpoint.Pdc : -elem.setpoint.Pac
end

"""
Write the TLC converter entry into a PowerModelsACDC power-flow data dictionary.

$(SIGNATURES)
"""
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
    convdc["Vtar"] = (elem.setpoint.Vac/sqrt(2)) / ( global_dict["V"] / 1e3) # division by sqrt(2) --> for base voltages, PowerModelsACDC uses RMS voltages, PowerImpedanceACDC uses amplitude  
    if convdc["type_ac"] == 2
        data["bus"][string(ac_bus)] = set_bus_type(data["bus"][string(ac_bus)], 2)
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
    end

    convdc["type_dc"] = pf_type_dc(conv.outerActive)

    droop = pf_acq_droop(conv.outerReactive)
    convdc["acq_droop"] = droop.enabled
    convdc["kq_droop"] = droop.kq * (conv.elec.Sbase / (global_dict["S"] * 1e-6))

    convdc["droop"] = 0.0
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
