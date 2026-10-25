export synchronousmachine, ElectricalSM, MechanicalSM, AVRSM, GovernorSM, SynchronousMachine
#  using SciMLLogging #Debug
### Abstract synchronous machine type (allow for other structures in future, subtype of Machine is this necessary)
"""
$(TYPEDEF)

Define the interface for synchronous-machine models derived from `Machine`.
"""
abstract type AbstractSynchronousMachine <: Machine end




################# ELECTRICAL #################################

"""
$(TYPEDEF)

Store the modified Kundur synchronous-machine circuit parameters, including field and
damper windings and an external RL branch. Circuit parameters use the machine per-unit
bases.

$(TYPEDFIELDS)
"""
@with_kw struct ElectricalSM <: AbstractStateSpace

    # eq::EquationInfo = electricalsmeq()

    "Base electrical angular frequency \\[rad/s\\]."
    ωn :: Float64 = 100*π
    
    # Base values
    "Line-to-line RMS voltage base \\[kV\\]."
    Vᵃᶜ_base :: Float64 = 220 # Converter AC voltage base, LL, RMS [kV]
    "Three-phase apparent-power base \\[MVA\\]."
    S_base :: Float64 = 1000 # Converter AC voltage base, LL, RMS [kV]

    
   

    # Transformer (RL-branch model)
    "External transformer inductance on the machine base \\[dimensionless\\]."
    lt :: Float64 = 0.065 # [pu]
    "External transformer resistance on the machine base \\[dimensionless\\]."
    rt :: Float64 = 0.0026 # [pu]

    # Modified Kundur's example
    "d-axis magnetizing inductance on the machine base \\[dimensionless\\]."
    La_d :: Float64 = 1.66 # d-axis magnetizing inductance
    "q-axis magnetizing inductance on the machine base \\[dimensionless\\]."
    La_q :: Float64 = 1.61 # q-axis magnetizing inductance
    "Stator leakage inductance on the machine base \\[dimensionless\\]."
    Ll :: Float64 = 0.15    # Stator leakage inductance
    "Armature resistance on the machine base \\[dimensionless\\]."
    Ra :: Float64 = 0.0015  # Armature resistance

    "Field leakage inductance on the machine base \\[dimensionless\\]."
    Lf_d :: Float64 = 0.165  # Field leakage inductance
    "d-axis damper leakage inductance on the machine base \\[dimensionless\\]."
    L1_d :: Float64 = 0.1713 # d-axis damper winding inductance
    "First q-axis damper leakage inductance on the machine base \\[dimensionless\\]."
    L1_q :: Float64 = 0.7252 # q-axis first damper winding inductance
    "Second q-axis damper leakage inductance on the machine base \\[dimensionless\\]."
    L2_q :: Float64 = 0.125  # q-axis second damper winding inductance

    # No mutual inductance
    "d-axis field-to-damper mutual inductance on the machine base \\[dimensionless\\]."
    L23_d :: Float64 = 0 # d-axis field-damper mutual inductance
    "Stored q-axis mutual-inductance parameter on the machine base, unused by the implemented equations \\[dimensionless\\]."
    L23_q :: Float64 = 0 # q-axis damper-damper mutual inductance

    "Field resistance on the machine base \\[dimensionless\\]."
    Rf_d :: Float64 = 0.0002 # Field circuit resistance
    "d-axis damper resistance on the machine base \\[dimensionless\\]."
    R1_d :: Float64 = 0.0200 # d-axis damper winding resistance
    "First q-axis damper resistance on the machine base \\[dimensionless\\]."
    R1_q :: Float64 = 0.0050 # q-axis first damper winding resistance
    "Second q-axis damper resistance on the machine base \\[dimensionless\\]."
    R2_q :: Float64 = 0.0100 # q-axis second damper winding resistance
end

statenames(::ElectricalSM) = (:i_d, :i_df, :i_d1, :i_q, :i_q1,:i_q2)
initialvalues(::ElectricalSM) =  (;) # No non-zero states



############################# MECHANICAL #######################################

"""
$(TYPEDEF)

Store synchronous-machine inertia and the steam-turbine time constants and torque
fractions.

$(TYPEDFIELDS)
"""
@with_kw struct MechanicalSM <: AbstractStateSpace
    
    #eq::EquationInfo{}=mechsmeq()
    # init::IntialStates1{(:ω_pu, :θ_sg),2}
    "Inertia constant \\[s\\]."
    H :: Float64 = 4 # Inertia constant [s]
    # Steam turbine
    "Steam-chest time constant \\[s\\]."
    T_CH :: Float64 = 2 # Steam chest time constant [s]
    "Reheater time constant \\[s\\]."
    T_RH :: Float64 = 5 # Reheater time constant [s]
    "Crossover time constant \\[s\\]."
    T_CO :: Float64 = 1 # Cross-over time constant [s]
    "High-pressure turbine torque fraction \\[dimensionless\\]."
    F_HP :: Float64 = 0.3 # High presure turbine fraction [pu]
    "Intermediate-pressure turbine torque fraction \\[dimensionless\\]."
    F_IP :: Float64 = 0.4 # Intermediate presure turbine fraction [pu]
    "Low-pressure turbine torque fraction \\[dimensionless\\]."
    F_LP :: Float64 = 0.3 # Low presure turbine fraction [pu]

