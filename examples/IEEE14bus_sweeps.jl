# This is a PowerImpedance implementation of the modified IEEE 14 bus system test system


# Arranging environment
using PowerImpedanceACDC
using Plots#;plotlyjs() #Dynamic backend
using LaTeXStrings # Latex fonts
using LinearAlgebra
using Munkres
using JLD2
using Peaks
# Include Amauris function to do eps exports with inkscape
include("C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Scripts\\Julia\\export_eps.jl")
# Path to the inscape executable 
inkscape="c:\\Users\\jkirchei\\Desktop\\inkscape\\inkscape\\bin\\inkscape.exe"
# Path to store the resulting eps
storage_path="C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Data\\Processed"
# Storage path for data
storage_path_data="C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Data\\Raw"
# Path to store the resulting eps

storage_path_fig="C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Data\\Processed"


struct PowerFlowResult
        Vm:: Vector{Float64} 
        Va:: Vector{Float64}
        P:: Vector{Float64}
        Q:: Vector{Float64}
        Vdc:: Vector{Float64}
        Pdc :: Vector{Float64}
end

struct ModeInfo
#Container to hold the information of the unstable mode from open loop or closed loop analysis 
    frequency:: Float64 # Frequency of the unstable mode 
    uncertainty:: Bool  # Uncertainty flag, indicating whether frequency resolution is sufficient
    λ_index:: Int64     # Index of the eigenvalue locus associated with the mode
    PFs :: Vector{Float64} # Participation factors of the mode
end

struct EVDInfo # Results from closed loop analysis

        stability:: Int64 # Stability assessment 
        modes:: Vector{ModeInfo} # Unstable modes

end


struct GNCInfo # Result from Open loop analysis
# Container to hold the information extracted from GNC, open loop analysis :)


        stability:: Int64 # Stability assessment with GNC: 1 = stable, 0 = unstable, -1 = unstable subsystem
        modes:: Vector{ModeInfo} # Unstable modes based on 1/(lambda+1) approach 


end
function Nyquist(L::Vector{Matrix{ComplexF64}}, omega::Vector{Float64})

    # Determine eigenvalues of the loop gain matrix at each frequency point 
    Λ = eigvals.(L)

    # Number of frequency points
    omegaₙ = size(Λ, 1)
    # Number of eigenvalues for each frequency point
    λₙ = size(Λ[1], 1)
    # L has dimensions λₙxλₙxomegaₙ 

    # Sorting algorithm of eigenvalues to create continuous eigenloci in Nyquist plot 
    # Create empty matrix for sorted eigenvalues 
    Λₛ = zeros(Complex{Float64}, omegaₙ, λₙ)
    # First row of eigenvalues remains the same 
    Λₛ[1,:] = Λ[1]

    for i in 2:omegaₙ
        
        # Row of eigenvalues at previous frequency point 
        Λ₁ = Λ[i-1]
        # Row of eigenvalues at current frequency point
        Λ₂ = Λ[i]

        # Algorithm: 
        # see Munkres.jl https://juliapackages.com/p/munkres
        # see eigenshuffle.m https://nl.mathworks.com/matlabcentral/fileexchange/22885-eigenshuffle
        # Sorting eigenvalues of row i to obtain minimum distance between row i and row i-1

        Λ₁_Re = real(Λ₁)
        Λ₂_Re = real(Λ₂)

        Λ₁_Re_Grid = [i for i in Λ₁_Re, j in 1:length(Λ₂_Re)]
        Λ₂_Re_Grid = [j for i in 1:length(Λ₁_Re), j in Λ₂_Re]

        Λ_Re = abs.(Λ₁_Re_Grid - Λ₂_Re_Grid)

        Λ₁_Im = imag(Λ₁)
        Λ₂_Im = imag(Λ₂)

        Λ₁_Im_Grid = [i for i in Λ₁_Im, j in 1:length(Λ₂_Im)]
        Λ₂_Im_Grid = [j for i in 1:length(Λ₁_Im), j in Λ₂_Im]

        Λ_Im = abs.(Λ₁_Im_Grid - Λ₂_Im_Grid)

        # Possible distances between eigenvalues
        D = sqrt.(Λ_Re.^2 + Λ_Im.^2)
        # Sequence of sorted eigenvalues
        S = munkres(D)

        Λ[i] = Λ[i][S]
        # Insert sorted eigenvalues in matrix Λₛ
        Λₛ[i, :] = Λ[i]

    end

    Λ = Λₛ



    x = real(Λ)
    y = imag(Λ)

    # Counting of clockwise and counterclockwise encirclements of each eigenvalue locus around the critical point (-1, 0j)
    cw = []
    ccw = []
    modes = ModeInfo[]
    for i in 1:λₙ
        cwi = 0      #Number of clockwise encirclements
        ccwi = 0     #Number of counterclockwise encirclements  
        for j in 2:omegaₙ
            if (y[j-1, i] < 0 && y[j, i] > 0 && x[j, i] < -1)
                cwi += 1
            elseif (y[j-1, i] > 0 && y[j, i] < 0  && x[j-1, i] < -1)
                ccwi += 1
            end
        end
        if abs(cwi - ccwi) > 0 # Net number of encirlements for respective eigenvalue
            #println("Eigenlocus ", i, " encircles the point (-1, 0j) ", abs(cwi - ccwi), " times.")
            # Throws back the oscillation frequency of the unstable mode with zeta closest to zero (if any) for the respective eigenlocus
        
            
            push!(modes, ModeInfo(Unstable_mode(Λ[:,i], omega)..., i, Float64[]))

        end
        push!(cw, cwi)
        push!(ccw, ccwi)
    end

    
    # Nyquist stability criterion
    # N: Net number of clockwise encirclements
    # P: Number of RHP poles of loop gain (matrix)
    # Z: number of RHP poles of closed-loop system
    # N = Z - P 
    # If Z = N + P > 0, system is unstable 
    # P is equal to or greater than zero => System is unstable if N > 0

    N = sum(cw) - sum(ccw) # Compare sum of clockwise with anticlockwise encirclements to determine stability of the system.

    stability = 1
    if N > 0
        # println("Result stability assessment: Unstable system \n")
        # println("Unstable frequencies around ",round.(unstable_modes; digits=2), " Hz")
        stability = 0
    elseif N < 0
        #println("Result stability assessment: Unstable subsystem \n")
        stability = -1
    else
        #println("Result stability assessment: Stable system if subsystems are stable \n")
        stability = 1   
    end






    return (stability, modes)




