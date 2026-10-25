module DocstringExamplesTests
using Test, PowerImpedance, Markdown, LinearAlgebra
const PI = PowerImpedance
const NB = PI.NetworkBuilder

const EXAMPLES = (
    (:SI_scale, Tuple{PI.InductionMachine}),
    (:SI_scale, Tuple{PI.MMC}),
    (:SI_scale, Tuple{PI.SynchronousMachine}),
    (:SI_scale, Tuple{PI.TLC}),
    (:_source_abcd, Tuple{Any}),
    (:ac_source, Tuple{}),
    (:blackbox_line, Tuple{}),
    (:cable, Tuple{}),
    (:component, Tuple{Any}),
    (:dc_source, Tuple{}),
    (:elecinputnames, Tuple{PI.AbstractStateSpace}),
    (:eval_abcd, Tuple{PI.Cable, Complex}),
    (:eval_abcd, Tuple{PI.Overhead_line, Complex}),
    (:eval_abcd, Tuple{PI.Transformer, ComplexF64}),
    (:eval_parameters, Tuple{PI.Cable, Complex}),
    (:eval_parameters, Tuple{PI.Overhead_line, Complex}),
    (:eval_y, Tuple{PI.Source, Complex}),
    (:impedance, Tuple{}),
    (:inductionmachine, Tuple{}),
    (:input_signals, Tuple{PI.MMC, Any, Any}),
    (:input_signals, Tuple{PI.TLC, Any, Any}),
    (:inputnames, Tuple{PI.TLC}),
    (:linearize, Tuple{PI.AbstractStateSpace, NamedTuple}),
    (:mmc, Tuple{}),
    (:outputnames, Tuple{PI.TLC}),
    (:overhead_line, Tuple{}),
    (:pftoinputs, Tuple{PI.InductionMachine, NamedTuple}),
    (:pftoinputs, Tuple{PI.MMC, NamedTuple}),
    (:pftoinputs, Tuple{PI.SynchronousMachine, NamedTuple}),
    (:pftoinputs, Tuple{PI.TLC, NamedTuple}),
    (:state_space!, Tuple{Any, Any, Any, PI.CCVI, PI.AbstractConverter}),
    (:state_space!, Tuple{Any, Any, Any, PI.CirculatingCurrentControl, PI.AbstractMMC}),
    (:state_space!,
        Tuple{Any, Any, Any, PI.CirculatingCurrentSuppressionControl, PI.AbstractMMC}),
    (:state_space!, Tuple{Any, Any, Any, PI.CompensatedModulation, PI.AbstractMMC}),
    (:state_space!, Tuple{Any, Any, Any, PI.DelayModulation, PI.AbstractTLC}),
    (:state_space!, Tuple{Any, Any, Any, PI.ElectricalIM}),
    (:state_space!, Tuple{Any, Any, Any, PI.ElectricalMMC, PI.AbstractMMC}),
    (:state_space!, Tuple{Any, Any, Any, PI.ElectricalSM}),
    (:state_space!, Tuple{Any, Any, Any, PI.ElectricalTLC, PI.AbstractTLC}),
    (:state_space!, Tuple{Any, Any, Any, PI.FrequencySupportLag}),
    (:state_space!, Tuple{Any, Any, Any, PI.GovernorSM}),
    (:state_space!, Tuple{Any, Any, Any, PI.InductionMachine}),
    (:state_space!, Tuple{Any, Any, Any, PI.InnerCurrentPIControl, PI.AbstractConverter}),
    (:state_space!, Tuple{Any, Any, Any, PI.Measurement, PI.AbstractConverter}),
    (:state_space!, Tuple{Any, Any, Any, PI.MeasurementSignal}),
    (:state_space!, Tuple{Any, Any, Any, PI.MechanicalIM}),
    (:state_space!, Tuple{Any, Any, Any, PI.MechanicalSM}),
    (:state_space!, Tuple{Any, Any, Any, PI.NoModulation, PI.AbstractTLC}),
    (:state_space!, Tuple{Any, Any, Any, PI.PadeDelay, PI.AbstractConverter}),
    (:state_space!, Tuple{Any, Any, Any, PI.SynchronousMachine}),
    (:state_space!, Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.AbstractFrequencySupport}),
    (:state_space!, Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.DCVoltageSupportLag}),
    (:state_space!, Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.MMC}),
    (:state_space!,
        Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.OuterActivePowerControl,
            PI.AbstractConverter}),
    (:state_space!,
        Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.OuterActiveVdcControl,
            PI.AbstractConverter}),
    (:state_space!,
        Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.OuterReactiveQControl,
            PI.AbstractConverter}),
    (:state_space!,
        Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.OuterReactiveVacControl,
            PI.AbstractConverter}),
    (:state_space!,
        Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.PLLSynchronization,
            PI.AbstractConverter}),
    (:state_space!, Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.TLC}),
    (:state_space!,
        Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.VSEWithDamping, PI.AbstractConverter}),
    (:state_space!, Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.ΔdqControlGFL, PI.MMC}),
    (:state_space!, Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.ΔdqControlGFM, PI.MMC}),
    (:state_space!, Tuple{Any, Any, Any, PI.TotalEnergyControl, PI.AbstractMMC}),
    (:state_space!, Tuple{Any, Any, Any, PI.UncompensatedModulation, PI.AbstractMMC}),
    (:state_space!, Tuple{Any, Any, Any, PI.ZeroSequenceCurrentControl, PI.AbstractMMC}),
    (:state_space!, Tuple{Any, Any, Any, Tuple, PI.AVRSM}),
    (:state_space!,
        Tuple{Any, Any, NamedTuple{(:meas, :power, :sync)}, PI.ΣEnergyControl,
            PI.AbstractMMC}),
    (:state_space!,
        Tuple{Any, Any, NamedTuple{(:meas, :power, :sync)}, PI.ΔEnergyControl,
            PI.AbstractMMC}),
    (:state_space!,
        Tuple{Any, Any, NamedTuple{(:meas, :power, :sync)}, PI.TerminalValuesPU,
            PI.ΣdqzControlTEC, PI.MMC}),
    (:state_space!,
        Tuple{Any, Any, NamedTuple{(:meas, :power, :sync)}, PI.TerminalValuesPU,
            PI.ΣdqzControlLEC, PI.MMC}),
    (:state_space!,
        Union{Tuple{Any, Any, Any, PI.TerminalValuesPU, PI.VoltageSupportLag}, Tuple{Any,
            Any, Any, PI.TerminalValuesPU, PI.VoltageSupportLag, Union{Nothing,
            PI.AbstractConverter}}}),
    (:state_space_block!, Tuple{Any, Any, Any, Any, Any, PI.AbstractStateSpace, Integer}),
    (:steady_state, Tuple{PI.AbstractStateSpace, NamedTuple}),
    (:synchronousmachine, Tuple{}),
    (:tlc, Tuple{}),
    (:transformer, Union{Tuple{}, Tuple{Any}}),
)

