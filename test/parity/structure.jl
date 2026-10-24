module ParityData
using PowerImpedance, LinearAlgebra, Printf, SHA, Logging
include("fixtures.jl")
include("../pscad/probe_names.jl")
using .ParityFixtures
const PI = PowerImpedance
const NB = PI.NetworkBuilder
const SOURCE_COMMIT = "a1a7fb71d6ac189ddf06d58e2817dc4197dd4031"
const FREQUENCIES = (1e-3, 1.0, 5.0, 49.0, 150.0, 500.0, 1500.0, 5000.0)
const Row = Tuple{String, Int, Int, Int, Float64, Float64}
const POWERFLOW_SOLVE_EXCEPTIONS = (
    :small_ac, :passive_ohl, :transformer_yy, :transformer_dy, :dc, :dc_cable)

function record!(rows, labels, name, value::Number)
    push!(rows, (name, 1, 1, 1, Float64(real(value)), Float64(imag(value))))
end

function record!(rows, labels, name, value::AbstractArray{<:Number})
    ndims(value) <= 3 || error("too many array dimensions: $name")
    for (i, dimension) in enumerate(size(value))
        push!(rows, (name * ".size", i, 1, 1, Float64(dimension), 0.0))
    end
    for index in CartesianIndices(value)
        iszero(value[index]) && continue
        coordinates = (Tuple(index)..., ntuple(_ -> 1, 3 - ndims(value))...)
        v = value[index]
        push!(rows, (name, coordinates..., Float64(real(v)), Float64(imag(v))))
    end
    # Empty and zero arrays retain their dataset key through their size record.
end

function record!(rows, labels, name, value)
    @nospecialize value
    if value isa AbstractDict
        for key in sort!(collect(keys(value)); by = string)
            record!(rows, labels, "$name.$key", value[key])
        end
    elseif value isa NamedTuple
        for key in keys(value)
            record!(rows, labels, "$name.$key", value[key])
        end
    elseif value isa Union{Tuple, AbstractArray}
        for (index, item) in enumerate(value)
            record!(rows, labels, "$name.$index", item)
        end
    elseif value !== missing && value !== nothing
        labels[name] = string(value)
    end
end

function bus_keys(state, data, mapping)
    result = Dict{Tuple{String, Int}, String}()
    for domain in (1, 2)
        group = domain == 1 ? "bus" : "busdc"
        rows = filter(r -> r.domain == domain, state.topology.connections)
        for bus in unique(rows.bus)
            nets = sort!(string.(unique(r.net for r in rows if r.bus == bus)))
            result[(group, bus)] = join(nets, "+")
        end
    end
    for (name, element) in pairs(state.elements)
        element isa PI.SynchronousMachine || continue
        entry = mapping[name]
        gen = data["gen"][string(entry.compkey)]
        result[("bus", gen["gen_bus"])] = "$name#terminal"
    end
    pending = Tuple{String, Int}[]
    for group in ("bus", "busdc"), id in keys(data[group])

        key = (group, parse(Int, id))
        haskey(result, key) || push!(pending, key)
    end
    while !isempty(pending)
        progress = false
        for key in copy(pending)
            group, id = key
            branchgroup = group == "bus" ? "branch" : "branchdc"
            fields = group == "bus" ? ("f_bus", "t_bus") : ("fbusdc", "tbusdc")
            neighbors = String[]
            for branch in values(data[branchgroup]), (a, b) in (fields, reverse(fields))

                get(branch, a, nothing) == id || continue
                other = get(branch, b, nothing)
                haskey(result, (group, other)) && push!(neighbors, result[(group, other)])
            end
            isempty(neighbors) && continue
            result[key] = "$group#helper[" * join(sort!(unique(neighbors)), "+") * "]"
            deleteat!(pending, findfirst(==(key), pending))
            progress = true
        end
        progress || error("unkeyed helper buses: $pending")
    end
    return result
