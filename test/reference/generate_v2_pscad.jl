using Pkg
const REPOSITORY = normpath(joinpath(@__DIR__, "../.."))
const SOURCE_COMMIT = "a1a7fb71d6ac189ddf06d58e2817dc4197dd4031"
readchomp(`git -C $REPOSITORY rev-parse HEAD`) == SOURCE_COMMIT ||
    error("reference generation requires $SOURCE_COMMIT")

if get(ENV, "PARITY_PSCAD_CHILD", "0") != "1"
    mktempdir(; prefix = "powerimpedance-parity-xml-") do environment
        Pkg.activate(environment)
        withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
            Pkg.develop(Pkg.PackageSpec(path = REPOSITORY))
            Pkg.add([Pkg.PackageSpec(name = "PythonCall", version = "0.9"),
                Pkg.PackageSpec(name = "CondaPkg", version = "0.2")])
        end
        withenv("PARITY_PSCAD_CHILD" => "1", "JULIA_CONDAPKG_BACKEND" => "Pixi",
            "JULIA_CONDAPKG_ENV" => nothing, "JULIA_CONDAPKG_OFFLINE" => "no",
            "JULIA_PYTHONCALL_EXE" => nothing, "OPENBLAS_NUM_THREADS" => "1",
            "JULIA_NUM_THREADS" => "1") do
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$environment`
            run(`$cmd $(@__FILE__) $ARGS`)
        end
    end
else
    using CondaPkg
    CondaPkg.resolve()
    using PythonCall, PowerImpedance, TOML, SHA, LinearAlgebra
    BLAS.set_num_threads(1)
    include("../parity/pscad.jl")
    const D = Base.invokelatest(getfield, Main, :ParityPSCAD)
    destination = joinpath(D.DIRECTORY, "topology_a1a7fb7")
    mkpath(destination)
    mktempdir(; prefix = "powerimpedance-parity-exports-") do exports
        probe_rows = Tuple{String, String}[]
        for fixture in D.ParityFixtures.FIXTURES
            fixture.probes.pscad || continue
            println("Exporting ", fixture.name)
            flush(stdout)
            fresh = D.export_fixture(fixture, exports)
            path = joinpath(destination, "$(fixture.name).toml")
            open(path, "w") do io
                TOML.print(io,
                    Dict("commit" => SOURCE_COMMIT,
                        "source_sha256" => bytes2hex(sha256(read(fresh.path))),
                        "canvases" => fresh.graphs);
                    sorted = true)
            end
            append!(probe_rows, [(string(fixture.name), p) for p in fresh.probes])
            println("EXPORTED ", fixture.name)
        end
        open(joinpath(D.DIRECTORY, "export_probe_names_a1a7fb7.tsv"), "w") do io
            println(io, "fixture\tprobe")
            for row in sort!(probe_rows)
                println(io, join(row, '\t'))
            end
        end
        write(joinpath(destination, "README.md"), """
        Electrical graphs extracted from commit `$SOURCE_COMMIT`.
        Each TOML records the commit and SHA-256 of its source `.pscx` file.
        Exports use 0.3 s / 50 μs / 250 μs / 0.2 s snapshot settings;
        networks containing machines use 5 s.

        `topology.jl` extracts circuit ports, wire segments, node labels and ground.
        Component parameters and ordered electrical port numbers are retained.
        Coordinates and component ids are omitted. Graphs are compared with
        `PSCADTopology.equivalent`. Probe names are listed in
        `../export_probe_names_a1a7fb7.tsv`.
        """)
    end
end
