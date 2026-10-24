native_node_limit(id)=fixture(id).category == :system ? 200 : 100

digest(path) = bytes2hex(open(sha256, path))

function probe_record(c)
    return Dict("name"=>c.name, "quantity"=>string(c.kind), "bus"=>something(c.bus, ""),
        "element"=>something(c.element, ""), "side"=>(c.pole === nothing ?
            (c.port === nothing ? "" : string(c.port)) : c.pole),
        "components"=>c.dim, "unit"=>c.unit,
        "orientation"=>string(something(c.orientation, :none)))
end

function recorded_probes(channels, reference_bus)
    optional(value) = isempty(value) ? nothing : value
    probes = [P.ProbeChannel(c["name"], Symbol(c["quantity"]), optional(c["bus"]),
                  optional(c["element"]),
                  c["side"] in ("", "P", "N") ? nothing : Symbol(c["side"]),
                  c["components"], c["unit"],
                  get(c, "orientation", "none") == "none" ? nothing :
                  Symbol(c["orientation"]);
                  pole = c["side"] in ("P", "N") ? c["side"] : nothing)
              for c in channels]
    return P.ProbeManifest(probes, reference_bus)
end

# TOML reads empty arrays as Union{}[]. These fields accept appended records or declared
# model differences, both before and after serialization.
function manifest_lists!(record)
    for field in ("run_records", "model_differences", "projects", "harness_revisions", "native_reference_checks")
        record[field] = Any[get(record, field, Any[])...]
    end
    return record
end

function write_table(path, rows)
    isempty(rows) && throw(ArgumentError("cannot write an empty table"))
    open(path, "w") do io
        println(io, join(string.(keys(first(rows))), '\t'))
        for row in rows
            println(io, join(string.(values(row)), '\t'))
        end
    end
    return path
end

function write_reference(path, reference)
    rows = [(frequency_Hz = f, row = r, column = c,
                real_S = real(reference[r, c, k]), imag_S = imag(reference[r, c, k]))
            for (k, f) in enumerate(passive_settings().frequencies) for c in 1:2 for r in 1:2]
    return write_table(path, rows)
end

function source_record()
    paths = [joinpath("test/manual/pscad/validation", file)
             for file in sort(readdir(ROOT))
             if endswith(file, ".jl") || file == "Project.toml"]
    append!(paths,
        ["test/pscad/fixtures.jl", "test/pscad/ieee9_network.jl",
            "src/Network/Solvers/make_y.jl", "src/Network/Solvers/make_z.jl",
            "src/Network/Components/source/source.jl", "src/Network/Components/transformer/transformer.jl",
            "src/Network/Components/transmission_line/cable.jl", "src/Network/Components/transmission_line/overhead_line.jl",
            "src/Network/Components/transmission_line/blackbox_line.jl",
            "src/Network/Components/AbstractElement.jl", "src/Network/Components/AbstractStateSpace.jl",
            "src/Network/Components/converter/common/kernels/delay.jl",
            "src/Network/Components/converter/common/loops/synchronization.jl",
            "src/PSCAD/PSCAD.jl", "src/Tools/abcd_parameters.jl",
            "src/Network/Components/impedance/impedance.jl", "src/PSCAD/units.jl", "src/PSCAD/rlc.jl",
            "src/PSCAD/types.jl", "src/PSCAD/plan.jl", "src/PSCAD/emitters/cables.jl",
            "src/PSCAD/emitters/lines.jl", "src/PSCAD/emitters/transformer.jl",
            "src/PSCAD/emitters/machine.jl", "src/PSCAD/emitters/mmc.jl",
            "src/PSCAD/emitters/mmc_energy.jl", "src/PSCAD/emitters/converter_common.jl",
            "src/PSCAD/blocks.jl", "src/PSCAD/export.jl", "src/PSCAD/emitters/tlc.jl",
            "src/PSCAD/emitters/sources.jl", "src/PSCAD/emitters/dc_precharge.jl", "src/PSCAD/emitters/probes.jl",
            "src/PSCAD/emitters/impedance.jl", "ext/PowerImpedancePSCADExt/writer.jl"])
    append!(paths, ["src/Network/Components/converter/MMC/" * file for file in
        ("MMC.jl", "electrical.jl", "modulation.jl", "inner_current.jl", "energy.jl")])
    append!(paths, ["test/pscad/networks.jl", "examples/P2P_HVDC_ALT.jl",
            "src/Network/NetworkBuilder/gs_converters.jl", "src/Network/Components/machine/SynchronousMachine.jl"])
    append!(paths, ["src/Network/Components/machine/InductionMachine.jl",
        "src/PSCAD/emitters/induction_machine.jl", "src/Network/NetworkBuilder/model.jl"])
    return [Dict("path" => path, "sha256" => digest(joinpath(REPOSITORY, path)))
            for path in paths]
end

