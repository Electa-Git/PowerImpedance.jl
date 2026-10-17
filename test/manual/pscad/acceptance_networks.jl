# Manual IEEE9 acceptance; P2P dynamic-validation and IEEE39 build records. Run in a
# PythonCall-enabled environment with POWERIMPEDANCE_PSCAD_CONFIG set. `--export-only`
# writes the projects/references without contacting the station.
using PowerImpedance, PythonCall, LinearAlgebra, DelimitedFiles
include("../../pscad/fixtures.jl")
include("../../pscad/networks.jl")
const P = PowerImpedance.PSCAD
const OUTPUT = mkpath("/tmp/pscad-network-acceptance")
const IEEE9_SETTINGS = P.SimulationSettings(simulation_time = 3.0,
    time_step = 10e-6, sample_step = 100e-6)
const RECORD_SETTINGS = P.SimulationSettings(simulation_time = 25.0,
    time_step = 10e-6, sample_step = 250e-6, source_ramp = 0.0)
BLAS.set_num_threads(1)

function write_reference(model)
    open(joinpath(OUTPUT, model.project_name * "_reference.tsv"), "w") do io
        println(io, "element\tquantity\treference\tunit")
        row(element, quantity, value, unit) = println(io,
            join((element, quantity, value, unit), '\t'))
        for bus in model.netlist.buses
            point = model.operating_point.bus_states[bus.key]
            row(bus.name, "vm", point.vm_pu, "pu")
            row(bus.name, "voltage", point.vm_pu * bus.base_kV * (bus.kind == :dc ? 2 : 1),
                bus.kind == :dc ? "kV_pole_to_pole" : "kV_phase_RMS")
            bus.kind == :dc || row(bus.name, "angle", rad2deg(point.va_rad), "deg")
        end
        for (name, flow) in sort(collect(model.operating_point.branch_flows); by = first)
            for (quantity, value) in pairs(flow)
                row(name, quantity, value, startswith(string(quantity), "q") ? "MVAr" : "MW")
            end
        end
        for e in model.netlist.elements
            e.model isa PowerImpedance.AbstractConverter || continue
            eq = P.converter_equilibrium(e)
            row(e.name, "P_ac_internal", eq.outputs.meas.P_ac_f * e.model.elec.Sbase, "MW")
            row(e.name, "Q_ac_internal", eq.outputs.meas.Q_ac_f * e.model.elec.Sbase, "MVAr")
            row(e.name, "Vdc_internal", eq.inputs.v_dc *
                (e.model isa PowerImpedance.MMC ? e.model.elec.vDC_base : e.model.elec.vDCbase), "kV")
            for (quantity, value) in pairs(eq.states)
                row(e.name, quantity, value, "model_state")
            end
        end
        # These are the same solved-current references used by acceptance.
        for channel in model.probes.channels
            channel.kind == :current && channel.dim == 1 || continue
            e = only(filter(e -> string(e.name) == channel.element, model.netlist.elements))
            bus, point = P._comparison_bus(model, channel.bus)
            flow = model.operating_point.branch_flows[e.name]
            field = e.model isa PowerImpedance.Source ? :pgdc :
                channel.side == "1" ? :pf : :pt
            reference = abs(flow[field]) / (2point.vm_pu * bus.base_kV)
            row(channel.element, "I_dc_side_" * channel.side, reference, "kA")
        end
    end
end

function export_case(name, network; settings = RECORD_SETTINGS,
        status = "export-only", reason = "")
    path = joinpath(OUTPUT, name * ".pscx")
    isfile(path) && rm(path)
    started = time_ns()
    model = Base.invokelatest(export_pscad, network; path, settings)
    elapsed = (time_ns() - started) * 1e-9
    write_reference(model)
    counts = PSCADNetworks.inventory(model.netlist)
    println(name, ": ", counts)
    return (; model, counts, export_seconds = elapsed, status, reason)
end

function build_verdict(messages)
    errors = String[]
    warning, completed = false, false
    for line in split(messages, '\n')
        isempty(strip(line)) && continue
        fields = split(line, '\t'; limit = 4)
        length(fields) == 4 || return "fail"
        status, text = lowercase(strip(fields[1])), strip(fields[4])
        status == "error" && push!(errors, text)
        warning |= status == "warning"
        summary = match(r"\bBuild:\s*(\d+) errors,\s*(\d+) warnings\b", text)
        if summary !== nothing
            summary.captures == ["1", "0"] || return "fail"
            completed = true
        end
    end
    licence = r"^The current license is limited to a maximum of 200 electrical nodes\. This project contains \d+ electrical nodes\.$"
    return length(errors) == 1 && !warning && completed && occursin(licence, only(errors)) ?
           "export verified (licence-blocked)" : "fail"
