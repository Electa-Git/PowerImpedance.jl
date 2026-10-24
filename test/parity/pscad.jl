module ParityPSCAD
using Test, PowerImpedance, PythonCall, TOML, SHA, LinearAlgebra
let previous_threads = BLAS.get_num_threads()
    try
        BLAS.set_num_threads(1)
        include("fixtures.jl")
    finally
        BLAS.set_num_threads(previous_threads)
    end
end
include("../pscad/topology.jl")
include("../pscad/probe_names.jl")
const P = PowerImpedance.PSCAD
const ETREE = pyimport("lxml.etree")
const SOURCE_COMMIT = "a1a7fb71d6ac189ddf06d58e2817dc4197dd4031"
const DIRECTORY = normpath(joinpath(@__DIR__, "../pscad/fixtures"))

function export_fixture(fixture, directory)
    state = fixture.build()
    machine = any(
        e -> e isa Union{PowerImpedance.SynchronousMachine,
            PowerImpedance.InductionMachine},
        values(state.elements))
    settings = P.SimulationSettings(simulation_time = machine ? 5.0 : 0.3,
        time_step = 50e-6, sample_step = 250e-6, snapshot_time = 0.2)
    path = joinpath(directory, "$(fixture.name).pscx")
    name = P.pscad_name(string(fixture.name))
    model = export_pscad(state; path, settings, name)
    root = ETREE.parse(path).getroot()
    graphs = PSCADTopology.xml_graphs(root, x -> pyconvert(String, x); check_named = true)
    probes = sort!([c.name
                    for c in model.probes.channels
                    if startswith(c.name, "V_") || startswith(c.name, "I_")])
    mapping = PSCADProbeNames.name_map(model.netlist, model.probes)
    return (; graphs, probes, path, mapping)
end

function read_probes(path)
    result = Dict{String, Vector{String}}()
    for line in eachline(path)
        startswith(line, "#") && continue
        line == "fixture\tprobe" && continue
        fixture, probe = split(line, '\t')
        push!(get!(result, fixture, String[]), probe)
    end
    return result
end

function run_parity()
    previous_threads = BLAS.get_num_threads()
    try
        BLAS.set_num_threads(1)
        probes = read_probes(joinpath(DIRECTORY, "export_probe_names_a1a7fb7.tsv"))
        fixtures = filter(f -> f.probes.pscad, ParityFixtures.FIXTURES)
        @testset "Frozen PSCAD exports" begin
            @test Set(keys(probes)) == Set(string(f.name) for f in fixtures)
            expected_files = Set("$(f.name).toml" for f in fixtures)
            snapshot_directory = joinpath(DIRECTORY, "topology_a1a7fb7")
            @test Set(filter(p -> endswith(p, ".toml"), readdir(snapshot_directory))) ==
                  expected_files
            mktempdir() do directory
                for fixture in fixtures
                    @testset "$(fixture.name)" begin
                        reference = TOML.parsefile(joinpath(snapshot_directory,
                            "$(fixture.name).toml"))
                        @test reference["commit"] == SOURCE_COMMIT
                        fresh = export_fixture(fixture, directory)
                        @test Set(keys(reference["canvases"])) == Set(keys(fresh.graphs))
                        rewritten = 0
                        for (canvas, graph) in fresh.graphs
                            expected = reference["canvases"][canvas]
                            rewritten += PSCADProbeNames.map_graph!(
                                expected, fresh.mapping.names)
                            PSCADProbeNames.turn_meters!(expected,
                                fresh.mapping.polarities)
                            @test PSCADTopology.equivalent(expected, graph)
                        end
                        old_probes = probes[string(fixture.name)]
                        mapped = sort!([get(fresh.mapping.names, p, p) for p in old_probes])
                        @test mapped == fresh.probes
                        count = sum(p -> haskey(fresh.mapping.names, p), old_probes)
                        println("PSCAD names fixture=", fixture.name,
                            " graph=", rewritten, " probes=", count,
                            " truncated=", fresh.mapping.truncated,
                            " turned=", join(sort!([name for (name, polarity) in
                                fresh.mapping.polarities if polarity == -1]), ','))
                    end
                end
            end
        end
    finally
        BLAS.set_num_threads(previous_threads)
    end
end
end
