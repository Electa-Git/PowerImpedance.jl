module PSCADMMCNoControlTests
import ..PSCADFixtures
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures
using ..PSCADTLCTests: evaluate
using ..PSCADMMCTests: converter_element
const P = PowerImpedance.PSCAD
const PI = PowerImpedance

@testset "MMC optional Sigma controls follow the owned equations" begin
    fixture = PSCADFixtures.mmc_pq_network()
    list = P.netlist(fixture, compute(PowerFlowProblem(fixture), ACDCPowerFlow()))
    original = only(filter(e -> e.model isa PI.MMC, list.elements))
    eq = P.converter_equilibrium(original)
    m = original.model
    abc = P.abc_to_dq_module("ABC_DQ")
    dq = P.dq_to_abc_module("DQ_ABC")
    transforms = (; abc = "network:ABC_DQ", dq = "network:DQ_ABC")
    for tec in (m.sigma_control.tec, PI.NoTotalEnergyControl()),
        zscc in (m.sigma_control.zscc, PI.NoZeroSequenceCurrentControl()),
        ccsc in (m.sigma_control.ccsc, PI.NoCirculatingCurrentSuppressionControl())
        sigma = PI.ΣdqzControlTEC(; tec, zscc, ccsc)
        model = PI.MMC(; m.meas, m.sync, m.delta_control, sigma_control = sigma,
            m.modulation, m.elec, m.bases)
        e = converter_element(original, model)
        definition = P.mmc_sigma("SIGMA", e, eq, transforms)
        modules = Dict(d.name => d for d in (abc, dq, definition))
        @test P.check_connectivity(definition.canvas, definition.name, modules) === nothing
        # Disabled controls have no integrator or hidden feedback gain.
        @test count(c -> c.defn == "master:integral", definition.canvas.components) ==
            PI.n_states(sigma)
        for voltage in (0.0, 0.83, 1.07), energy in (0.94, 1.08),
            currents in ((0.13, -0.21, 0.31), (-0.08, 0.19, -0.15))
            d, q, z = currents
            phases = (0.0, -2π / 3, 2π / 3)
            signals = Dict{String, Any}("theta_c" => 0.0, "P_ac_f" => 0.43,
                "v_dc_f" => voltage, "v_dc_divisor" => eq.outputs.meas.v_dc_f,
                "iS_abc" => m.bases.S / m.bases.v_dc .* (d .* cos.(phases) .+
                    q .* sin.(phases) .+ z))
            for half in ("u", "l"), phase in ("a", "b", "c")
                signals["v_Ctot_" * half * "_" * phase] = energy * m.bases.v_dc
            end
            states = merge(eq.states, (; iΣ_d = d, iΣ_q = q, iΣ_z = z,
                Δθ_pll = 0.0, vCΣ_z = energy, vCΣ_d = 0.0, vCΣ_q = 0.0,
                vCΔ_d = 0.0, vCΔ_q = 0.0, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0))
            meas = merge(eq.outputs.meas, (; P_ac_f = 0.43,
                v_dc_f = eq.outputs.meas.v_dc_f))
            expected = PI.state_space!(zeros(PI.n_states(sigma)), states,
                (; meas, power = (; P_ac_f = 0.43), sync = eq.outputs.sync),
                eq.terminal_pu, sigma, model)
            outputs = evaluate(definition, signals)
            @test outputs["vMS_d_ref"] ≈ expected.vMΣ_d_ref_c atol = 1e-6
            @test outputs["vMS_q_ref"] ≈ expected.vMΣ_q_ref_c atol = 1e-6
            # Only the divisor is held; half-DC feedforward remains live.
            @test outputs["vMS_z_ref"] ≈ expected.vMΣ_z_ref +
                (voltage - eq.outputs.meas.v_dc_f) / 2 atol = 1e-6
            @test outputs["iS_z"] ≈ z
        end
    end
end
end
