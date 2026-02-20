using DelimitedFiles,SymEngine
s = symbols("s")
@time net = @network begin
    
    g1 = ac_source(V = 16.5 * sqrt(2/3), pins = 3, transformation = false)
    g2 = ac_source(V = 18 * sqrt(2/3), pins = 3, transformation = false)
    g3 = ac_source(V = 13.8 * sqrt(2/3), pins = 3, transformation = false)

    tl78 = overhead_line(length = 76e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                            Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
            groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
            earth_parameters = (1,1,100), transformation = false)

    tl89 = overhead_line(length = 106e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                            Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
            groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
            earth_parameters = (1,1,100), transformation = false)  

    tl75 = overhead_line(length = 170e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                            Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
            groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
            earth_parameters = (1,1,100), transformation = false)

    tl96 = overhead_line(length = 179e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                            Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
            groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
            earth_parameters = (1,1,100), transformation = false) 

    tl54 = overhead_line(length = 89e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                            Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
            groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
            earth_parameters = (1,1,100), transformation = false)

    tl64 = overhead_line(length = 97e3,
            conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                            Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
            groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
            earth_parameters = (1,1,100), transformation = false)
            
    t1 = transformer(n = 16.5/230 , Lₚ = 4.9916e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.097/2,  Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = false)
    t2 = transformer(n = 18/230 ,   Lₚ = 6.4458e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.1052/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = false)
    t3 = transformer(n = 13.8/230 , Lₚ = 3.5523e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0987/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = false)

    l5 = impedance(z = 1269.6 + 10.1s, pins = 3, transformation = false) # Nominal P 41.6667 MW, nominal Q 16.66667 MVar
    l6 = impedance(z = 1763.3 + 16.84s, pins = 3, transformation = false) # Nominal P 30 MW, nominal Q 10 MVar
    l8 = impedance(z = 1587.16 + 14.43s, pins = 3, transformation = false) # Nominal P 33.33 MW, nominal Q 11.6667 MVar

    g1[2.1] == gnda
    g1[2.2] == gndb
    g1[2.3] == gndc

    g1[1.1] == t1[1.1] == Bus1a
    g1[1.2] == t1[1.2] == Bus1b
    g1[1.3] == t1[1.3] == Bus1c

    t1[2.1] == tl64[1.1] == tl54[1.1] == Bus4a
    t1[2.2] == tl64[1.2] == tl54[1.2] == Bus4b
    t1[2.3] == tl64[1.3] == tl54[1.3] == Bus4c

    tl64[2.1] == l6[1.1] == tl96[1.1] == Bus6a
    tl64[2.2] == l6[1.2] == tl96[1.2] == Bus6b
    tl64[2.3] == l6[1.3] == tl96[1.3] == Bus6c

    l6[2.1] == gnda
    l6[2.2] == gndb
    l6[2.3] == gndc

    tl54[2.1] == l5[1.1] == tl75[1.1] == Bus5a
    tl54[2.2] == l5[1.2] == tl75[1.2] == Bus5b
    tl54[2.3] == l5[1.3] == tl75[1.3] == Bus5c

    l5[2.1] == gnda
    l5[2.2] == gndb
    l5[2.3] == gndc

    tl96[2.1] == tl89[1.1] == t3[2.1] == Bus9a
    tl96[2.2] == tl89[1.2] == t3[2.2] == Bus9b
    tl96[2.3] == tl89[1.3] == t3[2.3] == Bus9c

    tl75[2.1] == tl78[1.1] == t2[2.1] == Bus7a
    tl75[2.2] == tl78[1.2] == t2[2.2] == Bus7b
    tl75[2.3] == tl78[1.3] == t2[2.3] == Bus7c

    tl78[2.1] == tl89[2.1] == l8[1.1] == Bus8a
    tl78[2.2] == tl89[2.2] == l8[1.2] == Bus8b
    tl78[2.3] == tl89[2.3] == l8[1.3] == Bus8c

    l8[2.1] == gnda
    l8[2.2] == gndb
    l8[2.3] == gndc

    t2[1.1] == g2[1.1] == Bus2a
    t2[1.2] == g2[1.2] == Bus2b
    t2[1.3] == g2[1.3] == Bus2c

    g2[2.1] == gnda
    g2[2.2] == gndb
    g2[2.3] == gndc

    t3[1.1] == g3[1.1] == Bus3a
    t3[1.2] == g3[1.2] == Bus3b
    t3[1.3] == g3[1.3] == Bus3c

    g3[2.1] == gnda
    g3[2.2] == gndb
    g3[2.3] == gndc



end

@time imp_ac1, omega_ac1 = determine_impedance(net, elim_elements=[:g1], input_pins=Any[:Bus1a,:Bus1b,:Bus1c], 
output_pins=Any[:gnda,:gndb,:gndc], omega_range = (0,4,2000)) # impedance seen from Bus1
@time imp_ac2, omega_ac2 = determine_impedance(net, elim_elements=[:g2], input_pins=Any[:Bus2a,:Bus2b,:Bus2c], 
output_pins=Any[:gnda,:gndb,:gndc], omega_range = (0,4,2000)) # impedance seen from Bus2
@time imp_ac3, omega_ac3 = determine_impedance(net, elim_elements=[:g3], input_pins=Any[:Bus3a,:Bus3b,:Bus3c], 
output_pins=Any[:gnda,:gndb,:gndc], omega_range = (0,4,2000)) # impedance seen from Bus3

p = bode(imp_ac1, omega = omega_ac1)












# writedlm("imp_abc.csv",  imp_ac, ',')
# writedlm("w.csv",  omega_ac, ',')

# save_plot(p,string("files/", "from_Bus2_to_gnd_G3_withConverter", ".pdf"))
# save_plot(p)


