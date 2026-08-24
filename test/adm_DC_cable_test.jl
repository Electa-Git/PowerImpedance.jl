

grid = Network()

add!(
	grid,
	:labanimal,
    cable(length = 200e3, positions = [(0,1.5), (1,1.5)],
    C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
    I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
    C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
    I2 = Insulator(rᵢ = 55.4e-3, rₒ = 6.12e-3, ϵᵣ = 2.3), transformation = true,
	earth_parameters = (1, 1, 100)),

)




# Read in validation data
# lines=readlines("test/data/data_OHL_validation.txt")
lines=readlines(joinpath(@__DIR__, "data", "data_DC_cable_validation.txt"))
validation_data = [split(line) for line in lines[2:end]]
frequency =
	real([parse(Complex{Float64}, replace(row[1], "(" => "")) for row in validation_data])
omegas=2*pi*frequency
matrices = [
	reshape(parse.(Complex{Float64}, replace.(row[2:end], "(" => "")), 2, 2) for
	row in validation_data
]
Y_validation=transpose.(matrices)


# Obtain analytical data
Y_cable = []
for k in eachindex(omegas)
	Y1 = PowerImpedance.get_y(grid.elements[:labanimal], 1im*omegas[k])
	push!(Y_cable, Y1)
end

# Compare angle and magnitudes
for k in eachindex(omegas)

	#println("Frequency: ", omegas[k]/(2*pi), " Hz. Index: ", k)
	for c ∈ 1:2

		for r ∈ 1:2
			@test abs(Y_cable[k][c, r]) ≈ abs(Y_validation[k][c, r]) rtol=0.2 # 20%
			@test angle(Y_cable[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol= 20*(pi/180) # degrees
		end



	end



end


# Plotting for visual inspection
# plot(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_cable, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_validation, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

# plot(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_cable, 1, 2))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_validation, 1, 2))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)