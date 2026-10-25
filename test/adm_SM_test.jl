function synchronousmachinecircuit()
    # Values used in the SG validation
    voltage = 380 / sqrt(3)
    machine = synchronousmachine(elec = ElectricalSM(Vᵃᶜ_base = 380.0))
    b = bases(machine)
    elements = (;
        sg1 = component(machine; powerflow = (p = 900 / b.S,
            v = 1.000177992 * voltage * sqrt(2) / b.v_ac)),
        g2 = ac_source(v = voltage * sqrt(2)))
    topology = (NetworkBuilder.Bus(:Bus2; ports = ((:sg1, :ac), (:g2, :ac)),
        domain = ACDQ),)
    state = NetworkBuilder.define(elements, topology; options = (; voltageBase = voltage))
    result = compute(PowerFlowProblem(state), ACDCPowerFlow())
    linearize(state.elements.sg1, result.operating_point[:sg1])
    return state
end

function sm_y(machine, s)
    A, B, C, D = machine.cache.A, machine.cache.B, machine.cache.C, machine.cache.D
    return C * ((s * I - A) \ B) + D
end

function SM_pscad_data()
    function read_pscad_Y(file)
        lines = readlines(file)
        validation_data = [split(line) for line in lines[2:end]]

        frequency = real([parse(ComplexF64, replace(row[1], "(" => ""))
                          for row in validation_data])
        omegas = 2π .* frequency

        matrices = [reshape(parse.(ComplexF64, replace.(row[2:end], "(" => "")), 2, 2)
                    for row in validation_data]

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
    for (i, s) in enumerate(s_vec)
        adm_ac[i] = Ybase*sm_y(net.elements[:sg1], s)
    end

    @test isapprox(adm_ac, Y_pscad, rtol = 9e-3)
end

@testset "Synchronous machine network admittance scaling" begin
    net = synchronousmachinecircuit()
    machine = net.elements[:sg1]
    state = NetworkBuilder.define(
        (sg1 = machine, grid = net.elements[:g2],
            load = impedance(z = 100.0, conductors = 3)),
        (
            NetworkBuilder.Bus(:bus_; ports = ((:sg1, :ac), (:grid, :ac), (:load, :side1)),
                domain = ACDQ),
            NetworkBuilder.Bus(:gnd; ports = ((:load, :side2),), domain = ACDQ)))
    point = OperatingPoint(Dict(:sg1 => machine.cache.values))
    model = NetworkBuilder.NetworkModel(state, point)
    frequencies = 2π * im .* [1.0, 10.0, 100.0]
    admittance = NetworkBuilder.get_y(model, :sg1, frequencies)
    Ybase = 1000 / 380^2
    for (index, s) in enumerate(frequencies)
        @test admittance[:, :, index] ≈ Ybase * sm_y(machine, s) rtol = 1e-10
    end
end
