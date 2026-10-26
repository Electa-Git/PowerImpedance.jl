# # P2P HVDC parametric OHL/UGC transition
#
# This `NetworkBuilder` study reuses a cached power-flow solution across
# overhead-line and underground-cable shares in a point-to-point HVDC system.

using PowerImpedance
using CairoMakie
using PowerImpedance.NetworkBuilder: Grid, Gridspace, NetworkState

# P and Q are active and reactive power injected into the network.
transmissionVoltage = 380 / sqrt(3)
pHVDC1 = 100
qC1 = 100
qC2 = 100

rho = 100.0
L = 100e3

connections = (
    NetworkBuilder.Bus(:B3; ports = ((:tl1, :side2), (:c1, :ac)), domain = ACDQ),
    NetworkBuilder.Bus(:B2; ports = ((:g4, :ac), (:tl1, :side1)), domain = ACDQ),
    NetworkBuilder.Bus(:B4; ports = ((:ugc, :side1), (:c1, :dc))),
    NetworkBuilder.Bus(:BX; ports = ((:ugc, :side2), (:ohl, :side1))),
    NetworkBuilder.Bus(:B5; ports = ((:ohl, :side2), (:c2, :dc))),
    NetworkBuilder.Bus(:B6; ports = ((:tl78, :side1), (:c2, :ac)), domain = ACDQ),
    NetworkBuilder.Bus(:B7; ports = ((:g1, :ac), (:tl78, :side2)), domain = ACDQ)
)

# Bus-voltage bounds belong in the builder options used for every case.
builder_options = (;
    voltageBase = transmissionVoltage,
    power_flow = (;
        is_bounded = (;
        bus_voltage = true,
    ),
    )
)

# `x` is the fraction of the corridor implemented as underground cable. A 100 m
# regularization at either endpoint avoids singular zero-length line models.
function ohl_to_ugc(x)
    share = clamp(x, 1e-3, 1 - 1e-3)
    ohl_model = overhead_line(;
        length = L * (1 - share),
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
        ), earth_parameters = (1, 1, rho))
    ugc_model = cable(;
        length = L * share,
        positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
        I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
        C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
        I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
        C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
        I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
        earth_parameters = (1, 1, rho))

    return (;
        g1 = ac_source(v = transmissionVoltage*sqrt(2), p = pHVDC1),
        c1 = let model = only(mmc(Grid;
                Sbase = 1000.0, vDC_base = 640.0, vACbase_LL_RMS = 380.0,
                elec = ElectricalMMC(turnsRatio = 1.0),
                limits = PowerImpedance.Limits(P_min = -1500.0, P_max = 1500.0,
                    Q_min = -500.0, Q_max = 500.0),
                sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664)),
                delta_control = ΔdqControlGFL(
                    outer_active = OuterActiveVdcControl(
                        pi_ctrl = PIControl(Kp = 6.0, Ki = 15.0)),
                    outer_reactive = OuterReactiveQControl(
                        pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
                    occ = InnerCurrentPIControl(
                        pi_ctrl = PIControl(Kp = 0.7691, Ki = 522.7654),
                        activate_ω_c_multiplication = false)),
                sigma_control = ΣdqzControlTEC(
                    ccsc = CirculatingCurrentSuppressionControl(
                        PIControl(Kp = 0.1048, Ki = 48.1914))),
                modulation = UncompensatedModulation(timeDelay = 200e-6,
                    padeOrderNum = 5, padeOrderDen = 5)))
            b = bases(model)
            component(model;
                delta_control = (outer_active = (v_dc_ref = 640.0 / b.v_dc,),
                    outer_reactive = (q_ref = qC1 / b.S,)),
                powerflow = (; p_ac = -pHVDC1 / b.S,
                    v_ac = (transmissionVoltage * sqrt(2)) / b.v_ac,
                    p_dc = 0.0 / b.S))
        end,
        c2 = let model = only(mmc(Grid;
                Sbase = 1000.0, vDC_base = 640.0, vACbase_LL_RMS = 333.0,
                elec = ElectricalMMC(turnsRatio = 333 / 380, Lᵣ = 0.0461, Rᵣ = 0.4103,
                    Lₐᵣₘ = 30e-3),
                limits = PowerImpedance.Limits(P_min = -1000.0, P_max = 1000.0,
                    Q_min = -1000.0, Q_max = 1000.0),
                sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.28, Ki = 12.5664)),
                delta_control = ΔdqControlGFL(
                    outer_active = OuterActivePowerControl(
                        pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
                    outer_reactive = OuterReactiveQControl(
                        pi_ctrl = PIControl(Kp = 0.1, Ki = 31.4159)),
                    occ = InnerCurrentPIControl(
                        pi_ctrl = PIControl(Kp = 0.7691, Ki = 522.7654),
                        activate_ω_c_multiplication = false)),
                sigma_control = ΣdqzControlTEC(
                    ccsc = CirculatingCurrentSuppressionControl(
                        PIControl(Kp = 0.1048, Ki = 48.1914))),
                modulation = UncompensatedModulation(timeDelay = 200e-6,
                    padeOrderNum = 5, padeOrderDen = 5)))
            b = bases(model)
            component(model;
                delta_control = (outer_active = (p_ref = pHVDC1 / b.S,),
                    outer_reactive = (q_ref = qC2 / b.S,)),
                powerflow = (; v_dc = 640.0 / b.v_dc,
                    v_ac = (transmissionVoltage * sqrt(2)) / b.v_ac,
                    p_dc = 0.0 / b.S))
        end,

        ugc = ugc_model,
        ohl = ohl_model,

        g4 = ac_source(v = transmissionVoltage*sqrt(2), p = pHVDC1),
        tl1 = overhead_line(; length = 25e3,
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
            earth_parameters = (1, 1, 100)),
        tl78 = overhead_line(; length = 90e3,
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
            earth_parameters = (1, 1, 100))
    )
