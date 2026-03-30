############################  outer_reactive.jl  ############################

using Parameters

abstract type AbstractOuterReactiveTLC <: AbstractStateSpace end

struct NoOuterReactiveControl <: AbstractOuterReactiveTLC end

statenames(::NoOuterReactiveControl) = ()
initialvalues(::NoOuterReactiveControl; kwargs...) = (;)

outerreactive(::NoOuterReactiveControl, x, meas, sync) = (; i_q_ref = 0.0)

state_space!(F, x, meas, sync, ::NoOuterReactiveControl; conv::AbstractTLC) = nothing

@with_kw struct OuterReactiveQControl <: AbstractOuterReactiveTLC
    ctrl::PIControl = PI_control()
    vac_supp::Union{Nothing, PIControl} = nothing
end

function statenames(block::OuterReactiveQControl)
    block.vac_supp === nothing ? (:ξ_q,) : (:ξ_vac_supp, :ξ_q)
end

function initialvalues(block::OuterReactiveQControl; kwargs...)
    names = statenames(block)
    return NamedTuple{names}(ntuple(_ -> 0.0, length(names)))
end

function outerreactive(block::OuterReactiveQControl, x, meas, sync)
    q_ref = block.ctrl.ref[1]
    Q_ac = -meas.v_q_f * meas.i_d_f + meas.v_d_f * meas.i_q_f

    if block.vac_supp === nothing
        i_q_ref = block.ctrl.Kₚ * (q_ref - Q_ac) + x.ξ_q
    else
        q_ref = q_ref + x.ξ_vac_supp
        i_q_ref = block.ctrl.Kₚ * (q_ref - Q_ac) + x.ξ_q
    end

    return (
        q_ref = q_ref,
        Q_ac = Q_ac,
        i_q_ref = i_q_ref
    )
end

function state_space!(F, x, meas, sync, block::OuterReactiveQControl; conv::AbstractTLC)
    q_ref = block.ctrl.ref[1]
    Q_ac = -meas.v_q_f * meas.i_d_f + meas.v_d_f * meas.i_q_f

    if block.vac_supp === nothing
        F[1] = block.ctrl.Kᵢ * (q_ref - Q_ac)
    else
        # Legacy ordering: support state first, then Q integrator
        V_mag = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
        Δq_unf = block.vac_supp.Kₚ * (block.vac_supp.ref[1] - V_mag)
        F[1] = block.vac_supp.ω_f * (Δq_unf - x.ξ_vac_supp)

        q_ref = q_ref + x.ξ_vac_supp
        F[2] = block.ctrl.Kᵢ * (q_ref - Q_ac)
    end

    return nothing
end

@with_kw struct OuterReactiveVacControl <: AbstractOuterReactiveTLC
    ctrl::PIControl = PI_control()
end

statenames(::OuterReactiveVacControl) = (:ξ_vac,)
initialvalues(::OuterReactiveVacControl; kwargs...) = (ξ_vac = 0.0,)

function outerreactive(block::OuterReactiveVacControl, x, meas, sync)
    Vac = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
    i_q_ref = block.ctrl.Kₚ * (block.ctrl.ref[1] - Vac) + x.ξ_vac

    return (
        Vac = Vac,
        i_q_ref = i_q_ref
    )
end

function state_space!(F, x, meas, sync, block::OuterReactiveVacControl; conv::AbstractTLC)
    Vac = sqrt(meas.v_d_f^2 + meas.v_q_f^2)
    F[1] = block.ctrl.Kᵢ * (block.ctrl.ref[1] - Vac)
    return nothing
end