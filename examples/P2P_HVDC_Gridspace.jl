# # P2P HVDC studies with Gridspace
#
# This tutorial constructs three studies directly from `Grid` objects:
#
# 1. the deterministic OHL/UGC length transition;
# 2. bounded uncertainty on every nonzero cable geometry dimension; and
# 3. bounded uncertainty on physically meaningful MMC parameters.
#
# There is one Monte Carlo loop: `determine_impedance` samples every uncertain
# axis together. It reuses the operating point and active-device linearization
# while only passive parameters change, and invalidates that cache when a
# sampled converter or the topology changes.

using Measurements
using Plots
using PowerImpedanceACDC
using PowerImpedanceACDC.NetworkBuilder: @gridspace, pin, ⟷
using Statistics

const NB = PowerImpedanceACDC.NetworkBuilder;

# ## Fixed network data

const transmission_voltage = 380 / sqrt(3)
const p_hvdc = 100.0
const q_c1 = 100.0
const q_c2 = 100.0
const soil_resistivity = 100.0
const corridor_length = 100e3;

const connections = (
    pin(:tl1, 2.1) ⟷ pin(:c1, 2.1) ⟷ :B3d,
    pin(:tl1, 2.2) ⟷ pin(:c1, 2.2) ⟷ :B3q,
    pin(:g4, 1.1) ⟷ pin(:tl1, 1.1) ⟷ :B2d,
    pin(:g4, 1.2) ⟷ pin(:tl1, 1.2) ⟷ :B2q,
    pin(:g4, 2.1) ⟷ :gndd,
    pin(:g4, 2.2) ⟷ :gndq,
    pin(:ugc, 1.1) ⟷ pin(:c1, 1.1) ⟷ :B4,
    pin(:ugc, 2.1) ⟷ pin(:ohl, 1.1) ⟷ :BX,
    pin(:ohl, 2.1) ⟷ pin(:c2, 1.1) ⟷ :B5,
    pin(:tl78, 1.1) ⟷ pin(:c2, 2.1) ⟷ :B6d,
    pin(:tl78, 1.2) ⟷ pin(:c2, 2.2) ⟷ :B6q,
    pin(:g1, 1.1) ⟷ pin(:tl78, 2.1) ⟷ :B7d,
    pin(:g1, 1.2) ⟷ pin(:tl78, 2.2) ⟷ :B7q,
    pin(:g1, 2.1) ⟷ :gndd,
    pin(:g1, 2.2) ⟷ :gndq
);

const builder_options = (;
    voltageBase = transmission_voltage,
    power_flow = (; is_bounded = (; bus_voltage = true))
);

