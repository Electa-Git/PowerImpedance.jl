export BuildMMC, ΔdqControlGFL, ΣdqzControlTEC
export CirculatingCurrentSuppressionControl, PControl , QControl, OutputCurrentControl, PLL, NoFilter, TotalEnergyControl, ZeroSequenceCurrentControl

export statenames, inputnames, initialvalues
export state_space!, pftoinputs


#region################## Electrical ################################
struct ElectricalMMC <: AbstractStateSpace
    ## Electrical parameters
    Lₐᵣₘ :: Float64        # arm inductance [pu]
    Rₐᵣₘ :: Float64        # equivalent arm resistance [pu]
    Cₐᵣₘ :: Float64        # capacitance per submodule [pu]
    N :: Int               # number of submodules per arm [-]
    turnsRatio :: Float64  # Turns ratio of the converter transformer, converter side/AC side [-]
end

statenames(::ElectricalMMC) = (:iΔd, :iΔq, :iΣd, :iΣq, :iΣz, :vCΔd, :vCΔq, :vCΔZd, :vCΔZq, :vCΣd, :vCΣq, :vCΣz)
initialvalues(e::ElectricalMMC, inputs) =  (; 
    iΔd = (inputs.Vᴳd * e.turnsRatio * inputs.Pac - inputs.Vᴳq * e.turnsRatio * inputs.Qac) / ( (inputs.Vᴳd * e.turnsRatio)^2 + (inputs.Vᴳq * e.turnsRatio)^2 ),
    iΔq = (inputs.Vᴳq * e.turnsRatio * inputs.Pac + inputs.Vᴳd * e.turnsRatio * inputs.Qac) / ( (inputs.Vᴳd * e.turnsRatio)^2 + (inputs.Vᴳq * e.turnsRatio)^2 ),
    iΣd = inputs.Pdc / (3*inputs.Vdc),
    vCΣz = inputs.Vdc)

#endregion
#region################## Control ###################################

### Abstract types ###
abstract type AbstractSynchronization           <: AbstractStateSpace end
abstract type AbstractMeasurement               <: AbstractStateSpace end
abstract type AbstractΔdqControl                <: AbstractStateSpace end
abstract type AbstractΣdqzControl               <: AbstractStateSpace end

abstract type AbstractOuterActiveControl        <: AbstractStateSpace end
abstract type AbstractOuterReactiveControl      <: AbstractStateSpace end
abstract type AbstractInnerCurrentControl       <: AbstractStateSpace end
abstract type AbstractEnergyControl             <: AbstractStateSpace end

# abstract type AbstractModulationBlock       <: AbstractStateSpace end
# abstract type AbstractDelayBlock            <: AbstractStateSpace end

### Higher level structures ###
#region

@with_kw struct ΔdqControlGFL{A<:AbstractOuterActiveControl, R<:AbstractOuterReactiveControl, I<:AbstractInnerCurrentControl, } <: AbstractΔdqControl 
    outer_active::A
    outer_reactive::R
    occ::I              # Output Current Control
end
statenames(c::ΔdqControlGFL) = (statenames(c.outer_active)..., statenames(c.outer_reactive)..., statenames(c.occ)...)
initialvalues(::ΔdqControlGFL, inputs) =  (;) 

@with_kw struct ΣdqzControlTEC{E<:AbstractEnergyControl, I1<:AbstractInnerCurrentControl, I2<:AbstractInnerCurrentControl} <: AbstractΣdqzControl
    tec::E      # Total Energy Control
    zscc::I1    # Zero-Sequence Current Control
    ccsc::I2    # Circulating Current Suppression Control
end
statenames(c::ΣdqzControlTEC) = (statenames(c.tec)..., statenames(c.zscc)..., statenames(c.circulating_current_suppression)...)
initialvalues(::ΣdqzControlTEC, inputs) =  (;) 
#endregion

### Lower level structures ###
#region

@with_kw struct TotalEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::TotalEnergyControl) = (:ξ_Wtot,)
initialvalues(::TotalEnergyControl, inputs) =  (;) 

struct ZeroSequenceCurrentControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::ZeroSequenceCurrentControl) = (:ξ_iΣz,)
initialvalues(::ZeroSequenceCurrentControl, inputs) =  (;) 

