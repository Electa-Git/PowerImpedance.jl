# This is a PowerImpedanceACDC implementation of the modified IEEE 14 bus system test system
# Author: Jan Kircheis 
# Date: Sep 2025
# Case 1: Low-frequenyc scillation induced by WF 1

# PQ filters are active in PSCAD?
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

# Arranging environment
using PowerImpedanceACDC
using Plots#;plotlyjs() #Dynamic backend
using LaTeXStrings # Latex fonts
# Include Amauris function to do eps exports with inkscape
include("C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Scripts\\Julia\\export_eps.jl")
# Path to the inscape executable 
inkscape="c:\\Users\\jkirchei\\Desktop\\inkscape\\inkscape\\bin\\inkscape.exe"
# Path to store the resulting eps
storage_path="C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work Package 4\\Data\\Processed"



# Operating points
P_MMC1= -500
Q_MMC1= 0
P_MMC2=-1000
Q_MMC2=0
Q_MMC3=0.0
Q_MMC4=0.0
Pwf=600
Qwf=0

# Get load parameters :)
R_B3=calc_RLC(314,63.333,380,"R")
L_B3=calc_RLC(314,63.333,380,"L")

R_B4=calc_RLC(159.333,13,380,"R")
C_B4=calc_RLC(159.333,13,380,"C")

R_B5=calc_RLC(25.333,5.333,380,"R")
L_B5=calc_RLC(25.333,5.333,380,"L")

R_B6=calc_RLC(37.333,25.0,380,"R")
L_B6=calc_RLC(37.333,25.0,380,"L")

# Stability analysis options
min_f=0.1 # Minimum frequency in Hz
max_f=5e3 # Maximum frequency in Hz 
n_f=4000 # Discretization of the frequency, high value needed for PMD

Vm=380/sqrt(3)


IEEE14bus = @network begin

voltageBase = Vm

# Sources
G1=ac_source(pins = 3, V = Vm, transformation = true)
G2=ac_source(pins = 3, V = Vm, transformation = true)
DC_WF1=dc_source(pins = 2, V = 320, transformation = true)
DC_WF2=dc_source(pins = 2, V = 320, transformation = true)
DC_WF3=dc_source(pins = 2, V = 320, transformation = true)
Zg2=impedance(z = (s::Complex)-> (1.0263 + s*0.0327), pins = 3, transformation = true) # Top area
Zg1=impedance(z = (s::Complex)-> (0.2874  + s*0.0091)  , pins = 3, transformation = true) # Bottom area


#Converters


 MMC1 = mmc(Vᵈᶜ = 640, vDCbase = 640, Sbase = 1000, vACbase_LL_RMS = 333, turnsRatio = 333/380, Vₘ = Vm, Lᵣ = 0.18 * (333^2/1000) /2/pi/50, Rᵣ = 0.001 *(333^2/1000),
        P = P_MMC1, Q = Q_MMC1,
        Rₐᵣₘ = 0.4,Lₐᵣₘ = 46.125e-3,Cₐᵣₘ = 11.3867e-3,N = 400,
        occ = PI_control(Kₚ = 0.6532, Kᵢ = 281.1370,n_f= 2,ω_f=200*2*pi),
        ccc = PI_control(Kₚ = 0.0936, Kᵢ = 40.5396),
        zcc = PI_control(Kₚ = 0.0936, Kᵢ = 40.5396),
        energy = PI_control(Kₚ = 1.469, Kᵢ = 31.4819),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664, n_f= 1,ω_f=75*2*pi),
        q = PI_control(Kₚ = 0.0, Kᵢ = 3, n_f = 2,ω_f = 140*2*pi),
        p = VSE(H = 5,K_d = 100,K_ω = 10,ref_ω = 1, n_f = 2,ω_f = 140*2*pi),
        VI= CCQSEM(Rᵥ = 0.01,Lᵥ = 0.25,ref_vd = 1,ref_vq = 0,n_f = 2,ω_f =200 ), gfm= true, timeDelay=200e-6, padeOrderNum=5, padeOrderDen=5) 