# These elements do not change in the length or cable-geometry studies. The
# qualified constructors still return singleton Gridspaces; `only` makes the
# fixed scalar elements explicit.
const fixed_element_specs = (;
    g1 = NB.ac_source(
        V = transmission_voltage,
        P = p_hvdc,
        P_min = -2000,
        P_max = 2000,
        Q_min = -1000,
        Q_max = 1000,
        pins = 3,
        transformation = true
    ),
    c1 = NB.mmc(
        Vᵈᶜ = 640,
        vDCbase = 640,
        Vₘ = transmission_voltage,
        P = -p_hvdc,
        Q = q_c1,
        P_min = -1500,
        P_max = 1500,
        Q_min = -500,
        Q_max = 500,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
        dc = PI_control(Kₚ = 6.0, Kᵢ = 15.0),
        timeDelay = 200e-6,
        padeOrderNum = 5,
        padeOrderDen = 5
    ),
    c2 = NB.mmc(
        Vᵈᶜ = 640,
        vDCbase = 640,
        Vₘ = transmission_voltage,
        P = p_hvdc,
        Q = q_c2,
        P_min = -1000,
        P_max = 1000,
        Q_min = -1000,
        Q_max = 1000,
        vACbase_LL_RMS = 333,
        turnsRatio = 333 / 380,
        Lᵣ = 0.0461,
        Rᵣ = 0.4103,
        Lₐᵣₘ = 30e-3,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
        timeDelay = 200e-6,
        padeOrderNum = 5,
        padeOrderDen = 5
    ),
    g4 = NB.ac_source(
        V = transmission_voltage,
        P = p_hvdc,
        P_min = -2000,
        P_max = 2000,
        Q_min = -1000,
        Q_max = 1000,
        pins = 3,
        transformation = true
    ),
    tl1 = NB.overhead_line(
        length = 25e3,
        conductors = NB.Conductors(
            organization = :flat,
            nᵇ = 3,
            nˢᵇ = 1,
            Rᵈᶜ = 0.063,
            rᶜ = 0.015,
            yᵇᶜ = 30.0,
            Δyᵇᶜ = 0.0,
            Δxᵇᶜ = 10.0,
            Δ̃xᵇᶜ = 0.0,
            dˢᵇ = 0.0,
            dˢᵃᵍ = 10.0
        ),
        groundwires = NB.Groundwires(
            nᵍ = 2,
            Rᵍᵈᶜ = 0.92,
            rᵍ = 0.0062,
            Δxᵍ = 6.5,
            Δyᵍ = 7.5,
            dᵍˢᵃᵍ = 10.0
        ),
        earth_parameters = (1, 1, soil_resistivity),
        transformation = true
    ),
    tl78 = NB.overhead_line(
        length = 90e3,
        conductors = NB.Conductors(
            organization = :flat,
            nᵇ = 3,
            nˢᵇ = 1,
            Rᵈᶜ = 0.063,
            rᶜ = 0.015,
            yᵇᶜ = 30.0,
            Δyᵇᶜ = 0.0,
            Δxᵇᶜ = 10.0,
            Δ̃xᵇᶜ = 0.0,
            dˢᵇ = 0.0,
            dˢᵃᵍ = 10.0
        ),
        groundwires = NB.Groundwires(
            nᵍ = 2,
            Rᵍᵈᶜ = 0.92,
            rᵍ = 0.0062,
            Δxᵍ = 6.5,
            Δyᵍ = 7.5,
            dᵍˢᵃᵍ = 10.0
        ),
        earth_parameters = (1, 1, soil_resistivity),
        transformation = true
    )
);

const fixed_elements = map(only, fixed_element_specs);

const corridor_conductors = only(NB.Conductors(
    organization = :flat,
    nᵇ = 2,
    nˢᵇ = 1,
    Rᵈᶜ = 0.0266,
    rᶜ = 44.8e-3 / 2,
    yᵇᶜ = 18.0,
    Δyᵇᶜ = 0.0,
    Δxᵇᶜ = 7.3,
    Δ̃xᵇᶜ = 0.0,
    dˢᵇ = 0.0,
    dˢᵃᵍ = 6.0
));

const corridor_groundwires = only(NB.Groundwires(
    nᵍ = 2,
    Rᵍᵈᶜ = 0.92,
    rᵍ = 0.0062,
    Δxᵍ = 7.3,
    Δyᵍ = 7.0,
    dᵍˢᵃᵍ = 6.0
));

# Cable layer boundaries are generated from positive thicknesses. Independent
# perturbations therefore cannot invert or overlap adjacent layers.
@gridspace struct P2PCableGeometry
    spacing::Float64
    burial_depth::Float64
    core_radius::Float64
    insulation_1::Float64
    sheath::Float64
    insulation_2::Float64
    screen::Float64
    insulation_3::Float64
end;

const nominal_geometry = only(P2PCableGeometry(
    spacing = 1.0,
    burial_depth = 1.0,
    core_radius = 0.02622,
    insulation_1 = 0.06006 - 0.02622,
    sheath = 0.06336 - 0.06006,
    insulation_2 = 0.06636 - 0.06336,
    screen = 0.06651 - 0.06636,
    insulation_3 = 0.07256 - 0.06651
));

# ## Deterministic OHL/UGC transition
#
# One explicit `Grid` holds the paired lengths. Treating the OHL and UGC
# lengths as independent grids would create an unphysical Cartesian product.
# A 100 m endpoint regularization avoids the singular zero-length line model;
# the labels retain the requested 0% and 100% values.

const characteristic_shares = (0.0, 0.1, 0.5, 0.9, 1.0)
const endpoint_fraction = 1e-3
const corridor_lengths = NB.Grid(map(characteristic_shares) do share
    effective_share = clamp(share, endpoint_fraction, 1 - endpoint_fraction)
    (;
        share,
        ohl = corridor_length * (1 - effective_share),
        ugc = corridor_length * effective_share
    )
end);

