function unwrap!(x, period = 2π)
    y = convert(eltype(x), period)
    v = first(x)
    @inbounds for k = eachindex(x)
        x[k] = v = v + rem(x[k] - v, y, RoundNearest)
    end
    return x
end

function read_validation_data(path::AbstractString)
    lines = readlines(path)
    validation_data = [split(line) for line in lines[2:end]]

    frequency = real([
        parse(ComplexF64, replace(row[1], "(" => ""))
        for row in validation_data
    ])
    omegas = 2π .* frequency

    matrices = [
        reshape(parse.(ComplexF64, replace.(row[2:end], "(" => "")), 3, 3)
        for row in validation_data
    ]

    return omegas, transpose.(matrices)
end

function element_y(elem, s::Complex)
    n = size(elem.A, 1)
    Iₙ = Matrix{ComplexF64}(I, n, n)
    Y = elem.C * ((s * Iₙ - elem.A) \ elem.B) + elem.D

    conv = elem.element_model
    elec = conv.elec

    vACbase = elec.vACbase_LL_RMS * sqrt(2 / 3)
    iACbase = 2 * elec.Sbase / (3 * vACbase)
    iDCbase = elec.Sbase / elec.vDCbase

    Y = Matrix{ComplexF64}(Y)

    Y[1, :] .*= iDCbase
    Y[:, 1] ./= elec.vDCbase

    Y[2:3, :] .*= iACbase
    Y[:, 2:3] ./= vACbase

    return Y
end

function tlc_plot_convention(Y::AbstractMatrix)
    return [transpose(Y[1, :]); transpose(-Y[2, :]); transpose(-Y[3, :])]
end

function common_tlc_blocks(; Vm, Vdc, Lf, Rf)
    elec = PowerImpedanceACDC.ElectricalTLC(
        Vᵈᶜ = Vdc,
        Vₘ = Vm,
        Lᵣ = Lf,
        Rᵣ = Rf,
        Sbase = 100.0,
        vACbase_LL_RMS = 220.0,
        vDCbase = Vdc,
    )

    meas = PowerImpedanceACDC.MeasurementTLC(
        vac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 0.5e4),
        iac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 0.5e4),
    )

    synch = PowerImpedanceACDC.PLLSynchronization(
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

    return elec, meas, synch, innerVoltage, innerCurrent, mod, limits
end

function build_case1_grid()
    Powf = 70.0
    Qowf = 20.0
    Vm = 220 / sqrt(3)          # phase RMS [kV]
    Vac_peak = Vm * sqrt(2)     # phase peak [kV]
    Vdc = 640.0

    Ztrafo_base = 220^2 / 100
    Lf = 0.08 * Ztrafo_base / (2π * 50)
    Rf = 0.01 * 0.08 * Ztrafo_base

    elec, meas, synch, innerVoltage, innerCurrent, mod, limits =
        common_tlc_blocks(; Vm, Vdc, Lf, Rf)

    q_ref_pu = -Qowf / elec.Sbase
    vdc_ref_pu = Vdc / elec.vDCbase
    vac_ref_pu = Vac_peak / (elec.vACbase_LL_RMS * sqrt(2 / 3))

    limits = PowerImpedanceACDC.Limits(
        P_min = -100.0,
        P_max = 100.0,
        Q_min = -50.0,
        Q_max = 50.0,
    )

    vac_ref_pu = Vac_peak / (elec.vACbase_LL_RMS * sqrt(2 / 3))

    outerActive = PowerImpedanceACDC.OuterActiveVdcControl(
        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 5.0, Ki = 5.0),
        vdc_ref = 0.0,   # legacy behavior: resolve from PF operating point
    )

    outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.04, Ki = 40.0),
        support = PowerImpedanceACDC.VoltageSupportLag(
            K = 5.0,
            ωc = 1 / 0.5,
            vac_ref = vac_ref_pu,
        ),
    )

    setpoint = PowerImpedanceACDC.SetPoint(
        Pac = Powf,
        Qac = Qowf,
        θac = 0.0,
        Vac = Vac_peak,
        Pdc = Powf,
        Vdc = Vdc,
    )

    dut = PowerImpedanceACDC.tlc(
        elec = elec,
        meas = meas,
        synch = synch,
        outerActive = outerActive,
        outerReactive = outerReactive,
        innerVoltage = innerVoltage,
        innerCurrent = innerCurrent,
        mod = mod,
        setpoint = setpoint,
        limits = limits,
    )

    grid = @network begin
        voltageBase = Vm

        G3 = ac_source(pins = 3, V = Vm, transformation = true)
        G_DC = dc_source(pins = 1, V = Vdc / 2)

        DUT = dut

        CableDC12 = cable(length = 10e3, positions = [(-0.5, 1), (0.5, 1)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3),
            transformation = true)

        G3[2.1] ⟷ gndD
        G3[2.2] ⟷ gndQ

        G3[1.1] == DUT[2.1] ⟷ NodeMMC1d
        G3[1.2] == DUT[2.2] ⟷ NodeMMC1q
        DUT[1.1] ⟷ CableDC12[1.1]
        CableDC12[2.1] ⟷ G_DC[1.1]

        G_DC[2.1] == gndDC
    end

    return grid
