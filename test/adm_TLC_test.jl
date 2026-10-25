
function unwrap!(x, period = 2π)
    y = convert(eltype(x), period)
    v = first(x)
    @inbounds for k in eachindex(x)
        x[k] = v = v + rem(x[k] - v, y, RoundNearest)
    end
    return x
end

function read_validation_data(path::AbstractString)
    lines = readlines(path)
    validation_data = [split(line) for line in lines[2:end]]

    frequency = real([parse(ComplexF64, replace(row[1], "(" => ""))
                      for row in validation_data])
    omegas = 2π .* frequency

    matrices = [reshape(parse.(ComplexF64, replace.(row[2:end], "(" => "")), 3, 3)
                for row in validation_data]

    return omegas, transpose.(matrices)
end

function tlc_y(elem, s::Complex)
    A, B, C, D = elem.cache.A, elem.cache.B, elem.cache.C, elem.cache.D
    n = size(A, 1)
    Iₙ = Matrix{ComplexF64}(I, n, n)
    Y = C * ((s * Iₙ - A) \ B) + D

    conv = elem
    elec = conv.elec

    Y = Matrix{ComplexF64}(Y)

    Y[1, :] .*= elec.iDCbase
    Y[:, 1] ./= elec.vDCbase

    Y[2:3, :] .*= elec.iACbase
    Y[:, 2:3] ./= elec.vACbase

    return Y
end

function tlc_plot_convention(Y::AbstractMatrix)
    return [transpose(Y[1, :]); transpose(Y[2, :]); transpose(Y[3, :])]
end

