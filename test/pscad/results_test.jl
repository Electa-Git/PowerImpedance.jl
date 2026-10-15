module PSCADResultsTests
using Test, PowerImpedance
const P = PowerImpedance.PSCAD
const FIXTURES = normpath(joinpath(@__DIR__, "../data/pscad"))
using ..PSCADFixtures: small_ac_network, dc_network, sm_network, tlc_case1_network,
                       tlc_case2_network

function synthetic_result(time, channels; probes = P.ProbeManifest(), frequency = 50.0)
    settings = P.SimulationSettings(frequency = frequency, sample_step = 250e-6)
    return PSCADResult(PSCADRun(), time, channels, probes, settings, (;), (;))
end

function add_three_phase!(channels, name, times, phasor; negative = 0.0im, frequency = 50.0)
    for index in 1:3
        phase = cis(-2π * (index - 1) / 3)
        channels["$name:$index"] = real.((phasor * phase + negative / phase) .*
                                         cis.(2π * frequency .* times))
    end
end

@testset "PSCAD settled phasors" begin
    # Nonzero time origin detects a DFT that substitutes sample indices for
    # actual times. A large negative sequence must disappear from X_+.
    times = collect(range(0.0032; step = 250e-6, length = 1201))
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    add_three_phase!(channels, "V_B1", times, 125 * cis(0.42); negative = 80 * cis(-0.7))
    channels["scalar"] = 2.5 .+ 0.4 .* cos.(2π * 50 .* times)
    result = synthetic_result(times, channels)
    settled = P.steady_state(result)
    @test collect(keys(settled)) == ["V_B1", "scalar"]
    @test settled["V_B1"].dim == 3
    @test isapprox(settled["V_B1"].peak, 125; rtol = 1e-12)
    @test isapprox(settled["V_B1"].rms, 125 / sqrt(2); rtol = 1e-12)
    @test isapprox(settled["V_B1"].angle, 0.42; atol = 1e-12)
    @test settled["scalar"].dim == 1
    @test isapprox(settled["scalar"].mean, 2.5; atol = 1e-12)
    @test isapprox(P.steady_state(result; window_cycles = 1)["V_B1"].angle, 0.42; atol = 1e-12)
    # Fewer than ten cycles are acceptable if a complete cycle exists.
    short_times = times[1:81]
    short_channels = PowerImpedance.OrderedDict(name => values[1:81]
    for (name, values) in channels)
    @test isapprox(
        P.steady_state(synthetic_result(short_times, short_channels))["V_B1"].peak,
        125; rtol = 1e-12)
    incomplete = copy(channels)
    delete!(incomplete, "V_B1:2")
    @test_throws ArgumentError P.steady_state(synthetic_result(times, incomplete))
    for invalid in (0, -1, 1.5, true)
        @test_throws ArgumentError P.steady_state(result; window_cycles = invalid)
    end
    irregular = copy(times)
    irregular[100] += 1e-6
    @test_throws ArgumentError P.steady_state(synthetic_result(irregular, channels))
    noninteger = collect(range(0.0; step = 270e-6, length = length(times)))
    @test_throws ArgumentError P.steady_state(synthetic_result(noninteger, channels))
    @test_throws ArgumentError P.steady_state(synthetic_result(times[1:80],
        PowerImpedance.OrderedDict(name => values[1:80] for (name, values) in channels)))
    @test P._probe_present(
        P.ProbeChannel(
            "V_B1", :voltage, "B1", nothing, nothing, 3, "kV"), channels)
    @test !P._probe_present(
        P.ProbeChannel(
            "V_B1", :voltage, "B1", nothing, nothing, 3, "kV"), incomplete)
    @test P._probe_present(
        P.ProbeChannel(
            "scalar", :voltage, "B1", nothing, nothing, 1, "kV"), channels)
end

@testset "PSCAD steady-state settling diagnostic" begin
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict("I_settling" => 2 .* (1 .- exp.(-times ./ 0.08)))
    result = synthetic_result(times, channels)
    @test_logs (:warn,
        "channel not settled within the steady-state window; lengthen simulation_time") P.steady_state(result)
    channels["I_settling"] = fill(2.0, length(times))
    @test_logs P.steady_state(result)
    @test P.steady_state(result)["I_settling"] == (dim = 1, mean = 2.0)
    empty!(channels)
    add_three_phase!(channels, "V_settling", times, 100cis(0.2))
    for samples in values(channels)
        samples .*= 1 .- exp.(-times ./ 0.08)
    end
    @test_logs (:warn,
        "channel not settled within the steady-state window; lengthen simulation_time") P.steady_state(result)
    empty!(channels)
    add_three_phase!(channels, "V_settling", times, 100cis(0.2))
    @test_logs P.steady_state(result)
    # A single indexed scalar retains the same mean and warning contract.
    empty!(channels)
    channels["I_settling:1"] = 2 .* (1 .- exp.(-times ./ 0.08))
    @test_logs (:warn,
        "channel not settled within the steady-state window; lengthen simulation_time") P.steady_state(result)
    channels["I_settling:1"] = fill(2.0, length(times))
    @test_logs P.steady_state(result)
    @test P.STEADY_STATE_SETTLING_RTOL == 1e-3
end

