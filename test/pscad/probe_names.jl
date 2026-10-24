module PSCADProbeNames
using PowerImpedance
const P = PowerImpedance.PSCAD

function name_map(list, probes)
    names = Dict{String, String}()
    truncated = String[]
    polarities = Dict{String, Int}()
    for channel in probes.channels
        channel.kind == :current || continue
        element = only(filter(e -> string(e.name) == channel.element, list.elements))
        outward = channel.port == :ac &&
                   element.model isa Union{PowerImpedance.Source,
                       PowerImpedance.SynchronousMachine, PowerImpedance.MMC,
                       PowerImpedance.TLC} ||
                   channel.port == :side2 && all(t -> !t.grounded, element.terminals)
        previous = outward ? :out : :into
        polarities[channel.name] = channel.orientation == previous ? 1 : -1
        ports = keys(element.ports)
        ports == (:ac, :dc) && (ports = (:dc, :ac))
        side = findfirst(==(channel.port), ports)
        side === nothing && error("missing old port number for $(channel.name)")
        old = P.pscad_name("I_$(element.pscad)_$side")
        haskey(names, old) && error("duplicate old current probe $old")
        names[old] = channel.name
        proposed = P.current_probe_name(element.pscad, channel.port)
        length(proposed) > 30 && push!(truncated, proposed)
    end
    return (; names, truncated, polarities)
end

function map_graph!(graph, names)
    rewritten = 0
    for component in graph["components"]
        component["definition"] in ("master:ammeter", "master:voltmetergnd") || continue
        parameters = component["parameters"]
        name = get(parameters, "Name", nothing)
        haskey(names, name) || continue
        parameters["Name"] = names[name]
        rewritten += 1
    end
    return rewritten
end

function turn_meters!(graph, polarities)
    turned = 0
    for (index, component) in enumerate(graph["components"])
        component["definition"] == "master:ammeter" || continue
        name = get(component["parameters"], "Name", "")
        get(polarities, name, 1) == -1 || continue
        for net in graph["nets"], pin in net["ports"]
            pin[1] == index && (pin[2] = 3 - pin[2])
        end
        turned += 1
    end
    return turned
end
end
