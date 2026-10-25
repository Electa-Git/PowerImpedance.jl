module BlackboxMMCTests
using Test, PowerImpedance, LinearAlgebra
const P = PowerImpedance
const NB = P.NetworkBuilder

const SCAN_Y = ComplexF64[1+2im 2-im 3+im; 4+im 5+3im 6-im; 7-im 8+im 9+2im]

@testset "Scan arguments and d/q rotation" begin
    arguments = Ref{Any}(nothing)
    interpolant = (v, p, q, f) -> begin
        arguments[] = (v, p, q, f)
        copy(SCAN_Y)
    end
    model = P.Blackbox_MMC(; itp = interpolant, vACbase = 380.0)
    @test_throws ArgumentError P.eval_parameters(model, 2π * im * 73.0)
    values = (ac = ACPortValues(315.0, 0.37, -24.0, 7.0),
        dc = DCPortValues(635.0, 24.5))
    response! = NB.build(model, values, :dq)
    @test model.cache.values === values
    s = 2π * im * 73.0
    actual = P.eval_parameters(model, s)
    @test arguments[] === (315.0 / (sqrt(2/3) * 380.0), 24.0, -7.0, real(s / (2π * im)))
    theta = values.ac.theta
    T = [1 0 0; 0 cos(theta) -sin(theta); 0 sin(theta) cos(theta)]
    expected = inv(T) * SCAN_Y * T
    @test actual == expected
    @test actual != SCAN_Y
    output = zeros(ComplexF64, 3, 3, 1)
    response!(output, [s])
    @test output[:, :, 1] == expected
    @test P.eval_abcd(model, s) == expected

    classic = P.Blackbox_MMC(; itp = interpolant)
    P.update!(classic, values.ac.v, values.ac.theta, -values.ac.p, values.ac.q,
        values.dc.v, values.dc.p)
    @test classic.cache.values === values
    @test P.eval_parameters(classic, s) == actual
    @test classic.powerflow == model.powerflow
end

@testset "Direct inputs and model data" begin
    model = P.Blackbox_MMC(; itp = (v, p, q, f) -> copy(SCAN_Y))
    defaults = (p_ac = -10.0, q_ac = 3.0, v_ac = 333.0, p_dc = 100.0, v_dc = 640.0)
    @test model isa P.AbstractLinFreqDomain
    @test !ismutabletype(typeof(model))
    @test all(name -> !isdefined(P, name),
        (:Converter, :Controller, :PI_control, :VSE_old, :CCQSEM, :FFVI))
    @test inputvalues(model) === (ac_control = :pq, dc_control = :p, powerflow = defaults)
    @test keys(inputs(model)) == (:ac_control, :dc_control, :powerflow)
    @test inputs(model).ac_control.default === :pq
    @test inputs(model).dc_control.default === :p
    @test inputs(model).ac_control.type === Symbol
    @test inputs(model).dc_control.type === Symbol
    @test map(input -> input.default, inputs(model).powerflow) === defaults
    @test map(input -> input.unit, inputs(model).powerflow) ==
        (p_ac = "MW", q_ac = "MVAr", v_ac = "kV", p_dc = "MW", v_dc = "kV")
    @test all(input -> !isempty(input.description), values(inputs(model).powerflow))
    @test bases(model) === nothing
    @test limits(model) === model.limits
    @test limits(model) == P.Limits(P_min = -100, P_max = 100, Q_min = -50, Q_max = 50)
    @test electricalconnections(model) == (ac = Port(ACDQ), dc = Port(DC_CM))
    @test P.admittance_order(model) === ((:dc, :dc), (:ac, :d), (:ac, :q))
    @test P.is_converter(model) && P.is_active(model) && !P.islinear(model)
    P.update!(model, 310.0, 0.1, 20.0, -4.0, 640.0, 20.2)
    configured = withinputs(model; ac_control = :pv, dc_control = :vdc,
        powerflow = (p_ac = 25.0, v_ac = 320.0))
    @test configured.powerflow === merge(defaults, (p_ac = 25.0, v_ac = 320.0))
    @test configured.ac_control === :pv && configured.dc_control === :vdc
    @test inputs(configured) == inputs(model)
    @test configured.itp === model.itp && configured.data === model.data
    @test configured.cache !== model.cache
    @test configured.cache.values === nothing
    @test model.powerflow === defaults
    lm = P.Limits(P_min = -80, P_max = 90, Q_min = -30, Q_max = 40)
    configured = component(model; limits = lm, dc_control = :vdc,
        powerflow = (q_ac = -8.0,))
    @test limits(configured) === lm
    @test inputvalues(configured).powerflow.q_ac === -8.0
    @test configured.cache.values === nothing
    for invalid in (:vac, :vac_supp, :invalid)
        @test_throws ArgumentError P.Blackbox_MMC(ac_control = invalid)
        @test_throws ArgumentError withinputs(model; ac_control = invalid)
    end
    for invalid in (:dc, :vdc_droop, :invalid)
        @test_throws ArgumentError P.Blackbox_MMC(dc_control = invalid)
        @test_throws ArgumentError withinputs(model; dc_control = invalid)
    end
    @test_throws ArgumentError withinputs(model; powerflow = (unknown = 0.0,))
    @test_throws r"ac_control" withinputs(model; ac_control = 1)
    @test_throws r"dc_control" withinputs(model; dc_control = 1)
    @test_throws r"powerflow.p_dc" withinputs(model; powerflow = (p_dc = "1",))
    @test withinputs(model; powerflow = (p_dc = 1,)).powerflow.p_dc === 1.0