struct CirculatingCurrentSuppressionControl <: AbstractInnerCurrentControl
    pi_control::PIControl
end
statenames(::CirculatingCurrentSuppressionControl) = (:ξ_iΣd, :ξ_iΣq)
initialvalues(::CirculatingCurrentSuppressionControl, inputs) =  (;) 

@with_kw struct PControl <: AbstractOuterActiveControl 
    pi_control::PIControl
    P_ac_ref::Float64 = 0
end
statenames(::PControl ) = (:ξ_P_ac,)
initialvalues(::PControl , inputs) =  (;)

@with_kw struct QControl <: AbstractOuterReactiveControl 
    pi_control::PIControl
    Q_ac_ref::Float64 = 0
end
statenames(::QControl) = (:ξ_Q_ac,)
initialvalues(::QControl, inputs) =  (;) 

struct OutputCurrentControl <: AbstractInnerCurrentControl 
    pi_control::PIControl
end
statenames(::OutputCurrentControl) = (:ξ_iΔd, :ξ_iΔq)
initialvalues(::OutputCurrentControl, inputs) =  (;)

struct PLL <: AbstractSynchronization
    pi_control::PIControl
end
statenames(::PLL) = (:ξ_PLL, :Δθ_PLL) #TODO: add all states (include filtering?)
initialvalues(::PLL, inputs) =  (;)

struct NoFilter <: AbstractMeasurement end
statenames(::NoFilter) = (;)
initialvalues(::NoFilter, inputs) =  (;) 
#endregion

#endregion
#region################## MMC #######################################
@with_kw struct MMC{M<:AbstractMeasurement, S<:AbstractSynchronization, D<:AbstractΔdqControl, Z<:AbstractΣdqzControl} <: AbstractStateSpace
    #### Blocks composing the MMC model:
    electrical_model::ElectricalMMC
    measurements::M
    synchronization::S
    delta_control::D
    sigma_control::Z

    #### Parameters
    ## Base values
    wbase :: Float64           # Base angular frequncy [rad/s]
    vAC_base :: Float64
    vDC_base :: Float64
    Sbase :: Float64

    # Base conversions
    baseConv1 :: Float64
    baseConv2 :: Float64
    baseConv3 :: Float64

    ## Parameters that needs computation 
    # TODO move this to somewhere appropriate
    Lₑ :: Float64
    Rₑ :: Float64 
end

statenames(c::MMC)                      = (statenames(c.measurements)..., statenames(c.synchronization)..., statenames(c.delta_control)..., statenames(c.sigma_control)..., statenames(c.electrical_model)...) 
initialvalues(c::MMC,inputs)            = merge(initialvalues(c.electrical_model, inputs), initialvalues(c.measurements, inputs), initialvalues(c.synchronization, inputs), initialvalues(c.delta_control, inputs), initialvalues(c.sigma_control, inputs))
inputnames(c::MMC)                      = (:Vᴳd, :Vᴳq, :Vdc, :Pac ,:Qac, :Pdc, :θac)
outputnames(c::MMC)                     = (:iΔd, :iΔq, :idc) 
elecinputnames(c::MMC)                  = (:Vᴳd, :Vᴳq, :Vdc)
#endregion
#region################## State-space equations #####################

### Higher level structures ###

function state_space!(F, x, inputs, conv::MMC)
    idx = 1

    # -- Signal Processing ------------------------------------------------------------------------    
    out_measurements, idx = run_block!(F, x, inputs, conv.measurements, conv, idx)
    out_synchronization, idx = run_block!(F, x, inputs, conv.synchronization, conv, idx)
    inputs = merge(inputs, out_measurements, out_synchronization)

    # -- Delta and Sigma control ------------------------------------------------------------------
    out_delta, idx = run_block!(F, x, inputs, conv.delta_control, conv, idx)
    out_sigma, idx = run_block!(F, x, inputs, conv.sigma_control, conv, idx)

    inputs = merge(inputs, out_delta, out_sigma)

    # -- Modulation -------------------------------------------------------------------------------
    # Going back to grid reference frame
    Δθ_c = inputs.Δθ_c
    I_θ = [cos(Δθ_c) sin(Δθ_c); -sin(Δθ_c) cos(Δθ_c)];
    I_2θ = [cos(-2Δθ_c) sin(-2Δθ_c); -sin(-2Δθ_c) cos(-2Δθ_c)];
    vMΔd_ref, vMΔq_ref = I_θ * [inputs.vMΔd_ref_c, inputs.vMΔq_ref_c]
    vMΣd_ref, vMΣq_ref = I_2θ * [inputs.vMΣd_ref_c, inputs.vMΣq_ref_c]

    outputs_control_converted = (vMΔd_ref = vMΔd_ref, vMΔq_ref = vMΔq_ref, vMΔZd_ref = 0, vMΔZq_ref = 0,
        vMΣd_ref = vMΣd_ref, vMΣq_ref = vMΣq_ref, vMΣz_ref = inputs.vMΣz_ref)
    inputs = merge(inputs, outputs_control_converted)

    # -- Electrical model -------------------------------------------------------------------------
    run_block!(F, x, inputs, conv.electrical_model, conv, idx)
    return nothing
