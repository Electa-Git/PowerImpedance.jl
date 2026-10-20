const MMC_SAMPLING_IDS = ["mmc_pq", "mmc_pf_q", "mmc_p_qv", "mmc_p_vac", "mmc_vdc_q", "mmc_pq_weak_grid", "mmc_gfm_vsm", "mmc_gfm_lec_compensated", "mmc_pq_no_energy_control"]
const TLC_FINE_STEP_DIRECTORY = joinpath(ROOT, "data", "tlc_pq_freq_support_1p25us")

# Local preparation archives complete fixture trees. Recorded runs and the retained 2.5 us
# TLC measurements remain unchanged.
function prepare_converter_sampling()
    archive = mkpath(joinpath(ROOT, "data", "archive", "converter_sampling"))
    for id in MMC_SAMPLING_IDS
        directory = joinpath(ROOT, "data", id)
        destination = joinpath(archive, id)
        ispath(destination) && error("archive already exists: $destination")
        prior = TOML.parsefile(joinpath(directory, "manifest.toml"))
        definition = deepcopy(prior["frequency_response"])
        if id in ("mmc_pq", "mmc_pf_q", "mmc_p_qv", "mmc_p_vac")
            settling = gfl_settling(prior["stability"]; fixture_id = id, tone_peak_pu = definition["tone_peak_pu"])
            definition["window_starts"] = settling["window_starts_s"]
            definition["simulation_time"] = settling["simulation_time_s"]
            definition["estimated_station_seconds"] = 3300
            definition["settling"] = settling
        end
        mv(directory, destination)
        mkpath(directory)
        for file in ("dq_active_reference.tsv", "operating_point.tsv")
            cp(joinpath(destination, file), joinpath(directory, file))
        end
        models = prepare_fixture(id; directory, definition)
        record = TOML.parsefile(joinpath(directory, "manifest.toml"))
        old_reference = read_response(joinpath(destination, "dq_active_reference.tsv"),
            length(definition["axes"]), definition["frequencies"])
        new_reference = read_response(joinpath(directory, "dq_active_reference.tsv"),
            length(definition["axes"]), definition["frequencies"])
        preservation_spec = (; quantity = "Y", voltage_bases = definition["voltage_bases_kV"],
            current_bases = definition["current_bases_kA"], frequencies = definition["frequencies"])
        native_reference_check(preservation_spec, new_reference, old_reference)["passed"] ||
            error("native reference changed: $id")
        record["archive_directory"] = relpath(destination, ROOT)
        write_manifest(directory, record)
        isempty(record["run_records"]) || error("fresh preparation inherited runs")
    end
    ispath(TLC_FINE_STEP_DIRECTORY) && error("fine-step TLC directory already exists")
    definition = deepcopy(TOML.parsefile(joinpath(ROOT, "data", "tlc_pq_freq_support", "manifest.toml"))["frequency_response"])
    definition["time_step"] = 1.25e-6
    definition["estimated_station_seconds"] = 2700
    mkpath(TLC_FINE_STEP_DIRECTORY)
    for file in ("dq_active_reference.tsv", "operating_point.tsv")
        cp(joinpath(ROOT, "data", "tlc_pq_freq_support", file), joinpath(TLC_FINE_STEP_DIRECTORY, file))
    end
    prepare_fixture("tlc_pq_freq_support"; directory = TLC_FINE_STEP_DIRECTORY, definition)
    record = TOML.parsefile(joinpath(TLC_FINE_STEP_DIRECTORY, "manifest.toml"))
    record["variant"] = "tlc_pq_freq_support: 1.25 us base / 0.625 us witness; original 2.5 us evidence retained"
    write_manifest(TLC_FINE_STEP_DIRECTORY, record)
    model, directory = prepare_timing()
    return (; archive, timing = directory, tlc = TLC_FINE_STEP_DIRECTORY, fixtures = copy(MMC_SAMPLING_IDS))
end

