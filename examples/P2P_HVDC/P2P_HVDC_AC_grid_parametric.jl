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
fontsize=16
legfontsize=16
default(fontfamily= "Computer Modern", xguidefontsize=fontsize,yguidefontsize=fontsize,
        tickfontsize=fontsize,titlefontsize=fontsize,legendfontsize=legfontsize,margin=2Plots.mm)



output_file = "stability_results.txt"


# Setting up power system
transmissionVoltage = 380 / sqrt(3)
# The P and Q defined here are what is injected into the network. 
qC1 = 0
s=symbols("s")


#############-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\
# Grid with black box MMC converter
#############-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------/

output_file = "stability_results.txt"
if !isfile(output_file)
    open(output_file, "w") do io
        println(io, "Index\tLength(km)\tP(MW)\tQ(MVar)\tStability_Result")
    end
end





# Case study settings


lengths =[70]#range(10, 80, step=20)  # 10, 20, 30, ..., 100
P = [1]#range(-1.0, 1.0, step=0.25)      # 100, 200, 300, ..., 1000
Q = [0.25]#range(0.0, 0.4, step=0.1)       


# Create all combinations of the parameters as tuple
parameter_range = vec(collect(Iterators.product(lengths, P, Q)))

start_index=1

global qC2
global l_OHL
global pHVDC1
global ynode, nodelist, omegasyedge, nodelist, omegas, loop, dummy


for (index,param) in enumerate(parameter_range[start_index:end])
    
l_OHL=param[1]*1e3 # Convert to meters
pHVDC1=param[2]*1000 # Scale P
qC2=param[3]*1000   # Scale Q


@time net = @network begin

        voltageBase = transmissionVoltage
    
        # AC grids
        g1 = ac_source(V = 1.0*transmissionVoltage, pins = 3, transformation = true)
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
        tl67 = overhead_line(length = l_OHL,
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
@time ynode,nodelist,omegas=make_y_node(net,freq_range = (1,1e3, 2000))
@time yedge,nodelist,omegas=make_y_edge(net,nodelist=nodelist,freq_range = (1,1e3, 2000))
@time loop=inv.(yedge).*ynode
@time dummy=nyquistplot(loop,omegas,zoom = "yes", SM = "GM", title  = " One OHL connected")


open(output_file, "a") do io
        # ... your loop code ...

        if start_index>1
            println(io, "$(index+start_index-1)\t$(param[1])\t$(param[2])\t$(param[3])\t$dummy")
        else
            println(io, "$(index)\t$(param[1])\t$(param[2])\t$(param[3])\t$dummy")
        end


end


println(" Doing Iteration "*"$(index+start_index)"*" with length"*string(l_OHL)*" km, P="*string(pHVDC1)*" MW, Q="*string(qC2)*" MVA now!.")

println(dummy)
end

#######PLotting :)#######################

struct StabilityResult
    index::Int
    length_km::Float64
    P_MW::Float64
    Q_MVar::Float64
    stability_result::String
end

output_file = "stability_results.txt"

results = StabilityResult[]

open(output_file, "r") do io
    # Skip header line
    readline(io)
    
    # Read each data line
    for line in eachline(io)
        parts = split(line, '\t')
        
        result = StabilityResult(
            parse(Int, parts[1]),
            parse(Float64, parts[2]),
            parse(Float64, parts[3]),
            parse(Float64, parts[4]),
            parts[5]
        )
        
        push!(results, result)
    end
end

# Full plot
plt=plot3d(    1,size = (600, 600),
    xlim = (-1, 1),
    ylim = (0, 0.3),
    zlim = (10, 70),
    legend = false,
    xticks = ([ -0.5, 0, 0.5, 1], ["-0.5", "0", "0.5", "1.0"]),
    zticks = ([10, 30, 50, 70], ["10", "30", "50", "70"]),
    marker = 2,)


for res in results

    marker = :square
    color = res.stability_result == "1" ? :blue : :red

    scatter3d!([res.P_MW], [res.Q_MVar], [res.length_km];
        markershape = marker,
        markercolor = color,
        markersize = 4,
        xlabel = "P [pu]",
        zlabel = "L [km]",
        ylabel = "Q [pu]",
        )


end
display(plt)

# Zoomed-in plot
plt2=plot3d(    1,size = (600, 600),
    xlim = (-1, 1),
    ylim = (0, 0.3),
    zlim = (-2, 1),
    legend = true,
    marker = 2,)


for res in results

    marker = :square
    color = res.stability_result == "1" ? :blue : :red

    scatter3d!([res.P_MW], [res.Q_MVar], [res.length_km];
        markershape = marker,
        markercolor = color,
        markersize = 4,
        xlabel = "P [pu]",
        zlabel = "L [km]",
        ylabel = "Q [pu]",
        )


end