end

function build_case2_grid()
    Powf = 70.0
    Qowf = 20.0
    Vm = 220 / sqrt(3)          # phase RMS [kV]
    Vac_peak = Vm * sqrt(2)     # phase peak [kV]
    Vdc = 640.0

    Ztrafo_base = 220^2 / 100
    Lf = 0.08 * Ztrafo_base / (2π * 50)
    Rf = 0.01 * 0.08 * Ztrafo_base

    elec, meas, synch, innerVoltage, innerCurrent, mod, limits =
        common_tlc_blocks(; Vm, Vdc, Lf, Rf)

    p_ref_pu = Powf / elec.Sbase
    q_ref_pu = -Qowf / elec.Sbase

    limits = PowerImpedanceACDC.Limits(
        P_min = -1000.0,
        P_max = 1000.0,
        Q_min = -1000.0,
        Q_max = 1000.0,
    )

    outerActive = PowerImpedanceACDC.OuterActivePowerControl(
        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.04, Ki = 40.0),
        support = PowerImpedanceACDC.FrequencySupportLag(
            Kω = 5.0,
            ωc = 1 / 0.5,
        ),
    )

    outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.04, Ki = 40.0),
    )

    setpoint = PowerImpedanceACDC.SetPoint(
        Pac = Powf,
        Qac = Qowf,
        θac = 0.0,
        Vac = Vac_peak,
        Pdc = Powf,
        Vdc = Vdc,
    )

    dut = PowerImpedanceACDC.tlc(
        elec = elec,
        meas = meas,
        synch = synch,
        outerActive = outerActive,
        outerReactive = outerReactive,
        innerVoltage = innerVoltage,
        innerCurrent = innerCurrent,
        mod = mod,
        setpoint = setpoint,
        limits = limits,
    )

    grid = @network begin
        voltageBase = Vm

        G3 = ac_source(pins = 3, V = Vm, transformation = true)
        G_DC = dc_source(pins = 1, V = Vdc / 2)

        DUT = dut

        G3[2.1] ⟷ gndD
        G3[2.2] ⟷ gndQ

        G3[1.1] == DUT[2.1]
        G3[1.2] == DUT[2.2]
        DUT[1.1] ⟷ G_DC[1.1]
        G_DC[2.1] == gndDC
    end

    return grid
end

#
# Case 1: Vdc ; QV-droop / Vac support
#

omegas, Y_validation = read_validation_data(joinpath(@__DIR__, "data", "data_TLC_validation_1.txt"))
grid = build_case1_grid()
elem = grid.elements[:DUT]

