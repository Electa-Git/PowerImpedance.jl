# Manual real-station acceptance; never included in the automatic test suite.
# Use a Julia environment containing PowerImpedance and PythonCall, and set
# POWERIMPEDANCE_PSCAD_CONFIG to the station configuration TOML.
using PowerImpedance, PythonCall, LinearAlgebra
include("../../pscad/fixtures.jl")

remote = RemoteConfig()
exports = mktempdir(mkpath(joinpath(remote.local_root, "exports"));
    prefix = "tlc-", cleanup = false)
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

sm_classic, sm_state = PSCADFixtures.sm_network()
sm_settings = PowerImpedance.PSCAD.SimulationSettings(simulation_time = 15.0,
    time_step = 10e-6, sample_step = 1e-3)
sm_classic_model = export_pscad(sm_classic;
    path = joinpath(exports, "sm_classic.pscx"), settings = sm_settings)
sm_builder_model = export_pscad(sm_state;
    path = joinpath(exports, "sm_builder.pscx"), settings = sm_settings)

# Ten seconds covers twenty 0.5 s support-lag time constants. The 10 us
# integration step and 40 us sampling match the validated TLC project.
# Retain the supported 0.05 s source ramp. Native divider behavior during
# startup must be checked on the station before accepting these cases.
tlc_settings = PowerImpedance.PSCAD.SimulationSettings(simulation_time = 10.0,
    time_step = 10e-6, sample_step = 40e-6, source_ramp = 0.05)
tlc1_classic, tlc1_state = PSCADFixtures.tlc_case1_network()
tlc2_classic, tlc2_state = PSCADFixtures.tlc_case2_network()
tlc1_classic_model = export_pscad(tlc1_classic;
    path = joinpath(exports, "tlc_case1_classic.pscx"), settings = tlc_settings, dc_reference = :none)
tlc1_builder_model = export_pscad(tlc1_state;
    path = joinpath(exports, "tlc_case1_builder.pscx"), settings = tlc_settings, dc_reference = :none)
tlc2_classic_model = export_pscad(tlc2_classic;
    path = joinpath(exports, "tlc_case2_classic.pscx"), settings = tlc_settings, dc_reference = :none)
tlc2_builder_model = export_pscad(tlc2_state;
    path = joinpath(exports, "tlc_case2_builder.pscx"), settings = tlc_settings, dc_reference = :none)

# Saved PQ settings use 10 s duration with 10 us integration and 250 us sampling; Tc=0. A
# source_ramp=0 and 0.2 s solved-measurement hold apply. R15 must settle before comparison
# of the final ten cycles.
mmc_settings = PowerImpedance.PSCAD.SimulationSettings(simulation_time = 10.0,
    time_step = 10e-6, sample_step = 250e-6, source_ramp = 0.0)
mmc_classic, mmc_state = PSCADFixtures.mmc_pq_network()
mmc_classic_model = export_pscad(mmc_classic;
    path = joinpath(exports, "mmc_pq_classic.pscx"), settings = mmc_settings, dc_reference = :none)
mmc_builder_model = export_pscad(mmc_state;
    path = joinpath(exports, "mmc_pq_builder.pscx"), settings = mmc_settings, dc_reference = :none)

cases = [(classic_model, classic_model, 0.01), (builder_model, classic_model, 0.01),
    (ohl_classic_model, ohl_classic_model, 0.02), (
        ohl_builder_model, ohl_classic_model, 0.02),
    (yy_classic_model, yy_classic_model, 0.01), (yy_builder_model, yy_classic_model, 0.01),
    (dc_classic_model, dc_classic_model, 0.01), (dc_builder_model, dc_classic_model, 0.01),
    (cable_classic_model, cable_classic_model, 0.01),
    (cable_builder_model, cable_classic_model, 0.01),
    (sm_classic_model, sm_classic_model, 0.02),
    (sm_builder_model, sm_classic_model, 0.02),
    (tlc1_classic_model, tlc1_classic_model, 0.01), (
        tlc1_builder_model, tlc1_classic_model, 0.01),
    (tlc2_classic_model, tlc2_classic_model, 0.01), (
        tlc2_builder_model, tlc2_classic_model, 0.01),
    (mmc_classic_model, mmc_classic_model, 0.01), (
        mmc_builder_model, mmc_classic_model, 0.01)]