end

function entry_keys(state, data, mapping)
    buses = bus_keys(state, data, mapping)
    entries = Dict{Tuple{String, String}, String}()
    for ((group, index), key) in buses
        entries[(group, string(index))] = key
    end
    for (name, entry) in mapping
        entries[(entry.pmtype, string(entry.compkey))] = string(name)
        if state.elements[name] isa PI.SynchronousMachine
            entries[("branch", string(entry.compkey))] = string(name)
        end
    end
    for (group, records) in data
        records isa AbstractDict || continue
        for (id, record) in records
            record isa AbstractDict || continue
            haskey(entries, (group, id)) && continue
            links = String[]
            for field in ("f_bus", "t_bus", "gen_bus", "load_bus", "shunt_bus",
                "busac_i", "fbusdc", "tbusdc", "busdc_i")
                haskey(record, field) || continue
                busgroup = field in ("fbusdc", "tbusdc", "busdc_i") ? "busdc" : "bus"
                push!(links, "$field=" * buses[(busgroup, record[field])])
            end
            isempty(links) && error("unkeyed PowerModels entry $group.$id")
            entries[(group, id)] = "$group#helper[" * join(links, ";") * "]"
        end
    end
    for group in unique(first.(keys(entries)))
        names = [v for ((g, _), v) in entries if g == group]
        allunique(names) || error("duplicate $group entry names")
    end
    return entries
end

function record_pm!(rows, labels, prefix, data, entries)
    for group in sort!(collect(keys(data)))
        records = data[group]
        if records isa AbstractDict && all(v -> v isa AbstractDict, values(records))
            for id in sort!(collect(keys(records)))
                name = entries[(group, id)]
                value = records[id]
                record!(rows, labels, "$prefix.$group.$name", value)
            end
        else
            record!(rows, labels, "$prefix.$group", records)
        end
    end
end

function plain_dump(io, path, value)
    if value isa AbstractDict
        for key in sort!(collect(keys(value)); by = string)
            plain_dump(io, isempty(path) ? string(key) : "$path.$key", value[key])
        end
    else
        println(io, path, " = ", repr(value))
    end
end

function structure_rows(value, path = "", rows = Tuple{String, String, String}[])
    type = string(typeof(value))
    if value isa Function
        push!(rows, (path, type, ""))
    elseif value isa Number
        formatted = value isa AbstractFloat ? @sprintf("%.17g", value) : repr(value)
        push!(rows, (path, type, formatted))
    elseif value isa Union{Symbol, AbstractString, Type, Nothing, Missing}
        push!(rows, (path, type, repr(value)))
    elseif value isa AbstractArray
        for index in CartesianIndices(value)
            structure_rows(value[index], "$path[$(join(Tuple(index), ','))]", rows)
        end
        isempty(value) && push!(rows, (path, type, repr(value)))
    elseif value isa Tuple
        for (i, item) in enumerate(value)
            structure_rows(item, "$path.$i", rows)
        end
    elseif parentmodule(typeof(value)) === PI || value isa NamedTuple
        for field in fieldnames(typeof(value))
            structure_rows(getfield(value, field), "$path.$field", rows)
        end
    else
        push!(rows, (path, type, ""))
    end
    return rows
end

function write_structure(directory, fixture, state)
    mkpath(directory)
    open(joinpath(directory, "$(fixture).tsv"), "w") do io
        println(io, "path\ttype\tvalue")
        for name in (:c1, :c2), field in (:element_model, :setpoint, :limits)

            element = state.elements[name]
            for row in structure_rows(getfield(element, field), "$fixture.$name.$field")
                println(io, join(row, '\t'))
            end
        end
    end
end