Y_TLC = Matrix{ComplexF64}[]
for ω in omegas
    Y1 = element_y(elem, 1im * ω)
    push!(Y_TLC, tlc_plot_convention(Y1))
end

for k in eachindex(omegas)
    for c in 1:3, r in 1:3
        @test abs(Y_TLC[k][c, r]) ≈ abs(Y_validation[k][c, r]) rtol = 0.07 #0.07
        @test angle(Y_TLC[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol = 3 * (π / 180)
    end
end

#
# Case 2: PQ-control
#

omegas, Y_validation = read_validation_data(joinpath(@__DIR__, "data", "data_TLC_validation_2.txt"))
grid = build_case2_grid()
elem = grid.elements[:DUT]

for i in eachindex(Y_validation)
    Y_validation[i][1, :] *= -1
end

Y_validation_abs = [Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]
Y_validation_angle = [Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]

for c in 1:3, r in 1:3
    setindex!.(Y_validation_abs, abs.(getindex.(Y_validation, r, c)), r, c)
    setindex!.(Y_validation_angle, unwrap!(angle.(getindex.(Y_validation, r, c))), r, c)
end

Y_TLC = Matrix{ComplexF64}[]
for ω in omegas
    Y1 = element_y(elem, 1im * ω)
    push!(Y_TLC, tlc_plot_convention(Y1))
end

Y_TLC_abs = [Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]
Y_TLC_angle = [Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]

for c in 1:3, r in 1:3
    setindex!.(Y_TLC_abs, abs.(getindex.(Y_TLC, r, c)), r, c)
    setindex!.(Y_TLC_angle, unwrap!(angle.(getindex.(Y_TLC, r, c))), r, c)
end

for k in eachindex(omegas)
    for c in 1:3, r in 1:3
        @test Y_TLC_abs[k][c, r] ≈ Y_validation_abs[k][c, r] rtol = 0.02 #0.02
        @test Y_TLC_angle[k][c, r] ≈ Y_validation_angle[k][c, r] atol = 1 * (π / 180)
    end
end
















## Legacy Code Implementation
#= ###Test data for: Vdc; QV-droop
function unwrap!(x, period = 2π)
	y = convert(eltype(x), period)
	v = first(x)
	@inbounds for k = eachindex(x)
		x[k] = v = v + rem(x[k] - v,  y, RoundNearest)
	end
    return x
end


Powf = 70
Qowf = 20
Vm = 220 /sqrt(3) 
Vdc = 640

Ztrafo_base = 220^2/100
Lf = 0.08 * Ztrafo_base /2/pi/50
Rf = 0.01 * 0.08*Ztrafo_base


grid=@network begin
    


    voltageBase = Vm # Apparently needed for correct per-unit calculation of the power flow

    G3 = ac_source(pins = 3, V = Vm, transformation = true)
    G_DC = dc_source(pins = 1, V = 1*Vdc/2)

DUT=tlc(Vᵈᶜ = Vdc, Vₘ = Vm, Lᵣ = Lf, Rᵣ = Rf, 
        Sbase = 100, vACbase_LL_RMS = 220, vDCbase = Vdc,
        Q = Qowf,
        occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8),
        pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = (2*pi)*80, n_f=2), # These gains are fine.
        v_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
        i_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
        f_supp = PI_control(ω_f = 1/0.5, Kₚ =5), #
        dc = PI_control(Kₚ = 5, Kᵢ = 5),
        q = PI_control(Kₚ = 0.04, Kᵢ = 40),
        vac_supp = PI_control(Kₚ=5,ref=[Vm*sqrt(2)],ω_f=1/0.5),
        timeDelay = 200e-6,
        padeOrderNum = 3,                    
        padeOrderDen = 3 )






    CableDC12 = cable(length = 10e3, positions = [(-0.5,1), (0.5,1)],
        C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),     
        I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)       




        
    G3[2.1] ⟷ gndD
    G3[2.2] ⟷ gndQ

    G3[1.1] == DUT[2.1] ⟷ NodeMMC1d
    G3[1.2] == DUT[2.2] ⟷ NodeMMC1q
    DUT[1.1] ⟷ CableDC12[1.1]
    CableDC12[2.1] ⟷ G_DC[1.1]

    G_DC[2.1] == gndDC