end

function state_space!(F, x, inputs, b::ΣdqzControlTEC, conv::MMC) 
    idx = 1

    # -- Outer Loop -------------------------------------------------------------------------------
    out_Wtot, idx = run_block!(F, x, inputs, b.tec, conv, idx)
    inputs = merge(inputs, out_Wtot)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_zscc, idx = run_block!(F, x, inputs, b.zscc, conv, idx)
    out_ccsc, idx = run_block!(F, x, inputs, b.ccsc, conv, idx)

    return merge(out_ccsc, out_zscc)
end

function state_space!(F, x, inputs, b::ΔdqControlGFL, conv::MMC)
    idx = 1
    # -- Outer Loop -------------------------------------------------------------------------------
    out_active, idx = run_block!(F, x, inputs, b.outer_active, conv, idx)
    out_reactive, idx = run_block!(F, x, inputs, b.outer_reactive, conv, idx)
    inputs = merge(inputs, out_active, out_reactive)

    # -- Inner Loop -------------------------------------------------------------------------------
    out_occ, _= run_block!(F, x, inputs, b.occ, conv, idx)

    return merge(out_active, out_reactive, out_occ)
end

### Lower level structures ###

function state_space!(F, x, inputs, b::CirculatingCurrentSuppressionControl, conv::MMC) 
    ξ_iΣd, ξ_iΣq, iΣd, iΣq = get_states(x, :ξ_iΣd, :ξ_iΣq, :iΣd, :iΣq)
    Δθ_c = inputs.Δθ_c
    iΣd_ref, iΣq_ref = 0, 0 # TODO add this as inputs/parameters if needed

    T_2θ = [cos(-2Δθ_c) -sin(-2Δθ_c); sin(-2Δθ_c) cos(-2Δθ_c)];
    iΣd_c, iΣq_c = T_2θ * [iΣd, iΣq]

    F[1] = (b.pi_control.Ki) * (iΣd_ref - iΣd_c)
    F[2] = (b.pi_control.Ki) * (iΣq_ref - iΣq_c)
    # vMΣd_ref = 2/Vdc*(- Ki_Σ * xiΣd - Kp_Σ * (iΣd_ref -  iΣd) + 2*Larm*iΣq)
    # vMΣq_ref = 2/Vdc*(- Ki_Σ * xiΣq - Kp_Σ * (iΣq_ref -  iΣq) - 2*Larm*iΣd)
    # Assuming constant w
    vMΣd_ref_c =2/inputs.Vdc* (- ξ_iΣd -
            b.pi_control.Kp * (iΣd_ref - iΣd_c) + 2 * conv.electrical_model.Lₐᵣₘ * iΣq_c)
    vMΣq_ref_c = 2/inputs.Vdc*(- ξ_iΣq -
            b.pi_control.Kp * (iΣq_ref - iΣq_c) - 2 * conv.electrical_model.Lₐᵣₘ * iΣd_c)

    # Output are in converter reference frame!
    return (vMΣd_ref_c=vMΣd_ref_c, vMΣq_ref_c=vMΣq_ref_c)
end

