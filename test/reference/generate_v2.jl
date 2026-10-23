using PowerImpedance, LinearAlgebra, PowerModels, PowerModelsACDC, Ipopt, SHA
include("../parity/structure.jl")
const D = ParityData

function main(output_directory)
    actual = readchomp(`git -C $(pkgdir(PowerImpedance)) rev-parse HEAD`)
    actual == D.SOURCE_COMMIT || error("reference generation requires $(D.SOURCE_COMMIT)")
    isfile(joinpath(output_directory, "metadata.txt")) &&
        error("reference already exists; generation is a one-time operation")
    BLAS.set_num_threads(1)
    rows, labels = D.Row[], Dict{String, String}()
    skipped, network_skipped, conversion_skipped = String[], String[], String[]
    errors = Pair{String, String}[]
    dump_directory = joinpath(pkgdir(PowerImpedance), "local/parity_v2")
    mkpath(dump_directory)
    summary = String[]
    for fixture in D.ParityFixtures.FIXTURES
        println("Collecting ", fixture.name)
        flush(stdout)
        result = open(joinpath(dump_directory, "$(fixture.name).solver.log"), "w") do io
            redirect_stdout(io) do
                redirect_stderr(io) do
                    D.collect_fixture(fixture; dump_directory)
                end
            end
        end
        append!(rows, result.rows)
        merge!(labels, result.labels)
        append!(skipped, result.skipped)
        append!(errors, result.errors)
        result.network_level_skipped && push!(network_skipped, string(fixture.name))
        result.conversion_skipped && push!(conversion_skipped, string(fixture.name))
        state = result.state
        active = join(string.(keys(filter(PowerImpedance.is_active, state.elements))), ", ")
        source = D.ParityFixtures.SOURCES[fixture.name]
        nets = length(unique(state.topology.connections.node))
        push!(summary,
            "| $(fixture.name) | $source | $(length(state.elements)) | " *
            "$active | $nets | $(fixture.probes.pscad) | $(length(result.rows)) |")
        println("Collected ", fixture.name, " rows=", length(result.rows),
            " skipped=", join(result.skipped, ','))
    end
    println("Collecting operating-point and legacy comparisons")
    flush(stdout)
    result = D.collect_oracles()
    append!(rows, result.rows)
    merge!(labels, result.labels)
    append!(skipped, result.skipped)
    append!(errors, result.errors)
    mkpath(output_directory)
    D.write_rows(joinpath(output_directory, "numeric.csv"), rows)
    D.write_labels(joinpath(output_directory, "labels.tsv"), labels)
    write(joinpath(dump_directory, "fixture_table.md"), join(summary, '\n') * "\n")
    open(joinpath(dump_directory, "exceptions.txt"), "w") do io
        for (name, message) in errors
            println(io, name, '\n', message, '\n')
        end
    end
    open(joinpath(output_directory, "metadata.txt"), "w") do io
        println(io, "format_version=2")
        println(io, "source_commit=$(D.SOURCE_COMMIT)")
        println(io, "julia_version=$VERSION")
        println(io, "powermodels_version=$(Base.pkgversion(PowerModels))")
        println(io, "powermodelsacdc_version=$(Base.pkgversion(PowerModelsACDC))")
        println(io, "ipopt_version=$(Base.pkgversion(Ipopt))")
        manifest = joinpath(dirname(Base.active_project()), "Manifest.toml")
        println(io, "dependency_manifest_sha256=$(D.file_sha(manifest))")
        numeric_sha = D.file_sha(joinpath(output_directory, "numeric.csv"))
        println(io, "numeric_sha256=$numeric_sha")
        println(io, "labels_sha256=$(D.file_sha(joinpath(output_directory, "labels.tsv")))")
        println(io, "frequencies_hz=$(join(D.FREQUENCIES, ','))")
        println(io, "frequency_unit=Hz_inputs_rad_per_second_responses")
        println(io, "complex_storage=real_imaginary_columns")
        println(io, "OPENBLAS_NUM_THREADS=$(get(ENV, "OPENBLAS_NUM_THREADS", "unset"))")
        println(io, "JULIA_NUM_THREADS=$(get(ENV, "JULIA_NUM_THREADS", "unset"))")
        println(io, "blas_threads=$(BLAS.get_num_threads())")
        println(io, "julia_threads=$(Threads.nthreads())")
        fixtures = D.ParityFixtures.FIXTURES
        println(io, "fixture_count=$(length(fixtures))")
        println(io, "fixtures=$(join((f.name for f in fixtures), ','))")
        pscad_names = join((f.name for f in fixtures if f.probes.pscad), ',')
        println(io, "pscad_fixtures=$pscad_names")
        println(io, "network_level_skipped=$(join(network_skipped, ','))")
        println(io, "pm_conversion_skipped=$(join(conversion_skipped, ','))")
        println(io, "topology_only=connection_dsl")
        println(io, "skipped=$(join(sort!(unique(skipped)), ','))")
        println(io, "stability_fixture=$(result.stability_fixture)")
    end
    println("numeric_bytes=", filesize(joinpath(output_directory, "numeric.csv")))
end

length(ARGS) == 1 || error("usage: julia generate_v2.jl OUTPUT_DIRECTORY")
main(abspath(only(ARGS)))
