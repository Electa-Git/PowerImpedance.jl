export TotalEnergyControl, ΣEnergyControl, ΔEnergyControl

abstract type AbstractEnergyControl             <: AbstractStateSpace end

@with_kw struct TotalEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::TotalEnergyControl) = (:ξ_Wtot,)

function state_space!(F, x, inputs::NamedTuple{(:meas, :power)}, b::TotalEnergyControl, conv::AbstractMMC)
    (; meas, power) = inputs
    (; ξ_Wtot, vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; v_dc_f) = meas
    (; P_ac_f) = power
    # wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/(2)
    wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/2;
    
    F[1] = b.pi_control.Ki * (b.ref - wΣz)
    #iΣ_z_ref = (Kp_wΣ * (wΣz_ref - wΣz) + Ki_wΣ * xwΣz + Pac_f) / 3 / Vdc,
    return ( iΣ_z_ref = ( (b.pi_control.Kp * (b.ref - wΣz) + ξ_Wtot + P_ac_f) / 3 / v_dc_f ),)
end

@with_kw struct ΣEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1 # reference for the energy in each leg (in pu)
end
statenames(::ΣEnergyControl) = (:FΣ1_d, :FΣ1_q, :FΣ1_z, :FΣ2_d, :FΣ2_q, :FΣ2_z, # Notch filter states
                                    :ξ_wΣ_d, :ξ_wΣ_q, :ξ_wΣ_z)                  # PI controller states

function state_space!(F, x, inputs::NamedTuple{(:meas, :power, :sync)}, b::ΣEnergyControl, conv::AbstractMMC)
    (; vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; ω_c) = inputs.sync
    (; v_dc_f) = inputs.meas
    (; P_ac_f) = inputs.power

    # values in per-unit. wΔ have mainly dc and -2ω_c components
    wΣd = (vCΔ_d^2 - vCΔ_q^2 + 2 * vCΔ_Zd * vCΔ_d + 2 * vCΔ_Zq * vCΔ_q + 4 * vCΣ_d * vCΣ_z)/2
    wΣq = (2* vCΔ_q * vCΔ_Zd - 2 * vCΔ_d * vCΔ_Zq - 2 * vCΔ_d * vCΔ_q + 4 * vCΣ_q * vCΣ_z)/2
    wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/2;

    # notch filter. Expressed in dqz in -2ω_c reference frame.
    ω_n = 2 * conv.elec.ωbase # TODO change by actual frequency? (depends on how it is implemented in PSCAD)
    ζ = 0.7    
    FΣ1 = [x.FΣ1_d, x.FΣ1_q, x.FΣ1_z]; FΣ2 = [x.FΣ2_d, x.FΣ2_q, x.FΣ2_z]; wΣ = [wΣd, wΣq, wΣz] # Defining the vectors
    J = [ 0 1 0
         -1 0 0
          0 0 0]
    J_min2ω = -2 * ω_c * J # Here the actual frequency must be used as it is linked to reference frame transformations

    F[1:3] = FΣ2 - 2 * ζ * ω_n * (FΣ1 + wΣ) - J_min2ω * FΣ1
    F[4:6] = -ω_n^2 * FΣ1 - J_min2ω * FΣ2
    wΣ_f = FΣ1 + wΣ

    # PI controllers
    ξ_wΣ = [x.ξ_wΣ_d, x.ξ_wΣ_q, x.ξ_wΣ_z]; wΣ_f_ref = [0, 0, b.ref]
    Ki_wΣ = b.pi_control.Ki
    F[7:9] = Ki_wΣ * (wΣ_f_ref - wΣ_f) - J_min2ω * ξ_wΣ

    iΣ_dc_ref = ( [0, 0, P_ac_f/3] - ξ_wΣ + b.pi_control.Kp * (wΣ_f_ref - wΣ_f) ) / v_dc_f #TODO check Eros implementation (there are small differences, including here) 

    return (iΣ_d_dc_ref = iΣ_dc_ref[1], iΣ_q_dc_ref = iΣ_dc_ref[2], iΣ_z_dc_ref = iΣ_dc_ref[3])

