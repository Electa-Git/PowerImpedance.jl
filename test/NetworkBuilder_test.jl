using PowerImpedanceACDC.NetworkBuilder: pin, ⟷

@testset "NetworkBuilder unit tests" begin
	legacy = @network begin
		z1 = impedance(z = 1, pins = 1)
		z2 = impedance(z = 2, pins = 1)

		z1[1.1] ⟷ z2[1.1] ⟷ n1
		z1[2.1] ⟷ z2[2.1] ⟷ gnd
	end

	elements = (; z1 = impedance(z = 1, pins = 1), z2 = impedance(z = 2, pins = 1))
	connections = (
		pin(:z1, 1.1) ⟷ pin(:z2, 1.1) ⟷ :n1,
		pin(:z1, 2.1) ⟷ pin(:z2, 2.1) ⟷ :gnd,
	)

	builder = NetworkBuilder.define(elements, connections)

	@test collect(keys(builder.network.elements)) == collect(keys(legacy.elements))
	@test Set(builder.network.nets[:n1]) == Set(legacy.nets[:n1])
	@test Set(builder.network.nets[:gnd]) == Set(legacy.nets[:gnd])
	@test builder.network.elements[:z1].pins == legacy.elements[:z1].pins
	@test builder.network.elements[:z2].pins == legacy.elements[:z2].pins

	@test NetworkBuilder.solve(builder).powerflow === nothing

	updated_elements = (; z1 = impedance(z = 3, pins = 1), z2 = impedance(z = 4, pins = 1))
	updated = NetworkBuilder.update!(builder; elements = updated_elements)

	@test updated.powerflow === nothing
	@test builder.network.elements[:z1].element_model.value == ComplexF64[3;;]
	@test Set(builder.network.nets[:n1]) == Set(legacy.nets[:n1])
end


# This is a PowerImpedanceACDC implementation of the IEEE 39 bus system test system
# Author: Jan Kircheis 
# Date: Jan 2026
# Related PSCAD model to be found under Etch: Control-->PowerImpedanceACDC-->IEEE 39-bus system
# 345 kV implementation ---> Everything referred to 345 kV

# Arrange environment


function calc_RLC(P, Q, V, component)
	# Function to calculate resistance, inductance or capacitance of a 3-phase series load for a given 1-phase active "P" and reactive power "Q" [MVA]
	# and phase-rms Voltage V [kV]
	# Discremination of component by string component "R", "L", "C"

	P=P*1e6
	Q=Q*1e6
	V=V*1e3

	S=sqrt(P^2+Q^2) # 1-phase apparent power
	S=S*3 # Get 3-phase power

	# Calculate phase current rms: I

	I=S/(sqrt(3)*V)

	if component == "R"

		R = P/(I^2)


		return R

	elseif component == "L"


		L = Q/(I^2*2*pi*50)
		return L

	elseif component == "C"

		C=(I^2)/(Q*2*pi*50)
		return C
	else
		error("No implemented load component specified!")
	end

end


#TODO:
# Get load parameters :)
# Load Bus 3
R_B3=calc_RLC(107.3333, 0.8, 345, "R")
L_B3=calc_RLC(107.3333, 0.8, 345, "L")

# Loads Bus 4
R_B4a=calc_RLC(166.6667, 61.3333, 345, "R")
L_B4=calc_RLC(166.6667, 61.3333, 345, "L")
R_B4b=calc_RLC(0, 100, 345, "R")
C_B4=calc_RLC(0, 100, 345, "C")

# Load Bus 5
R_B5=calc_RLC(0, 200, 345, "R")
C_B5=calc_RLC(0, 200, 345, "C")

# Load Bus 7
R_B7=calc_RLC(77.93333, 28.0, 345, "R")
L_B7=calc_RLC(77.93333, 28.0, 345, "L")

#Load Bus 8
R_B8=calc_RLC(174.0, 58.6667, 345, "R")
L_B8=calc_RLC(174.0, 58.6667, 345, "L")

# Load Bus 12
R_B12=calc_RLC(2.5, 29.3333, 230, "R")
L_B12=calc_RLC(2.5, 29.3333, 230, "L")

# Load Bus 15
R_B15=calc_RLC(106.6667, 51.0, 345, "R")
L_B15=calc_RLC(106.6667, 51.0, 345, "L")

# Load Bus 16
R_B16=calc_RLC(109.8, 10.7667, 345, "R")
L_B16=calc_RLC(109.8, 10.7667, 345, "L")

# Load Bus 18
R_B18=calc_RLC(52.6667, 10.0, 345, "R")
L_B18=calc_RLC(52.6667, 10.0, 345, "L")

# Load Bus 20
R_B20=calc_RLC(226.6667, 34.3333, 345, "R")
L_B20=calc_RLC(226.6667, 34.3333, 345, "L")

# Load Bus 21
R_B21=calc_RLC(91.3333, 38.3333, 345, "R")
L_B21=calc_RLC(91.3333, 38.3333, 345, "L")

# Load Bus 23
R_B23=calc_RLC(82.5, 28.2, 345, "R")
L_B23=calc_RLC(82.5, 28.2, 345, "L")

# Load Bus 24
R_B24=calc_RLC(102.8667, 30.73333, 345, "R")
C_B24=calc_RLC(102.8667, 30.73333, 345, "C")

# Load Bus 25
R_B25=calc_RLC(74.6667, 15.7333, 345, "R")
L_B25=calc_RLC(74.6667, 15.7333, 345, "L")

# Load Bus 26
R_B26=calc_RLC(46.3333, 5.6667, 345, "R")
L_B26=calc_RLC(46.3333, 5.6667, 345, "L")

# Load Bus 27
R_B27=calc_RLC(93.6667, 25.1667, 345, "R")
L_B27=calc_RLC(93.6667, 25.1667, 345, "L")

# Load Bus 28
R_B28=calc_RLC(68.6667, 9.2, 345, "R")
L_B28=calc_RLC(68.6667, 9.2, 345, "L")

# Load Bus 29
R_B29=calc_RLC(94.5, 8.9667, 345, "R")
L_B29=calc_RLC(94.5, 8.9667, 345, "L")

# Load Bus 31
R_B31=calc_RLC(3.0667, 1.5333, 22, "R")
L_B31=calc_RLC(3.0667, 1.5333, 22, "L")

# Load Bus 39
R_B39=calc_RLC(368, 83.3333, 345, "R")
L_B39=calc_RLC(368, 83.3333, 345, "L")

# Grid parameters
Vm1=345/sqrt(3) # rms - phase [kV]


# Transformer parameters
Lb_345=(345e3)^2/(2*pi*50*1000e6) # in H
Rb_345=(345e3)^2/(1000e6) # in Ohms

#STATCOM parameters
Vdc_ST=110 #Pole-pole DC voltage
S_ST=269 # MVA 
Z_ST_base = 345^2/S_ST
Lf_ST = 0.08 * Z_ST_base / 2/pi/50
Rf_ST = 0.01 * 0.08 * Z_ST_base
# Operating point
Q_ST=-0.5    #pu
Vac_ref_ST=0.9 #pu


const IEEE39_INPUT_PINS = [:Bus9d, :Bus9q]
const IEEE39_OUTPUT_PINS = [:gndD, :gndQ]
const IEEE39_ELIM_ELEMENTS = [:STATCOM]
const IEEE39_FREQ_RANGE = (1e0, 5e3, 10)

