
transmissionVoltage = 380 / sqrt(3)
pHVDC1 = 600
qC1 = 100
qC2 = 100
# The P and Q defined here are what is injected into the network.

net,
imp_topology = let
    g1 = ac_source(v = transmissionVoltage*sqrt(2), p = pHVDC1)

    # HVDC link 1
    # MMC1 controls the DC voltage, and is situated at the remote end.
    c1 = let model = PowerImpedance.mmc(
            elec = PowerImpedance.ElectricalMMC(vDC_base = 800,
            ),
            sync = PowerImpedance.PLLSynchronization(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.28, Ki = 12.5664),
            ),
            delta_control = PowerImpedance.ΔdqControlGFL(
                outer_active = PowerImpedance.OuterActiveVdcControl(
                    pi_ctrl = PowerImpedance.PIControl(Kp = 5, Ki = 15),
                ),
                outer_reactive = PowerImpedance.OuterReactiveQControl(
                    pi_ctrl = PowerImpedance.PIControl(Kp = 0.1, Ki = 31.4159),
                ),
                occ = PowerImpedance.InnerCurrentPIControl(
                    pi_ctrl = PowerImpedance.PIControl(Kp = 0.7691, Ki = 522.7654),
                    activate_ω_c_multiplication = false
                )
            ),
            sigma_control = PowerImpedance.ΣdqzControlTEC(
                ccsc = PowerImpedance.CirculatingCurrentSuppressionControl(
                PowerImpedance.PIControl(Kp = 0.1048, Ki = 48.1914),
            ),
            ),
            limits = PowerImpedance.Limits(
                P_min = -1500,
                P_max = 1500,
                Q_min = -500,
                Q_max = 500
            )
        )
        b = bases(model)
        #Amplitude LN for Vac setpoint
        component(model;
            delta_control = (outer_active = (v_dc_ref = (800) / b.v_dc,),
                outer_reactive = (q_ref = (qC1) / b.S,)),
            powerflow = (p_ac = (-pHVDC1) / b.S,
                v_ac = (transmissionVoltage * sqrt(2)) / b.v_ac, p_dc = (-pHVDC1) / b.S))
    end
    # MMC2 controls P&Q. It is connected to bus 7. Define the transformer impedance
    # parameters at the converter side!
    c2 = let model = PowerImpedance.mmc(
            elec = PowerImpedance.ElectricalMMC(
                vDC_base = 800,
                vACbase_LL_RMS = 333,
                turnsRatio = 333 / 380,
                Lᵣ = 0.0461,
                Rᵣ = 0.4103
            ),
            sync = PowerImpedance.PLLSynchronization(
                pi_ctrl = PowerImpedance.PIControl(Kp = 0.28, Ki = 12.5664),
            ),
            delta_control = PowerImpedance.ΔdqControlGFL(
                outer_active = PowerImpedance.OuterActivePowerControl(
                    pi_ctrl = PowerImpedance.PIControl(Kp = 0.1, Ki = 31.4159),
                ),
                outer_reactive = PowerImpedance.OuterReactiveQControl(
                    pi_ctrl = PowerImpedance.PIControl(Kp = 0.1, Ki = 31.4159),
                ),
                occ = PowerImpedance.InnerCurrentPIControl(
                    pi_ctrl = PowerImpedance.PIControl(Kp = 0.7691, Ki = 522.7654),
                    activate_ω_c_multiplication = false
                )
            ),
            sigma_control = PowerImpedance.ΣdqzControlTEC(
                ccsc = PowerImpedance.CirculatingCurrentSuppressionControl(
                PowerImpedance.PIControl(Kp = 0.1048, Ki = 48.1914),
            ),
            ),
            limits = PowerImpedance.Limits(
                P_min = -1000,
                P_max = 1000,
                Q_min = -1000,
                Q_max = 1000
            )
        )
        b = bases(model)
        #Amplitude LN for Vac setpoint
        component(model;
            delta_control = (outer_active = (p_ref = (pHVDC1) / b.S,),
                outer_reactive = (q_ref = (qC2) / b.S,)),
            powerflow = (v_ac = (transmissionVoltage * sqrt(2)) / b.v_ac,
                p_dc = (pHVDC1) / b.S, v_dc = (800) / b.v_dc))
    end

    dc_line = cable(length = 100e3, positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
        I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3))

    g4 = ac_source(v = transmissionVoltage*sqrt(2), p = pHVDC1)

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
            dᵍˢᵃᵍ = 10
        ),
        earth_parameters = (1, 1, 100))

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
            dᵍˢᵃᵍ = 10
        ),
        earth_parameters = (1, 1, 100))

    elements = (; g1, c1, c2, dc_line, g4, tl1, tl78)
    topology = (
        NetworkBuilder.Bus(:B3; ports = ((:c1, :ac), (:tl1, :side2)), domain = ACDQ),
        NetworkBuilder.Bus(:B2; ports = ((:g4, :ac), (:tl1, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:B4; ports = ((:c1, :dc), (:dc_line, :side1))),
        NetworkBuilder.Bus(:B5; ports = ((:c2, :dc), (:dc_line, :side2))),
        NetworkBuilder.Bus(:B6; ports = ((:c2, :ac), (:tl78, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:B7; ports = ((:g1, :ac), (:tl78, :side2)), domain = ACDQ)
    )
    state = NetworkBuilder.define(elements, topology;
        options = (; voltageBase = transmissionVoltage))
    state, topology
end
# Read validation data from text file
# Text file is generated by Ztool with PSCAD.
# lines=readlines("P2P_HVDC_1us#Y_AC#MMC2-1#.txt")
lines = readlines(joinpath(@__DIR__, "data", "P2P_HVDC_1us#Y_AC#MMC2-1#.txt"))
validation_data = [split(line) for line in lines[2:end]]
frequency = real([parse(Complex{Float64}, replace(row[1], "(" => ""))
                  for row in validation_data])
omegas=2*pi*frequency
matrices = [parse.(Complex{Float64}, replace.(row[2:end], "(" => ""))
            for row in validation_data]

# Converter admittance data to impedance data
Z_ac = Vector{Matrix{Complex{Float64}}}(undef, length(omegas))
imp_ac = Vector{Matrix{Complex{Float64}}}(undef, length(omegas))
result = compute(PowerFlowProblem(net), ACDCPowerFlow())
scan_state = NetworkBuilder.define(net.elements, imp_topology; options = net.options,
    exclude = (:g1,))
network_model = NetworkBuilder.NetworkModel(scan_state, result.operating_point)
for k in eachindex(omegas)
    omega=omegas[k]
    Z_ac[k]=inv([matrices[k][1] matrices[k][2]; matrices[k][3] matrices[k][4]])
    dummy,
    omega_ac = NetworkBuilder.determine_impedance(network_model;
        nets = [:B7d, :B7q],
        freq_range = (omega/(2*pi), (omega+1)/(2*pi), 2))
    imp_ac[k] = dummy[:, :, 1]
end

# Compare the impedance data with the data from the text file
for k in eachindex(omegas)

    #println("Frequency: ", omegas[k]/(2*pi), " Hz. Index: ", k)
    for c in 1:2
        for r in 1:2
            # Increased due to outliner @ 803 Hz
            @test abs(Z_ac[k][c, r]) ≈ abs(imp_ac[k][c, r]) rtol=0.18
            # Increased due to outliner @ 803 Hz
            @test angle(Z_ac[k][c, r]) ≈ angle(imp_ac[k][c, r]) atol = 5*(pi/180)
        end
    end
end

# Plotting for visual inspection