end

@testset "Model and classic power-flow conversion" begin
    gd = Dict("V" => 200e3, "Z" => 40.0, "omega" => 120π)
    initial = Dict{String, Any}(
        "convdc" => Dict{String, Any}(),
        "bus" => Dict("2" => Dict{String, Any}(
            "bus_type" => 1, "vm" => 0.95, "vmin" => 0.85, "vmax" => 1.15)),
        "busdc" => Dict("3" => Dict{String, Any}("bus_type" => 1)),
        "dcpol" => 2,
    )
    seeds = (p_ac = 40.0, q_ac = -6.0, v_ac = 220.0, p_dc = 42.0, v_dc = 640.0)
    lm = P.Limits(P_min = -80, P_max = 90, Q_min = -30, Q_max = 40)
    for ac_control in (:pq, :pv), dc_control in (:p, :vdc)
        @testset "$ac_control/$dc_control" begin
            model = P.Blackbox_MMC(; ac_control, dc_control, powerflow = seeds,
                limits = lm, Rₘₑ = 1.2, ω₀ = 100π)
            direct = deepcopy(initial)
            P.convert!(direct, model, P.PMACDC,
                (name = :mmc, index = 7, pmtype = "convdc"), (ac = 2, dc = 3), gd)
            conv = direct["convdc"]["7"]
            @test conv["type_ac"] == (ac_control == :pv ? 2 : 1)
            @test conv["type_dc"] == (dc_control == :vdc ? 2 : 1)
            @test conv["Vtar"] == 1.1
            @test direct["bus"]["2"]["bus_type"] == (ac_control == :pv ? 2 : 1)
            @test direct["bus"]["2"]["vm"] == 1.1
            @test direct["busdc"]["3"]["bus_type"] == (dc_control == :vdc ? 2 : 1)
            @test conv["P_g"] === 40.0 && conv["Q_g"] === -6.0
            @test conv["Pdcset"] === 42.0 && conv["Vdcset"] === 1.6
            @test conv["Vmmax"] ≈ 1.21
            @test conv["Vmmin"] ≈ 0.99
            @test conv["Imax"] == 0.2
            @test conv["rc"] == 0.03 && conv["xc"] == 0.0
            @test conv["acq_droop"] == conv["kq_droop"] == conv["droop"] == 0
            @test [conv[key] for key in ("Pacmin", "Pacmax", "Qacmin", "Qacmax")] ==
                [-80.0, 90.0, -30.0, 40.0]
            @test direct["busdc"]["3"]["Vdc"] == 1.6
            @test model.ω₀ == 100π
            @test model.cache.values === nothing
        end
    end
end

