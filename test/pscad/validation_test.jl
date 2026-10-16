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


@testset "Frozen native reference identity budget and recorded provenance" begin
    spec=(;quantity="Y",voltage_bases=[1.,2.],current_bases=[2.,1.],frequencies=[1.,1000.])
    reference=cat([0.4+0.1im 0.0;0.1 0.2],[0.2 0.1im;0. 0.3];dims=3)
    frozen=copy(reference)
    check=V.native_reference_check(spec,reference,reference)
    @test check["passed"] && check["max_absolute_SI"]==0
    @test check["limit"]==1e-6
    @test length(check["per_frequency"])==2
    @test V.native_reference_check(spec,reference*(1+0.5e-6),frozen)["passed"]
    @test !V.native_reference_check(spec,reference*(1+2e-6),frozen)["passed"]
    # A structurally zero entry uses the fixed pu floor, not a raw relative error.
    small=copy(reference);small[1,2,1]=0.5e-6*0.02
    @test V.native_reference_check(spec,small,frozen)["passed"]
    large=copy(reference);large[1,2,1]=2e-6*0.02
    @test !V.native_reference_check(spec,large,frozen)["passed"]
    @test reference==frozen
    @test_throws ArgumentError V.native_reference_check(spec,reference[:,:,1:1],frozen)
    invalid=copy(reference);invalid[1]=NaN
    @test_throws ArgumentError V.native_reference_check(spec,invalid,frozen)
    net=V.ac_rl_network();list=P.netlist(net,power_flow(net))
    actual_spec,actual_reference=V.applicable_scan("L1-01",net,list)
    mktempdir() do dir
        path=joinpath(dir,V.reference_filename(actual_spec))
        V.write_response(path,actual_reference,actual_spec.frequencies)
        V.write_table(joinpath(dir,"operating_point.tsv"),V.operating_point_rows(list))
        record=V.manifest_lists!(TOML.parse("native_reference_checks = []"))
        hash_before=V.digest(path)
        accepted=V.record_native_reference!(record,dir,actual_spec,actual_reference,actual_reference,list)
        @test accepted["passed"] && accepted["operating_point"]["passed"]
        @test accepted["frozen_sha256"]==hash_before
        @test V.digest(path)==hash_before
        parsed=V.manifest_lists!(TOML.parsefile(joinpath(dir,"manifest.toml")))
        @test parsed["native_reference_checks"] isa Vector{Any}
        @test length(parsed["native_reference_checks"])==1
        @test_throws ErrorException V.record_native_reference!(parsed,dir,actual_spec,actual_reference*1.01,actual_reference,list)
        failed=TOML.parsefile(joinpath(dir,"manifest.toml"))
        @test length(failed["native_reference_checks"])==2
        @test !last(failed["native_reference_checks"])["passed"]
        @test V.digest(path)==hash_before
        # Freeze first; do not bless a changed point merely because Y matched.
        rows=V.operating_point_rows(list)
        first_voltage=findfirst(r->r.quantity=="voltage_pu",rows)
        rows[first_voltage]=merge(rows[first_voltage],(value=rows[first_voltage].value+0.01,))
        V.write_table(joinpath(dir,"operating_point.tsv"),rows)
        @test !V.native_operating_point_check(list,joinpath(dir,"operating_point.tsv"))["passed"]
    end
end

@testset "Passive catalogue and generated source plans" begin
    @test length(V.REGISTRY) == 30
    @test length(unique(entry.id for entry in V.REGISTRY)) == 30
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
    integrator=V.network_stability(zeros(2,2),B,B,D,grid,1.0,1.0,rotation)
    @test integrator["status"]=="passed"
    @test integrator["nyquist_closed_RHP_count"]==0
    unstable_grid(s)=Matrix{ComplexF64}(I,2,2)/(2+s)
    stabilized=V.network_stability(B,B,3B,D,unstable_grid,2.0,1.0,rotation)
    @test stabilized["status"]=="passed"
    @test stabilized["nyquist_open_RHP_poles"]==2
    @test stabilized["nyquist_net"]==-2
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

@testset "Batch C device ports and finite complete-network roots" begin
    for (id,kind,scr) in (("L2-13",:gfm,8.),("L2-14",:compensated,8.),
        ("L2-15",:disabled,8.),("L2-16",:machine,8.),("L2-17",:gfm,2.5))
        parent=V.batch_c_device(kind);net=V.fixture(id).factory();dut=net.elements[:DUT]
        @test repr(parent.element_model)==repr(dut.element_model)
        @test parent.setpoint==dut.setpoint
        point=power_flow(net);list=V.fixture_netlist(net,point)
        bases=V.device_bases(dut.element_model.elec)
        form=P.identify_rlc(net.elements[:Grid];name=:Grid).form
        @test (bases.ac_voltage*sqrt(3/2))^2/bases.power/hypot(form.R,2π*50*form.L)≈scr
        @test 2π*50*form.L/form.R≈10
        B=dut.B./bases.voltage_inputs';C=dut.C.*bases.current_outputs
        D=dut.D.*bases.current_outputs./bases.voltage_inputs'
        ix=bases.ac_indices;B=B[:,ix];C=C[ix,:];D=D[ix,ix]
        @test iszero(D)
        rotation=real.((inv(PowerImpedance.get_y(net.elements[:Grid],0.0im)[1:2,1:2])-form.R*I)/form.L)
        # Independent ODE: differentiate grid KCL ig=-C*x and eliminate only
        # terminal voltage. This has no algebraic-infinity classification.
        closed=dut.A-B*((I+form.L*C*B)\(form.L*C*dut.A+form.R*C+form.L*rotation*C))
        poles=eigvals(closed)
        gate=V.stability_gate(net,V.fixture(id))
        @test length(gate["poles_real_per_s"])==size(dut.A,1)
        @test gate["most_positive_located_real_per_s"]≈maximum(real,poles) rtol=1e-3 atol=1e-8
        if id=="L2-17"
            @test maximum(real,poles)>0
            @test gate["status"]=="failed" && gate["nyquist_closed_RHP_count"]==2
            @test count(>(0),gate["poles_real_per_s"])==2
            continue
        end
        @test maximum(real,poles)<-1e-7
        @test gate["status"]=="passed" && gate["nyquist_closed_RHP_count"]==0
        spec,reference=V.applicable_scan(id,net,list)
        @test spec.currents==[("DUT",string(bases.ac_side))]
        @test spec.dc_clamped==(kind!=:machine)
        @test spec.time_step==(kind==:compensated ? 1e-6 : 2.5e-6)
        for f in (1.,75.,1000.)
            z=ComplexF64(2π*im*f);full=V.physical_y(dut,z)
            @test C*((z*I-dut.A)\B)+D≈full[ix,ix] rtol=1e-10 atol=1e-12
            @test reference[:,:,only(findall(==(f),spec.frequencies))]≈full[ix,ix]
        end
        if kind==:disabled
            @test dut.element_model.sigma_control.tec isa PowerImpedance.NoTotalEnergyControl
            @test dut.element_model.sigma_control.zscc isa PowerImpedance.NoZeroSequenceCurrentControl
            @test dut.element_model.sigma_control.ccsc isa PowerImpedance.CirculatingCurrentSuppressionControl
        elseif kind==:compensated
            @test dut.element_model.sigma_control isa PowerImpedance.ΣdqzControlLEC
            @test dut.element_model.modulation isa PowerImpedance.CompensatedModulation
        elseif kind==:machine
            @test spec.window_starts==(62.,64.) && spec.simulation_time==66.
            @test spec.window_duration==2.
            @test !haskey(V.scan_record(spec),"dc_voltage_base_kV")
            @test V.step_definition(spec,1000.).window_duration==2.
            @test V.step_definition(spec,1000.).time_step==1.25e-6
            @test first(spec.window_starts)>=1-12/gate["most_positive_located_real_per_s"]
            @test !haskey(net.elements,:G_DC)
            @test V.physical_y(dut,2π*im)≈PowerImpedance.get_y(dut,2π*im)*(1000/380^2)
        end
        plan,settings=V.scan_plan(list,spec,"baseline")
        @test P.check_connectivity(plan)===nothing
        probe=only(filter(c->c.kind==:current && c.element=="DUT" && c.side==string(bases.ac_side),plan.probes.channels))
        @test probe.orientation==:out
    end
end

@testset "Machine current-drive dq recovery without a DC port" begin
    net=V.fixture("L2-16").factory();list=V.fixture_netlist(net,power_flow(net))
    original,_=V.applicable_scan("L2-16",net,list)
    spec=merge(original,(frequencies=[1.,75.,1000.],phases=zeros(3),
        window_starts=(0.,2.),simulation_time=4.,injection_time=0.))
    time=collect(0.:spec.sample_step:4.)
    known=cat((V.physical_y(net.elements[:DUT],ComplexF64(2π*im*f)) for f in spec.frequencies)...;dims=3)
    models=Dict{String,P.PSCADModel}();results=Dict{String,P.PSCADResult}()
    for (j,axis) in enumerate(["baseline";spec.axes])
        plan,settings=V.scan_plan(list,spec,axis)
        voltage=repeat([spec.voltage_bases[1] 0.],length(time),1)
        current=zeros(length(time),2);drive=zeros(length(time),2)
        if axis!="baseline"
            column=j-1;mixing=[.4 .15;-.1 .35]
            for (k,f) in enumerate(spec.frequencies)
                v=mixing[:,column]*spec.tone_peak_pu*spec.voltage_bases[column]
                i=known[:,:,k]*v
                drive[:,column].+=spec.tone_peak_pu*spec.current_bases[column]*cos.(2π*f*time)
                for row in 1:2
                    voltage[:,row].+=real.(v[row]*cis.(2π*f*time))
                    current[:,row].+=real.(i[row]*cis.(2π*f*time))
                end
            end
        end
        channels=PowerImpedance.OrderedDict{String,Vector{Float64}}()
        vp=only(filter(c->c.kind==:voltage && c.bus==only(spec.buses).name,plan.probes.channels))
        ip=only(filter(c->c.kind==:current && c.element=="DUT" && c.side=="1",plan.probes.channels))
        dp=only(filter(c->c.kind==:injection_current,plan.probes.channels))
        for (probe,wave) in ((vp,phase_wave(time,voltage)),(ip,phase_wave(time,-current)),(dp,phase_wave(time,drive)))
            for phase in 1:3
                channels[probe.name*":"*string(phase)]=wave[:,phase]
            end
        end
        models[axis]=P.PSCADModel("synthetic.pscx",plan.name,list,plan.probes,settings,list.operating_point,(;))
        results[axis]=P.PSCADResult(PSCADRun(),time,channels,plan.probes,settings,(;),(;))
        samples=V.scan_samples(results[axis],models[axis],spec)
        @test !haskey(samples,:dc_voltage)
    end
    mktempdir() do directory
        result=V.compare_frequency_runs(results,models,known,directory;spec)
        @test result["status"]=="passed" && result["max_frobenius_error"]<1e-9
        response,quality=V.single_response(results[spec.axes[1]],results["baseline"],models[spec.axes[1]],spec,1)
        @test size(response)==(4,1,3) && quality["valid"]
    end
end

@testset "MMC batch B: owned controls, terminal bases and DC feedback" begin
    for (id,mode,scr) in (("L2-07",:pq,8.),("L2-08",:pf,8.),("L2-09",:qv,8.),
        ("L2-10",:vac,8.),("L2-11",:vdc,8.),("L2-12",:pq,2.5))
        net=V.fixture(id).factory()
        parent=V.PSCADFixtures.mmc_network(mode).state.elements.DUT
        dut=net.elements[:DUT];m=dut.element_model
        @test repr(m)==repr(parent.element_model)
        @test dut.limits==parent.limits
        @test m.modulation isa PowerImpedance.UncompensatedModulation
        @test m.sigma_control.tec isa PowerImpedance.TotalEnergyControl
        @test m.sigma_control.zscc isa PowerImpedance.ZeroSequenceCurrentControl
        @test m.sigma_control.ccsc isa PowerImpedance.CirculatingCurrentSuppressionControl
        if mode==:vac
            @test m.delta_control.outer_reactive.filter isa PowerImpedance.NoFilter
        end
        form=P.identify_rlc(net.elements[:Grid];name=:Grid).form
        @test 380^2/1000/hypot(form.R,2π*50*form.L)≈scr
        @test 2π*50*form.L/form.R≈10
        @test dut.setpoint.Pac==(mode==:vdc ? -600. : 600.)
        @test dut.setpoint.Qac==200. && dut.setpoint.Vdc==800.
        point=power_flow(net);list=V.fixture_netlist(net,point)
        spec,reference=V.applicable_scan(id,net,list)
        bases=V.device_bases(m.elec)
        @test spec.voltage_bases≈fill(380sqrt(2/3),2)
        @test spec.current_bases≈fill(1000sqrt(2)/(sqrt(3)*380),2)
        @test spec.dc_voltage_base_kV==800. && spec.power_base_MVA==1000.
        @test spec.time_step==(mode==:vdc ? 1.25e-6 : 2.5e-6)
        @test V.step_definition(spec,75.).time_step==spec.time_step/2
        @test spec.dc_clamped==(mode!=:vdc)
        @test V.scan_record(spec)["power_base_MVA"]==1000.
        # Verify state-space SI scaling against native full three-port Y,
        # including both transformer cross terms and the DC-current factor.
        B=dut.B./bases.voltage_inputs';C=dut.C.*bases.current_outputs
        D=dut.D.*bases.current_outputs./bases.voltage_inputs'
        for f in (1.,75.,1000.)
            z=ComplexF64(2π*im*f)
            y=PowerImpedance.get_y(dut,z)
            @test C*((z*I-dut.A)\B)+D≈y rtol=1e-11 atol=1e-12
            k=only(findall(==(f),spec.frequencies))
            if mode==:vdc
                # Independent full-node KCL with the physical resistor.
                g=600/800^2
                voltage=vcat(-(y[1,1]+g)\y[1:1,2:3],Matrix{ComplexF64}(I,2,2))
                @test reference[:,:,k]≈(y*voltage)[2:3,:] rtol=1e-11
                @test norm(reference[:,:,k]-y[2:3,2:3])>0
            else
                @test reference[:,:,k]≈y[2:3,2:3]
            end
        end
        if mode==:vdc
            @test all(e.name!=:G_DC for e in list.elements)
            load=only(filter(e->e.name==:DC_load,list.elements))
            @test load.terminals[2].grounded
            @test P.identify_rlc(net.elements[:DC_load];name=:DC_load).form.R≈800^2/600
        end
        for axis in ["baseline";spec.axes]
            plan,_=V.scan_plan(list,spec,axis)
            @test P.check_connectivity(plan)===nothing
            @test count(c->c isa P.ModuleInstancePlan && occursin(":CurrentPort_",c.defn),plan.main.components)==1
            probe=only(filter(c->c.kind==:current && c.element=="DUT" && c.side=="2",plan.probes.channels))
            @test probe.orientation==:out
            if mode==:vdc
                @test count(c -> c isa P.ComponentPlan && c.defn == "master:source_1", plan.main.components) == 2
                @test all(c -> startswith(Dict(c.params)["Name"], "precharge_"),
                    filter(c -> c isa P.ComponentPlan && c.defn == "master:source_1", plan.main.components))
                @test count(c -> c isa P.ComponentPlan && c.defn == "master:breaker1", plan.main.components) == 2
                @test count(c->c isa P.ComponentPlan && c.defn=="master:resistor" &&
                    parse(Float64,first(split(Dict(c.params)["R"])))≈800^2/1200,plan.main.components)==2
            end
        end
    end
    # The unchanged 1e-6 pu DC clamp gate must use the MMC's 800 kV base.
    net=V.fixture("L2-07").factory();list=V.fixture_netlist(net,power_flow(net))
    original,_=V.applicable_scan("L2-07",net,list)
    spec=merge(original,(frequencies=[7.],window_starts=(0.,1.),window_duration=1.,))
    time=collect(0.:.001:2.);wave=cos.(2π*7*time)
    baseline=(input=zeros(length(time),2),output=zeros(length(time),2),
        input_base=spec.voltage_bases,output_base=spec.current_bases,
        drive=zeros(length(time),2),drive_base=spec.current_bases,dc_voltage=fill(800.,length(time)))
    run=merge(baseline,(drive=hcat(spec.tone_peak_pu*spec.current_bases[1]*wave,zeros(length(time))),
        dc_voltage=800 .+ .00072wave))
    @test V.scan_quality(time,baseline,[run],spec;columns=[1])["valid"]
    @test !V.scan_quality(time,baseline,[merge(run,(dc_voltage=800 .+ .00088wave,))],spec;columns=[1])["valid"]
