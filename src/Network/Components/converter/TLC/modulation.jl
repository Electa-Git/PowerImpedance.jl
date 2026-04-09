############################  modulation.jl  ############################

############################  Abstract modulation slot  ############################

abstract type AbstractModulationTLC <: AbstractStateSpace end

############################  No modulation / no delay  ############################

struct NoModulation <: AbstractModulationTLC end

statenames(::NoModulation) = ()
# TODO: Delete after testing
#initialvalues(::NoModulation; kwargs...) = (;)

modulation(::NoModulation, x, iloop, conv::AbstractTLC) = (; m_d = iloop.m_d, m_q = iloop.m_q)

state_space!(F, x, iloop, ::NoModulation; conv::AbstractTLC) = nothing

############################  Pade time-delay modulation  ############################

struct PadeModulation <: AbstractModulationTLC
    timeDelay::Float64
    padeOrderNum::Int
    padeOrderDen::Int

    A::Matrix{Float64}
    B::Matrix{Float64}
    C::Matrix{Float64}
    D::Matrix{Float64}
end

function PadeModulation(;
    timeDelay::Real = 0.0,
    padeOrderNum::Int = 0,
    padeOrderDen::Int = 0
)
    if timeDelay == 0.0 || padeOrderDen == 0
        A = zeros(0, 0)
        B = zeros(0, 2)
        C = zeros(2, 0)
        D = Matrix{Float64}(I, 2, 2)
    else
        A, B, C, D = timeDelayPadeMatrices(padeOrderNum, padeOrderDen, timeDelay, 2)
        A = Matrix{Float64}(A)
        B = Matrix{Float64}(B)
        C = Matrix{Float64}(C)
        D = Matrix{Float64}(D)
    end

    return PadeModulation(
        Float64(timeDelay),
        padeOrderNum,
        padeOrderDen,
        A,
        B,
        C,
        D
    )
end

function statenames(block::PadeModulation)
    n = size(block.A, 1)
    return ntuple(i -> Symbol("m_delay_x$i"), n)
end

# TODO: Delete after testing
#= function initialvalues(block::PadeModulation; kwargs...)
    n = size(block.A, 1)
    return NamedTuple{statenames(block)}(ntuple(_ -> 0.0, n))
end =#

function modulation(block::PadeModulation, x, iloop, conv::AbstractTLC)
    u = [iloop.m_d; iloop.m_q]
    n = size(block.A, 1)

    y =
        n == 0 ? u :
        begin
            xd = collect(getfield(x, Symbol("m_delay_x$i")) for i in 1:n)
            block.C * xd + block.D * u
        end

    # Same dq/αβ phase compensation as in the old monolithic TLC
    T_ab_dq = 0.5 * [1 im; -im 1]
    T_dq_ab = 0.5 * [1 -im; im 1]

    m_ab_ref =
        (cos(conv.elec.ω₀ * block.timeDelay) - sin(conv.elec.ω₀ * block.timeDelay) * im) *
        (T_dq_ab * y)

    m_dq_ref = real(T_ab_dq * conj(m_ab_ref) + conj(T_ab_dq) * m_ab_ref)

    return (
        m_d = m_dq_ref[1],
        m_q = m_dq_ref[2]
    )
end

function state_space!(F, x, iloop, block::PadeModulation; conv::AbstractTLC)
    n = size(block.A, 1)
    n == 0 && return nothing

    xd = collect(getfield(x, Symbol("m_delay_x$i")) for i in 1:n)
    u = [iloop.m_d; iloop.m_q]

    dx = block.A * xd + block.B * u

    @inbounds for i in 1:n
        F[i] = dx[i]
    end

    return nothing
end