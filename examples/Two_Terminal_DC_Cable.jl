# Grid used for the Jicable paper 2025
# Based on Ozgur's original two-terminal HVDC system
# Modified version of the grid used the imp_test.jl
# Small-signal version of model16\Two_terminal
# Author: ⛪🍦
# Date: 09.03.2025 Last Modified:
using PowerImpedanceACDC
using SymEngine
using MAT
s = symbols("s")

mutable struct DataContainer
    f::Vector{Float64}
    Y_MMC::Vector{ComplexF64}
    Z_grid::Vector{ComplexF64}
    Z_cable::Vector{ComplexF64}
    DataContainer() = new()
end

#Case study options
start_value= -2; # IMPORTANT!!!! RAD/s or Hz??????????
end_value=4;
steps=5000;
data_path=""
iscorrected=false
if iscorrected

        data_path="C://Users//jkirchei//OneDrive - KU Leuven//Documents//PhD Project//Source//EMT//model16//a320kV_1600mm2_bi_fem_pscad_ex.gf46//Corrected"

else

        data_path="C://Users//jkirchei//OneDrive - KU Leuven//Documents//PhD Project//Source//EMT//model16//a320kV_1600mm2_normal.gf46//Uncorrected"
end



#Storage options
file_name= "09_10_2025_Julia_run4"
internal_file_name="data"
storage_path="C:/Users/jkirchei/OneDrive - KU Leuven/Documents/PhD Project/Work Package 4/Data/Raw/"

#Setup data storage
DC_data = DataContainer()
DC_data.Y_MMC=Vector{ComplexF64}(undef, steps)
DC_data.Z_grid=Vector{ComplexF64}(undef, steps)



transmissionVoltage = 380 / sqrt(3)
pHVDC1 = 100
qC1 = 100
qC2 = 100
# The P and Q defined here are what is injected into the network. 

net = @network begin

        voltageBase = transmissionVoltage
    
        g1 = ac_source(V = transmissionVoltage, P = pHVDC1, P_min = -2000, P_max = 2000, Q_max = 1000, Q_min = -1000, pins = 3, transformation = true)

                                
        # HVDC link 1
        # MMC1 controls the DC voltage, and is situated at the remote end.
        c1 = mmc(Vᵈᶜ = 640, vDCbase = 640, Vₘ = transmissionVoltage,
                P_max = 1500, P_min = -1500, P = -pHVDC1, Q = qC1, Q_max = 500, Q_min = -500,
                occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
                ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
                pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
                q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
                dc = PI_control(Kₚ = 6, Kᵢ = 15),  timeDelay= 200e-6, padeOrderNum = 5, padeOrderDen =5 
                )
        # MMC2 controls P&Q. It is connected to bus 7. Define the transformer impedance parameters at the converter side!
        c2 = mmc(Vᵈᶜ = 640, vDCbase = 640, Vₘ = transmissionVoltage,
                P_max = 1000, P_min = -1000, P = pHVDC1, Q = qC2, Q_max = 1000, Q_min = -1000,
                vACbase_LL_RMS = 333, turnsRatio = 333/380, Lᵣ = 0.0461, Rᵣ = 0.4103, Lₐᵣₘ = 30e-3,
                occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
                ccc = PI_control(Kₚ = 1*0.1048, Kᵢ = 1*48.1914),
                pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
                p = PI_control(Kₚ = 1*0.1, Kᵢ = 31.4159),
                q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159), timeDelay= 200e-6, padeOrderNum = 5, padeOrderDen =5
                )

        dc_line=blackbox_line(n=2,data_type=:PSCAD,length=20e3,
                        path=data_path,transformation=true)


        # dc_line = cable(length = 100e3, positions = [(-0.5,1), (0.5,1)],
        #     C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        #     C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        #     C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
        #     I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        #     I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        #     I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)

        g4 = ac_source(V = transmissionVoltage, P = pHVDC1, P_min = -2000, P_max = 2000, Q_max = 1000, Q_min = -1000, pins = 3, transformation = true)


        tl1 = impedance(z=0.009s,pins=3, transformation = true)

        tl78 = impedance(z=0.009s,pins=3, transformation = true)

        c1[2.1] ⟷ tl1[2.1] ⟷ B3d
        c1[2.2] ⟷ tl1[2.2] ⟷ B3q

        g4[1.1] ⟷ tl1[1.1] ⟷ B2d
        g4[1.2] ⟷ tl1[1.2] ⟷ B2q



        g4[2.1] ⟷ gndd
        g4[2.2] ⟷ gndq
        
        c1[1.1] ⟷ dc_line[1.1] ⟷ B4
        c2[1.1] ⟷ dc_line[2.1] ⟷ B5


        c2[2.1] == tl78[1.1] == B6d
        c2[2.2] == tl78[1.2] == B6q
        g1[1.1] == tl78[2.1] == B7d
        g1[1.2] == tl78[2.2] == B7q

        g1[2.1] == gndd
        g1[2.2] == gndq


end


# Partitioning point is B5. Stability of the individual subsystems is checked in PSCAD
# model16\MMCs_standalone 🔨✅

Z_MMC_DC, omega = determine_impedance(net, elim_elements = [:dc_line], input_pins = Any[:B5], output_pins = Any[:gndd, :gndq],freq_range = (1e1^start_value, 1e1^end_value, steps))
plot1=bodeplot(Z_MMC_DC,omega,legend = ["ZMMC"])
display(plot1[1])
# TODO: No direct plotting of impedance!

Z_Grid_DC, omega = determine_impedance(net, elim_elements = [:c2], input_pins = Any[:B5], output_pins = Any[:gndd, :gndq],freq_range = (1e1^start_value, 1e1^end_value, steps))
plot2=bodeplot(Z_Grid_DC,omega,legend = ["ZGrid"])
display(plot2[1])

Z_cable=[]

for element in omega

        dummy=PowerImpedanceACDC.get_y(net.elements[:dc_line],element*1*im)
        push!(Z_cable,1/dummy[1,1]) # Take short circuit admittance and inverse to get short circuit impedance
end

bodeplot(Z_cable,omega,legend = ["Zcable_uncorrected"])




Y_DC_c1=[]
Z_DC_c1=[]
for element in omega


        dummy=eval_abcd(net.elements[:c1].element_value,element*1*im)

        push!(Y_DC_c1,dummy[1,1])
        push!(Z_DC_c1,1/dummy[1,1])

end








#plot3=bodeplot(Y_DC_c1,omega,legend = ["Yc1"])

# Loop gain calculation

Y_MMC_DC=inv.(Z_MMC_DC)
Loopgain=Y_MMC_DC.*Z_Grid_DC


Loopgain_plot=bodeplot(Loopgain,omega)
display(Loopgain_plot[1])
# Matlab export 

DC_data.f = omega./(2*pi)
DC_data.Y_MMC=only.(inv.(Z_MMC_DC))
DC_data.Z_grid=only.(Z_Grid_DC)
DC_data.Z_cable=Z_cable

# Save data
# dict=Dict("Julia" => DC_data)
# matwrite(joinpath("C:/Users/jkirchei/OneDrive - KU Leuven/Documents/PhD Project/Work Package 4/Data/Raw/",file_name * ".mat"), dict; compress = false)

  