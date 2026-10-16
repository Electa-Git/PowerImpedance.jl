# Local project generation only; never connects to the station.
using PowerImpedance, PythonCall, LinearAlgebra
include("../../pscad/fixtures.jl")
include("../../pscad/topology.jl")
const P = PowerImpedance.PSCAD
const EXPERIMENTS = mkpath("/tmp/pscad-m5b-experiments")
const MMC_SETTINGS = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 250e-6, source_ramp = 0.0)
const TLC_SETTINGS = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 40e-6, source_ramp = 0.05)
BLAS.set_num_threads(1)

function write_reference(model)
    open(joinpath(EXPERIMENTS, model.project_name * "_reference.tsv"), "w") do io
        println(io, "element\tquantity\treference\tunit\tstate_index")
        row(element, quantity, value, unit, index = 0) = println(
            io, join((element, quantity, value, unit, index), '\t'))
        for (element, flow) in sort(collect(model.operating_point.branch_flows); by = first)
            for (quantity, value) in pairs(flow)
                row(element, quantity, value, quantity in (:qf, :qt, :qgrid, :qg) ? "MVAr" :
                                              "MW")
            end
        end
        for bus in model.netlist.buses
            point = model.operating_point.bus_states[bus.key]
            row(bus.name, "vm", point.vm_pu, "pu")
            row(bus.name, "voltage", point.vm_pu * bus.base_kV * (bus.kind == :dc ? 2 : 1),
                bus.kind == :dc ? "kV_pole_to_pole" : "kV_phase_RMS")
            bus.kind == :dc || row(bus.name, "angle", point.va_rad, "rad")
        end
        for element in filter(e -> e.model isa PowerImpedance.AbstractConverter, model.netlist.elements)
            eq = P.converter_equilibrium(element)
            x, y, m = eq.states, eq.outputs, element.model
            for quantity in fieldnames(typeof(eq.setpoint_pu))
                row(element.name, "reference_" * string(quantity),
                    getproperty(eq.setpoint_pu, quantity),
                    quantity == :θ_ac ? "rad" : "pu")
            end
            row(element.name, "reference_v_ac_measured_side",
                eq.setpoint_pu.v_ac * PowerImpedance.voltage_filter_ratio(m), "pu")
            for (quantity, value) in pairs(y.meas)
                row(element.name, quantity, value, quantity == :θ_f ? "rad" : "pu")
            end
            row(element.name, "omega_c", y.sync.ω_c, "pu")
            if m isa PowerImpedance.MMC
                row(element.name, "iS_z", x.iΣ_z, "pu")
                row(element.name, "i_dc_internal", 3x.iΣ_z*m.elec.Sbase/m.elec.vDC_base, "kA")
                caps = P.mmc_arm_capacitors(x, m.elec.vDC_base)
                for (half, voltages) in (("u", caps.upper), ("l", caps.lower)),
                    (phase, voltage) in zip(("a", "b", "c"), voltages)

                    row(element.name, "v_Ctot_" * half * "_" * phase * "_initial", voltage, "kV")
                end
            end
            for (index, (quantity, value)) in enumerate(pairs(x))
                row(element.name, quantity, value, "model_state", index)
            end
            residual = zeros(length(x))
            PowerImpedance._state_space!(
                residual, collect(values(x)), collect(values(eq.inputs)),
                eq.setpoint_pu, m, PowerImpedance.Equil())
            row(element.name, "equilibrium_residual_max", maximum(abs, residual), "model_rate")
        end
    end
end

function write_case(name, network, settings, dc_reference)
    path = joinpath(EXPERIMENTS, name * ".pscx")
    rm(path; force = true)
    model = export_pscad(network; path, settings, dc_reference)
    plan = P.build_plan(model.netlist; settings, name, dc_reference,
        description = "PowerImpedance.jl: $name")
    P.check_connectivity(plan)
    definitions = Dict(d.name => d for d in plan.modules)
    PSCADTopology.check_degrees(PSCADTopology.electrical_graph(plan.main, definitions), "Main")
    for d in plan.modules
        PSCADTopology.check_degrees(PSCADTopology.electrical_graph(d.canvas, definitions), d.name)
    end
    write_reference(model)
    println("Wrote ", name)
    return model, plan
end

for (stem, factory, reference) in ((
    "mmc_vdc", PSCADFixtures.mmc_vdc_network, :midpoint_resistors),
    ("mmc_pf", PSCADFixtures.mmc_pf_network, :none),
    ("mmc_qv", PSCADFixtures.mmc_qv_network, :none),
    ("mmc_vac", PSCADFixtures.mmc_vac_network, :none))
    fixture = factory()
    for (suffix, network) in (("classic", fixture.classic), ("builder", fixture.state))
        write_case(stem * "_" * suffix, network, MMC_SETTINGS, reference)
    end
end

fixture = PSCADFixtures.tlc_vac_network()
for (suffix, network) in (("classic", fixture.classic), ("builder", fixture.state))
    write_case("tlc_vac_" * suffix, network, TLC_SETTINGS, :none)
end

# The PQ default-ramp experiment uses the solved-measurement hold. Regular MMC fixtures
# retain their zero-ramp settings.
fixture = PSCADFixtures.mmc_pq_network()
default_ramp = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 250e-6)
write_case("mmc_pq_default_ramp", fixture.classic, default_ramp, :none)
fixture = PSCADFixtures.tlc_case2_network()
zero_ramp = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 40e-6, source_ramp = 0.0)
write_case("tlc_case2_zero_ramp", fixture.classic, zero_ramp, :none)

