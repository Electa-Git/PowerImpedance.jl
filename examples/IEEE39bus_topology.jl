# This is a PowerImpedanceimplementation of the IEEE 39 bus system test system

using PowerImpedanceACDC
using Plots;
using DelimitedFiles
using LinearAlgebra
using Munkres
using MAT
using JLD2
using LaTeXStrings
# Include Amauris function to do eps exports with inkscape
include("C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Scripts\\Julia\\export_eps.jl")
# Path to the inscape executable 
inkscape="c:\\Users\\jkirchei\\Desktop\\inkscape\\inkscape\\bin\\inkscape.exe"
# Path to store the resulting eps
storage_path_fig="C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Data\\Processed"
# Storage path for data
storage_path_data="C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Data\\Raw"

@time begin
struct ModeInfo
# A container to hold the mode information   

# For each mode of lambda get real part and oscillation frequency

        Reλ₁:: Vector{Float64} # All real parts of all oscillatory modes for lambda1
        Reλ₂:: Vector{Float64} # All real parts of all oscillatory modes for lambda2
        fλ₁:: Vector{Float64} # All oscillation frequencies for lambda1
        fλ₂:: Vector{Float64} # All oscillation frequencies for lambda2


end

struct GNCInfo
# Container to hold the information extracted from GNC

        stability:: Int64 # Stability assessment with GNC: 1 = stable, 0 = unstable, -1 = unstable subsystem
        GM1:: Vector{Float64} # Gain margins of lambda 1
        f_GM1:: Vector{Float64} # Frequencies at which gain margins of lambda 1 are obtained
        PM1:: Vector{Float64} # Phase margins of lambda 1
        f_PM1:: Vector{Float64} # Frequencies at which phase margins of lambda 1 are obtained
        VM1:: Vector{Float64} # Vector margins of lambda 1
        f_VM1:: Vector{Float64} # Frequencies at which vector margins of lambda 1 are obtained
        GM2:: Vector{Float64} # Gain margins of lambda 2
        f_GM2:: Vector{Float64} # Frequencies at which gain margins of lambda 2  are obtained
        PM2:: Vector{Float64} # Phase margins of lambda 2
        f_PM2:: Vector{Float64} # Frequencies at which phase margins of lambda 2 are obtained
        VM2:: Vector{Float64} # Vector margins of lambda 2
        f_VM2:: Vector{Float64} # Frequencies at which vector margins of lambda 2 are obtained
        


end

struct PowerFlowResult
        Vm:: Float64 
        Va:: Float64
        P:: Float64
        Q:: Float64
        Vdc:: Float64
        Pdc :: Float64
        Q_fixed :: Bool # True if Q is fixed, False if Vac-droop control is active
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


#TODO:
# Get load parameters :)
# Load Bus 3
R_B3=calc_RLC(107.3333,0.8,345,"R")
L_B3=calc_RLC(107.3333,0.8,345,"L")

# Loads Bus 4
R_B4a=calc_RLC(166.6667,61.3333,345,"R")
L_B4=calc_RLC(166.6667,61.3333,345,"L")
R_B4b=calc_RLC(0,100,345,"R")
C_B4=calc_RLC(0,100,345,"C")

# Load Bus 5
R_B5=calc_RLC(0,200,345,"R")
C_B5=calc_RLC(0,200,345,"C")

# Load Bus 7
R_B7=calc_RLC(77.93333,28.0,345,"R")
L_B7=calc_RLC(77.93333,28.0,345,"L")

#Load Bus 8
R_B8=calc_RLC(174.0,58.6667,345,"R")
L_B8=calc_RLC(174.0,58.6667,345,"L")

# Load Bus 12
R_B12=calc_RLC(2.5,29.3333,230,"R")
L_B12=calc_RLC(2.5,29.3333,230,"L")

# Load Bus 15
R_B15=calc_RLC(106.6667,51.0,345,"R")
L_B15=calc_RLC(106.6667,51.0,345,"L")

# Load Bus 16
R_B16=calc_RLC(109.8,10.7667,345,"R")
L_B16=calc_RLC(109.8,10.7667,345,"L")

# Load Bus 18
R_B18=calc_RLC(52.6667,10.0,345,"R")
L_B18=calc_RLC(52.6667,10.0,345,"L")

# Load Bus 20
R_B20=calc_RLC(226.6667,34.3333,345,"R")
L_B20=calc_RLC(226.6667,34.3333,345,"L")

# Load Bus 21
R_B21=calc_RLC(91.3333,38.3333,345,"R")
L_B21=calc_RLC(91.3333,38.3333,345,"L")

# Load Bus 23
R_B23=calc_RLC(82.5,28.2,345,"R")
L_B23=calc_RLC(82.5,28.2,345,"L")

# Load Bus 24
R_B24=calc_RLC(102.8667,30.73333,345,"R")
C_B24=calc_RLC(102.8667,30.73333,345,"C")

# Load Bus 25
R_B25=calc_RLC(74.6667,15.7333,345,"R")
L_B25=calc_RLC(74.6667,15.7333,345,"L")

# Load Bus 26
R_B26=calc_RLC(46.3333,5.6667,345,"R")
L_B26=calc_RLC(46.3333,5.6667,345,"L")

# Load Bus 27
R_B27=calc_RLC(93.6667,25.1667,345,"R")
L_B27=calc_RLC(93.6667,25.1667,345,"L")

# Load Bus 28
R_B28=calc_RLC(68.6667,9.2,345,"R")
L_B28=calc_RLC(68.6667,9.2,345,"L")

# Load Bus 29
R_B29=calc_RLC(94.5,8.9667,345,"R")
L_B29=calc_RLC(94.5,8.9667,345,"L")

# Load Bus 31
R_B31=calc_RLC(3.0667,1.5333,22,"R")
L_B31=calc_RLC(3.0667,1.5333,22,"L")

# Load Bus 39
R_B39=calc_RLC(368,83.3333,345,"R")
L_B39=calc_RLC(368,83.3333,345,"L")

