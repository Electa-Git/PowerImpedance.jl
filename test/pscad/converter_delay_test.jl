module PSCADConverterDelayTests
import ..PSCADFixtures
using Test, PowerImpedance
using ..PSCADFixtures
using ..PSCADMMCTests: converter_element, with_modulation
const P = PowerImpedance.PSCAD

@testset "Converter residual delay budget and initialization" begin
    dt = 10e-6
    @test P._converter_export_delay(0.0, dt) == 0.0
    @test P._converter_export_delay(dt, dt) == 0.0
    @test P._converter_export_delay(4dt, dt) ≈ 3dt
    @test_logs (:warn, r"residual rounded") @test P._converter_export_delay(2.5dt, dt; converter = :DUT) ≈ 2dt
    @test_logs (:warn, r"residual rounded") @test P._converter_export_delay(2.49dt, dt) ≈ dt
    @test_logs (:warn, r"residual rounded") @test P._converter_export_delay(2.51dt, dt) ≈ 2dt
    @test_logs @test P._converter_export_delay(200e-6, 2.5e-6) ≈ 197.5e-6
    for (tau, step) in ((dt/2, dt), (-dt, dt), (Inf, dt), (NaN, dt),
        (dt, 0.0), (dt, -dt), (dt, Inf), (dt, NaN))
        @test_throws ArgumentError P._converter_export_delay(tau, step)
    end
    settings = P.SimulationSettings(time_step = dt, sample_step = dt)
    transforms = (; abc = "network:ABC_DQ", dq = "network:DQ_ABC")
    for (kind, factory) in ((:tlc, PSCADFixtures.tlc_case2_network),
        (:uncompensated, PSCADFixtures.mmc_pq_network),
        (:compensated, PSCADFixtures.mmc_compensated_network))
        network = factory()
        list = P.netlist(network, compute(PowerFlowProblem(network), ACDCPowerFlow()))
        e = only(filter(e -> e.name == :DUT, list.elements))
        eq = P.converter_equilibrium(e)
        for tau in (0.0, dt, 4dt, 2.5dt, dt/2)
            block = kind == :tlc ? DelayModulation(timeDelay = tau, padeOrderNum = 3, padeOrderDen = 3) :
                kind == :uncompensated ? UncompensatedModulation(timeDelay = tau, padeOrderNum = 3, padeOrderDen = 3) :
                CompensatedModulation(timeDelay = tau, padeOrderNum = 3, padeOrderDen = 3)
            m = e.model
            altered = kind == :tlc ? converter_element(e, TLC(m.elec, m.meas, m.sync,
                m.outerActive, m.outerReactive, m.innerVoltage, m.innerCurrent, block,
                m.limits, m.bases, m.powerflow)) :
                converter_element(e, with_modulation(m, block))
            build() = kind == :tlc ? P.tlc_modulation("MOD", altered, eq, transforms, settings) :
                P.mmc_modulation("MOD", altered, eq, transforms, settings)
            if 0 < tau < dt
                @test_throws ArgumentError build()
                continue
            end
            definition = build()
            parameters = Dict(p.name => p.default for p in definition.parameters)
            residual = iszero(tau) ? 0.0 : round((tau-dt)/dt, RoundNearestTiesUp)*dt
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
                @test parameters["compensation"] ≈ m.bases.omega * residual
                if !isempty(queues)
                    restored = PowerImpedance.phase_compensated_dq(
                        [parameters["dDelay0"], parameters["qDelay0"]], parameters["compensation"])
                    @test collect(restored) ≈ [eq.outputs.mod.m_d, eq.outputs.mod.m_q]
                end
            elseif kind == :uncompensated
                for (stem, frame, expected) in (("mD", 1, [eq.outputs.mod.mΔd, eq.outputs.mod.mΔq]),
                    ("mS", -2, [eq.outputs.mod.mΣd, eq.outputs.mod.mΣq]))
                    @test parameters[stem * "phase"] ≈ frame * m.bases.omega * residual
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
                realized = exp(-s*dt + im*harmonic*m.bases.omega*dt) *
                    exp(-s*residual + im*harmonic*m.bases.omega*residual)
                @test realized ≈ exp(-s*total + im*harmonic*m.bases.omega*total)
            end
            !iszero(tau) && @test abs(total - tau) <= dt/2 + eps(tau)
        end
    end
end

end
