module PSCADConverterDelayTests
using Test, PowerImpedance
using ..PSCADFixtures
using ..PSCADMMCTests: converter_element, with_modulation
const P = PowerImpedance.PSCAD

@testset "Converter residual delay budget and initialization" begin
    dt = 10e-6
    @test P._converter_export_delay(0.0, dt) == 0.0
    @test P._converter_export_delay(dt, dt) == 0.0
    @test P._converter_export_delay(4dt, dt) ≈ 3dt
    @test P._converter_export_delay(2.5dt, dt) ≈ 1.5dt
    for (tau, step) in ((dt/2, dt), (-dt, dt), (Inf, dt), (NaN, dt),
        (dt, 0.0), (dt, -dt), (dt, Inf), (dt, NaN))
        @test_throws ArgumentError P._converter_export_delay(tau, step)
    end
    settings = P.SimulationSettings(time_step = dt, sample_step = dt)
    transforms = (; abc = "network:ABC_DQ", dq = "network:DQ_ABC")
    for (kind, factory) in ((:tlc, PSCADFixtures.tlc_case2_network),
        (:uncompensated, PSCADFixtures.mmc_pq_network),
        (:compensated, PSCADFixtures.mmc_compensated_network))
        network = factory().classic
        list = P.netlist(network, power_flow(network))
        e = only(filter(e -> e.name == :DUT, list.elements))
        eq = P.converter_equilibrium(e)
        for tau in (0.0, dt, 4dt, 2.5dt, dt/2)
            block = kind == :tlc ? DelayModulation(timeDelay = tau, padeOrderNum = 3, padeOrderDen = 3) :
                kind == :uncompensated ? UncompensatedModulation(timeDelay = tau, padeOrderNum = 3, padeOrderDen = 3) :
                CompensatedModulation(timeDelay = tau, padeOrderNum = 3, padeOrderDen = 3)
            m = e.model
            altered = kind == :tlc ? converter_element(e, TLC(m.elec, m.meas, m.sync,
                m.outerActive, m.outerReactive, m.innerVoltage, m.innerCurrent, block)) :
                converter_element(e, with_modulation(m, block))
            build() = kind == :tlc ? P.tlc_modulation("MOD", altered, eq, transforms, settings) :
                P.mmc_modulation("MOD", altered, eq, transforms, settings)
            if 0 < tau < dt
                @test_throws ArgumentError build()
                continue
            end
            definition = build()
            parameters = Dict(p.name => p.default for p in definition.parameters)
            residual = iszero(tau) ? 0.0 : tau - dt
            queues = filter(c -> c.defn == "master:tdelay", definition.canvas.components)
            @test length(queues) == (iszero(residual) ? 0 : kind == :tlc ? 2 : kind == :uncompensated ? 5 : 6)
            for queue in queues
                p = Dict(queue.params)
                @test parameters[p["T"]] ≈ residual
                @test parse(Int, p["N"]) == ceil(Int, residual/dt) + 1
                @test p["Init"] == "1"
                @test isfinite(parameters[p["X0"]])
            end
            @test (kind == :tlc ? altered.model.mod.delay.timeDelay : altered.model.modulation.delay1.timeDelay) == tau
            if kind == :tlc
                @test parameters["compensation"] ≈ m.elec.ωbase * residual
                if !isempty(queues)
                    restored = PowerImpedance.phase_compensated_dq(
                        [parameters["dDelay0"], parameters["qDelay0"]], parameters["compensation"])
                    @test collect(restored) ≈ [eq.outputs.mod.m_d, eq.outputs.mod.m_q]
                end
            elseif kind == :uncompensated
                for (stem, frame, expected) in (("mD", 1, [eq.outputs.mod.mΔd, eq.outputs.mod.mΔq]),
                    ("mS", -2, [eq.outputs.mod.mΣd, eq.outputs.mod.mΣq]))
                    @test parameters[stem * "phase"] ≈ frame * m.elec.ωbase * residual
                    if !isempty(queues)
                        restored = PowerImpedance.phase_compensated_dq(
                            [parameters[stem * "dY0"], parameters[stem * "qY0"]], parameters[stem * "phase"])
                        @test collect(restored) ≈ expected
                    end
                end
                !isempty(queues) && @test parameters["zeroY0"] == eq.outputs.mod.mΣz
            else
                # The abc insertion queue has no added dq carrier rotation.
                @test !haskey(parameters, "compensation")
                !isempty(queues) && @test all(p -> p.default == residual,
                    filter(p -> endswith(p.name, "Td"), definition.parameters))
            end
            # A rotating physical signal sees the sum of interface and residual
            # delays, for Δ, Σ and triplen frames, including noninteger ratios.
            total = dt + residual
            for harmonic in (1, -2, 3), frequency in (0.0, 75.0, 1000.0)
                s = 2pi * frequency * im
                realized = exp(-s*dt + im*harmonic*m.elec.ωbase*dt) *
                    exp(-s*residual + im*harmonic*m.elec.ωbase*residual)
                @test realized ≈ exp(-s*total + im*harmonic*m.elec.ωbase*total)
            end
            !iszero(tau) && @test total ≈ tau
        end
    end
end
@testset "Isolated timing witness transport and topology" begin
    include(joinpath(@__DIR__, "../manual/pscad/validation/validation.jl"))
    V = PSCADValidation
    plan, settings = V.timing_plan()
    @test length(plan.probes.channels) == 5
    @test count(c -> c.defn == "master:source_1", plan.main.components) == 5
    @test count(c -> c.defn == "master:tdelay", plan.main.components) == 2
    @test settings.sample_step == settings.time_step
    @test P.check_connectivity(plan) === nothing
    time = collect(0.0:settings.time_step:settings.simulation_time)
    input = 0.1sin.(2pi*1000 .* time) .+ (time .>= 0.002)
    channels = Dict("V_input" => input)
    for (name, tau) in V.TIMING_DELAYS
        total = iszero(tau) ? settings.time_step : tau
        k = floor(Int, total/settings.time_step)
        f = total/settings.time_step-k
        channels["V_"*name] = [i > k+1 ? (1-f)*input[i-k] + f*input[i-k-1] : 0.0 for i in eachindex(time)]
    end
    @test all(row.passed for row in V.timing_comparison(time, channels, settings.time_step))
    # Another whole step in the library/source path must stop the L2 queue.
    channels["V_four"] = [0.0; channels["V_four"][1:end-1]]
    @test !only(filter(row -> row.name == "four", V.timing_comparison(time, channels, settings.time_step))).passed
end

end