@testset "Docstring examples" begin
    for (name, signature) in EXAMPLES
        @testset "$name $signature" begin
            binding = Base.Docs.Binding(PI, name)
            doc = Base.Docs.meta(PI)[binding].docs[signature]
            text = join(part for part in doc.text if part isa AbstractString)
            blocks = filter(Markdown.parse(text).content) do block
                block isa Markdown.Code && block.language == "julia"
            end
            @test !isempty(blocks)
            sandbox = Module(gensym(:DocstringExample))
            Core.eval(sandbox, :(using PowerImpedance))
            for block in blocks
                @test begin
                    Base.include_string(sandbox, block.code, string(name))
                    true
                end
            end
        end
    end
end

@testset "Direct constructors and removed keywords" begin
    mktempdir() do directory
        path = joinpath(directory, "line.tsv")
        open(path, "w") do io
            println(io, "frequency\tZ\tY")
            for f in (10.0, 100.0)
                println(io, f, "\t0.01-", 2π*f*1e-6, "im\t0.0-", 2π*f*1e-10, "im")
            end
        end
        constructors = (
            (impedance, PI.Impedance, (z = 1.0,)),
            (transformer, PI.Transformer, (;)),
            (cable, PI.Cable, (positions = [(0.0, 1.0)],
                C1 = Conductor(rₒ = 0.02, ρ = 1.72e-8))),
            (overhead_line, PI.Overhead_line, (;)),
            (blackbox_line, PI.Blackbox_line, (n = 1, data_type = :LCMjl, path = path)),
            (ac_source, PI.Source, (;)),
            (dc_source, PI.Source, (;)),
            (mmc, PI.MMC, (sync = NoSynchronization(), delta_control = ΔdqControlGFL(
                outer_active = NoOuterActiveControl(),
                outer_reactive = NoOuterReactiveControl(), occ = NoInnerCurrentControl()),
                sigma_control = ΣdqzControlTEC())),
            (tlc, PI.TLC, (;)),
            (synchronousmachine, PI.SynchronousMachine, (;)),
            (inductionmachine, PI.InductionMachine, (;)),
        )
        removed = (pins = 3, transformation = true, connection = false,
            setpoint = nothing)
        for (constructor, target, kwargs) in constructors
            @testset "$constructor" begin
                @test constructor(; kwargs...) isa target
                grid = constructor(Grid; kwargs...)
                @test grid isa NB.Gridspace{target}
                @test eltype(grid) === target
                @test first(grid) isa target
                for (keyword, value) in pairs(removed)
                    rejected = NamedTuple{(keyword,)}((value,))
                    @test_throws MethodError constructor(; kwargs..., rejected...)
                end
            end
        end
        grid = blackbox_MMC(Grid)
        @test grid isa NB.Gridspace{PI.Blackbox_MMC}
        @test eltype(grid) === PI.Blackbox_MMC
        for (keyword, value) in pairs(removed)
            rejected = NamedTuple{(keyword,)}((value,))
            @test_throws MethodError blackbox_MMC(; rejected...)
        end
    end
