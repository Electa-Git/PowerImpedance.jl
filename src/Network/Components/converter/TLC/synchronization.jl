abstract type AbstractSynchronizationTLC <: AbstractStateSpace end

struct NoSynchronization <: AbstractSynchronizationTLC end

statenames(::NoSynchronization) = ()
# TODO: remove after testing
#initialvalues(::NoSynchronization; kwargs...) = (;)

syncangle(::NoSynchronization, x) = 0.0

function synchronization(::NoSynchronization, x, meas)
    return (
        θ_sync = 0.0,
        ω_sync = 1.0,
        Δω_sync = 0.0,
    )
end

state_space!(F, x, meas, ::NoSynchronization; conv::AbstractTLC) = nothing

struct PLLSynchronization{Filter<:AbstractMeasurementFilter} <: AbstractSynchronizationTLC
    pi_ctrl::PIControl
    filter::Filter
end

function PLLSynchronization(; pi_ctrl::PIControl = PIControl(), filter::AbstractMeasurementFilter = NoFilter())
    filter = measurement_filter_ss(filter)

    return PLLSynchronization{typeof(filter)}(
        pi_ctrl,
        filter,
    )
end

syncangle(::PLLSynchronization, x) = x.θ_pll

function statenames(block::PLLSynchronization)
    n = size(block.filter.A, 1)
    return (
        ntuple(i -> Symbol("v_q_pll_f_x$i"), n)...,
        :ξ_pll,
        :θ_pll,
    )
end

# TODO: delete after testing
#= function initialvalues(block::PLLSynchronization; setpoint = SetPoint(), kwargs...)
    n = size(block.A, 1)
    return NamedTuple{statenames(block)}((
        ntuple(_ -> 0.0, n)...,
        0.0,
        setpoint.θac
    ))
end =#


function synchronization(block::PLLSynchronization, x, meas)
    n = size(block.filter.A, 1)
    xf = collect(getfield(x, Symbol("v_q_pll_f_x$i")) for i in 1:n)
    u = [meas.v_q_f]

    v_pll = (block.filter.C * xf + block.filter.D * u)[1]
    Δω = -block.pi_ctrl.Kp * v_pll + x.ξ_pll

    return (
        θ_sync = x.θ_pll,
        ω_sync = 1.0 + Δω,
        Δω_sync = Δω,
    )
end

function state_space!(F, x, meas, block::PLLSynchronization; conv::AbstractTLC)
    n = size(block.filter.A, 1)
    xf = collect(getfield(x, Symbol("v_q_pll_f_x$i")) for i in 1:n)
    u = [meas.v_q_f]

    dx_f = block.filter.A * xf + block.filter.B * u
    v_pll = (block.filter.C * xf + block.filter.D * u)[1]
    Δω = -block.pi_ctrl.Kp * v_pll + x.ξ_pll

    @inbounds for i in 1:n
        F[i] = dx_f[i]
    end

    F[n + 1] = -block.pi_ctrl.Ki * v_pll
    F[n + 2] = conv.elec.ω₀ * Δω

    return nothing
end