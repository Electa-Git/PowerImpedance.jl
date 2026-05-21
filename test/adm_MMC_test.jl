
using PowerImpedanceACDC
using LinearAlgebra
using Test

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

    elec = elem.element_model.elec
    iACbase = 2 * elec.Sbase / (3 * elec.vAC_base)
    iDCbase = elec.Sbase / elec.vDC_base

    Y = Matrix{ComplexF64}(Y)
    Y[1, :] .*= iDCbase
    Y[2:3, :] .*= iACbase * elec.turnsRatio

    Y[:, 1] ./= elec.vDC_base
    Y[:, 2:3] ./= elec.vAC_base

    return Y
end

function mmc_plot_convention(Y::AbstractMatrix)
    return [transpose(Y[1, :]); transpose(-Y[2, :]); transpose(-Y[3, :])]
end

function common_mmc_blocks(; Pmmc, Qmmc, Vm, Vdc)
    elec = PowerImpedanceACDC.ElectricalMMC(
        vDC_base = 640.0,
        Sbase = 1060.0,
        vACbase_LL_RMS = 320.0,
        turnsRatio = 320 / 400,
        Lᵣ = 0.18 * (320^2 / 1060) / (2π * 50),
        Rᵣ = 0.001 * (320^2 / 1060),
        Rₐᵣₘ = 0.4,
        Lₐᵣₘ = 46.125e-3,
        Cₐᵣₘ = 11.3867e-3,
        N = 400,
    )

    meas = PowerImpedanceACDC.Measurement(
        P_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
        Q_ac = PowerImpedanceACDC.Butterworth(order = 2, ωc = 140 * 2π),
    )

    pll = PowerImpedanceACDC.PLLSynchronization(
        pi_ctrl = PowerImpedanceACDC.PIControl(
            Kp = 0.28,
            Ki = 12.5664,
        ),
        filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 75 * 2π),
    )

    synch = PowerImpedanceACDC.VSEWithDamping(
        H = 5.0,
        K_d = 100.0,
        K_ω = 10.0,
        P_ac_ref = Pmmc / 1060.0,
        pll = pll,
    )

    outerReactive = PowerImpedanceACDC.OuterReactiveQControl(
        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.0, Ki = 30.0),
        Q_ac_ref = -Qmmc / 1060.0,
    )

    innerVoltage = PowerImpedanceACDC.CCVI(
        R_v = 0.01,
        L_v = 0.25,
        V_d_ref = 1.0,
        V_q_ref = 0.0,
        filter = PowerImpedanceACDC.Butterworth(order = 2, ωc = 200.0),
    )

    innerCurrent = PowerImpedanceACDC.InnerCurrentPIControl(
        pi_ctrl = PowerImpedanceACDC.PIControl(
            Kp = 0.6787,
            Ki = 292.2087,
        ),
        filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 0.0001 * 2π),
    )

    delta_control = PowerImpedanceACDC.ΔdqControlGFM(
        outer_reactive = outerReactive,
        vi = innerVoltage,
        occ = innerCurrent,
    )

    energy = PowerImpedanceACDC.TotalEnergyControl(
        pi_control = PowerImpedanceACDC.PIControl(Kp = 1.386, Ki = 29.70),
    )

    zeroCurrent = PowerImpedanceACDC.ZeroSequenceCurrentControl(
        PowerImpedanceACDC.PIControl(Kp = 0.0992, Ki = 42.9719),
    )

    circulatingCurrent = PowerImpedanceACDC.CirculatingCurrentSuppressionControl(
        PowerImpedanceACDC.PIControl(Kp = 0.0992, Ki = 42.9719),
    )

    sigma_control = PowerImpedanceACDC.ΣdqzControlTEC(
        tec = energy,
        zscc = zeroCurrent,
        ccsc = circulatingCurrent,
    )

    mod = PowerImpedanceACDC.UncompensatedModulation(
        timeDelay = 200e-6,
        padeOrderNum = 5,
        padeOrderDen = 5,
    )

    setpoint = PowerImpedanceACDC.SetPoint(
        Pac = Pmmc,
        Qac = Qmmc,
        θac = 0.0,
        Vac = Vm,
        Pdc = Pmmc,
        Vdc = Vdc,
    )

    limits = PowerImpedanceACDC.Limits(
        P_min = -1500.0,
        P_max = 1500.0,
        Q_min = -1000.0,
        Q_max = 1000.0,
    )

    return elec, meas, synch, delta_control, sigma_control, mod, setpoint, limits
end

function build_mmc_grid()
    Pmmc = 0.7 * 1060
    Qmmc = 0.0
    Vm = 400 / sqrt(3)
    Vdc = 640.0

    elec, meas, synch, delta_control, sigma_control, mod, setpoint, limits =
        common_mmc_blocks(; Pmmc, Qmmc, Vm, Vdc)

    dut = PowerImpedanceACDC.mmc(
        elec = elec,
        meas = meas,
        sync = synch,
        delta_control = delta_control,
        sigma_control = sigma_control,
        modulation = mod,
        setpoint = setpoint,
        limits = limits,
    )

    grid = @network begin
        voltageBase = Vm

        G3 = ac_source(pins = 3, setpoint = SetPoint(Vac = Vm), transformation = true)
        G_DC = dc_source(pins = 1, setpoint = SetPoint(Vdc = Vdc / 2))

        DUT = dut

        G3[2.1] == gndD
        G3[2.2] == gndQ

        G3[1.1] == DUT[2.1]
        G3[1.2] == DUT[2.2]
        G_DC[1.1] == DUT[1.1]
        G_DC[2.1] == gndDC
    end

    return grid
end

omegas, Y_validation = read_validation_data(joinpath(@__DIR__, "data", "data_MMC_validation.txt"))
grid = build_mmc_grid()
elem = grid.elements[:DUT]

Y_MMC = Matrix{ComplexF64}[]
for ω in omegas
    Y1 = element_y(elem, 1im * ω)
    push!(Y_MMC, mmc_plot_convention(Y1))
end

for k in eachindex(omegas)
    for c in 1:3, r in 1:3
        @test abs(Y_MMC[k][c, r]) ≈ abs(Y_validation[k][c, r]) atol = 1e-4
        @test angle(Y_MMC[k][c, r]) ≈ angle(Y_validation[k][c, r]) atol = 7 * (π / 180)
    end
end