end

@testset "Adaptive witness windows contain whole tone and frame periods" begin
    spec = merge(V.l1_settings(), (protocol = "dq_active", time_step = 2.5e-6,
        sample_step = 20e-6, window_starts = (8.0, 9.0)))
    old_time = collect(0.0:spec.sample_step:8.2)
    old_signal = reshape(cos.(2π * 75 .* old_time), :, 1)
    @test_throws ArgumentError V.dft_phasors(old_time, old_signal, [75.0, 1000.0];
        start = 8.0, duration = 0.1)
    witness = V.step_definition(spec, 75.0)
    @test witness.frequencies == [75.0, 1000.0]
    @test witness.window_duration == 0.12
    @test witness.window_starts == (8.0, 8.12)
    @test witness.simulation_time == 8.24
    @test_throws ArgumentError V.dft_phasors(old_time, old_signal, witness.frequencies;
        start = last(witness.window_starts), duration = witness.window_duration)
    time = collect(0.0:witness.sample_step:witness.simulation_time)
    signal = reshape(V.multitone(time, witness.frequencies, witness.phases;
        amplitude = 1.0, onset = 2.0), :, 1)
    for start in witness.window_starts
        phasors = V.dft_phasors(time, signal, witness.frequencies;
            start, duration = witness.window_duration)
        @test vec(phasors) ≈ cis.(witness.phases) atol = 1e-10
    end
    for frequency in filter(!=(50.0), spec.frequencies)
        band = V.step_definition(spec, frequency)
        @test band.window_duration >= 0.1
        @test all(isapprox.(band.frequencies .* band.window_duration,
            round.(band.frequencies .* band.window_duration); atol = 1e-10))
        @test isinteger(round(50 * band.window_duration; digits = 10))
        @test all(isapprox.(collect(band.window_starts) ./ band.sample_step,
            round.(collect(band.window_starts) ./ band.sample_step); atol = 1e-8))
        @test isapprox(band.simulation_time / band.sample_step,
            round(band.simulation_time / band.sample_step); atol = 1e-8)
    end
end

@testset "TLC batch controls, grid and physical DC termination" begin
    for (id,scr) in (("L2-02",8.0),("L2-03",8.0),("L2-04",8.0),("L2-05",8.0),("L2-06",2.5))
        net=V.fixture(id).factory()
        form=P.identify_rlc(net.elements[:Grid];name=:Grid).form
        @test 220^2/100/hypot(form.R,2π*50*form.L)≈scr
        @test 2π*50*form.L/form.R≈10
        m=net.elements[:DUT].element_model
        @test m.innerVoltage isa PowerImpedance.NoInnerVoltageControl
        @test m.sync isa PowerImpedance.PLLSynchronization
        if id in ("L2-02","L2-06")
            @test m.outerActive.support isa PowerImpedance.FrequencySupportLag
            @test m.outerActive.support.Kω==5 && m.outerActive.support.ωc==2
        elseif id=="L2-03"
            @test m.outerActive.support isa PowerImpedance.NoFrequencySupport
            @test m.outerReactive.support.K==20 && m.outerReactive.support.ωc==100
        elseif id=="L2-04"
            @test m.outerReactive.filter isa PowerImpedance.NoFilter
            @test m.outerReactive.pi_ctrl.Kp==0 && m.outerReactive.pi_ctrl.Ki==100
        else
            @test m.outerActive isa PowerImpedance.OuterActiveVdcControl
            @test m.outerActive.pi_ctrl.Kp==5 && m.outerActive.pi_ctrl.Ki==5
            @test !haskey(net.elements,:CableDC12)
            @test P.identify_rlc(net.elements[:DC_load];name=:DC_load).form.R≈640^2/70
        end
    end
    # The DC load is physical, not an ideal voltage clamp. Its PF-only remote
    # zero reference contracts to the emitter's existing grounded DC terminal.
    net=V.fixture("L2-05").factory();point=power_flow(net)
    @test string(point[1]["termination_status"])=="LOCALLY_SOLVED"
    @test net.elements[:DUT].setpoint.Vdc≈640
    @test net.elements[:DUT].setpoint.Pdc≈-70
    list=V.fixture_netlist(net,point)
    @test all(e.name!=:G_DC for e in list.elements)
    load=only(filter(e->e.name==:DC_load,list.elements))
    @test load.terminals[2].grounded && load.terminals[2].bus===nothing
    spec,reference=V.applicable_scan("L2-05",net,list)
    @test !spec.dc_clamped && spec.active && spec.drive=="current"
    @test spec.time_step==0.625e-6 && spec.window_starts==(8.,9.)
    @test V.step_definition(spec,18.0).time_step==0.3125e-6
    for (k,f) in enumerate(spec.frequencies)
        y=PowerImpedance.get_y(net.elements[:DUT],ComplexF64(2π*im*f))
        g=70/640^2
        # Direct 3-node KCL solve, independent of the Schur reference formula.
        voltage=vcat(-(y[1,1]+g)\y[1:1,2:3],Matrix{ComplexF64}(I,2,2))
        @test reference[:,:,k]≈(y*voltage)[2:3,:] rtol=1e-12
        @test norm(reference[:,:,k]-y[2:3,2:3])>0
    end
    # Independent unreduced complete descriptor retains the DC algebraic node.
    e=net.elements[:DUT];el=e.element_model.elec;n=size(e.A,1)
    form=P.identify_rlc(net.elements[:Grid];name=:Grid).form
    rotation=real.((inv(PowerImpedance.get_y(net.elements[:Grid],0.0im)[1:2,1:2])-form.R*I)/form.L)
    ac=Matrix{Float64}(I,2,2)
    # Use native per-unit variables for the independent descriptor so tiny SI
    # conductances do not spoil the generalized eigenvalue backward error.
    zbase=el.vACbase/el.iACbase
    dc_conductance_pu=(70/640^2)*el.vDCbase/el.iDCbase
    full=[e.A zeros(n,2) e.B;
        zeros(2,n) -form.R/zbase*ac-form.L/zbase*rotation zeros(2,1) ac;
        e.C vcat(zeros(1,2),ac) e.D+diagm([dc_conductance_pu,0.,0.])]
    storage=diagm([ones(n);fill(form.L/zbase,2);zeros(3)])
    pencil=schur(full,storage)
    # Algebraic constraints have beta=0 in QZ. Round-off can report a finite
    # 1e19 quotient for an infinite pole; classify beta at backward-error scale,
    # rather than treating that quotient as a located dynamic mode.
    finite=abs.(pencil.β) .> 100eps(Float64)*max(norm(storage),1.0)
    poles=pencil.α[finite]./pencil.β[finite]
    gate=V.stability_gate(net,V.fixture("L2-05"))
    @test length(poles)==length(gate["poles_real_per_s"])
    # A singular descriptor's forward eigenvalue error depends on conditioning.
    # Check the same rightmost finite mode and its pencil backward error;
    # do not demand spurious extra digits from the QZ quotient.
    located=gate["most_positive_located_real_per_s"]
    residual=minimum(svdvals(full-located*storage))/max(norm(full),1.0)
    @test maximum(real,poles)<0 && argmin(abs.(poles.-located))==argmax(real.(poles)) && residual<1e-12
    println("DC complete-pencil normalized root residual: ",residual)
    for axis in ["baseline";spec.axes]
        plan,_=V.scan_plan(list,spec,axis)
        @test P.check_connectivity(plan)===nothing
        @test count(c -> c isa P.ComponentPlan && c.defn == "master:source_1", plan.main.components) == 2
                @test all(c -> startswith(Dict(c.params)["Name"], "precharge_"),
                    filter(c -> c isa P.ComponentPlan && c.defn == "master:source_1", plan.main.components))
                @test count(c -> c isa P.ComponentPlan && c.defn == "master:breaker1", plan.main.components) == 2
        @test count(c->c isa P.ComponentPlan && c.defn=="master:resistor" &&
            parse(Float64,first(split(Dict(c.params)["R"])))≈640^2/140,plan.main.components)==2
        probe=only(filter(c->c.kind==:current && c.element=="DC_load",plan.probes.channels))
        @test probe.orientation==:into
    end
    # Keep the 1e-6 clamp gate for source-clamped cases. A terminated converter
    # must be free to respond on DC; AC departures and drive gates are unchanged.
    short=merge(spec,(;frequencies=[7.],window_starts=(0.,1.),window_duration=1.,
        simulation_time=2.,injection_time=0.,tone_peak_pu=5e-5))
    time=collect(0.:.001:2.)
    wave=cos.(2π*7*time)
    input=zeros(length(time),2); input[:,1].=el.vACbase
    baseline=(;input,output=zeros(length(time),2),input_base=spec.voltage_bases,
        output_base=spec.current_bases,drive=zeros(length(time),2),drive_base=spec.current_bases,dc_voltage=fill(640.,length(time)))
    drive=hcat(5e-5*el.iACbase*wave,zeros(length(time)))
    run=merge(baseline,(;input=input+hcat(1e-4*el.vACbase*wave,zeros(length(time))),drive,
        dc_voltage=640 .+ 0.001wave))
    @test V.scan_quality(time,baseline,[run],short;columns=[1])["valid"]
    @test !V.scan_quality(time,baseline,[run],merge(short,(dc_clamped=true,));columns=[1])["valid"]
    frequencies=[1.,7.,137.]
    known=cat((V.device_port_y(net,ComplexF64(2π*im*f)) for f in frequencies)...;dims=3)
    inputs=[zeros(length(time),2) for _ in 1:2]
    outputs=[zeros(length(time),2) for _ in 1:2]
    mixing=[0.4 0.15;-0.1 0.35]
    for column in 1:2, (k,f) in enumerate(frequencies)
        v=mixing[:,column]*1e-4*el.vACbase
        current=known[:,:,k]*v
        for row in 1:2
            inputs[column][:,row].+=real.(v[row]*cis.(2π*f*time))
            outputs[column][:,row].+=real.(current[row]*cis.(2π*f*time))
        end
    end
    extracted=V.extract_response(time,inputs,outputs,zeros(length(time),2),
        zeros(length(time),2),frequencies;starts=(0.,1.),duration=1.,input_bases=spec.voltage_bases)
    recovery=maximum(maximum(abs,matrix-known) for matrix in extracted.matrices)
    @test recovery<1e-9
    println("DC-terminated TLC synthetic recovery error: ",recovery," S")
end

@testset "Isolated timing witness transport and topology" begin
    plan, settings = V.timing_plan()
    @test length(plan.probes.channels) == 5
    @test count(c -> c.defn == "master:source_1", plan.main.components) == 5
    @test count(c -> c.defn == "master:tdelay", plan.main.components) == 2
    @test settings.sample_step == settings.time_step
    @test P.check_connectivity(plan) === nothing
    time = collect(0.0:settings.time_step:settings.simulation_time)
    input = 0.1sin.(2pi*1000 .* time) .+ (time .>= 0.002)
    channels = Dict("V_input" => input)
    expected_steps = Dict("zero" => 1, "one" => 1, "four" => 4, "fractional" => 3)
    for (name, _) in V.TIMING_DELAYS
        steps = expected_steps[name]
        channels["V_"*name] = [i > steps ? input[i-steps] : 0.0 for i in eachindex(time)]
    end
    rows = V.timing_comparison(time, channels, settings.time_step)
    @test all(row.expected_total_delay_s ≈ expected_steps[row.name]*settings.time_step for row in rows)
    @test all(row.passed for row in V.timing_comparison(time, channels, settings.time_step))
    # Another whole step in the library/source path must stop the L2 queue.
    channels["V_four"] = [0.0; channels["V_four"][1:end-1]]
    @test !only(filter(row -> row.name == "four", V.timing_comparison(time, channels, settings.time_step))).passed
