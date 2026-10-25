module ModelDeclarationsTests
using Test, PowerImpedance, Logging
const PI = PowerImpedance
include("parity/fixtures.jl")

struct Undeclared end

function passive_models(n)
    (
        PI.Impedance(conductors = n),
        PI.Transformer(conductors = n),
        PI.Overhead_line(conductors = Conductors(nᵇ = n)),
        PI.Cable(positions = [(Float64(i), 1.0) for i in 1:n]),
        PI.Blackbox_line(n = n)
    )
end

physical_conductors(m::PI.Impedance) = m.conductors
physical_conductors(m::PI.Transformer) = m.conductors
physical_conductors(m::PI.Overhead_line) = m.conductors.nᵇ
physical_conductors(m::PI.Cable) = length(m.positions)
physical_conductors(m::PI.Blackbox_line) = m.n
physical_conductors(::Union{MMC, TLC, PI.Blackbox_MMC}) = 1

element_ports(::Union{MMC, TLC, PI.Blackbox_MMC}) = (:dc, :ac)
element_ports(m) = keys(electricalconnections(m))

function expected_pins(port, m, transformed)
    port.domain === ACDQ && return 2
    port.domain === ACABC && return transformed ? 2 : 3
    n = length(electricalconnections(m)) == 2 ? physical_conductors(m) : 1
    return n - (n == 2 && transformed)
end

function check_tree(model, tree = inputs(model))
    current = PI.inputvalues(model, tree)
    for (key, declaration) in pairs(tree)
        @test hasfield(typeof(model), key)
        value = getfield(model, key)
        if declaration isa Input
            @test current[key] === value
            @test declaration.default isa declaration.type
            @test value isa declaration.type
            @test declaration.type === Symbol || !isempty(declaration.unit)
            @test !isempty(declaration.description)
        else
            @test declaration isa NamedTuple
            check_tree(value, declaration)
        end
    end
end

declared_defaults(input::Input) = input.default
declared_defaults(tree::NamedTuple) = map(declared_defaults, tree)

function gfl(; outer_active = OuterActivePowerControl(),
        outer_reactive = OuterReactiveQControl(), powerflow = (;))
    return mmc(sync = PLLSynchronization(),
        delta_control = ΔdqControlGFL(; outer_active, outer_reactive,
            occ = InnerCurrentPIControl()), sigma_control = ΣdqzControlTEC(),
        powerflow = powerflow)
end

function gfm(; outer_reactive = OuterReactiveVacControl(), powerflow = (;))
    return mmc(sync = VSEWithDamping(pll = PLLSynchronization()),
        delta_control = ΔdqControlGFM(; outer_reactive,
            vi = CCVI(), occ = InnerCurrentPIControl()),
        sigma_control = ΣdqzControlTEC(), powerflow = powerflow)
end

@testset "Electrical domains and model ports" begin
    @test Port(ACDQ).terminals == (:d, :q)
    @test Port(ACABC).terminals == (:a, :b, :c)
    @test Port(DC_CM).terminals == (:dc,)
    for domain in (ACDQ, ACABC, DC_CM)
        @test PI.terminals(domain) == Port(domain).terminals
        @test PI.isac(domain) == (domain !== DC_CM)
        @test PI.isdc(domain) == (domain === DC_CM)
    end
    @test Port(ACDQ; terminals = (:x, :y)).terminals == (:x, :y)
    @test Port(ACABC; terminals = (:u, :v, :w)).terminals == (:u, :v, :w)
    @test Port(DC_CM; terminals = (:pole,)).terminals == (:pole,)
    @test_throws ArgumentError Port(ACDQ; terminals = (:x,))
    @test_throws ArgumentError Port(DC_CM; terminals = (:x, :y))
    @test_throws ArgumentError Port(ACABC; terminals = (1, 2, 3))
    @test_throws r"Undeclared" electricalconnections(Undeclared())
    for n in (1, 2, 3), model in passive_models(n)

        ports = electricalconnections(model)
        @test keys(ports) == (:side1, :side2)
        @test all(p -> p.domain === (n == 3 ? ACABC : DC_CM), ports)
    end
    for model in passive_models(4)
        @test_throws ArgumentError electricalconnections(model)
    end
    @test impedance(z = 1.0).conductors == 1
    @test impedance(z = [1.0 0.0; 0.0 2.0]).conductors == 2
    @test impedance(z = 1.0, conductors = 3).conductors == 3
    @test impedance(z = s -> 1.0).conductors == 1
    @test impedance(z = s -> 1.0, conductors = 2).conductors == 2
    for source in (ac_source(), component(ac_source(); v = 220/sqrt(3)))
        @test keys(electricalconnections(source)) == (:ac,)
        @test electricalconnections(source).ac.domain === ACABC
        @test source.conductors == 3
    end
    dc = dc_source()
    @test electricalconnections(dc) == (dc = Port(DC_CM),)
    @test dc.conductors == 1
    @test electricalconnections(gfl()) == (ac = Port(ACDQ), dc = Port(DC_CM))
    @test electricalconnections(tlc()) ==
          (ac = Port(ACDQ), dc = Port(DC_CM))
    @test electricalconnections(PI.Blackbox_MMC()) ==
          (ac = Port(ACDQ), dc = Port(DC_CM))
    @test electricalconnections(synchronousmachine()) == (ac = Port(ACDQ),)
    @test electricalconnections(inductionmachine()) == (ac = Port(ACDQ),)
