

abstract type AbstractStateSpace <: AbstractElementModel end

# Function for ordering states & initialvalues. Puts all that are not defined to zero & discards initial values that do not appear in statenames 
# Default: no explicit nonzero initial values; Fallback function, so that it is not necessary in all the modular parts to initialize.
initialvalues(::AbstractStateSpace; kwargs...) = (;)
dummyinitialvalues(::AbstractStateSpace; kwargs...) = (;)
# TODO: Find proper name, add check for discrepancy statenames and initialvalues
orderedinitialvalues(x;kwargs...) = NamedTuple{statenames(x)}((;NamedTuple{statenames(x)}(ntuple(i->0.0,length(statenames(x))))..., initialvalues(x;kwargs...)...))
# statenamesmodular(m::AbstractStateSpace) = merge([statenames(getfield(m,n)) for n in fieldnames(typeof(m))]...)
n_states(m::AbstractStateSpace) = length(statenames(m))
n_inputs(m::AbstractStateSpace) = length(inputnames(m))
n_outputs(m::AbstractStateSpace) = length(outputnames(m))
n_elec_inputs(m::AbstractStateSpace) = length(elecinputnames(m))

# Default for elecinputnames (only different for SM atm)
elecinputnames(m::AbstractStateSpace) = inputnames(m)


### Helper functions ###

function state_space_block!(F, x, inputs, setpoint_pu, block, m::AbstractStateSpace, idx::Integer)
    idx_end = idx + n_states(block) - 1
    out = state_space!(@view(F[idx:idx_end]), x, inputs, setpoint_pu, block, m)
    return out, idx_end + 1
end

# Default functions for state_space! that do not use the setpoint_pu or the full model
state_space!(F, x, inputs, setpoint_pu, block::AbstractStateSpace, m::AbstractStateSpace) = state_space!(F, x, inputs, block, m)
state_space!(F, x, inputs, block::AbstractStateSpace, m::AbstractStateSpace) = state_space!(F, x, inputs, block)

state_space_block!(F, x, inputs, block, m::AbstractStateSpace, idx::Integer) = state_space_block!(F, x, inputs, nothing, block, m::AbstractStateSpace, idx::Integer)

### Solution methods (additional equations dummyequations or outputequations)
abstract type AbstractSolveKind end
# Types for form of state-space equations
struct Equil <: AbstractSolveKind end
struct Jac <: AbstractSolveKind end

### Dispatch on modeler functions
# Equilib
solvekindequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace, ::Equil) =
    equilibriumequations!(F, x, inputs, setpoint_pu, y, m)

solvekindnames(m::AbstractStateSpace, ::Equil) = dummynames(m)

solvekindequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace, ::Jac) =
    outputequations!(@view(F[n_states(m)+1:end]), x, inputs, y, m)

solvekindnames(m::AbstractStateSpace, ::Jac) = outputnames(m)

solvekindequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace, ::AbstractSolveKind) = nothing

equilibriumequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace) = nothing
equilibriumequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace, block::AbstractStateSpace) = nothing

outputequations!(F, x, inputs, y, m::AbstractStateSpace) = nothing

function _state_space!(F, x, inputs, setpoint_pu::SetpointPU, m::AbstractStateSpace, solvekind::AbstractSolveKind)
    
    # Convert vector states to NamedTuple with keys the statenames (we enforce the same order)
    x_names = statenames(m)
    # F_names = (x_names..., solvekindnames(m, solvekind)...) TODO: Think about this
    x_nt = NamedTuple{x_names}(x)
    inputs_nt = NamedTuple{inputnames(m)}(inputs)
    
    # To where state space equations fill up F
    index_stsp = n_states(m)

    # Call the modeler's state space functions, certain algebr variables can be returned to be used by outputequations or dummyequations
    y = state_space!(@view(F[1:index_stsp]), x_nt, inputs_nt, setpoint_pu, m)
    
    # Modify output/dummy equations
    solvekindequations!(F, x_nt, inputs_nt, setpoint_pu, y, m, solvekind)

    return

end

