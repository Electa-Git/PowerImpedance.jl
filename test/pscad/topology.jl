module PSCADTopology
using PowerImpedance
const P = PowerImpedance.PSCAD

# Electrical geometry uses the same saved-project port table as the exporter. The adapter
# reads serialized XML; component ids and canvas coordinates do not form part of the
# graph's component identity.
function electrical_graph(canvas, modules)
    parent = Dict{Tuple{Int, Int}, Tuple{Int, Int}}()
    root(p) = get!(parent, p, p) == p ? p : (parent[p] = root(parent[p]))
    join(a, b) = (parent[root(a)] = root(b))
    records = Dict{String, Any}[]
    pins = Tuple{Tuple{Int, Int}, Tuple{Int, Int}}[]
    labels = Tuple{Tuple{Int, Int}, String}[]
    grounds = Tuple{Int, Int}[]
    probes = Set{Int}()
    for c in canvas.components
        if c.defn == "master:nodelabel"
            push!(labels, ((c.x, c.y), lowercase(Dict(c.params)["Name"])))
        elseif c.defn == "master:ground"
            push!(grounds, (c.x, c.y))
        else
            electrical = [point
                          for (point, kind) in P.component_ports(c, modules)
                          if kind == :electrical]
            isempty(electrical) && continue
            push!(records, Dict("definition" => c.defn, "parameters" => Dict(c.params)))
            i = length(records)
            c.defn in ("master:voltmetergnd", "master:voltmeter") && push!(probes, i)
            for (j, point) in enumerate(electrical)
                push!(pins, (point, (i, j)))
            end
        end
    end
    points = union(Set(first.(pins)), Set(first.(labels)), Set(grounds))
    segments = Tuple{Tuple{Int, Int}, Tuple{Int, Int}}[]
    for w in canvas.wires
        union!(points, w.vertices)
        append!(segments, zip(w.vertices[1:(end - 1)], w.vertices[2:end]))
    end
    for (a, b) in segments
        # Control-only wires have no electrical port, node label or ground. A segment
        # joining other segments is retained when their endpoints meet an electrical
        # point, including saved bridging paths.
        join(a, b)
        for p in points
            (a[1] == b[1] == p[1] && min(a[2], b[2]) <= p[2] <= max(a[2], b[2])) ||
                (a[2] == b[2] == p[2] && min(a[1], b[1]) <= p[1] <= max(a[1], b[1])) ||
                continue
            join(a, p)
        end
    end
    named = Dict{String, Tuple{Int, Int}}()
    for (point, name) in labels
        haskey(named, name) ? join(point, named[name]) : (named[name] = point)
    end
    for point in grounds[2:end]
        join(first(grounds), point)
    end
    groups = Dict{Tuple{Int, Int}, Vector{Vector{Int}}}()
    for (point, pin) in pins
        push!(get!(groups, root(point), Vector{Int}[]), collect(pin))
    end
    # Unattached electrical labels remain degree-zero nets; removing them would hide an
    # isolated label from the degree test.
    for point in [first.(labels); grounds]
        get!(groups, root(point), Vector{Int}[])
    end
    ground_roots = Set(root.(grounds))
    nets = Dict{String, Any}[]
    for (point, attachments) in groups
        push!(nets,
            Dict("ports" => sort!(attachments; by = Tuple),
                "ground" => point in ground_roots,
                "probe" => any(pin -> pin[1] in probes, attachments)))
    end
    sort!(nets; by = n -> string(n["ports"]))
    return Dict("components" => records, "nets" => nets)
end

function check_degrees(graph, name)
    for (i, net) in enumerate(graph["nets"])
        length(net["ports"]) >= 2 || net["ground"] || net["probe"] ||
            throw(ArgumentError("electrical topology $name net $i has $(length(net["ports"])) connections: $(net["ports"])"))
    end
    return nothing
end