function oracle_voltage!(rows, labels)
    model = ParityFixtures.PSCADFixtures.mmc_pq_network().elements.DUT
    reactive = model.delta_control.outer_reactive
    F = zeros(1)
    sp = PI.TerminalValuesPU(v_ac = 1.2, q_ac = -0.217)
    meas = (; vG_d_f = 0.891, vG_q_f = -0.133, Q_ac_f = -0.178)
    x = (; ξ_Q_ac = -0.087)
    result = PI.state_space!(F, x, (; meas), sp, reactive, model)
    prefix = "oracle.converter_voltage_mmc_nosupport"
    record!(rows, labels, "$prefix.F", F)
    record!(rows, labels, "$prefix.outputs", result)
end

function oracle_droop!(rows, labels)
    for kind in (:mmc, :tlc), order in (0, 2)

        model = ParityFixtures.Droop.converter(kind).element_model
        block = kind == :mmc ? model.delta_control.outer_active : model.outerActive
        point = PI.TerminalValuesPU(p_ac = 0.3, v_dc = 1.05)
        x = (; ξ_vdc_supp = 0.017, ξ_P_ac = 0.071)
        for (i, voltage) in enumerate((0.97, 1.05, 1.1))
            F = zeros(2)
            inputs = (; meas = (; P_ac_f = 0.21, v_dc_f = voltage),
                sync = (; ω_c = 0.98))
            outputs = PI.state_space!(F, x, inputs, point, block, model)
            record!(rows, labels, "oracle.droop_$kind.order$order.case$i.F", F)
            record!(rows, labels, "oracle.droop_$kind.order$order.case$i.outputs", outputs)
        end
    end
end

function pscad_operating_point!(rows, labels, name, state)
    P = PI.PSCAD
    data, bases, mapping = convert(state, PI.PMACDC)
    # The frozen synthetic runs used bounded AC bus voltages.
    result = NB.solve_acdcpf(data, PI._PM.ACPPowerModel,
        NB.powerflow_optimizer(state.options), (; bus_voltage = true);
        setting = NB.powerflow_setting(state.options))
    point = NB._operating_point(result, bases, state, mapping)
    pf = PI.PowerFlowResult(NB.ACDCPowerFlow(), result, data,
        NB._node_bus_mapping(state.topology), mapping, point, (;))
    list = P.netlist(state, pf)
    plan = P.build_plan(list)
    probe_mapping = PSCADProbeNames.name_map(list, plan.probes)
    names = probe_mapping.names
    frozen = load_labels(joinpath(@__DIR__, "../reference/v2/labels.tsv"))
    voltage_order = String[]
    index = 1
    while haskey(frozen, "pscad_op.$name.$index.quantity")
        quantity = frozen["pscad_op.$name.$index.quantity"]
        if quantity in ("voltage_rms", "voltage_dc")
            label = frozen["pscad_op.$name.$index.name"]
            push!(voltage_order, get(names, label, label))
        end
        index += 1
    end
    voltages = filter(c -> c.kind == :voltage, plan.probes.channels)
    voltage_name(c) = c.pole === nothing ? c.name : P.voltage_probe_name(c.bus)
    Set(voltage_order) == Set(voltage_name(c) for c in voltages) ||
        error("frozen voltage channels differ for $name")
    sort!(voltages; by = c -> findfirst(==(voltage_name(c)), voltage_order),
        alg = Base.Sort.MergeSort)
    ordered = [filter(c -> c.kind != :voltage, plan.probes.channels); voltages]
    probes = P.ProbeManifest(ordered, plan.probes.reference_bus)
    settings = P.SimulationSettings(sample_step = 250e-6)
    model = PI.PSCADModel("synthetic.pscx", "synthetic", list, probes,
        settings, list.operating_point, (;))
    times = collect(0.0:250e-6:0.3)
    channels = PI.OrderedDict{String, Vector{Float64}}()
    for (index, channel) in enumerate(probes.channels)
        polarity = get(probe_mapping.polarities, channel.name, 1)
        if channel.dim == 3
            for phase in 1:3
                angle = 0.01index - 2π * (phase - 1) / 3
                channels["$(channel.name):$phase"] = polarity .* ((1.0 + index) .*
                    cos.(2π * 50 .* times .+ angle))
            end
        else
            channels[channel.name] = fill(polarity * (1.0 + index), length(times))
        end
    end
    result = PI.PSCADResult(PI.PSCADRun(), times, channels, probes,
        settings, (;), (;))
    table = PI.compare_operating_point(result, model)
    for (i, row) in enumerate(table)
        record!(rows, labels, "pscad_op.$name.$i", NamedTuple(row))
    end
    println("PSCAD synthetic fixture=", name, " channels=",
        join((c.name for c in probes.channels), ','))
    return probe_mapping
