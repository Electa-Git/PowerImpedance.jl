# Generate local projects only. Run with PowerImpedance and PythonCall installed.
using PowerImpedance, PythonCall
include("../../pscad/fixtures.jl")
include("../../pscad/topology.jl")
const P = PowerImpedance.PSCAD
const EXPERIMENTS = mkpath("/tmp/pscad-mmc-experiments")
const SETTINGS = P.SimulationSettings(simulation_time = 10.0,
    time_step = 10e-6, sample_step = 250e-6, source_ramp = 0.0)

function write_experiment(name, canvas, definitions, signals, settings)
    probes = P.ProbeChannel[]
    for (i, (signal, unit)) in enumerate(signals)
        P.output_probe!(canvas, signal, "experiment", unit,
            (2160 + 324 * ((i - 1) ÷ 4), 108 + 180 * ((i - 1) % 4)))
        push!(probes, P.ProbeChannel(
            signal, :converter_diagnostic, nothing, nothing, nothing, 1, unit))
    end
    plan = P.ProjectPlan(name, "MMC station experiment: " * name,
        P._project_settings(settings, "MMC station experiment: " * name), canvas,
        P.AbstractLineDefinitionPlan[], P.AbstractLineWrapperPlan[], definitions,
        P.ProbeManifest(probes, nothing))
    P.check_connectivity(plan)
    modules = Dict(d.name => d for d in definitions)
    for (canvas_name, drawing) in [("Main", canvas);
                                   [(d.name, d.canvas) for d in definitions]]
        PSCADTopology.check_degrees(PSCADTopology.electrical_graph(drawing, modules), canvas_name)
    end
    P._write_project(plan, joinpath(EXPERIMENTS, name * ".pscx"))
    return plan
end

function experiment_instance!(canvas, definition, project, point, prefix)
    params = [p.name => P.block_value(p.default; unit = isempty(p.unit) ? nothing : p.unit)
              for p in definition.parameters]
    push!(canvas.components, P.ModuleInstancePlan(project * ":" * definition.name, params, point..., 0))
    for port in definition.ports
        port.kind == :electrical && continue
        label = port.kind == :output ? prefix * "_" * port.name : port.name
        P.module_signal_stub!(canvas, (point[1] + port.x, point[2] + port.y), label,
            port.kind == :input ? -1 : 1)
    end
end

fixture = PSCADFixtures.mmc_pq_network()
for (representation, network) in (("builder", fixture),)
    name = "mmc_pq_" * representation
    model = export_pscad(network; path = joinpath(EXPERIMENTS, name * ".pscx"),
        settings = SETTINGS, dc_reference = :none)
    converter = only(filter(e -> e.model isa PowerImpedance.MMC, model.netlist.elements))
    equilibrium = P.converter_equilibrium(converter)
    open(joinpath(EXPERIMENTS, name * "_reference.tsv"), "w") do io
        println(io, "quantity\tvalue\tunit\tstate_index")
        for (element, flow) in pairs(model.operating_point.branch_flows),
            (field, value) in pairs(flow)

            println(io, element, '_', field, '\t', value, '\t',
                startswith(string(field), "q") ? "MVAr" : "MW", "\t0")
        end
        for bus in model.netlist.buses
            point = model.operating_point.bus_states[bus.key]
            println(io, bus.name, "_vm\t", point.vm_pu, "\tpu\t0")
            println(io, bus.name, "_voltage\t",
                point.vm_pu * bus.base_kV * (bus.kind == :dc ? 2 : 1),
                '\t', bus.kind == :dc ? "kV_pole_to_pole" : "kV_phase_RMS", "\t0")
            bus.kind == :dc || println(io, bus.name, "_angle\t", point.va_rad, "\trad\t0")
        end
        y, x = equilibrium.outputs, equilibrium.states
        for (quantity, value, unit) in (("DUT_P_ac_f", y.meas.P_ac_f, "pu"),
            ("DUT_Q_ac_f", y.meas.Q_ac_f, "pu"), ("DUT_v_dc_f", y.meas.v_dc_f, "pu"),
            ("DUT_omega_c", y.sync.ω_c, "pu"), ("DUT_theta_c_initial", x.Δθ_pll, "rad"),
            ("DUT_iS_z", x.iΣ_z, "pu"), ("DUT_i_dc_internal", 3x.iΣ_z * 1000 / 800, "kA"),
            ("DUT_v_Ctot_mean", 800x.vCΣ_z, "kV"))
            println(io, quantity, '\t', value, '\t', unit, "\t0")
        end
        caps = P.mmc_arm_capacitors(x, 800.0)
        for (half, voltages) in (("u", caps.upper), ("l", caps.lower)),
            (phase, voltage) in zip(("a", "b", "c"), voltages)

            println(io, "DUT_v_Ctot_", half, '_', phase, "_initial\t", voltage, "\tkV\t0")
        end
        for (index, (state, value)) in enumerate(pairs(x))
            println(io, state, '\t', value, "\tmodel_state\t", index)
        end
        residual = zeros(length(x))
        PowerImpedance._state_space!(
            residual, collect(values(x)), collect(values(equilibrium.inputs)),
            equilibrium.terminal_pu, converter.model, PowerImpedance.Equil())
        println(io, "equilibrium_residual_max\t", maximum(abs, residual), "\tmodel_rate\t0")
    end