end

@testset "Declared defaults and configured field values" begin
    block = OuterActivePowerControl()
    updated = withinputs(block; p_ref = 0.3)
    @test inputs(updated) == inputs(block)
    @test inputs(updated).p_ref.default === 0.0
    @test inputvalues(updated).p_ref === 0.3

    converter = gfl()
    configured_converter = component(converter; limits = PI.Limits(P_max = 0.8),
        delta_control = (outer_active = (p_ref = 0.3,),),
        powerflow = (v_ac = 1.02, p_dc = 0.4))
    @test inputs(configured_converter) == inputs(converter)
    @test inputs(configured_converter).delta_control.outer_active.p_ref.default === 0.0
    @test inputs(configured_converter).powerflow.v_ac.default === 1.0
    @test inputvalues(configured_converter).delta_control.outer_active.p_ref === 0.3
    @test inputvalues(configured_converter).powerflow === configured_converter.powerflow
    @test inputvalues(configured_converter).powerflow ===
          (p_ac = 0.0, q_ac = 0.0, v_ac = 1.02, p_dc = 0.4, v_dc = 1.0)
    @test inputvalues(converter) == declared_defaults(inputs(converter))

    machine = synchronousmachine()
    configured_machine = withinputs(machine;
        avr = (v_ref = 1.04,), powerflow = (p = 0.3, v = 1.02))
    @test inputs(configured_machine) == inputs(machine)
    @test inputs(configured_machine).avr.v_ref.default === 1.01
    @test inputvalues(configured_machine) ===
          (avr = (v_ref = 1.04,), powerflow = (p = 0.3, q = 0.0, v = 1.02))
    @test inputvalues(machine) == declared_defaults(inputs(machine))

    source = ac_source()
    configured_source = component(source; v = 135.0, theta = 0.2, p = 100.0, q = -20.0)
    @test inputs(configured_source) == inputs(source)
    @test inputs(configured_source).v.default === 220/sqrt(3)
    @test inputvalues(configured_source) === (v = 135.0, theta = 0.2, p = 100.0, q = -20.0)
    @test inputvalues(source) == declared_defaults(inputs(source))
    dc = dc_source()
    configured_dc = withinputs(dc; v = 650.0, p = -90.0)
    @test inputs(configured_dc) == inputs(dc)
    @test inputs(configured_dc).v.default === 240.0
    @test inputvalues(configured_dc) === (v = 650.0, p = -90.0)
    @test inputvalues(dc) == declared_defaults(inputs(dc))

    for fresh in (gfl(), gfm(), tlc(),
        PI.Source(domain = DC_CM), OuterActivePowerControl(), OuterActiveVdcControl(),
        OuterReactiveQControl(), OuterReactiveVacControl(), DCVoltageSupportLag(),
        VoltageSupportLag(), VSEWithDamping(pll = PLLSynchronization()), AVRSM())
        @test inputvalues(fresh) == declared_defaults(inputs(fresh))
    end
    for fixture in ParityFixtures.FIXTURES
        for (name, element) in pairs(fixture.build().elements)
            @testset "$(fixture.name).$name defaults" begin
                model = element
                declarations = inputs(model)
                defaults = declared_defaults(declarations)
                fresh = with_logger(NullLogger()) do
                    withinputs(model; defaults...)
                end
                @test inputs(fresh) == declarations
                @test inputvalues(fresh) == defaults
                check_tree(fresh)
            end
        end
    end
end