# Only the specified named shunt moves apply. All component parameters and ordered pins
# remain in the independent 8be21ee reference graph.
function shunt_meter_returns(graph, moves)
    expected = deepcopy(graph)
    components, nets = expected["components"], expected["nets"]
    index(name) = only(findall(c -> get(c["parameters"], "Name", "") == name, components))
    net(pin) = only(filter(n -> pin in n["ports"], nets))
    for (meter_name, part_name) in moves
        m, p = index(meter_name), index(part_name)
        components[m]["definition"] == "master:ammeter" ||
            error("$meter_name is not a meter")
        components[p]["definition"] in
        ("master:resistor", "master:inductor", "master:capacitor") ||
            error("$part_name is not a passive shunt")
        bus, inner, ground = net([m, 1]), net([m, 2]), net([p, 2])
        Set(Tuple.(inner["ports"])) == Set([(m, 2), (p, 1)]) ||
            error("$meter_name does not precede the specified shunt")
        ground["ground"] && !bus["ground"] || error("$part_name is not a grounded shunt")
        for (n, before, after) in ((bus, [m, 1], [p, 1]),
            (inner, [m, 2], [m, 1]), (inner, [p, 1], [p, 2]),
            (ground, [p, 2], [m, 2]))
            deleteat!(n["ports"], only(findall(==(before), n["ports"])))
            push!(n["ports"], after)
        end
    end
    return expected
end

# Current direction is significant even when RMS values are unchanged.
function shunt_meter_direction(graph, meter_name, part_name)
    components, nets = graph["components"], graph["nets"]
    index(name) = only(findall(c -> get(c["parameters"], "Name", "") == name, components))
    m, p = index(meter_name), index(part_name)
    net(pin) = only(filter(n -> pin in n["ports"], nets))
    for (input, output, sign) in ((1, 2, 1), (2, 1, -1))
        net([m, output])["ground"] || continue
        [p, 2] in net([m, input])["ports"] || continue
        net([p, 1])["ground"] && continue
        return sign
    end
    error("$meter_name is not on the ground return of $part_name")
end

component_color(c) = (c["definition"], Tuple(sort!(collect(c["parameters"]); by = first)))

# Electrical port ordering preserves ammeter/current-source polarity and transformer
# winding order in the equivalence test. Full component parameters restrict the bijection;
# cable interfaces can have identical fields.
function equivalent(a, b)
    ac, bc = component_color.(a["components"]), component_color.(b["components"])
    sort(ac; by = string) == sort(bc; by = string) || return false
    length(a["nets"]) == length(b["nets"]) || return false
    candidates = [findall(==(color), bc) for color in ac]
    order = sortperm(length.(candidates))
    mapping = zeros(Int, length(ac))
    used = falses(length(bc))
    function compatible()
        for net in a["nets"]
            mapped = Set((mapping[pin[1]], pin[2])
            for pin in net["ports"]
            if mapping[pin[1]] != 0)
            any(
                other -> net["ground"] == other["ground"] &&
                         length(net["ports"]) == length(other["ports"]) &&
                         issubset(mapped, Set(Tuple.(other["ports"]))),
                b["nets"]) || return false
        end
        return true
    end
    function match_component(k)
        if k > length(order)
            signature(net, f) = (
                net["ground"], sort!([(f(pin[1]), pin[2])
                                      for pin in net["ports"]]))
            return sort!([signature(net, i -> mapping[i]) for net in a["nets"]]; by = string) ==
                   sort!([signature(net, identity) for net in b["nets"]]; by = string)
        end
        i = order[k]
        for j in candidates[i]
            used[j] && continue
            mapping[i], used[j] = j, true
            compatible() && match_component(k + 1) && return true
            mapping[i], used[j] = 0, false
        end
        return false
    end
    return match_component(1)
end