end

# Reuse the solved current-API fixture for the isolated module parameters.
list = P.netlist(fixture, compute(PowerFlowProblem(fixture), ACDCPowerFlow()))
element = only(filter(e -> e.model isa PowerImpedance.MMC, list.elements))
equilibrium = P.converter_equilibrium(element)
short_settings = P.SimulationSettings(simulation_time = 0.1,
    time_step = 10e-6, sample_step = 10e-6, source_ramp = 0.0)

for delayed in (false, true)
    name = delayed ? "mmc_delay" : "mmc_r12"
    abc, dq = P.abc_to_dq_module("ABC_DQ"), P.dq_to_abc_module("DQ_ABC")
    transforms = (; abc = name * ":ABC_DQ", dq = name * ":DQ_ABC")
    delay = delayed ? 200e-6 : 0.0
    m = element.model
    model = PowerImpedance.MMC(; m.meas, m.sync, m.delta_control, m.sigma_control,
        modulation = PowerImpedance.UncompensatedModulation(
            timeDelay = delay, padeOrderNum = 3, padeOrderDen = 3), m.elec)
    e = P.NetlistElement(element.name, element.pscad, model,
        electricalconnections(model), element.terminals, element.role, element.values)
    # Known constant global references initialize exact-delay histories. In the
    # delayed case Δ steps from zero at 0.02 s; Σ remains constant in global dq.
    delta = PowerImpedance.phase_compensated_dq([delayed ? 0.0 : -0.2, 0.0], m.elec.ωbase *
                                                                             delay)
    sigma = PowerImpedance.phase_compensated_dq([0.04, 0.0], -2m.elec.ωbase * delay)
    eq = merge(equilibrium,
        (;
            outputs = merge(equilibrium.outputs,
            (;
                mod = (;
                mΔd = delta.d, mΔq = delta.q, mΣd = sigma.d, mΣq = sigma.q, mΣz = 1.0)))))
    definition = P.mmc_modulation("MOD", e, eq, transforms, short_settings)
    graph = P.BlockGraph(P.ControlBlock[
        P.Const(P.Signal("vM_q_ref"), 0.0), P.Const(P.Signal("vMS_d_ref"), 0.02),
        P.Const(P.Signal("vMS_q_ref"), 0.0), P.Const(P.Signal("vMS_z_ref"), 0.5),
        P.Const(P.Signal("v_dc_f"), 1.0), P.Const(P.Signal("theta_rel"), 0.0)])
    if delayed
        append!(graph.nodes,
            P.ControlBlock[P.TimeStep(P.Signal("experiment_clock_s")),
                P.Compare(P.Signal("experiment_clock_s"), P.Signal("delta_step"), 0.02),
                P.Gain(P.Signal("delta_step"), P.Signal("vM_d_ref"), 80.0 /
                                                                     m.elec.vAC_base)])
    else
        push!(graph.nodes, P.Const(P.Signal("vM_d_ref"), 80.0 / m.elec.vAC_base))
    end
    canvas = P.lower!(P.CanvasPlan(), graph; origin = (72, 108))
    experiment_instance!(canvas, definition, name, (1080, 108), "R12")
    signals = [("R12_m_" * half * "_" * phase, "pu") for half in ("u", "l")
               for phase in ("a", "b", "c")]
    write_experiment(name, canvas, [abc, dq, definition], signals, short_settings)
    open(joinpath(EXPERIMENTS, name * "_reference.tsv"), "w") do io
        println(io, "quantity\tvalue\tunit")
        println(io, "delta_amplitude\t80\tkV")
        println(io, "sigma_dc\t400\tkV")
        println(io, "sigma_amplitude\t16\tkV")
        println(io, "delay\t", delay, "\ts")
        println(io, "delta_step_time\t", delayed ? 0.02 : 0.0, "\ts")
    end
