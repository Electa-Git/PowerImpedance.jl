
Lₚ=0.1
Lₛ=0.05
Rₚ=10
Rₛ=1
Rᵪ=1e4
Lᵪ=10
n=320/400

omegas = collect(range(2*pi*0.1, stop = 2*pi*5000, step = 10))

ABCD_analytical=[]
ABCD_numerical=[]

winding = transformer(n = n, Lₚ = Lₚ, Rₚ = Rₚ, Rₛ = Rₛ, Rₘ = Rᵪ,
    Lₘ = Lᵪ, Lₛ = Lₛ, conductors = 3)

for i in eachindex(omegas)
    ω=omegas[i]

    Z_p=[Rₚ+1im*ω*Lₚ 0 0;
         0 Rₚ+1im*ω*Lₚ 0;
         0 0 Rₚ+1im*ω*Lₚ]

    ABCD_p=[Diagonal([1, 1, 1]) Z_p;
            zeros(3, 3) Diagonal([1, 1, 1])]

    Z_s=[Rₛ+1im*ω*Lₛ 0 0;
         0 Rₛ+1im*ω*Lₛ 0;
         0 0 Rₛ+1im*ω*Lₛ]

    ABCD_s=[Diagonal([1, 1, 1]) Z_s;
            zeros(3, 3) Diagonal([1, 1, 1])]

    Y_core=[(1/Rᵪ + 1/(1im*ω*Lᵪ)) 0 0;
            0 (1/Rᵪ + 1/(1im*ω*Lᵪ)) 0;
            0 0 (1/Rᵪ + 1/(1im*ω*Lᵪ))]

    ABCD_core=[Diagonal([1, 1, 1]) zeros(3, 3);
               Y_core Diagonal([1, 1, 1])]

    ABCD_n=[Diagonal([n, n, n]) zeros(3, 3);
            zeros(3, 3) Diagonal([1/n, 1/n, 1/n])]

    # Analytical transformer model
    push!(ABCD_analytical, ABCD_p*ABCD_core*ABCD_n*ABCD_s)
    push!(ABCD_numerical, PowerImpedance.eval_abcd(winding, 1im*ω))
end

for index in eachindex(omegas)
    @test ABCD_analytical[index]≈ABCD_numerical[index] rtol=1e-9 atol=1e-9
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

        elements = (; source = ac_source(v = v1 * sqrt(2) / 1e3, theta = 0.0),
            transformer = transformer(n = ratio, Rₚ = 10, Lₚ = 0.1,
                Rₛ = 1, Lₛ = 0.05, Rₘ = rm, Lₘ = lm, conductors = 3,
                organization = organization, V₁ᵒ = v1, V₂ᵒ = 150e3 / sqrt(3)),
            load = impedance(z = load, conductors = 3))
        topology = (
            NetworkBuilder.Bus(
                :primary_; ports = ((:source, :ac),
                    (:transformer, :side1)), domain = ACDQ),
            NetworkBuilder.Bus(
                :secondary_; ports = ((:transformer, :side2),
                    (:load, :side1)),
                domain = ACDQ),
            NetworkBuilder.Bus(:gnd; ports = ((:load, :side2),), domain = ACDQ))
        state = NetworkBuilder.define(elements, topology;
            options = (; voltageBase = v1 / 1e3))
        powerflow = compute(PowerFlowProblem(state), ACDCPowerFlow())
        result, data = powerflow.result, powerflow.data
        index = powerflow.elem2comp[:transformer].compkey
        branch = data["branch"][string(index)]
        @test branch["tap"] == ratio
        @test branch["shift"] == shift
        @test result["termination_status"] == PowerImpedance.MOI.LOCALLY_SOLVED

        # Test-only precision isolates the branch model from the public solver's
        # loose convergence settings, which also serve larger hybrid networks.
        optimizer = PowerImpedance.JuMP.optimizer_with_attributes(
            PowerImpedance.Ipopt.Optimizer, "tol" => 1e-10,
            "constr_viol_tol" => 1e-10, "print_level" => 0)
        precise = NetworkBuilder.solve_acdcpf(data, PowerImpedance._PM.ACPPowerModel,
            optimizer, (;); setting = Dict("output" => Dict("branch_flows" => true)))
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
            # Eliminating the excitation node gives the unshifted two-port. Comparison
            # with the pi approximation measures its error against that reduction.
            diagonal = 1 / zp + ym + 1 / (ratio^2 * zs)
            base_z = PowerImpedance.PowerModelsACDC._get_pu_bases(1000,
                state.options.voltageBase)["Z"]
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
    elements = (; source = ac_source(v = source_voltage * sqrt(2), theta = 0.0),
        windings..., load = impedance(z = 500.0, conductors = 3))
    rows = [NB.Bus(Symbol("B$source_bus"); ports = ((:source, :ac),), domain = ACDQ)]
    for (bus, name) in enumerate(keys(windings))
        push!(rows, NB.Bus(Symbol("B$bus"); ports = ((name, :side1),), domain = ACDQ))
        push!(rows, NB.Bus(Symbol("B$(bus + 1)"); ports = ((name, :side2),), domain = ACDQ))
    end
    push!(rows, NB.Bus(Symbol("B$load_bus"); ports = ((:load, :side1),), domain = ACDQ))
    push!(rows, NB.Bus(:gnd; ports = ((:load, :side2),), domain = ACDQ))
    state = NB.define(deepcopy(elements), rows; options = (; voltageBase = voltage_base))
    return state, (; elements, rows)
