############################  common/kernels/delay.jl  ############################

"""
$(TYPEDEF)

Store a delay duration and channel count without a state-space realization.

$(TYPEDFIELDS)
"""
struct Delay 
    "Delay duration \\[s\\]."
    timeDelay::Float64
    "Number of independent input channels."
    n_inputs::Int
    
end




#=
Generic Pade delay implementation for converter state-space models.

The delay block is independent of TLC modulation and can be reused by other
converter models. It owns the delay matrices, state names, and state equations;
callers decide how to interpret the delayed output.
=#

export PadeDelay

"""
$(TYPEDEF)

Pade-approximated multi-input time delay.

$(TYPEDFIELDS)

# Notes

`PadeDelay` stores a state-space realization of a delay with `n_inputs`
independent channels. A zero `timeDelay` or zero denominator order creates a
zero-state pass-through block.
"""
struct PadeDelay <: AbstractStateSpace
    "Delay duration \\[s\\]."
    timeDelay::Float64
    "Requested Padé numerator polynomial order."
    padeOrderNum::Int
    "Requested Padé denominator polynomial order."
    padeOrderDen::Int
    "Number of independent input channels."
    n_inputs::Int
    "Prefix for generated delay-state names."
    state_prefix::Symbol

    "State matrix; its coefficients depend on the realization coordinates."
    A::Matrix{Float64}
    "Input matrix; its coefficients depend on the realization coordinates."
    B::Matrix{Float64}
    "Output matrix; its coefficients depend on the realization coordinates."
    C::Matrix{Float64}
    "Direct input-to-output gain matrix \\[dimensionless\\]."
    D::Matrix{Float64}
end

"""
$(TYPEDSIGNATURES)

Construct a [`PadeDelay`](@ref) from Pade approximation settings.

# Arguments

- `timeDelay`: Delay duration \\[s\\]. Default: `0.0`.
- `padeOrderNum`: Requested Padé numerator polynomial order. Default: `0`.
- `padeOrderDen`: Requested Padé denominator polynomial order. Default: `0`.
- `n_inputs`: Number of independent input channels. Default: `1`.
- `state_prefix`: Prefix for generated delay-state names. Default: `:delay`.

# Returns

- A `PadeDelay` instance.

# Notes

`state_prefix` controls the generated state names. For example, a two-channel
third-order delay with `state_prefix = :m_delay` yields states
`:m_delay_x1` through `:m_delay_x6`.

```math
a_i=\\frac{\\tau^{i-n}(m+n-i)!\\,n!}{m!\\,i!\\,(n-i)!},\\quad
b_i=\\frac{\\tau^{i-n}(-1)^i(m+n-i)!}{i!\\,(m-i)!},\\quad
d=\\frac{n!(-1)^m\\tau^{m-n}}{m!},\\quad
H(s)=\\frac{d s^n+\\sum_{i=0}^{n-1}b_i s^i}{s^n+\\sum_{i=0}^{n-1}a_i s^i}.
```

The requested numerator and denominator orders are ``m,n``; delay ``τ`` uses
\\[s\\]. Equal positive orders give the conventional diagonal Padé approximation.
Unequal orders are not validated: the constructed numerator still contains the
``d s^n`` term, so its degree and feedthrough can differ from the requested
approximation. Negative factorial arguments raise errors. Modal realization
improves conditioning; independent channels use block-diagonal copies.

A zero delay or zero denominator order bypasses coefficient construction and creates a
zero-state unity-gain block.

# Errors

- Throws `ArgumentError` for a nonpositive channel count; unsupported Padé order
  combinations can propagate factorial or realization errors.

# Examples

```julia
using PowerImpedance
component = PadeDelay(timeDelay=200e-6, padeOrderNum=3, padeOrderDen=3)
```
"""
function PadeDelay(;
    timeDelay::Real = 0.0,
    padeOrderNum::Int = 0,
    padeOrderDen::Int = 0,
    n_inputs::Int = 1,
    state_prefix::Symbol = :delay
)
    n_inputs > 0 || throw(ArgumentError("n_inputs must be positive"))

    if timeDelay == 0.0 || padeOrderDen == 0
        A = zeros(0, 0)
        B = zeros(0, n_inputs)
        C = zeros(n_inputs, 0)
        D = Matrix{Float64}(I, n_inputs, n_inputs)
    else
        A, B, C, D = pade_delay_matrices(padeOrderNum, padeOrderDen, timeDelay, n_inputs)
        A = Matrix{Float64}(A)
        B = Matrix{Float64}(B)
        C = Matrix{Float64}(C)
        D = D isa Number ? fill(Float64(D), 1, 1) : Matrix{Float64}(D) # This might be necessary for the bipolar MMC. Test for: "D = Matrix{Float64}(D)"
    end

    return PadeDelay(
        Float64(timeDelay),
        padeOrderNum,
        padeOrderDen,
        n_inputs,
        state_prefix,
        A,
        B,
        C,
        D,
    )
end

function statenames(block::PadeDelay)
    n = size(block.A, 1)
    return ntuple(i -> Symbol("$(block.state_prefix)_x$i"), n)
end

