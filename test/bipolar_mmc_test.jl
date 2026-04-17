using JuMP

function _build_test_mmc_pole(; Vac = 220 * sqrt(2 / 3), Vdc = 320.0)
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
    pole_pos = _build_test_mmc_pole()
    pole_neg = _build_test_mmc_pole()

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
            _build_test_mmc_pole(Vac = Vac_peak_ln, Vdc = 320.0),
            _build_test_mmc_pole(Vac = Vac_peak_ln, Vdc = 320.0),
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

    @test PowerImpedanceACDC.result["termination_status"] == JuMP.MOI.LOCALLY_SOLVED
end