end

name = "mmc_sigma"
abc = P.abc_to_dq_module("ABC_DQ")
transforms = (; abc = name * ":ABC_DQ", dq = name * ":DQ_ABC")
id, iq, iz = 0.023, -0.017, 0.2
# Match the isolated module's held values to its prescribed physical inputs.
x = merge(equilibrium.states,
    (; ξ_Wtot = 0.0, ξ_iΣ_z = 0.0, ξ_iΣ_d = 0.0, ξ_iΣ_q = 0.0,
        iΣ_d = id, iΣ_q = iq, iΣ_z = iz, Δθ_pll = 0.0,
        vCΔ_d = 0.0, vCΔ_q = 0.0, vCΔ_Zd = 0.0, vCΔ_Zq = 0.0,
        vCΣ_d = 0.0, vCΣ_q = 0.0, vCΣ_z = 808.0 / 800.0))
definition = P.mmc_sigma("SIGMA", element, (; states = x), transforms)
phases = (0.0, -2π / 3, 2π / 3)
current_base = element.model.elec.Sbase / element.model.elec.vDC_base
graph = P.BlockGraph(P.ControlBlock[P.Const(P.Signal("theta_c"), 0.0),
    P.Const(P.Signal("P_ac_f"), 0.6), P.Const(P.Signal("v_dc_f"), 1.0)])
for (i, phase) in enumerate(("a", "b", "c"))
    push!(graph.nodes,
        P.Const(P.Signal("circulating_" * phase),
            current_base * (iz + id * cos(phases[i]) + iq * sin(phases[i]))))
    for half in ("u", "l")
        push!(graph.nodes, P.Const(P.Signal("v_Ctot_" * half * "_" * phase), 808.0))
    end
end
push!(graph.nodes,
    P.ArrayMerge(P.Signal.(["circulating_a", "circulating_b", "circulating_c"]), P.Signal("iS_abc")))
canvas = P.lower!(P.CanvasPlan(), graph; origin = (72, 108))
experiment_instance!(canvas, definition, name, (1080, 108), "Sigma")
signals = [("Sigma_" * n, "pu") for n in ("vMS_d_ref", "vMS_q_ref", "vMS_z_ref", "iS_z")]
write_experiment(name, canvas, [abc, definition], signals, short_settings)
open(joinpath(EXPERIMENTS, name * "_reference.tsv"), "w") do io
    println(io, "quantity\tvalue\tunit")
    b = element.model.sigma_control.ccsc.pi_control
    l = element.model.elec.Lₐᵣₘ
    w = element.model.sigma_control.tec.pi_control
    z = element.model.sigma_control.zscc.pi_control
    error = 1 - (808.0 / 800.0)^2
    for (quantity, value) in (("Sigma_iS_z", iz), (
        "Sigma_vMS_z_ref_initial", 0.5 - z.Kp * w.Kp * error / 3),
        ("Sigma_vMS_z_ref_slope", -(z.Kp * w.Ki + z.Ki * w.Kp) * error / 3),
        ("Sigma_vMS_z_ref_quadratic", -z.Ki * w.Ki * error / 6),
        ("Sigma_vMS_d_ref_initial", b.Kp * id + 2l * iq),
        ("Sigma_vMS_q_ref_initial", b.Kp * iq - 2l * id),
        ("Sigma_vMS_d_ref_slope", b.Ki * id), ("Sigma_vMS_q_ref_slope", b.Ki * iq))
        println(io,
            quantity,
            '\t',
            value,
            '\t',
            endswith(quantity, "slope") ? "pu_per_s" :
            endswith(quantity, "quadratic") ? "pu_per_s2" : "pu")
    end
end

