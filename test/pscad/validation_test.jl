module PSCADValidationTests
using Test, PowerImpedance, LinearAlgebra, TOML, SHA
include("../manual/pscad/validation/validation.jl")
const V = PSCADValidation
const P = PowerImpedance.PSCAD

const RESUME_IDENTIFICATIONS = Ref(0)
const RESUME_IDENTITY = Dict("schema" => "2", "version" => "5.1.0",
    "pscad_sha256" => repeat("1", 64), "master_library_sha256" => repeat("2", 64),
    "fortran_version" => "fixture-fortran")

# Reuse only: a local child prints the fixture identity. Any attempted launch
# is an error, so these tests cannot contact a station or execute a PSCAD model.
function P.remote_command(::Val{:validation_resume}, ::RemoteConfig, command::AbstractString)
    occursin("identify.py", command) || error("unexpected native execution during resume")
    RESUME_IDENTIFICATIONS[] += 1
    script = "print(" * repr(sprint(TOML.print, RESUME_IDENTITY)) * ")"
    return `$(Base.julia_cmd()) --startup-file=no --project=@stdlib -e $script`
end

@testset "Manifest empty lists remain appendable after TOML round trip" begin
    record = V.manifest_lists!(Dict{String, Any}(
        "run_records" => Dict{String, Any}[], "model_differences" => String[]))
    @test all(record[field] isa Vector{Any}
    for field in ("run_records", "model_differences"))
    parsed = TOML.parse(sprint(TOML.print, record))
    @test all(isempty(parsed[field])
    for field in ("run_records", "model_differences"))
    V.manifest_lists!(parsed)
    push!(parsed["run_records"], Dict("axis" => "baseline", "project_sha256" => "fixture"))
    push!(parsed["model_differences"], "declared difference")
    restored = TOML.parse(sprint(TOML.print, parsed))
    @test restored["run_records"][1]["axis"] == "baseline"
    @test restored["model_differences"] == ["declared difference"]
    @test all(parsed[field] isa Vector{Any}
    for field in ("run_records", "model_differences"))
end

@testset "Resume an unindexed axis with native completion verification" begin
    mktempdir() do directory
        project = joinpath(directory, "fixture.pscx")
        write(project, "<project fixture=\"resume\"/>")
        settings = P.SimulationSettings(simulation_time = 0.0005,
            sample_step = 0.00025, time_step = 0.00005, output_stem = "scan")
        probes = P.ProbeManifest(
            [P.ProbeChannel("Voltage", :voltage, "B1", nothing, nothing, 1, "kV")], nothing)
        model = PSCADModel(project; settings, probes)
        remote = RemoteConfig("fixture", directory, "unused", "julia", "python";
            local_root = directory, transport = :validation_resume)
        root = mkpath(joinpath(directory, "runs", "baseline-before-crash", "run-complete"))
        cp(project, joinpath(root, "generated.pscx"))
        toolkit = mkpath(joinpath(root, "toolkit"))
        for (name, source) in P.PSCAD_REMOTE_SOURCES
            write(joinpath(toolkit, name), source)
        end
        input = Dict{String, Any}("schema_version" => 1,
            "project_sha256" => V.digest(project), "project_name" => "generated",
            "settings" => P._settings_record(settings),
            "probes" => Dict("names" => ["Voltage"]),
            "toolkit" => Dict(name => bytes2hex(sha256(source))
            for (name, source) in P.PSCAD_REMOTE_SOURCES))
        write(joinpath(root, "computation.toml"), sprint(TOML.print, input))
        output = mkpath(joinpath(root, "outputs"))
        write(joinpath(output, "solver.toml"), sprint(TOML.print, RESUME_IDENTITY))
        write(joinpath(output, "pscad-console.txt"), "offline fixture\n")
        write(joinpath(output, "build-messages.txt"), "normal\tbuild\t\tThe total number of live nodes: 12\n")
        write(joinpath(output, "timing.txt"), "3.25\n")
        parameters = Dict{String, Any}("time_duration" => 0.0005,
            "time_step" => 50.0, "sample_step" => 250.0,
            "PlotType" => "OUT", "output_filename" => "scan.out",
            "StartType" => "STANDARD", "SnapType" => "NONE", "SnapTime" => 0.0,
            "snapshot_filename" => "scan.snp", "MrunType" => "STANDALONE", "Mruns" => 1)
        readback = Dict(key => Dict("requested" => value, "observed" => value)
        for (key, value) in parameters)
        write(joinpath(output, "settings-readback.toml"), sprint(TOML.print, readback))
        write(joinpath(output, "scan.inf"), "PGB(1) Output Desc=\"Voltage\" Group=\"main\" Units=\"kV\"\n")
        data_path = joinpath(output, "scan_01.out")
        write(data_path, "TIME Voltage\n0.0 2.0\n0.00025 2.0\n0.0005 2.0\n")
        P._complete_run(root, input, P._pscad_digest(input), RESUME_IDENTITY)
        partial = mkpath(joinpath(directory, "runs", "baseline-partial", "run-incomplete"))
        write(joinpath(partial, "computation.toml"), sprint(TOML.print, input))
        @test V.completed_axis_runs(directory, "baseline", V.digest(project)) == [root]
        @test isempty(V.completed_axis_runs(directory, "d", V.digest(project)))
        @test isempty(V.completed_axis_runs(directory, "baseline", repeat("0", 64)))
        @test !isfile(joinpath(directory, "manifest.toml"))
        before = [(file["path"], file["sha256"]) for file in V.inventory(directory)]
        RESUME_IDENTIFICATIONS[] = 0
        resumed = V.resume_axis(model, "baseline", directory, remote)
        @test resumed.diagnostics.reused
        @test resumed.paths.run_directory == root
        @test resumed.time ≈ [0.0, 0.00025, 0.0005]
        @test resumed.channels["Voltage"] == fill(2.0, 3)
        @test RESUME_IDENTIFICATIONS[] == 1
        @test before == [(file["path"], file["sha256"]) for file in V.inventory(directory)]
        @test V.resume_axis(model, "d", directory, remote) === nothing
        @test RESUME_IDENTIFICATIONS[] == 1
        changed = PSCADModel(project;
            settings = P.SimulationSettings(
                simulation_time = 0.001, sample_step = 0.00025, time_step = 0.00005,
                output_stem = "scan"),
            probes)
        @test_logs (:warn, r"Retained axis run cannot be resumed") begin
            @test V.resume_axis(changed, "baseline", directory, remote) === nothing
        end
        @test RESUME_IDENTIFICATIONS[] == 1
        open(io -> write(io, "# damaged\n"), data_path, "a")
        @test_logs (:warn, r"Retained axis run cannot be resumed") begin
            @test V.resume_axis(model, "baseline", directory, remote) === nothing
        end
        @test RESUME_IDENTIFICATIONS[] == 1
    end
end

function phase_wave(time, dq)
    return hcat((dq[:, 1] .* cos.(2π .* 50 .* time .+ phase) .+
                 dq[:, 2] .* sin.(2π .* 50 .* time .+ phase)
    for phase in (0, -2π / 3, 2π / 3))...)
end