end

bounds(data, bus) = (data["bus"][string(bus)]["vmin"], data["bus"][string(bus)]["vmax"])

@testset "Transformer SI test data and rated bounds" begin
    primary = 380e3 / sqrt(3)
    secondary = 150e3 / sqrt(3)
    tested = transformer(:tests; conductors = 3,
        V₁ᵒ = primary, V₂ᵒ = secondary, I₁ᵒ = 5.0, P₁ᵒ = 100e3,
        V₁ˢ = 0.12 * primary, I₁ˢ = 1500.0, P₁ˢ = 600e3)
    # Independent per-phase OC/SC reference values in V, A, W, Ω and H.
    for (field, expected) in ((:n, 2.533333333333333),
        (:Rₚ, 0.13333333333333333), (:Rₛ, 0.02077562326869806),
        (:Lₚ, 0.02793077303636307), (:Lₛ, 0.004352094136552418),
        (:Rₘ, 481333.3333333334), (:Lₘ, 140.2539753949343))
        @test getproperty(tested, field) ≈ expected rtol = 1e-12
    end
    state, original = circuit((; winding = tested); voltage_base = primary / 1e3)
    data, _, mapping = convert(state, P.PMACDC)
    result = NB.solve_acdcpf(data, P._PM.ACPPowerModel,
        NB.powerflow_optimizer(state.options), NB.is_bounded_options(state.options);
        setting = NB.powerflow_setting(state.options))
    @test result["termination_status"] == P.MOI.LOCALLY_SOLVED
    branch = data["branch"][string(mapping[:winding].compkey)]
    @test collect(bounds(data, branch["f_bus"])) ≈ [0.9, 1.1]
    @test collect(bounds(data, branch["t_bus"])) ≈ [0.9, 1.1] .* (150 / 380)
end

include("pscad/ieee9_network.jl")

@testset "IEEE9 without transformer ratings" begin
    network = ieee9_network()
    for name in (:t1, :t2, :t3)
        model = network.elements[name]
        model.V₁ᵒ = model.V₂ᵒ = 0.0
    end
    powerflow = compute(PowerFlowProblem(network), ACDCPowerFlow())
    result, data, mapping = powerflow.result, powerflow.data, powerflow.elem2comp
    @test result["termination_status"] == P.MOI.LOCALLY_SOLVED
    for (name, voltage) in ((:g1, 16.5), (:g2, 18.0), (:g3, 13.8))
        generator = data["gen"][string(mapping[name].compkey)]
        bus = generator["gen_bus"]
        @test result["solution"]["bus"][string(bus)]["vm"] ≈ voltage / 220 atol = 1e-6
        @test collect(bounds(data, bus)) ≈ [0.9, 1.1] .* (voltage / 220)
    end
    for name in (:t1, :t2, :t3)
        branch = data["branch"][string(mapping[name].compkey)]
        @test collect(bounds(data, branch["t_bus"])) ≈ [0.9, 1.1] .* (230 / 220)
    end