name = "mmc_arm"
arm = P.mmc_arm("ARM", P.mmc_si(element.model.elec), 800.0)
canvas = P.CanvasPlan()
# src_ccin_1 positive command injects into its first electrical terminal; the arm meter
# measures POS -> NEG.
P.component!(canvas, "src_ccin_1", (180, 108), [
    "Name" => "forced_current", "Cntrl" => "1", "Tc" => "0.0 [s]"])
P.stub!(canvas, (180, 108), "forced_positive"; direction = -1)
P.stub!(canvas, (216, 108), nothing)
P.module_signal_stub!(canvas, (180, 144), "forced_current_cmd", -1)
experiment_instance!(canvas, arm, name, (1080, 108), "Arm")
P.stub!(canvas, (1026, 108), "forced_positive"; direction = -1)
P.stub!(canvas, (1134, 108), nothing)
P.lower!(canvas,
    P.BlockGraph(P.ControlBlock[P.Const(P.Signal("forced_current_cmd"), 0.01),
        P.Const(P.Signal("m_arm"), 0.5)]);
    origin = (72, 432))
write_experiment(
    name, canvas, [arm], [("Arm_i_arm", "kA"), ("Arm_v_Ctot", "kV")], short_settings)
open(joinpath(EXPERIMENTS, name * "_reference.tsv"), "w") do io
    println(io, "quantity\tvalue\tunit")
    println(io, "Arm_i_arm\t0.01\tkA")
    println(io, "Arm_v_Ctot_initial\t800\tkV")
    println(io, "Arm_v_Ctot_slope\t200\tkV_per_s")
    println(io, "Arm_v_Ctot_final\t820\tkV")
end

