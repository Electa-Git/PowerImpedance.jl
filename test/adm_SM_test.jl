
import PowerImpedance: @network

function synchronousmachinecircuit()
net = @network begin

        voltageBase = 380/sqrt(3)

        # Values used in the SG validation
    
        sg1 = synchronousmachine(setpoint=Setpoint(Vac =1.000177992* 380/sqrt(3), Pac= 900), 
                                        elec=ElectricalSM(Vᵃᶜ_base = 380.0)
                                )
        g2 = ac_source(setpoint=Setpoint(Vac = 380/sqrt(3)), pins = 3, transformation = true) #impedance(z=160, pins=3, transformation = true)

        # imp=impedance(z=0.00, pins=3, transformation = true)

        sg1[2.1] == gndd
        sg1[2.2] == gndq

        sg1[1.1] == g2[1.1] == Bus2d
        # imp[2.1]== g2[1.1] == Bus1d
        sg1[1.2] == g2[1.2] == Bus2q
        # imp[2.2] == g2[1.2] == Bus1q

        g2[2.1] == gndd
        g2[2.2] == gndq


end
return net
end



function SM_pscad_data()
    function read_pscad_Y(file)
        
        lines = readlines(file)
        validation_data = [split(line) for line in lines[2:end]]

        frequency = real([
            parse(ComplexF64, replace(row[1], "(" => ""))
            for row in validation_data
        ])
        omegas = 2π .* frequency

        matrices = [
            reshape(parse.(ComplexF64, replace.(row[2:end], "(" => "")), 2, 2)
            for row in validation_data
        ]

        return omegas, transpose.(matrices)
    end

   
    files = [joinpath(@__DIR__, "data", "SGvalidation_idealvac_1us#Y_AC#C-AC-1#.txt")]
    omega = Float64[]
    Y_all = Matrix{ComplexF64}[]

    for file in files
            ω_tmp, Y_tmp = read_pscad_Y(file)

            append!(omega, ω_tmp)


            append!(Y_all, Y_tmp)  # frequency dimension
    end

    # Sort by frequency
    idx = sortperm(omega)
    omega = omega[idx]

    # Reorder admittance matrices
    Y_all = Y_all[idx, :, :]

    # Optional: remove duplicate frequencies
    omega_unique, unique_idx = unique(omega), unique(i -> omega[i], eachindex(omega))
    omega = omega[unique_idx]
    Y_all = Y_all[unique_idx, :, :]


    return omega_unique, Y_all
end

@testset "Synchronous machine" begin
    ω, Y_pscad = SM_pscad_data()
    net = synchronousmachinecircuit()
    ## Get admittance at same freq points
    s_vec = ω .* im
    adm_ac = 0 .* Y_pscad
    Ybase = 1000/380^2
    for (i,s) in enumerate(s_vec) 
        adm_ac[i] =  Ybase*PowerImpedance.eval_y(net.elements[:sg1], s)
    end

    
    @test isapprox(adm_ac, Y_pscad, rtol=9e-3)
end