function common_tlc_blocks(; Vm, Vdc, Lf, Rf)
    elec = PowerImpedance.ElectricalTLC(
        Lᵣ = Lf,
        Rᵣ = Rf,
        Sbase = 100.0,
        vACbase_LL_RMS = 220.0,
        vDCbase = Vdc
    )

    meas = PowerImpedance.Measurement(
        v_ac = PowerImpedance.Butterworth(order = 2, ωc = 0.5e4),
        i_ac = PowerImpedance.Butterworth(order = 2, ωc = 0.5e4)
    )

    sync = PowerImpedance.PLLSynchronization(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.397887357729738,
            Ki = 7.957747154594767
        ),
        filter = PowerImpedance.Butterworth(order = 2, ωc = 2π * 80)
    )

    innerVoltage = PowerImpedance.NoInnerVoltageControl()

    innerCurrent = PowerImpedance.InnerCurrentPIControl(
        pi_ctrl = PowerImpedance.PIControl(
        Kp = 0.254647908947033,
        Ki = 0.8
    ),
    )

    mod = PowerImpedance.PadeModulation(
        timeDelay = 200e-6,
        padeOrderNum = 3,
        padeOrderDen = 3
    )

    limits = PowerImpedance.Limits(
        P_min = -1000.0,
        P_max = 1000.0,
        Q_min = -1000.0,
        Q_max = 1000.0
    )

    return elec, meas, sync, innerVoltage, innerCurrent, mod, limits
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

    elec, meas, sync, innerVoltage, innerCurrent,
    mod, limits = common_tlc_blocks(; Vm, Vdc, Lf, Rf)

    q_ref_pu = -Qowf / elec.Sbase
    vdc_ref_pu = Vdc / elec.vDCbase
    vac_ref_pu = Vac_peak / (elec.vACbase)

    limits = PowerImpedance.Limits(
        P_min = -100.0,
        P_max = 100.0,
        Q_min = -50.0,
        Q_max = 50.0
    )

    vac_ref_pu = Vac_peak / (elec.vACbase)

    outerActive = PowerImpedance.OuterActiveVdcControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 5.0, Ki = 5.0),
    )

    outerReactive = PowerImpedance.OuterReactiveQControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
        support = PowerImpedance.VoltageSupportLag(
            K = 5.0,
            ωc = 1 / 0.5
        )
    )

    dut = PowerImpedance.tlc(
        elec = elec,
        meas = meas,
        sync = sync,
        outerActive = outerActive,
        outerReactive = outerReactive,
        innerVoltage = innerVoltage,
        innerCurrent = innerCurrent,
        mod = mod,
        limits = limits
    )

    b = bases(dut)
    dut = component(dut; outerActive = (v_dc_ref = Vdc / b.v_dc,),
        outerReactive = (q_ref = Qowf / b.S,
            support = (v_ac_ref = Vac_peak / b.v_ac,)),
        powerflow = (p_ac = Powf / b.S, p_dc = Powf / b.S))
    CableDC12 = cable(length = 10e3, positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
        I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3)
    )
    elements = (; G3 = ac_source(v = Vm * sqrt(2)),
        G_DC = dc_source(v = Vdc), DUT = dut, CableDC12)
    topology = (
        NetworkBuilder.Bus(:NodeMMC1; ports = ((:G3, :ac), (:DUT, :ac)), domain = ACDQ),
        NetworkBuilder.Bus(:DC1; ports = ((:DUT, :dc), (:CableDC12, :side1))),
        NetworkBuilder.Bus(:DC2; ports = ((:CableDC12, :side2), (:G_DC, :dc))))
    grid = NetworkBuilder.define(elements, topology; options = (; voltageBase = Vm))
    result = compute(PowerFlowProblem(grid), ACDCPowerFlow())
    linearize(grid.elements.DUT, result.operating_point[:DUT])

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

    elec, meas, sync, innerVoltage, innerCurrent,
    mod, limits = common_tlc_blocks(; Vm, Vdc, Lf, Rf)

    p_ref_pu = Powf / elec.Sbase
    q_ref_pu = -Qowf / elec.Sbase

    limits = PowerImpedance.Limits(
        P_min = -1000.0,
        P_max = 1000.0,
        Q_min = -1000.0,
        Q_max = 1000.0
    )

    outerActive = PowerImpedance.OuterActivePowerControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
        support = PowerImpedance.FrequencySupportLag(
            Kω = 5.0,
            ωc = 1 / 0.5
        )
    )

    outerReactive = PowerImpedance.OuterReactiveQControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.04, Ki = 40.0),
    )

    dut = PowerImpedance.tlc(
        elec = elec,
        meas = meas,
        sync = sync,
        outerActive = outerActive,
        outerReactive = outerReactive,
        innerVoltage = innerVoltage,
        innerCurrent = innerCurrent,
        mod = mod,
        limits = limits
    )

    b = bases(dut)
    dut = component(dut; outerActive = (p_ref = Powf / b.S,),
        outerReactive = (q_ref = Qowf / b.S,),
        powerflow = (v_ac = Vac_peak / b.v_ac,
            p_dc = Powf / b.S, v_dc = Vdc / b.v_dc))
    elements = (; G3 = ac_source(v = Vm * sqrt(2)),
        G_DC = dc_source(v = Vdc), DUT = dut)
    topology = (
        NetworkBuilder.Bus(:AC; ports = ((:G3, :ac), (:DUT, :ac)), domain = ACDQ),
        NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc), (:G_DC, :dc))))
    grid = NetworkBuilder.define(elements, topology; options = (; voltageBase = Vm))
    result = compute(PowerFlowProblem(grid), ACDCPowerFlow())
    linearize(grid.elements.DUT, result.operating_point[:DUT])

    return grid
end

#
# Case 1: Vdc ; QV-droop / Vac support
#

omegas,
Y_validation = read_validation_data(joinpath(@__DIR__, "data",
    "data_TLC_validation_1.txt"))
grid = build_case1_grid()
elem = grid.elements[:DUT]

Y_TLC = Matrix{ComplexF64}[]
for ω in omegas
    Y1 = tlc_y(elem, 1im * ω)
    push!(Y_TLC, tlc_plot_convention(Y1))
end

for k in eachindex(omegas)
    for c in 1:3, r in 1:3

        @test abs(Y_TLC[k][c, r]) ≈ abs(Y_validation[k][c, r]) atol = 1e-4 #0.07 #0.07
        @test angle(Y_TLC[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol = 3 * (π / 180)
    end
end

#
# Case 2: PQ-control
#

omegas,
Y_validation = read_validation_data(joinpath(@__DIR__, "data",
    "data_TLC_validation_2.txt"))
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
    Y1 = tlc_y(elem, 1im * ω)
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

        @test Y_TLC_abs[k][c, r] ≈ Y_validation_abs[k][c, r] atol = 1e-4 #0.02
        @test Y_TLC_angle[k][c, r] ≈ Y_validation_angle[k][c, r] atol = 1 * (π / 180)
    end
end