end

# Read in validation data

# lines=readlines("test/data/data_MMC_validation.txt")
lines=readlines(joinpath(@__DIR__, "data", "data_TLC_validation_1.txt"))
validation_data = [split(line) for line in lines[2:end]]
frequency =
	real([parse(Complex{Float64}, replace(row[1], "(" => "")) for row in validation_data])
omegas=2*pi*frequency
matrices = [
	reshape(parse.(Complex{Float64}, replace.(row[2:end], "(" => "")), 3, 3) for
	row in validation_data
]
Y_validation=transpose.(matrices)

# Obtain analytical data
Y_TLC = []
for k in eachindex(omegas)
	Y1 = eval_abcd(grid.elements[:DUT].element_model, 1im*omegas[k])
	push!(Y_TLC, [transpose(Y1[1, :]); transpose(-Y1[2, :]); transpose(-Y1[3, :])]) # Keep sign of Ydc, swapping sign of Yacs
end

# Compare angle and magnitudes
for k in eachindex(omegas)

	#println("Frequency: ", omegas[k]/(2*pi), " Hz")
	for c ∈ 1:3

		for r ∈ 1:3

    #println("Comparing element (", c, ", ", r, ")")
			@test abs(Y_TLC[k][c, r]) ≈ abs(Y_validation[k][c, r]) rtol=0.07 # %
			@test angle(Y_TLC[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol=3*(pi/180) # degrees
		end



	end



end


# # Plotting for visual inspection
# plot(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_TLC, 3, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_validation, 3, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

# plot(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_TLC, 1, 3))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_validation, 1, 3))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)



###Test data for: PQ-control
Vm1=220/sqrt(3) # rms - phase [kV]

Vm=Vm1

#STATCOM parameters
Vdc_ST=640 #Pole-pole DC voltage
S_ST=100 # MVA 
Z_ST_base = 220^2/S_ST
Lf_ST = 0.08 * Z_ST_base /2/pi/50
Rf_ST = 0.01 * 0.08*Z_ST_base

Q_ST=1.0
Vac_ref_ST=1.0

@time grid=@network begin
    


    voltageBase = Vm 

    G3 = ac_source(pins = 3, V = Vm, transformation = true)
    G_DC = dc_source(pins = 1, V = Vdc_ST/2)


DUT=tlc(Vᵈᶜ = 640, Vₘ =  220 /sqrt(3), Lᵣ = Lf, Rᵣ = Rf, 
                Sbase = 100, vACbase_LL_RMS = 220, vDCbase = Vdc,
                P = Powf, Q = Qowf,
                P_max = 1000, P_min = -1000, Q_max = 1000, Q_min = -1000,
                occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8),
                pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = (2*pi)*80, n_f=2), # These gains are fine.
                v_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
                i_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
                f_supp = PI_control(ω_f = 1/0.5, Kₚ =5), #
                p = PI_control(Kₚ = 0.04, Kᵢ = 40),
                q = PI_control(Kₚ = 0.04, Kᵢ = 40),
                timeDelay = 200e-6,
                padeOrderNum = 3,                    
                padeOrderDen = 3 
        )



    G3[2.1] ⟷ gndD
    G3[2.2] ⟷ gndQ

    G3[1.1] == DUT[2.1] 
    G3[1.2] == DUT[2.2]
    DUT[1.1] ⟷ G_DC[1.1]
    G_DC[2.1] == gndDC



end


# Read in validation data

# lines=readlines("test/data/data_MMC_validation.txt")
lines=readlines(joinpath(@__DIR__, "data", "data_TLC_validation_2.txt"))
validation_data = [split(line) for line in lines[2:end]]
frequency =
	real([parse(Complex{Float64}, replace(row[1], "(" => "")) for row in validation_data])