@testset "Coherent multi-tone and fixed frame" begin
    spec = V.l1_settings()
    time = collect(0.0:spec.sample_step:3.0)
    tone = V.multitone(time, spec.frequencies, spec.phases;
        amplitude = spec.tone_peak_pu, onset = spec.injection_time)
    @test all(iszero, tone[time .< spec.injection_time])
    phasors = V.dft_phasors(time, reshape(tone, :, 1), spec.frequencies;
        start = 1.0, duration = 1.0)
    @test maximum(abs.(vec(phasors) - spec.tone_peak_pu .* cis.(spec.phases))) < 1e-12
    @test maximum(abs, tone) <= length(spec.frequencies) * spec.tone_peak_pu
    @test inv(spec.sample_step * (maximum(spec.frequencies) + spec.frequency)) >= 40
    dq = hcat(1.0 .+ tone, 0.3 .- 2tone)
    @test maximum(abs.(V.fixed_dq(time, phase_wave(time, dq)) - dq)) < 1e-12
    @test_throws ArgumentError V.multitone(time, [1, 1], [0, 0]; amplitude = 1.0)
    @test_throws ArgumentError V.dft_phasors(time, dq, [1.5]; start = 1.0, duration = 1.0)
    @test_throws ArgumentError V.dft_phasors(time, dq, [1.0]; start = 1.0, duration = 3.0)
    bad_time = copy(time)
    bad_time[100] += 1e-6
    @test_throws ArgumentError V.dft_phasors(
        bad_time, dq, [1.0]; start = 1.0, duration = 1.0)
end

@testset "Direct DFT matrix recovery with baseline and mixed inputs" begin
    time = collect(0.0:1e-5:2.2)
    frequencies = [1.0, 7.0, 50.0, 137.0, 1000.0]
    phases = [-π * k * (k - 1) / length(frequencies) for k in eachindex(frequencies)]
    baseline_v = hcat(1 .+ 0.01cos.(2π .* 50 .* time), 0.2 .+ 0.03sin.(2π .* 50 .* time))
    baseline_i = hcat(0.3 .+ 0.02sin.(2π .* 50 .* time), -0.1 .+ 0.04cos.(2π .* 50 .* time))
    known = cat(
        ([0.2 + 0.00001im*f -0.07 + 0.02im; 0.11 - 0.03im 0.4 - 0.00002im*f]
        for f in frequencies)...;
        dims = 3)
    mixing = [1.0 -0.15; 0.2 1.0]
    voltages, currents = Matrix{Float64}[], Matrix{Float64}[]
    for axis in 1:2
        voltage, current = copy(baseline_v), copy(baseline_i)
        for (k, f) in enumerate(frequencies)
            v = 0.01 .* cis(phases[k]) .* mixing[:, axis]
            i = known[:, :, k] * v
            for component in 1:2
                voltage[:, component] .+= real.(v[component] .* cis.(2π .* f .* time))
                current[:, component] .+= real.(i[component] .* cis.(2π .* f .* time))
            end
        end
        push!(voltages, voltage)
        push!(currents, current)
    end
    extracted = V.extract_response(
        time, voltages, currents, baseline_v, baseline_i, frequencies;
        starts = (0.2, 1.2), duration = 1.0)
    maximum_error = maximum(maximum(abs, matrix - known)
    for matrix in extracted.matrices)
    @test maximum_error < 1e-9
    @info "Synthetic admittance recovery" maximum_error
    @test maximum(extracted.conditions) < 2
    @test_throws ArgumentError V.extract_response(
        time, [voltages[1], voltages[1]], currents,
        baseline_v, baseline_i, frequencies; starts = (0.2,), duration = 1.0)
end

@testset "Approved complex comparison and statuses" begin
    frequency = [10.0]
    reference = reshape(ComplexF64[0.0, 0.2im, -0.5, 1.0], 2, 2, 1)
    @test all(row.within_tolerance
    for row in V.comparison_rows(frequency, reference, reference))
    measured = copy(reference)
    measured[1, 1, 1] = 0.00039
    @test all(row.within_tolerance
    for row in V.comparison_rows(frequency, measured, reference))
    measured[1, 1, 1] = 0.00041
    @test !all(row.within_tolerance
    for row in V.comparison_rows(frequency, measured, reference))
    @test all(row.within_tolerance
    for row in V.comparison_rows(frequency, measured, reference; active = true))
    small = fill(ComplexF64(0), 2, 2, 1)
    rows = V.comparison_rows(frequency, small .+ 0.0004, small)
    @test all(!row.phase_scored && row.phase_error_deg == 0 for row in rows)
    @test all(row.within_tolerance for row in rows)
    @test all(row.status == "model_mismatch" && !row.within_tolerance
    for row in V.comparison_rows(frequency, reference, reference; model_mismatch = "declared delay difference"))
    @test all(row.status == "invalid_measurement" && !row.within_tolerance
    for row in V.comparison_rows(frequency, reference, reference; valid = false))
    measured = reference .* cis(deg2rad(3.1))
    @test !all(row.within_tolerance
    for row in V.comparison_rows(frequency, measured, reference; active = true))
    @test_throws ArgumentError V.comparison_rows(frequency, measured .* NaN, reference)
end

@testset "Passive catalogue and generated source plans" begin
    @test length(V.REGISTRY) == 9
    @test length(unique(entry.id for entry in V.REGISTRY)) == 9
    for entry in filter(e->startswith(e.id,"L1-"),V.REGISTRY)
        net = entry.factory()
        @test V.passive_gate(net, entry)["status"] == "passed"
        powerflow = entry.id == "L1-08" ? power_flow(net) : nothing
        @test P.check_connectivity(P.build_plan(P.netlist(net, powerflow))) === nothing
    end
    net = V.ac_rl_network()
    list = P.netlist(net, power_flow(net))
    baseline, _ = V.l1_plan(list, "l1_01", :baseline)
    for axis in (:baseline, :d, :q)
        plan, settings = V.l1_plan(list, "l1_01", axis)
        @test P.check_connectivity(plan) === nothing
        @test length(plan.modules) == 2
        @test count(c -> c.defn == "master:source_3", plan.main.components) == 1
        controlled = last(plan.modules)
        sources = filter(c -> c.defn == "master:source_1", controlled.canvas.components)
        @test length(sources) == 3
        @test all(Dict(c.params)["Cntrl"] == "1" && Dict(c.params)["Grnd"] == "1"
        for c in sources)
        sums = filter(c -> c.defn == "master:sumjct", controlled.canvas.components)
        @test !isempty(sums)
        @test all(count(pin -> Dict(c.params)[pin] != "0", (
                      "A", "B", "C", "D", "E", "F", "G")) >= 2
        for c in sums)
        instance = only(filter(c -> c isa P.ModuleInstancePlan, plan.main.components))
        @test Dict(instance.params) == Dict(
            "d_amplitude_pu" => string(axis == :d ? V.l1_settings().tone_peak_pu : 0.0),
            "q_amplitude_pu" => string(axis == :q ? V.l1_settings().tone_peak_pu : 0.0))
        # The amplitude values are the sole construction difference.
        @test repr(plan.modules) == repr(baseline.modules)
        index = only(findall(c -> c isa P.ModuleInstancePlan, plan.main.components))
        plan.main.components[index] = baseline.main.components[index]
        @test repr(plan) == repr(baseline)
        @test settings.time_step == 2e-6
    end
    @test_throws ArgumentError V.l1_plan(list, "l1_01", :unknown)
    # Independent physical RL dq law in the positive-sine q convention.
    native = V.reference_admittance(net)
    for (k, f) in enumerate(V.l1_settings().frequencies)
        z = [20 + im*2π*f*0.05 2π*50*0.05; -2π*50*0.05 20 + im*2π*f*0.05]
        @test native[:, :, k] ≈ inv(z) atol = 1e-12
    end
