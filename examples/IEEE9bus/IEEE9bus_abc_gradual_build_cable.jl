using DelimitedFiles,SymEngine
s = symbols("s")
@time net = @network begin

    g1 = ac_source(V = 16.5 * sqrt(2/3), pins = 3, transformation = false)
    g2 = ac_source(V = 18 * sqrt(2/3), pins = 3, transformation = false)
    g3 = ac_source(V = 13.8 * sqrt(2/3), pins = 3, transformation = false)

    c78 = cable(length = 76e3, positions = [(-0.5,1.9), (0,1.9), (0.5,1.9)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = false, earth_parameters = (1,1,100))

    c89 = cable(length = 106e3, positions = [(-0.5,1.9), (0,1.9), (0.5,1.9)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = false, earth_parameters = (1,1,100))

    c75 = cable(length = 170e3, positions = [(-0.5,1.9), (0,1.9), (0.5,1.9)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = false, earth_parameters = (1,1,100))

    c96 = cable(length = 179e3, positions = [(-0.5,1.9), (0,1.9), (0.5,1.9)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = false, earth_parameters = (1,1,100))


    c54 = cable(length = 89e3, positions = [(-0.5,1.9), (0,1.9), (0.5,1.9)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = false, earth_parameters = (1,1,100))

    c64 = cable(length = 97e3, positions = [(-0.5,1.9), (0,1.9), (0.5,1.9)],
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = false, earth_parameters = (1,1,100))
            
    # Including capacitances
            
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

    t1[2.1] == c64[1.1] == c54[1.1] == Bus4a
    t1[2.2] == c64[1.2] == c54[1.2] == Bus4b
    t1[2.3] == c64[1.3] == c54[1.3] == Bus4c

    c64[2.1] == l6[1.1] == c96[1.1] == Bus6a
    c64[2.2] == l6[1.2] == c96[1.2] == Bus6b
    c64[2.3] == l6[1.3] == c96[1.3] == Bus6c

    l6[2.1] == gnda
    l6[2.2] == gndb
    l6[2.3] == gndc

    c54[2.1] == l5[1.1] == c75[1.1] == Bus5a
    c54[2.2] == l5[1.2] == c75[1.2] == Bus5b
    c54[2.3] == l5[1.3] == c75[1.3] == Bus5c

    l5[2.1] == gnda
    l5[2.2] == gndb
    l5[2.3] == gndc

    c96[2.1] == c89[1.1] == t3[2.1] == Bus9a
    c96[2.2] == c89[1.2] == t3[2.2] == Bus9b
    c96[2.3] == c89[1.3] == t3[2.3] == Bus9c

    c75[2.1] == c78[1.1] == t2[2.1] == Bus7a
    c75[2.2] == c78[1.2] == t2[2.2] == Bus7b
    c75[2.3] == c78[1.3] == t2[2.3] == Bus7c

    c78[2.1] == c89[2.1] == l8[1.1] == Bus8a
    c78[2.2] == c89[2.2] == l8[1.2] == Bus8b
    c78[2.3] == c89[2.3] == l8[1.3] == Bus8c

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


@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g2], input_pins=Any[:Bus2a,:Bus2b,:Bus2c], 
output_pins=Any[:gnda,:gndb,:gndc], omega_range = (0,4,2000))
# parameters_type Y gives weird results

p = bode(imp_ac, omega = omega_ac)

writedlm("imp_abc.csv",  imp_ac, ',')
writedlm("w.csv",  omega_ac, ',')


# save_plot(p,string("files/", "from_Bus2_to_gnd_G3_withConverter", ".pdf"))
# save_plot(p)