@testset "PSCAD operating-point comparison" begin
    classic, state = small_ac_network()
    netlist = P.netlist(classic, power_flow(classic))
    plan = P.build_plan(netlist)
    model = PSCADModel("synthetic.pscx", "synthetic", netlist, plan.probes,
        P.SimulationSettings(), netlist.operating_point, (source = :fixture,))
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    # Independent circuit solution in phase RMS kV and kA. Shift the entire
    # PSCAD voltage reference to verify relative-angle comparison.
    source_voltage = 380 / sqrt(3)
    impedance_value = 0.19 + 2π * 50 * 0.0122im
    current = source_voltage / (400 + impedance_value)
    receiving_voltage = 400 * current
    offset = cis(0.52)
    add_three_phase!(channels, "V_B1", times, sqrt(2) * source_voltage * offset)
    add_three_phase!(channels, "V_B2", times, sqrt(2) * receiving_voltage * offset)
    for name in ("I_source_1", "I_line_1", "I_line_2", "I_load_1")
        add_three_phase!(channels, name, times, sqrt(2) * current * offset)
    end
    result = synthetic_result(times, channels; probes = plan.probes)
    comparison = compare_operating_point(result, model)
    @test length(comparison) == 7
    @test all(comparison.within_tolerance)
    @test maximum(comparison.error) < 1e-7
    @test count(==(:voltage_rms), comparison.quantity) == 2
    @test count(==(:voltage_angle), comparison.quantity) == 1
    @test count(==(:current_rms), comparison.quantity) == 4
    @test only(comparison.name[comparison.quantity .== :voltage_angle]) == "V_B2"
    @test isapprox(
        only(comparison.pscad[(comparison.quantity .== :current_rms) .& (comparison.name .== "I_load_1")]),
        abs(current); rtol = 1e-12)
    @test isapprox(abs(receiving_voltage) * sqrt(3), 379.80216745; atol = 1e-7)
    @test isapprox(abs(current), 0.548197209; atol = 1e-9)
    doubled = deepcopy(channels)
    for index in 1:3
        doubled["I_line_2:$index"] .*= 2
    end
    failed = compare_operating_point(synthetic_result(times, doubled), model)
    @test failed.name[.!failed.within_tolerance] == ["I_line_2"]
    # The two terminal power records must remain distinct, including receiving
    # reactive power. These independent records deliberately differ.
    flows = copy(model.operating_point.branch_flows)
    flows[:line] = (pf = 120.0, qf = 30.0, pt = -90.0, qt = -40.0)
    point = P.OperatingPointRecord(model.operating_point.bus_states, flows,
        model.operating_point.setpoints, model.operating_point.slack_bus, model.operating_point.bases)
    sides_model = PSCADModel(model.project_path, model.project_name, model.netlist,
        model.probes, model.settings, point, model.provenance)
    sides = compare_operating_point(result, sides_model)
    @test only(sides.powerflow[sides.name .== "I_line_1"]) ==
          hypot(120, 30) / (3 * source_voltage)
    @test only(sides.powerflow[sides.name .== "I_line_2"]) ==
          hypot(90, 40) / (3 * (netlist.buses[2].vm_pu * netlist.buses[2].base_kV))
    voltage_manifest = P.ProbeManifest(filter(c -> c.kind == :voltage, model.probes.channels), "B1")
    voltage_model = PSCADModel(model.project_path, model.project_name, model.netlist,
        voltage_manifest, model.settings, model.operating_point, model.provenance)
    @test length(compare_operating_point(result, voltage_model)) == 3
    missing = copy(channels)
    delete!(missing, "V_B1:3")
    @test_throws ArgumentError compare_operating_point(synthetic_result(times, missing), model)
    plain = P.netlist(state, nothing)
    no_pf = PSCADModel("synthetic.pscx", "synthetic", plain, plan.probes,
        model.settings, plain.operating_point, (;))
    @test_throws ArgumentError compare_operating_point(result, no_pf)
    delete!(flows, :line)
    @test_throws ArgumentError compare_operating_point(result, sides_model)
    @test_throws ArgumentError compare_operating_point(result, model; rtol_v = -1)
end

