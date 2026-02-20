using DelimitedFiles,SymEngine
s = symbols("s")
@time net = @network begin
    
    g2 = ac_source(V = 18 * sqrt(2/3), pins = 3, transformation = false)

    # Including capacitances
            
#     t2 = transformer(n = 18/230 ,   Lₚ = 6.4458e-4, Rₚ = 0, Rₛ = 0, Lₛ = 0.1052, Lₘ = 0.0648, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = false)

    # Excluding capacitances
            
    t2 = transformer(n = 18/230 , Lₚ = 6.4458e-4/2, Lₛ  = 0.1052/2, Cₜ = 7e-9, Cₛ = 12e-9, pins = 3, transformation = false)

    l8 = impedance(z = 1587.16 + 14.43s, pins = 3, transformation = false) # Nominal P 33.33 MW, nominal Q 11.6667 MVar

    g2[2.1] == gnda
    g2[2.2] == gndb
    g2[2.3] == gndc

    g2[1.1] == t2[1.1] == Bus2a
    g2[1.2] == t2[1.2] == Bus2b
    g2[1.3] == t2[1.3] == Bus2c

    t2[2.1] == l8[1.1] == Bus7a
    t2[2.2] == l8[1.2] == Bus7b
    t2[2.3] == l8[1.3] == Bus7c

    l8[2.1] == gnda
    l8[2.2] == gndb
    l8[2.3] == gndc

    




end

@time imp_ac, omega_ac = determine_impedance(net, elim_elements=[:g2], input_pins=Any[:Bus2a,:Bus2b,:Bus2c], 
output_pins=Any[:gnda,:gndb,:gndc], omega_range = (0,4,1000))

# imp_ac_d = []
# imp_ac_q = []

# for n in eachindex(imp_ac)
#     push!(imp_ac_d,imp_ac[n,1][1])
#     push!(imp_ac_q,imp_ac[n,1][2])
# end
p = bode(imp_ac, omega = omega_ac)

writedlm("imp_abc.csv",  imp_ac, ',')
writedlm("w.csv",  omega_ac, ',')


# save_plot(p,string("files/", "from_Bus2_to_gnd_G3_withConverter", ".pdf"))
# save_plot(p)