end

@testset "One-step realization reference keeps the native comparison separate" begin
    for id in ("L2-07", "L2-11", "L2-14", "L2-01", "L2-05")
        net = V.fixture(id).factory(); list = V.fixture_netlist(net, power_flow(net))
        spec, native = V.applicable_scan(id, net, list)
        if id == "L2-14"
            el = net.elements[:DUT]; m = el.element_model
            @test !V.interface_step_eligible(m) # existing fixture has positive delay
            el.element_model = MMC(m.meas, m.sync, m.delta_control, m.sigma_control,
                CompensatedModulation(), m.elec)
            PowerImpedance.update!(el, el.setpoint)
        end
        if id == "L2-05"
            el = net.elements[:DUT]; m = el.element_model
            net.elements[:DUT] = PowerImpedance.Element(element_model =
                TLC(m.elec, m.meas, m.sync, m.outerActive, m.outerReactive,
                    m.innerVoltage, m.innerCurrent, NoModulation()),
                input_pins = 1, output_pins = 2, setpoint = el.setpoint,
                limits = el.limits, pins = deepcopy(el.pins), symbol = :DUT)
            el = net.elements[:DUT]
            PowerImpedance.update!(el, el.setpoint)
        end
        short = merge(spec, (; frequencies = [18.0, 1000.0]))
        original = deepcopy(net.elements[:DUT].A)
        realization = V.interface_step_reference(net, short)
        @test net.elements[:DUT].A == original
        if id == "L2-01"
            @test realization === nothing # positive 200 us model delay
            continue
        end
        @test size(realization) == (2, 2, 2)
        @test all(isfinite, realization)
        delayed = deepcopy(net)
        el = delayed.elements[:DUT]
        delayed.elements[:DUT] = PowerImpedance.Element(element_model =
            V.one_step_model(el.element_model, short.time_step),
            input_pins = 1, output_pins = 2, setpoint = el.setpoint, limits = el.limits)
        el = delayed.elements[:DUT]
        PowerImpedance.update!(el, el.setpoint)
        rational = cat((V.device_port_y(delayed, ComplexF64(im*2π*f)) for f in short.frequencies)...; dims = 3)
        # At these small steps the independent 3/3 rational evaluation is
        # indistinguishable from exact transport, including DC Schur reduction.
        @test norm(realization-rational)/norm(realization) < 1e-9
        quality = Dict("valid" => true, "model_mismatch" => "", "status" => "failed")
        rows, result = V.interface_step_comparison(short, realization, realization, quality)
        @test result["status"] == "passed"
        @test result["original_model_status"] == "failed" && quality["status"] == "failed"
        @test all(row.within_tolerance for row in rows)
        quality["valid"] = false
        _, invalid = V.interface_step_comparison(short, realization, realization, quality)
        @test invalid["status"] == "invalid_measurement"
        @test_throws ErrorException V.interface_step_reference(net, merge(short, (; time_step = 0.0)))
    end
    @test !V.zero_modulation_delay(UncompensatedModulation(timeDelay = 1e-6, padeOrderNum = 3, padeOrderDen = 3))
end

@testset "MMC GFL modal settling and frozen fine-step variant" begin
    for decay in (10.952732, 1.99183483, 10.9087697, 10.8907848)
        settling = V.gfl_settling(Dict("most_positive_located_real_per_s" => -decay))
        @test settling["window_starts_s"] == [16.0, 17.0]
        @test settling["simulation_time_s"] == 18.0
        @test settling["predicted_normalized_tail"] < 0.001
    end
    @test_throws ErrorException V.gfl_settling(Dict("most_positive_located_real_per_s" => 1.0))
    net = V.fixture("L2-01").factory(); list = V.fixture_netlist(net, power_flow(net))
    spec, native = V.applicable_scan("L2-01", net, list)
    frozen = V.scan_record(spec); frozen["time_step"] = 1.25e-6
    fine, reference = V.applicable_scan("L2-01", net, list; definition = frozen)
    @test spec.time_step == 2.5e-6 && fine.time_step == 1.25e-6
    @test V.step_definition(fine, 18.0).time_step == 0.625e-6
    @test fine.window_starts == spec.window_starts && reference == native
    @test V.M9C2_TLC_DIRECTORY != joinpath(V.ROOT, "data", "L2-01")
    @test V.M9C2_IDS == ["L2-" * lpad(i, 2, '0') for i in 7:15]
    command = V.converter_acceptance_command()
    @test command.exec[end] == "--converters"
    @test command.exec[end - 1] == joinpath(V.REPOSITORY, "test/manual/pscad/acceptance.jl")
    @test "--project=$(dirname(Base.active_project()))" in command.exec
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

module PSCADQueueSettlingTests
using Test, PowerImpedance, TOML
include("../manual/pscad/validation/validation.jl")
const V = PSCADValidation

V.run_fixture(::Val{:queue_failure}; kwargs...) = error("offline fixture failure")
V.run_fixture(::Val{:queue_success}; kwargs...) = Dict("status" => "completed")
@testset "Queue records a thrown fixture and continues" begin
    mktempdir() do directory
        write(joinpath(directory, "payload.txt"), "kept")
        write(joinpath(directory, "manifest.toml"), "fixture_id = \"offline\"\n")
        outcomes = Any[]
        @test_logs (:warn, r"Fixture failed; continuing queue") begin
            for id in (Val(:queue_failure), Val(:queue_success))
                push!(outcomes, V.run_fixture_continuing(id; directory, remote = nothing, deadline = Inf))
            end
        end
        @test outcomes[1]["status"] == "run_or_analysis_failed"
        @test occursin("offline fixture failure", outcomes[1]["failure"])
        @test outcomes[2]["status"] == "completed"
        @test TOML.parsefile(joinpath(directory, "manifest.toml"))["status"] == "run_or_analysis_failed"
    end
end

@testset "Three coherent settling windows distinguish decay and persistence" begin
    times = collect(0.0:0.001:60.0)
    spec = (; quantity = "Y", dimension = 2, drive = "current", dc_clamped = false,
        frequencies = [1.0, 3.0], phases = [0.0, -π], axes = ["p1_d", "p1_q"],
        tone_peak_pu = 0.0005, window_starts = (48.0, 52.0, 56.0), window_duration = 4.0)
    zeros2 = zeros(length(times), 2)
    voltage = hcat(ones(length(times)), zeros(length(times)))
    baseline = (; input = voltage, output = zeros2, voltage, current = zeros2,
        drive = zeros2, input_base = ones(2), output_base = ones(2), drive_base = ones(2))
    drive = hcat(V.multitone(times, spec.frequencies, spec.phases; amplitude = spec.tone_peak_pu),
        zeros(length(times)))
    function response(envelope)
        delta = drive .* envelope
        return (; input = voltage + delta, output = delta, voltage = voltage + delta,
            current = delta, drive)
    end
    steady = V.settling_window_changes(times, baseline, response(ones(length(times))), spec)
    @test steady["late"]["valid"] && steady["early"]["valid"]
    @test length(steady["late"]["adjacent_changes"]) == 2
    decay = V.settling_window_changes(times, baseline, response(1 .+ 0.8exp.(-times/10)), spec)
    @test !decay["early"]["valid"] && decay["late"]["valid"]
    persistent = V.settling_window_changes(times, baseline, response(1 .+ 0.1sin.(2π*0.027times)), spec)
    @test !persistent["late"]["valid"]
    @test all(!change["passed"] for change in persistent["late"]["adjacent_changes"])
end
end

module PSCADM9c8QueueTests
using Test
# Isolated orchestration doubles never load or contact a station.
module Queue
const ROOT = mktempdir()
const calls = String[]
RemoteConfig() = nothing
write_manifest(directory, record) = nothing
function run_settling_experiment(; kwargs...)
    push!(calls, "settling")
    error("offline settling failure")
end
function run_timing(args...; kwargs...)
    push!(calls, "timing")
    error("offline timing failure")
end
function run_fixture(id; kwargs...)
    push!(calls, id)
    return Dict("status" => "prepared_station_pending")
end
include("../manual/pscad/validation/queue.jl")
end
@testset "Pending queue continues after settling and timing failures" begin
    @test_throws ErrorException Queue.run_m9c8(timeout = 0)
    @test isempty(Queue.calls)
    record = @test_logs (:warn, r"Settling experiment failed") (:warn, r"Timing witness failed") Queue.run_m9c8(timeout = 1)
    @test Queue.calls == ["settling", "timing", "L2-16"]
    @test record["settling"]["status"] == "run_or_analysis_failed"
    @test record["timing"]["status"] == "run_or_analysis_failed"
    @test occursin("offline timing failure", record["timing"]["failure"])
    @test record["L2-16"]["status"] == "prepared_station_pending"
    rm(Queue.ROOT; recursive = true)
end
end

module PSCADOddRecorderTests
using Test, PowerImpedance
include("../manual/pscad/validation/validation.jl")
const V = PSCADValidation

@testset "Odd recorder ratio preparation and coherent half-step witnesses" begin
    spec = merge(V.l1_settings(), (; dimension = 2, protocol = "dq_active",
        frequencies = [1.0, 7.0, 1000.0], time_step = 2.5e-6,
        sample_step = 25 * 2.5e-6, window_starts = (16.0, 17.0),
        window_duration = 1.0, simulation_time = 18.0))
    @test V.check_recorder_sampling(spec) == 25
    for ratio in (8, 16, 20, 24, 26)
        even = merge(spec, (; sample_step = ratio * spec.time_step))
        @test_throws ErrorException V.check_recorder_sampling(even)
        mktempdir() do directory
            @test_throws ErrorException V.prepare_scan_projects(directory, nothing, even, String[])
            @test isempty(readdir(directory))
        end
    end
    for ratio in (1, 5, 25)
        @test V.check_recorder_sampling(merge(spec, (; sample_step = ratio * spec.time_step))) == ratio
    end
    @test_throws ErrorException V.check_recorder_sampling(merge(spec, (; sample_step = 25.5spec.time_step)))
    @test_throws ErrorException V.check_recorder_sampling(merge(spec, (; window_duration = 1.00001)))
    @test_throws ErrorException V.check_recorder_sampling(merge(spec, (; frequencies = [1.1, 1000.0])))
    @test_throws ErrorException V.check_recorder_sampling(merge(spec, (; frequencies = [2000.0, 10000.0])))
    for n in 7:15
        dt = n == 11 ? 1.25e-6 : n == 14 ? 1e-6 : 2.5e-6
        starts = n <= 10 ? (16.0, 17.0) : (8.0, 9.0)
        main = merge(spec, (; time_step = dt, sample_step = 25dt,
            frequencies = filter(!=(50.0), V.l1_settings().frequencies),
            window_starts = starts, simulation_time = last(starts) + 1))
        @test V.check_recorder_sampling(main) == 25
        @test inv(2main.sample_step) > 4 * 1050
        for frequency in main.frequencies
            witness = V.step_definition(main, frequency)
            @test V.check_recorder_sampling(witness) == 25
            @test witness.sample_step == 25witness.time_step
            @test witness.time_step == dt / 2
        end
    end
end

@testset "Eight-second zero-delay windows retain short coherent witnesses" begin
    for id in V.M9C13_IDS
        dt = id == "L2-11" ? 1.25e-6 : 2.5e-6
        start = id in ("L2-11", "L2-12") ? 8.0 : 16.0
        old = merge(V.l1_settings(), (; id, dimension = 2, protocol = "dq_active",
            frequencies = filter(!=(50.0), V.l1_settings().frequencies),
            time_step = dt, sample_step = 25dt, window_starts = (start, start + 1),
            window_duration = 1.0, simulation_time = start + 2))
        main = merge(old, (; window_starts = (start, start + 8),
            window_duration = 8.0, simulation_time = start + 16))
        @test V.check_recorder_sampling(main) == 25
        @test main.simulation_time == (start == 16 ? 32.0 : 24.0)
        @test round(Int, main.window_duration / main.sample_step) == (id == "L2-11" ? 256000 : 128000)
        for frequency in main.frequencies
            witness = V.step_definition(main, frequency)
            previous = V.step_definition(old, frequency)
            @test V.check_recorder_sampling(witness) == 25
            @test witness == previous
        end
        witness = V.step_definition(main, 1000.0)
        @test witness.window_duration == 0.1
        @test witness.simulation_time == start + 0.2
    end
end

@testset "EMT Nyquist chatter under even and odd decimation" begin
    dt = 2.5e-6
    frequencies = [1.0, 7.0, 1000.0]
    phases = [0.3, -0.7, 1.2]
    times = collect((0:400024) .* dt)
    clean = V.multitone(times, frequencies, phases; amplitude = 1.0)
    # The 1 Hz envelope overlaps a driven tone after even decimation. Its slow
    # 0.23 Hz term is deliberately noncoherent with the one-second DFT window.
    signal = clean + [0.2 * (1 + 0.4cos(2π*t) + 0.02sin(2π*0.23t)) *
        (isodd(n) ? -1 : 1) for (n, t) in zip(0:400024, times)]
    expected = cis.(phases)
    for ratio in (8, 25), offset in 0:(ratio-1)
        indices = (offset+1):ratio:(offset+400000)
        recorded_times = times[indices]
        phasors = vec(V.dft_phasors(recorded_times, reshape(signal[indices], :, 1),
            frequencies; start = first(recorded_times), duration = 1.0))
        clean_phasors = vec(V.dft_phasors(recorded_times, reshape(clean[indices], :, 1),
            frequencies; start = first(recorded_times), duration = 1.0))
        @test maximum(abs.((clean_phasors - expected) ./ expected)) < 1e-10
        relative_error = abs.((phasors - expected) ./ expected)
        if ratio == 8
            @test relative_error[1] > 0.05
        else
            @test maximum(relative_error) < 1e-6
        end
    end
