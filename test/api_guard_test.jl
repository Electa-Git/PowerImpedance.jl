module APIGuardTests
using Test

const FORBIDDEN = (
    r"\bElement\b", r"Setpoint", r"SetpointPU", r"@network", r"\bgs_",
    r"transformation *=", r"connection *=", r"_port_descriptions", r"build_network",
    r"element_model", r"\.pins\b",
)

const ALLOWED = Dict(
    "ext/PowerImpedancePSCADExt/writer.jl" => (r"\betree\.Element\b",),
    "ext/PowerImpedancePSCADExt/rowdefn.jl" => (r"\betree\.Element\b",),
    # Constructor rejection checks must spell the removed keywords.
    "test/docstring_examples_test.jl" => (r"transformation *=", r"connection *="),
    # write_structure is used only by the excluded frozen reference generator.
    "test/parity/structure.jl" => (r"element_model",),
)

# Stored calculations and exports retain the names used by their frozen source.
const EXCLUDED_DIRECTORIES = (
    "test/reference", "test/pscad/fixtures", "docs/src/examples",
)
const EXCLUDED_FILES = (
    "test/api_guard_test.jl", "test/parity/topology_08f3d2e.tsv",
)
const MIGRATION_HEADING = "## Migrating from Element and Setpoint"

function excluded(path)
    path in EXCLUDED_FILES && return true
    return any(EXCLUDED_DIRECTORIES) do directory
        path == directory || startswith(path, directory * "/")
    end
end

function migration_text_lines(lines)
    skipped = falses(length(lines))
    migration = false
    text = false
    for (number, line) in enumerate(lines)
        if startswith(line, "## ")
            migration = line == MIGRATION_HEADING
            # The requested migration title contains the removed type names.
            skipped[number] = migration
            text = false
        end
        migration || continue
        if !text && occursin(r"^```text\s*$", line)
            text = true
            skipped[number] = true
        elseif text
            skipped[number] = true
            occursin(r"^```\s*$", line) && (text = false)
        end
    end
    return skipped
end

@testset "Removed API names" begin
    root = dirname(@__DIR__)
    relative(path) = replace(relpath(path, root), '\\' => '/')
    for directory in ("src", "ext", "test", "docs/src", "examples", "integration")
        for (folder, directories, files) in walkdir(joinpath(root, directory))
            filter!(name -> !excluded(relative(joinpath(folder, name))), directories)
            for file in files
                path = joinpath(folder, file)
                name = relative(path)
                excluded(name) && continue
                content = read(path, String)
                # As in a text search, omit binary images and serialized numeric data.
                (isvalid(content) && !occursin('\0', content)) || continue
                lines = split(content, '\n')
                skipped = name == "docs/src/network.md" ?
                    migration_text_lines(lines) : falses(length(lines))
                allowed = get(ALLOWED, name, ())
                failures = String[]
                for (number, line) in enumerate(lines)
                    skipped[number] && continue
                    checked = line
                    for pattern in allowed
                        checked = replace(checked, pattern => "")
                    end
                    for pattern in FORBIDDEN
                        occursin(pattern, checked) || continue
                        push!(failures, "$name:$number $pattern: $line")
                    end
                end
                @test failures == String[]
            end
        end
    end
end
end