function EVD_PND(Zcl_bus:: Vector{Matrix{Complex{Float64}}}, omega :: Vector{Float64}, fmin :: Float64, fmax :: Float64)
# Optimized EVD function to calculate the unstable oscillation frequencies fast with PND
# Returns the idenitified oscillation frequencies with the PND criterion, and their corresponding real parts
    f = real(omega)./(2*pi)
    # Determine eigenvalues of the closed-loop bus impedance matrix at each frequency point 
    Λ = eigvals.(Zcl_bus)
    # Number of frequency points
    omegaₙ = size(Λ, 1)
    # Number of eigenvalues for each frequency point
    λₙ = size(Λ[1], 1)


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

    end

    Λ = Λₛ


    # Determining x-axis limits 
    index_fmin = findmin(abs.(f .- fmin))[2]
    index_fmax = findmin(abs.(f .- fmax))[2]

    PND_modes = Vector{Vector{Float64}}(undef,λₙ) # Vector with all (stable and unstable) oscillatory modes for each eigenvalue of the closed-loop impedance matrix
    PND_unstable = false # Initialize variable
    PND_reals = Vector{Vector{Float64}}(undef,λₙ) # Vector with the real parts of all (stable and unstable) oscillatory modes for each eigenvalue
    real_lambda = real.(Λ) # also the real and imaginary parts
    imag_lambda = imag.(Λ)




    # (2) For each eigenvalue the PND criterion is applied
    min_real_lambda = zeros(λₙ, 2) # First column is the minimum real part of each lambda at the osc freqs, and second the index
    for i in 1:λₙ
        # Find the zero crossing of the imaginary part (oscillatory modes)
        sign_changes = diff(signbit.(imag_lambda[index_fmin:index_fmax,i])) .!= 0
        critical_points_PND = findall(sign_changes) # Indices where lambda exhibits a zero crossing of the imaginary part --> oscillatory mode 
        if length(critical_points_PND)>0 # Lambda has oscillatory modes, apply PND criterion to determine if they are unstable or not
            modes = []
            real_parts = [] # Holds the real parts of oscillatory modes
            idx_reals = []
            # println("Zero-crossings of the imaginary part of eigenvalue ",i)
            for point in critical_points_PND # Point= index where zero crossing occurs
                if abs(f[index_fmin+point]-50.0) > 0.5
                    # Around the synchronous frequency, the stability assessment might be blurred by the frame transformation effects so skip it
                    # println(" Crossing at ",f[index_fmin+point]," Hz")
                    
                    # PND criteria
                    if real_lambda[index_fmin+point, i]>0
                        # Stable: if the closed-loop has positive damping at the resonance points (imag = 0)
                        # More conservative than the PMD criteria
                    else
                        # Unstable with an oscillatory mode at this frequency
                        PND_unstable = true
                    end
                    push!(modes,f[index_fmin+point]) # Add the oscillation frequency to the list of modes for this lambda
                    push!(real_parts,real_lambda[index_fmin+point, i]) # Add the real part for this mode to the list of real parts for this lambda
                    push!(idx_reals,index_fmin+point)
                end
            end
            PND_modes[i] = modes # Add all (stable and unstable) oscillation frequencies 
            PND_reals[i] = real_parts # Add the real parts of all (stable and unstable) oscillation modes for this lambda
        else
            PND_modes[i] = []
            PND_reals[i] = []

        end
    end

    return PND_modes, PND_reals




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

    # Counting of clockwise and counterclockwise encirclements and estimate the unstable frequencies
    cw = []
    ccw = []


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

    N = sum(cw) - sum(ccw) 

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

    ##### ----- STABILITY MARGINS ----- #####
    # Gain margins
    gain_margins= Vector{Vector{Float64}}(undef,λₙ) 
    frequencies_GM = Vector{Vector{Float64}}(undef,λₙ) 
    # Phase margins
    phase_margins= Vector{Vector{Float64}}(undef,λₙ) 
    frequencies_PM = Vector{Vector{Float64}}(undef,λₙ) 
    # Vector margins 
    vector_margins= Vector{Vector{Float64}}(undef,λₙ) 
    frequencies_VM = Vector{Vector{Float64}}(undef,λₙ) 

    #Loop over eigenvalues :)
    for t=1:λₙ
        L=Λ[:,t] 
        # Wrap angle of loop gain between 0° and -360°
        L_mag = abs.(Λ[:,t])
        # L_mag_dB = 20*log10.(L_mag)
        L_ph = angle.(Λ[:,t]).*(180/π)
        for i in 1:length(L_ph)
            if L_ph[i] > 0
                L_ph[i] = L_ph[i] - 360 # Wrapping angle between 0° and -360°
            end
        end


        # Gain margins
        gain_margins_lambda = []
        frequencies_GM_lambda = []
        counter_GM = 0 
        for i in 2:length(L)
            if ((L_ph[i-1] > -180 && L_ph[i] < -180) || (L_ph[i-1] < -180 && L_ph[i] > -180)) && (real(Λ[i,t]) < 0)
                GM = -20*log10(L_mag[i])
                GM = round(GM, digits = 2)
                f_pcf = round(omega[i]/(2*π), digits = 2)
                push!(gain_margins_lambda   , GM)
                push!(frequencies_GM_lambda, f_pcf)
                #println("\t Gain margin is ", GM, " dB at phase crossover frequency ", f_pcf, " Hz")
                counter_GM = counter_GM + 1
            end
        end

        if counter_GM == 0
            #println("\t Infinite gain margin")
        end

        gain_margins[t] = gain_margins_lambda
        frequencies_GM[t] = frequencies_GM_lambda


        phase_margins_lambda = []
        frequencies_PM_lambda = []
        counter_PM = 0 
        for i in 2:length(L)
                if (abs(L[i-1]) > 1 && abs(L[i]) < 1) || (abs(L[i-1]) < 1 && abs(L[i]) > 1)
                PM = L_ph[i] + 180
                if PM > 180
                        PM = PM - 360
                end
                PM = round(PM, digits = 2)
                f_gcf = round(omega[i]/(2*π), digits = 2)
                push!(phase_margins_lambda   , PM)
                push!(frequencies_PM_lambda, f_gcf)
                #println("\t Phase margin is ", PM, "° at gain crossover frequency ", f_gcf, " Hz")
                counter_PM = counter_PM + 1
                end
        end

        if counter_PM == 0
                #println("\t Infinite phase margin")
        end
        phase_margins[t] = phase_margins_lambda
        frequencies_PM[t] = frequencies_PM_lambda

        # Vector margins
        L_VM_dif = abs.(L .+ 1)
        index_VM = findall(x -> x == minimum(L_VM_dif), L_VM_dif)
        index_VM = index_VM[1]
        VM = L_VM_dif[index_VM]*100
        VM = round(VM, digits = 2)
        f_VM = round(omega[index_VM]/(2*π), digits = 2)
        #println("\t Vector margin is ", VM, " % at frequency ", f_VM, " Hz")
        vector_margins[t] = [VM]
        frequencies_VM[t] = [f_VM]



    end





    return stability, gain_margins, frequencies_GM, phase_margins, frequencies_PM, vector_margins, frequencies_VM




