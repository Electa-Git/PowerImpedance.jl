
Powf = 70
Qowf = 20
Vm = 220 /sqrt(3) 
Vdc = 640

Ztrafo_base = 220^2/100
Lf = 0.08 * Ztrafo_base /2/pi/50
Rf = 0.01 * 0.08*Ztrafo_base


grid=@network begin
    


    voltageBase = Vm # Apparently needed for correct per-unit calculation of the power flow

    G3 = ac_source(pins = 3, V = Vm, transformation = true)
    G_DC = dc_source(pins = 1, V = Vdc/2)

DUT=tlc(Vᵈᶜ = Vdc, Vₘ = Vm, Lᵣ = Lf, Rᵣ = Rf, 
        Sbase = 100, vACbase_LL_RMS = 220, vDCbase = Vdc,
        Q = Qowf,
        occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8),
        pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = (2*pi)*80, n_f=2), # These gains are fine.
        v_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
        i_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
        f_supp = PI_control(ω_f = 1/0.5, Kₚ =5), #
        dc = PI_control(Kₚ = 5, Kᵢ = 5),
        q = PI_control(Kₚ = 0.04, Kᵢ = 40),
        vac_supp = PI_control(Kₚ=5,ref=[Vm*sqrt(2)],ω_f=1/0.5),
        timeDelay = 200e-6,
        padeOrderNum = 3,                    
        padeOrderDen = 3 )






    CableDC12 = cable(length = 10e3, positions = [(-0.5,1), (0.5,1)],
        C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),     
        I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)       




        
    G3[2.1] ⟷ gndD
    G3[2.2] ⟷ gndQ

    G3[1.1] == DUT[2.1] ⟷ NodeMMC1d
    G3[1.2] == DUT[2.2] ⟷ NodeMMC1q
    DUT[1.1] ⟷ CableDC12[1.1]
    CableDC12[2.1] ⟷ G_DC[1.1]

    G_DC[2.1] == gndDC



end

# Read in validation data

# lines=readlines("test/data/data_MMC_validation.txt")
lines=readlines(joinpath(@__DIR__, "data", "data_TLC_validation.txt"))
validation_data = [split(line) for line in lines[2:end]]
frequency =
	real([parse(Complex{Float64}, replace(row[1], "(" => "")) for row in validation_data])
omegas=2*pi*frequency
matrices = [
	reshape(parse.(Complex{Float64}, replace.(row[2:end], "(" => "")), 3, 3) for
	row in validation_data
]
Y_validation=transpose.(matrices)

# Obtain analytical data
Y_TLC = []
for k in eachindex(omegas)
	Y1 = eval_abcd(grid.elements[:DUT].element_value, 1im*omegas[k])
	push!(Y_TLC, [transpose(Y1[1, :]); transpose(-Y1[2, :]); transpose(-Y1[3, :])]) # Keep sign of Ydc, swapping sign of Yacs
end

# Compare angle and magnitudes
for k in eachindex(omegas)

	#println("Frequency: ", omegas[k]/(2*pi), " Hz")
	for c ∈ 1:3

		for r ∈ 1:3


			@test abs(Y_TLC[k][c, r]) ≈ abs(Y_validation[k][c, r]) rtol=0.07 # %
			@test angle(Y_TLC[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol=3*(pi/180) # degrees
		end



	end



end



# Plotting for visual inspection
# plot(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_MMC, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_validation, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

# plot(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_MMC, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_validation, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