@testset "Declared ports match every fixture element" begin
    for fixture in ParityFixtures.FIXTURES
        state = fixture.build()
        for (name, element) in pairs(state.elements)
            @testset "$(fixture.name).$name" begin
                model = element
                ports = electricalconnections(model)
                sides = element_ports(model)
                @test Set(sides) == Set(keys(ports))
                @test length(ports) in (1, 2)
                for key in sides
                    rows = filter(row -> row.component == name && row.port == key,
                        state.topology.connections)
                    transformed = (first(rows).frame == :dq &&
                                   ports[key].domain === ACABC) ||
                                  (ports[key].domain === DC_CM && length(ports) == 2 &&
                                   physical_conductors(model) == 2)
                    actual = length(unique(rows.terminal))
                    @test actual == expected_pins(ports[key], model, transformed)
                end
                check_tree(model)
            end
        end
    end
end

@testset "Input declarations and defaults" begin
    declaration = Input(1.0; unit = "pu", type = Real, description = "Voltage")
    @test declaration.default === 1.0
    @test declaration.unit == "pu"
    @test declaration.type === Real
    @test declaration.description == "Voltage"
    @test inputs(Undeclared()) == (;)
    for (block, key, value) in (
        (OuterActivePowerControl(), :p_ref, 0.0),
        (OuterActiveVdcControl(), :v_dc_ref, 1.0),
        (OuterReactiveQControl(), :q_ref, 0.0),
        (OuterReactiveVacControl(), :v_ac_ref, 1.0),
        (VSEWithDamping(pll = PLLSynchronization()), :p_ref, 0.0),
        (DCVoltageSupportLag(), :v_dc_ref, 1.0),
        (VoltageSupportLag(), :v_ac_ref, 1.0),
        (AVRSM(), :v_ref, 1.01))
        @test inputs(block)[key].default === value
        @test inputs(block)[key].type === Float64
        @test inputvalues(block)[key] === value
        @test getfield(withinputs(block; NamedTuple{(key,)}((0.7,))...), key) === 0.7
        check_tree(block)
    end
    for block in (NoSynchronization(), NoOuterActiveControl(), NoFrequencySupport(),
        NoOuterReactiveControl(), NoVoltageSupport(), NoInnerVoltageControl(),
        NoInnerCurrentControl(), NoTotalEnergyControl(), NoZeroSequenceCurrentControl(),
        NoCirculatingCurrentSuppressionControl(), NoModulation(), PI.NoFilter())
        @test inputs(block) == (;)
        @test inputvalues(block) == (;)
    end
    @test inputs(inductionmachine()) == (;)
    defaults = (p_ac = 0.0, q_ac = 0.0, v_ac = 1.0, p_dc = 0.0, v_dc = 1.0)
    for m in (gfl(), gfm(), tlc())
        @test inputvalues(m).powerflow === defaults
    end
    m = gfl()
    @test keys(inputs(m)) == (:delta_control, :sigma_control, :sync, :powerflow)
    @test keys(inputs(m).delta_control) == (:outer_active, :outer_reactive, :occ)
    @test keys(inputs(m).delta_control.outer_active) == (:p_ref, :support)
    @test keys(inputs(m).delta_control.outer_reactive) == (:q_ref, :support)
    @test inputs(m).delta_control.outer_active.support == (;)
    @test inputs(m).delta_control.outer_reactive.support == (;)
    @test inputs(m).delta_control.occ == (;)
    @test inputs(m).sync == (;)
    @test keys(inputs(m).sigma_control) == (:tec, :zscc, :ccsc)
    @test all(isempty, inputs(m).sigma_control)
    @test keys(inputs(gfm()).delta_control) == (:outer_reactive, :vi, :occ)
    @test inputs(gfm()).delta_control.vi == (;)
    @test keys(inputs(gfm()).sync) == (:p_ref, :pll)
    @test inputs(gfm()).sync.pll == (;)
    @test keys(inputs(tlc())) ==
          (:sync, :outerActive, :outerReactive, :innerVoltage, :innerCurrent, :powerflow)
    lec = ΣdqzControlLEC(wsigma = ΣEnergyControl(pi_control = PIControl()),
        wdelta = ΔEnergyControl(pi_control = PIControl()),
        ccc = CirculatingCurrentControl(PIControl()))
    @test keys(inputs(lec)) ==
          (:wsigma, :wdelta, :ccc)
    sm = synchronousmachine()
    @test keys(inputs(sm)) == (:avr, :powerflow)
    @test inputvalues(sm) ==
          (avr = (v_ref = 1.01,), powerflow = (p = 0.0, q = 0.0, v = 1.0))
    @test inputvalues(ac_source()) ==
          (v = 220/sqrt(3), theta = 0.0, p = 0.0, q = 0.0)
    @test inputvalues(dc_source()) == (v = 240.0, p = 0.0)
    @test inputvalues(ac_source(v = 310.0, theta = 0.3, p = 120.0, q = -25.0)) ==
          (v = 310.0, theta = 0.3, p = 120.0, q = -25.0)
    @test inputvalues(dc_source(v = 650.0, p = -115.0)) ==
          (v = 650.0, p = -115.0)
    @test inputvalues(ac_source()).v == 220/sqrt(3)
    @test inputvalues(dc_source()).v == 240.0
    @test gfl(powerflow = (v_ac = 1.02,)).powerflow == merge(defaults, (v_ac = 1.02,))
    @test tlc(powerflow = (v_dc = 0.98,)).powerflow ==
          merge(defaults, (v_dc = 0.98,))
    @test synchronousmachine(powerflow = (q = 0.1,)).powerflow ==
          (p = 0.0, q = 0.1, v = 1.0)
    @test_throws r"powerflow.unknown" gfl(powerflow = (unknown = 1.0,))
    @test_throws r"powerflow.unknown" tlc(powerflow = (unknown = 1.0,))
    @test_throws r"powerflow.unknown" synchronousmachine(powerflow = (unknown = 1.0,))
