export linearize, steady_state

is_converter(::AbstractStateSpace) = false




# Function for ordering states & initialvalues. Puts all that are not defined to zero & discards initial values that do not appear in statenames 
# Default: no explicit nonzero initial values; Fallback function, so that it is not necessary in all the modular parts to initialize.
"""
$(TYPEDSIGNATURES)

Return an empty initial-state specification for a block without a specialized
initializer.

# Arguments

- `::AbstractStateSpace`: Concrete model or block.
- `kwargs...`: Accepted and ignored by this fallback.

# Returns

- An empty named tuple. `orderedinitialvalues` supplies zeros for the block states.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
initial = P.initialvalues(NoModulation())
@assert isempty(initial)
```
"""
initialvalues(::AbstractStateSpace; kwargs...) = (;)
# equilibriuminitialvalues(::AbstractStateSpace; kwargs...) = (;)
# TODO: Find proper name, add check for discrepancy statenames and initialvalues
"""
$(TYPEDSIGNATURES)

Order the initial states by the model state names and fill unspecified states with zero.

# Arguments

- `x`: Model or block providing `statenames` and `initialvalues` methods.
- `kwargs...`: Additional keywords forwarded to the selected component or initialization
  method.

# Returns

- Named tuple of initial values in `statenames(x)` order.

# Notes

Keys not declared by the model are discarded.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
model = ElectricalTLC()
initial = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
```
"""
orderedinitialvalues(x;kwargs...) = NamedTuple{statenames(x)}((;NamedTuple{statenames(x)}(ntuple(i->0.0,length(statenames(x))))..., initialvalues(x;kwargs...)...))
# statenamesmodular(m::AbstractStateSpace) = merge([statenames(getfield(m,n)) for n in fieldnames(typeof(m))]...)
n_states(m::AbstractStateSpace) = length(statenames(m))
n_inputs(m::AbstractStateSpace) = length(inputnames(m))
n_outputs(m::AbstractStateSpace) = length(outputnames(m))
n_elec_inputs(m::AbstractStateSpace) = length(elecinputnames(m))

# Default for elecinputnames (only different for SM atm)
"""
$(TYPEDSIGNATURES)

Return all input names as electrical inputs for the default state-space interface.

# Arguments

- `m`: Model implementing `inputnames`.

# Returns

- Tuple of electrical input names retained as admittance columns.

# Notes

Models with auxiliary control references override this method to return only their
electrical input names.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
names = P.elecinputnames(model)
```
"""
elecinputnames(m::AbstractStateSpace) = inputnames(m)


### Helper functions ###

"""
$(TYPEDSIGNATURES)

Evaluate one component block into its derivative slice and advance the destination
index.

# Arguments

- `F`: Writable parent derivative buffer. The block slice starts at `idx`; normalized
  electrical-state rates use \\[s⁻¹\\], angle rates use \\[rad/s\\], and filter-state rates
  follow the realization.
- `x`: Named state values of the parent model, containing all states required by the
  block. Normalized electrical states use \\[dimensionless\\] and angles use \\[rad\\];
  filter states follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `setpoint_pu`: Operating point on the component bases \\[dimensionless\\]; its voltage
  angle uses \\[rad\\].
- `block`: Submodel whose derivative slice is evaluated.
- `m`: Parent model providing shared parameters to the submodel.
- `idx`: First destination index for the block derivatives.

# Returns

- `out`: Outputs returned by the block.
- `idx_next`: First unused derivative index after the block.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
F = zeros(2)
data = (inputs=inputs, mod=(m_d=2.0, m_q=0.0))
outputs, next_index = P.state_space_block!(F, x, data, point, model.elec, model, 1)
@assert next_index == 3
```
"""
function state_space_block!(F, x, inputs, setpoint_pu, block, m::AbstractStateSpace, idx::Integer)
    idx_end = idx + n_states(block) - 1
    out = state_space!(@view(F[idx:idx_end]), x, inputs, setpoint_pu, block, m)
    return out, idx_end + 1
end

# Default functions for state_space! that do not use the setpoint_pu or the full model
state_space!(F, x, inputs, setpoint_pu, block::AbstractStateSpace, m::AbstractStateSpace) = state_space!(F, x, inputs, block, m)
state_space!(F, x, inputs, setpoint_pu,  m::AbstractStateSpace) = state_space!(F, x, inputs, m)

state_space!(F, x, inputs, ::Nothing, block::AbstractStateSpace, m::AbstractStateSpace) = state_space!(F, x, inputs, block, m)
state_space!(F, x, inputs, block::AbstractStateSpace, m::AbstractStateSpace) = state_space!(F, x, inputs, block)
state_space!(F, x, inputs,::Nothing,  block::AbstractStateSpace) = state_space!(F, x, inputs, block)



state_space_block!(F, x, inputs, block, m::AbstractStateSpace, idx::Integer) = state_space_block!(F, x, inputs, nothing, block, m::AbstractStateSpace, idx::Integer)

