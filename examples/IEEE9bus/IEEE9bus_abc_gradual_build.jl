using DelimitedFiles,SymEngine
s = symbols("s")
@time net = @network begin
    
    g2 = ac_source(V = 18 * sqrt(2/3), pins = 3, transformation = false)

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

    # Including capacitances
            
    t2 = transformer(n = 18/230 ,   Lₚ = 6.4458e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.1052/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, organization = :YY, transformation = false)
    # t3 = transformer(n = 13.8/230 , Lₚ = 3.5523e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0987/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, organization = :YY, transformation = false)

    # Excluding capacitances

    l8 = impedance(z = 1587.16 + 14.43s, pins = 3, transformation = false) # Nominal P 33.33 MW, nominal Q 11.6667 MVar

    l_dummy = impedance(z = s, pins = 3, transformation = false)

    g2[2.1] == gnda
    g2[2.2] == gndb
    g2[2.3] == gndc 

    t2[1.1] == g2[1.1] == Bus2a
    t2[1.2] == g2[1.2] == Bus2b
    t2[1.3] == g2[1.3] == Bus2c    

    # Single and double lines
    tl78[1.1] == t2[2.1] == Bus7a
    tl78[1.2] == t2[2.2] == Bus7b
    tl78[1.3] == t2[2.3] == Bus7c

    # tl89[1.1] == tl78[2.1] == Bus8a
    # tl89[1.2] == tl78[2.2] == Bus8b
    # tl89[1.3] == tl78[2.3] == Bus8c

    l8[1.1] == tl89[1.1] == tl78[2.1] == Bus8a
    l8[1.2] == tl89[1.2] == tl78[2.2] == Bus8b
    l8[1.3] == tl89[1.3] == tl78[2.3] == Bus8c
    # l8[1.1] == tl78[2.1] == Bus8a
    # l8[1.2] == tl78[2.2] == Bus8b
    # l8[1.3] == tl78[2.3] == Bus8c
    # tl75[1.1] == tl89[1.1] == tl78[2.1] == Bus8a
    # tl75[1.2] == tl89[1.2] == tl78[2.2] == Bus8b
    # tl75[1.3] == tl89[1.3] == tl78[2.3] == Bus8c


    tl89[2.1] == l_dummy[1.1] == Bus9a
    tl89[2.2] == l_dummy[1.2] == Bus9b
    tl89[2.3] == l_dummy[1.3] == Bus9c

    # tl75[2.1] == l_dummy2[1.1] == Bus1a
    # tl75[2.2] == l_dummy2[1.2] == Bus1b
    # tl75[2.3] == l_dummy2[1.3] == Bus1c

    l_dummy[2.1] == gnda
    l_dummy[2.2] == gndb
    l_dummy[2.3] == gndc

    # l_dummy2[2.1] == gnda
    # l_dummy2[2.2] == gndb
    # l_dummy2[2.3] == gndc

    l8[2.1] == gnda
    l8[2.2] == gndb
    l8[2.3] == gndc

    # Single impedance tests

    # tl78[2.1] == l_dummy[1.1] == Bus8a
    # tl78[2.2] == l_dummy[1.2] == Bus8b
    # tl78[2.3] == l_dummy[1.3] == Bus8c

    # l_dummy[2.1] == gnda
    # l_dummy[2.2] == gndb
    # l_dummy[2.3] == gndc

    # l_dummy[2.1] == l_dummy[2.2] == l_dummy[2.3] == gnd

end


@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g2], input_pins=Any[:Bus2a,:Bus2b,:Bus2c], 
output_pins=Any[:gnda,:gndb,:gndc], omega_range = (0,4,2000))
# parameters_type Y gives weird results

p = bode(imp_ac, omega = omega_ac)

writedlm("imp_abc.csv",  imp_ac, ',')
writedlm("w.csv",  omega_ac, ',')


# save_plot(p,string("files/", "from_Bus2_to_gnd_G3_withConverter", ".pdf"))
# save_plot(p)


