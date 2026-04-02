export synchronousmachine, ElectricalSM, MechanicalSM, AVRSM, GovernorSM, EquationInfo, electricalsmeq, OperatingPoint, SynchronousMachine
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

function pftoinputs(m::SynchronousMachine, setpoint::SetPoint)
    
    v_bus_d = setpoint.Vac * cos(setpoint.θac) /  (m.elec.Vᵃᶜ_base * sqrt(2/3))
    v_bus_q = -setpoint.Vac * sin(setpoint.θac) / (m.elec.Vᵃᶜ_base * sqrt(2/3))
    Tm0 = setpoint.Pac / m.elec.S_base # You use setpoint power as mechanical torque (cst torque and ω is 1pu  ), TODO: Provide power of generator and should be fine    

    return NamedTuple{inputnames(m)}((v_bus_d, v_bus_q, Tm0))
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

function state_space!(F, x, v_dq, didq_dt, block::AVRSM;gen::SynchronousMachine)
    
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

function synchronousmachine(;elec=ElectricalSM(),mech=MechanicalSM(),avr=AVRSM(),gov=GovernorSM(), setpoint=SetPoint(), connection=true)
    
    gen = SynchronousMachine(elec, mech,avr, gov)
    # Transformation property set to false, as model is natively defined in dq-frame. TODO: Fix this
    elem = Element(input_pins = 2, output_pins = 2, element_model = gen, transformation = false; connection, setpoint)
    return elem
end


function get_state(label::Symbol,x)
    return getfield(x, label)
end





# function update!(gen::SynchronousMachine, Vac, θac, Pac, Qac)

    
    


#     #### 1. Inputs & Initial values based on power flow
#     v_bus_d = Vac * cos(θac) /  (gen.elec.Vᵃᶜ_base * sqrt(2/3))
#     v_bus_q = -Vac * sin(θac) / (gen.elec.Vᵃᶜ_base * sqrt(2/3))
#     Tm0 = Pac / gen.elec.S_base # You use setpoint power as mechanical torque (cst torque and ω is 1pu  ), TODO: Provide power of generator and should be fine

#     ### Custom inital values 

#     global map = statenames(gen)
#     global init = orderedinitialvalues(gen;Tm0) 
    
#     inputs = [v_bus_d,v_bus_q, Tm0]
#     p=(inputs, map,gen, Equil())

#     f!(du, u,p) = state_space!(du,u, p[1], p[2], p[3], p[4])
#     println("Starting to solve for Steady-State Solution!")
#     prob = NonlinearProblem(f!, collect(values(init)), p)

#     ### 3. Find equilibrium
   
#     sol=solve(prob;maxiters=20,abstol = 1e-6,reltol = 1e-6)
#     if SciMLBase.successful_retcode(sol)
#         println("SG steady-state solution found!")
#     else
#         error("SG steady-state solution not found!")
#     end
#     equilibrium = sol.u[1:n_states(gen)] #Discarding addit states for equil (not relevat for SM)

#     ### 4. Calculate Jacobian

#     nb_states = n_states(gen)
#     nb_inputs = 3 # vd, vq, Tm
#     nb_outputs = 2 #id, iq

#     h!(F,x) = state_space!(F, x[1:end-nb_inputs], x[end-nb_inputs+1:end],map, gen, Jac())
#     ha = x -> (F = fill(zero(eltype(x)), nb_states+nb_outputs); h!(F, x); return F)
#     jac = zeros(nb_states+nb_outputs, nb_states+nb_inputs)
#     ForwardDiff.jacobian!(jac, ha, [equilibrium; inputs])

#     ### 5. New operating point
#     A=jac[1:nb_states, 1:nb_states]
#     B=jac[1:nb_states, nb_states+1:end-1]
#     C=jac[nb_states+1:end, 1:nb_states]
#     D=jac[nb_states+1:end, nb_states+1:end-1]

#     setpoint = SetPoint(;Vac,θac, Pac,Qac)

#     return setpoint, A,B,C,D # Return new element
#     ### END
# end



# function synchronousmachine(;args...)
#     gen = SynchronousMachine()
#     connection = true
#     for (key, val) in pairs(args)
#         if in(key, propertynames(gen))
#             setfield!(gen, key, val)
#         elseif (key == :connection)
#             connection = val
#         else
#             throw(ArgumentError("Machine does not have a property $(key)."))
#         end
#     end
#     # Transformation property set to false, as model is natively defined in dq-frame
#     elem = Element(input_pins = 2, output_pins = 2, element_value = gen, transformation = false, connection = connection)
# # end