### Solution methods (additional equations equilibriumequations or outputequations)
"""
$(TYPEDEF)

Select the additional equations used for equilibrium or Jacobian evaluation.
"""
abstract type AbstractSolveKind end
# Types for form of state-space equations
"""
$(TYPEDEF)

Select equilibrium constraints when evaluating component state equations.

$(TYPEDFIELDS)
"""
struct Equil <: AbstractSolveKind end
"""
$(TYPEDEF)

Select output equations when differentiating a component model.

$(TYPEDFIELDS)
"""
struct Jac <: AbstractSolveKind end

### Dispatch on modeler functions
# Equilib
solvekindequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace, ::Equil) =
    equilibriumequations!(F, x, inputs, setpoint_pu, y, m)

solvekindnames(m::AbstractStateSpace, ::Equil) = equilibriumnames(m)

solvekindequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace, ::Jac) =
    outputequations!(@view(F[n_states(m)+1:end]), x, inputs, y, m)

solvekindnames(m::AbstractStateSpace, ::Jac) = outputnames(m)

solvekindequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace, ::AbstractSolveKind) = nothing

equilibriumequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace) = nothing
equilibriumequations!(F, x, inputs, setpoint_pu, y, m::AbstractStateSpace, block::AbstractStateSpace) = nothing

outputequations!(F, x, inputs, y, m::AbstractStateSpace) = nothing

function _state_space!(F, x, inputs, setpoint_pu::Union{SetpointPU, Nothing}, m::AbstractStateSpace, solvekind::AbstractSolveKind)
    
    # Convert vector states to NamedTuple with keys the statenames (we enforce the same order)
    x_names = statenames(m)
    # F_names = (x_names..., solvekindnames(m, solvekind)...) TODO: Think about this
    x_nt = NamedTuple{x_names}(x)
    inputs_nt = NamedTuple{inputnames(m)}(inputs)
    
    # To where state space equations fill up F
    index_stsp = n_states(m)

    # Call the modeler's state space functions, certain algebr variables can be returned to be used by outputequations or equilibriumequations
    y = state_space!(@view(F[1:index_stsp]), x_nt, inputs_nt, setpoint_pu, m)
    
    # Modify output/equilibrium equations
    solvekindequations!(F, x_nt, inputs_nt, setpoint_pu, y, m, solvekind)

    return

end

"""
$(TYPEDSIGNATURES)

Solve the nonlinear equilibrium and differentiate state and output equations to obtain
the electrical linearization.

# Arguments

- `m`: State-space component model.
- `values`: NamedTuple keyed by port name with `ACPortValues` and `DCPortValues`.

# Returns

- `A`: Linearized state matrix.
- `B`: Linearized electrical-input matrix.
- `C`: Linearized output matrix.
- `D`: Linearized electrical feedthrough matrix. Matrix units follow the declared state,
  input, and output coordinates.

# Notes

```math
f(x_0,u_0)=0,\\quad A=\\left.\\frac{\\partial f}{\\partial x}\\right|_0,\\quad B=\\left.\\frac{\\partial f}{\\partial u_e}\\right|_0,\\quad C=\\left.\\frac{\\partial g}{\\partial x}\\right|_0,\\quad D=\\left.\\frac{\\partial g}{\\partial u_e}\\right|_0.
```

Electrical inputs ``u_e`` exclude auxiliary reference inputs, which remain fixed during
differentiation. Each call recomputes and stores the terminal values, state and
matrices in the model cache. Converter solves retry with a trust-region algorithm
after a failed default solve.

# Errors

- Raises an error when equilibrium cannot be found; propagates unsupported-model and
  differentiation errors.

# Examples

```julia
using PowerImpedance
model = synchronousmachine().element_model
values = (ac = ACPortValues(220sqrt(2/3), 0.0, 100.0, 0.0),)
A, B, C, D = linearize(model, values)
```
"""
function linearize(m::AbstractStateSpace, values::NamedTuple)

    # Power flow to inputs of state_space function
    inputs, setpoint_pu = pftoinputs(m, values)
    inputs_vec = collect(Base.values(inputs))

    # Initial values
    init = orderedinitialvalues(m; setpoint_pu, inputs)

    # Parameters for equilibirum with NonlinearSolve.jl
    p_equil = (; inputs = inputs_vec, m = m, setpoint_pu)

    # Initialize problem
    f!(du, u, p) = _state_space!(du, u, p.inputs, p.setpoint_pu, p.m, Equil())
    @info "Starting to solve for steady-state solution"
    prob = NonlinearProblem(f!, collect(promote(Base.values(init)...)), p_equil)
    default_error = nothing
    sol = try
        solve(prob; maxiters = 20, abstol = 1e-6, reltol = 1e-6)
    catch exception
        is_converter(m) || rethrow()
        default_error = exception
        nothing
    end
    if is_converter(m) && (sol === nothing || !SciMLBase.successful_retcode(sol))
        retry = try
            solve(prob, NonlinearSolve.TrustRegion();
                maxiters = 20, abstol = 1e-6, reltol = 1e-6)
        catch
            nothing
        end
        if retry !== nothing && SciMLBase.successful_retcode(retry)
            sol = retry
        elseif default_error !== nothing
            throw(default_error)
        end
    end

    name = string(nameof(typeof(m)))

    if SciMLBase.successful_retcode(sol)
        @info "$name steady-state solution found!"
    else
        error("$name steady-state solution not found!")
    end

    equilibrium = sol.u[1:n_states(m)] # discard equilibrium states if any

    ϵ = 1e-15
    equilibrium[abs.(equilibrium) .< ϵ] .= 0


    nb_states = n_states(m)
    nb_inputs = n_inputs(m)
    nb_elec_inputs = n_elec_inputs(m)
    nb_addit_inputs = nb_inputs - nb_elec_inputs
    nb_outputs = n_outputs(m)

    h!(F,x) = _state_space!(F, x[1:end-nb_inputs], x[end-nb_inputs+1:end],
        setpoint_pu, m, Jac())
    jac = zeros(nb_states+nb_outputs, nb_states+nb_inputs)
    x = [equilibrium; inputs_vec]; F = fill(zero(eltype(x)), nb_states+nb_outputs)
    ForwardDiff.jacobian!(jac, h!, F, x)
     
    A = jac[1:nb_states, 1:nb_states]
    B = jac[1:nb_states, nb_states+1:end-nb_addit_inputs]
    C = jac[nb_states+1:end, 1:nb_states]
    D = jac[nb_states+1:end, nb_states+1:end-nb_addit_inputs]

    m.cache.values = values
    m.cache.state = equilibrium
    m.cache.A, m.cache.B, m.cache.C, m.cache.D = A, B, C, D
    return A,B,C,D 