end
end

module PSCADM9c10QueueTests
using Test, TOML
module Queue
const ROOT = mktempdir()
const calls = String[]
RemoteConfig() = nothing
manifest_lists!(record) = record
write_manifest(directory, record) = open(io -> TOML.print(io, record), joinpath(directory, "manifest.toml"), "w")
using TOML
function run_fixture(id; kwargs...)
    push!(calls, id)
    id == "L2-07" && error("offline fixture failure")
    return Dict("status" => "completed")
end
include("../manual/pscad/validation/queue.jl")
end
@testset "MMC queue preserves order and continues after a fixture failure" begin
    for timeout in (0.0, -1.0, Inf, NaN)
        @test_throws ErrorException Queue.run_m9c10(; timeout)
    end
    @test isempty(Queue.calls)
    directory = mkpath(joinpath(Queue.ROOT, "data", "L2-07"))
    write(joinpath(directory, "manifest.toml"), "fixture_id = \"L2-07\"\n")
    record = @test_logs (:warn, r"Fixture failed; continuing queue") Queue.run_m9c10(timeout = 1)
    @test Queue.calls == ["L2-07", "L2-08", "L2-09", "L2-10", "L2-12", "L2-13", "L2-15", "L2-11", "L2-14"]
    @test record["L2-07"]["status"] == "run_or_analysis_failed"
    @test occursin("offline fixture failure", record["L2-07"]["failure"])
    @test all(record[id]["status"] == "completed" for id in Queue.calls[2:end])
    @test TOML.parsefile(joinpath(Queue.ROOT, "data", "m9c10", "manifest.toml")) == record
    empty!(Queue.calls)
    @test_logs (:warn, r"Fixture failed; continuing queue") Queue.run_m9c10(timeout = 1)
    @test length(Queue.calls) == 9
    rm(Queue.ROOT; recursive = true)
end
end

module PSCADM9c13QueueTests
using Test, TOML
module Queue
using TOML
const ROOT = mktempdir()
const calls = String[]
const interrupt = Ref(false)
RemoteConfig() = nothing
manifest_lists!(record) = record
write_manifest(directory, record) = open(io -> TOML.print(io, record), joinpath(directory, "manifest.toml"), "w")
function run_fixture(id; directory, remote, deadline)
    isfinite(deadline) || error("missing queue deadline")
    if !isempty(calls)
        saved = TOML.parsefile(joinpath(ROOT, "data", "m9c13", "manifest.toml"))
        haskey(saved, last(calls)) || error("previous outcome not saved before advancing")
    end
    push!(calls, id)
    interrupt[] && throw(InterruptException())
    id == "L2-07" && error("offline fixture failure")
    return Dict("status" => id == "L2-09" ? "invalid_measurement" : "passed")
end
include("../manual/pscad/validation/queue.jl")
end
@testset "Eight-second queue records failures, resumes and stops on interrupt" begin
    for timeout in (0.0, -1.0, Inf, NaN)
        @test_throws ErrorException Queue.run_m9c13(; timeout)
    end
    @test isempty(Queue.calls)
    directory = mkpath(joinpath(Queue.ROOT, "data", "L2-07"))
    write(joinpath(directory, "manifest.toml"), "fixture_id = \"L2-07\"\n")
    expected = ["L2-07", "L2-08", "L2-09", "L2-10", "L2-11", "L2-12"]
    for attempt in 1:2
        empty!(Queue.calls)
        record = @test_logs (:warn, r"Fixture failed; continuing queue") Queue.run_m9c13(timeout = 1)
        @test Queue.calls == expected
        @test record["L2-07"]["status"] == "run_or_analysis_failed"
        @test occursin("offline fixture failure", record["L2-07"]["failure"])
        @test record["L2-09"]["status"] == "invalid_measurement"
        @test all(record[id]["status"] == "passed" for id in expected[[2, 4, 5, 6]])
        @test TOML.parsefile(joinpath(Queue.ROOT, "data", "m9c13", "manifest.toml")) == record
    end
    empty!(Queue.calls)
    Queue.interrupt[] = true
    @test_throws InterruptException Queue.run_m9c13(timeout = 1)
    @test Queue.calls == ["L2-07"]
    rm(Queue.ROOT; recursive = true)
end
end

module PSCADResidualStepTests
using Test, PowerImpedance, LinearAlgebra, TOML
include("../manual/pscad/validation/validation.jl")
const V = PSCADValidation

@testset "Residual step columns and measured readout timing" begin
    spec = (; time_step = 1e-5, frequency = 50.0)
    gamma = V.injection_readout_factor(1000.0, spec)
    @test V.kcl_readout_check(2gamma, 2.0, gamma)["passed"]
    @test !V.kcl_readout_check(2.0, 2.0, gamma)["passed"]
    @test !V.kcl_readout_check(0.0, 0.0, gamma)["passed"]
    predicted = reshape(ComplexF64[1, 0.2im, 0.3, 0.05], 4, 1, 1) .* gamma
    gamma_half = V.injection_readout_factor(1000.0, merge(spec, (; time_step = spec.time_step/2)))
    predicted_half = predicted .* (gamma_half / gamma)
    @test !V.matrix_change(predicted_half, predicted; epsilon = 0.01)["passed"]
    offset = fill(0.0001 + 0.0002im, 4, 1, 1)
    main, half = predicted + offset, predicted_half + offset
    @test V.residual_step_change(main, half, predicted, predicted_half; valid = true)["passed"]
    @test !V.residual_step_change(main, half .+ 0.001, predicted, predicted_half; valid = true)["passed"]
    @test V.residual_step_change(main, half, predicted, predicted_half; valid = false)["status"] == "invalid_measurement"
    @test V.residual_step_change(main, half, predicted, predicted; valid = true)["status"] == "failed"
    large_reference = reshape(ComplexF64[6, 5, 2, 1], 4, 1, 1)
    large_main = large_reference + offset
    large_half = large_reference .* (gamma_half / gamma) + offset .+ 0.0014
    change = V.residual_step_change(large_main, large_half, large_reference,
        large_reference .* (gamma_half / gamma); valid = true)
    @test change["passed"] && change["status"] == "passed"
    @test change["residual_normalised_frobenius"] > 0.01
    @test change["residual_normalised_entry"] > 0.01
    @test change["frobenius_change"] ≈ norm(fill(0.0014, 4)) / norm(large_main)
    @test change["entry_change"] ≈ maximum(0.0014 ./ abs.(large_main))
end

@testset "KCL readout evidence uses recorded orientations and both windows" begin
    times = collect(0.0:1e-4:3.0)
    spec = (; time_step = 2.5e-6, frequency = 50.0, frequencies = [100.0, 700.0],
        buses = [(; name = "AC")], axes = ["p1_d", "p1_q"],
        window_starts = (1.0, 2.0), window_duration = 1.0)
    probes = V.P.ProbeManifest([
        V.P.ProbeChannel("dut", :current, "AC", "DUT", "2", 3, "kA", :out),
        V.P.ProbeChannel("grid", :current, "AC", "Grid", "1", 3, "kA", :into),
        V.P.ProbeChannel("drive", :injection_current, "AC", "injection_1", "1", 3, "kA", :out)], nothing)
    model = (; probes)
    wave(dq) = hcat([dq[:,1] .* cos.(2π*50 .* times .+ phase) +
        dq[:,2] .* sin.(2π*50 .* times .+ phase) for phase in (0, -2π/3, 2π/3)]...)
    baseline = (; time = times, channels = Dict("$(name):$phase" => zeros(length(times))
        for name in ("dut", "grid", "drive") for phase in 1:3))
    for column in 1:2
        drive, terminal = zeros(length(times), 2), zeros(length(times), 2)
        for f in spec.frequencies
            drive[:,column] .+= cos.(2π*f .* times)
            terminal[:,column] .+= real.(V.injection_readout_factor(f, spec) .* cis.(2π*f .* times))
        end
        function recorded(total)
            signals = Dict("dut" => wave(-0.4total), "grid" => wave(0.6total), "drive" => wave(drive))
            channels = Dict("$(name):$phase" => samples[:,phase] for (name,samples) in signals for phase in 1:3)
            return (; time = times, channels)
        end
        evidence = V.readout_evidence(recorded(terminal), baseline, model, spec, column)
        @test evidence["passed"]
        @test length(evidence["rows"]) == 4
        @test evidence["max_relative_error"] < 1e-10
        @test !V.readout_evidence(recorded(drive), baseline, model, spec, column)["passed"]
    end
end

@testset "Exported termination and all affected converter topologies" begin
    for n in 7:15
        id = "L2-" * lpad(n, 2, '0')
        net = V.fixture(id).factory()
        @test V.residual_step_eligible(id, net) == (n <= 12)
        n <= 12 || continue
        list = V.fixture_netlist(net, power_flow(net))
        spec, _ = V.applicable_scan(id, net, list)
        short = merge(spec, (; frequencies = [750.0, 1000.0], phases = [0.0, -π]))
        plan, _ = V.scan_plan(list, short, "p1_q")
        parts = filter(c -> c isa V.P.ComponentPlan && c.defn in ("master:resistor", "master:inductor"), plan.main.components)
        # Use the actual exported component fields; their rounding differs
        # from the fixture's unrounded parameters.
        text = join(["<User defn=\"$(c.defn)\">" *
            join(["<param name=\"$k\" value=\"$v\"/>" for (k,v) in c.params]) * "</User>" for c in parts])
        mktempdir() do directory
            path = joinpath(directory, "fixture.pscx")
            write(path, text)
            termination = V.exported_termination(net, path)
            @test (termination.dc_resistance === nothing) == (n != 11)
            prediction = V.discrete_response_column(net, short, 2, termination)
            @test size(prediction) == (4, 1, 2)
            @test all(isfinite, prediction)
            y = V.interface_step_reference(net, short;
                dc_conductance = termination.dc_resistance === nothing ? nothing : inv(termination.dc_resistance))
            for (k,f) in enumerate(short.frequencies)
                scale = short.current_bases[2] ./ [short.voltage_bases; short.current_bases]
                physical = prediction[:,1,k] ./ scale ./ V.injection_readout_factor(f, short)
                r, l = termination.resistance, termination.inductance
                z = [r+im*2π*f*l 2π*50*l; -2π*50*l r+im*2π*f*l]
                @test physical[3:4] ≈ y[:,:,k] * physical[1:2]
                @test physical[3:4] + z \ physical[1:2] ≈ [0, 1]
            end
            write(path, replace(text, "[ohm]" => "[H]"))
            @test_throws ErrorException V.exported_termination(net, path)
        end
    end
end

@testset "Qualification uses the fixture's selected reference and step rule" begin
    function record()
        Dict{String, Any}("tier_a_status" => "passed",
            "tier_c_result" => Dict("valid" => true, "status" => "failed", "model_mismatch" => ""),
            "interface_step_result" => Dict("status" => "passed"),
            "amplitude_refinement" => Dict("valid" => true, "passed" => true),
            "raw_step_refinement" => Dict("valid" => true, "passed" => false, "status" => "failed"),
            "residual_step_refinement" => Dict("valid" => true, "passed" => true, "status" => "passed"),
            "step_refinement" => Dict("valid" => true, "passed" => true, "status" => "passed"))
    end
    r = record()
    @test V.qualify_fixture!(r; residual = true)["status"] == "passed"
    @test r["comparison_summary"]["plain_model"] == "failed"
    @test r["comparison_summary"]["raw_step"] == "failed"
    @test V.qualify_fixture!(r; residual = false)["status"] == "failed"
    r["tier_c_result"]["status"] = "passed"
    r["step_refinement"] = r["raw_step_refinement"]
    @test V.qualify_fixture!(r; residual = false)["status"] == "failed"
    r = record(); r["tier_c_result"]["valid"] = false
    @test V.qualify_fixture!(r; residual = true)["status"] == "invalid_measurement"
    for gate in ("amplitude_refinement", "step_refinement")
        r = record(); r[gate]["passed"] = false
        @test V.qualify_fixture!(r; residual = true)["status"] == "failed"
        r[gate]["valid"] = false
        @test V.qualify_fixture!(r; residual = true)["status"] == "invalid_measurement"
    end
    r = record(); r["interface_step_result"]["status"] = "failed"
    @test V.qualify_fixture!(r; residual = true)["status"] == "failed"
    r = record(); r["tier_a_status"] = "failed"
    @test V.qualify_fixture!(r; residual = true)["status"] == "failed"
    r = record(); r["tier_c_result"]["status"] = "passed"
    @test V.qualify_fixture!(r; residual = false)["status"] == "passed"
    r = record(); r["tier_c_result"]["model_mismatch"] = "declared mismatch"
    @test V.qualify_fixture!(r; residual = true)["status"] == "model_mismatch"
    @test_throws ErrorException V.reanalyse_m9c12(["L2-13"]; data_root = "/tmp")
    @test_throws ErrorException V.reanalyse_m9c12(["L2-07"]; data_root = "/tmp", output_root = "/")
end
end

module PSCADComposedValidationTests
using Test, PowerImpedance, LinearAlgebra, TOML
include("../manual/pscad/validation/validation.jl")
const V=PSCADValidation
const P=PowerImpedance.PSCAD

function abc_wave(times,dq)
    return hcat([dq[:,1].*cos.(2π*50 .* times .+ phase)+dq[:,2].*sin.(2π*50 .* times .+ phase)
        for phase in (0.,-2π/3,2π/3)]...)
end