end

function run_case(case, remote)
    model = case.model
    settings = model.settings
    started = time_ns()
    result, rows, detail = nothing, [], ""
    status = case.status == "build-only" ? "fail" : "run_failed"
    work_root = mkpath(joinpath(remote.local_root, "network-acceptance", model.project_name))
    previous_runs = Set(readdir(work_root; join = true))
    try
        result = compute(model, PSCADRun(); options = (; remote,
            work_root,
            simulation_time = settings.simulation_time, time_step = settings.time_step,
            sample_step = settings.sample_step, verbosity = 2))
        if case.status == "acceptance"
            rows = compare_operating_point(result, model; rtol_v = 0.01,
                atol_angle_deg = 1.0, rtol_i = 0.02)
            open(joinpath(OUTPUT, model.project_name * "_comparison.tsv"), "w") do io
                println(io, "quantity\tname\tpscad\tpowerflow\terror\twithin_tolerance")
                for row in rows
                    println(io, join(values(row), '\t'))
                end
            end
            status = all(rows.within_tolerance) ? "passed" : "comparison_failed"
            detail = result.paths.outputs
        else
            detail = "Expected a licence node-cap build failure; the project completed instead."
        end
    catch error
        detail = sprint(showerror, error)
        write(joinpath(OUTPUT, model.project_name * "_failure.txt"), detail)
    end
    runs = filter(path -> path ∉ previous_runs && isdir(path) &&
        startswith(basename(path), "run-"),
        readdir(work_root; join = true))
    if case.status == "build-only" && result === nothing && length(runs) == 1
        # The runner retains these messages when project.run() stops at the licence check
        # before EMTDC can run. Messages from retained runs cannot establish build or
        # simulation success for this invocation.
        message_path = joinpath(only(runs), "outputs", "build-messages.txt")
        if isfile(message_path)
            status = build_verdict(read(message_path, String))
            detail *= "; build messages: " * message_path
        end
    end
    timing_path = isempty(runs) ? "" :
        joinpath(last(sort(runs; by = mtime)), "outputs", "timing.txt")
    run_seconds = isfile(timing_path) ? parse(Float64, strip(read(timing_path, String))) : NaN
    return (; status, wall_seconds = (time_ns() - started) * 1e-9, run_seconds, detail)
end

function native_dimensions(case, remote)
    name = case.model.project_name
    directory = joinpath(remote.local_root, "network-acceptance", name)
    runs = filter(path -> isdir(path) && startswith(basename(path), "run-"),
        readdir(directory; join = true))
    isempty(runs) && return (missing, missing, missing, missing)
    root = last(sort(runs; by = mtime))
    message_path = joinpath(root, "outputs", "build-messages.txt")
    messages = isfile(message_path) ? read(message_path, String) : ""
    live_match = match(r"The total number of live nodes: (\d+)", messages)
    live_nodes = live_match === nothing ? missing : parse(Int, only(live_match.captures))
    subsystems = occursin("Subsystem splitting has been internally disabled", messages) ? 1 : missing
    path = joinpath(root, "generated.map")
    remote_path = P._remote_path(remote.remote_root,
        P._local_parts(root, remote.local_root)...,
        case.model.settings.output_stem, "generated.gf81", "generated.map")
    text = ""
    try
        P.fetch_station_file(remote, remote_path, path)
        cp(path, joinpath(OUTPUT, name * "_native.map"); force = true)
        text = read(path, String)
    catch error
        write(joinpath(OUTPUT, name * "_map_fetch_failure.txt"), sprint(showerror, error))
        return (live_nodes, missing, missing, subsystems)
    end
    dimension(field) = parse(Int, only(match(Regex("(?m)^\\s*" * field *
        "\\s*=\\s*(\\d+)"), text).captures))
    return (live_nodes, dimension("NODES"), dimension("NNODES"), dimension("SUBSYS"))
end

cases = [
    export_case("ieee9_classic", PSCADFixtures.ieee9_network();
        settings = IEEE9_SETTINGS, status = "acceptance", reason = "network-scale AC case"),
    export_case("p2p_builder", PSCADNetworks.p2p_builder(0.25);
        reason = "dynamic validation only; unstable in Julia, no operating-point acceptance")]

