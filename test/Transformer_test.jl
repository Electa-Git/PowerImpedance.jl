


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
                V₁ᵒ = v1, V₂ᵒ = 150e3 / sqrt(3)))
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

module TransformerVoltageTests
using Test, PowerImpedance, LinearAlgebra, Logging
const P = PowerImpedance
const NB = P.NetworkBuilder

function circuit(windings; voltage_base = 120.0, source_voltage = voltage_base,
        source_bus = 1, load_bus = length(windings) + 1)
    elements = (; source = ac_source(; pins = 3, transformation = true,
        setpoint = Setpoint(Vac = source_voltage * sqrt(2), θac = 0.0)),
        windings..., load = impedance(; z = 500.0, pins = 3, transformation = true))
    rows = [(; node = Symbol("B$(source_bus)$suffix"), element = :source,
        side = 1, terminal) for (terminal, suffix) in enumerate(("d", "q"))]
    for (bus, name) in enumerate(keys(windings)), side in 1:2,
            (terminal, suffix) in enumerate(("d", "q"))
        push!(rows, (; node = Symbol("B$(bus + side - 1)$suffix"),
            element = name, side, terminal))
    end
    for (terminal, suffix) in enumerate(("d", "q"))
        push!(rows, (; node = Symbol("B$(load_bus)$suffix"), element = :load,
            side = 1, terminal))
        push!(rows, (; node = :gnd, element = :load, side = 2, terminal))
    end
    state = NB.define(deepcopy(elements), rows; options = (; voltageBase = voltage_base))
    network = NB.build_network(state.elements, state.topology, state.options)
    return network, state
end

bounds(data, bus) = (data["bus"][string(bus)]["vmin"], data["bus"][string(bus)]["vmax"])

@testset "Transformer SI test data and rated bounds" begin
    primary = 380e3 / sqrt(3)
    secondary = 150e3 / sqrt(3)
    tested = transformer(:tests; pins = 3, transformation = true,
        V₁ᵒ = primary, V₂ᵒ = secondary, I₁ᵒ = 5.0, P₁ᵒ = 100e3,
        V₁ˢ = 0.12 * primary, I₁ˢ = 1500.0, P₁ˢ = 600e3)
    # Independent per-phase OC/SC reference values in V, A, W, Ω and H.
    for (field, expected) in ((:n, 2.533333333333333),
        (:Rₚ, 0.13333333333333333), (:Rₛ, 0.02077562326869806),
        (:Lₚ, 0.02793077303636307), (:Lₛ, 0.004352094136552418),
        (:Rₘ, 481333.3333333334), (:Lₘ, 140.2539753949343))
        @test getproperty(tested.element_model, field) ≈ expected rtol = 1e-12
    end
    network, state = circuit((; winding = tested); voltage_base = primary / 1e3)
    result, data, _, mapping = power_flow(network)
    @test result["termination_status"] == P.MOI.LOCALLY_SOLVED
    branch = data["branch"][string(last(mapping[:winding]))]
    @test collect(bounds(data, branch["f_bus"])) ≈ [0.9, 1.1]
    @test collect(bounds(data, branch["t_bus"])) ≈ [0.9, 1.1] .* (150 / 380)
    builder_data, _, builder_mapping = convert(state, P.PMACDC)
    builder_branch = builder_data["branch"][string(builder_mapping[:winding].compkey)]
    @test bounds(builder_data, builder_branch["f_bus"]) == bounds(data, branch["f_bus"])
    @test bounds(builder_data, builder_branch["t_bus"]) == bounds(data, branch["t_bus"])
end

include("pscad/ieee9_network.jl")

@testset "IEEE9 without transformer ratings" begin
    network = ieee9_network()
    for name in (:t1, :t2, :t3)
        model = network.elements[name].element_model
        model.V₁ᵒ = model.V₂ᵒ = 0.0
    end
    result, data, _, mapping = power_flow(network)
    @test result["termination_status"] == P.MOI.LOCALLY_SOLVED
    for (name, voltage) in ((:g1, 16.5), (:g2, 18.0), (:g3, 13.8))
        generator = data["gen"][string(last(mapping[name]))]
        bus = generator["gen_bus"]
        @test result["solution"]["bus"][string(bus)]["vm"] ≈ voltage / 220 atol = 1e-6
        @test collect(bounds(data, bus)) ≈ [0.9, 1.1] .* (voltage / 220)
    end
    for name in (:t1, :t2, :t3)
        branch = data["branch"][string(last(mapping[name]))]
        @test collect(bounds(data, branch["t_bus"])) ≈ [0.9, 1.1] .* (230 / 220)
    end
