module DirectModelParityTests
using Test, LinearAlgebra, Printf
const PREVIOUS_BLAS_THREADS = BLAS.get_num_threads()
try
    BLAS.set_num_threads(1)
    include("parity/structure.jl")
finally
    BLAS.set_num_threads(PREVIOUS_BLAS_THREADS)
end
const D = ParityData
const DIRECTORY = joinpath(@__DIR__, "reference/v2")
const STORED_ONLY = (
    keys = Set("oracle.droop_$kind.order$order.$dataset"
        for kind in (:mmc, :tlc), order in (0, 2),
            dataset in ("x", "y.1", "y.2", "y.3")),
    families = (),
)

stored_only(name) = name in STORED_ONLY.keys ||
    any(prefix -> startswith(name, "$prefix."), STORED_ONLY.families)
const GENERATOR_POWER_SEED_FIELDS = (gen = ("pg", "qg"), gendc = ("pgdcset",))

function default_power_seed(name, value)
    parts = split(name, '.')
    length(parts) == 5 && parts[2] == "pm" || return false
    fields = get(GENERATOR_POWER_SEED_FIELDS, Symbol(parts[3]), ())
    return parts[5] in fields && value === 0.0 + 0.0im
end

const TOLERANCES = Dict(
    "pm" => (rtol = 1e-13, atol = 1e-13),
    "nodes" => (rtol = 0.0, atol = 0.0),
    "pf" => (rtol = 1e-12, atol = 1e-12),
    "op" => (rtol = 1e-12, atol = 1e-12),
    "ss" => (rtol = 1e-10, atol = 1e-12),
    "eig" => (rtol = 1e-8, atol = 1e-12),
    "y" => (rtol = 1e-12, atol = 1e-12),
    "ynode" => (rtol = 1e-12, atol = 1e-12),
    "yedge" => (rtol = 1e-12, atol = 1e-12),
    "zdet" => (rtol = 1e-12, atol = 1e-12),
    "stability" => (rtol = 1e-12, atol = 1e-12),
    "oracle" => (rtol = 1e-12, atol = 1e-12),
    "pscad_op" => (rtol = 1e-12, atol = 1e-12)
)

function family(name)
    parts = split(name, '.')
    first(parts) in ("oracle", "stability", "pscad_op") && return first(parts)
    "eig" in parts && return "eig"
    return parts[2]
end

function fixture_name(name)
    parts = split(name, '.')
    return first(parts) in ("oracle", "stability", "pscad_op") ? parts[2] : parts[1]
end

function arrays(rows)
    result = Dict{String, Any}()
    dimensions = Dict{String, Vector{Int}}()
    for ((name, i, _, _), value) in rows
        endswith(name, ".size") || continue
        base = chop(name; tail = 5)
        shape = get!(dimensions, base, Int[])
        length(shape) < i && resize!(shape, i)
        shape[i] = Int(real(value))
    end
    for (name, shape) in dimensions
        result[name] = zeros(ComplexF64, Tuple(shape))
    end
    for ((name, i, j, k), value) in rows
        endswith(name, ".size") && continue
        if haskey(dimensions, name)
            shape = dimensions[name]
            coordinates = (i, j, k)[1:length(shape)]
            result[name][coordinates...] = value
        else
            (i, j, k) == (1, 1, 1) || error("missing array size for $name")
            result[name] = value
        end
    end
    return result
end

