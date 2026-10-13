digest(path) = bytes2hex(open(sha256, path))

function probe_record(c)
    return Dict("name"=>c.name, "quantity"=>string(c.kind), "bus"=>something(c.bus, ""),
        "element"=>something(c.element, ""), "side"=>something(c.side, ""),
        "components"=>c.dim, "unit"=>c.unit,
        "orientation"=>string(something(c.orientation, :none)))
end

function recorded_probes(channels, reference_bus)
    optional(value) = isempty(value) ? nothing : value
    probes = [P.ProbeChannel(c["name"], Symbol(c["quantity"]), optional(c["bus"]),
                  optional(c["element"]), optional(c["side"]), c["components"], c["unit"],
                  get(c, "orientation", "none") == "none" ? nothing : Symbol(c["orientation"]))
              for c in channels]
    return P.ProbeManifest(probes, reference_bus)
end

# TOML reads empty arrays as Union{}[]. These ledger fields accept appended
# records or declared model differences, both before and after serialization.
function manifest_lists!(record)
    for field in ("run_records", "model_differences", "projects", "harness_revisions")
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
            for (k, f) in enumerate(l1_settings().frequencies) for c in 1:2 for r in 1:2]
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
            "src/Network/Components/AbstractElement.jl", "src/Tools/abcd_parameters.jl",
            "src/Network/Components/impedance/impedance.jl", "src/PSCAD/units.jl", "src/PSCAD/rlc.jl",
            "src/PSCAD/types.jl", "src/PSCAD/plan.jl", "src/PSCAD/emitters/cables.jl",
            "src/PSCAD/emitters/lines.jl", "src/PSCAD/emitters/transformer.jl",
            "src/PSCAD/emitters/machine.jl", "src/PSCAD/emitters/mmc.jl",
            "src/PSCAD/blocks.jl", "src/PSCAD/export.jl", "src/PSCAD/emitters/tlc.jl",
            "src/PSCAD/emitters/sources.jl", "src/PSCAD/emitters/probes.jl",
            "src/PSCAD/emitters/impedance.jl", "ext/PowerImpedancePSCADExt/writer.jl"])
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
        "fixture_version" => 1, "layer" => "L1", "description" => entry.description,
        "parent_fixture" => entry.parent, "topology" => entry.topology, "physics" =>
            entry.physics,
        "stability" => gate, "tiers" => entry.tiers, "estimated_live_nodes" =>
            entry.estimated_nodes,
        "live_node_limit_exclusive" => 100, "julia_version" => string(VERSION),
        "export_commit" => readchomp(`git -C $REPOSITORY rev-parse HEAD`),
        "source_files" => source_record(), "pscad_version_observed" => "not_run",
        "compiler_observed" => "not_run", "model_differences" => entry.differences,
        "status" => "prepared_station_pending", "tier_a_tolerances" => "existing compare_operating_point defaults",
        "tier_b_tolerances" => Dict("rms" => 0.05, "peak" => 0.1, "gain" => 0.05,
            "modal_frequency" => 0.02, "damping" => 0.1),
        "tier_d_tolerances" =>
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

function write_operating_point(path, model)
    rows = NamedTuple[]
    for bus in model.netlist.buses
        point = model.operating_point.bus_states[bus.key]
        push!(rows, (
            owner = bus.name, quantity = "voltage_pu", value = point.vm_pu, unit = "pu"))
        push!(rows, (
            owner = bus.name, quantity = "angle", value = point.va_rad, unit = "rad"))
    end
    for (element, flow) in model.operating_point.branch_flows,
        (quantity, value) in pairs(flow)

        push!(rows,
            (owner = string(element), quantity = string(quantity), value,
                unit =
                startswith(string(quantity), "q") ? "MVAr" : "MW"))
    end
    return write_table(path, rows)
end
