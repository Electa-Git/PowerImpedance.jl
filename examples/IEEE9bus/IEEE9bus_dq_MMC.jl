using DelimitedFiles,SymEngine,HVDCstability
s = symbols("s")
# Old file, not updated. Contains an MMC with SI controller gains.
@time net = @network begin
    
        
        g1 = ac_source(V = 16.5 * sqrt(2/3), P_min = 50, P = 200, P_max = 1500, Q = 0, Q_max = 500, Q_min = -500, pins = 3, transformation = true)
        g3 = ac_source(V = 13.8 * sqrt(2/3), P_min = 50, P = 200, P_max = 1500, Q = 0, Q_max = 500, Q_min = -500, pins = 3, transformation = true)
    
        tl78 = overhead_line(length = 35e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
    
        tl89 = overhead_line(length = 53e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)  
    
        tl75 = overhead_line(length = 100e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
    
        tl96 = overhead_line(length = 39e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true) 
    
        tl54 = overhead_line(length = 45e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
    
        tl64 = overhead_line(length = 17e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
                
    
        # Including capacitances
                
        t1 = transformer(n = 16.5/380 , Lₚ = 4.9916e-5/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0265/2,  Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
        
        t3 = transformer(n = 13.8/380 , Lₚ = 3.5523e-5/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0269/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
    

        l5 = impedance(z = 960 + s, pins = 3, transformation = true) 
        l6 = impedance(z = 960 + s, pins = 3, transformation = true) 
        l8 = impedance(z = 960 + s, pins = 3, transformation = true) 

        c1 = mmc(Vᵈᶜ = 640, Vₘ = 380*sqrt(2/3),
                P_max = 1000, P_min = -1000, P = 124, Q = -1, Q_max = 500, Q_min = -500, P_dc = -124,
                occ = PI_control(Kₚ = 135.0011, Kᵢ = 9.1603e+04),
                ccc = PI_control(Kₚ = 42.9123, Kᵢ = 1.9739e+04),
                pll = PI_control(Kₚ = 2.8351e-04, Kᵢ = 0.0127),
                power = PI_control(Kₚ = 2.1487e-07, Kᵢ = 6.7503e-05)
                )

        dc = dc_source(V = 640)

        dc[1.1] == gnd

        dc[2.1] == c1[1.1]       

        # t2 = transformer(n = 380/380 ,   Lₚ = 0.0287/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0287/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
        # c1[2.1] == t2[1.1] == Bus2d
        # c1[2.2] == t2[1.2] == Bus2q

        # t2 = transformer(n = 18/380 ,   Lₚ = 6.4458e-5/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0287/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
        # g2 = ac_source(V = 18 * sqrt(2/3),  pins = 3, transformation = true)

        # t2[1.1] == g2[1.1] == Bus2d
        # t2[1.2] == g2[1.2] == Bus2q

        # g2[2.1] == gndd
        # g2[2.2] == gndq


        g1[2.1] == gndd
        g1[2.2] == gndq

        g1[1.1] == t1[1.1] == Bus1d
        g1[1.2] == t1[1.2] == Bus1q

        t1[2.1] == tl64[1.1] == tl54[1.1] == Bus4d
        t1[2.2] == tl64[1.2] == tl54[1.2] == Bus4q

        tl64[2.1] == l6[1.1] == tl96[1.1] == Bus6d
        tl64[2.2] == l6[1.2] == tl96[1.2] == Bus6q

        l6[2.1] == gndd
        l6[2.2] == gndq

        tl54[2.1] == l5[1.1] == tl75[1.1] == Bus5d
        tl54[2.2] == l5[1.2] == tl75[1.2] == Bus5q

        l5[2.1] == gndd
        l5[2.2] == gndq

        tl96[2.1] == tl89[1.1] == t3[2.1] == Bus9d
        tl96[2.2] == tl89[1.2] == t3[2.2] == Bus9q

        # Including a separate converter transformer
        # tl75[2.1] == tl78[1.1] == t2[2.1] == Bus7d
        # tl75[2.2] == tl78[1.2] == t2[2.2] == Bus7q
        # Converter transformer represented internally within the MMC using a series RL impedance
        tl75[2.1] == tl78[1.1] == c1[2.1] == Bus7d
        tl75[2.2] == tl78[1.2] == c1[2.2] == Bus7q

        tl78[2.1] == tl89[2.1] == l8[1.1] == Bus8d
        tl78[2.2] == tl89[2.2] == l8[1.2] == Bus8q

        l8[2.1] == gndd
        l8[2.2] == gndq

        t3[1.1] == g3[1.1] == Bus3d
        t3[1.2] == g3[1.2] == Bus3q

        g3[2.1] == gndd
        g3[2.2] == gndq


end


@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g3], input_pins=Any[:Bus3d,:Bus3q], 
output_pins=Any[:gndd,:gndq], omega_range = (-2,4,2000))

p = bode(imp_ac, omega = omega_ac)

writedlm("imp_dq_MMC.csv",  imp_ac, ',')
writedlm("w_dq_MMC.csv",  omega_ac, ',')


