using DelimitedFiles
using JuMP
using LinearAlgebra
using Plots
using PowerImpedanceACDC
using PowerImpedanceACDC:
    @network,
    CCVI,
    CirculatingCurrentSuppressionControl,
    ElectricalMMC,
    InnerCurrentPIControl,
    Limits,
    Measurement,
    OuterActivePowerControl,
    OuterReactiveQControl,
    PIControl,
    PLLSynchronization,
    SetPoint,
    TotalEnergyControl,
    UncompensatedModulation,
    VSEWithDamping,
    ZeroSequenceCurrentControl,
    Butterworth,
    ΔdqControlGFL,
    ΔdqControlGFM,
    ΣdqzControlTEC,
    ac_source,
    bipolar_mmc,
    dc_source,
    eval_parameters,
    mmc,
    update!
using Test

const BIPOLAR_MMC_PSCAD_DIR = joinpath(@__DIR__, "data")
const POWERFLOW_BASE_MVA = 1000.0
const MMC_POLE_VDC_KV = 640.0
const BIPOLAR_VDC_TOTAL_KV = 2 * MMC_POLE_VDC_KV
const BIPOLAR_PHASE_FLOOR = 2e-3

_dict_get_anykey(dict_like, key::String, default = 0.0) = haskey(dict_like, key) ? dict_like[key] : haskey(dict_like, Symbol(key)) ? dict_like[Symbol(key)] : default
_pole_value(value, pole::String; default = 0.0) = value isa Dict ? _dict_get_anykey(value, pole, default) : value

function bipolar_parse_complex(text::AbstractString)
    cleaned = replace(strip(text), "(" => "", ")" => "")
    return parse(ComplexF64, cleaned)
end

function read_bipolar_power_flow(path::AbstractString)
    rows = split.(readlines(path)[2:end])
    ac = rows[findfirst(row -> row[1] in ("MMC_AC", "MMC-AC"), rows)]

    return (
        Vac_LL_RMS = parse(Float64, ac[2]),
        Pac_terminal = parse(Float64, ac[3]),
        Qac_terminal = parse(Float64, ac[5]),
        θac = parse(Float64, ac[6]),
    )
end

function read_bipolar_scan(path::AbstractString)
    raw = readdlm(path, Char(9), String)

    omegas = Float64[]
    matrices = Matrix{ComplexF64}[]

    for row_idx in 2:size(raw, 1)
        row = raw[row_idx, :]
        push!(omegas, 2π * real(bipolar_parse_complex(row[1])))
        vals = bipolar_parse_complex.(row[2:end])
        n_ports = round(Int, sqrt(length(vals)))
        n_ports^2 == length(vals) || throw(ArgumentError("Bipolar scan row does not contain a square admittance matrix."))
        push!(matrices, transpose(reshape(vals, n_ports, n_ports)))
    end

    return omegas, matrices
end

function build_mapping_test_pole(; Vac = 220 * sqrt(2 / 3), Vdc = 320.0)
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
        setpoint = SetPoint(Pac = 0.7, Qac = 0.0, θac = -1.5393799172821/2 /π *360, Vac = Vac, Vdc = Vdc, Pdc = -0.7),
        limits = Limits(P_min = -1.0, P_max = 1.0, Q_min = -1.0, Q_max = 1.0),
    )
end

function build_adm_style_gfm_pole(; Pac, Qac, Vac_setpoint, Vdc)
    elec = ElectricalMMC(
        vDC_base = MMC_POLE_VDC_KV,
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

    meas = Measurement(
        P_ac = Butterworth(order = 2, ωc = 140 * 2π),
        Q_ac = Butterworth(order = 2, ωc = 140 * 2π),
    )

    pll = PLLSynchronization(
        pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664),
        filter = Butterworth(order = 1, ωc = 75 * 2π),
    )

    sync = VSEWithDamping(
        H = 5.0,
        K_d = 100.0,
        K_ω = 10.0,
        P_ac_ref = Pac / 1060.0,
        pll = pll,
    )

    delta_control = ΔdqControlGFM(
        outer_reactive = OuterReactiveQControl(
            pi_ctrl = PIControl(Kp = 0.0, Ki = 30.0),
            Q_ac_ref = -Qac / 1060.0,
        ),
        vi = CCVI(
            R_v = 0.01,
            L_v = 0.25,
            V_d_ref = 1.0,
            V_q_ref = 0.0,
            filter = Butterworth(order = 2, ωc = 200.0),
        ),
        occ = InnerCurrentPIControl(
            pi_ctrl = PIControl(Kp = 0.6787, Ki = 292.2087),
            filter = Butterworth(order = 1, ωc = 0.000001 * 2π),
        ),
    )

    sigma_control = ΣdqzControlTEC(
        tec = TotalEnergyControl(
            pi_control = PIControl(Kp = 1.386, Ki = 29.70),
        ),
        zscc = ZeroSequenceCurrentControl(PIControl(Kp = 0.0992, Ki = 42.9719)),
        ccsc = CirculatingCurrentSuppressionControl(PIControl(Kp = 0.0992, Ki = 42.9719)),
    )

    return mmc(
        elec = elec,
        meas = meas,
        sync = sync,
        delta_control = delta_control,
        sigma_control = sigma_control,
        modulation = UncompensatedModulation(timeDelay = 200e-6, padeOrderNum = 5, padeOrderDen = 5),
        setpoint = SetPoint(Pac = Pac, Qac = Qac, θac = 0.0, Vac = Vac_setpoint, Vdc = Vdc, Pdc = Pac),
        limits = Limits(P_min = -1500.0, P_max = 1500.0, Q_min = -1000.0, Q_max = 1000.0),
    )