write(joinpath(EXPERIMENTS, "README.md"),
    """
Current station status: the earlier four isolated experiments passed. The
unheld full PQ projects failed start-up in round 2. Both revised PQ projects
passed station round 3 with the approved 0.2 s solved-measurement hold.

Generate these files with `test/manual/pscad/write_mmc_experiments.jl` in a Julia
project containing PowerImpedance and PythonCall. Run each project as written,
in its own fresh station run. Preserve the filename stem, project namespace,
module qualifications, and output settings (`pi.out`); do not rename a namespace.

Use the existing RemoteConfig and compute interfaces, for example:

    using PowerImpedance, PythonCall
    remote = RemoteConfig()
    result = compute(PSCADModel("/tmp/pscad-mmc-experiments/mmc_r12.pscx"),
        PSCADRun(); options = (; remote, simulation_time = 0.1,
            time_step = 10e-6, sample_step = 10e-6, verbosity = 1))

For each full PQ project use simulation_time=10.0 and sample_step=250e-6,
retaining time_step=10e-6. The saved PQ project has these same duration/step/
sampling values. Both sources use Tc=0. R15 is checked in the final ten cycles:
inspect P/Q, Vdc, iS_z and capacitor means for settling. theta_c increases at
100π rad/s and is an angle diagnostic rather than a settled scalar.

* mmc_r12: 0.1 s, 10 us step/sample. Known Σ voltage is 400+16*cos(2θ) kV;
  known Δ voltage is 80*cos(θ) kV. θ=100π*t plus phase 0,-2π/3,+2π/3.
  R12_m_u_a/b/c must be 0.5+0.02*cos(2θ)-0.1*cos(θ), and lower channels
  0.5+0.02*cos(2θ)+0.1*cos(θ). At t=0 phase A is 0.42/0.62,
  phases B/C are 0.54/0.44. Multiplication by 800 gives the arm voltage
  references in kV. This isolates the assembly sign without electrical feedback.
* mmc_delay: 0.1 s, 10 us step/sample. Σ has the same 16 kV rotating term;
  Δ steps from zero to the 80 kV rotating term at 0.02 s. Its contribution
  appears after 200 us, at 0.0202 s. Use θ=100π*(t-0.0002) in both terms;
  before the delayed step only Σ contributes. This checks the five exact
  delays and the +ωTd / -2ωTd frame compensation independently of Padé poles.
* mmc_sigma: 0.1 s, 10 us step/sample. Sigma_iS_z=0.2 and
  Sigma_vMS_z_ref follows the quadratic polynomial whose initial value,
  slope and quadratic coefficient are in the reference TSV. The d/q channels
  have the initial values and slopes
  in mmc_sigma_reference.tsv, from Kp*i_d+2Larm*i_q and
  Kp*i_q-2Larm*i_d, with slopes Ki*i_d and Ki*i_q. Capacitors are held at
  808 kV and P_ac_f=0.6: TEC error is 1-(808/800)^2=-0.0201. This
  exercises both energy and zero-sequence PI integrators with known inputs.
* mmc_arm: 0.1 s, 10 us step/sample. Arm_i_arm=+0.01 kA. With insertion
  m=0.5 and N/C_SM=40000, Arm_v_Ctot=800+200*t kV (820 kV at 0.1 s).
  Inspect the first samples as well as the slope: positive current must charge
  the capacitor. This uses the actual electrical arm module and current meter.
* mmc_pq_classic and mmc_pq_builder: 10 s, 10 us step, 250 us sample.
  DUT_P_ac_f=0.6, DUT_Q_ac_f=0.2, DUT_v_dc_f=1, DUT_omega_c=1.
  Network-side powers are 600 MW / 200 MVAr. DUT_iS_z is about 0.20127 pu;
  I_DUT_1 must equal 3*DUT_iS_z*1.25 kA. All six DUT_v_Ctot_u/l_a/b/c
  cycle means should be close to the solved 800 kV; individual instantaneous
  voltages retain the arm ripple. Each reference TSV contains all solved
  terminal flows and bus values, internal pu references, six initial arm
  voltages and the complete converged state vector in state_index order.
  model_state denotes the current Julia realization's coordinate, not SI.

Inspect initialization for finite insertion indices, capacitor voltages and
currents. Sources retain Tc=0. From t=0 until 0.2 s, every consumed control
measurement is held at its solved value. This includes DC voltage in both
modulation and Σ divisions, P/Q, dq voltage/current measurements, circulating
d/q/z currents and TEC energy. MEAS holds go before all ten measurement
filters; solved dynamic filter states remain at equilibrium. PLL/OCC inputs
are the held MEAS outputs, so their local filters remain consistent too.
Σ currents are held after the -2θ transform, and energy after aggregation.
Physical arm current/capacitor dynamics remain active; the PLL angle advances.

The saved TLC time-sig/compare pattern is used for every selector
(local/TLC/Simple_2L_VSC_RL.pscx:5912–5929), with the private 0.2 s release
constant shared with TLC. At 0.2 s all selectors release to measured inputs;
NoFilter outputs switch immediately, while dynamic filter states are continuous.
Inspect 0, 250 us, 0.19975, 0.2 and 0.20025 s and the release transient.
Before release expect DUT_P_ac_f=0.6, DUT_Q_ac_f=0.2, DUT_v_dc_f=1 and
DUT_iS_z equal to its reference TSV. These held probes do not validate actual
terminal powers or idc=3*iS_z during the hold. Use only the final ten cycles,
[9.8,10.0] s, for steady-state comparisons after inspecting R15 settling.
After release the original measured equations and filters are restored;
there is no steady-state clamp, reset, added filter or change of normalization.
A later zero voltage denominator still returns 1e99 in PSCAD. Check that the isolated
transformer side builds/runs without ITRIANG or small-diagonal diagnostics.

The fixture adds current-API TEC (Kp=1.386, Ki=29.70, from adm_MMC_test.jl)
and zero-sequence PI control (the saved CCSC gains 0.1048/48.1914). The saved
PQ model supplies neither pair of gains; this difference is explicit and
these additions were exercised by station round 3. The script specifies no optional
filter or delay; the fixture uses NoFilter and zero delay. It follows the
script's ideal AC source (31_10.jl:114–116), rather than the saved source's
0.5-ohm resistance (GFL_MMC_Validation.pscx:687–710), and its P/Q controller
without voltage support rather than the saved Kd=20/wf=100 voltage droop
(11992–11998). Its ratio is exactly 333/380, rather than rounded 0.8763
(11894–11902). The saved DC source includes R=0.05 ohm (799–813); the
reduced fixture uses an ideal DC source. Saved 640 kV capacitor guesses
(6644, 7128–7192, 7708) are replaced by converged-state initial values.
The near-ideal YY construction adds the accepted
1e-4 pu leakage and 1e-3 % exciting current; Lr/Rr retain the Julia plant's
full recovered reactor values.

Existing comparison policy: network/internal P/Q absolute error <=0.01 pu
of 1000 MVA, and converter-connected DC currents use
abs(diff)/max(abs(ref),1000/800) with rtol_i. Approved MMC station checks reuse
rtol_v=0.01 for capacitor cycle means versus solved Vdc and rtol_i=0.02 for
idc=3*iS_z. The comparison quantities are :converter_arm_voltage and
:converter_dc_current_identity, named by each capacitor probe and DUT_iS_z.
iS_z versus its solved value is reported without an assertion. source_ramp=0
matches the saved MMC source timing. No new tolerance or public keyword is introduced.

Station round 1 (PSCAD 5.1.0): mmc_r12, mmc_delay and mmc_sigma built and
ran for 0.1 s with 10 us sampling. Each CSV contains 10001 samples. The
CSVs in /tmp/pscad-mmc-results were evaluated over the complete run against
the equations above and the reference TSVs, without changing predictions.

| Experiment/channel | Outcome | Maximum absolute deviation |
|---|---|---|
| mmc_r12, all six indices | PASS; R12 closed: upper=Σ-Δ, lower=Σ+Δ | 4.3570402e-9 |
| mmc_delay, all six indices | PASS; arrival exactly 0.0202 s; both frame compensations confirmed | 4.3552753e-9 |
| mmc_sigma, iS_z | PASS | 2.4999999e-10 pu |
| mmc_sigma, vMS_z_ref | PASS | 1.1839700e-8 pu |
| mmc_sigma, vMS_d_ref | PASS | 7.4962259e-12 pu |
| mmc_sigma, vMS_q_ref | PASS | 7.7104817e-10 pu |

Fitting the Σ voltage-reference polynomials at t=0, 0.05 and 0.1 s gives maximum initial-value
deviation 1.4496993e-10 pu, maximum slope deviation 6.8758301e-8 pu/s,
and z quadratic-coefficient deviation 4.8188999e-7 pu/s². The inferred TEC
error is -0.0201000020201 versus -0.0201, deviation 2.0201e-9. These are
measured residuals, not new acceptance tolerances. The delay sample at
0.02019 s has identical upper/lower A indices; at 0.0202 s they are
0.4199999999907 and 0.6200000000093.

The largest Σ residual comes from decimal gain rendering: 1/6 is written as
0.166666667, 1/3 as 0.333333333, and invIzero as 0.266666667. Using the
serialized values gives z polynomial coefficients 0.5009731939049684,
0.4683691994383955 and 4.794803824889667, reproducing the native trace
within 9.44e-15 pu. The gain formatting and original TSVs are unchanged.

mmc_arm failed compilation in round 1 because electrical L/R fields named
armL/armR were indeterminate. The regenerated arm writes literal values
0.05 [H] and 1.07 [ohm], following the saved PQ project's 50e-3 [H] and
1.07 [ohm] at GFL_MMC_Validation.pscx:11345–11359. Every generated module
electrical parameter is now checked for a finite numeric literal, except
identifier metadata Name. Control parameters remain module inputs. No
symbolic electrical construction is admitted without saved station evidence.
At the end of round 1 the revised mmc_arm and both full PQ projects awaited
station build/run. The three passing control experiments do not establish
full MMC acceptance.

Station round 2 (PSCAD 5.1.0): mmc_arm PASS. Positive 0.01 kA charges the
capacitor at 200 kV/s, with a 20 kV rise over 0.1 s. Reported values are
800 kV at zero, 800.001 kV at 10 us and 809.999 kV at 0.05 s. The two
nonzero-time values differ by -0.001 kV from 800+200*t. No full arm trace was
supplied for a whole-run maximum deviation.

Both full PQ projects build without errors or ITRIANG but FAIL start-up:
their module channels are NaN from 250 us. The classic raw files in
/tmp/pscad-mmc-results/pq_round2 contain 40001 samples over 10 s; 21 of 25
channels are non-finite at all 40000 samples after zero. The AC bus voltages
and negative DC pole remain finite. Initial P_ac_f/Q_ac_f/v_dc_f/iS_z are
0/0/0/0 versus solved 0.6/0.2/1/0.20127207609887254 pu. Initial omega_c
and theta_c agree; maximum capacitor initial-value deviation from the TSV
is 3.5632854e-7 kV. The builder failure is station-reported; its raw files
were not supplied. R15 settling is unassessed.

All five saved MMC projects normalize using measured DC voltage. The PQ
witness is local/GFL-MMC/PQ-Mode/GFL_MMC_Validation.pscx: voltmeter V_dc_2
10956–10960, PerUnit_2 instance 9338–9347 and voltage division 4770–4780,
imported Vbase_dc 5055–5063, V_dc_pu_2 controller labels 9783–9787 and
9865–9869, half-Vdc normalization 2954–2969 and 3276–3291. Their PI reset
comparator is 3172–3182, integral Yo=YRst=0 at 3356–3371 and 3413–3428,
and Main t_rst=0 at 621–644. Σ zero-sequence insertion is the constant 1
at 10738–10745. These legacy controls lack the required full TEC/ZSCC.
No applicable nominal-Vdc selector, initialized measurement output or
positive delayed enable was found. XML does not establish the legacy
first-step execution order. The separate TLC nominal-voltage hold is at
local/TLC/Simple_2L_VSC_RL.pscx:5885–5888,5912–5929.

All five saved workspaces have perturbation-task start overrides. The PQ
workspace GFL_MMC_Validation_workSpace.pswx:26–27,42–43 sets start_method=1
and startup_inputfile=Snapshot.snp with both overrides true, while its project
has StartType=0 at line 9. The PQ sweep script freq_sweep_ACDC_full.py:38–46
prepares a cold-start snapshot via an imported helper absent from the supplied
local bundle. This does not establish the native first-step initialization
sequence. No workspace enum meaning or snapshot start is inferred for these
fresh exports.

Every fixture measurement uses zero-state NoFilter; a zero meter input
therefore gives a zero output. iS_z is a stateless arm-meter sum. The existing
Butterworth initialization was checked statically at orders 1–6 for all ten
measurement quantities: 60 initial-output comparisons with zero maximum
deviation. These dynamic filters are not present in the PQ fixture. Σ also
divides by zero in (energy_pi+P_ac_f)/(3*v_dc_f); protecting only modulation
would be insufficient.

At the end of round 2 implementation stopped and the PQ projects/reference
TSVs were retained without regeneration. Review options were a finite hold of solved
measurement outputs (Vdc, P/Q, dq signals and iS_z) before releasing the
measured equations, with duration decided explicitly, or a station experiment
establishing native measurement/inductor initialization and execution order
before choosing initialization-only seeding. Transferring the TLC's 0.2 s
hold to MMC needs a decision. Permanent nominal-Vdc normalization changes
the current modulation and DC response. There is no new tolerance or filter.

The 0.2 s solved-measurement hold described above was subsequently adopted to
avoid the zero-denominator start-up failure. The classic and builder PQ projects
are regenerated with that hold;
their solved reference values and complete state vectors are retained. The
isolated Σ module now has the same selectors, with held values matched to its
prescribed constant current/energy inputs. Its original reference polynomials
are unchanged. Revised native start-up, handover and R15 settling passed in
station round 3.

Station round 3 (PSCAD 5.1.0): both PQ representations PASS, with identical
results over [9.8,10.0] s of their 10 s runs. The handover was clean and no
ITRIANG occurred. Station-reported results:

| Channel/check | Settled value | Reference / reported deviation |
|---|---|---|
| DUT_P_ac_f | 0.5999999 pu | 0.6 pu |
| DUT_Q_ac_f | 0.2000000 pu | 0.2 pu |
| DUT_v_dc_f | 1.0 pu | 1.0 pu |
| DUT_omega_c | 1.000000001 pu | 1.0 pu; diagnostic |
| AC-terminal network-side power | 600.0 + j199.95 MVA | 600 + j200 MVA; P/Q errors 2.6e-9 / 5e-5 pu on 1000 MVA |
| Six capacitor cycle means | 799.46–799.54 kV | 800 kV; approximately -0.06 % |
| Capacitor ripple | 83 kV peak to peak | Diagnostic |
| DUT_iS_z | 0.200977 pu | Solved 0.201272 pu; -0.15 %, diagnostic only |
| I_DUT_1 | 0.753663 kA | 3*DUT_iS_z*1.25 kA to 1e-6 kA |
| DC current versus power flow | 0.753663 kA | 603.41 MW / 800 kV; -0.08 % |

The detailed audits are in /tmp/pscad-mmc-results:
round2_pq_channel_audit.tsv, round2_saved_startup_audit.tsv,
round2_measurement_initialization.tsv and round2_butterworth_initialization.tsv.
""")
