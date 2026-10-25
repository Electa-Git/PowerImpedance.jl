# Physical parameters and topology copied from local/IEEE9bus/IEEE9bus_abc.jl.
# Source voltages are phase peak. The balanced circuit uses dq buses for power flow
# and export. Sources retain unspecified
# P/Q and the classic default voltage base. Symbolic series impedances become functions of
# s. Explicit-model voltage ratings are PF-bound metadata (phase RMS V), inferred from
# fixed source voltages and turns ratios; they do not enter eval_abcd.

function ieee9_network()
    g1 = ac_source(v = 16.5 * sqrt(2/3))
    g2 = ac_source(v = 18 * sqrt(2/3))
    g3 = ac_source(v = 13.8 * sqrt(2/3))

    tl78 = overhead_line(; length = 76e3,
        conductors = Conductors(
            organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(
            nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    tl89 = overhead_line(; length = 106e3,
        conductors = Conductors(
            organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(
            nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    tl75 = overhead_line(; length = 170e3,
        conductors = Conductors(
            organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(
            nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    tl96 = overhead_line(; length = 179e3,
        conductors = Conductors(
            organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(
            nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    tl54 = overhead_line(; length = 89e3,
        conductors = Conductors(
            organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(
            nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    tl64 = overhead_line(; length = 97e3,
        conductors = Conductors(
            organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(
            nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ = 10),
        earth_parameters = (1, 1, 100))

    t1 = transformer(; n = 16.5/230, Lₚ = 4.9916e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.097/2,
        V₁ᵒ = 16.5e3/sqrt(3), V₂ᵒ = 230e3/sqrt(3),
        Cₜ = 7e-9, Cₛ = 12e-9, conductors = 3)
    t2 = transformer(; n = 18/230, Lₚ = 6.4458e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.1052/2,
        V₁ᵒ = 18e3/sqrt(3), V₂ᵒ = 230e3/sqrt(3),
        Cₜ = 7e-9, Cₛ = 12e-9, conductors = 3)
    t3 = transformer(; n = 13.8/230, Lₚ = 3.5523e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0987/2,
        V₁ᵒ = 13.8e3/sqrt(3), V₂ᵒ = 230e3/sqrt(3),
        Cₜ = 7e-9, Cₛ = 12e-9, conductors = 3)

    # Nominal P 41.6667 MW, nominal Q 16.66667 MVar
    l5 = impedance(; z = s -> 1269.6 + 10.1 * s, conductors = 3)
    # Nominal P 30 MW, nominal Q 10 MVar
    l6 = impedance(; z = s -> 1763.3 + 16.84 * s, conductors = 3)
    # Nominal P 33.33 MW, nominal Q 11.6667 MVar
    l8 = impedance(; z = s -> 1587.16 + 14.43 * s, conductors = 3)

    elements = (; g1, g2, g3, tl78, tl89, tl75, tl96, tl54, tl64,
        t1, t2, t3, l5, l6, l8)
    rows = (
        NetworkBuilder.Bus(:Bus1; ports = ((:g1, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus2; ports = ((:g2, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus3; ports = ((:g3, :ac),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus7; ports = ((:tl78, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus8; ports = ((:tl78, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus9; ports = ((:tl89, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus8; ports = ((:tl89, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus5; ports = ((:tl75, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus7; ports = ((:tl75, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus6; ports = ((:tl96, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus9; ports = ((:tl96, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus4; ports = ((:tl54, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus5; ports = ((:tl54, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus4; ports = ((:tl64, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus6; ports = ((:tl64, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus1; ports = ((:t1, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus4; ports = ((:t1, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus2; ports = ((:t2, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus7; ports = ((:t2, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus3; ports = ((:t3, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus9; ports = ((:t3, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus5; ports = ((:l5, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:l5, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus6; ports = ((:l6, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:l6, :side2),), domain = ACDQ),
        NetworkBuilder.Bus(:Bus8; ports = ((:l8, :side1),), domain = ACDQ),
        NetworkBuilder.Bus(:gnd; ports = ((:l8, :side2),), domain = ACDQ))
    return NetworkBuilder.define(elements, rows;
        options = (; voltageBase = 220 / sqrt(3)))
end
