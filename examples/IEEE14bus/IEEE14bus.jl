# This is a PowerImpedanceACDC implementation of the modified IEEE 14 bus system test system
# Author: Jan Kircheis 
# Date: Sep 2025


function calc_RLC(S,V,component)
# Function to calculate resistance, inductance or capacitance of a 3-phase shunt load for a given 1-phase power S
# and phase-rms Voltage V 
# Discremination of component by string component "R", "L", "C"
        
        S=S*3 # Get 3-phase power
        if component == "R"

        R = V^2/S
        return R

        elseif component =="L"

        L= (V^2/S)/(2*pi*50)
        return L

        elseif component == "C"

        C=(S)/((V^2)*2*pi*50)
        return C
        else
        error("No implemented load component specified!")
        end

end
using PowerImpedanceACDC
using SymEngine
using XLSX
s = symbols("s")


# Operating points
P_MMC1=-1000
Q_MMC1= 0
P_MMC2=-1000
Q_MMC2=0
Q_MMC3=0.0
Q_MMC4=0.0
Pwf=600
Qwf=0


R_B2=calc_RLC(72.333,380,"R")
L_B2=calc_RLC(42.333,380,"L")
R_B5=calc_RLC(25.333,380,"R")
L_B5=calc_RLC(05.333,380,"L")
R_B3=calc_RLC(314,380,"R")
L_B3=calc_RLC(63.333,380,"L")
R_B4=calc_RLC(159.333,380,"R")
C_B4=calc_RLC(13.000,380,"C")
R_B12=calc_RLC(2.033,380,"R")
L_B12=calc_RLC(0.533,380,"L")
R_B13=calc_RLC(1.933,380,"R")
L_B13=calc_RLC(1.933,380,"L")
R_B14=calc_RLC(49.666,380,"R")
L_B14=calc_RLC(16.666,380,"L")
R_B9=calc_RLC(98.333,380,"R")
L_B9=calc_RLC(55.333,380,"L")
R_B10=calc_RLC(30.0,380,"R")
L_B10=calc_RLC(19.333,380,"L")
R_B11=calc_RLC(11.666,380,"R")
L_B11=calc_RLC(6,380,"L")
R_B6=calc_RLC(37.333,380,"R")
L_B6=calc_RLC(25.0,380,"L")
Vm=380/sqrt(3)

# Stability analysis options
min_f=0.001 # Minimum frequency in Hz
max_f=4e3 # Maximum frequency in Hz 
n_f=2000 # Number of frequency points in the


IEEE14bus = @network begin

voltageBase = Vm

# Sources
G1=ac_source(pins = 3, V = Vm, transformation = true)
G2=ac_source(pins = 3, V = Vm, transformation = true)
DC_WF1=dc_source(pins = 2, V = 320, transformation = true)
DC_WF2=dc_source(pins = 2, V = 320, transformation = true)
DC_WF3=dc_source(pins = 2, V = 320, transformation = true)
Zg1=impedance(z = 0.2874  + 0.0091*s, pins = 3, transformation = true) # Bottom area
Zg2=impedance(z = 1.026 + 1*0.0327*s, pins = 3, transformation = true) # Top area


#Converters

