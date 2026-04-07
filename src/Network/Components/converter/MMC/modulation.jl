abstract type AbstractModulationMMC               <: AbstractStateSpace end 

struct UncompensatedModulation <: AbstractModulationMMC end
statenames(::UncompensatedModulation) = (;)
initialvalues(::UncompensatedModulation, inputs) = (;) 

function state_space!(F, x, inputs, b::UncompensatedModulation, conv::AbstractMMC)
    (;Δθ_c, Vdc, vMΔd_ref_c, vMΔq_ref_c, vMΣd_ref_c, vMΣq_ref_c, vMΣz_ref) = inputs

    # Δ variables multiplied by -1 * baseConv1 * 2/Vdc
    mΔd_c = -conv.elec.baseConv1 * 2/Vdc * vMΔd_ref_c 
    mΔq_c = -conv.elec.baseConv1 * 2/Vdc * vMΔq_ref_c

    # Σ variables multiplied by 2/Vdc
    mΣd_c = 2/Vdc * vMΣd_ref_c
    mΣq_c = 2/Vdc * vMΣq_ref_c
    mΣz = 2/Vdc * vMΣz_ref          # zero-sequence is reference-frame independent

    I_θ = [cos(Δθ_c) sin(Δθ_c); -sin(Δθ_c) cos(Δθ_c)];
    I_2θ = [cos(-2Δθ_c) sin(-2Δθ_c); -sin(-2Δθ_c) cos(-2Δθ_c)];
    mΔd, mΔq = I_θ * [mΔd_c, mΔq_c]
    mΣd, mΣq = I_2θ * [mΣd_c, mΣq_c]

    return (mΔd = mΔd, mΔq = mΔq, mΔZd = 0, mΔZq = 0,
        mΣd = mΣd, mΣq = mΣq, mΣz = mΣz)
end