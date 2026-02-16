export synchronousmachine


# include("controller.jl") # Removed this for now, will need to think in the future how to implement controllers for SGs.
# TODO: Right now, second pins of the SG should be connected to the ground.
@with_kw mutable struct SynchronousMachine <: Machine
    wn :: Union{Int, Float64} = 100*π
    
    # Base values
    Vᵃᶜ_base :: Union{Int, Float64} = 220 # Converter AC voltage base, LL, RMS [kV]
    S_base :: Union{Int, Float64} = 1000 # Converter AC voltage base, LL, RMS [kV]

    # Transformer (RL-branch model)
    lt :: Union{Int, Float64} = 0.065 # [pu]
    rt :: Union{Int, Float64} = 0.0026 # [pu]

    # Modified Kundur's example
    La_d :: Union{Int, Float64} = 1.66 # d-axis magnetizing inductance
    La_q :: Union{Int, Float64} = 1.61 # q-axis magnetizing inductance
    Ll :: Union{Int, Float64} = 0.15    # Stator leakage inductance
    Ra :: Union{Int, Float64} = 0.0015  # Armature resistance

    Lf_d :: Union{Int, Float64} = 0.165  # Field leakage inductance
    L1_d :: Union{Int, Float64} = 0.1713 # d-axis damper winding inductance
    L1_q :: Union{Int, Float64} = 0.7252 # q-axis first damper winding inductance
    L2_q :: Union{Int, Float64} = 0.125  # q-axis second damper winding inductance

    # No mutual inductance
    L23_d :: Union{Int, Float64} = 0 # d-axis field-damper mutual inductance
    L23_q :: Union{Int, Float64} = 0 # q-axis damper-damper mutual inductance

    Rf_d :: Union{Int, Float64} = 0.0002 # Field circuit resistance
    R1_d :: Union{Int, Float64} = 0.0200 # d-axis damper winding resistance
    R1_q :: Union{Int, Float64} = 0.0050 # q-axis first damper winding resistance
    R2_q :: Union{Int, Float64} = 0.0100 # q-axis second damper winding resistance

    H :: Union{Int, Float64} = 4 # Inertia constant [s]

    # Steam turbine
    T_CH :: Union{Int, Float64} = 2 # Steam chest time constant [s]
    T_RH :: Union{Int, Float64} = 5 # Reheater time constant [s]
    T_CO :: Union{Int, Float64} = 1 # Cross-over time constant [s]
    F_HP :: Union{Int, Float64} = 0.3 # High presure turbine fraction [pu]
    F_IP :: Union{Int, Float64} = 0.4 # Intermediate presure turbine fraction [pu]
    F_LP :: Union{Int, Float64} = 0.3 # Low presure turbine fraction [pu]

    # Governor
    T_w :: Union{Int, Float64} = 0.1 # Speed lag time constant [s]
    T_G :: Union{Int, Float64} = 0.2 # Time constant of the governor [s]
    R :: Union{Int, Float64} = 0.05   # Frequency control droop / Inverse of the gain [pu/pu]

    # AVR
    vref_SG :: Union{Int, Float64}   = 1.01 # Terminal voltage magnitude reference [pu]
    T_R :: Union{Int, Float64}       = 0.05     # Terminal voltage filter time constant [s]
    T_B :: Union{Int, Float64}       = 1.0       # Lag time constant [s]
    T_C :: Union{Int, Float64}       = 0.1        # Lead time constant [s]
    T_A :: Union{Int, Float64}       = 0.02    # Regulator (lag) time constant [s]
    K_A :: Union{Int, Float64}       = 200      # Regulator gain [pu]

    P :: Union{Int, Float64} = 0              # active power [MW]
    Q :: Union{Int, Float64} = 0                # reactive power [MVA]
    P_min :: Union{Float64, Int} = -100         # min active power output [MW]
    P_max :: Union{Float64, Int} = 100          # max active power output [MW]
    Q_min :: Union{Float64, Int} = -50          # min reactive power output [MVA]
    Q_max :: Union{Float64, Int} = 50           # max reactive power output [MVA]

    θ :: Union{Int, Float64} = 0
    V :: Union{Int, Float64} = 220*sqrt(2/3)             # AC voltage, amplitude [kV]

    # controls :: OrderedDict{Symbol, Controller} = OrderedDict{Symbol, Controller}() # Disabled for now
    equilibrium :: Array{Union{Int, Float64}} = [0]
    A :: Array{Complex} = [0]
    B :: Array{Complex} = [0]
    C :: Array{Complex} = [0]
    D :: Array{Complex} = [0]