end



function IEEE39bus_powerflow!(grid::Network,Q_ST :: Float64, Vac_ref_ST :: Float64)
# Q_ST [SI/MVA], Vac_ref_ST [SI/kV]
        # Fix some values for power flow convergence
        grid.elements[Symbol("STATCOM")].element_value.P_dc = 0  # Check helps!
        grid.elements[Symbol("STATCOM")].element_value.Q = Q_ST   # MVA
        grid.elements[Symbol("STATCOM")].element_value.controls[:q].ref=[0] # Needed so that the setpoint is set correctly internally
        grid.elements[Symbol("STATCOM")].element_value.controls[:vac_supp].ref=[Vac_ref_ST]
        grid.elements[Symbol("STATCOM")].element_value.Vₘ = grid.elements[Symbol("STATCOM")].element_value.vACbase_LL_RMS/sqrt(3) # Set Vm to default value again to have correct bus voltage limits!
        result, _, nodes2bus, _ = PowerImpedanceACDC.power_flow(grid) # run power flow routine, which also obtains the linearized state-space of the STATCOM

        # Check whether Q limits are reached!
        q_pf=result["solution"]["convdc"]["1"]["qgrid"]
        Qfixed=false
        if abs((q_pf*result["solution"]["baseMVA"]))>grid.elements[Symbol("STATCOM")].element_value.Sbase
                Qfixed=true
                println("Q limits of the STATCOM are reached in power flow! Adjusting the power flow to the maximum Q value of the STATCOM.")
                # We need to convert the Vac-droop to Q fixed!
                vac_supp_controller=grid.elements[Symbol("STATCOM")].element_value.controls[:vac_supp] # Save the vac_droop controller with Vac setpoint!
                delete!(grid.elements[Symbol("STATCOM")].element_value.controls,:vac_supp) # Remove the vac_supp controller
                # Set the Q setpoint to the maximum value and run power flow again
                grid.elements[Symbol("STATCOM")].element_value.Q = -sign(q_pf)*grid.elements[Symbol("STATCOM")].element_value.Sbase  # Sign swapped in PMACDC!
                grid.elements[Symbol("STATCOM")].element_value.controls[:q].ref=[0] # Needed so that the setpoint is set correctly internally
                #Set Vm to default value again to have correct bus voltage limits!
                grid.elements[Symbol("STATCOM")].element_value.Vₘ  =  grid.elements[Symbol("STATCOM")].element_value.vACbase_LL_RMS/sqrt(3)
                result, _, _, _ = PowerImpedanceACDC.power_flow(grid)
                push!(grid.elements[Symbol("STATCOM")].element_value.controls,:vac_supp => vac_supp_controller) # Add the vac_supp controller back to the STATCOM
                
        end
        # Store the power flow results in the powerflow array
        Q_fixed=Qfixed
        bus=nodes2bus[Set([:Bus9d, :Bus9q])][2]
        Vm=result["solution"]["bus"][string(bus)]["vm"]
        Va=result["solution"]["bus"][string(bus)]["va"]
        P=-result["solution"]["convdc"]["1"]["pgrid"] * result["solution"]["baseMVA"]
        Q=-1.0*result["solution"]["convdc"]["1"]["qgrid"] * result["solution"]["baseMVA"]
        Pdc=result["solution"]["convdc"]["1"]["pdc"] * result["solution"]["baseMVA"]
        Vdc = result["solution"]["busdc"]["1"]["vm"] * (1)

        return Vm,Va,P,Q,Vdc,Pdc,Q_fixed


end

function IEEE39bus_parametric(line_status::Dict{Symbol,Bool})
# Function to obtain the IEEE39bus network with parametric topology control

# Grid parameters
Vm1=345/sqrt(3) # rms - phase [kV]


# Transformer parameters
Lb_345=(345e3)^2/(2*pi*50*1000e6) # in H
Rb_345=(345e3)^2/(1000e6) # in Ohms

#STATCOM parameters
Vdc_ST=110 #Pole-pole DC voltage
S_ST=269 # MVA 
Z_ST_base = 345^2/S_ST
Lf_ST = 0.08 * Z_ST_base /2/pi/50
Rf_ST = 0.01 * 0.08*Z_ST_base
Q_ST=0.5# per unit of Sbase
Vac_ref_ST=1.0 # per unit of Vm1


IEEE39bus = @network begin
    
voltageBase = Vm1




# Sources @ 345 kV
G30=ac_source(pins = 3, V = Vm1, transformation = true)
G31=ac_source(pins = 3, V = Vm1, transformation = true)
G32=ac_source(pins = 3, V = Vm1, transformation = true)
G33=ac_source(pins = 3, V = Vm1, transformation = true)
G34=ac_source(pins = 3, V = Vm1, transformation = true)
G35=ac_source(pins = 3, V = Vm1, transformation = true)
G36=ac_source(pins = 3, V = Vm1, transformation = true)
G37=ac_source(pins = 3, V = Vm1, transformation = true)
G38=ac_source(pins = 3, V = Vm1, transformation = true)
G39=ac_source(pins = 3, V = Vm1, transformation = true)
# Source impedances @ 345 kV
Zg30=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg31=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg32=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg33=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg34=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg35=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg36=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg37=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg38=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)
Zg39=impedance(z = (s::Complex)-> 2.0*(0.495318602  + s*0.0315330178), pins = 3, transformation = true)

