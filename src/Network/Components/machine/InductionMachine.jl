export inductionmachine, InductionMachine, ElectricalIM, MechanicalIM


##### Electrical model ###############333

@doc raw"""
   
    $(TYPEDSIGNATURES)

Electrical subsystem of an induction machine.

The model is formulated in the synchronous dq reference frame using an
inverse-Γ representation. It describes the dynamics of stator currents
and rotor flux linkages and computes the electromagnetic torque supplied
to the mechanical subsystem.

# Parameters

## Base quantities

- `ωn` : electrical base angular frequency (rad/s)
- `p_f` : number of poles
- `Vac_base` : line-to-line RMS voltage base
- `S_base` : power base

## Transformer impedance

- `lt` : transformer inductance
- `rt` : transformer resistance

## Machine parameters

- `l_m` : magnetizing inductance
- `l_sl` : stator leakage inductance
- `r_s` : stator resistance
- `l_rl` : rotor leakage inductance
- `r_r` : rotor resistance

# States

- `i_d` : d-axis stator current
- `i_q` : q-axis stator current
- `Ψ_df` : d-axis rotor flux linkage
- `Ψ_qf` : q-axis rotor flux linkage

# Initial Conditions

The electrical states are initialized from the active and reactive
power setpoint:

```julia
i_d  = 2/3 * p_ac
i_q  = -2/3 * q_ac
Ψ_df = 1.0
Ψ_qf = 0.0
"""
@with_kw struct ElectricalIM <: AbstractStateSpace

    ωn :: Float64 = 100π
    p_f :: Float64 = 2

    # Base values
    Vac_base :: Float64 = 220
    S_base :: Float64 = 1000

    # Transformer
    lt :: Float64 = 0.0
    rt :: Float64 = 0.0

    # Machine
    l_m :: Float64 = 1.66
    l_sl :: Float64 = 0.15
    r_s :: Float64 = 0.0015

    l_rl :: Float64 = 0.165
    r_r :: Float64 = 0.01
end

statenames(::ElectricalIM) = (:i_d,:i_q,:Ψ_df,:Ψ_qf)
initialvalues(::ElectricalIM;setpoint_pu::SetpointPU) = (;i_d=2/3*setpoint_pu.p_ac, i_q=-2/3*setpoint_pu.q_ac, Ψ_df=1.0)



######## Mechanical model #######################3
@doc raw""" 

    $(TYPEDSIGNATURES)
Mechanical subsystem of an induction machine. 

The model describes rotor-speed dynamics driven by the difference between electromagnetic torque and a speed-dependent load torque. 

# Parameters 
- `H` : inertia constant 
- T_0 : Nominal load torque [pu]
- A : nonlinear coefficient
- B: linear coefficient
- C: constant coefficient

```math
\tau_m = T_0 (A \omega_r^m + B \omega_r + C)
```

# Initial conditions
- ω_r = 1.0

"""
@with_kw struct MechanicalIM <: AbstractStateSpace

    H :: Float64 = 4.0 # Inertia of motor


    # Mechanical torque model of form T(ω) = T₀*(A*ωᵐ+B*ω+C)
    T_0 :: Float64 = 0.9

    A :: Float64 = 0.0
    B :: Float64 = 0.0
    C::Float64 = 1.0
    m :: Int = 1

end

statenames(::MechanicalIM) = (:ω_r,)
initialvalues(::MechanicalIM) = (ω_r = 1.0,)

########## Induction Machine #############33
@doc raw"""
    $(TYPEDSIGNATURES)

Dynamic induction machine model composed of an electrical subsystem (`ElectricalIM`) and a mechanical subsystem (`MechanicalIM`). 

The electrical subsystem computes stator-current and rotor-flux dynamics as well as the electromagnetic torque. 
The mechanical subsystem uses this torque to determine rotor-speed dynamics. 

# Components
- `elec::ElectricalIM` : electrical model
- `mech::MechanicalIM` : mechanical model

# States 
The complete state vector consists of 
- `i_d` 
- `i_q` 
- `Ψ_df` 
- `Ψ_qf` 
- `ω_r` 

# Inputs 
- `vd` : d-axis terminal voltage 
- `vq` : q-axis terminal voltage 

# Outputs 
- `id` : d-axis stator current 
- `iq` : q-axis stator current 

# Notes

The external interface uses a dq-lagging convention for voltages and currents, while the internal state-space equations are evaluated using a dq-leading convention. The required sign conversions are handled automatically.

"""


