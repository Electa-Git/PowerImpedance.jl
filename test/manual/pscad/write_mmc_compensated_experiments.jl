# Local compensated MMC project generation; no station connection.
using PowerImpedance, PythonCall, LinearAlgebra
include("../../pscad/fixtures.jl")
include("../../pscad/topology.jl")
const P = PowerImpedance.PSCAD
const EXPERIMENTS = mkpath("/tmp/pscad-mmc-compensated")
const SETTINGS = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 250e-6, source_ramp = 0.0)
const COMPENSATED_SETTINGS = P.SimulationSettings(simulation_time = 5.0, time_step = 1e-6,
    sample_step = 250e-6, source_ramp = 0.0)
BLAS.set_num_threads(1)

function write_reference(model, directory = EXPERIMENTS)
    open(joinpath(directory, model.project_name * "_reference.tsv"), "w") do io
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

function write_case(name, network, settings, dc_reference, directory = EXPERIMENTS)
    path = joinpath(directory, name * ".pscx")
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
    write_reference(model, directory)
    println("Wrote ", name)
    return model, plan
end

fixture = PSCADFixtures.mmc_compensated_network()
for (suffix, network) in (("classic", fixture.classic), ("builder", fixture.state))
    write_case("mmc_compensated_" * suffix, network, COMPENSATED_SETTINGS, :none)
end

const MMC_RECHECK = mkpath(joinpath(EXPERIMENTS, "mmc-recheck"))
for (stem, factory, reference) in (("mmc_pq", PSCADFixtures.mmc_pq_network, :none),
    ("mmc_pf", PSCADFixtures.mmc_pf_network, :none),
    ("mmc_qv", PSCADFixtures.mmc_qv_network, :none),
    ("mmc_vac", PSCADFixtures.mmc_vac_network, :none),
    ("mmc_vdc", PSCADFixtures.mmc_vdc_network, :midpoint_resistors))
    fixture = factory()
    for (suffix, network) in (("classic", fixture.classic), ("builder", fixture.state))
        write_case(stem * "_" * suffix, network, SETTINGS, reference, MMC_RECHECK)
    end
end

write(joinpath(MMC_RECHECK, "README.md"), """
# MMC recheck after the DC-divisor-only start-up correction

Ten projects cover pq, pf, qv, vac and vdc, each classic and builder.
Each uses 10 s duration, 10 us integration, 250 us sampling, zero source ramp
and its own solved reference TSV, including indexed converged states.
Vdc retains midpoint reference resistors; the other cases use dc_reference=:none.
The accepted plant, controls, probes and comparison tolerances are unchanged.

The 0.2 s hold covers only the measured DC-voltage value used as a divisor.
One MEAS selector supplies a private denominator to Σ and uncompensated
modulation. All voltage/current, P/Q, PLL, circulating-current and capacitor
energy feedback runs live from t=0; Vdc errors and half-DC feedforward are live.
The electrical plant starts from rest; closed loops bring it to the operating
point. Solved control/filter/capacitor states are retained. There are no other
hold selectors. This applies to compensated and uncompensated MMCs.

Build and run each project under its own name with a fresh start. Inspect
finite charging and the 0.2 s DC-divisor handover, settling, and every existing
comparison row over [9.8,10.0] s. Use each case's own TSV; Vdc contains both
DUT and SEND references. These revised projects have not been run in PSCAD.
""")