end
statenames(::MechanicalSM) = (:ω_pu,:θ_sg)
initialvalues(::MechanicalSM) =  (ω_pu=1.0,)



################# GOVERNOR ######################


"""
$(TYPEDEF)

Store speed-measurement lag, governor servo time constant, and frequency droop.

$(TYPEDFIELDS)
"""
@with_kw struct GovernorSM <: AbstractStateSpace
    "Speed-measurement lag time constant \\[s\\]."
    T_w :: Float64 = 0.1 # Speed lag time constant [s]
    "Governor servo time constant \\[s\\]."
    T_G :: Float64 = 0.2 # Time constant of the governor [s]
    "Normalized frequency-to-power droop \\[dimensionless\\]."
    R :: Float64 = 0.05   # Frequency control droop / Inverse of the gain [pu/pu]
end

statenames(::GovernorSM) = (:δω_filt, :flow, :TchHP, :TreIP, :TcrLP)
initialvalues(::GovernorSM;inputs) =  NamedTuple{(:flow, :TchHP, :TreIP, :TcrLP)}(ntuple(i -> inputs.Tm0, 4)) #Initalize those to same value



########################### AVR #############################

const _AVR_VOLTAGE_INPUT =
    Input(1.01; unit = "pu", description = "AVR voltage reference")

"""
$(TYPEDEF)

Regulate synchronous-machine terminal voltage with a measurement filter,
lead-lag compensator and exciter lag.

$(TYPEDFIELDS)

# Notes

At equilibrium, the open-circuit field voltage is

```math
E_f = K_A(v_{ref} - |V_t|),
```

where ``E_f`` denotes field voltage, ``V_t`` terminal voltage and ``v_{ref}``
its reference in \\[dimensionless\\]. The regulator gain is ``K_A``.
A complete machine power-flow point sets the fixed effective reference to
``v_{ref} = |V_{t,pf}| + E_{f,pf}/K_A`` and requires nonzero `K_A`.
The configured `v_ref` field remains unchanged. Without a complete operating
point, the standalone AVR and machine use `v_ref` without reference conversion
or phasor initialization.
"""
@with_kw struct AVRSM <: AbstractStateSpace
    "Configured terminal-voltage reference \\[dimensionless\\], superseded by the effective reference at a power-flow operating point."
    v_ref :: Float64 = _AVR_VOLTAGE_INPUT.default
    "Terminal-voltage measurement-filter time constant \\[s\\]."
    T_R :: Float64       = 0.05     # Terminal voltage filter time constant [s]
    "Lead-lag denominator time constant \\[s\\]."
    T_B :: Float64       = 1.0       # Lag time constant [s]
    "Lead-lag numerator time constant \\[s\\]."
    T_C :: Float64       = 0.1        # Lead time constant [s]
    "Exciter-lag time constant \\[s\\]."
    T_A :: Float64       = 0.02    # Regulator (lag) time constant [s]
    "Regulator gain \\[dimensionless\\]."
    K_A :: Float64       = 200      # Regulator gain [pu]
end

statenames(::AVRSM) = (:v_f, :ξ_AVR, :v_df)
initialvalues(::AVRSM) =  (;)



