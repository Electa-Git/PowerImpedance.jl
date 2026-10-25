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
)

@testset "Removed API names in src and ext" begin
    root = dirname(@__DIR__)
    for directory in ("src", "ext")
        for (folder, _, files) in walkdir(joinpath(root, directory))
            for file in files
                path = joinpath(folder, file)
                relative = relpath(path, root)
                allowed = get(ALLOWED, relative, ())
                failures = String[]
                for (number, line) in enumerate(eachline(path))
                    checked = line
                    for pattern in allowed
                        checked = replace(checked, pattern => "")
                    end
                    for pattern in FORBIDDEN
                        occursin(pattern, checked) || continue
                        push!(failures, "$relative:$number $pattern: $line")
                    end
                end
                @test failures == String[]
            end
        end
    end
end
end
