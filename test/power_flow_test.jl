
using JLD2: jldopen

Powf = 70
Qowf = 20
Vm = 220 / sqrt(3) #Vln,rms !!!!!!!!!!!!Change!!!!!!!!!!!!!!!!!!
Vdc = 640

Ztrafo_base = 220^2/100

Lf = 0.08 * Ztrafo_base / 2/pi/50
Rf = 0.01 * 0.08 * Ztrafo_base

Ltrafo = 0.15 * Ztrafo_base/2/pi/50
Rtrafo = 0.15/20 * Ztrafo_base

power_grid = @network begin



	voltageBase = Vm # Apparently needed for correct per-unit calculation of the power flow


	TLC1 = tlc(Vᵈᶜ = Vdc, Vₘ = Vm, Lᵣ = Lf, Rᵣ = Rf,
		Sbase = 100, vACbase_LL_RMS = 220,
		P = Powf, Q = Qowf,
		P_max = 1000, P_min = -1000, Q_max = 1000, Q_min = -1000,
		occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8),
		pll = PI_control(
			Kₚ = 0.397887357729738,
			Kᵢ = 7.957747154594767,
			ω_f = (2*pi)*80,
			n_f = 2,
		), # These gains are fine.
		v_meas_filt = PI_control(ω_f = 0.5e4, n_f = 2),
		i_meas_filt = PI_control(ω_f = 0.5e4, n_f = 2),
		f_supp = PI_control(ω_f = 1/0.5, Kₚ = 5), #
		p = PI_control(Kₚ = 0.04, Kᵢ = 40),
		q = PI_control(Kₚ = 0.04, Kᵢ = 40),
		timeDelay = 200e-6,
		padeOrderNum = 3,
		padeOrderDen = 3,
	)

	TF1 = transformer(
		n = 220/400,
		Lₚ = 4.9916e-4/2,
		Rₚ = 0,
		Rₛ = 0,
		Lₛ = 0.097/2,
		Cₜ = 7e-9,
		Cₛ = 12e-9,
		pins = 3,
		transformation = true,
	)

	SM1 = synchronousmachine(P = 50, Q = 10, V = 0.99 * 220/sqrt(3))

	imp1 = impedance(z = 1, pins = 3, transformation = true)

	tl1 = overhead_line(length = 25e3,
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
		earth_parameters = (1, 1, 100), transformation = true)



	CableDC12 = cable(length = 30e3, positions = [(-0.5, 1), (0.5, 1)],
		C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
		I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
		C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
		I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
		C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
		I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3),
		transformation = true)


	# # Extra AC/DC converter to represent DC voltage and get power flow converged 
	# OWF = mmc(Vᵈᶜ = Vdc, vDCbase = 640, Vₘ = Vm, 
	# P_max = 1000, P_min = -1000, P = -Powf, Q = 0, Q_max = 1000, Q_min = -1000,
	# occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
	# ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
	# pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
	# # vac_supp = PI_control(ω_f = 1/0.5, Kₚ =5, ref=[Vm*sqrt(2)]),
	# dc = PI_control(Kₚ = 5, Kᵢ = 15),
	# q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
	# )  



	# Extra AC/DC converter to represent DC voltage and get power flow converged 
	MMC1 = mmc(Vᵈᶜ = Vdc, vDCbase = 640, Vₘ = Vm,
		P_max = 1000, P_min = -1000, P = -Powf, Q = 0, Q_max = 1000, Q_min = -1000,
		occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
		ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
		pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
		# vac_supp = PI_control(ω_f = 1/0.5, Kₚ =5, ref=[Vm*sqrt(2)]),
		dc = PI_control(Kₚ = 5, Kᵢ = 15),
		q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
	)

	MMC2 = mmc(Vᵈᶜ = Vdc, vDCbase = 640, Vₘ = Vm,
		P_max = 1000, P_min = -1000, P = -Powf, Q = 0, Q_max = 1000, Q_min = -1000,
		occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
		ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
		pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
		# vac_supp = PI_control(ω_f = 1/0.5, Kₚ =5, ref=[Vm*sqrt(2)]),
		p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
		q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
	)


	G1 = ac_source(pins = 3, V = Vm, transformation = true)

	G2 = ac_source(pins = 3, V = 400/sqrt(3), transformation = true)
	G_DC = dc_source(pins = 2, V = Vdc, transformation = true)

	G1[2.1] ⟷ gndD
	G1[2.2] ⟷ gndQ


	G1[1.1] ⟷ imp1[1.1]
	G1[1.2] ⟷ imp1[1.2]

	imp1[2.1] ⟷ SM1[1.1] ⟷ MMC1[2.1]
	imp1[2.2] ⟷ SM1[1.2] ⟷ MMC1[2.2]

	SM1[2.1] ⟷ gndD
	SM1[2.2] ⟷ gndQ

	CableDC12[1.1] == MMC1[1.1] ⟷ NodeMMC2d

	MMC2[1.1] == CableDC12[2.1] ⟷ NodeDC1

	TF1[1.1] ⟷ MMC2[2.1] ⟷ TLC1[2.1] #⟷ # NodeMMC1d
	TF1[1.2] ⟷ MMC2[2.2] ⟷ TLC1[2.2] ⟷ NodeMMC1q

	TLC1[1.1] ⟷ G_DC[2.1]

	G_DC[1.1] ⟷ gndDC

	TF1[2.1] ⟷ tl1[1.1] #⟷ # NodeMMC1d
	TF1[2.2] ⟷ tl1[1.2]

	tl1[2.1] ⟷ G2[1.1]
	tl1[2.2] ⟷ G2[1.2]

	G2[2.1] ⟷ gndD
	G2[2.2] ⟷ gndQ

end

function deep_equal(a, b; path = "")
	if typeof(a) != typeof(b)
		@error "Type mismatch at $path: $(typeof(a)) vs $(typeof(b))"
		return false
	elseif isa(a, Dict)
		if keys(a) != keys(b)
			# println("Key mismatch at $path")
			@error "Key mismatch at $path" keys(a) keys(b)
			return false
		end
		for k in keys(a)
			if !deep_equal(a[k], b[k]; path = "$path → $k")
				return false
			end
		end
		return true
	elseif isa(a, AbstractArray)
		if length(a) != length(b)
			@error "Array length mismatch at $path: $(length(a)) vs $(length(b))"
			return false
		end
		for i in eachindex(a)
			if !deep_equal(a[i], b[i]; path = "$path[$i]")
				return false
			end
		end
		return true
	elseif isa(a, Number)
		if !isapprox(a, b; atol = 1e-8)
			@error "Float mismatch at $path: $a vs $b"
			return false
		end
		return true
	else
		if a != b
			@error "Mismatch at $path: $a vs $b"
			return false
		end
		return true
	end
end
atol=1e-8
new_result = result["solution"]
new_data_dict = data

original_data = jldopen(joinpath(@__DIR__, "data", "pf_dict.jld"))["pf_dict"]
original_results = jldopen(joinpath(@__DIR__, "data", "results.jld"))["results"]

# @test deep_equal(original_data, new_data_dict)
# @test deep_equal(original_results, new_result)
