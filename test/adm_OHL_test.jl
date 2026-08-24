

grid = Network()

add!(
	grid,
	:labanimal,
	overhead_line(length = 50e3,
		conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063,
			rᶜ = 0.015, yᵇᶜ = 30,
			Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
		groundwires = Groundwires(
			nᵍ = 2,
			Rᵍᵈᶜ = 0.92,
			rᵍ = 0.0062,
			Δxᵍ = 6.5,
			Δyᵍ = 7.5,
			dᵍˢᵃᵍ = 10,
		),
		earth_parameters = (1, 1, 100), transformation = true),
)

bundled_ohl = overhead_line(length = 50e3,
	conductors = Conductors(
		organization = :flat, nᵇ = 2, nˢᵇ = 2, Rᵈᶜ = 0.0598, rᶜ = 30.42e-3 / 2,
		yᵇᶜ = 18.0, Δyᵇᶜ = 0, Δxᵇᶜ = 7.3, Δ̃xᵇᶜ = 0, dˢᵇ = 0.45, dˢᵃᵍ = 6.0),
	groundwires = Groundwires(
		nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 7.3, Δyᵍ = 7.0, dᵍˢᵃᵍ = 6.0),
	earth_parameters = (1, 1, 100),
	transformation = true,
)

(Z_bundled, Y_bundled) = PowerImpedance.eval_parameters(
	bundled_ohl.element_model, 1im*2π*50)
@test size(Z_bundled) == (2, 2)
@test size(Y_bundled) == (2, 2)
@test all(isfinite, Z_bundled)
@test all(isfinite, Y_bundled)




# Read in validation data
# lines=readlines("test/data/data_OHL_validation.txt")
lines=readlines(joinpath(@__DIR__, "data", "data_OHL_validation.txt"))
validation_data = [split(line) for line in lines[2:end]]
frequency =
	real([parse(Complex{Float64}, replace(row[1], "(" => "")) for row in validation_data])
omegas=2*pi*frequency
matrices = [
	reshape(parse.(Complex{Float64}, replace.(row[2:end], "(" => "")), 4, 4) for
	row in validation_data
]
Y_validation=transpose.(matrices)


# Obtain analytical data
Y_OHL = []
for k in eachindex(omegas)
	Y1 = PowerImpedance.get_y(grid.elements[:labanimal], 1im*omegas[k])
	push!(Y_OHL, Y1) # Keep sign of Ydc, swapping sign of Yacs
end

# Compare angle and magnitudes
for k in eachindex(omegas)


	for c ∈ 1:4

		for r ∈ 1:4

			@test abs(Y_OHL[k][c, r]) ≈ abs(Y_validation[k][c, r]) rtol=0.01 # 1%
			@test angle(Y_OHL[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol=0.1*(pi/180) # degrees
		end

	end

end


# Plotting for visual inspection
# plot(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_OHL, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance [dB]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_validation, 1, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance [dB]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)