@testset "PSCAD DC operating-point comparison" begin
    classic, _ = dc_network()
    list = P.netlist(classic, power_flow(classic))
    plan = P.build_plan(list)
    model = PSCADModel("dc.pscx", "dc", list, plan.probes,
        P.SimulationSettings(), list.operating_point, (; source = :fixture))
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    add_three_phase!(channels, "V_BUS1", times, 320sqrt(2) * cis(0.23))
    add_three_phase!(channels, "I_ac_1", times, 0.8sqrt(2) * cis(0.23))
    add_three_phase!(channels, "I_ac_load_1", times, 0.8sqrt(2) * cis(0.23))
    for (bus, voltage) in (("D1", 320.0), ("D2", 318.0))
        # Common-mode offset cancels in the differential voltage. Integer-cycle
        # ripple averages to zero, exercising the actual scalar window means.
        channels["V_$(bus)_P"] = voltage .+ 1.7 .+ 0.4 .* cos.(2π * 50 .* times)
        channels["V_$(bus)_N"] = -voltage .+ 1.7 .+ 0.3 .* sin.(2π * 50 .* times)
    end
    for name in ("I_from_1", "I_to_1", "I_line_1", "I_line_2")
        channels[name] = -2.0 .+ 0.2 .* cos.(2π * 50 .* times)
    end
    result = synthetic_result(times, channels; probes = plan.probes)
    comparison = compare_operating_point(result, model)
    @test all(comparison.within_tolerance)
    @test count(==(:voltage_dc), comparison.quantity) == 2
    @test count(==(:current_dc), comparison.quantity) == 4
    @test comparison.powerflow[comparison.quantity .== :voltage_dc] ≈ [640.0, 636.0]
    @test comparison.powerflow[comparison.quantity .== :current_dc] ≈ fill(2.0, 4)
    @test maximum(comparison.error) < 1e-8
    perturbed = deepcopy(channels)
    perturbed["V_D2_P"] .+= 20.0
    perturbed["I_line_2"] .*= 1.1
    failed = compare_operating_point(synthetic_result(times, perturbed), model)
    @test Set(failed.name[.!failed.within_tolerance]) == Set(["V_D2", "I_line_2"])
    missing = copy(channels)
    delete!(missing, "V_D1_N")
    @test_throws ArgumentError compare_operating_point(synthetic_result(times, missing), model)
    manifest = P.ProbeManifest(filter(c -> c.name != "V_D1_N", plan.probes.channels), plan.probes.reference_bus)
    incomplete_model = PSCADModel(model.project_path, model.project_name, list,
        manifest, model.settings, model.operating_point, model.provenance)
    @test_throws ArgumentError compare_operating_point(result, incomplete_model)
    # No solved DC source power: omit its current row, keep voltage and branch
    # evidence. AC missing-data behavior remains unchanged.
    flows = copy(list.operating_point.branch_flows)
    delete!(flows, :from)
    point = P.OperatingPointRecord(list.operating_point.bus_states, flows,
        list.operating_point.setpoints, list.operating_point.slack_bus, list.operating_point.bases)
    partial = PSCADModel(model.project_path, model.project_name, list, plan.probes,
        model.settings, point, model.provenance)
    @test count(==(:current_dc), compare_operating_point(result, partial).quantity) == 3
end

