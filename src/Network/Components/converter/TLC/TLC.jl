export tlc,
       TLC,
       AbstractTLC,
       ElectricalTLC,
       MeasurementTLC,
       AbstractSynchronizationTLC,
       NoSynchronization,
       PLLSynchronization,
       AbstractOuterActiveTLC,
       AbstractFrequencySupportTLC,
       NoOuterActiveControl,
       NoFrequencySupport,
       OuterActivePowerControl,
       FrequencySupportLag,
       OuterActiveVdcControl,
       AbstractOuterReactiveTLC,
       AbstractVoltageSupportTLC,
       NoOuterReactiveControl,
       NoVoltageSupport,
       OuterReactiveQControl,
       OuterReactiveVacControl,
       VoltageSupportLag,
       AbstractInnerVoltageTLC,
       NoInnerVoltageControl,
       AbstractInnerCurrentTLC,
       NoInnerCurrentControl,
       InnerCurrentPIControl,
       AbstractModulationTLC,
       NoModulation,
       PadeModulation

abstract type AbstractTLC <: AbstractStateSpace end

include("electrical.jl")
include("measurement.jl")
include("synchronization.jl")
include("outer_active.jl")
include("outer_reactive.jl")
include("inner_voltage.jl")
include("inner_current.jl")
include("modulation.jl")

struct TLC{
    E<:ElectricalTLC,
    Meas<:MeasurementTLC,
    Synch<:AbstractSynchronizationTLC,
    Active<:AbstractOuterActiveTLC,
    Reactive<:AbstractOuterReactiveTLC,
    IV<:AbstractInnerVoltageTLC,
    IC<:AbstractInnerCurrentTLC,
    Mod<:AbstractModulationTLC} <: AbstractTLC

    elec::E
    meas::Meas
    synch::Synch
    outerActive::Active
    outerReactive::Reactive
    innerVoltage::IV
    innerCurrent::IC
    mod::Mod
end

statenames(c::TLC) = (
    statenames(c.elec)...,
    statenames(c.meas)...,
    statenames(c.synch)...,
    statenames(c.outerActive)...,
    statenames(c.outerReactive)...,
    statenames(c.innerVoltage)...,
    statenames(c.innerCurrent)...,
    statenames(c.mod)...
)

function initialvalues(c::TLC; inputs, setpoint=SetPoint(), kwargs...)
    # 1) electrical operating-point states
    elec_init = initialvalues(c.elec; inputs, setpoint, kwargs...)

    # 2) raw measurement inputs seen by MeasurementTLC at initialization
    meas_inputs = (
        v_d = inputs.v_d,
        v_q = inputs.v_q,
        vdc = inputs.vdc,
        i_d = elec_init.i_d,
        i_q = elec_init.i_q,
        idc = 0.0,
        θ   = setpoint.θac
    )

    return merge(
        elec_init,
        initialvalues(c.meas; inputs=meas_inputs, setpoint, kwargs..., conv=c),
        initialvalues(c.synch; inputs=meas_inputs, setpoint, kwargs..., conv=c),
        initialvalues(c.outerActive; inputs, setpoint, kwargs..., conv=c),
        initialvalues(c.outerReactive; inputs, setpoint, kwargs..., conv=c),
        initialvalues(c.innerVoltage; inputs, setpoint, kwargs..., conv=c),
        initialvalues(c.innerCurrent; inputs, setpoint, kwargs..., conv=c),
        initialvalues(c.mod; inputs, setpoint, kwargs..., conv=c)
    )
end

inputnames(::TLC) = (:vdc, :v_d, :v_q)
outputnames(::TLC) = (:idc, :i_d, :i_q)

function pftoinputs(c::TLC, setpoint::SetPoint)
    vACbase = c.elec.vACbase_LL_RMS * sqrt(2 / 3)
    v_bus_d = setpoint.Vac * cos(setpoint.θac) / vACbase
    v_bus_q = -setpoint.Vac * sin(setpoint.θac) / vACbase
    vdc = setpoint.Vdc / c.elec.vDCbase
    NamedTuple{inputnames(c)}((vdc, v_bus_d, v_bus_q))
end



function raw_measurements(c::TLC, x, inputs)
    θ = syncangle(c.synch, x)
    cθ = cos(θ)
    sθ = sin(θ)

    v_d =  cθ * inputs.v_d - sθ * inputs.v_q
    v_q =  sθ * inputs.v_d + cθ * inputs.v_q

    i_d =  cθ * x.i_d - sθ * x.i_q
    i_q =  sθ * x.i_d + cθ * x.i_q

    return (
        v_d = v_d,
        v_q = v_q,
        vdc = inputs.vdc,
        i_d = i_d,
        i_q = i_q,
        idc = 0.0,
        θ   = θ
    )
end