# Only the manual station command calls this function. An interrupted queue resumes
# matching completed runs through the native hash checks.
function run_converter_sampling(; remote = RemoteConfig(), timeout = 43200.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    deadline = time() + timeout
    run_timing(remote, deadline)
    run_fixture("tlc_vdc_q"; remote, deadline)
    run_fixture("tlc_pq_freq_support"; remote, directory = TLC_FINE_STEP_DIRECTORY, deadline)
    for id in MMC_SAMPLING_IDS
        run_fixture(id; remote, deadline)
    end
    return nothing
end

# The acceptance script performs fresh exports and station runs. Its command is separate
# from inclusion; loading the harness never contacts the station.
function converter_acceptance_command()
    project = Base.active_project()
    project === nothing && error("converter acceptance requires an active Julia project")
    script = joinpath(REPOSITORY, "test", "manual", "pscad", "acceptance.jl")
    return `$(Base.julia_cmd()) --project=$(dirname(project)) $script --converters`
end

# Converter measurements resume matching runs; acceptance starts fresh runs afterward.
# Per-run timeouts come from station configuration, independently of the
# converter-measurement deadline.
function run_converter_sampling_acceptance(; timeout = 43200.0)
    run_converter_sampling(; timeout)
    run(converter_acceptance_command())
    return nothing
end

# This queue resumes only MMC measurements, then starts converter acceptance with fresh
# runs. Timing and TLC measurements are separate from this queue.
function run_mmc_acceptance(; timeout = 43200.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    deadline = time() + timeout
    remote = RemoteConfig()
    for id in MMC_SAMPLING_IDS
        run_fixture(id; remote, deadline)
    end
    run(converter_acceptance_command())
    return nothing
end

# Catch fixture failures outside run_fixture's inner analysis try block too
# (input verification, reconstruction and stability can fail before that block).
function run_fixture_continuing(id; directory = joinpath(ROOT, "data", id),
        remote, deadline)
    try
        return run_fixture(id; directory, remote, deadline)
    catch failure
        failure isa InterruptException && rethrow()
        record = manifest_lists!(TOML.parsefile(joinpath(directory, "manifest.toml")))
        record["status"] = "run_or_analysis_failed"
        record["failure"] = sprint(showerror, failure)
        write_manifest(directory, record)
        @warn "Fixture failed; continuing queue" fixture = id error = record["failure"]
        return record
    end
end

# Acceptance is deliberately first; its own native runs remain fresh.
function run_converter_settling_acceptance(; timeout = 43200.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    acceptance_directory = mkpath(joinpath(ROOT, "data", "converter_settling_acceptance"))
    acceptance = Dict{String, Any}("status" => "completed")
    try
        run(converter_acceptance_command())
    catch failure
        failure isa InterruptException && rethrow()
        acceptance["status"] = "run_or_analysis_failed"
        acceptance["failure"] = sprint(showerror, failure)
        @warn "Converter acceptance failed; continuing queue" error = acceptance["failure"]
    end
    open(io -> TOML.print(io, acceptance), joinpath(acceptance_directory, "acceptance.toml"), "w")
    remote = RemoteConfig()
    deadline = time() + timeout
    for id in ["mmc_vdc_q", "mmc_pq_weak_grid", "mmc_gfm_vsm", "mmc_gfm_lec_compensated", "mmc_pq_no_energy_control"]
        run_fixture_continuing(id; remote, deadline)
    end
    run_settling_experiment(; remote, deadline)
    return nothing
end

# Local preparation only; retained station records remain in complete trees.
function prepare_machine_timing_settling()
    machine = joinpath(ROOT, "data", "synchronous_machine")
    archive = joinpath(ROOT, "data", "archive", "machine_timing_settling", "synchronous_machine")
    timing = joinpath(ROOT, "data", "machine_timing_settling", "timing")
    ispath(archive) && error("archive already exists: $archive")
    ispath(timing) && error("timing witness already prepared: $timing")
    prior = TOML.parsefile(joinpath(machine, "manifest.toml"))
    prepare_settling_experiment()
    prepare_timing(timing)
    definition = deepcopy(prior["frequency_response"])
    definition["time_step"] = 1.25e-6
    definition["estimated_station_seconds"] = 9000
    mkpath(dirname(archive))
    mv(machine, archive)
    mkpath(machine)
    for file in ("dq_active_reference.tsv", "operating_point.tsv")
        cp(joinpath(archive, file), joinpath(machine, file))
    end
    prepare_fixture("synchronous_machine"; directory = machine, definition)
    record = TOML.parsefile(joinpath(machine, "manifest.toml"))
    record["archive_directory"] = relpath(archive, ROOT)
    record["variant"] = "1.25 us base / 0.625 us witness; 2.5 us evidence archived"
    write_manifest(machine, record)
    return nothing
end

# Each outcome is saved before advancing. Native completion/hash verification
# provides resumption; failed items are retried on the next invocation.
function run_machine_timing_settling(; timeout = 14400.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    directory = mkpath(joinpath(ROOT, "data", "machine_timing_settling"))
    record = Dict{String, Any}()
    remote = RemoteConfig()
    deadline = time() + timeout
    try
        result = run_settling_experiment(; remote, deadline)
        record["settling"] = Dict("status" => result["status"])
        haskey(result, "failure") && (record["settling"]["failure"] = result["failure"])
    catch failure
        failure isa InterruptException && rethrow()
        record["settling"] = Dict("status" => "run_or_analysis_failed",
            "failure" => sprint(showerror, failure))
        @warn "Settling experiment failed; continuing queue" error = record["settling"]["failure"]
    end
    write_manifest(directory, record)
    try
        run_timing(remote, deadline; directory = joinpath(directory, "timing"))
        record["timing"] = Dict("status" => "passed")
    catch failure
        failure isa InterruptException && rethrow()
        record["timing"] = Dict("status" => "run_or_analysis_failed",
            "failure" => sprint(showerror, failure))
        @warn "Timing witness failed; continuing queue" error = record["timing"]["failure"]
    end
    write_manifest(directory, record)
    result = run_fixture_continuing("synchronous_machine"; remote, deadline)
    record["synchronous_machine"] = Dict("status" => result["status"])
    haskey(result, "failure") && (record["synchronous_machine"]["failure"] = result["failure"])
    write_manifest(directory, record)
    return record
end

const MMC_STEP_REFINEMENT_IDS = ["mmc_pq", "mmc_pf_q", "mmc_p_qv", "mmc_p_vac", "mmc_pq_weak_grid",
    "mmc_gfm_vsm", "mmc_pq_no_energy_control", "mmc_vdc_q", "mmc_gfm_lec_compensated"]

# Fresh local exports only; complete retained trees keep their source and input records.
function prepare_mmc_step_refinement()
    revision = readchomp(`git -C $REPOSITORY rev-parse HEAD`)
    revision == "adbf8c2e9f43eccef3d82fa37756fe942d677a93" ||
        error("step-refinement preparation requires adbf8c2")
    archive = joinpath(ROOT, "data", "archive", "mmc_step_refinement")
    for id in MMC_STEP_REFINEMENT_IDS
        ispath(joinpath(archive, id)) && error("archive already exists: $id")
        isfile(joinpath(ROOT, "data", id, "manifest.toml")) || error("missing fixture: $id")
    end
    mkpath(archive)
    for id in MMC_STEP_REFINEMENT_IDS
        directory = joinpath(ROOT, "data", id)
        destination = joinpath(archive, id)
        prior = TOML.parsefile(joinpath(directory, "manifest.toml"))
        definition = deepcopy(prior["frequency_response"])
        definition["sample_step"] = 25 * definition["time_step"]
        mv(directory, destination)
        prepare_fixture(id; directory, definition)
        record = TOML.parsefile(joinpath(directory, "manifest.toml"))
        net = fixture(id).factory()
        list = fixture_netlist(net, power_flow(net))
        spec, reference = applicable_scan(id, net, list; definition)
        old_reference = read_response(joinpath(destination, reference_filename(spec)),
            length(spec.axes), spec.frequencies)
        native_reference_check(spec, reference, old_reference)["passed"] ||
            error("native reference changed: $id")
        # Prepared adaptive bands retain fresh projects; each measurement selects its own
        # worst axis and frequency.
        if haskey(prior, "step_witness_definition")
            witness = step_definition(spec, first(prior["step_witness_definition"]["frequencies"]))
            prefix = step_prefix(witness)
            if !any(startswith(project["axis"], prefix) for project in record["projects"])
                for (axis, model) in prepare_scan_projects(directory, list, witness, spec.axes; prefix)
                    record_project!(record, axis, model, directory)
                end
            end
        end
        record["archive_directory"] = relpath(destination, ROOT)
        record["recorder_ratio"] = check_recorder_sampling(spec)
        record["preparation_purpose"] = "step-refinement odd recorder ratio; fresh native runs required"
        isempty(record["run_records"]) || error("fresh preparation inherited runs")
        write_manifest(directory, record)
    end
    return copy(MMC_STEP_REFINEMENT_IDS)
end

# Each outcome is saved before continuing. Native completion/hash checks verify completed
# runs for resumption.
function run_mmc_step_refinement(; timeout = 36000.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    directory = mkpath(joinpath(ROOT, "data", "mmc_step_refinement"))
    record = Dict{String, Any}()
    remote = RemoteConfig()
    deadline = time() + timeout
    for id in MMC_STEP_REFINEMENT_IDS
        result = run_fixture_continuing(id; remote, deadline)
        record[id] = Dict("status" => result["status"])
        haskey(result, "failure") && (record[id]["failure"] = result["failure"])
        write_manifest(directory, record)
    end
    return record
end

const MMC_COHERENT_WINDOW_IDS = ["mmc_pq", "mmc_pf_q", "mmc_p_qv", "mmc_p_vac", "mmc_vdc_q", "mmc_pq_weak_grid"]

# One predeclared window change; complete retained trees remain read-only records.
function prepare_mmc_coherent_windows()
    revision = readchomp(`git -C $REPOSITORY rev-parse --short=7 HEAD`)
    revision == "635ef92" || error("coherent-window preparation requires 635ef92")
    archive = joinpath(ROOT, "data", "archive", "mmc_coherent_windows")
    for id in MMC_COHERENT_WINDOW_IDS
        ispath(joinpath(archive, id)) && error("archive already exists: $id")
        isfile(joinpath(ROOT, "data", id, "manifest.toml")) || error("missing fixture: $id")
    end
    mkpath(archive)
    for id in MMC_COHERENT_WINDOW_IDS
        directory = joinpath(ROOT, "data", id)
        destination = joinpath(archive, id)
        prior = TOML.parsefile(joinpath(directory, "manifest.toml"))
        definition = deepcopy(prior["frequency_response"])
        start = first(definition["window_starts"])
        definition["window_duration"] = 8.0
        definition["window_starts"] = [start, start + 8.0]
        definition["simulation_time"] = start + 16.0
        definition["estimated_station_seconds"] = id == "mmc_vdc_q" ? 2280 : id == "mmc_pq_weak_grid" ? 1140 : 1680
        if haskey(definition, "settling")
            definition["settling"]["window_starts_s"] = definition["window_starts"]
            definition["settling"]["window_duration_s"] = 8.0
            definition["settling"]["simulation_time_s"] = definition["simulation_time"]
        end
        net = fixture(id).factory()
        residual_step_eligible(id, net) || error("coherent-window requires a zero-delay fixture: $id")
        list = fixture_netlist(net, power_flow(net))
        spec, reference = applicable_scan(id, net, list; definition)
        check_recorder_sampling(spec) == 25 || error("coherent-window requires recorder ratio 25")
        mv(directory, destination)
        prepare_fixture(id; directory, definition)
        record = TOML.parsefile(joinpath(directory, "manifest.toml"))
        old_reference = read_response(joinpath(destination, reference_filename(spec)),
            length(spec.axes), spec.frequencies)
        native_reference_check(spec, reference, old_reference)["passed"] ||
            error("native reference changed: $id")
        # All prepared comparison bands remain available, without reusing measured
        # axis/band selections or native completions.
        for project in prior["projects"]
            band = match(r"half_step_(\d+)_1000__baseline$", project["axis"])
            band === nothing && continue
            witness = step_definition(spec, parse(Float64, only(band.captures)))
            prefix = step_prefix(witness)
            if !any(startswith(project["axis"], prefix) for project in record["projects"])
                for (axis, model) in prepare_scan_projects(directory, list, witness, spec.axes; prefix)
                    record_project!(record, axis, model, directory)
                end
            end
        end
        record["archive_directory"] = relpath(destination, ROOT)
        record["recorder_ratio"] = check_recorder_sampling(spec)
        record["preparation_purpose"] = "coherent-window predeclared 8 s main windows; fresh native runs required; no further window changes after results"
        isempty(record["run_records"]) || error("fresh preparation inherited runs")
        write_manifest(directory, record)
    end
    return copy(MMC_COHERENT_WINDOW_IDS)
end

# The fixture runner performs residual comparisons and verifies retained runs for
# resumption.
function run_mmc_coherent_windows(; timeout = 14400.0)
    isfinite(timeout) && timeout > 0 || error("timeout must be finite and positive")
    directory = mkpath(joinpath(ROOT, "data", "mmc_coherent_windows"))
    record = Dict{String, Any}()
    remote = RemoteConfig()
    deadline = time() + timeout
    for id in MMC_COHERENT_WINDOW_IDS
        result = run_fixture_continuing(id; remote, deadline)
        record[id] = Dict("status" => result["status"])
        haskey(result, "failure") && (record[id]["failure"] = result["failure"])
        write_manifest(directory, record)
    end
    return record
end

const SHARED_BUS_SHUNT_IDS = ["two_tlc_shared_bus", "mmc_rc_shunt"]

const COUPLED_LINE_CONVERTER_IDS = ["two_mmc_shared_bus", "mmc_pi_line", "mmc_gfm_gfl_shared_bus"]
const MACHINE_DC_COUPLING_IDS = ["two_mmc_dc_cable", "machine_mmc_shared_bus"]

function run_composed_queue(ids,queue_name;timeout,remote,local_witness_first=false)
    isfinite(timeout)&&timeout>0 || error("timeout must be finite and positive")
    deadline=time()+timeout;directory=mkpath(joinpath(ROOT,"data",queue_name))
    path=joinpath(directory,"queue.toml")
    record=isfile(path) ? TOML.parsefile(path) : Dict{String,Any}("order"=>copy(ids),"outcomes"=>Dict{String,Any}())
    record["order"]==ids || error("composed queue order changed")
    for id in ids
        try
            result=local_witness_first && id=="mmc_rc_shunt" ?
                run_composed(id;remote,deadline,protocols=["composed_local"]) : run_composed(id;remote,deadline)
            record["outcomes"][id]=Dict("status"=>result["status"])
        catch failure
            failure isa InterruptException && rethrow()
            record["outcomes"][id]=Dict("status"=>"run_or_analysis_failed","failure"=>sprint(showerror,failure))
            @warn "Composed fixture failed; continuing queue" fixture=id reason=sprint(showerror,failure)
        end
        open(io->TOML.print(io,record;sorted=true),path,"w")
    end
    return record
end

function run_shared_bus_shunt(;timeout=10800.,remote=RemoteConfig())
    return run_composed_queue(SHARED_BUS_SHUNT_IDS,"shared_bus_shunt_queue";timeout,remote)
end

function run_coupled_line_converter(;timeout=14400.,remote=RemoteConfig())
    return run_composed_queue(COUPLED_LINE_CONVERTER_IDS,"coupled_line_converter_queue";timeout,remote)
end

function run_coupled_local_witness(;timeout=18000.,remote=RemoteConfig())
    return run_composed_queue(["mmc_rc_shunt";COUPLED_LINE_CONVERTER_IDS],"coupled_local_witness_queue";timeout,remote,local_witness_first=true)
end

function run_machine_dc_coupling(;timeout=28800.,remote=RemoteConfig())
    return run_composed_queue(MACHINE_DC_COUPLING_IDS,"machine_dc_coupling_queue";timeout,remote)
end