end

@testset "Immutable input configuration and limits" begin
    model = gfl(outer_active = OuterActivePowerControl(
        support = DCVoltageSupportLag(), pi_ctrl = PIControl(Kp = 0.2, Ki = 1.0)))
    configured = withinputs(model;
        delta_control = (outer_active = (p_ref = 0.25, support = (v_dc_ref = 1.04,)),))
    @test configured !== model
    @test configured.delta_control !== model.delta_control
    @test configured.delta_control.outer_active !== model.delta_control.outer_active
    @test model.delta_control.outer_active.p_ref === 0.0
    @test model.delta_control.outer_active.support.v_dc_ref === 1.0
    @test configured.delta_control.outer_active.p_ref === 0.25
    @test configured.delta_control.outer_active.support.v_dc_ref === 1.04
    @test configured.delta_control.outer_reactive === model.delta_control.outer_reactive
    @test configured.delta_control.occ === model.delta_control.occ
    @test configured.sigma_control === model.sigma_control
    @test configured.sync === model.sync
    @test configured.meas === model.meas
    @test configured.modulation === model.modulation
    @test configured.elec === model.elec
    @test_throws r"delta_control.outer_active.p_reff" withinputs(model;
        delta_control = (outer_active = (p_reff = 0.1,),))
    @test withinputs(OuterActivePowerControl(); p_ref = 1).p_ref === 1.0
    promoted = withinputs(model; delta_control = (outer_active = (p_ref = 1,),))
    @test promoted.delta_control.outer_active.p_ref === 1.0
    @test_throws r"delta_control.outer_active.p_ref" withinputs(model;
        delta_control = (outer_active = (p_ref = "1",),))
    @test_throws r"delta_control.outer_active.support.v_dc_ref" withinputs(model;
        delta_control = (outer_active = (support = (v_dc_ref = "1.0",),),))
    @test_throws r"delta_control.outer_active" withinputs(model;
        delta_control = (outer_active = 0.1,))
    @test_throws r"unknown" withinputs(model; unknown = 0.0)
    promoted = withinputs(model; powerflow = (p_dc = 1,))
    @test promoted.powerflow.p_dc === 1.0
    @test_throws r"powerflow.p_ac" withinputs(model; powerflow = (p_ac = "1",))
    changed_limits = PI.Limits(P_min = -0.7, P_max = 0.8, Q_min = -0.3, Q_max = 0.4)
    configured = component(model; limits = changed_limits,
        delta_control = (outer_active = (p_ref = 0.4,),))
    @test limits(configured) === changed_limits
    @test configured.delta_control.outer_active.p_ref === 0.4
    @test model.limits === PI.Limits()
    @test component(model).limits === model.limits
    @test_throws ArgumentError component(PI.Impedance(); limits = changed_limits)
    @test_throws ArgumentError component(model; limits = "limits")
    partial = withinputs(gfl(powerflow = (p_dc = 0.3,)); powerflow = (v_ac = 1.02,))
    @test partial.powerflow.p_dc === 0.3
    @test partial.powerflow.v_ac === 1.02
    @test partial.powerflow.p_ac === 0.0
    @test_logs (:warn, r"MMC powerflow.p_ac") withinputs(model; powerflow = (p_ac = 0.2,))
    @test_logs (:warn, r"MMC powerflow.p_ac") component(model; powerflow = (p_ac = 0.2,))
    @test_logs withinputs(model; powerflow = (p_dc = 0.2,))
    @test_logs PI.powerflow_targets(model)
    tl = tlc(outerActive = OuterActiveVdcControl())
    @test_logs (:warn, r"TLC powerflow.v_dc") withinputs(tl; powerflow = (v_dc = 1.1,))
    @test_logs withinputs(tl; powerflow = (p_ac = 0.2,))
    for block in (OuterActiveVdcControl(filter = PI.Butterworth(order = 2, ωc = 20.0)),
        OuterReactiveVacControl(filter = PI.Butterworth(order = 2, ωc = 20.0)))
        key = first(keys(inputs(block)))
        updated = withinputs(block; NamedTuple{(key,)}((1.02,))...)
        @test updated.filter === block.filter
        @test updated.pi_ctrl === block.pi_ctrl
    end
    seeded = withinputs(synchronousmachine();
        avr = (v_ref = 1.04,), powerflow = (p = 0.2,))
    @test seeded.avr.v_ref === 1.04
    @test seeded.powerflow == (p = 0.2, q = 0.0, v = 1.0)
    machine = synchronousmachine()
    promoted = withinputs(machine; avr = (v_ref = 1,), powerflow = (p = 1,))
    @test promoted.avr.v_ref === 1.0
    @test promoted.powerflow.p === 1.0
    @test_throws r"avr.v_ref" withinputs(machine; avr = (v_ref = "1",))
    @test_throws r"powerflow.p" withinputs(machine; powerflow = (p = "1",))