# MMC1: ✅ matching! Double-check parameters again and push base case of the new system
 MMC1 = mmc(Vᵈᶜ = 640, vDCbase = 640, Sbase = 1000, vACbase_LL_RMS = 333, turnsRatio = 333/380, Vₘ = Vm, Lᵣ = 0.18 * (333^2/1000) /2/pi/50, Rᵣ = 0.001 *(333^2/1000),
        P = P_MMC1, Q = Q_MMC1,  P_max = 1500, P_min = -1500, Q_max = 500, Q_min = -500,
        Rₐᵣₘ = 0.4,Lₐᵣₘ = 46.125e-3,Cₐᵣₘ = 11.3867e-3,N = 400,
        occ = PI_control(Kₚ = 0.6532, Kᵢ = 281.1370,n_f= 2,ω_f=200*2*pi),
        ccc = PI_control(Kₚ = 0.0936, Kᵢ = 40.5396),
        zcc = PI_control(Kₚ = 0.0936, Kᵢ = 40.5396),
        energy = PI_control(Kₚ = 1.469, Kᵢ = 31.4819),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664, n_f= 1,ω_f=75*2*pi),
        q = PI_control(Kₚ = 0.0, Kᵢ = 3, n_f = 2,ω_f = 140*2*pi),
        p = VSE(H = 5,K_d = 100,K_ω = 10,ref_ω = 1, n_f = 2,ω_f = 140*2*pi),
        VI= CCQSEM(Rᵥ = 0.01,Lᵥ = 0.25,ref_vd = 1,ref_vq = 0,n_f = 2,ω_f =200 ), gfm= true, timeDelay=200e-6, padeOrderNum=5, padeOrderDen=5) 

# PQ ✅ matching!
MMC2=mmc(Vᵈᶜ = 640, vDCbase = 640, Sbase = 1000, vACbase_LL_RMS = 333, turnsRatio = 333/380, Vₘ = Vm, Lᵣ = 0.18 * (333^2/1000) /2/pi/50, Rᵣ = 0.001 *(333^2/1000),
        P = P_MMC2, Q = Q_MMC2,  P_max = 1500, P_min = -1500, Q_max = 500, Q_min = -500,
        Rₐᵣₘ = 0.4,Lₐᵣₘ = 46.125e-3,Cₐᵣₘ = 11.3867e-3,N = 400,
        occ = PI_control(Kₚ = 0.6532, Kᵢ = 281.1370,n_f= 2,ω_f=400*2*pi),
        ccc = PI_control(Kₚ = 0.0936, Kᵢ = 40.5396),
        zcc = PI_control(Kₚ = 0.0936, Kᵢ = 40.5396),
        energy = PI_control(Kₚ = 1.469, Kᵢ = 31.4819),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664, n_f= 1,ω_f=75*2*pi),
        q = PI_control(Kₚ = 0.0, Kᵢ = 3, n_f = 2,ω_f = 140*2*pi),
        p = VSE(H = 5,K_d = 100,K_ω = 10,ref_ω = 1, n_f = 2,ω_f = 140*2*pi),
        VI= CCQSEM(Rᵥ = 0.0,Lᵥ = 0.4,ref_vd = 1,ref_vq = 0,n_f = 2,ω_f =200), gfm= true, timeDelay=200e-6, padeOrderNum=5, padeOrderDen=5) 
#Vdc ✅ matching!
MMC3=mmc(Vᵈᶜ = 640 , vDCbase = 640, Sbase = 1000, vACbase_LL_RMS = 333, turnsRatio = 333/380, Vₘ = Vm, Lᵣ = 0.1305*(333^2/1000)/2/pi/50, Rᵣ = 0.0037*(333^2/1000),
        Q = Q_MMC3, P_max = 1500, P_min = -1500, Q_max = 500, Q_min = -500,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        zcc = PI_control(Kₚ = 0.0992, Kᵢ = 42.9719),
        energy = PI_control(Kₚ = 1.2894, Kᵢ = 27.63),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664), # Kᵢ = 12.5664
        dc = PI_control(Kₚ = 5, Kᵢ = 15),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159), timeDelay=200e-6, padeOrderNum=5, padeOrderDen=5
        #p= PI_control(Kₚ = 0.1, Kᵢ = 31.4159)
        )   
#Vdc ✅ matching!
MMC4=mmc(Vᵈᶜ = 640 , vDCbase = 640, Sbase = 1000, vACbase_LL_RMS = 333, turnsRatio = 333/380, Vₘ = Vm, Lᵣ = 0.1305*(333^2/1000)/2/pi/50, Rᵣ = 0.0037*(333^2/1000),
        Q = Q_MMC4,P_max = 1500, P_min = -1500, Q_max = 500, Q_min = -500,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        zcc = PI_control(Kₚ = 0.0992, Kᵢ = 42.9719),
        energy = PI_control(Kₚ = 1.2894, Kᵢ = 27.63),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        #pll = PI_control(Kₚ = 1.5, Kᵢ = 314.15),
        dc = PI_control(Kₚ = 5, Kᵢ = 15),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159), timeDelay=200e-6, padeOrderNum=5, padeOrderDen=5
        #p= PI_control(Kₚ = 0.1, Kᵢ = 31.4159)
        )   