end

function Unstable_mode(Λ::Vector{ComplexF64}, omega::Vector{Float64})
    # Function to determine the unstable frequencies of an eigenlocus λ(ω)
    # The function returns the unstable frequency of the mode with zeta closest to zero
    G = 1 ./ (1 .+ Λ)
    G_mag = abs.(G)
    G_ph_unwrapped = angle.(G)
    unwrap!(G_ph_unwrapped) # Unwrap the phase to avoid discontinuities around -180° and 180° affecting the derivative estimation
    
    critical_points = argmaxima(G_mag, 5)
    unstable_freqs = Float64[]
    damping_values = Float64[]

    uncertain = false
    if length(critical_points)>0
        for point in critical_points
            # Use the three-point formula to approximate the phase angle derivate
            d1 = omega[point] - omega[point-1]
            d2 = omega[point+1] - omega[point]
            c_minus = -d2 / ( d1*(d1+d2) )
            c_zero  =  (d2 - d1) / ( d1*d2 )
            c_plus  =  d1 / ( d2*(d1+d2) )
            dtheta_dw = round(c_minus*G_ph_unwrapped[point-1] + c_zero*G_ph_unwrapped[point] + c_plus*G_ph_unwrapped[point+1], digits=4) + 0.0
            
            # # Optional: check that the first order approximations also hold around the critical point
            dtheta1_dw = round((G_ph_unwrapped[point] - G_ph_unwrapped[point-1]) / (omega[point] - omega[point-1]), digits=4) + 0.0
            dtheta2_dw = round((G_ph_unwrapped[point+1] - G_ph_unwrapped[point]) / (omega[point+1] - omega[point]), digits=4) + 0.0
            if signbit(dtheta_dw) == signbit(dtheta1_dw) && signbit(dtheta1_dw) == signbit(dtheta2_dw)
            #     # Phase angle shift analysis: dθ/dωₘ ≈ -1/(ωₘζ) > 0 → ζ < 0 → unstable mode at ωₘ
                if !signbit(dtheta_dw) # If the derivative is positive the mode is unstable
                    push!(unstable_freqs, omega[point] / (2π))
                    # Approximation of damping ratio of the unstable mode based on the phase angle shift analysis
                    push!(damping_values, 1/(omega[point]*dtheta_dw) )
                end
            else
                # Show a warning if the three derivates do not match
                #println(" Uncertain phase shift analysis around ", round(omega[point]/(2π), digits=2), " Hz. Try adding more frequency points.")
                uncertain=true
            end
        end
    else
        return nothing, uncertain # No critical points found, no unstable frequencies, failed!
    end

    # Sort the unstable frequencies in the ascending order of their damping ratio (i.e. the unstable mode with zeta closest to zero is returned)
    if length(unstable_freqs) > 0
        sorted_indices = sortperm(damping_values)
        unstable_freqs = unstable_freqs[sorted_indices]
        return unstable_freqs[1], uncertain
    end
    
    return nothing, uncertain
end

# Thanks to the user lucas711642 (https://discourse.julialang.org/u/lucas711642) for the short angle unwrap function :D
function unwrap!(x, period = 2π)
	y = convert(eltype(x), period)
	v = first(x)
	@inbounds for k = eachindex(x)
		x[k] = v = v + rem(x[k] - v,  y, RoundNearest)
	end
    return
end