# The electrical branch current and older injection recording are related by
# an abc transport. Build this fixture independently of the checker: the
# driven projection is unchanged, and the recorded null coordinate is tan(w*h).
function recorded_drive(drive,spec)
    out=copy(drive);t=tan(2π*spec.frequency*spec.time_step)
    for j in 1:2:length(drive)
        out[j]=drive[j]-t*drive[j+1]
        out[j+1]=t*drive[j]+drive[j+1]
    end
    return out
end
function direct_readout(f,spec,n=2)
    a=2π*spec.frequency*spec.time_step
    return exp(im*2π*f*spec.time_step)*kron(Matrix{Float64}(I,n÷2,n÷2),[cos(a) sin(a);-sin(a) cos(a)])
end

# Independent synthetic terminal models. The extra RC branch makes omitting a
# shunt from either aggregate Y or recorded KCL observably wrong.
function two_device_bus()
    net=V.l3_network("L3-01")
    add!(net,:Filter,impedance(z=s->2.0+inv(5e-6*s),pins=3,transformation=true))
    V.composed_ac!(net,:Filter,1,:AC);V.composed_ac!(net,:Filter,2,:gnd);connect!(net)
    point=power_flow(net);list=V.fixture_netlist(net,point);c=V.l3_circuit("L3-01",net)
    spec=merge(V.l3_spec("L3-01",list),(;frequencies=[7.,137.],phases=[0.,-π],
        window_starts=(1.,2.),window_duration=1.,simulation_time=3.,injection_time=0.,tone_peak_pu=1e-4))
    scale=spec.current_bases[1]/spec.voltage_bases[1]
    y1=ComplexF64[.35+.1im .06-.02im;-.04+.03im .28-.08im]*scale
    y2=ComplexF64[.21-.06im -.03+.01im;.02+.04im .31+.09im]*scale
    shunt=ComplexF64[.08+.12im .01;-.01 .08+.12im]*scale
    grid=ComplexF64[.9-.25im .03;-.03 .9-.25im]*scale
    agg=y1+y2+shunt;z=inv(agg+grid)
    refs=Dict("C1_Y"=>cat(y1,y1;dims=3),"C2_Y"=>cat(y2,y2;dims=3),
        "aggregate_Y"=>cat(agg,agg;dims=3),
        "direct_Z"=>cat((z*direct_readout(f,spec) for f in spec.frequencies)...;dims=3))
    return (;net,list,c,spec,y1,y2,shunt,grid,z,refs)
end

function synthetic_bus_run(bus,axis;spec=bus.spec,omit_shunt=false)
    times=collect(0.:spec.sample_step:spec.simulation_time)
    plan,settings=V.scan_plan(bus.list,spec,axis)
    v=zeros(length(times),2);i1=copy(v);i2=copy(v);ish=copy(v);ig=copy(v);drive=copy(v)
    if axis!="baseline"
        column=only(findall(==(axis),spec.axes))
        for (k,f) in enumerate(spec.frequencies)
            a=zeros(ComplexF64,2);a[column]=spec.tone_peak_pu*spec.current_bases[column]*cis(spec.phases[k])
            vp=V.injection_readout_factor(f,spec)*bus.z*a
            for (samples,phasor) in ((v,vp),(i1,bus.y1*vp),(i2,bus.y2*vp),
                    (ish,bus.shunt*vp),(ig,bus.grid*vp),(drive,recorded_drive(a,spec))), row in 1:2
                samples[:,row].+=real.(phasor[row].*cis.(2π*f.*times))
            end
        end
    end
    v[:,1].+=spec.voltage_bases[1]
    channels=PowerImpedance.OrderedDict{String,Vector{Float64}}()
    for probe in plan.probes.channels
        if probe.dim==3
            samples=if probe.kind==:voltage && probe.bus==only(spec.buses).name
                v
            elseif probe.kind==:injection_current
                drive
            elseif probe.kind==:current && probe.bus==only(spec.buses).name
                inward=probe.element=="C1" ? i1 : probe.element=="C2" ? i2 :
                    probe.element=="Filter" ? (omit_shunt ? zero(ish) : ish) : ig
                probe.orientation==:into ? inward : -inward
            else
                zeros(length(times),2)
            end
            abc=abc_wave(times,samples)
            for phase in 1:3;channels[probe.name*":"*string(phase)]=abc[:,phase];end
        else
            channels[probe.name]=fill(probe.kind==:voltage && probe.side=="P" ? 320. :
                probe.kind==:voltage && probe.side=="N" ? -320. : 0.,length(times))
        end
    end
    model=P.PSCADModel("synthetic.pscx",plan.name,bus.list,plan.probes,settings,bus.list.operating_point,(;))
    result=P.PSCADResult(PSCADRun(),times,channels,plan.probes,settings,(;),(;))
    return model,result
end

@testset "Composed shared-port individual Y, aggregate Y, direct Z and shunt KCL" begin
    bus=two_device_bus();spec=bus.spec
    models=Dict{String,P.PSCADModel}();results=Dict{String,P.PSCADResult}()
    for axis in ["baseline";spec.axes]
        models[axis],results[axis]=synthetic_bus_run(bus,axis)
    end
    baseline=V.composed_samples(results["baseline"],models["baseline"],spec,bus.c)
    runs=[V.composed_samples(results[axis],models[axis],spec,bus.c) for axis in spec.axes]
    extracted=V.composed_extract(results["baseline"].time,baseline,runs,spec,bus.c)
    for (target,known) in bus.refs
        @test extracted[target].matrices[1] ≈ known rtol=1e-9 atol=1e-9
        @test extracted[target].matrices[2] ≈ known rtol=1e-9 atol=1e-9
        @test maximum(extracted[target].conditions)<100
    end
    @test bus.refs["aggregate_Y"] != bus.refs["C1_Y"]+bus.refs["C2_Y"]
    for target in ("C1_Y","C2_Y")
        ts=V.composed_target_spec(spec,bus.c,target)
        @test ts.current_bases ≈ spec.current_bases/2
        @test ts.voltage_bases==spec.voltage_bases
    end
    mktempdir() do directory
        comparison=V.composed_comparison(results,models,bus.refs,directory,spec,bus.c)
        @test all(x["status"]=="passed" for x in values(comparison.comparisons))
        @test all(x["passed"] for x in comparison.kcl)
        @test all(x["max_relative_error"]<1e-8 for x in comparison.kcl)
        @test all(isempty(x["invalid_reasons"]) for x in values(comparison.comparisons))
        # The former scalar null-coordinate check fails even with exact KCL.
        nullrows=[r for x in comparison.kcl for r in x["rows"] if r["check"]=="transported dq KCL residual"]
        @test all(abs(complex(r["recorded_real"],r["recorded_imag"]))>1e-8 for r in nullrows)
        @test all(r["relative_error"]<1e-10 && r["limit"]==1e-6 for r in nullrows)
        @test all(any(occursin("Filter",b) for b in r["branches"]) for x in comparison.kcl for r in x["rows"])
        @test length(readdir(directory))==12
    end
    singular=copy(results);singular["p1_q"]=results["p1_d"]
    mktempdir() do directory
        invalid=V.composed_comparison(singular,models,bus.refs,directory,spec,bus.c)
        @test all(x["status"]=="invalid_measurement" for x in values(invalid.comparisons))
        @test all(any(startswith(r,"response_extraction:") for r in x["invalid_reasons"]) for x in values(invalid.comparisons))
    end
    badmodel,bad=synthetic_bus_run(bus,"p1_d";omit_shunt=true)
    @test !V.composed_readout_evidence(bad,results["baseline"],badmodel,spec,bus.c,1)["passed"]
    mktempdir() do directory
        corrupted=copy(results);corrupted["p1_d"]=bad
        invalid=V.composed_comparison(corrupted,models,bus.refs,directory,spec,bus.c)
        @test all("kcl_readout" in x["invalid_reasons"] for x in values(invalid.comparisons))
    end
    column=V.composed_column(results["p1_d"],results["baseline"],models["p1_d"],spec,bus.c,1)
    halfspec=merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2))
    halfmodel,half=synthetic_bus_run(bus,"p1_d";spec=halfspec)
    halfcol=V.composed_column(half,results["baseline"],halfmodel,halfspec,bus.c,1)
    @test all(V.matrix_change(halfcol[t].matrix,column[t].matrix;epsilon=.02)["passed"] for t in keys(column))
    amplified_model,amplified=synthetic_bus_run(bus,"p1_d";spec=merge(spec,(;tone_peak_pu=2spec.tone_peak_pu)))
    amplified_samples=V.composed_samples(amplified,amplified_model,spec,bus.c)
    quality=V.composed_quality(amplified.time,baseline,[amplified_samples],spec,bus.c,"C1_Y";columns=[1])
    @test !quality["valid"] && "drive_amplitude_error" in quality["invalid_reasons"]
    unsettled=deepcopy(results["p1_d"])
    for phase in 1:3
        unsettled.channels["I_C1_2:$phase"][unsettled.time.>=2.] .*= 1.2
    end
    mktempdir() do directory
        changed=copy(results);changed["p1_d"]=unsettled
        invalid=V.composed_comparison(changed,models,bus.refs,directory,spec,bus.c)
        @test "window_change" in invalid.comparisons["C1_Y"]["invalid_reasons"]
    end
    # Individual errors cannot disappear through cancellation in aggregate Y.
    corrupted=deepcopy(bus.refs);corrupted["C1_Y"] .*= 1.2;corrupted["C2_Y"] .*= .8
    mktempdir() do directory
        check=V.composed_comparison(results,models,corrupted,directory,spec,bus.c)
        @test check.comparisons["aggregate_Y"]["status"]=="passed"
        @test check.comparisons["C1_Y"]["status"]=="failed"
        @test check.comparisons["C2_Y"]["status"]=="failed"
    end
end

@testset "Heterogeneous devices retain original bases beside the aggregate rating" begin
    net=Network()
    add!(net,:C1,V.batch_c_device(:gfm))
    add!(net,:C2,deepcopy(V.mmc_grid_network(mode=:pq).elements[:DUT]))
    bases=V.L3_AGGREGATE_BASES["L3-03"]
    vb=bases.voltage_LL_kV*sqrt(2/3);ib=2bases.power_MVA/(3vb)
    spec=(;quantity="Y",axes=["p1_d","p1_q"],voltage_bases=fill(vb,2),current_bases=fill(ib,2))
    circuit=(;net)
    gfm=V.composed_target_spec(spec,circuit,"C1_Y")
    mmc=V.composed_target_spec(spec,circuit,"C2_Y")
    @test bases.power_MVA==2060.
    @test gfm.voltage_bases≈fill(400sqrt(2/3),2)
    @test gfm.current_bases≈fill(1060sqrt(2)/(sqrt(3)*400),2)
    @test mmc.voltage_bases≈fill(380sqrt(2/3),2)
    @test mmc.current_bases≈fill(1000sqrt(2)/(sqrt(3)*380),2)
    @test V.composed_target_spec(spec,circuit,"aggregate_Y").current_bases==fill(ib,2)
    @test V.composed_target_spec(spec,circuit,"direct_Z").quantity=="Z"
end

@testset "Four-coordinate extraction retains cross-port Y and direct Z" begin
    times=collect(0.:.0005:3.);fs=[7.,137.]
    known=ComplexF64[1 .2im .1 -.03im;-.1im 1.1 .02 .08;.13 .01 1.2 .2im;.03im .07 -.1im .9]
    grid=2Matrix{Float64}(I,4,4);z=inv(known+grid)
    voltages=Matrix{Float64}[];currents=Matrix{Float64}[];drives=Matrix{Float64}[]
    for column in 1:4
        v=zeros(length(times),4);i=copy(v);d=copy(v)
        for f in fs,row in 1:4
            v[:,row].+=real.(z[row,column].*cis.(2π*f.*times))
            i[:,row].+=real.((known*z)[row,column].*cis.(2π*f.*times))
            d[:,row].+=(row==column).*cos.(2π*f.*times)
        end
        push!(voltages,v);push!(currents,i);push!(drives,d)
    end
    base=zeros(length(times),4)
    y=V.extract_response(times,voltages,currents,base,base,fs;starts=(1.,2.),duration=1.)
    zz=V.extract_response(times,drives,voltages,base,base,fs;starts=(1.,2.),duration=1.)
    @test size(y.matrices[1])==(4,4,2)
    for k in 1:2
        @test y.matrices[1][:,:,k]≈known atol=1e-12
        @test zz.matrices[1][:,:,k]≈z atol=1e-12
        @test norm(y.matrices[1][1:2,3:4,k])>0
        @test norm(y.matrices[1][3:4,1:2,k])>0
    end
    # Exercise the composed recorder path too, including KCL at the undriven
    # port. Coupling is specified independently by the known full matrix above.
    spec=(;id="L3-07",quantity="Y",dimension=2,axes=["p1_d","p1_q","p2_d","p2_q"],
        buses=[(;name="A"),(;name="B")],frequencies=fs,phases=zeros(2),frequency=50.,time_step=2.5e-6,
        voltage_bases=ones(4),current_bases=ones(4),tone_peak_pu=1e-4,drive="current",window_starts=(1.,2.),window_duration=1.)
    probes=P.ProbeChannel[]
    for (port,bus) in enumerate(("A","B"))
        push!(probes,P.ProbeChannel("v$port",:voltage,bus,nothing,nothing,3,"kV"))
        push!(probes,P.ProbeChannel("dut$port",:current,bus,"DUT$port","2",3,"kA",:out))
        push!(probes,P.ProbeChannel("grid$port",:current,bus,"Grid$port","1",3,"kA",:into))
        push!(probes,P.ProbeChannel("drive$port",:injection_current,bus,"injection_$port","1",3,"kA",:out))
    end
    model=(;probes=P.ProbeManifest(probes,nothing))
    models=Dict(axis=>model for axis in ["baseline";spec.axes])
    results=Dict{String,Any}()
    for (column,axis) in enumerate(["baseline";spec.axes])
        v=zeros(length(times),4);i=copy(v);g=copy(v);d=copy(v)
        if axis!="baseline"
            for f in fs
                drive=zeros(ComplexF64,4);drive[column-1]=spec.tone_peak_pu
                voltage=V.injection_readout_factor(f,spec)*z*drive
                for (samples,phasor) in ((v,voltage),(i,known*voltage),(g,grid*voltage),(d,recorded_drive(drive,spec))), row in 1:4
                    samples[:,row].+=real.(phasor[row].*cis.(2π*f.*times))
                end
            end
        end
        channels=Dict{String,Vector{Float64}}()
        for port in 1:2, (stem,samples) in (("v",v),("dut",-i),("grid",g),("drive",d))
            abc=abc_wave(times,samples[:,(2port-1):2port])
            for phase in 1:3;channels["$stem$port:$phase"]=abc[:,phase];end
        end
        results[axis]=(;time=times,channels)
    end
    circuit=(;devices=Symbol[],grids=[:Grid1,:Grid2],ports=[(:DUT1,2),(:DUT2,2)])
    refs=Dict("aggregate_Y"=>cat(known,known;dims=3),
        "direct_Z"=>cat((z*direct_readout(f,spec,4) for f in fs)...;dims=3))
    mktempdir() do directory
        comparison=V.composed_comparison(results,models,refs,directory,spec,circuit)
        @test all(x["status"]=="passed" for x in values(comparison.comparisons))
        @test length(comparison.kcl)==4
        @test all(x["passed"] for x in comparison.kcl)
        @test all(Set(r["port"] for r in x["rows"])==Set([1,2]) for x in comparison.kcl)
        @test all(x["max_relative_error"]<1e-10 for x in comparison.kcl)
    end
