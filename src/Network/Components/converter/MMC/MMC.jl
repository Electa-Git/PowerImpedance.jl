export mmc, MMC, AbstractMMC,       # MMC
    ΔdqControlGFL, ΔdqControlGFM,   # High level structures
    ΣdqzControlTEC, ΣdqzControlLEC


### Abstract types ###
abstract type AbstractMMC                       <: AbstractConverter end
abstract type AbstractΔdqControl                <: AbstractStateSpace end
abstract type AbstractΣdqzControl               <: AbstractStateSpace end
voltage_filter_ratio(conv::AbstractMMC) = conv.elec.turnsRatio

### Include files ###
include("electrical.jl")
include("energy.jl")
include("inner_current.jl")
include("modulation.jl")


################## Structs #####################

### MMC ###
@with_kw struct MMC{S<:AbstractSynchronization, Δ<:AbstractΔdqControl, Σ<:AbstractΣdqzControl, Mod<:AbstractModulationMMC} <: AbstractMMC
    #### Blocks composing the MMC model:
    meas::Measurement
    sync::S
    delta_control::Δ
    sigma_control::Σ
    modulation::Mod                      
    elec::ElectricalMMC
end

statenames(c::MMC) = (statenames(c.meas)..., statenames(c.sync)..., statenames(c.delta_control)..., statenames(c.sigma_control)..., statenames(c.modulation)..., statenames(c.elec)...) 
initialvalues(c::MMC; inputs, setpoint_pu)  = (; initialvalues(c.meas; inputs)..., initialvalues(c.sync; setpoint_pu)..., initialvalues(c.delta_control; inputs, setpoint_pu, conv=c)..., initialvalues(c.sigma_control)..., initialvalues(c.elec; inputs, setpoint_pu)...,)
inputnames(::MMC)                           = (:v_dc, :vG_d, :vG_q)
outputnames(::MMC)                          = (:i_dc, :iΔ_d, :iΔ_q) 

### High level structures ###
@with_kw struct ΔdqControlGFL{A<:AbstractOuterActiveControl, R<:AbstractOuterReactiveControl, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    outer_active::A
    outer_reactive::R
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFL) = (statenames(c.outer_active)..., statenames(c.outer_reactive)..., statenames(c.occ)...)
initialvalues(c::ΔdqControlGFL; inputs, setpoint_pu, conv) = (; initialvalues(c.outer_active; setpoint_pu)...,
                                                                initialvalues(c.outer_reactive; setpoint_pu)...,
                                                                initialvalues(c.occ; inputs, conv)...) 

@with_kw struct ΔdqControlGFM{R<:AbstractOuterReactiveControl, V<:AbstractVirtualImpedance, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    outer_reactive::R
    vi::V               # Virtual Impedance
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFM) = (statenames(c.outer_reactive)..., statenames(c.vi)..., statenames(c.occ)...)
initialvalues(c::ΔdqControlGFM; inputs, setpoint_pu, conv) = (; initialvalues(c.outer_reactive; setpoint_pu)...,
                                                                initialvalues(c.vi; inputs, conv)...,
                                                                initialvalues(c.occ; inputs, conv)...) 

@with_kw struct ΣdqzControlTEC{E<:AbstractEnergyControl, I1<:AbstractInnerCurrentControl, I2<:AbstractInnerCurrentControl} <: AbstractΣdqzControl
    tec::E = NoTotalEnergyControl()                     # Total Energy Control
    zscc::I1 = NoZeroSequenceCurrentControl()           # Zero-Sequence Current Control
    ccsc::I2 = NoCirculatingCurrentSuppressionControl() # Circulating Current Suppression Control
end
statenames(c::ΣdqzControlTEC) = (statenames(c.tec)..., statenames(c.zscc)..., statenames(c.ccsc)...)
initialvalues(c::ΣdqzControlTEC) = (; initialvalues(c.tec)..., initialvalues(c.zscc)..., initialvalues(c.ccsc)...) 

@with_kw struct ΣdqzControlLEC{E1<:AbstractEnergyControl, E2<:AbstractEnergyControl, I<:AbstractInnerCurrentControl} <: AbstractΣdqzControl
    wsigma::E1      # Sum Energy Control
    wdelta::E2      # Delta Energy Control
    ccc::I          # Circulating Current Control
end
statenames(c::ΣdqzControlLEC) = (statenames(c.wsigma)..., statenames(c.wdelta)..., statenames(c.ccc)...)
initialvalues(c::ΣdqzControlLEC) = (; initialvalues(c.wsigma)..., initialvalues(c.wdelta)..., initialvalues(c.ccc)...) 


################## State-space equations #####################

