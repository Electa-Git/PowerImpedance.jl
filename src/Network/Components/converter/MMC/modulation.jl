abstract type AbstractModulationMMC               <: AbstractStateSpace end 

struct UncompensatedModulation <: AbstractModulationMMC end
statenames(::UncompensatedModulation) = (;)

struct UncompensatedModulationDelay{D<:PadeDelay} <: AbstractModulationMMC 
    delay::D
end

function UncompensatedModulationDelay(;
    timeDelay::Real = 0.0,
    padeOrderNum::Int = 0,
    padeOrderDen::Int = 0
)
    delay = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 2,
        state_prefix = :m_delay,
    )
    return DelayModulation{PadeDelay}(delay)
end


function state_space!(F, x, (meas, out_delta, out_sigma), b::UncompensatedModulation, conv::AbstractMMC)
    (;v_dc_f) = meas
    (; vMΔd_ref_c, vMΔq_ref_c) = out_delta
    (; vMΣd_ref_c, vMΣq_ref_c, vMΣz_ref) = out_sigma

    # First, the references are converter to grid reference framoe
    Δθ_c = syncangle(conv.sync, x)
    vMΔd_ref, vMΔq_ref = inverse_frame_transform(vMΔd_ref_c, vMΔq_ref_c, Δθ_c)
    vMΣd_ref, vMΣq_ref = inverse_frame_transform(vMΣd_ref_c, vMΣq_ref_c, -2*Δθ_c) # Zero sequence is reference frame independent, so not transformed

    # Δ variables multiplied by -1 * baseConv1 * 2/v_dc_f
    mΔd = -conv.elec.baseConv1 * 2/v_dc_f * vMΔd_ref 
    mΔq = -conv.elec.baseConv1 * 2/v_dc_f * vMΔq_ref

    # Σ variables multiplied by 2/v_dc_f
    mΣd = 2/v_dc_f * vMΣd_ref
    mΣq = 2/v_dc_f * vMΣq_ref
    mΣz = 2/v_dc_f * vMΣz_ref          # zero-sequence is reference-frame independent

    return (mΔd = mΔd, mΔq = mΔq, mΔZd = 0, mΔZq = 0,
        mΣd = mΣd, mΣq = mΣq, mΣz = mΣz)
end

struct CompensatedModulation <: AbstractModulationMMC end
statenames(::CompensatedModulation) = (;)

function state_space!(F, x, (meas, out_delta, out_sigma), b::CompensatedModulation, conv::AbstractMMC)
    (; vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; vMΔd_ref_c, vMΔq_ref_c) = inputs.vMΔ_ref_c
    (; vMΣd_ref_c, vMΣq_ref_c, vMΣz_ref) = inputs.vMΣ_ref_c
    
    # First, the references are converter to grid reference framoe
    Δθ_c = syncangle(conv.sync, x)
    vMΔd_ref, vMΔq_ref = inverse_frame_transform(vMΔd_ref_c, vMΔq_ref_c, Δθ_c)
    vMΣd_ref, vMΣq_ref = inverse_frame_transform(vMΣd_ref_c, vMΣq_ref_c, -2*Δθ_c) # Zero sequence is reference frame independent, so not transformed

    VΣΔ_CmdqZ = 1/4 * [ 2 * vCΣ_z       0              2 * vCΣ_d               vCΔ_d + vCΔ_Zd       vCΔ_Zq - vCΔ_q       vCΔ_d       vCΔ_q
                        0              2 * vCΣ_z       2 * vCΣ_q               -vCΔ_q - vCΔ_Zq      vCΔ_Zd - vCΔ_d       vCΔ_q       -vCΔ_d
                        vCΣ_d           vCΣ_q           2 * vCΣ_z               vCΔ_d               vCΔ_q               vCΔ_Zd      vCΔ_Zq
                        -vCΔ_d - vCΔ_Zd  vCΔ_q + vCΔ_Zq   -2 * vCΔ_d              -vCΣ_d - 2 * vCΣ_z   vCΣ_q               -vCΣ_d      vCΣ_q
                        vCΔ_q - vCΔ_Zq   vCΔ_d - vCΔ_Zd   -2 * vCΔ_q              vCΣ_q               vCΣ_d - 2 * vCΣ_z    -vCΣ_q      -vCΣ_d
                        -vCΔ_d          -vCΔ_q          -2 * vCΔ_Zd             -vCΣ_d              -vCΣ_q              -2 * vCΣ_z  0
                        -vCΔ_q          vCΔ_d           -2 * vCΔ_Zq             vCΣ_q               -vCΣ_d              0          -2 * vCΣ_z]
    
    # For optimization, the matrix VΣΔ_CmdqZ could be inversed or factorized (symbolically) beforehand. But is it needed?
    (mΣd, mΣq, mΣz, mΔd, mΔq, mΔZd, mΔZq) = [fill(1, 3); fill(conv.elec.baseConv1, 4)] .*  # Δ variables multiplied by baseConv1 (DC -> AC base conversion)
                                                    VΣΔ_CmdqZ \ [vMΣd_ref; vMΣq_ref; vMΣz_ref; vMΔd_ref; vMΔq_ref; 0; 0] # vΔZdq_c are set to zero by controller, but mΔZdq_c can be different from zero

    return (mΔd = mΔd, mΔq = mΔq, mΔZd = 0, mΔZq = 0,
        mΣd = mΣd, mΣq = mΣq, mΣz = mΣz)
end