function state_space!(F, x, inputs, b::ZeroSequenceCurrentControl, conv::MMC)
    ξ_iΣz, iΣz = get_states(x, :ξ_iΣz, :iΣz)
    (;iΣz_ref, Vdc)  = inputs

    F[1] = b.pi_control.Ki * (iΣz_ref - iΣz);
    # vMΣz_ref = 2/Vdc*(Vdc/2 - Kp_Σz*(iΣz_ref - iΣz) - Ki_Σz * xiΣz),
    return ( vMΣz_ref = 2/Vdc*(Vdc/2 - b.pi_control.Kp *(iΣz_ref - iΣz) - ξ_iΣz), )
end

function state_space!(F, x, inputs, b::TotalEnergyControl, conv::MMC)
    ξ_Wtot, vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz = get_states(x, :ξ_Wtot, :vCΔd, :vCΔq, :vCΔZd, :vCΔZq, :vCΣd, :vCΣq, :vCΣz)
    (; P_ac_F, Vdc) = inputs

    # wΣz = (vCΔd^2 + vCΔq^2 + vCΔZd^2 + vCΔZq^2 + vCΣd^2 + vCΣq^2 + 2*vCΣz^2)/(2)
    wΣz = (vCΔd^2 + vCΔq^2 + vCΔZd^2 + vCΔZq^2 + vCΣd^2 + vCΣq^2 + 2vCΣz^2)/2;
    
    F[1] = b.pi_control.Ki * (b.ref - wΣz)
    #iΣz_ref = (Kp_wΣ * (wΣz_ref - wΣz) + Ki_wΣ * xwΣz + Pac_f) / 3 / Vdc,
    return ( (iΣz_ref = (b.pi_control.Kp * (b.ref - wΣz) + ξ_Wtot + P_ac_F) / 3 / Vdc ),)
end