################### SYNCHRONOUS MACHINE ######################
"""
$(TYPEDEF)

Represent a synchronous machine in the dq frame with modified Kundur
electrical equations, steam turbine, governor, lead-lag AVR, and exciter.
Electrical quantities use the three-phase `S_base` \\[MVA\\] and
line-to-line RMS `Vᵃᶜ_base` \\[kV\\] bases.

$(TYPEDFIELDS)

# Notes

For a complete power-flow point, `Pac` and `Qac` are generator-terminal powers
\\[MW\\] and \\[MVAr\\], while phase-peak `Vac` \\[kV\\] and `θac` \\[rad\\]
describe the receiving bus after the external `rt`/`lt` branch.
At synchronous speed, fixed references include armature loss and field excitation:

```math
T_{m0} = p_{pf} + R_a |I_{pf}|^2, \\qquad
v_{ref} = |V_{t,pf}| + E_{f,pf}/K_A.
```

Here ``p_{pf}`` denotes terminal active power, ``R_a`` armature resistance
and ``I_{pf}`` terminal current, on machine pu bases. Terminal voltage
``V_{t,pf}`` and field voltage ``E_{f,pf}`` also use machine pu bases.
The AVR gain is ``K_A``.
The effective reference replaces `avr.v_ref` in the equations while the
configured field remains unchanged. Initial states use the power-flow phasors
and the high-voltage solution of the external branch. Turbine fractions must
sum to one for `Tm0` to equal total turbine torque. References remain fixed
during linearization.

Without a complete operating point, the AVR uses `avr.v_ref` and turbine
torque is `Tm0 = Pac/S_base`. Initial states use synchronous-speed and governor
seeds without phasor initialization. A complete setpoint supplied to `pftoinputs`
gives the same reference conversion as a solver-provided point. Construction
alone leaves references
unchanged and requires a separate power-flow solve.

The PSCAD admittance comparison has aggregate error below 1%, with the
largest differences at low frequencies.
"""
@with_kw struct SynchronousMachine <: AbstractStateSpace
    "Machine electrical subsystem."
    elec::ElectricalSM
    "Machine mechanical subsystem."
    mech::MechanicalSM
    "Automatic voltage regulator and exciter."
    avr::AVRSM
    "Governor and steam-turbine dynamics."
    gov::GovernorSM
    "Operating limits in \\[MW\\] and \\[MVAr\\]."
    limits::Limits
    "Power-flow seeds on machine bases \\[dimensionless\\]."
    powerflow::NamedTuple
    "Retained terminal values, converged state and linearization matrices."
    cache::LinearizationCache = LinearizationCache()
end

statenames(m::SynchronousMachine) = (statenames(m.elec)..., statenames(m.mech)...,statenames(m.gov)...,statenames(m.avr)...)
function initialvalues(m::SynchronousMachine; inputs, terminal_pu=nothing, kwargs...)
    terminal_pu === nothing && return merge(initialvalues(m.elec),
        initialvalues(m.mech), initialvalues(m.gov; inputs), initialvalues(m.avr))
    return _machine_powerflow_state(m, terminal_pu).state
end
inputnames(m::SynchronousMachine) = (:vd, :vq, :Tm0, :vref_SG)
outputnames(m::SynchronousMachine) = (:id, :iq)
elecinputnames(m::SynchronousMachine) = (:vd, :vq)

# Reconstruct the terminal operating point from receiving-bus voltage and
# terminal power. The larger |Vt|² root is the normal high-voltage branch.
function _machine_powerflow_state(m::SynchronousMachine, sp::TerminalValuesPU)
    e = m.elec
    Vbus = sp.v_ac * cis(sp.θ_ac)
    Sterminal = complex(sp.p_ac, sp.q_ac)
    z = complex(e.rt, e.lt)
    a = abs2(Vbus) + 2real(conj(z) * Sterminal)
    vt2 = (a + sqrt(a^2 - 4abs2(z) * abs2(Sterminal))) / 2
    i2 = abs2(Sterminal) / vt2
    I = conj((Sterminal - z * i2) / Vbus)
    Vterminal = Vbus + z * I

    # The machine dq frame conjugates the physical phasors.
    internal_voltage = conj(Vbus + complex(e.Ra + e.rt,
        e.La_q + e.Ll + e.lt) * I)
    θ_sg = -π / 2 - angle(internal_voltage)
    i_rotor = cis(θ_sg) * conj(I)
    v_rotor = cis(θ_sg) * conj(Vbus)
    i_d, i_q = real(i_rotor), imag(i_rotor)
    i_df = (-imag(v_rotor) - (e.Ra + e.rt) * i_q +
        (e.La_d + e.Ll + e.lt) * i_d) / e.La_d
    Ef = e.La_d * i_df
    Tm0 = sp.p_ac + e.Ra * i2
    v_f = abs(Vterminal)
    ξ_AVR = Ef / m.avr.K_A
    state = (; i_d, i_df, i_d1=0.0, i_q, i_q1=0.0, i_q2=0.0,
        ω_pu=1.0, θ_sg, δω_filt=0.0, flow=Tm0, TchHP=Tm0,
        TreIP=Tm0, TcrLP=Tm0, v_f, ξ_AVR, v_df=e.Rf_d * i_df)
    return (; state, Tm0, vref_SG=v_f + ξ_AVR)
end