end

@testset "Transformer voltage levels propagate through chains" begin
    windings = (;
        first = transformer(; conductors = 3,
            n = 2.0, Rₚ = 0.1, Rₛ = 0.1, Lₚ = 1e-3, Lₛ = 1e-3),
        second = transformer(; conductors = 3,
            n = 3.0, Rₚ = 0.1, Rₛ = 0.1, Lₚ = 1e-3, Lₛ = 1e-3))
    state, original = circuit(windings)
    data, _, mapping = convert(state, P.PMACDC)
    result = NB.solve_acdcpf(data, P._PM.ACPPowerModel,
        NB.powerflow_optimizer(state.options), NB.is_bounded_options(state.options);
        setting = NB.powerflow_setting(state.options))
    @test result["termination_status"] == P.MOI.LOCALLY_SOLVED
    first = data["branch"][string(mapping[:first].compkey)]
    second = data["branch"][string(mapping[:second].compkey)]
    @test bounds(data, first["f_bus"]) == (0.9, 1.1)
    @test bounds(data, first["t_bus"]) == (0.45, 0.55)
    @test bounds(data, second["f_bus"]) == (0.45, 0.55)
    @test bounds(data, second["t_bus"]) == ((20 / 120) * 0.9, (20 / 120) * 1.1)
    # A source on the final secondary anchors propagation in the reverse direction.
    reverse, _ = circuit(windings; source_voltage = 30.0, source_bus = 3, load_bus = 1)
    reverse_data, levels, rm = convert(reverse, P.PMACDC)
    @test levels["transformer_voltage_levels"][:first] == (180.0, 90.0)
    @test levels["transformer_voltage_levels"][:second] == (90.0, 30.0)
    reverse_branch = reverse_data["branch"][string(rm[:first].compkey)]
    @test bounds(reverse_data, reverse_branch["f_bus"]) == (1.5 * 0.9, 1.5 * 1.1)

    # Voltage control inside the base band does not redefine the nominal level.
    in_band, _ = circuit(windings; source_voltage = 126.0)
    _, in_band_levels, _ = convert(in_band, P.PMACDC)
    @test in_band_levels["transformer_voltage_levels"][:first] == (120.0, 60.0)
    @test in_band_levels["transformer_voltage_levels"][:second] == (60.0, 20.0)

    rated = deepcopy(windings)
    rated.first.V₁ᵒ = 120e3
    rated.first.V₂ᵒ = 60e3
    rated_chain, _ = circuit(rated)
    _, rated_levels, _ = convert(rated_chain, P.PMACDC)
    @test rated_levels["transformer_voltage_levels"][:second] == (60.0, 20.0)

    # The first unreached primary seeds an entire component from the network base.
    unseeded_rows = copy(original.rows)
    unseeded_rows[1] = NB.Bus(:B4; ports = ((:source, :ac),), domain = ACDQ)
    unseeded = NB.define(original.elements, unseeded_rows; options = state.options)
    _, unseeded_levels, _ = convert(unseeded, P.PMACDC)
    @test unseeded_levels["transformer_voltage_levels"][:first] == (120.0, 60.0)
    @test unseeded_levels["transformer_voltage_levels"][:second] == (60.0, 20.0)
end

