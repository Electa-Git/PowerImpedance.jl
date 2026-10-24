module PSCADNetworks
using PowerImpedance, LinearAlgebra, Test
const P = PowerImpedance.PSCAD
const NB = PowerImpedance.NetworkBuilder

# Include model definitions through one named definition, excluding subsequent
# frequency scans and plotting. Each example has its own variable namespace.
function load_through(path, target)
    namespace = Module(gensym(:NetworkExample))
    Core.eval(namespace, :(using PowerImpedance))
    Core.eval(namespace, :(import PowerImpedance: @network))
    done = Ref(false)
    function select(expression)
        done[] && return :(nothing)
        expression isa Expr || return expression
        if expression.head == :using
            return :(nothing) # PowerImpedance is already imported above.
        end
        statement = expression.head == :macrocall &&
            expression.args[1] == Symbol("@time") ? expression.args[end] : expression
        statement.head == :macrocall && statement.args[1] == Symbol("@show") &&
            return :(nothing)
        if statement.head == :function && statement.args[1].args[1] == target ||
            statement.head == :(=) && statement.args[1] == target
            done[] = true
        end
        return expression
    end
    Base.include(select, namespace, path)
    done[] || error("definition $target not found in $path")
    return namespace
end

function p2p_builder(share)
    namespace = load_through(joinpath(pkgdir(PowerImpedance),
        "examples/P2P_HVDC_ALT.jl"), :ohl_to_ugc)
    return Base.invokelatest() do
        NB.define(namespace.ohl_to_ugc(share), namespace.connections;
            options = namespace.builder_options)
    end
end

function ieee39_classic()
    namespace = load_through(joinpath(pkgdir(PowerImpedance),
        "examples/IEEE39bus.jl"), :IEEE39bus)
    return Base.invokelatest(getproperty, namespace, :IEEE39bus)
end

function ieee39_builder()
    namespace = Module(gensym(:IEEE39Fixture))
    Core.eval(namespace, :(using Test, LinearAlgebra))
    skip_testsets(expression) = expression isa Expr && expression.head == :macrocall &&
        expression.args[1] == Symbol("@testset") ? :(nothing) : expression
    Base.include(skip_testsets, namespace,
        joinpath(pkgdir(PowerImpedance), "test/NetworkBuilder_test.jl"))
    return Base.invokelatest() do
        NB.define(namespace.ieee39bus_elements(), namespace.ieee39bus_connections();
            options = (; voltageBase = namespace.Vm1,
                power_flow = (; is_bounded = (; bus_voltage = true))))
    end
end

function inventory(netlist)
    counts = Dict{String, Int}()
    parent = Dict(b.key => b.key for b in netlist.buses)
    root(key) = parent[key] == key ? key : (parent[key] = root(parent[key]))
    for e in netlist.elements
        kind = string(nameof(typeof(e.model)))
        counts[kind] = get(counts, kind, 0) + 1
        e.model isa Union{PowerImpedance.Overhead_line, PowerImpedance.Cable} && continue
        # The emitted TLC phase voltage sources and DC current source are
        # electrically separate (tlc_electrical_canvas), linked only by controls.
        e.model isa PowerImpedance.TLC && continue
        buses = [t.bus for t in e.terminals if !t.grounded]
        for bus in buses[2:end]
            parent[root(bus)] = root(first(buses))
        end
    end
    ac = count(b -> b.kind != :dc, netlist.buses)
    dc = length(netlist.buses) - ac
    return (; elements = length(netlist.elements), counts, ac_buses = ac, dc_buses = dc,
        bus_nodes = 3ac + 2dc, subsystems = length(Set(root.(collect(keys(parent))))))
end
end
