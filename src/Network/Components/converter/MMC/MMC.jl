export mmc, MMC, AbstractMMC, BuildMMC,             # MMC
    ΔdqControlGFL, ΔdqControlGFM, ΣdqzControlTEC,   # High level structures

    NoMeasurementFilter,                            # Measurements
    PLL, VSEWithDamping, VSEWithoutDamping,         # Synchronization
    PControl,                                       # Outer active
    QControl,                                       # Outer reactive
    TotalEnergyControl,                             # Energy
    CCVI,                                           # Inner voltage
    CirculatingCurrentSuppressionControl, ZeroSequenceCurrentControl, OutputCurrentControl,     # Inner current
    UncompensatedModulation, CompensatedModulation,  # Modulation
    ElectricalMMC,

    statenames, inputnames, initialvalues,          # Functions
    state_space!, pftoinputs


### Abstract types ###
abstract type AbstractMMC                       <: AbstractConverter end
abstract type AbstractΔdqControl                <: AbstractStateSpace end
abstract type AbstractΣdqzControl               <: AbstractStateSpace end

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

statenames(c::MMC)                          = (statenames(c.meas)..., statenames(c.sync)..., statenames(c.delta_control)..., statenames(c.sigma_control)..., statenames(c.modulation)..., statenames(c.elec)...) 
initialvalues(c::MMC; inputs, setpoint_pu)  = (; initialvalues(c.meas; inputs)..., initialvalues(c.sync; setpoint_pu)..., initialvalues(c.delta_control; inputs, setpoint_pu, conv=c)..., initialvalues(c.sigma_control)..., initialvalues(c.elec; inputs, setpoint_pu)...,)
inputnames(::MMC)                           = (:v_dc, :vG_d, :vG_q)
outputnames(::MMC)                          = (:i_dc, :iΔ_d, :iΔ_q) 
elecinputnames(c::MMC)                      = inputnames(c)


### High level structures ###

@with_kw struct ΔdqControlGFL{A<:AbstractOuterActiveControl, R<:AbstractOuterReactiveControl, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    outer_active::A
    outer_reactive::R
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFL) = (statenames(c.outer_active)..., statenames(c.outer_reactive)..., statenames(c.occ)...)
initialvalues(c::ΔdqControlGFL; inputs, setpoint_pu, conv) = (; initialvalues(c.outer_active)..., initialvalues(c.outer_reactive)..., initialvalues(c.occ; inputs, setpoint_pu, conv)...) 

@with_kw struct ΔdqControlGFM{R<:AbstractOuterReactiveControl, V<:AbstractVirtualImpedance, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    outer_reactive::R
    vi::V               # Virtual Impedance
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFM) = (statenames(c.outer_reactive)..., statenames(c.vi)..., statenames(c.occ)...)
initialvalues(c::ΔdqControlGFM; inputs, setpoint_pu, conv) = (; initialvalues(c.outer_reactive)..., initialvalues(c.vi)..., initialvalues(c.occ; inputs, setpoint_pu, conv)...) 

output_outer_reactive_control(conv::AbstractMMC, out) = output_outer_reactive_control(conv.delta_control, out)
output_outer_reactive_control(::ΔdqControlGFL, out) = (iΔ_q_ref = out,)
output_outer_reactive_control(::ΔdqControlGFM, out) = (vgfm_d_ref = out,)

@with_kw struct ΣdqzControlTEC{E<:AbstractEnergyControl, I1<:AbstractInnerCurrentControl, I2<:AbstractInnerCurrentControl} <: AbstractΣdqzControl
    tec::E      # Total Energy Control
    zscc::I1    # Zero-Sequence Current Control
    ccsc::I2    # Circulating Current Suppression Control
end
statenames(c::ΣdqzControlTEC) = (statenames(c.tec)..., statenames(c.zscc)..., statenames(c.ccsc)...)
initialvalues(c::ΣdqzControlTEC) = (; initialvalues(c.tec)..., initialvalues(c.zscc)..., initialvalues(c.ccsc)...) 


################## State-space equations #####################

### MMC ###

function state_space!(F, x, inputs, c::MMC)
    # -- Signal Processing ------------------------------------------------------------------------    
    sig_in = input_signals(c, x, inputs)

    meas, i = run_block!(F, x, sig_in, c.meas, c, 1)
    sync, i = run_block!(F, x, meas, c.sync, c, i)

    # -- Delta and Sigma control ------------------------------------------------------------------
    out_delta, i = run_block!(F, x, (meas, sync), c.delta_control, c, i)
    out_sigma, i = run_block!(F, x, meas, c.sigma_control, c, i)

    # -- Modulation -------------------------------------------------------------------------------
    out_modulation, i = run_block!(F, x, (meas, out_delta, out_sigma), c.modulation, c, i)

    # -- Electrical model -------------------------------------------------------------------------
    run_block!(F, x, (out_modulation, sig_in, inputs), c.elec, c, i)

    return nothing
end


### Higher level structures ###

function state_space!(F, x, meas, b::ΣdqzControlTEC, c::MMC) 
    # -- Outer Loop -------------------------------------------------------------------------------
    out_Wtot, i = run_block!(F, x, meas, b.tec, c, 1)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_zscc, i = run_block!(F, x, (meas, out_Wtot), b.zscc, c, i)
    out_ccsc, i = run_block!(F, x, meas, b.ccsc, c, i)

    return merge(out_ccsc, out_zscc)
end

function state_space!(F, x, (meas, sync), b::ΔdqControlGFL, c::MMC)
    # -- Outer Loop -------------------------------------------------------------------------------
    out_active, i = run_block!(F, x, (meas, sync), b.outer_active, c, 1)
    out_reactive, i = run_block!(F, x, meas, b.outer_reactive, c, i)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_occ, _= run_block!(F, x, (meas, sync, (;out_active..., out_reactive...)), b.occ, c, i)

    return out_occ
end

function state_space!(F, x, (meas, sync), b::ΔdqControlGFM, c::MMC)
    # -- Outer Loop -------------------------------------------------------------------------------
    out_reactive, i = run_block!(F, x, meas, b.outer_reactive, c, 1)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_vi, i = run_block!(F, x, (meas, sync, out_reactive), b.vi, c, i)

    out_occ, _= run_block!(F, x, (meas, sync, out_vi), b.occ, c, i)

    return out_occ
end

################## Handling of inputs and outputs ############

function pftoinputs(c::MMC, setpoint::SetPoint) 
    Vm  = setpoint.Vac / c.elec.vAC_base       # Grid side voltage (peak,phase) perunitized by converter-side base voltage (peak,phase) #TODO check why this choice and how it impacts the rest
    v_dc = setpoint.Vdc / c.elec.vDC_base
    p_ac = setpoint.Pac / c.elec.Sbase
    q_ac = - setpoint.Qac / c.elec.Sbase   # TODO check if this minus sign is really needed/relevant
    p_dc = setpoint.Pdc / c.elec.Sbase
    
    vG_d = Vm * cos(setpoint.θac)   # d component of the grid voltage in the grid frame  
    vG_q = -Vm * sin(setpoint.θac)  # q component of the grid voltage in the grid frame

    return (v_dc = v_dc, vG_d = vG_d, vG_q = vG_q), 
        SetpointPU(p_ac, q_ac, p_dc, setpoint.θac)
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
    setpoint::SetPoint=SetPoint(),
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



################## Helper functions ##########################
function run_block!(F, x, inputs, block, conv, idx)
    idx_end = idx + n_states(block) - 1
    out = state_space!(@view(F[idx:idx_end]), x, inputs, block, conv)
    return out, idx_end+1
end