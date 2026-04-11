############################  measurement.jl  ############################

############################  Single-signal measurement block  ############################

@with_kw struct MeasurementSignal{F<:AbstractMeasurementFilter} <: AbstractStateSpace
    signal::Symbol
    filter::F = NoFilter()
end

"""
    MeasurementSignal(signal, filter)

Convenience constructor that builds the state-space matrices from the selected filter.
"""
function MeasurementSignal(signal::Symbol, filter::F) where {F<:AbstractMeasurementFilter}
    filter = measurement_filter_ss(filter)
    return MeasurementSignal{F}(signal=signal, filter=filter)
end

############################  Interface for one signal  ############################

function statenames(m::MeasurementSignal)
    nx = size(m.filter.A, 1)
    return ntuple(i -> Symbol("$(m.signal)_f_x$i"), nx)
end

function initialvalues(m::MeasurementSignal; inputs=nothing, kwargs...)
    names = statenames(m)
    nx = size(m.filter.A, 1)

    nx == 0 && return NamedTuple{names}(())

    u0 = inputs === nothing ? 0.0 : getfield(inputs, m.signal)
    x0 = -(m.filter.A \ (m.filter.B * [u0]))
    return NamedTuple{names}(Tuple(vec(x0)))
end

inputnames(m::MeasurementSignal) = (m.signal,)
outputnames(m::MeasurementSignal) = (Symbol("$(m.signal)_f"),)

function state_space!(F, x, inputs, m::MeasurementSignal; kwargs...)
    nx = size(m.filter.A, 1)

    if nx == 0
        return NamedTuple{outputnames(m)}((getfield(inputs, m.signal),))
    end

    names = statenames(m)
    xv = collect(getfield(x, name) for name in names)
    u = [getfield(inputs, m.signal)]

    dx = m.filter.A * xv + m.filter.B * u
    y = (m.filter.C * xv + m.filter.D * u)[1]

    @inbounds for i in eachindex(dx)
        F[i] = dx[i]
    end

    return NamedTuple{outputnames(m)}((y,))
end

function outputequations!(F, x, inputs, y, m::MeasurementSignal)
    F[1] = getfield(y, outputnames(m)[1])
    return nothing
end

############################  Composite measurement block  ############################

struct MeasurementTLC <: AbstractStateSpace
    v_d::MeasurementSignal
    v_q::MeasurementSignal
    vdc::MeasurementSignal
    i_d::MeasurementSignal
    i_q::MeasurementSignal
    idc::MeasurementSignal
    θ::MeasurementSignal
end

"""
    MeasurementTLC(; vac, iac, vdc, idc, θ)

Convenience constructor:
- the same filter spec is applied to both `v_d` and `v_q`
- the same filter spec is applied to both `i_d` and `i_q`
- scalar filters are used for `vdc`, `idc`, and `θ`
"""
function MeasurementTLC(;
    vac::AbstractMeasurementFilter = NoFilter(),
    iac::AbstractMeasurementFilter = NoFilter(),
    vdc::AbstractMeasurementFilter = NoFilter(),
    idc::AbstractMeasurementFilter = NoFilter(),
    θ::AbstractMeasurementFilter   = NoFilter()
)
    return MeasurementTLC(
        MeasurementSignal(:v_d, vac),
        MeasurementSignal(:v_q, vac),
        MeasurementSignal(:vdc, vdc),
        MeasurementSignal(:i_d, iac),
        MeasurementSignal(:i_q, iac),
        MeasurementSignal(:idc, idc),
        MeasurementSignal(:θ,   θ)
    )
end

############################  Interface for composite block  ############################

statenames(m::MeasurementTLC) = (
    statenames(m.v_d)...,
    statenames(m.v_q)...,
    statenames(m.vdc)...,
    statenames(m.i_d)...,
    statenames(m.i_q)...,
    statenames(m.idc)...,
    statenames(m.θ)...
)

function initialvalues(m::MeasurementTLC; inputs=nothing, kwargs...)
    return merge(
        initialvalues(m.v_d; inputs, kwargs...),
        initialvalues(m.v_q; inputs, kwargs...),
        initialvalues(m.vdc; inputs, kwargs...),
        initialvalues(m.i_d; inputs, kwargs...),
        initialvalues(m.i_q; inputs, kwargs...),
        initialvalues(m.idc; inputs, kwargs...),
        initialvalues(m.θ; inputs, kwargs...)
    )
end

inputnames(::MeasurementTLC) = (:v_d, :v_q, :vdc, :i_d, :i_q, :idc, :θ)
outputnames(::MeasurementTLC) = (:v_d_f, :v_q_f, :vdc_f, :i_d_f, :i_q_f, :idc_f, :θ_f)

function state_space!(F, x, inputs, m::MeasurementTLC; kwargs...)
    index = 1

    n = n_states(m.v_d)
    v_d = state_space!(@view(F[index:index+n-1]), x, inputs, m.v_d)
    index += n

    n = n_states(m.v_q)
    v_q = state_space!(@view(F[index:index+n-1]), x, inputs, m.v_q)
    index += n

    n = n_states(m.vdc)
    vdc = state_space!(@view(F[index:index+n-1]), x, inputs, m.vdc)
    index += n

    n = n_states(m.i_d)
    i_d = state_space!(@view(F[index:index+n-1]), x, inputs, m.i_d)
    index += n

    n = n_states(m.i_q)
    i_q = state_space!(@view(F[index:index+n-1]), x, inputs, m.i_q)
    index += n

    n = n_states(m.idc)
    idc = state_space!(@view(F[index:index+n-1]), x, inputs, m.idc)
    index += n

    n = n_states(m.θ)
    θ = state_space!(@view(F[index:index+n-1]), x, inputs, m.θ)

    return merge(v_d, v_q, vdc, i_d, i_q, idc, θ)
end

function outputequations!(F, x, inputs, y, m::MeasurementTLC)
    F[1] = y.v_d_f
    F[2] = y.v_q_f
    F[3] = y.vdc_f
    F[4] = y.i_d_f
    F[5] = y.i_q_f
    F[6] = y.idc_f
    F[7] = y.θ_f
    return nothing
end
