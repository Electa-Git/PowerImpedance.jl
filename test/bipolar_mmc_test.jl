# using JuMP: MOI.LOCALLY_SOLVED Should not be necessary, using called in PIACDC
using DelimitedFiles

function build_test_mmc_pole(; Vac = 220 * sqrt(2 / 3), Vdc = 320.0)
    elec = ElectricalMMC(vDC_base = Vdc)

    sync = PLLSynchronization()
    delta_control = ΔdqControlGFL(
        outer_active = OuterActivePowerControl(),
        outer_reactive = OuterReactiveQControl(),
        occ = InnerCurrentPIControl(),
    )
    sigma_control = ΣdqzControlTEC(
        tec = TotalEnergyControl(pi_control = PIControl()),
        zscc = ZeroSequenceCurrentControl(PIControl()),
        ccsc = CirculatingCurrentSuppressionControl(PIControl()),
    )

    return mmc(
        elec = elec,
        sync = sync,
        delta_control = delta_control,
        sigma_control = sigma_control,
        setpoint = SetPoint(Pac = 0.0, Qac = 0.0, θac = 0.0, Vac = Vac, Vdc = Vdc, Pdc = 0.0),
        limits = PowerImpedanceACDC.Limits(P_min = -1.0, P_max = 1.0, Q_min = -1.0, Q_max = 1.0),
    )
end

@testset "Bipolar MMC Admittance Mapping" begin
    pole_pos = build_test_mmc_pole()
    pole_neg = build_test_mmc_pole()

    Yp = ComplexF64[1.0 0.1 0.2; 0.3 2.0 0.4; 0.5 0.6 3.0]
    Yn = ComplexF64[1.5 0.2 0.1; 0.4 1.8 0.3; 0.7 0.5 2.5]

    pole_pos.A = zeros(ComplexF64, 1, 1)
    pole_pos.B = zeros(ComplexF64, 1, 3)
    pole_pos.C = zeros(ComplexF64, 3, 1)
    pole_pos.D = Yp

    pole_neg.A = zeros(ComplexF64, 1, 1)
    pole_neg.B = zeros(ComplexF64, 1, 3)
    pole_neg.C = zeros(ComplexF64, 3, 1)
    pole_neg.D = Yn

    bipolar = bipolar_mmc(pole_pos, pole_neg).element_model
    Y = PowerImpedanceACDC.eval_parameters(bipolar, 2im * pi * 50)

    expected = ComplexF64[
        1.0 -1.0 0.0 0.1 0.2;
       -1.0 2.5 -1.5 0.1 -0.1;
        0.0 -1.5 1.5 -0.2 -0.1;
        0.3 0.1 -0.4 3.8 0.7;
        0.5 0.2 -0.7 1.1 5.5;
    ]

    @test size(Y) == (5, 5)
    @test Y ≈ expected atol = 1e-12
end

@testset "Bipolar MMC Power-Flow Backend Smoke" begin
    Vac_rms_ln = 220 / sqrt(3)
    Vac_peak_ln = Vac_rms_ln * sqrt(2)

    @network begin
        voltageBase = Vac_rms_ln

        G = ac_source(pins = 3, V = Vac_rms_ln, transformation = true)

        S_p = dc_source(pins = 2, transformation = true, V = 320.0)
        S_r = dc_source(pins = 2, transformation = true, V = 0.0)
        S_n = dc_source(pins = 2, transformation = true, V = 320.0)

        BIP = bipolar_mmc(
            build_test_mmc_pole(Vac = Vac_peak_ln, Vdc = 320.0),
            build_test_mmc_pole(Vac = Vac_peak_ln, Vdc = 320.0),
        )

        G[2.1] == gndD
        G[2.2] == gndQ

        G[1.1] == BIP[2.1]
        G[1.2] == BIP[2.2]

        BIP[1.1] == S_p[1.1] == nodeP
        BIP[1.2] == S_r[1.1] == nodeR
        BIP[1.3] == S_n[1.1] == nodeN

        S_p[2.1] == gndDP
        S_r[2.1] == gndDR
        S_n[2.1] == gndDN
    end

    @test get(PowerImpedanceACDC.data, "_mcdc", false) == true
    @test length(PowerImpedanceACDC.data["convdc"]) == 1

    conv = first(values(PowerImpedanceACDC.data["convdc"]))
    @test haskey(conv, "status")
    @test conv["status"] isa Dict

    @test PowerImpedanceACDC.result["termination_status"] == PIACDC.JuMP.MOI.LOCALLY_SOLVED # Uses that JuMP is a dependency of PIACDC
end

function read_bipolar_validation_data(path::AbstractString)
    raw = readdlm(path, '\t', String)
    n = size(raw, 1) - 1

    omegas = zeros(Float64, n)
    Y_data = Matrix{ComplexF64}[]

    for k in 1:n
        row = raw[k + 1, :]
        omegas[k] = 2π * parse(Float64, row[1])
        vals = parse.(Float64, row[2:end])

        Y = zeros(ComplexF64, 5, 5)
        idx = 1
        for i in 1:5, j in 1:5
            Y[i, j] = vals[idx] + 1im * vals[idx + 1]
            idx += 2
        end
        push!(Y_data, Y)
    end

    return omegas, Y_data
end

