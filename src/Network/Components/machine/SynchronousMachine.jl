export synchronousmachine, ElectricalSM, MechanicalSM, AVRSM, GovernorSM, SynchronousMachine
#  using SciMLLogging #Debug
### Abstract synchronous machine type (allow for other structures in future, subtype of Machine is this necessary)
abstract type AbstractSynchronousMachine <: Machine end




################# ELECTRICAL #################################

@with_kw struct ElectricalSM <: AbstractStateSpace

    # eq::EquationInfo = electricalsmeq()

    ωn :: Float64 = 100*π
    
    # Base values
    Vᵃᶜ_base :: Float64 = 220 # Converter AC voltage base, LL, RMS [kV]
    S_base :: Float64 = 1000 # Converter AC voltage base, LL, RMS [kV]

    
   

    # Transformer (RL-branch model)
    lt :: Float64 = 0.065 # [pu]
    rt :: Float64 = 0.0026 # [pu]

    # Modified Kundur's example
    La_d :: Float64 = 1.66 # d-axis magnetizing inductance
    La_q :: Float64 = 1.61 # q-axis magnetizing inductance
    Ll :: Float64 = 0.15    # Stator leakage inductance
    Ra :: Float64 = 0.0015  # Armature resistance

    Lf_d :: Float64 = 0.165  # Field leakage inductance
    L1_d :: Float64 = 0.1713 # d-axis damper winding inductance
    L1_q :: Float64 = 0.7252 # q-axis first damper winding inductance
    L2_q :: Float64 = 0.125  # q-axis second damper winding inductance

    # No mutual inductance
    L23_d :: Float64 = 0 # d-axis field-damper mutual inductance
    L23_q :: Float64 = 0 # q-axis damper-damper mutual inductance

    Rf_d :: Float64 = 0.0002 # Field circuit resistance
    R1_d :: Float64 = 0.0200 # d-axis damper winding resistance
    R1_q :: Float64 = 0.0050 # q-axis first damper winding resistance
    R2_q :: Float64 = 0.0100 # q-axis second damper winding resistance
end

statenames(::ElectricalSM) = (:i_d, :i_df, :i_d1, :i_q, :i_q1,:i_q2)
initialvalues(::ElectricalSM) =  (;) # No non-zero states



############################# MECHANICAL #######################################

@with_kw struct MechanicalSM <: AbstractStateSpace
    
    #eq::EquationInfo{}=mechsmeq()
    # init::IntialStates1{(:ω_pu, :θ_sg),2}
    H :: Float64 = 4 # Inertia constant [s]
    # Steam turbine
    T_CH :: Float64 = 2 # Steam chest time constant [s]
    T_RH :: Float64 = 5 # Reheater time constant [s]
    T_CO :: Float64 = 1 # Cross-over time constant [s]
    F_HP :: Float64 = 0.3 # High presure turbine fraction [pu]
    F_IP :: Float64 = 0.4 # Intermediate presure turbine fraction [pu]
    F_LP :: Float64 = 0.3 # Low presure turbine fraction [pu]

end
statenames(::MechanicalSM) = (:ω_pu,:θ_sg)
initialvalues(::MechanicalSM) =  (ω_pu=1.0,)



################# GOVERNOR ######################


@with_kw struct GovernorSM <: AbstractStateSpace
    T_w :: Float64 = 0.1 # Speed lag time constant [s]
    T_G :: Float64 = 0.2 # Time constant of the governor [s]
    R :: Float64 = 0.05   # Frequency control droop / Inverse of the gain [pu/pu]
end

statenames(::GovernorSM) = (:δω_filt, :flow, :TchHP, :TreIP, :TcrLP)
initialvalues(::GovernorSM;inputs) =  NamedTuple{(:flow, :TchHP, :TreIP, :TcrLP)}(ntuple(i -> inputs.Tm0, 4)) #Initalize those to same value



########################### AVR #############################

@with_kw struct AVRSM <: AbstractStateSpace
    # eq::EquationInfo=avrsmeq()
    vref_SG :: Float64   = 1.01 # Terminal voltage magnitude reference [pu]
    T_R :: Float64       = 0.05     # Terminal voltage filter time constant [s]
    T_B :: Float64       = 1.0       # Lag time constant [s]
    T_C :: Float64       = 0.1        # Lead time constant [s]
    T_A :: Float64       = 0.02    # Regulator (lag) time constant [s]
    K_A :: Float64       = 200      # Regulator gain [pu]
end

statenames(::AVRSM) = (:v_f, :ξ_AVR, :v_df)
initialvalues(::AVRSM) =  (;)



################### SYNCHRONOUS MACHINE ######################

struct SynchronousMachine <: AbstractStateSpace
    elec::ElectricalSM
    mech::MechanicalSM
    avr::AVRSM
    gov::GovernorSM
end

