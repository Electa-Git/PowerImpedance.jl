# For debugging
# include("../src/HVDCstability.jl")
# using .HVDCstability
# using DelimitedFiles,SymEngine
# For normal operation
using DelimitedFiles,SymEngine,HVDCstability
s = symbols("s")
transmissionVoltage = 333 / sqrt(3)
pHVDC1 = 600
qC1 = -100
qC2 = 100

# The P and Q defined here are what is injected into the network. 
# The setpoint of the reactive power controller is minus the value set here. This is adjusted internally, no action here needed.
# For voltage controlling converters the voltage references have to be defined inside the corresponding voltage controller!!
net = @network begin
        voltageBase = transmissionVoltage
        g1 = ac_source(V = transmissionVoltage, P = pHVDC1, P_min = -2000, P_max = 2000, Q_max = 1000, Q_min = -1000, pins = 3, transformation = true)
        
        # HVDC link 1
        # PU gains
        # MMC1 controls the DC voltage.
        c1 = mmc(Vᵈᶜ = 800, vDCbase = 800, Vₘ = transmissionVoltage,
                P_max = 1500, P_min = -1500, P = -pHVDC1, Q = qC1, Q_max = 500, Q_min = -500,
                # vACbase_LL_RMS = 333, turnsRatio = 333/380, Lᵣ = 0.0461, Rᵣ = 0.4103,
                vACbase_LL_RMS = 333, turnsRatio = 333/333, Lᵣ = 0.0635, Rᵣ = 0.5544,
                occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
                ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
                pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
                # vac_supp = PI_control(Kₚ = 20, ω_f = 100, ref = [transmissionVoltage*sqrt(2)]),
                q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159, ref = [qC1]),
                # vac = PI_control(Kₚ = 0, Kᵢ = 100, ref = [transmissionVoltage*sqrt(2)]),
                dc = PI_control(Kₚ = 5, Kᵢ = 15, ref = [1.0])
                )
        # MMC2 controls P&Q.
        # Total energy controller not considered in the validations.
        c2 = mmc(Vᵈᶜ = 800, vDCbase = 800, Vₘ = transmissionVoltage,
                P_max = 1000, P_min = -1000, P = pHVDC1, Q = qC2, Q_max = 1000, Q_min = -1000,
                # vACbase_LL_RMS = 333, turnsRatio = 333/380, Lᵣ = 0.0461, Rᵣ = 0.4103,
                vACbase_LL_RMS = 333, turnsRatio = 333/333, Lᵣ = 0.0635, Rᵣ = 0.5544,
                occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
                ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
                pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
                # energy = PI_control(Kₚ = 2.7023, Kᵢ = 121.2777, ref = [1.0]),
                # zcc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
                p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159, ref = [pHVDC1]),
                # vac_supp = PI_control(Kₚ = 20, ω_f = 100, ref = [transmissionVoltage*sqrt(2)]),
                q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159, ref = [qC2])
                # vac = PI_control(Kₚ = 0, Kᵢ = 100, ref = [transmissionVoltage*sqrt(2)]) #Peak
                )

        dc_line = impedance(z = 1e-3, pins = 1, transformation = false) 
        # dc_line = cable(length = 100e3, positions = [(-0.5,1), (0.5,1)],
        #         C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        #         C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        #         C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
        #         I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        #         I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        #         I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)
        g4 = ac_source(V = transmissionVoltage, P = pHVDC1, P_min = -2000, P_max = 2000, Q_max = 1000, Q_min = -1000, pins = 3, transformation = true)

        tl1 = overhead_line(length = 50e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)

        tl2 = overhead_line(length = 50e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)

        c1[2.1] ⟷ tl1[2.1]
        c1[2.2] ⟷ tl1[2.2]

        g4[1.1] ⟷ tl1[1.1] ⟷ Bus1d
        g4[1.2] ⟷ tl1[1.2] ⟷ Bus1q

        # g4[1.1] ⟷ c1[2.1] ⟷ Bus1d
        # g4[1.2] ⟷ c1[2.2] ⟷ Bus1q

        g4[2.1] ⟷ gndd
        g4[2.2] ⟷ gndq
        
        c1[1.1] ⟷ dc_line[1.1]
        c2[1.1] ⟷ dc_line[2.1]

        c2[2.1] == tl2[1.1]
        c2[2.2] == tl2[1.2]
        g1[1.1] == tl2[2.1] == Bus2d
        g1[1.2] == tl2[2.2] == Bus2q

        g1[2.1] == gndd
        g1[2.2] == gndq


end

# @time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g1], input_pins=Any[:Bus2d,:Bus2q], 
# output_pins=Any[:gndd,:gndq], omega_range = (-2,4,2000))
@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g4], input_pins=Any[:Bus1d,:Bus1q], 
output_pins=Any[:gndd,:gndq], omega_range = (-2,4,2000))

writedlm("./files/imp_P2P_validation.csv",  imp_ac, ',')
writedlm("./files/w_P2P_validation.csv",  omega_ac, ',')


# writedlm("./files/A_p2p.csv",  net.elements[:c1].element_value.A, ',')
# writedlm("./files/B_p2p.csv",  net.elements[:c1].element_value.B, ',')
# writedlm("./files/C_p2p.csv",  net.elements[:c1].element_value.C, ',')
# writedlm("./files/D_p2p.csv",  net.elements[:c1].element_value.D, ',')
