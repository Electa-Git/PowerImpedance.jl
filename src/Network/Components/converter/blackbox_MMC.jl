# This is a PowerImpedanceACDC element in order to model a MMC converter soley based on frequency scans, e.g.
# imported Two-port admittance matrix. It is a blackbox model, meaning that the internal structure of the converter is not modeled.
# The converter is represented by its imported Y-parameters.


export blackbox_MMC

# Type definition, add only elements needed for the blackbox model
@with_kw mutable struct Blackbox_MMC <: Converter

end

# Constructor function
# Pull in the data from file here and store it in the struct
# Then do the model matching for the equivalent resistor --> which pkg?
function blackbox_MMC(;args...)

    bbmmc = Blackbox_MMC()


end

# Here grab the data from the powerflow and store it in the converter struct
# Might wanna do a two stage interpolation here: First interpolate for the OP variables (Vm, θ, Pac, Qac, Vdc, Pdc),
# then interpolate for the frequency variable in eval_parameters function to make things faster 
function update!(converter :: Blackbox_MMC, Vm, θ, Pac, Qac, Vdc, Pdc)



end

# Here do the interpolation of the imported data to evaluate the admittance matrix at the given s=jω
function eval_parameters(converter :: Blackbox_MMC, s :: Complex)



end