# function update!(gen :: SynchronousMachine, Pac, Qac, Vm, θ) # TODO: Removed Pac and Qac from this function, see if it will be necessary.
#     Ld = gen.elec.La_d + gen.elec.Ll + gen.elec.lt
#     Lf1_d = gen.elec.La_d + gen.elec.L23_d
#     Lff_d = Lf1_d + gen.elec.Lf_d
#     L11_d = Lf1_d + gen.elec.L1_d

#     Lq  = gen.elec.La_q + gen.elec.Ll + gen.elec.lt
#     L11_q  = gen.elec.L1_q + gen.elec.La_q
#     L22_q  = gen.elec.L2_q + gen.elec.La_q

#     Z_base = gen.elec.Vᵃᶜ_base^2 / gen.elec.S_base
#     I_base = sqrt(2/3)*gen.elec.S_base / gen.elec.Vᵃᶜ_base
    


#     init_x = zeros(16, 1) # TODO: Automatize this based on the presence of the AVR.

#     # Initialization values

#     v_bus_d0 = gen.V * cos(θ) /  (gen.Vᵃᶜ_base * sqrt(2/3))
#     v_bus_q0 = -gen.V * sin(θ) / (gen.Vᵃᶜ_base * sqrt(2/3))
#     # Initialization without an AVR
#     # e_df0   = 0.005 * 200 * gen.Rf_d/gen.La_d # Exciter [pu]
#     # Tm0     = 0.5                     # Mechanical torque [pu]
#     Tm0 = gen.P / gen.S_base

#     # State variables initialization
#     # Damper winding currents initialized at zero. These are located at indices 3, 5 and 6. The same also holds for the filtered speed difference at index 9
#     # init_x[2] = e_df0 / gen.Rf_d # In the absence of an AVR
#     init_x[7] = 1 # initialize the inital rotating speed to 1
#     init_x[10:13] = [Tm0;Tm0;Tm0;Tm0] # initialize all the torques to be the same as the mechanical torque
#     # The remaining state variables to be initialized are the stator currents (indices 1 and 4) and the angular position of the rotor reference frame (index 8)

#     exp_init = Expr(:block)
#     # Initialization without an AVR
#     # input1 - vd
#     # input2 - vq
#     # input3 - if
#     # input4 - TH
#     # input5 - TI
#     # input6 - TL
#     # input7 - e_df
#     # State variables without AVR: id, iq, w_pu
#     # push!(exp_init.args, :(
        
#     #     theta_grid = 0; 
#     #     d = (x[4] - theta_grid);
#     #     T = [cos(d) -sin(d);
#     #         sin(d)  cos(d)]; 
#     #     v_dq = T*inputs[1:2];
#     #     flux_d = - $Ld*x[1] + $gen.La_d*inputs[3]; # d-axis flux
#     #     flux_q = - $Lq*x[2];  # q-axis flux

#     #     L_D = [-$Ld       $gen.La_d   $gen.La_d; 
#     #         -$gen.La_d   $Lff_d      $Lf1_d;
#     #         -$gen.La_d   $Lf1_d      $L11_d];

#     #     L_Q = [-$Lq       $gen.La_q    $gen.La_q; 
#     #         -$gen.La_q   $L11_q       $gen.La_q;
#     #         -$gen.La_q   $gen.La_q    $L22_q];
        
#     #     RHS_D = $gen.wn*[(v_dq[1]  +	$gen.Ra*x[1] - x[3]*flux_q);
#     #                 (inputs[7] -	$gen.Rf_d*inputs[3]);
#     #                 0];

#     #     RHS_Q = $gen.wn*[(v_dq[2]  +  $gen.Ra*x[2] + x[3]*flux_d);
#     #                 0;
#     #                 0];
#     #     diD_dt = L_D \ RHS_D;
#     #     diQ_dt = L_Q \ RHS_Q;

#     #     F[1] = diD_dt[1];
#     #     F[2] = diQ_dt[1];
        
#     #     T_turb = $gen.F_HP*inputs[4] + $gen.F_IP*inputs[5] + $gen.F_LP*inputs[6];
#     #     Te = -(flux_d*x[2] - flux_q*x[1]); 