# The gitignored model is deliberately loaded only by this manual script.
local_path = joinpath(pkgdir(PowerImpedance), "local", "P2P_HVDC.jl")
local_status = "absent"
if isfile(local_path)
    namespace = PSCADNetworks.load_through(local_path, :net)
    push!(cases, export_case("p2p_classic", Base.invokelatest(getproperty, namespace, :net);
        reason = "dynamic validation only; unstable in Julia, no operating-point acceptance"))
    local_status = "present; 25 km cable + 75 km DC overhead line"
end
push!(cases, export_case("ieee39_classic", PSCADNetworks.ieee39_classic();
    status = "build-only",
    reason = "licence: node cap; 528 live nodes exceeds EDUCATIONAL 200"))
push!(cases, export_case("ieee39_builder", PSCADNetworks.ieee39_builder();
    status = "build-only",
    reason = "licence: node cap; 528 live nodes exceeds EDUCATIONAL 200"))

open(joinpath(OUTPUT, "inventory.tsv"), "w") do io
    println(io, "project\telements\telement_counts\tac_buses\tdc_buses\telectrical_bus_nodes\tnatural_subsystems\texport_seconds\tstatus\treason")
    for case in cases
        c = case.counts
        println(io, join((case.model.project_name, c.elements,
            join([k * "=" * string(v) for (k, v) in sort(collect(c.counts))], ","),
            c.ac_buses, c.dc_buses, c.bus_nodes, c.subsystems, case.export_seconds,
            case.status, case.reason), '\t'))
    end
end

write(joinpath(OUTPUT, "README.md"), """
# network closing exports

Only ieee9_classic is run and compared by this script. It uses 3 s / 10 us /
100 us at 50 Hz, default 0.05 s source ramp and the final ten cycles (2.8,3.0] s.
Existing comparison rules are unchanged: AC voltage 1%, relative angle 1 degree
and current 2%. The station run-Hcm4nU passed on the EDUCATIONAL licence:
78 live nodes, 41 comparison rows, all within tolerance. Worst voltage magnitude
error was 2.19e-5 relative, worst angle error 4.99e-4 degrees, and worst current
error 0.169% (I_tl64_2, 3.9 A); see ieee9_classic_comparison.tsv.

The committed IEEE9 fixture copies local/IEEE9bus/IEEE9bus_abc.jl physical
parameters and connectivity, including Ct=7 nF/Cs=12 nF on all three YY
transformers. Old source V is already phase peak: Setpoint.Vac receives the same
number, without sqrt(2). Symbolic impedances become functions; transformation=true
selects the supported balanced dq frame. P/Q remain unspecified: all three sources
become type-3 reference buses at angle zero; their P/Q dispatch follows the fixed
voltages, load impedances and network equations. The current classic default
voltage base 220/sqrt(3) kV is retained. Existing transformer PF-bound ratings
are inferred as phase-RMS primary (16.5,18,13.8)/sqrt(3) and secondary 230/sqrt(3)
kV, following test/Transformer_test.jl; they do not enter the explicit transformer
equations. This avoids incompatible bounds from an assumed common primary base.
The station measured 78 live nodes vs the EDUCATIONAL cap of 200. Exported
YY and Delta-Y winding ratings use the solved primary LL RMS voltage, not the
common bus base or open-circuit metadata: IEEE9 16.5/230, 18/230 and 13.8/230 kV.
Changing only these ratings removed the NT_2 zero diagonal and yielded a finite
3 s station run (Bus1 peak 13.47 kV, Bus7 approximately 189 kV).

P2P builder is exported at share 0.25 (25 km cable + 75 km DC OHL).
Classic local/P2P_HVDC.jl: $local_status. Its old phase-RMS source V mapping is
sqrt(2)*V, separate from IEEE9's phase-peak source convention. These P2P records
are dynamic validation only: station fit 3473.033 Hz / 0.687548 ms reproduces
Julia's unstable modes +1374.359/+1426.121 1/s at 3428.518/3526.556 Hz dq
(the two relevant abc sidebands are 3478.518/3476.556 Hz). c1 differential
modulation-delay states carry 98.81–98.84% of converter-state participation.
No P2P operating-point comparison is attempted. The prescribed physical-variant
screen failed: V1/V2/V3 largest located growth +1341.276/+331.226/+263.933 1/s,
frequencies 3500.142/8932.535/15058.576 Hz dq and Nyquist nets 10/6/2.
The original IEEE14 hybrid also failed: +72.786701 1/s at 29.652282 Hz dq,
full-network Nyquist net 3. No variant or correction was applied.

IEEE39 classic and builder have station verdict "export verified (licence-blocked)":
528 live nodes vs the 200-node EDUCATIONAL cap, with Build: 1 errors, 0 warnings.
The criterion is a completed export with all offline checks and a station build
whose only error is the licence node-cap message, with no warnings.
Classic has 90 elements; builder has 89 (T8_9 disconnected).
Both have 49 AC + 2 DC buses, 151 bus conductor nodes and 28 natural subsystems.
The station disables subsystem splitting on the EDUCATIONAL licence and uses
one subsystem; that message is normal. Distributed lines/cables decouple natural
subsystems. Short-section exporters warn when length/299792458 is below the step;
PSCAD aborts when its computed travel time is below the step. The P2P example's
regularized 100 m endpoints cannot run at 10 us and are not acceptance cases.

All P2P and IEEE39 records retain 25 s / 10 us / 250 us, zero source ramp. Every
*_reference.tsv contains solved bus voltages/angles, terminal power flows and,
where present, converter P/Q, DC voltages/currents and converged states.
inventory.tsv separates bus nodes from native internal nodes and marks the
acceptance/export-only/build-only records. Existing endpoint projects and historical station
outputs in this directory are retained as historical evidence and are not run.

Use --export-only to write all projects/references without station contact.
Without that flag, IEEE9 is run and compared and both IEEE39 projects are sent
through the existing runner, which stops at their licence build error before
EMTDC runs on the EDUCATIONAL licence. The fresh build-messages.txt determines
the IEEE39 verdict by error text, regardless of message position; other errors,
warnings or missing/incomplete messages fail. runs.tsv and the verdict table
below record every outcome and wall/native call times. native_dimensions.tsv
collects dimensions only for IEEE9. P2P projects are never built or run.
""")

