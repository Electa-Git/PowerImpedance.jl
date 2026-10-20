

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

@testset "Cable earth return against homogeneous-earth Pollaczek integral" begin
    # Gauss–Legendre integration keeps the independent integral reference local
    # to this test and needs only LinearAlgebra, already a test dependency.
    function gauss_rule(n)
        beta = [k / sqrt(4k^2 - 1) for k in 1:(n-1)]
        rule = eigen(SymTridiagonal(zeros(n), beta))
        return rule.values, 2 .* rule.vectors[1, :].^2
    end
    function integrate_segments(f, breaks, rule)
        nodes, weights = rule
        return sum(sum(weights[k] * f((a+b)/2 + (b-a)/2 * nodes[k])
            for k in eachindex(nodes)) * (b-a)/2
            for (a, b) in zip(breaks[1:end-1], breaks[2:end]))
    end
    function pollaczek(s, radius_or_distance, horizontal, depth_sum, rule)
        mu = 4π * 1e-7
        m = sqrt(s * mu / 100.0)
        # K₀(z) = ∫₀∞ exp(-z cosh(t)) dt. Truncate after real(z) cosh(t)=40.
        function k0(z)
            last = acosh(40 / real(z))
            breaks = vcat(collect(0.0:1.0:last), last)
            return integrate_segments(t -> exp(-z * cosh(t)), breaks, rule)
        end
        image_distance = hypot(horizontal, depth_sum)
        breaks = sort(unique(vcat(0.0,
            filter(x -> x < 50.0, abs(m) .* 10.0.^(-1:4)), 50.0)))
        integral = integrate_segments(breaks, rule) do lambda
            q = sqrt(lambda^2 + m^2)
            exp(-depth_sum * q) * cos(horizontal * lambda) / (lambda + q)
        end
        # The omitted lambda tail is bounded by exp(-50H)/(50H).
        return s * mu / (2π) *
            (k0(m * radius_or_distance) - k0(m * image_distance) + 2integral)
    end
    coarse, fine = gauss_rule(32), gauss_rule(64)
    conductor = Conductor(rᵢ = 0.02, rₒ = 0.03, ρ = 1.72e-8)
    element = cable(length = 1e3, positions = [(0.0, 1.0), (0.5, 1.0)],
        C1 = conductor, earth_parameters = (1, 1, 100), eliminate = false)
    for frequency in (1.0, 50.0, 1000.0)
        s = 2π * frequency * im
        Z, _ = PowerImpedance.eval_parameters(element.element_model, s)
        m = sqrt(s * 4π * 1e-7 / conductor.ρ)
        metal = conductor.ρ * m / (2π * conductor.rₒ) *
            coth(m * (conductor.rₒ - conductor.rᵢ)) +
            conductor.ρ / (2π * conductor.rₒ * (conductor.rᵢ + conductor.rₒ))
        for (term, distance, horizontal, H) in
                ((Z[1, 1] - metal, conductor.rₒ, 0.0, 2.0),
                 (Z[1, 2], 0.5, 0.5, 2.0))
            reference = pollaczek(s, distance, horizontal, H, fine)
            @test abs(sqrt(s * 4π * 1e-7 / 100) * distance) < 0.01
            @test pollaczek(s, distance, horizontal, H, coarse) ≈ reference rtol = 1e-10
            @test term ≈ reference rtol = 1e-4
        end
        # Unequal depths check each self depth, mutual separation, and depth sum.
        unequal = deepcopy(element.element_model)
        unequal.positions[2] = (0.5, 1.3)
        Zu, _ = PowerImpedance.eval_parameters(unequal, s)
        @test Zu[1, 2] ≈ pollaczek(s, hypot(0.5, 0.3), 0.5, 2.3, fine) rtol = 1e-4
        m_earth = sqrt(s * 4π * 1e-7 / 100)
        for i in eachindex(unequal.positions)
            depth = unequal.positions[i][2]
            documented = s * 4π * 1e-7 / (2π) *
                (-log(exp(Base.MathConstants.eulergamma) * m_earth * conductor.rₒ / 2) +
                 0.5 - 4m_earth * depth / 3)
            self = Zu[i, i] - metal
            @test self ≈ documented rtol = 5e-14
            @test self ≈ pollaczek(s, conductor.rₒ, 0.0, 2depth, fine) rtol = 1e-4
        end
        reversed = deepcopy(unequal)
        reverse!(reversed.positions)
        Zr, _ = PowerImpedance.eval_parameters(reversed, s)
        @test isequal(Zu, Zr[[2, 1], [2, 1]])
    end
    # Check the DC limit against the conductor's independent annular resistance.
    resistance = conductor.ρ / (π * (conductor.rₒ^2 - conductor.rᵢ^2))
    Zdc, Ydc = PowerImpedance.eval_parameters(element.element_model, 1e-12im)
    @test real(Zdc[1, 1]) ≈ resistance rtol = 1e-8
    @test abs(imag(Zdc[1, 1])) < 1e-10
    @test abs(Zdc[1, 2]) < 1e-10
    @test maximum(abs, Ydc) < 1e-20
end

@testset "Equal-depth cable series impedance retains part-1 bits" begin
    model = cable(length = 1e3, positions = [(0.0, 1.3), (0.5, 1.3)],
        C1 = Conductor(rₒ = 0.01, ρ = 1.72e-8),
        I1 = Insulator(rᵢ = 0.01, rₒ = 0.02, ϵᵣ = 2.3),
        C2 = Conductor(rᵢ = 0.02, rₒ = 0.021, ρ = 2.14e-7),
        I2 = Insulator(rᵢ = 0.021, rₒ = 0.023, ϵᵣ = 2.3),
        earth_parameters = (1, 1, 100), eliminate = false).element_model
    # Frozen common-depth Z from the constant correction, checked on both versions.
    path = joinpath(@__DIR__, "data", "cable_self_depth_part1.txt")
    for line in readlines(path)[2:end]
        fields = split(line)
        s = 2π * parse(Float64, fields[1]) * im
        Z, _ = PowerImpedance.eval_parameters(model, s)
        expected = parse.(UInt64, fields[3:end]; base = 16)
        @test reinterpret(UInt64, vec(Z)) == expected
    end
end
