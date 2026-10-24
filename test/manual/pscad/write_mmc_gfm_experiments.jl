# Local GFM project generation; no station connection.
using PowerImpedance, PythonCall, LinearAlgebra
include("../../pscad/fixtures.jl")
include("../../pscad/topology.jl")
const P = PowerImpedance.PSCAD
const EXPERIMENTS = mkpath("/tmp/pscad-mmc-gfm")
const SETTINGS = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
    sample_step = 250e-6, source_ramp = 0.0)
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
            for quantity in fieldnames(typeof(eq.terminal_pu))
                row(element.name, "reference_" * string(quantity),
                    getproperty(eq.terminal_pu, quantity),
                    quantity == :θ_ac ? "rad" : "pu")
            end
            row(element.name, "reference_v_ac_measured_side",
                eq.terminal_pu.v_ac * PowerImpedance.voltage_filter_ratio(m), "pu")
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
                eq.terminal_pu, m, PowerImpedance.Equil())
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

fixture = PSCADFixtures.mmc_gfm_network()
for (suffix, network) in (("builder", fixture),)
    write_case("mmc_gfm_" * suffix, network, SETTINGS, :none)
end

write(joinpath(EXPERIMENTS, "README.md"),
    """
# GFM MMC grid-forming MMC

mmc_gfm_classic.pscx and mmc_gfm_builder.pscx mirror test/adm_MMC_test.jl's
build_mmc_grid(): 1060 MVA, 320/400 kV LL RMS transformer, 640 kV DC,
VSEWithDamping with its filtered PLL, reactive PI -> filtered CCVI -> OCC,
TEC/ZSCC/CCSC and 200 us uncompensated modulation delay. Control values and
filters follow that Julia fixture. FFVI.pscx is the primitive witness; its
FFVI direct voltage path is not substituted for Julia's CCVI/OCC cascade.
Saved evidence: local/GFM-MMC/FFVI-VSM/PSCAD model/FFVI.pscx:65168–66145
(CCVI), 67793–68955 (PLL), 68956–70164 (VSM), 57638–58619 (filters).
The current exporter uses its accepted near-ideal YY transformer and exact
200 us dq delays with the existing phase compensation, as documented in TLC/MMC.
Exact delay and Julia's Pade(5,5) differ away from steady state.

Build/run under the written filename/namespace: 10 s, 10 us integration,
250 us sampling, zero source ramp, fresh start. The saved FFVI project uses
5 s / 1 us / 250 us at lines 4–6; 10 us follows the accepted MMC cases.
The grounded DC-source midpoint needs no added pole-reference resistors.
The accepted 0.2 s solved-measurement hold remains in MEAS and SIGMA;
physical arm currents/capacitors stay active. omega_c is VSM frequency,
theta_c is its absolute EMT angle. The embedded PLL has separate local nets.

Each reference TSV contains solved terminal MW/MVAr, bus voltages/angles,
internal pu references/measurements, six initial arm capacitor voltages,
and the full converged state vector in state_index order (model_state units).
Use each case's own reference. Inspect finite start-up and release traces,
settling, all six capacitor means and signed idc=3*iS_z. Compare the final ten
50 Hz cycles [9.8,10.0] s with the existing converter rules: voltage 1%,
current 2%, angle 1 degree, power difference 0.01 of converter rating.
The existing omega_c probe adds the machine-speed row: abs(omega-1)<=1e-3 pu.
Station acceptance requires both cases to build, run finite, settle and pass
every comparison row. These generated projects have not been run in PSCAD.
""")
