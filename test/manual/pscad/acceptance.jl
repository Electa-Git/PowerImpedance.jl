# Manual real-station acceptance; never included in the automatic test suite.
# Use a Julia environment containing PowerImpedance and PythonCall, and set
# POWERIMPEDANCE_PSCAD_CONFIG to the station configuration TOML.
using PowerImpedance, PythonCall, LinearAlgebra
include("../../pscad/fixtures.jl")

remote = RemoteConfig()
exports = mktempdir(mkpath(joinpath(remote.local_root, "exports"));
    prefix = "m2-", cleanup = false)
classic, state = PSCADFixtures.small_ac_network()
classic_model = export_pscad(classic; path = joinpath(exports, "small_ac_classic.pscx"))
builder_model = export_pscad(state; path = joinpath(exports, "small_ac_builder.pscx"))
ohl_classic, ohl_state = PSCADFixtures.passive_ohl_network()
ohl_classic_model = export_pscad(ohl_classic;
    path = joinpath(exports, "passive_ohl_classic.pscx"))
ohl_builder_model = export_pscad(ohl_state;
    path = joinpath(exports, "passive_ohl_builder.pscx"))

yy_classic, yy_state = PSCADFixtures.transformer_network()
yy_classic_model = export_pscad(yy_classic; path = joinpath(exports, "transformer_yy_classic.pscx"))
yy_builder_model = export_pscad(yy_state; path = joinpath(exports, "transformer_yy_builder.pscx"))
dc_classic, dc_state = PSCADFixtures.dc_network()
dc_classic_model = export_pscad(dc_classic; path = joinpath(exports, "dc_classic.pscx"))
dc_builder_model = export_pscad(dc_state; path = joinpath(exports, "dc_builder.pscx"))

cable_classic, cable_state = PSCADFixtures.dc_cable_network()
cable_classic_model = export_pscad(cable_classic; path = joinpath(exports, "dc_cable_classic.pscx"))
cable_builder_model = export_pscad(cable_state; path = joinpath(exports, "dc_cable_builder.pscx"))

cases = [(classic_model, classic_model, 0.01), (builder_model, classic_model, 0.01),
    (ohl_classic_model, ohl_classic_model, 0.02), (
        ohl_builder_model, ohl_classic_model, 0.02),
    (yy_classic_model, yy_classic_model, 0.01), (yy_builder_model, yy_classic_model, 0.01),
    (dc_classic_model, dc_classic_model, 0.01), (dc_builder_model, dc_classic_model, 0.01),
    (cable_classic_model, cable_classic_model, 0.01),
    (cable_builder_model, cable_classic_model, 0.01)]

# Detect the merged model by its positive-sequence transfer, without relying
# on a commit hash. Compare against YY to remove the fixture's no-load loss angle.
dy_classic, dy_state = PSCADFixtures.transformer_network(; organization = :ΔY)
sequence = ComplexF64[1, cis(-2π / 3), cis(2π / 3)]
yy_abcd = PowerImpedance.eval_abcd(yy_state.elements.line.element_model, 2π * 50im)
dy_abcd = PowerImpedance.eval_abcd(dy_state.elements.line.element_model, 2π * 50im)
yy_transfer = dot(sequence, yy_abcd[1:3, 1:3] * sequence) / 3
dy_transfer = dot(sequence, dy_abcd[1:3, 1:3] * sequence) / 3
shift = -rad2deg(angle(dy_transfer / yy_transfer))
if isapprox(shift, 30.0; atol = 1e-8, rtol = 0)
    dy_classic_model = export_pscad(dy_classic; path = joinpath(exports, "transformer_dy_classic.pscx"))
    dy_builder_model = export_pscad(dy_state; path = joinpath(exports, "transformer_dy_builder.pscx"))
    append!(cases, [(dy_classic_model, dy_classic_model, 0.01),
        (dy_builder_model, dy_classic_model, 0.01)])
else
    println("ΔY skipped: model fix not merged")
end

for (model, classic_reference, rtol_v) in cases
    dc_cable = any(model.netlist.elements) do element
        element.model isa PowerImpedance.Cable &&
            all(t -> t.bus !== nothing && t.bus.domain == 2, element.terminals)
    end
    simulation_time = dc_cable ? 3.0 :
                      any(bus -> bus.kind == :dc, model.netlist.buses) ? 1.0 : 0.3
    result = compute(model,
        PSCADRun();
        options = (;
            remote, simulation_time, time_step = 50e-6,
            sample_step = 250e-6, verbosity = 1))
    # NB.solve skips power flow for this linear fixture. Both representations
    # therefore compare against the equivalent classic circuit's solved record.
    reference = isempty(model.operating_point.bus_states) ? classic_reference : model
    comparison = compare_operating_point(result, reference; rtol_v)
    if any(bus -> bus.kind == :dc, model.netlist.buses)
        settled = PowerImpedance.PSCAD.steady_state(result)
        for bus in filter(bus -> bus.kind == :dc, model.netlist.buses)
            poles = filter(c -> c.kind == :voltage && c.bus == bus.name, model.probes.channels)
            positive = only(filter(c -> c.side == "P", poles))
            negative = only(filter(c -> c.side == "N", poles))
            vp, vn = settled[positive.name].mean, settled[negative.name].mean
            println(bus.name, " pole voltages [kV]: ", vp, ", ", vn,
                "; relative midpoint error: ", abs(vp + vn) / (2bus.base_kV))
            vp > 0 && vn < 0 && isapprox(vp, -vn; rtol = 0.01, atol = 0) ||
                error("DC pole symmetry failed at $(bus.name)")
        end
    end
    println(model.project_name)
    show(stdout, MIME("text/plain"), comparison)
    println()
    # Retain all measured errors, including the OHL case's 2% voltage check.
    open(joinpath(exports, model.project_name * "_comparison.tsv"), "w") do io
        println(io, "quantity\tname\tpscad\tpowerflow\terror\twithin_tolerance")
        for row in comparison
            println(io, join(values(row), '\t'))
        end
    end
    all(comparison.within_tolerance) ||
        error("PSCAD acceptance failed for $(model.project_name)")
end

# Diagnostic, not asserted: the Transformer_test magnetizing branch (Lₘ = 10 H,
# Rₘ = 1e4 Ω) draws a magnetizing current comparable to the load current and
# exposes the power-flow pi-model approximation of the transformer T-model.
stress_classic, _ = PSCADFixtures.transformer_network(; Rₘ = 1e4, Lₘ = 10.0)
stress_model = export_pscad(stress_classic;
    path = joinpath(exports, "transformer_yy_stress.pscx"))
stress = compute(stress_model, PSCADRun();
    options = (; remote, simulation_time = 0.3, time_step = 50e-6,
        sample_step = 250e-6, verbosity = 1))
println("transformer_yy_stress (diagnostic, not asserted)")
show(stdout, MIME("text/plain"), compare_operating_point(stress, stress_model))
println()