MMC2=mmc(Vᵈᶜ = 640, vDCbase = 640, Sbase = 1000, vACbase_LL_RMS = 333, turnsRatio = 333/380, Vₘ = Vm, Lᵣ = 0.18 * (333^2/1000) /2/pi/50, Rᵣ = 0.001 *(333^2/1000),
        P = P_MMC2, Q = Q_MMC2,  
        Rₐᵣₘ = 0.4,Lₐᵣₘ = 46.125e-3,Cₐᵣₘ = 11.3867e-3,N = 400,
        occ = PI_control(Kₚ = 0.6532, Kᵢ = 281.1370,n_f= 2,ω_f=400*2*pi),
        ccc = PI_control(Kₚ = 0.0936, Kᵢ = 40.5396),
        zcc = PI_control(Kₚ = 0.0936, Kᵢ = 40.5396),
        energy = PI_control(Kₚ = 1.469, Kᵢ = 31.4819),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664, n_f= 1,ω_f=75*2*pi),
        q = PI_control(Kₚ = 0.0, Kᵢ = 3, n_f = 2,ω_f = 140*2*pi),
        p = VSE(H = 5,K_d = 100,K_ω = 10,ref_ω = 1, n_f = 2,ω_f = 140*2*pi),
        VI= CCQSEM(Rᵥ = 0.0,Lᵥ = 0.4,ref_vd = 1,ref_vq = 0,n_f = 2,ω_f =50), gfm= true, timeDelay=200e-6, padeOrderNum=5, padeOrderDen=5) 


MMC3=mmc(Vᵈᶜ = 640 , vDCbase = 640, Sbase = 1000, vACbase_LL_RMS = 333, turnsRatio = 333/380, Vₘ = Vm, Lᵣ = 0.1305*(333^2/1000)/2/pi/50, Rᵣ = 0.0037*(333^2/1000),
        Q = Q_MMC3,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654,n_f= 2,ω_f=600*2*pi),
        # occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654,n_f= 2,ω_f=100*2*pi), # Retuning required for trip of T2_5
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        zcc = PI_control(Kₚ = 0.0992, Kᵢ = 42.9719),
        energy = PI_control(Kₚ = 1.2894, Kᵢ = 27.63),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664,n_f= 1,ω_f=80*2*pi),
        dc = PI_control(Kₚ = 5, Kᵢ = 15),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159,n_f= 1,ω_f=100*2*pi),timeDelay= 250e-6, padeOrderNum=5, padeOrderDen=5
        #p= PI_control(Kₚ = 0.1, Kᵢ = 31.4159)
        )   

MMC4=mmc(Vᵈᶜ = 640 , vDCbase = 640, Sbase = 1000, vACbase_LL_RMS = 333, turnsRatio = 333/380, Vₘ = Vm, Lᵣ = 0.1305*(333^2/1000)/2/pi/50, Rᵣ = 0.0037*(333^2/1000),
        Q = Q_MMC4,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654,n_f= 2,ω_f=100*2*pi),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        zcc = PI_control(Kₚ = 0.0992, Kᵢ = 42.9719),
        energy = PI_control(Kₚ = 1.2894, Kᵢ = 27.63),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664,n_f= 1,ω_f=80*2*pi),
        #pll = PI_control(Kₚ = 1.5, Kᵢ = 314.15),
        dc = PI_control(Kₚ = 5, Kᵢ = 15),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159,n_f= 1,ω_f=100*2*pi) ,timeDelay=200e-6, padeOrderNum=5, padeOrderDen=5
        #p= PI_control(Kₚ = 0.1, Kᵢ = 31.4159)
        )   

# Delays deactivated for the wind farms!
WF1= tlc(Vᵈᶜ = 640, Vₘ = Vm, Lᵣ =0.08*(380^2/600)/2/pi/50, Rᵣ = 0.0008*(380^2/600), 
        Sbase = 600, vACbase_LL_RMS = 380, 
        P = Pwf, Q = Qwf,
        occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8), 
        pll = PI_control(Kₚ = 0.3978, Kᵢ = 7.9577, ω_f = 2*pi*50,n_f=1),
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
        P = Pwf, Q = Qwf,
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
        P = Pwf, Q = Qwf,
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
T1_2 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T1_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
# Create HFO instability with trip of T2_5
T2_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T4_5 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T2_4 = overhead_line(length = 250e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)


