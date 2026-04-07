export mmc, MMC, AbstractMMC, BuildMMC,             # MMC
    ΔdqControlGFL, ΔdqControlGFM, ΣdqzControlTEC,   # High level structures

    NoFilter,                                       # Measurements
    PLL, VSEWithDamping, VSEWithoutDamping,         # Synchronization
    PControl,                                       # Outer active
    QControl,                                       # Outer reactive
    TotalEnergyControl,                             # Energy
    CCVI,                                           # Inner voltage
    CirculatingCurrentSuppressionControl, ZeroSequenceCurrentControl, OutputCurrentControl,     # Inner current
    UncompensatedModulation,                        # Modulation

    statenames, inputnames, initialvalues,          # Functions
    state_space!, pftoinputs

### Abstract types ###
abstract type AbstractMMC                       <: AbstractStateSpace end
abstract type AbstractΔdqControl                <: AbstractStateSpace end
abstract type AbstractΣdqzControl               <: AbstractStateSpace end

### Include files ###
include("electrical.jl")
include("measurement.jl")
include("synchronization.jl")
include("outer_active.jl")
include("outer_reactive.jl")
include("energy.jl")
include("inner_voltage.jl")
include("inner_current.jl")
include("modulation.jl")


################## Structs #####################

### Higher level structures ###

@with_kw struct ΔdqControlGFL{A<:AbstractOuterActiveControl, R<:AbstractOuterReactiveControl, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    outer_active::A
    outer_reactive::R
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFL) = (statenames(c.outer_active)..., statenames(c.outer_reactive)..., statenames(c.occ)...)
initialvalues(c::ΔdqControlGFL, inputs) = merge(initialvalues(c.outer_active, inputs),initialvalues(c.outer_reactive, inputs), initialvalues(c.occ, inputs)) 

@with_kw struct ΔdqControlGFM{R<:AbstractOuterReactiveControl, V<:AbstractVirtualImpedance, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    outer_reactive::R
    vi::V               # Virtual Impedance
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFM) = (statenames(c.outer_reactive)..., statenames(c.vi)..., statenames(c.occ)...)
initialvalues(c::ΔdqControlGFM, inputs) = merge(initialvalues(c.outer_reactive, inputs),initialvalues(c.vi, inputs), initialvalues(c.occ, inputs)) 

# TODO: fix this (these functions shouldn't exist)
out_q_control(::ΔdqControlGFL, out) = (; iΔq_ref = out)
out_q_control(::ΔdqControlGFM, out) = (; Vⱽd_ref = out)

@with_kw struct ΣdqzControlTEC{E<:AbstractEnergyControl, I1<:AbstractInnerCurrentControl, I2<:AbstractInnerCurrentControl} <: AbstractΣdqzControl
    tec::E      # Total Energy Control
    zscc::I1    # Zero-Sequence Current Control
    ccsc::I2    # Circulating Current Suppression Control
end
statenames(c::ΣdqzControlTEC) = (statenames(c.tec)..., statenames(c.zscc)..., statenames(c.ccsc)...)
initialvalues(c::ΣdqzControlTEC, inputs) = merge(initialvalues(c.tec, inputs),initialvalues(c.zscc, inputs), initialvalues(c.ccsc, inputs)) 

### MMC ###
@with_kw struct MMC{Meas<:AbstractMeasurement, S<:AbstractSynchronization, Δ<:AbstractΔdqControl, Σ<:AbstractΣdqzControl, Mod<:AbstractModulationMMC} <: AbstractMMC
    #### Blocks composing the MMC model:
    measurements::Meas
    synchronization::S
    delta_control::Δ
    sigma_control::Σ
    modulation::Mod                      
    elec::ElectricalMMC
end

statenames(c::MMC)                      = (statenames(c.measurements)..., statenames(c.synchronization)..., statenames(c.delta_control)..., statenames(c.sigma_control)..., statenames(c.elec)...) 
initialvalues(c::MMC;inputs, kwargs...) = merge(initialvalues(c.measurements, inputs), initialvalues(c.synchronization, inputs), initialvalues(c.delta_control, inputs), initialvalues(c.sigma_control, inputs), initialvalues(c.elec, inputs))
inputnames(::MMC)                      = (:Vdc, :Vᴳd, :Vᴳq, :Pac ,:Qac, :Pdc, :θac)
outputnames(::MMC)                     = (:idc, :iΔd, :iΔq) 
elecinputnames(::MMC)                  = (:Vdc, :Vᴳd, :Vᴳq)


################## State-space equations #####################

### MMC ###

