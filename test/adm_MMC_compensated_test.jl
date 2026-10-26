using PowerImpedance, LinearAlgebra, Test
using DelimitedFiles: readdlm

function element_y(elem, system, s::Complex)
    A, B, C, D = system.A, system.B, system.C, system.D
    n = size(A, 1)
    Iₙ = Matrix{ComplexF64}(I, n, n)
    Y = C * ((s * Iₙ - A) \ B) + D

    elec = elem.elec
    b = elem.bases
    iACbase = 2 * b.S / (3 * b.v_ac)
    iDCbase = b.S / b.v_dc

    Y = Matrix{ComplexF64}(Y)
    Y[1, :] .*= iDCbase
    Y[2:3, :] .*= iACbase * elec.turnsRatio

    Y[:, 1] ./= b.v_dc
    Y[:, 2:3] ./= b.v_ac

    return Y
end

function compensated_mmc_plot_convention(Y::AbstractMatrix)
    return [transpose(Y[1, :]); transpose(Y[2, :]); transpose(Y[3, :])]
end

function compensated_mmc_blocks(; Pmmc, Qmmc, Vm, Vdc)
    elec = PowerImpedance.ElectricalMMC(
        turnsRatio = 320 / 400,
        Lᵣ = 0.18 * (320^2 / 1060) / (2π * 50),
        Rᵣ = 0.001 * (320^2 / 1060),
        Rₐᵣₘ = 0.4,
        Lₐᵣₘ = 46.125e-3,
        Cₐᵣₘ = 11.3867e-3,
        N = 400
    )

    meas = PowerImpedance.Measurement(
        P_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
        Q_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π)
    )

    pll = PowerImpedance.PLLSynchronization(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.28,
            Ki = 12.5664
        ),
        filter = PowerImpedance.Butterworth(order = 1, ωc = 75 * 2π)
    )

    synch = PowerImpedance.VSEWithDamping(
        H = 5.0,
        K_d = 100.0,
        K_ω = 10.0,
        pll = pll
    )

    outerReactive = PowerImpedance.OuterReactiveQControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 30.0),
    )

    innerVoltage = PowerImpedance.CCVI(
        R_v = 0.01,
        L_v = 0.25,
        V_d_ref = 1.0,
        V_q_ref = 0.0,
        filter = PowerImpedance.Butterworth(order = 2, ωc = 200.0)
    )

    innerCurrent = PowerImpedance.InnerCurrentPIControl(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.6787,
            Ki = 292.2087
        ),
        filter = PowerImpedance.Butterworth(order = 1, ωc = 0.0001 * 2π)
    )

    delta_control = PowerImpedance.ΔdqControlGFM(
        outer_reactive = outerReactive,
        vi = innerVoltage,
        occ = innerCurrent
    )

    wsigma = PowerImpedance.ΣEnergyControl(
        pi_control = PowerImpedance.PIControl(Kp = 0.4*1.386, Ki = 0.2*29.70),
    )

    wdelta = PowerImpedance.ΔEnergyControl(
        pi_control = PowerImpedance.PIControl(Kp = 0.4*1.386, Ki = 0.2*29.70),
    )

    ccc = PowerImpedance.CirculatingCurrentControl(
        PowerImpedance.PIControl(Kp = 0.0992, Ki = 42.9719),
    )

    sigma_control = PowerImpedance.ΣdqzControlLEC(
        wsigma = wsigma,
        wdelta = wdelta,
        ccc = ccc
    )

    mod = PowerImpedance.CompensatedModulation(
        timeDelay = 200e-6,
        padeOrderNum = 5,
        padeOrderDen = 5
    )

    limits = PowerImpedance.Limits(
        P_min = -1500.0,
        P_max = 1500.0,
        Q_min = -1000.0,
        Q_max = 1000.0
    )

    return elec, meas, synch, delta_control, sigma_control, mod, limits
end

function build_compensated_mmc_grid()
    Pmmc = 0.7 * 1060
    Qmmc = 0.0
    Vm = 400 / sqrt(3)
    Vdc = 640.0

    elec, meas, synch, delta_control, sigma_control,
    mod, limits = compensated_mmc_blocks(; Pmmc, Qmmc, Vm, Vdc)

    dut = PowerImpedance.mmc(vDC_base = 640.0, Sbase = 1060.0, vACbase_LL_RMS = 320.0,
        elec = elec, meas = meas, sync = synch, delta_control = delta_control,
        sigma_control = sigma_control, modulation = mod, limits = limits)

    b = bases(dut)
    dut = component(dut; sync = (p_ref = Pmmc / b.S,),
        delta_control = (outer_reactive = (q_ref = Qmmc / b.S,),),
        powerflow = (v_ac = Vm * sqrt(2) / b.v_ac,
            p_dc = Pmmc / b.S, v_dc = Vdc / b.v_dc))

    voltage = b.v_ac / elec.turnsRatio
    magnitude = (voltage * sqrt(3 / 2))^2 / b.S / 8
    resistance = magnitude / sqrt(101)
    inductance = 10resistance / (2π * 50)
    elements = (; DUT = dut, G3 = ac_source(v = voltage),
        Grid = impedance(z = s -> resistance + inductance * s, conductors = 3),
        G_DC = dc_source(v = Vdc))
    topology = (
        NetworkBuilder.Bus(:AC; ports = ((:DUT, :ac), (:Grid, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Grid; ports = ((:Grid, :side2), (:G3, :ac)), domain = ACDQ),
        NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc), (:G_DC, :dc))))
    grid = NetworkBuilder.define(elements, topology;
        options = (; voltageBase = voltage / sqrt(2)))
    result = compute(PowerFlowProblem(grid), ACDCPowerFlow())
    return grid, result.operating_point