"""
$(TYPEDSIGNATURES)

Convert physical terminal values to normalized external inputs and internal
terminal data.
Port powers are positive into the machine. Delivering 900 MW gives `ac.p = -900`.

# Arguments

- `m`: Synchronous-machine electrical, mechanical, governor, and AVR blocks.
- `values`: NamedTuple with an `ac` port value in
  \\[kV\\], \\[rad\\], \\[MW\\] and \\[MVAr\\].

# Returns

- `inputs`: Named tuple of bus voltages `vd`, `vq`, fixed turbine torque `Tm0`, and
  effective AVR reference `vref_SG`, on machine bases \\[dimensionless\\].
- `terminal_pu`: Normalized operating point; powers and voltages use \\[dimensionless\\]
  and the angle uses \\[rad\\]. Returns `nothing` when `values.ac.q` is `NaN`.

# Notes

```math
v_d=(V/V_b)\\cos\\theta,\\qquad v_q=-(V/V_b)\\sin\\theta.
```

Here ``V`` is the physical AC phase-peak voltage \\[kV\\], ``V_b`` is its base \\[kV\\], and
``\\theta`` is the operating-point angle \\[rad\\]. Powers are divided by the component
power base after negation. A complete operating point determines fixed turbine and AVR
references from the terminal power-flow solution; otherwise `Tm0=-values.ac.p/S_base`
and the configured AVR reference is retained.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = synchronousmachine()
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
inputs, point_pu = P.pftoinputs(model, values)
```
"""
function pftoinputs(m::SynchronousMachine, values::NamedTuple)
    v_bus_d = values.ac.v * cos(values.ac.theta) / (m.elec.Vᵃᶜ_base * sqrt(2/3))
    v_bus_q = -values.ac.v * sin(values.ac.theta) / (m.elec.Vᵃᶜ_base * sqrt(2/3))
    p_ac = -values.ac.p / m.elec.S_base
    if isnan(values.ac.q)
        return (; vd=v_bus_d, vq=v_bus_q, Tm0=p_ac,
            vref_SG=m.avr.v_ref), nothing
    end
    sp = TerminalValuesPU(p_ac=p_ac, q_ac=-values.ac.q / m.elec.S_base,
        θ_ac=values.ac.theta, v_ac=values.ac.v / (m.elec.Vᵃᶜ_base * sqrt(2/3)))
    point = _machine_powerflow_state(m, sp)
    return (; vd=v_bus_d, vq=v_bus_q, Tm0=point.Tm0,
        vref_SG=point.vref_SG), sp
end

function outputequations!(F, x, inputs, y, gen::SynchronousMachine)
    
    theta_grid = 0; # The angle of the global dq reference frame TODO: Check if this is correct
    d = get_state(:θ_sg, x) - theta_grid; # New reference frame angle - old RF angle
    T_inv = [cos(d) sin(d);
        -sin(d)  cos(d)]; # Rotation to stator's RF
    F[1:2] = -T_inv* [x.i_d;x.i_q] #Grid ref frame currentst
end


#################### STATE SPACE EQUATIONS ###############################

"""
$(TYPEDSIGNATURES)

Evaluate synchronous-machine winding dynamics and electromagnetic torque, writing state
derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `v_dq`: d/q bus-voltage pair in internal machine coordinates \\[dimensionless\\].
- `block`: Synchronous-machine winding parameters.
- `gen`: Synchronous-machine electrical, mechanical, governor, and AVR blocks.

# Returns

- `Te`: Electromagnetic torque on the machine base \\[dimensionless\\].
- `didq_dt`: Tuple of d/q current time derivatives on the machine current base \\[s⁻¹\\].

# Notes

```math
L_D\\dot{\\mathbf i}_D=\\mathbf r_D,\\quad L_Q\\dot{\\mathbf i}_Q=\\mathbf r_Q,\\quad T_e=-(\\Psi_d i_q-\\Psi_q i_d).
```

The assembled d/q inductance matrices contain stator, field, and damper couplings.
Right-hand sides include winding resistive drops and speed-induced flux voltages, scaled
by the electrical base angular frequency \\[rad/s\\]. Currents, fluxes, and torque use
machine bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
model = synchronousmachine()
inputs, point_pu = P.pftoinputs(model, values)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point_pu)
block = model.elec
F = zeros(P.n_states(block))
P.state_space!(F, x, (inputs.vd, inputs.vq), block; gen=model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, v_dq, block::ElectricalSM; gen::SynchronousMachine)
    Ld = block.La_d + block.Ll + block.lt
    Lf1_d = block.La_d + block.L23_d
    Lff_d = Lf1_d + block.Lf_d
    L11_d = Lf1_d + block.L1_d

    Lq  = block.La_q + block.Ll + block.lt
    L11_q  = block.L1_q + block.La_q
    L22_q  = block.L2_q + block.La_q

    i_d         = get_state(:i_d, x)      # d-axis stator current
    i_df        = get_state(:i_df, x)        # Field current
    i_d1        = get_state(:i_d1, x)      # d-axis damping winding current

    i_q         = get_state(:i_q, x)         # q-axis stator current
    i_q1        = get_state(:i_q1, x)       # q-axis 1st damping winding current
    i_q2        = get_state(:i_q2, x)       # q-axis 2nd damping winding current
    v_df        = get_state(:v_df, x)

    v_d = v_dq[1]
    v_q = v_dq[2]

    L_D = [-Ld       block.La_d   block.La_d; 
            -block.La_d   Lff_d      Lf1_d;
            -block.La_d   Lf1_d      L11_d];

    L_Q = [-Lq       block.La_q    block.La_q; 
        -block.La_q   L11_q       block.La_q;
        -block.La_q   block.La_q    L22_q];

    Ψ_d = - Ld*i_d + block.La_d*(i_df + i_d1); # d-axis flux
    Ψ_q = - Lq*i_q + block.La_q*(i_q1 + i_q2); # q-axis flux

    Te = -(Ψ_d*i_q - Ψ_q*i_d); # Generator operation electrical torque n_ppoles*w_m = w_e
    # z = merge(z, (;Te))
    
    w_pu = get_state(:ω_pu, x)

    RHS_D = block.ωn*[(v_d  +	(block.Ra+block.rt)*i_d	- w_pu*Ψ_q);
                    (v_df -	block.Rf_d*i_df)
                    (0    - block.R1_d*i_d1)]

    RHS_Q = block.ωn*[(v_q  +  (block.Ra+block.rt)*i_q + w_pu*Ψ_d)
                (0    -  block.R1_q*i_q1)
                (0    -  block.R2_q*i_q2)]

    F[1:3] = L_D \ RHS_D # Tests show that this is faster than precomputing inverse lol
    F[4:6] = L_Q \ RHS_Q

    didq_dt = (F[1], F[4])

    # z = merge(z, (did_dt=F[1], diq_dt=F[4])) # Necessary for AVR
    
    return Te, didq_dt
end

"""
$(TYPEDSIGNATURES)