T2_3 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T3_4 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

# Top area⬆
T12_13 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_12 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_13 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T6_11 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)


T10_11 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T13_14 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T9_14 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

T9_10 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
T7_9 = overhead_line(length = 20e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

# Cables
# ABB Datasheet cables with no amouring to represent onshore cables 
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

T10_11[1.1] ⟷ T9_10[2.1] ⟷ Bus10d
T10_11[1.2] ⟷ T9_10[2.2] ⟷ Bus10q

T10_11[2.1] ⟷ T6_11[2.1]  ⟷ Bus11d
T10_11[2.2] ⟷ T6_11[2.2]  ⟷ Bus11q

end



Ynode,nodelist_node,omegas=make_y_node(IEEE14bus,freq_range = (min_f,max_f,n_f))
Yedge,nodelist_edge,omegas=make_y_edge(IEEE14bus,nodelist=nodelist_node,freq_range = (min_f,max_f,n_f))
loopgain=inv.(Yedge).*Ynode
Zcl_bus = inv.(Yedge + Ynode)


######################################################################################################################################################################

# Nice plotting for Nyquist 🤔🧠😌
nyquistplot(loopgain,omegas,zoom = "yes", SM = "PM")
file_name="01_14_2026_fig2"

width = 3.5/2                     #width in inches
xlims = (-2.0, -0.8)
ylims = (-0.6, 0.6)
fontsize=6
legfontsize=4


default(fontfamily= "Computer Modern", xguidefontsize=fontsize,yguidefontsize=fontsize,
        tickfontsize=fontsize,titlefontsize=fontsize,legendfontsize=legfontsize)
width_px = Int(round(width* 100))  # Determining pixels, dpi of 100 is default
height_px = Int(round(width* 100)) # Determining pixels, dpi of 100 is default



# Tweak the plot we get from the Nyquist function
# By doing this in this script we dont need to touch the nqyuist function 🐦‍⬛🦩
# Uncomment unstable frequencies for that TODO: DO smarter with keyword argument 
gfa=current()
plot!(gfa, xlabel = L"\Re\{Λ_{i}(\mathbf{L})\}", ylabel = L"\Im\{Λ_{i}(\mathbf{L})\}", size=(width_px,height_px), 
legend=:none,xlims = xlims, ylims = ylims, title="", left_margin=-3Plots.mm,
right_margin=0Plots.mm,
top_margin=0Plots.mm,
bottom_margin=-4Plots.mm)

# Adjust lineweights
for (idx,series) in enumerate(gfa.series_list)

gfa.series_list[idx].plotattributes[:linewidth]=0.8


end

display(gfa)
save_eps_inkscape(gfa, joinpath(storage_path,file_name * ".eps"),
inkscape_cmd=inkscape)

##################################################################################################################################################################

# Nice plotting for EVD
# Commenting out the other plots; Im, Re and combined plot in EVD fuction
EVD_IEEE14bus= EVD(Zcl_bus, omegas, min_f, max_f)


file_name="01_15_2026_fig1"

width =3.5                   #width in inches
height=1                  #height in inches
fontsize=6
legfontsize=2


default(fontfamily= "Computer Modern", xguidefontsize=fontsize,yguidefontsize=fontsize,
        tickfontsize=fontsize,titlefontsize=fontsize,legendfontsize=legfontsize)
width_px = Int(round(width* 100))  # Determining pixels, dpi of 100 is default
height_px = Int(round(height* 100)) # Determining pixels, dpi of 100 is default


gfa=current()


# Adjust lineweights
for (idx,series) in enumerate(gfa.series_list)

gfa.series_list[idx].plotattributes[:linewidth]=0.8


end



plot!(gfa, xlabel = "Frequency [Hz]", ylabel = L"Λ_{i}(\mathbf{Z_{cl}}) [dB]", size=(width_px,height_px), 
legend=:none, title="", left_margin=0Plots.mm,
right_margin=0Plots.mm,
top_margin=0Plots.mm,
bottom_margin=2Plots.mm,xticks = ([1,10,100,1000], [10^0, 10^1, 10^2, 10^3,]))

# Hacking the oscillation frequency into it 🥲
annotate!(gfa,10,70,"83.1 Hz")
gfa.subplots[1].attr[:annotations][1][3].font.pointsize=fontsize

display(gfa)
save_eps_inkscape(gfa, joinpath(storage_path,file_name * ".eps"),
inkscape_cmd=inkscape)
########################################################################################################################################################

# Plotting of PFs for unstable mode 
# Double-check whether the PFs are picked at 83.1 Hz from the EVD :)

file_name="01_16_2026_fig1"

width =3.5                   #width in inches
height=1.0                   #height in inches
fontsize=6
legfontsize=2


default(fontfamily= "Computer Modern", xguidefontsize=fontsize,yguidefontsize=fontsize,
        tickfontsize=fontsize,titlefontsize=fontsize,legendfontsize=legfontsize)
width_px = Int(round(width* 100))  # Determining pixels, dpi of 100 is default
height_px = Int(round(height* 100)) # Determining pixels, dpi of 100 is default





[0.0, 0.0, 0.0, 0.04, 0.06, 0.0, 0.11, 0.14, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.19, 0.07, 0.09, 0.08, 0.1]
pfs=[0.0, 0.0, 0.0, 0.04, 0.06, 0.0, 0.11, 0.14, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.19, 0.07, 0.09, 0.08, 0.1]
str_vec = string.(nodelist_node)
node_labels = [replace(string(s), "Bus" => "") for s in str_vec]

pf_dq_bus=[]
str_vec_dq=[]

# Sum PFs of dq buses together to reduce the width of the figure :)
for (idx,pf) in enumerate(pfs)

        
        if occursin("d", node_labels[idx]) 


                push!(pf_dq_bus, pfs[idx]+pfs[idx+1])
                dq_bus=replace(node_labels[idx],"d"=>"")
                push!(str_vec_dq, dq_bus) 

        elseif occursin("q", node_labels[idx]) 
        # Already taken care of because nodeordering is d.....q....DC

        elseif occursin("DC", node_labels[idx]) 
        

                if node_labels[idx]=="DC1"

                        dq_bus=replace(node_labels[idx],"DC1"=>"15")

                elseif node_labels[idx]=="DC2"

                        dq_bus=replace(node_labels[idx],"DC2"=>"17")

                elseif node_labels[idx]=="DC3"

                        dq_bus=replace(node_labels[idx],"DC3"=>"16")
                
                elseif node_labels[idx]=="DC4"

                        dq_bus=replace(node_labels[idx],"DC4"=>"18")


                end

                push!(pf_dq_bus, pfs[idx])
                push!(str_vec_dq, dq_bus) 

                
        end



end

# Sorting the Buses in ascending order 
indices=sortperm([parse(Int,x) for x in str_vec_dq])
str_vec_dq=str_vec_dq[A]
pf_dq_bus=pf_dq_bus[A]



default(fontfamily= "Computer Modern", xguidefontsize=fontsize,yguidefontsize=fontsize,
        tickfontsize=fontsize,titlefontsize=fontsize,legendfontsize=legfontsize)
width_px = Int(round(width* 100))  # Determining pixels, dpi of 100 is default
height_px = Int(round(height* 100)) # Determining pixels, dpi of 100 is default


bar_PFs=plot(bar(str_vec_dq,pf_dq_bus))
plot!(bar_PFs,size=(width_px,height_px), xlabel="Bus",ylabel= L"PFs [pu]",legend=false, color=:green)


save_eps_inkscape(bar_PFs, joinpath(storage_path,file_name * ".eps"),
inkscape_cmd=inkscape)