function EigValDec(Zcl_bus::Vector{Matrix{ComplexF64}}, omega::Vector{Float64})
    # Function to do EVD of the bus impedance matrix and return peaks in the eigenvalue spectrum
    # No PMD is performed here -this function only returns identified peaks and sorts
    # them according to their steepness Steepness <---> ζ


    f = real(omega)./(2*pi)

    # Determine eigenvalues of the closed-loop bus impedance matrix at each frequency point 
    Λ = eigvals.(Zcl_bus)
    # Determine the related eigenvectors 
    Φ = eigvecs.(Zcl_bus)

    # Number of frequency points
    omegaₙ = size(Λ, 1)
    # Number of eigenvalues for each frequency point
    λₙ = size(Λ[1], 1)
    # Zcl_bus has dimensions λₙxλₙxomegaₙ 

    # Sorting algorithm of eigenvalues to create continuous lines in EVD plot 
    # Create empty matrix for sorted eigenvalues 
    Λₛ = zeros(Complex{Float64}, omegaₙ, λₙ)
    # First row of eigenvalues remains the same 
    Λₛ[1,:] = Λ[1]

    for i in 2:omegaₙ
        # Row of eigenvalues at previous frequency point 
        Λ₁ = Λ[i-1]
        # Row of eigenvalues at current frequency point
        Λ₂ = Λ[i]

        # Algorithm: 
        # see Munkres.jl https://juliapackages.com/p/munkres
        # see eigenshuffle.m https://nl.mathworks.com/matlabcentral/fileexchange/22885-eigenshuffle
        # Sorting eigenvalues of row i to obtain minimum distance between row i and row i-1
        Λ₁_Re = real(Λ₁)
        Λ₂_Re = real(Λ₂)

        Λ₁_Re_Grid = [i for i in Λ₁_Re, j in 1:length(Λ₂_Re)]
        Λ₂_Re_Grid = [j for i in 1:length(Λ₁_Re), j in Λ₂_Re]

        Λ_Re = abs.(Λ₁_Re_Grid - Λ₂_Re_Grid)

        Λ₁_Im = imag(Λ₁)
        Λ₂_Im = imag(Λ₂)

        Λ₁_Im_Grid = [i for i in Λ₁_Im, j in 1:length(Λ₂_Im)]
        Λ₂_Im_Grid = [j for i in 1:length(Λ₁_Im), j in Λ₂_Im]

        Λ_Im = abs.(Λ₁_Im_Grid - Λ₂_Im_Grid)

        # Possible distances between eigenvalues
        D = sqrt.(Λ_Re.^2 + Λ_Im.^2)
        # Sequence of sorted eigenvalues
        S = munkres(D)

        Λ[i] = Λ[i][S]
        # Insert sorted eigenvalues in matrix Λₛ
        Λₛ[i, :] = Λ[i]
        # Eigenvectors are sorted based on same sequence 
        Φ[i] = Φ[i][:,S]

    end

    Λ = Λₛ

    # Normalizing eigenvectors
    for i in 1:omegaₙ
        for j in 1:λₙ
            N = 1/sqrt(transpose(Φ[i][:,j]) * Φ[i][:,j])
            Φ[i][:,j] = N * Φ[i][:,j]
        end
    end

    Ψ = inv.(Φ)

    abs_lambda = abs.(Λ)

    modes=ModeInfo[]
    steepness_values = Float64[]
    stability=true # Just a flag to indicate whether a peak was found
    # Each Eigenvalue is checked for a local maximum and subsequently for a peak
    for i in 1:λₙ
        # Finding local maxima
        critical_points= argmaxima(abs_lambda[:,i],5)
        println("Critical points for PMD criteria of mode ", i, ": ", f[critical_points], " Hz")
        if length(critical_points)==1
        # Check whether local maximum is a real peak
            point = critical_points[1]
            peak=abs_lambda[point,i]
            println("Peak value of mode ", i, " is ", peak, " at frequency ", f[point], " Hz")
            fmin=0.9*f[point]
            fmax=1.1*f[point]
            println("Checking for a peak with steepness around the critical point in the frequency window [", fmin, ", ", fmax, "] Hz")

            window_start = findfirst(x -> x >= fmin, f)
            if isnothing(window_start) window_start = 1 end
            
            window_end = findfirst(x -> x >= fmax, f)
            if isnothing(window_end) window_end = length(f) end

            println("Window start index: ", window_start, " at frequency ", f[window_start], " Hz")
            println("Window end index: ", window_end, " at frequency ", f[window_end], " Hz")

            # Assuming symmetrical peak around critical point
            if !isempty(findall(x->x <= 0.7*peak,abs_lambda[window_start:window_end,i]))    # Peak found with steepness confirmed
                stability = false # Set flag to indicate peak found
                #Get PFs full as well :)
                P = zeros(λₙ);
                # k (Bus) = row; i (Mode) = column
                P = abs.(Φ[point][:, i] .* Ψ[point][i, :])
                P ./= sum(P)
                push!(modes,ModeInfo(f[point], false, i, P))


                #Calculate steepness for each peak found in order to distinguish afterwards 
                index_l=findfirst(x->x >= 0.7*peak,abs_lambda[window_start:point,i]) # Left stepeness
                index_r=findfirst(x->x <= 0.7*peak,abs_lambda[point+1:window_end,i]) # Right steepness

                steepness_l = 0.0
                steepness_r = 0.0
                if !isnothing(index_l) # Safeguard against low frequency resolution
                    f_l = f[window_start - 1 + index_l]
                    if f[point] - f_l > 0
                        steepness_l = (peak - 0.7*peak) / (f[point] - f_l)
                    end
                end
                if !isnothing(index_r) # Safeguard against low frequency resolution
                    f_r = f[point + index_r]
                    if f_r - f[point] > 0
                        steepness_r = (peak - 0.7*peak) / (f_r - f[point])
                    end
                end
                println("Steepness calculation for mode ", i, ":")
                println("Steepness on the left side of the peak: ", steepness_l, " and on the right side of the peak: ", steepness_r)

                push!(steepness_values, max(steepness_l, steepness_r))

            else
                # No peak

            end
        
        elseif length(critical_points)>1 # Lambda got multiple peaks

            for point in critical_points
                #println("Critical point for PMD criteria of mode ", i, ": ", f[point], " Hz with value ", abs_lambda[point,i])
            
                # Check whether local maximum is a real peak
                peak=abs_lambda[point,i]
                println("Peak value of mode ", i, " is ", peak, " at frequency ", f[point], " Hz")
                fmin=0.9*f[point]
                fmax=1.1*f[point]
                println("Checking for a peak with steepness around the critical point in the frequency window [", fmin, ", ", fmax, "] Hz")

                window_start = findfirst(x -> x >= fmin, f)
                if isnothing(window_start) window_start = 1 end
                
                window_end = findfirst(x -> x >= fmax, f)
                if isnothing(window_end) window_end = length(f) end

                println("Window start index: ", window_start, " at frequency ", f[window_start], " Hz")
                println("Window end index: ", window_end, " at frequency ", f[window_end], " Hz")

                # Assuming symmetrical peak around critical point
                if !isempty(findall(x->x <= 0.7*peak,abs_lambda[window_start:window_end,i]))    # Peak found with steepness confirmed
                    stability = false
                    #Get PFs full as well :) Dishwasher
                    P = zeros(λₙ);
                    # k (Bus) = row; i (Mode) = column
                    P = abs.(Φ[point][:, i] .* Ψ[point][i, :])
                    P ./= sum(P)
                        push!(modes,ModeInfo(f[point], false, i, P))


                    #Calculate steepness for each peak found in order to distinguish afterwards 
                    index_l=findfirst(x->x >= 0.7*peak,abs_lambda[window_start:point,i])
                    index_r=findfirst(x->x <= 0.7*peak,abs_lambda[point+1:window_end,i])

                    steepness_l = 0.0
                    steepness_r = 0.0
                    if !isnothing(index_l) 
                        f_l = f[window_start - 1 + index_l]
                        if f[point] - f_l > 0
                            steepness_l = (peak - 0.7*peak) / (f[point] - f_l)
                        end
                    end
                    if !isnothing(index_r) 
                        f_r = f[point + index_r]
                        if f_r - f[point] > 0
                            steepness_r = (peak - 0.7*peak) / (f_r - f[point])
                        end
                    end

                    push!(steepness_values, max(steepness_l, steepness_r))

                else # No peak found :)


                end
            end

        
        else # No maxs found 

        end
    end
    
    # Sort modes according to steepness values
    if length(modes) > 0
        sorted_indices = sortperm(steepness_values, rev=true)
        modes = modes[sorted_indices]
    end


    return (stability, modes)