end

@testset "Power-flow reference ownership" begin
    seeds = (p_ac = 0.51, q_ac = 0.52, v_ac = 1.03, p_dc = 0.54, v_dc = 1.05)
    for (active, active_values) in (
            (NoOuterActiveControl(), (;)),
            (OuterActivePowerControl(p_ref = 0.11), (p_ac = 0.11,)),
            (OuterActiveVdcControl(v_dc_ref = 1.12), (v_dc = 1.12,)),
            (
                OuterActivePowerControl(p_ref = 0.13,
                    support = DCVoltageSupportLag(v_dc_ref = 1.14)),
                (p_ac = 0.13, v_dc = 1.14))),
        (reactive, reactive_values) in (
            (NoOuterReactiveControl(), (;)),
            (OuterReactiveQControl(q_ref = -0.21), (q_ac = -0.21,)),
            (OuterReactiveVacControl(v_ac_ref = 1.22), (v_ac = 1.22,)),
            (
                OuterReactiveQControl(q_ref = -0.23,
                    support = VoltageSupportLag(v_ac_ref = 1.24)),
                (q_ac = -0.23, v_ac = 1.24)))

        models = (
            gfl(outer_active = active, outer_reactive = reactive, powerflow = seeds),
            tlc(outerActive = active, outerReactive = reactive,
                powerflow = seeds)
        )
        expected = merge(seeds, active_values, reactive_values)
        for model in models
            @test_logs @test PI.powerflow_targets(model) === expected
            check_tree(model)
            owned = merge(active_values, reactive_values)
            for key in keys(seeds)
                changes = NamedTuple{(key,)}((0.6,))
                if haskey(owned, key)
                    pattern = Regex("$(nameof(typeof(model))) powerflow.$key")
                    @test_logs (:warn, pattern) withinputs(model; powerflow = changes)
                else
                    @test_logs withinputs(model; powerflow = changes)
                end
            end
        end
    end
    for (reactive, references) in (
        (NoOuterReactiveControl(), (;)),
        (OuterReactiveQControl(q_ref = 0.21), (q_ac = 0.21,)),
        (OuterReactiveVacControl(v_ac_ref = 1.22), (v_ac = 1.22,)),
        (OuterReactiveQControl(q_ref = 0.23,
                support = VoltageSupportLag(v_ac_ref = 1.24)),
            (q_ac = 0.23, v_ac = 1.24)))
        m = withinputs(gfm(outer_reactive = reactive, powerflow = seeds);
            sync = (p_ref = 0.31,))
        @test PI.powerflow_targets(m) === merge(seeds, (p_ac = 0.31,), references)
        check_tree(m)
    end
    for fixture in ParityFixtures.FIXTURES, (name, m) in pairs(fixture.build().elements)

        m isa Union{MMC, TLC} || continue
        @testset "$(fixture.name).$name ownership" begin
            tree = inputvalues(m)
            expected = m.powerflow
            reference_values = Dict{Symbol, Float64}()
            function collect_references(tree)
                for (key, value) in pairs(tree)
                    if value isa NamedTuple
                        key == :powerflow || collect_references(value)
                    elseif key in (:p_ref, :q_ref, :v_ac_ref, :v_dc_ref)
                        quantity = Dict(:p_ref => :p_ac, :q_ref => :q_ac,
                            :v_ac_ref => :v_ac, :v_dc_ref => :v_dc)[key]
                        reference_values[quantity] = value
                    end
                end
            end
            collect_references(tree)
            for (key, value) in reference_values
                expected = merge(expected, NamedTuple{(key,)}((value,)))
            end
            @test PI.powerflow_targets(m) === expected
            @test PI.powerflow_targets(m).p_dc === m.powerflow.p_dc
        end
    end
