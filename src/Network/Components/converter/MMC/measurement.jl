abstract type AbstractMeasurement               <: AbstractStateSpace end


struct NoMeasurementFilter <: AbstractMeasurement end
statenames(::NoMeasurementFilter) = (;)
initialvalues(::NoMeasurementFilter, inputs) = (;) 

function state_space!(F, x, inputs, b::NoMeasurementFilter, conv::AbstractMMC)
    iΔd, iΔq = get_states(x, :iΔd, :iΔq)

    P_ac = (inputs.Vᴳd * iΔd + inputs.Vᴳq * iΔq)
    Q_ac =  (-inputs.Vᴳq * iΔd + inputs.Vᴳd * iΔq)
    
    (P_ac_F = P_ac, Q_ac_F = Q_ac)
end