end

function build_bipolar_gfm_station(; Pac_pole, Qac_pole, Vac_setpoint, Vdc_total)
    return bipolar_mmc(
        build_adm_style_gfm_pole(Pac = Pac_pole, Qac = Qac_pole, Vac_setpoint = Vac_setpoint, Vdc = Vdc_total / 2),
        build_adm_style_gfm_pole(Pac = Pac_pole, Qac = Qac_pole, Vac_setpoint = Vac_setpoint, Vdc = Vdc_total / 2),
    )
end

function build_bipolar_gfm_from_adm_mmc_test()
    Pmmc = 0.7 * 1060
    Qmmc = 0.0
    Vm = 400 / sqrt(3)

    elem = build_bipolar_gfm_station(
        Pac_pole = Pmmc,
        Qac_pole = Qmmc,
        Vac_setpoint = Vm,
        Vdc_total = BIPOLAR_VDC_TOTAL_KV,
    )

    update!(
        elem.element_model,
        Vm * sqrt(2),
        0.0,
        2 * Pmmc,
        2 * Qmmc,
        BIPOLAR_VDC_TOTAL_KV,
        2 * Pmmc,
    )

    return elem
end

function build_bipolar_gfm_from_pscad_power_flow(pscad_pf)
    Pac_pole = -pscad_pf.Pac_terminal / 2
    Qac_pole = pscad_pf.Qac_terminal / 2
    Vac_ln_rms = pscad_pf.Vac_LL_RMS / sqrt(3)
    Vac_ln_peak = pscad_pf.Vac_LL_RMS * sqrt(2 / 3)

    elem = build_bipolar_gfm_station(
        Pac_pole = Pac_pole,
        Qac_pole = Qac_pole,
        Vac_setpoint = Vac_ln_rms,
        Vdc_total = BIPOLAR_VDC_TOTAL_KV,
    )

    update!(
        elem.element_model,
        Vac_ln_peak,
        pscad_pf.θac,
        2 * Pac_pole,
        2 * Qac_pole,
        BIPOLAR_VDC_TOTAL_KV,
        2 * Pac_pole,
    )

    return elem
end

function bipolar_admittance_si_scan_convention(elem, s::Complex)
    # Raw BipolarMMC ordering is [p, r, n, d, q] and values are per-unit.
    Y = Matrix{ComplexF64}(eval_parameters(elem.element_model, s))

    ep = elem.element_model.pole_pos.element_model.elec
    i_dc_base = ep.Sbase / ep.vDC_base
    i_ac_base = (2 * ep.Sbase / (3 * ep.vAC_base)) * ep.turnsRatio

    Y[1:3, :] .*= i_dc_base
    Y[4:5, :] .*= i_ac_base
    Y[:, 1:3] ./= ep.vDC_base
    Y[:, 4:5] ./= ep.vAC_base

    # PSCAD scan ordering is [d, q, p, n] and uses the opposite AC-current sign.
    Y_scan = Y[[4, 5, 1, 3], [4, 5, 1, 3]]
    Y_scan[1:2, :] .*= -1
    return Y_scan
end

phase_delta(a, b) = abs(angle(exp(1im * (angle(a) - angle(b)))))
phase_is_testable(a, b; floor = BIPOLAR_PHASE_FLOOR) = max(abs(a), abs(b)) >= floor
bipolar_component_is_ignored(row, col) = (row, col) in ((3, 4), (4, 3))