open(joinpath(OUTPUT, "runs.tsv"), "w") do io
    println(io, "project\texport_seconds\tstatus\twall_seconds\trun_seconds\tdetail")
    for case in cases
        status = case.status == "acceptance" ? "pending station acceptance" :
                 case.status == "build-only" ? "pending station build" : case.status
        println(io, join((case.model.project_name, case.export_seconds, status,
            NaN, NaN, case.reason), '\t'))
    end
end

if !("--export-only" in ARGS)
    remote = RemoteConfig()
    accepted = Ref(true)
    open(joinpath(OUTPUT, "README.md"), "a") do io
        println(io, "\n## This invocation's verdicts\n\n| Project | Verdict |\n| --- | --- |")
    end
    open(joinpath(OUTPUT, "runs.tsv"), "w") do io
        println(io, "project\texport_seconds\tstatus\twall_seconds\trun_seconds\tdetail")
        for case in cases
            if case.status == "export-only"
                println(io, join((case.model.project_name, case.export_seconds,
                    case.status, NaN, NaN, case.reason), '\t'))
                open(joinpath(OUTPUT, "README.md"), "a") do readme
                    println(readme, "| ", case.model.project_name, " | ", case.status, " |")
                end
                continue
            end
            run = run_case(case, remote)
            accepted[] &= run.status in ("passed", "export verified (licence-blocked)")
            println(io, join((case.model.project_name, case.export_seconds, run.status,
                run.wall_seconds, run.run_seconds, replace(run.detail, '\n' => ' ', '\t' => ' ')), '\t'))
            flush(io)
            open(joinpath(OUTPUT, "README.md"), "a") do readme
                println(readme, "| ", case.model.project_name, " | ", run.status, " |")
            end
            println(case.model.project_name, ": ", run.status)
        end
    end
    open(joinpath(OUTPUT, "native_dimensions.tsv"), "w") do io
        println(io, "project\tlive_nodes\tmaximum_node_dimension\tnode_lookup_dimension\tnative_subsystems")
        for case in cases
            case.status == "acceptance" || continue
            println(io, join((case.model.project_name, native_dimensions(case, remote)...), '\t'))
        end
    end
    accepted[] || error("network native acceptance failed; see /tmp/pscad-network-acceptance/runs.tsv")
end