@testset "PSCAD converter-connected DC current comparison" begin
    times = collect(0.0:250e-6:0.3)
    station_currents = Dict(
        "I_G_DC_1" => (7.837e-5, 2.66e-13),
        "I_DUT_1" => (-9.956e-5, 1.83e-14),
        "I_CableDC12_1" => (9.956e-5, 1.83e-14),
        "I_CableDC12_2" => (7.837e-5, 2.66e-13))
    for network in tlc_case1_network()
        solved = network isa Network ? power_flow(network) :
                 NetworkBuilder.solve(network).powerflow
        list = P.netlist(network, solved)
        plan = P.build_plan(list)
        dc_buses = Set(b.name for b in list.buses if b.kind == :dc)
        probes = P.ProbeManifest(
            filter(c -> c.kind == :current && c.bus in dc_buses, plan.probes.channels), nothing)
        model = PSCADModel("synthetic.pscx", "synthetic", list, probes,
            P.SimulationSettings(), list.operating_point, (; source = :fixture))
        converter = only(filter(e -> e.model isa PowerImpedance.TLC, list.elements))
        base = converter.model.elec.Sbase / converter.model.elec.vDCbase
        @test base == 0.15625
        @test Set(c.name for c in probes.channels) == Set(keys(station_currents))
        @test P._dc_converter_current_bases(list) ==
              Dict(b.key => base for b in list.buses if b.kind == :dc)
        channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
        function set_reference!(probe, reference)
            bus = only(filter(b -> b.name == probe.bus, list.buses))
            e = only(filter(e -> string(e.name) == probe.element, list.elements))
            field = e.model isa PowerImpedance.Source ? :pgdc :
                    probe.side == "1" ? :pf : :pt
            flow = list.operating_point.branch_flows[e.name]
            list.operating_point.branch_flows[e.name] = merge(flow,
                NamedTuple{(field,)}((-reference * 2bus.base_kV * bus.vm_pu,)))
        end
        for probe in probes.channels
            measured, reference = station_currents[probe.name]
            channels[probe.name] = fill(measured, length(times))
            set_reference!(probe, reference)
        end
        rows = compare_operating_point(synthetic_result(times, channels), model)
        @test length(rows) == 4
        for row in rows
            measured, reference = station_currents[row.name]
            @test row.quantity == :current_dc
            @test row.pscad ≈ abs(measured)
            @test row.powerflow ≈ reference
            @test row.error ≈ abs(abs(measured) - reference) / base
            @test row.within_tolerance
        end
        # Exact zero and either sign of near-zero mean use the same base;
        # references above the base recover the existing relative rule.
        for reference in (0.0, 1e-13, 0.5), deviation in (0.019, 0.021), sign in (-1, 1)
            denominator = max(reference, base)
            for probe in probes.channels
                set_reference!(probe, reference)
                channels[probe.name] .= sign * (reference + deviation * denominator)
            end
            for row in compare_operating_point(synthetic_result(times, channels), model)
                @test row.error ≈ deviation
                @test row.within_tolerance == (deviation < 0.02)
            end
        end
        for probe in probes.channels
            set_reference!(probe, 0.0)
            channels[probe.name] .= 0.0
        end
        @test all(iszero, compare_operating_point(synthetic_result(times, channels), model).error)

        # Removing the cable separates the source DC bus from the converter.
        # Their grounded terminals do not join DC-domain components.
        disconnected = P.Netlist(list.buses,
            filter(e -> e.name != :CableDC12, list.elements), list.operating_point,
            list.voltageBase, list.frequency)
        terminal = only(filter(t -> t.bus !== nothing && t.bus.domain == 2, converter.terminals))
        @test P._dc_converter_current_bases(disconnected) == Dict(terminal.bus => base)

        remote_bus = only(filter(b -> b.kind == :dc && b.key != terminal.bus, list.buses))
        second_terminals = [P.Terminal(:DUT2, t.side, t.terminals, t.nets,
                                t.bus == terminal.bus ? remote_bus.key : t.bus, t.grounded)
                            for t in converter.terminals]
        same_base = P.NetlistElement(:DUT2, "DUT2", converter.element, converter.model,
            second_terminals, converter.role, converter.setpoint)
        shared = P.Netlist(list.buses, [list.elements; same_base], list.operating_point,
            list.voltageBase, list.frequency)
        @test P._dc_converter_current_bases(shared) ==
              Dict(b.key => base for b in list.buses if b.kind == :dc)
        different_element = tlc(elec = PowerImpedance.ElectricalTLC(Sbase = 200.0,
            vDCbase = 640.0))
        different_base = P.NetlistElement(:DUT2, "DUT2", different_element,
            different_element.element_model, second_terminals, converter.role, converter.setpoint)
        mixed = P.Netlist(
            list.buses, [list.elements; different_base], list.operating_point,
            list.voltageBase, list.frequency)
        @test_throws ArgumentError P._dc_converter_current_bases(mixed)
        # The two converters share their AC bus, but removing the cable
        # leaves independent DC components with independent current bases.
        separate = P.Netlist(list.buses, [disconnected.elements; different_base],
            list.operating_point, list.voltageBase, list.frequency)
        @test P._dc_converter_current_bases(separate) ==
              Dict(terminal.bus => base, remote_bus.key => 0.3125)
    end

    # Converter-free DC components keep the previous relative/zero rule.
    classic, _ = dc_network()
    list = P.netlist(classic, power_flow(classic))
    @test isempty(P._dc_converter_current_bases(list))
    plan = P.build_plan(list)
    probes = P.ProbeManifest(filter(c -> c.name == "I_line_1", plan.probes.channels), nothing)
    model = PSCADModel("synthetic.pscx", "synthetic", list, probes,
        P.SimulationSettings(), list.operating_point, (; source = :fixture))
    probe = only(probes.channels)
    bus = only(filter(b -> b.name == probe.bus, list.buses))
    flow = list.operating_point.branch_flows[:line]
    for reference in (2.0, 1e-13, 0.0), measured in (0.0, 7.837e-5, 2.02)

        list.operating_point.branch_flows[:line] = merge(flow,
            (; pf = reference * 2bus.base_kV * bus.vm_pu))
        channels = PowerImpedance.OrderedDict(probe.name => fill(measured, length(times)))
        row = only(compare_operating_point(synthetic_result(times, channels), model))
        expected = iszero(reference) ? (iszero(measured) ? 0.0 : Inf) :
                   abs(measured - reference) / reference
        @test row.error ≈ expected
        @test row.within_tolerance == (expected <= 0.02)
    end
end

@testset "PSCAD settings and existing-project types" begin
    settings = P.SimulationSettings()
    @test settings.simulation_time == 2.0
    @test settings.time_step == 10e-6
    @test settings.sample_step == 100e-6
    @test settings.snapshot_time === nothing
    @test settings.output_stem == "pi"
    @test settings.frequency == 50.0
    @test settings.source_ramp == 0.05
    @test P.SimulationSettings(source_ramp = 0).source_ramp == 0.0
    for value in (-1, Inf, NaN, true)
        @test_throws ArgumentError P.SimulationSettings(source_ramp = value)
    end
    for field in (:simulation_time, :time_step, :sample_step, :frequency),
        value in (0, -1, Inf, NaN, true)

        @test_throws ArgumentError P.SimulationSettings(; (field => value,)...)
    end
    for value in (0, -1, 3.0, Inf, NaN, true)
        @test_throws ArgumentError P.SimulationSettings(snapshot_time = value)
    end
    @test P.SimulationSettings(snapshot_time = 2).snapshot_time == 2.0
    @test_throws ArgumentError P.SimulationSettings(sample_step = 1e-6)
    for value in ("", "1bad", "bad-stem", repeat("a", 21), "café", "pi/escape")
        @test_throws ArgumentError P.SimulationSettings(output_stem = value)
    end
    @test isempty(P.ProbeManifest().channels)
    @test PSCADRun() isa AbstractFormulation
    @test PSCADRun().backend === P.PSCADBackend
    @test PowerImpedance._default_backend(PSCADRun) === P.PSCADBackend
    mktempdir() do root
        path = joinpath(root, "handbuilt.pscx")
        write(path, "fixture")
        model = PSCADModel(path)
        @test model.project_path == path
        @test model.project_name == "handbuilt"
        @test model.netlist === nothing
        @test model.operating_point === nothing
        @test model.provenance == (source = :file,)
        @test_throws ArgumentError PSCADModel(path * "missing")
        other = joinpath(root, "bad.txt")
        write(other, "fixture")
        @test_throws ArgumentError PSCADModel(other)
    end