function state_space!(F, x, inputs, conv::MMC)
    # -- Signal Processing ------------------------------------------------------------------------    
    out_measurements, i = run_block!(F, x, inputs, conv.measurements, conv, 1)
    inputs = merge(inputs, out_measurements)
    out_synchronization, i = run_block!(F, x, inputs, conv.synchronization, conv, i)
    inputs = merge(inputs, out_synchronization)

    # -- Delta and Sigma control ------------------------------------------------------------------
    out_delta, i = run_block!(F, x, inputs, conv.delta_control, conv, i)
    out_sigma, i = run_block!(F, x, inputs, conv.sigma_control, conv, i)

    inputs = merge(inputs, out_delta, out_sigma)

    # -- Modulation -------------------------------------------------------------------------------
    # Going back to grid reference frame
    out_modulation, _ = run_block!(F, x, inputs, conv.modulation, conv, i)
    inputs = merge(inputs, out_modulation)

    # -- Electrical model -------------------------------------------------------------------------
    run_block!(F, x, inputs, conv.elec, conv, i)

    return nothing
end


### Higher level structures ###

function state_space!(F, x, inputs, b::ΣdqzControlTEC, conv::MMC) 
    # -- Outer Loop -------------------------------------------------------------------------------
    out_Wtot, i = run_block!(F, x, inputs, b.tec, conv, 1)
    inputs = merge(inputs, out_Wtot)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_zscc, i = run_block!(F, x, inputs, b.zscc, conv, i)
    out_ccsc, i = run_block!(F, x, inputs, b.ccsc, conv, i)

    return merge(out_ccsc, out_zscc)
end

function state_space!(F, x, inputs, b::ΔdqControlGFL, conv::MMC)
    # -- Outer Loop -------------------------------------------------------------------------------
    out_active, i = run_block!(F, x, inputs, b.outer_active, conv, 1)
    out_reactive, i = run_block!(F, x, inputs, b.outer_reactive, conv, i)
    inputs = merge(inputs, out_active, out_reactive)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_occ, _= run_block!(F, x, inputs, b.occ, conv, i)

    return out_occ
end

function state_space!(F, x, inputs, b::ΔdqControlGFM, conv::MMC)
    # -- Outer Loop -------------------------------------------------------------------------------
    out_reactive, i = run_block!(F, x, inputs, b.outer_reactive, conv, 1)
    inputs = merge(inputs, out_reactive)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_vi, i = run_block!(F, x, inputs, b.vi, conv, i)
    inputs = merge(inputs, out_vi)
    out_occ, _= run_block!(F, x, inputs, b.occ, conv, i)

    return out_occ
end

################## Handling of inputs and outputs ############

function pftoinputs(c::MMC, setpoint::SetPoint) 
    Vm  = setpoint.Vac / c.elec.vAC_base       # Grid side voltage (peak,phase) perunitized by converter-side base voltage (peak,phase) #TODO check why this choice and how it impacts the rest
    Vdc = setpoint.Vdc / c.elec.vDC_base
    Pac = setpoint.Pac / c.elec.Sbase
    Qac = - setpoint.Qac / c.elec.Sbase   # TODO check if this minus sign is really needed/relevant
    Pdc = setpoint.Pdc / c.elec.Sbase
    
    Vᴳd = Vm * cos(setpoint.θac)   # d component of the grid voltage in the grid frame  
    Vᴳq = -Vm * sin(setpoint.θac)  # q component of the grid voltage in the grid frame

    return NamedTuple{inputnames(c)}((Vdc, Vᴳd, Vᴳq, Pac, Qac, Pdc, setpoint.θac))
end


function outputequations!(F, x, y, inputs, c::MMC)
    # NB: All electrical state variables are in grid dq frame (and not converter frame)
    iΣz, iΔd, iΔq  = get_states(x, :iΣz, :iΔd, :iΔq)
    F[1:3] = [3*iΣz, iΔd, iΔq]
end


################## Contructor ################################

function mmc(;
    elec::ElectricalMMC = ElectricalMMC(),
    measurements::AbstractMeasurement = NoFilter(),
    synchronization::AbstractSynchronization,
    delta_control::AbstractΔdqControl,
    sigma_control::AbstractΣdqzControl,
    modulation::AbstractModulationMMC = UncompensatedModulation(),
    setpoint::SetPoint=SetPoint(),
    connection::Bool = true)

    return Element(input_pins = 1, 
        output_pins = 2, 
        element_model = MMC(measurements, synchronization, delta_control, sigma_control, modulation, elec), 
        transformation = false; 
        connection, setpoint)
end



################## Helper functions ##########################
function run_block!(F, x, inputs, block, conv, idx)
    idx_end = idx + n_states(block) - 1
    out = state_space!(@view(F[idx:idx_end]), x, inputs, block, conv)
    return out, idx_end+1
end

function get_states(x, labels::Symbol...)
    return map(lbl -> getfield(x, lbl), labels)
end