end

function passive_project(plan,path)
    parts=filter(c->c isa P.ComponentPlan && c.defn in ("master:resistor","master:inductor","master:capacitor"),plan.main.components)
    write(path,join(["<User defn=\"$(c.defn)\">"*join(["<param name=\"$k\" value=\"$v\"/>" for (k,v) in c.params])*"</User>" for c in parts]))
    return path
end

@testset "Frozen L3 registration, complete-network gate and composed residual reference" begin
    @test V.M9D_A_IDS==["L3-01","L3-08"]
    @test sort!([e.id for e in V.REGISTRY if startswith(e.id,"L3-")])==sort([V.M9D_A_IDS;V.M9D_B_IDS])
    @test V.L3_NATIVE_NODES==Dict("L3-01"=>31,"L3-02"=>77,"L3-03"=>77,"L3-04"=>67,
        "L3-05"=>52,"L3-06"=>55,"L3-07"=>96,"L3-08"=>55)
    for (id,right,amp) in (("L3-01",-1.9916375342503203,.0004508893578873102),
            ("L3-08",-10.953699604677505,.00047389717632280974))
        net=V.l3_network(id);point=power_flow(net);list=V.fixture_netlist(net,point);c=V.l3_circuit(id,net)
        gate=V.composed_stability(c)
        @test gate["status"]=="passed"
        @test gate["most_positive_located_real_per_s"]≈right rtol=1e-5
        @test gate["descriptor_native_residual"]<1e-10
        @test gate["closed_RHP_count"]==0
        spec=V.l3_spec(id,list)
        @test spec.tone_peak_pu==amp
        @test spec.window_starts==(16.,24.) && spec.window_duration==8. && spec.simulation_time==32.
        @test V.check_recorder_sampling(spec)==25
        @test spec.power_base_MVA==(id=="L3-01" ? 200. : 1000.)
        @test V.composed_step_spec(spec,7.).window_starts==(16.,17.)
        plan,_=V.scan_plan(list,spec,"baseline")
        @test P.check_connectivity(plan)===nothing
        measured_plan,_=V.scan_plan(list,merge(spec,(;recorder_scope="measurement")),"p1_d")
        @test P.check_connectivity(measured_plan)===nothing
        @test all(p.kind in (:voltage,:current,:injection_current) for p in measured_plan.probes.channels)
        @test length(measured_plan.probes.channels)<length(plan.probes.channels)
        @test !any(p.kind==:voltage && p.bus==V.port_probe(list,:G_A,1).name for p in measured_plan.probes.channels)
        @test !any(p.kind==:current && p.element=="Grid_A" && p.side=="2" for p in measured_plan.probes.channels)
        @test count(x->x isa P.ComponentPlan && x.defn=="master:ammeter",measured_plan.main.components)==
            count(x->x isa P.ComponentPlan && x.defn=="master:ammeter",plan.main.components)
        passives(canvas)=[(x.defn,x.params,x.x,x.y,x.orient) for x in canvas.components
            if x isa P.ComponentPlan && x.defn in ("master:resistor","master:inductor","master:capacitor")]
        @test passives(measured_plan.main)==passives(plan.main)
        plain=V.composed_reference(c,spec)
        @test size(plain["aggregate_Y"])==(2,2,23)
        if id=="L3-01"
            @test plain["aggregate_Y"]≈plain["C1_Y"]+plain["C2_Y"]
            for name in c.devices
                @test !V.interface_step_eligible(net.elements[name].element_model)
                @test net.elements[name].element_model.mod.delay.timeDelay==200e-6
            end
            # Preserve every native state, including an injected unstable mode.
            net.elements[:C1].A[1,:].=0;net.elements[:C1].A[:,1].=0;net.elements[:C1].A[1,1]=10.
            @test maximum(real,V.composed_descriptor(c).poles)>0
            @test V.composed_stability(c)["status"]=="failed"
            continue
        end
        local_spec=V.l3_spec(id,list;local_scan=true)
        @test local_spec.frequencies==[collect(232.:1.5:260.5);collect(334.:1.5:361.)]
        @test local_spec.tone_peak_pu==5.910035278632797e-5
        @test length(local_spec.frequencies)==39
        @test V.check_recorder_sampling(local_spec)==25
        local_step=V.composed_step_spec(local_spec,245.5;local_scan=true)
        @test local_step.frequencies==local_spec.frequencies && local_step.window_starts==(16.,24.)
        @test local_step.simulation_time==32. && V.check_recorder_sampling(local_step)==25
        mktempdir() do directory
            project=passive_project(plan,joinpath(directory,"actual.pscx"))
            forms=V.exported_composed_passives(c,project,list)
            @test forms[:Filter].R≈2. && forms[:Filter].C≈5e-6
            @test forms[:Grid_A].L≈.05716979654497069 rtol=1e-8
            step=V.composed_step_spec(spec,1000.)
            pred=V.composed_predicted_columns(c,spec,1,forms)
            predhalf=V.composed_predicted_columns(c,step,1,forms)
            discrete=V.composed_reference(c,spec;time_step=spec.time_step,forms)
            @test norm(discrete["aggregate_Y"]-discrete["C1_Y"])>0
            # Independent single-device reduction plus analytic RC and grid.
            for (k,f) in enumerate(spec.frequencies)
                s=ComplexF64(im*2π*f);e=net.elements[:C1]
                isolated=Network();isolated.elements[:DUT]=e
                yy=V.interface_step_reference(isolated,merge(spec,(;frequencies=[f])))[:,:,1]
                sh=V.composed_passive_y(net.elements[:Filter],forms[:Filter],s)[1:2,1:2]
                gy=V.composed_passive_y(net.elements[:Grid_A],forms[:Grid_A],s)[1:2,1:2]
                @test discrete["C1_Y"][:,:,k]≈yy
                @test discrete["aggregate_Y"][:,:,k]≈yy+sh
                @test discrete["direct_Z"][:,:,k]≈inv(yy+sh+gy)
            end
            main=Dict(t=>(matrix=p,quality=Dict("valid"=>true)) for (t,p) in pred)
            half=Dict(t=>(matrix=p,quality=Dict("valid"=>true)) for (t,p) in predhalf)
            checks=[Dict{String,Any}("passed"=>true)]
            model=(;project_path=project,netlist=list)
            group=Dict{String,Any}()
            witness=V.composed_witnesses!(group,c,spec,step,1,main,half,main,(main=model,half=model),checks,directory)
            @test all(w["status"]=="passed" for w in values(witness))
            @test any(!w["raw_step"]["passed"] for w in values(witness))
            @test all(w["selected_step"]["entry_change"]<1e-12 for w in values(witness))
            @test all(w["reproduction"]["main"]["passed"] for w in values(witness))
            checks[1]["passed"]=false
            bad=V.composed_witnesses!(group,c,spec,step,1,main,half,main,(main=model,half=model),checks,directory)
            @test all(w["status"]=="invalid_measurement" for w in values(bad))
            @test all("kcl_readout" in w["invalid_reasons"] for w in values(bad))
            V.composed_reference_files!(nothing,c,spec,directory,forms)
            @test V.composed_reference_files!(nothing,c,spec,directory,forms;verify=true)===nothing
            frozen=joinpath(directory,V.scan_prefix(spec)*"discrete_aggregate_Y_reference.tsv")
            frozen_refs=V.composed_frozen_references(directory,spec,c,"discrete")
            for (k,f) in enumerate(spec.frequencies)
                @test frozen_refs["direct_Z"][:,:,k]≈V.injection_readout_factor(f,spec)*discrete["direct_Z"][:,:,k]
            end
            changed=copy(frozen_refs["aggregate_Y"]);changed[1,1,1]*=1.1
            V.write_response(frozen,changed,spec.frequencies)
            @test_throws ErrorException V.composed_reference_files!(nothing,c,spec,directory,forms;verify=true)
            # An exported physical-value change is rejected before prediction.
            write(project,replace(read(project,String),"2.0 [ohm]"=>"3.0 [ohm]"))
            @test_throws Exception V.exported_composed_passives(c,project,list)
        end
    end
end


@testset "Internal lumped nodes use the same reduction and local device voltage" begin
    parent=V.l3_network("L3-08");net=Network();net.voltageBase[1]=380/sqrt(3)
    for name in (:C1,:G_A,:Grid_A,:D_C1)
        add!(net,name,deepcopy(parent.elements[name]))
    end
    V.composed_ac!(net,:C1,2,:Remote);V.composed_ac!(net,:G_A,1,:Src)
    V.composed_ac!(net,:G_A,2,:gnd);V.composed_ac!(net,:Grid_A,1,:AC);V.composed_ac!(net,:Grid_A,2,:Src)
    connect!(net,(:C1,Symbol("1.1")),:DC);connect!(net,(:D_C1,Symbol("1.1")),:DC)
    connect!(net,(:D_C1,Symbol("2.1")),:gnd)
    add!(net,:Line,impedance(z=s->2.0+.02s,pins=3,transformation=true))
    V.composed_ac!(net,:Line,1,:AC);V.composed_ac!(net,:Line,2,:Remote)
    for (name,bus) in ((:Cnear,:AC),(:Cfar,:Remote))
        add!(net,name,impedance(z=s->inv(2e-6*s),pins=3,transformation=true))
        V.composed_ac!(net,name,1,bus);V.composed_ac!(net,name,2,:gnd)
    end
    connect!(net);point=power_flow(net);list=V.fixture_netlist(net,point)
    c=V.composed_circuit(net,[:C1],[:Grid_A],[(:Line,1)])
    @test length(c.nodes)==4
    gate=V.composed_stability(c)
    @test gate["status"]=="passed" && gate["descriptor_native_residual"]<1e-10
    @test gate["most_positive_located_real_per_s"]≈-10.9540877 rtol=1e-6
    spec=merge(V.l3_spec("L3-08",list),(;buses=[V.port_probe(list,:Line,1)],frequencies=[237.,367.],phases=[0.,-π]))
    plan,_=V.scan_plan(list,spec,"baseline")
    mktempdir() do directory
        project=passive_project(plan,joinpath(directory,"pi.pscx"))
        forms=V.exported_composed_passives(c,project,list)
        refs=V.composed_reference(c,spec;time_step=spec.time_step,forms)
        predicted=V.composed_predicted_columns(c,spec,1,forms)
        functions=V.composed_device_functions(c;time_step=spec.time_step)
        for (k,f) in enumerate(spec.frequencies)
            s=im*2π*f;q=s*I(2)+[0. 2π*50;-2π*50 0.]
            line=inv(2I(2)+.02q);cap=2e-6q;yd=functions[:C1](s)[2:3,2:3]
            remote=(line+cap+yd)\line
            aggregate=cap+line-line*remote
            grid=V.composed_passive_y(net.elements[:Grid_A],forms[:Grid_A],s)[1:2,1:2]
            near=(aggregate+grid)\[1.,0.];local_voltage=remote*near
            @test refs["aggregate_Y"][:,:,k]≈aggregate rtol=1e-10
            @test refs["C1_Y"][:,:,k]≈yd rtol=1e-10
            @test refs["direct_Z"][:,:,k]≈inv(aggregate+grid) rtol=1e-10
            b=V.device_bases(net.elements[:C1].element_model.elec)
            expected=V.injection_readout_factor(f,spec).*spec.current_bases[1].*
                [local_voltage./b.ac_voltage;(yd*local_voltage)./b.ac_current]
            @test predicted["C1_Y"][:,1,k]≈expected rtol=1e-10
            @test norm(local_voltage-near)>1e-3
        end
    end
end