Evaluate synchronous-machine rotor-speed and angle dynamics, writing state derivatives
into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `Te`: Electromagnetic torque on the machine torque base \\[dimensionless\\].
- `block`: Rotor inertia and turbine torque fractions.
- `gen`: Synchronous-machine electrical, mechanical, governor, and AVR blocks.

# Returns

- Assigned rotor-angle derivative \\[rad/s\\].

# Notes

```math
T_t=F_{HP}T_{HP}+F_{IP}T_{IP}+F_{LP}T_{LP},\\quad \\dot\\omega=(T_t-T_e)/(2H),\\quad \\dot\\theta=\\omega_n(\\omega-1).
```

Torques and speed use machine bases \\[dimensionless\\]; inertia uses \\[s\\] and rotor
angle \\[rad\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
model = synchronousmachine()
inputs, point_pu = P.pftoinputs(model, values)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point_pu)
block = model.mech
F = zeros(P.n_states(block))
P.state_space!(F, x, inputs.Tm0, block; gen=model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, Te, block::MechanicalSM; gen::SynchronousMachine)
    
    TchHP       = get_state(:TchHP, x)         # Steam chest HP torque [pu]
    TreIP       = get_state(:TreIP, x)         # Reheater IP torque [pu]
    TcrLP       = get_state(:TcrLP, x)         # Crossover LP torque [pu]
    w_pu        = get_state(:ω_pu, x)
    # Te          = z.Te               # Electrical torque [pu]
    

    T_turb = block.F_HP*TchHP + block.F_IP*TreIP + block.F_LP*TcrLP
    
    F[1] = (T_turb - Te)/(2*block.H)   # Newton's II Law
    F[2] = gen.elec.ωn*(w_pu - 1)

    # return z
end

"""
$(TYPEDSIGNATURES)

Evaluate synchronous-machine governor and turbine dynamics, writing state derivatives
into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `Tm`: Fixed turbine torque reference on the machine torque base \\[dimensionless\\].
- `block`: Governor lag and droop parameters.
- `gen`: Synchronous-machine electrical, mechanical, governor, and AVR blocks.

# Returns

- Assigned low-pressure torque-state derivative on the machine base \\[s⁻¹\\].

# Notes

```math
\\dot{\\delta\\omega}_f=(1-\\omega-\\delta\\omega_f)/T_w,\\quad \\dot f=(\\delta\\omega_f/R+T_m-f)/T_G.
```

Steam-chest, reheater, and crossover torque states follow successive first-order lags
with the time constants stored in `gen.mech` \\[s\\]. Torque, flow, and speed are
normalized \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
model = synchronousmachine()
inputs, point_pu = P.pftoinputs(model, values)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point_pu)
block = model.gov
F = zeros(P.n_states(block))
P.state_space!(F, x, inputs.Tm0, block; gen=model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, Tm, block::GovernorSM; gen::SynchronousMachine)
    
    dw_filt     = get_state(:δω_filt, x)          # Speed difference filtered [pu]
    flow        = get_state(:flow, x)           # Turbine valve flow [pu]
    TchHP       = get_state(:TchHP, x)         # Steam chest HP torque [pu]
    TreIP       = get_state(:TreIP, x)         # Reheater IP torque [pu]
    TcrLP       = get_state(:TcrLP, x)          # Crossover LP torque [pu]
    w_pu        = get_state(:ω_pu, x)
    
    F[1] = 1/block.T_w*( 1 - w_pu  - dw_filt ); # Governor frequency filter
    F[2] = 1/block.T_G*( dw_filt/block.R + Tm - flow); # Servo TF

    F[3] = 1/gen.mech.T_CH*(flow  - TchHP); # HP turbine fraction
    F[4] = 1/gen.mech.T_RH*(TchHP - TreIP); # IP turbine fraction
    F[5] = 1/gen.mech.T_CO*(TreIP - TcrLP); # LP turbine fraction

    # return z
end

"""
$(TYPEDSIGNATURES)