end

@testset "PSCAD machine network-side comparison policy" begin
    classic, _ = sm_network()
    netlist = P.netlist(classic, power_flow(classic))
    plan = P.build_plan(netlist)
    model = PSCADModel("synthetic.pscx", "synthetic", netlist, plan.probes,
        P.SimulationSettings(), netlist.operating_point, (source = :fixture,))
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    flow = netlist.operating_point.branch_flows[:sg1]
    bus = only(netlist.buses)
    voltage = bus.vm_pu * bus.base_kV
    for channel in plan.probes.channels
        if channel.kind == :voltage
            add_three_phase!(channels, channel.name, times, sqrt(2) * voltage)
        elseif channel.kind == :current
            element_flow = netlist.operating_point.branch_flows[Symbol(channel.element)]
            power = channel.element == "sg1" ? complex(element_flow.pf, element_flow.qf) :
                    complex(element_flow.pg, element_flow.qg)
            add_three_phase!(channels, channel.name, times,
                sqrt(2) * conj(power / (3voltage)))
        else
            channels[channel.name] = fill(channel.kind == :machine_speed ? 1.0 : -123.0,
                length(times))
        end
    end
    comparison = compare_operating_point(synthetic_result(times, channels), model)
    @test all(comparison.within_tolerance)
    @test Set(comparison.quantity) == Set([:voltage_rms, :current_rms,
        :machine_p, :machine_q, :machine_voltage, :machine_speed])
    for quantity in (:machine_p, :machine_q, :machine_voltage)
        @test only(filter(r -> r.quantity == quantity, comparison)).name == "I_sg1_1"
    end
    vt = only(filter(r -> r.quantity == :machine_voltage, comparison))
    @test vt.pscad ≈ flow.terminal_voltage_kV rtol = 1e-8
    @test vt.powerflow == flow.terminal_voltage_kV
    p = only(filter(r -> r.quantity == :machine_p, comparison))
    q = only(filter(r -> r.quantity == :machine_q, comparison))
    @test p.pscad ≈ flow.pf
    @test q.pscad ≈ flow.qf
    @test p.powerflow == flow.pf != flow.pg
    @test q.powerflow == flow.qf != flow.qg
    diagnostics = filter(
        c -> c.kind in (:machine_p, :machine_q,
            :machine_voltage, :machine_diagnostic),
        plan.probes.channels)
    @test isempty(intersect(Set(comparison.name), Set(c.name for c in diagnostics)))
    settled = P.steady_state(synthetic_result(times, channels))
    for channel in diagnostics
        @test settled[channel.name].mean == -123.0
    end
    missing_diagnostics = copy(channels)
    for channel in diagnostics
        delete!(missing_diagnostics, channel.name)
    end
    @test compare_operating_point(synthetic_result(times, missing_diagnostics), model) ==
          comparison
    wrong_diagnostic_dimension = copy(channels)
    delete!(wrong_diagnostic_dimension, "sg1_Vt")
    add_three_phase!(wrong_diagnostic_dimension, "sg1_Vt", times, 9.0)
    @test compare_operating_point(synthetic_result(times, wrong_diagnostic_dimension), model) ==
          comparison

    # Independently specified balanced sinusoids: 2 kA RMS at 0.8 power factor,
    # including leading current and reversal of both active and reactive power.
    angle = 0.37
    lag = atan(0.6, 0.8)
    for (current, expected) in (
        (2sqrt(2) * cis(angle - lag), complex(3voltage * 2 * 0.8, 3voltage * 2 * 0.6)),
        (2sqrt(2) * cis(angle + lag), complex(3voltage * 2 * 0.8, -3voltage * 2 * 0.6)),
        (-2sqrt(2) * cis(angle - lag), -complex(3voltage * 2 * 0.8, 3voltage * 2 * 0.6)))
        measured = deepcopy(channels)
        add_three_phase!(measured, "V_Bus2", times, sqrt(2) * voltage * cis(angle))
        add_three_phase!(measured, "I_sg1_1", times, current)
        table = compare_operating_point(synthetic_result(times, measured), model)
        @test only(filter(r -> r.quantity == :machine_p, table)).pscad ≈ real(expected)
        @test only(filter(r -> r.quantity == :machine_q, table)).pscad ≈ imag(expected)
    end

    # The 1000 MVA rating governs both power errors, even for zero reference Q.
    flows = copy(model.operating_point.branch_flows)
    flows[:sg1] = merge(flow, (pf = 600.0, qf = 0.0))
    point = P.OperatingPointRecord(model.operating_point.bus_states, flows,
        model.operating_point.setpoints, model.operating_point.slack_bus,
        model.operating_point.bases)
    reference = PSCADModel(model.project_path, model.project_name, netlist,
        plan.probes, model.settings, point, model.provenance)
    for (power, error, accepted) in ((609.0 + 9im, 0.009, true),
        (591.0 - 9im, 0.009, true), (611.0 + 11im, 0.011, false))
        measured = deepcopy(channels)
        add_three_phase!(measured, "I_sg1_1", times, sqrt(2) * conj(power / (3voltage)))
        table = compare_operating_point(synthetic_result(times, measured), reference)
        for quantity in (:machine_p, :machine_q)
            row = only(filter(r -> r.quantity == quantity, table))
            @test row.error ≈ error
            @test row.within_tolerance == accepted
        end
    end
    index = findfirst(e -> e.name == :sg1, netlist.elements)
    e = netlist.elements[index]
    rated = deepcopy(e.element)
    rated.element_model = SynchronousMachine(
        ElectricalSM(Vᵃᶜ_base = 380.0, S_base = 2000.0),
        e.model.mech, e.model.avr, e.model.gov)
    elements = copy(netlist.elements)
    elements[index] = P.NetlistElement(e.name, e.pscad, rated, rated.element_model,
        e.terminals, e.role, e.setpoint)
    rated_netlist = P.Netlist(
        netlist.buses, elements, point, netlist.voltageBase, netlist.frequency)
    rated_model = PSCADModel(model.project_path, model.project_name, rated_netlist,
        plan.probes, model.settings, point, model.provenance)
    measured = deepcopy(channels)
    add_three_phase!(measured, "I_sg1_1", times, sqrt(2) * conj((609.0 + 9im) / (3voltage)))
    rated_table = compare_operating_point(synthetic_result(times, measured), rated_model)
    for quantity in (:machine_p, :machine_q)
        @test only(filter(r -> r.quantity == quantity, rated_table)).error ≈ 0.0045
    end

    # Known exported R = 0.37544 ohm and L = 0.0298765659 H. The measured
    # bus current is in kA, so their drop reconstructs phase RMS terminal kV.
    measured = deepcopy(channels)
    add_three_phase!(measured, "I_sg1_1", times, sqrt(2) * (2.0 - 1im))
    expected_terminal = abs(voltage + (0.37544 + 2π * 50 * 0.0298765659im) * (2.0 - 1im))
    table = compare_operating_point(synthetic_result(times, measured), model)
    @test only(filter(r -> r.quantity == :machine_voltage, table)).pscad ≈ expected_terminal rtol = 1e-12
    flows[:sg1] = merge(flow, (terminal_voltage_kV = expected_terminal / 1.005,))
    for (rtol_v, accepted) in ((0.004, false), (0.006, true))
        row = only(filter(r -> r.quantity == :machine_voltage,
            compare_operating_point(synthetic_result(times, measured), reference; rtol_v)))
        @test row.error ≈ 0.005
        @test row.within_tolerance == accepted
    end

    for (speed, expected) in ((1.0009, true), (0.9991, true), (1.0011, false), (
        0.9989, false))
        changed = deepcopy(channels)
        changed["sg1_speed"] .= speed
        row = only(filter(r -> r.quantity == :machine_speed,
            compare_operating_point(synthetic_result(times, changed), model)))
        @test row.within_tolerance == expected
        @test row.error ≈ abs(speed - 1)
    end
    for name in ("sg1_speed", "V_Bus2:2", "I_sg1_1:3")
        missing = copy(channels)
        delete!(missing, name)
        @test_throws ArgumentError compare_operating_point(synthetic_result(times, missing), model)
    end
    manifest = P.ProbeManifest(filter(c -> c.name != "V_Bus2", plan.probes.channels),
        plan.probes.reference_bus)
    incomplete = PSCADModel(model.project_path, model.project_name, netlist,
        manifest, model.settings, model.operating_point, model.provenance)
    @test_throws ArgumentError compare_operating_point(synthetic_result(times, channels), incomplete)