### MMC ###
function state_space!(F, x, inputs, setpoint_pu::SetpointPU, c::MMC)
    # -- Signal Processing ------------------------------------------------------------------------    
    sig_in = input_signals(c, x, inputs)

    meas, i = state_space_block!(F, x, sig_in, setpoint_pu, c.meas, c, 1)
    sync_out, i = state_space_block!(F, x, meas, setpoint_pu, c.sync, c, i)

    # -- Delta and Sigma control ------------------------------------------------------------------
    out_delta, i = state_space_block!(F, x, (; meas, sync = sync_out), setpoint_pu, c.delta_control, c, i)
    out_sigma, i = state_space_block!(F, x, (meas = meas, power = (P_ac_f = meas.P_ac_f,), sync = sync_out), setpoint_pu, c.sigma_control, c, i)

    # -- Modulation -------------------------------------------------------------------------------
    out_modulation, i = state_space_block!(F, x, (; meas, out_delta, out_sigma), setpoint_pu, c.modulation, c, i)

    # -- Electrical model -------------------------------------------------------------------------
    state_space_block!(F, x, (; out_modulation, sig_in, inputs), setpoint_pu, c.elec, c, i)

    return nothing
end


### Higher level structures ###

function state_space!(F, x, inputs::NamedTuple{(:meas, :power, :sync)}, setpoint_pu::SetpointPU, b::ΣdqzControlTEC, c::MMC) 
    (; meas) = inputs
    # -- Outer Loop -------------------------------------------------------------------------------
    out_Wtot, i = state_space_block!(F, x, meas, setpoint_pu, b.tec, c, 1)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_zscc, i = state_space_block!(F, x, (; meas, out_Wtot), setpoint_pu, b.zscc, c, i)
    out_ccsc, i = state_space_block!(F, x, meas, setpoint_pu, b.ccsc, c, i)

    return merge(out_ccsc, out_zscc)
end

function state_space!(F, x, inputs::NamedTuple{(:meas, :power, :sync)}, setpoint_pu::SetpointPU, b::ΣdqzControlLEC, c::MMC) 
    (; meas, power, sync) = inputs
    # -- Outer Loop -------------------------------------------------------------------------------
    out_wsigma, i = state_space_block!(F, x, (; meas, power, sync), setpoint_pu, b.wsigma, c, 1)
    out_wdelta, i = state_space_block!(F, x, (; meas, power, sync), setpoint_pu, b.wdelta, c, i)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_ccc, _ = state_space_block!(F, x, (; meas, sync, out_wΣ = out_wsigma, out_wΔ = out_wdelta), setpoint_pu, b.ccc, c, i)

    return out_ccc
end

function state_space!(F, x, inputs, setpoint_pu::SetpointPU, b::ΔdqControlGFL, c::MMC)
    (; meas, sync) = inputs
    # -- Outer Loop -------------------------------------------------------------------------------
    out_active, i = state_space_block!(F, x, (; meas, sync), setpoint_pu, b.outer_active, c, 1)
    out_reactive, i = state_space_block!(F, x, (; meas, sync), setpoint_pu, b.outer_reactive, c, i)

    # -- Inner Loop -------------------------------------------------------------------------------
    
    out_occ, _= state_space_block!(F, x, (; meas, sync, vloop = (; out_active..., iΔ_q_ref = out_reactive.q_ctrl_ref)), setpoint_pu, b.occ, c, i)

    return merge(out_active, out_occ)
end

function state_space!(F, x, inputs, setpoint_pu::SetpointPU, b::ΔdqControlGFM, c::MMC)
    (; meas, sync) = inputs
    # -- Outer Loop -------------------------------------------------------------------------------
    out_reactive, i = state_space_block!(F, x, (; meas, sync), setpoint_pu, b.outer_reactive, c, 1)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_vi, i = state_space_block!(F, x, (; meas, sync, out_reactive), setpoint_pu, b.vi, c, i)

    out_occ, _= state_space_block!(F, x, (; meas, sync, vloop = out_vi), setpoint_pu, b.occ, c, i)

    return out_occ
end


################## Handling of inputs and outputs ############

function pftoinputs(c::MMC, setpoint::Setpoint) 
    v_ac  = setpoint.Vac / c.elec.vAC_base       # Grid side voltage (peak,phase) perunitized by converter-side base voltage (peak,phase) #TODO check why this choice and how it impacts the rest
    v_dc = setpoint.Vdc / c.elec.vDC_base
    p_ac = setpoint.Pac / c.elec.Sbase
    q_ac = - setpoint.Qac / c.elec.Sbase   # TODO check if this minus sign is really needed/relevant
    p_dc = setpoint.Pdc / c.elec.Sbase
    
    vG_d = v_ac * cos(setpoint.θac)   # d component of the grid voltage in the grid frame  
    vG_q = -v_ac * sin(setpoint.θac)  # q component of the grid voltage in the grid frame

    return (v_dc = v_dc, vG_d = vG_d, vG_q = vG_q), 
        SetpointPU(p_ac, q_ac, setpoint.θac, v_ac, p_dc, v_dc)