G_DC=dc_source(pins = 1, V = Vdc_ST/2) # DC voltage source to arrange Powerflow of Statcom, not possible to directly connect to DC-controlling STATCOM
STATCOM= tlc(Vᵈᶜ = Vdc_ST, Lᵣ = Lf_ST, Rᵣ = Rf_ST, 
        Sbase = S_ST, vDCbase = Vdc_ST,Vₘ = Vm1,
        Q = Q_ST*S_ST,vACbase_LL_RMS = 345,
        occ =PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8),
        pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = (2*pi)*80, n_f=2), # These gains are fine.
        v_meas_filt = PI_control(ω_f = 150*2*pi, n_f=2),
        i_meas_filt = PI_control(ω_f = (1/3)*1e4, n_f=2),
        dc = PI_control(Kₚ = 0.05, Kᵢ = 0.1),
        q = PI_control(Kₚ = 0.15, Kᵢ = 150),
        vac_supp = PI_control(Kₚ=15,ω_f=(100*2*pi),ref=[Vm1*sqrt(2)*Vac_ref_ST]), 
        timeDelay = 150e-6,
        padeOrderNum = 3,                    
        padeOrderDen = 3 
)

dummy_impedance=impedance(z = 1e6, pins = 1) # Dummy impedance to arrange powerflow of DC-controlling STATCOM
# Transformers

# Bus 2 - Bus 30

TR2_30 = transformer(n = 345/345 , Lₚ = (0.0181/2)*Lb_345, Lₛ = (0.0181/2)*Lb_345,  pins = 3, transformation = true)


# Bus 6 - Bus 31

TR6_31 = transformer(n = 345/345 , Lₚ = (0.025/2)*Lb_345, Lₛ = (0.025/2)*Lb_345, pins = 3, transformation = true)


# Bus 10 - Bus 32

TR10_32 = transformer(n = 345/345 , Lₚ = (0.02/2)*Lb_345, Lₛ = (0.02/2)*Lb_345,  pins = 3, transformation = true)

# Bus 11 - Bus 12

TR11_12 = transformer(n = 345/345 , Lₚ = (0.0435/2)*Lb_345, Rₚ = (0.0016/2)*Rb_345, Lₛ = (0.0435/2)*Lb_345, Rₛ = (0.0016/2)*Rb_345,  pins = 3, transformation = true)

# Bus 12 - Bus 13

TR12_13 = transformer(n = 345/345 , Lₚ = (0.0435/2)*Lb_345, Rₚ = (0.0016/2)*Rb_345, Lₛ = (0.0435/2)*Lb_345, Rₛ = (0.0016/2)*Rb_345,  pins = 3, transformation = true)

# Bus 19 - Bus 20

TR19_20 = transformer(n = 345/345 , Lₚ = (0.0138 /2)*Lb_345, Rₚ = (0.0007/2)*Rb_345, Lₛ = (0.0138 /2)*Lb_345, Rₛ = (0.0007/2)*Rb_345,  pins = 3, transformation = true)

# Bus 19 - Bus 33

TR19_33 = transformer(n = 345/345 , Lₚ = (0.0142 /2)*Lb_345, Rₚ = (0.0007/2)*Rb_345, Lₛ = (0.0142 /2)*Lb_345, Rₛ = (0.0007/2)*Rb_345,  pins = 3, transformation = true)


# Bus 20 - Bus 34

TR20_34 = transformer(n = 345/345 , Lₚ = (0.0180 /2)*Lb_345, Rₚ = (0.0009/2)*Rb_345, Lₛ = (0.0180 /2)*Lb_345, Rₛ = (0.0009/2)*Rb_345,  pins = 3, transformation = true)


# Bus 22 - Bus 35

TR22_35 = transformer(n = 345/345 , Lₚ = (0.0143 /2)*Lb_345, Lₛ = (0.0143 /2)*Lb_345,  pins = 3, transformation = true)

# Bus 23 - Bus 36

TR23_36 = transformer(n = 345/345 , Lₚ = (0.0272 /2)*Lb_345, Rₚ = (0.0005/2)*Rb_345, Lₛ = (0.0272 /2)*Lb_345, Rₛ = (0.0005/2)*Rb_345,  pins = 3, transformation = true)

# Bus 25 - Bus 37

TR25_37 = transformer(n = 345/345 , Lₚ = (0.0232 /2)*Lb_345, Rₚ = (0.0006/2)*Rb_345, Lₛ = (0.0232 /2)*Lb_345, Rₛ = (0.0006/2)*Rb_345,  pins = 3, transformation = true)

# Bus 29 - Bus 38

TR29_38 = transformer(n = 345/345 , Lₚ = (0.0156 /2)*Lb_345, Rₚ = (0.0008/2)*Rb_345, Lₛ = (0.0156 /2)*Lb_345, Rₛ = (0.0008/2)*Rb_345,  pins = 3, transformation = true)







# Power lines

T1_2 = overhead_line(length = 72.4730e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection =line_status[:T1_2])

T1_39 = overhead_line(length = 44.0833e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T1_39]) # Connection = true --> Line connected, false: disconnected

T2_3 = overhead_line(length = 26.6263e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T2_3])

T2_25 = overhead_line(length = 15.1647e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T2_25])

T3_4 = overhead_line(length = 37.5590e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T3_4])

T3_18 = overhead_line(length = 23.4523e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T3_18])

T4_5 = overhead_line(length = 22.5707e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T4_5])

T4_14 = overhead_line(length = 22.7470e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T4_14])

T5_6 = overhead_line(length = 4.5847e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T5_6])

T5_8 = overhead_line(length = 19.7493e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T5_8])

T6_7 = overhead_line(length = 16.2227e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T6_7])

T6_11 = overhead_line(length = 14.4593e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T6_11])

T7_8 = overhead_line(length = 8.1113e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T7_8])

T8_9 = overhead_line(length = 64.009e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T8_9])

T9_39 = overhead_line(length = 44.0833e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection=line_status[:T9_39]) # Connection = true --> Line connected, false: disconnected

T10_11 = overhead_line(length = 7.5823e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T10_11])

T10_13 = overhead_line(length = 7.5823e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T10_13])

T13_14 = overhead_line(length = 17.8097e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection= line_status[:T13_14])

T14_15 = overhead_line(length = 38.2643e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true,connection= line_status[:T14_15])

T15_16 = overhead_line(length = 16.5753e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T15_16])

T16_17 = overhead_line(length = 15.6937e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true,connection = line_status[:T16_17])

T16_19 = overhead_line(length = 34.3850e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T16_19])

