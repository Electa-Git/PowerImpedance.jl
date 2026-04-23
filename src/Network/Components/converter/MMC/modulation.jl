export UncompensatedModulation, CompensatedModulation


abstract type AbstractModulationMMC               <: AbstractStateSpace end 


struct UncompensatedModulation{D<:PadeDelay} <: AbstractModulationMMC 
    delay1::D
    delay2::D
    delay3::D
end
statenames(m::UncompensatedModulation) = (statenames(m.delay1)..., statenames(m.delay2)..., statenames(m.delay3)...)

function UncompensatedModulation(;
    timeDelay::Real = 0.0,
    padeOrderNum::Int = 0,
    padeOrderDen::Int = 0
)
    delay1 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 2,
        state_prefix = :mΔ_delay,
    )
    delay2 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 2,
        state_prefix = :mΣ_delay,
    )
    delay3 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 1,
        state_prefix = :mΣ_z_delay,
    )
    return UncompensatedModulation{PadeDelay}(delay1, delay2, delay3)
end


function state_space!(F, x, inputs, b::UncompensatedModulation, conv::AbstractMMC)
    (; meas, out_delta, out_sigma) = inputs
    (;v_dc_f) = meas
    (; vMΔ_d_ref_c, vMΔ_q_ref_c) = out_delta
    (; vMΣ_d_ref_c, vMΣ_q_ref_c, vMΣ_z_ref) = out_sigma

    # First, the references are converter to grid reference framoe
    Δθ_c = syncangle(conv.sync, x)
    vMΔ_d_ref, vMΔ_q_ref = inverse_frame_transform(vMΔ_d_ref_c, vMΔ_q_ref_c, Δθ_c)
    vMΣ_d_ref, vMΣ_q_ref = inverse_frame_transform(vMΣ_d_ref_c, vMΣ_q_ref_c, -2*Δθ_c) # Zero sequence is reference frame independent, so not transformed

    # Δ variables multiplied by -1 * baseConv1 * 2/v_dc_f
    mΔd = -conv.elec.baseConv1 * 2/v_dc_f * vMΔ_d_ref 
    mΔq = -conv.elec.baseConv1 * 2/v_dc_f * vMΔ_q_ref

    # Σ variables multiplied by 2/v_dc_f
    mΣd = 2/v_dc_f * vMΣ_d_ref
    mΣq = 2/v_dc_f * vMΣ_q_ref
    mΣz = 2/v_dc_f * vMΣ_z_ref          # zero-sequence is reference-frame independent

    # Pade delays
    y, i = state_space_block!(F, x, (mΔd, mΔq), b.delay1, conv, 1)
    mΔd, mΔq = phase_compensated_dq(y, conv.elec.ωbase * b.delay1.timeDelay)

    y, i = state_space_block!(F, x, (mΣd, mΣq), b.delay2, conv, i)
    mΣd, mΣq = phase_compensated_dq(y, -2*conv.elec.ωbase * b.delay2.timeDelay)

    mΣz = state_space_block!(F, x, (mΣz, ), b.delay3, conv, i)[1][1]

    return (mΔd = mΔd, mΔq = mΔq, mΔZd = 0, mΔZq = 0,
        mΣd = mΣd, mΣq = mΣq, mΣz = mΣz)
end

struct CompensatedModulation <: AbstractModulationMMC end
statenames(::CompensatedModulation) = (;)

function state_space!(F, x, inputs, b::CompensatedModulation, conv::AbstractMMC)
    (; meas, out_delta, out_sigma) = inputs
    (; vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; vMΔ_d_ref_c, vMΔ_q_ref_c) = out_delta
    (; vMΣ_d_ref_c, vMΣ_q_ref_c, vMΣ_z_ref) = out_sigma
    
    # First, the references are converter to grid reference framoe
    Δθ_c = syncangle(conv.sync, x)
    vMΔ_d_ref, vMΔ_q_ref = inverse_frame_transform(vMΔ_d_ref_c, vMΔ_q_ref_c, Δθ_c)
    vMΣ_d_ref, vMΣ_q_ref = inverse_frame_transform(vMΣ_d_ref_c, vMΣ_q_ref_c, -2*Δθ_c) # Zero sequence is reference frame independent, so not transformed

    VΣΔ_CmdqZ = 1/4 * [ 2 * vCΣ_z       0              2 * vCΣ_d               vCΔ_d + vCΔ_Zd       vCΔ_Zq - vCΔ_q       vCΔ_d       vCΔ_q
                        0              2 * vCΣ_z       2 * vCΣ_q               -vCΔ_q - vCΔ_Zq      vCΔ_Zd - vCΔ_d       vCΔ_q       -vCΔ_d
                        vCΣ_d           vCΣ_q           2 * vCΣ_z               vCΔ_d               vCΔ_q               vCΔ_Zd      vCΔ_Zq
                        -vCΔ_d - vCΔ_Zd  vCΔ_q + vCΔ_Zq   -2 * vCΔ_d              -vCΣ_d - 2 * vCΣ_z   vCΣ_q               -vCΣ_d      vCΣ_q
                        vCΔ_q - vCΔ_Zq   vCΔ_d - vCΔ_Zd   -2 * vCΔ_q              vCΣ_q               vCΣ_d - 2 * vCΣ_z    -vCΣ_q      -vCΣ_d
                        -vCΔ_d          -vCΔ_q          -2 * vCΔ_Zd             -vCΣ_d              -vCΣ_q              -2 * vCΣ_z  0
                        -vCΔ_q          vCΔ_d           -2 * vCΔ_Zq             vCΣ_q               -vCΣ_d              0          -2 * vCΣ_z]
    
    # For optimization, the matrix VΣΔ_CmdqZ could be inversed or factorized (symbolically) beforehand. But is it needed?
    (mΣd, mΣq, mΣz, mΔd, mΔq, mΔZd, mΔZq) = [fill(1, 3); fill(conv.elec.baseConv1, 4)] .*  # Δ variables multiplied by baseConv1 (DC -> AC base conversion)
                                                    VΣΔ_CmdqZ \ [vMΣ_d_ref; vMΣ_q_ref; vMΣ_z_ref; vMΔ_d_ref; vMΔ_q_ref; 0; 0] # vΔZdq_c are set to zero by controller, but mΔZdq_c can be different from zero

    return (mΔd = mΔd, mΔq = mΔq, mΔZd = mΔZd, mΔZq = mΔZq,
        mΣd = mΣd, mΣq = mΣq, mΣz = mΣz)
end
