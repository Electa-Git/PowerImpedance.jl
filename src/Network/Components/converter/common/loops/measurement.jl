############################  common/loops/measurement.jl  ############################

#=
Shared converter measurement blocks.

The measurement layer converts raw converter signals into filtered signals used
by synchronization and control loops. Power measurements are derived from the
filtered voltage and current measurements before their own optional filters are
applied.
=#

export MeasurementSignal,
       Measurement

############################  Single-signal measurement block  ############################

"""
$(TYPEDEF)

Single measured signal with an optional measurement filter.

$(TYPEDFIELDS)
"""
@with_kw struct MeasurementSignal{F<:AbstractMeasurementFilter} <: AbstractStateSpace
    "Name of the raw input signal; output names append `_f`."
    signal::Symbol
    "Measurement filter with a scalar state-space realization."
    filter::F = NoFilter()
end

"""
$(TYPEDSIGNATURES)

Construct a filtered measurement signal.

# Arguments

- `signal`: Name of the raw input signal; output names append `_f`.
- `filter`: Filter specification realized before storage.

# Returns

- A `MeasurementSignal` instance.

# Notes

The filter specification is converted to state-space matrices with
`measurement_filter_ss` before being stored.

# Examples

```julia
using PowerImpedance
component = MeasurementSignal(:v_dc, PowerImpedance.NoFilter())
```
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

function initialvalues(m::MeasurementSignal; inputs=nothing)
    names = statenames(m)
    nx = size(m.filter.A, 1)

    nx == 0 && return NamedTuple{names}(())

    u0 = inputs === nothing ? 0.0 : getfield(inputs, m.signal)
    x0 = -(m.filter.A \ (m.filter.B * [u0]))
    return NamedTuple{names}(Tuple(vec(x0)))
end

inputnames(m::MeasurementSignal) = (m.signal,)

outputnames(m::MeasurementSignal) = (Symbol("$(m.signal)_f"),)

"""
$(TYPEDSIGNATURES)

Evaluate a measured signal's filter state-space equations.

# Arguments

- `F`: Writable filter-state derivative buffer, in realization coordinates per second.
- `x`: Named filter-state values in the realized state coordinates.
- `inputs`: Named tuple containing `m.signal`, in the units of the measured signal.
- `m`: Signal selector and its realized scalar filter.

# Returns

- Named tuple containing the filtered signal under its generated output name, in the
  input signal units.

# Notes

For `NoFilter`, this is a zero-state pass-through and returns the raw input
under the filtered output name.

```math
\\dot{x}=Ax+Bu,\\qquad y=Cx+Du.
```

Time uses \\[s\\]. Realization-state units depend on the matrices; input and output have
the same physical signal units. A realization without states returns its direct output.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
block = MeasurementSignal(:v_dc, P.Butterworth(order=2, ωc=2π*100))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
outputs = P.state_space!(F, x, (v_dc=1.0,), block)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, m::MeasurementSignal)
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

"""
$(TYPEDEF)

Composite measurement block for the shared AC/DC converter signal set.

$(TYPEDFIELDS)
"""
struct Measurement <: AbstractStateSpace
    "Measurement block for d-axis grid voltage."
    vG_d::MeasurementSignal
    "Measurement block for q-axis grid voltage."
    vG_q::MeasurementSignal
    "Measurement block for dc voltage."
    v_dc::MeasurementSignal
    "Measurement block for d-axis ac current."
    i_d::MeasurementSignal
    "Measurement block for q-axis ac current."
    i_q::MeasurementSignal
    "Measurement block for dc current."
    i_dc::MeasurementSignal
    "Measurement block for synchronization angle."
    θ::MeasurementSignal
    "Measurement block for ac active power."
    P_ac::MeasurementSignal
    "Measurement block for ac reactive power."
    Q_ac::MeasurementSignal
    "Measurement block for dc active power."
    P_dc::MeasurementSignal
end

"""
$(TYPEDSIGNATURES)

Construct the converter measurement block from filter specifications.

# Arguments

- `v_ac`: Filter specification for v_ac measurements. Default: `NoFilter()`.
- `i_ac`: Filter specification for i_ac measurements. Default: `NoFilter()`.
- `v_dc`: Filter specification for v_dc measurements. Default: `NoFilter()`.
- `i_dc`: Filter specification for i_dc measurements. Default: `NoFilter()`.
- `θ`: Filter specification for θ measurements. Default: `NoFilter()`.
- `P_ac`: Filter specification for P_ac measurements. Default: `NoFilter()`.
- `Q_ac`: Filter specification for Q_ac measurements. Default: `NoFilter()`.
- `P_dc`: Filter specification for P_dc measurements. Default: `NoFilter()`.

# Returns

- A `Measurement` instance.

# Notes

The `v_ac` filter is applied to `vG_d` and `vG_q`; the `i_ac` filter is applied to
`i_d` and `i_q`; scalar filters are used for `v_dc`, `i_dc`, `θ`, `P_ac`, `Q_ac`,
and `P_dc`.

# Examples

```julia
using PowerImpedance
component = Measurement()
```
"""
function Measurement(;
    v_ac::AbstractMeasurementFilter = NoFilter(),
    i_ac::AbstractMeasurementFilter = NoFilter(),
    v_dc::AbstractMeasurementFilter = NoFilter(),
    i_dc::AbstractMeasurementFilter = NoFilter(),
    θ::AbstractMeasurementFilter   = NoFilter(),
    P_ac::AbstractMeasurementFilter = NoFilter(),
    Q_ac::AbstractMeasurementFilter = NoFilter(),
    P_dc::AbstractMeasurementFilter = NoFilter(),
)
    return Measurement(
        MeasurementSignal(:vG_d, v_ac),
        MeasurementSignal(:vG_q, v_ac),
        MeasurementSignal(:v_dc, v_dc),
        MeasurementSignal(:i_d, i_ac),
        MeasurementSignal(:i_q, i_ac),
        MeasurementSignal(:i_dc, i_dc),
        MeasurementSignal(:θ,   θ),
        MeasurementSignal(:P_ac, P_ac),
        MeasurementSignal(:Q_ac, Q_ac),
        MeasurementSignal(:P_dc, P_dc),
    )