end

# The test compares AC terminal admittance with the DC voltage held fixed.
@testset "Unit tests for MMC with compensated modulation" begin
    data = readdlm(joinpath(@__DIR__, "data", "mmc_compensated_pscad_export.tsv"),
        '\t', Float64; comments = true)
    omegas = 2π .* data[:, 1]
    Y_validation = [reshape(complex.(row[2:2:end], row[3:2:end]), 2, 2)
                    for row in eachrow(data)]
    grid, point = build_compensated_mmc_grid()
    elem = grid.elements[:DUT]
    system = linearize(elem, point[:DUT]).system
    @test all(pole -> real(pole) < 0, eigvals(system.A))

    Y_MMC = Matrix{ComplexF64}[]
    for ω in omegas
        Y1 = element_y(elem, system, 1im * ω)
        push!(Y_MMC, compensated_mmc_plot_convention(Y1)[2:3, 2:3])
    end

    for k in eachindex(omegas)
        for c in 1:2, r in 1:2

            @test abs(Y_MMC[k][c, r])≈abs(Y_validation[k][c, r]) atol=1e-4 rtol=1e-2
            @test Y_MMC[k][c, r]≈Y_validation[k][c, r] atol=1e-4 rtol=1e-2
        end
    end
end
#### Plotting results if needed
# ##
# using ColorSchemes
# set_theme!(theme_latexfonts())
# update_theme!(palette = (color = ColorSchemes.tol_bright.colors,))
# update_theme!(Theme( Axis = (topspinevisible = false, rightspinevisible = false)))

# ##
# fig = Figure(size=(1000, 600))

# for c ∈ 1:3
#     for r ∈ 1:3

#         if c == 1 && r == 3
#             vlines!(ax, [415.0], color=:black, linestyle=:dash)
#             # Annotate the resonance frequency
#         end
#         if c ∈ 2:3 && r == 1
#             vlines!(ax, [50], color=:black, linestyle=:dash)
#             # Annotate the resonance frequency

#         end
#         if r == 1
#             ax.ylabel = "Magnitude"
#         end
#         if c == 3
#             ax.xlabel = "Frequency (Hz)"
#             ax.xticklabelsvisible = true
#         end
#         if c == 3 && r == 3
#             axislegend(ax, position = :lb)
#         end
#     end
# end
# display(fig)
# ##
# fig = Figure(size=(1000, 600))
# for c ∈ 1:3
#     for r ∈ 1:3
#         hlines!(ax, [1e-4], color=:red, linestyle=:dash, label="Tolerance")

#         if r == 1
#             ax.ylabel = "Magnitude"
#         end
#         if c == 3
#             ax.xlabel = "Frequency (Hz)"
#             ax.xticklabelsvisible = true
#         end
#         if c == 3 && r == 3
#             axislegend(ax, position = :lb)
#         end
#     end
# end
# display(fig)

# ##
# fig = Figure(size=(1000, 600))

# for c ∈ 1:3
#     for r ∈ 1:3
#         ax = Axis(fig[c, r], title="Y[$c, $r]", xscale=log10, xticklabelsvisible = false)

#         if c == 1 && r == 3
#             vlines!(ax, [415.0], color=:black, linestyle=:dash)
#         end
#         if c ∈ 2:3 && r == 1
#             vlines!(ax, [50], color=:black, linestyle=:dash)
#         end
#         if r == 1
#             ax.ylabel = "Angle (°)"
#         end
#         if c == 3
#             ax.xlabel = "Frequency (Hz)"
#             ax.xticklabelsvisible = true
#         end
#         if c == 3 && r == 3
#             axislegend(ax, position = :lb)
#         end
#     end
# end
# display(fig)
# ##
# fig = Figure(size=(1000, 600))
# for c ∈ 1:3
#     for r ∈ 1:3
#         ax = Axis(fig[c, r], title="Y[$c, $r]", xscale=log10, xticklabelsvisible = false)
#         hlines!(ax, [7], color=:red, linestyle=:dash, label="Tolerance")

#         if c == 1 && r == 3
#             vlines!(ax, [415.0], color=:black, linestyle=:dash)
#         end
#         if c ∈ 2:3 && r == 1
#             vlines!(ax, [50], color=:black, linestyle=:dash)
#         end
#         if r == 1
#             ax.ylabel = "Angle Error (°)"
#         end
#         if c == 3
#             ax.xlabel = "Frequency (Hz)"
#             ax.xticklabelsvisible = true
#         end
#         if c == 3 && r == 3
#             axislegend(ax, position = :lb)
#         end
#     end
# end
# display(fig)
