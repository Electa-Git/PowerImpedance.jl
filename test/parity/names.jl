module ParityNames
using PowerImpedance
const PI = PowerImpedance

const PREVIOUS_ROWS = let rows = Dict{Symbol, Vector{NamedTuple}}()
    path = joinpath(@__DIR__, "topology_08f3d2e.tsv")
    for line in Iterators.drop(eachline(path), 1)
        fixture, net, bus, component, port, terminal, domain, frame = split(line, '\t')
        row = (; net = Symbol(net), bus = parse(Int, bus), component = Symbol(component),
            port = Symbol(port), terminal = Symbol(terminal), domain = parse(Int, domain),
            frame = Symbol(frame))
        push!(get!(rows, Symbol(fixture), NamedTuple[]), row)
    end
    rows
end

function net_map(name, state)
    previous = PREVIOUS_ROWS[Symbol(name)]
    current = collect(state.topology.connections)
    length(previous) == length(current) || error("$name: topology row count differs")
    by_terminal = Dict((r.component, r.port, r.terminal) => r for r in current)
    length(by_terminal) == length(current) || error("$name: repeated terminal")
    forward = Dict{Symbol, Vector{Symbol}}()
    reverse = Dict{Symbol, Symbol}()
    for (index, old) in enumerate(previous)
        key = (old.component, old.port, old.terminal)
        new = by_terminal[key]
        new == current[index] || error("$name: topology row $index moved")
        Base.structdiff(old, (; net = nothing)) ==
            Base.structdiff(new, (; net = nothing)) ||
            error("$name: topology row $index differs: $old -> $new")
        targets = get!(forward, old.net, Symbol[])
        new.net in targets || push!(targets, new.net)
        length(targets) == 1 || PI.isgroundnet(old.net) ||
            error("$name: nongrounded net $(old.net) splits into $targets")
        origin = get!(reverse, new.net, old.net)
        origin == old.net ||
            error("$name: nets $origin and $(old.net) merge into $(new.net)")
    end
    return forward
end

function pscad_names(name, list)
    P = PI.PSCAD
    rows = PREVIOUS_ROWS[Symbol(name)]
    used = P._NameReservations()
    result = Dict{String, String}()
    for (index, bus) in enumerate(list.buses)
        nets = unique(r.net for r in rows
            if r.domain == bus.key.domain && r.bus == bus.key.index)
        isempty(nets) && error("$name: missing previous bus $(bus.key)")
        proposed = P.bus_name(nets)
        old = P.pscad_name(proposed === nothing ? "BUS$index" : proposed; used)
        old == bus.name && continue
        result[P.voltage_probe_name(old)] = P.voltage_probe_name(bus.name)
    end
    element_names = Dict(element.name => P.pscad_name(element.name; used)
        for element in list.elements)
    return (; voltage_names = result, element_names)
end

function retained_nets(name, state, mapping)
    rows = PREVIOUS_ROWS[Symbol(name)]
    sources = Set(key for (key, model) in pairs(state.elements) if PI.is_source(model))
    active = Set(key for (key, model) in pairs(state.elements) if PI.is_active(model))
    source_nets = Set(r.net for r in rows if r.component in sources)
    nets = unique(r.net for r in rows if r.bus != 0 && r.net ∉ source_nets)
    if length(nets) > 12
        retained = Set(nets)
        nets = unique(r.net for r in rows if r.net in retained && r.component in active)
        nets = nets[1:min(12, length(nets))]
    end
    return [only(mapping[net]) for net in nets]
end

function dataset_names(key, mappings)
    parts = String.(split(key, '.'))
    haskey(mappings, first(parts)) || return [key]
    mapping = mappings[first(parts)]
    if parts[2] == "nodes"
        return [join([parts[1:2]; string(net); parts[4:end]], '.')
            for net in mapping[Symbol(parts[3])]]
    end
    for index in 3:length(parts)
        parts[index] = replace(parts[index], r"[^+;\[\]=]+" => token ->
            haskey(mapping, Symbol(token)) ?
                join(string.(mapping[Symbol(token)]), '+') : token)
    end
    return [join(parts, '.')]
end

function mapped_datasets(data, mappings)
    result = empty(data)
    for (key, value) in data, mapped in dataset_names(key, mappings)
        haskey(result, mapped) && error("repeated mapped dataset $mapped")
        result[mapped] = value
    end
    return result
end
end
