abstract type AbstractModulationMMC               <: AbstractStateSpace end 
struct ModulationInputs
    meas
    vMΔ_ref_c
    vMΣ_ref_c
end


struct UncompensatedModulation <: AbstractModulationMMC end
statenames(::UncompensatedModulation) = (;)

function state_space!(F, x, inputs::ModulationInputs, b::UncompensatedModulation, conv::AbstractMMC)
    (;v_dc_f) = inputs.meas
    (; vMΔd_ref_c, vMΔq_ref_c) = inputs.vMΔ_ref_c
    (; vMΣd_ref_c, vMΣq_ref_c, vMΣz_ref) = inputs.vMΣ_ref_c

    Δθ_c = syncangle(conv.sync, x)
    # First, the references are converter to grid reference framoe
    I_θ = [cos(Δθ_c) sin(Δθ_c); -sin(Δθ_c) cos(Δθ_c)];
    I_2θ = [cos(-2Δθ_c) sin(-2Δθ_c); -sin(-2Δθ_c) cos(-2Δθ_c)];

    vMΔd_ref, vMΔq_ref = I_θ * [vMΔd_ref_c, vMΔq_ref_c]
    vMΣd_ref, vMΣq_ref = I_2θ * [vMΣd_ref_c, vMΣq_ref_c] # Zero sequence is reference frame independent, so not transformed


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

function state_space!(F, x, inputs, b::CompensatedModulation, conv::AbstractMMC)
    (; vCΔd, vCΔq, vCΔZd, vCΔZq, vCΣd, vCΣq, vCΣz) = x
    (;Δθ_c, 
        vMΔd_ref_c, vMΔq_ref_c, vMΣd_ref_c, vMΣq_ref_c, vMΣz_ref) = inputs
    
    # First, the references are converter to grid reference framoe
    I_θ = [cos(Δθ_c) sin(Δθ_c); -sin(Δθ_c) cos(Δθ_c)];
    I_2θ = [cos(-2Δθ_c) sin(-2Δθ_c); -sin(-2Δθ_c) cos(-2Δθ_c)];

    vMΔd_ref, vMΔq_ref = I_θ * [vMΔd_ref_c, vMΔq_ref_c]
    vMΣd_ref, vMΣq_ref = I_2θ * [vMΣd_ref_c, vMΣq_ref_c] # Zero sequence is reference frame independent, so not transformed

    VΣΔ_CmdqZ = 1/4 * [ 2 * vCΣz       0              2 * vCΣd               vCΔd + vCΔZd       vCΔZq - vCΔq       vCΔd       vCΔq
                        0              2 * vCΣz       2 * vCΣq               -vCΔq - vCΔZq      vCΔZd - vCΔd       vCΔq       -vCΔd
                        vCΣd           vCΣq           2 * vCΣz               vCΔd               vCΔq               vCΔZd      vCΔZq
                        -vCΔd - vCΔZd  vCΔq + vCΔZq   -2 * vCΔd              -vCΣd - 2 * vCΣz   vCΣq               -vCΣd      vCΣq
                        vCΔq - vCΔZq   vCΔd - vCΔZd   -2 * vCΔq              vCΣq               vCΣd - 2 * vCΣz    -vCΣq      -vCΣd
                        -vCΔd          -vCΔq          -2 * vCΔZd             -vCΣd              -vCΣq              -2 * vCΣz  0
                        -vCΔq          vCΔd           -2 * vCΔZq             vCΣq               -vCΣd              0          -2 * vCΣz]
    
    # For optimization, the matrix VΣΔ_CmdqZ could be inversed or factorized (symbolically) beforehand. But is it needed?
    (mΣd, mΣq, mΣz, mΔd, mΔq, mΔZd, mΔZq) = [fill(1, 3); fill(conv.elec.baseConv1, 4)] .*  # Δ variables multiplied by baseConv1 (DC -> AC base conversion)
                                                    VΣΔ_CmdqZ \ [vMΣd_ref; vMΣq_ref; vMΣz_ref; vMΔd_ref; vMΔq_ref; 0; 0] # vΔZdq_c are set to zero by controller, but mΔZdq_c can be different from zero

    return (mΔd = mΔd, mΔq = mΔq, mΔZd = 0, mΔZq = 0,
        mΣd = mΣd, mΣq = mΣq, mΣz = mΣz)
end
