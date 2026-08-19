# # P2P HVDC parametric OHL/UGC transition
#
# This example demonstrates the `NetworkBuilder` workflow for reusing a cached
# power-flow solution while sweeping the relative share of overhead line and
# underground cable in a point-to-point HVDC system.

using PowerImpedance
import Plots

# The P and Q defined here are what is injected into the network.
transmissionVoltage = 380 / sqrt(3)
pHVDC1 = 100
qC1 = 100
qC2 = 100

rho = 100.0
L = 100e3

connections = (
    (node = :B3d, element = :tl1, side = 2, terminal = 1),
    (node = :B3d, element = :c1, side = 2, terminal = 1),
    (node = :B3q, element = :tl1, side = 2, terminal = 2),
    (node = :B3q, element = :c1, side = 2, terminal = 2),
    (node = :B2d, element = :g4, side = 1, terminal = 1),
    (node = :B2d, element = :tl1, side = 1, terminal = 1),
    (node = :B2q, element = :g4, side = 1, terminal = 2),
    (node = :B2q, element = :tl1, side = 1, terminal = 2),
    (node = :B4, element = :ugc, side = 1, terminal = 1),
    (node = :B4, element = :c1, side = 1, terminal = 1),
    (node = :BX, element = :ugc, side = 2, terminal = 1),
    (node = :BX, element = :ohl, side = 1, terminal = 1),
    (node = :B5, element = :ohl, side = 2, terminal = 1),
    (node = :B5, element = :c2, side = 1, terminal = 1),
    (node = :B6d, element = :tl78, side = 1, terminal = 1),
    (node = :B6d, element = :c2, side = 2, terminal = 1),
    (node = :B6q, element = :tl78, side = 1, terminal = 2),
    (node = :B6q, element = :c2, side = 2, terminal = 2),
    (node = :B7d, element = :g1, side = 1, terminal = 1),
    (node = :B7d, element = :tl78, side = 2, terminal = 1),
    (node = :B7q, element = :g1, side = 1, terminal = 2),
    (node = :B7q, element = :tl78, side = 2, terminal = 2)
)

# Pro-tip: define bounded quantities directly from the top-level API, rather than hacking through the build_acdcpf options.
builder_options = (;
    voltageBase = transmissionVoltage,
    power_flow = (;
        is_bounded = (;
        bus_voltage = true,
    ),
    )
)

# Wrap the network components into a function that can be called with different values of `x` to sweep the OHL/UGC transition, returning a tuple of elements:
function ohl_to_ugc(x)
    ohl_model = overhead_line(
        length = L * (1 - (x + 1e-3)),
        conductors = Conductors(
            organization = :flat,
            nᵇ = 2,
            nˢᵇ = 1,
            Rᵈᶜ = 0.0266, rᶜ = 44.8e-3 / 2,
            yᵇᶜ = 18.0, Δyᵇᶜ = 0.0, Δxᵇᶜ = 7.3, Δ̃xᵇᶜ = 0.0,
            dˢᵇ = 0.0,
            dˢᵃᵍ = 6.0
        ),
        groundwires = Groundwires(
            nᵍ = 2,
            Rᵍᵈᶜ = 0.92, rᵍ = 0.0062,
            Δxᵍ = 7.3, Δyᵍ = 7.0, dᵍˢᵃᵍ = 6.0
        ), earth_parameters = (1, 1, rho),
        transformation = true
    )

    ugc_model = cable(
        length = L * (x + 1e-3),
        positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
        I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
        C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
        I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
        C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
        I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
        earth_parameters = (1, 1, rho),
        transformation = true
    )

    return (;
        g1 = ac_source(
            V = transmissionVoltage,
            P = pHVDC1,
            P_min = -2000,
            P_max = 2000,
            Q_max = 1000,
            Q_min = -1000,
            pins = 3,
            transformation = true
        ),

        c1 = only(NetworkBuilder.mmc(Vᵈᶜ = 640, vDCbase = 640, Vₘ = transmissionVoltage,
            P_max = 1500, P_min = -1500, P = -pHVDC1, Q = qC1, Q_max = 500,
            Q_min = -500,
            occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
            ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
            pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
            q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
            dc = PI_control(Kₚ = 6, Kᵢ = 15), timeDelay = 200e-6, padeOrderNum = 5,
            padeOrderDen = 5
        )),

        c2 = only(NetworkBuilder.mmc(Vᵈᶜ = 640, vDCbase = 640, Vₘ = transmissionVoltage,
            P_max = 1000, P_min = -1000, P = pHVDC1, Q = qC2, Q_max = 1000,
            Q_min = -1000,
            vACbase_LL_RMS = 333, turnsRatio = 333 / 380, Lᵣ = 0.0461, Rᵣ = 0.4103,
            Lₐᵣₘ = 30e-3,
            occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
            ccc = PI_control(Kₚ = 1 * 0.1048, Kᵢ = 1 * 48.1914),
            pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
            p = PI_control(Kₚ = 1 * 0.1, Kᵢ = 31.4159),
            q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159), timeDelay = 200e-6,
            padeOrderNum = 5, padeOrderDen = 5
        )),

        ugc = ugc_model,
        ohl = ohl_model,

        g4 = ac_source(
            V = transmissionVoltage,
            P = pHVDC1,
            P_min = -2000,
            P_max = 2000,
            Q_max = 1000,
            Q_min = -1000,
            pins = 3,
            transformation = true
        ),

        tl1 = overhead_line(length = 25e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1,
                Rᵈᶜ = 0.063,
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
            earth_parameters = (1, 1, 100), transformation = true),

        tl78 = overhead_line(length = 90e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1,
                Rᵈᶜ = 0.063,
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
            earth_parameters = (1, 1, 100), transformation = true)
    )
