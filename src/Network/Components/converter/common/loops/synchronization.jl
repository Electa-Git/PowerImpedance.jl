############################  common/loops/synchronization.jl  ############################

#=
Shared synchronization blocks for converter control models.

Synchronization blocks provide the control-frame angle and frequency deviation
used by downstream outer and inner loops. The current implementations cover a
no-synchronization pass-through and a filtered PLL.
=#

export AbstractSynchronization,
       NoSynchronization,
       PLLSynchronization,
       VSEWithDamping

"""
Abstract supertype for TLC-compatible synchronization blocks.
"""
abstract type AbstractSynchronization <: AbstractStateSpace end

"""
Synchronization block that fixes the control frame to the stationary frame.
"""
struct NoSynchronization <: AbstractSynchronization end

"""
Return state names for no synchronization.

$(SIGNATURES)
"""
statenames(::NoSynchronization) = ()

"""
Return the synchronization angle used before measurement filtering.

$(SIGNATURES)
"""
syncangle(::NoSynchronization, x) = 0.0

"""
Return nominal synchronization outputs without state equations.

$(SIGNATURES)
"""
state_space!(F, x, meas, block::NoSynchronization; conv::AbstractConverter) = (ω_c = 1.0,)

"""
Phase-locked-loop synchronization block.

$(TYPEDEF)

# Fields

$(TYPEDFIELDS)
"""
struct PLLSynchronization{Filter<:AbstractMeasurementFilter} <: AbstractSynchronization
    pi_ctrl::PIControl
    filter::Filter
end

"""
Construct a PLL synchronization block.

$(SIGNATURES)

# Details

The `filter` argument filters the measured q-axis voltage before the PI
controller computes the frequency deviation.
"""
function PLLSynchronization(; pi_ctrl::PIControl = PIControl(), filter::AbstractMeasurementFilter = NoFilter())
    filter = measurement_filter_ss(filter)

    return PLLSynchronization{typeof(filter)}(
        pi_ctrl,
        filter,
    )
end

"""
Return the PLL angle used before measurement filtering.

$(SIGNATURES)
"""
syncangle(::PLLSynchronization, x) = x.Δθ_pll

"""
Return PLL state names.

$(SIGNATURES)
"""
function statenames(block::PLLSynchronization)
    n = size(block.filter.A, 1)
    return (
        ntuple(i -> Symbol("v_q_pll_f_x$i"), n)...,
        :ξ_pll,
        :Δθ_pll,
    )
end

"""
Evaluate PLL filter, PI integrator, and angle state equations.

$(SIGNATURES)
"""
function state_space!(F, x, meas, block::PLLSynchronization, conv::AbstractConverter)
    n = size(block.filter.A, 1)
    xf = collect(getfield(x, Symbol("v_q_pll_f_x$i")) for i in 1:n)
    _, vG_q_pll_f = frame_transform(meas.vG_d_f, meas.vG_q_f, (x.Δθ_pll - syncangle(conv.sync, x))) # Ensuring that voltage is in PLL reference frame (it is not the converter reference frame in GFM)
    u = [vG_q_pll_f]

    dx_f = block.filter.A * xf + block.filter.B * u
    v_pll = (block.filter.C * xf + block.filter.D * u)[1]
    Δω = -block.pi_ctrl.Kp * v_pll + x.ξ_pll

    @inbounds for i in 1:n
        F[i] = dx_f[i]
    end

    F[n + 1] = -block.pi_ctrl.Ki * v_pll
    F[n + 2] = conv.elec.ωbase * Δω

    return (ω_c = Δω + 1,)
end


@with_kw struct VSEWithDamping <: AbstractSynchronization   # VSE = Virtual Swing Equation
    H::Float64 = 5          # Virtual Inertia [s]
    K_d::Float64 = 100      # Damping coefficient [-]
    K_ω::Float64 = 10       # Droop coefficient [-]
    P_ac_ref::Float64 = 0   # Active power reference [pu]
    ω_ref::Float64 = 1      # Angular frequency reference [pu]
    pll::PLLSynchronization # PLL
end
statenames(b::VSEWithDamping) = (statenames(b.pll)..., :ω_VSM, :Δθ_VSM) # Careful: the order matters!
initialvalues(b::VSEWithDamping; setpoint_pu) = (; initialvalues(b.pll)..., (; ω_VSM=1, Δθ_VSM=setpoint_pu.θ_ac)...)

function state_space!(F, x, meas, b::VSEWithDamping, conv::AbstractConverter)
    i = 1
    n = n_states(b.pll)

    out_pll = state_space!(@view(F[i:i+n-1]), x, meas, b.pll, conv)
    i += n

    ω_PLL = out_pll.ω_c
    
    ω_VSM = x.ω_VSM

    P_ac_f = meas.vG_d_f * meas.i_d_f + meas.vG_q_f * meas.i_q_f
    
    # dω_VSM / dt = ...
    F[i] = (b.P_ac_ref - P_ac_f - b.K_d * (ω_VSM-ω_PLL) - b.K_ω * (ω_VSM-b.ω_ref)) / (2*b.H) 

    # dΔθ_VSM/dt
    F[i+1] = conv.elec.ωbase * (ω_VSM-1)
    
    return (; ω_c = ω_VSM)
end

syncangle(::VSEWithDamping, x) = x.Δθ_VSM
       