# ✅ matching!
WF1= tlc(Vᵈᶜ = 640, Vₘ = Vm, Lᵣ =0.08*(380^2/600)/2/pi/50, Rᵣ = 0.0008*(380^2/600), 
        Sbase = 600, vACbase_LL_RMS = 380, 
        P = Pwf, Q = Qwf,
        occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8), 
        pll = PI_control(Kₚ = 3, Kᵢ = 38.5155, ω_f = 2*pi*80,n_f=1), # These PLL gains result in an instability in PSCAD. 
        #pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = 2*pi*80,n_f=1),
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
        pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = 2*pi*80,n_f=1),
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
        pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = 2*pi*80,n_f=1),
        v_meas_filt = PI_control(ω_f = 1e4,n_f=1), 
        i_meas_filt = PI_control(ω_f = 1e4,n_f=1),
        #vac_supp = PI_control(ω_f = 1/0.5, Kₚ =10),
        #f_supp = PI_control(ω_f = 1/0.5, Kₚ =10),
        p = PI_control(Kₚ = 0.01, Kᵢ = 10), 
        q = PI_control(Kₚ = 0.01, Kᵢ = 10), #timeDelay=200e-6, padeOrderDen=5, padeOrderNum=5
        )



# Overhead lines
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

T2_4 = overhead_line(length = 100e3,
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

T6_11 = overhead_line(length = 5e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)


T10_11 = overhead_line(length = 5e3,
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

T9_10 = overhead_line(length = 5e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
T7_9 = overhead_line(length = 5e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
# T7_8 = overhead_line(length = 100e3,
#         conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
#                         Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
#         groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
#         earth_parameters = (1,1,100), transformation = true)

# Cables
# Validated against PSCAD: ✅, rided semicons to improve match
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
# Modeled as shunt branch with resistance and inductance/capacitance

#LoadB2

LoadB2= impedance(z = 1/((1/R_B2)+(1/(s*L_B2))), pins = 3, transformation = true)

#LoadB5

LoadB5= impedance(z = 1/((1/R_B5)+(1/(s*L_B5))), pins = 3, transformation = true)

# LoadB3

LoadB3= impedance(z = 1/((1/R_B3)+(1/(s*L_B3))), pins = 3, transformation = true)

# LoadB4

LoadB4= impedance(z = 1/((1/R_B4)+(s*C_B4)), pins = 3, transformation = true)

# LoadB12

#LoadB12= impedance(z = 1/((1/R_B12)+(1/(s*L_B12))), pins = 3, transformation = true)

# LoadB13

#LoadB13= impedance(z = 1/((1/R_B13)+(1/(s*L_B13))), pins = 3, transformation = true)

# LoadB14

#LoadB14= impedance(z = 1/((1/R_B14)+(1/(s*L_B14))), pins = 3, transformation = true)


# LoadB9

#LoadB9= impedance(z = 1/((1/R_B9)+(1/(s*L_B9))), pins = 3, transformation = true)


# LoadB10

#LoadB10= impedance(z = 1/((1/R_B10)+(1/(s*L_B10))), pins = 3, transformation = true)

# LoadB11

#LoadB11= impedance(z = 1/((1/R_B11)+(1/(s*L_B11))), pins = 3, transformation = true)


# LoadB6

LoadB6= impedance(z = 1/((1/R_B6)+(1/(s*L_B6))), pins = 3, transformation = true)




# Connections

# Load grounding
LoadB2[2.1] ⟷ gndD
LoadB2[2.2] ⟷ gndQ

LoadB5[2.1] ⟷ gndD
LoadB5[2.2] ⟷ gndQ

LoadB3[2.1] ⟷ gndD
LoadB3[2.2] ⟷ gndQ

LoadB4[2.1] ⟷ gndD
LoadB4[2.2] ⟷ gndQ

# LoadB12[2.1] ⟷ gndD
# LoadB12[2.2] ⟷ gndQ

# LoadB13[2.1] ⟷ gndD
# LoadB13[2.2] ⟷ gndQ

# LoadB14[2.1] ⟷ gndD
# LoadB14[2.2] ⟷ gndQ

# LoadB9[2.1] ⟷ gndD
# LoadB9[2.2] ⟷ gndQ

# LoadB10[2.1] ⟷ gndD
# LoadB10[2.2] ⟷ gndQ

# LoadB11[2.1] ⟷ gndD
# LoadB11[2.2] ⟷ gndQ

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

T2_3[1.1] ⟷ T2_4[1.1] ⟷ T2_5[1.1] ⟷ T1_2[2.1]  ⟷ LoadB2[1.1] ⟷ Bus2d
T2_3[1.2] ⟷ T2_4[1.2] ⟷ T2_5[1.2] ⟷ T1_2[2.2]  ⟷ LoadB2[1.2] ⟷ Bus2q

T2_3[2.1] ⟷ T3_4[1.1] ⟷ LoadB3[1.1] ⟷ Bus3d
T2_3[2.2] ⟷ T3_4[1.2] ⟷ LoadB3[1.2] ⟷ Bus3q

T4_5[1.1] ⟷ T2_4[2.1] ⟷ T3_4[2.1] ⟷ LoadB4[1.1] ⟷ MMC4[2.1] ⟷ Bus4d
T4_5[1.2] ⟷ T2_4[2.2] ⟷ T3_4[2.2] ⟷ LoadB4[1.2] ⟷ MMC4[2.2] ⟷ Bus4q

T4_5[2.1] ⟷ T2_5[2.1] ⟷ T1_5[2.1] ⟷ LoadB5[1.1] ⟷ MMC3[2.1] ⟷ Bus5d
T4_5[2.2] ⟷ T2_5[2.2] ⟷ T1_5[2.2] ⟷ LoadB5[1.2] ⟷ MMC3[2.2] ⟷ Bus5q

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

Zg2[2.1] ⟷ MMC1[2.1] ⟷ T6_12[1.1] ⟷ T6_13[1.1] ⟷ T6_11[1.1] ⟷ LoadB6[1.1] ⟷ Bus6d
Zg2[2.2] ⟷ MMC1[2.2] ⟷ T6_12[1.2] ⟷ T6_13[1.2] ⟷ T6_11[1.2] ⟷ LoadB6[1.2] ⟷ Bus6q

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
loopgain=convert(Vector{Matrix{ComplexF64}},loopgain)
nyquistplot(loopgain,omegas,zoom = "yes", SM = "GM", title  = "WF1 PLL-induced")

# Y_dd=[]
# Y_dq=[]
# Y_qd=[]
# Y_qq=[]
# Yseq=[]
# T= [1  1 ; -im  im]
# for i in 1:length(omegas)

#         Y=PowerImpedanceACDC.eval_parameters(IEEE14bus.elements[:MMC1].element_value,1*omegas[i]*im)
#         Ydq=[Y[2,2] -Y[2,3];     
#              -Y[3,2] Y[3,3]]
#         push!(Yseq,inv(T)*Ydq*T)
#         push!(Y_dd,Y[2,2])
#         push!(Y_dq,Y[2,3])
#         push!(Y_qd,Y[3,2])
#         push!(Y_qq,Y[3,3])
# end

# bodeplot(Y_dd,omegas)
# bodeplot(Y_dq,omegas)
# bodeplot(Y_qd,omegas)
# bodeplot(Y_qq,omegas)
# seq=bodeplot(Yseq,omegas)
Zcl_bus = inv.(Yedge + Ynode)

EVD_Energy_Hu1b = EVD(Zcl_bus, omegas, min_f, max_f)

# imp_ac, omega_ac = determine_impedance(IEEE14bus, elim_elements=[:MMC2], input_pins=Any[:Bus7d,:Bus7q], 
# output_pins=Any[:gndD,:gndQ], freq_range = (100,5000,1000))

# T= [1  1 ; -im  im]

# Y_dd=[]
# Z_seq=[]
# Z_pp=[]
# for i in 1:length(omega_ac)
#         push!(Y_dd,imp_ac[i][1,1])

#         dummy=[imp_ac[i][1,1] -imp_ac[i][1,2];-imp_ac[i][2,1] imp_ac[i][2,2]]
#         Zseq=inv(T)*dummy*T
#         push!(Z_seq,Zseq)
#         push!(Z_pp,Zseq[1,1])
# end



# testDCcables = @network begin

# voltageBase = Vm

# # Sources
# G1=ac_source(pins = 3, V = Vm, transformation = true)

# OHL_Julia=overhead_line(length = 100e3,
#         conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
#                         Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
#         groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
#         earth_parameters = (1,1,100), transformation = true)

#         G1[2.1] ⟷ gndD
#         G1[2.2] ⟷ gndQ
#         G1[1.1] ⟷ OHL_Julia[1.1]
#         G1[1.2] ⟷ OHL_Julia[1.2]
#         OHL_Julia[2.1] ⟷ gndD
#         OHL_Julia[2.2] ⟷ gndQ


# end


# DC cable validation with PSCAD
# path=data_path="C://Users//jkirchei//OneDrive - KU Leuven//Documents//PhD Project//Source//EMT//model17//ieee_14_bus_GFM_Jan.gf46//CableDC23"
# testDCcables = Network()

# add!(testDCcables, :dc_line_PSCAD, blackbox_line(n=2,data_type=:PSCAD,length=200e3,
#                         path=data_path,transformation=true))



# add!(testDCcables,:dc_line_Julia,cable(length = 200e3, positions = [(0,1.5), (1,1.5)],
#     C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
#     I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
#     C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
#     I2 = Insulator(rᵢ = 55.4e-3, rₒ = 6.12e-3, ϵᵣ = 2.3), transformation = true))

# omegas =  2*pi* 10 .^range(log10(0.1), log10(1e3), length= 1000) 

# Zser_PSCAD=[]
# Zser_Julia=[]

# Y_PSCAD=[]
# Y_Julia=[]

# for omega in omegas
        
#         push!(Zser_PSCAD,PowerImpedanceACDC.eval_parameters(testDCcables.elements[:dc_line_PSCAD].element_value,1*im*omega)[1][1])
#         push!(Zser_Julia,PowerImpedanceACDC.eval_parameters(testDCcables.elements[:dc_line_Julia].element_value,1*im*omega)[1][1])
#         push!(Y_PSCAD,PowerImpedanceACDC.get_y(testDCcables.elements[:dc_line_PSCAD],1*im*omega)[1,1])
#         push!(Y_Julia,PowerImpedanceACDC.get_y(testDCcables.elements[:dc_line_Julia],1*im*omega)[1,1])
# end

# display(bodeplot(Y_PSCAD,omegas,legend="PSCAD"))
# display(bodeplot(Y_Julia,omegas,legend="Julia"))

# display(bodeplot(Zser_PSCAD,omegas,legend="PSCAD Zser"))
# display(bodeplot(Zser_Julia,omegas,legend="Julia Zser"))







# 09.23.2025: Evaluate match with PSCAD with respect of the stability
# Case 1: Varying the delays of MMC2: t=250 us, 280 us, 300 us, 310 us
# Oscillation more in the 100 Hz range --> Current controller interacts with the delay
# t=250 us: Stable --> PSCAD stable
# t=280 us: Stable --> PSCAD stable
# t=300 us: Stable --> PSCAD unstable
# t=310 us: Unstable --> PSCAD unstable
#
# Case 2: Keeping the delay of MMC2 at t=280 us, vary the load at Bus B9
# Rid R_B9 --> Unstable --> PSCAD unstable
# Rid R_B9 & L_B9 --> Unstable --> PSCAD unstable








#Debugging powerflow. PSCAD results in Labnotebook WP2 
# 09.16.2025
# With powerflow fixes:
# P_MMC1=0.0
# Q_MMC1=0.0
# P_MMC2=0
# Q_MMC2=0.0
# Q_MMC3=300.0
# Q_MMC4=500.0

# LOCALLY_SOLVED
# Starting to solve for Steady-State Solution!
# MMC steady-state solution found!
# 1 Active Power [MW]: 6.114065455820066e-10
# 1 Reactive Power [MVar]: 6.098935663675533e-18
# 1 AC Voltage Magnitude [pu]: 0.9910942425464588
# 1 AC Voltage Angle [rad]: -0.030981420711136496
# 1 DC Voltage [kV]: 640.0000000000041
# Starting to solve for Steady-State Solution!
# MMC steady-state solution found!
# 2 Active Power [MW]: 8.311698419888077e-5
# 2 Reactive Power [MVar]: -3.986997274885765e-5
# 2 AC Voltage Magnitude [pu]: 0.9231394906435596
# 2 AC Voltage Angle [rad]: -0.21201526630325768
# 2 DC Voltage [kV]: 640.0000005514787
# Starting to solve for Steady-State Solution!
# MMC steady-state solution found!
# 3 Active Power [MW]: -0.7501460060568431       
# 3 Reactive Power [MVar]: -300.0
# 3 AC Voltage Magnitude [pu]: 1.0113182606664906
# 3 AC Voltage Angle [rad]: -0.3335121823283423  
# 3 DC Voltage [kV]: 640.0
# Starting to solve for Steady-State Solution!
# MMC steady-state solution found!
# 4 Active Power [MW]: -2.050538839546767
# 4 Reactive Power [MVar]: -500.0
# 4 AC Voltage Magnitude [pu]: 1.0194558583184579
# 4 AC Voltage Angle [rad]: -0.4856591146865801
# 4 DC Voltage [kV]: 640.0
# Good match with PSCAD 🔨🔨


# P_MMC1=500
# Q_MMC1=0.0
# P_MMC2=0
# Q_MMC2=0.0
# Q_MMC3=300.0
# Q_MMC4=500.0

# MMC steady-state solution found!
# 1 Active Power [MW]: 500.0
# 1 Reactive Power [MVar]: -2.4590937187914374e-16
# 1 AC Voltage Magnitude [pu]: 0.9940335530227677 
# 1 AC Voltage Angle [rad]: -0.006008037579977978 
# 1 DC Voltage [kV]: 636.8633328433635
# Starting to solve for Steady-State Solution!    
# MMC steady-state solution found!
# 2 Active Power [MW]: -7.560875973404649e-6     
# 2 Reactive Power [MVar]: 1.0224029208401247e-6 
# 2 AC Voltage Magnitude [pu]: 0.9258772422928434
# 2 AC Voltage Angle [rad]: -0.187041964621589   
# 2 DC Voltage [kV]: 640.0000006455141
# Starting to solve for Steady-State Solution!   
# MMC steady-state solution found!
# 3 Active Power [MW]: -506.3461306418194       
# 3 Reactive Power [MVar]: -300.0
# 3 AC Voltage Magnitude [pu]: 0.965029462088033
# 3 AC Voltage Angle [rad]: -0.45833758159755805
# 3 DC Voltage [kV]: 640.0
# Starting to solve for Steady-State Solution!  
# MMC steady-state solution found!
# 4 Active Power [MW]: -2.2143959571338496
# 4 Reactive Power [MVar]: -500.0
# 4 AC Voltage Magnitude [pu]: 0.9810126483193679
# 4 AC Voltage Angle [rad]: -0.5883991290427185
# 4 DC Voltage [kV]: 640.0
# Good match with PSCAD 🔨🔨