function compare_numeric(reference, live_rows)
    live = arrays(Dict(r[1:4] => complex(r[5], r[6]) for r in live_rows))
    maxima = Dict{Tuple{String, String}, Tuple{Float64, Float64}}()
    @test all(name -> haskey(reference, name), STORED_ONLY.keys)
    stored = Set(filter(stored_only, collect(keys(reference))))
    @test isempty(intersect(Set(keys(live)), stored))
    extra = setdiff(Set(keys(live)), Set(keys(reference)))
    accepted = Set(name for name in extra if default_power_seed(name, live[name]))
    @test extra == accepted
    @test setdiff(Set(keys(reference)), stored) ⊆ Set(keys(live))
    @printf("parity accepted_zero_power_seeds=%d\n", length(accepted))
    for name in sort!(collect(intersect(keys(reference), keys(live))))
        ref, value = reference[name], live[name]
        kind = family(name)
        tolerance = TOLERANCES[kind]
        @test size(value) == size(ref)
        size(value) == size(ref) || continue
        absolute, relative = 0.0, 0.0
        pairs = ref isa Number ? ((value, ref),) : zip(value, ref)
        passed = true
        for (v, r) in pairs
            delta = abs(v - r)
            ratio = iszero(delta) ? 0.0 : iszero(r) ? Inf : delta / abs(r)
            absolute, relative = max(absolute, delta), max(relative, ratio)
            passed &= delta <= tolerance.atol + tolerance.rtol * abs(r)
        end
        @testset "$name" begin
            @test passed
        end
        if !iszero(absolute)
            @printf("parity dataset=%s max_abs=%.17g max_rel=%.17g\n",
                name, absolute, relative)
        end
        group = (fixture_name(name), kind)
        previous = get(maxima, group, (0.0, 0.0))
        maxima[group] = max.(previous, (absolute, relative))
    end
    for ((fixture, kind), (absolute, relative)) in sort!(collect(maxima); by = first)
        @printf("parity fixture=%s family=%s max_abs=%.17g max_rel=%.17g\n",
            fixture, kind, absolute, relative)
    end
end

function run_parity()
    previous_threads = BLAS.get_num_threads()
    try
        BLAS.set_num_threads(1)
        @testset "Frozen numerical reference" begin
            metadata = D.load_metadata(joinpath(DIRECTORY, "metadata.txt"))
            @test metadata["source_commit"] == D.SOURCE_COMMIT
            @test metadata["format_version"] == "2"
            valid = metadata["source_commit"] == D.SOURCE_COMMIT
            for file in ("numeric.csv", "labels.tsv")
                field = file == "numeric.csv" ? "numeric_sha256" : "labels_sha256"
                matched = D.file_sha(joinpath(DIRECTORY, file)) == metadata[field]
                @test matched
                valid &= matched
            end
            valid || error("reference metadata or data hash differs")
            fixtures = D.ParityFixtures.FIXTURES
            @test join((f.name for f in fixtures), ',') == metadata["fixtures"]
            @test length(fixtures) == parse(Int, metadata["fixture_count"])
            pscad_names = join((f.name for f in fixtures if f.probes.pscad), ',')
            @test pscad_names == metadata["pscad_fixtures"]
            reference = arrays(D.load_rows(joinpath(DIRECTORY, "numeric.csv")))
            rows, labels = D.Row[], Dict{String, String}()
            skipped, network_skipped, conversion_skipped = String[], String[], String[]
            reference_skipped = split(metadata["skipped"], ','; keepempty = false)
            reference_network_skipped = split(metadata["network_level_skipped"], ',';
                keepempty = false)
            for fixture in fixtures
                println("Recomputing ", fixture.name)
                flush(stdout)
                result = D.collect_fixture(fixture;
                    network_level_skipped =
                        string(fixture.name) in reference_network_skipped,
                    skipped_families = reference_skipped)
                append!(rows, result.rows)
                merge!(labels, result.labels)
                append!(skipped, result.skipped)
                result.network_level_skipped &&
                    push!(network_skipped, string(fixture.name))
                result.conversion_skipped &&
                    push!(conversion_skipped, string(fixture.name))
            end
            result = D.collect_oracles()
            append!(rows, result.rows)
            merge!(labels, result.labels)
            append!(skipped, result.skipped)
            @test sort!(unique(skipped)) == reference_skipped
            @test network_skipped == reference_network_skipped
            @test join(conversion_skipped, ',') == metadata["pm_conversion_skipped"]
            @test result.stability_fixture == metadata["stability_fixture"]
            reference_labels = D.load_labels(joinpath(DIRECTORY, "labels.tsv"))
            for (key, label) in reference_labels
                parts = split(key, '.')
                first(parts) == "pscad_op" && last(parts) == "name" || continue
                names = result.pscad_name_maps[parts[2]]
                reference_labels[key] = get(names, label, label)
            end
            filter!(pair -> !stored_only(first(pair)), reference_labels)
            @test labels == reference_labels
            compare_numeric(reference, rows)
        end
    finally
        BLAS.set_num_threads(previous_threads)
    end
end
run_parity()
end