@testset "Unrated transformer behind an AC branch" begin
    winding = transformer(; conductors = 3,
        n = 2.0, Rₚ = 0.1, Rₛ = 0.1, Lₚ = 1e-3, Lₛ = 1e-3)
    line = overhead_line(; length = 1e3,
        conductors = Conductors(; organization = :flat, nᵇ = 3, nˢᵇ = 1,
            Rᵈᶜ = 0.063, rᶜ = 0.015, yᵇᶜ = 30, Δxᵇᶜ = 10))
    series = impedance(; z = 0.1, conductors = 3)
    for (feed, source_voltage, primary, secondary) in
        ((line, 120.0, 120.0, 60.0), (series, 30.0, 30.0, 15.0))
        state, original = circuit((; feed, winding); source_voltage)
        data, _, mapping = convert(state, P.PMACDC)
        result = NB.solve_acdcpf(data, P._PM.ACPPowerModel,
            NB.powerflow_optimizer(state.options), NB.is_bounded_options(state.options);
            setting = NB.powerflow_setting(state.options))
        @test result["termination_status"] == P.MOI.LOCALLY_SOLVED
        branch = data["branch"][string(mapping[:winding].compkey)]
        @test collect(bounds(data, branch["f_bus"])) ≈ [0.9, 1.1] .* (primary / 120)
        @test collect(bounds(data, branch["t_bus"])) ≈ [0.9, 1.1] .* (secondary / 120)
        @test result["solution"]["bus"][string(branch["t_bus"])]["vm"] ≈
              secondary / 120 rtol = 0.01
        _, levels, _ = convert(state, P.PMACDC)
        @test levels["transformer_voltage_levels"][:winding] == (primary, secondary)
    end
end

@testset "Source voltage seeds require a finite positive input" begin
    feed = impedance(z = 0.1, conductors = 3)
    winding = transformer(conductors = 3, n = 2.0)
    for voltage in (NaN, Inf, 0.0, -30.0)
        source = ac_source(v = voltage)
        levels = Dict{String, Any}("V" => 120e3)
        records = [
            (; name = :source, model = source, ports = (ac = 1,), pmtype = "gen"),
            (; name = :feed, model = feed, ports = (side1 = 1, side2 = 2),
                pmtype = "branch"),
            (; name = :winding, model = winding, ports = (side1 = 2, side2 = 3),
                pmtype = "branch")]
        @test_nowarn NB._infer_transformer_voltage_levels!(levels, records)
        @test levels["transformer_voltage_levels"][:winding] == (120.0, 60.0)
    end
end

@testset "Conflicting transformer voltage levels retain the first bound" begin
    state,
    _ = circuit((; first = transformer(; conductors = 3,
            n = 2.0, Rₚ = 0.1, Rₛ = 0.1),
        second = transformer(; conductors = 3,
            n = 3.0, Rₚ = 0.1, Rₛ = 0.1)))
    # Connect the two transformers in parallel with incompatible nominal ratios.
    conflict = NB.define(
        (; source = state.elements.source,
            first = state.elements.first, second = state.elements.second),
        (
            NB.Bus(:B1; ports = ((:source, :ac), (:first, :side1), (:second, :side1)),
                domain = ACDQ),
            NB.Bus(:B2; ports = ((:first, :side2), (:second, :side2)), domain = ACDQ)
        );
        options = state.options)
    logger = Test.TestLogger(min_level = Logging.Warn)
    data, levels, mapping = with_logger(logger) do
        convert(conflict, P.PMACDC)
    end
    branch = data["branch"][string(mapping[:first].compkey)]
    @test any(
        log -> occursin("Conflicting transformer voltage levels",
                   string(log.message)) &&
               occursin("bus $(branch["t_bus"])", string(log.message)) &&
               occursin("60.0 kV and 40.0 kV", string(log.message)),
        logger.logs)
    @test levels["transformer_voltage_levels"][:first] == (120.0, 60.0)
    @test levels["transformer_voltage_levels"][:second] == (120.0, 60.0)
    @test bounds(data, branch["t_bus"]) == (0.45, 0.55)
    @test length(levels["transformer_voltage_bounded_buses"]) == 2
end
end