#     #     F[3] = (T_turb - Te)/(2*$gen.H);
#     #     F[4] = $gen.wn*(x[3] - 1)))

#     # With AVR
#     # input1 - vd
#     # input2 - vq
#     # input3 - flow
#     # input4 - TH
#     # input5 - TI
#     # input6 - TL
#     function state_space_equil!(F,x,inputs,gen)
#         i_d         = x[1];        # d-axis stator current
#         i_df        = x[2];        # Field current
#         i_d1        = 0;        # d-axis damping winding current

#         i_q         = x[3];         # q-axis stator current
#         i_q1        = 0;        # q-axis 1st damping winding current
#         i_q2        = 0;        # q-axis 2nd damping winding current

#         w_pu        = x[4];            # Per unit rotor angular speed omega/omega_n
#         theta_sg    = x[5];        # Angular position of the rotor reference frame
#         TchHP       = inputs[3];          # Steam chest HP torque [pu]
#         TreIP       = inputs[4];          # Reheater IP torque [pu]
#         TcrLP       = inputs[5];          # Crossover LP torque [pu]

#         # AVR-related states

#         v_f         = x[6];
#         x_AVR       = x[7];
#         v_df        = x[8];

#         v_bus_d = inputs[1];  # d-axis grid voltage [pu]
#         v_bus_q = inputs[2]; # q-axis grid voltage [pu]

#         # theta_grid = atan(-v_bus_q,v_bus_d);
#         theta_grid = 0;  
#         d = theta_sg - theta_grid; # New reference frame angle - old RF angle
#         T = [cos(d) -sin(d);
#             sin(d)  cos(d)]; # Rotation to rotor's RF
#         Wpu = [0 1;-1 0]; # Rotation matrix multiplied by the derivative of its inverse
#         v_dq = T*[v_bus_d; v_bus_q];
#         v_d = v_dq[1];
#         v_q = v_dq[2];

#         # SG (d-aligned, q-lagging)
#         # Same eqs. as Paul C. Krause book but with qd swaped by dq
#         # In addition, Te is computed for generator operation 

#         flux_d = - Ld*i_d + gen.La_d*(i_df + i_d1); # d-axis flux
#         flux_q = - Lq*i_q + gen.La_q*(i_q1 + i_q2); # q-axis flux

#         Te = -(flux_d*i_q - flux_q*i_d); # Generator operation electrical torque n_ppoles*w_m = w_e

#         L_D = [-Ld       gen.La_d   gen.La_d; 
#             -gen.La_d   Lff_d      Lf1_d;
#             -gen.La_d   Lf1_d      L11_d];

#         L_Q = [-Lq       gen.La_q   gen.La_q; 
#             -gen.La_q   L11_q       gen.La_q;
#             -gen.La_q   gen.La_q    L22_q];

#         RHS_D = gen.wn*[(v_d  +	(gen.Ra+gen.rt)*i_d	- w_pu*flux_q);
#                     (v_df -	gen.Rf_d*i_df);
#                     (0    - gen.R1_d*i_d1)];

#         RHS_Q = gen.wn*[(v_q  +  (gen.Ra+gen.rt)*i_q + w_pu*flux_d);
#                     (0    -  gen.R1_q*i_q1);
#                     (0    -  gen.R2_q*i_q2)];

#         did_dt = L_D \ RHS_D;
#         diq_dt = L_Q \ RHS_Q;

#         F[1:2] =  did_dt[1:2];
#         F[3] =  diq_dt[1];

#         T_turb = gen.F_HP*TchHP +gen.F_IP*TreIP + gen.F_LP*TcrLP;

#         F[4] = (T_turb - Te)/(2*gen.H);   # Newton's II Law
#         F[5] = gen.wn*(w_pu - 1);
        
#         # AVR and exciter
#         v_t = v_dq + gen.rt*[i_d;i_q] + w_pu*gen.lt*Wpu*[i_d;i_q] + gen.lt/gen.wn*[F[1];F[3]]; # Machine terminal voltage

#         F[6] = 1/gen.T_R*(sqrt(v_t[1]*v_t[1]+v_t[2]*v_t[2]) - v_f);        # Voltage magnitude measurement (LPF)
#         dv = gen.vref_SG - v_f;                             # Error TODO: The voltage reference can be made an input to the state-space model.
#         F[7] = 1/gen.T_B*(dv - x_AVR);                 # Lead-lag state
#         y_AVR = gen.T_C/gen.T_B*dv + (1 - gen.T_C/gen.T_B)*x_AVR;       # Lead-lag output 
#         F[8] = 1/gen.T_A*( gen.K_A*y_AVR*gen.Rf_d/gen.La_d - v_df)    
#     end

