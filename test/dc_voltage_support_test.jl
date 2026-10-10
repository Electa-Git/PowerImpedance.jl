module DCVoltageSupportTests
using Test, PowerImpedance, LinearAlgebra, Logging
const PI = PowerImpedance
const NB = PI.NetworkBuilder
include("legacy_mmc_reference.jl")

active(m::MMC) = m.delta_control.outer_active
active(m::TLC) = m.outerActive

function converter(kind; K = 5.0, voltage = 672.0, dcbase = 640.0)
    point = Setpoint(Pac = 50.0, Qac = 25.0, Vac = 380sqrt(2/3), Vdc = voltage, Pdc = 50.0)
    limits = PI.Limits(P_min = -100.0, P_max = 100.0, Q_min = -50.0, Q_max = 50.0)
    outer = OuterActivePowerControl(pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0),
        support = DCVoltageSupportLag(; K, ωc = 2.0))
    reactive = OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0))
    sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.085, Ki = 32.0))
    occ = InnerCurrentPIControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 43.0))
    return kind === :mmc ? mmc(
        elec = ElectricalMMC(Sbase = 500.0, vDC_base = dcbase),
        delta_control = ΔdqControlGFL(outer_active = outer, outer_reactive = reactive, occ = occ),
        sigma_control = ΣdqzControlTEC(
            tec = TotalEnergyControl(pi_control = PIControl(Kp = 1.4, Ki = 30.0)),
            zscc = ZeroSequenceCurrentControl(PIControl(Kp = 0.1, Ki = 43.0)),
            ccsc = CirculatingCurrentSuppressionControl(PIControl(Kp = 0.1, Ki = 43.0))),
        sync = sync, setpoint = point, limits = limits) : tlc(
        elec = ElectricalTLC(Sbase = 500.0, vACbase_LL_RMS = 380.0, vDCbase = dcbase),
        outerActive = outer, outerReactive = reactive, innerCurrent = occ,
        sync = sync, setpoint = point, limits = limits)
end

function droop_network(kind; K = 5.0)
    elements = (;
        DUT = converter(kind; K),
        G_AC = ac_source(pins = 3, transformation = true,
            setpoint = Setpoint(Vac = 380sqrt(2/3))),
        G_DC = dc_source(setpoint = Setpoint(Vdc = 680.0)),
        line = impedance(z = s -> 0.5, pins = 1))
    rows = [(node = Symbol("AC" * axis), element, side, terminal)
        for (element, side) in ((:DUT, 2), (:G_AC, 1))
        for (terminal, axis) in enumerate(("d", "q"))]
    append!(rows, [
        (node = :DC1, element = :DUT, side = 1, terminal = 1),
        (node = :DC1, element = :line, side = 1, terminal = 1),
        (node = :DC2, element = :line, side = 2, terminal = 1),
        (node = :DC2, element = :G_DC, side = 1, terminal = 1)])
    return NB.define(elements, rows; options = (; voltageBase = 380/sqrt(3)))
end

@testset "DC-voltage support equations and state ordering" begin
    @test :DCVoltageSupportLag in names(PI)
    @test DCVoltageSupportLag() == DCVoltageSupportLag(K = 0.0, ωc = 0.0)
    block = OuterActivePowerControl(pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0),
        support = DCVoltageSupportLag(K = 5.0, ωc = 2.0))
    @test PI.statenames(block) == (:ξ_vdc_supp, :ξ_P_ac)
    @test PI.n_states(block.support) == 1
    @test PI.n_states(block) == 2
    @test PI.initialvalues(block; setpoint_pu = PI.SetpointPU()).ξ_vdc_supp == 0.0
    sp = PI.SetpointPU(p_ac = 0.3, v_dc = 1.05)
    x = (; ξ_vdc_supp = 0.017, ξ_P_ac = 0.071)
    for kind in (:mmc, :tlc), measured_voltage in (0.97, 1.05, 1.1)
        m = converter(kind).element_model
        inputs = (; meas = (; P_ac_f = 0.21, v_dc_f = measured_voltage), sync = (; ω_c = 0.98))
        F = zeros(2)
        y = PI.state_space!(F, x, inputs, sp, block, m)
        # Independent MMC_legacy.jl:444–454; the lag always has order one,
        # regardless of the legacy PI controller's n_f and Ki fields.
        delta_p_unfiltered = 5.0 * (1.05 - measured_voltage)
        effective_reference = 0.3 - 0.017
        @test F[1] == 2.0 * (delta_p_unfiltered - 0.017)
        @test F[2] == 10.0 * (effective_reference - 0.21)
        @test y.iΔ_d_ref == 0.2 * (effective_reference - 0.21) + 0.071
        @test y.P_ac_f == 0.21
        other = (; inputs..., sync = (; ω_c = 1.02))
        other_F = zeros(2)
        @test PI.state_space!(other_F, x, other, sp, block, m) == y
        @test other_F == F
    end
    space = DCVoltageSupportLag(Grid; K = Grid([3.0, 5.0]), ωc = 2.0)
    @test collect(space) == [DCVoltageSupportLag(K = 3.0, ωc = 2.0), DCVoltageSupportLag(K = 5.0, ωc = 2.0)]