Evaluate synchronous-machine voltage-regulator and exciter dynamics, writing state
derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `v_dq`: d/q bus-voltage pair in internal machine coordinates \\[dimensionless\\].
- `didq_dt`: Tuple of d/q current time derivatives on the machine current base \\[s⁻¹\\].
- `block`: Voltage-regulator and exciter parameters.
- `gen`: Synchronous-machine electrical, mechanical, governor, and AVR blocks.
- `vref`: Fixed effective terminal-voltage reference on the machine base
  \\[dimensionless\\]. Default: `block.v_ref`.

# Returns

- Assigned normalized field-voltage derivative \\[s⁻¹\\].

# Notes

```math
\\dot v_f=(|V_t|-v_f)/T_R,\\quad \\dot\\xi=(v_{ref}-v_f-\\xi)/T_B,\\quad y=(T_C/T_B)(v_{ref}-v_f)+(1-T_C/T_B)\\xi,\\quad \\dot v_{df}=(K_A yR_f/L_{ad}-v_{df})/T_A.
```

Terminal voltage is reconstructed from bus voltage, external branch drop, and current
derivatives. Voltages use machine bases \\[dimensionless\\]; time constants use \\[s\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
model = synchronousmachine()
inputs, point_pu = P.pftoinputs(model, values)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point_pu)
block = model.avr
F = zeros(P.n_states(block))
electrical = zeros(P.n_states(model.elec))
_, didq_dt = P.state_space!(electrical, x, (inputs.vd, inputs.vq), model.elec; gen=model)
P.state_space!(F, x, (inputs.vd, inputs.vq), didq_dt, block; gen=model, vref=inputs.vref_SG)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, v_dq, didq_dt::Tuple, block::AVRSM;
        gen::SynchronousMachine, vref=block.v_ref)
    
    v_d = v_dq[1]
    v_q = v_dq[2]
    i_d = get_state(:i_d, x)
    i_q = get_state(:i_q, x)
    w_pu = get_state(:ω_pu, x)
    did_dt = didq_dt[1]
    diq_dt = didq_dt[2]
    v_f = get_state(:v_f, x)
    v_df = get_state(:v_df, x)
    x_AVR = get_state(:ξ_AVR, x)
    
    # AVR and exciter (split up for speed gains)
    v_td = v_d +gen.elec.rt*i_d + w_pu*gen.elec.lt*i_q + gen.elec.lt/gen.elec.ωn*did_dt # Machine terminal voltage
    v_tq = v_q +gen.elec.rt*i_q - w_pu*gen.elec.lt*i_d + gen.elec.lt/gen.elec.ωn*diq_dt # Machine terminal voltage

    F[1] = 1/block.T_R*(sqrt(v_td^2+v_tq^2)- v_f)        # Voltage magnitude measurement (LPF)
    dv = vref - v_f                                     # Fixed effective reference
    F[2] = 1/block.T_B*(dv - x_AVR)                 # Lead-lag state
    y_AVR = block.T_C/block.T_B*dv + (1 - block.T_C/block.T_B)*x_AVR       # Lead-lag output 
    F[3] = 1/block.T_A*( block.K_A*y_AVR*gen.elec.Rf_d/gen.elec.La_d - v_df) # Considering putting this in electrical part

    # return z
end


