############################  common/loops/measurement.jl  ############################

#=
Shared converter measurement blocks.

The measurement layer converts raw converter signals into filtered signals used
by synchronization and control loops. The composite `Measurement` type is
currently named for TLC compatibility, but the individual `MeasurementSignal`
building block is topology-independent.
=#

export MeasurementSignal,
       Measurement

############################  Single-signal measurement block  ############################

"""
Single measured signal with an optional measurement filter.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
@with_kw struct MeasurementSignal{F<:AbstractMeasurementFilter} <: AbstractStateSpace
    signal::Symbol
    filter::F = NoFilter()
end

"""
Construct a filtered measurement signal.

$(SIGNATURES)

# Details

The filter specification is converted to state-space matrices with
[`measurement_filter_ss`](@ref) before being stored.
"""
function MeasurementSignal(signal::Symbol, filter::F) where {F<:AbstractMeasurementFilter}
    filter = measurement_filter_ss(filter)
    return MeasurementSignal{F}(signal=signal, filter=filter)
end

############################  Interface for one signal  ############################

"""
Return generated state names for a measured signal.

$(SIGNATURES)
"""
function statenames(m::MeasurementSignal)
    nx = size(m.filter.A, 1)
    return ntuple(i -> Symbol("$(m.signal)_f_x$i"), nx)
end

"""
Return steady-state initial filter states for a measured signal.

$(SIGNATURES)
"""
function initialvalues(m::MeasurementSignal; inputs=nothing)
    names = statenames(m)
    nx = size(m.filter.A, 1)

    nx == 0 && return NamedTuple{names}(())

    u0 = inputs === nothing ? 0.0 : getfield(inputs, m.signal)
    x0 = -(m.filter.A \ (m.filter.B * [u0]))
    return NamedTuple{names}(Tuple(vec(x0)))
end

"""
Return the raw input name consumed by a measured signal.

$(SIGNATURES)
"""
inputnames(m::MeasurementSignal) = (m.signal,)

"""
Return the filtered output name produced by a measured signal.

$(SIGNATURES)
"""
outputnames(m::MeasurementSignal) = (Symbol("$(m.signal)_f"),)

"""
Evaluate a measured signal's filter state-space equations.

$(SIGNATURES)

# Details

For `NoFilter`, this is a zero-state pass-through and returns the raw input
under the filtered output name.
"""
function state_space!(F, x, inputs, m::MeasurementSignal, ::AbstractConverter)
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

"""
Write a measured signal's output equation.

$(SIGNATURES)
"""
function outputequations!(F, x, inputs, y, m::MeasurementSignal)
    F[1] = getfield(y, outputnames(m)[1])
    return nothing
end

############################  Composite measurement block  ############################

"""
Composite measurement block for the TLC signal set.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct Measurement <: AbstractStateSpace
    vG_d::MeasurementSignal
    vG_q::MeasurementSignal
    v_dc::MeasurementSignal
    i_d::MeasurementSignal
    i_q::MeasurementSignal
    i_dc::MeasurementSignal
    θ::MeasurementSignal
end

"""
Construct the TLC measurement block from filter specifications.

$(SIGNATURES)

# Details

The `v_ac` filter is applied to `vG_d` and `vG_q`; the `i_ac` filter is applied to
`i_d` and `i_q`; scalar filters are used for `v_dc`, `i_dc`, and `θ`.
"""
function Measurement(;
    v_ac::AbstractMeasurementFilter = NoFilter(),
    i_ac::AbstractMeasurementFilter = NoFilter(),
    v_dc::AbstractMeasurementFilter = NoFilter(),
    i_dc::AbstractMeasurementFilter = NoFilter(),
    θ::AbstractMeasurementFilter   = NoFilter()
)
    return Measurement(
        MeasurementSignal(:vG_d, v_ac),
        MeasurementSignal(:vG_q, v_ac),
        MeasurementSignal(:v_dc, v_dc),
        MeasurementSignal(:i_d, i_ac),
        MeasurementSignal(:i_q, i_ac),
        MeasurementSignal(:i_dc, i_dc),
        MeasurementSignal(:θ,   θ)
    )
end

############################  Interface for composite block  ############################

"""
Return all measurement state names in execution order.

$(SIGNATURES)
"""
statenames(m::Measurement) = (
    statenames(m.vG_d)...,
    statenames(m.vG_q)...,
    statenames(m.v_dc)...,
    statenames(m.i_d)...,
    statenames(m.i_q)...,
    statenames(m.i_dc)...,
    statenames(m.θ)...
)

"""
Return initial values for every measurement filter.

$(SIGNATURES)
"""
function initialvalues(m::Measurement; inputs=nothing)
    return (;
        initialvalues(m.vG_d; inputs)...,
        initialvalues(m.vG_q; inputs)...,
        initialvalues(m.v_dc; inputs)...,
        initialvalues(m.i_d; inputs)...,
        initialvalues(m.i_q; inputs)...,
        initialvalues(m.i_dc; inputs)...,
        initialvalues(m.θ; inputs)...
    )
end

"""
Return raw input names for the composite measurement block.

$(SIGNATURES)
"""
inputnames(::Measurement) = (:vG_d, :vG_q, :v_dc, :i_d, :i_q, :i_dc, :θ)

"""
Return filtered output names for the composite measurement block.

$(SIGNATURES)
"""
outputnames(::Measurement) = (:vG_d_f, :vG_q_f, :v_dc_f, :i_d_f, :i_q_f, :i_dc_f, :θ_f)

"""
Evaluate all measurement filters and return their filtered outputs.

$(SIGNATURES)
"""
function state_space!(F, x, inputs, m::Measurement, c::AbstractConverter)
    vG_d, i = state_space!(F, x, inputs, m.vG_d, c, 1)
    vG_q, i = state_space!(F, x, inputs, m.vG_q, c, i)
    v_dc, i = state_space!(F, x, inputs, m.v_dc, c, i)
    i_d, i = state_space!(F, x, inputs, m.i_d, c, i)
    i_q, i = state_space!(F, x, inputs, m.i_q, c, i)
    i_dc, i = state_space!(F, x, inputs, m.i_dc, c, i)
    θ, _ = state_space!(F, x, inputs, m.θ, c, i)
    return merge(vG_d, vG_q, v_dc, i_d, i_q, i_dc, θ)
end

"""
Write composite measurement output equations.

$(SIGNATURES)
"""
function outputequations!(F, x, inputs, y, m::Measurement)
    F[1] = y.vG_d_f
    F[2] = y.vG_q_f
    F[3] = y.v_dc_f
    F[4] = y.i_d_f
    F[5] = y.i_q_f
    F[6] = y.i_dc_f
    F[7] = y.θ_f
    return nothing
end