function inventory(directory)
    files = Dict{String, Any}[]
    for (root, _, names) in walkdir(directory), name in sort(names)
        # A manifest cannot contain its own cryptographic hash. Its byte count
        # and digest are printed after writing, outside the indexed payload.
        name == "manifest.toml" && root == directory && continue
        path = joinpath(root, name)
        extension = lowercase(splitext(name)[2])
        role = extension == ".pscx" ? "project" :
               extension in (".out", ".psout", ".inf", ".infx") ?
               "native_output" :
               extension == ".tsv" ? "numerical_evidence" : "provenance_or_resource"
        push!(files,
            Dict("path" => relpath(path, directory), "role" => role,
                "kept" => true, "bytes" => filesize(path), "sha256" => digest(path),
                "producer" =>
                    startswith(relpath(path, directory), "runs") ? "station run" :
                    "local preparation/analysis"))
    end
    return sort!(files; by = file -> file["path"])
end

function write_manifest(directory, record)
    record["files"] = inventory(directory)
    record["kept_payload_bytes"] = sum(file["bytes"] for file in record["files"])
    record["updated_utc"] = string(now(UTC))
    record["manifest_hash_policy"] = "self excluded from inventory; size and SHA256 printed after writing"
    path = joinpath(directory, "manifest.toml")
    open(io -> TOML.print(io, record; sorted = true), path, "w")
    println("Manifest: ", path, " bytes=", filesize(path), " sha256=", digest(path))
    return path
end

function verify_inputs(directory, record)
    for source in record["source_files"]
        digest(joinpath(REPOSITORY, source["path"])) == source["sha256"] ||
            error("source changed since preparation: $(source["path"])")
    end
    for file in record["files"]
        path = joinpath(directory, file["path"])
        isfile(path) && filesize(path) == file["bytes"] && digest(path) == file["sha256"] ||
            error("kept artifact changed: $(file["path"])")
    end
    return nothing
end

function preparation_record(entry, gate, models; directory)
    return manifest_lists!(Dict{String, Any}(
        "schema_version" => 1, "fixture_id" => entry.id,
        "fixture_version" => 1, "category" => string(entry.category), "description" => entry.description,
        "parent_fixture" => entry.parent, "topology" => entry.topology, "physics" =>
            entry.physics,
        "stability" => gate, "measurements" => entry.measurements, "estimated_live_nodes" =>
            entry.estimated_nodes,
        "live_node_limit_exclusive" => native_node_limit(entry.id), "julia_version" => string(VERSION),
        "export_commit" => readchomp(`git -C $REPOSITORY rev-parse HEAD`),
        "source_files" => source_record(), "pscad_version_observed" => "not_run",
        "compiler_observed" => "not_run", "model_differences" => entry.differences,
        "status" => "prepared_station_pending", "operating_point_tolerances" => "existing compare_operating_point defaults",
        "time_domain_tolerances" => Dict("rms" => 0.05, "peak" => 0.1, "gain" => 0.05,
            "modal_frequency" => 0.02, "damping" => 0.1),
        "growth_tolerances" =>
            Dict("frequency" => 0.02, "growth" => 0.1, "growth_floor_per_s" => 0.5),
        "projects" =>
            [Dict("axis" => axis, "path" => relpath(model.project_path, directory),
                 "sha256" => digest(model.project_path), "settings" =>
                     P._settings_record(model.settings),
                 "mhi_xml_version" => model.provenance.mhi_xml_version,
                 "baseline_axis" => model.provenance.baseline_axis,
                 "probes" => probe_record.(model.probes.channels))
             for (axis, model) in models],
        "environment_project_sha256" => digest(Base.active_project()),
        "environment_manifest_sha256" =>
            isfile(joinpath(dirname(Base.active_project()), "Manifest.toml")) ?
            digest(joinpath(dirname(Base.active_project()), "Manifest.toml")) : "absent",
        "run_records" => Dict{String, Any}[],
        "retention" => "all generated payload kept; commit decision deferred until measured sizes"))
end

function operating_point_rows(list)
    rows = NamedTuple[]
    for bus in list.buses
        point = list.operating_point.bus_states[bus.key]
        push!(rows, (
            owner = bus.name, quantity = "voltage_pu", value = point.vm_pu, unit = "pu"))
        push!(rows, (
            owner = bus.name, quantity = "angle", value = point.va_rad, unit = "rad"))
    end
    for (element, flow) in list.operating_point.branch_flows,
        (quantity, value) in pairs(flow)

        push!(rows,
            (owner = string(element), quantity = string(quantity), value,
                unit =
                quantity == :speed_pu ? "pu" : startswith(string(quantity), "q") ? "MVAr" : "MW"))
    end
    return rows
end

write_operating_point(path, model) = write_table(path, operating_point_rows(model.netlist))

# NonlinearSolve uses 1e-6 absolute/relative residual tolerances, which do not imply a
# uniform forward-admittance bound for ill-conditioned realisations. The separate
# reference comparison requires the actual difference within one ppm on declared pu
# bases/floors, or stops. Passive/active response tolerances are 20,000/50,000 times
# larger and use the frozen file. The reference limit is independent of measured
# discrepancies.
const NATIVE_REFERENCE_LIMIT = 1e-6