@testset "Stage B frozen factories, numerical admission and conditioning" begin
    @test V.M9D_B_IDS==["L3-02","L3-04","L3-03"]
    # Independent values frozen by the proposal; no preparation or native runs.
    for (id,right,peak,peak_f,sampled,discrete_peak,amp) in (
            ("L3-02",-10.872237947687688,21.79954783506469,50.232250432178716,
                21.79954608163451,21.801587951588505,.000255889219949928),
            ("L3-04",-10.954087715861549,41.05819735993356,367.28750909034244,
                41.05810094572044,34.467198177827676,.0007118962353546502),
            ("L3-03",-.0006283185308747,26.3847297623963,50.49689963194021,
                26.38423668513727,26.38493241075408,.0006924416531567809))
        net=V.fixture(id).factory();point=power_flow(net);list=V.fixture_netlist(net,point);c=V.l3_circuit(id,net)
        spec=V.l3_spec(id,list);gate=V.composed_stability(c)
        @test gate["status"]=="passed"
        @test gate["most_positive_located_real_per_s"]≈right rtol=1e-9
        j=argmax(gate["poles_real_per_s"])
        if id=="L3-03"
            @test abs(gate["poles_imag_rad_per_s"][j])<1e-12
        else
            @test abs(gate["poles_imag_rad_per_s"][j])≈(id=="L3-02" ? 18.51585338533926 : 18.562915099914086) rtol=1e-9
        end
        @test gate["closed_RHP_count"]==0
        @test gate["descriptor_native_residual"]<1e-10
        @test gate["frequency_count"]==6001
        @test spec.tone_peak_pu==amp
        @test spec.window_starts==(16.,24.) && spec.window_duration==8. && spec.simulation_time==32.
        @test V.check_recorder_sampling(spec)==25
        @test V.check_recorder_sampling(V.composed_step_spec(spec,7.))==25
        @test V.L3_NATIVE_NODES[id]==(id=="L3-04" ? 67 : 77)
        @test net.voltageBase[1]==380/sqrt(3)
        @test spec.power_base_MVA==(id=="L3-02" ? 2000. : id=="L3-03" ? 2060. : 1000.)
        grid=PowerImpedance.get_y(net.elements[:Grid_A],ComplexF64(1.))
        rating=id=="L3-03" ? 2060. : 1000.
        r=380^2/rating/8/sqrt(101);l=10r/(2π*50);q=I(2)+[0. 2π*50;-2π*50 0.]
        @test grid[1:2,1:2]≈inv(r*I(2)+l*q) rtol=1e-12
        # Reproduce the exact dense proposal grid and the refined peak height.
        fs=sort!(unique([exp10.(range(0,3;length=3001));spec.frequencies]))
        dense_spec=merge(spec,(;frequencies=fs))
        plain=V.composed_reference(c,dense_spec)
        discrete=V.composed_reference(c,dense_spec;time_step=spec.time_step)
        @test maximum(cond(plain["direct_Z"][:,:,k]) for k in eachindex(fs))≈sampled rtol=1e-9
        @test maximum(cond(discrete["direct_Z"][:,:,k]) for k in eachindex(fs))≈discrete_peak rtol=1e-9
        refined=V.composed_reference(c,merge(spec,(;frequencies=[peak_f])))
        @test cond(refined["direct_Z"][:,:,1])≈peak rtol=1e-9
        @test Set(keys(plain))==Set(["aggregate_Y","direct_Z",[string(n)*"_Y" for n in c.devices]...])
        plan,_=V.scan_plan(list,spec,"baseline")
        measured,_=V.scan_plan(list,merge(spec,(;recorder_scope="measurement")),"p1_d")
        @test P.check_connectivity(plan)===nothing
        @test P.check_connectivity(measured)===nothing
        @test count(x->x isa P.ComponentPlan && x.defn=="master:ammeter",measured.main.components)==
            count(x->x isa P.ComponentPlan && x.defn=="master:ammeter",plan.main.components)
        @test all(p.kind in (:voltage,:current,:injection_current) for p in measured.probes.channels)
        for name in c.devices
            b=V.device_bases(net.elements[name].element_model.elec)
            @test any(p->p.kind==:voltage && p.bus==V.port_probe(list,name,b.ac_side).name,measured.probes.channels)
            @test any(p->p.kind==:current && p.element==string(name) && p.side==string(b.ac_side),measured.probes.channels)
            @test net.elements[Symbol("D_",name)].setpoint.Vdc==b.dc_voltage
        end
        mktempdir() do directory
            project=passive_project(plan,joinpath(directory,"actual.pscx"))
            forms=V.exported_composed_passives(c,project,list)
            functions=V.composed_device_functions(c;time_step=spec.time_step)
            native=V.composed_device_functions(c)
            for name in c.devices
                e=net.elements[name];b=V.device_bases(e.element_model.elec)
                changed=V.interface_step_eligible(e.element_model)
                @test changed==(id!="L3-03" || name==:C2)
                for f in (7.,137.,750.)
                    s=ComplexF64(im*2π*f)
                    if changed
                        isolated=Network();isolated.elements[:DUT]=e
                        independent=V.interface_step_reference(isolated,merge(spec,(;frequencies=[f])))[:,:,1]
                        @test functions[name](s)[b.ac_indices,b.ac_indices]≈independent rtol=1e-12
                        @test norm(functions[name](s)-native[name](s))>1e-8
                    else
                        @test functions[name](s)==native[name](s)
                        @test e.element_model.modulation.delay1.timeDelay==200e-6
                    end
                end
            end
            if id!="L3-04"
                refs=V.composed_reference(c,spec;time_step=spec.time_step,forms)
                @test refs["aggregate_Y"]≈refs["C1_Y"]+refs["C2_Y"] rtol=1e-12
                for (k,f) in enumerate(spec.frequencies)
                    gy=V.composed_passive_y(net.elements[:Grid_A],forms[:Grid_A],im*2π*f)[1:2,1:2]
                    @test refs["direct_Z"][:,:,k]≈inv(refs["C1_Y"][:,:,k]+refs["C2_Y"][:,:,k]+gy) rtol=1e-12
                end
            else
                @test length(c.nodes)==4 && c.ports==[(:Line,1)]
                @test forms[:Line].R==2. && forms[:Line].L==.02
                @test forms[:Cnear].C≈2e-6 && forms[:Cfar].C≈2e-6
                @test only(spec.buses).name==V.port_probe(list,:Line,1).name
                @test only(spec.buses).name!=V.port_probe(list,:C1,2).name
                local_spec=V.l3_spec(id,list;local_scan=true)
                @test local_spec.frequencies==collect(357.:.5:378.)
                @test local_spec.tone_peak_pu==2.4385006018880013e-5
                @test local_spec.resonance_groups==[collect(1:43)]
                @test V.scan_record(local_spec)["resonance_groups"]==[collect(1:43)]
                step=V.composed_step_spec(local_spec,367.;local_scan=true)
                @test step.frequencies==local_spec.frequencies && step.window_starts==(16.,24.)
                @test step.simulation_time==32. && V.check_recorder_sampling(step)==25
                local_refs=V.composed_reference(c,local_spec;time_step=spec.time_step)
                resolution=V.half_power_resonance(local_spec.frequencies,
                    [norm(local_refs["direct_Z"][:,:,k]) for k in eachindex(local_spec.frequencies)])
                @test resolution["resolved"]
                @test resolution["centre_Hz"]≈366.9188533723705 rtol=1e-9
                @test resolution["width_Hz"]≈5.727917076969845 rtol=1e-9
                @test length(V.l3_specs(id,list))==2
            end
            # Each device/aggregate/direct-Z residual is independently qualified.
            step=V.composed_step_spec(spec,750.)
            pred=V.composed_predicted_columns(c,spec,1,forms)
            predhalf=V.composed_predicted_columns(c,step,1,forms)
            main=Dict(t=>(matrix=p,quality=Dict("valid"=>true)) for (t,p) in pred)
            half=Dict(t=>(matrix=p,quality=Dict("valid"=>true)) for (t,p) in predhalf)
            model=(;project_path=project,netlist=list);group=Dict{String,Any}()
            witness=V.composed_witnesses!(group,c,spec,step,1,main,half,main,
                (main=model,half=model),[Dict("passed"=>true)],directory)
            @test all(w["status"]=="passed" && w["step_reference"]=="composed_residual" for w in values(witness))
            @test all(w["selected_step"]["entry_change"]<1e-12 for w in values(witness))
        end
        if id=="L3-03"
            @test occursin("equilibrium",spec.settling["scope"])
            @test occursin("400-to-380",only(filter(x->occursin("equilibrium",x),V.fixture(id).differences)))
            b=V.device_bases(net.elements[:C1].element_model.elec)
            @test b.power==1060. && b.dc_voltage==640.
            @test b.ac_voltage≈400sqrt(2/3)
        end
    end
end

@testset "Near-end scan retains remote converter V/I and local departure gates" begin
    net=V.l3_network("L3-04");point=power_flow(net);list=V.fixture_netlist(net,point);c=V.l3_circuit("L3-04",net)
    spec=merge(V.l3_spec("L3-04",list),(;frequencies=[7.,137.],phases=[0.,-π],
        window_starts=(1.,2.),window_duration=1.,simulation_time=3.,injection_time=0.,
        tone_peak_pu=1e-4,recorder_scope="measurement"))
    scale=spec.current_bases[1]/spec.voltage_bases[1]
    yd=ComplexF64[.4+.06im .03;-.02 .3-.08im]*scale
    yl=ComplexF64[.8+.1im .02;-.02 .8+.1im]*scale
    cn=ComplexF64[.08+.12im .01;-.01 .08+.12im]*scale
    cf=1.2cn;yg=ComplexF64[.9-.25im .03;-.03 .9-.25im]*scale
    remote=(yl+cf+yd)\yl;aggregate=cn+yl-yl*remote;z=inv(aggregate+yg)
    times=collect(0.:spec.sample_step:spec.simulation_time)
    models=Dict{String,P.PSCADModel}();results=Dict{String,P.PSCADResult}()
    remote_bus=V.port_probe(list,:C1,2).name
    for axis in ["baseline";spec.axes]
        plan,settings=V.scan_plan(list,spec,axis)
        v=zeros(length(times),2);u=copy(v);d=copy(v)
        currents=Dict((element,side)=>copy(v) for (element,side) in
            (("C1","2"),("Cnear","1"),("Cfar","1"),("Line","1"),("Grid_A","1")))
        if axis!="baseline"
            column=only(findall(==(axis),spec.axes))
            for (k,f) in enumerate(spec.frequencies)
                drive=zeros(ComplexF64,2);drive[column]=spec.tone_peak_pu*spec.current_bases[column]*cis(spec.phases[k])
                near=V.injection_readout_factor(f,spec)*z*drive;far=remote*near
                pairs=[(v,near),(u,far),(d,recorded_drive(drive,spec)),
                    (currents[("C1","2")],yd*far),(currents[("Cnear","1")],cn*near),
                    (currents[("Cfar","1")],cf*far),(currents[("Line","1")],yl*(near-far)),
                    (currents[("Grid_A","1")],yg*near)]
                for (samples,phasor) in pairs, row in 1:2
                    samples[:,row].+=real.(phasor[row].*cis.(2π*f.*times))
                end
            end
        end
        v[:,1].+=spec.voltage_bases[1];u[:,1].+=spec.voltage_bases[1]
        channels=PowerImpedance.OrderedDict{String,Vector{Float64}}()
        for probe in plan.probes.channels
            if probe.dim==3
                samples=if probe.kind==:voltage
                    probe.bus==remote_bus ? u : v
                elseif probe.kind==:injection_current
                    d
                else
                    inward=currents[(probe.element,probe.side)]
                    probe.orientation==:into ? inward : -inward
                end
                abc=abc_wave(times,samples)
                for phase in 1:3;channels[probe.name*":"*string(phase)]=abc[:,phase];end
            else
                channels[probe.name]=fill(probe.kind==:voltage && probe.side=="P" ? 400. :
                    probe.kind==:voltage && probe.side=="N" ? -400. : 0.,length(times))
            end
        end
        models[axis]=P.PSCADModel("remote.pscx",plan.name,list,plan.probes,settings,list.operating_point,(;))
        results[axis]=P.PSCADResult(PSCADRun(),times,channels,plan.probes,settings,(;),(;))
    end
    refs=Dict("C1_Y"=>cat(yd,yd;dims=3),"aggregate_Y"=>cat(aggregate,aggregate;dims=3),
        "direct_Z"=>cat((z*direct_readout(f,spec) for f in spec.frequencies)...;dims=3))
    mktempdir() do directory
        comparison=V.composed_comparison(results,models,refs,directory,spec,c)
        @test all(x["status"]=="passed" for x in values(comparison.comparisons))
        @test all(x["passed"] for x in comparison.kcl)
        base=V.composed_samples(results["baseline"],models["baseline"],spec,c)
        run=V.composed_samples(results["p1_d"],models["p1_d"],spec,c)
        @test norm(run.device_voltages["C1_Y"]-run.voltage)>1e-3
        @test haskey(run.outputs,"C1_Y")
        bad_voltages=Dict(k=>copy(v) for (k,v) in run.device_voltages)
        bad_voltages["C1_Y"][:,1].+=.02V.device_bases(net.elements[:C1].element_model.elec).ac_voltage
        bad=merge(run,(;device_voltages=bad_voltages))
        individual=V.composed_quality(times,base,[bad],spec,c,"C1_Y";columns=[1])
        @test !individual["valid"] && "input_departure_pu" in individual["invalid_reasons"]
        @test V.composed_quality(times,base,[bad],spec,c,"aggregate_Y";columns=[1])["valid"]
    end
end

end

module PSCADM9dAQueueTests
using Test, TOML
module Queue
using TOML
const ROOT=mktempdir()
const calls=String[]
const interrupt=Ref(false)
const deadlines=Float64[]
const protocols_seen=Any[]
RemoteConfig()=nothing
function run_composed(id;remote,deadline,protocols=nothing)
    push!(calls,id);push!(deadlines,deadline);push!(protocols_seen,protocols)
    interrupt[] && throw(InterruptException())
    id in ("L3-01","L3-02") && error("offline fixture failure")
    return Dict("status"=>id=="L3-04" ? "failed" : "passed")