#     inputs_init = [v_bus_d0;v_bus_q0;Tm0;Tm0;Tm0]    

#     function f!(expr, F, x, inputs) # F derivative of state variable x state variable vector, inputs input vqlue expr equation of mmc
#         f = eval(:((F,x,inputs) -> $expr))
#         return Base.invokelatest(f, F,x,inputs)
#     end
#     init_init = zeros(8,1)
#     init_init[4] = 1
#     g!(du,u,p) = state_space_equil!(du, u, p[1], p[2]) # g is the state-space formulation used to obtain the steady-state operation point, copy from f, see some lines above
#     println("Starting to solve for Steady-State Solution!")
#     prob = NonlinearProblem(g!, init_init, (inputs_init, gen))
#     sol=solve(prob;maxiters=20,abstol = 1e-6,reltol = 1e-6)
#     if SciMLBase.successful_retcode(sol)
#         println("SG steady-state solution found!")
#     else
#         error("SG steady-state solution not found!")
#     end
#     equilibrium_init = sol.u

#     # k!(F,x) = f!(exp_init, F, x, inputs_init)
#     # init_init = zeros(8,1)
#     # init_init[4] = 1
#     # k_init = nlsolve(k!, init_init , autodiff = :forward, iterations = 200, ftol = 1e-6, xtol = 1e-3, method = :trust_region)
#     # if converged(k_init)
#     #     println("SG steady-state solution found!")
#     # end
#     # equilibrium_init= k_init.zero #debug here
#     # println("Inputs for the steady state solution")
#     # println(inputs_init)
#     # println("Steady state solution")
#     # println(equilibrium_init)
#     init_x[1] = equilibrium_init[1]
#     init_x[2] = equilibrium_init[2]
#     init_x[4] = equilibrium_init[3]
#     init_x[8] = equilibrium_init[5]
#     init_x[14] = equilibrium_init[6]
#     init_x[15] = equilibrium_init[7]
#     init_x[16] = equilibrium_init[8]

#     # vector_inputs = [v_bus_d0;v_bus_q0;Tm0] # voltages are not in pu here!
#     vector_inputs = [gen.V * cos(θ); -gen.V * sin(θ);Tm0]
#     # setup control parameters and equations 
#     # TODO: for now, AVR is added as a standard. Can make it optional in the future.
    
#     # add state variables
#     exp_fin = Expr(:block)
#     function state_space_jac!(F, x, inputs, gen)
   
#         i_d         = x[1];        # d-axis stator current
#         i_df        = x[2];        # Field current
#         i_d1        = x[3];        # d-axis damping winding current

#         i_q         = x[4];         # q-axis stator current
#         i_q1        = x[5];        # q-axis 1st damping winding current
#         i_q2        = x[6];        # q-axis 2nd damping winding current

#         w_pu        = x[7];            # Per unit rotor angular speed omega/omega_n
#         theta_sg    = x[8];        # Angular position of the rotor reference frame
#         dw_filt     = x[9];          # Speed difference filtered [pu]
#         flow        = x[10];           # Turbine valve flow [pu]
#         TchHP       = x[11];          # Steam chest HP torque [pu]
#         TreIP       = x[12];          # Reheater IP torque [pu]
#         TcrLP       = x[13];          # Crossover LP torque [pu]

#         # AVR-related states

#         v_f         = x[14];
#         x_AVR       = x[15];
#         v_df        = x[16];

#         v_bus_d = inputs[1] /  (gen.Vᵃᶜ_base * sqrt(2/3)); # d-axis grid voltage [pu]
#         v_bus_q = inputs[2] /  (gen.Vᵃᶜ_base * sqrt(2/3)); # q-axis grid voltage [pu]
#         Tm      = inputs[3];  # Initial torque [pu] # When the AVR is not implemented, this input is the field voltage e_df