# Called only by the XML test environment, whose node adapter returns ordinary
# strings/integers. Definitions with no electrical ports still get empty graphs.
function xml_graphs(root, string_value; check_named = false)
    definitions = root.xpath("./definitions/Definition")
    modules = Dict{String, P.ModuleDefinitionPlan}()
    module_names = Set{String}()
    for d in definitions
        ports = P.ModulePortPlan[]
        for p in d.xpath("./svg/port")
            kind = string_value(p.get("model")) == "Natural" ? :electrical :
                   string_value(p.get("mode")) == "Input" ? :input : :output
            push!(ports,
                P.ModulePortPlan(string_value(p.get("name")), kind,
                    parse(Int, string_value(p.get("x"))), parse(Int, string_value(p.get("y"))),
                    parse(Int, string_value(p.get("dim")))))
        end
        if !isempty(ports)
            name = string_value(d.get("name"))
            push!(module_names, name)
            modules[name] = P.ModuleDefinitionPlan(name, P.ModuleParameterPlan[],
                ports, P.CanvasPlan())
        end
    end
    graphs = Dict{String, Any}()
    for d in definitions
        name = string_value(d.get("name"))
        if string_value(d.get("classid")) == "RowDefn"
            # Row geometry supplies zero circuit nodes. Every material/fitting field
            # remains in electrical graph equality, including line parameters.
            graphs[name] = Dict(
                "components" => [Dict(
                     "definition" => string_value(c.get("defn")),
                     "parameters" => Dict(string_value(p.get("name")) =>
                              string_value(p.get("value"))
                     for p in c.xpath("./paramlist/param")))
                 for c in d.xpath("./schematic/User")],
                "nets" => Dict{String, Any}[])
            continue
        end
        name == "Main" || name in module_names || continue
        components = P.AbstractComponentPlan[]
        cable_wrappers = Dict{String, Any}[]
        for c in d.xpath("./schematic/User")
            params = [string_value(p.get("name")) => string_value(p.get("value"))
                      for p in c.xpath("./paramlist/param")]
            defn = string_value(c.get("defn"))
            values = (defn, params, parse(Int, string_value(c.get("x"))),
                parse(Int, string_value(c.get("y"))), parse(Int, string_value(c.get("orient"))))
            push!(components,
                startswith(defn, "master:") || startswith(defn, "Z_tool:") ? P.ComponentPlan(values...) :
                P.ModuleInstancePlan(values...))
        end
        wires = P.WirePlan[]
        for w in d.xpath("./schematic/Wire")
            x, y = parse(Int, string_value(w.get("x"))),
            parse(Int, string_value(w.get("y")))
            vertices = [(x + parse(Int, string_value(v.get("x"))),
                            y + parse(Int, string_value(v.get("y"))))
                        for v in w.xpath("./vertex")]
            class = string_value(w.get("classid"))
            if class == "WireOrthogonal"
                # Saved exports contain abutments and multi-segment paths. WirePlan
                # requires two vertices; each saved axis-aligned segment is retained
                # separately for graph extraction.
                for (a, b) in zip(vertices[1:(end - 1)], vertices[2:end])
                    push!(wires, P.WirePlan([a, b]))
                end
            elseif class == "TLine"
                defn = string_value(w.get("defn"))
                params = [string_value(p.get("name")) => string_value(p.get("value"))
                          for p in w.xpath("./User/paramlist/param")]
                if Dict(params)["Mode"] == "0"
                    push!(cable_wrappers, Dict("definition" => defn,
                        "parameters" => Dict(params)))
                    continue
                end
                row = last(split(defn, ':'))
                # First/last vertices are terminals, as saved in
                # local/OHL/DUT_2.pscx:1798–1839,17181–17212.
                ports = [
                    P.ModulePortPlan("sending", :electrical,
                        vertices[1][1] - x, vertices[1][2] - y),
                    P.ModulePortPlan("receiving", :electrical,
                        vertices[end][1] - x, vertices[end][2] - y)]
                modules[row] = P.ModuleDefinitionPlan(row, P.ModuleParameterPlan[], ports,
                    P.CanvasPlan())
                params = [string_value(p.get("name")) => string_value(p.get("value"))
                          for p in w.xpath("./User/paramlist/param")]
                push!(components, P.ModuleInstancePlan(defn, params, x, y, 0))
            elseif class == "Cable"
                # Cable interfaces supply the physical terminals; wrapper vertices are
                # graphics rather than wires. Wrapper length and other fields remain in
                # the graph.
                push!(cable_wrappers,
                    Dict("definition" => string_value(w.get("defn")),
                        "parameters" => Dict(string_value(p.get("name")) =>
                                 string_value(p.get("value"))
                        for p in w.xpath("./User/paramlist/param"))))
                continue
            else
                throw(ArgumentError("unknown electrical wrapper $class in $name"))
            end
        end
        canvas = P.CanvasPlan(components, wires)
        check_named && P.check_connectivity(canvas, name, modules)
        graphs[name] = electrical_graph(canvas, modules)
        append!(graphs[name]["components"], cable_wrappers)
        # A Natural module port binds to an explicit xnode, as saved in
        # local/TLC/Simple_2L_VSC_RL.pscx:3377–3382,5604–5613.
        if haskey(modules, name)
            for port in modules[name].ports
                port.kind == :electrical || continue
                count(c -> c.defn == "master:xnode" && Dict(c.params)["Name"] == port.name,
                    components) == 1 ||
                    throw(ArgumentError("electrical topology $name boundary $(port.name) has no unique xnode"))
            end
        end
    end
    return graphs
end
end
