module PSCADSettlingTests
import ..PSCADFixtures
using Test, PowerImpedance
using ..PSCADFixtures: small_ac_network, dc_network, sm_network, tlc_case1_network
using ..PSCADResultsTests: synthetic_result, add_three_phase!
const P = PowerImpedance.PSCAD

@testset "PSCAD comparison settling" begin
    classic = small_ac_network()
    list = P.netlist(classic, compute(PowerFlowProblem(classic), ACDCPowerFlow()))
    probes = P.build_plan(list).probes
    model = PSCADModel("synthetic.pscx", "synthetic", list, probes,
        P.SimulationSettings(), list.operating_point, (;))
    times = collect(0.0:250e-6:0.3)
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    voltage = 380 / sqrt(3)
    current = voltage / (400 + 0.19 + 2π * 50 * 0.0122im)
    add_three_phase!(channels, "V_B1", times, sqrt(2) * voltage)
    add_three_phase!(channels, "V_B2", times, sqrt(2) * 400current)
    for (name, polarity) in (("I_source_ac", -1), ("I_line_side1", 1),
        ("I_line_side2", -1), ("I_load_side1", 1))
        add_three_phase!(channels, name, times, polarity * sqrt(2) * current)
    end
    result = synthetic_result(times, channels)
    table = compare_operating_point(result, model)
    @test propertynames(table) ==
          (:quantity, :name, :pscad, :powerflow, :error, :settling, :within_tolerance)
    @test all(table.within_tolerance)
    @test maximum(table.settling) < 1e-10
    for fraction in (-0.1, Inf, -Inf, NaN, nothing, 1im)
        @test_throws ArgumentError compare_operating_point(result, model;
            settling_fraction = fraction)
    end

    # The last ten cycles have midpoint 0.200125 s and half means 0.1 s apart.
    # The window mean agrees with the reference despite a 0.4% current change.
    ramped = deepcopy(channels)
    for index in 1:3
        ramped["I_line_side2:$index"] .*= 1 .+ 0.04 .* (times .- 0.200125)
    end
    ramp_result = synthetic_result(times, ramped)
    row = only(filter(r -> r.name == "I_line_side2",
        compare_operating_point(ramp_result, model)))
    @test row.error < 1e-7
    @test row.settling ≈ 0.004 atol = 1e-12
    @test !row.within_tolerance
    @test all(compare_operating_point(ramp_result, model;
        settling_fraction = 0.3).within_tolerance)
    @test all(compare_operating_point(ramp_result, model;
        rtol_i = 0.05).within_tolerance)

    growing = deepcopy(channels)
    for index in 1:3
        growing["I_line_side2:$index"] .*= exp.(4times) .*
                                      (1 .+ 0.3 .* sin.(2π * 5 .* times))
    end
    table = compare_operating_point(synthetic_result(times, growing), model)
    @test length(table) == 7
    @test all(isfinite, table.pscad)
    @test !only(filter(r -> r.name == "I_line_side2", table)).within_tolerance
    @test only(filter(r -> r.name == "I_line_side2", table)).settling > 0.002

    # Relative angles cross +/-180 degrees between halves; wrap their change.
    states = copy(model.operating_point.bus_states)
    b1, b2 = list.buses
    states[b2.key] = merge(states[b2.key], (; va_rad = states[b1.key].va_rad + π))
    point = P.OperatingPointRecord(states, model.operating_point.branch_flows,
        model.operating_point.values, model.operating_point.slack_bus,
        model.operating_point.bases)
    voltage_probes = P.ProbeManifest(filter(c -> c.kind == :voltage, probes.channels), "B1")
    angle_model = PSCADModel(model.project_path, model.project_name, list,
        voltage_probes, model.settings, point, (;))
    rotated = deepcopy(channels)
    angles = π .+ ifelse.(times .<= 0.2, -deg2rad(0.15), deg2rad(0.15))
    for index in 1:3
        rotated["V_B2:$index"] = sqrt(2) * abs(400current) .*
                                cos.(2π * 50 .* times .+ angles .- 2π * (index - 1) / 3)
    end
    row = only(filter(r -> r.quantity == :voltage_angle,
        compare_operating_point(synthetic_result(times, rotated), angle_model)))
    @test row.error < 1e-10
    @test row.settling ≈ 0.3 atol = 1e-10
    @test !row.within_tolerance

    # A common angle change cancels in the relative bus angle.
    for (name, phasor) in (("V_B1", voltage), ("V_B2", 400current)), index in 1:3
        rotated["$name:$index"] = sqrt(2) .* real.(phasor .* cis.(angles) .*
                                                cis.(2π * 50 .* times .- 2π * (index - 1) / 3))
    end
    table = compare_operating_point(synthetic_result(times, rotated), model)
    @test all(table.within_tolerance)
    @test only(filter(r -> r.quantity == :voltage_angle, table)).settling < 1e-10
end

@testset "PSCAD differential DC voltage settling" begin
    classic = dc_network()
    list = P.netlist(classic, compute(PowerFlowProblem(classic), ACDCPowerFlow()))
    probes = P.ProbeManifest(filter(c -> c.kind == :voltage && c.bus == "D1",
        P.build_plan(list).probes.channels), nothing)
    model = PSCADModel("synthetic.pscx", "synthetic", list, probes,
        P.SimulationSettings(), list.operating_point, (;))
    times = collect(0.0:250e-6:0.3)
    drift = 100 .* (times .- 0.200125)
    channels = PowerImpedance.OrderedDict("V_D1_P" => 320 .+ drift,
        "V_D1_N" => -320 .+ drift, "theta" => 2π * 50 .* times)
    row = only(compare_operating_point(synthetic_result(times, channels), model))
    @test row.pscad ≈ 640
    @test row.settling < 1e-12
    @test row.within_tolerance
    for (change, accepted) in ((0.0009, true), (0.0011, false))
        channels["V_D1_P"] = 320 .+ (640change / 0.1) .* (times .- 0.200125)
        channels["V_D1_N"] .= -320
        row = only(compare_operating_point(synthetic_result(times, channels), model))
        @test row.error < 1e-12
        @test row.settling ≈ change
        @test row.within_tolerance == accepted
    end