function outputequations!(F, x, inputs, c::TLC)
    meas_in = raw_measurements(c, x, inputs)
    meas  = measurement_outputs(x, meas_in, c.meas)
    sync  = synchronization(c.synch, x, meas)
    pact  = outeractive(c.outerActive, x, meas, sync)
    qact  = outerreactive(c.outerReactive, x, meas, sync)
    vloop = innervoltage(c.innerVoltage, x, meas, sync, pact, qact)
    iloop = innercurrent(c.innerCurrent, x, meas, sync, vloop, c)
    mod   = modulation(c.mod, x, iloop, c)

    y = electrical_outputs(c.elec, x, inputs, mod)

    F[1] = y.idc
    F[2] = y.i_d
    F[3] = y.i_q

    return nothing
end

function state_space!(F, x, inputs, c::TLC)
    meas_in = raw_measurements(c, x, inputs)
    meas  = measurement_outputs(x, meas_in, c.meas)
    sync  = synchronization(c.synch, x, meas)
    pact  = outeractive(c.outerActive, x, meas, sync)
    qact  = outerreactive(c.outerReactive, x, meas, sync)
    vloop = innervoltage(c.innerVoltage, x, meas, sync, pact, qact)
    iloop = innercurrent(c.innerCurrent, x, meas, sync, vloop, c)
    mod   = modulation(c.mod, x, iloop, c)

    i = 1

    n = n_states(c.elec)
    state_space!(@view(F[i:i+n-1]), x, inputs, mod, c.elec; conv=c)
    i += n

    n = n_states(c.meas)
    state_space!(@view(F[i:i+n-1]), x, meas_in, c.meas; conv=c)
    i += n

    n = n_states(c.synch)
    state_space!(@view(F[i:i+n-1]), x, meas, c.synch; conv=c)
    i += n

    n = n_states(c.outerActive)
    state_space!(@view(F[i:i+n-1]), x, meas, sync, c.outerActive; conv=c)
    i += n

    n = n_states(c.outerReactive)
    state_space!(@view(F[i:i+n-1]), x, meas, sync, c.outerReactive; conv=c)
    i += n

    n = n_states(c.innerVoltage)
    state_space!(@view(F[i:i+n-1]), x, meas, sync, pact, qact, c.innerVoltage; conv=c)
    i += n

    n = n_states(c.innerCurrent)
    state_space!(@view(F[i:i+n-1]), x, meas, sync, vloop, c.innerCurrent; conv=c)
    i += n

    n = n_states(c.mod)
    state_space!(@view(F[i:i+n-1]), x, iloop, c.mod; conv=c)

    return nothing
end


function equilibrium_state_space!(F, x, inputs, c::TLC, setpoint::SetPoint)
    equilibrium_state_space!(F, x, inputs, c, c.outerActive, setpoint)
    return nothing
end

function equilibrium_state_space!(F, x, inputs, c::TLC, ::AbstractOuterActiveTLC, setpoint::SetPoint)
    state_space!(F, x, inputs, c)
    return nothing
end

function equilibrium_state_space!(F, x, inputs, c::TLC, ::OuterActiveVdcControl, setpoint::SetPoint)
    # Start from the ordinary TLC state equations
    state_space!(F, x, inputs, c)

    # Replace the ξ_vdc residual by the legacy DC power-balance condition.
    # This is the elimination of the helper-state formulation used in TLC_legacy.jl.
    idx_ξvdc = n_states(c.elec) + n_states(c.meas) + n_states(c.synch) + 1

    T = promote_type(
        mapreduce(typeof, promote_type, values(x)),
        mapreduce(typeof, promote_type, values(inputs))
    )
    y = zeros(T, n_outputs(c))
    outputequations!(y, x, inputs, c)

    Idc_in = (setpoint.Pdc / c.elec.Sbase) / inputs.vdc
    F[idx_ξvdc] = Idc_in - y[1]

    return nothing
end

function tlc(;
    elec::ElectricalTLC = ElectricalTLC(),
    meas::MeasurementTLC = MeasurementTLC(),
    synch::AbstractSynchronizationTLC = NoSynchronization(),
    outerActive::AbstractOuterActiveTLC = NoOuterActiveControl(),
    outerReactive::AbstractOuterReactiveTLC = NoOuterReactiveControl(),
    innerVoltage::AbstractInnerVoltageTLC = NoInnerVoltageControl(),
    innerCurrent::AbstractInnerCurrentTLC = NoInnerCurrentControl(),
    mod::AbstractModulationTLC = NoModulation(),
    setpoint::SetPoint = SetPoint(),
    limits::Limits = Limits(),
    connection::Bool = true
)
    conv = TLC(elec, meas, synch, outerActive, outerReactive, innerVoltage, innerCurrent, mod)

    return Element(
        input_pins = 1,
        output_pins = 2,
        element_model = conv,
        transformation = false;
        connection,
        setpoint,
        limits,
    )
end