end
    
function calc_RLC(P,Q,V,component)
# Function to calculate resistance, inductance or capacitance of a 3-phase series load for a given 1-phase active "P" and reactive power "Q" [MVA]
# and phase-rms Voltage V [kV]
# Discremination of component by string component "R", "L", "C"
        
        P=P*1e6
        Q=Q*1e6
        V=V*1e3

        S=sqrt(P^2+Q^2) # 1-phase apparent power
        S=S*3 # Get 3-phase power

        # Calculate phase current rms: I

        I=S/(sqrt(3)*V)

        if component == "R"

        R = P/(I^2)
        
        
        return R

        elseif component =="L"

        
        L= Q/(I^2*2*pi*50)
        return L

        elseif component == "C"

        C=(I^2)/(Q*2*pi*50)
        return C
        else
        error("No implemented load component specified!")
        end

end
function IEEE14bus_powerflow!(grid::Network, P_WF :: Float64, Q_MMC1 :: Float64, Q_MMC2:: Float64, Q_MMC3 :: Float64)
# Q, P_WF in SI [MVA]

        
        # MMC1
        grid.elements[Symbol("MMC1")].element_value.Q = Q_MMC1   # MVA
        grid.elements[Symbol("MMC1")].element_value.P = -P_WF*(3/2)   # MVA Split the WF power over the two HVDC links
        grid.elements[Symbol("MMC1")].element_value.Vₘ = 380/sqrt(3) # kV - phase
        # MMC2
        grid.elements[Symbol("MMC2")].element_value.Q = Q_MMC2   # MVA
        grid.elements[Symbol("MMC2")].element_value.P = -P_WF*(3/2)    # MVA Split the WF power over the two HVDC links
        grid.elements[Symbol("MMC2")].element_value.Vₘ = 380/sqrt(3) # kV - phase
        # MMC3
        grid.elements[Symbol("MMC3")].element_value.Q = Q_MMC3   # MVA
        grid.elements[Symbol("MMC3")].element_value.Vₘ = 380/sqrt(3) # kV - phase
        # MMC4
        grid.elements[Symbol("MMC4")].element_value.Q = Q_MMC3   # MVA
        grid.elements[Symbol("MMC4")].element_value.Vₘ = 380/sqrt(3) # kV - phase


        
        # Wind farms 
        grid.elements[Symbol("WF1")].element_value.Q = 0   # MVA
        grid.elements[Symbol("WF2")].element_value.Q = 0   # MVA
        grid.elements[Symbol("WF3")].element_value.Q = 0   # MVA
        grid.elements[Symbol("WF1")].element_value.P = P_WF   # MVA
        grid.elements[Symbol("WF2")].element_value.P = P_WF   # MVA
        grid.elements[Symbol("WF3")].element_value.P = P_WF   # MVA

        # Help with convergence by setting P_dc to the expected value for the wind farms....speed needs to be checked
        grid.elements[Symbol("WF1")].element_value.P_dc=P_WF  
        grid.elements[Symbol("WF2")].element_value.P_dc=P_WF  
        grid.elements[Symbol("WF3")].element_value.P_dc=P_WF  
        # Reset Vm
        grid.elements[Symbol("WF1")].element_value.Vₘ = 380/sqrt(3) # kV - phase
        grid.elements[Symbol("WF2")].element_value.Vₘ = 380/sqrt(3) # kV - phase
        grid.elements[Symbol("WF3")].element_value.Vₘ = 380/sqrt(3) # kV - phase


        result, _, nodes2bus, elem2comp = PowerImpedanceACDC.power_flow(grid) # run power flow routine, which also obtains the linearized state-space of the STATCOM

end

# Operating points
P_MMC1= -1000
Q_MMC1= -400
P_MMC2=-1000
Q_MMC2=-400
Q_MMC3=400
Q_MMC4=400
Pwf=600
Qwf=0

# Get load parameters :)
R_B3=calc_RLC(314/7,63.333/7,380,"R")
L_B3=calc_RLC(314/7,63.333/7,380,"L")

R_B4=calc_RLC(159.333/4,13/3,380,"R")
C_B4=calc_RLC(159.333/4,13/3,380,"C")

R_B5=calc_RLC(20.0,5.333,380,"R")
L_B5=calc_RLC(20.0,5.333,380,"L")

R_B6=calc_RLC(37.333,25.0,380,"R")
L_B6=calc_RLC(37.333,25.0,380,"L")

R_B10=calc_RLC(30.0/3,19.3333/3,380,"R")
L_B10=calc_RLC(30.0/3,19.3333/3,380,"L")

R_B11=calc_RLC(11.6667,6.0,380,"R")
L_B11=calc_RLC(11.6667,6.0,380,"L")


Vm=380/sqrt(3)


IEEE14bus = @network begin