function native_reference_check(spec, recomputed, frozen)
    size(recomputed)==size(frozen) || throw(ArgumentError("native reference dimensions changed"))
    size(frozen,3)==length(spec.frequencies) || throw(ArgumentError("native reference frequency count changed"))
    all(isfinite,recomputed) && all(isfinite,frozen) ||
        throw(ArgumentError("non-finite native reference"))
    actual=scale_response(recomputed,spec);expected=scale_response(frozen,spec)
    delta=actual-expected
    entries=abs.(delta)./max.(abs.(expected),0.02)
    frobenius=[norm(delta[:,:,k])/max(norm(expected[:,:,k]),0.1) for k in eachindex(spec.frequencies)]
    worst=argmax(entries)
    return Dict{String,Any}("passed"=>maximum(entries)<=NATIVE_REFERENCE_LIMIT && maximum(frobenius)<=NATIVE_REFERENCE_LIMIT,
        "limit"=>NATIVE_REFERENCE_LIMIT,"entry_floor_pu"=>0.02,"frobenius_floor_pu"=>0.1,
        "max_entry_scaled_error"=>maximum(entries),"max_frobenius_scaled_error"=>maximum(frobenius),
        "max_absolute_pu"=>maximum(abs,delta),"max_absolute_SI"=>maximum(abs,recomputed-frozen),
        "SI_unit"=>spec.quantity=="Y" ? "S" : spec.quantity=="Z" ? "ohm" : "1",
        "max_relative_nonzero_entry_error"=>maximum(abs(recomputed[i]-frozen[i])/abs(frozen[i])
            for i in eachindex(frozen) if !iszero(frozen[i]);init=0.0),
        "worst_frequency_Hz"=>spec.frequencies[worst[3]],"worst_row"=>worst[1],"worst_column"=>worst[2],
        "per_frequency"=>[Dict("frequency_Hz"=>f,"max_entry_scaled_error"=>maximum(entries[:,:,k]),
            "frobenius_scaled_error"=>frobenius[k],"max_absolute_SI"=>maximum(abs,recomputed[:,:,k]-frozen[:,:,k]))
            for (k,f) in enumerate(spec.frequencies)],
        "bound_scope"=>"enforced actual forward discrepancy; solver residual convergence alone gives no universal forward-error guarantee",
        "authority"=>"frozen prepared reference; C tolerances and reference bytes unchanged")
end

function native_operating_point_check(list, path)
    frozen=Dict((r[1],r[2])=>(value=r[3],unit=r[4])
        for r in split.(readlines(path)[2:end],'\t'))
    actual=Dict((r.owner,r.quantity)=>(value=string(r.value),unit=r.unit) for r in operating_point_rows(list))
    keys(actual)==keys(frozen) || throw(ArgumentError("native operating-point rows changed"))
    rows=Dict{String,Any}[]
    for key in sort!(collect(keys(frozen)))
        old,new=frozen[key],actual[key]
        old.unit==new.unit || throw(ArgumentError("native operating-point units changed"))
        old_value,new_value=tryparse(Float64,old.value),tryparse(Float64,new.value)
        if old_value===nothing || new_value===nothing
            old.value==new.value || throw(ArgumentError("native operating-point missing value changed"))
            continue
        end
        # PF uses 1000 MVA globally and constr_viol_tol=1e-5. This is an
        # enforced point-identity budget, not an inverse-Jacobian error theorem.
        base=old.unit in ("MW","MVAr") ? 1000.0 : max(abs(old_value),1.0)
        difference=abs(new_value-old_value)
        push!(rows,Dict("owner"=>key[1],"quantity"=>key[2],"unit"=>old.unit,
            "frozen"=>old_value,"recomputed"=>new_value,"absolute_difference"=>difference,
            "scaled_difference"=>difference/base))
    end
    maximum_difference=maximum(r["scaled_difference"] for r in rows;init=0.0)
    return Dict("passed"=>maximum_difference<=1e-5,"limit"=>1e-5,
        "power_base_MVA"=>1000.0,"max_scaled_difference"=>maximum_difference,"rows"=>rows)
end

function record_native_reference!(record, directory, spec, recomputed, frozen, list;
        purpose="station recomputation")
    check=native_reference_check(spec,recomputed,frozen)
    check["operating_point"]=native_operating_point_check(list,joinpath(directory,"operating_point.tsv"))
    check["passed"] &= check["operating_point"]["passed"]
    check["purpose"]=purpose
    check["julia_version"]=string(VERSION)
    check["recorded_utc"]=string(now(UTC))
    check["reference_file"]=reference_filename(spec)
    check["frozen_sha256"]=digest(joinpath(directory,reference_filename(spec)))
    check["status"]=check["passed"] ? "passed" : "native_reference_outside_solver_scale_budget"
    manifest_lists!(record)
    push!(record["native_reference_checks"],check)
    write_manifest(directory,record)
    check["passed"] || error("native reference changed beyond solver-scale guard: entry=$(check["max_entry_scaled_error"]), Frobenius=$(check["max_frobenius_scaled_error"]), limit=$(check["limit"]); see native_reference_checks in manifest")
    return check
end