end

@testset "Legacy DC droop adapter and reference policy" begin
    for (kind, adapter, factory) in ((:mmc, NB._legacy_mmc, mmc), (:tlc, NB._legacy_tlc, tlc))
        p = PI_control(Kₚ = 0.2, Kᵢ = 10.0)
        droop = PI_control(Kₚ = 5.0, Kᵢ = 99.0, n_f = 4, ω_f = 2.0, ref = [1.05])
        kwargs = (; Sbase = 500.0, p, vdc_droop = droop)
        e = @test_logs min_level=Logging.Warn adapter(kwargs, :station)
        @test e.setpoint.Vdc == 672.0
        @test active(e.element_model).support == DCVoltageSupportLag(K = 5.0, ωc = 2.0)
        @test active(e.element_model).pi_ctrl == PIControl(Kp = 0.2, Ki = 10.0)
        @test droop.ref == [1.05]
        @test PI.n_states(active(e.element_model)) == 2
        @test adapter((; kwargs..., vDCbase = 800.0)).setpoint.Vdc == 840.0
        e = @test_logs (:warn, r"converter :station: legacy :vdc_droop reference 672.0 differs from setpoint 680.0") adapter((; kwargs..., setpoint = Setpoint(Vdc = 680.0)), :station)
        @test e.setpoint.Vdc == 680.0
        e = @test_logs min_level=Logging.Warn adapter((; kwargs..., Vᵈᶜ = 672.0), :station)
        @test e.setpoint.Vdc == 672.0
        e = adapter((; Sbase = 500.0, controls = Dict(:p => p, :vdc_droop => droop)))
        @test active(e.element_model).support == DCVoltageSupportLag(K = 5.0, ωc = 2.0)
        @test adapter((; p, Vᵈᶜ = 672.0, vdc_droop = PI_control(ref = [0]))).setpoint.Vdc == 672.0
        @test_throws r"requires the :p" adapter((; vdc_droop = droop))
        @test_throws r"simultaneous active-power supports" adapter((; kwargs..., f_supp = PI_control()))
        @test_throws ArgumentError factory(Grid; elec = kind === :mmc ? ElectricalMMC() : ElectricalTLC(), vdc_droop = droop)
        space = NB.define((; station = factory(Grid; kwargs..., Vᵈᶜ = 680.0)), [
            (node = :dc, element = :station, side = 1, terminal = 1),
            (node = :d, element = :station, side = 2, terminal = 1),
            (node = :q, element = :station, side = 2, terminal = 2)])
        state = @test_logs (:warn, r"converter :station: legacy :vdc_droop reference 672.0 differs from setpoint 680.0") materialize(first(configurations(space)))
        @test active(state.elements.station.element_model).support == DCVoltageSupportLag(K = 5.0, ωc = 2.0)
        @test state.elements.station.setpoint.Vdc == 680.0
    end
end

@testset "DC droop power-flow voltage and power bases" begin
    for kind in (:mmc, :tlc), voltage in (640.0, 672.0), dcbase in (640.0, 800.0), powerbase in (250.0, 1000.0)
        e = converter(kind; voltage, dcbase)
        bases = PI.PowerModelsACDC._get_pu_bases(powerbase, 320.0)
        bases["omega"] = 100π
        data = Dict{String,Any}("dcpol" => 2, "convdc" => Dict{String,Any}(),
            "bus" => Dict("1" => Dict{String,Any}("bus_type" => 3)),
            "busdc" => Dict("1" => Dict{String,Any}("bus_type" => 1)))
        PI.convert!(data, e, PI.PMACDC, 1, (1, 1), bases)
        c = data["convdc"]["1"]
        @test c["type_dc"] == 4
        @test c["Vdcset"] * 640.0 == voltage
        @test c["Pacset"] == -50.0
        @test powerbase / (640.0 * c["droop"]) ≈ 5.0 * 500.0 / dcbase
        if voltage == 672.0 && dcbase == 640.0
            @test c["Vdcset"] * 640.0 != 705.6 # Historical operating-voltage normalization.
            @test powerbase / (640.0 * c["droop"]) ≈ 3.90625
        end
        zero = OuterActivePowerControl(support = DCVoltageSupportLag())
        @test PI.pf_type_dc(zero) == 4
        @test isinf(PI.pf_dc_droop(zero, dcbase, 500.0, bases, data))
    end
