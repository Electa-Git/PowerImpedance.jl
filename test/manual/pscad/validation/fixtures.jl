# The registry is a catalogue of frozen physical circuits, not a dispatch layer.
# L2 grid-strength variants and L3/L4 circuits are deliberately not constructed here.
const REGISTRY = [
    (id = "L1-01", description = "AC series/parallel RLC; RL two-source witness",
        parent = "M1 small_ac_network", factory = () -> ac_rl_network(),
        topology = "ideal AC source — RL branch — ideal AC source",
        physics = ["R/L energy and loss", "dq coupling", "clamped two-port reduction"],
        dissipativity = "R=20 Ω damps every branch-current mode; both port voltages are prescribed",
        differences = String[], tiers = ["A", "C"], estimated_nodes = 30),
    (id = "L1-02", description = "DC two-terminal RLC",
        parent = "M2 dc_network", factory = () -> dc_rlc_network(),
        topology = "two DC sources — differential RL and parallel RC sections; AC slack island",
        physics = ["pole scaling", "DC loss", "capacitive charging"],
        dissipativity = "positive series and parallel resistance; no isolated lossless storage",
        differences = ["DM midpoint references: two 10 MΩ pole shunts, 20 MΩ differential path"],
        tiers = ["A", "C"], estimated_nodes = 32),
    (id = "L1-03", description = "AC overhead line",
        parent = "M1 passive_ohl_network", factory = () -> PSCADFixtures.passive_ohl_network().classic,
        topology = "AC source — 25 km OHL — resistive load",
        physics = ["earth return", "propagation", "phase ordering"],
        dissipativity = "positive conductor/earth loss and resistive termination",
        differences = ["PSCAD rational line/earth fit versus native evaluation; retain fit settings/results"],
        tiers = ["A", "C"], estimated_nodes = 36),
    (id = "L1-04", description = "AC coaxial cable",
        parent = "M2 dc_cable_network geometry + M1 AC topology", factory = () -> ac_cable_network(),
        topology = "AC source — three underground coaxial cores — resistive load",
        physics = ["dielectric charging", "eliminated sheaths", "AC core ordering"],
        dissipativity = "positive conductor/earth loss and resistive termination",
        differences = ["PSCAD rational cable/earth fit and grounded conductor elimination; quantify before C"],
        tiers = ["A", "C"], estimated_nodes = 40),
    (id = "L1-05", description = "DC cable + DC overhead line",
        parent = "M2 dc_cable_network + M7 dc_ohl_test geometry", factory = () -> dc_mixed_network(),
        topology = "DC source — 25 km cable — 75 km DC OHL — DC source; AC slack island",
        physics = ["mixed-medium reflection", "DC fit", "differential order"],
        dissipativity = "positive conductor/earth loss in both source-terminated sections",
        differences = [
            "DC line/cable fits start at 0.001 Hz, DCenab=0; DC and broadband errors require measurement",
            "DM midpoint references: two 10 MΩ pole shunts, 20 MΩ differential path"],
        tiers = ["A", "C"], estimated_nodes = 40),
    (id = "L1-06", description = "YY transformer",
        parent = "M1 transformer_network", factory = () -> PSCADFixtures.transformer_network().classic,
        topology = "AC source — YY T model — resistive load",
        physics = ["turns ratio", "magnetizing current", "T-model response"],
        dissipativity = "positive winding/magnetizing resistance and resistive load",
        differences = ["YY leakage 1e-4 pu and excitation 1e-3 percent",
            "power-flow approximation versus explicit T model"], tiers = ["A", "C"], estimated_nodes = 48),
    (id = "L1-07", description = "Dyn11 transformer",
        parent = "M2 transformer_network(:ΔY)",
        factory = () -> PSCADFixtures.transformer_network(organization = :ΔY).classic,
        topology = "AC source — Dyn11 T model — resistive load",
        physics = ["+30 degree secondary shift", "turns ratio", "winding loss"],
        dissipativity = "positive winding/magnetizing resistance and resistive load",
        differences = ["power-flow approximation versus explicit Dyn11 T model"],
        tiers = ["A", "C"], estimated_nodes = 48),
    (id = "L1-08", description = "IEEE9 passive system anchor",
        parent = "M7 ieee9_network", factory = PSCADFixtures.ieee9_network,
        topology = "3 ideal AC sources, 3 YY transformers, 6 OHL, 3 impedance loads",
        physics = ["network assembly", "multi-bus reduction", "voltage levels"],
        dissipativity = "lossy lines and resistive loads terminate the lossless transformer storage",
        differences = ["YY winding regularization", "rational line/earth fits",
            "power-flow approximation versus explicit transformer T/capacitance model"],
        tiers = ["A", "C"], estimated_nodes = 78)
]

function fixture(id)
    index = findfirst(entry -> entry.id == id, REGISTRY)
    index === nothing && throw(ArgumentError("unknown fixture $id"))
    return REGISTRY[index]
end

