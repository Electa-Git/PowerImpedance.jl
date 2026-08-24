using PowerImpedance
using Aqua

function undocumented_names(root::Module)
    findings = Pair{Module,Symbol}[]
    VERSION < v"1.11" && return findings

    function visit(current::Module)
        for name in Base.Docs.undocumented_names(current)
            name == nameof(root) || push!(findings, current => name)
        end

        for name in names(current; all = true)
            isdefined(current, name) || continue
            value = getproperty(current, name)
            value isa Module || continue
            value === current && continue
            parentmodule(value) === current || continue
            visit(value)
        end
    end

    visit(root)
    return findings
end

findings = undocumented_names(PowerImpedance)

if isempty(findings)
    println(stderr, "Aqua undocumented-names advisory passed")
else
    redirect_stderr(devnull) do
        Aqua.test_undocumented_names(PowerImpedance; broken = true)
    end

    println(
        stderr,
        "Aqua undocumented-names advisory reported $(length(findings)) module-local findings:",
    )
    for (owner, name) in findings
        println(stderr, "  ", owner, ".", name)
    end
end