function state_space!(F, x, inputs, b::ElectricalMMC, conv::MMC) 
    
    iΔd, iΔq, iΣd, iΣq, iΣz, vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz = get_states(x, :iΔd, :iΔq, :iΣd, :iΣq, :iΣz, :vCΔd, :vCΔq, :vCΔZd, :vCΔZq, :vCΣd, :vCΣq, :vCΣz)
    (; vMΔd_ref, vMΔq_ref, vMΔZd_ref, vMΔZq_ref, vMΣd_ref, vMΣq_ref, vMΣz_ref) = inputs
    (; Vᴳd, Vᴳq) = inputs

    (mΔd, mΔq, mΔZd, mΔZq, mΣd, mΣq, mΣz) = 1 * [-vMΔd_ref * conv.baseConv1; -vMΔq_ref * conv.baseConv1; -vMΔZd_ref * conv.baseConv1; -vMΔZq_ref * conv.baseConv1; vMΣd_ref; vMΣq_ref; vMΣz_ref];

    vMΔd = conv.baseConv2 * ((mΔq*vCΣq)/4 - (mΔd*vCΣz)/2 - (mΔd*vCΣd)/4 - (mΔZd*vCΣd)/4 + (mΔZq*vCΣq)/4 - (mΣd*vCΔd)/4 - (mΣz*vCΔd)/2 +
            (mΣq*vCΔq)/4 - (mΣd*vCΔZd)/4 + (mΣq*vCΔZq)/4);
    vMΔq = conv.baseConv2 * ((mΔd*vCΣq)/4 + (mΔq*vCΣd)/4 - (mΔq*vCΣz)/2 - (mΔZd*vCΣq)/4 - (mΔZq*vCΣd)/4 + (mΣd*vCΔq)/4 + (mΣq*vCΔd)/4 -
            (mΣz*vCΔq)/2 - (mΣd*vCΔZq)/4 - (mΣq*vCΔZd)/4);

    # vMΣd = (mΔd*vCΔd)/4 - (mΔq*vCΔq)/4 + (mΔd*vCΔZd)/4 + (mΔZd*vCΔd)/4 + (mΔq*vCΔZq)/4 + (mΔZq*vCΔq)/4 + (mΣd*vCΣz)/2 + (mΣz*vCΣd)/2;
    vMΣd =mΔd*vCΔd/4 - mΔq*vCΔq/4 + mΔd*vCΔZd/4 + mΔZd*vCΔd/4 + mΔq*vCΔZq/4 + mΔZq*vCΔq/4 + mΣd*vCΣz/2 + mΣz*vCΣd/2;
    # vMΣq = (mΔq*vCΔZd)/4 - (mΔq*vCΔd)/4 - (mΔd*vCΔZq)/4 - (mΔd*vCΔq)/4 + (mΔZd*vCΔq)/4 - (mΔZq*vCΔd)/4 + (mΣq*vCΣz)/2 + (mΣz*vCΣq)/2;
    vMΣq = mΔq*vCΔZd/4 - mΔq*vCΔd/4 - mΔd*vCΔZq/4 - mΔd*vCΔq/4 + mΔZd*vCΔq/4 - mΔZq*vCΔd/4 + mΣq*vCΣz/2 + mΣz*vCΣq/2;
    # vMΣz = (mΔd*vCΔd)/4 + (mΔq*vCΔq)/4 + (mΔZd*vCΔZd)/4 + (mΔZq*vCΔZq)/4 + (mΣd*vCΣd)/4 + (mΣq*vCΣq)/4 + (mΣz*vCΣz)/2;
    vMΣz = mΔd*vCΔd/4 + mΔq*vCΔq/4 + mΔZd*vCΔZd/4 + mΔZq*vCΔZq/4 + mΣd*vCΣd/4 + mΣq*vCΣq/4 + mΣz*vCΣz/2;
    # diΔd_dt =-(Vᴳd - vMΔd + Rₑ*iΔd + Lₑ*iΔq*w)/Lₑ, grid frame
    F[1] = -(Vᴳd * conv.electrical_model.turnsRatio - vMΔd + conv.Rₑ*iΔd + conv.Lₑ*iΔq)/conv.Lₑ;                 
    # diΔq_dt =-(Vᴳq - vMΔq + Rₑ*iΔq - Lₑ*iΔd*w)/Lₑ, grid frame
    F[2] = -(Vᴳq * conv.electrical_model.turnsRatio - vMΔq + conv.Rₑ*iΔq - conv.Lₑ*iΔd)/conv.Lₑ;                 
    # diΣd_dt =-(vMΣd + Rₐᵣₘ*iΣd - 2*Lₐᵣₘ*iΣq*w)/Lₐᵣₘ, grid 2w frame
    F[3] = -(vMΣd + conv.electrical_model.Rₐᵣₘ*iΣd - 2*conv.electrical_model.Lₐᵣₘ*iΣq)/conv.electrical_model.Lₐᵣₘ;                                 
    # diΣq_dt =-(vMΣq + Rₐᵣₘ*iΣq + 2*Lₐᵣₘ*iΣd*w)/Lₐᵣₘ,  grid 2w frame
    F[4] = -(vMΣq + conv.electrical_model.Rₐᵣₘ*iΣq + 2*conv.electrical_model.Lₐᵣₘ*iΣd)/conv.electrical_model.Lₐᵣₘ;                                  
    # diΣz_dt =-(vMΣz - Vᵈᶜ/2 + Rₐᵣₘ*iΣz)/Lₐᵣₘ
    F[5] = -(vMΣz - inputs.Vdc/2 + conv.electrical_model.Rₐᵣₘ*iΣz)/conv.electrical_model.Lₐᵣₘ;                                     
    # dvCΔd_dt =(N*(iΣz*mΔd - (iΔq*mΣq)/4 + iΣd*(mΔd/2 + mΔZd/2) - iΣq*(mΔq/2 + mΔZq/2) + iΔd*(mΣd/4 + mΣz/2) - (2*Cₐᵣₘ*vCΔq*w)/N))/(2*Cₐᵣₘ)
    F[6] = (conv.electrical_model.N*(iΣz*mΔd - iΔq*conv.baseConv3*mΣq/4 + iΣd*(mΔd/2 + mΔZd/2) - iΣq*(mΔq/2 + mΔZq/2) + iΔd*conv.baseConv3*(mΣd/4 + mΣz/2) - 2*conv.electrical_model.Cₐᵣₘ*vCΔq/conv.electrical_model.N))/2/conv.electrical_model.Cₐᵣₘ;
    # dvCΔq_dt =-(N*((iΔd*mΣq)/4 - iΣz*mΔq + iΣq*(mΔd/2 - mΔZd/2) + iΣd*(mΔq/2 - mΔZq/2) + iΔq*(mΣd/4 - mΣz/2) - (2*Cₐᵣₘ*vCΔd*w)/N))/(2*Cₐᵣₘ)
    F[7] = -(conv.electrical_model.N*((iΔd*conv.baseConv3*mΣq)/4 - iΣz*mΔq + iΣq*(mΔd/2 - mΔZd/2) + iΣd*(mΔq/2 - mΔZq/2) + iΔq*conv.baseConv3*(mΣd/4 - mΣz/2) - 2*conv.electrical_model.Cₐᵣₘ*vCΔd/conv.electrical_model.N))/2/conv.electrical_model.Cₐᵣₘ;
    # dvCΔZd_dt =(N*(iΔd*mΣd + 2*iΣd*mΔd + iΔq*mΣq + 2*iΣq*mΔq + 4*iΣz*mΔZd))/(8*Cₐᵣₘ) - 3*vCΔZq*w
    F[8] = (conv.electrical_model.N*(iΔd*conv.baseConv3*mΣd + 2*iΣd*mΔd + iΔq*conv.baseConv3*mΣq + 2*iΣq*mΔq + 4*iΣz*mΔZd))/(8*conv.electrical_model.Cₐᵣₘ) - 3*vCΔZq;
    # dvCΔZq_dt =3*vCΔZd*w + (N*(iΔq*mΣd - iΔd*mΣq + 2*iΣd*mΔq - 2*iΣq*mΔd + 4*iΣz*mΔZq))/(8*Cₐᵣₘ)
    F[9] = 3*vCΔZd + (conv.electrical_model.N*(iΔq*conv.baseConv3*mΣd - iΔd*conv.baseConv3*mΣq + 2*iΣd*mΔq - 2*iΣq*mΔd + 4*iΣz*mΔZq))/(8*conv.electrical_model.Cₐᵣₘ);
    # dvCΣd_dt =(N*(iΣd*mΣz + iΣz*mΣd + iΔd*(mΔd/4 + mΔZd/4) - iΔq*(mΔq/4 - mΔZq/4) + (4*Cₐᵣₘ*vCΣq*w)/N))/(2*Cₐᵣₘ)
    F[10] = (conv.electrical_model.N*(iΣd*mΣz + iΣz*mΣd + iΔd*conv.baseConv3*(mΔd/4 + mΔZd/4) - iΔq*conv.baseConv3*(mΔq/4 - mΔZq/4) + 4*conv.electrical_model.Cₐᵣₘ*vCΣq/conv.electrical_model.N))/(2*conv.electrical_model.Cₐᵣₘ);
    # dvCΣq_dt =-(N*(iΔq*(mΔd/4 - mΔZd/4) - iΣz*mΣq - iΣq*mΣz + iΔd*(mΔq/4 + mΔZq/4) + (4*Cₐᵣₘ*vCΣd*w)/N))/(2*Cₐᵣₘ)
    F[11] = -(conv.electrical_model.N*(iΔq*conv.baseConv3*(mΔd/4 - mΔZd/4) - iΣz*mΣq - iΣq*mΣz + iΔd*conv.baseConv3*(mΔq/4 + mΔZq/4) + 4*conv.electrical_model.Cₐᵣₘ*vCΣd/conv.electrical_model.N))/(2*conv.electrical_model.Cₐᵣₘ);
    # dvCΣz_dt =(N*(iΔd*mΔd + iΔq*mΔq + 2*iΣd*mΣd + 2*iΣq*mΣq + 4*iΣz*mΣz))/(8*Cₐᵣₘ)
    F[12] = (conv.electrical_model.N*(iΔd*conv.baseConv3*mΔd + iΔq*conv.baseConv3*mΔq + 2*iΣd*mΣd + 2*iΣq*mΣq + 4*iΣz*mΣz))/(8*conv.electrical_model.Cₐᵣₘ);
    F[1:12] *= conv.wbase

