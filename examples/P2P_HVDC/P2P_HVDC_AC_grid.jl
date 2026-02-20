# This is a PowerImpedanceACDC implementation of a Point-to-Point HVDC system connected to AC grids at both ends.
# Based on the P2P_HVDC, extended AC grid for Cigre 2026 paper
# Author: Jan Kircheis ⛪🍦
# Date: 17.12.2025


# Setting up the environment
using PowerImpedanceACDC
using SymEngine
using Plots #;plotlyjs() #Set PlotlyJS backend, installed in local Julia environment !

# Set default plot settings for powerpoint-like, paper-like figures
# Have an additional margin to prevent label cutoff when resizing figures
fontsize=24
legfontsize=14
default(fontfamily= "Computer Modern", xguidefontsize=fontsize,yguidefontsize=fontsize,
        tickfontsize=fontsize,titlefontsize=fontsize,legendfontsize=legfontsize,margin=12Plots.mm)






# Setting up power system
transmissionVoltage = 380 / sqrt(3)
# The P and Q defined here are what is injected into the network. 
pHVDC1 = 600
qC1 = 0
qC2 = 300
s=symbols("s")


#####-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Analytical grid model
net = @network begin

        voltageBase = transmissionVoltage
    
        # AC grids
        g1 = ac_source(V = 0.9*transmissionVoltage, pins = 3, transformation = true)
        Zg1=impedance(z=1+s*0.03, pins=3, transformation=true)
        g2 = ac_source(V = transmissionVoltage, pins = 3, transformation = true)
        Zg2=impedance(z=1+s*0.01, pins=3, transformation=true)
        g3 = ac_source(V = transmissionVoltage, pins = 3, transformation = true)
        Zg3=impedance(z=1+s*0.01, pins=3, transformation=true)
                                
        # HVDC link 1
        # MMC1 controls the DC voltage, and is situated at the remote end.
        c1 = mmc(Vᵈᶜ = 800, vDCbase = 800, 
                P = -pHVDC1, Q = qC1,
                occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
                ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
                pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
                q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
                #dc = PI_control(Kₚ = 100, Kᵢ = 15),
                dc = PI_control(Kₚ = 5, Kᵢ = 15),
                # timeDelay=200e-6, padeOrderDen=5, padeOrderNum=5
                )
        # MMC2 controls P&Q. It is connected to bus 6. Define the transformer impedance parameters at the converter side!
        c2 = mmc(Vᵈᶜ = 800, vDCbase = 800, 
                P = pHVDC1, Q = qC2,
                vACbase_LL_RMS = 333, turnsRatio = 333/380, Lᵣ = 0.0461, Rᵣ = 0.4103,
                occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
                ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
                pll = PI_control(Kₚ = 7, Kᵢ = 12.5664,ω_f = 2*pi*50,n_f=1),
                #pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
                #pll = PI_control(Kₚ = 5, Kᵢ = 12.5664,ω_f = 2*pi*50,n_f=1),
                p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
                q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159)
                )
        # DC cable between the two converters
        dc_line = cable(length = 100e3, positions = [(-0.5,1), (0.5,1)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)


        # c1 side of the power system (DC-MMC) 
        tl1 = overhead_line(length = 25e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
        tl2 = overhead_line(length = 25e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
        tl3 =overhead_line(length = 50e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)



        # c2 side of the power system (PQ-MMC)    
        tl67 = overhead_line(length = 90e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)

        # tl67_2 = overhead_line(length = 80e3,
        # conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
        #                 Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        # groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        # earth_parameters = (1,1,100), transformation = true)



        # AC-side grid connection c1
        g3[1.1] ⟷ Zg3[1.1] ⟷ Bg3d
        g3[1.2] ⟷ Zg3[1.2] ⟷ Bg3q

        g2[1.1] ⟷ Zg2[1.1] ⟷ Bg2d
        g2[1.2] ⟷ Zg2[1.2] ⟷ Bg2q

        g3[2.1] ⟷ gndD
        g3[2.2] ⟷ gndQ

        g2[2.1] ⟷ gndD
        g2[2.2] ⟷ gndQ

        c1[2.1] ⟷ tl3[2.1] ⟷ tl2[2.1] ⟷ B3d
        c1[2.2] ⟷ tl3[2.2] ⟷ tl2[2.2] ⟷ B3q

        Zg2[2.1] ⟷ tl2[1.1] ⟷ tl1[2.1] ⟷ B2d
        Zg2[2.2] ⟷ tl2[1.2] ⟷ tl1[2.2] ⟷ B2q

        Zg3[2.1] ⟷ tl1[1.1] ⟷ tl3[1.1] ⟷ B1d
        Zg3[2.2] ⟷ tl1[1.2] ⟷ tl3[1.2] ⟷ B1q

        
        # DC grid
        c1[1.1] ⟷ dc_line[1.1] ⟷ B4
        c2[1.1] ⟷ dc_line[2.1] ⟷ B5

        # AC-grid side connection c2
        c2[2.1] == tl67[1.1] ==  B6d#tl67_2[1.1]  == # 
        c2[2.2] == tl67[1.2]  == B6q #tl67_2[1.2] == #  

        Zg1[2.1] ⟷ tl67[2.1]  ⟷ B7d #tl67_2[2.1]⟷ # #
        Zg1[2.2] ⟷ tl67[2.2] ⟷  B7q #tl67_2[2.2] ⟷ # #

        g1[1.1] == Zg1[1.1] == B8d
        g1[1.2] == Zg1[1.2] == B8q

        g1[2.1] == gndd
        g1[2.2] == gndq



end


# Stability analysis
ynode,nodelist,omegas=make_y_node(net,freq_range = (1,1e3, 2000))
yedge,nodelist,omegas=make_y_edge(net,nodelist=nodelist,freq_range = (1,1e3, 2000))
loop=inv.(yedge).*ynode
nyquistplot(loop,omegas,zoom = "yes", SM = "GM", title  = "Analytical models - One OHL connected")
# Zcl=inv.(ynode+yedge)
# EVD_Energy_Hu1b = EVD(Zcl, omegas, 1, 5e3)




# # Case 1: PLL induced instability at c2 (PQ-MMC). PSCAD validated ✔️
# # Base case stable with pll = PI_control(Kₚ = 7, Kᵢ = 12.5664,ω_f = 2*pi*50,n_f=1) and
# # Both AC OHL lines (80 & 90 km) connected between c2 and g1 (lower grid impedance)
# # Change to unstable case by disconnecting the 80 km line :)
# # pHVDC1 = 500
# # qC1 = 0
# # qC2 = 0


# # Case 2: PLL induced instability at c2 (PQ-MMC), change of OP. PSCAD validated ✔️
# # pHVDC1 = 600
# # qC1 = 0
# # qC2 = 300
# # Base case stable with pll = PI_control(Kₚ = 7, Kᵢ = 12.5664,ω_f = 2*pi*50,n_f=1) and
# # Both AC OHL lines (80 & 90 km) connected between c2 and g1 (lower grid impedance)
# # Change to unstable case by disconnecting the 80 km line :)




#############-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\
# Grid with black box MMC converter
#############-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------/





grid = @network begin

        voltageBase = transmissionVoltage
    
        # AC grids
        g1 = ac_source(V = 0.9*transmissionVoltage, pins = 3, transformation = true)
        Zg1=impedance(z=1+0.03*s, pins=3, transformation=true)
        g2 = ac_source(V = transmissionVoltage, pins = 3, transformation = true)
        Zg2=impedance(z=1+0.01*s, pins=3, transformation=true)
        g3 = ac_source(V = transmissionVoltage, pins = 3, transformation = true)
        Zg3=impedance(z=1+0.01*s, pins=3, transformation=true)
                                
        # HVDC link 1
        # MMC1 controls the DC voltage, and is situated at the remote end.
        c1 = mmc(Vᵈᶜ = 800, vDCbase = 800, 
                P = -pHVDC1, Q = qC1,
                occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
                ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
                pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
                q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
                #dc = PI_control(Kₚ = 100, Kᵢ = 15),
                dc = PI_control(Kₚ = 5, Kᵢ = 15),
                # timeDelay=200e-6, padeOrderDen=5, padeOrderNum=5
                )
        # MMC2 controls P&Q. It is connected to bus 6. 
        c2 = blackbox_MMC(Vᵈᶜ = 800, vDCbase = 800, vACbase=380,
                P = pHVDC1, Q = qC2,
                p=PI_control(), # Empty controller necessary for the powerflow function to detect operting mode of the MMC :)
                q=PI_control(), 
                path_f = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Scripts\\Julia\\30_12_2025_run1_f.txt",
                path_MMC = "C:\\Users\\jkirchei\\OneDrive - KU Leuven\\Documents\\PhD Project\\Work package 2\\Scripts\\Julia\\30_12_2025_run1.txt"
                )


        # DC cable between the two converters
        dc_line = cable(length = 100e3, positions = [(-0.5,1), (0.5,1)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)


        # c1 side of the power system (DC-MMC) 
        tl1 = overhead_line(length = 25e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
        tl2 = overhead_line(length = 25e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
        tl3 =overhead_line(length = 50e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)



        # c2 side of the power system (PQ-MMC)    
        tl67 = overhead_line(length = 90e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)

        # tl67_2 = overhead_line(length = param,
        # conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
        #                 Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        # groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        # earth_parameters = (1,1,100), transformation = true)



        # AC-side grid connection c1
        g3[1.1] ⟷ Zg3[1.1] ⟷ Bg3d
        g3[1.2] ⟷ Zg3[1.2] ⟷ Bg3q

        g2[1.1] ⟷ Zg2[1.1] ⟷ Bg2d
        g2[1.2] ⟷ Zg2[1.2] ⟷ Bg2q

        g3[2.1] ⟷ gndD
        g3[2.2] ⟷ gndQ

        g2[2.1] ⟷ gndD
        g2[2.2] ⟷ gndQ

        c1[2.1] ⟷ tl3[2.1] ⟷ tl2[2.1] ⟷ B3d
        c1[2.2] ⟷ tl3[2.2] ⟷ tl2[2.2] ⟷ B3q

        Zg2[2.1] ⟷ tl2[1.1] ⟷ tl1[2.1] ⟷ B2d
        Zg2[2.2] ⟷ tl2[1.2] ⟷ tl1[2.2] ⟷ B2q

        Zg3[2.1] ⟷ tl1[1.1] ⟷ tl3[1.1] ⟷ B1d
        Zg3[2.2] ⟷ tl1[1.2] ⟷ tl3[1.2] ⟷ B1q

        
        # DC grid
        c1[1.1] ⟷ dc_line[1.1] ⟷ B4
        c2[1.1] ⟷ dc_line[2.1] ⟷ B5

        # AC-grid side connection c2
        c2[2.1] == tl67[1.1] == B6d #tl67_2[1.1] == 
        c2[2.2] == tl67[1.2] ==  B6q#tl67_2[1.2] == 

        Zg1[2.1] ⟷ tl67[2.1] ⟷  B7d# tl67_2[2.1] == 
        Zg1[2.2] ⟷ tl67[2.2] ⟷  B7q#tl67_2[2.2] ==
        g1[1.1] == Zg1[1.1] == B8d
        g1[1.2] == Zg1[1.2] == B8q

        g1[2.1] == gndd
        g1[2.2] == gndq



end


# Stability analysis
ynode,nodelist,omegas=make_y_node(grid,freq_range = (1,1e3, 2000))
yedge,nodelist,omegas=make_y_edge(grid,nodelist=nodelist,freq_range = (1,1e3, 2000))
loop=inv.(yedge).*ynode
nyquistplot(loop,omegas,zoom = "yes", SM = "GM", title  = " One OHL connected")


########################################################################################################################################################################################################
# Compare admittances of black-box MMC with analytical MMC model
########################################################################################################################################################################################################


freq_Y_MMC= collect(range(1, stop=1000, step=0.2))

Y_MMC1_anl= []
Y_dd_anl = []
Y_dq_anl = []
Y_qd_anl = []
Y_qq_anl = []
Y_dc_anl = []
for i in 1:length(freq_Y_MMC)
    Y1 = eval_abcd(net.elements[:c2].element_value, 1im*2*pi*freq_Y_MMC[i]) 
    push!(Y_MMC1_anl, [transpose(Y1[1,:]); transpose(-Y1[2,:]); transpose(-Y1[3,:])]) # Keep sign of Ydc, swapping sign of Yacs
    push!(Y_dd_anl, -Y1[2,2]) 
    push!(Y_qd_anl, -Y1[3,2]) 
    push!(Y_dq_anl, -Y1[2,3]) 
    push!(Y_qq_anl, -Y1[3,3]) 
    push!(Y_dc_anl, Y1[1,1])

end


bode_Y_MMC=bodeplot(Y_MMC1_anl, 2*pi.*freq_Y_MMC, legend = [L"Ydcdc",L"Ydcd",L"Ydcq",L"Yddc",L"Ydd",L"Ydq",L"Yqdc",L"Yqd",L"Yqq"]); # LaTeXStrings with "L" prefix. Requires --LaTeXStrings.jl--

# Plotting of complete Y_MMC matrix in one large plot
l_full= @layout [a b c; d e f; g h i] 
# Remove redundant labels for cleaner appearance
for i=1:9

    if i==1 || i==4 || i==7
        continue
    end

    bode_Y_MMC[i].subplots[2][:yaxis][:guide] = ""
    bode_Y_MMC[i].subplots[1][:yaxis][:guide] = ""

end

for i=1:9

    if i==7 || i==8 || i==9
        continue
    end

    bode_Y_MMC[i].subplots[2][:xaxis][:guide] = ""

end




# Get blackbox data 😌😌

Y_MMC1_bb= []
Y_dd_bb = []
Y_dq_bb = []
Y_qd_bb = []
Y_qq_bb = []
Y_dc_bb = []
for i in 1:length(freq_Y_MMC)

    Y1=eval_abcd(grid.elements[:c2].element_value,1im*2*pi*freq_Y_MMC[i])
    push!(Y_MMC1_bb,Y1)
    push!(Y_dd_bb, Y1[2,2]) 
    push!(Y_qd_bb, Y1[3,2]) 
    push!(Y_dq_bb, Y1[2,3]) 
    push!(Y_qq_bb, Y1[3,3]) 
    push!(Y_dc_bb, Y1[1,1])
end

# Merge plots
# Ydcdc
plot!(bode_Y_MMC[1], freq_Y_MMC,20*log10.(abs.([Y[1,1] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1); # LaTeXStrings with "L" prefix. Requires --LaTeXStrings.jl--
plot!(bode_Y_MMC[1], freq_Y_MMC,angle.([Y[1,1] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2); # LaTeXStrings with "L" prefix. Requires --LaTeXStrings.jl--

# Ydcd
plot!(bode_Y_MMC[2],freq_Y_MMC, 20*log10.(abs.([Y[1,2] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1)
plot!(bode_Y_MMC[2],freq_Y_MMC, angle.([Y[1,2] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2)

# Ydcq
plot!(bode_Y_MMC[3],freq_Y_MMC, 20*log10.(abs.([Y[1,3] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1)
plot!(bode_Y_MMC[3],freq_Y_MMC, angle.([Y[1,3] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2)

# Yddc
plot!(bode_Y_MMC[4],freq_Y_MMC, 20*log10.(abs.([Y[2,1] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1)
plot!(bode_Y_MMC[4],freq_Y_MMC, angle.([Y[2,1] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2)

# Ydd
plot!(bode_Y_MMC[5],freq_Y_MMC, 20*log10.(abs.([Y[2,2] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1)
plot!(bode_Y_MMC[5],freq_Y_MMC, angle.([Y[2,2] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2)    

# Ydq
plot!(bode_Y_MMC[6],freq_Y_MMC, 20*log10.(abs.([Y[2,3] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1)
plot!(bode_Y_MMC[6],freq_Y_MMC, angle.([Y[2,3] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2)

# Yqdc
plot!(bode_Y_MMC[7],freq_Y_MMC, 20*log10.(abs.([Y[3,1] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1)
plot!(bode_Y_MMC[7],freq_Y_MMC, angle.([Y[3,1] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2)

# Yqd
plot!(bode_Y_MMC[8],freq_Y_MMC, 20*log10.(abs.([Y[3,2] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1)
plot!(bode_Y_MMC[8],freq_Y_MMC, angle.([Y[3,2] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2)

# Yqq
plot!(bode_Y_MMC[9],freq_Y_MMC, 20*log10.(abs.([Y[3,3] for Y in Y_MMC1_bb])), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=1)
plot!(bode_Y_MMC[9],freq_Y_MMC, angle.([Y[3,3] for Y in Y_MMC1_bb]).*(180/π), linewidth = :auto, linestyle = :auto,minorgrid=true, label="BB",subplot=2)

plot(bode_Y_MMC[1], bode_Y_MMC[2], bode_Y_MMC[3],bode_Y_MMC[4], bode_Y_MMC[5], bode_Y_MMC[6], bode_Y_MMC[7], bode_Y_MMC[8], bode_Y_MMC[9], layout = l_full, size = (1200, 1200))
# # Ydd