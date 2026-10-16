# The registry is a catalogue of frozen physical circuits, not a dispatch layer.
# L2 TLC variants retain the M4/M5b controls; L3 entries are added by composed_execution.jl.
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
        tiers = ["A", "C"], estimated_nodes = 78),
    (id = "L2-01", description = "TLC P/Q, PLL/OCC against SCR 8 Thevenin grid",
        parent = "M4 tlc_case2_network controls and electrical parameters",
        factory = () -> tlc_strong_network(),
        topology = "AC source — series RL — TLC AC; ideal DC source clamps TLC DC",
        physics = ["PLL/grid interaction", "P/Q outer and current inner loops", "clamped-DC AC admittance"],
        dissipativity = "complete-network Nyquist and located roots required; no passive shortcut",
        differences = ["M4 Padé 3/3 200 us modulation delay versus PSCAD exact delay; quantify phase in band",
            "averaged TLC; limits retained at M4 values; ideal DC source; no DC cable"],
        tiers = ["A", "C"], estimated_nodes = 45),
    (id = "L2-02", description = "TLC P-f/Q, SCR 8 / X/R 10",
        parent = "M4 TLC electrical/inner/PLL parameters; M5b shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :pf, scr = 8.0),
        topology = "AC source — RL — TLC; ideal DC source",
        physics = ["frequency support lag", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["M4 Padé 3/3 200 us modulation versus PSCAD exact delay", "L2-01 already contains the same M4 frequency support lag; explicit mode witness"],
        tiers = ["A", "C"], estimated_nodes = 45),
    (id = "L2-03", description = "TLC P/Q-V, SCR 8 / X/R 10",
        parent = "M4 TLC electrical/inner/PLL parameters; M5b shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :qv, scr = 8.0),
        topology = "AC source — RL — TLC; ideal DC source",
        physics = ["voltage support lag/droop", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["M4 Padé 3/3 200 us modulation versus PSCAD exact delay", "Q-V K=20, omega_c=100 rad/s; P has no frequency support"],
        tiers = ["A", "C"], estimated_nodes = 45),
    (id = "L2-04", description = "TLC P/VAC, SCR 8 / X/R 10",
        parent = "M4 TLC electrical/inner/PLL parameters; M5b shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :vac, scr = 8.0),
        topology = "AC source — RL — TLC; ideal DC source",
        physics = ["AC voltage regulation", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["M4 Padé 3/3 200 us modulation versus PSCAD exact delay", "VAC NoFilter, Kp=0, Ki=100; P has no frequency support"],
        tiers = ["A", "C"], estimated_nodes = 45),
    (id = "L2-05", description = "TLC Vdc/Q with resistive DC load, SCR 8 / X/R 10",
        parent = "M4 TLC electrical/inner/PLL parameters; M5b shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :vdc, scr = 8.0),
        topology = "AC source — RL — TLC; DC — resistor — zero-voltage reference",
        physics = ["DC voltage regulation and AC/DC feedback", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["M4 Padé 3/3 200 us modulation versus PSCAD exact delay", "DC load 640^2/70 ohm; remote zero-voltage reference is a short, not a clamp at the converter"],
        tiers = ["A", "C"], estimated_nodes = 49),
    (id = "L2-06", description = "TLC P/Q weak-grid twin, SCR 2.5 / X/R 10",
        parent = "M4 TLC electrical/inner/PLL parameters; M5b shared outer-loop gains",
        factory = () -> tlc_strong_network(mode = :pq, scr = 2.5),
        topology = "AC source — RL — TLC; ideal DC source",
        physics = ["weak-grid PLL/controller coupling", "PLL/grid interaction", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["M4 Padé 3/3 200 us modulation versus PSCAD exact delay", "Identical M4 controls and requests to L2-01, including its P-f lag"],
        tiers = ["A", "C"], estimated_nodes = 45),
    [(id = id, description = "MMC $(label), SCR $(scr) / X/R 10",
        parent = "M5a/M5b mmc_network parameters and controls",
        factory = () -> mmc_grid_network(; mode, scr),
        topology = mode == :vdc ? "AC source — RL — MMC; physical DC resistor to ground" :
            "AC source — RL — MMC; ideal DC source",
        physics = ["PLL/grid interaction", "TEC/ZSCC/CCSC", "terminated AC-port admittance"],
        dissipativity = "complete-network Nyquist and all finite descriptor roots required",
        differences = ["averaged MMC with uncompensated modulation; M5a/M5b parameters unchanged",
            "Thevenin SCR at external 380 kV / 1000 MVA; transformer ratio 333/380 retained"],
        tiers = ["A", "C"], estimated_nodes = mode == :vdc ? 65 : 61)
     for (id, mode, label, scr) in (("L2-07", :pq, "P/Q", 8.0),
         ("L2-08", :pf, "P-f/Q", 8.0), ("L2-09", :qv, "P/Q-V", 8.0),
         ("L2-10", :vac, "P/VAC", 8.0), ("L2-11", :vdc, "Vdc/Q", 8.0),
         ("L2-12", :pq, "P/Q weak-grid twin", 2.5))]...,
    [(id=id, description=label, parent=parent,
        factory=()->batch_c_network(kind; scr),
        topology=kind==:machine ? "AC source — RL — synchronous machine with native rt/lt" :
            "AC source — RL — MMC; ideal DC source",
        physics=["complete-network active-device dynamics", "AC-terminal dq admittance"],
        dissipativity="complete-network Nyquist and all finite descriptor roots required",
        differences=kind==:machine ? ["native machine Y is per-unit; explicit SI boundary conversion", "existing PSCAD machine iron-loss and initialization conventions"] :
            ["200 us Padé 5/5 modulation versus native PSCAD delay; controls and electrical parameters unchanged"],
        tiers=["A","C"], estimated_nodes=kind==:machine ? 45 : 65)
     for (id,kind,label,parent,scr) in (("L2-13",:gfm,"GFM MMC, SCR 8","M6a mmc_gfm_network",8.),
         ("L2-14",:compensated,"LEC/CCC compensated MMC","M6b mmc_compensated_network",8.),
         ("L2-15",:disabled,"P/Q MMC with disabled TEC/ZSCC","legacy-mapped P2P receiving MMC c2",8.),
         ("L2-16",:machine,"Synchronous machine with AVR/governor/turbine","M3 sm_network",8.),
         ("L2-17",:gfm,"GFM MMC weak-grid twin","M6a mmc_gfm_network",2.5))]...
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

# M4 owned factory supplies every TLC block; only topology and Q=5 MVAr change.
function tlc_strong_network(; mode = :pq, scr = 8.0)
    parent = PSCADFixtures.tlc_case2_network().classic
    net = Network()
    net.voltageBase .= parent.voltageBase
    dut = deepcopy(parent.elements[:DUT])
    m = dut.element_model
    # M4 fixtures.jl:tlc_network owns plant/PLL/current loops and P-f gains.
    # M5b mapping table owns Q-V 20/100 and VAC 0/100 (NoFilter).
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
    dut = tlc(elec=m.elec, meas=m.meas, sync=m.sync, outerActive=active,
        outerReactive=reactive, innerVoltage=m.innerVoltage,
        innerCurrent=m.innerCurrent, mod=m.mod, limits=dut.limits,
        setpoint=Setpoint(Pac=power,Qac=5.0,Vac=220sqrt(2/3),Pdc=power,Vdc=640.0))
    add!(net, :DUT, dut)
    for name in (:G3, :G_DC)
        add!(net, name, deepcopy(parent.elements[name]))
    end
    z = 220.0^2 / 100.0 / scr
    resistance = z/sqrt(101)
    inductance = 10resistance/(2π*50)
    add!(net, :Grid, impedance(z=s->resistance+inductance*s, pins=3, transformation=true))
    for terminal in 1:2
        for (element, side, bus) in ((:DUT,2,"AC"), (:Grid,1,"AC"), (:Grid,2,"Grid"), (:G3,1,"Grid"))
            connect!(net, (element, Symbol("$side.$terminal")), Symbol(bus*string(terminal)))
        end
        connect!(net, (:G3,Symbol("2.$terminal")), :gnd)
    end
    connect!(net, (:DUT,Symbol("1.1")), :DC)
    if mode == :vdc
        # PF-only zero-voltage reference draws zero power. fixture_netlist
        # contracts it to ground; emitters/impedance.jl:emit! supplies the
        # existing grounded R/2 pole-resistor construction.
        net.elements[:G_DC] = dc_source(setpoint=Setpoint(Vdc=0.0))
        add!(net, :DC_load, impedance(z=s->640.0^2/70.0,pins=1))
        connect!(net, (:DC_load,Symbol("1.1")), :DC)
        connect!(net, (:DC_load,Symbol("2.1")), :DC_zero)
        connect!(net, (:G_DC,Symbol("1.1")), :DC_zero)
    else
        connect!(net, (:G_DC,Symbol("1.1")), :DC)
    end
    connect!(net, (:G_DC,Symbol("2.1")), :gnd)
    connect!(net)
    return net
end

# PF represents a DC resistor as a two-bus branch and needs a remote 0 V
# reference. PSCAD's existing DC-impedance emitter directly supports a grounded
# terminal (emitters/impedance.jl:1-37), while dc_source! requires positive Vdc.
# Collapse only that ideal zero-voltage reference to ground, preserving the
# converter's solved point and resistor's terminal-1 power. No component or
# PSCAD field is introduced: this is the exact same circuit with its ideal
# zero-voltage source contracted to node identity.
function fixture_netlist(net, point)
    list=P.netlist(net,point)
    haskey(net.elements,:DC_load) || return list
    source=only(filter(e->e.name==:G_DC,list.elements))
    source.setpoint.Vdc==0.0 || error("DC ground reference must be exactly zero")
    ground_bus=only(source.terminals[findall(t->!t.grounded,source.terminals)]).bus
    elements=P.NetlistElement[]
    for e in list.elements
        e.name==:G_DC && continue
        terminals=[t.bus==ground_bus ?
            P.Terminal(t.element,t.side,t.terminals,fill(:gnd,length(t.nets)),nothing,true) : t
            for t in e.terminals]
        role=e.name==:DC_load ? :load : e.role
        push!(elements,P.NetlistElement(e.name,e.pscad,e.element,e.model,terminals,role,e.setpoint))
    end
    op=list.operating_point
    operating_point=P.OperatingPointRecord(
        Dict(k=>v for (k,v) in op.bus_states if k!=ground_bus),
        Dict(k=>v for (k,v) in op.branch_flows if k!=:G_DC),
        Dict(k=>v for (k,v) in op.setpoints if k!=:G_DC),op.slack_bus,op.bases)
    return P.Netlist(filter(b->b.key!=ground_bus,list.buses),elements,operating_point,
        list.voltageBase,list.frequency)
end

# M5a/M5b owns the MMC and every controller; only the terminal network changes.
function mmc_grid_network(; mode = :pq, scr = 8.0)
    parent = PSCADFixtures.mmc_network(mode).state
    dut = deepcopy(parent.elements.DUT)
    elec = dut.element_model.elec
    voltage = elec.vAC_base / elec.turnsRatio
    power = mode == :vdc ? -600.0 : 600.0
    dut.setpoint = Setpoint(Pac=power, Qac=200.0, Vac=voltage,
        Vdc=elec.vDC_base, Pdc=power)
    net = Network()
    net.voltageBase[1] = voltage / sqrt(2)
    add!(net, :DUT, dut)
    add!(net, :G3, deepcopy(parent.elements.G_AC))
    add!(net, :G_DC, dc_source(setpoint=Setpoint(Vdc=mode == :vdc ? 0.0 : elec.vDC_base)))
    impedance_magnitude = (voltage * sqrt(3/2))^2 / elec.Sbase / scr
    resistance = impedance_magnitude / sqrt(101)
    inductance = 10resistance / (2π*50)
    add!(net, :Grid, impedance(z=s->resistance+inductance*s, pins=3, transformation=true))
    for terminal in 1:2
        for (element, side, bus) in ((:DUT,2,"AC"), (:Grid,1,"AC"), (:Grid,2,"Grid"), (:G3,1,"Grid"))
            connect!(net, (element, Symbol("$side.$terminal")), Symbol(bus*string(terminal)))
        end
        connect!(net, (:G3,Symbol("2.$terminal")), :gnd)
    end
    connect!(net, (:DUT,Symbol("1.1")), :DC)
    if mode == :vdc
        resistance_dc = elec.vDC_base^2 / abs(power)
        add!(net, :DC_load, impedance(z=s->resistance_dc,pins=1))
        connect!(net, (:DC_load,Symbol("1.1")), :DC)
        connect!(net, (:DC_load,Symbol("2.1")), :DC_zero)
        connect!(net, (:G_DC,Symbol("1.1")), :DC_zero)
    else
        connect!(net, (:G_DC,Symbol("1.1")), :DC)
    end
    connect!(net, (:G_DC,Symbol("2.1")), :gnd)
    connect!(net)
    return net
end

function batch_c_device(kind)
    kind==:gfm && return deepcopy(PSCADFixtures.mmc_gfm_network().state.elements.DUT)
    kind==:compensated && return deepcopy(PSCADFixtures.mmc_compensated_network().state.elements.DUT)
    kind==:disabled && return deepcopy(PSCADM7Networks.p2p_builder(1.).elements.c2)
    kind==:machine && return deepcopy(PSCADFixtures.sm_network().state.elements.sg1)
    throw(ArgumentError("unknown batch C device $kind"))
end

function batch_c_network(kind; scr=8.)
    dut=batch_c_device(kind)
    bases=device_bases(dut.element_model.elec)
    net=Network();net.voltageBase[1]=bases.ac_voltage/sqrt(2)
    add!(net,:DUT,dut)
    add!(net,:G3,ac_source(pins=3,transformation=true,setpoint=Setpoint(Vac=bases.ac_voltage)))
    z=(bases.ac_voltage*sqrt(3/2))^2/bases.power/scr
    resistance=z/sqrt(101);inductance=10resistance/(2π*50)
    add!(net,:Grid,impedance(z=s->resistance+inductance*s,pins=3,transformation=true))
    for terminal in 1:2
        for (element,side,bus) in ((:DUT,bases.ac_side,"AC"),(:Grid,1,"AC"),(:Grid,2,"Grid"),(:G3,1,"Grid"))
            connect!(net,(element,Symbol("$side.$terminal")),Symbol(bus*string(terminal)))
        end
        connect!(net,(:G3,Symbol("2.$terminal")),:gnd)
        bases.dc_voltage===nothing && connect!(net,(:DUT,Symbol("2.$terminal")),:gnd)
    end
    if bases.dc_voltage!==nothing
        add!(net,:G_DC,dc_source(setpoint=Setpoint(Vdc=bases.dc_voltage)))
        connect!(net,(:DUT,Symbol("1.1")),:DC)
        connect!(net,(:G_DC,Symbol("1.1")),:DC)
        connect!(net,(:G_DC,Symbol("2.1")),:gnd)
    end
    connect!(net)
    return net
end