end

@testset "Baseline project clones differ only in amplitude" begin
    template = "<component><param name=\"d_amplitude_pu\" value=\"0.0\"/>" *
               "<param name=\"q_amplitude_pu\" value=\"0.0\"/></component>"
    @test V.injection_project(template, :baseline) == template
    for axis in (:d, :q)
        injected = V.injection_project(template, axis)
        changed = "<param name=\"$(axis)_amplitude_pu\" value=\"$(V.l1_settings().tone_peak_pu)\"/>"
        original = "<param name=\"$(axis)_amplitude_pu\" value=\"0.0\"/>"
        @test length(findall(changed, injected)) == 1
        @test replace(injected, changed => original; count = 1) == template
    end
    @test_throws ArgumentError V.injection_project(template, :unknown)
    @test_throws ErrorException V.injection_project(template * template, :d)
    @test_throws ErrorException V.injection_project("<project/>", :baseline)
end

@testset "L1-01 native reference through measurement and file output" begin
    net = V.ac_rl_network()
    list = P.netlist(net, power_flow(net))
    spec = V.l1_settings()
    time = collect(0.0:spec.sample_step:spec.simulation_time)
    a = net.elements[:grid_a].setpoint
    b = net.elements[:grid_b].setpoint
    voltage_a = [a.Vac*cos(a.θac), -a.Vac*sin(a.θac)]
    voltage_b = [b.Vac*cos(b.θac), -b.Vac*sin(b.θac)]
    current_0 = PowerImpedance.get_y(net.elements[:branch], ComplexF64(0)) *
                [voltage_a; voltage_b]
    reference = V.reference_admittance(net)
    models, results = Dict{String, P.PSCADModel}(), Dict{String, P.PSCADResult}()
    for (axis_index, axis) in enumerate(("baseline", "d", "q"))
        name = "l1_01_" * axis
        plan, settings = V.l1_plan(list, name, Symbol(axis))
        models[axis] = P.PSCADModel("synthetic.pscx", name, list, plan.probes, settings,
            list.operating_point, (source = :synthetic,))
        va = repeat(permutedims(voltage_a), length(time), 1)
        vb = repeat(permutedims(voltage_b), length(time), 1)
        ia = repeat(permutedims(real.(current_0[1:2])), length(time), 1)
        if axis != "baseline"
            injected_axis = axis_index - 1
            va[:, injected_axis] .+= V.multitone(time, spec.frequencies, spec.phases;
                amplitude = spec.tone_peak_pu * spec.voltage_base_kV, onset = spec.injection_time)
            for (k, f) in enumerate(spec.frequencies), component in 1:2

                phasor = reference[component, injected_axis, k] * spec.tone_peak_pu *
                         spec.voltage_base_kV * cis(spec.phases[k])
                ia[:, component] .+= real.(phasor .* cis.(2π .* f .* time))
            end
        end
        channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
        for probe in plan.probes.channels
            values = probe.kind == :voltage ? (probe.bus == "A" ? va : vb) :
                     probe.bus == "A" ? ia : -ia
            abc = phase_wave(time, values)
            for component in 1:3
                channels[probe.name * ":" * string(component)] = abc[:, component]
            end
        end
        results[axis] = P.PSCADResult(
            PSCADRun(), time, channels, plan.probes, settings, (;), (;))
    end
    mktempdir() do directory
        outcome = V.compare_frequency_runs(results, models, reference, directory)
        @test outcome["status"] == "passed"
        @test outcome["max_frobenius_error"] < 1e-9
        @test isfile(joinpath(directory, "comparison_C.tsv"))
        @test length(readlines(joinpath(directory, "comparison_C.tsv"))) ==
              1 + 4length(spec.frequencies)
        files = V.inventory(directory)
        @test all(file["bytes"] > 0 && length(file["sha256"]) == 64 for file in files)
        @info "L1-01 synthetic pipeline" max_frobenius_error = outcome["max_frobenius_error"]
    end
end
@testset "General DC/AC/network matrix recovery and refinement gates" begin
    time = collect(0.0:2e-5:2.2)
    frequencies = [1.0, 7.0, 137.0, 1000.0]
    for dimension in (1, 2, 3, 4, 6), quantity in ("Y", "Z")

        known = cat(
            ([complex(0.15*(r==c)+0.01r, 0.02c+f*1e-5)
              for r in 1:dimension, c in 1:dimension] for f in frequencies)...;
            dims = 3)
        baseline_input = fill(0.1, length(time), dimension)
        baseline_output = fill(0.2, length(time), dimension)
        inputs, outputs = Matrix{Float64}[], Matrix{Float64}[]
        for column in 1:dimension
            input, output = copy(baseline_input), copy(baseline_output)
            for (k, f) in enumerate(frequencies)
                input[:, column] .+= 0.001cos.(2π*f .* time)
                for row in 1:dimension
                    output[:, row] .+= real.(0.001known[row, column, k] .*
                                             cis.(2π*f .* time))
                end
            end
            push!(inputs, input)
            push!(outputs, output)
        end
        extracted = V.extract_response(
            time, inputs, outputs, baseline_input, baseline_output,
            frequencies; starts = (0.2, 1.2), duration = 1.0)
        error = maximum(maximum(abs, actual-known) for actual in extracted.matrices)
        @test error < 1e-9
        @test all(row.within_tolerance
        for row in V.comparison_rows(frequencies, known, known))
        @info "General coherent matrix recovery" dimension quantity maximum_error=error
        @test V.matrix_change(known*1.009, known; epsilon = 0.01)["passed"]
        @test !V.matrix_change(known*1.011, known; epsilon = 0.01)["passed"]
        @test V.matrix_change(known*1.019, known; epsilon = 0.02)["passed"]
        @test !V.matrix_change(known*1.021, known; epsilon = 0.02)["passed"]
    end
    spec=V.l1_settings()
    for f in (1.0, 237.0, 750.0, 1000.0)
        refined=V.step_definition(spec, f)
        @test refined.time_step==1e-6
        @test all(isapprox.(refined.frequencies .* refined.window_duration,
            round.(refined.frequencies .* refined.window_duration); atol = 1e-10))
        @test refined.simulation_time==last(refined.window_starts)+refined.window_duration
    end
end