end

function exception_text(exception, backtrace)
    return sprint(showerror, exception, backtrace)
end

function collect_family!(action, rows, labels, skipped, errors, key;
        skipped_families = ())
    if key in skipped_families
        push!(skipped, key)
        return (; ok = false, value = nothing)
    end
    local_rows, local_labels = Row[], Dict{String, String}()
    try
        value = action(local_rows, local_labels)
        append!(rows, local_rows)
        merge!(labels, local_labels)
        return (; ok = true, value)
    catch exception
        push!(skipped, key)
        push!(errors, key => exception_text(exception, catch_backtrace()))
        return (; ok = false, value = nothing)
    end
end

function collect_oracles()
    rows, labels = Row[], Dict{String, String}()
    skipped, errors = String[], Pair{String, String}[]
    collect_family!(
        rows, labels, skipped, errors, "oracle.converter_voltage_mmc_nosupport") do r, l
        oracle_voltage!(r, l)
    end
    collect_family!(rows, labels, skipped, errors, "oracle.droop") do r, l
        oracle_droop!(r, l)
    end
    pscad_name_maps = Dict{String, Dict{String, String}}()
    pscad_polarities = Dict{String, Dict{String, Int}}()
    for name in (:small_ac, :sm, :mmc_pq, :tlc_case2)
        result = collect_family!(rows, labels, skipped, errors, "pscad_op.$name") do r, l
            build = getfield(ParityFixtures.PSCADFixtures, Symbol(name, "_network"))
            pscad_operating_point!(r, l, string(name), build())
        end
        if result.ok
            pscad_name_maps[string(name)] = result.value.names
            pscad_polarities[string(name)] = result.value.polarities
        end
    end
    result = collect_family!(rows, labels, skipped, errors, "stability.mmc_vdc") do r, l
        fixture = only(f for f in ParityFixtures.FIXTURES if f.name == :mmc_vdc)
        builder, element, direction = fixture.build(), :DUT, :dc
        freq_range, order_maxima = (1.0, 1.0e3, 1000), 5
        response, nodes, frequencies, model = NB._check_stability_response(
            builder, element; direction, freq_range)
        checkpoint = PI.FrequencyResponseResult(PI.LoopGain(), :loopgain, response,
            frequencies, nodes, model, (; element, direction))
        calculated = compute(PI.StabilityProblem(checkpoint),
            PI.GeneralizedNyquist(; order_maxima))
        completed = PI.StabilityResult(calculated.formulation, calculated.analysis,
            calculated.output, (; element, direction))
        formulation = (; completed.formulation.backend, completed.formulation.order_maxima)
        fields = (;
            formulation, completed.analysis, completed.output, completed.diagnostics)
        record!(r, l, "stability.mmc_vdc", fields)
    end
    stability_fixture = result.ok ? "mmc_vdc" : ""
    return (; rows, labels, skipped, errors, stability_fixture, pscad_name_maps,
        pscad_polarities)
end

# Frozen Setpoint powers enter induction machines and converter DC ports.
const SETPOINT_POWER_SIGNS = (
    Source = (ac = -1, dc = -1),
    SynchronousMachine = (ac = -1, dc = 1),
    InductionMachine = (ac = 1, dc = 1),
    MMC = (ac = -1, dc = 1),
    TLC = (ac = -1, dc = 1),
    Blackbox_MMC = (ac = -1, dc = 1),
)