"""
$(TYPEDSIGNATURES)

Evaluate the coupled synchronous-machine electrical, mechanical, governor, and AVR
dynamics, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `gen`: Synchronous-machine electrical, mechanical, governor, and AVR blocks.

# Returns

- First unused derivative index after the assembled machine blocks.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
model = synchronousmachine()
inputs, point_pu = P.pftoinputs(model, values)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point_pu)
F = zeros(P.n_states(model))
P.state_space!(F, x, inputs, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, gen::SynchronousMachine)
    

    index = 1
    
    ### Inputs
    v_bus_d = inputs.vd
    v_bus_q = inputs.vq
    Tm = inputs.Tm0

    theta_grid = 0; # The angle of the global dq reference frame TODO: Check if this is correct
    d = get_state(:θ_sg, x) - theta_grid; # New reference frame angle - old RF angle
    T = [cos(d) -sin(d);
        sin(d)  cos(d)]; # Rotation to rotor's RF
    v_dq = T*[v_bus_d; v_bus_q];
    # vd = v_dq[1];
    # vq = v_dq[2];
    # z = merge(z,(;vd,vq, Tm0))

    ### ElectricalSM
    index_end = index + n_states(gen.elec) -1  #Nb of equatinos
    Te, didq_dt = state_space!(@view(F[index:index_end]), x, v_dq, gen.elec ;gen)
    index = index_end+1

    ### MechanicalSM
    index_end = index + n_states(gen.mech)-1 #Nb of equatinos
    state_space!(@view(F[index:index_end]), x, Te, gen.mech;gen)
    index = index_end+1
    
    ### Governor
    index_end = index + n_states(gen.gov)-1 #Nb of equatinos
    state_space!(@view(F[index:index_end]), x, Tm, gen.gov;gen)
    index = index_end+1

    ### AVR
    index_end = index + n_states(gen.avr)-1 #Nb of equatinos
    state_space!(@view(F[index:index_end]), x, v_dq, didq_dt, gen.avr;
        gen, vref=get(inputs, :vref_SG, gen.avr.v_ref))
    index = index_end+1

    
end


###### HElper functions ########################

"""
$(TYPEDSIGNATURES)

Construct a synchronous-machine model from electrical and mechanical subsystems.

# Arguments

- `elec`: Electrical subsystem and its physical base quantities. Default:
  `ElectricalSM()`.
- `mech`: Mechanical subsystem. Default: `MechanicalSM()`.
- `avr`: Automatic voltage regulator. Default: `AVRSM()`.
- `gov`: Governor subsystem. Default: `GovernorSM()`.
- `powerflow`: Partial power-flow seeds on machine bases \\[dimensionless\\].
  Default: `(;)`.

# Returns

- An immutable `SynchronousMachine` with an `ACDQ` port.

# Examples

```julia
using PowerImpedance
machine = component(synchronousmachine();
    powerflow = (p = 0.1, q = 0.0, v = 1.0))
```
"""
function synchronousmachine(; elec = ElectricalSM(), mech = MechanicalSM(),
        avr = AVRSM(), gov = GovernorSM(), powerflow::NamedTuple = (;))
    defaults = map(input -> input.default, _MACHINE_POWERFLOW_INPUTS)
    seeds = _withinputs(defaults, _MACHINE_POWERFLOW_INPUTS,
        powerflow, "powerflow")
    return SynchronousMachine(elec, mech, avr, gov, Limits(), seeds, LinearizationCache())
end


function get_state(label::Symbol,x)
    return getfield(x, label)
end




# This did not work!
# function eval_abcd(gen :: SynchronousMachine, s :: Complex)
#     Y = eval_parameters(gen,s)
#     abcd = y_to_abcd(Y)
# end

# Repeating what is done for the MMC

function eval_abcd(gen :: SynchronousMachine, s :: Complex)
    return eval_y(gen, s)
end

function eval_y(gen :: SynchronousMachine, s :: Complex)
    Y = eval_parameters(gen, s)
    return Y
end

"""
$(TYPEDSIGNATURES)

Return the factors that convert per-unit machine admittance to siemens.

# Arguments

- `model`: Component model with electrical base quantities.

# Returns

- Matrix of output-current-base to input-voltage-base ratios \\[S\\].

# Notes

```math
Y_{ij}^{SI}=Y_{ij}^{pu}\\frac{I_{b,i}}{V_{b,j}}.
```

