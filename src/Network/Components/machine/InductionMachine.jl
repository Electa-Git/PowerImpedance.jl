export inductionmachine, TorqueModel, InductionMachine


# include("controller.jl") # Removed this for now, will need to think in the future how to implement controllers for SGs.
# TODO: Right now, second pins of the SG should be connected to the ground.
@with_kw mutable struct InductionMachine <: Machine
    
    
    ω_n :: Union{Int, Float64} = 2*50*π
    p_f:: Union{Int, Float64} = 2 # Nb. of poles (2 per 3phase winding set)

    # Base values
    Vᵃᶜ_base :: Union{Int, Float64} = 220 # Converter AC voltage base, LL, RMS [kV]
    S_base :: Union{Int, Float64} = 1000 # Converter AC voltage base, LL, RMS [kV]

    # Transformer (RL-branch model), default no transformer
    lt :: Union{Int, Float64} = 0 #0.065 # [pu]
    rt :: Union{Int, Float64} = 0# 0.0026 # [pu]

    # Values from Harnefors (in same format as SM)
    l_m :: Union{Int, Float64} = 1.66 # magnetizing inductance [pu] (same for d,q)
    l_sl :: Union{Int, Float64} = 0.15  # Stator leakage inductance [pu]
    r_s :: Union{Int, Float64} = 0.0015  # Stator/Armature resistance [pu]

    l_rl :: Union{Int, Float64} = 0.165  # Rotor/Field leakage inductance [pu]
    r_r :: Union{Int, Float64} = 0.01 # Rotor/field circuit resistance [pu]


    H :: Union{Int, Float64} = 4 # Inertia constant [s]

    # Load model (T0(Aω^(m)+Bω+C)) for parabolic m=2, B=C=0
    torque = TorqueModel() # Container for load coefficients
    T_0 :: Union{Int, Float64} =0.9 # Synchronous torque [pu]
   
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

struct TorqueModel
    A :: Union{Int, Float64} # Parabolic constant [pu]
    B :: Union{Int, Float64} # Linear constant [pu]
    C :: Union{Int, Float64} # Constant [pu]
    m :: Int # Load model exponent
end
function TorqueModel(;model_type="constant", A=0,B=0, C=1, m=1)

    if model_type == "quadratic" # Parabolic load model
        # Warn about possible modeling mistake
        if A == 0 && B == 0
            println("Parabolic load model specified with no parabolic (A) or linear (B) coefficient")
            A = 1
            C=0
        end
        m = 2 
    elseif model_type == "power" # 
        if m == 0
            println("No exponent (m) defined")
            m=2
        end
        B = 0
        C= 0
    elseif model_type=="constant"
        A = 0
        B = 0
        C=1
        m=1
    end
    return TorqueModel(A,B,C,m)
end

function inductionmachine(;args...)
    gen = InductionMachine()
    for (key, val) in pairs(args)
        if in(key, propertynames(gen))
            setfield!(gen, key, val)                                                        
        else
            throw(ArgumentError("Machine does not have a property $(key)."))
        end
    end

    elem = Element(input_pins = 2, output_pins = 2, element_value = gen)
end


function state_space(x;gen::InductionMachine, V)    
          
         # Parameter calculations

            ## Inverse Γ-model (book Harnefors)
            l_s = gen.l_m + gen.l_sl + gen.lt # + transformer impedance
            l_r = gen.l_m + gen.l_rl

            # Refer rotor leakage to stator
            l_M = gen.l_m^2/l_r;
            l_σ = l_s-l_M

            # Equivalent resistance
            r_eq = gen.r_s+ gen.rt
            r_R = (gen.l_m/l_r)^2*gen.r_r

            # Steady-state torque
            T0 = gen.T_0

            # Base values
            Z_base = gen.Vᵃᶜ_base^2 / gen.S_base
            I_base = sqrt(2/3)*gen.S_base / gen.Vᵃᶜ_base
            Ψ_base = gen.Vᵃᶜ_base/ gen.ω_n
            τ_base = 3/2*(gen.p_f/2)*Ψ_base*I_base
            ### States
            i_d     = x[1]  # d-axis stator current
            i_q     = x[2]  # q-axis stator current
            Ψ_df    = x[3]  # Rotor field d-axis
            Ψ_qf    = x[4]  # Rotor field q-axis

            ω_r     = x[5]  # Per unit rotor angular speed omega/omega_n

            ### Inputs
            v_d = V[1]#inputs[1] # d-axis grid voltage [pu]
            v_q = V[2]#inputs[2] # q-axis grid voltage [pu]

        

            # Individual equations for performance (NLSolve for small problems)

            # Current state equations
            F1 = gen.ω_n / l_σ *(v_d-(r_eq+r_R)*i_d + l_σ*i_q + ω_r*Ψ_qf + r_R/l_M*Ψ_df)
            F2 = gen.ω_n / l_σ *(v_q-(r_eq+r_R)*i_q - l_σ*i_d - ω_r*Ψ_df + r_R/l_M*Ψ_qf)

            # Rotor flux state equations
            F3 = gen.ω_n*(r_R*i_d - (r_R/l_M)*Ψ_df + (1.0 - ω_r) * Ψ_qf)
            F4 = gen.ω_n*(r_R*i_q - (r_R/l_M)*Ψ_qf - (1.0 - ω_r) * Ψ_df)

            # Mechanical equations

            τ_e = (Ψ_df*i_q - Ψ_qf*i_d); # Opposite of SM (generating torque (motor) <> using torque (SM)). TODO: Uniformize this
            τ_m = T0 *(gen.torque.A*ω_r^(gen.torque.m) + gen.torque.B * ω_r + gen.torque.C)
            F5 = (1/(2*gen.H) * (τ_e-τ_m))
        
            

            return [F1,F2,F3,F4,F5]