end

function input_signals(c::MMC, x, inputs)
    θ = syncangle(c.sync, x)
    v = frame_transform(inputs.vG_d, inputs.vG_q, θ)
    i = frame_transform(x.iΔ_d, x.iΔ_q, θ)

    return ( # If not speficied otherwise, all fields are in converter reference frame 
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

function outputequations!(F, x, y, inputs, c::MMC)
    # NB: All electrical state variables are in grid dq frame (and not converter frame)
    F[1:3] = [3*x.iΣ_z, x.iΔ_d, x.iΔ_q]
end


################## Contructor ################################

function mmc(;
    elec::ElectricalMMC = ElectricalMMC(),
    meas::Measurement = Measurement(),
    sync::AbstractSynchronization,
    delta_control::AbstractΔdqControl,
    sigma_control::AbstractΣdqzControl,
    modulation::AbstractModulationMMC = UncompensatedModulation(),
    setpoint::Setpoint=Setpoint(),
    limits::Limits = Limits(),
    connection::Bool = true)

    return Element(
        input_pins = 1, 
        output_pins = 2, 
        element_model = MMC(meas, sync, delta_control, sigma_control, modulation, elec), 
        transformation = false; 
        connection,
        setpoint,
        limits)
end

############################  Power-flow integration MMC ############################



equilibriumequations!(F, x, inputs, setpoint_pu::SetpointPU, y, c::MMC) =
    equilibriumequations!(F, x, inputs, setpoint_pu, y, c, c.delta_control)

equilibriumequations!(F, x, inputs, setpoint_pu::SetpointPU, y, c::MMC, b::ΔdqControlGFL) =
    equilibriumequations!(F, x, inputs, setpoint_pu, y, c, b.outer_active)

function equilibriumequations!(F, x, inputs, setpoint_pu::SetpointPU, y, c::MMC, ::OuterActiveVdcControl)
    idx_ξvdc = findfirst(==(:ξ_v_dc), statenames(c))
    @assert !isnothing(idx_ξvdc)
    i_dc_ref = setpoint_pu.p_dc / inputs.v_dc
    F[idx_ξvdc] = i_dc_ref - 3*x.iΣ_z
    return y
end

pf_type_ac(::ΔdqControlGFL) = 1
pf_type_ac(block::ΔdqControlGFM) = pf_type_ac(block.outer_reactive)

pf_type_dc(::VSEWithDamping) = 1
pf_type_dc(::NoSynchronization) = 1
pf_type_dc(::PLLSynchronization) = 1
pf_type_dc(block::ΔdqControlGFL, sync::AbstractSynchronization) = pf_type_dc(block.outer_active)
pf_type_dc(::ΔdqControlGFM, sync::AbstractSynchronization) = pf_type_dc(sync)

function convert!(data,elem::Element{<:MMC},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)
    
    conv = elem.element_model
    dc_node = make_node(elem, 1)
    ac_nodes = make_node(elem, 2)
    dc_bus = add_bus_dc!(data, nodes2bus, bus2nodes, dc_node, global_dict)
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)

    key = comp_elem_interface!(data, elem2comp, comp2elem, elem, "convdc")
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
    convdc["Vtar"] = (elem.setpoint.Vac/sqrt(2)) / (global_dict["V"] / 1e3) # division by sqrt(2) --> for base voltages, PowerModelsACDC uses RMS voltages, PowerImpedanceACDC uses amplitude
    if convdc["type_ac"] == 2
        data["bus"][string(ac_bus)] = set_bus_type(data["bus"][string(ac_bus)], 2)
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
    end
    convdc["type_dc"] = pf_type_dc(conv.delta_control, conv.sync)
    convdc["acq_droop"] = 0
    convdc["kq_droop"] = 0.0
    convdc["droop"] = 0.0
    convdc["Vdcset"] = elem.setpoint.Vdc / (data["dcpol"] * global_dict["V"] / 1e3)
    convdc["Pacset"] = -elem.setpoint.Pac
    convdc["Pdcset"] = !iszero(elem.setpoint.Pdc) ? elem.setpoint.Pdc : elem.setpoint.Pac
    convdc["dVdcSet"] = 0.0

    convdc["islcc"] = 0
    convdc["transformer"] = 0
    convdc["rtf"] = 0.0
    convdc["xtf"] = 0.0
    convdc["tm"] = 1.0
    convdc["filter"] = 0
    convdc["bf"] = 0.0
    convdc["reactor"] = 1

    convdc["rc"] = conv.elec.turnsRatio^(-2) * (conv.elec.Rₑ * conv.elec.zAC_base) / global_dict["Z"]
    convdc["xc"] = conv.elec.turnsRatio^(-2) * (conv.elec.Lₑ * conv.elec.lAC_base) * global_dict["omega"] / global_dict["Z"]

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
