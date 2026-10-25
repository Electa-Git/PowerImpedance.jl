# The registry is a catalogue of frozen physical circuits. TLC variants retain the fixture
# controls; composed_execution.jl adds the composed circuits.
const REGISTRY = [
    (id = "passive_ac_rlc", category = :passive, description = "AC series/parallel RLC; RL two-source witness",
        parent = "small_ac_network", factory = () -> ac_rl_network(),
        topology = "ideal AC source — RL branch — ideal AC source",
        physics = ["R/L energy and loss", "dq coupling", "clamped two-port reduction"],
        dissipativity = "R=20 Ω damps every branch-current mode; both port voltages are prescribed",
        differences = String[], measurements = ["operating_point", "frequency_response"], estimated_nodes = 30),
    (id = "passive_dc_rlc", category = :passive, description = "DC two-terminal RLC",
        parent = "dc_network", factory = () -> dc_rlc_network(),
        topology = "two DC sources — differential RL and parallel RC sections; AC slack island",
        physics = ["pole scaling", "DC loss", "capacitive charging"],
        dissipativity = "positive series and parallel resistance; no isolated lossless storage",
        differences = ["DM midpoint references: two 10 MΩ pole shunts, 20 MΩ differential path"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 32),
    (id = "ac_ohl_untransposed", category = :passive, description = "AC overhead line",
        parent = "passive_ohl_network",
            factory = () -> PSCADFixtures.passive_ohl_network(),
        topology = "AC source — 25 km OHL — resistive load",
        physics = ["earth return", "propagation", "phase ordering"],
        dissipativity = "positive conductor/earth loss and resistive termination",
        differences = ["PSCAD rational line/earth fit versus native evaluation; retain fit settings/results"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 36),
    (id = "ac_cable_coaxial", category = :passive, description = "AC coaxial cable",
        parent = "dc_cable_network geometry + AC topology", factory = () -> ac_cable_network(),
        topology = "AC source — three underground coaxial cores — resistive load",
        physics = ["dielectric charging", "eliminated sheaths", "AC core ordering"],
        dissipativity = "positive conductor/earth loss and resistive termination",
        differences = ["PSCAD rational cable/earth fit and grounded conductor elimination; quantify before frequency-response measurement"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 40),
    (id = "dc_cable_ohl", category = :passive, description = "DC cable + DC overhead line",
        parent = "dc_cable_network + dc_ohl_test geometry", factory = () -> dc_mixed_network(),
        topology = "DC source — 25 km cable — 75 km DC OHL — DC source; AC slack island",
        physics = ["mixed-medium reflection", "DC fit", "differential order"],
        dissipativity = "positive conductor/earth loss in both source-terminated sections",
        differences = [
            "DC line/cable fits start at 0.001 Hz, DCenab=0; DC and broadband errors require measurement",
            "DM midpoint references: two 10 MΩ pole shunts, 20 MΩ differential path"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 40),
    (id = "transformer_yy", category = :passive, description = "YY transformer",
        parent = "transformer_network",
            factory = () -> PSCADFixtures.transformer_network(),
        topology = "AC source — YY T model — resistive load",
        physics = ["turns ratio", "magnetizing current", "T-model response"],
        dissipativity = "positive winding/magnetizing resistance and resistive load",
        differences = ["YY leakage 1e-4 pu and excitation 1e-3 percent",
            "power-flow approximation versus explicit T model"], measurements = ["operating_point", "frequency_response"], estimated_nodes = 48),
    (id = "transformer_dyn11", category = :passive, description = "Dyn11 transformer",
        parent = "transformer_network(:ΔY)",
        factory = () -> PSCADFixtures.transformer_network(organization = :ΔY),
        topology = "AC source — Dyn11 T model — resistive load",
        physics = ["+30 degree secondary shift", "turns ratio", "winding loss"],
        dissipativity = "positive winding/magnetizing resistance and resistive load",
        differences = ["power-flow approximation versus explicit Dyn11 T model"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 48),
    (id = "ieee9_bus_impedance", category = :passive, description = "IEEE9 passive system anchor",
        parent = "ieee9_network", factory = PSCADFixtures.ieee9_network,
        topology = "3 ideal AC sources, 3 YY transformers, 6 OHL, 3 impedance loads",
        physics = ["network assembly", "multi-bus reduction", "voltage levels"],
        dissipativity = "lossy lines and resistive loads terminate the lossless transformer storage",
        differences = ["YY winding regularization", "rational line/earth fits",
            "power-flow approximation versus explicit transformer T/capacitance model"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 78),
    (id = "tlc_pq_freq_support", category = :device, description = "TLC P/Q, PLL/OCC against SCR 8 Thevenin grid",
        parent = "TLC tlc_case2_network controls and electrical parameters",
        factory = () -> tlc_strong_network(),
        topology = "AC source — series RL — TLC AC; ideal DC source clamps TLC DC",
        physics = ["PLL/grid interaction", "P/Q outer and current inner loops", "clamped-DC AC admittance"],
        dissipativity = "complete-network Nyquist and located roots required; no passive shortcut",
        differences = ["TLC Padé 3/3 200 us modulation delay versus PSCAD exact delay; quantify phase in band",
            "averaged TLC; limits retained at TLC values; ideal DC source; no DC cable"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 45),
    (id = "tlc_pf_q", category = :device, description = "TLC P-f/Q, SCR 8 / X/R 10",
        parent = "TLC electrical/inner/PLL parameters; converter-control shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :pf, scr = 8.0),
        topology = "AC source — RL — TLC; ideal DC source",
        physics = ["frequency support lag", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["TLC Padé 3/3 200 us modulation versus PSCAD exact delay", "tlc_pq_freq_support already contains the same TLC frequency support lag; explicit mode witness"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 45),
    (id = "tlc_p_qv", category = :device, description = "TLC P/Q-V, SCR 8 / X/R 10",
        parent = "TLC electrical/inner/PLL parameters; converter-control shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :qv, scr = 8.0),
        topology = "AC source — RL — TLC; ideal DC source",
        physics = ["voltage support lag/droop", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["TLC Padé 3/3 200 us modulation versus PSCAD exact delay", "Q-V K=20, omega_c=100 rad/s; P has no frequency support"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 45),
    (id = "tlc_p_vac", category = :device, description = "TLC P/VAC, SCR 8 / X/R 10",
        parent = "TLC electrical/inner/PLL parameters; converter-control shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :vac, scr = 8.0),
        topology = "AC source — RL — TLC; ideal DC source",
        physics = ["AC voltage regulation", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["TLC Padé 3/3 200 us modulation versus PSCAD exact delay", "VAC NoFilter, Kp=0, Ki=100; P has no frequency support"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 45),
    (id = "tlc_vdc_q", category = :device, description = "TLC Vdc/Q with resistive DC load, SCR 8 / X/R 10",
        parent = "TLC electrical/inner/PLL parameters; converter-control shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :vdc, scr = 8.0),
        topology = "AC source — RL — TLC; DC — resistor — zero-voltage reference",
        physics = ["DC voltage regulation and AC/DC feedback", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["TLC Padé 3/3 200 us modulation versus PSCAD exact delay", "DC load 640^2/70 ohm; remote zero-voltage reference is a short, not a clamp at the converter"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 49),
    (id = "tlc_pq_weak_grid", category = :device, description = "TLC P/Q weak-grid twin, SCR 2.5 / X/R 10",
        parent = "TLC electrical/inner/PLL parameters; converter-control shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :pq, scr = 2.5),
        topology = "AC source — RL — TLC; ideal DC source",
        physics = ["weak-grid PLL/controller coupling", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["TLC Padé 3/3 200 us modulation versus PSCAD exact delay", "Identical TLC controls and requests to tlc_pq_freq_support, including its P-f lag"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 45),
    [(id = id, category = :device, description = "MMC $(label), SCR $(scr) / X/R 10",
        parent = "MMC mmc_network parameters and controls",
        factory = () -> mmc_grid_network(; mode, scr),
        topology = mode == :vdc ? "AC source — RL — MMC; physical DC resistor to ground" :
            "AC source — RL — MMC; ideal DC source",
        physics = ["PLL/grid interaction", "TEC/ZSCC/CCSC", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["averaged MMC with uncompensated modulation; MMC parameters unchanged",
            "Thevenin SCR at external 380 kV / 1000 MVA; transformer ratio 333/380 retained"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = mode == :vdc ? 65 : 61)
     for (id, mode, label, scr) in (("mmc_pq", :pq, "P/Q", 8.0),
         ("mmc_pf_q", :pf, "P-f/Q", 8.0), ("mmc_p_qv", :qv, "P/Q-V", 8.0),
         ("mmc_p_vac", :vac, "P/VAC", 8.0), ("mmc_vdc_q", :vdc, "Vdc/Q", 8.0),
         ("mmc_pq_weak_grid", :pq, "P/Q weak-grid twin", 2.5))]...,
    [(id=id, category=:device, description=label, parent=parent,
        factory=()->active_device_network(kind; scr),
        topology=kind==:machine ? "AC source — RL — synchronous machine with native rt/lt" :
            "AC source — RL — MMC; ideal DC source",
        physics=["complete-network active-device dynamics", "AC-terminal dq admittance"],
        dissipativity="complete-network Nyquist and all finite descriptor roots required",
        differences=kind==:machine ? ["native machine Y is per-unit; explicit SI boundary conversion", "existing PSCAD machine iron-loss and initialization conventions"] :
            ["200 us Padé 5/5 modulation versus native PSCAD delay; controls and electrical parameters unchanged"],
        measurements=["operating_point", "frequency_response"], estimated_nodes=kind==:machine ? 45 : 65)
     for (id,kind,label,parent,scr) in (("mmc_gfm_vsm",:gfm,"GFM MMC, SCR 8","GFM MMC mmc_gfm_network",8.),
         ("mmc_gfm_lec_compensated",:compensated,"LEC/CCC compensated MMC","compensated MMC mmc_compensated_network",8.),
         ("mmc_pq_no_energy_control",:disabled,"P/Q MMC with disabled TEC/ZSCC","legacy-mapped P2P receiving MMC c2",8.),
         ("synchronous_machine",:machine,"Synchronous machine with AVR/governor/turbine","machine sm_network",8.),
         ("mmc_gfm_weak_grid",:gfm,"GFM MMC weak-grid twin","GFM MMC mmc_gfm_network",2.5))]...,
    (id = "induction_machine", category = :device,
        description = "Induction machine with constant load torque",
        parent = "PSCADFixtures.im_network", factory = () -> induction_machine_network(),
        topology = "220 kV AC source — 0.01 ohm resistor — induction machine",
        physics = ["rotor flux and slip dynamics", "AC-terminal dq admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots recorded",
        differences = ["reference circuit with element names DUT, Grid and G3",
            "NetworkBuilder.get_y applies the machine SI scaling"],
        measurements = ["operating_point", "frequency_response"], estimated_nodes = 45)
]

function fixture(id)
    index = findfirst(entry -> entry.id == id, REGISTRY)
    index === nothing && throw(ArgumentError("unknown fixture $id"))
    return REGISTRY[index]
end

function port_nets(state, name, port)
    rows = NetworkBuilder.sortedcomponentconnections(state.topology, name;
        withground = true)
    return collect(filter(row -> row.port == port, rows).net)
end

function component_nets(state, name)
    return collect(NetworkBuilder.sortedcomponentconnections(state.topology, name;
        withground = true).net)
end

function passive_dimension(model)
    domain = first(electricalconnections(model)).domain
    return PowerImpedance.isac(domain) ? 2 : 1
end

function fixture_topology(state; exclude = ())
    topology = NetworkBuilder.Bus[]
    for name in keys(state.elements)
        name in exclude && continue
        rows = NetworkBuilder.sortedcomponentconnections(state.topology, name;
            withground = true)
        for port in unique(rows.port)
            row = first(filter(row -> row.port == port, rows))
            bus = row.domain == 2 ? row.net :
                Symbol(chop(string(row.net); tail = length(string(row.terminal))))
            domain = row.frame == :dq ? ACDQ : row.frame == :abc ? ACABC : DC_CM
            push!(topology, NetworkBuilder.Bus(bus; ports = ((name, port),), domain))
        end
    end
    return topology
end

function ac_rl_network()
    voltage = 380 / sqrt(3)
    elements = (;
        grid_a = ac_source(v = voltage * sqrt(2), theta = 0.0),
        grid_b = ac_source(v = 0.98voltage * sqrt(2), theta = -0.01),
        branch = impedance(z = s -> 20.0 + 0.05s, conductors = 3))
    topology = (
        NetworkBuilder.Bus(:A; ports = ((:grid_a, :ac), (:branch, :side1)),
            domain = ACDQ),
        NetworkBuilder.Bus(:B; ports = ((:grid_b, :ac), (:branch, :side2)),
            domain = ACDQ))
    return NetworkBuilder.define(elements, topology; options = (; voltageBase = voltage))
end

# Replaying connectivity avoids merging the original D2 source net into DM.
function dc_sections_parent(parent)
    topology = [NetworkBuilder.Bus(
        bus.ports == [(:line, :side2)] ? :DM : bus.name;
        ports = bus.ports, domain = bus.domain) for bus in fixture_topology(parent)]
    return NetworkBuilder.define(deepcopy(parent.elements), topology;
        options = parent.options)
end

function dc_rlc_network()
    parent = dc_sections_parent(PSCADFixtures.dc_network())
    # Keep RL and parallel RC as separate supported scalar realizations.
    elements = merge(parent.elements,
        (; rc = impedance(z = s -> inv(1 / 10.0 + 1e-6s), conductors = 1)))
    topology = fixture_topology(parent)
    append!(topology, [NetworkBuilder.Bus(:DM; ports = ((:rc, :side1),)),
        NetworkBuilder.Bus(:D2; ports = ((:rc, :side2),))])
    return NetworkBuilder.define(elements, topology; options = parent.options)
end

function ac_cable_network()
    parent = PSCADFixtures._small_ac_circuit()
    replacement = deepcopy(PSCADFixtures.dc_cable_network().elements.line)
    replacement.positions = [(-0.5, 1.0), (0.0, 1.0), (0.5, 1.0)]
    return NetworkBuilder.define(merge(parent.elements, (; line = replacement)),
        parent.rows; options = parent.options)
end

function dc_mixed_network()
    parent = dc_sections_parent(PSCADFixtures.dc_cable_network())
    parent.elements.line.length = 25e3
    ohl = overhead_line(length = 75e3,
        conductors = Conductors(organization = :flat, nᵇ = 2, nˢᵇ = 1,
            Rᵈᶜ = 0.0266, rᶜ = 0.0224, yᵇᶜ = 18.0, Δxᵇᶜ = 7.3, dˢᵃᵍ = 6.0),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062,
            Δxᵍ = 7.3, Δyᵍ = 7.0, dᵍˢᵃᵍ = 6.0),
        earth_parameters = (1, 1, 100))
    topology = fixture_topology(parent)
    append!(topology, [NetworkBuilder.Bus(:DM; ports = ((:ohl, :side1),)),
        NetworkBuilder.Bus(:D2; ports = ((:ohl, :side2),))])
    return NetworkBuilder.define(merge(parent.elements, (; ohl)), topology;
        options = parent.options)
end

function passive_gate(net, entry)
    evidence = String[]
    for (name, element) in pairs(net.elements)
        model = element
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

function passive_settings()
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

# The TLC factory supplies every block; only topology and Q=5 MVAr change.
function tlc_strong_network(; mode = :pq, scr = 8.0)
    parent = PSCADFixtures.tlc_case2_network()
    m = deepcopy(parent.elements.DUT)
    # fixtures.jl:tlc_network supplies plant/PLL/current loops and P-f gains. The mode
    # mapping supplies Q-V gains 20/100 and VAC gains 0/100 (NoFilter).
    active = mode in (:pq, :pf) ? m.outerActive :
        mode == :vdc ? PowerImpedance.OuterActiveVdcControl(
            pi_ctrl = PowerImpedance.PIControl(Kp=5.0, Ki=5.0)) :
        PowerImpedance.OuterActivePowerControl(pi_ctrl=m.outerActive.pi_ctrl,
            support=PowerImpedance.NoFrequencySupport())
    reactive = mode == :qv ? PowerImpedance.OuterReactiveQControl(
        pi_ctrl=m.outerReactive.pi_ctrl,
        support=PowerImpedance.VoltageSupportLag(K=20.0, ωc=100.0)) :
        mode == :vac ? PowerImpedance.OuterReactiveVacControl(
            pi_ctrl=PowerImpedance.PIControl(Kp=0.0, Ki=100.0),
            filter=PowerImpedance.NoFilter()) : m.outerReactive
    mode in (:pq, :pf, :qv, :vac, :vdc) || error("unknown TLC fixture mode $mode")
    # A resistive DC load consumes power: Vdc-control case rectifies from AC.
    power = mode == :vdc ? -70.0 : 70.0
    model = tlc(elec=m.elec, meas=m.meas, sync=m.sync, outerActive=active,
        outerReactive=reactive, innerVoltage=m.innerVoltage,
        innerCurrent=m.innerCurrent, mod=m.mod, limits=limits(m))
    b = bases(model)
    active_inputs = mode == :vdc ? (; v_dc_ref = 640.0 / b.v_dc) :
        (; p_ref = power / b.S)
    active_seeds = mode == :vdc ? (; p_ac = power / b.S) :
        (; v_dc = 640.0 / b.v_dc)
    reactive_inputs = mode == :vac ? (; v_ac_ref = 220sqrt(2/3) / b.v_ac) :
        mode == :qv ? (; q_ref = 5.0 / b.S,
            support = (; v_ac_ref = 220sqrt(2/3) / b.v_ac)) : (; q_ref = 5.0 / b.S)
    reactive_seeds = mode == :vac ? (; q_ac = 5.0 / b.S) : mode == :qv ? (;) :
        (; v_ac = 220sqrt(2/3) / b.v_ac)
    dut = component(model; outerActive = active_inputs, outerReactive = reactive_inputs,
        powerflow = (; active_seeds..., reactive_seeds..., p_dc = power / b.S))
    z = 220.0^2 / 100.0 / scr
    resistance = z/sqrt(101)
    inductance = 10resistance/(2π*50)
    elements = (; DUT = dut, G3 = deepcopy(parent.elements.G3),
        G_DC = dc_source(v = mode == :vdc ? 0.0 : 640.0),
        Grid = impedance(z = s -> resistance+inductance*s, conductors = 3))
    topology = NetworkBuilder.Bus[
        NetworkBuilder.Bus(:AC; ports = ((:DUT, :ac), (:Grid, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Grid; ports = ((:Grid, :side2), (:G3, :ac)), domain = ACDQ),
        NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc),))]
    if mode == :vdc
        # The PF-only zero-voltage reference draws zero power. `fixture_netlist` replaces
        # it with ground; emitters/impedance.jl:emit! supplies the grounded R/2 pole
        # resistors.
        elements = merge(elements,
            (; DC_load = impedance(z = s -> 640.0^2/70.0, conductors = 1)))
        append!(topology, [
            NetworkBuilder.Bus(:DC; ports = ((:DC_load, :side1),)),
            NetworkBuilder.Bus(:DC_zero; ports = ((:DC_load, :side2), (:G_DC, :dc)))])
    else
        push!(topology, NetworkBuilder.Bus(:DC; ports = ((:G_DC, :dc),)))
    end
    return NetworkBuilder.define(elements, topology; options = parent.options)
end

# PF represents a DC resistor as a two-bus branch with a remote 0 V reference. PSCAD's
# DC-impedance emitter supports a grounded terminal (emitters/impedance.jl:1-37), while
# dc_source! requires positive Vdc. Replacing only that ideal zero-voltage source with
# ground gives the same circuit, converter solved point and resistor terminal-1 power,
# with unchanged components and PSCAD fields.
function fixture_netlist(state, point = compute(PowerFlowProblem(state), ACDCPowerFlow()))
    point === nothing || NetworkBuilder.NetworkModel(state, point.operating_point)
    list = P.netlist(state, point)
    haskey(state.elements, :DC_load) || return list
    inputvalues(state.elements.G_DC).v == 0.0 ||
        error("DC ground reference must be exactly zero")
    ground_net = only(port_nets(state, :G_DC, :dc))
    ground_bus = only(b.key for b in list.buses if ground_net in b.nets)
    elements=P.NetlistElement[]
    for e in list.elements
        e.name==:G_DC && continue
        terminals=[t.bus==ground_bus ?
                   P.Terminal(t.element, t.port, t.terminals,
                       fill(:gnd, length(t.nets)), nothing, true) : t
                   for t in e.terminals]
        role=e.name==:DC_load ? :load : e.role
        push!(elements, P.NetlistElement(
            e.name, e.pscad, e.model, e.ports, terminals, role, e.values))
    end
    op=list.operating_point
    operating_point=P.OperatingPointRecord(
        Dict(k=>v for (k,v) in op.bus_states if k!=ground_bus),
        Dict(k=>v for (k,v) in op.branch_flows if k!=:G_DC),
        Dict(k=>v for (k,v) in op.values if k!=:G_DC),op.slack_bus,op.bases)
    return P.Netlist(filter(b->b.key!=ground_bus,list.buses),elements,operating_point,
        list.voltageBase,list.frequency)
end

# The fixture supplies the MMC and every controller; only the terminal network changes.
function mmc_grid_network(; mode = :pq, scr = 8.0)
    parent = PSCADFixtures.mmc_network(mode)
    model = deepcopy(parent.elements.DUT)
    elec = model.elec
    b = bases(model)
    voltage = elec.vAC_base / elec.turnsRatio
    power = mode == :vdc ? -600.0 : 600.0
    active_inputs = mode == :vdc ? (; v_dc_ref = elec.vDC_base / b.v_dc) :
        (; p_ref = power / b.S)
    active_seeds = mode == :vdc ? (; p_ac = power / b.S) :
        (; v_dc = elec.vDC_base / b.v_dc)
    reactive_inputs = mode == :vac ? (; v_ac_ref = voltage / b.v_ac) :
        mode == :qv ? (; q_ref = 200.0 / b.S,
            support = (; v_ac_ref = voltage / b.v_ac)) : (; q_ref = 200.0 / b.S)
    reactive_seeds = mode == :vac ? (; q_ac = 200.0 / b.S) : mode == :qv ? (;) :
        (; v_ac = voltage / b.v_ac)
    dut = component(model; delta_control = (; outer_active = active_inputs,
            outer_reactive = reactive_inputs),
        powerflow = (; active_seeds..., reactive_seeds..., p_dc = power / b.S))
    impedance_magnitude = (voltage * sqrt(3/2))^2 / elec.Sbase / scr
    resistance = impedance_magnitude / sqrt(101)
    inductance = 10resistance / (2π*50)
    elements = (; DUT = dut, G3 = deepcopy(parent.elements.G_AC),
        G_DC = dc_source(v = mode == :vdc ? 0.0 : elec.vDC_base),
        Grid = impedance(z = s -> resistance+inductance*s, conductors = 3))
    topology = NetworkBuilder.Bus[
        NetworkBuilder.Bus(:AC; ports = ((:DUT, :ac), (:Grid, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Grid; ports = ((:Grid, :side2), (:G3, :ac)), domain = ACDQ),
        NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc),))]
    if mode == :vdc
        resistance_dc = elec.vDC_base^2 / abs(power)
        elements = merge(elements,
            (; DC_load = impedance(z = s -> resistance_dc, conductors = 1)))
        append!(topology, [
            NetworkBuilder.Bus(:DC; ports = ((:DC_load, :side1),)),
            NetworkBuilder.Bus(:DC_zero; ports = ((:DC_load, :side2), (:G_DC, :dc)))])
    else
        push!(topology, NetworkBuilder.Bus(:DC; ports = ((:G_DC, :dc),)))
    end
    return NetworkBuilder.define(elements, topology;
        options = (; voltageBase = voltage / sqrt(2)))
end

function active_device(kind)
    kind==:gfm && return deepcopy(PSCADFixtures.mmc_gfm_network().elements[:DUT])
    kind==:compensated &&
        return deepcopy(PSCADFixtures.mmc_compensated_network().elements[:DUT])
    if kind == :disabled
        m = system_original_p2p_network().elements.c2
        b = bases(m)
        return component(m; powerflow = (; p_dc = 0.0 / b.S))
    end
    kind==:machine && return deepcopy(PSCADFixtures.sm_network().elements[:sg1])
    throw(ArgumentError("unknown active device $kind"))
end

function active_device_network(kind; scr=8.)
    dut=active_device(kind)
    b=device_bases(dut.elec)
    z=(b.ac_voltage*sqrt(3/2))^2/b.power/scr
    resistance=z/sqrt(101);inductance=10resistance/(2π*50)
    elements = (; DUT = dut, G3 = ac_source(v = b.ac_voltage),
        Grid = impedance(z = s -> resistance+inductance*s, conductors = 3))
    topology = NetworkBuilder.Bus[
        NetworkBuilder.Bus(:AC; ports = ((:DUT, :ac), (:Grid, :side1)), domain = ACDQ),
        NetworkBuilder.Bus(:Grid; ports = ((:Grid, :side2), (:G3, :ac)), domain = ACDQ)]
    if b.dc_voltage !== nothing
        elements = merge(elements, (; G_DC = dc_source(v = b.dc_voltage)))
        push!(topology, NetworkBuilder.Bus(:DC; ports = ((:DUT, :dc), (:G_DC, :dc))))
    end
    return NetworkBuilder.define(elements, topology;
        options = (; voltageBase = b.ac_voltage/sqrt(2)))
end