end

function state_space!(F, x, inputs, b::PControl , conv::MMC) 
    ## Get state, inputs and parameters
    ξ_P_ac = get_state(:ξ_P_ac, x)
    P_ac_F = inputs.P_ac_F
    P_ac_ref = b.P_ac_ref
    
    ## Differential eq for ξ_P_ac
    F[1] =  b.pi_control.Ki * (P_ac_ref - P_ac_F)
    ## Controller output
    return (iΔd_ref = b.pi_control.Kp * (P_ac_ref - P_ac_F) + ξ_P_ac,)
end

function state_space!(F, x, inputs, b::QControl ,conv::MMC) 
    ξ_Q_ac = get_state(:ξ_Q_ac, x)
    Q_ac_F = inputs.Q_ac_F

    F[1] = b.pi_control.Ki *(b.Q_ac_ref - Q_ac_F)

    return (iΔq_ref= b.pi_control.Kp*(b.Q_ac_ref - Q_ac_F) + ξ_Q_ac,) # named tuple
end

function state_space!(F, x, inputs, b::OutputCurrentControl ,conv::MMC) 
    ξ_iΔd, ξ_iΔq, iΔd, iΔq = get_states(x, :ξ_iΔd, :ξ_iΔq, :iΔd, :iΔq)
    (; iΔd_ref, iΔq_ref, Vᴳd, Vᴳq, Δθ_c) = inputs 

    T_θ = [cos(Δθ_c) -sin(Δθ_c); sin(Δθ_c) cos(Δθ_c)]
    iΔd_c, iΔq_c = T_θ * [iΔd, iΔq]
    Vᴳd_c, Vᴳq_c = T_θ * [Vᴳd; Vᴳq] * conv.electrical_model.turnsRatio


    Vᴳd_fc = Vᴳd_c # if voltage is filtered, change this #TODO
    Vᴳq_fc = Vᴳq_c # if voltage is filtered!

    F[1] = b.pi_control.Ki * (iΔd_ref - iΔd_c)
    F[2] = b.pi_control.Ki * (iΔq_ref - iΔq_c)
    
    # TODO: add omega in these equations! (here, uses approximation w=1)
    # vMΔd_ref = 2/Vdc*(Ki_Δ * xiΔd + Kp_Δ * (iΔd_ref -  iΔd) + Leqac*iΔq + Vᴳd)
    # vMΔq_ref = 2/Vdc*(Ki_Δ * xiΔq + Kp_Δ * (iΔq_ref -  iΔq) - Leqac*iΔd + Vᴳq)
    vMΔd_ref_c = 2/inputs.Vdc*( ξ_iΔd +
                b.pi_control.Kp * (iΔd_ref - iΔd_c) + conv.Lₑ * iΔq_c + 1*Vᴳd_fc);
    vMΔq_ref_c = 2/inputs.Vdc*(ξ_iΔq +
                b.pi_control.Kp * (iΔq_ref - iΔq_c) - conv.Lₑ * iΔd_c + 1*Vᴳq_fc);

    
    # Output are in converter reference frame!
    return (vMΔd_ref_c=vMΔd_ref_c, vMΔq_ref_c=vMΔq_ref_c)
