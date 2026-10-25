module PSCADProbeNames
using PowerImpedance
const P = PowerImpedance.PSCAD

function name_map(list, probes; voltage_names = Dict{String, String}(),
        element_names = Dict{Symbol, String}())
    names = copy(voltage_names)
    components = Dict(get(element_names, e.name, e.pscad) => e.pscad
        for e in list.elements)
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
        port_index = findfirst(==(channel.port), ports)
        port_index === nothing && error("missing old port number for $(channel.name)")
        designator = get(element_names, element.name, element.pscad)
        old = P.pscad_name("I_$(designator)_$port_index")
        haskey(names, old) && error("duplicate old current probe $old")
        names[old] = channel.name
        proposed = P.current_probe_name(element.pscad, channel.port)
        length(proposed) > 30 && push!(truncated, proposed)
    end
    return (; names, truncated, polarities, components)
end

function map_graph!(graph, names; components = Dict{String, String}())
    rewritten = 0
    ordered = sort!(collect(components); by = pair -> -length(first(pair)))
    for component in graph["components"]
        parameters = component["parameters"]
        name = get(parameters, "Name", nothing)
        name === nothing && continue
        if component["definition"] in ("master:ammeter", "master:voltmetergnd") &&
           haskey(names, name)
            parameters["Name"] = names[name]
            rewritten += 1
            continue
        end
        # Generated part names begin with their component's PSCAD name.
        for (old, new) in ordered
            name == old || startswith(name, old * "_") || continue
            if old != new
                parameters["Name"] = P.pscad_name(new * chop(name; head = length(old),
                    tail = 0))
                rewritten += 1
            end
            break
        end
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
