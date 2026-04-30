using PowerImpedanceACDC
using PowerImpedanceACDC.NetworkBuilder: pin, ⟷

# The P and Q defined here are what is injected into the network.
transmissionVoltage = 380 / sqrt(3)
pHVDC1 = 100
qC1 = 100
qC2 = 100

rho = 100.0
L = 100e3

connections = (
	pin(:c1, 2.1) ⟷ pin(:tl1, 2.1) ⟷ :B3d,
	pin(:c1, 2.2) ⟷ pin(:tl1, 2.2) ⟷ :B3q, pin(:g4, 1.1) ⟷ pin(:tl1, 1.1) ⟷ :B2d,
	pin(:g4, 1.2) ⟷ pin(:tl1, 1.2) ⟷ :B2q, pin(:g4, 2.1) ⟷ :gndd,
	pin(:g4, 2.2) ⟷ :gndq,

	# component[(ac or dc side) . (1 = d, 2 = q)]
	pin(:c1, 1.1) ⟷ pin(:ugc, 1.1) ⟷ :B4,
	pin(:ugc, 2.1) ⟷ pin(:ohl, 1.1) ⟷ :BX,
	pin(:c2, 1.1) ⟷ pin(:ohl, 2.1) ⟷ :B5, pin(:c2, 2.1) ⟷ pin(:tl78, 1.1) ⟷ :B6d,
	pin(:c2, 2.2) ⟷ pin(:tl78, 1.2) ⟷ :B6q,
	pin(:g1, 1.1) ⟷ pin(:tl78, 2.1) ⟷ :B7d,
	pin(:g1, 1.2) ⟷ pin(:tl78, 2.2) ⟷ :B7q, pin(:g1, 2.1) ⟷ :gndd,
	pin(:g1, 2.2) ⟷ :gndq,
)

builder_options = (; voltageBase = transmissionVoltage)

function transition_elements(x)
	ohl_model = overhead_line(
		length = L * (1 - (x + 1e-3)),
		conductors = Conductors(
			organization = :flat,
			# two DC poles: +320 kV and -320 kV
			nᵇ = 2,
			# intentional: one physical conductor per pole
			nˢᵇ = 1,
			# ACSR Bluebird 2156 kcmil, 84/19
			# Nexans: Rdc20 = 0.0266 Ω/km, ampacity ≈ 1630 A
			Rᵈᶜ = 0.0266, rᶜ = 44.8e-3 / 2,
			# compact ±320 kV HVDC bipole-ish geometry
			yᵇᶜ = 18.0, Δyᵇᶜ = 0.0, Δxᵇᶜ = 7.3, Δ̃xᵇᶜ = 0.0,
			# irrelevant for nˢᵇ = 1, but left explicit
			dˢᵇ = 0.0,
			# representative sag offset
			dˢᵃᵍ = 6.0,
		),
		groundwires = Groundwires(
			nᵍ = 2,
			# keep your existing shield-wire class
			Rᵍᵈᶜ = 0.92, rᵍ = 0.0062,
			# two shield wires approximately above/around the pole positions
			Δxᵍ = 7.3, Δyᵍ = 7.0, dᵍˢᵃᵍ = 6.0,
		), earth_parameters = (1, 1, rho),
		transformation = true,
	)

	ugc_model = cable(
		length = L * (x + 1e-3),
		positions = [(-0.5, 1), (0.5, 1)],
		# core conductor
		C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
		# main insulation
		I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
		# sheath
		C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
		# sheath/jacket insulation
		I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
		# aluminium water-blocking foil
		C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
		# outer jacket
		I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
		earth_parameters = (1, 1, rho),
		transformation = true,
	)

	return (;
		g1 = ac_source(
			V = transmissionVoltage,
			P = pHVDC1,
			P_min = -2000,
			P_max = 2000,
			Q_max = 1000,
			Q_min = -1000,
			pins = 3,
			transformation = true,
		),

		# HVDC link 1
		# MMC1 controls the DC voltage, and is situated at the remote end.
		c1 = mmc(Vᵈᶜ = 640, vDCbase = 640, Vₘ = transmissionVoltage,
			P_max = 1500, P_min = -1500, P = -pHVDC1, Q = qC1, Q_max = 500,
			Q_min = -500,
			occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
			ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
			pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
			q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
			dc = PI_control(Kₚ = 6, Kᵢ = 15), timeDelay = 200e-6, padeOrderNum = 5,
			padeOrderDen = 5,
		),

		# MMC2 controls P&Q. It is connected to bus 7. Define the transformer impedance parameters at the converter side!
		c2 = mmc(Vᵈᶜ = 640, vDCbase = 640, Vₘ = transmissionVoltage,
			P_max = 1000, P_min = -1000, P = pHVDC1, Q = qC2, Q_max = 1000,
			Q_min = -1000,
			vACbase_LL_RMS = 333, turnsRatio = 333 / 380, Lᵣ = 0.0461, Rᵣ = 0.4103,
			Lₐᵣₘ = 30e-3,
			occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
			ccc = PI_control(Kₚ = 1 * 0.1048, Kᵢ = 1 * 48.1914),
			pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
			p = PI_control(Kₚ = 1 * 0.1, Kᵢ = 31.4159),
			q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159), timeDelay = 200e-6,
			padeOrderNum = 5, padeOrderDen = 5,
		),

		ugc = ugc_model,
		ohl = ohl_model,

		g4 = ac_source(
			V = transmissionVoltage,
			P = pHVDC1,
			P_min = -2000,
			P_max = 2000,
			Q_max = 1000,
			Q_min = -1000,
			pins = 3,
			transformation = true,
		),

		tl1 = overhead_line(length = 25e3,
			conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1,
				Rᵈᶜ = 0.063,
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

		tl78 = overhead_line(length = 90e3,
			conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1,
				Rᵈᶜ = 0.063,
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
end

function show_transition_abcd(elements)
	w = 1im * 2 * pi * 50

	gtest = Network()
	add!(gtest, :labanimal, elements.ohl)
	@show z_ohl =
		PowerImpedanceACDC.y_to_abcd(
			PowerImpedanceACDC.get_y(gtest.elements[:labanimal], w),
		)

	gtest = Network()
	add!(gtest, :labanimal, elements.ugc)
	@show z_ugc =
		PowerImpedanceACDC.y_to_abcd(
			PowerImpedanceACDC.get_y(gtest.elements[:labanimal], w),
		)
end

function run_transition_study()
	builder = nothing
	cached_powerflow = nothing

	for x in 0.0:0.1:1.0
		elements = transition_elements(x)
		show_transition_abcd(elements)

		if builder === nothing
			@time begin
				builder =
					NetworkBuilder.define(elements, connections; options = builder_options)
				solved = NetworkBuilder.solve(builder)
				cached_powerflow = solved.powerflow
			end
			cached_powerflow === nothing &&
				error("Expected power-flow results from an active network.")
		else
			@time NetworkBuilder.update!(
				builder;
				elements = elements,
				powerflow = cached_powerflow,
			)
		end

		net = builder.network

		# Determine impedance seen at the AC side of the HVDC link
		@time zgrid, omega_ac =
			determine_impedance(net, elim_elements = [:c2], input_pins = [:B5],
				output_pins = [:gndd], freq_range = (100, 5000, 1000))

		# Plot Z_dd
		Zg = getindex.(zgrid, 1, 1) #getindex.(imp_ac, 2, 2) qq, off diag qd
		display(
			bodeplot(Zg, omega_ac, legend = "Z @B5, UGC=$(round(x * 100; digits = 2)) %"),
		)
	end
end

@time run_transition_study()