#         # Infinite bus
#         # theta_grid = atan(-v_bus_q,v_bus_d);
#         theta_grid = 0; # The angle of the global dq reference frame TODO: Check if this is correct
#         d = theta_sg - theta_grid; # New reference frame angle - old RF angle
#         T = [cos(d) -sin(d);
#             sin(d)  cos(d)]; # Rotation to rotor's RF
#         Wpu = [0 1;-1 0]; # Rotation matrix multiplied by the derivative of its inverse
#         v_dq = T*[v_bus_d; v_bus_q];
#         v_d = v_dq[1];
#         v_q = v_dq[2];

#         # SG (d-aligned, q-lagging)
#         # Same eqs. as Paul C. Krause book but with qd swaped by dq
#         # In addition, Te is computed for generator operation 
#         L_D = [-Ld       gen.La_d   gen.La_d; 
#             -gen.La_d   Lff_d      Lf1_d;
#             -gen.La_d   Lf1_d      L11_d];

#         L_Q = [-Lq       gen.La_q    gen.La_q; 
#             -gen.La_q   L11_q       gen.La_q;
#             -gen.La_q   gen.La_q    L22_q];

#         flux_d = - Ld*i_d + gen.La_d*(i_df + i_d1); # d-axis flux
#         flux_q = - Lq*i_q + gen.La_q*(i_q1 + i_q2); # q-axis flux

#         Te = -(flux_d*i_q - flux_q*i_d); # Generator operation electrical torque n_ppoles*w_m = w_e

#         RHS_D = gen.wn*[(v_d  +	(gen.Ra+gen.rt)*i_d	- w_pu*flux_q);
#                     (v_df -	gen.Rf_d*i_df);
#                     (0    - gen.R1_d*i_d1)];

#         RHS_Q = gen.wn*[(v_q  +  (gen.Ra+gen.rt)*i_q + w_pu*flux_d);
#                     (0    -  gen.R1_q*i_q1);
#                     (0    -  gen.R2_q*i_q2)];

#         F[1:3] = L_D \ RHS_D;
#         F[4:6] = L_Q \ RHS_Q;

#         T_turb = gen.F_HP*TchHP + gen.F_IP*TreIP + gen.F_LP*TcrLP;

#         F[7] = (T_turb - Te)/(2*gen.H);   # Newton's II Law
#         F[8] = gen.wn*(w_pu - 1);

#         # Mechanical equations for the governor
#         F[9] = 1/gen.T_w*( 1 - w_pu  - dw_filt ); # Governor frequency filter
#         F[10] = 1/gen.T_G*( dw_filt/gen.R + Tm - flow); # Servo TF

#         F[11] = 1/gen.T_CH*(flow  - TchHP); # HP turbine fraction
#         F[12] = 1/gen.T_RH*(TchHP - TreIP); # IP turbine fraction
#         F[13] = 1/gen.T_CO*(TreIP - TcrLP); # LP turbine fraction
        
#         # AVR and exciter
#         v_t = v_dq +gen.rt*[i_d;i_q] + w_pu*gen.lt*Wpu*[i_d;i_q] + gen.lt/gen.wn*[F[1];F[4]]; # Machine terminal voltage
        
#         # F[14] = 1/$gen.T_R*(sqrt(transpose(v_t)*v_t) - v_f);        # Voltage magnitude measurement (LPF)
#         F[14] = 1/gen.T_R*(sqrt(v_t[1]*v_t[1]+v_t[2]*v_t[2]) - v_f);        # Voltage magnitude measurement (LPF)
#         dv = gen.vref_SG - v_f;                             # Error TODO: The voltage reference can be made an input to the state-space model.
#         F[15] = 1/gen.T_B*(dv - x_AVR);                 # Lead-lag state
#         y_AVR = gen.T_C/gen.T_B*dv + (1 - gen.T_C/gen.T_B)*x_AVR;       # Lead-lag output 
#         F[16] = 1/gen.T_A*( gen.K_A*y_AVR*gen.Rf_d/gen.La_d - v_df);
#         F[17:18] = -T\[i_d;i_q]
#     end
        

#     # Setting up the equilibrium point based on the initial solution
    
#     # println("Overall steady-state solution")
#     # println(gen.equilibrium)

#     # Add outputs

#     # push!(exp_fin.args,
#     # :(  F[17:18] = -T\[i_d;i_q]))
    
#     state_vars = 16
#     input_vars = 3 # vd, vq, Tm
#     output_vars= 2