end

@testset "PSCAD INF and legacy output parser" begin
    expected = ["V_BUS:1", "V_BUS:2", "Voltage", "right:Voltage", "Repeated",
        "main:Repeated", "Café", "main:Repeated:2", "C9", "C10", "C11", "C12"]
    @test P.parse_inf(joinpath(FIXTURES, "fixture.inf")) == expected
    result = read_pscad_output(FIXTURES; stem = "fixture")
    @test result.time == [0.0, 0.25, 0.5]
    @test collect(keys(result.channels)) == expected
    @test result.channels["C12"] == [12.0, 112.0, 212.0]
    @test result.channels["V_BUS:1"] == [1.0, 101.0, 201.0]
    @test basename.(result.outs) == ["fixture_01.out", "fixture_02.out"]
    @test P._data_rows(first(result.outs)) == 3
    for (text, value) in ((".5D+1", 5.0), ("-.5d+1", -5.0), ("1.25-02", 0.0125))
        @test P._pscad_number(text) == value
    end
    @test_throws ArgumentError P._pscad_number("invalid")
    @test_throws ArgumentError read_pscad_output(FIXTURES; stem = "malformed")
    mktempdir() do root
        for name in ("fixture.inf", "fixture_01.out", "fixture_02.out")
            cp(joinpath(FIXTURES, name), joinpath(root, name))
        end
        @test P._wait_outputs(
            [root, root], "fixture", 3; timeout = 1, poll_interval = 0.01).outs ==
              [joinpath(root, basename(path)) for path in result.outs]
        original = read(joinpath(root, "fixture_02.out"), String)
        for text in ("0 11 12\n0.25 111 112\n", "0 11 12\n0 111 112\n0.5 211 212\n",
            "0 11 12\n0.25 Inf 112\n0.5 211 212\n", "0 11\n0.25 111 112\n0.5 211 212\n",
            "0 11 12\n0.3 111 112\n0.5 211 212\n")
            write(joinpath(root, "fixture_02.out"), text)
            @test_throws ArgumentError read_pscad_output(root; stem = "fixture")
        end
        write(joinpath(root, "fixture_02.out"), original)
        duplicate = mkpath(joinpath(root, "duplicate"))
        cp(joinpath(root, "fixture.inf"), joinpath(duplicate, "fixture.inf"))
        @test_throws ArgumentError P._wait_outputs(
            [root], "fixture", 3; timeout = 0.1, poll_interval = 0.01)
        rm(duplicate; recursive = true)
        rm(joinpath(root, "fixture_02.out"))
        @test_throws ArgumentError read_pscad_output(root; stem = "fixture")
        caught = try
            P._wait_outputs([root], "fixture", 3; timeout = 0.05, poll_interval = 0.01)
        catch error
            error
        end
        @test caught isa ArgumentError
        @test occursin("OUT files found", sprint(showerror, caught))
        @test occursin("rows per file", sprint(showerror, caught))
        @test occursin("[3]", sprint(showerror, caught))
    end