voltageBase = Vm

# Sources
G1=ac_source(pins = 3, V = Vm, transformation = true)
G2=ac_source(pins = 3, V = Vm, transformation = true)
DC_WF1=dc_source(pins = 2, V = 320, transformation = true)
DC_WF2=dc_source(pins = 2, V = 320, transformation = true)
DC_WF3=dc_source(pins = 2, V = 320, transformation = true)
Zg2=impedance(z = (s::Complex)-> (0.7184*(14/25) + s*0.02289*(14/25)), pins = 3, transformation = true) # Top area
Zg1=impedance(z = (s::Complex)-> (0.2874  + s*0.0091)  , pins = 3, transformation = true) # Bottom area


#Converters


 MMC1=blackbox_MMC(Vᵈᶜ = 640, vDCbase = 640, vACbase=380,
                P = -1000, Q = 300,Vₘ = Vm,Rₘₑ=0.47,
                p=PI_control(), # Empty controller necessary for the powerflow function to detect operting mode of the MMC :)
                q=PI_control(), P_max=1000,P_min=-1000,Q_max=1000,Q_min=-1000,
                path_f = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\11_06_2026_run1_f.txt",
                path_MMC = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\11_06_2026_run1_merged.txt") 


MMC2=blackbox_MMC(Vᵈᶜ = 640, vDCbase = 640, vACbase=380,
                P = -1000, Q = 300,Vₘ = Vm,Rₘₑ=0.47,
                p=PI_control(), # Empty controller necessary for the powerflow function to detect operting mode of the MMC :)
                q=PI_control(), P_max=1000,P_min=-1000,Q_max=1000,Q_min=-1000,
                path_f = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\11_06_2026_run1_f.txt",
                #path_MMC = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\11_06_2026_run2_merged.txt") 
                path_MMC = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\07_07_2026_run1_merged.txt")
                # Slow VI tuning :)
MMC3=blackbox_MMC(Vᵈᶜ = 640, vDCbase = 640, vACbase=380,
                P = 0, Q = 300,Vₘ = Vm,Rₘₑ=1.33,
                dc=PI_control(), # Empty controller necessary for the powerflow function to detect operting mode of the MMC :)
                q=PI_control(),  P_max=1000,P_min=-1000,Q_max=1000,Q_min=-1000,
                path_f = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\11_06_2026_run1_f.txt",
                path_MMC = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\11_06_2026_run3_merged.txt")  


MMC4=blackbox_MMC(Vᵈᶜ = 640, vDCbase = 640, vACbase=380,
                P = 0, Q = 300,Vₘ = Vm,Rₘₑ=1.33,
                dc=PI_control(), # Empty controller necessary for the powerflow function to detect operting mode of the MMC :)
                q=PI_control(),  P_max=1000,P_min=-1000,Q_max=1000,Q_min=-1000,
                path_f = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\11_06_2026_run1_f.txt",
                path_MMC = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Data\\Raw\\11_06_2026_run4_merged.txt"
        )   

# Delays deactivated for the wind farms!
WF1= tlc(Vᵈᶜ = 640, Vₘ = Vm, Lᵣ =0.08*(380^2/600)/2/pi/50, Rᵣ = 0.0008*(380^2/600), 
        Sbase = 600, vACbase_LL_RMS = 380, 
        P = Pwf, Q = Qwf,P_max=600,P_min=-600,Q_max=600,Q_min=-600,
        occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8), 
        pll = PI_control(Kₚ = 0.3978, Kᵢ = 7.9577, ω_f = 2*pi*50,n_f=1), # 50 Hz also in PSCAD?
        #pll = PI_control(Kₚ = 3, Kᵢ = 38.5155, ω_f = 2*pi*50,n_f=1), # Fast PLL tuning
        v_meas_filt = PI_control(ω_f = 1e4,n_f=1), 
        i_meas_filt = PI_control(ω_f = 1e4,n_f=1),
        #vac_supp = PI_control(ω_f = 1/0.5, Kₚ =10),
        #f_supp = PI_control(ω_f = 1/0.5, Kₚ =10),
        p = PI_control(Kₚ = 0.01, Kᵢ = 10), 
        q = PI_control(Kₚ = 0.01, Kᵢ = 10), #timeDelay=200e-6, padeOrderDen=5, padeOrderNum=5
        )

WF2= tlc(Vᵈᶜ = 640, Vₘ = Vm, Lᵣ =0.08*(380^2/600)/2/pi/50, Rᵣ = 0.0008*(380^2/600), 
        Sbase = 600, vACbase_LL_RMS = 380, 
        P = Pwf, Q = Qwf,P_max=600,P_min=-600,Q_max=600,Q_min=-600,
        occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8),
        pll = PI_control(Kₚ = 0.3978, Kᵢ = 7.9577, ω_f = 2*pi*80,n_f=1),
        v_meas_filt = PI_control(ω_f = 1e4,n_f=1),
        i_meas_filt = PI_control(ω_f = 1e4,n_f=1), 
        #vac_supp = PI_control(ω_f = 1/0.5, Kₚ =10),
        #f_supp = PI_control(ω_f = 1/0.5, Kₚ =10),
        p = PI_control(Kₚ = 0.01, Kᵢ = 10), 
        q = PI_control(Kₚ = 0.01, Kᵢ = 10), #timeDelay=200e-6, padeOrderDen=5, padeOrderNum=5
        )

WF3= tlc(Vᵈᶜ = 640, Vₘ = Vm, Lᵣ =0.08*(380^2/600)/2/pi/50, Rᵣ = 0.0008*(380^2/600), 
        Sbase = 600, vACbase_LL_RMS = 380, 
        P = Pwf, Q = Qwf,P_max=600,P_min=-600,Q_max=600,Q_min=-600,
        occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8), 
        pll = PI_control(Kₚ = 0.3978, Kᵢ = 7.9577, ω_f = 2*pi*80,n_f=1),
        v_meas_filt = PI_control(ω_f = 1e4,n_f=1), 
        i_meas_filt = PI_control(ω_f = 1e4,n_f=1),
        #vac_supp = PI_control(ω_f = 1/0.5, Kₚ =10),
        #f_supp = PI_control(ω_f = 1/0.5, Kₚ =10),
        p = PI_control(Kₚ = 0.01, Kᵢ = 10), 
        q = PI_control(Kₚ = 0.01, Kᵢ = 10), #timeDelay=200e-6, padeOrderDen=5, padeOrderNum=5
        )



