using PowerImpedance.NetworkBuilder: powerflow_optimizer, is_bounded_options,
powerflow_setting, solve_acdcpf, get_y, NetworkModel
using LinearAlgebra
using PowerImpedance
import PowerImpedance: @network
using Test

if !isdefined(@__MODULE__, :PI)
	const PI = PowerImpedance
end
if !isdefined(@__MODULE__, :NB)
	const NB = PowerImpedance.NetworkBuilder
end

@testset "NetworkBuilder unit tests" begin
	legacy = @network begin
		z1 = impedance(z = 1, pins = 1)
		z2 = impedance(z = 2, pins = 1)

		z1[1.1] ⟷ z2[1.1] ⟷ n1
		z1[2.1] ⟷ z2[2.1] ⟷ gnd
	end

	elements = (; z1 = impedance(z = 1, pins = 1), z2 = impedance(z = 2, pins = 1))
	connections = (
		(node = :n1, element = :z1, side = 1, terminal = 1),
		(node = :n1, element = :z2, side = 1, terminal = 1),
		(node = :gnd, element = :z1, side = 2, terminal = 1),
		(node = :gnd, element = :z2, side = 2, terminal = 1),
	)

	builder = NetworkBuilder.define(elements, connections)
	buildernetwork = NetworkBuilder.build_network(
		builder.elements,
		builder.topology,
		builder.options,
	)

	@test collect(keys(buildernetwork.elements)) == collect(keys(legacy.elements))
	@test Set(buildernetwork.nets[:n1]) == Set(legacy.nets[:n1])
	@test Set(buildernetwork.nets[:gnd]) == Set(legacy.nets[:gnd])
	@test buildernetwork.elements[:z1].pins == legacy.elements[:z1].pins
	@test buildernetwork.elements[:z2].pins == legacy.elements[:z2].pins

	@test NetworkBuilder.solve(builder).powerflow === nothing

	updated_elements = (; z1 = impedance(z = 3, pins = 1), z2 = impedance(z = 4, pins = 1))
	updated = NetworkBuilder.update!(builder; elements = updated_elements)
	updatednetwork = NetworkBuilder.build_network(
		builder.elements,
		builder.topology,
		builder.options,
	)

	@test updated.operating_point === nothing
	@test builder.elements[:z1].element_model.value == ComplexF64[3;;]
	@test Set(updatednetwork.nets[:n1]) == Set(updatednetwork.nets[:n1])
end