end

@testset "Transformer voltage levels propagate through chains" begin
    windings = (; first = transformer(; pins = 3, transformation = true,
        n = 2.0, Rₚ = 0.1, Rₛ = 0.1, Lₚ = 1e-3, Lₛ = 1e-3),
        second = transformer(; pins = 3, transformation = true,
            n = 3.0, Rₚ = 0.1, Rₛ = 0.1, Lₚ = 1e-3, Lₛ = 1e-3))
    network, state = circuit(windings)
    result, data, _, mapping = power_flow(network)
    @test result["termination_status"] == P.MOI.LOCALLY_SOLVED
    first = data["branch"][string(last(mapping[:first]))]
    second = data["branch"][string(last(mapping[:second]))]
    @test bounds(data, first["f_bus"]) == (0.9, 1.1)
    @test bounds(data, first["t_bus"]) == (0.45, 0.55)
    @test bounds(data, second["f_bus"]) == (0.45, 0.55)
    @test bounds(data, second["t_bus"]) == ((20 / 120) * 0.9, (20 / 120) * 1.1)
    builder_data, _, bm = convert(state, P.PMACDC)
    for name in (:first, :second)
        a = data["branch"][string(last(mapping[name]))]
        b = builder_data["branch"][string(bm[name].compkey)]
        @test bounds(data, a["f_bus"]) == bounds(builder_data, b["f_bus"])
        @test bounds(data, a["t_bus"]) == bounds(builder_data, b["t_bus"])
    end

    # A source on the final secondary anchors propagation in the reverse direction.
    _, reverse = circuit(windings; source_voltage = 30.0, source_bus = 3, load_bus = 1)
    reverse_data, levels, rm = convert(reverse, P.PMACDC)
    @test levels["transformer_voltage_levels"][:first] == (180.0, 90.0)
    @test levels["transformer_voltage_levels"][:second] == (90.0, 30.0)
    reverse_branch = reverse_data["branch"][string(rm[:first].compkey)]
    @test bounds(reverse_data, reverse_branch["f_bus"]) == (1.5 * 0.9, 1.5 * 1.1)

    # Voltage control inside the base band does not redefine the nominal level.
    _, in_band = circuit(windings; source_voltage = 126.0)
    _, in_band_levels, _ = convert(in_band, P.PMACDC)
    @test in_band_levels["transformer_voltage_levels"][:first] == (120.0, 60.0)
    @test in_band_levels["transformer_voltage_levels"][:second] == (60.0, 20.0)

    rated = deepcopy(windings)
    rated.first.element_model.V₁ᵒ = 120e3
    rated.first.element_model.V₂ᵒ = 60e3
    _, rated_chain = circuit(rated)
    _, rated_levels, _ = convert(rated_chain, P.PMACDC)
    @test rated_levels["transformer_voltage_levels"][:second] == (60.0, 20.0)

    # The first unreached primary seeds an entire component from the network base.
    unseeded_rows = [(; row.node, row.element, row.side, row.terminal)
                     for row in state.topology.connections]
    for index in eachindex(unseeded_rows)
        row = unseeded_rows[index]
        row.element == :source || continue
        suffix = row.terminal == 1 ? "d" : "q"
        unseeded_rows[index] = merge(row, (; node = Symbol("B4$suffix")))
    end
    unseeded = NB.define(state.elements, unseeded_rows; options = state.options)
    _, unseeded_levels, _ = convert(unseeded, P.PMACDC)
    @test unseeded_levels["transformer_voltage_levels"][:first] == (120.0, 60.0)
    @test unseeded_levels["transformer_voltage_levels"][:second] == (60.0, 20.0)
end

