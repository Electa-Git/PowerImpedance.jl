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
println(stderr, "Undocumented public names: ", findings)
@test isempty(findings)

Aqua.test_all(PowerImpedance; undocumented_names = true)
