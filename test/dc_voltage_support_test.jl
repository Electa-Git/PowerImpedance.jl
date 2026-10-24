module DCVoltageSupportTests
using Test, PowerImpedance, LinearAlgebra, Logging
const PI = PowerImpedance
const NB = PI.NetworkBuilder
include("parity/structure.jl")

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
            # Normalization uses the declared DC-voltage base instead of the operating
            # voltage.
            @test c["Vdcset"] * 640.0 != 705.6
            @test powerbase / (640.0 * c["droop"]) ≈ 3.90625
        end
        zero = OuterActivePowerControl(support = DCVoltageSupportLag())
        @test PI.pf_type_dc(zero) == 4
        @test isinf(PI.pf_dc_droop(zero, dcbase, 500.0, bases, data))
    end
end

@testset "DC droop off-nominal power-flow/dynamic operating point" begin
    for kind in (:mmc, :tlc), K in (0.0, 5.0)
        state = droop_network(kind; K)
        solved = NB.solve(state)
        m = state.elements.DUT
        point = solved.operating_point[:DUT]
        result, data = solved.result, solved.data
        record = data["convdc"][string(solved.elem2comp[:DUT].compkey)]
        solution = result["solution"]
        flow = solution["convdc"][string(record["index"])]
        vdc = solution["busdc"][string(record["busdc_i"])]["vm"]
        @test flow["pconv"] ≈ record["Pacset"] - (vdc - record["Vdcset"]) / record["droop"] atol=1e-6
        @test abs(point.dc.v - 640.0) > 30.0
        @test point.dc.v ≈ 2state.options.voltageBase * vdc
        inputs, sp = PI.pftoinputs(m, point)
        vector = PI.steady_state(m, point)
        x = NamedTuple{PI.statenames(m)}(Tuple(vector))
        F = zeros(length(vector))
        outputs = PI.state_space!(F, x, inputs, sp, m)
        equil_F = zeros(length(vector))
        PI._state_space!(equil_F, vector, collect(values(inputs)), sp, m, PI.Equil())
        @test norm(F, Inf) <= 1e-6 # The equilibrium residual tolerance is 1e-6.
        @test isequal(F, equil_F) # The residual is evaluated with the native equations.
        @test x.ξ_vdc_supp == 0.0
        @test F[findfirst(==(:ξ_vdc_supp), PI.statenames(m))] == 0.0
        @test abs(outputs.meas.P_ac_f - sp.p_ac) <= 1e-6
        @test sp.v_dc == point.dc.v / 640.0
        K > 0 && @test abs(-point.ac.p - 50.0) > 30.0
        println((; kind, K, Vdc = point.dc.v, Pac = point.ac.p, residual = norm(F, Inf)))
    end
end

@testset "DC droop against historical MMC steady state and admittance" begin
    reference = ParityData.load_rows(joinpath(@__DIR__, "reference/v2/numeric.csv"))
    for order in (0, 2)
        p_filter = order == 0 ? PI.NoFilter() : PI.Butterworth(order = order, ωc = 80.0)
        q_filter = order == 0 ? PI.NoFilter() : PI.Butterworth(order = order, ωc = 120.0)
        energy_filter = PI.measurement_filter_ss(q_filter)
        e = mmc(
            elec = ElectricalMMC(Sbase = 500.0, vDC_base = 640.0,
                vACbase_LL_RMS = 380.0, turnsRatio = 1.0),
            meas = Measurement(P_ac = p_filter, Q_ac = q_filter),
            sync = PLLSynchronization(pi_ctrl = PIControl(Kp = 0.085, Ki = 32.0)),
            delta_control = ΔdqControlGFL(
                outer_active = OuterActivePowerControl(
                    pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0),
                    support = DCVoltageSupportLag(K = 5.0, ωc = 2.0)),
                outer_reactive = OuterReactiveQControl(
                    pi_ctrl = PIControl(Kp = 0.2, Ki = 10.0)),
                occ = InnerCurrentPIControl(pi_ctrl = PIControl(Kp = 0.1, Ki = 43.0),
                    activate_ω_c_multiplication = false)),
            sigma_control = ΣdqzControlTEC(
                tec = TotalEnergyControl(PIControl(Kp = 1.4, Ki = 30.0),
                    1.1, energy_filter, true),
                zscc = ZeroSequenceCurrentControl(PIControl(Kp = 0.1, Ki = 43.0)),
                ccsc = CirculatingCurrentSuppressionControl(
                    PIControl(Kp = 0.1, Ki = 43.0); ref = (0.02, -0.01))),
            modulation = UncompensatedModulation(),
            setpoint = Setpoint(Pac = 50.0, Qac = 25.0, θac = 0.0,
                Vac = (380 / sqrt(3)) * sqrt(2), Vdc = 672.0, Pdc = 50.0),
            limits = PI.Limits(P_min = 0.9, P_max = 1.1, Q_min = -0.5, Q_max = 0.5))
        PI.update!(e, e.setpoint)
        prefix = "oracle.droop_mmc.order$order"
        x = [real(get(reference, ("$prefix.x", i, 1, 1), 0.0)) for i in 1:12]
        @test PI._steady_state(e)[end-11:end] ≈ x
        for (index, ω) in enumerate((2π, 100π, 1000π))
            y = [get(reference, ("$prefix.y.$index", i, j, 1), 0.0 + 0.0im)
                for i in 1:3, j in 1:3]
            @test PI.eval_y(e, ComplexF64(im*ω)) ≈ y
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