@testset "Unrated transformer behind an AC branch" begin
    winding = transformer(; pins = 3, transformation = true,
        n = 2.0, Rₚ = 0.1, Rₛ = 0.1, Lₚ = 1e-3, Lₛ = 1e-3)
    line = overhead_line(; length = 1e3,
        conductors = Conductors(; organization = :flat, nᵇ = 3, nˢᵇ = 1,
            Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30, Δxᵇᶜ = 10),
        transformation = true)
    series = impedance(; z = 0.1, pins = 3, transformation = true)
    for (feed, source_voltage, primary, secondary) in
            ((line, 120.0, 120.0, 60.0), (series, 30.0, 30.0, 15.0))
        network, state = circuit((; feed, winding); source_voltage)
        result, data, _, mapping = power_flow(network)
        @test result["termination_status"] == P.MOI.LOCALLY_SOLVED
        branch = data["branch"][string(last(mapping[:winding]))]
        @test collect(bounds(data, branch["f_bus"])) ≈ [0.9, 1.1] .* (primary / 120)
        @test collect(bounds(data, branch["t_bus"])) ≈ [0.9, 1.1] .* (secondary / 120)
        @test result["solution"]["bus"][string(branch["t_bus"])]["vm"] ≈
            secondary / 120 rtol = 0.01
        builder_data, levels, bm = convert(state, P.PMACDC)
        @test levels["transformer_voltage_levels"][:winding] == (primary, secondary)
        builder_branch = builder_data["branch"][string(bm[:winding].compkey)]
        @test bounds(builder_data, builder_branch["f_bus"]) == bounds(data, branch["f_bus"])
        @test bounds(builder_data, builder_branch["t_bus"]) == bounds(data, branch["t_bus"])
    end
end

@testset "Source voltage seeds require a finite positive setpoint" begin
    source = ac_source(; pins = 3, transformation = true)
    feed = impedance(; z = 0.1, pins = 3, transformation = true)
    winding = transformer(; pins = 3, transformation = true, n = 2.0)
    winding.symbol = :winding
    for voltage in (missing, NaN, Inf, 0.0, -30.0)
        source.setpoint = Setpoint(; Vac = voltage)
        levels = Dict{String, Any}("V" => 120e3)
        @test_nowarn P._infer_transformer_voltage_levels!(levels,
            [(source, (1,)), (feed, (1, 2)), (winding, (2, 3))])
        @test levels["transformer_voltage_levels"][:winding] == (120.0, 60.0)
    end
end

@testset "Conflicting transformer voltage levels retain the first bound" begin
    _, state = circuit((; first = transformer(; pins = 3, transformation = true,
        n = 2.0, Rₚ = 0.1, Rₛ = 0.1),
        second = transformer(; pins = 3, transformation = true,
            n = 3.0, Rₚ = 0.1, Rₛ = 0.1)))
    # Connect the two transformers in parallel with incompatible nominal ratios.
    rows = [(; row.node, row.element, row.side, row.terminal)
            for row in state.topology.connections if row.element != :load]
    for index in eachindex(rows)
        row = rows[index]
        row.element == :second || continue
        suffix = row.terminal == 1 ? "d" : "q"
        rows[index] = merge(row, (; node = Symbol("B$(row.side)$suffix")))
    end
    conflict = NB.define((; source = state.elements.source,
        first = state.elements.first, second = state.elements.second), rows;
        options = state.options)
    logger = Test.TestLogger(min_level = Logging.Warn)
    data, levels, mapping = with_logger(logger) do
        convert(conflict, P.PMACDC)
    end
    branch = data["branch"][string(mapping[:first].compkey)]
    @test any(log -> occursin("Conflicting transformer voltage levels", string(log.message)) &&
        occursin("bus $(branch["t_bus"])", string(log.message)) &&
        occursin("60.0 kV and 40.0 kV", string(log.message)), logger.logs)
    @test levels["transformer_voltage_levels"][:first] == (120.0, 60.0)
    @test levels["transformer_voltage_levels"][:second] == (120.0, 60.0)
    @test bounds(data, branch["t_bus"]) == (0.45, 0.55)
    @test length(levels["transformer_voltage_bounded_buses"]) == 2
end
end