T16_21 = overhead_line(length = 23.8050e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T16_21])

T16_24 = overhead_line(length = 10.4037e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T16_24])

T17_18 = overhead_line(length = 14.4593e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T17_18])

T17_27 = overhead_line(length = 30.5057e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T17_27])

T21_22 = overhead_line(length = 24.6867e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T21_22] )

T22_23 = overhead_line(length = 16.9280e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T22_23])

T23_24 = overhead_line(length = 61.7167e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T23_24])

T25_26 = overhead_line(length = 56.95573e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T25_26])

T26_27 = overhead_line(length = 25.9210e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T26_27])

T26_28 = overhead_line(length = 83.5820e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T26_28])

T26_29 = overhead_line(length = 110.2083e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T26_29])

T28_29 = overhead_line(length = 26.6263e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true, connection = line_status[:T28_29])









































# Loads

# Load Bus 3
LoadB3= impedance(z = (s::Complex)-> (R_B3+s*L_B3), pins = 3, transformation = true)

# Load Bus 4
LoadB4a= impedance(z = (s::Complex)-> (R_B4a+s*L_B4), pins = 3, transformation = true)
LoadB4b= impedance(z = (s::Complex)-> (R_B4b+(1/(s*C_B4))), pins = 3, transformation = true)
# Load Bus 5
LoadB5= impedance(z = (s::Complex)-> (R_B5+(1/(s*C_B5))), pins = 3, transformation = true)

# Load Bus 7
LoadB7= impedance(z = (s::Complex)-> (R_B7+s*L_B7), pins = 3, transformation = true)

# Load Bus 8
LoadB8= impedance(z = (s::Complex)-> (R_B8+s*L_B8), pins = 3, transformation = true)

# Load Bus 12
LoadB12= impedance(z = (s::Complex)-> (345/230)*(345/230)*(R_B12+s*L_B12), pins = 3, transformation = true) #Referring load to 345 kV side
# Load Bus 15
LoadB15= impedance(z = (s::Complex)-> (R_B15+s*L_B15), pins = 3, transformation = true)

# Load Bus 16
LoadB16= impedance(z = (s::Complex)-> (R_B16+s*L_B16), pins = 3, transformation = true)

# Load Bus 18
LoadB18= impedance(z = (s::Complex)-> (R_B18+s*L_B18), pins = 3, transformation = true)

# Load Bus 20
LoadB20= impedance(z = (s::Complex)-> (R_B20+s*L_B20), pins = 3, transformation = true)

# Load Bus 21
LoadB21= impedance(z = (s::Complex)-> (R_B21+s*L_B21), pins = 3, transformation = true)

# Load Bus 23
LoadB23= impedance(z = (s::Complex)-> (R_B23+s*L_B23), pins = 3, transformation = true)
# Load Bus 24
LoadB24= impedance(z = (s::Complex)-> (R_B24+(1/(s*C_B24))), pins = 3, transformation = true)

# Load Bus 25
LoadB25= impedance(z = (s::Complex)-> (R_B25+s*L_B25), pins = 3, transformation = true)

# Load Bus 26
LoadB26= impedance(z = (s::Complex)-> (R_B26+s*L_B26), pins = 3, transformation = true)

# Load Bus 27
LoadB27= impedance(z = (s::Complex)-> (R_B27+s*L_B27), pins = 3, transformation = true)

# Load Bus 28
LoadB28= impedance(z = (s::Complex)-> (R_B28+s*L_B28), pins = 3, transformation = true)
# Load Bus 29
LoadB29= impedance(z = (s::Complex)-> (R_B29+s*L_B29), pins = 3, transformation = true)

# Load Bus 31
LoadB31= impedance(z = (s::Complex)-> (345/22)*(345/22)*(R_B31+s*L_B31), pins = 3, transformation = true) #Referring load to 345 kV side

# Load Bus 39
LoadB39= impedance(z = (s::Complex)-> (R_B39+s*L_B39), pins = 3, transformation = true)

# Dummy impedances to help with lumped pins of lines as a consequence of topology variations
dummy_impedance_B1 = impedance(z = 1e13, pins = 3, transformation = true)





# Connection

# Sources grounding

G30[2.1] ⟷ gndD
G30[2.2] ⟷ gndQ
G31[2.1] ⟷ gndD
G31[2.2] ⟷ gndQ
G32[2.1] ⟷ gndD
G32[2.2] ⟷ gndQ
G33[2.1] ⟷ gndD
G33[2.2] ⟷ gndQ
G34[2.1] ⟷ gndD
G34[2.2] ⟷ gndQ
G35[2.1] ⟷ gndD
G35[2.2] ⟷ gndQ
G36[2.1] ⟷ gndD
G36[2.2] ⟷ gndQ
G37[2.1] ⟷ gndD
G37[2.2] ⟷ gndQ
G38[2.1] ⟷ gndD
G38[2.2] ⟷ gndQ
G39[2.1] ⟷ gndD
G39[2.2] ⟷ gndQ
G_DC[2.1] ⟷ gndDC

# Loads grounding

LoadB3[2.1] ⟷ gndD
LoadB3[2.2] ⟷ gndQ
LoadB4a[2.1] ⟷ gndD
LoadB4a[2.2] ⟷ gndQ
LoadB4b[2.1] ⟷ gndD
LoadB4b[2.2] ⟷ gndQ
LoadB5[2.1] ⟷ gndD
LoadB5[2.2] ⟷ gndQ
LoadB7[2.1] ⟷ gndD
LoadB7[2.2] ⟷ gndQ
LoadB8[2.1] ⟷ gndD
LoadB8[2.2] ⟷ gndQ
LoadB12[2.1] ⟷ gndD
LoadB12[2.2] ⟷ gndQ
LoadB15[2.1] ⟷ gndD
LoadB15[2.2] ⟷ gndQ
LoadB16[2.1] ⟷ gndD
LoadB16[2.2] ⟷ gndQ
LoadB18[2.1] ⟷ gndD
LoadB18[2.2] ⟷ gndQ
LoadB20[2.1] ⟷ gndD     
LoadB20[2.2] ⟷ gndQ
LoadB21[2.1] ⟷ gndD
LoadB21[2.2] ⟷ gndQ
LoadB23[2.1] ⟷ gndD
LoadB23[2.2] ⟷ gndQ
LoadB24[2.1] ⟷ gndD
LoadB24[2.2] ⟷ gndQ
LoadB25[2.1] ⟷ gndD
LoadB25[2.2] ⟷ gndQ
LoadB26[2.1] ⟷ gndD
LoadB26[2.2] ⟷ gndQ
LoadB27[2.1] ⟷ gndD
LoadB27[2.2] ⟷ gndQ
LoadB28[2.1] ⟷ gndD
LoadB28[2.2] ⟷ gndQ
LoadB29[2.1] ⟷ gndD
LoadB29[2.2] ⟷ gndQ
LoadB31[2.1] ⟷ gndD
LoadB31[2.2] ⟷ gndQ
LoadB39[2.1] ⟷ gndD
LoadB39[2.2] ⟷ gndQ
dummy_impedance_B1[2.1] ⟷ gndD  
dummy_impedance_B1[2.2] ⟷ gndQ