end

@with_kw struct ΔEnergyControl <: AbstractEnergyControl
    pi_control::PIControl
    ref::Float64 = 1
end
statenames(::ΔEnergyControl) = (:FΔ1_d, :FΔ1_q, :FΔ1_Zd, :FΔ1_Zq, :FΔ2_d, :FΔ2_q, :FΔ2_Zd, :FΔ2_Zq, # Notch filter states
                                    :ξ_wΔ_d, :ξ_wΔ_q, :ξ_wΔ_Zd, :ξ_wΔ_Zq) # PI controller states

function state_space!(F, x, inputs::NamedTuple{(:meas, :power, :sync)}, b::ΔEnergyControl, conv::AbstractMMC)
    (; vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; ω_c) = inputs.sync

    # values in per-unit. wΔ have mainly ω_c and 3ω_c components
    wΔd = vCΔ_d * vCΣ_d + 2 * vCΔ_d * vCΣ_z - vCΔ_q * vCΣ_q + vCΔ_Zd * vCΣ_d - vCΔ_Zq * vCΣ_q
    wΔq = 2 * vCΔ_q * vCΣ_z - vCΔ_q * vCΣ_d - vCΔ_d * vCΣ_q + vCΔ_Zd * vCΣ_q + vCΔ_Zq * vCΣ_d
    wΔZd = vCΔ_d * vCΣ_d + vCΔ_q * vCΣ_q + 2 * vCΔ_Zd * vCΣ_z
    wΔZq = vCΔ_q * vCΣ_d - vCΔ_d * vCΣ_q + 2 * vCΔ_Zq * vCΣ_z

    # notch filter. Expressed in dqz in ω_c reference frame
    ω_n = conv.elec.ωbase # TODO change by actual frequency? (depends on how it is implemented in PSCAD)
    ζ = 0.7
    FΔ1 = [x.FΔ1_d, x.FΔ1_q, x.FΔ1_Zd, x.FΔ1_Zq]; FΔ2 = [x.FΔ2_d, x.FΔ2_q, x.FΔ2_Zd, x.FΔ2_Zq]; wΔ = [wΔd, wΔq, wΔZd, wΔZq]
    J_dq = [ 0 1
            -1 0]
    J_G = [ J_dq * ω_c zeros(2,2)
            zeros(2,2) J_dq * (-3ω_c)] # The minus sign comes from the convention used in Freytes thesis (could this be updated to a more consistent one?)

    F[1:4] = FΔ2 - 2 * ζ * ω_n * (FΔ1 + wΔ) - J_G * FΔ1
    F[5:8] = -ω_n^2 * FΔ1 - J_G * FΔ2
    wΔ_f = wΔ + FΔ1

    # PI controllers
    ξ_wΔ = [x.ξ_wΔ_d, x.ξ_wΔ_q, x.ξ_wΔ_Zd, x.ξ_wΔ_Zq]; wΔ_f_ref = [0, 0, 0, 0]
    Ki_wΔ = b.pi_control.Ki
    F[9:12] = Ki_wΔ * (wΔ_f_ref - wΔ_f) - J_G * ξ_wΔ
    
    d, q, Zd, Zq = -1*(ξ_wΔ + b.pi_control.Kp * (wΔ_f_ref - wΔ_f)) #TODO check Eros implementation (there are small differences, including here)
    iΣ_dqZ_ac_ref = 3/(2√2) * [d + Zd, q + Zq, 0]

    return (iΣ_d_ac_ref = iΣ_dqZ_ac_ref[1], iΣ_q_ac_ref = iΣ_dqZ_ac_ref[2], iΣ_z_ac_ref = iΣ_dqZ_ac_ref[3])
end
