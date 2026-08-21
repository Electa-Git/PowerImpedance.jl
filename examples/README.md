# P2P HVDC link
This example models a point-to-point HVDC link and calculates its frequency-domain impedance. The link contains two modular multilevel converters (MMCs), an underground DC cable, two AC transmission lines, and ideal AC grids:

![p2p figure](examples/pictures/P2P_HVDC.png)

## Initializing a network

Create a network with the transmission-system line-to-line RMS voltage as its per-unit voltage base:

```julia
using PowerImpedance
import PowerImpedance: @network

net = @network begin
    voltageBase = transmissionVoltage
end
```

The voltage base is required for consistent per-unit conversion. Define the ideal AC sources at the two converter terminals:

```julia
g1 = ac_source(V = transmissionVoltage, P = pHVDC1, P_min = -2000, P_max = 2000, Q_max = 1000, Q_min = -1000, pins = 3, transformation = true)

g4 = ac_source(V = transmissionVoltage, P = pHVDC1, P_min = -2000, P_max = 2000, Q_max = 1000, Q_min = -1000, pins = 3, transformation = true)

```

The remote-terminal MMC regulates DC voltage:

```julia
# HVDC link 1
# MMC1 controls the DC voltage, and is situated at the remote end.
c1 = mmc(Vᵈᶜ = 800, vDCbase = 800, Vₘ = transmissionVoltage,
        P_max = 1500, P_min = -1500, P = -pHVDC1, Q = qC1, Q_max = 500, Q_min = -500,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
        dc = PI_control(Kₚ = 5, Kᵢ = 15),
        )
```

The second MMC regulates active and reactive power:

```julia
 # MMC2 controls P&Q. It is connected to bus 7. 
c2 = mmc(Vᵈᶜ = 800, vDCbase = 800, Vₘ = transmissionVoltage,
        P_max = 1000, P_min = -1000, P = pHVDC1, Q = qC2, Q_max = 1000, Q_min = -1000,
        vACbase_LL_RMS = 333, turnsRatio = 333/380, Lᵣ = 0.0461, Rᵣ = 0.4103,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159)
        )
```

A 100 km bipolar underground cable connects the DC terminals. Its concentric conductor and insulation layers define the frequency-dependent cable model:

```julia
dc_line = cable(length = 100e3, positions = [(-0.5,1), (0.5,1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)
```

A 25 km overhead line connects the remote converter to its ideal AC grid. A 90 km line connects the other converter terminal:

```julia 
# TL at the remote end
tl1 = overhead_line(length = 25e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

tl78 = overhead_line(length = 90e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)
```

Connect the component terminals to the AC, DC, and reference nodes:

```julia
c1[2.1] ⟷ tl1[2.1] ⟷ B3d
c1[2.2] ⟷ tl1[2.2] ⟷ B3q

g4[1.1] ⟷ tl1[1.1] ⟷ B2d
g4[1.2] ⟷ tl1[1.2] ⟷ B2q



g4[2.1] ⟷ gndd
g4[2.2] ⟷ gndq

c1[1.1] ⟷ dc_line[1.1] ⟷ B4
c2[1.1] ⟷ dc_line[2.1] ⟷ B5

# 30 km power line at the AC side
c2[2.1] == tl78[1.1] ⟷ B6d
c2[2.2] == tl78[1.2] ⟷ B6q
g1[1.1] == tl78[2.1] == B7d
g1[1.2] == tl78[2.2] == B7q

g1[2.1] == gndd
g1[2.2] == gndq
```

The macro builds the network. [PowerModelsACDC](https://github.com/Electa-Git/PowerModelsACDC.jl) solves its operating point, and the solved values update the converter setpoints.

## Determining impedance

Calculate the AC impedance seen from bus 7 while excluding the ideal source from the retained subnetwork:

```julia
# Determine impedance seen at the AC side of the HVDC link
imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g1], input_pins=Any[:B7d,:B7q], 
output_pins=Any[:gndd,:gndq], freq_range = (10,1000,1000))
```

Select the direct-axis entry and plot its Bode response:

```julia
Z_dd = getindex.(imp_ac,1,1)

impedance_bode = bodeplot(Z_dd, omega_ac,legend="Z_dd")
display(impedance_bode)
```

The resulting curve shows the direct-axis impedance magnitude and phase of the P2P HVDC link:

![Bode plot](examples/pictures/impedance_bode.svg)