# Sources

G30[1.1] ⟷ Zg30[1.1]
G30[1.2] ⟷ Zg30[1.2]
G31[1.1] ⟷ Zg31[1.1]
G31[1.2] ⟷ Zg31[1.2]    
G32[1.1] ⟷ Zg32[1.1]
G32[1.2] ⟷ Zg32[1.2]
G33[1.1] ⟷ Zg33[1.1]
G33[1.2] ⟷ Zg33[1.2]
G34[1.1] ⟷ Zg34[1.1]
G34[1.2] ⟷ Zg34[1.2]
G35[1.1] ⟷ Zg35[1.1]
G35[1.2] ⟷ Zg35[1.2]
G36[1.1] ⟷ Zg36[1.1]
G36[1.2] ⟷ Zg36[1.2]
G37[1.1] ⟷ Zg37[1.1]
G37[1.2] ⟷ Zg37[1.2]
G38[1.1] ⟷ Zg38[1.1]
G38[1.2] ⟷ Zg38[1.2]
G39[1.1] ⟷ Zg39[1.1]
G39[1.2] ⟷ Zg39[1.2]
G_DC[1.1] ⟷ dummy_impedance[2.1]


T1_39[1.1] ⟷ T1_2[1.1] ⟷ dummy_impedance_B1[1.1] ==Bus1d #
T1_39[1.2] ⟷ T1_2[1.2] ⟷ dummy_impedance_B1[1.2] == Bus1q #

T2_25[1.1] ⟷ T1_2[2.1] == T2_3[1.1] ⟷ TR2_30[1.1] == Bus2d
T2_25[1.2] ⟷ T1_2[2.2] == T2_3[1.2] ⟷ TR2_30[1.2] == Bus2q

T2_3[2.1] ⟷ T3_18[1.1] ⟷ T3_4[1.1] ⟷ LoadB3[1.1] == Bus3d
T2_3[2.2] ⟷ T3_18[1.2] ⟷ T3_4[1.2] ⟷ LoadB3[1.2] == Bus3q

T3_4[2.1] ⟷ T4_5[1.1] ⟷ T4_14[1.1] ⟷ LoadB4a[1.1] ⟷ LoadB4b[1.1] == Bus4d
T3_4[2.2] ⟷ T4_5[1.2] ⟷ T4_14[1.2] ⟷ LoadB4a[1.2] ⟷ LoadB4b[1.2] == Bus4q

T4_5[2.1] ⟷ T5_6[1.1] ⟷ T5_8[1.1] ⟷LoadB5[1.1] == Bus5d
T4_5[2.2] ⟷ T5_6[1.2] ⟷ T5_8[1.2] ⟷LoadB5[1.2] == Bus5q

T5_6[2.1] ⟷ T6_7[1.1] ⟷ T6_11[1.1] ⟷ TR6_31[1.1]  == Bus6d
T5_6[2.2] ⟷ T6_7[1.2] ⟷ T6_11[1.2] ⟷ TR6_31[1.2]  == Bus6q

T6_7[2.1] ⟷ T7_8[1.1] ⟷ LoadB7[1.1] == Bus7d
T6_7[2.2] ⟷ T7_8[1.2] ⟷ LoadB7[1.2] == Bus7q

T7_8[2.1] ⟷ T8_9[1.1] ⟷ T5_8[2.1] ⟷ LoadB8[1.1] == Bus8d
T7_8[2.2] ⟷ T8_9[1.2] ⟷ T5_8[2.2] ⟷ LoadB8[1.2] == Bus8q

T8_9[2.1] ⟷ T9_39[1.1] == STATCOM[2.1] == Bus9d
T8_9[2.2] ⟷ T9_39[1.2] == STATCOM[2.2] == Bus9q
dummy_impedance[1.1] == STATCOM[1.1]

T10_11[1.1] ⟷ T10_13[1.1] ⟷ TR10_32[1.1] == Bus10d
T10_11[1.2] ⟷ T10_13[1.2] ⟷ TR10_32[1.2] == Bus10q

T10_11[2.1] ⟷ T6_11[2.1] ⟷ TR11_12[1.1] == Bus11d
T10_11[2.2] ⟷ T6_11[2.2] ⟷ TR11_12[1.2] == Bus11q

TR11_12[2.1] ⟷ TR12_13[1.1] ⟷ LoadB12[1.1] == Bus12d
TR11_12[2.2] ⟷ TR12_13[1.2] ⟷ LoadB12[1.2] == Bus12q

T10_13[2.1] ⟷ T13_14[1.1] ⟷ TR12_13[2.1] == Bus13d
T10_13[2.2] ⟷ T13_14[1.2] ⟷ TR12_13[2.2] == Bus13q

T14_15[1.1] ⟷ T13_14[2.1] ⟷ T4_14[2.1] == Bus14d
T14_15[1.2] ⟷ T13_14[2.2] ⟷ T4_14[2.2] == Bus14q

T14_15[2.1] ⟷ T15_16[1.1] ⟷ LoadB15[1.1] == Bus15d
T14_15[2.2] ⟷ T15_16[1.2] ⟷ LoadB15[1.2] == Bus15q

