module PSCADNetworks
using PowerImpedance, LinearAlgebra, Test
const P = PowerImpedance.PSCAD
const NB = PowerImpedance.NetworkBuilder

include("../parity/fixtures.jl")

function p2p_builder(share)
    fixture = ParityFixtures.P2PAlt
    return NB.define(fixture.ohl_to_ugc(share), fixture.connections;
        options = fixture.builder_options)
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