end

@testset "Declarations leave converter calculation inputs unchanged" begin
    point = (ac = ACPortValues(310.0, 0.1, -80.0, 20.0),
        dc = DCPortValues(640.0, -80.0))
    for model in (gfl(),
        gfm(),
        tlc(outerActive = OuterActiveVdcControl(),
            outerReactive = OuterReactiveVacControl()))
        configured = with_logger(NullLogger()) do
            withinputs(model; powerflow = (p_ac = 0.2, q_ac = 0.1,
                v_ac = 1.04, p_dc = 0.3, v_dc = 1.05))
        end
        @test PI.pftoinputs(configured, point) == PI.pftoinputs(model, point)
    end
    configured = withinputs(gfl();
        delta_control = (outer_active = (p_ref = 0.9,), outer_reactive = (q_ref = 0.4,)))
    @test PI.pftoinputs(configured, point) == PI.pftoinputs(gfl(), point)
end

@testset "Component bases and stored limits" begin
    b = BaseValues(S = 300.0, v_ac = 20.0, v_dc = 150.0, omega = 100π)
    @test PI.i_ac(b) === 10.0
    @test PI.i_dc(b) === 2.0
    @test PI.z_ac(b) === 2.0
    @test BaseValues(S = 300.0, v_ac = 20.0, omega = 100π).v_dc === nothing
    mm = gfl()
    bm = bases(mm)
    @test (bm.S, bm.v_ac, bm.v_dc, bm.omega) ===
          (mm.elec.Sbase, mm.elec.vAC_base, mm.elec.vDC_base, mm.elec.ωbase)
    tl = tlc()
    bt = bases(tl)
    @test (bt.S, bt.v_ac, bt.v_dc, bt.omega) ===
          (tl.elec.Sbase, tl.elec.vACbase, tl.elec.vDCbase, tl.elec.ωbase)
    for (model, voltage) in (
        (synchronousmachine(), ElectricalSM().Vᵃᶜ_base),
        (inductionmachine(), ElectricalIM().Vac_base))
        b = bases(model)
        @test b.S === model.elec.S_base
        @test b.v_ac == voltage * sqrt(2/3)
        @test b.v_dc === nothing
        @test b.omega === model.elec.ωn
    end
    for model in passive_models(3)
        @test bases(model) === nothing
        @test limits(model) === nothing
    end
    @test limits(inductionmachine()) === nothing
    @test limits(Undeclared()) === nothing
    @test bases(ac_source()) === nothing
    @test bases(dc_source()) === nothing
    requested = PI.Limits(P_min = -10.0, P_max = 10.0, Q_min = -5.0, Q_max = 5.0)
    for element in (
        mmc(sync = PLLSynchronization(),
            delta_control = ΔdqControlGFL(outer_active = NoOuterActiveControl(),
                outer_reactive = NoOuterReactiveControl(),
                occ = NoInnerCurrentControl()),
            sigma_control = ΣdqzControlTEC(), limits = requested),
        tlc(limits = requested), synchronousmachine(),
        component(ac_source(); limits = requested), dc_source())
        @test limits(element) === element.limits
    end
    @test limits(ac_source()) === PI.Limits()
    for model in (tl, synchronousmachine(), ac_source(),
        dc_source())
        @test limits(component(model; limits = requested)) === requested
    end
end
end