end

@testset "PSCAD rating-based settling near zero" begin
    classic = tlc_case1_network()
    list = P.netlist(classic, compute(PowerFlowProblem(classic), ACDCPowerFlow()))
    probes = P.ProbeManifest(filter(c -> c.kind in (:converter_p, :converter_q),
        P.build_plan(list).probes.channels), nothing)
    model = PSCADModel("synthetic.pscx", "synthetic", list, probes,
        P.SimulationSettings(), list.operating_point, (;))
    times = collect(0.0:250e-6:0.3)
    rating = only(filter(e -> e.name == :DUT, list.elements)).model.elec.Sbase
    flow = list.operating_point.branch_flows[:DUT]
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    for probe in probes.channels
        reference = (probe.kind == :converter_p ? flow.pt : flow.qt) / rating
        channels[probe.name] = reference .+ 2e-5 .* cos.(2π * 5 .* times)
    end
    table = compare_operating_point(synthetic_result(times, channels), model)
    active = only(filter(r -> r.quantity == :converter_p, table))
    @test abs(active.powerflow) < 1e-4
    @test 0 < active.settling < 4e-5
    @test all(table.within_tolerance)
    for (change, accepted) in ((0.0009, true), (0.0011, false))
        for probe in probes.channels
            reference = (probe.kind == :converter_p ? flow.pt : flow.qt) / rating
            channels[probe.name] = reference .+ (change / 0.1) .* (times .- 0.200125)
        end
        for row in compare_operating_point(synthetic_result(times, channels), model)
            @test row.error < 1e-12
            @test row.settling ≈ change
            @test row.within_tolerance == accepted
        end
    end
end

@testset "PSCAD machine phasor settling" begin
    classic = sm_network()
    list = P.netlist(classic, compute(PowerFlowProblem(classic), ACDCPowerFlow()))
    plan = P.build_plan(list)
    probes = P.ProbeManifest(filter(c -> c.kind == :voltage || c.name == "I_sg1_ac",
        plan.probes.channels), plan.probes.reference_bus)
    model = PSCADModel("synthetic.pscx", "synthetic", list, probes,
        P.SimulationSettings(), list.operating_point, (;))
    times = collect(0.0:250e-6:0.3)
    bus = only(list.buses)
    voltage = bus.vm_pu * bus.base_kV
    flow = list.operating_point.branch_flows[:sg1]
    power = complex(flow.pf, flow.qf)
    current = conj(power / (3voltage))
    rating = only(filter(e -> e.name == :sg1, list.elements)).model.elec.S_base
    delta = 0.01
    angles = ifelse.(times .<= 0.2, -delta, delta)
    channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
    add_three_phase!(channels, "V_Bus2", times, sqrt(2) * voltage)
    for index in 1:3
        channels["I_sg1_ac:$index"] = sqrt(2) .* real.(current .* cis.(angles) .*
                                                   cis.(2π * 50 .* times .- 2π * (index - 1) / 3))
    end
    table = compare_operating_point(synthetic_result(times, channels), model)
    p = only(filter(r -> r.quantity == :machine_p, table))
    q = only(filter(r -> r.quantity == :machine_q, table))
    @test p.error < 0.01
    @test q.error < 0.01
    @test p.settling ≈ 2abs(imag(power)) * sin(delta) / rating
    @test q.settling ≈ 2abs(real(power)) * sin(delta) / rating
    @test !q.within_tolerance
    @test only(filter(r -> r.quantity == :current_rms, table)).settling < 1e-12
    # Independently recorded exported machine impedance, in ohms.
    z = 0.37544 + 2π * 50 * 0.0298765659im
    expected = abs(abs(voltage - z * current * cis(delta)) -
                   abs(voltage - z * current * cis(-delta))) / flow.terminal_voltage_kV
    row = only(filter(r -> r.quantity == :machine_voltage, table))
    @test row.settling ≈ expected rtol = 1e-10
end

@testset "PSCAD machine speed settling" begin
    classic = sm_network()
    list = P.netlist(classic, compute(PowerFlowProblem(classic), ACDCPowerFlow()))
    probes = P.ProbeManifest(filter(c -> c.kind == :machine_speed,
        P.build_plan(list).probes.channels), nothing)
    model = PSCADModel("synthetic.pscx", "synthetic", list, probes,
        P.SimulationSettings(), list.operating_point, (;))
    times = collect(0.0:250e-6:0.3)
    name = only(probes.channels).name
    channels = PowerImpedance.OrderedDict(name => ones(length(times)))
    row = only(compare_operating_point(synthetic_result(times, channels), model;
        settling_fraction = 0))
    @test row.settling == 0
    @test row.within_tolerance
    for (change, accepted) in ((0.9e-4, true), (1.1e-4, false))
        channels[name] = 1 .+ (change / 0.1) .* (times .- 0.200125)
        row = only(compare_operating_point(synthetic_result(times, channels), model))
        @test row.error < 1e-12
        @test row.settling ≈ change
        @test row.within_tolerance == accepted
    end
end
end