transition_builders = NB.Gridspace{NB.BuilderState}(
    lengths -> begin
        r1 = nominal_geometry.core_radius
        r2 = r1 + nominal_geometry.insulation_1
        r3 = r2 + nominal_geometry.sheath
        r4 = r3 + nominal_geometry.insulation_2
        r5 = r4 + nominal_geometry.screen
        r6 = r5 + nominal_geometry.insulation_3

        affected_elements = (;
            ohl = only(NB.overhead_line(
                length = lengths.ohl,
                conductors = corridor_conductors,
                groundwires = corridor_groundwires,
                earth_parameters = (1, 1, soil_resistivity),
                transformation = true
            )),
            ugc = only(NB.cable(
                length = lengths.ugc,
                positions = [
                    (-nominal_geometry.spacing / 2, nominal_geometry.burial_depth),
                    (nominal_geometry.spacing / 2, nominal_geometry.burial_depth)
                ],
                C1 = Conductor(rₒ = r1, ρ = 2.354e-8, μᵣ = 1.035),
                I1 = Insulator(rᵢ = r1, rₒ = r2, ϵᵣ = 2.67, μᵣ = 1.469),
                C2 = Conductor(rᵢ = r2, rₒ = r3, ρ = 2.14e-7, μᵣ = 1.0),
                I2 = Insulator(rᵢ = r3, rₒ = r4, ϵᵣ = 2.3, μᵣ = 1.0),
                C3 = Conductor(rᵢ = r4, rₒ = r5, ρ = 2.826e-8, μᵣ = 1.0),
                I3 = Insulator(rᵢ = r5, rₒ = r6, ϵᵣ = 2.3, μᵣ = 1.0),
                earth_parameters = (1, 1, soil_resistivity),
                transformation = true
            ))
        )
        NB.define(merge(deepcopy(fixed_elements), affected_elements), connections;
            options = builder_options)
    end,
    (corridor_lengths,),
    (:corridor_lengths,)
);

transition = NB.determine_impedance(
    transition_builders;
    nets = [:B5],
    elim_elements = [:c2],
    freq_range = (100.0, 5e3, 400),
    seed = 2026
);

transition_plot = plot(
    xscale = :log10,
    xlabel = "Frequency [Hz]",
    ylabel = "|Z| [dBΩ]",
    title = "P2P OHL/UGC transition at B5",
    framestyle = :box,
    minorgrid = true
)
for (case, share) in zip(transition, characteristic_shares)
    frequency = real.(case.frequencies) ./ (2π)
    magnitude = 20 .* log10.(abs.(vec(case.impedance[1, 1, :])))
    plot!(transition_plot, frequency, magnitude;
        label = "UGC = $(round(Int, 100share))%", linewidth = 2)
end
transition_plot

# ## ±10% uncertainty on every cable geometry dimension
#
# `Grid(value, 10/sqrt(3))` describes a relative standard deviation. With a
# uniform distribution this is exactly a bounded ±10% interval. The axes below
# are the two cable positions, core radius, and all five positive layer
# thicknesses.

cable_geometry = P2PCableGeometry(
    spacing = NB.Grid(1.0, 10 / sqrt(3)),
    burial_depth = NB.Grid(1.0, 10 / sqrt(3)),
    core_radius = NB.Grid(0.02622, 10 / sqrt(3)),
    insulation_1 = NB.Grid(0.06006 - 0.02622, 10 / sqrt(3)),
    sheath = NB.Grid(0.06336 - 0.06006, 10 / sqrt(3)),
    insulation_2 = NB.Grid(0.06636 - 0.06336, 10 / sqrt(3)),
    screen = NB.Grid(0.06651 - 0.06636, 10 / sqrt(3)),
    insulation_3 = NB.Grid(0.07256 - 0.06651, 10 / sqrt(3))
);