end

# Some plots and eye-candy:
function transition_bode_sample(x, zgrid, omega_ac)
    Zg = vec(zgrid[1, 1, :])

    f = real.(omega_ac ./ (2π))
    mag_dB = 20 .* log10.(abs.(Zg))
    phase_deg = angle.(Zg) .* (180 / π)

    return (;
        x = x,
        f = f,
        mag_dB = mag_dB,
        phase_deg = phase_deg
    )
end

function padded_limits(values; padding = 0.08)
    finite_values = values[isfinite.(values)]

    isempty(finite_values) &&
        error("Cannot determine plot limits from non-finite values.")

    vmin = minimum(finite_values)
    vmax = maximum(finite_values)

    if vmin == vmax
        delta = max(abs(vmin), 1.0)
        return (vmin - delta, vmax + delta)
    end

    delta = padding * (vmax - vmin)
    return (vmin - delta, vmax + delta)
end

function transition_bode_frame(sample; mag_ylims, phase_ylims = (-180, 180))
    label = "Z @B5, UGC = $(round(sample.x * 100; digits = 2)) %"

    plt = Plots.plot(
        layout = (2, 1),
        size = (950, 700),
        legend = :topright
    )

    Plots.plot!(
        plt[1],
        sample.f,
        sample.mag_dB;
        xaxis = :log10,
        ylabel = "Magnitude [dB]",
        label = label,
        linewidth = 2,
        minorgrid = true,
        framestyle = :box,
        xlims = (minimum(sample.f), maximum(sample.f)),
        ylims = mag_ylims,
        title = "Impedance seen at B5 during UGC/OHL transition"
    )

    Plots.plot!(
        plt[2],
        sample.f,
        sample.phase_deg;
        xaxis = :log10,
        xlabel = "Frequency [Hz]",
        ylabel = "Phase [deg]",
        label = "",
        legend = :none,
        linewidth = 2,
        minorgrid = true,
        framestyle = :box,
        xlims = (minimum(sample.f), maximum(sample.f)),
        ylims = phase_ylims,
        yticks = -360:90:360
    )

    return plt
end

function save_transition_animation(
        samples;
        filename = "transition_harmonic_peaks.mp4",
        fps = 8
)
    isempty(samples) && error("No transition samples were generated.")

    all_mag = reduce(vcat, (sample.mag_dB for sample in samples))
    mag_ylims = padded_limits(all_mag)

    anim = Plots.Animation()

    for sample in samples
        plt = transition_bode_frame(sample; mag_ylims = mag_ylims)
        Plots.frame(anim, plt)
    end

    Plots.mp4(anim, filename; fps = fps)
    return filename
end

# Welcome to the new world order:
function run_transition_study(;
        x_values = 0.0:0.02:1.0,
        animation_filename = "transition_harmonic_peaks.mp4",
        animation_fps = 8,
        show_static_plots = false
)
    builder = nothing
    cached_powerflow = nothing
    samples = NamedTuple[]

    for x in x_values
        elements = ohl_to_ugc(x)

        if builder === nothing
            @time begin
                builder = NetworkBuilder.define(elements, connections; options = builder_options)
                solved = NetworkBuilder.solve(builder)
                cached_powerflow = solved.powerflow
            end

            cached_powerflow === nothing &&
                error("Expected power-flow results from an active network.")
        else
            @time NetworkBuilder.update!(
                builder;
                elements = elements,
                operating_point = cached_powerflow.operating_point
            )
        end

        @time zgrid, omega_ac = NetworkBuilder.determine_impedance(
            builder;
            elim_elements = [:c2],
            nets = [:B5],
            freq_range = (100, 5000, 1000)
        )

        sample = transition_bode_sample(x, zgrid, omega_ac)
        push!(samples, sample)

        if show_static_plots
            Zg = vec(zgrid[1, 1, :])
            display(
                bodeplot(
                Zg,
                omega_ac;
                legend = "Z @B5, UGC=$(round(x * 100; digits = 2)) %"
            ),
            )
        end
    end

    save_transition_animation(
        samples;
        filename = animation_filename,
        fps = animation_fps
    )

    return samples
end

# This runs locally, but we are not creating MP4 animations inside a CI pipeline, innit?
if abspath(PROGRAM_FILE) == @__FILE__
    @time samples = run_transition_study(
        x_values = 0.0:0.02:1.0,
        animation_filename = "transition_harmonic_peaks.mp4",
        animation_fps = 8
    )
end
