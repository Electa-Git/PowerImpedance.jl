export inductionmachine, InductionMachine, ElectricalIM, MechanicalIM


##### Electrical model ###############333

"""
$(TYPEDEF)

Represent induction-machine stator-current and rotor-flux dynamics using an inverse-Γ
model in synchronous dq coordinates. Electrical states and circuit parameters use
machine per-unit bases; the internal q axis leads, while the external interface uses a
lagging q axis.

$(TYPEDFIELDS)
"""
@with_kw struct ElectricalIM <: AbstractStateSpace

    "Base electrical angular frequency \\[rad/s\\]."
    ωn :: Float64 = 100π
    "Stored legacy parameter; not used by the current state equations."
    p_f :: Float64 = 2

    # Base values
    "Line-to-line RMS voltage base \\[kV\\]."
    Vac_base :: Float64 = 220
    "Three-phase apparent-power base \\[MVA\\]."
    S_base :: Float64 = 1000

    # Transformer
    "External transformer inductance on the machine base \\[dimensionless\\]."
    lt :: Float64 = 0.0
    "External transformer resistance on the machine base \\[dimensionless\\]."
    rt :: Float64 = 0.0

    # Machine
    "Magnetizing inductance on the machine base \\[dimensionless\\]."
    l_m :: Float64 = 1.66
    "Stator leakage inductance on the machine base \\[dimensionless\\]."
    l_sl :: Float64 = 0.15
    "Stator resistance on the machine base \\[dimensionless\\]."
    r_s :: Float64 = 0.0015

    "Rotor leakage inductance on the machine base \\[dimensionless\\]."
    l_rl :: Float64 = 0.165
    "Rotor resistance on the machine base \\[dimensionless\\]."
    r_r :: Float64 = 0.01
end

statenames(::ElectricalIM) = (:i_d,:i_q,:Ψ_df,:Ψ_qf)
initialvalues(::ElectricalIM;setpoint_pu::SetpointPU) = (;i_d=2/3*setpoint_pu.p_ac, i_q=-2/3*setpoint_pu.q_ac, Ψ_df=1.0)



######## Mechanical model #######################3
"""
$(TYPEDEF)

Represent induction-machine rotor inertia and a polynomial speed-dependent load torque.

$(TYPEDFIELDS)
"""
@with_kw struct MechanicalIM <: AbstractStateSpace

    "Inertia constant \\[s\\]."
    H :: Float64 = 4.0 # Inertia of motor


    # Mechanical torque model of form T(ω) = T₀*(A*ωᵐ+B*ω+C)
    "Load-torque scale on the machine torque base \\[dimensionless\\]."
    T_0 :: Float64 = 0.9

    "Coefficient of the speed-power term in load torque \\[dimensionless\\]."
    A :: Float64 = 0.0
    "Coefficient of the linear speed term in load torque \\[dimensionless\\]."
    B :: Float64 = 0.0
    "Constant load-torque coefficient \\[dimensionless\\]."
    C::Float64 = 1.0
    "Exponent of normalized rotor speed in the load-torque polynomial."
    m :: Int = 1

end

statenames(::MechanicalIM) = (:ω_r,)
initialvalues(::MechanicalIM) = (ω_r = 1.0,)

########## Induction Machine #############33


"""
$(TYPEDEF)

Combine induction-machine electrical and mechanical subsystems. External voltages and
currents use a lagging q axis; state equations use a leading q axis, with sign
conversion at the interface.

$(TYPEDFIELDS)
"""
struct InductionMachine <: AbstractStateSpace
    "Machine electrical subsystem."
    elec::ElectricalIM
    "Machine mechanical subsystem."
    mech::MechanicalIM
end
"""
$(TYPEDSIGNATURES)

Create an induction machine element.

# Arguments

- `elec`: Electrical subsystem and its physical base quantities. Default:
  `ElectricalIM()`.
- `mech`: Mechanical subsystem. Default: `MechanicalIM()`.
- `setpoint`: Physical operating point; powers use \\[MW\\] or \\[MVAr\\], voltages \\[kV\\],
  and angles \\[rad\\]. Default: `Setpoint()`.
- `connection`: Whether the element participates in network construction. Default:
  `true`.

# Returns

- An `Element` containing an `InductionMachine` model.

# Examples

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
"""
$(TYPEDSIGNATURES)

Convert a physical power-flow operating point to normalized external inputs and internal
setpoint data.

# Arguments

- `m`: Induction-machine electrical and mechanical blocks.
- `setpoint`: Physical operating point; powers use \\[MW\\] or \\[MVAr\\], voltages \\[kV\\],
  and angles \\[rad\\].

# Returns

- `inputs`: Named tuple of bus voltages `vd`, `vq`, on machine bases \\[dimensionless\\].
- `setpoint_pu`: Normalized operating point; powers and voltages use \\[dimensionless\\]
  and the angle uses \\[rad\\].

# Notes

```math
v_d=(V/V_b)\\cos\\theta,\\qquad v_q=-(V/V_b)\\sin\\theta.
```

