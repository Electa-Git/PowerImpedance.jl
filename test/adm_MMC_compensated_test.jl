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
    return [transpose(Y[1, :]); transpose(Y[2, :]); transpose(Y[3, :])]
end


function common_mmc_blocks(; Pmmc, Qmmc, Vm, Vdc)
    elec = PowerImpedance.ElectricalMMC(
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

    meas = PowerImpedance.Measurement(
        P_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
        Q_ac = PowerImpedance.Butterworth(order = 2, ωc = 140 * 2π),
    )

    pll = PowerImpedance.PLLSynchronization(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.28,
            Ki = 12.5664,
        ),
        filter = PowerImpedance.Butterworth(order = 1, ωc = 75 * 2π),
    )

    synch = PowerImpedance.VSEWithDamping(
        H = 5.0,
        K_d = 100.0,
        K_ω = 10.0,
        pll = pll,
    )

    outerReactive = PowerImpedance.OuterReactiveQControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 30.0),
    )

    innerVoltage = PowerImpedance.CCVI(
        R_v = 0.01,
        L_v = 0.25,
        V_d_ref = 1.0,
        V_q_ref = 0.0,
        filter = PowerImpedance.Butterworth(order = 2, ωc = 200.0),
    )

    innerCurrent = PowerImpedance.InnerCurrentPIControl(
        pi_ctrl = PowerImpedance.PIControl(
            Kp = 0.6787,
            Ki = 292.2087,
        ),
        filter = PowerImpedance.Butterworth(order = 1, ωc = 0.0001 * 2π),
    )

    delta_control = PowerImpedance.ΔdqControlGFM(
        outer_reactive = outerReactive,
        vi = innerVoltage,
        occ = innerCurrent,
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
        ccc = ccc,
    )

    mod = PowerImpedance.CompensatedModulation(
        timeDelay = 200e-6,
        padeOrderNum = 5,
        padeOrderDen = 5,
    )

    setpoint = PowerImpedance.Setpoint(
        Pac = Pmmc,
        Qac = Qmmc,
        θac = 0.0,
        Vac = Vm * sqrt(2),
        Pdc = Pmmc,
        Vdc = Vdc,
    )

    limits = PowerImpedance.Limits(
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

    dut = PowerImpedance.mmc(
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

        G3 = ac_source(pins = 3, setpoint = Setpoint(Vac = Vm), transformation = true)
        G_DC = dc_source(pins = 1, setpoint = Setpoint(Vdc = Vdc / 2))

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

# Validation of GFM-CCVI with CM
@testset "Unit tests for MMC with compensated modulation" begin
    omegas, Y_validation = read_validation_data(joinpath(@__DIR__, "data", "data_MMC_CM_validation.txt"))
    grid = build_mmc_grid()
    elem = grid.elements[:DUT]

    Y_MMC = Matrix{ComplexF64}[]
    for ω in omegas
        Y1 = element_y(elem, 1im * ω)
        push!(Y_MMC, mmc_plot_convention(Y1))
    end

    for k in eachindex(omegas)
        for c in 1:3, r in 1:3
            @test abs(Y_MMC[k][c, r]) ≈ abs(Y_validation[k][c, r]) atol = 1e-4 rtol = 1e-2
            @test Y_MMC[k][c, r] ≈ Y_validation[k][c, r] atol = 1e-4 rtol = 1e-2
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
#         ax = Axis(fig[c, r], title="Y[$c, $r]", xscale=log10, yscale=log10, xticklabelsvisible = false)

#         lines!(ax, omegas/(2pi), abs.(getindex.(Y_MMC, c, r)), color=Cycled(2), linewidth=2, label="PIACDC")
#         scatter!(ax, omegas/(2pi), abs.(getindex.(Y_validation, c, r)), markersize=6, label="PSCAD")

#         if c == 1 && r == 3
#             vlines!(ax, [415.0], color=:black, linestyle=:dash)
#             # Annotate the resonance frequency
#             text!(ax, "415 Hz", position = (450.0, 1e-3), align = (:left, :bottom), color=:black, fontsize=18)
#         end
#         if c ∈ 2:3 && r == 1
#             vlines!(ax, [50], color=:black, linestyle=:dash)
#             # Annotate the resonance frequency
#             text!(ax, "50 Hz", position = (60, 1e-6), align = (:left, :bottom), color=:black, fontsize=18)
            
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
#         ax = Axis(fig[c, r], title="Y[$c, $r]", xscale=log10, yscale=log10, xticklabelsvisible = false)
#         scatterlines!(ax, omegas/(2pi), abs.(abs.(getindex.(Y_MMC, c, r)) - abs.(getindex.(Y_validation, c, r))), linewidth=2, markersize=6, color=:tomato, label="Error")
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

#         lines!(ax, omegas/(2pi), rad2deg.(angle.(getindex.(Y_MMC, c, r))), color=Cycled(2), linewidth=2, label="PIACDC")
#         scatter!(ax, omegas/(2pi), rad2deg.(angle.(getindex.(Y_validation, c, r))), markersize=6, label="PSCAD")

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
#         diff = abs.(rad2deg.(angle.(getindex.(Y_MMC, c, r))) - rad2deg.(angle.(getindex.(Y_validation, c, r))))
#         scatterlines!(ax, omegas/(2pi), min.(diff, 360 .- diff), linewidth=2, markersize=6, color=:tomato, label="Error")
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