cable_uq_builders = NB.Gridspace{NB.BuilderState}(
    (lengths, geometry) -> begin
        r1 = geometry.core_radius
        r2 = r1 + geometry.insulation_1
        r3 = r2 + geometry.sheath
        r4 = r3 + geometry.insulation_2
        r5 = r4 + geometry.screen
        r6 = r5 + geometry.insulation_3

        affected_elements = (;
            ohl = only(NB.overhead_line(
                length = lengths.ohl,
                conductors = corridor_conductors,
                groundwires = corridor_groundwires,
                earth_parameters = (1, 1, soil_resistivity),
                transformation = true
            )),
            ugc = only(NB.cable(
                length = lengths.ugc,
                positions = [
                    (-geometry.spacing / 2, geometry.burial_depth),
                    (geometry.spacing / 2, geometry.burial_depth)
                ],
                C1 = Conductor(rₒ = r1, ρ = 2.354e-8, μᵣ = 1.035),
                I1 = Insulator(rᵢ = r1, rₒ = r2, ϵᵣ = 2.67, μᵣ = 1.469),
                C2 = Conductor(rᵢ = r2, rₒ = r3, ρ = 2.14e-7, μᵣ = 1.0),
                I2 = Insulator(rᵢ = r3, rₒ = r4, ϵᵣ = 2.3, μᵣ = 1.0),
                C3 = Conductor(rᵢ = r4, rₒ = r5, ρ = 2.826e-8, μᵣ = 1.0),
                I3 = Insulator(rᵢ = r5, rₒ = r6, ϵᵣ = 2.3, μᵣ = 1.0),
                earth_parameters = (1, 1, soil_resistivity),
                transformation = true
            ))
        )
        NB.define(merge(deepcopy(fixed_elements), affected_elements), connections;
            options = builder_options)
    end,
    (corridor_lengths, cable_geometry),
    (:corridor_lengths, :cable_geometry)
);

cable_trials = 200 #src
#md cable_trials = 30
cable_uq = NB.determine_impedance(
    cable_uq_builders;
    nets = [:B5],
    elim_elements = [:c2],
    freq_range = (100.0, 5e3, 400),
    trials = cable_trials,
    distribution = :uniform,
    seed = 2027,
    return_samples = true
);

cable_panels = map(eachindex(characteristic_shares)) do index
    deterministic = transition[index]
    uncertain = cable_uq[index]
    frequency = real.(deterministic.frequencies) ./ (2π)
    deterministic_db = 20 .* log10.(abs.(vec(deterministic.impedance[1, 1, :])))
    samples_db = 20 .* log10.(abs.(uncertain.samples[1, 1, :, :]))
    mean_db = vec(mean(samples_db; dims = 2))
    q05_db = [quantile(view(samples_db, row, :), 0.05) for row in axes(samples_db, 1)]
    q95_db = [quantile(view(samples_db, row, :), 0.95) for row in axes(samples_db, 1)]

    panel = plot(frequency, deterministic_db;
        xscale = :log10, label = "nominal", linewidth = 2,
        xlabel = "Frequency [Hz]", ylabel = "|Z| [dBΩ]",
        title = "UGC = $(round(Int, 100characteristic_shares[index]))%",
        framestyle = :box, minorgrid = true)
    plot!(panel, frequency, mean_db;
        ribbon = (mean_db .- q05_db, q95_db .- mean_db),
        label = "±10% geometry: mean, 5–95%", linewidth = 2,
        linestyle = :dash, fillalpha = 0.18)
    panel
end

plot(cable_panels...;
    layout = (3, 2), size = (1100, 1100),
    plot_title = "P2P cable-geometry uncertainty at B5")

# ## Converter-parameter uncertainty
#
# This pass fixes the corridor at 50% UGC and samples both MMCs. Arm-reactor
# inductance and submodule capacitance use bounded ±5% manufacturing tolerances;
# equivalent arm resistance uses ±10% to cover conductor tolerance and operating
# temperature. These are defensible screening assumptions, not substitutes for
# project-specific procurement distributions.
#
# Unlike the passive study, every converter sample invalidates the active cache.
# The solver therefore repeats the power flow, converter equilibrium, and
# linearization inside the same Monte Carlo loop.

const half_corridor = corridor_lengths[3];