write(joinpath(EXPERIMENTS, "README.md"),
    """
# M5b station experiments

Ten normal exports cover MMC Vdc, P-f, Q-V, VAC and TLC VAC in classic and NetworkBuilder
representations. MMC runs use 10 s, 10 us integration, 250 us sampling, source ramp zero,
fresh start and the accepted 0.2 s solved-measurement hold. TLC VAC uses the
M4 10 s / 10 us / 40 us settings and 0.05 s source ramp.
Namespaces, project canvas settings and output settings come directly from the
exporter. Build and run each project under its own filename without renaming
its namespace or changing output filenames. No native run is claimed here.

Each reference TSV contains solved terminal MW/MVAr, bus voltages and angles,
internal per-unit references and measurements, initial arm voltages and the
full converged Julia state vector (model_state rows, state_index ordering,
separately for DUT and SEND in Vdc). Model-state coordinates are not SI.
VAC initialization includes the solved reactive power and converged ξ_v_ac;
it does not reuse the original requested 200 MVAr as an equilibrium reference.
Use each representation's own TSV: their numerical power-flow solutions need
not have identical last digits. Inspect settling and compare the final ten
cycles [9.8,10.0] s using the existing acceptance policy.

* mmc_vdc_classic/builder: DUT regulates 800 kV with PI gains 5/15. SEND is
  a remote PQ converter through the validation script's 60 km bipolar cable;
  it supplies the DC side instead of imposing another DC-voltage target.
  The existing exporter supplies 1e7 ohm pole references per DC bus;
  their placement differs from the saved project's single ground return. Compare both converters and cable current.
* mmc_pf_classic/builder: existing 600 MW/200 MVAr PQ plant, plus the M4 TLC
  frequency-support lag Kω=5, ωc=2 rad/s. At nominal frequency support is zero.
* mmc_qv_classic/builder: saved voltage lag K=20, ωc=100 rad/s and source
  R=0.01 ohm as an explicit series resistor. References use the measured
  transformer side, with exact 333/380 ratio.
* mmc_vac_classic/builder: saved VAC PI Kp=0, Ki=100 and validation script's
  explicit 0.1 H AC grid reactor. The solved Q and ξ_v_ac are in the TSV.
* tlc_vac_classic/builder: same VAC generator and saved 0/100 gains,
  on the M4 TLC plant with a 0.1 H grid reactor separating its controlled
  AC bus from the source. The usual M4 DC start-up selector is unchanged.
* mmc_pq_default_ramp: the existing PQ fixture with default 0.05 s source
  ramp, now exported directly through the normal exporter. Compared with
  zero ramp, only Main's three source Tc fields change. Arm source commands
  and all control holds retain their accepted construction.
* tlc_case2_zero_ramp: existing TLC case 2 with zero source ramp, 10 s,
  10 us integration and its existing 40 us sampling. No hold or equation changes.

Inspect finite voltages, insertion indices and currents at start and at the
0.2 s release. MMC held probes report solved controls before release and do
not establish physical terminal power during that interval. Inspect all
terminal currents and six capacitor traces after release, settling warnings,
transformer diagnostics and source-ramp transients. Existing comparisons use
rtol_v=0.01, rtol_i=0.02, angle_atol=1 degree and atol_p=0.01 of converter MVA;
capacitor means use solved Vdc and idc=3*iS_z uses the approved current base.
Both ramp experiments passed station round 1, establishing that every supported
converter accepts any finite, nonnegative source ramp. The library default
remains 0.05 s; regular MMC fixtures retain zero and TLC fixtures retain the
default. Both ramp cases are also included in the full acceptance pass.

Provenance: local/GFL-MMC/DVC-Mode/GFL_MMC_Validation.pscx:2020–2045,
2565–2573 and DC_Voltage_Control.jl:62–104,126–133; Q-V_Droop saved module
621–644, droop11992–11998 and source687–710; VAC_Control saved PI11936–11941,
VacControl8025–8215 and VAC_Control.jl:104–116. P-f support gains come from
local/TLC/Simple_2L_VSC_RL.pscx:876–877 (5, 0.5 s) and the accepted M4 TLC fixture, not a saved
MMC P-f mode. The common MMC plant and explicit differences are recorded in
M5a and M5b sections of docs/src/developers/pscad_mapping.md.

DVC's saved current source (0.7527 kA, 0.05 s ramp) is replaced by the script's
remote PQ converter/cable; its saved 1 ohm feed resistor is omitted and
the existing exporter supplies pole references. No source current ramp is inferred. The script's
legacy constructors are rebuilt directly with the modular API. All MMC modes
retain the M5a full Σ additions (TEC 1.386/29.70 and ZSCC0.1048/48.1914),
NoFilter, zero modulation delay, exact ratio, converged capacitor voltages,
and the accepted near-ideal transformer construction. PQ/P-f omit saved
source resistance; Q-V retains its scalar R, and VAC uses the script's reactor
rather than inferring a source impedance from its saved source's Type=4 fields.
Q-V references also follow the solved Julia voltage/Q, rather than the saved
fixed 1 pu/200 MVAr requests. Both representations retain their own solved TSVs.
Q-V/VAC remote DC systems are reduced to the same ideal DC source as M5a,
omitting saved 0.05 ohm DC source resistance. The Vdc droop API gap and the
legacy Σ adapter defect remain deferred. All twelve station round-1 projects
passed the operating-point comparisons against their own reference TSVs.
Use test/manual/pscad/compare_m5b_results.jl with the CSV files in
/tmp/pscad-m5b-results/ to reproduce the detailed 252 comparison rows and
summary in /tmp/pscad-m5b-comparison/. The developer doc records the measured
errors and the Q-V/VAC solved-point differences.
""")