end

@testset "PSCAD TLC power signs, units and rating normalization" begin
    classic, _ = tlc_case2_network()
    netlist = P.netlist(classic, power_flow(classic))
    settings = P.SimulationSettings(source_ramp = 0.05)
    plan = P.build_plan(netlist; settings)
    model = PSCADModel("synthetic.pscx", "synthetic", netlist, plan.probes,
        settings, netlist.operating_point, (source = :fixture,))
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    converter = only(filter(e -> e.model isa PowerImpedance.TLC, netlist.elements))
    flow = netlist.operating_point.branch_flows[:DUT]
    @test flow.pt == -flow.pgrid
    @test flow.qt == -flow.qgrid
    @test flow.pt ≈ converter.setpoint.Pac
    @test flow.qt ≈ converter.setpoint.Qac
    for channel in plan.probes.channels
        bus = only(filter(b -> b.name == channel.bus, netlist.buses))
        voltage = bus.base_kV * bus.vm_pu
        if channel.kind == :voltage
            if bus.kind == :dc
                channels[channel.name] = fill(channel.side == "P" ? voltage : -voltage, length(times))
            else
                add_three_phase!(channels, channel.name, times, sqrt(2) * voltage *
                                                                cis(bus.va_rad))
            end
        elseif channel.kind == :current
            e = only(filter(e -> string(e.name) == channel.element, netlist.elements))
            f = netlist.operating_point.branch_flows[e.name]
            if bus.kind == :dc
                key = e.model isa PowerImpedance.Source ? :pgdc :
                      channel.side == "1" ? :pf : :pt
                channels[channel.name] = fill(haskey(f, key) ? f[key] / (2voltage) : 0.0, length(times))
            else
                keys = e.model isa PowerImpedance.Source ? (:pg, :qg) :
                       channel.side == "1" ? (:pf, :qf) : (:pt, :qt)
                current = sqrt(2) * conj(complex(f[keys[1]], f[keys[2]]) /
                               (3voltage * cis(bus.va_rad)))
                add_three_phase!(channels, channel.name, times, current)
            end
        else
            reference = channel.kind == :converter_p ?
                        flow.pt / converter.model.elec.Sbase :
                        channel.kind == :converter_q ?
                        flow.qt / converter.model.elec.Sbase : -123.0
            channels[channel.name] = fill(reference, length(times))
        end
    end
    table = compare_operating_point(synthetic_result(times, channels), model)
    @test all(table.within_tolerance)
    @test count(r -> r.name == "I_DUT_2" && r.quantity in (:converter_p, :converter_q), table) ==
          2
    for quantity in (:converter_p, :converter_q)
        row = only(filter(r -> r.quantity == quantity && r.name == "I_DUT_2", table))
        @test row.powerflow == (quantity == :converter_p ? flow.pt : flow.qt)
        internal = only(filter(r -> r.quantity == quantity && r.name != "I_DUT_2", table))
        @test internal.powerflow == row.powerflow / 100.0
        @test internal.pscad ≈ internal.powerflow
    end
    ac_bus = only(filter(b -> b.kind != :dc, netlist.buses))
    solved_voltage = ac_bus.vm_pu * ac_bus.base_kV * cis(ac_bus.va_rad)
    for deviation in (0.009, 0.011)
        measured = deepcopy(channels)
        add_three_phase!(measured, "I_DUT_2", times,
            sqrt(2) * conj(complex(flow.pt + 100deviation, flow.qt - 100deviation) /
                 (3solved_voltage)))
        changed = compare_operating_point(synthetic_result(times, measured), model)
        for quantity in (:converter_p, :converter_q)
            row = only(filter(r -> r.quantity == quantity && r.name == "I_DUT_2", changed))
            @test row.error ≈ deviation
            @test row.within_tolerance == (deviation < 0.01)
        end
    end
    for (probe, quantity) in (("DUT_P_ac_f", :converter_p), ("DUT_Q_ac_f", :converter_q)),
        deviation in (0.009, 0.011)

        measured = deepcopy(channels)
        measured[probe] .+= deviation
        row = only(filter(r -> r.name == probe,
            compare_operating_point(synthetic_result(times, measured), model)))
        @test row.error ≈ deviation
        @test row.within_tolerance == (deviation < 0.01)
        @test row.quantity == quantity
    end
    wrong_sign = deepcopy(channels)
    wrong_sign["DUT_Q_ac_f"] .*= -1
    row = only(filter(r -> r.name == "DUT_Q_ac_f",
        compare_operating_point(synthetic_result(times, wrong_sign), model)))
    @test row.error ≈ 2abs(flow.qt) / converter.model.elec.Sbase
    @test !row.within_tolerance
    wrong_units = deepcopy(channels)
    wrong_units["DUT_P_ac_f"] .*= 100
    @test !only(filter(r -> r.name == "DUT_P_ac_f",
        compare_operating_point(synthetic_result(times, wrong_units), model))).within_tolerance
    @test isempty(intersect(Set(table.name), Set((
        "DUT_v_dc_f", "DUT_omega_c", "DUT_theta_c"))))
    missing = deepcopy(channels)
    delete!(missing, "DUT_Q_ac_f")
    @test_throws ArgumentError compare_operating_point(synthetic_result(times, missing), model)

    # Both 640 kV DC ends put case 1 near zero P. A 117 W discrepancy must
    # use the 100 MVA rating rather than the approximately 3.2 kW reference.
    case1, _ = tlc_case1_network()
    list1 = P.netlist(case1, power_flow(case1))
    flow1 = list1.operating_point.branch_flows[:DUT]
    rating = only(filter(e -> e.name == :DUT, list1.elements)).model.elec.Sbase
    internal_probes = P.ProbeManifest(
        filter(c -> c.kind in (:converter_p, :converter_q),
            plan.probes.channels), nothing)
    internal_model = PSCADModel("synthetic.pscx", "synthetic", list1, internal_probes,
        settings, list1.operating_point, (source = :fixture,))
    internal_channels = PowerImpedance.OrderedDict(
        "DUT_P_ac_f" => fill(-3.083e-5, length(times)),
        "DUT_Q_ac_f" => fill(flow1.qt / rating, length(times)))
    internal_table = compare_operating_point(
        synthetic_result(times, internal_channels), internal_model)
    active = only(filter(r -> r.quantity == :converter_p, internal_table))
    @test rating == 100.0
    @test round(active.powerflow; sigdigits = 6) == -3.2e-5
    @test active.powerflow == flow1.pt / rating
    @test active.error ≈ abs(active.pscad * rating - flow1.pt) / rating
    @test round(active.error * rating * 1e6) == 117.0
    @test active.within_tolerance
    @test all(internal_table.within_tolerance)

    # Zero and negative solved powers have the same rating-based threshold.
    for reference in (0.0, -0.5), deviation in (0.009, 0.011)

        list1.operating_point.branch_flows[:DUT] = merge(
            flow1, (; pt = reference * rating, qt = reference * rating))
        for probe in ("DUT_P_ac_f", "DUT_Q_ac_f")
            internal_channels[probe] .= reference - deviation
        end
        changed = compare_operating_point(
            synthetic_result(times, internal_channels), internal_model)
        for row in changed
            @test row.powerflow == reference
            @test row.error ≈ deviation
            @test row.within_tolerance == (deviation < 0.01)
        end
    end