omegas=2*pi*frequency
matrices = [
	reshape(parse.(Complex{Float64}, replace.(row[2:end], "(" => "")), 3, 3) for
	row in validation_data
]
# Flipping the DC sign as in the PSCAD model the sign is inverted
Y_validation=transpose.(matrices)
for i in eachindex(Y_validation)
    Y_validation[i][1, :] *= -1
end

Y_validation_abs=[Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]
Y_validation_angle=[Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]

for c ∈ 1:3
    for r ∈ 1:3
        setindex!.(Y_validation_abs, abs.(getindex.(Y_validation,r,c)), r, c)
        setindex!.(Y_validation_angle, unwrap!(angle.(getindex.(Y_validation,r,c))), r, c)
        
    end
end

# Obtain analytical data
Y_TLC = []
for k in eachindex(omegas)
	Y1 = eval_abcd(grid.elements[:DUT].element_model, 1im*omegas[k])
	push!(Y_TLC, [transpose(Y1[1, :]); transpose(-Y1[2, :]); transpose(-Y1[3, :])]) # Keep sign of Ydc, swapping sign of Yacs
end

Y_TLC_abs=[Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]
Y_TLC_angle=[Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]

for c ∈ 1:3
    for r ∈ 1:3
        setindex!.(Y_TLC_abs, abs.(getindex.(Y_TLC,r,c)), r, c)
        setindex!.(Y_TLC_angle, unwrap!(angle.(getindex.(Y_TLC,r,c))), r, c)
        
    end
end

# Compare angle and magnitudes
for k in eachindex(omegas)

	#println("Frequency: ", omegas[k]/(2*pi), " Hz")
	for c ∈ 1:3

		for r ∈ 1:3

            #println("Comparing element (", c, ", ", r, ")")
			@test Y_TLC_abs[k][c, r] ≈ Y_validation_abs[k][c, r] rtol=0.02 # %
			@test Y_TLC_angle[k][c, r] ≈ Y_validation_angle[k][c, r] atol=1*(pi/180) # degrees

        
        end



	end



end



# # Plotting for visual inspection
# plot(omegas./(2*pi), 20*log10.(getindex.(Y_TLC_abs, 1, 3)),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), 20*log10.(getindex.(Y_validation_abs, 1, 3)),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

# plot(omegas./(2*pi), rad2deg.(getindex.(Y_TLC_angle, 1, 3)),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), rad2deg.(getindex.(Y_validation_angle, 1, 3)),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)
 =#


























# Legacy test implementation TODO: Delete

#= ###Test data for: Vdc; QV-droop
function unwrap!(x, period = 2π)
	y = convert(eltype(x), period)
	v = first(x)
	@inbounds for k = eachindex(x)
		x[k] = v = v + rem(x[k] - v,  y, RoundNearest)
	end
    return x
end


Powf = 70
Qowf = 20
Vm = 220 /sqrt(3) 
Vdc = 640

Ztrafo_base = 220^2/100
Lf = 0.08 * Ztrafo_base /2/pi/50
Rf = 0.01 * 0.08*Ztrafo_base


grid=@network begin
    


    voltageBase = Vm # Apparently needed for correct per-unit calculation of the power flow

    G3 = ac_source(pins = 3, V = Vm, transformation = true)
    G_DC = dc_source(pins = 1, V = 1*Vdc/2)