end
include("../manual/pscad/validation/queue.jl")
end
@testset "Stage A queue records failures and continues in frozen order" begin
    for timeout in (0.,-1.,Inf,NaN)
        @test_throws ErrorException Queue.run_m9d_a(;timeout)
    end
    @test isempty(Queue.calls)
    record=@test_logs (:warn,r"Composed fixture failed; continuing queue") Queue.run_m9d_a(timeout=1.)
    @test Queue.calls==["L3-01","L3-08"]
    @test record["outcomes"]["L3-01"]["status"]=="run_or_analysis_failed"
    @test record["outcomes"]["L3-08"]["status"]=="passed"
    @test TOML.parsefile(joinpath(Queue.ROOT,"data","m9d2","queue.toml"))==record
    empty!(Queue.calls);Queue.interrupt[]=true
    @test_throws InterruptException Queue.run_m9d_a(timeout=1.)
    @test Queue.calls==["L3-01"]
    rm(Queue.ROOT;recursive=true)
end
@testset "Stage B queue persists outcomes, continues in order and stops on interrupt" begin
    empty!(Queue.calls);empty!(Queue.deadlines);Queue.interrupt[]=false
    for timeout in (0.,-1.,Inf,NaN)
        @test_throws ErrorException Queue.run_m9d_b(;timeout)
    end
    @test isempty(Queue.calls)
    record=@test_logs (:warn,r"Composed fixture failed; continuing queue") Queue.run_m9d_b(timeout=10.)
    @test Queue.calls==["L3-02","L3-04","L3-03"]
    @test length(unique(Queue.deadlines))==1
    @test record["order"]==Queue.calls
    @test record["outcomes"]["L3-02"]["status"]=="run_or_analysis_failed"
    @test record["outcomes"]["L3-04"]["status"]=="failed"
    @test record["outcomes"]["L3-03"]["status"]=="passed"
    path=joinpath(Queue.ROOT,"data","m9d3","queue.toml")
    @test TOML.parsefile(path)==record
    empty!(Queue.calls);Queue.interrupt[]=true
    @test_throws InterruptException Queue.run_m9d_b(timeout=1.)
    @test Queue.calls==["L3-02"]
    @test TOML.parsefile(path)==record
    rm(Queue.ROOT;recursive=true)
end

@testset "Combined queue starts with the L3-08 local witness only" begin
    empty!(Queue.calls);empty!(Queue.protocols_seen);Queue.interrupt[]=false
    record=@test_logs (:warn,r"Composed fixture failed; continuing queue") Queue.run_m9d_ab(timeout=10.)
    @test Queue.calls==["L3-08","L3-02","L3-04","L3-03"]
    @test Queue.protocols_seen==[["composed_local"],nothing,nothing,nothing]
    @test record["outcomes"]["L3-08"]["status"]=="passed"
    @test record["outcomes"]["L3-02"]["status"]=="run_or_analysis_failed"
    @test record["outcomes"]["L3-03"]["status"]=="passed"
    rm(Queue.ROOT;recursive=true)
end

end

module PSCADComposedInvalidEvidenceTests
using Test, TOML
# Exercise the real group runner up to its invalid-measurement return, with
# local deterministic main results. Any attempted witness execution is an error.
const P=(;PSCADResult=Any,PSCADModel=Any)
const checks=[Dict("passed"=>false,"max_relative_error"=>.01,
    "summary"=>[Dict("port"=>1,"coordinate"=>2,"max_relative_error"=>.01,"failed_rows"=>[1])],
    "rows"=>[Dict("axis"=>"p1_d","port"=>1,"coordinate"=>2,"relative_error"=>.01,"passed"=>false)])]
scan_prefix(spec)="main_"
existing_model(args...;kwargs...)=(;project_path="stored")
function execute_axis!(record,key,args...)
    key in ("main_baseline","main_measurement_p1_d","main_measurement_p1_q") || error("unexpected witness")
    return :stored_result
end
compare_operating_point(args...)=(;within_tolerance=[true])
write_table(args...)=nothing
exported_composed_passives(args...)=nothing
composed_reference_files!(args...;kwargs...)=nothing
interface_step_eligible(args...)=false
composed_frozen_references(args...)=nothing
const seen_resonance_groups=Ref{Any}(nothing)
function composed_comparison(args...;resonance_groups)
    seen_resonance_groups[]=resonance_groups
    return (;comparisons=Dict("aggregate_Y"=>Dict("status"=>"invalid_measurement",
        "invalid_reasons"=>["kcl_readout"])),selection=(;column=1,frequency=7.),kcl=checks)
end
function write_manifest(directory,record)
    open(io->TOML.print(io,record),joinpath(directory,"manifest.toml"),"w")
end
source=read(joinpath(@__DIR__,"../manual/pscad/validation/composed_execution.jl"),String)
first_line=findfirst("function run_composed_group!",source)
last_line=findnext("\nfunction run_composed(",source,last(first_line))
include_string(@__MODULE__,source[first(first_line):first(last_line)-1])
@testset "Invalid composed group persists KCL rows and cause before returning" begin
    mktempdir() do directory
        record=Dict{String,Any}();spec=(;protocol="composed_coarse",axes=["p1_d","p1_q"])
        circuit=(;devices=[:C1],net=(;elements=Dict(:C1=>(;element_model=nothing))))
        group=run_composed_group!(record,circuit,nothing,spec;directory,remote=nothing,deadline=Inf)
        saved=TOML.parsefile(joinpath(directory,"manifest.toml"))["groups"][spec.protocol]
        @test group["status"]=="invalid_measurement"
        @test saved["readout_checks"]==checks
        @test saved["invalid_reasons"]["aggregate_Y"]==["kcl_readout"]
        @test saved["measurand_summary"]["aggregate_Y"]["invalid_reasons"]==["kcl_readout"]
        @test saved["measurand_summary"]["aggregate_Y"]["witness"]=="not_run"
        @test isempty(seen_resonance_groups[])
        local_spec=merge(spec,(;protocol="composed_local",resonance_groups=[collect(1:43)]))
        local_group=run_composed_group!(Dict{String,Any}(),circuit,nothing,local_spec;
            directory,remote=nothing,deadline=Inf)
        @test seen_resonance_groups[]==[collect(1:43)]
        @test local_group["status"]=="invalid_measurement"
    end
end
end

module PSCADCompactWitnessTests
using Test, PowerImpedance, TOML, SHA
include("../manual/pscad/validation/validation.jl")
const V=PSCADValidation
const P=PowerImpedance.PSCAD

@testset "Compact exact-frequency witness labels preserve short evidence names" begin
    for protocol in ("","dq_active","composed_coarse"), fs in ([750.,1000.],[7.,1000.])
        spec=(;protocol,frequencies=fs)
        @test V.step_prefix(spec)==V.scan_prefix(spec)*"half_step_"*join(round.(Int,fs),"_")*"__"
    end
    for (fs,label) in (([collect(232.:1.5:260.5);collect(334.:1.5:361.)],"232_361_n39_0d674b400f77"),
            (collect(357.:.5:378.),"357_378_n43_ec5aa7b9b0a2"))
        spec=(;protocol="composed_local",frequencies=fs)
        @test V.step_prefix(spec)=="composed_local_half_step_"*label*"__"
        changed=copy(fs);changed[2]+=.001
        @test round.(Int,changed)==round.(Int,fs)
        @test V.step_prefix(merge(spec,(;frequencies=changed)))!=V.step_prefix(spec)
        @test V.step_prefix(merge(spec,(;frequencies=copy(fs))))==V.step_prefix(spec)
    end
end

@testset "Preparation bounds station scratch and mapped local paths before writes" begin
    remote=(;remote_root=raw"C:\Users\Amauri\AppData\Local\PowerImpedance\PSCAD\Remote",
        shared_root=raw"Z:\Documents\KUL\PowerImpedance.jl\local\pscad-exchange",
        local_root="/home/amartins/Documents/KUL/PowerImpedance.jl/local/pscad-exchange")
    for id in [V.M9D_A_IDS;V.M9D_B_IDS]
        spec=(;id,frequencies=[1.,7.,750.,1000.],protocol="composed_coarse",axes=["p1_d","p1_q"],
            time_step=2.5e-6,sample_step=62.5e-6,window_duration=8.,window_starts=(16.,24.),simulation_time=32.)
        specs=[spec]
        if id in ("L3-04","L3-08")
            fs=id=="L3-04" ? collect(357.:.5:378.) : [collect(232.:1.5:260.5);collect(334.:1.5:361.)]
            push!(specs,merge(spec,(;protocol="composed_local",frequencies=fs)))
        end
        paths=V.check_prepared_run_paths(id,V.composed_run_axes(specs),remote)
        @test paths["remote"]["length"]==(id in ("L3-04","L3-08") ? 175 : 160)
        @test paths["mapped_local"]["length"]==(id in ("L3-04","L3-08") ? 173 : 158)
        @test paths["local"]["length"]==(id in ("L3-04","L3-08") ? 185 : 170)
        @test all(endswith(item["path"],raw"\run-XXXXXX\toolkit\supervisor.ps1") for item in values(paths))
    end
    axes=["compact_baseline"]
    lengths=V.prepared_run_paths("L3-08",axes,remote)
    for (field,label) in ((:remote_root,"remote"),(:shared_root,"mapped_local"),(:local_root,"local"))
        root=getproperty(remote,field)*repeat("x",240-lengths[label]["length"])
        boundary=merge(remote,NamedTuple{(field,)}((root,)))
        @test V.check_prepared_run_paths("L3-08",axes,boundary)[label]["length"]==240
        too_long=merge(remote,NamedTuple{(field,)}((root*"x",)))
        @test_throws r"exceeds 240 characters" V.check_prepared_run_paths("L3-08",axes,too_long)
        mktempdir() do directory
            spec=merge(V.l1_settings(),(;id="L3-08",dimension=2,protocol="composed_local",
                time_step=2.5e-6,sample_step=62.5e-6,frequencies=[7.,1000.]))
            @test_throws r"exceeds 240 characters" V.prepare_scan_projects(directory,nothing,spec,String[];
                prefix="compact_",remote=merge(too_long,(;remote_root=repeat("x",250))))
            @test isempty(readdir(directory))
        end
    end
end

@testset "Local witness repair archives unused projects and preserves completed evidence" begin
    mktempdir() do directory
        mktempdir() do staging
            old_prefix="composed_local_half_step_"*join(round.(Int,[collect(232.:1.5:260.5);collect(334.:1.5:361.)]),"_")*"__"
            compact=V.step_prefix((;protocol="composed_local",frequencies=[collect(232.:1.5:260.5);collect(334.:1.5:361.)]))
            projects=Dict{String,Any}[];models=Pair{String,P.PSCADModel}[]
            settings=P.SimulationSettings();probes=P.ProbeManifest()
            for axis in ("baseline","p1_d","p1_q")
                old=joinpath(mkpath(joinpath(directory,old_prefix*axis)),"l3_08.pscx")
                write(old,"old local witness $axis")
                push!(projects,Dict("axis"=>old_prefix*axis,"path"=>relpath(old,directory),"sha256"=>V.digest(old)))
                key=compact*axis;path=joinpath(mkpath(joinpath(staging,key)),"l3_08_0d674b400f77.pscx")
                write(path,"compact namespace local witness $axis")
                model=P.PSCADModel(path,"l3_08_0d674b400f77",nothing,probes,settings,nothing,
                    (;source=:validation,mhi_xml_version="offline",baseline_axis=compact*"baseline"))
                push!(models,key=>model)
            end
            retained=joinpath(mkpath(joinpath(directory,"runs","composed_local_p1_d-ABCDEF","run-ABCDEF")),"completed.out")
            write(retained,"completed local main evidence")
            runs=[Dict{String,Any}("axis"=>"composed_coarse_p1_d","status"=>"passed"),
                Dict{String,Any}("axis"=>"composed_local_p1_d","path"=>relpath(retained,directory)),
                Dict{String,Any}("axis"=>"composed_local_half_amplitude_p1_d","status"=>"passed")]
            groups=Dict("composed_coarse"=>Dict("status"=>"passed"),"composed_local"=>Dict("selection"=>Dict("column"=>1)))
            record=Dict{String,Any}("projects"=>projects,"run_records"=>runs,"groups"=>groups,"source_files"=>[Dict("path"=>"old","sha256"=>"old")])
            write(joinpath(directory,"manifest.toml"),sprint(TOML.print,record))
            before=deepcopy(record);payload=V.digest(retained);manifest=V.digest(joinpath(directory,"manifest.toml"))
            push!(record["run_records"],Dict("axis"=>first(projects)["axis"]))
            @test_throws r"run-recorded witness" V.replace_local_witness_projects!(record,directory,models,old_prefix)
            pop!(record["run_records"])
            @test V.digest(joinpath(directory,"manifest.toml"))==manifest
            # A completion missing from the manifest is protected too.
            unindexed=mkpath(joinpath(directory,"runs",first(projects)["axis"]*"-ABCDEF","run-ABCDEF"))
            write(joinpath(unindexed,"complete.toml"),"")
            write(joinpath(unindexed,"generated.pscx"),"old")
            write(joinpath(unindexed,"computation.toml"),sprint(TOML.print,Dict("project_sha256"=>first(projects)["sha256"])))
            @test_throws r"completed witness" V.replace_local_witness_projects!(record,directory,models,old_prefix)
            rm(unindexed;recursive=true)
            V.replace_local_witness_projects!(record,directory,models,old_prefix)
            @test record["run_records"]==before["run_records"]
            @test record["groups"]==before["groups"]
            @test V.digest(retained)==payload
            repair=record["local_witness_repair"]
            @test repair["previous_projects"]==before["projects"]
            @test repair["previous_source_files"]==before["source_files"]
            @test V.digest(joinpath(directory,repair["archive"],"manifest.toml"))==manifest
            for old in before["projects"]
                @test V.digest(joinpath(directory,repair["archive"],old["path"]))==old["sha256"]
                @test !ispath(joinpath(directory,old["path"]))
            end
            @test length(record["projects"])==3
            @test all(startswith(p["axis"],compact) for p in record["projects"])
            @test all(isfile(joinpath(directory,p["path"])) for p in record["projects"])
            @test all(p["sha256"]!=q["sha256"] for p in record["projects"] for q in before["projects"])
        end
    end
end
end
