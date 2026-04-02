

abstract type AbstractStateSpace <: AbstractElementModel end

# Function for ordering states & initialvalues. Puts all that are not defined to zero & discards initial values that do not appear in statenames 
# TODO: Find proper name, add check for discrepancy statenames and initialvalues
orderedinitialvalues(x;kwargs...) = NamedTuple{statenames(x)}((;NamedTuple{statenames(x)}(ntuple(i->0.0,length(statenames(x))))..., initialvalues(x;kwargs...)...))
# statenamesmodular(m::AbstractStateSpace) = merge([statenames(getfield(m,n)) for n in fieldnames(typeof(m))]...)
n_states(m::AbstractStateSpace) = length(statenames(m))
n_inputs(m::AbstractStateSpace) = length(inputnames(m))
n_outputs(m::AbstractStateSpace) = length(outputnames(m))
n_elec_inputs(m::AbstractStateSpace) = length(elecinputnames(m))

# Default for elecinputnames (only different for SM atm)
elecinputnames(m::AbstractStateSpace) = inputnames(m)


### Solution methods (additional equations dummyequations or outputequations)
abstract type AbstractSolveKind end
# Types for form of state-space equations
struct Equil <: AbstractSolveKind end
struct Jac <: AbstractSolveKind end

### Dispatch on modeler functions
# Equilib
solvekindequations!(F,x,inputs,y,m::AbstractStateSpace, solvekind::Equil) = dummyequations!(F,x,inputs,y,m::AbstractStateSpace)
solvekindnames(m::AbstractStateSpace, solvekind::Equil) = dummynames(m::AbstractStateSpace)

solvekindequations!(F,x,inputs,y,m::AbstractStateSpace, solvekind::Jac) = outputequations!(F,x,inputs,y,m::AbstractStateSpace)
solvekindnames(m::AbstractStateSpace, solvekind::Jac) = outputnames(m::AbstractStateSpace)

### Define default functions (they don't do anything), if no specific method is defined
solvekindequations!(F,x,inputs,y,m::AbstractStateSpace, solvekind::AbstractSolveKind) = nothing
solvekindnames(m::AbstractStateSpace, solvekind::AbstractSolveKind) = (;)

dummyequations!(F,x,inputs,y,m::AbstractStateSpace) = nothing
dummynames(m::AbstractStateSpace) = (;)

outputequations!(F,x,inputs,y,m::AbstractStateSpace) = nothing
outputnames(m::AbstractStateSpace) = (;)

equilibrium_state_space!(F, x, inputs, m::AbstractStateSpace, setpoint::SetPoint) =
    state_space!(F, x, inputs, m)

function _state_space!(F, x, inputs, m::AbstractStateSpace, solvekind::AbstractSolveKind)
    
    # Convert vector states to NamedTuple with keys the statenames (we enforce the same order)
    x_names = statenames(m)
    # F_names = (x_names..., solvekindnames(m, solvekind)...) TODO: Think about this
    x_nt = NamedTuple{x_names}(x)
    inputs_nt = NamedTuple{inputnames(m)}(inputs)
    
    # To where state space equations fill up F
    index_stsp = n_states(m)

    # Call the modeler's state space functions, certain algebr variables can be returned to be used by outputequations or dummyequations
    y = state_space!(@view(F[1:index_stsp]), x_nt, inputs_nt, m)
    
    # Modify output/dummy equations
    solvekindequations!(@view(F[index_stsp+1:end]),x_nt,inputs_nt, y, m, solvekind)

    return

end

# function _equilibrium_space!(F, x, inputs, m::AbstractStateSpace, setpoint::SetPoint)
#     x_names = statenames(m)
#     x_nt = NamedTuple{x_names}(x)
#     inputs_nt = NamedTuple{inputnames(m)}(inputs)

#     index_stsp = n_states(m)

#     equilibrium_state_space!(@view(F[1:index_stsp]), x_nt, inputs_nt, m, setpoint)
#     solvekindequations!(@view(F[index_stsp+1:end]), x_nt, inputs_nt, m, Equil())

#     return
# end
    
function update!(elem::Element, m::AbstractStateSpace, setpoint::SetPoint)

    # Power flow to inputs of state_space function
    global inputs = pftoinputs(m, setpoint)
    inputs_vec = collect(values(inputs))
    # Initial values
    global init = orderedinitialvalues(m;setpoint, inputs)

    # Parameters for equilibirum with NonlinearSolve.jl
    p_equil=(;inputs=inputs_vec, m, solvekind=Equil())

    # Initialize problem
    f!(du,u,p) = _state_space!(du, u, p.inputs, p.m, p.solvekind)
    println("Starting to solve for steady-state solution")
    prob = NonlinearProblem(f!, collect(values(init)), p_equil)
    global sol=solve(prob;maxiters=20,abstol = 1e-6,reltol = 1e-6)
    
    # Solve nonlinear problem
    if SciMLBase.successful_retcode(sol)
        println("$(elem.symbol) steady-state solution found!")
    else
        error("$(elem.symbol) steady-state solution not found!")
    end 
    global equilibrium = sol.u[1:n_states(m)] #Discarding the equilibrium value for dummy states
    
    # Calculate Jacobian
    nb_states = n_states(m)
    nb_inputs = n_inputs(m) # vd, vq, Tm
    nb_elec_inputs = n_elec_inputs(m)
    nb_addit_inputs = nb_inputs-nb_elec_inputs
    nb_outputs = n_outputs(m) #id, iq

    h!(F,x) = _state_space!(F, x[1:end-nb_inputs], x[end-nb_inputs+1:end], m, Jac())
    ha = x -> (F = fill(zero(eltype(x)), nb_states+nb_outputs); h!(F, x); return F)
    jac = zeros(nb_states+nb_outputs, nb_states+nb_inputs)
    ForwardDiff.jacobian!(jac, ha, [equilibrium; inputs_vec])

    ### 5. New operating point
    elem.A=jac[1:nb_states, 1:nb_states]
    elem.B=jac[1:nb_states, nb_states+1:end-nb_addit_inputs] # We discard additional inputs for our state-space matrices.
    elem.C=jac[nb_states+1:end, 1:nb_states]
    elem.D=jac[nb_states+1:end, nb_states+1:end-nb_addit_inputs]

    return elem

end


