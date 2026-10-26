const LINE_CHAIN_IDS = ("ac_ohl_untransposed", "ac_cable_coaxial", "dc_cable_ohl", "ieee9_bus_impedance", "two_mmc_dc_cable")

"""
$(TYPEDSIGNATURES)

Re-evaluate retained PSCAD response matrices against line and cable references.
Retain recorded measurement bases, quality flags, integration-step comparisons
and acceptance tolerances. Stored native runs and source manifests remain unchanged.
Record source and input hashes because the analysing files can differ from the
recorded revision.

# Arguments

- `ids`: Fixture identifiers. Default: `LINE_CHAIN_IDS`.
- `data_root`: Directory containing the stored fixture records.
- `output_root`: Separate destination for comparisons and file hashes, restricted
  to this worktree's `data/line_chain_analysis` or `/tmp`.
  Default: `joinpath(ROOT, "data", "line_chain_analysis")`.

# Returns

- Dictionary of fixture analyses with stored and recalculated maximum scaled
  errors. Incomplete measurements are pending. Native execution and stability
  evaluation are separate from these comparisons.
"""
function reanalyse_line_chain(ids = LINE_CHAIN_IDS; data_root,
        output_root = joinpath(ROOT, "data", "line_chain_analysis"))
    selected = ids isa AbstractString ? [ids] : collect(ids)
    !isempty(selected) && all(in(LINE_CHAIN_IDS), selected) || error("unknown line-chain fixture")
    # Resolve existing ancestors as well as the leaf: a symlink must not turn
    # an apparently local output into a write to the stored evidence directory.
    function resolved(path)
        path = abspath(path)
        ancestor = path
        while !ispath(ancestor)
            ancestor = dirname(ancestor)
        end
        return normpath(joinpath(realpath(ancestor), relpath(path, ancestor)))
    end
    inside(path, root) = path == root || startswith(path, root * "/")
    destination = resolved(output_root)
    allowed = (joinpath(realpath(ROOT), "data", "line_chain_analysis"), realpath("/tmp"))
    any(root -> inside(destination, root), allowed) || error("analysis output must be under worktree data/line_chain_analysis or /tmp")
    evidence = realpath(data_root)
    (inside(destination, evidence) || inside(evidence, destination)) && error("output overlaps stored evidence")
    outcomes = Dict{String, Any}()
    for id in selected
        directory = joinpath(evidence, id)
        output = resolved(joinpath(destination, id))
        any(root -> inside(output, root), allowed) && !inside(output, evidence) || error("analysis output escapes its allowed directory")
        manifest = joinpath(directory, "manifest.toml")
        manifest_text = read(manifest, String)
        manifest_hash = bytes2hex(sha256(manifest_text))
        original = TOML.parse(manifest_text)
        original["fixture_id"] == id || error("stored fixture identity differs")
        inputs = Dict{String, String}[]
        function retained(path)
            relative = relpath(path, directory)
            saved = only(filter(file -> file["path"] == relative, original["files"]))
            hash = digest(path)
            hash == saved["sha256"] || error("retained evidence changed: $relative")
            push!(inputs, Dict("path" => abspath(path), "sha256" => hash))
            return path
        end
        analysis = Dict{String, Any}("fixture_id" => id,
            "analysis_revision" => Dict("commit" => readchomp(`git -C $REPOSITORY rev-parse HEAD`),
                "julia_version" => string(VERSION), "source_files" => source_record(),
                "source_manifest" => manifest, "source_manifest_sha256" => manifest_hash),
            "analysis_inputs" => inputs, "measurement_policy" => "retained SI matrices, recorded bases and quality flags; witnesses unchanged",
            "scope" => "reference comparison only; native qualification and stability not re-evaluated")
        mkpath(output)
        write(joinpath(output, "source_manifest.toml"), manifest_text)
        net = fixture(id).factory()
        list = fixture_netlist(net, compute(PowerFlowProblem(net), ACDCPowerFlow()))
        targets = Dict{String, Any}()
        if id == "two_mmc_dc_cable"
            c = coupled_circuit(id, net)
            spec = coupled_spec(id, list)
            definition = original["measurement_groups"][spec.protocol]
            spec = merge(spec, (; voltage_bases = Float64.(definition["voltage_bases_kV"]),
                current_bases = Float64.(definition["current_bases_kA"]),
                time_step = Float64(definition["time_step"])))
            group = get(get(original, "groups", Dict()), spec.protocol, Dict())
            if !haskey(group, "plain")
                analysis["status"] = "pending stored coarse response matrices"
            else
                baseline = only(filter(project -> project["axis"] == scan_prefix(spec)*"baseline", original["projects"]))
                project = retained(joinpath(directory, baseline["path"]))
                forms = exported_composed_passives(c, project, list)
                for label in ("plain", "discrete")
                    haskey(group, label) || continue
                    refs = composed_reference(c, spec; time_step = label == "plain" ? nothing : spec.time_step,
                        forms = label == "plain" ? nothing : forms)
                    if label == "discrete"
                        for target in ["direct_Z"; filter(t -> startswith(t, "DC_"), collect(keys(refs)))], (k, f) in enumerate(spec.frequencies)
                            refs[target][:, :, k] .*= injection_readout_factor(f, spec)
                        end
                    end
                    for (target, reference) in refs
                        ts = composed_target_spec(spec, c, target)
                        frozen_path = joinpath(directory, scan_prefix(spec)*label*"_"*target*"_reference.tsv")
                        measured_path = joinpath(directory, "analysis", spec.protocol, label, target*"_measured.tsv")
                        quality = group[label][target]
                        indices = startswith(target, "DC_") ? [1, 2] : composed_score_indices(c, target)
                        columns = startswith(target, "DC_") ? collect(eachindex(spec.axes)) : indices
                        targets[label*"_"*target] = (; spec = ts, reference, frozen_path, measured_path, quality, indices, columns)
                    end
                end
            end
        else
            spec, reference = applicable_scan(id, net, list; definition = original["frequency_response"])
            measured_path = joinpath(directory, "analysis", spec.protocol,
                spec.quantity == "Y" ? "measured_S.tsv" : "measured_ohm.tsv")
            targets["response"] = (; spec, reference,
                frozen_path = joinpath(directory, reference_filename(spec)), measured_path,
                quality = original["frequency_response_result"], indices = collect(eachindex(spec.axes)), columns = collect(eachindex(spec.axes)))
        end
        comparisons = Dict{String, Any}()
        for (target, data) in targets
            spec, reference, quality = data.spec, data.reference, data.quality
            n = length(spec.axes)
            measured = read_response(retained(data.measured_path), n, spec.frequencies; rows = size(reference, 1))
            frozen = read_response(retained(data.frozen_path), n, spec.frequencies; rows = size(reference, 1))
            rows = Dict(label => response_rows(spec,
                scale_response(measured, spec)[data.indices, data.columns, :],
                scale_response(ref, spec)[data.indices, data.columns, :];
                active = get(spec, :active, false), valid = quality["valid"],
                model_mismatch = quality["model_mismatch"]) for (label, ref) in (("old", frozen), ("new", reference)))
            for (label, entries) in rows
                write_table(joinpath(output, target*"_"*label*"_frequency_response.tsv"), entries)
            end
            write_response(joinpath(output, target*"_reference.tsv"), reference, spec.frequencies; quantity = spec.quantity)
            comparisons[target] = Dict("retained_quality" => quality,
                "reference_change" => native_reference_check(spec, reference, frozen),
                "max_errors" => Dict(label => Dict(
                    "frobenius" => maximum(row.frobenius_error for row in entries),
                    "entry" => maximum(row.complex_error_pu / max(abs(complex(row.reference_real_pu, row.reference_imag_pu)), 0.02) for row in entries),
                    "all_entries_within_tolerance" => all(row.within_tolerance for row in entries))
                    for (label, entries) in rows))
        end
        analysis["comparisons"] = comparisons
        isempty(comparisons) || (analysis["status"] = "analysed retained measurements")
        # Verify every consumed file again before publishing an analysis.
        # A running queue may append new runs to the original manifest. The
        # saved snapshot fixes this analysis; every consumed payload must stay
        # byte-identical to that snapshot throughout the calculation.
        analysis["source_manifest_end_sha256"] = digest(manifest)
        analysis["source_manifest_advanced"] = analysis["source_manifest_end_sha256"] != manifest_hash
        all(digest(input["path"]) == input["sha256"] for input in inputs) || error("source evidence changed during analysis")
        analysis["retained_inputs_unchanged"] = true
        write_manifest(output, analysis)
        outcomes[id] = analysis
        println(id, ": ", analysis["status"])
    end
    return outcomes
end