"""
$(TYPEDSIGNATURES)

Evaluate the Pade delay state-space equations and output.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Channel values in delay-input order. Their physical units are preserved;
  converter modulation inputs are \\[dimensionless\\].
- `block`: Realized delay matrices and channel count.
- `conv`: Parent converter providing electrical bases and synchronization.

# Returns

- Vector of delayed channel outputs, in the same physical units as the inputs.

# Notes

`inputs` must contain `block.n_inputs` values. The returned vector is the
delayed output. The method writes delay-state derivatives into `F`.

```math
\\dot{x}=Ax+Bu,\\qquad y=Cx+Du.
```

Time uses \\[s\\]. Realization-state units depend on the matrices; input and output have
the same physical signal units. A realization without states returns its direct output.

# Errors

- Throws `DimensionMismatch` when the input length differs from the channel count.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
block = PadeDelay(timeDelay=200e-6, padeOrderNum=3, padeOrderDen=3, n_inputs=2)
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
outputs = P.state_space!(F, x, (1.0, 0.0), block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, block::PadeDelay, conv::AbstractConverter)
    u = collect(inputs)
    length(u) == block.n_inputs || throw(DimensionMismatch(
        "PadeDelay expected $(block.n_inputs) inputs, got $(length(u))"
    ))

    n = size(block.A, 1)
    n == 0 && return u

    xd = collect(getfield(x, name) for name in statenames(block))
    dx = block.A * xd + block.B * u

    @inbounds for i in 1:n
        F[i] = dx[i]
    end

    return block.C * xd + block.D * u
end

"""
$(TYPEDSIGNATURES)

Build state-space matrices for a Pade delay approximation.

# Arguments

- `padeOrderNum`: Requested Padé numerator polynomial order.
- `padeOrderDen`: Requested Padé denominator polynomial order.
- `t_delay`: Delay duration \\[s\\].
- `numberVars`: Number of independent delayed channels.

# Returns

- `A`: State matrix.
- `B`: Input matrix.
- `C`: Output matrix.
- `D`: Feedthrough gain \\[dimensionless\\]. State coordinates follow the returned
  realization; time is in \\[s\\].

# Notes

The realization is converted to modal form to reduce conditioning problems from
the controllable canonical representation. `numberVars` creates independent,
block-diagonal copies of the single-channel delay.

```math
a_i=\\frac{\\tau^{i-n}(m+n-i)!\\,n!}{m!\\,i!\\,(n-i)!},\\quad
b_i=\\frac{\\tau^{i-n}(-1)^i(m+n-i)!}{i!\\,(m-i)!},\\quad
d=\\frac{n!(-1)^m\\tau^{m-n}}{m!},\\quad
H(s)=\\frac{d s^n+\\sum_{i=0}^{n-1}b_i s^i}{s^n+\\sum_{i=0}^{n-1}a_i s^i}.
```

The requested numerator and denominator orders are ``m,n``; delay ``τ`` uses
\\[s\\]. Equal positive orders give the conventional diagonal Padé approximation.
Unequal orders are not validated: the constructed numerator still contains the
``d s^n`` term, so its degree and feedthrough can differ from the requested
approximation. Negative factorial arguments raise errors. Modal realization
improves conditioning; independent channels use block-diagonal copies.

# Examples

```julia
using PowerImpedance
PowerImpedance.pade_delay_matrices(3, 3, 200e-6, 2)
```
"""
function pade_delay_matrices(padeOrderNum, padeOrderDen, t_delay, numberVars)
    size_A = padeOrderDen
    a_k = factorial(padeOrderNum)
    b_l = (factorial(padeOrderDen) * (-1)^padeOrderNum * t_delay^(padeOrderNum - padeOrderDen)) / a_k

    Ad = zeros(size_A, size_A)
    Bd = zeros(size_A, 1)
    Bd[end] = 1
    Cd = zeros(1, size_A)
    Dd = b_l
    Ad[1:end-1, 2:end] = Matrix(1.0I, padeOrderDen - 1, padeOrderDen - 1)

    for i in 0:padeOrderDen-1
        a_i = (
            t_delay^(i - padeOrderDen) *
            factorial(padeOrderNum + padeOrderDen - i) *
            factorial(padeOrderDen) /
            (factorial(i) * factorial(padeOrderDen - i))
        ) / a_k
        b_i = (
            t_delay^(i - padeOrderDen) *
            (-1)^i *
            factorial(padeOrderNum + padeOrderDen - i) *
            factorial(padeOrderNum) /
            (factorial(i) * factorial(padeOrderNum - i))
        ) / a_k

        Ad[end, i + 1] = -a_i
        Cd[i + 1] = b_i - a_i * b_l
    end

    sys = ss(Ad, Bd, Cd, Dd)
    sys_modal = modal_form(sys; C1 = true)
    Ad = sys_modal[1].A
    Bd = sys_modal[1].B
    Cd = sys_modal[1].C

    if numberVars == 1
        return Ad, Bd, Cd, Dd
    end

    A = cat(ntuple(_ -> Ad, numberVars)...; dims = (1, 2))
    B = cat(ntuple(_ -> Bd, numberVars)...; dims = (1, 2))
    C = cat(ntuple(_ -> Cd, numberVars)...; dims = (1, 2))
    D = cat(ntuple(_ -> Dd, numberVars)...; dims = (1, 2))

    return A, B, C, D
end
