#=
Shared inner-voltage-loop slot for modular converters.

The current modular TLC implementation only provides a pass-through voltage
loop. The abstraction is kept so voltage-loop implementations can be added
without changing the surrounding converter orchestration.
=#

export AbstractInnerVoltageTLC,
       NoInnerVoltageControl

"""
Abstract supertype for TLC inner-voltage controllers.
"""
abstract type AbstractInnerVoltageTLC <: AbstractStateSpace end

"""
Pass-through inner-voltage controller.

Forwards active and reactive current references to the inner-current loop.
"""
struct NoInnerVoltageControl <: AbstractInnerVoltageTLC end

"""
Return state names for no inner-voltage control.

$(SIGNATURES)
"""
statenames(::NoInnerVoltageControl) = ()

"""
Forward outer-loop current references.

$(SIGNATURES)
"""
state_space!(F, x, meas, sync, pact, qact, block::NoInnerVoltageControl; conv::AbstractTLC) =
    (; i_d_ref = pact.i_d_ref, i_q_ref = qact.i_q_ref)