# The MMC modes use the same measurement hold and zero ramp. Saved settings are 10 s / 10
# us / 250 us; P-f's 0.5 s lag gets twenty time constants.
for (stem, fixture, reference) in (
    ("mmc_vdc", PSCADFixtures.mmc_vdc_network(), :midpoint_resistors),
    ("mmc_pf", PSCADFixtures.mmc_pf_network(), :none),
    ("mmc_qv", PSCADFixtures.mmc_qv_network(), :none),
    ("mmc_vac", PSCADFixtures.mmc_vac_network(), :none))
    classic_mode = export_pscad(fixture.classic;
        path = joinpath(exports, stem * "_classic.pscx"), settings = mmc_settings,
        dc_reference = reference)
    builder_mode = export_pscad(fixture.state;
        path = joinpath(exports, stem * "_builder.pscx"), settings = mmc_settings,
        dc_reference = reference)
    append!(cases, [(classic_mode, classic_mode, 0.01), (builder_mode, classic_mode, 0.01)])
end

# TLC VAC shares the same generator, timing and ramp as the other TLC modes.
tlc_vac = PSCADFixtures.tlc_vac_network()
tlc_vac_classic = export_pscad(tlc_vac.classic;
    path = joinpath(exports, "tlc_vac_classic.pscx"), settings = tlc_settings, dc_reference = :none)
tlc_vac_builder = export_pscad(tlc_vac.state;
    path = joinpath(exports, "tlc_vac_builder.pscx"), settings = tlc_settings, dc_reference = :none)
append!(cases, [
    (tlc_vac_classic, tlc_vac_classic, 0.01), (tlc_vac_builder, tlc_vac_classic, 0.01)])

# Both source-ramp experiments run in the same station pass; regular MMC/TLC fixture
# settings remain unchanged.
mmc_default_ramp = export_pscad(mmc_classic;
    path = joinpath(exports, "mmc_pq_default_ramp.pscx"),
    settings = PowerImpedance.PSCAD.SimulationSettings(simulation_time = 10.0,
        time_step = 10e-6, sample_step = 250e-6), dc_reference = :none)
tlc_zero_ramp = export_pscad(tlc2_classic;
    path = joinpath(exports, "tlc_case2_zero_ramp.pscx"),
    settings = PowerImpedance.PSCAD.SimulationSettings(simulation_time = 10.0,
        time_step = 10e-6, sample_step = 40e-6, source_ramp = 0.0), dc_reference = :none)
append!(cases, [
    (mmc_default_ramp, mmc_default_ramp, 0.01), (tlc_zero_ramp, tlc_zero_ramp, 0.01)])

# GFM uses the MMC timing/hold, including its configured 200 us modulation delay.
gfm = PSCADFixtures.mmc_gfm_network()
gfm_classic_model = export_pscad(gfm.classic;
    path = joinpath(exports, "mmc_gfm_classic.pscx"), settings = mmc_settings, dc_reference = :none)
gfm_builder_model = export_pscad(gfm.state;
    path = joinpath(exports, "mmc_gfm_builder.pscx"), settings = mmc_settings, dc_reference = :none)
append!(cases, [(gfm_classic_model, gfm_classic_model, 0.01),
    (gfm_builder_model, gfm_classic_model, 0.01)])

# The compensated MMC requires the FFVI 1 us step; a 10 us step is unstable.
compensated_settings = PowerImpedance.PSCAD.SimulationSettings(simulation_time = 5.0,
    time_step = 1e-6, sample_step = 250e-6, source_ramp = 0.0)
compensated = PSCADFixtures.mmc_compensated_network()
compensated_classic_model = export_pscad(compensated.classic;
    path = joinpath(exports, "mmc_compensated_classic.pscx"), settings = compensated_settings, dc_reference = :none)
compensated_builder_model = export_pscad(compensated.state;
    path = joinpath(exports, "mmc_compensated_builder.pscx"), settings = compensated_settings, dc_reference = :none)
append!(cases, [(compensated_classic_model, compensated_classic_model, 0.01),
    (compensated_builder_model, compensated_builder_model, 0.01)])

# Positive-sequence transfer identifies the Dyn11 rotation independently of a commit hash.
# The YY comparison removes the fixture's no-load loss angle.
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

converters_only = "--converters" in ARGS
all(arg -> arg == "--converters", ARGS) || error("usage: acceptance.jl [--converters]")
if converters_only
    filter!(case -> any(e -> e.model isa Union{PowerImpedance.TLC, PowerImpedance.MMC},
        case[1].netlist.elements), cases)
end