@testset "Power flow and frequency model" begin
    arguments = Ref{Any}(nothing)
    interpolant = (v, p, q, f) -> begin
        arguments[] = (v, p, q, f)
        copy(SCAN_Y)
    end
    model = P.Blackbox_MMC(; itp = interpolant,
        powerflow = (p_ac = 10.0, q_ac = 3.0, v_ac = 220 / sqrt(3),
            p_dc = 10.0, v_dc = 640.0))
    ac = component(ac_source(); v = 220sqrt(2/3), theta = 0.0)
    dc = component(dc_source(); v = 640.0)
    state = NB.define((; mmc = model, ac, dc), (
        NB.Bus(:AC; ports = ((:ac, :ac), (:mmc, :ac))),
        NB.Net(:DC; terminals = ((:dc, :dc, :dc), (:mmc, :dc, :dc))),
    ); options = (voltageBase = 220 / sqrt(3),))
    result = NB.solve(state)
    @test result.result["termination_status"] == P.MOI.LOCALLY_SOLVED
    op = result.operating_point[:mmc]
    @test keys(op) == (:ac, :dc)
    @test op.ac isa ACPortValues && op.dc isa DCPortValues
    @test op.ac.p ≈ -10.0
    @test op.ac.q ≈ -3.0
    @test op.ac.v ≈ ac.v
    @test op.ac.theta ≈ ac.theta
    @test op.dc.v ≈ dc.v
    @test op.dc.p > 0.0
    frequency_model = NB.NetworkModel(state, result.operating_point)
    @test model.cache.values === op
    @test model.powerflow.p_ac === 10.0
    s = 2π * im * 73.0
    actual = NB.get_y(frequency_model, :mmc, [s])[:, :, 1]
    @test actual == P.eval_parameters(model, s)
    @test arguments[] == (op.ac.v / (sqrt(2/3) * model.vACbase),
        -op.ac.p, -op.ac.q, real(s / (2π * im)))
    @test NB.sortedcomponentconnections(state.topology, :mmc).port == [:dc, :ac, :ac]
    elemresult = Dict("pgrid" => -0.01, "qgrid" => -0.003, "pdc" => 0.0101)
    buses = (ac = Dict("vm" => 1.0, "va" => 0.12), dc = Dict("vm" => 1.6))
    physical = P.transform(elemresult, buses, Dict("V" => 200e3, "S" => 1e9),
        model, P.PMACDC, P.PIACDC)
    @test physical.ac.p == -10.0 && physical.ac.q == -3.0
    @test physical.dc.p == 10.1 && physical.dc.v == 640.0
end

@testset "Scan-file construction" begin
    mktempdir() do directory
        path_f = joinpath(directory, "frequency.tsv")
        path_MMC = joinpath(directory, "admittance.tsv")
        write(path_f, "1\t10.0\n2\t100.0\n")
        open(path_MMC, "w") do io
            println(io, join(("column$i" for i in 1:24), '\t'))
            for v in (0.98, 1.02), p in (10.0, 20.0), q in (1.0, 2.0)
                i_ac = hypot(p, q) / (sqrt(3) * v * 380.0)
                p_dc = p + 3 * 1.25 * i_ac^2
                row = ComplexF64[1.0, v, p, q, p_dc, i_ac]
                for f in (10.0, 100.0)
                    append!(row, vec(permutedims((1 + f / 1000) * SCAN_Y)))
                end
                println(io, join((replace(string(x), " " => "") for x in row), '\t'))
            end
        end
        for dc_control in (:p, :vdc)
            model = blackbox_MMC(; path_f, path_MMC, ac_control = :pv, dc_control,
                powerflow = (p_ac = 15.0,))
            @test model isa P.Blackbox_MMC
            @test model.Rₘₑ ≈ 1.25
            @test length(model.data) == 8
            @test model.powerflow ===
                (p_ac = 15.0, q_ac = 3.0, v_ac = 333.0, p_dc = 100.0, v_dc = 640.0)
            @test model.itp(1.0, 15.0, 1.5, 55.0) ≈ 1.055 * SCAN_Y
            @test model.cache.values === nothing
        end
    end
end
end