end

function state_space!(F, x, inputs, b::PLL ,conv::MMC)
    ξ_PLL, Δθ_PLL   = get_states(x, :ξ_PLL, :Δθ_PLL)
    Vᴳd, Vᴳq        = inputs.Vᴳd, inputs.Vᴳq

    T_θ_PLL = [cos(Δθ_PLL) -sin(Δθ_PLL); sin(Δθ_PLL) cos(Δθ_PLL)];

    (_, Vᴳq_pll) = T_θ_PLL * [Vᴳd, Vᴳq] * conv.electrical_model.turnsRatio #TODO check if really needed to multiply by turnratio?

    Vᴳq_pll_f = -1*Vᴳq_pll     #TODO implement filter


    Δω = b.pi_control.Kp * Vᴳq_pll_f + ξ_PLL #Delta omega_pll [pu]
    
    F[1] = Vᴳq_pll_f * b.pi_control.Ki
    F[2] = conv.wbase*Δω;
    
    return (;Δθ_c = get_state(:Δθ_PLL, x)) # return the synchronisation angle
end 

function state_space!(F, x, inputs, b::NoFilter ,conv::MMC)
    iΔd, iΔq = get_states(x, :iΔd, :iΔq)

    P_ac = (inputs.Vᴳd * iΔd + inputs.Vᴳq * iΔq) #TODO check if this is ok (it uses values not in conv ref frame!)
    Q_ac =  (-inputs.Vᴳq * iΔd + inputs.Vᴳd * iΔq)
    
    (P_ac_F = P_ac, Q_ac_F = Q_ac)
end

#endregion
#region################## Handling of inputs and outputs ############