DUT=tlc(Vᵈᶜ = Vdc, Vₘ = Vm, Lᵣ = Lf, Rᵣ = Rf, 
        Sbase = 100, vACbase_LL_RMS = 220, vDCbase = Vdc,
        Q = Qowf,
        occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8),
        pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = (2*pi)*80, n_f=2), # These gains are fine.
        v_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
        i_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
        f_supp = PI_control(ω_f = 1/0.5, Kₚ =5), #
        dc = PI_control(Kₚ = 5, Kᵢ = 5),
        q = PI_control(Kₚ = 0.04, Kᵢ = 40),
        vac_supp = PI_control(Kₚ=5,ref=[Vm*sqrt(2)],ω_f=1/0.5),
        timeDelay = 200e-6,
        padeOrderNum = 3,                    
        padeOrderDen = 3 )






    CableDC12 = cable(length = 10e3, positions = [(-0.5,1), (0.5,1)],
        C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),     
        I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)       




        
    G3[2.1] ⟷ gndD
    G3[2.2] ⟷ gndQ

    G3[1.1] == DUT[2.1] ⟷ NodeMMC1d
    G3[1.2] == DUT[2.2] ⟷ NodeMMC1q
    DUT[1.1] ⟷ CableDC12[1.1]
    CableDC12[2.1] ⟷ G_DC[1.1]

    G_DC[2.1] == gndDC



end

# Read in validation data

# lines=readlines("test/data/data_MMC_validation.txt")
lines=readlines(joinpath(@__DIR__, "data", "data_TLC_validation_1.txt"))
validation_data = [split(line) for line in lines[2:end]]
frequency =
	real([parse(Complex{Float64}, replace(row[1], "(" => "")) for row in validation_data])
omegas=2*pi*frequency
matrices = [
	reshape(parse.(Complex{Float64}, replace.(row[2:end], "(" => "")), 3, 3) for
	row in validation_data
]
Y_validation=transpose.(matrices)

# Obtain analytical data
Y_TLC = []
for k in eachindex(omegas)
	Y1 = eval_abcd(grid.elements[:DUT].element_model, 1im*omegas[k])
	push!(Y_TLC, [transpose(Y1[1, :]); transpose(-Y1[2, :]); transpose(-Y1[3, :])]) # Keep sign of Ydc, swapping sign of Yacs
end

