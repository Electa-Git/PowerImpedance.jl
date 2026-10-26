module ParityCoverage
using PowerImpedance
include("fixtures.jl")
const PI = PowerImpedance

function included_files(path, seen = Set{String}())
    path = normpath(path)
    path in seen && return seen
    push!(seen, path)
    for m in eachmatch(r"(?m)^include\(\"([^\"]+)\"\)", read(path, String))
        included_files(joinpath(dirname(path), m[1]), seen)
    end
    return seen
end

function collect_models!(found, value)
    push!(found, string(nameof(typeof(value))))
    value isa Union{Number, Symbol, AbstractString, Function, Type, Module} && return
    if value isa Union{AbstractArray, Tuple, NamedTuple}
        foreach(v -> collect_models!(found, v), value)
    elseif parentmodule(typeof(value)) === PI
        for field in fieldnames(typeof(value))
            collect_models!(found, getfield(value, field))
        end
    end
end

function main()
    files = included_files(joinpath(pkgdir(PI), "src/PowerImpedance_impl.jl"))
    selected = filter(files) do path
        occursin("/Components/machine/", path) ||
            (occursin("/Components/converter/", path) &&
             !endswith(path, "blackbox_MMC.jl"))
    end
    expected = Set{String}()
    for path in sort!(collect(selected))
        for m in eachmatch(r"\bstruct\s+([^\s{<]+)", read(path, String))
            name = Symbol(m[1])
            isdefined(PI, name) || continue
            type = getfield(PI, name)
            type isa Type && !isabstracttype(type) && push!(expected, string(name))
        end
    end
    delete!(expected, "Delay")
    found = Set{String}()
    for fixture in ParityFixtures.FIXTURES
        state = fixture.build()
        for element in values(state.elements)
            collect_models!(found, element)
        end
    end
    kinds = ("Butterworth", "Chebyshev", "Bessel", "CriticalDamping")
    union!(expected, kinds)
    names = join(sort!(collect(expected)), ", ")
    println("Included concrete structs and filter kinds: ", names)
    absent = sort!(collect(setdiff(expected, found)))
    println("Absent names (", length(absent), "): ", join(absent, ", "))
    return absent
end
end

isempty(ParityCoverage.main()) || exit(1)