end

@testset "Ports and source targets" begin
    for count in (1, 3)
        domain = count == 1 ? DC_CM : ACABC
        for model in (impedance(z = 1.0, conductors = count),
                transformer(conductors = count))
            @test model.conductors === count
            @test electricalconnections(model) ==
                (side1 = Port(domain), side2 = Port(domain))
        end
    end
    ac = ac_source(v = 220sqrt(2/3), theta = 0.1, p = 100.0, q = 5.0)
    dc = dc_source(v = 640.0, p = 100.0)
    @test !ismutabletype(PI.Source)
    @test Set(fieldnames(PI.Source)) ==
        Set((:v, :theta, :p, :q, :conductors, :domain, :limits, :ABCD))
    @test ac.conductors === 3 && dc.conductors === 1
    @test electricalconnections(ac) == (ac = Port(ACABC),)
    @test electricalconnections(dc) == (dc = Port(DC_CM),)
    @test inputvalues(ac) === (v = 220sqrt(2/3), theta = 0.1, p = 100.0, q = 5.0)
    @test inputvalues(dc) === (v = 640.0, p = 100.0)
    @test ac_source().v === 220 / sqrt(3)
    @test dc_source().v === 240.0
    @test_throws MethodError ac_source(limits = PI.Limits())
    @test_throws MethodError dc_source(limits = PI.Limits())
    for model in (ac, dc)
        count = model.conductors
        ideal = Matrix{ComplexF64}(I, 2count, 2count)
        @test model.ABCD == ideal
        @test PI.eval_abcd(model, 100π * im) === model.ABCD
        PI.eval_y(model, 100π * im)
        @test model.ABCD == ideal
        configured = component(model; limits = PI.Limits(P_max = 200.0), v = 130.0)
        @test configured.v === 130.0
        @test limits(configured).P_max === 200.0
        @test configured.ABCD === model.ABCD
    end
    state = NB.define((; dc, load = impedance(z = 10.0, conductors = 1)), (
        NB.Bus(:DC; ports = ((:dc, :dc), (:load, :side1))),
        NB.Net(:gnd; terminals = ((:load, :side2, :dc),)),
    ))
    data, _, _ = convert(state, PI.PMACDC)
    bus = only(values(data["busdc"]))
    @test bus["Vdc"] === 0.0
    @test bus["Vdcmax"] === 0.0
    @test bus["Vdcmin"] === 0.0
    @test only(values(data["gendc"]))["vgdc"] > 0.0
end
end
