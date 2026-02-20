using DelimitedFiles,SymEngine
s = symbols("s")
@time net = @network begin
    
        
        g3 = ac_source(V = 13.8 * sqrt(2/3), pins = 3, transformation = true)
        tl89 = overhead_line(length = 53e3,
                conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                                Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
                groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
                earth_parameters = (1,1,100), transformation = true)  
    
        
        t3 = transformer(n = 13.8/380 , Lₚ = 3.5523e-5/2, Rₚ = 0, Rₛ = 0, Lₛ = 0.0269/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = true)
    

        l8 = impedance(z = 960 + s, pins = 3, transformation = true) 



        tl89[1.1] == t3[2.1] == Bus9d
        tl89[1.2] == t3[2.2] == Bus9q

        tl89[2.1] == l8[1.1] == Bus8d
        tl89[2.2] == l8[1.2] == Bus8q

        l8[2.1] == gndd
        l8[2.2] == gndq

        t3[1.1] == g3[1.1] == Bus3d
        t3[1.2] == g3[1.2] == Bus3q

        g3[2.1] == gndd
        g3[2.2] == gndq


end

#@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:gen1], input_pins=Any[:TestNode1,:TestNode2,:TestNode3], 
#output_pins=Any[:gnd,:gnd,:gnd], omega_range = (0,4,1000))

@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g3], input_pins=Any[:Bus3d,:Bus3q], 
output_pins=Any[:gndd,:gndq], omega_range = (0,4,1000))

p = bode(imp_ac, omega = omega_ac)

writedlm("imp_dq_MMC.csv",  imp_ac, ',')
writedlm("w_dq_MMC.csv",  omega_ac, ',')


