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
    @test length(V.REGISTRY) == 25
    @test length(unique(entry.id for entry in V.REGISTRY)) == 25
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