end

# One deterministic Gridspace axis pairs OHL and UGC lengths at each corridor share.
function transition_network_space(x_values)
    shares = Grid(collect(x_values))
    return Gridspace{NetworkState}(
        share -> NetworkBuilder.define(
            ohl_to_ugc(share),
            connections;
            options = builder_options
        ),
        (shares,),
        (:ugc_share,)
    )
end

function transition_peak(response, share)
    magnitude_db = 20 .* log10.(abs.(vec(response.response[1, 1, :])))
    frequencies_hz = real.(response.frequencies) ./ (2π)
    peak_index = argmax(magnitude_db)
    return (;
        ugc_share = share,
        peak_magnitude_db = magnitude_db[peak_index],
        peak_frequency_hz = frequencies_hz[peak_index]
    )
end

function save_transition_animation(study; filename = "transition_harmonic_peaks.mp4",
    fps = 8)
    panel = only(study.plot.panels)
    groups = panel.group_order
    CairoMakie.record(study.plot.figure, filename,
        eachindex(groups); framerate = fps) do frame
        for (index, group) in pairs(groups)
            foreach(plot -> plot.visible[] = index == frame, panel.groups[group])
        end
    end
    foreach(group -> foreach(plot -> plot.visible[] = true, panel.groups[group]), groups)
    return filename
end

function run_transition_study(;
        x_values = 0.0:0.02:1.0,
        frequency_range = (100.0, 5e3, 1000),
        animation_filename = nothing,
        animation_fps = 8,
        display_plot = false
)
    shares = collect(x_values)
    problems = PowerImpedanceProblem(
        transition_network_space(shares);
        nodes = [:B5],
        eliminated_elements = [:c2],
        frequency_range
    )
    result = compute(
        ParametricProblem(problems),
        Combinatorial(NodalImpedance())
    )
    labels = ["UGC = $(round(100share; digits=1))%" for share in shares]
    groups = [Symbol("ugc_", replace(string(round(100share; digits = 1)), "." => "_"))
              for share in shares]
    plot = only(PowerImpedance.plot(
        result;
        entries = (:B5, :B5),
        labels,
        series_groups = groups,
        title = "Impedance at B5 during the OHL/UGC transition",
        figure_size = (950, 700),
        display_plot,
        controls = false
    ))
    peaks = [transition_peak(response, share)
             for (response, share) in zip(result.values, shares)]
    study = (; result, plot, peaks)
    animation_filename === nothing || save_transition_animation(
        study;
        filename = animation_filename,
        fps = animation_fps
    )
    return study
end

# The documentation uses five corridor shares and a reduced frequency grid.
#md transition_docs = run_transition_study(; x_values=0.0:0.25:1.0, frequency_range=(100.0,
#md     5e3, 160))
#md transition_docs.plot.figure
#
# The peak table records the resonance movement seen in the plotted curves.
#md transition_docs.peaks

if abspath(PROGRAM_FILE) == @__FILE__ #src
    study = run_transition_study(; #src
        animation_filename = "transition_harmonic_peaks.mp4") #src
    display(study.plot.figure) #src
    println(study.peaks) #src
end #src
