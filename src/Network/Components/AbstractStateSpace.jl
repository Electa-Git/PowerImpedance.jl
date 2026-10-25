export linearize, steady_state




# Order states and initial values. Fill unspecified states with zero and discard
# initial values whose names are absent from statenames.
# Default initial values are zero. Modular parts can supply specialized initializers.
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
# `equilibriuminitialvalues(::AbstractStateSpace; kwargs...) = (;)`
# TODO find a name and check discrepancies between statenames and initialvalues.
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
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
model = ElectricalTLC()
initial = P.orderedinitialvalues(model; inputs, terminal_pu=point)
```
"""
orderedinitialvalues(x;kwargs...) = NamedTuple{statenames(x)}((;NamedTuple{statenames(x)}(ntuple(i->0.0,length(statenames(x))))..., initialvalues(x;kwargs...)...))
# statenamesmodular(m::AbstractStateSpace) = merge([statenames(getfield(m,n)) for n in fieldnames(typeof(m))]...)
n_states(m::AbstractStateSpace) = length(statenames(m))
n_inputs(m::AbstractStateSpace) = length(inputnames(m))
n_outputs(m::AbstractStateSpace) = length(outputnames(m))
n_elec_inputs(m::AbstractStateSpace) = length(elecinputnames(m))

# Default for elecinputnames. Synchronous machines currently specialize this method.
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
model = tlc()
names = P.elecinputnames(model)
```
"""
elecinputnames(m::AbstractStateSpace) = inputnames(m)


# Helper functions

"""
$(TYPEDSIGNATURES)

Evaluate one component block into its derivative slice and advance the destination
index.

# Arguments

- `F`: Writable parent derivative buffer. The block slice starts at `idx`. Normalized
  electrical-state rates use \\[s⁻¹\\], angle rates use \\[rad/s\\], and filter-state rates
  follow the realization.
- `x`: Named state values of the parent model, containing all states required by the
  block. Normalized electrical states use \\[dimensionless\\] and angles use \\[rad\\].
  Filter states follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `terminal_pu`: Operating point on the component bases \\[dimensionless\\]. Its voltage
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
model = tlc()
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
F = zeros(2)
data = (inputs=inputs, mod=(m_d=2.0, m_q=0.0))
outputs, next_index = P.state_space_block!(F, x, data, point, model.elec, model, 1)
@assert next_index == 3
```
"""
function state_space_block!(F, x, inputs, terminal_pu, block, m::AbstractStateSpace,
        idx::Integer)
    idx_end = idx + n_states(block) - 1
    out = state_space!(@view(F[idx:idx_end]), x, inputs, terminal_pu, block, m)
    return out, idx_end + 1
end

# Forward state_space! calls to methods with fewer arguments.
state_space!(F, x, inputs, terminal_pu, block::AbstractStateSpace, m::AbstractStateSpace) =
    state_space!(F, x, inputs, block, m)
state_space!(F, x, inputs, terminal_pu,  m::AbstractStateSpace) =
    state_space!(F, x, inputs, m)

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
solvekindequations!(F, x, inputs, terminal_pu, y, m::AbstractStateSpace, ::Equil) =
    equilibriumequations!(F, x, inputs, terminal_pu, y, m)

solvekindnames(m::AbstractStateSpace, ::Equil) = equilibriumnames(m)

solvekindequations!(F, x, inputs, terminal_pu, y, m::AbstractStateSpace, ::Jac) =
    outputequations!(@view(F[n_states(m)+1:end]), x, inputs, y, m)

solvekindnames(m::AbstractStateSpace, ::Jac) = outputnames(m)

solvekindequations!(F, x, inputs, terminal_pu, y, m::AbstractStateSpace,
        ::AbstractSolveKind) = nothing

equilibriumequations!(F, x, inputs, terminal_pu, y, m::AbstractStateSpace) = nothing
equilibriumequations!(F, x, inputs, terminal_pu, y, m::AbstractStateSpace,
        block::AbstractStateSpace) = nothing

outputequations!(F, x, inputs, y, m::AbstractStateSpace) = nothing

function _state_space!(F, x, inputs, terminal_pu::Union{TerminalValuesPU, Nothing},
        m::AbstractStateSpace, solvekind::AbstractSolveKind)
    
    # Convert vector states to NamedTuple with keys the statenames (we enforce the same order)
    x_names = statenames(m)
    # TODO consider `F_names = (x_names..., solvekindnames(m, solvekind)...)`.
    x_nt = NamedTuple{x_names}(x)
    inputs_nt = NamedTuple{inputnames(m)}(inputs)
    
    # To where state space equations fill up F
    index_stsp = n_states(m)

    # Call the modeler's state-space functions. Returned algebraic variables can be used
    # by outputequations or equilibriumequations.
    y = state_space!(@view(F[1:index_stsp]), x_nt, inputs_nt, terminal_pu, m)
    
    # Modify output or equilibrium equations
    solvekindequations!(F, x_nt, inputs_nt, terminal_pu, y, m, solvekind)

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

- Raises an error when equilibrium cannot be found. Propagates unsupported-model and
  differentiation errors.

# Examples

```julia
using PowerImpedance
model = synchronousmachine()
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
A, B, C, D = linearize(model, values)
```
"""
function linearize(m::AbstractStateSpace, values::NamedTuple)

    # Power flow to inputs of state_space function
    inputs, terminal_pu = pftoinputs(m, values)
    inputs_vec = collect(Base.values(inputs))

    # Initial values
    init = orderedinitialvalues(m; terminal_pu, inputs)

    # Parameters for equilibrium with NonlinearSolve.jl
    p_equil = (; inputs = inputs_vec, m = m, terminal_pu)

    # Initialize problem
    f!(du, u, p) = _state_space!(du, u, p.inputs, p.terminal_pu, p.m, Equil())
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
        terminal_pu, m, Jac())
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
model = synchronousmachine()
values = (ac = ACPortValues(220sqrt(2/3), 0.0, -100.0, 0.0),)
x = steady_state(model, values)
@assert steady_state(model, values) === x
```
"""
function steady_state(model::AbstractStateSpace, values::NamedTuple)
    isequal(model.cache.values, values) || linearize(model, values)
    return model.cache.state
end
