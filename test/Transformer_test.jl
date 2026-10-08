


Lₚ=0.1
Lₛ=0.05
Rₚ=10
Rₛ=1
Rᵪ=1e4
Lᵪ=10
n=320/400

omegas = collect(range(2*pi*0.1, stop=2*pi*5000, step=10))

ABCD_analytical=[]
ABCD_numerical=[]


grid = Network()

add!(
	grid,
	:labanimal,
    transformer(n = n , Lₚ = Lₚ, Rₚ = Rₚ, Rₛ = Rₛ, Rₘ = Rᵪ, Lₘ = Lᵪ,
    Lₛ = Lₛ,
    pins = 3, transformation = true)
)





for i in eachindex(omegas)

    ω=omegas[i]

    Z_p=[Rₚ+1im*ω*Lₚ 0 0;
      0 Rₚ+1im*ω*Lₚ 0;
      0 0 Rₚ+1im*ω*Lₚ]

    ABCD_p=[Diagonal([1,1,1]) Z_p;
      zeros(3,3) Diagonal([1,1,1])]   

    Z_s=[Rₛ+1im*ω*Lₛ 0 0;
      0 Rₛ+1im*ω*Lₛ 0;
      0 0 Rₛ+1im*ω*Lₛ]

    ABCD_s=[Diagonal([1,1,1]) Z_s;
      zeros(3,3) Diagonal([1,1,1])]

    Y_core=[ (1/Rᵪ + 1/(1im*ω*Lᵪ)) 0 0;
             0 (1/Rᵪ + 1/(1im*ω*Lᵪ)) 0;
             0 0 (1/Rᵪ + 1/(1im*ω*Lᵪ))]

    ABCD_core=[Diagonal([1,1,1]) zeros(3,3);
               Y_core Diagonal([1,1,1])]


    ABCD_n=[Diagonal([n,n,n]) zeros(3,3);
            zeros(3,3) Diagonal([1/n,1/n,1/n])]

    # Analytical transformer model
    push!(ABCD_analytical, ABCD_p*ABCD_core*ABCD_n*ABCD_s)
    push!(ABCD_numerical, PowerImpedance.eval_abcd(grid.elements[:labanimal].element_model, 1im*ω))




end


for index in eachindex(omegas)
       
    @test ABCD_analytical[index] ≈ ABCD_numerical[index] rtol = 1e-9 atol = 1e-9
    
end




@testset "Exact transformer pi power flow" begin
    for organization in (:YY, :ΔY), realistic in (false, true)

        ratio = 380 / 150
        zp = 10 + 100π * 0.1im
        zs = 1 + 100π * 0.05im
        rm, lm = realistic ? (1e6, 1000.0) : (1e4, 10.0)
        ym = 1 / rm + 1 / (100π * lm * im)
        shift = organization == :ΔY ? -π / 6 : 0.0
        winding_ratio = ratio * cis(shift)
        v1 = 380e3 / sqrt(3)
        load = 400.0

        # KCL at the primary excitation node and secondary load node.
        # This circuit solve does not use ABCD or the pi conversion.
        nodal = ComplexF64[1/zp+ym+1/(ratio^2*zs) -1/(conj(winding_ratio)*zs);
                           -1/(winding_ratio*zs) 1/zs+1/load]
        excitation, v2 = nodal \ ComplexF64[v1 / zp, 0]
        i1 = (v1 - excitation) / zp
        expected_from = 3v1 * conj(i1) / 1e9
        expected_to = -3abs2(v2) / load / 1e9

        net = Network()
        net.voltageBase[1] = v1 / 1e3
        add!(net,
            :source,
            ac_source(pins = 3, transformation = true,
                setpoint = Setpoint(Vac = v1 * sqrt(2) / 1e3, θac = 0.0)))
        add!(net,
            :transformer,
            transformer(n = ratio, Rₚ = 10, Lₚ = 0.1,
                Rₛ = 1, Lₛ = 0.05, Rₘ = rm, Lₘ = lm, pins = 3,
                organization = organization, transformation = true,
                V₁ᵒ = v1 / 1e3, V₂ᵒ = 150 / sqrt(3)))
        add!(net, :load, impedance(z = load, pins = 3, transformation = true))
        for k in 1:2
            primary, secondary, ground = Symbol.(("primary_$k", "secondary_$k", "gnd_$k"))
            for (element, side, node) in ((:source, 1, primary), (:source, 2, ground),
                (:transformer, 1, primary), (:transformer, 2, secondary),
                (:load, 1, secondary), (:load, 2, ground))
                connect!(net, (element, Symbol("$side.$k")), node)
            end
        end
        connect!(net)
        result, data, _, components = power_flow(net)
        _, index = components[:transformer]
        branch = data["branch"][string(index)]
        @test branch["tap"] == ratio
        @test branch["shift"] == shift
        @test result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED

        # Test-only precision isolates the branch model from the public solver's
        # loose convergence settings, which also serve larger hybrid networks.
        optimizer = PowerImpedance.JuMP.optimizer_with_attributes(
            PowerImpedance.Ipopt.Optimizer, "tol" => 1e-10,
            "constr_viol_tol" => 1e-10, "print_level" => 0)
        precise = PowerImpedance.solve_acdcpf(data, PowerImpedance._PM.ACPPowerModel,
            optimizer; setting = Dict("output" => Dict("branch_flows" => true)))
        @test precise["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED
        bus = precise["solution"]["bus"][string(branch["t_bus"])]
        solved_v2 = bus["vm"] * v1 * cis(bus["va"])
        flow = precise["solution"]["branch"][string(index)]
        solved_from = flow["pf"] + im * flow["qf"]
        @test solved_v2 ≈ v2 rtol = 1e-6
        @test conj(solved_from * 1e9 / (3v1)) ≈ i1 rtol = 1e-6
        @test solved_from ≈ expected_from rtol = 1e-6
        @test flow["pt"] ≈ expected_to rtol = 1e-6
        @test abs(flow["qt"]) < 1e-10

        if realistic
            # Eliminate the excitation node to obtain the unshifted two-port,
            # then reproduce the previous approximation for an error comparison.
            diagonal = 1 / zp + ym + 1 / (ratio^2 * zs)
            base_z = PowerImpedance.PowerModelsACDC._get_pu_bases(1000,
                net.voltageBase[1])["Z"]
            y11 = (1 / zp - 1 / (zp^2 * diagonal)) * base_z
            y12 = -base_z / (zp * ratio * zs * diagonal)
            y22 = (1 / zs - 1 / (ratio^2 * zs^2 * diagonal)) * base_z
            old_tap = sqrt(real(y22 / y11))
            old_series = -y12 * old_tap
            old_shunt = (y22 - old_series) / 2
            old_y21 = -old_series / (old_tap * cis(shift))
            old_y22 = old_series + old_shunt
            old_v2 = -old_y21 * v1 / (old_y22 + base_z / load)
            old_y11 = (old_series + old_shunt) / old_tap^2
            old_y12 = -old_series / (old_tap * cis(-shift))
            old_i1 = (old_y11 * v1 + old_y12 * old_v2) / base_z
            for (corrected, previous, exact) in ((solved_v2, old_v2, v2),
                (conj(solved_from * 1e9 / (3v1)), old_i1, i1))
                previous_error = abs(previous - exact)
                @test abs(corrected - exact) < previous_error
                @test abs(corrected - previous) <= previous_error + abs(corrected - exact)
                @test previous_error / abs(exact) < 0.01
            end
        end
    end
end