function record_operating_point!(rows, labels, name, state, point)
    for (element, values) in point.values
        # The frozen operating-point datasets omit sources.
        PI.is_source(state.elements[element]) && continue
        signs = get(SETPOINT_POWER_SIGNS, nameof(typeof(state.elements[element])),
            (ac = 1, dc = 1))
        fields = (;)
        if haskey(values, :ac)
            ac = values.ac
            fields = (; Pac = signs.ac * ac.p, Qac = signs.ac * ac.q,
                Vac = ac.v, θac = ac.theta)
        end
        if haskey(values, :dc)
            dc = values.dc
            fields = merge(fields, (; Pdc = signs.dc * dc.p, Vdc = dc.v))
        end
        record!(rows, labels, "$name.op.$element", fields)
    end
end

function record_state_space!(rows, labels, name, state, point)
    for (element, value) in pairs(state.elements)
        !PI.islinear(value) && PI.is_active(value) || continue
        A, B, C, D = PI.linearize(value, point[element])
        for (field, matrix) in (("A", A), ("B", B), ("C", C), ("D", D))
            record!(rows, labels, "$name.ss.$element.$field", matrix)
        end
        record!(rows, labels, "$name.ss.$element.x", value.cache.state)
        eig = sort!(eigvals(A); by = v -> (real(v), imag(v)))
        record!(rows, labels, "$name.ss.$element.eig", eig)
    end
end

function record_admittances!(rows, labels, name, state, point, frequencies)
    for (element, value) in pairs(state.elements)
        PI.is_source(value) && continue
        connections = NB.sortedcomponentconnections(state.topology, element;
            withground = true, acfirst = false)
        admittance! = NB.build(value, get(point, element, (;)),
            NB._component_frame(connections))
        n = length(connections.net)
        response = Array{ComplexF64, 3}(undef, n, n, length(frequencies))
        admittance!(response, frequencies)
        record!(rows, labels, "$name.y.$element", response)
    end
end