function ac_rl_network()
    voltage = 380 / sqrt(3)
    net = Network()
    net.voltageBase[1] = voltage
    add!(net,
        :grid_a,
        ac_source(pins = 3, transformation = true,
            setpoint = Setpoint(Vac = voltage * sqrt(2), θac = 0.0)))
    add!(net,
        :grid_b,
        ac_source(pins = 3, transformation = true,
            setpoint = Setpoint(Vac = 0.98voltage * sqrt(2), θac = -0.01)))
    add!(net, :branch, impedance(z = s -> 20.0 + 0.05s, pins = 3, transformation = true))
    for (terminal, axis) in enumerate(("d", "q"))
        for (element, side, bus) in ((:grid_a, 1, "A"), (:grid_b, 1, "B"),
            (:branch, 1, "A"), (:branch, 2, "B"))
            connect!(net, (element, Symbol("$side.$terminal")), Symbol(bus * axis))
        end
        for source in (:grid_a, :grid_b)
            connect!(net, (source, Symbol("2.$terminal")), Symbol("gnd" * axis))
        end
    end
    connect!(net)
    return net
end

# Construct the intended extension with existing add!/connect! operations.
# Replaying connectivity avoids merging the original D2 source net into DM.
function dc_sections_parent(parent)
    net = Network()
    net.voltageBase .= parent.voltageBase
    for (name, element) in parent.elements
        add!(net, name, deepcopy(element))
    end
    for (node, pins) in parent.nets, pin in pins

        target = pin == (:line, Symbol("2.1")) ? :DM : node
        connect!(net, pin, target)
    end
    connect!(net)
    return net
end

function dc_rlc_network()
    net = dc_sections_parent(PSCADFixtures.dc_network().classic)
    # Keep RL and parallel RC as separate supported scalar realizations.
    add!(net, :rc, impedance(z = s -> inv(1 / 10.0 + 1e-6s), pins = 1))
    connect!(net, (:rc, Symbol("1.1")), :DM)
    connect!(net, (:rc, Symbol("2.1")), :D2)
    connect!(net)
    return net
end

function ac_cable_network()
    net = PSCADFixtures.small_ac_network().classic
    replacement = deepcopy(PSCADFixtures.dc_cable_network().classic.elements[:line])
    replacement.element_model.positions = [(-0.5, 1.0), (0.0, 1.0), (0.5, 1.0)]
    replacement.pins = copy(net.elements[:line].pins)
    replacement.input_pins = net.elements[:line].input_pins
    replacement.output_pins = net.elements[:line].output_pins
    net.elements[:line] = replacement
    return net
end

function dc_mixed_network()
    net = dc_sections_parent(PSCADFixtures.dc_cable_network().classic)
    net.elements[:line].element_model.length = 25e3
    ohl = overhead_line(length = 75e3,
        conductors = Conductors(organization = :flat, nᵇ = 2, nˢᵇ = 1,
            Rᵈᶜ = 0.0266, rᶜ = 0.0224, yᵇᶜ = 18.0, Δxᵇᶜ = 7.3, dˢᵃᵍ = 6.0),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062,
            Δxᵍ = 7.3, Δyᵍ = 7.0, dᵍˢᵃᵍ = 6.0),
        earth_parameters = (1, 1, 100), transformation = true)
    add!(net, :ohl, ohl)
    connect!(net, (:ohl, Symbol("1.1")), :DM)
    connect!(net, (:ohl, Symbol("2.1")), :D2)
    connect!(net)
    return net
end

function passive_gate(net, entry)
    evidence = String[]
    for (name, element) in net.elements
        model = element.element_model
        if model isa PowerImpedance.Source
            continue
        elseif model isa PowerImpedance.Impedance
            form = P.identify_rlc(element; name).form
            form.R !== nothing && form.R > 0 || error("$name has no positive dissipation")
            all(x -> x === nothing || x > 0, (form.L, form.C)) ||
                error("invalid storage in $name")
        elseif model isa PowerImpedance.Overhead_line
            model.conductors.Rᵈᶜ > 0 || error("nonpositive conductor loss in $name")
        elseif model isa PowerImpedance.Cable
            all(c -> c.ρ > 0, values(model.conductors)) ||
                error("nonpositive cable loss in $name")
        elseif model isa PowerImpedance.Transformer
            si = P.transformer_si(model)
            all(>=(0), (si.R_p, si.R_s, si.R_m, si.L_p, si.L_s, si.L_m, si.C_t, si.C_s)) ||
                error("nonpassive transformer $name")
        else
            error("dissipativity rule does not admit $(typeof(model))")
        end
        push!(evidence, string(name, ": ", typeof(model)))
    end
    return Dict("method" => "dissipativity", "status" => "passed",
        "reason" => entry.dissipativity, "elements" => evidence,
        "scope" => "registered source-terminated passive topology; no active-device inference")
end

function l1_settings()
    frequencies = unique(sort!([round.(Int, exp10.(range(0, 3; length = 25))); 50]))
    n = length(frequencies)
    phases = [-π * k * (k - 1) / n for k in 1:n]
    return (frequencies = Float64.(frequencies), phases = phases,
        tone_peak_pu = 5e-5, injection_time = 0.5, window_starts = (1.0, 2.0),
        window_duration = 1.0, simulation_time = 3.0,
        time_step = 2e-6, sample_step = 10e-6, frequency = 50.0,
        voltage_base_kV = 380sqrt(2 / 3),
        current_base_kA = 1000sqrt(2) / (sqrt(3) * 380), station_budget_seconds = 900)
end