end


function synchronousmachine(;args...)
    gen = SynchronousMachine()
    connection = true
    for (key, val) in pairs(args)
        if in(key, propertynames(gen))
            setfield!(gen, key, val)
        elseif (key == :connection)
            connection = val
        else
            throw(ArgumentError("Machine does not have a property $(key)."))
        end
    end
    # Transformation property set to false, as model is natively defined in dq-frame
    elem = Element(input_pins = 2, output_pins = 2, element_value = gen, transformation = false, connection = connection)
end

function update!(gen :: SynchronousMachine, Pac, Qac, Vm, θ) # TODO: Removed Pac and Qac from this function, see if it will be necessary.
    Ld = gen.La_d + gen.Ll + gen.lt
    Lf1_d = gen.La_d + gen.L23_d
    Lff_d = Lf1_d + gen.Lf_d
    L11_d = Lf1_d + gen.L1_d

    Lq  = gen.La_q + gen.Ll + gen.lt
    L11_q  = gen.L1_q + gen.La_q
    L22_q  = gen.L2_q + gen.La_q

    Z_base = gen.Vᵃᶜ_base^2 / gen.S_base
    I_base = sqrt(2/3)*gen.S_base / gen.Vᵃᶜ_base
    

    gen.V = Vm
    gen.θ = θ
    gen.P = Pac
    gen.Q = Qac

    init_x = zeros(16, 1) # TODO: Automatize this based on the presence of the AVR.

    # Initialization values

    v_bus_d0 = gen.V * cos(θ) /  (gen.Vᵃᶜ_base * sqrt(2/3))
    v_bus_q0 = -gen.V * sin(θ) / (gen.Vᵃᶜ_base * sqrt(2/3))
    # Initialization without an AVR
    # e_df0   = 0.005 * 200 * gen.Rf_d/gen.La_d # Exciter [pu]
    # Tm0     = 0.5                     # Mechanical torque [pu]
    Tm0 = gen.P / gen.S_base

    # State variables initialization
    # Damper winding currents initialized at zero. These are located at indices 3, 5 and 6. The same also holds for the filtered speed difference at index 9
    # init_x[2] = e_df0 / gen.Rf_d # In the absence of an AVR
    init_x[7] = 1 # initialize the inital rotating speed to 1
    init_x[10:13] = [Tm0;Tm0;Tm0;Tm0] # initialize all the torques to be the same as the mechanical torque
    # The remaining state variables to be initialized are the stator currents (indices 1 and 4) and the angular position of the rotor reference frame (index 8)

    exp_init = Expr(:block)
    # Initialization without an AVR
    # input1 - vd
    # input2 - vq
    # input3 - if
    # input4 - TH
    # input5 - TI
    # input6 - TL
    # input7 - e_df
    # State variables without AVR: id, iq, w_pu
    # push!(exp_init.args, :(
        
    #     theta_grid = 0; 
    #     d = (x[4] - theta_grid);
    #     T = [cos(d) -sin(d);
    #         sin(d)  cos(d)]; 
    #     v_dq = T*inputs[1:2];
    #     flux_d = - $Ld*x[1] + $gen.La_d*inputs[3]; # d-axis flux
    #     flux_q = - $Lq*x[2];  # q-axis flux

    #     L_D = [-$Ld       $gen.La_d   $gen.La_d; 
    #         -$gen.La_d   $Lff_d      $Lf1_d;
    #         -$gen.La_d   $Lf1_d      $L11_d];

    #     L_Q = [-$Lq       $gen.La_q    $gen.La_q; 
    #         -$gen.La_q   $L11_q       $gen.La_q;
    #         -$gen.La_q   $gen.La_q    $L22_q];
        
    #     RHS_D = $gen.wn*[(v_dq[1]  +	$gen.Ra*x[1] - x[3]*flux_q);
    #                 (inputs[7] -	$gen.Rf_d*inputs[3]);
    #                 0];

    #     RHS_Q = $gen.wn*[(v_dq[2]  +  $gen.Ra*x[2] + x[3]*flux_d);
    #                 0;
    #                 0];
    #     diD_dt = L_D \ RHS_D;
    #     diQ_dt = L_Q \ RHS_Q;

    #     F[1] = diD_dt[1];
    #     F[2] = diQ_dt[1];
        
    #     T_turb = $gen.F_HP*inputs[4] + $gen.F_IP*inputs[5] + $gen.F_LP*inputs[6];
    #     Te = -(flux_d*x[2] - flux_q*x[1]); 

    #     F[3] = (T_turb - Te)/(2*$gen.H);
    #     F[4] = $gen.wn*(x[3] - 1)))

    # With AVR
    # input1 - vd
    # input2 - vq
    # input3 - flow
    # input4 - TH
    # input5 - TI
    # input6 - TL
    function state_space_equil!(F,x,inputs,gen)
        i_d         = x[1];        # d-axis stator current
        i_df        = x[2];        # Field current
        i_d1        = 0;        # d-axis damping winding current

        i_q         = x[3];         # q-axis stator current
        i_q1        = 0;        # q-axis 1st damping winding current
        i_q2        = 0;        # q-axis 2nd damping winding current

        w_pu        = x[4];            # Per unit rotor angular speed omega/omega_n
        theta_sg    = x[5];        # Angular position of the rotor reference frame
        TchHP       = inputs[3];          # Steam chest HP torque [pu]
        TreIP       = inputs[4];          # Reheater IP torque [pu]
        TcrLP       = inputs[5];          # Crossover LP torque [pu]

        # AVR-related states

        v_f         = x[6];
        x_AVR       = x[7];
        v_df        = x[8];

        v_bus_d = inputs[1];  # d-axis grid voltage [pu]
        v_bus_q = inputs[2]; # q-axis grid voltage [pu]

        # theta_grid = atan(-v_bus_q,v_bus_d);
        theta_grid = 0;  
        d = theta_sg - theta_grid; # New reference frame angle - old RF angle
        T = [cos(d) -sin(d);
            sin(d)  cos(d)]; # Rotation to rotor's RF
        Wpu = [0 1;-1 0]; # Rotation matrix multiplied by the derivative of its inverse
        v_dq = T*[v_bus_d; v_bus_q];
        v_d = v_dq[1];
        v_q = v_dq[2];

        # SG (d-aligned, q-lagging)
        # Same eqs. as Paul C. Krause book but with qd swaped by dq
        # In addition, Te is computed for generator operation 

        flux_d = - Ld*i_d + gen.La_d*(i_df + i_d1); # d-axis flux
        flux_q = - Lq*i_q + gen.La_q*(i_q1 + i_q2); # q-axis flux

        Te = -(flux_d*i_q - flux_q*i_d); # Generator operation electrical torque n_ppoles*w_m = w_e

        L_D = [-Ld       gen.La_d   gen.La_d; 
            -gen.La_d   Lff_d      Lf1_d;
            -gen.La_d   Lf1_d      L11_d];

        L_Q = [-Lq       gen.La_q   gen.La_q; 
            -gen.La_q   L11_q       gen.La_q;
            -gen.La_q   gen.La_q    L22_q];

        RHS_D = gen.wn*[(v_d  +	(gen.Ra+gen.rt)*i_d	- w_pu*flux_q);
                    (v_df -	gen.Rf_d*i_df);
                    (0    - gen.R1_d*i_d1)];

        RHS_Q = gen.wn*[(v_q  +  (gen.Ra+gen.rt)*i_q + w_pu*flux_d);
                    (0    -  gen.R1_q*i_q1);
                    (0    -  gen.R2_q*i_q2)];

        did_dt = L_D \ RHS_D;
        diq_dt = L_Q \ RHS_Q;

        F[1:2] =  did_dt[1:2];
        F[3] =  diq_dt[1];

        T_turb = gen.F_HP*TchHP +gen.F_IP*TreIP + gen.F_LP*TcrLP;

        F[4] = (T_turb - Te)/(2*gen.H);   # Newton's II Law
        F[5] = gen.wn*(w_pu - 1);
        
        # AVR and exciter
        v_t = v_dq + gen.rt*[i_d;i_q] + w_pu*gen.lt*Wpu*[i_d;i_q] + gen.lt/gen.wn*[F[1];F[3]]; # Machine terminal voltage

        F[6] = 1/gen.T_R*(sqrt(v_t[1]*v_t[1]+v_t[2]*v_t[2]) - v_f);        # Voltage magnitude measurement (LPF)
        dv = gen.vref_SG - v_f;                             # Error TODO: The voltage reference can be made an input to the state-space model.
        F[7] = 1/gen.T_B*(dv - x_AVR);                 # Lead-lag state
        y_AVR = gen.T_C/gen.T_B*dv + (1 - gen.T_C/gen.T_B)*x_AVR;       # Lead-lag output 
        F[8] = 1/gen.T_A*( gen.K_A*y_AVR*gen.Rf_d/gen.La_d - v_df)    
    end

    inputs_init = [v_bus_d0;v_bus_q0;Tm0;Tm0;Tm0]    

    function f!(expr, F, x, inputs) # F derivative of state variable x state variable vector, inputs input vqlue expr equation of mmc
        f = eval(:((F,x,inputs) -> $expr))
        return Base.invokelatest(f, F,x,inputs)
    end
    init_init = zeros(8,1)
    init_init[4] = 1
    g!(du,u,p) = state_space_equil!(du, u, p[1], p[2]) # g is the state-space formulation used to obtain the steady-state operation point, copy from f, see some lines above
    println("Starting to solve for Steady-State Solution!")
    prob = NonlinearProblem(g!, init_init, (inputs_init, gen))
    sol=solve(prob;maxiters=20,abstol = 1e-6,reltol = 1e-6)
    if SciMLBase.successful_retcode(sol)
        println("SG steady-state solution found!")
    else
        error("SG steady-state solution not found!")
    end
    equilibrium_init = sol.u

    # k!(F,x) = f!(exp_init, F, x, inputs_init)
    # init_init = zeros(8,1)
    # init_init[4] = 1
    # k_init = nlsolve(k!, init_init , autodiff = :forward, iterations = 200, ftol = 1e-6, xtol = 1e-3, method = :trust_region)
    # if converged(k_init)
    #     println("SG steady-state solution found!")
    # end
    # equilibrium_init= k_init.zero #debug here
    # println("Inputs for the steady state solution")
    # println(inputs_init)
    # println("Steady state solution")
    # println(equilibrium_init)
    init_x[1] = equilibrium_init[1]
    init_x[2] = equilibrium_init[2]
    init_x[4] = equilibrium_init[3]
    init_x[8] = equilibrium_init[5]
    init_x[14] = equilibrium_init[6]
    init_x[15] = equilibrium_init[7]
    init_x[16] = equilibrium_init[8]

    # vector_inputs = [v_bus_d0;v_bus_q0;Tm0] # voltages are not in pu here!
    vector_inputs = [gen.V * cos(θ); -gen.V * sin(θ);Tm0]
    # setup control parameters and equations 
    # TODO: for now, AVR is added as a standard. Can make it optional in the future.
    
    # add state variables
    exp_fin = Expr(:block)
    function state_space_jac!(F, x, inputs, gen)
   
        i_d         = x[1];        # d-axis stator current
        i_df        = x[2];        # Field current
        i_d1        = x[3];        # d-axis damping winding current

        i_q         = x[4];         # q-axis stator current
        i_q1        = x[5];        # q-axis 1st damping winding current
        i_q2        = x[6];        # q-axis 2nd damping winding current

        w_pu        = x[7];            # Per unit rotor angular speed omega/omega_n
        theta_sg    = x[8];        # Angular position of the rotor reference frame
        dw_filt     = x[9];          # Speed difference filtered [pu]
        flow        = x[10];           # Turbine valve flow [pu]
        TchHP       = x[11];          # Steam chest HP torque [pu]
        TreIP       = x[12];          # Reheater IP torque [pu]
        TcrLP       = x[13];          # Crossover LP torque [pu]

        # AVR-related states

        v_f         = x[14];
        x_AVR       = x[15];
        v_df        = x[16];

        v_bus_d = inputs[1] /  (gen.Vᵃᶜ_base * sqrt(2/3)); # d-axis grid voltage [pu]
        v_bus_q = inputs[2] /  (gen.Vᵃᶜ_base * sqrt(2/3)); # q-axis grid voltage [pu]
        Tm      = inputs[3];  # Initial torque [pu] # When the AVR is not implemented, this input is the field voltage e_df

        # Infinite bus
        # theta_grid = atan(-v_bus_q,v_bus_d);
        theta_grid = 0; # The angle of the global dq reference frame
        d = theta_sg - theta_grid; # New reference frame angle - old RF angle
        T = [cos(d) -sin(d);
            sin(d)  cos(d)]; # Rotation to rotor's RF
        Wpu = [0 1;-1 0]; # Rotation matrix multiplied by the derivative of its inverse
        v_dq = T*[v_bus_d; v_bus_q];
        v_d = v_dq[1];
        v_q = v_dq[2];

        # SG (d-aligned, q-lagging)
        # Same eqs. as Paul C. Krause book but with qd swaped by dq
        # In addition, Te is computed for generator operation 
        L_D = [-Ld       gen.La_d   gen.La_d; 
            -gen.La_d   Lff_d      Lf1_d;
            -gen.La_d   Lf1_d      L11_d];

        L_Q = [-Lq       gen.La_q    gen.La_q; 
            -gen.La_q   L11_q       gen.La_q;
            -gen.La_q   gen.La_q    L22_q];

        flux_d = - Ld*i_d + gen.La_d*(i_df + i_d1); # d-axis flux
        flux_q = - Lq*i_q + gen.La_q*(i_q1 + i_q2); # q-axis flux

        Te = -(flux_d*i_q - flux_q*i_d); # Generator operation electrical torque n_ppoles*w_m = w_e

        RHS_D = gen.wn*[(v_d  +	(gen.Ra+gen.rt)*i_d	- w_pu*flux_q);
                    (v_df -	gen.Rf_d*i_df);
                    (0    - gen.R1_d*i_d1)];

        RHS_Q = gen.wn*[(v_q  +  (gen.Ra+gen.rt)*i_q + w_pu*flux_d);
                    (0    -  gen.R1_q*i_q1);
                    (0    -  gen.R2_q*i_q2)];

        F[1:3] = L_D \ RHS_D;
        F[4:6] = L_Q \ RHS_Q;

        T_turb = gen.F_HP*TchHP + gen.F_IP*TreIP + gen.F_LP*TcrLP;

        F[7] = (T_turb - Te)/(2*gen.H);   # Newton's II Law
        F[8] = gen.wn*(w_pu - 1);

        # Mechanical equations for the governor
        F[9] = 1/gen.T_w*( 1 - w_pu  - dw_filt ); # Governor frequency filter
        F[10] = 1/gen.T_G*( dw_filt/gen.R + Tm - flow); # Servo TF

        F[11] = 1/gen.T_CH*(flow  - TchHP); # HP turbine fraction
        F[12] = 1/gen.T_RH*(TchHP - TreIP); # IP turbine fraction
        F[13] = 1/gen.T_CO*(TreIP - TcrLP); # LP turbine fraction
        
        # AVR and exciter
        v_t = v_dq +gen.rt*[i_d;i_q] + w_pu*gen.lt*Wpu*[i_d;i_q] + gen.lt/gen.wn*[F[1];F[4]]; # Machine terminal voltage
        
        # F[14] = 1/$gen.T_R*(sqrt(transpose(v_t)*v_t) - v_f);        # Voltage magnitude measurement (LPF)
        F[14] = 1/gen.T_R*(sqrt(v_t[1]*v_t[1]+v_t[2]*v_t[2]) - v_f);        # Voltage magnitude measurement (LPF)
        dv = gen.vref_SG - v_f;                             # Error TODO: The voltage reference can be made an input to the state-space model.
        F[15] = 1/gen.T_B*(dv - x_AVR);                 # Lead-lag state
        y_AVR = gen.T_C/gen.T_B*dv + (1 - gen.T_C/gen.T_B)*x_AVR;       # Lead-lag output 
        F[16] = 1/gen.T_A*( gen.K_A*y_AVR*gen.Rf_d/gen.La_d - v_df);
        F[17:18] = -T\[i_d;i_q]
    end
        

    # Setting up the equilibrium point based on the initial solution
    gen.equilibrium = init_x
    # println("Overall steady-state solution")
    # println(gen.equilibrium)

    # Add outputs

    # push!(exp_fin.args,
    # :(  F[17:18] = -T\[i_d;i_q]))
    
    state_vars = 16
    input_vars = 3 # vd, vq, Tm
    output_vars= 2

    h!(F,x) = state_space_jac!(F, x[1:end-input_vars], x[end-input_vars+1:end], gen)
    ha = x -> (F = fill(zero(eltype(x)), state_vars+output_vars); h!(F, x); return F)
    jac = zeros(state_vars+output_vars, state_vars+input_vars)
    ForwardDiff.jacobian!(jac, ha, [gen.equilibrium[1:state_vars];vector_inputs])

    # State space matrices
    gen.A=jac[1:state_vars, 1:state_vars]
    gen.B=jac[1:state_vars, state_vars+1:end-1]
    gen.C=jac[state_vars+1:end, 1:state_vars]
    gen.D=jac[state_vars+1:end, state_vars+1:end-1]

    gen.B /= 1e3
    gen.C *= I_base * 1e3
    gen.D *= I_base 

    # writedlm( "A.csv",  gen.A, ',')
    # writedlm( "B.csv",  gen.B, ',')
    # writedlm( "C.csv",  gen.C, ',')
    # writedlm( "D.csv",  gen.D, ',')
end



function eval_parameters(gen :: SynchronousMachine, s :: Complex)
    # numerical
    I = Matrix{Complex}(Diagonal([1 for dummy in 1:size(gen.A,1)]))
    Y = (gen.C*inv(s*I-gen.A))*gen.B + gen.D

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