T15_16[2.1] ⟷ T16_17[1.1] ⟷ T16_19[1.1] ⟷ T16_21[1.1] ⟷ T16_24[1.1] ⟷ LoadB16[1.1] == Bus16d
T15_16[2.2] ⟷ T16_17[1.2] ⟷ T16_19[1.2] ⟷ T16_21[1.2] ⟷ T16_24[1.2] ⟷ LoadB16[1.2] == Bus16q

T16_17[2.1] ⟷ T17_18[1.1] ⟷ T17_27[1.1] == Bus17d
T16_17[2.2] ⟷ T17_18[1.2] ⟷ T17_27[1.2] == Bus17q

T17_18[2.1] ⟷ LoadB18[1.1] ⟷ T3_18[2.1] == Bus18d
T17_18[2.2] ⟷ LoadB18[1.2] ⟷ T3_18[2.2] == Bus18q

T16_19[2.1] ⟷ TR19_20[1.1] ⟷ TR19_33[1.1] == Bus19d
T16_19[2.2] ⟷ TR19_20[1.2] ⟷ TR19_33[1.2] == Bus19q

TR19_20[2.1] ⟷ TR20_34[1.1] ⟷ LoadB20[1.1] ==  Bus20d
TR19_20[2.2] ⟷ TR20_34[1.2] ⟷ LoadB20[1.2] ==  Bus20q

T16_21[2.1] ⟷ LoadB21[1.1] ⟷ T21_22[1.1]== Bus21d
T16_21[2.2] ⟷ LoadB21[1.2] ⟷ T21_22[1.2]== Bus21q

T21_22[2.1] ⟷ T22_23[1.1] ⟷ TR22_35[1.1] == Bus22d
T21_22[2.2] ⟷ T22_23[1.2] ⟷ TR22_35[1.2] == Bus22q

T22_23[2.1] ⟷ LoadB23[1.1] ⟷ T23_24[1.1] ⟷ TR23_36[1.1] == Bus23d
T22_23[2.2] ⟷ LoadB23[1.2] ⟷ T23_24[1.2] ⟷ TR23_36[1.2] == Bus23q

T16_24[2.1] ⟷ T23_24[2.1] ⟷LoadB24[1.1] == Bus24d
T16_24[2.2] ⟷ T23_24[2.2] ⟷LoadB24[1.2] == Bus24q

T2_25[2.1] ⟷ LoadB25[1.1] ⟷ T25_26[1.1] ⟷ TR25_37[1.1]== Bus25d
T2_25[2.2] ⟷ LoadB25[1.2] ⟷ T25_26[1.2] ⟷ TR25_37[1.2]== Bus25q

T25_26[2.1] ⟷ LoadB26[1.1] ⟷ T26_27[1.1] ⟷ T26_28[1.1] ⟷ T26_29[1.1] == Bus26d
T25_26[2.2] ⟷ LoadB26[1.2] ⟷ T26_27[1.2] ⟷ T26_28[1.2] ⟷ T26_29[1.2] == Bus26q

T26_27[2.1] ⟷ T17_27[2.1] ⟷ LoadB27[1.1] == Bus27d
T26_27[2.2] ⟷ T17_27[2.2] ⟷ LoadB27[1.2] == Bus27q

T26_28[2.1] ⟷ T28_29[1.1] ⟷ LoadB28[1.1] == Bus28d
T26_28[2.2] ⟷ T28_29[1.2] ⟷ LoadB28[1.2] == Bus28q

T26_29[2.1] ⟷ LoadB29[1.1] ⟷ T28_29[2.1] ⟷ TR29_38[1.1] == Bus29d
T26_29[2.2] ⟷ LoadB29[1.2] ⟷ T28_29[2.2] ⟷ TR29_38[1.2] == Bus29q

TR2_30[2.1] ⟷ Zg30[2.1] == Bus30d
TR2_30[2.2] ⟷ Zg30[2.2] == Bus30q

TR6_31[2.1] ⟷ Zg31[2.1] == Bus31d
TR6_31[2.2] ⟷ Zg31[2.2] == Bus31q

TR10_32[2.1] ⟷ Zg32[2.1] ⟷ LoadB31[1.1] == Bus32d
TR10_32[2.2] ⟷ Zg32[2.2] ⟷ LoadB31[1.2] == Bus32q

TR19_33[2.1] ⟷ Zg33[2.1] == Bus33d
TR19_33[2.2] ⟷ Zg33[2.2] == Bus33q

TR20_34[2.1] ⟷ Zg34[2.1] == Bus34d
TR20_34[2.2] ⟷ Zg34[2.2] == Bus34q

TR22_35[2.1] ⟷ Zg35[2.1] == Bus35d
TR22_35[2.2] ⟷ Zg35[2.2] == Bus35q

TR23_36[2.1] ⟷ Zg36[2.1] == Bus36d
TR23_36[2.2] ⟷ Zg36[2.2] == Bus36q

TR25_37[2.1] ⟷ Zg37[2.1] == Bus37d
TR25_37[2.2] ⟷ Zg37[2.2] == Bus37q

TR29_38[2.1] ⟷ Zg38[2.1] == Bus38d
TR29_38[2.2] ⟷ Zg38[2.2] == Bus38q

Zg39[2.1] ⟷ T1_39[2.1] ⟷ T9_39[2.1] ⟷ LoadB39[1.1] == Bus39d
Zg39[2.2] ⟷ T1_39[2.2] ⟷ T9_39[2.2] ⟷ LoadB39[1.2] == Bus39q

end

end


# Make ordered DICT! Or double-check whether ordered Dict really needed!
topology = Dict{Symbol,Bool}(
    :T1_2 => true,  :T1_39 => true, :T2_3 => true,  :T2_25 => true, :T3_4 => true,
    :T3_18 => true, :T4_5 => true,  :T9_39 => true, :T5_6 => true,  :T5_8 => true,
    :T6_7 => true,  :T6_11 => true, :T7_8 => true,  :T8_9 => true, :T4_14 => true,      
    :T10_11 => true,:T10_13 => true,:T13_14 => true,:T14_15 => true,:T15_16 => true,
    :T16_17 => true,:T16_19 => true,:T16_21 => true,:T16_24 => true,:T17_18 => true,
    :T17_27 => true,:T21_22 => true,:T22_23 => true,:T23_24 => true,:T25_26 => true,
    :T26_27 => true,:T26_28 => true,:T26_29 => true,:T28_29 => true
)