function update!(elem::Element, m::AbstractStateSpace, setpoint::Setpoint)

    # Power flow to inputs of state_space function
    inputs, setpoint_pu = pftoinputs(m, setpoint)
    inputs_vec = collect(values(inputs))

    # Initial values
    init = orderedinitialvalues(m; setpoint_pu, inputs)

    # Parameters for equilibirum with NonlinearSolve.jl
    p_equil = (; inputs = inputs_vec, m = m, setpoint_pu)

    # Initialize problem
    f!(du, u, p) = _state_space!(du, u, p.inputs, p.setpoint_pu, p.m, Equil())
    @info "Starting to solve for steady-state solution"
    prob = NonlinearProblem(f!, collect(promote(values(init)...)), p_equil)
    sol = solve(prob; maxiters = 20, abstol = 1e-6, reltol = 1e-6)

    name = isdefined(elem, :symbol) ? string(elem.symbol) : string(nameof(typeof(m)))

    if SciMLBase.successful_retcode(sol)
        @info "$name steady-state solution found!"
    else
        error("$name steady-state solution not found!")
    end

    equilibrium = sol.u[1:n_states(m)] # discard dummy states if any

    nb_states = n_states(m)
    nb_inputs = n_inputs(m)
    nb_elec_inputs = n_elec_inputs(m)
    nb_addit_inputs = nb_inputs - nb_elec_inputs
    nb_outputs = n_outputs(m)

    h!(F,x) = _state_space!(F, x[1:end-nb_inputs], x[end-nb_inputs+1:end], setpoint_pu, m, Jac())
    jac = zeros(nb_states+nb_outputs, nb_states+nb_inputs)
    x = [equilibrium; inputs_vec]; F = fill(zero(eltype(x)), nb_states+nb_outputs)
    ForwardDiff.jacobian!(jac, h!, F, x)

    
    elem.A = jac[1:nb_states, 1:nb_states]
    elem.B = jac[1:nb_states, nb_states+1:end-nb_addit_inputs]
    elem.C = jac[nb_states+1:end, 1:nb_states]
    elem.D = jac[nb_states+1:end, nb_states+1:end-nb_addit_inputs]
    elem.setpoint = setpoint
    elem.element_model = m

    return elem
end

function update(elem::Element{T}, setpoint::Setpoint) where {T<:AbstractStateSpace}
    
    m = elem.element_model

    # Power flow to inputs of state_space function
    inputs, setpoint_pu = pftoinputs(m, setpoint)
    inputs_vec = collect(values(inputs))

    # Initial values
    init = orderedinitialvalues(m; setpoint_pu, inputs)

    # Parameters for equilibirum with NonlinearSolve.jl
    p_equil = (; inputs = inputs_vec, m = m, setpoint_pu)

    # Initialize problem
    f!(du, u, p) = _state_space!(du, u, p.inputs, p.setpoint_pu, p.m, Equil())
    @info "Starting to solve for steady-state solution"
    prob = NonlinearProblem(f!, collect(promote(values(init)...)), p_equil)
    sol = solve(prob; maxiters = 20, abstol = 1e-6, reltol = 1e-6)

    name = isdefined(elem, :symbol) ? string(elem.symbol) : string(nameof(typeof(m)))

    if SciMLBase.successful_retcode(sol)
        @info "$name steady-state solution found!"
    else
        error("$name steady-state solution not found!")
    end

    equilibrium = sol.u[1:n_states(m)] # discard dummy states if any

    nb_states = n_states(m)
    nb_inputs = n_inputs(m)
    nb_elec_inputs = n_elec_inputs(m)
    nb_addit_inputs = nb_inputs - nb_elec_inputs
    nb_outputs = n_outputs(m)

    h!(F,x) = _state_space!(F, x[1:end-nb_inputs], x[end-nb_inputs+1:end], setpoint_pu, m, Jac())
    jac = zeros(nb_states+nb_outputs, nb_states+nb_inputs)
    x = [equilibrium; inputs_vec]; F = fill(zero(eltype(x)), nb_states+nb_outputs)
    ForwardDiff.jacobian!(jac, h!, F, x)
     
    A = jac[1:nb_states, 1:nb_states]
    B = jac[1:nb_states, nb_states+1:end-nb_addit_inputs]
    C = jac[nb_states+1:end, 1:nb_states]
    D = jac[nb_states+1:end, nb_states+1:end-nb_addit_inputs]

    return A,B,C,D 
end

