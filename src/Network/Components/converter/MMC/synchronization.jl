abstract type AbstractSynchronization           <: AbstractStateSpace end

struct PLL <: AbstractSynchronization
    pi_control::PIControl
end
statenames(::PLL) = (:ξ_PLL, :Δθ_PLL)           #TODO: add all states (include filtering?)
initialvalues(::PLL, inputs) = (;ξ_PLL = 0.0)

@with_kw struct VSEWithDamping <: AbstractSynchronization   # VSE = Virtual Swing Equation
    H::Float64 = 5          # Virtual Inertia [s]
    K_d::Float64 = 100      # Damping coefficient [-]
    K_ω::Float64 = 10       # Droop coefficient [-]
    P_ac_ref::Float64 = 0   # Active power reference [pu]
    ω_ref::Float64 = 1      # Angular frequency reference [pu]
    pll::PLL                # PLL
end
statenames(b::VSEWithDamping) = (statenames(b.pll)..., :ω_VSM, :Δθ_VSM) # Careful: the order matters!
initialvalues(b::VSEWithDamping, inputs) = merge(initialvalues(b.pll, inputs), (; ω_VSM=1, Δθ_VSM=inputs.θac) )

@with_kw struct VSEWithoutDamping <: AbstractSynchronization   # VSE = Virtual Swing Equation
    H::Float64 = 5          # Virtual Inertia [s]
    K_d::Float64 = 100      # Damping coefficient [-]
    K_ω::Float64 = 10       # Droop coefficient [-]
    P_ac_ref::Float64 = 0   # Active power reference [pu]
    ω_ref::Float64 = 1      # Angular frequency reference [pu]
end
statenames(::VSEWithoutDamping) = (:ω_VSM, :Δθ_VSM)
initialvalues(::VSEWithoutDamping, inputs) = (; ω_VSM=1, Δθ_VSM=inputs.θac)

function state_space!(F, x, inputs, b::PLL, conv::AbstractMMC)
    (; ξ_PLL, Δθ_PLL)   = x
    (; Vᴳd, Vᴳq)        = inputs

    T_θ_PLL = [cos(Δθ_PLL) -sin(Δθ_PLL); sin(Δθ_PLL) cos(Δθ_PLL)]
    (_, Vᴳq_pll) = T_θ_PLL * [Vᴳd, Vᴳq] * conv.elec.turnsRatio              #TODO check if really needed to multiply by turnratio?
    Vᴳq_pll_f = -1*Vᴳq_pll     #TODO implement filter

    Δω_PLL = b.pi_control.Kp * Vᴳq_pll_f + ξ_PLL #Delta omega_pll [pu]
    
    F[1] = Vᴳq_pll_f * b.pi_control.Ki
    F[2] = conv.elec.wbase * Δω_PLL
    
    return (;Δθ_c = Δθ_PLL, ω_c = Δω_PLL + 1) # returns the synchronisation angle
end 

function state_space!(F, x, inputs, b::VSEWithDamping, conv::AbstractMMC)
    idx = 1
    out_pll, idx = run_block!(F, x, inputs, b.pll, conv, idx)

    ω_PLL = out_pll.ω_c
    (; ω_VSM, Δθ_VSM) = x
    (;P_ac_F) = inputs

    # dω_VSM / dt = 
    F[idx] =(b.P_ac_ref - P_ac_F - b.K_d * (ω_VSM-ω_PLL) - b.K_ω * (ω_VSM-b.ω_ref)) / (2*b.H) 

    # dΔθ_VSM/dt
    F[idx + 1] = conv.elec.wbase * (ω_VSM-1)
    
    return (;Δθ_c = Δθ_VSM, ω_c = ω_VSM)
end
                    
function state_space!(F, x, inputs, b::VSEWithoutDamping, conv::AbstractMMC)
    (; ω_VSM, Δθ_VSM) = x
    (;P_ac_F) = inputs

    # dω_VSM / dt = 
    F[1] =(b.P_ac_ref - P_ac_F - b.K_ω * (ω_VSM-b.ω_ref)) / (2*b.H) 

    # dΔθ_VSM/dt
    F[2] = conv.elec.wbase * (ω_VSM-1)
    
    return (;Δθ_c = Δθ_VSM, ω_c = ω_VSM)
end