statenames(m::SynchronousMachine) = (statenames(m.elec)..., statenames(m.mech)...,statenames(m.avr)..., statenames(m.gov)...)
initialvalues(m::SynchronousMachine;inputs, kwargs...) =  merge(initialvalues(m.elec), initialvalues(m.mech),initialvalues(m.avr),initialvalues(m.gov;inputs))
inputnames(m::SynchronousMachine) = (:vd, :vq, :Tm0)
outputnames(m::SynchronousMachine) = (:id, :iq)
elecinputnames(m::SynchronousMachine) = (:vd, :vq)

function pftoinputs(m::SynchronousMachine, setpoint::Setpoint)
    
    v_bus_d = setpoint.Vac * cos(setpoint.θac) /  (m.elec.Vᵃᶜ_base * sqrt(2/3))
    v_bus_q = -setpoint.Vac * sin(setpoint.θac) / (m.elec.Vᵃᶜ_base * sqrt(2/3))
    Tm0 = setpoint.Pac / m.elec.S_base # You use setpoint power as mechanical torque (cst torque and ω is 1pu  ), TODO: Provide power of generator and should be fine    

    return NamedTuple{inputnames(m)}((v_bus_d, v_bus_q, Tm0)), nothing
end


function outputequations!(F, x, inputs, y, gen::SynchronousMachine)
    
    theta_grid = 0; # The angle of the global dq reference frame TODO: Check if this is correct
    d = get_state(:θ_sg, x) - theta_grid; # New reference frame angle - old RF angle
    T_inv = [cos(d) sin(d);
        -sin(d)  cos(d)]; # Rotation to rotor's RF
    F[1:2] = -T_inv*[x.i_d;x.i_q] #Grid ref frame currentst
end


#################### STATE SPACE EQUATIONS ###############################

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

function state_space!(F, x, v_dq, didq_dt::Tuple, block::AVRSM;gen::SynchronousMachine)
    
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
    dv = block.vref_SG - v_f                             # Error TODO: The voltage reference can be made an input to the state-space model.
    F[2] = 1/block.T_B*(dv - x_AVR)                 # Lead-lag state
    y_AVR = block.T_C/block.T_B*dv + (1 - block.T_C/block.T_B)*x_AVR       # Lead-lag output 
    F[3] = 1/block.T_A*( block.K_A*y_AVR*gen.elec.Rf_d/gen.elec.La_d - v_df) # Considering putting this in electrical part

    # return z
end


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
    state_space!(@view(F[index:index_end]), x, v_dq, didq_dt, gen.avr;gen)
    index = index_end+1

    
end


###### HElper functions ########################

function synchronousmachine(;elec=ElectricalSM(),mech=MechanicalSM(),avr=AVRSM(),gov=GovernorSM(), setpoint=Setpoint(), connection=true)
    
    gen = SynchronousMachine(elec, mech,avr, gov)
    # Transformation property set to false, as model is natively defined in dq-frame. TODO: Fix this; outpins 0 bcs oneport, kept for legacy
    elem = Element(input_pins = 2, output_pins = 2, element_model = gen, transformation = false; connection, setpoint)
    return elem
end


function get_state(label::Symbol,x)
    return getfield(x, label)
end




function eval_parameters(elem :: Element, s :: Complex)
    # numerical
    I = Matrix{Complex}(Diagonal([1 for dummy in 1:size(elem.A,1)]))
    Y = (elem.C*inv(s*I-elem.A))*elem.B + elem.D

    return Y
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


pmtype(::Element{<:SynchronousMachine}) = "gen"

function convert!(data,elem::Element{<:SynchronousMachine},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)

    # Find the nodes not connected to the ground
    ac_nodes = make_non_ground_node(elem, bus2nodes)
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)
    

    key = comp_elem_interface!(data, elem2comp, comp2elem, elem, pmtype(elem))
    return convert!(data, elem, PMACDC, key, (ac_bus,), global_dict)
end

function convert!(data, elem::Element{<:SynchronousMachine}, ::Type{PMACDC}, key_branch, (ac_bus,), global_dict)
    machine = elem.element_model
    interm_bus = add_interm_bus_ac!(data, global_dict)
    
    

    _initialize_gen_entry!(data, key_branch, interm_bus, elem, global_dict)

    # key_branch = length(data["branch"]) + 1
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
    branch["br_r"] = machine.elec.rt * (machine.elec.Vᵃᶜ_base^2 / machine.elec.S_base) / global_dict["Z"]
    branch["br_x"] = machine.elec.lt * (machine.elec.Vᵃᶜ_base^2 / machine.elec.S_base) / global_dict["Z"]
    branch["g_fr"] = 0
    branch["b_fr"] = 0
    branch["g_to"] = 0
    branch["b_to"] = 0

    bus = data["bus"][string(interm_bus)]
    if isapprox(elem.limits.P_max, elem.setpoint.Pac)
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

function transform(elemresult, busresult, global_dict, elem::Element{<:SynchronousMachine}, ::Type{PMACDC}, ::Type{PIACDC})
			
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