end

############################  Interface for composite block  ############################

statenames(m::Measurement) = (
    statenames(m.vG_d)...,
    statenames(m.vG_q)...,
    statenames(m.v_dc)...,
    statenames(m.i_d)...,
    statenames(m.i_q)...,
    statenames(m.i_dc)...,
    statenames(m.θ)...,
    statenames(m.P_ac)...,
    statenames(m.Q_ac)...,
    statenames(m.P_dc)...
)

function initialvalues(m::Measurement; inputs=nothing)
    return (;
        initialvalues(m.vG_d; inputs)...,
        initialvalues(m.vG_q; inputs)...,
        initialvalues(m.v_dc; inputs)...,
        initialvalues(m.i_d; inputs)...,
        initialvalues(m.i_q; inputs)...,
        initialvalues(m.i_dc; inputs)...,
        initialvalues(m.θ; inputs)...,
    )
end

inputnames(::Measurement) = (:vG_d, :vG_q, :v_dc, :i_d, :i_q, :i_dc, :θ)

outputnames(::Measurement) = (
    :vG_d_f,
    :vG_q_f,
    :v_dc_f,
    :i_d_f,
    :i_q_f,
    :i_dc_f,
    :θ_f,
    :P_ac_f,
    :Q_ac_f,
    :P_dc_f,
)

"""
$(TYPEDSIGNATURES)

Evaluate all measurement filters and return their filtered outputs.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `m`: Voltage, current, angle, and power measurement filters.
- `c`: Parent converter providing electrical bases and synchronization.

# Returns

- `vG_d_f`: Filtered grid-voltage d component in the synchronization frame
  \\[dimensionless\\].
- `vG_q_f`: Filtered grid-voltage q component in the synchronization frame
  \\[dimensionless\\].
- `v_dc_f`: Filtered DC voltage \\[dimensionless\\].
- `i_d_f`: Filtered AC-current d component in the synchronization frame
  \\[dimensionless\\].
- `i_q_f`: Filtered AC-current q component in the synchronization frame
  \\[dimensionless\\].
- `i_dc_f`: Filtered DC current \\[dimensionless\\].
- `θ_f`: Filtered synchronization angle \\[rad\\].
- `P_ac_f`: Filtered active AC power \\[dimensionless\\].
- `Q_ac_f`: Filtered reactive AC power \\[dimensionless\\].
- `P_dc_f`: Filtered DC power \\[dimensionless\\].

# Notes

```math
p_{ac}=v_{d,f}i_{d,f}+v_{q,f}i_{q,f},\\quad q_{ac}=-v_{q,f}i_{d,f}+v_{d,f}i_{q,f},\\quad p_{dc}=v_{dc,f}i_{dc,f}.
```

Power measurements are calculated from individually filtered voltage and current
signals, then passed through their own power filters. All electrical quantities use
converter bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = tlc().element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
block = Measurement()
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
signals = P.input_signals(model, x, inputs)
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, m::Measurement, c::AbstractConverter)
    vG_d, i = state_space_block!(F, x, inputs, m.vG_d, c, 1)
    vG_q, i = state_space_block!(F, x, inputs, m.vG_q, c, i)
    v_dc, i = state_space_block!(F, x, inputs, m.v_dc, c, i)
    i_d, i = state_space_block!(F, x, inputs, m.i_d, c, i)
    i_q, i = state_space_block!(F, x, inputs, m.i_q, c, i)
    i_dc, i = state_space_block!(F, x, inputs, m.i_dc, c, i)
    θ, i = state_space_block!(F, x, inputs, m.θ, c, i)

    # Computing the power from the measured signals
    measured = merge(vG_d, vG_q, v_dc, i_d, i_q, i_dc, θ)
    power_inputs = merge(inputs, (;
        P_ac = measured.vG_d_f * measured.i_d_f + measured.vG_q_f * measured.i_q_f,
        Q_ac = -measured.vG_q_f * measured.i_d_f + measured.vG_d_f * measured.i_q_f,
        P_dc = measured.v_dc_f * measured.i_dc_f,
    ))

    P_ac, i = state_space_block!(F, x, power_inputs, m.P_ac, c, i)
    Q_ac, i = state_space_block!(F, x, power_inputs, m.Q_ac, c, i)
    P_dc, _ = state_space_block!(F, x, power_inputs, m.P_dc, c, i)

    return merge(measured, P_ac, Q_ac, P_dc)
end

function outputequations!(F, x, inputs, y, m::Measurement)
    F[1] = y.vG_d_f
    F[2] = y.vG_q_f
    F[3] = y.v_dc_f
    F[4] = y.i_d_f
    F[5] = y.i_q_f
    F[6] = y.i_dc_f
    F[7] = y.θ_f
    F[8] = y.P_ac_f
    F[9] = y.Q_ac_f
    F[10] = y.P_dc_f
    return nothing
end