#     h!(F,x) = state_space_jac!(F, x[1:end-input_vars], x[end-input_vars+1:end], gen)
#     ha = x -> (F = fill(zero(eltype(x)), state_vars+output_vars); h!(F, x); return F)
#     jac = zeros(state_vars+output_vars, state_vars+input_vars)
#     ForwardDiff.jacobian!(jac, ha, [gen.equilibrium[1:state_vars];vector_inputs])

#     # State space matrices
#     A=jac[1:state_vars, 1:state_vars]
#     B=jac[1:state_vars, state_vars+1:end-1]
#     C=jac[state_vars+1:end, 1:state_vars]
#     D=jac[state_vars+1:end, state_vars+1:end-1]

#     B /= 1e3
#     C *= I_base * 1e3
#     D *= I_base 

#     # Update operating point
    
#     V = Vm
#     θ = θ
#     P = Pac
#     Q = Qac
#     equilibrium = init_x

#     op = OperatingPoint(;A,B,C,D,V,θ, P,Q,equilibrium)

#     return synchronousmachine(;elec, mech, avr, gov, op) # Return new element

# end



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


function make_power_flow!(machine:: SynchronousMachine, data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)

    # Check if AC or DC source (second one not implemented)
    # is_three_phase(elem) ? nothing : error("DC sources are currently not implemented")

    ### MAKE BUSES OUT OF THE NODES
    # Find the nodes not connected to the ground
    ac_nodes = make_non_ground_node(elem, bus2nodes) 
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)
    # Make busses for the non-ground nodes 
    interm_bus = add_interm_bus_ac!(data, global_dict) # No mapping to node, bcs no corresponding node in PowerImpedance

    # Make the generator component for injection
    key = injection_initialization!(data, elem2comp, comp2elem, interm_bus, elem, global_dict)
    key = string(key)

    # Add additional branch & bus for SM transformer (RL-branch)
    
    key_branch = length(data["branch"]) + 1
    key_branch_str = string(key_branch)

    (data["branch"])[key_branch_str] = Dict{String, Any}()
    ((data["branch"])[key_branch_str])["f_bus"] = interm_bus
    ((data["branch"])[key_branch_str])["t_bus"] = ac_bus
    ((data["branch"])[key_branch_str])["source_id"] = Any["branch", key_branch]
    ((data["branch"])[key_branch_str])["index"] = key_branch
    ((data["branch"])[key_branch_str])["rate_a"] = 1
    ((data["branch"])[key_branch_str])["rate_b"] = 1
    ((data["branch"])[key_branch_str])["rate_c"] = 1
    ((data["branch"])[key_branch_str])["br_status"] = 1
    ((data["branch"])[key_branch_str])["angmin"] = ang_min
    ((data["branch"])[key_branch_str])["angmax"] = ang_max
    ((data["branch"])[key_branch_str])["transformer"] = false
    ((data["branch"])[key_branch_str])["tap"] = 1
    ((data["branch"])[key_branch_str])["shift"] = 0
    ((data["branch"])[key_branch_str])["c_rating_a"] = 1

    
    ((data["branch"])[key_branch_str])["br_r"] = machine.elec.rt * (machine.elec.Vᵃᶜ_base^2 / machine.elec.S_base) / global_dict["Z"]
    ((data["branch"])[key_branch_str])["br_x"] = machine.elec.lt * (machine.elec.Vᵃᶜ_base^2 / machine.elec.S_base) / global_dict["Z"]
    ((data["branch"])[key_branch_str])["g_fr"] = 0
    ((data["branch"])[key_branch_str])["b_fr"] = 0
    ((data["branch"])[key_branch_str])["g_to"] = 0
    ((data["branch"])[key_branch_str])["b_to"] = 0

    # Change type of final bus, intermediate bus is PQ-bus
    if isapprox(elem.limits.P_max, elem.setpoint.Pac)
        ((data["bus"])[string(interm_bus)]) = set_bus_type((data["bus"])[string(interm_bus)], 1)
    else
        ((data["bus"])[string(interm_bus)]) = set_bus_type((data["bus"])[string(interm_bus)], 2)
    end

    ((data["bus"])[string(interm_bus)])["vm"] = ((data["gen"])[key])["vg"]
    ((data["bus"])[string(interm_bus)])["vmin"] =  0.9*((data["gen"])[key])["vg"]
    ((data["bus"])[string(interm_bus)])["vmax"] =  1.1*((data["gen"])[key])["vg"]
end