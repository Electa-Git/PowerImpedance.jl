module PSCADProbeNames
using PowerImpedance
const P = PowerImpedance.PSCAD

function name_map(list, probes)
    names = Dict{String, String}()
    truncated = String[]
    for channel in probes.channels
        channel.kind == :current || continue
        element = only(filter(e -> string(e.name) == channel.element, list.elements))
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
    return (; names, truncated)
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
end