function pftoinputs(c::MMC, setpoint::SetPoint) 

    Vm  = setpoint.Vac / c.vAC_base       # Grid side voltage (peak,phase) perunitized by converter-side base voltage (peak,phase) #TODO check why this choice and how it impacts the rest
    Vdc = setpoint.Vdc / c.vDC_base
    Pac = setpoint.Pac / c.Sbase
    Qac = - setpoint.Qac / c.Sbase   # TODO check if this minus sign is really needed/relevant
    Pdc = setpoint.Pdc / c.Sbase
    
    Vᴳd = Vm * cos(setpoint.θac)   # d component of the grid voltage in the grid frame  
    Vᴳq = -Vm * sin(setpoint.θac)  # q component of the grid voltage in the grid frame

    return NamedTuple{inputnames(c)}((Vᴳd, Vᴳq, Vdc, Pac, Qac, Pdc, setpoint.θac))
end


function outputequations!(F, x, inputs, gen::MMC)
    # NB: All electrical state variables are in grid dq frame (and not converter frame)
    iΔd, iΔq, iΣz = get_states(x, :iΔd, :iΔq, :iΣz)
    F[1:3] = iΔd, iΔq, 3*iΣz
end


#endregion
#region################## Contructor ################################

function BuildMMC(;
    elec_params=(
        Lₐᵣₘ = 50e-3,        # arm inductance [H]
        Rₐᵣₘ = 1.07,         # equivalent arm resistance[Ω]
        Cₐᵣₘ = 10e-3,        # capacitance per submodule [F]
        N = 400,             # number of submodules per arm [-]
        turnsRatio  = 1,     # Turns ratio of the converter transformer, converter side/AC side [-]
        Lᵣ = 60e-3,          # inductance of the converter transformer at the converter side [H]
        Rᵣ = 0.535,          # resistance of the converter transformer at the converter side [Ω]
    ),
    base_values=(
        wbase = 100π,
        vACbase_LL_RMS = 380,   # Voltage base LL converter side [kV]
        Sbase = 1000,           # Power base [MW]
        vDC_base = 640,          # DC voltage base [kV])
    ),
    kwargs...)  
    (; Lₐᵣₘ, Rₐᵣₘ, Cₐᵣₘ, N, turnsRatio, Lᵣ, Rᵣ) = elec_params
    (; wbase, vACbase_LL_RMS, Sbase, vDC_base) = base_values


    vAC_base = vACbase_LL_RMS*sqrt(2/3)
    iAC_base = 2*Sbase/3/vAC_base
    iDC_base = Sbase/vDC_base
    zAC_base = (3/2)*vAC_base^2/Sbase
    zDC_base = vDC_base/iDC_base
    lAC_base = zAC_base/wbase
    lDC_base = zDC_base/wbase
    cbase = 1/wbase/zDC_base
    Lₑ = (Lₐᵣₘ / 2 + Lᵣ) / lAC_base
    Rₑ = (Rₐᵣₘ / 2 + Rᵣ) / zAC_base
    Lₐᵣₘ = Lₐᵣₘ / lDC_base
    Rₐᵣₘ = Rₐᵣₘ / zDC_base
    Cₐᵣₘ = Cₐᵣₘ / cbase

    baseConv1 = vAC_base/vDC_base;# AC to DC voltage
    baseConv2 = vDC_base/vAC_base;# DC to AC voltage
    baseConv3 = iAC_base/iDC_base;# AC to DC current

    elec = ElectricalMMC(Lₐᵣₘ, Rₐᵣₘ, Cₐᵣₘ, N, turnsRatio)
    
    return MMC(; electrical_model = elec, 
    wbase=wbase, vAC_base, vDC_base, Sbase,
    Lₑ = Lₑ, Rₑ = Rₑ,  
    baseConv1=baseConv1, baseConv2=baseConv2, baseConv3=baseConv3,
    kwargs...)
end
#endregion
#region################## Helper functions ##########################
function run_block!(F, x, inputs, block, conv, idx)
    idx_end = idx + n_states(block) - 1
    out = state_space!(@view(F[idx:idx_end]), x, inputs, block, conv)
    return out, idx_end+1
end

function get_states(x, labels::Symbol...)
    return map(lbl -> getfield(x, lbl), labels)
end

#endregion
