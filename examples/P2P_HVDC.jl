using PowerImpedanceACDC

transmissionVoltage = 380 / sqrt(3)
pHVDC1 = 600
qC1 = 100
qC2 = 100
# The P and Q defined here are what is injected into the network. 

@time net = @network begin

	voltageBase = transmissionVoltage

	g1 = ac_source(
		V = transmissionVoltage,
		P = pHVDC1,
		P_min = -2000,
		P_max = 2000,
		Q_max = 1000,
		Q_min = -1000,
		pins = 3,
		transformation = true,
	)


	# HVDC link 1
	# MMC1 controls the DC voltage, and is situated at the remote end.
	c1 = mmc(Vᵈᶜ = 800, vDCbase = 800, Vₘ = transmissionVoltage,
		P_max = 100, P_min = -100, P = -pHVDC1, Q = qC1, Q_max = 500, Q_min = -500,
		occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
		ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
		pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
		q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
		dc = PI_control(Kₚ = 5, Kᵢ = 15),
	)
	# MMC2 controls P&Q. It is connected to bus 7. Define the transformer impedance parameters at the converter side!
	c2 = mmc(Vᵈᶜ = 800, vDCbase = 800, Vₘ = transmissionVoltage,
		P_max = 100, P_min = -100, P = pHVDC1, Q = qC2, Q_max = 1000, Q_min = -1000,
		vACbase_LL_RMS = 333, turnsRatio = 333/380, Lᵣ = 0.0461, Rᵣ = 0.4103,
		occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
		ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
		pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
		p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
		q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
	)

	dc_line = cable(length = 100e3, positions = [(-0.5, 1), (0.5, 1)],
		C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
		C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
		C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
		I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
		I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
		I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3),
		transformation = true)

	g4 = ac_source(
		V = transmissionVoltage,
		P = pHVDC1,
		P_min = -2000,
		P_max = 2000,
		Q_max = 1000,
		Q_min = -1000,
		pins = 3,
		transformation = true,
	)


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

	tl78 = overhead_line(length = 90e3,
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

# Determine impedance seen at the AC side of the HVDC link
@time imp_ac, omega_ac =
	determine_impedance(net, elim_elements = [:g1], input_pins = [:B7d, :B7q],
		output_pins = [:gndd, :gndq], freq_range = (100, 5000, 1000))

# Plot Z_dd
Z_dd = getindex.(imp_ac, 1, 1)
bodeplot(Z_dd, omega_ac, legend = "Z_dd")
