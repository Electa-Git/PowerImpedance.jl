############################  common/kernels/delay.jl  ############################

#=
Generic Pade delay implementation for converter state-space models.

The delay block is independent of TLC modulation and can be reused by other
converter models. It owns the delay matrices, state names, and state equations;
callers decide how to interpret the delayed output.
=#

export PadeDelay

"""
Pade-approximated multi-input time delay.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)

# Details

`PadeDelay` stores a state-space realization of a delay with `n_inputs`
independent channels. A zero `timeDelay` or zero denominator order creates a
zero-state pass-through block.
"""
struct PadeDelay <: AbstractStateSpace
    timeDelay::Float64
    padeOrderNum::Int
    padeOrderDen::Int
    n_inputs::Int
    state_prefix::Symbol

    A::Matrix{Float64}
    B::Matrix{Float64}
    C::Matrix{Float64}
    D::Matrix{Float64}
end

"""
Construct a [`PadeDelay`](@ref) from Pade approximation settings.

$(SIGNATURES)

# Details

`state_prefix` controls the generated state names. For example, a two-channel
third-order delay with `state_prefix = :m_delay` yields states
`:m_delay_x1` through `:m_delay_x6`.
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

"""
Return the state names of a Pade delay block.

$(SIGNATURES)
"""
function statenames(block::PadeDelay)
    n = size(block.A, 1)
    return ntuple(i -> Symbol("$(block.state_prefix)_x$i"), n)
end

"""
Evaluate the Pade delay state-space equations and output.

$(SIGNATURES)

# Details

`inputs` must contain `block.n_inputs` values. The returned vector is the
delayed output. The method writes delay-state derivatives into `F`.
"""
function state_space!(F, x, inputs, block::PadeDelay; kwargs...)
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
Build state-space matrices for a Pade delay approximation.

$(SIGNATURES)

# Details

The realization is converted to modal form to reduce conditioning problems from
the controllable canonical representation. `numberVars` creates independent,
block-diagonal copies of the single-channel delay.
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