function report_bipolar_test_failures(omegas, validation_y, model_y; mag_atol = 1e-1, phase_atol_deg = 30.0)
    labels = ["d-d" "d-q" "d-p" "d-n"; "q-d" "q-q" "q-p" "q-n"; "p-d" "p-q" "p-p" "p-n"; "n-d" "n-q" "n-p" "n-n"]
    phase_atol = deg2rad(phase_atol_deg)

    mag_failures = String[]
    phase_failures = String[]

    for k in eachindex(omegas)
        freq_hz = omegas[k] / (2π)

        for row in 1:4, col in 1:4
            bipolar_component_is_ignored(row, col) && continue

            model_entry = model_y[k][row, col]
            validation_entry = validation_y[k][row, col]

            if !isapprox(abs(model_entry), abs(validation_entry); atol = mag_atol)
                push!(mag_failures, "$(round(freq_hz; digits = 4)) Hz ($(labels[row, col]))")
            end

            if phase_is_testable(model_entry, validation_entry) && !(phase_delta(model_entry, validation_entry) <= phase_atol)
                push!(phase_failures, "$(round(freq_hz; digits = 4)) Hz ($(labels[row, col]))")
            end
        end
    end

    if !isempty(mag_failures)
        @info "Bipolar MMC admittance magnitude mismatches" failures = mag_failures
    end

    if !isempty(phase_failures)
        @info "Bipolar MMC admittance phase mismatches" failures = phase_failures
    end
end


@testset "Bipolar MMC Admittance Mapping" begin
    pole_pos = build_mapping_test_pole()
    pole_neg = build_mapping_test_pole()

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
    Y = eval_parameters(bipolar, 2im * π * 50)

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



@testset "Bipolar MMC GFM PSCAD admittance" begin
    scan_path = joinpath(BIPOLAR_MMC_PSCAD_DIR, "data_MMC_bipolar.txt")

    omegas, Y_scan = read_bipolar_scan(scan_path)

    @test size(first(Y_scan)) == (4, 4)

    # Match the single-MMC GFM operating point from adm_MMC_test.jl on both poles.
    elem = build_bipolar_gfm_from_adm_mmc_test()
    Y_model = [bipolar_admittance_si_scan_convention(elem, 1im * ω) for ω in omegas]

    report_bipolar_test_failures(omegas, Y_scan, Y_model)

    for k in eachindex(omegas)
        for row in 1:4, col in 1:4
            bipolar_component_is_ignored(row, col) && continue

            @test abs(Y_model[k][row, col]) ≈ abs(Y_scan[k][row, col]) atol = 1e-1
            if phase_is_testable(Y_model[k][row, col], Y_scan[k][row, col])
                @test phase_delta(Y_model[k][row, col], Y_scan[k][row, col]) <= 30 * (π / 180)
            end
        end
    end

    #plot_path = save_bipolar_gfm_admittance_plot(omegas ./ 2π, Y_scan, Y_model)
    #@test isfile(plot_path)
end



# TODO: Currently broken, waiting for refactor changes before touching the power flow again
# @testset "Bipolar MMC GFM PSCAD power flow" begin
#     pf_path = joinpath(BIPOLAR_MMC_PSCAD_DIR, "bipolar_MMC_Scan_power_flow.txt")
#     pscad_pf = read_bipolar_power_flow(pf_path)

#     @test pscad_pf.Vac_LL_RMS ≈ 403.668 atol = 1e-3
#     @test pscad_pf.Pac_terminal ≈ -1483.88 atol = 1e-2
#     @test pscad_pf.Qac_terminal ≈ 0.508287 atol = 1e-6
#     @test pscad_pf.θac ≈ -1.53937 atol = 1e-5

#     vac_ln_rms = pscad_pf.Vac_LL_RMS / sqrt(3)

#     try
#         run_bipolar_mcdc_power_flow(pscad_pf)
#         status = PowerImpedanceACDC.result["termination_status"]

#         if status == JuMP.MOI.LOCALLY_SOLVED
#             conv = first(values(PowerImpedanceACDC.result["solution"]["convdc"]))
#             bus = first(values(PowerImpedanceACDC.result["solution"]["bus"]))
#             solved_pf = solved_bipolar_pf_from_solution(conv, bus, vac_ln_rms)

#             @test solved_pf.Vac_LL_RMS ≈ pscad_pf.Vac_LL_RMS atol = 1e-3
#             @test solved_pf.Pac_terminal ≈ pscad_pf.Pac_terminal atol = 1.0
#             @test solved_pf.Qac_terminal ≈ pscad_pf.Qac_terminal atol = 1.0
#             @test solved_pf.θac ≈ pscad_pf.θac atol = 2e-2
#         else
#             @info "Bipolar MCDC power flow did not converge to LOCALLY_SOLVED" status
#             @test_broken status == JuMP.MOI.LOCALLY_SOLVED
#         end
#     catch err
#         @info "Bipolar MCDC power-flow validation raised an exception" err
#         @test_broken false
#     end
# end