end

@testset "DC droop off-nominal power-flow/dynamic operating point" begin
    for kind in (:mmc, :tlc), representation in (:classic, :builder), K in (0.0, 5.0)
        state = droop_network(kind; K)
        if representation === :classic
            net = NB.build_network(state.elements, state.topology, state.options)
            result, data, _, emap = power_flow(net)
            e = net.elements[:DUT]
            record = data["convdc"][string(last(emap[:DUT]))]
        else
            solved = NB.solve(state)
            e = solved.network.elements[:DUT]
            result = solved.powerflow.result
            data = solved.powerflow.data
            record = data["convdc"][string(solved.powerflow.elem2comp[:DUT].compkey)]
        end
        solution = result["solution"]
        flow = solution["convdc"][string(record["index"])]
        vdc = solution["busdc"][string(record["busdc_i"])]["vm"]
        @test flow["pconv"] ≈ record["Pacset"] - (vdc - record["Vdcset"]) / record["droop"] atol=1e-6
        @test abs(e.setpoint.Vdc - 640.0) > 30.0
        @test e.setpoint.Vdc ≈ 2state.options.voltageBase * vdc
        m = e.element_model
        inputs, sp = PI.pftoinputs(m, e.setpoint)
        vector = PI._steady_state(e)
        x = NamedTuple{PI.statenames(m)}(Tuple(vector))
        F = zeros(length(vector))
        outputs = PI.state_space!(F, x, inputs, sp, m)
        equil_F = zeros(length(vector))
        PI._state_space!(equil_F, vector, collect(values(inputs)), sp, m, PI.Equil())
        @test norm(F, Inf) <= 1e-6 # Existing equilibrium accuracy; no tolerance change.
        @test isequal(F, equil_F) # No equation is replaced to obtain this residual.
        @test x.ξ_vdc_supp == 0.0
        @test F[findfirst(==(:ξ_vdc_supp), PI.statenames(m))] == 0.0
        @test abs(outputs.meas.P_ac_f - sp.p_ac) <= 1e-6
        @test sp.v_dc == e.setpoint.Vdc / 640.0
        K > 0 && @test abs(e.setpoint.Pac - 50.0) > 30.0
        println((; kind, representation, K, Vdc = e.setpoint.Vdc, Pac = e.setpoint.Pac, residual = norm(F, Inf)))
    end
end

@testset "DC droop against historical MMC steady state and admittance" begin
    for order in (0, 2)
        controls = PI.OrderedDict{Symbol,PI.Controller}(
            :pll => PI_control(Kₚ = 0.085, Kᵢ = 32.0),
            :p => PI_control(Kₚ = 0.2, Kᵢ = 10.0, n_f = order, ω_f = 80.0),
            :q => PI_control(Kₚ = 0.2, Kᵢ = 10.0, ref = [25.0], n_f = order, ω_f = 120.0),
            :vdc_droop => PI_control(Kₚ = 5.0, ω_f = 2.0, ref = [1.05]),
            :ccc => PI_control(Kₚ = 0.1, Kᵢ = 43.0, ref = [0.02, -0.01]),
            :energy => PI_control(Kₚ = 1.4, Kᵢ = 30.0, ref = [1.1]),
            :occ => PI_control(Kₚ = 0.1, Kᵢ = 43.0),
            :zcc => PI_control(Kₚ = 0.1, Kᵢ = 43.0))
        old = LegacyMMCReference.MMC(; Sbase = 500.0, controls = deepcopy(controls))
        LegacyMMCReference.update!(old, 380sqrt(2/3), 0.0, 50.0, -25.0, 672.0, 50.0)
        e = NB._legacy_mmc((; Sbase = 500.0, controls = deepcopy(controls),
            P = 50.0, Vₘ = 380/sqrt(3), Vᵈᶜ = 672.0, P_dc = 50.0))
        PI.update!(e, e.setpoint)
        @test PI._steady_state(e)[end-11:end] ≈ old.equilibrium[1:12]
        for ω in (2π, 100π, 1000π)
            reference = LegacyMMCReference.eval_parameters(old, ComplexF64(im*ω))
            reference[2:3, :] .*= -1 # Generation to terminal load-current sign.
            @test PI.eval_y(e, ComplexF64(im*ω)) ≈ reference
        end
    end
end

@testset "PSCAD DC droop fail-fast" begin
    for kind in (:mmc, :tlc)
        e = converter(kind)
        m = e.element_model
        @test_throws r"converter :station:.*DCVoltageSupportLag.*not yet exportable" PI.PSCAD.converter_equilibrium((; name = :station, model = m))
        @test_throws r"converter :station:.*DCVoltageSupportLag.*not yet exportable" PI.PSCAD.converter_active("P", (; name = :station), nothing, active(m))
    end
end
end