Here ``V`` is the physical AC phase-peak voltage \\[kV\\], ``V_b`` is its base \\[kV\\], and
``\\theta`` is the operating-point angle \\[rad\\]. Powers are divided by the component
power base.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = inductionmachine().element_model
point = Setpoint(Pac=100.0, Qac=0.0, Vac=220sqrt(2/3), θac=0.0, Pdc=100.0, Vdc=640.0)
inputs, point_pu = P.pftoinputs(model, point)
```
"""
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


"""
$(TYPEDSIGNATURES)

Evaluate induction-machine winding dynamics and electromagnetic torque, writing state
derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `v_dq`: d/q bus-voltage pair in internal machine coordinates \\[dimensionless\\].
- `block`: Induction-machine winding parameters.
- `indm`: Induction-machine electrical and mechanical blocks.

# Returns

- Electromagnetic torque on the machine torque base \\[dimensionless\\].

# Notes

```math
L_M=L_m^2/(L_m+L_{rl}),\\quad L_\\sigma=L_m+L_{sl}+L_t-L_M,\\quad R_R=(L_m/(L_m+L_{rl}))^2R_r,\\quad \\tau_e=\\Psi_d i_q-\\Psi_q i_d.
```

The electrical equations use synchronous dq-leading coordinates. Current and rotor-flux
derivatives include stator/rotor loss, synchronous-frame coupling, and slip terms
``1-ω_r``; all electrical quantities use machine bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
point = Setpoint(Pac=100.0, Qac=0.0, Vac=220sqrt(2/3), θac=0.0)
model = inductionmachine(setpoint=point).element_model
inputs, point_pu = P.pftoinputs(model, point)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point_pu)
block = model.elec
F = zeros(P.n_states(block))
P.state_space!(F, x, (inputs.vd, -inputs.vq), block; indm=model)
@assert all(isfinite, F)
```
"""
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



"""
$(TYPEDSIGNATURES)

Evaluate induction-machine rotor-speed dynamics, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `τ_e`: Electromagnetic torque on the machine torque base \\[dimensionless\\].
- `block`: Rotor inertia and load-torque parameters.
- `indm`: Induction-machine electrical and mechanical blocks.

# Returns

- Assigned normalized rotor-speed derivative \\[s⁻¹\\].

# Notes

```math
\\tau_m=T_0(A\\omega_r^m+B\\omega_r+C),\\qquad \\dot\\omega_r=(\\tau_e-\\tau_m)/(2H).
```

Torques and rotor speed use machine bases \\[dimensionless\\]; ``H`` uses \\[s\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
point = Setpoint(Pac=100.0, Qac=0.0, Vac=220sqrt(2/3), θac=0.0)
model = inductionmachine(setpoint=point).element_model
inputs, point_pu = P.pftoinputs(model, point)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point_pu)
block = model.mech
F = zeros(P.n_states(block))
P.state_space!(F, x, 0.1, block; indm=model)
@assert all(isfinite, F)
```
"""
function state_space!( F, x, τ_e, block::MechanicalIM; indm::InductionMachine)

    # States
    ω_r = x.ω_r

    # Torque equation
    τ_m = block.T_0*(block.A*ω_r^(block.m) + block.B*ω_r + block.C)

    F[1] =  (τ_e - τ_m)/(2*block.H)
end




"""
$(TYPEDSIGNATURES)

Evaluate the coupled induction-machine electrical and mechanical dynamics, writing state
derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `indm`: Induction-machine electrical and mechanical blocks.

# Returns

- First unused derivative index after the assembled machine blocks.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
point = Setpoint(Pac=100.0, Qac=0.0, Vac=220sqrt(2/3), θac=0.0)
model = inductionmachine(setpoint=point).element_model
inputs, point_pu = P.pftoinputs(model, point)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point_pu)
F = zeros(P.n_states(model))
P.state_space!(F, x, inputs, model)
@assert all(isfinite, F)
```
"""
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
    # Convert torque from the machine MVA base to the network VA base.
    T_0 = mech.T_0 * elec.S_base * 1e6 / Sbase
    # Power flow initial values
    data["im"][key_str]["P_ag"] = T_0
    data["im"][key_str]["Q_ag"] = 0.0
    data["im"][key_str]["status"] = 1
    data["im"][key_str]["im_bus"] = ac_bus

    # Power flow limits (not used in power flow)
    data["im"][key_str]["Pacmin"] = 0.9 * T_0 #/ Sbase
    data["im"][key_str]["Vmmin"] = 0.9 # Should be extended with local_base/global_base but we do not care (not used in PF)
    data["im"][key_str]["Vmmax"] = 1.1
    data["im"][key_str]["Pacmax"] = 1.1 * T_0 #/ Sbase
    data["im"][key_str]["Pacrated"] = T_0 #/ Sbase

    # Power flow elements
    data["im"][key_str]["x_m"] = elec.l_m * impscale # In per unit equal
    data["im"][key_str]["x_rl"] = elec.l_rl * impscale
    data["im"][key_str]["x_sl"] = (elec.l_sl + elec.lt) * impscale
    data["im"][key_str]["r_r"] = elec.r_r * impscale
    data["im"][key_str]["r_s"] = (elec.r_s + elec.rt) * impscale

    # Torque parameters
    data["im"][key_str]["torque"] =  Dict{String, Any}()
    data["im"][key_str]["torque"]["T_0"] = T_0
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
"""
$(TYPEDSIGNATURES)

Return the factors that convert normalized model admittance to physical terminal
admittance.

# Arguments

- `elem`: Network element containing the component model and operating point.

# Returns

- Matrix of output-current-base to input-voltage-base ratios \\[S\\].

# Notes

```math
Y_{ij}^{SI}=Y_{ij}^{pu}\\frac{I_{b,i}}{V_{b,j}}.
```

The common entry is `S_base/Vac_base²` \\[S\\], using the three-phase power base
in \\[MVA\\] and line-to-line RMS voltage base in \\[kV\\]. These factors are returned
for explicit use; core `eval_y` does not automatically apply them to induction machines.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
element = inductionmachine()
scale = P.SI_scale(element)
```
"""
function SI_scale(elem::Element{<:InductionMachine})
    elec = elem.element_model.elec
    Ybase = elec.S_base / elec.Vac_base^2 
    scale = fill(Ybase,2,2)
    
    return scale
end