end

"""
$(TYPEDSIGNATURES)

Return the converged state at the supplied terminal values, reusing the model cache
when the values compare equal with `isequal`. Otherwise, call [`linearize`](@ref).

# Arguments

- `model`: State-space component model.
- `values`: NamedTuple keyed by port name with `ACPortValues` and `DCPortValues`.

# Returns

- Cached state vector in `statenames(model)` order and the model's state coordinates.
  Repeated calls with equal values return the same vector object. Changes to this
  vector also change the cached state.

# Errors

- Propagates equilibrium-solve and differentiation errors from `linearize`.

# Examples

```julia
model = synchronousmachine().element_model
values = (ac = ACPortValues(220sqrt(2/3), 0.0, 100.0, 0.0),)
x = steady_state(model, values)
@assert steady_state(model, values) === x
```
"""
function steady_state(model::AbstractStateSpace, values::NamedTuple)
    isequal(model.cache.values, values) || linearize(model, values)
    return model.cache.state
end

# transitional
function update(elem::Element{<:AbstractStateSpace}, setpoint::Setpoint)
    m = elem.element_model
    elem._equilibrium = nothing
    A, B, C, D = linearize(m, _terminal_values(m, setpoint))
    elem._equilibrium = (m, setpoint, copy(m.cache.state))
    return A, B, C, D
end

"""
$(TYPEDSIGNATURES)

Return a copy of the converged state vector retained by the core linearization.

# Arguments

- `elem`: Network element containing the component model and operating point.

# Returns

- State vector in `statenames(elem.element_model)` order and the model's state
  coordinates, with the same small-value zeroing used for linearization.

# Notes

Core updates clear the retained vector before the solve and store a new vector
only after successful linearization. Changes to the returned copy leave
the retained state unchanged.

# Errors

- Throws `ArgumentError` without a setpoint when the current model lacks a retained
  state. With a setpoint, propagates core solve or linearization errors.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
point = Setpoint(Pac=100.0, Qac=0.0, Vac=220sqrt(2/3), θac=0.0)
element = synchronousmachine(setpoint=point)
P.update!(element, point)
state = P._steady_state(element)
```
"""
function _steady_state(elem::Element{<:AbstractStateSpace})
    saved = elem._equilibrium
    saved !== nothing && saved[1] === elem.element_model ||
        throw(ArgumentError("element :$(elem.symbol) has no retained converged state"))
    return copy(saved[3])
end

function _steady_state(elem::Element{<:AbstractStateSpace}, setpoint::Setpoint)
    saved = elem._equilibrium
    if saved === nothing || saved[1] !== elem.element_model || !isequal(saved[2], setpoint)
        update(elem, setpoint)
    end
    return _steady_state(elem)
end

"""
$(TYPEDSIGNATURES)

Update the component operating point or stored linearization in place.

# Arguments

- `elem`: Network element containing the component model and operating point.
- `setpoint`: Physical operating point; powers use \\[MW\\] or \\[MVAr\\], voltages \\[kV\\],
  and angles \\[rad\\].

# Returns

- The updated `Element`, with its operating point and linearization matrices stored.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
point = Setpoint(Pac=100.0, Qac=0.0, Vac=220sqrt(2/3), θac=0.0)
element = synchronousmachine(setpoint=point)
P.update!(element, point)
```
"""
function update!(elem::Element, setpoint::Setpoint)

    A, B, C, D = update(elem, setpoint)
    
    elem.A = A
    elem.B = B
    elem.C = C
    elem.D = D
    elem.setpoint = setpoint

    return elem
end
