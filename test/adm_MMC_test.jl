
Pmmc = 0.7*1060
Qmmc = 0
Vm = 400 / sqrt(3)
Vdc = 640

grid=@network begin



	voltageBase = Vm

	G3 = ac_source(pins = 3, V = Vm, transformation = true)
	G_DC=dc_source(pins = 1, V = 320)

	MMC1 = mmc(Vᵈᶜ = Vdc, vDCbase = 640, Sbase = 1060, vACbase_LL_RMS = 320,
		turnsRatio = 320/400, Vₘ = Vm, Lᵣ = 0.18 * (320^2/1060) / 2/pi/50,
		Rᵣ = 0.001 * (320^2/1060),
		P_max = 1500, P_min = -1500, P = Pmmc, Q = Qmmc, Q_max = 1000, Q_min = -1000,
		Rₐᵣₘ = 0.4, Lₐᵣₘ = 46.125e-3, Cₐᵣₘ = 11.3867e-3, N = 400,
		occ = PI_control(Kₚ = 0.6787, Kᵢ = 292.2087, n_f = 1, ω_f = 0.0001*2*pi),
		ccc = PI_control(Kₚ = 0.0992, Kᵢ = 42.9719),
		zcc = PI_control(Kₚ = 0.0992, Kᵢ = 42.9719),
		energy = PI_control(Kₚ = 1.386, Kᵢ = 29.70),
		pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664, n_f = 1, ω_f = 75*2*pi),
		q = PI_control(Kₚ = 0.0, Kᵢ = 30.0, n_f = 2, ω_f = 140*2*pi),
		p = VSE(H = 5, K_d = 100, K_ω = 10, ref_ω = 1, n_f = 2, ω_f = 140*2*pi),
		VI = CCQSEM(Rᵥ = 0.01, Lᵥ = 0.25, ref_vd = 1, ref_vq = 0, n_f = 2, ω_f = 200),
		gfm = true, timeDelay = 200e-6, padeOrderNum = 5, padeOrderDen = 5)

	G3[2.1] == gndD
	G3[2.2] == gndQ
	G3[1.1] == MMC1[2.1]
	G3[1.2] == MMC1[2.2]
	G_DC[1.1] == MMC1[1.1]
	G_DC[2.1] == gndDC


end

# Read in validation data

# lines=readlines("test/data/data_MMC_validation.txt")
lines=readlines(joinpath(@__DIR__, "data", "data_MMC_validation.txt"))
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
Y_MMC = []
for k in eachindex(omegas)
	Y1 = eval_abcd(grid.elements[:MMC1].element_model, 1im*omegas[k])
	push!(Y_MMC, [transpose(Y1[1, :]); transpose(-Y1[2, :]); transpose(-Y1[3, :])]) # Keep sign of Ydc, swapping sign of Yacs
end

# Compare angle and magnitudes
for k in eachindex(omegas)

	#println("Frequency: ", omegas[k]/(2*pi), " Hz")
	for c ∈ 1:3

		for r ∈ 1:3


			@test abs(Y_MMC[k][c, r]) ≈ abs(Y_validation[k][c, r]) rtol=0.11 # %
			@test angle(Y_MMC[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol=7*(pi/180) # degrees
		end



	end



end



# Plotting for visual inspection
# plot(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_MMC, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_validation, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

# plot(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_MMC, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_validation, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