converter_uq_elements = merge(
    (;
        g1 = fixed_element_specs.g1,
        g4 = fixed_element_specs.g4,
        tl1 = fixed_element_specs.tl1,
        tl78 = fixed_element_specs.tl78
    ),
    (;
        c1 = NB.mmc(
            Vᵈᶜ = 640,
            vDCbase = 640,
            Vₘ = transmission_voltage,
            P = -p_hvdc,
            Q = q_c1,
            P_min = -1500,
            P_max = 1500,
            Q_min = -500,
            Q_max = 500,
            Lₐᵣₘ = NB.Grid(50e-3, 5 / sqrt(3)),
            Rₐᵣₘ = NB.Grid(1.07, 10 / sqrt(3)),
            Cₐᵣₘ = NB.Grid(10e-3, 5 / sqrt(3)),
            occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
            ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
            pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
            q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
            dc = PI_control(Kₚ = 6.0, Kᵢ = 15.0),
            timeDelay = 200e-6,
            padeOrderNum = 5,
            padeOrderDen = 5
        ),
        c2 = NB.mmc(
            Vᵈᶜ = 640,
            vDCbase = 640,
            Vₘ = transmission_voltage,
            P = p_hvdc,
            Q = q_c2,
            P_min = -1000,
            P_max = 1000,
            Q_min = -1000,
            Q_max = 1000,
            vACbase_LL_RMS = 333,
            turnsRatio = 333 / 380,
            Lᵣ = 0.0461,
            Rᵣ = 0.4103,
            Lₐᵣₘ = NB.Grid(30e-3, 5 / sqrt(3)),
            Rₐᵣₘ = NB.Grid(1.07, 10 / sqrt(3)),
            Cₐᵣₘ = NB.Grid(10e-3, 5 / sqrt(3)),
            occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
            ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
            pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
            p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
            q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
            timeDelay = 200e-6,
            padeOrderNum = 5,
            padeOrderDen = 5
        ),
        ohl = NB.overhead_line(
            length = half_corridor.ohl,
            conductors = corridor_conductors,
            groundwires = corridor_groundwires,
            earth_parameters = (1, 1, soil_resistivity),
            transformation = true
        ),
        ugc = NB.cable(
            length = half_corridor.ugc,
            positions = [(-0.5, 1.0), (0.5, 1.0)],
            C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
            I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
            C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
            I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
            C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
            I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
            earth_parameters = (1, 1, soil_resistivity),
            transformation = true
        )
    )
);

converter_uq_builders = NB.define(converter_uq_elements, connections;
    options = builder_options);

converter_trials = 100 #src
#md converter_trials = 5
converter_uq = NB.determine_impedance(
    converter_uq_builders;
    nets = [:B3d, :B5, :B6d],
    freq_range = (100.0, 5e3, 400),
    trials = converter_trials,
    distribution = :uniform,
    seed = 2028,
    return_samples = true
);

# Peak impedance and its frequency are direct resonance-screening KPIs. They
# retain the nonlinear effect of every trial; computing them from the mean
# impedance would hide trial-to-trial resonance movement.
converter_case = only(converter_uq)
converter_frequency = real.(converter_case.frequencies) ./ (2π)
converter_kpis = map(enumerate((:B3d, :B5, :B6d))) do (net_index, net)
    samples_db = 20 .* log10.(abs.(converter_case.samples[net_index, net_index, :, :]))
    peak_db = vec(maximum(samples_db; dims = 1))
    peak_frequency = [converter_frequency[argmax(view(samples_db, :, trial))]
                      for trial in axes(samples_db, 2)]
    (;
        net,
        peak_db_median = median(peak_db),
        peak_db_q05 = quantile(peak_db, 0.05),
        peak_db_q95 = quantile(peak_db, 0.95),
        peak_frequency_median = median(peak_frequency),
        peak_frequency_q05 = quantile(peak_frequency, 0.05),
        peak_frequency_q95 = quantile(peak_frequency, 0.95)
    )
end;

converter_panels = map(enumerate((:B3d, :B5, :B6d))) do (net_index, net)
    samples_db = 20 .* log10.(abs.(converter_case.samples[net_index, net_index, :, :]))
    median_db = [median(view(samples_db, row, :)) for row in axes(samples_db, 1)]
    q05_db = [quantile(view(samples_db, row, :), 0.05) for row in axes(samples_db, 1)]
    q95_db = [quantile(view(samples_db, row, :), 0.95) for row in axes(samples_db, 1)]
    plot(converter_frequency, median_db;
        ribbon = (median_db .- q05_db, q95_db .- median_db),
        xscale = :log10, label = "median, 5–95%", linewidth = 2,
        xlabel = "Frequency [Hz]", ylabel = "|Z| [dBΩ]", title = string(net),
        framestyle = :box, minorgrid = true, fillalpha = 0.2)
end

plot(converter_panels...;
    layout = (3, 1), size = (950, 1050),
    plot_title = "P2P converter-parameter uncertainty")

# The numeric KPI table is also available for automated screening.
converter_kpis
