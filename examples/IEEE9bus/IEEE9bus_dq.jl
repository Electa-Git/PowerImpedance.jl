using HVDCstability,SymEngine
s = symbols("s")
@time net = @network begin
    
        g1 = ac_source(V = 16.5 * sqrt(2/3), pins = 3, transformation = true)
        g2 = ac_source(V = 18 * sqrt(2/3), pins = 3, transformation = true)
        g3 = ac_source(V = 13.8 * sqrt(2/3), pins = 3, transformation = true)
    
        tl78 = overhead_line(length = 76e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
    
        tl89 = overhead_line(length = 106e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)  
    
        tl75 = overhead_line(length = 170e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
    
        tl96 = overhead_line(length = 179e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true) 
    
        tl54 = overhead_line(length = 89e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
    
        tl64 = overhead_line(length = 97e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)
                
        # Lₘ =, Rₘ =
    
        # Including capacitances
                
        t1 = transformer(n = 16.5/230 , Lₚ = 4.9916e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.097/2,  Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
        t2 = transformer(n = 18/230 ,   Lₚ = 6.4458e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.1052/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
        t3 = transformer(n = 13.8/230 , Lₚ = 3.5523e-4/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0987/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
    
        l5 = impedance(z = 1269.6 + 10.1s, pins = 3, transformation = true) # Nominal P 41.6667 MW, nominal Q 16.66667 MVar
        l6 = impedance(z = 1763.3 + 16.84s, pins = 3, transformation = true) # Nominal P 30 MW, nominal Q 10 MVar
        l8 = impedance(z = 1587.16 + 14.43s, pins = 3, transformation = true) # Nominal P 33.33 MW, nominal Q 11.6667 MVar

    g1[1.1] == gndd
    g1[1.2] == gndq

    g1[2.1] == t1[1.1] == Bus1d
    g1[2.2] == t1[1.2] == Bus1q

#     c1 = mmc(Vᵈᶜ = 640, Vₘ = 230*sqrt(2/3),
#                 P_max = 1500, P_min = -1500, P = 100, Q = 0, Q_max = 500, Q_min = -500, P_dc = -100,
#                 occ = PI_control(ζ = 0.7, bandwidth = 1000),
#                 ccc = PI_control(ζ = 0.7, bandwidth = 300),
#                 power = PI_control(Kₚ = 2.0020e-07, Kᵢ = 1.0010e-04),
#                 energy = PI_control(Kₚ = 120, Kᵢ = 400, ref=[1*3072e4]),
#                 zcc = PI_control(ζ = 0.7, bandwidth = 300),
#                 timeDelay=150e-6, padeOrderNum=3, padeOrderDen=3
#                 )

#     dc = dc_source(V = 640)

#     dc[1.1] == gndd

#     c1[1.1] == dc[2.1]

#     c1[2.1] == t1[1.1] == Bus1d
#     c1[2.2] == t1[1.2] == Bus1q

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

    tl75[2.1] == tl78[1.1] == t2[2.1] == Bus7d
    tl75[2.2] == tl78[1.2] == t2[2.2] == Bus7q

    tl78[2.1] == tl89[2.1] == l8[1.1] == Bus8d
    tl78[2.2] == tl89[2.2] == l8[1.2] == Bus8q

    l8[2.1] == gndd
    l8[2.2] == gndq

    t2[1.1] == g2[1.1] == Bus2d
    t2[1.2] == g2[1.2] == Bus2q

    g2[2.1] == gndd
    g2[2.2] == gndq

    t3[1.1] == g3[1.1] == Bus3d
    t3[1.2] == g3[1.2] == Bus3q

    g3[2.1] == gndd
    g3[2.2] == gndq

end

#@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:gen1], input_pins=Any[:TestNode1,:TestNode2,:TestNode3], 
#output_pins=Any[:gnd,:gnd,:gnd], omega_range = (0,4,1000))

@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g2], input_pins=Any[:Bus2d,:Bus2q], 
output_pins=Any[:gndd,:gndq], omega_range = (0,4,1000))

# imp_ac_d = []
# imp_ac_q = []

# for n in eachindex(imp_ac)
#     push!(imp_ac_d,imp_ac[n,1][1])
#     push!(imp_ac_q,imp_ac[n,1][2])
# end
p = bode(imp_ac, omega = omega_ac)

# save_plot(p,string("files/", "from_Bus2_to_gnd_G3_withConverter", ".pdf"))
save_plot(p)