# Overhead lines

# Bottom area ⬇
T1_2 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T1_5 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
# Create HFO instability with trip of T2_5
T2_5 = overhead_line(length = 30e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T4_5 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T2_4 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)


T2_3 = overhead_line(length = 10e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T3_4 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

# Top area⬆
T12_13 = overhead_line(length = 40e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_12 = overhead_line(length = 50e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_13 = overhead_line(length = 10e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_11 = overhead_line(length = 10e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)


T10_11 = overhead_line(length = 10e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T13_14 = overhead_line(length = 15e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T9_14 = overhead_line(length = 10e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T9_10 = overhead_line(length = 5e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
T7_9 = overhead_line(length = 10e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

# Cables
# ABB Datasheet cables with no armouring to represent onshore cables 
CableDC23 = cable(length = 200e3, positions = [(0,1.5), (1,1.5)],
    C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
    I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
    C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
    I2 = Insulator(rᵢ = 55.4e-3, rₒ = 6.12e-3, ϵᵣ = 2.3), transformation = true)  

CableDC23_1 = cable(length = 200e3, positions = [(0,1.5), (1,1.5)],
    C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
    I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
    C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
    I2 = Insulator(rᵢ = 55.4e-3, rₒ = 6.12e-3, ϵᵣ = 2.3), transformation = true)     

# Loads
# Modeled as shunt branches with resistance and inductance/capacitance


# LoadB3

LoadB3= impedance(z =(s::Complex)->  (R_B3+s*L_B3), pins = 3, transformation = true)


# LoadB4

LoadB4= impedance(z = (s::Complex)-> (R_B4+(1/(s*C_B4))), pins = 3, transformation = true)


# LoadB5

LoadB5= impedance(z = (s::Complex)-> (R_B5+s*L_B5), pins = 3, transformation = true)

# LoadB6

LoadB6= impedance(z = (s::Complex)-> (R_B6+s*L_B6), pins = 3, transformation = true)


# LoadB10

LoadB10= impedance(z = (s::Complex)-> (R_B10+s*L_B10), pins = 3, transformation = true)


# LoadB11

LoadB11= impedance(z = (s::Complex)-> (R_B11+s*L_B11), pins = 3, transformation = true)


# Connections

# Load grounding

LoadB3[2.1] ⟷ gndD
LoadB3[2.2] ⟷ gndQ

LoadB4[2.1] ⟷ gndD
LoadB4[2.2] ⟷ gndQ

LoadB5[2.1] ⟷ gndD
LoadB5[2.2] ⟷ gndQ

LoadB6[2.1] ⟷ gndD
LoadB6[2.2] ⟷ gndQ

LoadB10[2.1] ⟷ gndD
LoadB10[2.2] ⟷ gndQ

LoadB11[2.1] ⟷ gndD
LoadB11[2.2] ⟷ gndQ


#Sources grounding
G1[2.1] ⟷ gndD
G1[2.2] ⟷ gndQ

G2[2.1] ⟷ gndD
G2[2.2] ⟷ gndQ
DC_WF1[2.1] ⟷ gndDC
DC_WF2[2.1] ⟷ gndDC
DC_WF3[2.1] ⟷ gndDC

# Bottom area

Zg1[1.1] ⟷ G1[1.1] 
Zg1[1.2] ⟷ G1[1.2] 

Zg1[2.1] ⟷ T1_2[1.1] ⟷ T1_5[1.1] ⟷ Bus1d
Zg1[2.2] ⟷ T1_2[1.2] ⟷ T1_5[1.2] ⟷ Bus1q

T2_3[1.1] ⟷ T2_4[1.1]  ⟷ T1_2[2.1]  ⟷ T2_5[1.1] ⟷ Bus2d#  #
T2_3[1.2] ⟷ T2_4[1.2]  ⟷ T1_2[2.2]  ⟷ T2_5[1.2] ⟷Bus2q# #

T2_3[2.1] ⟷ T3_4[1.1] ⟷  LoadB3[1.1] ⟷ Bus3d 
T2_3[2.2] ⟷ T3_4[1.2] ⟷  LoadB3[1.2] ⟷ Bus3q 

T4_5[1.1] ⟷ T2_4[2.1] ⟷ T3_4[2.1] ⟷  MMC4[2.1] ⟷ LoadB4[1.1] ⟷ Bus4d 
T4_5[1.2] ⟷ T2_4[2.2] ⟷ T3_4[2.2] ⟷  MMC4[2.2] ⟷ LoadB4[1.2] ⟷ Bus4q  

T4_5[2.1] ⟷ T1_5[2.1] ⟷ MMC3[2.1] ⟷  LoadB5[1.1] ⟷ T2_5[2.1] ⟷Bus5d ##
T4_5[2.2] ⟷ T1_5[2.2] ⟷ MMC3[2.2] ⟷ LoadB5[1.2] ⟷ T2_5[2.2] ⟷Bus5q#  #

# HVDC links

CableDC23[1.1] ⟷ MMC1[1.1] ⟷ BusDC1
CableDC23_1[1.1] ⟷ MMC2[1.1] ⟷ BusDC2
CableDC23[2.1] ⟷ MMC3[1.1] ⟷ BusDC3
CableDC23_1[2.1] ⟷ MMC4[1.1] ⟷ BusDC4

# DC side TLC

WF1[1.1] ⟷ DC_WF1[1.1]
WF2[1.1] ⟷ DC_WF2[1.1]
WF3[1.1] ⟷ DC_WF3[1.1]

# Top area

Zg2[1.1] ⟷ G2[1.1] 
Zg2[1.2] ⟷ G2[1.2]

Zg2[2.1] ⟷ MMC1[2.1] ⟷ T6_12[1.1] ⟷ T6_13[1.1] ⟷ T6_11[1.1] ⟷ LoadB6[1.1] ⟷Bus6d 
Zg2[2.2] ⟷ MMC1[2.2] ⟷ T6_12[1.2] ⟷ T6_13[1.2] ⟷ T6_11[1.2] ⟷ LoadB6[1.2] ⟷Bus6q

T6_12[2.1] ⟷ T12_13[1.1] ⟷ WF1[2.1] ⟷ Bus12d
T6_12[2.2] ⟷ T12_13[1.2] ⟷ WF1[2.2] ⟷ Bus12q

T12_13[2.1] ⟷ T6_13[2.1] ⟷ T13_14[1.1] ⟷ WF2[2.1] ⟷ Bus13d
T12_13[2.2] ⟷ T6_13[2.2] ⟷ T13_14[1.2] ⟷ WF2[2.2] ⟷ Bus13q

T9_14[1.1] ⟷ T13_14[2.1]  ⟷ WF3[2.1] ⟷ Bus14d
T9_14[1.2] ⟷ T13_14[2.2]  ⟷ WF3[2.2] ⟷ Bus14q

T9_14[2.1] ⟷ T7_9[1.1]  ⟷ T9_10[1.1]  ⟷ Bus9d
T9_14[2.2] ⟷ T7_9[1.2]  ⟷ T9_10[1.2]  ⟷ Bus9q
# T7_8 Floating no Bus 8!
MMC2[2.1] ⟷ T7_9[2.1]  ⟷ Bus7d
MMC2[2.2] ⟷ T7_9[2.2]  ⟷ Bus7q

T10_11[1.1] ⟷ T9_10[2.1] ⟷ LoadB10[1.1] ⟷ Bus10d
T10_11[1.2] ⟷ T9_10[2.2] ⟷ LoadB10[1.2] ⟷ Bus10q

T10_11[2.1] ⟷ T6_11[2.1]  ⟷ LoadB11[1.1] ⟷ Bus11d
T10_11[2.2] ⟷ T6_11[2.2]  ⟷ LoadB11[1.2] ⟷ Bus11q

end

line_status = Dict(
    :Base_case => true, # All lines connected
    :T1_2 => true,
    :T1_5 => true,
    :T2_5 => true,
    :T4_5 => true,
    :T2_4 => true,
    :T2_3 => true,
    :T3_4 => true,
    :T12_13 => true,
    :T6_12 => true,
    :T6_13 => true,
    :T6_11 => true,
    :T10_11 => true,
    :T13_14 => true,
    :T9_14 => true,
    :T9_10 => true,

)


# Case study options
min_f=1e0 # Minimum frequency in Hz
max_f=2e3 # Maximum frequency in Hz 
n_f=300 # Number of frequency points in the sweep
omegas= 2*pi* 10 .^range(log10(min_f), log10(max_f), length= n_f) 
P_WF = range(0, 1.0, length=7) # Correlated with P_WF2, P_WF3, P_MMC1 and P_MMC2
Q_MMC1 = range(-0.4, 0.4, step=0.2)  #Correlated with Q_MMC2
Q_MMC2 = range(-0.4, 0.4, step=0.2)  
Q_MMC3 = range(-0.4, 0.4, step=0.2)

# Data storage for the case study results
#Powerflows=Array{PowerFlowResult}(undef, length(line_status), length(P_WF),length(Q_MMC1),length(Q_MMC2),length(Q_MMC3)) # Q-V-powerflow results
GNCs= Array{GNCInfo}(undef, length(line_status), length(P_WF),length(Q_MMC1),length(Q_MMC2),length(Q_MMC3))
Yedges= fill(zeros(ComplexF64, 0, 0), length(line_status), n_f)
Ynodes= fill(zeros(ComplexF64, 0, 0), length(line_status),length(P_WF),length(Q_MMC1),length(Q_MMC2),length(Q_MMC3), n_f)
# Get node list once, since nodes don't change with topology 
_,node_list_IEEE14Bus, _ = make_y_node(IEEE14bus, freq_range=(min_f, max_f, n_f))
# Define element list of the Ynode once as the elements dont change within the loop 💅🏼
element_list_IEEE14Bus = [:WF1,:WF2,:WF3,:MMC1,:MMC2,:MMC3,:MMC4,:Zg1,:Zg2]
@time begin
# Iterate over topology cases by mutating `line_status` in place. `:T7_9`
# is always kept connected; for each other case, the current line is
# temporarily disconnected, the net is built and evaluated, and the line is restored afterward.

for line in keys(line_status)

    if line == :Base_case
        #Nothing
    else
        nets=IEEE14bus.elements[line].pins # Save the net to restore connection later
        elem=IEEE14bus.elements[line] # Save the element to restore connection later
        PowerImpedanceACDC.delete!(IEEE14bus,line) # Delete the line 
    end
    index=findfirst(==(line),collect(keys(line_status)))

    Yedges[index,:],_,_=make_y_edge(IEEE14bus,nodelist=node_list_IEEE14Bus,freq_range = (min_f,max_f, n_f))
    # Run studies
    for (i, P) in enumerate(P_WF)

        for (j, Q1) in enumerate(Q_MMC1)

            for (k, Q2) in enumerate(Q_MMC2)
                
                for (l, Q3) in enumerate(Q_MMC3)
                #println("Now case: Line $(line), P=$(P*600) MW, Q1=$(Q1*1000) MVar, Q2=$(Q2*1000) MVar, Q3=$(Q3*1000) MVar")
                _=IEEE14bus_powerflow!(IEEE14bus, P*600, Q1*1000, Q2*1000, Q3*1000)
                #Powerflows[index, i, j, k, l] = PowerFlowResult(dummy[1], dummy[2], dummy[3], dummy[4], dummy[5], dummy[6])
                Ynodes[index,i,j,k,l,:],_,_=make_y_node(IEEE14bus,
                                                        nodelist=node_list_IEEE14Bus,
                                                        elementlist=element_list_IEEE14Bus,
                                                        freq_range = (min_f,max_f, n_f))
                
                end
            end
            
        end
    end
    if line == :Base_case
        #Nothing
    else
        # Restore the line connection
        add!(IEEE14bus, line, elem)
        for (k,values) in nets
            connect!(IEEE14bus, (line,k), values)
        end
    end


end


###########################################################################Stability analysis################################################################################################################################
for line in keys(line_status)
    index=findfirst(==(line),collect(keys(line_status)))
    for (i, P) in enumerate(P_WF)
        for (j, Q1) in enumerate(Q_MMC1)
            for (k, Q2) in enumerate(Q_MMC2)
                for (l, Q3) in enumerate(Q_MMC3)
                    loop=inv.(Yedges[index,:]).*Ynodes[index,i,j,k,l,:]
                    #println("Index = $(index), $(i),$(j),$(k),$(l)")
                    stability,modes= Nyquist(loop, omegas)
                    GNCs[index,i,j,k,l] = GNCInfo(stability,modes)
                end
            end
        end
    end
end


#############################################################################High res analysis where the phase angle fails##############################################################################################

#All cases that are unstable and have modes with uncertainty in the angle derivative
uncertain_cases=  findall(gnc -> (gnc.stability != 1) && !isempty(gnc.modes) && (gnc.modes[1].uncertainty == true), GNCs)


if !isempty(uncertain_cases)
    # println("Number of uncertain cases: ", length(uncertain_cases))
    # println("Doing high resolution analysis for these cases to get sound angle derivative estimation")
    
    # These cases we will run again :) with higher frequency resolution to get a matching angle derivative estimation :)
    # Case study options
    min_f=1e0 # Minimum frequency in Hz
    max_f=2e3 # Maximum frequency in Hz 
    ratio_f=3 # Ratio of frequency points between low res and high res, to get a more sound angle derivative estimation
    high_res_n_f= 1000#ratio_f*n_f # Number of frequency points in the sweep
    omegas_high_res= 2*pi* 10 .^range(log10(min_f), log10(max_f), length= high_res_n_f) 


    # Initializing with nothing here since we wont fill all the entries, but keeping the original structure alive 
    Yedges_high_res= fill(zeros(ComplexF64, 0, 0), length(uncertain_cases), high_res_n_f)
    Ynodes_high_res= fill(zeros(ComplexF64, 0, 0), length(uncertain_cases), high_res_n_f)
    #results=(; line_status=..., P_WF=..., Q_MMC1=..., Q_MMC2=..., Q_MMC3=..., num_samples=..., Ynodes=Ynodes_high_res)
    # Iterate ove the uncertain cases with higher frequency resolution to achieve sound angle derivative estimation :)
    for (i, index) in enumerate(uncertain_cases)

        # Run studies
        #println(index)

        line = collect(keys(line_status))[index[1]]

        if line == :Base_case
            #Nothing
        else
            nets=IEEE14bus.elements[line].pins # Save the net to restore connection later
            elem=IEEE14bus.elements[line] # Save the element to restore connection later
            PowerImpedanceACDC.delete!(IEEE14bus,line) # Delete the line 
        end

        if i ==1 # First time we need to fill anyways
            Yedges_high_res[i,:],_,_=make_y_edge(IEEE14bus,nodelist=node_list_IEEE14Bus,freq_range = (min_f,max_f, high_res_n_f))
           
        else # Not the first time we might can reuse Yedge because already calculated 
           # Check whether Yedge has been calculated already 

            idx=findfirst(c-> c[1] == index[1] , uncertain_cases)

            if idx == i # Not calculated yet
            
            Yedges_high_res[i,:],_,_=make_y_edge(IEEE14bus,nodelist=node_list_IEEE14Bus,freq_range = (min_f,max_f, high_res_n_f))
            
            elseif idx < i # Already calculated, fill in the Yedge from the previous calculation
                Yedges_high_res[i,:] = Yedges_high_res[idx,:]

            else
                error("This should not happen, since we are iterating in order, but the index of the already calculated Yedge is higher than the current index. This means there is a logical error in the code.")
            end

        end

        _=IEEE14bus_powerflow!(IEEE14bus, P_WF[index[2]]*600, Q_MMC1[index[3]]*1000, Q_MMC2[index[4]]*1000, Q_MMC3[index[5]]*1000)
        Ynodes_high_res[i,:],_,_=make_y_node(IEEE14bus,nodelist=node_list_IEEE14Bus,
                                                elementlist=element_list_IEEE14Bus,
                                                freq_range = (min_f,max_f, high_res_n_f))

        if line == :Base_case
            #Nothing
        else
            # Restore the line connection
            add!(IEEE14bus, line, elem)
            for (k,values) in nets
                connect!(IEEE14bus, (line,k), values)
            end
        end


    end

    for (i, index) in enumerate(uncertain_cases)
        loop=inv.(Yedges_high_res[i,:]).*Ynodes_high_res[i,:]
        stability,modes= Nyquist(loop, omegas_high_res)
        GNCs[index[1],index[2],index[3],index[4],index[5]] = GNCInfo(stability,modes) # Replace the GNCInfo with the new stability result and modes from the high res analysis
    end

else
    
end

end