write(joinpath(EXPERIMENTS, "README.md"),
    """
# compensated MMC energy-controlled MMC with physical compensated modulation

mmc_compensated_classic.pscx and mmc_compensated_builder.pscx mirror
build_mmc_grid() in test/adm_MMC_compensated_test.jl: 1060 MVA,
320/400 kV LL RMS transformer, 640 kV DC, 742 MW/0 MVAr,
VSEWithDamping 5/100/10, reactive PI -> filtered CCVI -> OCC,
ΣEnergyControl and ΔEnergyControl (Kp=0.5544, Ki=5.94), CCC
(Kp=0.0992, Ki=42.9719), and 200 us compensated modulation.

The Δ gains are the original values (k=1), matching the core test. With the
corrected triplen frame, the formerly unstable +0.115752 ± j942.538554 s^-1
pair becomes -12.550944 ± j940.716108 s^-1; all 89 Julia poles are stable.
Beyond the deliberately slow stable OCC poles (-0.000628319 s^-1), the
least-damped pair is -4.873459 ± j10.339475 s^-1.

The Σ and Δ notches use fixed nominal frequencies 2*ωbase and ωbase,
respectively, with ζ=sqrt(2)/2; the rotating integrators reproduce
energy.jl:67–151 and inner_current.jl:81–104, including the corrected +3ω triplen
pair. Physical energy measurements retain higher EMT harmonics. The
triplen energy pair is synchronously lifted from the scalar zero sequence.
The 0.2 s hold supplies only the measured DC-voltage divisor, through one
MEAS selector shared by all measured-DC divisions. Every loop uses live
voltage/current, P/Q, PLL and energy feedback from t=0, including iS_z.
Vdc errors and Σ half-DC feedforward are live. Capacitor divisors are live.
The electrical plant starts from rest; its closed loops bring it to the
operating point. Solved control/filter/capacitor states remain initialized.
No other hold selector exists. This shared rule applies to every MMC.

Compensated modulation uses upper vΣ-vΔ and lower vΣ+vΔ voltages,
divided by each arm's own capacitor voltage, then six exact 200 us delays.
History constants are the physical solved ratios at the initial angle.
Julia instead solves the seven-coordinate harmonic law at
src/Network/Components/converter/MMC/modulation.jl:143; a steady harmonic
preflight measured up to 0.003994 insertion-index difference (about 0.004).
The physical ratios contain the mΔZd/mΔZq third-harmonic content and
higher harmonics implicitly; the arm delays apply to that full waveform.
No insertion-index comparison row or tolerance is added.
Saved primitive witnesses and source lines are retained in
test/pscad/fixtures/mmc_energy_saved_fragments.xml. The accepted near-ideal
YY transformer is retained. Exact delays differ from Padé away from
steady state, as already documented for uncompensated modulation.

Build/run each project under its written name: 5 s duration, 1 us
integration, 250 us sampling, zero source ramp, fresh start. The grounded
DC source midpoint needs no added reference resistors.
Each TSV contains solved terminal MW/MVAr, bus voltages/angles, internal
pu references/measurements, initial arm capacitors and all 89 converged
states with state_index. Use each case's own reference.
Inspect finite start-up, release and settling, then compare the last ten
50 Hz cycles [4.8,5.0] s with existing voltage 1%, current 2%, angle
1 degree and power difference 0.01 of converter rating rules. Check all
six capacitor cycle means, signed idc=3*iS_z and abs(omega_c-1)<=1e-3 pu.
Station acceptance requires both cases to build, run finite, settle and
pass every existing row. Both previous classic variants built but diverged:
holding energy hid charging (capacitors about 10,000 kV before release,
non-finite at 0.278 s); the meter-only hold left live energy above frozen
iS_z, opening the inner loop (-59 kA in 5 ms, lower capacitor -94 kV in
2 ms, non-finite at 0.608 s). Compensated division removes the natural
energy balance, making either open-loop window fatal. The divisor-only
revision keeps every inner/outer feedback loop closed from the first step.
After the core frame fix, the station's 10 us case grew from about 2 s
and became non-finite at 2.88 s. At the validated FFVI 1 us step it settled
from 1 s through 4.8 s: P=0.7000000, Q about 1e-7, omega=1,
iS_z=0.233935 (reference 0.233948), all six capacitor means 639.4-639.5 kV
with constant 77.9 kV ripple. Export warns above 1 us without changing
the selected step or the global default. Ten revised MMC
projects and their own references are in mmc-recheck/ for the same station checks.
""")