struct InductionMachine <: AbstractStateSpace
    elec::ElectricalIM
    mech::MechanicalIM
end
@doc raw"""
    inductionmachine(; elec=ElectricalIM(),
                        mech=MechanicalIM(),
                        setpoint=Setpoint(),
                        connection=true)

Create an induction machine element.

# Arguments

- `elec` : electrical machine model.
- `mech` : mechanical machine model.
- `setpoint` : operating-point specification used for initialization.
- `connection` : whether the element is connected to the network.

# Returns

An `Element` containing an `InductionMachine` model.

# Example

```julia
im = inductionmachine(
    elec = ElectricalIM(),
    mech = MechanicalIM(T_0 = 0.9))
```   

"""
function inductionmachine(; elec = ElectricalIM(), mech = MechanicalIM(), setpoint = Setpoint(), connection = true)

    indm = InductionMachine(elec,mech)

    return Element(
        input_pins = 3,
        output_pins = 3,
        element_model = indm,
        transformation = true;
        connection,
        setpoint
    )
end

statenames(m::InductionMachine) =
(
    statenames(m.elec)...,
    statenames(m.mech)...
)

initialvalues(m::InductionMachine;setpoint_pu, kwargs...) = merge(initialvalues(m.elec;setpoint_pu), initialvalues(m.mech))

inputnames(::InductionMachine) = (:vd,:vq)
outputnames(::InductionMachine) = (:id,:iq)
function pftoinputs(m::InductionMachine, setpoint::Setpoint)

    Sbase = m.elec.S_base
    Vacbase_LL = m.elec.Vac_base
    Vac_base_phpk = sqrt(2/3)* Vacbase_LL
    v_bus_d = setpoint.Vac*cos(setpoint.θac) / Vac_base_phpk

    v_bus_q = -setpoint.Vac*sin(setpoint.θac) / (Vac_base_phpk) # Inputs are in dq-lagging

    sp = setpoint
    sp_pu = SetpointPU(p_ac = sp.Pac/Sbase, q_ac = sp.Qac/Sbase, θ_ac= sp.θac, v_ac = sp.Vac/Vac_base_phpk)
    return NamedTuple{inputnames(m)}((v_bus_d,v_bus_q)), sp_pu
end

function outputequations!(F,x,inputs,y,m::InductionMachine)

    F[1] = x.i_d #Load convention (implemented like this)
    F[2] = -x.i_q #Load convention, but state-space model with dq-leading, so reverse sign

end


############ State space equations ###########


function state_space!(F, x, v_dq, block::ElectricalIM; indm::InductionMachine)

    # Parameters
    l_s = block.l_m + block.l_sl + block.lt
    l_r = block.l_m + block.l_rl

    l_M = block.l_m^2 / l_r
    l_σ = l_s - l_M

    r_eq = block.r_s + block.rt
    r_R = (block.l_m/l_r)^2 * block.r_r

    # States
    i_d  = x.i_d
    i_q  = x.i_q
    Ψ_df = x.Ψ_df
    Ψ_qf = x.Ψ_qf
    ω_r = x.ω_r

    # Inputs
    v_d, v_q = v_dq

    #Equations
    F[1] = block.ωn/l_σ*(v_d-(r_eq+r_R)*i_d+l_σ*i_q+ω_r*Ψ_qf+r_R/l_M*Ψ_df)
    F[2] = block.ωn/l_σ*(v_q-(r_eq+r_R)*i_q-l_σ*i_d-ω_r*Ψ_df+r_R/l_M*Ψ_qf)
    F[3] = block.ωn*(r_R*i_d-(r_R/l_M)*Ψ_df+(1-ω_r)*Ψ_qf)
    F[4] = block.ωn*(r_R*i_q-(r_R/l_M)*Ψ_qf-(1-ω_r)*Ψ_df)

    # Algebraic variables
    τ_e = Ψ_df*i_q - Ψ_qf*i_d

    return τ_e
end



function state_space!( F, x, τ_e, block::MechanicalIM; indm::InductionMachine)

    # States
    ω_r = x.ω_r

    # Torque equation
    τ_m = block.T_0*(block.A*ω_r^(block.m) + block.B*ω_r + block.C)

    F[1] =  (τ_e - τ_m)/(2*block.H)