# This is a PowerImpedance implementation of the IEEE 39 bus system test system
# Author: Jan Kircheis 
# Date: Jan 2026
# Related PSCAD model to be found under Etch: Control-->PowerImpedance-->IEEE 39-bus system
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
	elec = PowerImpedance.ElectricalTLC(
		Lᵣ = Lf_ST,
		Rᵣ = Rf_ST,
		Sbase = S_ST,
		vACbase_LL_RMS = 345,
		vDCbase = Vdc_ST,
	)

	meas = PowerImpedance.Measurement(
		v_ac = PowerImpedance.Butterworth(order = 2, ωc = 0.5e4),
		i_ac = PowerImpedance.Butterworth(order = 2, ωc = 0.5e4),
	)

	sync = PowerImpedance.PLLSynchronization(
		pi_ctrl = PowerImpedance.PIControl(
			Kp = 0.397887357729738,
			Ki = 7.957747154594767,
		),
		filter = PowerImpedance.Butterworth(order = 2, ωc = 2π * 80),
	)

	innerVoltage = PowerImpedance.NoInnerVoltageControl()

	innerCurrent = PowerImpedance.InnerCurrentPIControl(
		pi_ctrl = PowerImpedance.PIControl(
			Kp = 0.254647908947033,
			Ki = 0.8,
		),
	)

	mod = PowerImpedance.PadeModulation(
		timeDelay = 200e-6,
		padeOrderNum = 3,
		padeOrderDen = 3,
	)

	limits = PowerImpedance.Limits(
		P_min = -1000.0,
		P_max = 1000.0,
		Q_min = -1000.0,
		Q_max = 1000.0,
	)

	outerActive = PowerImpedance.OuterActiveVdcControl(
		pi_ctrl = PowerImpedance.PIControl(Kp = 5.0, Ki = 5.0),
	)

	outerReactive = PowerImpedance.OuterReactiveQControl(
		pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
		support = PowerImpedance.VoltageSupportLag(
			K = 5.0,
			ωc = 1 / 0.5,
		),
	)

	setpoint = PowerImpedance.Setpoint(
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
		G30=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G31=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G32=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G33=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G34=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G35=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G36=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G37=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G38=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
		G39=ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true)
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

		G_DC=dc_source(pins = 1, setpoint=Setpoint(Vdc = Vdc_ST/2)) # DC voltage source to arrange Powerflow of Statcom, not possible to directly connect to DC-controlling STATCOM



		STATCOM = PowerImpedance.tlc(
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

	elec = PowerImpedance.ElectricalTLC(
		Lᵣ = Lf_ST,
		Rᵣ = Rf_ST,
		Sbase = S_ST,
		vACbase_LL_RMS = 345,
		vDCbase = Vdc_ST,
	)

	meas = PowerImpedance.Measurement(
		v_ac = PowerImpedance.Butterworth(order = 2, ωc = 0.5e4),
		i_ac = PowerImpedance.Butterworth(order = 2, ωc = 0.5e4),
	)

	sync = PowerImpedance.PLLSynchronization(
		pi_ctrl = PowerImpedance.PIControl(
			Kp = 0.397887357729738,
			Ki = 7.957747154594767,
		),
		filter = PowerImpedance.Butterworth(order = 2, ωc = 2π * 80),
	)

	innerVoltage = PowerImpedance.NoInnerVoltageControl()

	innerCurrent = PowerImpedance.InnerCurrentPIControl(
		pi_ctrl = PowerImpedance.PIControl(
			Kp = 0.254647908947033,
			Ki = 0.8,
		),
	)

	mod = PowerImpedance.PadeModulation(
		timeDelay = 200e-6,
		padeOrderNum = 3,
		padeOrderDen = 3,
	)

	limits = PowerImpedance.Limits(
		P_min = -1000.0,
		P_max = 1000.0,
		Q_min = -1000.0,
		Q_max = 1000.0,
	)

	outerActive = PowerImpedance.OuterActiveVdcControl(
		pi_ctrl = PowerImpedance.PIControl(Kp = 5.0, Ki = 5.0),
	)

	outerReactive = PowerImpedance.OuterReactiveQControl(
		pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
		support = PowerImpedance.VoltageSupportLag(
			K = 5.0,
			ωc = 1 / 0.5,
		),
	)

	setpoint = PowerImpedance.Setpoint(
		Pac = 0.0,
		Qac = Q_ST*S_ST,
		θac = 0.0,
		Vac = Vm1*sqrt(2)*Vac_ref_ST,
		Pdc = 0.0,
		Vdc = Vdc_ST,
	)
	return (;





		# Sources @ 345 kV
		G30 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G31 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G32 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G33 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G34 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G35 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G36 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G37 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G38 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
		G39 = ac_source(pins = 3, setpoint=Setpoint(Vac = Vm1), transformation = true),
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

		G_DC = dc_source(pins = 1, setpoint=Setpoint(Vdc = Vdc_ST/2)), # DC voltage source to arrange Powerflow of Statcom, not possible to directly connect to DC-controlling STATCOM

		STATCOM = PowerImpedance.tlc(
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
		(node = :gndD, element = :LoadB3, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB3, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB4a, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB4a, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB4b, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB4b, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB5, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB5, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB7, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB7, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB8, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB8, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB12, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB12, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB15, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB15, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB16, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB16, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB18, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB18, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB20, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB20, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB21, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB21, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB23, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB23, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB24, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB24, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB25, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB25, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB26, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB26, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB27, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB27, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB28, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB28, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB29, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB29, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB31, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB31, side = 2, terminal = 2),
		(node = :gndD, element = :LoadB39, side = 2, terminal = 1),
		(node = :gndQ, element = :LoadB39, side = 2, terminal = 2),
		(node = :link_G30_Zg30_1, element = :G30, side = 1, terminal = 1),
		(node = :link_G30_Zg30_1, element = :Zg30, side = 1, terminal = 1),
		(node = :link_G30_Zg30_2, element = :G30, side = 1, terminal = 2),
		(node = :link_G30_Zg30_2, element = :Zg30, side = 1, terminal = 2),
		(node = :link_G31_Zg31_1, element = :G31, side = 1, terminal = 1),
		(node = :link_G31_Zg31_1, element = :Zg31, side = 1, terminal = 1),
		(node = :link_G31_Zg31_2, element = :G31, side = 1, terminal = 2),
		(node = :link_G31_Zg31_2, element = :Zg31, side = 1, terminal = 2),
		(node = :link_G32_Zg32_1, element = :G32, side = 1, terminal = 1),
		(node = :link_G32_Zg32_1, element = :Zg32, side = 1, terminal = 1),
		(node = :link_G32_Zg32_2, element = :G32, side = 1, terminal = 2),
		(node = :link_G32_Zg32_2, element = :Zg32, side = 1, terminal = 2),
		(node = :link_G33_Zg33_1, element = :G33, side = 1, terminal = 1),
		(node = :link_G33_Zg33_1, element = :Zg33, side = 1, terminal = 1),
		(node = :link_G33_Zg33_2, element = :G33, side = 1, terminal = 2),
		(node = :link_G33_Zg33_2, element = :Zg33, side = 1, terminal = 2),
		(node = :link_G34_Zg34_1, element = :G34, side = 1, terminal = 1),
		(node = :link_G34_Zg34_1, element = :Zg34, side = 1, terminal = 1),
		(node = :link_G34_Zg34_2, element = :G34, side = 1, terminal = 2),
		(node = :link_G34_Zg34_2, element = :Zg34, side = 1, terminal = 2),
		(node = :link_G35_Zg35_1, element = :G35, side = 1, terminal = 1),
		(node = :link_G35_Zg35_1, element = :Zg35, side = 1, terminal = 1),
		(node = :link_G35_Zg35_2, element = :G35, side = 1, terminal = 2),
		(node = :link_G35_Zg35_2, element = :Zg35, side = 1, terminal = 2),
		(node = :link_G36_Zg36_1, element = :G36, side = 1, terminal = 1),
		(node = :link_G36_Zg36_1, element = :Zg36, side = 1, terminal = 1),
		(node = :link_G36_Zg36_2, element = :G36, side = 1, terminal = 2),
		(node = :link_G36_Zg36_2, element = :Zg36, side = 1, terminal = 2),
		(node = :link_G37_Zg37_1, element = :G37, side = 1, terminal = 1),
		(node = :link_G37_Zg37_1, element = :Zg37, side = 1, terminal = 1),
		(node = :link_G37_Zg37_2, element = :G37, side = 1, terminal = 2),
		(node = :link_G37_Zg37_2, element = :Zg37, side = 1, terminal = 2),
		(node = :link_G38_Zg38_1, element = :G38, side = 1, terminal = 1),
		(node = :link_G38_Zg38_1, element = :Zg38, side = 1, terminal = 1),
		(node = :link_G38_Zg38_2, element = :G38, side = 1, terminal = 2),
		(node = :link_G38_Zg38_2, element = :Zg38, side = 1, terminal = 2),
		(node = :link_G39_Zg39_1, element = :G39, side = 1, terminal = 1),
		(node = :link_G39_Zg39_1, element = :Zg39, side = 1, terminal = 1),
		(node = :link_G39_Zg39_2, element = :G39, side = 1, terminal = 2),
		(node = :link_G39_Zg39_2, element = :Zg39, side = 1, terminal = 2),
		(node = :link_G_DC_dummy_impedance_1, element = :G_DC, side = 1, terminal = 1),
		(node = :link_G_DC_dummy_impedance_1, element = :dummy_impedance, side = 2, terminal = 1),
		(node = :Bus1d, element = :T1_39, side = 1, terminal = 1),
		(node = :Bus1d, element = :T1_2, side = 1, terminal = 1),
		(node = :Bus1q, element = :T1_39, side = 1, terminal = 2),
		(node = :Bus1q, element = :T1_2, side = 1, terminal = 2),
		(node = :Bus2d, element = :T2_25, side = 1, terminal = 1),
		(node = :Bus2d, element = :T1_2, side = 2, terminal = 1),
		(node = :Bus2d, element = :T2_3, side = 1, terminal = 1),
		(node = :Bus2d, element = :TR2_30, side = 1, terminal = 1),
		(node = :Bus2q, element = :T2_25, side = 1, terminal = 2),
		(node = :Bus2q, element = :T1_2, side = 2, terminal = 2),
		(node = :Bus2q, element = :T2_3, side = 1, terminal = 2),
		(node = :Bus2q, element = :TR2_30, side = 1, terminal = 2),
		(node = :Bus3d, element = :T2_3, side = 2, terminal = 1),
		(node = :Bus3d, element = :T3_18, side = 1, terminal = 1),
		(node = :Bus3d, element = :T3_4, side = 1, terminal = 1),
		(node = :Bus3d, element = :LoadB3, side = 1, terminal = 1),
		(node = :Bus3q, element = :T2_3, side = 2, terminal = 2),
		(node = :Bus3q, element = :T3_18, side = 1, terminal = 2),
		(node = :Bus3q, element = :T3_4, side = 1, terminal = 2),
		(node = :Bus3q, element = :LoadB3, side = 1, terminal = 2),
		(node = :Bus4d, element = :T3_4, side = 2, terminal = 1),
		(node = :Bus4d, element = :T4_5, side = 1, terminal = 1),
		(node = :Bus4d, element = :T4_14, side = 1, terminal = 1),
		(node = :Bus4d, element = :LoadB4a, side = 1, terminal = 1),
		(node = :Bus4d, element = :LoadB4b, side = 1, terminal = 1),
		(node = :Bus4q, element = :T3_4, side = 2, terminal = 2),
		(node = :Bus4q, element = :T4_5, side = 1, terminal = 2),
		(node = :Bus4q, element = :T4_14, side = 1, terminal = 2),
		(node = :Bus4q, element = :LoadB4a, side = 1, terminal = 2),
		(node = :Bus4q, element = :LoadB4b, side = 1, terminal = 2),
		(node = :Bus5d, element = :T4_5, side = 2, terminal = 1),
		(node = :Bus5d, element = :T5_6, side = 1, terminal = 1),
		(node = :Bus5d, element = :T5_8, side = 1, terminal = 1),
		(node = :Bus5d, element = :LoadB5, side = 1, terminal = 1),
		(node = :Bus5q, element = :T4_5, side = 2, terminal = 2),
		(node = :Bus5q, element = :T5_6, side = 1, terminal = 2),
		(node = :Bus5q, element = :T5_8, side = 1, terminal = 2),
		(node = :Bus5q, element = :LoadB5, side = 1, terminal = 2),
		(node = :Bus6d, element = :T5_6, side = 2, terminal = 1),
		(node = :Bus6d, element = :T6_7, side = 1, terminal = 1),
		(node = :Bus6d, element = :T6_11, side = 1, terminal = 1),
		(node = :Bus6d, element = :TR6_31, side = 1, terminal = 1),
		(node = :Bus6q, element = :T5_6, side = 2, terminal = 2),
		(node = :Bus6q, element = :T6_7, side = 1, terminal = 2),
		(node = :Bus6q, element = :T6_11, side = 1, terminal = 2),
		(node = :Bus6q, element = :TR6_31, side = 1, terminal = 2),
		(node = :Bus7d, element = :T6_7, side = 2, terminal = 1),
		(node = :Bus7d, element = :T7_8, side = 1, terminal = 1),
		(node = :Bus7d, element = :LoadB7, side = 1, terminal = 1),
		(node = :Bus7q, element = :T6_7, side = 2, terminal = 2),
		(node = :Bus7q, element = :T7_8, side = 1, terminal = 2),
		(node = :Bus7q, element = :LoadB7, side = 1, terminal = 2),
		(node = :Bus8d, element = :T7_8, side = 2, terminal = 1),
		(node = :Bus8d, element = :T8_9, side = 1, terminal = 1),
		(node = :Bus8d, element = :T5_8, side = 2, terminal = 1),
		(node = :Bus8d, element = :LoadB8, side = 1, terminal = 1),
		(node = :Bus8q, element = :T7_8, side = 2, terminal = 2),
		(node = :Bus8q, element = :T8_9, side = 1, terminal = 2),
		(node = :Bus8q, element = :T5_8, side = 2, terminal = 2),
		(node = :Bus8q, element = :LoadB8, side = 1, terminal = 2),
		(node = :Bus9d, element = :T8_9, side = 2, terminal = 1),
		(node = :Bus9d, element = :T9_39, side = 1, terminal = 1),
		(node = :Bus9d, element = :STATCOM, side = 2, terminal = 1),
		(node = :Bus9q, element = :T8_9, side = 2, terminal = 2),
		(node = :Bus9q, element = :T9_39, side = 1, terminal = 2),
		(node = :Bus9q, element = :STATCOM, side = 2, terminal = 2),
		(node = :link_dummy_impedance_STATCOM_1, element = :dummy_impedance, side = 1, terminal = 1),
		(node = :link_dummy_impedance_STATCOM_1, element = :STATCOM, side = 1, terminal = 1),
		(node = :Bus10d, element = :T10_11, side = 1, terminal = 1),
		(node = :Bus10d, element = :T10_13, side = 1, terminal = 1),
		(node = :Bus10d, element = :TR10_32, side = 1, terminal = 1),
		(node = :Bus10q, element = :T10_11, side = 1, terminal = 2),
		(node = :Bus10q, element = :T10_13, side = 1, terminal = 2),
		(node = :Bus10q, element = :TR10_32, side = 1, terminal = 2),
		(node = :Bus11d, element = :T10_11, side = 2, terminal = 1),
		(node = :Bus11d, element = :T6_11, side = 2, terminal = 1),
		(node = :Bus11d, element = :TR11_12, side = 1, terminal = 1),
		(node = :Bus11q, element = :T10_11, side = 2, terminal = 2),
		(node = :Bus11q, element = :T6_11, side = 2, terminal = 2),
		(node = :Bus11q, element = :TR11_12, side = 1, terminal = 2),
		(node = :Bus12d, element = :TR11_12, side = 2, terminal = 1),
		(node = :Bus12d, element = :TR12_13, side = 1, terminal = 1),
		(node = :Bus12d, element = :LoadB12, side = 1, terminal = 1),
		(node = :Bus12q, element = :TR11_12, side = 2, terminal = 2),
		(node = :Bus12q, element = :TR12_13, side = 1, terminal = 2),
		(node = :Bus12q, element = :LoadB12, side = 1, terminal = 2),
		(node = :Bus13d, element = :T10_13, side = 2, terminal = 1),
		(node = :Bus13d, element = :T13_14, side = 1, terminal = 1),
		(node = :Bus13d, element = :TR12_13, side = 2, terminal = 1),
		(node = :Bus13q, element = :T10_13, side = 2, terminal = 2),
		(node = :Bus13q, element = :T13_14, side = 1, terminal = 2),
		(node = :Bus13q, element = :TR12_13, side = 2, terminal = 2),
		(node = :Bus14d, element = :T14_15, side = 1, terminal = 1),
		(node = :Bus14d, element = :T13_14, side = 2, terminal = 1),
		(node = :Bus14d, element = :T4_14, side = 2, terminal = 1),
		(node = :Bus14q, element = :T14_15, side = 1, terminal = 2),
		(node = :Bus14q, element = :T13_14, side = 2, terminal = 2),
		(node = :Bus14q, element = :T4_14, side = 2, terminal = 2),
		(node = :Bus15d, element = :T14_15, side = 2, terminal = 1),
		(node = :Bus15d, element = :T15_16, side = 1, terminal = 1),
		(node = :Bus15d, element = :LoadB15, side = 1, terminal = 1),
		(node = :Bus15q, element = :T14_15, side = 2, terminal = 2),
		(node = :Bus15q, element = :T15_16, side = 1, terminal = 2),
		(node = :Bus15q, element = :LoadB15, side = 1, terminal = 2),
		(node = :Bus16d, element = :T15_16, side = 2, terminal = 1),
		(node = :Bus16d, element = :T16_17, side = 1, terminal = 1),
		(node = :Bus16d, element = :T16_19, side = 1, terminal = 1),
		(node = :Bus16d, element = :T16_21, side = 1, terminal = 1),
		(node = :Bus16d, element = :T16_24, side = 1, terminal = 1),
		(node = :Bus16d, element = :LoadB16, side = 1, terminal = 1),
		(node = :Bus16q, element = :T15_16, side = 2, terminal = 2),
		(node = :Bus16q, element = :T16_17, side = 1, terminal = 2),
		(node = :Bus16q, element = :T16_19, side = 1, terminal = 2),
		(node = :Bus16q, element = :T16_21, side = 1, terminal = 2),
		(node = :Bus16q, element = :T16_24, side = 1, terminal = 2),
		(node = :Bus16q, element = :LoadB16, side = 1, terminal = 2),
		(node = :Bus17d, element = :T16_17, side = 2, terminal = 1),
		(node = :Bus17d, element = :T17_18, side = 1, terminal = 1),
		(node = :Bus17d, element = :T17_27, side = 1, terminal = 1),
		(node = :Bus17q, element = :T16_17, side = 2, terminal = 2),
		(node = :Bus17q, element = :T17_18, side = 1, terminal = 2),
		(node = :Bus17q, element = :T17_27, side = 1, terminal = 2),
		(node = :Bus18d, element = :T17_18, side = 2, terminal = 1),
		(node = :Bus18d, element = :LoadB18, side = 1, terminal = 1),
		(node = :Bus18d, element = :T3_18, side = 2, terminal = 1),
		(node = :Bus18q, element = :T17_18, side = 2, terminal = 2),
		(node = :Bus18q, element = :LoadB18, side = 1, terminal = 2),
		(node = :Bus18q, element = :T3_18, side = 2, terminal = 2),
		(node = :Bus19d, element = :T16_19, side = 2, terminal = 1),
		(node = :Bus19d, element = :TR19_20, side = 1, terminal = 1),
		(node = :Bus19d, element = :TR19_33, side = 1, terminal = 1),
		(node = :Bus19q, element = :T16_19, side = 2, terminal = 2),
		(node = :Bus19q, element = :TR19_20, side = 1, terminal = 2),
		(node = :Bus19q, element = :TR19_33, side = 1, terminal = 2),
		(node = :Bus20d, element = :TR19_20, side = 2, terminal = 1),
		(node = :Bus20d, element = :TR20_34, side = 1, terminal = 1),
		(node = :Bus20d, element = :LoadB20, side = 1, terminal = 1),
		(node = :Bus20q, element = :TR19_20, side = 2, terminal = 2),
		(node = :Bus20q, element = :TR20_34, side = 1, terminal = 2),
		(node = :Bus20q, element = :LoadB20, side = 1, terminal = 2),
		(node = :Bus21d, element = :T16_21, side = 2, terminal = 1),
		(node = :Bus21d, element = :LoadB21, side = 1, terminal = 1),
		(node = :Bus21d, element = :T21_22, side = 1, terminal = 1),
		(node = :Bus21q, element = :T16_21, side = 2, terminal = 2),
		(node = :Bus21q, element = :LoadB21, side = 1, terminal = 2),
		(node = :Bus21q, element = :T21_22, side = 1, terminal = 2),
		(node = :Bus22d, element = :T21_22, side = 2, terminal = 1),
		(node = :Bus22d, element = :T22_23, side = 1, terminal = 1),
		(node = :Bus22d, element = :TR22_35, side = 1, terminal = 1),
		(node = :Bus22q, element = :T21_22, side = 2, terminal = 2),
		(node = :Bus22q, element = :T22_23, side = 1, terminal = 2),
		(node = :Bus22q, element = :TR22_35, side = 1, terminal = 2),
		(node = :Bus23d, element = :T22_23, side = 2, terminal = 1),
		(node = :Bus23d, element = :LoadB23, side = 1, terminal = 1),
		(node = :Bus23d, element = :T23_24, side = 1, terminal = 1),
		(node = :Bus23d, element = :TR23_36, side = 1, terminal = 1),
		(node = :Bus23q, element = :T22_23, side = 2, terminal = 2),
		(node = :Bus23q, element = :LoadB23, side = 1, terminal = 2),
		(node = :Bus23q, element = :T23_24, side = 1, terminal = 2),
		(node = :Bus23q, element = :TR23_36, side = 1, terminal = 2),
		(node = :Bus24d, element = :T16_24, side = 2, terminal = 1),
		(node = :Bus24d, element = :T23_24, side = 2, terminal = 1),
		(node = :Bus24d, element = :LoadB24, side = 1, terminal = 1),
		(node = :Bus24q, element = :T16_24, side = 2, terminal = 2),
		(node = :Bus24q, element = :T23_24, side = 2, terminal = 2),
		(node = :Bus24q, element = :LoadB24, side = 1, terminal = 2),
		(node = :Bus25d, element = :T2_25, side = 2, terminal = 1),
		(node = :Bus25d, element = :LoadB25, side = 1, terminal = 1),
		(node = :Bus25d, element = :T25_26, side = 1, terminal = 1),
		(node = :Bus25d, element = :TR25_37, side = 1, terminal = 1),
		(node = :Bus25q, element = :T2_25, side = 2, terminal = 2),
		(node = :Bus25q, element = :LoadB25, side = 1, terminal = 2),
		(node = :Bus25q, element = :T25_26, side = 1, terminal = 2),
		(node = :Bus25q, element = :TR25_37, side = 1, terminal = 2),
		(node = :Bus26d, element = :T25_26, side = 2, terminal = 1),
		(node = :Bus26d, element = :LoadB26, side = 1, terminal = 1),
		(node = :Bus26d, element = :T26_27, side = 1, terminal = 1),
		(node = :Bus26d, element = :T26_28, side = 1, terminal = 1),
		(node = :Bus26d, element = :T26_29, side = 1, terminal = 1),
		(node = :Bus26q, element = :T25_26, side = 2, terminal = 2),
		(node = :Bus26q, element = :LoadB26, side = 1, terminal = 2),
		(node = :Bus26q, element = :T26_27, side = 1, terminal = 2),
		(node = :Bus26q, element = :T26_28, side = 1, terminal = 2),
		(node = :Bus26q, element = :T26_29, side = 1, terminal = 2),
		(node = :Bus27d, element = :T26_27, side = 2, terminal = 1),
		(node = :Bus27d, element = :T17_27, side = 2, terminal = 1),
		(node = :Bus27d, element = :LoadB27, side = 1, terminal = 1),
		(node = :Bus27q, element = :T26_27, side = 2, terminal = 2),
		(node = :Bus27q, element = :T17_27, side = 2, terminal = 2),
		(node = :Bus27q, element = :LoadB27, side = 1, terminal = 2),
		(node = :Bus28d, element = :T26_28, side = 2, terminal = 1),
		(node = :Bus28d, element = :T28_29, side = 1, terminal = 1),
		(node = :Bus28d, element = :LoadB28, side = 1, terminal = 1),
		(node = :Bus28q, element = :T26_28, side = 2, terminal = 2),
		(node = :Bus28q, element = :T28_29, side = 1, terminal = 2),
		(node = :Bus28q, element = :LoadB28, side = 1, terminal = 2),
		(node = :Bus29d, element = :T26_29, side = 2, terminal = 1),
		(node = :Bus29d, element = :LoadB29, side = 1, terminal = 1),
		(node = :Bus29d, element = :T28_29, side = 2, terminal = 1),
		(node = :Bus29d, element = :TR29_38, side = 1, terminal = 1),
		(node = :Bus29q, element = :T26_29, side = 2, terminal = 2),
		(node = :Bus29q, element = :LoadB29, side = 1, terminal = 2),
		(node = :Bus29q, element = :T28_29, side = 2, terminal = 2),
		(node = :Bus29q, element = :TR29_38, side = 1, terminal = 2),
		(node = :Bus30d, element = :TR2_30, side = 2, terminal = 1),
		(node = :Bus30d, element = :Zg30, side = 2, terminal = 1),
		(node = :Bus30q, element = :TR2_30, side = 2, terminal = 2),
		(node = :Bus30q, element = :Zg30, side = 2, terminal = 2),
		(node = :Bus31d, element = :TR6_31, side = 2, terminal = 1),
		(node = :Bus31d, element = :Zg31, side = 2, terminal = 1),
		(node = :Bus31q, element = :TR6_31, side = 2, terminal = 2),
		(node = :Bus31q, element = :Zg31, side = 2, terminal = 2),
		(node = :Bus32d, element = :TR10_32, side = 2, terminal = 1),
		(node = :Bus32d, element = :Zg32, side = 2, terminal = 1),
		(node = :Bus32d, element = :LoadB31, side = 1, terminal = 1),
		(node = :Bus32q, element = :TR10_32, side = 2, terminal = 2),
		(node = :Bus32q, element = :Zg32, side = 2, terminal = 2),
		(node = :Bus32q, element = :LoadB31, side = 1, terminal = 2),
		(node = :Bus33d, element = :TR19_33, side = 2, terminal = 1),
		(node = :Bus33d, element = :Zg33, side = 2, terminal = 1),
		(node = :Bus33q, element = :TR19_33, side = 2, terminal = 2),
		(node = :Bus33q, element = :Zg33, side = 2, terminal = 2),
		(node = :Bus34d, element = :TR20_34, side = 2, terminal = 1),
		(node = :Bus34d, element = :Zg34, side = 2, terminal = 1),
		(node = :Bus34q, element = :TR20_34, side = 2, terminal = 2),
		(node = :Bus34q, element = :Zg34, side = 2, terminal = 2),
		(node = :Bus35d, element = :TR22_35, side = 2, terminal = 1),
		(node = :Bus35d, element = :Zg35, side = 2, terminal = 1),
		(node = :Bus35q, element = :TR22_35, side = 2, terminal = 2),
		(node = :Bus35q, element = :Zg35, side = 2, terminal = 2),
		(node = :Bus36d, element = :TR23_36, side = 2, terminal = 1),
		(node = :Bus36d, element = :Zg36, side = 2, terminal = 1),
		(node = :Bus36q, element = :TR23_36, side = 2, terminal = 2),
		(node = :Bus36q, element = :Zg36, side = 2, terminal = 2),
		(node = :Bus37d, element = :TR25_37, side = 2, terminal = 1),
		(node = :Bus37d, element = :Zg37, side = 2, terminal = 1),
		(node = :Bus37q, element = :TR25_37, side = 2, terminal = 2),
		(node = :Bus37q, element = :Zg37, side = 2, terminal = 2),
		(node = :Bus38d, element = :TR29_38, side = 2, terminal = 1),
		(node = :Bus38d, element = :Zg38, side = 2, terminal = 1),
		(node = :Bus38q, element = :TR29_38, side = 2, terminal = 2),
		(node = :Bus38q, element = :Zg38, side = 2, terminal = 2),
		(node = :Bus39d, element = :Zg39, side = 2, terminal = 1),
		(node = :Bus39d, element = :T1_39, side = 2, terminal = 1),
		(node = :Bus39d, element = :T9_39, side = 2, terminal = 1),
		(node = :Bus39d, element = :LoadB39, side = 1, terminal = 1),
		(node = :Bus39q, element = :Zg39, side = 2, terminal = 2),
		(node = :Bus39q, element = :T1_39, side = 2, terminal = 2),
		(node = :Bus39q, element = :T9_39, side = 2, terminal = 2),
		(node = :Bus39q, element = :LoadB39, side = 1, terminal = 2),
	)
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
	return (; builder, solved, network = solved.network)
end

function ieee39bus_with_nwbuilder_powerflow()
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

	data, _, elempitopm = convert(builder, PI.PMACDC)

    options = builder.options

    result = solve_acdcpf(
        data,
        PI._PM.ACPPowerModel,
        powerflow_optimizer(options),
        is_bounded_options(options);
        setting = powerflow_setting(options),
    )

	network = NB.build_network(builder.elements, builder.topology, builder.options)


	return (; builder, solved=(;data, result, elempitopm), network )
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
	built = build_ieee39bus_with_networkbuilder()

	builtnetw = built.network

	z_legacy, omega_legacy = determine_ieee39bus_impedance(legacy; freq_range)
	z_built, omega_built = determine_ieee39bus_impedance(builtnetw; freq_range)

	@test isequal(omega_built, omega_legacy)
	@test axes(z_built) == axes(z_legacy)
	@test isapprox(z_built, z_legacy, rtol=1e-12,atol=1e-12)

	eignew = eigvals(builtnetw.elements[:STATCOM].A)
	eiglegacy = eigvals(legacy.elements[:STATCOM].A)

	@test sort(real(eignew)) ≈ sort(real(eiglegacy)) rtol=1e-8
	@test sort(imag(eignew)) ≈ sort(imag(eiglegacy)) rtol=1e-8

	# @test legacy.elements[:STATCOM].A ≈ built.elements[:STATCOM].A rtol=1e-8 #Check if the linearized state matrix are approx the same

	return nothing
end

function test_nwbuilder_powerflow_parity(; freq_range = IEEE39_FREQ_RANGE)
	sharedpf = build_ieee39bus_with_networkbuilder().solved.powerflow
	direct_case = ieee39bus_with_nwbuilder_powerflow()
	newpf = direct_case.solved
	classic_network = NB.build_network(
		direct_case.builder.elements,
		direct_case.builder.topology,
		direct_case.builder.options,
	)
	classic_result, classic_data, classic_nodes2bus, classic_elem2comp =
		PI.power_flow(classic_network)

	function dicts_approx_equal(dict1, dict2; atol = 1e-8)
		keys1 = keys(dict1)
		keys2 = keys(dict2)
		if keys1 != keys2
			return false
		end
		for key in keys1
			val1 = dict1[key]
			val2 = dict2[key]
			if val1 isa AbstractDict && val2 isa AbstractDict
				if !dicts_approx_equal(val1, val2; atol)
					return false
				end
			elseif val1 isa Number && val2 isa Number
				isapprox(val1, val2; atol) || return false
			elseif !isequal(val1, val2)
				return false
			end
		end
		return true
	end
	normalize_mapping(mapping) = Dict(
		name => value isa NamedTuple ? (value.pmtype, value.compkey) : Tuple(value)
		for (name, value) in mapping
	)

	# The shared calculation and the direct NetworkBuilder parameterization use
	# the same PowerModelsACDC model and therefore have the same complete result.
	@test sharedpf.result["termination_status"] == newpf.result["termination_status"]
	@test dicts_approx_equal(sharedpf.result["solution"], newpf.result["solution"])

	# The Classic route numbers buses in construction order. Compare complete
	# component and bus solutions through their semantic mappings instead of
	# comparing those incidental integer identifiers.
	shared_elements = normalize_mapping(sharedpf.elem2comp)
	classic_elements = normalize_mapping(classic_elem2comp)
	@test shared_elements == classic_elements == normalize_mapping(newpf.elempitopm)
	for (element, (group, index)) in shared_elements
		haskey(sharedpf.result["solution"], group) || continue
		@test dicts_approx_equal(
			sharedpf.result["solution"][group][string(index)],
			classic_result["solution"][group][string(index)],
		)
	end

	typed_bus_nodes = Dict{Tuple{Symbol,Int},Set{Symbol}}()
	for (node, bus) in sharedpf.nodes2bus
		bus[1] === :ground && continue
		push!(get!(typed_bus_nodes, bus, Set{Symbol}()), node)
	end
	for ((domain, typed_bus), nodes) in typed_bus_nodes
		@test haskey(classic_nodes2bus, nodes)
		classic_group, classic_bus = classic_nodes2bus[nodes]
		typed_group = domain === :ac ? "bus" : "busdc"
		@test classic_group == typed_group
		@test dicts_approx_equal(
			sharedpf.result["solution"][typed_group][string(typed_bus)],
			classic_result["solution"][classic_group][string(classic_bus)],
		)
	end

	@test sharedpf.result["termination_status"] == classic_result["termination_status"]
	@test Set(keys(sharedpf.result["solution"])) ==
	      Set(keys(classic_result["solution"]))
	for group in ("bus", "busdc", "gen", "gendc", "branch", "branchdc", "convdc")
		@test length(sharedpf.data[group]) == length(classic_data[group])
	end
	@test Set(keys(sharedpf.nodes2bus)) ==
	      Set(row.node for row in ieee39bus_connections())
	@test sharedpf.active_setpoint_values === sharedpf.operating_point.setpoints
	for field in fieldnames(Setpoint)
		@test isapprox(
			getfield(classic_network.elements[:STATCOM].setpoint, field),
			getfield(sharedpf.operating_point[:STATCOM], field);
			atol = 1e-8,
		)
	end

	# @test isequal(legacypf, builtpf)
	# @test axes(z_built) == axes(z_legacy)
	# @test isequal(z_built, z_legacy)

	return nothing
end

function test_linearizedadmittance_parity(; freq_range = IEEE39_FREQ_RANGE)
	legacy = build_ieee39bus_with_macro()
	built = build_ieee39bus_with_networkbuilder().builder
	newadmnw = convert(built, NetworkModel)

	freqs = range(freq_range[1], freq_range[2], step=freq_range[3])
	s = 1im .* 2π .* freqs
	elemkeys = [:STATCOM, :T1_39, :T9_39, :LoadB39]
	for key in elemkeys
		@test haskey(legacy.elements, key) #"Legacy network is missing element $key"
		@test haskey(newadmnw.indices.elements, key) #"New network is missing element $key"
		
		ylegacy = PI.eval_y.((legacy.elements[key],), s;SI_units = true) #Should be pu (disabled scaling)
		ynew = get_y(newadmnw,key, s)
		ynew = [ynew[:,:,i] for i in axes(ynew, 3)]

		@test isapprox(ylegacy, ynew; atol = 1e-4, rtol=1e-4) #"Admittance mismatch for element $key"
	end
	
	




	# @test isequal(omega_built, omega_legacy)
	# @test axes(z_built) == axes(z_legacy)


	# @test legacy.elements[:STATCOM].A ≈ built.elements[:STATCOM].A rtol=1e-11 #Check if the linearized state matrix are approx the same


	return nothing
end


function test_ynode_and_edge_parity(; freq_range = IEEE39_FREQ_RANGE)
	legacy = build_ieee39bus_with_macro()
	built = build_ieee39bus_with_networkbuilder().builder
	newadmnw = convert(built, NetworkModel)
	Z, omega = determine_impedance(legacy; input_pins=[:Bus9d, :Bus9q], output_pins=[:gndD, :gndQ], elim_elements=[:STATCOM], freq_range)
	s = omega .*im
	yedge = NB.make_y_edge(newadmnw, s)
	Znew = [inv(yedge[1:2,1:2,i]) for i in axes(yedge,3)]

	@test isapprox(Z,Znew)
	Ynodeleg, _, omega = make_y_node(legacy;freq_range)
	#Restructure to have AC-first. TODO: Update so you look at net ids for better robustness
	Ynodeleg_sc = [[A[end-1, end-1] A[end-1, end] A[end-1, end-2]; A[end, end-1] A[end, end] A[end, end-2]; A[end-2,end-1] A[end-2,end] A[end-2,end-2]] for A in Ynodeleg] # Only take Ysc
	
	Ynodenew = NB.make_y_node(newadmnw, im.*omega)
	DC_dummy_adm = zeros(3,3)
	DC_dummy_adm[3,3] = 1e-4 #Dummy impedance added at DC side
	Ynodenew = [Ynodenew[:,:,i] .+ DC_dummy_adm for i in axes(Ynodenew,3)]

	@test isapprox(Ynodeleg_sc, Ynodenew;rtol=1e-7, atol=1e-7)
end

function test_determine_impedance_parity(; freq_range = IEEE39_FREQ_RANGE)
	legacy = build_ieee39bus_with_macro()
	built = build_ieee39bus_with_networkbuilder().builder
	newadmnw = convert(built, NetworkModel)
	Z, omega = determine_impedance(legacy; input_pins=[:Bus9d, :Bus9q], output_pins=[:gndD, :gndQ], elim_elements=[:STATCOM], freq_range)
	Znew, omega_new = NB.determine_impedance(newadmnw; nets=[:Bus9d, :Bus9q], elim_elements=[:STATCOM], freq_range)
	Zresh = cat(Z...; dims=3)

	@test isequal(omega, omega_new)
	@test isapprox(Zresh,Znew)
	
end


@testset "IEEE39bus NetworkBuilder parity" begin
	test_ieee39bus_networkbuilder_parity()
end

@testset "IEEE39bus NetworkBuilder power flow parity" begin
	test_nwbuilder_powerflow_parity()
end

@testset "IEEE39bus NetworkBuilder linearized admittance parity" begin
	test_linearizedadmittance_parity()
end

@testset "IEEE39bus NetworkBuilder linearized admittance Ynode and Yedge parity" begin
	test_ynode_and_edge_parity()
end


@testset "IEEE39bus NetworkBuilder linearized admittance determine_impedance parity" begin
	test_determine_impedance_parity()
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
		(node = :B, element = :a, side = 1, terminal = 1),
		(node = :B, element = :open_line, side = 1, terminal = 1),
		(node = :B, element = :b, side = 1, terminal = 1),
		(node = :gnd, element = :a, side = 2, terminal = 1),
		(node = :gnd, element = :b, side = 2, terminal = 1),
	)

	builder = NetworkBuilder.define(elements, connections)
	network = NB.build_network(builder.elements, builder.topology, builder.options)

	@test !haskey(network.elements, :open_line)
	@test network.elements[:a].pins[Symbol("1.1")] == :B
	@test network.elements[:b].pins[Symbol("1.1")] == :B
	@test network.elements[:a].pins[Symbol("2.1")] == :gnd
	@test network.elements[:b].pins[Symbol("2.1")] == :gnd
end