function build_ieee39bus_with_macro()
	elec = PowerImpedanceACDC.ElectricalTLC(
		Lᵣ = Lf_ST,
		Rᵣ = Rf_ST,
		Sbase = S_ST,
		vACbase_LL_RMS = 345,
		vDCbase = Vdc_ST,
	)

	meas = PowerImpedanceACDC.Measurement(
		v_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 0.5e4),
		i_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 0.5e4),
	)

	sync = PowerImpedanceACDC.PLLSynchronization(
		pi_ctrl = PowerImpedanceACDC.PIControl(
			Kp = 0.397887357729738,
			Ki = 7.957747154594767,
		),
		filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 2π * 80),
	)

	innerVoltage = PowerImpedanceACDC.NoInnerVoltageControl()

	innerCurrent = PowerImpedanceACDC.InnerCurrentPIControl(
		pi_ctrl = PowerImpedanceACDC.PIControl(
			Kp = 0.254647908947033,
			Ki = 0.8,
		),
	)

	mod = PowerImpedanceACDC.PadeModulation(
		timeDelay = 200e-6,
		padeOrderNum = 3,
		padeOrderDen = 3,
	)

	limits = PowerImpedanceACDC.Limits(
		P_min = -1000.0,
		P_max = 1000.0,
		Q_min = -1000.0,
		Q_max = 1000.0,
	)

	outerActive = PowerImpedanceACDC.OuterActiveVdcControl(
		pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 5.0, Ki = 5.0),
		v_dc_ref = 0.0,
	)

	outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
		pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.04, Ki = 40.0),
		support = PowerImpedanceACDC.VoltageSupportLag(
			K = 5.0,
			ωc = 1 / 0.5,
			v_ac_ref = Vm1*sqrt(2)*Vac_ref_ST / elec.vACbase,
		),
	)

	setpoint = PowerImpedanceACDC.SetPoint(
		Pac = 0.0,
		Qac = Q_ST*S_ST,
		θac = 0.0,
		Vac = Vm1*sqrt(2)*Vac_ref_ST,
		Pdc = 0.0,
		Vdc = Vdc_ST,
	)
	return @network begin

		voltageBase = Vm1




		# Sources @ 345 kV
		G30=ac_source(pins = 3, V = Vm1, transformation = true)
		G31=ac_source(pins = 3, V = Vm1, transformation = true)
		G32=ac_source(pins = 3, V = Vm1, transformation = true)
		G33=ac_source(pins = 3, V = Vm1, transformation = true)
		G34=ac_source(pins = 3, V = Vm1, transformation = true)
		G35=ac_source(pins = 3, V = Vm1, transformation = true)
		G36=ac_source(pins = 3, V = Vm1, transformation = true)
		G37=ac_source(pins = 3, V = Vm1, transformation = true)
		G38=ac_source(pins = 3, V = Vm1, transformation = true)
		G39=ac_source(pins = 3, V = Vm1, transformation = true)
		# Source impedances @ 345 kV
		Zg30=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg31=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg32=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg33=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg34=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg35=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg36=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg37=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg38=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)
		Zg39=impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		)

		G_DC=dc_source(pins = 1, V = Vdc_ST/2) # DC voltage source to arrange Powerflow of Statcom, not possible to directly connect to DC-controlling STATCOM



		STATCOM = PowerImpedanceACDC.tlc(
			elec = elec,
			meas = meas,
			sync = sync,
			outerActive = outerActive,
			outerReactive = outerReactive,
			innerVoltage = innerVoltage,
			innerCurrent = innerCurrent,
			mod = mod,
			setpoint = setpoint,
			limits = limits,
		)

		dummy_impedance=impedance(z = 1e4, pins = 1) # Dummy impedance to arrange powerflow of DC-controlling STATCOM
		# Transformers

		# Bus 2 - Bus 30

		TR2_30 = transformer(
			n = 345/345,
			Lₚ = (0.0181/2)*Lb_345,
			Lₛ = (0.0181/2)*Lb_345,
			pins = 3,
			transformation = true,
		)


		# Bus 6 - Bus 31

		TR6_31 = transformer(
			n = 345/345,
			Lₚ = (0.025/2)*Lb_345,
			Lₛ = (0.025/2)*Lb_345,
			pins = 3,
			transformation = true,
		)


		# Bus 10 - Bus 32

		TR10_32 = transformer(
			n = 345/345,
			Lₚ = (0.02/2)*Lb_345,
			Lₛ = (0.02/2)*Lb_345,
			pins = 3,
			transformation = true,
		)

		# Bus 11 - Bus 12

		TR11_12 = transformer(
			n = 345/345,
			Lₚ = (0.0435/2)*Lb_345,
			Rₚ = (0.0016/2)*Rb_345,
			Lₛ = (0.0435/2)*Lb_345,
			Rₛ = (0.0016/2)*Rb_345,
			pins = 3,
			transformation = true,
		)

		# Bus 12 - Bus 13

		TR12_13 = transformer(
			n = 345/345,
			Lₚ = (0.0435/2)*Lb_345,
			Rₚ = (0.0016/2)*Rb_345,
			Lₛ = (0.0435/2)*Lb_345,
			Rₛ = (0.0016/2)*Rb_345,
			pins = 3,
			transformation = true,
		)

		# Bus 19 - Bus 20

		TR19_20 = transformer(
			n = 345/345,
			Lₚ = (0.0138 / 2)*Lb_345,
			Rₚ = (0.0007/2)*Rb_345,
			Lₛ = (0.0138 / 2)*Lb_345,
			Rₛ = (0.0007/2)*Rb_345,
			pins = 3,
			transformation = true,
		)

		# Bus 19 - Bus 33

		TR19_33 = transformer(
			n = 345/345,
			Lₚ = (0.0142 / 2)*Lb_345,
			Rₚ = (0.0007/2)*Rb_345,
			Lₛ = (0.0142 / 2)*Lb_345,
			Rₛ = (0.0007/2)*Rb_345,
			pins = 3,
			transformation = true,
		)


		# Bus 20 - Bus 34

		TR20_34 = transformer(
			n = 345/345,
			Lₚ = (0.0180 / 2)*Lb_345,
			Rₚ = (0.0009/2)*Rb_345,
			Lₛ = (0.0180 / 2)*Lb_345,
			Rₛ = (0.0009/2)*Rb_345,
			pins = 3,
			transformation = true,
		)


		# Bus 22 - Bus 35

		TR22_35 = transformer(
			n = 345/345,
			Lₚ = (0.0143 / 2)*Lb_345,
			Lₛ = (0.0143 / 2)*Lb_345,
			pins = 3,
			transformation = true,
		)

		# Bus 23 - Bus 36

		TR23_36 = transformer(
			n = 345/345,
			Lₚ = (0.0272 / 2)*Lb_345,
			Rₚ = (0.0005/2)*Rb_345,
			Lₛ = (0.0272 / 2)*Lb_345,
			Rₛ = (0.0005/2)*Rb_345,
			pins = 3,
			transformation = true,
		)

		# Bus 25 - Bus 37

		TR25_37 = transformer(
			n = 345/345,
			Lₚ = (0.0232 / 2)*Lb_345,
			Rₚ = (0.0006/2)*Rb_345,
			Lₛ = (0.0232 / 2)*Lb_345,
			Rₛ = (0.0006/2)*Rb_345,
			pins = 3,
			transformation = true,
		)

		# Bus 29 - Bus 38

		TR29_38 = transformer(
			n = 345/345,
			Lₚ = (0.0156 / 2)*Lb_345,
			Rₚ = (0.0008/2)*Rb_345,
			Lₛ = (0.0156 / 2)*Lb_345,
			Rₛ = (0.0008/2)*Rb_345,
			pins = 3,
			transformation = true,
		)








		# Power lines

		T1_2 = overhead_line(length = 72.4730e3,
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

		T1_39 = overhead_line(length = 44.0833e3,
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

		T2_3 = overhead_line(length = 26.6263e3,
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

		T2_25 = overhead_line(length = 15.1647e3,
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

		T3_4 = overhead_line(length = 37.5590e3,
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

		T3_18 = overhead_line(length = 23.4523e3,
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

		T4_5 = overhead_line(length = 22.5707e3,
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

		T4_14 = overhead_line(length = 22.7470e3,
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

		T5_6 = overhead_line(length = 4.5847e3,
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

		T5_8 = overhead_line(length = 19.7493e3,
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

		T6_7 = overhead_line(length = 16.2227e3,
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

		T6_11 = overhead_line(length = 14.4593e3,
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

		T7_8 = overhead_line(length = 8.1113e3,
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

		T8_9 = overhead_line(length = 64.009e3,
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
			earth_parameters = (1, 1, 100), transformation = true, connection = false)

		T9_39 = overhead_line(length = 44.0833e3,
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
			earth_parameters = (1, 1, 100), transformation = true, connection = true) # Connection = true --> Line connected, false: disconnected

		T10_11 = overhead_line(length = 7.5823e3,
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

		T10_13 = overhead_line(length = 7.5823e3,
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

		T13_14 = overhead_line(length = 17.8097e3,
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

		T14_15 = overhead_line(length = 38.2643e3,
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

		T15_16 = overhead_line(length = 16.5753e3,
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

		T16_17 = overhead_line(length = 15.6937e3,
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

		T16_19 = overhead_line(length = 34.3850e3,
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

		T16_21 = overhead_line(length = 23.8050e3,
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

		T16_24 = overhead_line(length = 10.4037e3,
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

		T17_18 = overhead_line(length = 14.4593e3,
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

		T17_27 = overhead_line(length = 30.5057e3,
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

		T21_22 = overhead_line(length = 24.6867e3,
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

		T22_23 = overhead_line(length = 16.9280e3,
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

		T23_24 = overhead_line(length = 61.7167e3,
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

		T25_26 = overhead_line(length = 56.95573e3,
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

		T26_27 = overhead_line(length = 25.9210e3,
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

		T26_28 = overhead_line(length = 83.5820e3,
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

		T26_29 = overhead_line(length = 110.2083e3,
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

		T28_29 = overhead_line(length = 26.6263e3,
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

		# Loads

		# Load Bus 3
		LoadB3 =
			impedance(z = (s::Complex) -> (R_B3+s*L_B3), pins = 3, transformation = true)

		# Load Bus 4
		LoadB4a =
			impedance(z = (s::Complex) -> (R_B4a+s*L_B4), pins = 3, transformation = true)
		LoadB4b = impedance(
			z = (s::Complex) -> (R_B4b+(1/(s*C_B4))),
			pins = 3,
			transformation = true,
		)
		# Load Bus 5
		LoadB5 = impedance(
			z = (s::Complex) -> (R_B5+(1/(s*C_B5))),
			pins = 3,
			transformation = true,
		)

		# Load Bus 7
		LoadB7 =
			impedance(z = (s::Complex) -> (R_B7+s*L_B7), pins = 3, transformation = true)

		# Load Bus 8
		LoadB8 =
			impedance(z = (s::Complex) -> (R_B8+s*L_B8), pins = 3, transformation = true)

		# Load Bus 12
		LoadB12 = impedance(
			z = (s::Complex)->(345/230)*(345/230)*(R_B12+s*L_B12),
			pins = 3,
			transformation = true,
		) #Referring load to 345 kV side
		# Load Bus 15
		LoadB15 =
			impedance(z = (s::Complex) -> (R_B15+s*L_B15), pins = 3, transformation = true)

		# Load Bus 16
		LoadB16 =
			impedance(z = (s::Complex) -> (R_B16+s*L_B16), pins = 3, transformation = true)

		# Load Bus 18
		LoadB18 =
			impedance(z = (s::Complex) -> (R_B18+s*L_B18), pins = 3, transformation = true)

		# Load Bus 20
		LoadB20 =
			impedance(z = (s::Complex) -> (R_B20+s*L_B20), pins = 3, transformation = true)

		# Load Bus 21
		LoadB21 =
			impedance(z = (s::Complex) -> (R_B21+s*L_B21), pins = 3, transformation = true)

		# Load Bus 23
		LoadB23 =
			impedance(z = (s::Complex) -> (R_B23+s*L_B23), pins = 3, transformation = true)
		# Load Bus 24
		LoadB24 = impedance(
			z = (s::Complex) -> (R_B24+(1/(s*C_B24))),
			pins = 3,
			transformation = true,
		)

		# Load Bus 25
		LoadB25 =
			impedance(z = (s::Complex) -> (R_B25+s*L_B25), pins = 3, transformation = true)

		# Load Bus 26
		LoadB26 =
			impedance(z = (s::Complex) -> (R_B26+s*L_B26), pins = 3, transformation = true)

		# Load Bus 27
		LoadB27 =
			impedance(z = (s::Complex) -> (R_B27+s*L_B27), pins = 3, transformation = true)

		# Load Bus 28
		LoadB28 =
			impedance(z = (s::Complex) -> (R_B28+s*L_B28), pins = 3, transformation = true)
		# Load Bus 29
		LoadB29 =
			impedance(z = (s::Complex) -> (R_B29+s*L_B29), pins = 3, transformation = true)

		# Load Bus 31
		LoadB31 = impedance(
			z = (s::Complex)->(345/22)*(345/22)*(R_B31+s*L_B31),
			pins = 3,
			transformation = true,
		) #Referring load to 345 kV side

		# Load Bus 39
		LoadB39 =
			impedance(z = (s::Complex) -> (R_B39+s*L_B39), pins = 3, transformation = true)

		# Connection

		# Sources grounding

		G30[2.1] ⟷ gndD
		G30[2.2] ⟷ gndQ
		G31[2.1] ⟷ gndD
		G31[2.2] ⟷ gndQ
		G32[2.1] ⟷ gndD
		G32[2.2] ⟷ gndQ
		G33[2.1] ⟷ gndD
		G33[2.2] ⟷ gndQ
		G34[2.1] ⟷ gndD
		G34[2.2] ⟷ gndQ
		G35[2.1] ⟷ gndD
		G35[2.2] ⟷ gndQ
		G36[2.1] ⟷ gndD
		G36[2.2] ⟷ gndQ
		G37[2.1] ⟷ gndD
		G37[2.2] ⟷ gndQ
		G38[2.1] ⟷ gndD
		G38[2.2] ⟷ gndQ
		G39[2.1] ⟷ gndD
		G39[2.2] ⟷ gndQ
		G_DC[2.1] ⟷ gndDC

		# Loads grounding

		LoadB3[2.1] ⟷ gndD
		LoadB3[2.2] ⟷ gndQ
		LoadB4a[2.1] ⟷ gndD
		LoadB4a[2.2] ⟷ gndQ
		LoadB4b[2.1] ⟷ gndD
		LoadB4b[2.2] ⟷ gndQ
		LoadB5[2.1] ⟷ gndD
		LoadB5[2.2] ⟷ gndQ
		LoadB7[2.1] ⟷ gndD
		LoadB7[2.2] ⟷ gndQ
		LoadB8[2.1] ⟷ gndD
		LoadB8[2.2] ⟷ gndQ
		LoadB12[2.1] ⟷ gndD
		LoadB12[2.2] ⟷ gndQ
		LoadB15[2.1] ⟷ gndD
		LoadB15[2.2] ⟷ gndQ
		LoadB16[2.1] ⟷ gndD
		LoadB16[2.2] ⟷ gndQ
		LoadB18[2.1] ⟷ gndD
		LoadB18[2.2] ⟷ gndQ
		LoadB20[2.1] ⟷ gndD
		LoadB20[2.2] ⟷ gndQ
		LoadB21[2.1] ⟷ gndD
		LoadB21[2.2] ⟷ gndQ
		LoadB23[2.1] ⟷ gndD
		LoadB23[2.2] ⟷ gndQ
		LoadB24[2.1] ⟷ gndD
		LoadB24[2.2] ⟷ gndQ
		LoadB25[2.1] ⟷ gndD
		LoadB25[2.2] ⟷ gndQ
		LoadB26[2.1] ⟷ gndD
		LoadB26[2.2] ⟷ gndQ
		LoadB27[2.1] ⟷ gndD
		LoadB27[2.2] ⟷ gndQ
		LoadB28[2.1] ⟷ gndD
		LoadB28[2.2] ⟷ gndQ
		LoadB29[2.1] ⟷ gndD
		LoadB29[2.2] ⟷ gndQ
		LoadB31[2.1] ⟷ gndD
		LoadB31[2.2] ⟷ gndQ
		LoadB39[2.1] ⟷ gndD
		LoadB39[2.2] ⟷ gndQ


		# Sources

		G30[1.1] ⟷ Zg30[1.1]
		G30[1.2] ⟷ Zg30[1.2]
		G31[1.1] ⟷ Zg31[1.1]
		G31[1.2] ⟷ Zg31[1.2]
		G32[1.1] ⟷ Zg32[1.1]
		G32[1.2] ⟷ Zg32[1.2]
		G33[1.1] ⟷ Zg33[1.1]
		G33[1.2] ⟷ Zg33[1.2]
		G34[1.1] ⟷ Zg34[1.1]
		G34[1.2] ⟷ Zg34[1.2]
		G35[1.1] ⟷ Zg35[1.1]
		G35[1.2] ⟷ Zg35[1.2]
		G36[1.1] ⟷ Zg36[1.1]
		G36[1.2] ⟷ Zg36[1.2]
		G37[1.1] ⟷ Zg37[1.1]
		G37[1.2] ⟷ Zg37[1.2]
		G38[1.1] ⟷ Zg38[1.1]
		G38[1.2] ⟷ Zg38[1.2]
		G39[1.1] ⟷ Zg39[1.1]
		G39[1.2] ⟷ Zg39[1.2]
		G_DC[1.1] ⟷ dummy_impedance[2.1]


		T1_39[1.1] ⟷ T1_2[1.1] == Bus1d
		T1_39[1.2] ⟷ T1_2[1.2] == Bus1q

		T2_25[1.1] ⟷ T1_2[2.1] == T2_3[1.1] ⟷ TR2_30[1.1] == Bus2d
		T2_25[1.2] ⟷ T1_2[2.2] == T2_3[1.2] ⟷ TR2_30[1.2] == Bus2q

		T2_3[2.1] ⟷ T3_18[1.1] ⟷ T3_4[1.1] ⟷ LoadB3[1.1] == Bus3d
		T2_3[2.2] ⟷ T3_18[1.2] ⟷ T3_4[1.2] ⟷ LoadB3[1.2] == Bus3q

		T3_4[2.1] ⟷ T4_5[1.1] ⟷ T4_14[1.1] ⟷ LoadB4a[1.1] ⟷ LoadB4b[1.1] == Bus4d
		T3_4[2.2] ⟷ T4_5[1.2] ⟷ T4_14[1.2] ⟷ LoadB4a[1.2] ⟷ LoadB4b[1.2] == Bus4q

		T4_5[2.1] ⟷ T5_6[1.1] ⟷ T5_8[1.1] ⟷ LoadB5[1.1] == Bus5d
		T4_5[2.2] ⟷ T5_6[1.2] ⟷ T5_8[1.2] ⟷ LoadB5[1.2] == Bus5q

		T5_6[2.1] ⟷ T6_7[1.1] ⟷ T6_11[1.1] ⟷ TR6_31[1.1] == Bus6d
		T5_6[2.2] ⟷ T6_7[1.2] ⟷ T6_11[1.2] ⟷ TR6_31[1.2] == Bus6q

		T6_7[2.1] ⟷ T7_8[1.1] ⟷ LoadB7[1.1] == Bus7d
		T6_7[2.2] ⟷ T7_8[1.2] ⟷ LoadB7[1.2] == Bus7q

		T7_8[2.1] ⟷ T8_9[1.1] ⟷ T5_8[2.1] ⟷ LoadB8[1.1] == Bus8d
		T7_8[2.2] ⟷ T8_9[1.2] ⟷ T5_8[2.2] ⟷ LoadB8[1.2] == Bus8q

		T8_9[2.1] ⟷ T9_39[1.1] == STATCOM[2.1] == Bus9d
		T8_9[2.2] ⟷ T9_39[1.2] == STATCOM[2.2] == Bus9q
		dummy_impedance[1.1] == STATCOM[1.1]

		T10_11[1.1] ⟷ T10_13[1.1] ⟷ TR10_32[1.1] == Bus10d
		T10_11[1.2] ⟷ T10_13[1.2] ⟷ TR10_32[1.2] == Bus10q

		T10_11[2.1] ⟷ T6_11[2.1] ⟷ TR11_12[1.1] == Bus11d
		T10_11[2.2] ⟷ T6_11[2.2] ⟷ TR11_12[1.2] == Bus11q

		TR11_12[2.1] ⟷ TR12_13[1.1] ⟷ LoadB12[1.1] == Bus12d
		TR11_12[2.2] ⟷ TR12_13[1.2] ⟷ LoadB12[1.2] == Bus12q

		T10_13[2.1] ⟷ T13_14[1.1] ⟷ TR12_13[2.1] == Bus13d
		T10_13[2.2] ⟷ T13_14[1.2] ⟷ TR12_13[2.2] == Bus13q

		T14_15[1.1] ⟷ T13_14[2.1] ⟷ T4_14[2.1] == Bus14d
		T14_15[1.2] ⟷ T13_14[2.2] ⟷ T4_14[2.2] == Bus14q

		T14_15[2.1] ⟷ T15_16[1.1] ⟷ LoadB15[1.1] == Bus15d
		T14_15[2.2] ⟷ T15_16[1.2] ⟷ LoadB15[1.2] == Bus15q

		T15_16[2.1] ⟷
		T16_17[1.1] ⟷ T16_19[1.1] ⟷ T16_21[1.1] ⟷ T16_24[1.1] ⟷ LoadB16[1.1] == Bus16d
		T15_16[2.2] ⟷
		T16_17[1.2] ⟷ T16_19[1.2] ⟷ T16_21[1.2] ⟷ T16_24[1.2] ⟷ LoadB16[1.2] == Bus16q

		T16_17[2.1] ⟷ T17_18[1.1] ⟷ T17_27[1.1] == Bus17d
		T16_17[2.2] ⟷ T17_18[1.2] ⟷ T17_27[1.2] == Bus17q

		T17_18[2.1] ⟷ LoadB18[1.1] ⟷ T3_18[2.1] == Bus18d
		T17_18[2.2] ⟷ LoadB18[1.2] ⟷ T3_18[2.2] == Bus18q

		T16_19[2.1] ⟷ TR19_20[1.1] ⟷ TR19_33[1.1] == Bus19d
		T16_19[2.2] ⟷ TR19_20[1.2] ⟷ TR19_33[1.2] == Bus19q

		TR19_20[2.1] ⟷ TR20_34[1.1] ⟷ LoadB20[1.1] == Bus20d
		TR19_20[2.2] ⟷ TR20_34[1.2] ⟷ LoadB20[1.2] == Bus20q

		T16_21[2.1] ⟷ LoadB21[1.1] ⟷ T21_22[1.1] == Bus21d
		T16_21[2.2] ⟷ LoadB21[1.2] ⟷ T21_22[1.2] == Bus21q

		T21_22[2.1] ⟷ T22_23[1.1] ⟷ TR22_35[1.1] == Bus22d
		T21_22[2.2] ⟷ T22_23[1.2] ⟷ TR22_35[1.2] == Bus22q

		T22_23[2.1] ⟷ LoadB23[1.1] ⟷ T23_24[1.1] ⟷ TR23_36[1.1] == Bus23d
		T22_23[2.2] ⟷ LoadB23[1.2] ⟷ T23_24[1.2] ⟷ TR23_36[1.2] == Bus23q

		T16_24[2.1] ⟷ T23_24[2.1] ⟷ LoadB24[1.1] == Bus24d
		T16_24[2.2] ⟷ T23_24[2.2] ⟷ LoadB24[1.2] == Bus24q

		T2_25[2.1] ⟷ LoadB25[1.1] ⟷ T25_26[1.1] ⟷ TR25_37[1.1] == Bus25d
		T2_25[2.2] ⟷ LoadB25[1.2] ⟷ T25_26[1.2] ⟷ TR25_37[1.2] == Bus25q

		T25_26[2.1] ⟷ LoadB26[1.1] ⟷ T26_27[1.1] ⟷ T26_28[1.1] ⟷ T26_29[1.1] == Bus26d
		T25_26[2.2] ⟷ LoadB26[1.2] ⟷ T26_27[1.2] ⟷ T26_28[1.2] ⟷ T26_29[1.2] == Bus26q

		T26_27[2.1] ⟷ T17_27[2.1] ⟷ LoadB27[1.1] == Bus27d
		T26_27[2.2] ⟷ T17_27[2.2] ⟷ LoadB27[1.2] == Bus27q

		T26_28[2.1] ⟷ T28_29[1.1] ⟷ LoadB28[1.1] == Bus28d
		T26_28[2.2] ⟷ T28_29[1.2] ⟷ LoadB28[1.2] == Bus28q

		T26_29[2.1] ⟷ LoadB29[1.1] ⟷ T28_29[2.1] ⟷ TR29_38[1.1] == Bus29d
		T26_29[2.2] ⟷ LoadB29[1.2] ⟷ T28_29[2.2] ⟷ TR29_38[1.2] == Bus29q

		TR2_30[2.1] ⟷ Zg30[2.1] == Bus30d
		TR2_30[2.2] ⟷ Zg30[2.2] == Bus30q

		TR6_31[2.1] ⟷ Zg31[2.1] == Bus31d
		TR6_31[2.2] ⟷ Zg31[2.2] == Bus31q

		TR10_32[2.1] ⟷ Zg32[2.1] ⟷ LoadB31[1.1] == Bus32d
		TR10_32[2.2] ⟷ Zg32[2.2] ⟷ LoadB31[1.2] == Bus32q

		TR19_33[2.1] ⟷ Zg33[2.1] == Bus33d
		TR19_33[2.2] ⟷ Zg33[2.2] == Bus33q

		TR20_34[2.1] ⟷ Zg34[2.1] == Bus34d
		TR20_34[2.2] ⟷ Zg34[2.2] == Bus34q

		TR22_35[2.1] ⟷ Zg35[2.1] == Bus35d
		TR22_35[2.2] ⟷ Zg35[2.2] == Bus35q

		TR23_36[2.1] ⟷ Zg36[2.1] == Bus36d
		TR23_36[2.2] ⟷ Zg36[2.2] == Bus36q

		TR25_37[2.1] ⟷ Zg37[2.1] == Bus37d
		TR25_37[2.2] ⟷ Zg37[2.2] == Bus37q

		TR29_38[2.1] ⟷ Zg38[2.1] == Bus38d
		TR29_38[2.2] ⟷ Zg38[2.2] == Bus38q

		Zg39[2.1] ⟷ T1_39[2.1] ⟷ T9_39[2.1] ⟷ LoadB39[1.1] == Bus39d
		Zg39[2.2] ⟷ T1_39[2.2] ⟷ T9_39[2.2] ⟷ LoadB39[1.2] == Bus39q

	end
end

function ieee39bus_elements()

	elec = PowerImpedanceACDC.ElectricalTLC(
		Lᵣ = Lf_ST,
		Rᵣ = Rf_ST,
		Sbase = S_ST,
		vACbase_LL_RMS = 345,
		vDCbase = Vdc_ST,
	)

	meas = PowerImpedanceACDC.Measurement(
		v_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 0.5e4),
		i_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 0.5e4),
	)

	sync = PowerImpedanceACDC.PLLSynchronization(
		pi_ctrl = PowerImpedanceACDC.PIControl(
			Kp = 0.397887357729738,
			Ki = 7.957747154594767,
		),
		filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 2π * 80),
	)

	innerVoltage = PowerImpedanceACDC.NoInnerVoltageControl()

	innerCurrent = PowerImpedanceACDC.InnerCurrentPIControl(
		pi_ctrl = PowerImpedanceACDC.PIControl(
			Kp = 0.254647908947033,
			Ki = 0.8,
		),
	)

	mod = PowerImpedanceACDC.PadeModulation(
		timeDelay = 200e-6,
		padeOrderNum = 3,
		padeOrderDen = 3,
	)

	limits = PowerImpedanceACDC.Limits(
		P_min = -1000.0,
		P_max = 1000.0,
		Q_min = -1000.0,
		Q_max = 1000.0,
	)

	outerActive = PowerImpedanceACDC.OuterActiveVdcControl(
		pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 5.0, Ki = 5.0),
		v_dc_ref = 0.0,
	)

	outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
		pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.04, Ki = 40.0),
		support = PowerImpedanceACDC.VoltageSupportLag(
			K = 5.0,
			ωc = 1 / 0.5,
			v_ac_ref = Vm1*sqrt(2)*Vac_ref_ST / elec.vACbase,
		),
	)

	setpoint = PowerImpedanceACDC.SetPoint(
		Pac = 0.0,
		Qac = Q_ST*S_ST,
		θac = 0.0,
		Vac = Vm1*sqrt(2)*Vac_ref_ST,
		Pdc = 0.0,
		Vdc = Vdc_ST,
	)
	return (;





		# Sources @ 345 kV
		G30 = ac_source(pins = 3, V = Vm1, transformation = true),
		G31 = ac_source(pins = 3, V = Vm1, transformation = true),
		G32 = ac_source(pins = 3, V = Vm1, transformation = true),
		G33 = ac_source(pins = 3, V = Vm1, transformation = true),
		G34 = ac_source(pins = 3, V = Vm1, transformation = true),
		G35 = ac_source(pins = 3, V = Vm1, transformation = true),
		G36 = ac_source(pins = 3, V = Vm1, transformation = true),
		G37 = ac_source(pins = 3, V = Vm1, transformation = true),
		G38 = ac_source(pins = 3, V = Vm1, transformation = true),
		G39 = ac_source(pins = 3, V = Vm1, transformation = true),
		# Source impedances @ 345 kV
		Zg30 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg31 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg32 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg33 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg34 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg35 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg36 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg37 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg38 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),
		Zg39 = impedance(
			z = (s::Complex) -> (0.191736 + s*0.0122063),
			pins = 3,
			transformation = true,
		),

		G_DC = dc_source(pins = 1, V = Vdc_ST/2), # DC voltage source to arrange Powerflow of Statcom, not possible to directly connect to DC-controlling STATCOM

		STATCOM = PowerImpedanceACDC.tlc(
			elec = elec,
			meas = meas,
			sync = sync,
			outerActive = outerActive,
			outerReactive = outerReactive,
			innerVoltage = innerVoltage,
			innerCurrent = innerCurrent,
			mod = mod,
			setpoint = setpoint,
			limits = limits,
		),

		dummy_impedance = impedance(z = 1e4, pins = 1), # Dummy impedance to arrange powerflow of DC-controlling STATCOM
		# Transformers

		# Bus 2 - Bus 30

		TR2_30 = transformer(
			n = 345/345,
			Lₚ = (0.0181/2)*Lb_345,
			Lₛ = (0.0181/2)*Lb_345,
			pins = 3,
			transformation = true,
		),


		# Bus 6 - Bus 31

		TR6_31 = transformer(
			n = 345/345,
			Lₚ = (0.025/2)*Lb_345,
			Lₛ = (0.025/2)*Lb_345,
			pins = 3,
			transformation = true,
		),


		# Bus 10 - Bus 32

		TR10_32 = transformer(
			n = 345/345,
			Lₚ = (0.02/2)*Lb_345,
			Lₛ = (0.02/2)*Lb_345,
			pins = 3,
			transformation = true,
		),

		# Bus 11 - Bus 12

		TR11_12 = transformer(
			n = 345/345,
			Lₚ = (0.0435/2)*Lb_345,
			Rₚ = (0.0016/2)*Rb_345,
			Lₛ = (0.0435/2)*Lb_345,
			Rₛ = (0.0016/2)*Rb_345,
			pins = 3,
			transformation = true,
		),

		# Bus 12 - Bus 13

		TR12_13 = transformer(
			n = 345/345,
			Lₚ = (0.0435/2)*Lb_345,
			Rₚ = (0.0016/2)*Rb_345,
			Lₛ = (0.0435/2)*Lb_345,
			Rₛ = (0.0016/2)*Rb_345,
			pins = 3,
			transformation = true,
		),

		# Bus 19 - Bus 20

		TR19_20 = transformer(
			n = 345/345,
			Lₚ = (0.0138 / 2)*Lb_345,
			Rₚ = (0.0007/2)*Rb_345,
			Lₛ = (0.0138 / 2)*Lb_345,
			Rₛ = (0.0007/2)*Rb_345,
			pins = 3,
			transformation = true,
		),

		# Bus 19 - Bus 33

		TR19_33 = transformer(
			n = 345/345,
			Lₚ = (0.0142 / 2)*Lb_345,
			Rₚ = (0.0007/2)*Rb_345,
			Lₛ = (0.0142 / 2)*Lb_345,
			Rₛ = (0.0007/2)*Rb_345,
			pins = 3,
			transformation = true,
		),


		# Bus 20 - Bus 34

		TR20_34 = transformer(
			n = 345/345,
			Lₚ = (0.0180 / 2)*Lb_345,
			Rₚ = (0.0009/2)*Rb_345,
			Lₛ = (0.0180 / 2)*Lb_345,
			Rₛ = (0.0009/2)*Rb_345,
			pins = 3,
			transformation = true,
		),


		# Bus 22 - Bus 35

		TR22_35 = transformer(
			n = 345/345,
			Lₚ = (0.0143 / 2)*Lb_345,
			Lₛ = (0.0143 / 2)*Lb_345,
			pins = 3,
			transformation = true,
		),

		# Bus 23 - Bus 36

		TR23_36 = transformer(
			n = 345/345,
			Lₚ = (0.0272 / 2)*Lb_345,
			Rₚ = (0.0005/2)*Rb_345,
			Lₛ = (0.0272 / 2)*Lb_345,
			Rₛ = (0.0005/2)*Rb_345,
			pins = 3,
			transformation = true,
		),

		# Bus 25 - Bus 37

		TR25_37 = transformer(
			n = 345/345,
			Lₚ = (0.0232 / 2)*Lb_345,
			Rₚ = (0.0006/2)*Rb_345,
			Lₛ = (0.0232 / 2)*Lb_345,
			Rₛ = (0.0006/2)*Rb_345,
			pins = 3,
			transformation = true,
		),

		# Bus 29 - Bus 38

		TR29_38 = transformer(
			n = 345/345,
			Lₚ = (0.0156 / 2)*Lb_345,
			Rₚ = (0.0008/2)*Rb_345,
			Lₛ = (0.0156 / 2)*Lb_345,
			Rₛ = (0.0008/2)*Rb_345,
			pins = 3,
			transformation = true,
		),

		# Power lines

		T1_2 = overhead_line(length = 72.4730e3,
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

		T1_39 = overhead_line(length = 44.0833e3,
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

		T2_3 = overhead_line(length = 26.6263e3,
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

		T2_25 = overhead_line(length = 15.1647e3,
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

		T3_4 = overhead_line(length = 37.5590e3,
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

		T3_18 = overhead_line(length = 23.4523e3,
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

		T4_5 = overhead_line(length = 22.5707e3,
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

		T4_14 = overhead_line(length = 22.7470e3,
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

		T5_6 = overhead_line(length = 4.5847e3,
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

		T5_8 = overhead_line(length = 19.7493e3,
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

		T6_7 = overhead_line(length = 16.2227e3,
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

		T6_11 = overhead_line(length = 14.4593e3,
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

		T7_8 = overhead_line(length = 8.1113e3,
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

		T8_9 = overhead_line(length = 64.009e3,
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
			earth_parameters = (1, 1, 100), transformation = true, connection = false),

		T9_39 = overhead_line(length = 44.0833e3,
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
			earth_parameters = (1, 1, 100), transformation = true, connection = true), # Connection = true --> Line connected, false: disconnected

		T10_11 = overhead_line(length = 7.5823e3,
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

		T10_13 = overhead_line(length = 7.5823e3,
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

		T13_14 = overhead_line(length = 17.8097e3,
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

		T14_15 = overhead_line(length = 38.2643e3,
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

		T15_16 = overhead_line(length = 16.5753e3,
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

		T16_17 = overhead_line(length = 15.6937e3,
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

		T16_19 = overhead_line(length = 34.3850e3,
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

		T16_21 = overhead_line(length = 23.8050e3,
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

		T16_24 = overhead_line(length = 10.4037e3,
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

		T17_18 = overhead_line(length = 14.4593e3,
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

		T17_27 = overhead_line(length = 30.5057e3,
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

		T21_22 = overhead_line(length = 24.6867e3,
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

		T22_23 = overhead_line(length = 16.9280e3,
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

		T23_24 = overhead_line(length = 61.7167e3,
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

		T25_26 = overhead_line(length = 56.95573e3,
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

		T26_27 = overhead_line(length = 25.9210e3,
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

		T26_28 = overhead_line(length = 83.5820e3,
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

		T26_29 = overhead_line(length = 110.2083e3,
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

		T28_29 = overhead_line(length = 26.6263e3,
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

		# Loads

		# Load Bus 3
		LoadB3 =
		impedance(z = (s::Complex) -> (R_B3+s*L_B3), pins = 3, transformation = true),

		# Load Bus 4
		LoadB4a =
		impedance(z = (s::Complex) -> (R_B4a+s*L_B4), pins = 3, transformation = true),
		LoadB4b = impedance(
			z = (s::Complex) -> (R_B4b+(1/(s*C_B4))),
			pins = 3,
			transformation = true,
		),
		# Load Bus 5
		LoadB5 = impedance(
			z = (s::Complex) -> (R_B5+(1/(s*C_B5))),
			pins = 3,
			transformation = true,
		),

		# Load Bus 7
		LoadB7 =
		impedance(z = (s::Complex) -> (R_B7+s*L_B7), pins = 3, transformation = true),

		# Load Bus 8
		LoadB8 =
		impedance(z = (s::Complex) -> (R_B8+s*L_B8), pins = 3, transformation = true),

		# Load Bus 12
		LoadB12 = impedance(
			z = (s::Complex)->(345/230)*(345/230)*(R_B12+s*L_B12),
			pins = 3,
			transformation = true,
		), #Referring load to 345 kV side
		# Load Bus 15
		LoadB15 =
		impedance(z = (s::Complex) -> (R_B15+s*L_B15), pins = 3, transformation = true),

		# Load Bus 16
		LoadB16 =
		impedance(z = (s::Complex) -> (R_B16+s*L_B16), pins = 3, transformation = true),

		# Load Bus 18
		LoadB18 =
		impedance(z = (s::Complex) -> (R_B18+s*L_B18), pins = 3, transformation = true),

		# Load Bus 20
		LoadB20 =
		impedance(z = (s::Complex) -> (R_B20+s*L_B20), pins = 3, transformation = true),

		# Load Bus 21
		LoadB21 =
		impedance(z = (s::Complex) -> (R_B21+s*L_B21), pins = 3, transformation = true),

		# Load Bus 23
		LoadB23 =
		impedance(z = (s::Complex) -> (R_B23+s*L_B23), pins = 3, transformation = true),
		# Load Bus 24
		LoadB24 = impedance(
			z = (s::Complex) -> (R_B24+(1/(s*C_B24))),
			pins = 3,
			transformation = true,
		),

		# Load Bus 25
		LoadB25 =
		impedance(z = (s::Complex) -> (R_B25+s*L_B25), pins = 3, transformation = true),

		# Load Bus 26
		LoadB26 =
		impedance(z = (s::Complex) -> (R_B26+s*L_B26), pins = 3, transformation = true),

		# Load Bus 27
		LoadB27 =
		impedance(z = (s::Complex) -> (R_B27+s*L_B27), pins = 3, transformation = true),

		# Load Bus 28
		LoadB28 =
		impedance(z = (s::Complex) -> (R_B28+s*L_B28), pins = 3, transformation = true),
		# Load Bus 29
		LoadB29 =
		impedance(z = (s::Complex) -> (R_B29+s*L_B29), pins = 3, transformation = true),

		# Load Bus 31
		LoadB31 = impedance(
			z = (s::Complex)->(345/22)*(345/22)*(R_B31+s*L_B31),
			pins = 3,
			transformation = true,
		), #Referring load to 345 kV side

		# Load Bus 39
		LoadB39 =
		impedance(z = (s::Complex) -> (R_B39+s*L_B39), pins = 3, transformation = true))
end

function ieee39bus_connections()
	return (

		# Sources grounding

		pin(:G30, 2.1) ⟷ :gndD,
		pin(:G30, 2.2) ⟷ :gndQ,
		pin(:G31, 2.1) ⟷ :gndD,
		pin(:G31, 2.2) ⟷ :gndQ,
		pin(:G32, 2.1) ⟷ :gndD,
		pin(:G32, 2.2) ⟷ :gndQ,
		pin(:G33, 2.1) ⟷ :gndD,
		pin(:G33, 2.2) ⟷ :gndQ,
		pin(:G34, 2.1) ⟷ :gndD,
		pin(:G34, 2.2) ⟷ :gndQ,
		pin(:G35, 2.1) ⟷ :gndD,
		pin(:G35, 2.2) ⟷ :gndQ,
		pin(:G36, 2.1) ⟷ :gndD,
		pin(:G36, 2.2) ⟷ :gndQ,
		pin(:G37, 2.1) ⟷ :gndD,
		pin(:G37, 2.2) ⟷ :gndQ,
		pin(:G38, 2.1) ⟷ :gndD,
		pin(:G38, 2.2) ⟷ :gndQ,
		pin(:G39, 2.1) ⟷ :gndD,
		pin(:G39, 2.2) ⟷ :gndQ,
		pin(:G_DC, 2.1) ⟷ :gndDC,

		# Loads grounding

		pin(:LoadB3, 2.1) ⟷ :gndD,
		pin(:LoadB3, 2.2) ⟷ :gndQ,
		pin(:LoadB4a, 2.1) ⟷ :gndD,
		pin(:LoadB4a, 2.2) ⟷ :gndQ,
		pin(:LoadB4b, 2.1) ⟷ :gndD,
		pin(:LoadB4b, 2.2) ⟷ :gndQ,
		pin(:LoadB5, 2.1) ⟷ :gndD,
		pin(:LoadB5, 2.2) ⟷ :gndQ,
		pin(:LoadB7, 2.1) ⟷ :gndD,
		pin(:LoadB7, 2.2) ⟷ :gndQ,
		pin(:LoadB8, 2.1) ⟷ :gndD,
		pin(:LoadB8, 2.2) ⟷ :gndQ,
		pin(:LoadB12, 2.1) ⟷ :gndD,
		pin(:LoadB12, 2.2) ⟷ :gndQ,
		pin(:LoadB15, 2.1) ⟷ :gndD,
		pin(:LoadB15, 2.2) ⟷ :gndQ,
		pin(:LoadB16, 2.1) ⟷ :gndD,
		pin(:LoadB16, 2.2) ⟷ :gndQ,
		pin(:LoadB18, 2.1) ⟷ :gndD,
		pin(:LoadB18, 2.2) ⟷ :gndQ,
		pin(:LoadB20, 2.1) ⟷ :gndD,
		pin(:LoadB20, 2.2) ⟷ :gndQ,
		pin(:LoadB21, 2.1) ⟷ :gndD,
		pin(:LoadB21, 2.2) ⟷ :gndQ,
		pin(:LoadB23, 2.1) ⟷ :gndD,
		pin(:LoadB23, 2.2) ⟷ :gndQ,
		pin(:LoadB24, 2.1) ⟷ :gndD,
		pin(:LoadB24, 2.2) ⟷ :gndQ,
		pin(:LoadB25, 2.1) ⟷ :gndD,
		pin(:LoadB25, 2.2) ⟷ :gndQ,
		pin(:LoadB26, 2.1) ⟷ :gndD,
		pin(:LoadB26, 2.2) ⟷ :gndQ,
		pin(:LoadB27, 2.1) ⟷ :gndD,
		pin(:LoadB27, 2.2) ⟷ :gndQ,
		pin(:LoadB28, 2.1) ⟷ :gndD,
		pin(:LoadB28, 2.2) ⟷ :gndQ,
		pin(:LoadB29, 2.1) ⟷ :gndD,
		pin(:LoadB29, 2.2) ⟷ :gndQ,
		pin(:LoadB31, 2.1) ⟷ :gndD,
		pin(:LoadB31, 2.2) ⟷ :gndQ,
		pin(:LoadB39, 2.1) ⟷ :gndD,
		pin(:LoadB39, 2.2) ⟷ :gndQ,

		# Sources

		pin(:G30, 1.1) ⟷ pin(:Zg30, 1.1),
		pin(:G30, 1.2) ⟷ pin(:Zg30, 1.2),
		pin(:G31, 1.1) ⟷ pin(:Zg31, 1.1),
		pin(:G31, 1.2) ⟷ pin(:Zg31, 1.2),
		pin(:G32, 1.1) ⟷ pin(:Zg32, 1.1),
		pin(:G32, 1.2) ⟷ pin(:Zg32, 1.2),
		pin(:G33, 1.1) ⟷ pin(:Zg33, 1.1),
		pin(:G33, 1.2) ⟷ pin(:Zg33, 1.2),
		pin(:G34, 1.1) ⟷ pin(:Zg34, 1.1),
		pin(:G34, 1.2) ⟷ pin(:Zg34, 1.2),
		pin(:G35, 1.1) ⟷ pin(:Zg35, 1.1),
		pin(:G35, 1.2) ⟷ pin(:Zg35, 1.2),
		pin(:G36, 1.1) ⟷ pin(:Zg36, 1.1),
		pin(:G36, 1.2) ⟷ pin(:Zg36, 1.2),
		pin(:G37, 1.1) ⟷ pin(:Zg37, 1.1),
		pin(:G37, 1.2) ⟷ pin(:Zg37, 1.2),
		pin(:G38, 1.1) ⟷ pin(:Zg38, 1.1),
		pin(:G38, 1.2) ⟷ pin(:Zg38, 1.2),
		pin(:G39, 1.1) ⟷ pin(:Zg39, 1.1),
		pin(:G39, 1.2) ⟷ pin(:Zg39, 1.2),
		pin(:G_DC, 1.1) ⟷ pin(:dummy_impedance, 2.1),
		pin(:T1_39, 1.1) ⟷ pin(:T1_2, 1.1) ⟷ :Bus1d,
		pin(:T1_39, 1.2) ⟷ pin(:T1_2, 1.2) ⟷ :Bus1q,
		pin(:T2_25, 1.1) ⟷ pin(:T1_2, 2.1) ⟷ pin(:T2_3, 1.1) ⟷ pin(:TR2_30, 1.1) ⟷ :Bus2d,
		pin(:T2_25, 1.2) ⟷ pin(:T1_2, 2.2) ⟷ pin(:T2_3, 1.2) ⟷ pin(:TR2_30, 1.2) ⟷ :Bus2q,
		pin(:T2_3, 2.1) ⟷ pin(:T3_18, 1.1) ⟷ pin(:T3_4, 1.1) ⟷ pin(:LoadB3, 1.1) ⟷ :Bus3d,
		pin(:T2_3, 2.2) ⟷ pin(:T3_18, 1.2) ⟷ pin(:T3_4, 1.2) ⟷ pin(:LoadB3, 1.2) ⟷ :Bus3q,
		pin(:T3_4, 2.1) ⟷
		pin(:T4_5, 1.1) ⟷
		pin(:T4_14, 1.1) ⟷ pin(:LoadB4a, 1.1) ⟷ pin(:LoadB4b, 1.1) ⟷ :Bus4d,
		pin(:T3_4, 2.2) ⟷
		pin(:T4_5, 1.2) ⟷
		pin(:T4_14, 1.2) ⟷ pin(:LoadB4a, 1.2) ⟷ pin(:LoadB4b, 1.2) ⟷ :Bus4q,
		pin(:T4_5, 2.1) ⟷ pin(:T5_6, 1.1) ⟷ pin(:T5_8, 1.1) ⟷ pin(:LoadB5, 1.1) ⟷ :Bus5d,
		pin(:T4_5, 2.2) ⟷ pin(:T5_6, 1.2) ⟷ pin(:T5_8, 1.2) ⟷ pin(:LoadB5, 1.2) ⟷ :Bus5q,
		pin(:T5_6, 2.1) ⟷ pin(:T6_7, 1.1) ⟷ pin(:T6_11, 1.1) ⟷ pin(:TR6_31, 1.1) ⟷ :Bus6d,
		pin(:T5_6, 2.2) ⟷ pin(:T6_7, 1.2) ⟷ pin(:T6_11, 1.2) ⟷ pin(:TR6_31, 1.2) ⟷ :Bus6q,
		pin(:T6_7, 2.1) ⟷ pin(:T7_8, 1.1) ⟷ pin(:LoadB7, 1.1) ⟷ :Bus7d,
		pin(:T6_7, 2.2) ⟷ pin(:T7_8, 1.2) ⟷ pin(:LoadB7, 1.2) ⟷ :Bus7q,
		pin(:T7_8, 2.1) ⟷ pin(:T8_9, 1.1) ⟷ pin(:T5_8, 2.1) ⟷ pin(:LoadB8, 1.1) ⟷ :Bus8d,
		pin(:T7_8, 2.2) ⟷ pin(:T8_9, 1.2) ⟷ pin(:T5_8, 2.2) ⟷ pin(:LoadB8, 1.2) ⟷ :Bus8q,
		pin(:T8_9, 2.1) ⟷ pin(:T9_39, 1.1) ⟷ pin(:STATCOM, 2.1) ⟷ :Bus9d,
		pin(:T8_9, 2.2) ⟷ pin(:T9_39, 1.2) ⟷ pin(:STATCOM, 2.2) ⟷ :Bus9q,
		pin(:dummy_impedance, 1.1) ⟷ pin(:STATCOM, 1.1),
		pin(:T10_11, 1.1) ⟷ pin(:T10_13, 1.1) ⟷ pin(:TR10_32, 1.1) ⟷ :Bus10d,
		pin(:T10_11, 1.2) ⟷ pin(:T10_13, 1.2) ⟷ pin(:TR10_32, 1.2) ⟷ :Bus10q,
		pin(:T10_11, 2.1) ⟷ pin(:T6_11, 2.1) ⟷ pin(:TR11_12, 1.1) ⟷ :Bus11d,
		pin(:T10_11, 2.2) ⟷ pin(:T6_11, 2.2) ⟷ pin(:TR11_12, 1.2) ⟷ :Bus11q,
		pin(:TR11_12, 2.1) ⟷ pin(:TR12_13, 1.1) ⟷ pin(:LoadB12, 1.1) ⟷ :Bus12d,
		pin(:TR11_12, 2.2) ⟷ pin(:TR12_13, 1.2) ⟷ pin(:LoadB12, 1.2) ⟷ :Bus12q,
		pin(:T10_13, 2.1) ⟷ pin(:T13_14, 1.1) ⟷ pin(:TR12_13, 2.1) ⟷ :Bus13d,
		pin(:T10_13, 2.2) ⟷ pin(:T13_14, 1.2) ⟷ pin(:TR12_13, 2.2) ⟷ :Bus13q,
		pin(:T14_15, 1.1) ⟷ pin(:T13_14, 2.1) ⟷ pin(:T4_14, 2.1) ⟷ :Bus14d,
		pin(:T14_15, 1.2) ⟷ pin(:T13_14, 2.2) ⟷ pin(:T4_14, 2.2) ⟷ :Bus14q,
		pin(:T14_15, 2.1) ⟷ pin(:T15_16, 1.1) ⟷ pin(:LoadB15, 1.1) ⟷ :Bus15d,
		pin(:T14_15, 2.2) ⟷ pin(:T15_16, 1.2) ⟷ pin(:LoadB15, 1.2) ⟷ :Bus15q,
		pin(:T15_16, 2.1) ⟷
		pin(:T16_17, 1.1) ⟷
		pin(:T16_19, 1.1) ⟷
		pin(:T16_21, 1.1) ⟷ pin(:T16_24, 1.1) ⟷ pin(:LoadB16, 1.1) ⟷ :Bus16d,
		pin(:T15_16, 2.2) ⟷
		pin(:T16_17, 1.2) ⟷
		pin(:T16_19, 1.2) ⟷
		pin(:T16_21, 1.2) ⟷ pin(:T16_24, 1.2) ⟷ pin(:LoadB16, 1.2) ⟷ :Bus16q,
		pin(:T16_17, 2.1) ⟷ pin(:T17_18, 1.1) ⟷ pin(:T17_27, 1.1) ⟷ :Bus17d,
		pin(:T16_17, 2.2) ⟷ pin(:T17_18, 1.2) ⟷ pin(:T17_27, 1.2) ⟷ :Bus17q,
		pin(:T17_18, 2.1) ⟷ pin(:LoadB18, 1.1) ⟷ pin(:T3_18, 2.1) ⟷ :Bus18d,
		pin(:T17_18, 2.2) ⟷ pin(:LoadB18, 1.2) ⟷ pin(:T3_18, 2.2) ⟷ :Bus18q,
		pin(:T16_19, 2.1) ⟷ pin(:TR19_20, 1.1) ⟷ pin(:TR19_33, 1.1) ⟷ :Bus19d,
		pin(:T16_19, 2.2) ⟷ pin(:TR19_20, 1.2) ⟷ pin(:TR19_33, 1.2) ⟷ :Bus19q,
		pin(:TR19_20, 2.1) ⟷ pin(:TR20_34, 1.1) ⟷ pin(:LoadB20, 1.1) ⟷ :Bus20d,
		pin(:TR19_20, 2.2) ⟷ pin(:TR20_34, 1.2) ⟷ pin(:LoadB20, 1.2) ⟷ :Bus20q,
		pin(:T16_21, 2.1) ⟷ pin(:LoadB21, 1.1) ⟷ pin(:T21_22, 1.1) ⟷ :Bus21d,
		pin(:T16_21, 2.2) ⟷ pin(:LoadB21, 1.2) ⟷ pin(:T21_22, 1.2) ⟷ :Bus21q,
		pin(:T21_22, 2.1) ⟷ pin(:T22_23, 1.1) ⟷ pin(:TR22_35, 1.1) ⟷ :Bus22d,
		pin(:T21_22, 2.2) ⟷ pin(:T22_23, 1.2) ⟷ pin(:TR22_35, 1.2) ⟷ :Bus22q,
		pin(:T22_23, 2.1) ⟷
		pin(:LoadB23, 1.1) ⟷ pin(:T23_24, 1.1) ⟷ pin(:TR23_36, 1.1) ⟷ :Bus23d,
		pin(:T22_23, 2.2) ⟷
		pin(:LoadB23, 1.2) ⟷ pin(:T23_24, 1.2) ⟷ pin(:TR23_36, 1.2) ⟷ :Bus23q,
		pin(:T16_24, 2.1) ⟷ pin(:T23_24, 2.1) ⟷ pin(:LoadB24, 1.1) ⟷ :Bus24d,
		pin(:T16_24, 2.2) ⟷ pin(:T23_24, 2.2) ⟷ pin(:LoadB24, 1.2) ⟷ :Bus24q,
		pin(:T2_25, 2.1) ⟷
		pin(:LoadB25, 1.1) ⟷ pin(:T25_26, 1.1) ⟷ pin(:TR25_37, 1.1) ⟷ :Bus25d,
		pin(:T2_25, 2.2) ⟷
		pin(:LoadB25, 1.2) ⟷ pin(:T25_26, 1.2) ⟷ pin(:TR25_37, 1.2) ⟷ :Bus25q,
		pin(:T25_26, 2.1) ⟷
		pin(:LoadB26, 1.1) ⟷
		pin(:T26_27, 1.1) ⟷ pin(:T26_28, 1.1) ⟷ pin(:T26_29, 1.1) ⟷ :Bus26d,
		pin(:T25_26, 2.2) ⟷
		pin(:LoadB26, 1.2) ⟷
		pin(:T26_27, 1.2) ⟷ pin(:T26_28, 1.2) ⟷ pin(:T26_29, 1.2) ⟷ :Bus26q,
		pin(:T26_27, 2.1) ⟷ pin(:T17_27, 2.1) ⟷ pin(:LoadB27, 1.1) ⟷ :Bus27d,
		pin(:T26_27, 2.2) ⟷ pin(:T17_27, 2.2) ⟷ pin(:LoadB27, 1.2) ⟷ :Bus27q,
		pin(:T26_28, 2.1) ⟷ pin(:T28_29, 1.1) ⟷ pin(:LoadB28, 1.1) ⟷ :Bus28d,
		pin(:T26_28, 2.2) ⟷ pin(:T28_29, 1.2) ⟷ pin(:LoadB28, 1.2) ⟷ :Bus28q,
		pin(:T26_29, 2.1) ⟷
		pin(:LoadB29, 1.1) ⟷ pin(:T28_29, 2.1) ⟷ pin(:TR29_38, 1.1) ⟷ :Bus29d,
		pin(:T26_29, 2.2) ⟷
		pin(:LoadB29, 1.2) ⟷ pin(:T28_29, 2.2) ⟷ pin(:TR29_38, 1.2) ⟷ :Bus29q,
		pin(:TR2_30, 2.1) ⟷ pin(:Zg30, 2.1) ⟷ :Bus30d,
		pin(:TR2_30, 2.2) ⟷ pin(:Zg30, 2.2) ⟷ :Bus30q,
		pin(:TR6_31, 2.1) ⟷ pin(:Zg31, 2.1) ⟷ :Bus31d,
		pin(:TR6_31, 2.2) ⟷ pin(:Zg31, 2.2) ⟷ :Bus31q,
		pin(:TR10_32, 2.1) ⟷ pin(:Zg32, 2.1) ⟷ pin(:LoadB31, 1.1) ⟷ :Bus32d,
		pin(:TR10_32, 2.2) ⟷ pin(:Zg32, 2.2) ⟷ pin(:LoadB31, 1.2) ⟷ :Bus32q,
		pin(:TR19_33, 2.1) ⟷ pin(:Zg33, 2.1) ⟷ :Bus33d,
		pin(:TR19_33, 2.2) ⟷ pin(:Zg33, 2.2) ⟷ :Bus33q,
		pin(:TR20_34, 2.1) ⟷ pin(:Zg34, 2.1) ⟷ :Bus34d,
		pin(:TR20_34, 2.2) ⟷ pin(:Zg34, 2.2) ⟷ :Bus34q,
		pin(:TR22_35, 2.1) ⟷ pin(:Zg35, 2.1) ⟷ :Bus35d,
		pin(:TR22_35, 2.2) ⟷ pin(:Zg35, 2.2) ⟷ :Bus35q,
		pin(:TR23_36, 2.1) ⟷ pin(:Zg36, 2.1) ⟷ :Bus36d,
		pin(:TR23_36, 2.2) ⟷ pin(:Zg36, 2.2) ⟷ :Bus36q,
		pin(:TR25_37, 2.1) ⟷ pin(:Zg37, 2.1) ⟷ :Bus37d,
		pin(:TR25_37, 2.2) ⟷ pin(:Zg37, 2.2) ⟷ :Bus37q,
		pin(:TR29_38, 2.1) ⟷ pin(:Zg38, 2.1) ⟷ :Bus38d,
		pin(:TR29_38, 2.2) ⟷ pin(:Zg38, 2.2) ⟷ :Bus38q,
		pin(:Zg39, 2.1) ⟷
		pin(:T1_39, 2.1) ⟷ pin(:T9_39, 2.1) ⟷ pin(:LoadB39, 1.1) ⟷ :Bus39d,
		pin(:Zg39, 2.2) ⟷
		pin(:T1_39, 2.2) ⟷ pin(:T9_39, 2.2) ⟷ pin(:LoadB39, 1.2) ⟷ :Bus39q)
end

function build_ieee39bus_with_networkbuilder()

	builder_options = (;
		voltageBase = Vm1,
		power_flow = (;
			is_bounded = (;
				bus_voltage = true,
			),
		),
	)

	builder = NetworkBuilder.define(
		ieee39bus_elements(),
		ieee39bus_connections();
		options = builder_options,
	)
	solved = NetworkBuilder.solve(builder)
	return (; builder, solved, network = builder.network)
end

function determine_ieee39bus_impedance(network; freq_range = IEEE39_FREQ_RANGE)
	return determine_impedance(
		network;
		input_pins = IEEE39_INPUT_PINS,
		output_pins = IEEE39_OUTPUT_PINS,
		elim_elements = IEEE39_ELIM_ELEMENTS,
		freq_range = freq_range,
	)
end

function test_ieee39bus_networkbuilder_parity(; freq_range = IEEE39_FREQ_RANGE)
	legacy = build_ieee39bus_with_macro()
	built = build_ieee39bus_with_networkbuilder().network

	z_legacy, omega_legacy = determine_ieee39bus_impedance(legacy; freq_range)
	z_built, omega_built = determine_ieee39bus_impedance(built; freq_range)

	@test isequal(omega_built, omega_legacy)
	@test axes(z_built) == axes(z_legacy)
	@test isequal(z_built, z_legacy)

	return nothing
end

@testset "IEEE39bus NetworkBuilder parity" begin
	test_ieee39bus_networkbuilder_parity()
end

@testset "NetworkBuilder drops endpoints of declared disconnected elements" begin
	elements = (;
		a = impedance(z = 1.0, pins = 1),
		b = impedance(z = 2.0, pins = 1),
		open_line = overhead_line(
			length = 1e3,
			conductors = Conductors(
				organization = :flat,
				nᵇ = 3,
				nˢᵇ = 1,
				Rᵈᶜ = 0.063,
				rᶜ = 0.015,
				yᵇᶜ = 30,
				Δyᵇᶜ = 0,
				Δxᵇᶜ = 10,
				Δ̃xᵇᶜ = 0,
				dˢᵇ = 0,
				dˢᵃᵍ = 10,
			),
			groundwires = Groundwires(
				nᵍ = 2,
				Rᵍᵈᶜ = 0.92,
				rᵍ = 0.0062,
				Δxᵍ = 6.5,
				Δyᵍ = 7.5,
				dᵍˢᵃᵍ = 10,
			),
			earth_parameters = (1, 1, 100),
			transformation = true,
			connection = false,
		),
	)

	connections = (
		pin(:a, 1.1) ⟷ pin(:open_line, 1.1) ⟷ pin(:b, 1.1) ⟷ :B,
		pin(:a, 2.1) ⟷ :gnd,
		pin(:b, 2.1) ⟷ :gnd,
	)

	builder = NetworkBuilder.define(elements, connections)

	@test !haskey(builder.network.elements, :open_line)
	@test builder.network.elements[:a].pins[Symbol("1.1")] == :B
	@test builder.network.elements[:b].pins[Symbol("1.1")] == :B
	@test builder.network.elements[:a].pins[Symbol("2.1")] == :gnd
	@test builder.network.elements[:b].pins[Symbol("2.1")] == :gnd
end