failures = Pair{String, String}[]
for (model, classic_reference, rtol_v) in cases
    try
        dc_cable = any(model.netlist.elements) do element
            element.model isa PowerImpedance.Cable &&
                all(t -> t.bus !== nothing && t.bus.domain == 2, element.terminals)
        end
        machine = any(e -> e.model isa PowerImpedance.SynchronousMachine, model.netlist.elements)
        converter = any(e -> e.model isa Union{PowerImpedance.TLC, PowerImpedance.MMC}, model.netlist.elements)
        mmc = any(e -> e.model isa PowerImpedance.MMC, model.netlist.elements)
        compensated_mmc = any(e -> e.model isa PowerImpedance.MMC &&
                                  e.model.modulation isa PowerImpedance.CompensatedModulation,
            model.netlist.elements)
        simulation_time = compensated_mmc ? 5.0 : converter ? 10.0 :
                          machine ? 15.0 :
                          dc_cable ? 3.0 :
                          any(bus -> bus.kind == :dc, model.netlist.buses) ? 1.0 : 0.3
        result = compute(model,
            PSCADRun();
            options = (;
                remote, simulation_time, time_step = compensated_mmc ? 1e-6 : (machine || converter) ? 10e-6 : 50e-6,
                sample_step = mmc ? 250e-6 : converter ? 40e-6 : machine ? 1e-3 : 250e-6, verbosity = 1))
        # NB.solve skips power flow for this linear fixture. Both representations compare
        # against the equivalent classic circuit's solved record.
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
        if machine
            settled = PowerImpedance.PSCAD.steady_state(result)
            for channel in model.probes.channels
                channel.kind in
                (:machine_p, :machine_q, :machine_voltage, :machine_diagnostic) || continue
                println(channel.name, " settled mean [", channel.unit, "]: ",
                    settled[channel.name].mean)
            end
        end
        if converter
            settled = PowerImpedance.PSCAD.steady_state(result)
            for channel in model.probes.channels
                channel.kind in
                (:converter_diagnostic, :converter_arm_voltage, :converter_sum_current) ||
                    continue
                if channel.kind == :converter_sum_current
                    element = only(filter(e -> string(e.name) == channel.element,
                        model.netlist.elements))
                    equilibrium = PowerImpedance.PSCAD.converter_equilibrium(element)
                    reference_current = equilibrium.states.iΣ_z
                    println(channel.name, " settled mean [pu]: ", settled[channel.name].mean,
                        "; solved equilibrium [pu]: ", reference_current,
                        "; difference [pu]: ", settled[channel.name].mean - reference_current)
                    continue
                end
                println(channel.name, " settled mean [", channel.unit,
                    "]: ", settled[channel.name].mean)
            end
        end
        # A frequency-dependent cable fit and remaining lag transients can affect
        # the final window; inspect settling warnings before accepting the table.
        # Retain all measured errors, including the OHL case's 2% voltage check.
        open(joinpath(exports, model.project_name * "_comparison.tsv"), "w") do io
            println(io, "quantity\tname\tpscad\tpowerflow\terror\tsettling\twithin_tolerance")
            for row in comparison
                println(io, join(values(row), '\t'))
            end
        end
        all(comparison.within_tolerance) ||
            error("PSCAD acceptance failed for $(model.project_name)")
    catch err
        err isa InterruptException && rethrow()
        detail = sprint(showerror, err, catch_backtrace())
        push!(failures, model.project_name => detail)
        println(stderr, model.project_name, ": FAILED: ", detail)
    end
end

# Diagnostic, not asserted: the Transformer_test magnetizing branch (Lₘ = 10 H,
# Rₘ = 1e4 Ω) draws a magnetizing current comparable to the load current and
# exposes the power-flow pi-model approximation of the transformer T-model.
if !converters_only
    try
        stress_classic, _ = PSCADFixtures.transformer_network(; Rₘ = 1e4, Lₘ = 10.0)
        stress_model = export_pscad(stress_classic;
            path = joinpath(exports, "transformer_yy_stress.pscx"))
        stress = compute(stress_model, PSCADRun();
            options = (; remote, simulation_time = 0.3, time_step = 50e-6,
                sample_step = 250e-6, verbosity = 1))
        println("transformer_yy_stress (diagnostic, not asserted)")
        show(stdout, MIME("text/plain"), compare_operating_point(stress, stress_model))
        println()
    catch err
        err isa InterruptException && rethrow()
        detail = sprint(showerror, err, catch_backtrace())
        push!(failures, "transformer_yy_stress" => detail)
    end
end

open(joinpath(exports, "acceptance_failures.txt"), "w") do io
    println(io, length(failures), " failed cases")
    for (name, detail) in failures
        println(io, "\n", name, "\n", detail)
    end
end
if !isempty(failures)
    println(stderr, "PSCAD acceptance failures (", length(failures), "):")
    for (name, detail) in failures
        println(stderr, "\n", name, "\n", detail)
    end
    exit(1)
end
