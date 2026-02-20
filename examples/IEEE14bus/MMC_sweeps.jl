# This is a quick script serves to evaluate the passivity properties of MMC3 with respect to the cutoff frequency of the 
# VFF to alleviate the instability indentified in case 2 
# Author: Jan Kircheis 
# Date: Jan 2026

# Struct for storing the raw admittance data 
mutable struct DataContainer
    parameter::Float64
    frequency::Vector{Float64}
    data::Vector{Float64}
    DataContainer() = new()
end
using LinearAlgebra

vbase_AC = 310.2687e+03; # primary dawg
ibase_AC = 1519.342; # primary dawg
pu_SI=(vbase_AC/ibase_AC); # Convert from SI to pu

DUT=deepcopy(IEEE14bus.elements[:MMC3].element_value) # Just assigning creates only a reference, ie. a pointer pointing to the object.
# For mutuable type you need to use deepcopy() to create an independent object...🤓


Vm=DUT.Vₘ
θ=DUT.θ
Pac=DUT.P 
Qac=DUT.Q
Vdc=DUT.Vᵈᶜ
Pdc=DUT.P_dc


# Case study options
omega_Y_MMC1 = collect(range(2*pi*50, stop=2*pi*5000, step=10)) #Frequency range and resolution
start_value=100; # Hz??????????
end_value=600;
steps=20;
parameter_values=LinRange(start_value,end_value,steps)


#Setup data storage
data_ipf=[DataContainer() for _ in 1:length(parameter_values)]
eigenvalues=Dict()
stability_state_space = true

# Build loop
# For loop over the parameter values
@time for j in eachindex(parameter_values)


DUT.controls[:occ].ω_f=2*pi*parameter_values[j] # Change the parameter of the VI control
PowerImpedanceACDC.update!(DUT, Vm, θ, Pac, Qac, Vdc, Pdc) # Works 💘


# Check for stability first, eg. check whether A only has neg. eigenvalues, which is sufficient for the Y to be stable 
Λₒ = eigvals(DUT.A)
for i in 1:length(Λₒ)
    if real(Λₒ[i]) > 0
        
        global stability_state_space=false
        
    end
end

ipf =[]
Y_mmc=[]
for i in 1:length(omega_Y_MMC1)
    Y1 = eval_abcd(DUT, 1im*omega_Y_MMC1[i]) 
    Y1[2, :] = -Y1[2, :]
    Y1[3, :] = -Y1[3, :]

    push!(Y_mmc,Y1)
    #push!(ipf,pu_SI*0.5*passivity(Y1,omega_Y_MMC1[i])) # Convert from SI to pu 👺

end


data_ipf[j].frequency=omega_Y_MMC1./(2*pi)
data_ipf[j].parameter=parameter_values[j]
data_ipf[j].data=(pu_SI*0.5).*passivity(Y_mmc,omega_Y_MMC1)


end

println("Analysis done! System was...(tension building up)")
if stability_state_space
    println("Stable!")
else
    println("Not stable!")
end

########################################################################################################################
# Plotting

file_name="01_18_2026_fig1"

width =3.5/2                  #width in inches
height=3.5/2                   #height in inches
fontsize=6
legfontsize=2


default(fontfamily= "Computer Modern", xguidefontsize=fontsize,yguidefontsize=fontsize,
        tickfontsize=fontsize,titlefontsize=fontsize,legendfontsize=legfontsize)
width_px = Int(round(width* 100))  # Determining pixels, dpi of 100 is default
height_px = Int(round(height* 100)) # Determining pixels, dpi of 100 is default




plot_IPFs = plot(size=(width_px,height_px),
    left_margin=-3Plots.mm,
    right_margin=0Plots.mm,
    top_margin=0Plots.mm,
    bottom_margin=-4Plots.mm)

plot!(plot_IPFs, xlabel= "Frequency[Hz]",ylabel= L"0.5\cdotΛ_{min}(\mathbf{Y_{mmc}}+\mathbf{Y_{mmc}}^{H}) [pu]",minorgrid=true, legend=:none, xaxis = :log10)
# Create and add lines to the plot
for i in eachindex(parameter_values)
    
    plot!(plot_IPFs, data_ipf[i].frequency,data_ipf[i].data,color=:greens,line_z=1*parameter_values[i])

    # Code for label for first and last values
    # if i ==1
        
    #     plot!(p, data_ipf[i].frequency,abs.(data_ipf[i].data[1]), color=:reds,line_z=1e6*parameter_values[i], dpi= 400,label=start_value)

    # elseif i == lastindex(parameter_values)

    #     plot!(p, data_ipf[i].frequency,abs.(data_ipf[i].data[1]),color=:reds,line_z=1e6*parameter_values[i], dpi= 400,label=end_value)
    # else
        
    #     plot!(p, data_ipf[i].frequency,abs.(data_ipf[i].data[1]),color=:reds,line_z=1e6*parameter_values[i], dpi= 400)

    # end

    
end

display(plot_IPFs)


# Add inset to zoom in at oscillation frequency
dummy=plot!(plot_IPFs,data_ipf[1].frequency,data_ipf[1].data,inset=bbox(0.55, 0.1, 0.26, 0.26, :relative),color=:greens,legend=:none, subplot=2,
            xlims = (700, 1000),ylims=(-0.4,-0.25),
            xticks = [918.6],
            yticks = [-0.4,-0.3])

for i in eachindex(parameter_values)

    dummy=plot!(dummy,data_ipf[i].frequency,data_ipf[i].data, color=:greens,line_z=1*parameter_values[i],subplot=2)


    
end



display(dummy)





save_eps_inkscape(plot_IPFs, joinpath(storage_path,file_name * ".eps"),
inkscape_cmd=inkscape)