end

@testset "PSCAD large output completion" begin
    mktempdir() do root
        write(joinpath(root, "large.inf"), "PGB(1) Desc=\"Voltage\" Group=\"\"\n")
        path = joinpath(root, "large_01.out")
        write(path, "0.0 1.0\n")
        P._wait_outputs([root], "large", 1; timeout = 5.0, poll_interval = 0.001)
        rows = 1_000_000
        open(path, "w") do io
            for _ in 1:rows
                println(io, "0.0 1.0")
            end
        end
        # The stability timeout excludes the subsequent large row count.
        elapsed = @elapsed files = P._wait_outputs([root], "large", rows;
            timeout = 0.1, poll_interval = 0.001)
        @test files.outs == [path]
        @test elapsed > 0.1
        @test_throws r"rows per file: \[1000000\]; expected 1000001" P._wait_outputs(
            [root], "large", rows + 1; timeout = 0.1, poll_interval = 0.001)
    end
end

@testset "PSCAD buffered output completion" begin
    mktempdir() do root
        write(joinpath(root, "buffered.inf"), "PGB(1) Desc=\"Voltage\" Group=\"\"\n")
        path = joinpath(root, "buffered_01.out")
        write(path, "0.0 1.0\n")
        writer = @async begin
            sleep(0.2)
            open(path, "a") do io
                println(io, "0.1 2.0")
            end
        end
        try
            @test P._wait_outputs([root], "buffered", 2;
                timeout = 5.0, poll_interval = 0.01).outs == [path]
        finally
            wait(writer)
        end
    end
end

end