# Compare angle and magnitudes
for k in eachindex(omegas)

	#println("Frequency: ", omegas[k]/(2*pi), " Hz")
	for c ∈ 1:3

		for r ∈ 1:3

    #println("Comparing element (", c, ", ", r, ")")
			@test abs(Y_TLC[k][c, r]) ≈ abs(Y_validation[k][c, r]) rtol=0.07 # %
			@test angle(Y_TLC[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol=3*(pi/180) # degrees
		end



	end



end


# # Plotting for visual inspection
# plot(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_TLC, 3, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), 20*log10.(abs.(getindex.(Y_validation, 3, 1))),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

# plot(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_TLC, 1, 3))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), rad2deg.(angle.(getindex.(Y_validation, 1, 3))),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)



###Test data for: PQ-control
Vm1=220/sqrt(3) # rms - phase [kV]

Vm=Vm1

#STATCOM parameters
Vdc_ST=640 #Pole-pole DC voltage
S_ST=100 # MVA 
Z_ST_base = 220^2/S_ST
Lf_ST = 0.08 * Z_ST_base /2/pi/50
Rf_ST = 0.01 * 0.08*Z_ST_base

Q_ST=1.0
Vac_ref_ST=1.0

@time grid=@network begin
    


    voltageBase = Vm 

    G3 = ac_source(pins = 3, V = Vm, transformation = true)
    G_DC = dc_source(pins = 1, V = Vdc_ST/2)


DUT=tlc(Vᵈᶜ = 640, Vₘ =  220 /sqrt(3), Lᵣ = Lf, Rᵣ = Rf, 
                Sbase = 100, vACbase_LL_RMS = 220, vDCbase = Vdc,
                P = Powf, Q = Qowf,
                P_max = 1000, P_min = -1000, Q_max = 1000, Q_min = -1000,
                occ = PI_control(Kₚ = 0.254647908947033, Kᵢ = 0.8),
                pll = PI_control(Kₚ = 0.397887357729738, Kᵢ = 7.957747154594767, ω_f = (2*pi)*80, n_f=2), # These gains are fine.
                v_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
                i_meas_filt = PI_control(ω_f = 0.5e4, n_f=2),
                f_supp = PI_control(ω_f = 1/0.5, Kₚ =5), #
                p = PI_control(Kₚ = 0.04, Kᵢ = 40),
                q = PI_control(Kₚ = 0.04, Kᵢ = 40),
                timeDelay = 200e-6,
                padeOrderNum = 3,                    
                padeOrderDen = 3 
        )



    G3[2.1] ⟷ gndD
    G3[2.2] ⟷ gndQ

    G3[1.1] == DUT[2.1] 
    G3[1.2] == DUT[2.2]
    DUT[1.1] ⟷ G_DC[1.1]
    G_DC[2.1] == gndDC



end


# Read in validation data

# lines=readlines("test/data/data_MMC_validation.txt")
lines=readlines(joinpath(@__DIR__, "data", "data_TLC_validation_2.txt"))
validation_data = [split(line) for line in lines[2:end]]
frequency =
	real([parse(Complex{Float64}, replace(row[1], "(" => "")) for row in validation_data])
omegas=2*pi*frequency
matrices = [
	reshape(parse.(Complex{Float64}, replace.(row[2:end], "(" => "")), 3, 3) for
	row in validation_data
]
# Flipping the DC sign as in the PSCAD model the sign is inverted
Y_validation=transpose.(matrices)
for i in eachindex(Y_validation)
    Y_validation[i][1, :] *= -1
end

Y_validation_abs=[Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]
Y_validation_angle=[Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]

for c ∈ 1:3
    for r ∈ 1:3
        setindex!.(Y_validation_abs, abs.(getindex.(Y_validation,r,c)), r, c)
        setindex!.(Y_validation_angle, unwrap!(angle.(getindex.(Y_validation,r,c))), r, c)
        
    end
end

# Obtain analytical data
Y_TLC = []
for k in eachindex(omegas)
	Y1 = eval_abcd(grid.elements[:DUT].element_model, 1im*omegas[k])
	push!(Y_TLC, [transpose(Y1[1, :]); transpose(-Y1[2, :]); transpose(-Y1[3, :])]) # Keep sign of Ydc, swapping sign of Yacs
end

Y_TLC_abs=[Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]
Y_TLC_angle=[Matrix{Float64}(undef, 3, 3) for _ in 1:length(Y_validation)]

for c ∈ 1:3
    for r ∈ 1:3
        setindex!.(Y_TLC_abs, abs.(getindex.(Y_TLC,r,c)), r, c)
        setindex!.(Y_TLC_angle, unwrap!(angle.(getindex.(Y_TLC,r,c))), r, c)
        
    end
end

# Compare angle and magnitudes
for k in eachindex(omegas)

	#println("Frequency: ", omegas[k]/(2*pi), " Hz")
	for c ∈ 1:3

		for r ∈ 1:3

            #println("Comparing element (", c, ", ", r, ")")
			@test Y_TLC_abs[k][c, r] ≈ Y_validation_abs[k][c, r] rtol=0.02 # %
			@test Y_TLC_angle[k][c, r] ≈ Y_validation_angle[k][c, r] atol=1*(pi/180) # degrees

        
        end



	end



end



# # Plotting for visual inspection
# plot(omegas./(2*pi), 20*log10.(getindex.(Y_TLC_abs, 1, 3)),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), 20*log10.(getindex.(Y_validation_abs, 1, 3)),xlabel= "Frequency[Hz]",ylabel= "Admittance Y_11 [dB]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)

# plot(omegas./(2*pi), rad2deg.(getindex.(Y_TLC_angle, 1, 3)),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10)
# plot!(omegas./(2*pi), rad2deg.(getindex.(Y_validation_angle, 1, 3)),xlabel= "Frequency[Hz]",ylabel= "Admittance Angle [degree]",minorgrid=true, legend=:none, xaxis = :log10, line=:dash)
 =#