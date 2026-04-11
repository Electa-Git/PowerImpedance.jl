############################  inner_voltage.jl  ############################

abstract type AbstractInnerVoltageTLC <: AbstractStateSpace end

struct NoInnerVoltageControl <: AbstractInnerVoltageTLC end

statenames(::NoInnerVoltageControl) = ()

state_space!(F, x, meas, sync, pact, qact, block::NoInnerVoltageControl; conv::AbstractTLC) =
    (; i_d_ref = pact.i_d_ref, i_q_ref = qact.i_q_ref)