function collect_fixture(fixture; dump_directory = nothing,
        network_level_skipped = false, skipped_families = ())
    @nospecialize fixture
    rows, labels = Row[], Dict{String, String}()
    skipped, errors = String[], Pair{String, String}[]
    state = fixture.build()
    name = string(fixture.name)
    conversion_skipped = false
    for (node, (domain, bus)) in NB._node_bus_mapping(state.topology)
        record!(rows, labels, "$name.nodes.$node.domain", domain)
        record!(rows, labels, "$name.nodes.$node.bus", bus)
    end
    if dump_directory !== nothing && fixture.name in (:p2p_alt, :p2p_gridspace_nominal)
        write_structure(joinpath(dump_directory, "structure"), fixture.name, state)
    end
    converted = collect_family!(rows, labels, skipped, errors, "$name.pm";
        skipped_families) do r, l
        data, _, mapping = convert(state, PI.PMACDC)
        entries = entry_keys(state, data, mapping)
        record_pm!(r, l, "$name.pm", data, entries)
        if dump_directory !== nothing
            open(joinpath(dump_directory, "$name.data.txt"), "w") do io
                plain_dump(io, "", data)
            end
        end
        (; data, entries)
    end
    if fixture.name == :connection_dsl
        conversion_skipped = !converted.ok
        converted.ok && error("connection_dsl unexpectedly has PowerModels input")
        return (; rows, labels, state, skipped, errors, network_level_skipped,
            conversion_skipped)
    end
    powerflow = collect_family!(rows, labels, skipped, errors, "$name.pf";
        skipped_families) do r, l
        result = compute(NB.PowerFlowProblem(state), NB.ACDCPowerFlow())
        converted.ok || error("PowerModels entry names are unavailable")
        record_pm!(r, l, "$name.pf", result.result["solution"], converted.value.entries)
        l["$name.pf.termination_status"] = string(result.result["termination_status"])
        if dump_directory !== nothing
            open(joinpath(dump_directory, "$name.solution.txt"), "w") do io
                plain_dump(io, "", result.result)
            end
        end
        result
    end
    if !powerflow.ok
        for family in ("op", "ss", "y", "ynode", "yedge", "zdet")
            push!(skipped, "$name.$family")
            push!(errors, "$name.$family" => "power-flow operating point unavailable")
        end
        return (; rows, labels, state, skipped, errors, network_level_skipped,
            conversion_skipped)
    end
    point = powerflow.value.operating_point
    collect_family!(rows, labels, skipped, errors, "$name.op"; skipped_families) do r, l
        record_operating_point!(r, l, name, state, point)
    end
    collect_family!(rows, labels, skipped, errors, "$name.ss"; skipped_families) do r, l
        record_state_space!(r, l, name, state, point)
    end
    frequencies = ComplexF64.(2π * im .* collect(FREQUENCIES))
    collect_family!(rows, labels, skipped, errors, "$name.y"; skipped_families) do r, l
        record_admittances!(r, l, name, state, point, frequencies)
    end
    if !network_level_skipped
        model = NB.NetworkModel(state, point)
        indices = [model.indices.nodes[n] for n in fixture.probes.nets]
        selected = NB.NetworkModel(model.element_admittances, model.active_elements,
            model.passive_elements, model.grounded_nodes, indices, model.indices)
        collect_family!(rows, labels, skipped, errors, "$name.ynode";
            skipped_families) do r, l
            record!(r, l, "$name.ynode", NB.make_y_node(selected, frequencies))
        end
        collect_family!(rows, labels, skipped, errors, "$name.yedge";
            skipped_families) do r, l
            record!(r, l, "$name.yedge", NB.make_y_edge(selected, frequencies))
        end
        collect_family!(rows, labels, skipped, errors, "$name.zdet";
            skipped_families) do r, l
            for (i, f) in enumerate(FREQUENCIES)
                impedance,
                omega = NB.determine_impedance(model; nets = fixture.probes.nets,
                    elim_elements = fixture.probes.elim_elements, freq_range = (f, f, 1))
                record!(r, l, "$name.zdet.$i.response", impedance)
                record!(r, l, "$name.zdet.$i.frequencies", omega)
            end
        end
    end
    return (; rows, labels, state, skipped, errors, network_level_skipped,
        conversion_skipped)
end

function write_rows(path, rows)
    sort!(rows; by = r -> r[1:4])
    allunique(r[1:4] for r in rows) || error("duplicate numeric coordinates")
    open(path, "w") do io
        println(io, "dataset,i,j,k,real,imag")
        for row in rows
            @printf(io, "%s,%d,%d,%d,%.17g,%.17g\n", row...)
        end
    end
end

function write_labels(path, labels)
    open(path, "w") do io
        println(io, "dataset\tvalue")
        for name in sort!(collect(keys(labels)))
            println(io, name, '\t', labels[name])
        end
    end
end

function load_rows(path)
    result = Dict{Tuple{String, Int, Int, Int}, ComplexF64}()
    for line in Iterators.drop(eachline(path), 1)
        name, i, j, k, re, im = split(line, ',')
        key = (name, parse(Int, i), parse(Int, j), parse(Int, k))
        haskey(result, key) && error("duplicate numeric coordinate $key")
        result[key] = complex(parse(Float64, re), parse(Float64, im))
    end
    return result
end

function load_labels(path)
    Dict(Tuple(split(line, '\t'; limit = 2)) for line in
                                                 Iterators.drop(eachline(path), 1))
end
load_metadata(path) = Dict(Tuple(split(line, '='; limit = 2)) for line in eachline(path))
file_sha(path) = bytes2hex(sha256(read(path)))
end