##### Case study options
min_f=1e0 # Minimum frequency in Hz
max_f=5e3 # Maximum frequency in Hz 
n_f=500 # Number of frequency points in the
omegas= 2*pi* 10 .^range(log10(min_f), log10(max_f), length= n_f) 
# Q_steps=[1.0]
# V_steps=[1.0]
Q_steps=range(start=-1.0, stop=1.0, length=21)
V_steps=range(start=0.9, stop=1.1, length=21)
C=250e-6*0.5 # DC-side capacitance of the STATCOM: 250e-6F for each pole ---> 0.5*250e-6 is equivalent capacitance for the differential mode

#### Pre-allocate arrays to store results
Zgrid = Array{Matrix{ComplexF64},2}(undef, length(topology)+1, n_f) # Line-f-AC_impedance
Y_Statcom = Array{Matrix{ComplexF64},4}(undef, length(topology)+1, length(Q_steps), length(V_steps),n_f) # Line-Q-V-STATCOM_admittance (full 3x3 matrix)
Y_Statcom_ac = Array{Matrix{ComplexF64},4}(undef, length(topology)+1, length(Q_steps), length(V_steps), n_f) # Line-Q-V-STATCOM_admittance AC
powerflow=Array{PowerFlowResult}(undef, length(topology)+1, length(Q_steps), length(V_steps)) # Line-Q-V-Powerflow results
GNCs=Array{Any}(undef, length(topology)+1, length(Q_steps), length(V_steps)) # Line-Q-V-GNCs
#Z_cl = Array{Matrix{ComplexF64},4}(undef, length(topology), length(Q_steps), length(V_steps), n_f) # Line-Q-V-f-Zcl
#modes = Array{ModeInfo}(undef, length(topology), length(Q_steps), length(V_steps)) # Line-Q-V-unstable modes


for lines in keys(topology)

        topology[lines]=false # Disconnect the line

        # Obtain grid impedance. As the grid is linear, the impedance is independent of the operating point ✔️
        grid=IEEE39bus_parametric(topology)
        index=findfirst(==(lines),collect(keys(topology)))
        Zgrid[index,:], _ =determine_impedance(grid, input_pins=[:Bus9d,:Bus9q], output_pins=[:gndD, :gndQ], elim_elements=[:STATCOM],freq_range=(min_f, max_f,n_f))
        for i in eachindex(Q_steps) # Iterate over all Q-setpoints

                for j in eachindex(V_steps) # Iterate over all V-setpoints

                        Vm_pf,Va_pf,P_pf,Q_pf,Vdc_pf,Pdc_pf,Q_fixed=@time IEEE39bus_powerflow!(grid,Q_steps[i]*269,V_steps[j]*sqrt(2/3)*345) # Update power flow and obtain STATCOM Y for the given operating point
                        powerflow[index,i,j] =PowerFlowResult(Vm_pf,Va_pf,P_pf,Q_pf,Vdc_pf,Pdc_pf,Q_fixed)
                        # Grab STATCOM admittance for the given operating point
                        for k in eachindex(omegas)
                                Y1 = PowerImpedanceACDC.eval_parameters(grid.elements[:STATCOM].element_value, omegas[k]*1im)
                                Y_Statcom[index, i, j, k] = [transpose(Y1[1,:]); transpose(-Y1[2,:]); transpose(-Y1[3,:])]
                        end
                end
        end
        topology[lines]=true
end

# Base case: all lines connected (index = length(topology)+1)
index_base = length(topology)+1 
grid_base=IEEE39bus_parametric(topology)
Zgrid[index_base,:], _ =determine_impedance(grid_base, input_pins=[:Bus9d,:Bus9q], output_pins=[:gndD, :gndQ], elim_elements=[:STATCOM],freq_range=(min_f, max_f,n_f))
for i in eachindex(Q_steps)
        for j in eachindex(V_steps)
                Vm_pf,Va_pf,P_pf,Q_pf,Vdc_pf,Pdc_pf,Q_fixed=@time IEEE39bus_powerflow!(grid_base,Q_steps[i]*269,V_steps[j]*sqrt(2/3)*345)
                powerflow[index_base,i,j] =PowerFlowResult(Vm_pf,Va_pf,P_pf,Q_pf,Vdc_pf,Pdc_pf,Q_fixed)
                for k in eachindex(omegas)
                        Y1 = PowerImpedanceACDC.eval_parameters(grid_base.elements[:STATCOM].element_value, omegas[k]*1im)
                        Y_Statcom[index_base, i, j, k] = [transpose(Y1[1,:]); transpose(-Y1[2,:]); transpose(-Y1[3,:])]
                end
        end
end




# Collapsing 3x3 admittance matrix to a 2x2 matrix by considering the DC-side dynamics

@time for line in 1:size(Y_Statcom, 1), i in 1:size(Y_Statcom, 2), j in 1:size(Y_Statcom, 3), k in 1:size(Y_Statcom, 4)
                Y = Y_Statcom[line, i, j, k]
                Yc = C*1im*omegas[k]
                denom = -Yc - Y[1,1]
                Y_Statcom_ac[line, i, j, k]=[(Y[2,1]*Y[1,2]+denom*Y[2,2])/denom (Y[2,1]*Y[1,3]+denom*Y[2,3])/denom; (Y[3,1]*Y[1,2]+denom*Y[3,2])/denom (Y[3,1]*Y[1,3]+denom*Y[3,3])/denom]

end




# Calculate Nyquist 
@time for line in 1:size(Y_Statcom_ac, 1),i in 1:size(Y_Statcom_ac, 2),j in 1:size(Y_Statcom_ac, 3)
               
                loopgain=Zgrid[line, :].*(Y_Statcom_ac[line, i, j, :]) # Loop gain = Zgrid * Y_Statcom
                stability, gain_margins, frequencies_GM, phase_margins, frequencies_PM, vector_margins, frequencies_VM = Nyquist(loopgain, omegas)
                GNCs[line, i, j] = GNCInfo(stability, gain_margins[1], frequencies_GM[1], 
                                        phase_margins[1],frequencies_PM[1], 
                                        vector_margins[1], frequencies_VM[1], 
                                        gain_margins[2], frequencies_GM[2], 
                                        phase_margins[2], frequencies_PM[2], 
                                        vector_margins[2], frequencies_VM[2])

end

end