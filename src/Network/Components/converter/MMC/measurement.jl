abstract type AbstractMeasurement               <: AbstractStateSpace end


struct NoFilter <: AbstractMeasurement end
statenames(::NoFilter) = (;)
initialvalues(::NoFilter, inputs) = (;) 

function state_space!(F, x, inputs, b::NoFilter, conv::AbstractMMC)
    iΔd, iΔq = get_states(x, :iΔd, :iΔq)

    P_ac = (inputs.Vᴳd * iΔd + inputs.Vᴳq * iΔq)
    Q_ac =  (-inputs.Vᴳq * iΔd + inputs.Vᴳd * iΔq)
    
    (P_ac_F = P_ac, Q_ac_F = Q_ac)
end