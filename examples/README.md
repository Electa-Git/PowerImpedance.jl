# P2P HVDC link
A usage example is provided here to help you become familiar with the package functions and frequency-domain analysis methods. This is a point-to-point HVDC link, shown in the figure below:
![p2p figure](examples/pictures/P2P_HVDC.png)

## Initializing a network
First, we set up a network that includes all components and their respective controls. Each component has its own pins, which will be connected to form the network. Let's start by defining the network using the `@network` macro:
```julia
using PowerImpedance
import PowerImpedance: @network

net = @network begin
    voltageBase = transmissionVoltage
end
```
Where the base voltage should be included for correct p.u. calculations. Now, we will start defining our components. First, two ideal AC voltage sources:
```julia
g1 = ac_source(V = transmissionVoltage, P = pHVDC1, P_min = -2000, P_max = 2000, Q_max = 1000, Q_min = -1000, pins = 3, transformation = true)

g4 = ac_source(V = transmissionVoltage, P = pHVDC1, P_min = -2000, P_max = 2000, Q_max = 1000, Q_min = -1000, pins = 3, transformation = true)

```
Next, the first MMC in DVC-control mode:
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
Then, the second MMC in PQ-mode:
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
Then the underground DC cable connecting both converters:
```julia
dc_line = cable(length = 100e3, positions = [(-0.5,1), (0.5,1)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)
```
And the two transmission lines connecting the MMCs with the voltage sources:
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
Finally, we connect the pins of all defined components to form the network:

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
This macro will call [PowerModelsACDC](https://github.com/Electa-Git/PowerModelsACDC.jl) to run the powerflow, and update the converter's setpoints based on these results.

## Determining impedance
Now, we determine the impedance as seen from bus 7:
```julia
# Determine impedance seen at the AC side of the HVDC link
imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g1], input_pins=Any[:B7d,:B7q], 
output_pins=Any[:gndd,:gndq], freq_range = (10,1000,1000))
```
Finally, we use the `bodeplot` function to plot the dd-channel impedance:
```julia
Z_dd = getindex.(imp_ac,1,1)

impedance_bode = bodeplot(Z_dd, omega_ac,legend="Z_dd")
display(impedance_bode)
```
Which gives this bodeplot for the P2P HVDC link:

![Bode plot](examples/pictures/impedance_bode.svg)
