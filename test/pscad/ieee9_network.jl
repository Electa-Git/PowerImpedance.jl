# Physical parameters and topology copied from local/IEEE9bus/IEEE9bus_abc.jl.
# Old source V is phase peak: copy it directly to Setpoint.Vac, without sqrt(2).
# The balanced circuit uses transformation=true for the supported dq power flow
# and export. Sources retain unspecified P/Q; the classic default voltage base
# is retained. Symbolic series impedances become functions of s.
# Explicit-model voltage ratings are PF-bound metadata (phase RMS V), inferred
# from the fixed source voltages and turns ratios; they do not enter eval_abcd.
import PowerImpedance: @network

function ieee9_network()
    return @network begin
        g1 = ac_source(setpoint = Setpoint(Vac = 16.5 * sqrt(2/3)), pins = 3, transformation = true)
        g2 = ac_source(setpoint = Setpoint(Vac = 18 * sqrt(2/3)), pins = 3, transformation = true)
        g3 = ac_source(setpoint = Setpoint(Vac = 13.8 * sqrt(2/3)), pins = 3, transformation = true)

        tl78 = overhead_line(length = 76e3,
            conductors = Conductors(
                organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
            earth_parameters = (1, 1, 100), transformation = true)

        tl89 = overhead_line(length = 106e3,
            conductors = Conductors(
                organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
            earth_parameters = (1, 1, 100), transformation = true)

        tl75 = overhead_line(length = 170e3,
            conductors = Conductors(
                organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
            earth_parameters = (1, 1, 100), transformation = true)

        tl96 = overhead_line(length = 179e3,
            conductors = Conductors(
                organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
            earth_parameters = (1, 1, 100), transformation = true)

        tl54 = overhead_line(length = 89e3,
            conductors = Conductors(
                organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
            earth_parameters = (1, 1, 100), transformation = true)

        tl64 = overhead_line(length = 97e3,
            conductors = Conductors(
                organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
                Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
            groundwires = Groundwires(
                nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
            earth_parameters = (1, 1, 100), transformation = true)

        t1 = transformer(n = 16.5/230, Lₚ = 4.9916e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.097/2,
            V₁ᵒ = 16.5e3/sqrt(3), V₂ᵒ = 230e3/sqrt(3),
            Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
        t2 = transformer(n = 18/230, Lₚ = 6.4458e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.1052/2,
            V₁ᵒ = 18e3/sqrt(3), V₂ᵒ = 230e3/sqrt(3),
            Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
        t3 = transformer(n = 13.8/230, Lₚ = 3.5523e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0987/2,
            V₁ᵒ = 13.8e3/sqrt(3), V₂ᵒ = 230e3/sqrt(3),
            Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)

        l5 = impedance(z = s -> 1269.6 + 10.1 * s, pins = 3, transformation = true) # Nominal P 41.6667 MW, nominal Q 16.66667 MVar
        l6 = impedance(z = s -> 1763.3 + 16.84 * s, pins = 3, transformation = true) # Nominal P 30 MW, nominal Q 10 MVar
        l8 = impedance(z = s -> 1587.16 + 14.43 * s, pins = 3, transformation = true) # Nominal P 33.33 MW, nominal Q 11.6667 MVar

        g1[2.1] ⟷ gndD
        g1[2.2] ⟷ gndQ

        g1[1.1] ⟷ t1[1.1] ⟷ Bus1d
        g1[1.2] ⟷ t1[1.2] ⟷ Bus1q

        t1[2.1] ⟷ tl64[1.1] ⟷ tl54[1.1] ⟷ Bus4d
        t1[2.2] ⟷ tl64[1.2] ⟷ tl54[1.2] ⟷ Bus4q

        tl64[2.1] ⟷ l6[1.1] ⟷ tl96[1.1] ⟷ Bus6d
        tl64[2.2] ⟷ l6[1.2] ⟷ tl96[1.2] ⟷ Bus6q

        l6[2.1] ⟷ gndD
        l6[2.2] ⟷ gndQ

        tl54[2.1] ⟷ l5[1.1] ⟷ tl75[1.1] ⟷ Bus5d
        tl54[2.2] ⟷ l5[1.2] ⟷ tl75[1.2] ⟷ Bus5q

        l5[2.1] ⟷ gndD
        l5[2.2] ⟷ gndQ

        tl96[2.1] ⟷ tl89[1.1] ⟷ t3[2.1] ⟷ Bus9d
        tl96[2.2] ⟷ tl89[1.2] ⟷ t3[2.2] ⟷ Bus9q

        tl75[2.1] ⟷ tl78[1.1] ⟷ t2[2.1] ⟷ Bus7d
        tl75[2.2] ⟷ tl78[1.2] ⟷ t2[2.2] ⟷ Bus7q

        tl78[2.1] ⟷ tl89[2.1] ⟷ l8[1.1] ⟷ Bus8d
        tl78[2.2] ⟷ tl89[2.2] ⟷ l8[1.2] ⟷ Bus8q

        l8[2.1] ⟷ gndD
        l8[2.2] ⟷ gndQ

        t2[1.1] ⟷ g2[1.1] ⟷ Bus2d
        t2[1.2] ⟷ g2[1.2] ⟷ Bus2q

        g2[2.1] ⟷ gndD
        g2[2.2] ⟷ gndQ

        t3[1.1] ⟷ g3[1.1] ⟷ Bus3d
        t3[1.2] ⟷ g3[1.2] ⟷ Bus3q

        g3[2.1] ⟷ gndD
        g3[2.2] ⟷ gndQ
    end
end
