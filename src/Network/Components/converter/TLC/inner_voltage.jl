############################  inner_voltage.jl  ############################

abstract type AbstractInnerVoltageTLC <: AbstractStateSpace end

struct NoInnerVoltageControl <: AbstractInnerVoltageTLC end

statenames(::NoInnerVoltageControl) = ()
# TODO: Delete after testing
#initialvalues(::NoInnerVoltageControl; kwargs...) = (;)

innervoltage(::NoInnerVoltageControl, x, meas, sync, pact, qact) =
    (; i_d_ref = pact.i_d_ref, i_q_ref = qact.i_q_ref)

state_space!(F, x, meas, sync, pact, qact, ::NoInnerVoltageControl; conv::AbstractTLC) = nothing