@testset "Every L1 port construction and native reduction" begin
    for entry in filter(e->startswith(e.id,"L1-"),V.REGISTRY)
        net=entry.factory()
        list=P.netlist(net, power_flow(net))
        spec, reference=V.scan_definition(entry.id, net, list)
        @test all(isfinite, reference)
        @test size(reference)==(
            length(spec.axes), length(spec.axes), length(spec.frequencies))
        @test spec.travel_lower_bound_s==0 || spec.time_step<spec.travel_lower_bound_s
        @test inv(spec.sample_step*(maximum(spec.frequencies)+50))>=40
        if entry.id in ("L1-02", "L1-05")
            @test net.elements[:line].pins[Symbol("2.1")] ==
                  net.elements[entry.id == "L1-02" ? :rc : :ohl].pins[Symbol("1.1")]
            @test net.elements[:to].pins[Symbol("1.1")] ==
                  net.elements[entry.id == "L1-02" ? :rc : :ohl].pins[Symbol("2.1")]
            @test net.elements[:to].pins[Symbol("1.1")] !=
                  net.elements[:line].pins[Symbol("2.1")]
        elseif entry.id=="L1-08"
            @test maximum(abs, reference[1:2, :, :])<1e-10
            @test maximum(abs, reference[:, 1:2, :])<1e-10
            @test maximum(abs, reference[3:4, 3:4, :])>0.1
        end
        baseline, _=V.scan_plan(list, spec, "baseline")
        for (column, axis) in enumerate(spec.axes)
            plan, _=V.scan_plan(list, spec, axis)
            @test P.check_connectivity(plan)===nothing
            @test repr(plan.modules)==repr(baseline.modules)
            for index in eachindex(plan.main.components)
                c=plan.main.components[index]
                if c isa P.ModuleInstancePlan
                    plan.main.components[index]=baseline.main.components[index]
                end
            end
            @test repr(plan)==repr(baseline)
        end
        for definition in baseline.modules
            sums=filter(c->c.defn=="master:sumjct", definition.canvas.components)
            @test all(count(pin->Dict(c.params)[pin]!="0", (
                          "A", "B", "C", "D", "E", "F", "G"))>=2 for c in sums)
        end
        # Use independent constant dq/DC samples to verify every probe mapping,
        # differential pole scaling, full port ordering and direct-Z input choice.
        settings=V.scan_settings(spec)
        time=[0.0, 0.01, 0.02]
        voltage=collect(1.0:length(spec.axes))
        current=voltage .+ 10
        channels=PowerImpedance.OrderedDict{String, Vector{Float64}}()
        for (port, bus) in enumerate(spec.buses)
            indices=(spec.dimension * (port - 1) + 1):(spec.dimension * port)
            if spec.dimension==1
                for pole in ("P", "N")
                    probe=only(filter(
                        c->c.kind==:voltage && c.bus==bus.name && c.side==pole,
                        baseline.probes.channels))
                    channels[probe.name]=fill((pole=="P" ? 1 : -1)*voltage[first(indices)]/2, 3)
                end
            else
                probe=only(filter(c->c.kind==:voltage && c.bus==bus.name, baseline.probes.channels))
                abc=phase_wave(time, repeat(voltage[indices]', 3, 1))
                for phase in 1:3
                    channels[probe.name * ":" * string(phase)]=abc[:, phase]
                end
            end
            element, side=spec.currents[port]
            probe=only(filter(c->c.element==element && c.side==side, baseline.probes.channels))
            direction = probe.orientation == (spec.quantity == "Y" ? :into : :out) ? 1 : -1
            if spec.dimension==1
                channels[probe.name]=fill(direction * current[first(indices)], 3)
            else
                abc=phase_wave(time, repeat((direction .* current[indices])', 3, 1))
                for phase in 1:3
                    channels[probe.name * ":" * string(phase)]=abc[:, phase]
                end
            end
        end
        model=P.PSCADModel("synthetic.pscx", "synthetic", list, baseline.probes,
            settings, list.operating_point, (source = :synthetic,))
        result=P.PSCADResult(
            PSCADRun(), time, channels, baseline.probes, settings, (;), (;))
        sampled=V.scan_samples(result, model, spec)
        @test maximum(abs, sampled.voltage-repeat(voltage', 3, 1))<1e-12
        @test maximum(abs, sampled.current-repeat(current', 3, 1))<1e-12
        @test sampled.input == (spec.quantity=="Y" ? sampled.voltage : sampled.current)
        @test sampled.output == (spec.quantity=="Y" ? sampled.current : sampled.voltage)
    end
end

@testset "Native Dyn11 rotation acts on both voltage and current sides" begin
    yy=V.PSCADFixtures.transformer_network().classic.elements[:line]
    dy=V.PSCADFixtures.transformer_network(organization = :ΔY).classic.elements[:line]
    rotation=[cos(π/6) sin(π/6); -sin(π/6) cos(π/6)]
    transform=[Matrix{Float64}(I, 2, 2) zeros(2, 2); zeros(2, 2) rotation]
    for f in (1.0, 42.0, 1000.0)
        yyy=PowerImpedance.get_y(yy, ComplexF64(im*2π*f))
        ydy=PowerImpedance.get_y(dy, ComplexF64(im*2π*f))
        @test ydy≈transform*yyy*transform' rtol=1e-10 atol=1e-12
    end
    @test rotation*[1.0, 0.0] ≈ [cos(π/6), -sin(π/6)]
    v=[0.7, 0.2]
    i=[0.3, -0.1]
    @test dot(rotation*v, rotation*i) ≈ dot(v, i)
end

@testset "Lowered tone graph agrees with independent multi-tone samples" begin
    spec=V.l1_settings()
    graph, signal, _=V.tone_graph(spec)
    times=[0.1, 0.6, 1.017, 2.049]
    expected=V.multitone(times, spec.frequencies, spec.phases;
        amplitude = spec.voltage_base_kV, onset = spec.injection_time)
    for (k, t) in enumerate(times)
        values=Dict{String, Float64}()
        for node in graph.nodes
            value=if node isa P.TimeStep
                t
            elseif node isa P.Compare
                values[node.input.name]>node.threshold ? 1.0 : 0.0
            elseif node isa P.Const
                node.value
            elseif node isa P.Gain
                node.g*values[node.input.name]
            elseif node isa P.Sum
                sum(sign*values[input.name]
                for (sign, input) in zip(node.signs, node.inputs))
            elseif node isa P.Trig
                node.kind==:cos ? cos(values[node.input.name]) :
                sin(values[node.input.name])
            elseif node isa P.Mult
                values[node.left.name]*values[node.right.name]
            else
                error("unexpected tone primitive")
            end
            values[node.output.name]=value
        end
        @test values[signal.name] ≈ expected[k] atol=1e-10
    end
end
@testset "abc port construction, phase twin, extraction and local Z acceptance" begin
    synthetic_maximum = 0.0
    for id in ("L1-03", "L1-04", "L1-08")
        net = V.fixture(id).factory()
        list = P.netlist(net, power_flow(net))
        spec, native = V.applicable_scan(id, net, list)
        @test spec.dimension == 3
        if id in ("L1-03", "L1-04")
            start = id == "L1-03" ? 5.0 : 20.0
            @test spec.protocol == "abc_settled"
            @test spec.window_starts == (start, start + 1.0)
            @test spec.simulation_time == start + 2.0
            witness = V.step_definition(spec, 316.0)
            @test first(witness.window_starts) >= start
            @test witness.simulation_time >= start + 2witness.window_duration
        end
        @test spec.axes == ["p$(port)_$(phase)" for port in 1:2 for phase in ("a", "b", "c")]
        @test 50.0 in spec.frequencies
        @test size(native) == (6, 6, 24)
        @test all(isfinite, native)
        @test spec.sample_step*maximum(spec.frequencies) <= 1/40
        if id == "L1-08"
            twin = V.phase_twin(net, list)
            @test all(!e.transformation && e.input_pins == e.output_pins == 3 for e in values(twin.elements))
            for (name, element) in net.elements
                @test repr(element.element_model) == repr(twin.elements[name].element_model)
                @test element.setpoint == twin.elements[name].setpoint
                @test PowerImpedance.get_abcd(twin.elements[name], ComplexF64(im*2π*137)) ≈
                      eval_abcd(element.element_model, ComplexF64(im*2π*137))
            end
            @test maximum(abs, native[1:3, :, :]) < 1e-10
            @test maximum(abs, native[:, 1:3, :]) < 1e-10
            legacy, _ = V.scan_definition(id, net, list)
            incidence_before = [copy(e.pins) for e in values(net.elements)]
            diagnostic = V.projected_admittance_z(net, list, legacy, 237.0)
            @test size(diagnostic) == (4, 4)
            @test maximum(abs, diagnostic[1:2, :]) < 1e-10
            @test all(isfinite, diagnostic)
            @test incidence_before == [e.pins for e in values(net.elements)]
        else
            for (k, f) in enumerate(spec.frequencies)
                @test native[:, :, k] ≈ PowerImpedance.abcd_to_y(
                    eval_abcd(net.elements[:line].element_model, ComplexF64(im*2π*f)))
            end
        end
        baseline_plan, settings = V.scan_plan(list, spec, "baseline")
        for axis in spec.axes
            plan, _ = V.scan_plan(list, spec, axis)
            @test repr(plan.modules) == repr(baseline_plan.modules)
            @test P.check_connectivity(plan) === nothing
            parameters = [pair for c in plan.main.components if c isa P.ModuleInstancePlan
                for pair in c.params if endswith(first(pair), "_amplitude_pu")]
            @test count(pair -> parse(Float64, last(pair)) != 0, parameters) == 1
            for index in eachindex(plan.main.components)
                plan.main.components[index] isa P.ModuleInstancePlan &&
                    (plan.main.components[index] = baseline_plan.main.components[index])
            end
            @test repr(plan) == repr(baseline_plan)
        end
        # Voltage ports add per-phase gains after nominal dq->abc; current ports
        # merge phase commands directly. No perturbation undergoes Park rotation.
        for definition in baseline_plan.modules
            occursin("Port", definition.name) || continue
            @test Set(parameter.name for parameter in definition.parameters) ==
                  Set(["a_amplitude_pu", "b_amplitude_pu", "c_amplitude_pu"])
            sums = filter(c -> c.defn == "master:sumjct", definition.canvas.components)
            @test all(count(pin -> Dict(c.params)[pin] != "0", ("A", "B", "C", "D", "E", "F", "G")) >= 2 for c in sums)
        end
        # Independent known 6x6 Y / pair of 3x3 direct Z responses. Full physical
        # probe paths, inward/outward conversion, baseline and coherent DFT run.
        frequencies = [1.0, 7.0, 50.0, 137.0, 1000.0]
        spec = merge(spec, (; frequencies, phases = [-π*k*(k-1)/5 for k in 1:5],
            window_starts = (0.2, 1.2), window_duration = 1.0,
            simulation_time = 2.2, injection_time = 0.0, sample_step = 2e-5))
        time = collect(0.0:spec.sample_step:spec.simulation_time)
        known_pu = cat(([complex(0.15*(r==c)+0.01r, 0.02c+f*1e-5)
            for r in 1:6, c in 1:6] for f in frequencies)...; dims = 3)
        if spec.quantity == "Z"
            known_pu[1:3, :, :] .= 0
            known_pu[:, 1:3, :] .= 0
        end
        input_base = spec.quantity == "Y" ? spec.voltage_bases : spec.current_bases
        output_base = spec.quantity == "Y" ? spec.current_bases : spec.voltage_bases
        known = known_pu .* reshape(output_base, :, 1, 1) ./ reshape(input_base, 1, :, 1)
        models, results = Dict{String, P.PSCADModel}(), Dict{String, P.PSCADResult}()
        for (axis_index, axis) in enumerate(["baseline"; spec.axes])
            plan, settings = V.scan_plan(list, spec, axis)
            voltage = reduce(hcat, [phase_wave(time, repeat([spec.voltage_bases[3port-2] 0.0], length(time), 1)) for port in 1:2])
            current = zeros(length(time), 6)
            input, output = spec.quantity == "Y" ? (voltage, current) : (current, voltage)
            if axis != "baseline"
                column = axis_index-1
                for (k, f) in enumerate(frequencies)
                    drive = spec.tone_peak_pu * input_base[column] * cis(spec.phases[k])
                    input[:, column] .+= real.(drive .* cis.(2π*f .* time))
                    for row in 1:6
                        output[:, row] .+= real.(known[row, column, k]*drive .* cis.(2π*f .* time))
                    end
                end
            end
            channels = PowerImpedance.OrderedDict{String, Vector{Float64}}()
            for (port, bus) in enumerate(spec.buses)
                indices = (3port-2):3port
                vp = only(filter(c -> c.kind == :voltage && c.bus == bus.name, plan.probes.channels))
                owner, side = spec.currents[port]
                ip = only(filter(c -> c.kind == (spec.quantity == "Y" ? :current : :injection_current) &&
                    c.element == owner && c.side == side, plan.probes.channels))
                sign = ip.orientation == (spec.quantity == "Y" ? :into : :out) ? 1 : -1
                for phase in 1:3
                    channels[vp.name * ":" * string(phase)] = voltage[:, indices[phase]]
                    channels[ip.name * ":" * string(phase)] = sign * current[:, indices[phase]]
                end
            end
            models[axis] = P.PSCADModel("synthetic.pscx", plan.name, list, plan.probes,
                settings, list.operating_point, (source = :synthetic,))
            results[axis] = P.PSCADResult(PSCADRun(), time, channels, plan.probes, settings, (;), (;))
            samples = V.scan_samples(results[axis], models[axis], spec)
            @test samples.voltage == voltage
            @test samples.current == current
        end
        mktempdir() do directory
            outcome = V.compare_frequency_runs(results, models, known, directory; spec)
            @test outcome["status"] == "passed"
            @test outcome["max_frobenius_error"] < 1e-9
            synthetic_maximum = max(synthetic_maximum, outcome["max_frobenius_error"])
            @test length(readlines(joinpath(directory, "comparison_C.tsv"))) ==
                1+(spec.quantity == "Y" ? 36 : 18)*length(frequencies)
            column = 4
            actual, quality = V.single_response(results[spec.axes[column]], results["baseline"],
                models[spec.axes[column]], spec, column)
            @test quality["valid"]
            @test maximum(abs, actual-known_pu[:, column:column, :]) < 1e-9
        end
        if spec.quantity == "Z"
            bad = copy(known_pu)
            bad[4:6, 4:6, :] .*= 1.03
            rows = V.response_rows(spec, bad, known_pu)
            @test !all(row.within_tolerance for row in rows)
            @test maximum(row.frobenius_error for row in rows) ≈ 0.03
        end
    end
    @info "abc full-probe synthetic recovery" maximum_frobenius_error = synthetic_maximum
    net = V.fixture("L1-05").factory()
    spec, reference = V.applicable_scan("L1-05", net, P.netlist(net, power_flow(net)))
    @test spec.window_starts == (6.0, 7.0)
    @test spec.simulation_time == 8.0
    @test V.step_definition(spec, 1000.0).window_starts == (6.0, 6.1)
    @test V.step_definition(spec, 1.0).window_starts == (6.0, 7.0)
    @test V.step_prefix(V.step_definition(spec, 1000.0)) == "settled_half_step_750_1000__"
end
@testset "Steady abc drift and floating YY neutral constraints" begin
    time = collect(0.0:1e-4:3.0)
    signal = hcat(cos.(2π*50 .* time), sin.(2π*50 .* time), cos.(2π*50 .* time .+ 0.2)) .+ 0.01
    spec = merge(V.l1_settings(), (; dimension = 3, axes = ["a", "b", "c"], quantity = "Y"))
    base = (input = signal, output = signal, input_base = ones(3), output_base = ones(3))
    drive = V.multitone(time, spec.frequencies, spec.phases; amplitude = spec.tone_peak_pu, onset = 0.5)
    runs = [merge(base, (; input = signal + drive * [Float64(j == k) for j in 1:3]',
        output = signal + drive * ones(3)')) for k in 1:3]
    quality = V.scan_quality(time, base, runs, spec)
    @test quality["valid"] && quality["baseline_dc_drift"] < 1e-12 && quality["baseline_fundamental_drift"] < 1e-12
    decaying = signal .+ 0.02exp.(-time)
    bad = merge(base, (; input = decaying, output = decaying))
    bad_runs = [merge(bad, (; input = decaying + drive * [Float64(j == k) for j in 1:3]',
        output = decaying + drive * ones(3)')) for k in 1:3]
    @test V.scan_quality(time, bad, bad_runs, spec)["baseline_dc_drift"] > 1e-3
    net = V.fixture("L1-08").factory()
    list = V.P.netlist(net, power_flow(net))
    twin = V.phase_twin(net, list)
    a = cis(2π / 3)
    plus = ComplexF64[1, a^2, a]
    minus = conj(plus)
    for e in values(net.elements)
        e.element_model isa PowerImpedance.Transformer || continue
        model = e.element_model
        for frequency in (1.0, 50.0, 1000.0)
            s = ComplexF64(im * 2π * frequency)
            grounded = PowerImpedance.abcd_to_y(eval_abcd(model, s))
            floating = V.floating_star_transformer_y(model, s; regularization = false)
            for side in 1:2, sequence in (plus, minus)
                excitation = zeros(ComplexF64, 6)
                excitation[(3side-2):3side] = sequence
                @test floating * excitation ≈ grounded * excitation rtol = 1e-11 atol = 1e-12
            end
            # Only the externally grounded/bridging capacitors carry zero
            # sequence: floating winding neutrals pass none across the core.
            capacitance = s .* [(model.Cₜ+model.Cₛ)*Matrix{Float64}(I,3,3) -model.Cₛ*Matrix{Float64}(I,3,3);
                -model.Cₛ*Matrix{Float64}(I,3,3) (model.Cₜ+model.Cₛ)*Matrix{Float64}(I,3,3)]
            excitation = [ones(3); zeros(3)]
            @test floating * excitation ≈ capacitance * excitation atol = 1e-11
        end
    end
    buses = [V.port_probe(list, :g1, 1), V.port_probe(list, :l5, 1)]
    response = V.phase_network_z(twin, buses, 50.0; floating_stars = true)
    @test maximum(abs, response[1:3, :, :]) == 0
    @test all(isfinite, response) && norm(response[4:6, 4:6]) > 0
end

@testset "Perturbation departure uses declared windows and retains steady offsets" begin
    time=collect(0.0:1e-4:3.0)
    spec=merge(V.l1_settings(),(;dimension=1,axes=["dc"],quantity="Y",
        frequencies=[1.0],phases=[0.0],tone_peak_pu=0.004))
    baseline=(input=ones(length(time),1),output=ones(length(time),1),input_base=[1.0],output_base=[1.0])
    wave=reshape(V.multitone(time,spec.frequencies,spec.phases;amplitude=spec.tone_peak_pu,onset=spec.injection_time),:,1)
    whole=copy(wave);whole[1]=0.2 # turn-on/startup evidence outside the C windows
    run=merge(baseline,(input=baseline.input+whole,output=baseline.output+0.4whole))
    quality=V.scan_quality(time,baseline,[run],spec)
    @test quality["valid"]
    @test quality["input_departure_pu"]≈0.004
    @test quality["full_run_input_departure_pu"]≈0.2
    half=copy(wave)/2;half[1]=0.2
    half_run=merge(baseline,(input=baseline.input+half,output=baseline.output+0.4half))
    half_quality=V.scan_quality(time,baseline,[half_run],merge(spec,(tone_peak_pu=0.002,)))
    @test half_quality["valid"]
    @test half_quality["input_departure_pu"]≈quality["input_departure_pu"]/2
    @test half_quality["full_run_input_departure_pu"]≈quality["full_run_input_departure_pu"]
    unsafe=0.011wave/spec.tone_peak_pu
    unsafe_run=merge(baseline,(input=baseline.input+unsafe,output=baseline.output+0.4unsafe))
    @test !V.scan_quality(time,baseline,[unsafe_run],merge(spec,(tone_peak_pu=0.011,)))["valid"]
    offset=merge(run,(input=run.input .+ 0.011,))
    @test !V.scan_quality(time,baseline,[offset],spec)["valid"]
end

@testset "Complete-network gate stable and unstable witnesses" begin
    A=-Matrix{Float64}(I,2,2); B=Matrix{Float64}(I,2,2); D=zeros(2,2)
    grid(s)=Matrix{ComplexF64}(I,2,2)/(1+s)
    rotation=zeros(2,2)
    stable=V.network_stability(A,B,0.5B,D,grid,1.0,1.0,rotation)
    cascade=[A zeros(2,2);B A]
    unstable=V.network_stability(cascade,[B;zeros(2,2)],[zeros(2,2) -2B],D,grid,1.0,1.0,rotation)
    @test stable["status"]=="passed" && stable["nyquist_net"]==0
    @test stable["most_positive_located_real_per_s"]≈-1
    @test unstable["status"]=="failed"
    @test unstable["most_positive_located_real_per_s"]>0
    @test unstable["nyquist_net"]!=0
end

@testset "TLC port current drive, native reference and synthetic dq recovery" begin
    net=V.fixture("L2-01").factory(); point=power_flow(net)
    gate=V.stability_gate(net,V.fixture("L2-01"))
    @test gate["status"]=="passed"
    @test gate["most_positive_located_real_per_s"]≈-1.991781088 rtol=1e-6
    list=P.netlist(net,point); original,reference=V.applicable_scan("L2-01",net,list)
    @test reference[:,:,1]≈PowerImpedance.get_y(net.elements[:DUT],2π*im)[2:3,2:3]
    @test original.drive=="current" && original.active
    @test original.time_step==2.5e-6 && original.tone_peak_pu==5e-5
    for band in (original,V.step_definition(original,18.0),V.step_definition(original,1000.0))
        @test inv(band.sample_step*(maximum(band.frequencies)+50))>=40
        @test all(isapprox(t/band.sample_step,round(t/band.sample_step);atol=1e-7)
            for t in (band.window_starts...,band.window_duration,band.simulation_time))
        @test all(isapprox(f*band.window_duration,round(f*band.window_duration);atol=1e-10)
            for f in band.frequencies)
    end
    @test V.step_definition(original,1.0).window_starts==(8.0,9.0)
    @test V.step_definition(original,1000.0).time_step==1.25e-6
    @test V.band_sample_step(original)≈20e-6
    form=P.identify_rlc(net.elements[:Grid];name=:Grid).form
    @test 220^2/100/hypot(form.R,2π*50*form.L)≈8
    @test 2π*50*form.L/form.R≈10
    frequencies=[1.0,7.0,137.0,1000.0]
    spec=merge(original,(;frequencies,phases=zeros(4),injection_time=0.0,
        window_starts=(1.0,2.0),simulation_time=3.0))
    time=collect(0.0:spec.sample_step:spec.simulation_time)
    known_pu=cat(([0.2+0.00001im*f -0.05+0.02im;0.08-0.03im 0.3-0.00002im*f]
        for f in frequencies)...;dims=3)
    known=known_pu .* reshape(spec.current_bases,:,1,1) ./ reshape(spec.voltage_bases,1,:,1)
    # Current drive produces mixed terminal voltages. Recover Y using the full
    # voltage matrix, never dividing each measured current by command current.
    mixing=[0.4 0.15; -0.1 0.35]
    models=Dict{String,P.PSCADModel}(); results=Dict{String,P.PSCADResult}()
    for (j,axis) in enumerate(["baseline";spec.axes;"half"])
        logical=axis=="half" ? spec.axes[1] : axis
        local_spec=axis=="half" ? merge(spec,(tone_peak_pu=spec.tone_peak_pu/2,)) : spec
        plan,settings=V.scan_plan(list,local_spec,logical)
        @test count(c->c isa P.ModuleInstancePlan && occursin(":CurrentPort_",c.defn),plan.main.components)==1
        @test count(c->c isa P.ComponentPlan && c.defn=="master:source_3",plan.main.components)==1
        @test P.check_connectivity(plan)===nothing
        voltage=repeat([spec.voltage_bases[1] 0.0],length(time),1)
        current=zeros(length(time),2); drive=zeros(length(time),2)
        if axis!="baseline"
            column=axis=="half" ? 1 : j-1
            for (k,f) in enumerate(frequencies)
                amplitude=local_spec.tone_peak_pu*spec.current_bases[column]
                v=mixing[:,column].*local_spec.tone_peak_pu*spec.voltage_bases[column]
                i=known[:,:,k]*v
                drive[:,column].+=amplitude*cos.(2π*f.*time)
                for row in 1:2
                    voltage[:,row].+=real.(v[row].*cis.(2π*f.*time))
                    current[:,row].+=real.(i[row].*cis.(2π*f.*time))
                end
            end
        end
        voltage_abc=phase_wave(time,voltage);current_abc=phase_wave(time,current);drive_abc=phase_wave(time,drive)
        channels=PowerImpedance.OrderedDict{String,Vector{Float64}}()
        vp=only(filter(c->c.kind==:voltage && c.bus==only(spec.buses).name,plan.probes.channels))
        ip=only(filter(c->c.kind==:current && c.element=="DUT" && c.side=="2",plan.probes.channels))
        dp=only(filter(c->c.kind==:injection_current,plan.probes.channels))
        @test ip.orientation==:out && dp.orientation==:out
        for phase in 1:3
            channels[vp.name*":"*string(phase)]=voltage_abc[:,phase]
            channels[ip.name*":"*string(phase)]=-current_abc[:,phase]
            channels[dp.name*":"*string(phase)]=drive_abc[:,phase]
        end
        for pole in ("P","N")
            probe=only(filter(c->c.kind==:voltage && c.bus==V.port_probe(list,:DUT,1).name && c.side==pole,plan.probes.channels))
            channels[probe.name]=fill(pole=="P" ? 320.0 : -320.0,length(time))
        end
        models[axis]=P.PSCADModel("synthetic.pscx",plan.name,list,plan.probes,settings,list.operating_point,(;))
        results[axis]=P.PSCADResult(PSCADRun(),time,channels,plan.probes,settings,(;),(;))
        recovered=V.scan_samples(results[axis],models[axis],local_spec)
        @test recovered.current≈current atol=1e-14
        @test maximum(abs,recovered.voltage-voltage)<1e-10
    end
    mktempdir() do directory
        outcome=V.compare_frequency_runs(results,models,known,directory;spec)
        @test outcome["status"]=="passed"
        @test outcome["max_frobenius_error"]<1e-9
        println("TLC synthetic max Frobenius recovery error: ",outcome["max_frobenius_error"])
        @test all(r.frobenius_limit==0.05 && r.phase_limit_deg==3 for r in
            V.response_rows(spec,known_pu,known_pu;active=true))
        base,bq=V.single_response(results[spec.axes[1]],results["baseline"],models[spec.axes[1]],spec,1)
        half,hq=V.single_response(results["half"],results["baseline"],models["half"],merge(spec,(tone_peak_pu=spec.tone_peak_pu/2,)),1)
        @test size(base)==(4,1,4) && bq["valid"] && hq["valid"]
        @test V.matrix_change(half,base;epsilon=0.02)["passed"]
    end
end

end

module PSCADResonanceTests
using Test, PowerImpedance, LinearAlgebra
include("../manual/pscad/validation/validation.jl")
const V=PSCADValidation
@testset "Resolved resonance owner rule" begin
    f=collect(90.:.1:110.)
    response(centre,width)=reshape(ComplexF64[1/(1+im*2*(x-centre)/width) for x in f],1,1,:)
    reference=response(100.,4.)
    matched=V.resonance_qualification(f,reference,reference)
    @test matched["resolved"] && matched["passed"]
    @test abs(matched["Julia"]["width_Hz"]-4)<.01
    shifted=response(100.5,4.)
    rule=V.resonance_qualification(f,shifted,reference)
    @test rule["resolved"] && rule["passed"]
    rows=V.comparison_rows(f,shifted,reference)
    judged=V.resonance_judged_rows(rows,rule)
    @test any(!r.within_tolerance for r in rows if 99<=r.frequency_Hz<=101)
    @test all(r.within_tolerance for r in judged if r.comparison_rule=="resonance_frequency_width")
    @test all(r.within_tolerance==old.within_tolerance for (r,old) in zip(judged,rows) if r.comparison_rule=="complex")
    @test !V.resonance_qualification(f,response(102.,4.),reference)["passed"]
    @test !V.resonance_qualification(f,response(100.,4.5),reference)["passed"]
    @test_throws ArgumentError V.half_power_resonance([90.,100.,110.],[.1,1.,.1])
    sparse=V.resonance_qualification(f[1:20:end],reference[:,:,1:20:end],reference[:,:,1:20:end])
    @test !sparse["resolved"]
    @test all(r.comparison_rule=="complex" for r in V.resonance_judged_rows(rows,sparse))
    @test !V.resonance_qualification(f,response(90.,4.),reference)["resolved"]
    @test all(!r.within_tolerance for r in V.resonance_judged_rows(rows,rule;valid=false))
    @test all(r.status=="model_mismatch" for r in V.resonance_judged_rows(
        V.comparison_rows(f,shifted,reference;model_mismatch="documented difference"),rule))
    @test all(r.status=="invalid_measurement" for r in V.resonance_judged_rows(
        V.comparison_rows(f,shifted,reference;valid=false),rule))
    @test all(!r.within_tolerance for r in V.resonance_judged_rows(
        V.comparison_rows(f,reference,reference),rule;valid=false))
    dip=V.resonance_qualification(f,inv.(reference),inv.(reference);quantity="Y")
    @test dip["resolved"] && dip["passed"]
    @test_throws ArgumentError V.half_power_resonance(reverse(f),ones(length(f)))
end
@testset "Quarter-Hz three-phase coherent extraction" begin
    f=collect(312.:.25:313.)
    t=collect(0.:1/4096:8.)
    y=ComplexF64[2+.1im .1+.2im .2-.1im;.3+.1im 3+.2im .1+.1im;.2+.3im .4-.1im 4+.1im]
    zero=zeros(length(t),3);inputs=Matrix{Float64}[];outputs=Matrix{Float64}[]
    for axis in 1:3
        u=zeros(length(t),3);v=zeros(length(t),3)
        for (k,freq) in enumerate(f)
            phase=-π*k*(k-1)/length(f)
            u[:,axis].+=cos.(2π*freq.*t.+phase)
            for row in 1:3
                v[:,row].+=real.(y[row,axis].*cis.(2π*freq.*t.+phase))
            end
        end
        push!(inputs,u);push!(outputs,v)
    end
    r=V.extract_response(t,inputs,outputs,zero,zero,f;starts=(0.,4.),duration=4.)
    @test all(maximum(abs,m[:,:,k]-y)<1e-9 for m in r.matrices for k in eachindex(f))
end
end

module PSCADResonanceConstructionTests
using Test,PowerImpedance
include("../manual/pscad/validation/validation.jl")
const V=PSCADValidation
@testset "Bus5 extra-bin construction and retained half-step model" begin
    net=V.fixture("L1-08").factory();list=V.P.netlist(net,power_flow(net))
    base,_=V.applicable_scan("L1-08",net,list)
    spec,reference=V.resonance_spec(net,list,base)
    @test length(spec.buses)==1 && only(spec.buses).name=="Bus5"
    @test spec.currents==[("injection_1","1")]
    @test size(reference)==(3,3,40)
    @test isempty(intersect(spec.frequencies,base.frequencies))
    @test all(isinteger(f*spec.window_duration) for f in spec.frequencies)
    @test 1/(spec.sample_step*maximum(spec.frequencies))>=40
    @test spec.window_starts==(2.,6.) && spec.simulation_time==10.
    plan,_=V.scan_plan(list,spec,"p1_a")
    probes=filter(c->c.kind==:injection_current,plan.probes.channels)
    @test length(probes)==1 && only(probes).bus=="Bus5" && only(probes).orientation==:out
    step=merge(spec,(;time_step=spec.time_step/2));prefix=V.scan_prefix(spec)*"half_step__"
    mktempdir() do directory
        write(joinpath(directory,"fixture.pscx"),"<project/>")
        record=Dict("projects"=>[Dict("axis"=>prefix*"p1_a","path"=>"fixture.pscx",
            "probes"=>V.probe_record.(plan.probes.channels))])
        model=V.existing_model(record,prefix*"p1_a",list,step,directory;prefix)
        @test model.settings.time_step==1e-6
    end
end
@testset "Frequency grid interval can dominate the one-percent limit" begin
    f=collect(.3:.025:1.7)
    r(c)=reshape(ComplexF64[1/(1+im*2*(x-c)/.4) for x in f],1,1,:)
    q=V.resonance_qualification(f,r(1.02),r(1.))
    @test q["resolved"] && q["passed"]
    @test q["frequency_limit_Hz"]≈.025
end
end

module PSCADBandSamplingTests
using Test,PowerImpedance,LinearAlgebra
include("../manual/pscad/validation/validation.jl")
const V=PSCADValidation
@testset "Band sampling preserves windows, sidebands and integration steps" begin
    spec=(;frequency=50.,frequencies=collect(312.:.25:322.),dimension=3,
        time_step=2e-6,window_starts=(2.,6.),window_duration=4.,simulation_time=10.)
    dt=V.band_sample_step(spec)
    @test dt≈64e-6
    @test V.band_sample_step(merge(spec,(;time_step=1e-6)))≈dt
    @test 1/(dt*maximum(spec.frequencies))>=40
    @test all(isapprox(b/dt,round(b/dt);atol=1e-8) for b in (2.,6.,4.,10.))
    @test round(Int,10/dt)+1==156251
    @test round(Int,4/dt)==62500
    dq=merge(spec,(;dimension=2,frequencies=[1000.]))
    @test 1/(V.band_sample_step(dq)*1050)>=40
    @test dq.time_step==2e-6
    @test_throws ErrorException V.band_sample_step(merge(spec,(;time_step=.1)))
end
@testset "64-us coherent abc response recovery" begin
    dt=64e-6;t=collect(0.:dt:8.);f=[312.,316.25,322.]
    y=ComplexF64[2+.1im .1+.2im .2-.1im;.3+.1im 3+.2im .1+.1im;.2+.3im .4-.1im 4+.1im]
    baseline=zeros(length(t),3);inputs=Matrix{Float64}[];outputs=Matrix{Float64}[]
    for axis in 1:3
        u=zeros(length(t),3);v=zeros(length(t),3)
        for (k,freq) in enumerate(f)
            phase=-π*k*(k-1)/length(f)
            u[:,axis].+=cos.(2π*freq.*t.+phase)
            for row in 1:3
                v[:,row].+=real.(y[row,axis].*cis.(2π*freq.*t.+phase))
            end
        end
        push!(inputs,u);push!(outputs,v)
    end
    extracted=V.extract_response(t,inputs,outputs,baseline,baseline,f;starts=(0.,4.),duration=4.)
    @test all(maximum(abs,m[:,:,k]-y)<1e-9 for m in extracted.matrices for k in eachindex(f))
end
@testset "Resonance recorder selection leaves the circuit intact" begin
    net=V.fixture("L1-08").factory();list=V.P.netlist(net,power_flow(net))
    base,_=V.applicable_scan("L1-08",net,list);spec,_=V.resonance_spec(net,list,base)
    selected,_=V.scan_plan(list,spec,"p1_a")
    full,_=V.scan_plan(list,merge(spec,(;protocol="abc_resonance_all_probes")),"p1_a")
    discarded=filter(c->c isa V.P.ComponentPlan && c.defn=="master:pgb" &&
        !(Dict(c.params)["Name"] in Set(p.name for p in selected.probes.channels)),full.main.components)
    labelpoints=Set((c.x-36,c.y) for c in discarded)
    recording_wires=Set(((c.x-36,c.y),(c.x,c.y)) for c in discarded)
    keep(c)=!(c isa V.P.ComponentPlan && (c.defn=="master:pgb" ||
        c.defn=="master:datalabel" && (c.x,c.y) in labelpoints))
    # Only recorder assemblies change, no electrical component/connection does.
    @test repr(filter(keep,selected.main.components))==repr(filter(keep,full.main.components))
    @test repr(selected.main.wires)==repr(filter(w->Tuple(w.vertices) ∉ recording_wires,full.main.wires))
    @test repr(selected.lines)==repr(full.lines)
    @test repr(selected.modules)==repr(full.modules)
    @test length(selected.probes.channels)==2
    @test sum(c.dim for c in selected.probes.channels)==6
    @test all(c.bus=="Bus5" for c in selected.probes.channels)
    @test count(c->c isa V.P.ComponentPlan && c.defn=="master:pgb",selected.main.components)==2
end
end