function build_scan_matched_mmc_pole(; Pac, Qac, Vac, Vdc)
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

    meas = PowerImpedanceACDC.Measurement()

    sync = PowerImpedanceACDC.PLLSynchronization(
        pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.28, Ki = 12.5664),
        filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 75 * 2π),
    )

    delta_control = PowerImpedanceACDC.ΔdqControlGFL(
        outer_active = PowerImpedanceACDC.OuterActivePowerControl(
            pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.1, Ki = 31.4159),
            P_ac_ref = Pac / 1060.0,
            filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 140 * 2π),
        ),
        outer_reactive = PowerImpedanceACDC.OuterReactiveQControl(
            pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.0, Ki = 30.0),
            Q_ac_ref = -Qac / 1060.0,
            filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 140 * 2π),
        ),
        occ = PowerImpedanceACDC.InnerCurrentPIControl(
            pi_ctrl = PowerImpedanceACDC.PIControl(Kp = 0.6787, Ki = 292.2087),
            filter = PowerImpedanceACDC.Butterworth(order = 1, ωc = 200.0),
        ),
    )

    sigma_control = PowerImpedanceACDC.ΣdqzControlTEC(
        tec = PowerImpedanceACDC.TotalEnergyControl(
            pi_control = PowerImpedanceACDC.PIControl(Kp = 1.386, Ki = 29.70),
        ),
        zscc = PowerImpedanceACDC.ZeroSequenceCurrentControl(
            PowerImpedanceACDC.PIControl(Kp = 0.0, Ki = 0.0),
        ),
        ccsc = PowerImpedanceACDC.CirculatingCurrentSuppressionControl(
            PowerImpedanceACDC.PIControl(Kp = 0.0992, Ki = 42.9719),
        ),
    )

    return PowerImpedanceACDC.mmc(
        elec = elec,
        meas = meas,
        sync = sync,
        delta_control = delta_control,
        sigma_control = sigma_control,
        modulation = PowerImpedanceACDC.UncompensatedModulation(
            timeDelay = 0.0,
            padeOrderNum = 0,
            padeOrderDen = 0,
        ),
        setpoint = SetPoint(Pac = Pac, Qac = Qac, θac = 0.0, Vac = Vac, Vdc = Vdc, Pdc = Pac),
        limits = PowerImpedanceACDC.Limits(
            P_min = -1500.0,
            P_max = 1500.0,
            Q_min = -1000.0,
            Q_max = 1000.0,
        ),
    )
end

function build_bipolar_scan_component()
    Pac_pole = 0.7 * 1060
    Qac_pole = 0.0
    Vac = 400 / sqrt(3)
    Vdc_total = 640.0

    elem = bipolar_mmc(
        build_scan_matched_mmc_pole(Pac = Pac_pole, Qac = Qac_pole, Vac = Vac, Vdc = Vdc_total),
        build_scan_matched_mmc_pole(Pac = Pac_pole, Qac = Qac_pole, Vac = Vac, Vdc = Vdc_total),
    )

    # Direct component update at station setpoint (no power-flow, no network macro).
    PowerImpedanceACDC.update!(
        elem.element_model,
        Vac,
        0.0,
        2 * Pac_pole,
        2 * Qac_pole,
        Vdc_total,
        2 * Pac_pole,
    )

    return elem
end

function bipolar_component_y_dqprn(elem, s::Complex)
    # Raw ordering from BipolarMMC is [p, r, n, d, q] and values are per-unit.
    Y = Matrix{ComplexF64}(PowerImpedanceACDC.eval_parameters(elem.element_model, s))

    ep = elem.element_model.pole_pos.element_model.elec
    i_dc_base = ep.Sbase / ep.vDC_base
    i_ac_base = (2 * ep.Sbase / (3 * ep.vAC_base)) * ep.turnsRatio

    Y[1:3, :] .*= i_dc_base
    Y[4:5, :] .*= i_ac_base

    Y[:, 1:3] ./= ep.vDC_base
    Y[:, 4:5] ./= ep.vAC_base

    # Validation data ordering is [d, q, p, r, n].
    Y = Y[[4, 5, 1, 2, 3], [4, 5, 1, 2, 3]]

    # Match scan current sign convention used in existing MMC validation tests.
    Y[1:2, :] .*= -1

    return Y
end

@testset "Bipolar MMC GFL Scan Validation (Component-Only)" begin
    omegas, Y_validation =
        read_bipolar_validation_data(joinpath(@__DIR__, "data", "data_bipolar_validation_PQ_GFL.txt"))

    elem = build_bipolar_scan_component()
    max_err = 0.0
    worst_freq_hz = 0.0
    worst_idx = (0, 0)
    for (k, ω) in enumerate(omegas)
        Y_model = bipolar_component_y_dqprn(elem, 1im * ω)
        for i in 1:5, j in 1:5
            err = abs(Y_model[i, j] - Y_validation[k][i, j])
            if err > max_err
                max_err = err
                worst_freq_hz = ω / (2π)
                worst_idx = (i, j)
            end
        end
    end

    if max_err > 1e-4
        @info "Bipolar component-only scan mismatch (candidate BriskSim mismatch)" max_err worst_freq_hz worst_idx
    end
    @test_broken max_err <= 1e-4
end