# TODO: These are uncommented, because they are part of the broken power flow test
# function save_bipolar_gfm_admittance_plot(frequencies, scan_y, model_y)
#     labels = ["d-d" "d-q" "d-p" "d-n"; "q-d" "q-q" "q-p" "q-n"; "p-d" "p-q" "p-p" "p-n"; "n-d" "n-q" "n-p" "n-n"]
#     components = [(row, col) for row in 1:4 for col in 1:4 if !bipolar_component_is_ignored(row, col)]
#     plt = plot(layout = (length(components), 2), size = (1200, 2800))

#     for (component, (row, col)) in enumerate(components)
#         mag_idx = 2component - 1
#         phase_idx = 2component

#         scan_component = getindex.(scan_y, row, col)
#         model_component = getindex.(model_y, row, col)

#         plot!(
#             plt[mag_idx],
#             frequencies,
#             abs.(scan_component),
#             xaxis = :log10,
#             yaxis = :log10,
#             label = "PSCAD",
#             linewidth = 1.8,
#             title = labels[row, col],
#         )
#         plot!(
#             plt[mag_idx],
#             frequencies,
#             abs.(model_component),
#             xaxis = :log10,
#             yaxis = :log10,
#             label = "PowerImpedanceACDC",
#             linestyle = :dash,
#             linewidth = 1.8,
#             ylabel = "|Y|",
#         )

#         plot!(
#             plt[phase_idx],
#             frequencies,
#             rad2deg.(angle.(scan_component)),
#             xaxis = :log10,
#             label = "PSCAD",
#             linewidth = 1.8,
#         )
#         plot!(
#             plt[phase_idx],
#             frequencies,
#             rad2deg.(angle.(model_component)),
#             xaxis = :log10,
#             label = "PowerImpedanceACDC",
#             linestyle = :dash,
#             linewidth = 1.8,
#             ylabel = "deg",
#         )
#     end

#     mkpath(joinpath(@__DIR__, "output"))
#     path = joinpath(@__DIR__, "output", "Bipolar_MMC_GFM_admittance_comparison.png")
#     savefig(plt, path)
#     return path
# end

# function run_bipolar_mcdc_power_flow(pscad_pf)
#     Vac_ln_rms = pscad_pf.Vac_LL_RMS / sqrt(3)
#     Pac_pole = -pscad_pf.Pac_terminal / 2
#     Qac_pole = pscad_pf.Qac_terminal / 2

#     @network begin
#         voltageBase = Vac_ln_rms

#         G = ac_source(pins = 3, V = Vac_ln_rms, transformation = true)
#         S_pr = dc_source(pins = 1, V = BIPOLAR_VDC_TOTAL_KV / 2)
#         S_rn = dc_source(pins = 1, V = BIPOLAR_VDC_TOTAL_KV / 2)

#         BIP = build_bipolar_gfm_station(
#             Pac_pole = Pac_pole,
#             Qac_pole = Qac_pole,
#             Vac_setpoint = Vac_ln_rms,
#             Vdc_total = BIPOLAR_VDC_TOTAL_KV,
#         )

#         G[2.1] == gndD
#         G[2.2] == gndQ
#         G[1.1] == BIP[2.1]
#         G[1.2] == BIP[2.2]

#         S_pr[1.1] == BIP[1.1]
#         S_pr[2.1] == BIP[1.2]
#         S_rn[1.1] == BIP[1.2]
#         S_rn[2.1] == BIP[1.3]
#     end

#     conv = first(values(PowerImpedanceACDC.result["solution"]["convdc"]))
#     bus = first(values(PowerImpedanceACDC.result["solution"]["bus"]))
#     return conv, bus
# end

# function solved_bipolar_pf_from_solution(conv, bus, vac_ln_rms_base)
#     pgrid = _pole_value(conv["pgrid"], "p") + _pole_value(conv["pgrid"], "n")
#     qgrid = _pole_value(conv["qgrid"], "p") + _pole_value(conv["qgrid"], "n")

#     return (
#         Vac_LL_RMS = bus["vm"] * vac_ln_rms_base * sqrt(3),
#         Pac_terminal = -pgrid * POWERFLOW_BASE_MVA,
#         Qac_terminal = qgrid * POWERFLOW_BASE_MVA,
#         θac = bus["va"],
#     )
# end