end




function state_space!(F, x, inputs,indm::InductionMachine)

    v_dq = (inputs.vd, -inputs.vq) # Transform from dq-lagging to dq-leading
    index = 1

    index_end = index + n_states(indm.elec) - 1

    τ_e = state_space!(@view(F[index:index_end]), x, v_dq, indm.elec; indm)


    index = index_end+1
    index_end = index + n_states(indm.mech) - 1

    state_space!(@view(F[index:index_end]), x, τ_e, indm.mech; indm)
    index = index_end + 1

end

pmtype(elem::Element{<:InductionMachine}) = "im"

function  convert!(data, elem::Element{<:InductionMachine}, ::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)

    ### MAKE BUSES OUT OF THE NODES
    # Find the nodes not connected to the ground
    ac_nodes = make_non_ground_node(elem, bus2nodes) 
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)

    key = comp_elem_interface!(data, elem2comp, comp2elem, elem, "im")

    return convert!(data, elem, PMACDC, key, (ac_bus,), global_dict)
end


function convert!(data, elem::Element{<:InductionMachine}, ::Type{PMACDC}, key, (ac_bus,), global_dict)

    # Check if AC or DC source (second one not implemented)
    # is_three_phase(elem) ? nothing : error("DC sources are currently not implemented")

    
    key_str = string(key)
    data["im"][key_str] = Dict{String, Any}()

    indm = elem.element_model
    elec = indm.elec
    mech = indm.mech
    Sbase = global_dict["S"]
    Vbase = global_dict["V"]
    impscale = ((elec.Vac_base)^2/elec.S_base)/global_dict["Z"]
    # Power flow initial values
    data["im"][key_str]["P_ag"] = mech.T_0
    data["im"][key_str]["Q_ag"] = 0.0
    data["im"][key_str]["status"] = 1
    data["im"][key_str]["im_bus"] = ac_bus

    # Power flow limits (not used in power flow)
    data["im"][key_str]["Pacmin"] = 0.9 * mech.T_0 #/ Sbase
    data["im"][key_str]["Vmmin"] = 0.9 # Should be extended with local_base/global_base but we do not care (not used in PF)
    data["im"][key_str]["Vmmax"] = 1.1
    data["im"][key_str]["Pacmax"] = 1.1 * mech.T_0 #/ Sbase
    data["im"][key_str]["Pacrated"] = mech.T_0 #/ Sbase

    # Power flow elements
    data["im"][key_str]["x_m"] = elec.l_m * impscale # In per unit equal
    data["im"][key_str]["x_rl"] = elec.l_rl * impscale
    data["im"][key_str]["x_sl"] = elec.l_sl * impscale
    data["im"][key_str]["r_r"] = elec.r_r * impscale
    data["im"][key_str]["r_s"] = elec.r_s * impscale

    # Torque parameters
    data["im"][key_str]["torque"] =  Dict{String, Any}()
    data["im"][key_str]["torque"]["T_0"] = mech.T_0 
    data["im"][key_str]["torque"]["A"] = mech.A
    data["im"][key_str]["torque"]["B"] = mech.B
    data["im"][key_str]["torque"]["C"] = mech.C
    data["im"][key_str]["torque"]["m"] = mech.m
   
    return nothing
    
end

function transform(elemresult, busresult, global_dict, elem::Element{<:InductionMachine}, ::Type{PMACDC}, ::Type{PIACDC})
			
    acbusresult = busresult[1]
    Pgen = elemresult["pg"] * global_dict["S"] / 1e6 #MW
    Qgen = elemresult["qg"] * global_dict["S"] / 1e6 #MVAr
    Vm =
        (acbusresult["vm"] *
            global_dict["V"] / 1e3) * sqrt(2) # Convert the LN-RMS voltage coming from the PF to LN-PK
    θ = acbusresult["va"]

    setpoint = Setpoint(Pac=Pgen, Qac=Qgen, θac=θ, Vac=Vm)
    return setpoint
end

##################### SI Scaling ######################################
function SI_scale(elem::Element{<:InductionMachine})
    elec = elem.element_model.elec
    Ybase = elec.S_base / elec.Vac_base^2 
    scale = fill(Ybase,2,2)
    
    return scale
end