end

function update!(gen :: InductionMachine, Pac, Qac, Vm, θ)
    
    # Parameter calculations

     ## Inverse Γ-model (book Harnefors)
    l_s = gen.l_m + gen.l_sl + gen.lt # + transformer impedance
    l_r = gen.l_m + gen.l_rl

    # Refer rotor leakage to stator
    l_M = gen.l_m^2/l_r;
    l_σ = l_s-l_M

    # Equivalent resistance
    r_eq = gen.r_s+ gen.rt
    r_R = (gen.l_m/l_r)^2*gen.r_r

    # Steady-state torque
    T_0 = gen.T_0

    # Base values
    Z_base = gen.Vᵃᶜ_base^2 / gen.S_base
    I_base = sqrt(2/3)*gen.S_base / gen.Vᵃᶜ_base
    Ψ_base = gen.Vᵃᶜ_base/ gen.ω_n
    τ_base = 3/2*(gen.p_f/2)*Ψ_base*I_base


    gen.V = Vm
    gen.θ = θ
    gen.P = Pac
    gen.Q = Qac

    # Initialization values (Put here in dq-leading, convert later back to lagging)

    v_bus_d0 = gen.V * cos(θ) /  (gen.Vᵃᶜ_base * sqrt(2/3))
    v_bus_q0 = gen.V * sin(θ) / (gen.Vᵃᶜ_base * sqrt(2/3))
    
    inputs_vector = [v_bus_d0;v_bus_q0] # voltages are in pu here!
   
    x0_ss = [T_0,T_0,1.0,0.0,1.0]
    f(u,p) = state_space(u;gen=p[1], V=p[2])
    prob = NonlinearProblem(f, x0_ss, (gen, (v_bus_d0,v_bus_q0)))
    nb_states = 5
    nb_outputs=2
    nb_inputs=2
    println("Starting to solve for Steady-State Solution!")
    sol_ss = solve(prob, SimpleNewtonRaphson(), maxiters=20,abstol = 1e-6,reltol = 1e-6)
    if SciMLBase.successful_retcode(sol_ss)
        println("IM steady-state solution found!")
    else
        println("IM steady-state solution not found!")
    end
    h(u) = state_space(u[1:end-nb_inputs];gen, V = u[end-nb_inputs+1:end])
    jac=zeros(nb_states,nb_states+nb_inputs)
    ForwardDiff.jacobian!(jac,h,[sol_ss;1.0;0])
    gen.A = jac[1:nb_states, 1:nb_states]
    gen.B = jac[1:nb_states, nb_states+1:end]
    gen.B[:,2] = -gen.B[:,2]
    gen.C = [1 0 0 0 0;0 -1 0 0 0] #Convert from dq-leading to dq-lagging
    gen.D = [0.0 0.0 ;0.0 0.0]
   

    

    
    

    # Setting up the equilibrium point based on the initial solution
    gen.equilibrium = sol_ss
    # println("Overall steady-state solution")
    # println(gen.equilibrium)

    gen.C /= Z_base 
    gen.D /= Z_base 

    # writedlm( "A.csv",  gen.A, ',')
    # writedlm( "B.csv",  gen.B, ',')
    # writedlm( "C.csv",  gen.C, ',')
    # writedlm( "D.csv",  gen.D, ',')
end


function eval_parameters(gen :: InductionMachine, s :: Complex)
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

function eval_abcd(gen :: InductionMachine, s :: Complex)
    return eval_y(gen, s)
end

function eval_y(gen :: InductionMachine, s :: Complex)
    Y = eval_parameters(gen, s)
    return Y
end

function make_power_flow!(machine:: InductionMachine, data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)

    # Check if AC or DC source (second one not implemented)
    # is_three_phase(elem) ? nothing : error("DC sources are currently not implemented")

    ### MAKE BUSES OUT OF THE NODES
    # Find the nodes not connected to the ground
    ac_nodes = make_non_ground_node(elem, bus2nodes) 
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)

    key = comp_elem_interface!(data, elem2comp, comp2elem, elem, "im")
    key_str = string(key)
    data["im"][key_str] = Dict{String, Any}()

    torque = machine.torque
    # Power flow initial values
    data["im"][key_str]["P_ag"] = machine.T_0
    data["im"][key_str]["Q_ag"] = 0.0
    data["im"][key_str]["status"] = 1
    data["im"][key_str]["im_bus"] = ac_bus

    # Power flow limits (not used in power flow)
    data["im"][key_str]["Pacmin"] = 0.9 * machine.T_0
    data["im"][key_str]["Vmmin"] = 0.9 # Should be extended with local_base/global_base but we do not care (not used in PF)
    data["im"][key_str]["Vmmax"] = 1.1
    data["im"][key_str]["Pacmax"] = 1.1 * machine.T_0
    data["im"][key_str]["Pacrated"] = machine.T_0

    # Power flow elements
    data["im"][key_str]["x_m"] = machine.l_m # In per unit equal
    data["im"][key_str]["x_rl"] = machine.l_rl
    data["im"][key_str]["x_sl"] = machine.l_sl
    data["im"][key_str]["r_r"] = machine.r_r
    data["im"][key_str]["r_s"] = machine.r_s

    # Torque parameters
    data["im"][key_str]["torque"] =  Dict{String, Any}()
    data["im"][key_str]["torque"]["T_0"] = machine.T_0 
    data["im"][key_str]["torque"]["A"] = torque.A
    data["im"][key_str]["torque"]["B"] = torque.B
    data["im"][key_str]["torque"]["C"] = torque.C
    data["im"][key_str]["torque"]["m"] = torque.m
   
    
end