The common entry is `S_base/Vᵃᶜ_base²` \\[S\\], using the three-phase power base
in \\[MVA\\] and line-to-line RMS voltage base in \\[kV\\]. These factors are returned
for explicit use by the network admittance calculation.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = synchronousmachine()
scale = P.SI_scale(model)
```
"""
function SI_scale(model::SynchronousMachine)
    elec = model.elec
    return fill(elec.S_base / elec.Vᵃᶜ_base^2, 2, 2)
end



electricalconnections(::SynchronousMachine) = (ac = Port(ACDQ),)

is_generator(::SynchronousMachine) = true
is_passive(::SynchronousMachine) = false
admittance_order(::SynchronousMachine) = ((:ac, :d), (:ac, :q))

inputs(::AVRSM) = (v_ref = _AVR_VOLTAGE_INPUT,)
inputs(model::SynchronousMachine) = (
    avr = inputs(model.avr),
    powerflow = _MACHINE_POWERFLOW_INPUTS,
)

bases(model::SynchronousMachine) = BaseValues(S = model.elec.S_base,
    v_ac = model.elec.Vᵃᶜ_base * sqrt(2/3), omega = model.elec.ωn)

limits(model::SynchronousMachine) = model.limits

function _withinputs(model::SynchronousMachine, declarations::NamedTuple, changes, path)
    configured = invoke(_withinputs, Tuple{Any, NamedTuple, Any, Any},
        model, declarations, changes, path)
    return Parameters.reconstruct(configured; cache = LinearizationCache())
end


pmtype(::SynchronousMachine, rows) = "gen"

function convert!(data, machine::SynchronousMachine, ::Type{PMACDC}, component_key,
        ports::NamedTuple, global_dict)
    key_branch = component_key.index
    ac_bus = ports.ac
    target = inputvalues(machine).powerflow
    b = bases(machine)
    point = (p = target.p * b.S, q = target.q * b.S, v = target.v * b.v_ac)
    lm = limits(machine)
    interm_bus = add_interm_bus_ac!(data, global_dict)



    key_branch_str = string(key_branch)
    data["gen"][key_branch_str] = Dict{String, Any}()
    gen = data["gen"][key_branch_str]
    gen["mBase"] = global_dict["S"] / 1e6
    gen["gen_bus"] = interm_bus
    gen["pc1"] = 0
    gen["pc2"] = 0
    gen["qc1min"] = 0
    gen["qc1max"] = 0
    gen["qc2min"] = 0
    gen["qc2max"] = 0
    gen["ramp_agc"] = 0
    gen["ramp_q"] = 0
    gen["ramp_10"] = 0
    gen["ramp_30"] = 0
    gen["apf"] = 0
    gen["startup"] = 0
    gen["shutdown"] = 0
    gen["gen_status"] = 1
    gen["source_id"] = Any["gen", key_branch]
    gen["index"] = key_branch

    s_base = global_dict["S"] / 1e6
    v_base = global_dict["V"] / 1e3
    gen["pg"] = point.p / s_base
    gen["qg"] = point.q / s_base
    gen["pmin"] = lm.P_min / s_base
    gen["pmax"] = lm.P_max / s_base
    gen["qmin"] = lm.Q_min / s_base
    gen["qmax"] = lm.Q_max / s_base
    gen["vg"] = point.v / v_base/sqrt(2)
    gen["model"] = 1
    gen["cost"] = 0
    gen["ncost"] = 0

    key_branch_str = string(key_branch)

    data["branch"][key_branch_str] = Dict{String, Any}()
    branch = data["branch"][key_branch_str]
    branch["f_bus"] = interm_bus
    branch["t_bus"] = ac_bus
    branch["source_id"] = Any["branch", key_branch]
    branch["index"] = key_branch
    branch["rate_a"] = 1
    branch["rate_b"] = 1
    branch["rate_c"] = 1
    branch["br_status"] = 1
    branch["angmin"] = ang_min
    branch["angmax"] = ang_max
    branch["transformer"] = false
    branch["tap"] = 1
    branch["shift"] = 0
    branch["c_rating_a"] = 1
    branch["br_r"] = machine.elec.rt *
        (machine.elec.Vᵃᶜ_base^2 / machine.elec.S_base) / global_dict["Z"]
    branch["br_x"] = machine.elec.lt *
        (machine.elec.Vᵃᶜ_base^2 / machine.elec.S_base) / global_dict["Z"]
    branch["g_fr"] = 0
    branch["b_fr"] = 0
    branch["g_to"] = 0
    branch["b_to"] = 0

    bus = data["bus"][string(interm_bus)]
    if isapprox(lm.P_max, point.p)
        data["bus"][string(interm_bus)] = set_bus_type(bus, 1)
    else
        data["bus"][string(interm_bus)] = set_bus_type(bus, 2)
    end

    gen = data["gen"][key_branch_str]
    data["bus"][string(interm_bus)]["vm"] = gen["vg"]
    data["bus"][string(interm_bus)]["vmin"] = 0.9 * gen["vg"]
    data["bus"][string(interm_bus)]["vmax"] = 1.1 * gen["vg"]
    return nothing
end


"""
$(TYPEDSIGNATURES)

Return AC port powers positive into the machine. Delivering 900 MW gives `ac.p = -900`.
"""
function transform(elemresult, busresult::NamedTuple, global_dict,
        model::SynchronousMachine, ::Type{PMACDC}, ::Type{PIACDC})

    acbusresult = busresult.ac
    Pgen = elemresult["pg"] * global_dict["S"] / 1e6 #MW
    Qgen = elemresult["qg"] * global_dict["S"] / 1e6 #MVAr
    Vm =
        (acbusresult["vm"] *
            # Convert the LN-RMS voltage coming from the PF to LN-PK
            global_dict["V"] / 1e3) * sqrt(2)
    θ = acbusresult["va"]

    return (ac = ACPortValues(Vm, θ, -Pgen, -Qgen),)
end
