import PowerImpedanceACDC.NetworkBuilder: ⟷, pin
function inductionmachinecircuit()
    transmissionVoltage = 220 / sqrt(3)
    g1 = ac_source(setpoint=Setpoint(Vac = transmissionVoltage, Pac = -500), pins = 3, transformation = true)
            
    im1 = inductionmachine(;mech=MechanicalIM(T_0=0.9,A=0.0,B=0.00,C=1.0,m=0),
                                    elec = ElectricalIM(r_s = 0.01))
    
    imp = impedance(z = 0.01, pins = 3, transformation = true)

    elements = (;g1,im1,imp)

    connections = (
            pin(:im1, 1.1) ⟷ pin(:imp, 1.1),
            pin(:im1, 1.2) ⟷ pin(:imp, 1.2),

            pin(:imp, 2.1) ⟷ pin(:g1, 1.1),
            pin(:imp, 2.2) ⟷ pin(:g1, 1.2),

            pin(:g1, 2.1) ⟷ :gndd,
            pin(:g1, 2.2) ⟷ :gndq,
            pin(:im1, 2.1) ⟷ :gndd,
            pin(:im1, 2.2) ⟷ :gndq,
    )

    builder_options = (;
            voltageBase = transmissionVoltage,
            power_flow = (;
                is_bounded = (;
                    bus_voltage = true,
                ),
            ),
        )
    builder = NetworkBuilder.define(
            elements,
            connections;
            options = builder_options,
        )


    linearizedadmittancenetwork = convert(builder, NB.LinearizedAdmittanceNetwork) 

    return linearizedadmittancenetwork
end


function read_im_validation_data()
    
    path = joinpath(@__DIR__, "data", "IM_Ztool_1us#Y_AC#-1#.txt")
    lines = readlines(path)
    validation_data = [split(line) for line in lines[2:end]]

    frequency = real([
        parse(ComplexF64, replace(row[1], "(" => ""))
        for row in validation_data
    ])
    omegas = 2π .* frequency

    matrices = cat([
        transpose(reshape(parse.(ComplexF64, replace.(row[2:end], "(" => "")), 2, 2))
        for row in validation_data
    ]...;dims=3)

    return omegas, (matrices)
end

@testset "Induction machine" begin
    
    ω, Y_pscad = read_im_validation_data()
    lnnw = inductionmachinecircuit()
    ## Get admittance at same freq points
    s = ω .* im
    Y_im = NB.get_y(lnnw, :im1, s)
    
    @test isapprox(Y_im, Y_pscad, rtol=1e-3,atol=1e-6)

end




