function _project_settings(settings::SimulationSettings, description)
    snapshot = settings.snapshot_time
    return SettingsPlan([
        "time_duration" => pscad_value(settings.simulation_time),
        "time_step" => pscad_value(settings.time_step * 1e6),
        "sample_step" => pscad_value(settings.sample_step * 1e6),
        "PlotType" => "1", "output_filename" => settings.output_stem * ".out",
        "SnapType" => snapshot === nothing ? "0" : "1",
        "SnapTime" => pscad_value(snapshot === nothing ? 0.0 : snapshot),
        "snapshot_filename" => settings.output_stem * ".snp",
        "StartType" => "0", "MrunType" => "0", "Mruns" => "1",
        "creator" => "PowerImpedance.jl $(Base.pkgversion(PowerImpedance))",
        "description" => description])
end

"""
$(TYPEDSIGNATURES)

Build a PSCAD project plan for an AC/DC network, including synchronous machines.
Place sources, branches, shunts, DC references and bus probes in separate cells.
Node labels connect the buses. Build the plan in memory without file access
or a power-flow solve.

# Arguments

- `netlist`: Network connectivity and optional solved operating point.
- `settings`: Simulation settings. Default: `SimulationSettings()`.
  Frequency \\[Hz\\] must equal the network frequency.
- `name`: ASCII project identifier. Default: `"network"`.
- `description`: Project description. Default: `name`.
- `line_options`: PSCAD ground and frequency/phase parameter overrides.
  Default: an empty named tuple.
- `dc_reference`: `:midpoint_resistors` (default) adds two grounding resistors
  per DC bus without a local source midpoint or grounded shunt.
  `:none` omits those resistors.

# Returns

- A `ProjectPlan` with the Main schematic, line rows, modules, settings and probes.
"""
function build_plan(netlist::Netlist; settings::SimulationSettings = SimulationSettings(),
        name::AbstractString = "network", description::AbstractString = name,
        line_options = (;), dc_reference = :midpoint_resistors)
    dc_reference in (:midpoint_resistors, :none) ||
        throw(ArgumentError("dc_reference must be :midpoint_resistors or :none"))
    overrides = _line_options(line_options)
    settings.frequency == netlist.frequency ||
        throw(ArgumentError("PSCAD settings frequency must match the network's $(netlist.frequency) Hz frame"))
    name == pscad_name(name) ||
        throw(ArgumentError("name must be an ASCII PSCAD identifier of at most 30 characters"))
    used = _NameReservations(vcat([bus.name for bus in netlist.buses], [e.pscad
                                                                        for e in netlist.elements]))
    dc_labels = Dict(bus.key => (pscad_name(bus.name * "_P"; used),
                         pscad_name(bus.name * "_N"; used))
    for bus in netlist.buses if bus.kind == :dc)
    state = PlanState(
        CanvasPlan(AbstractComponentPlan[], WirePlan[], used,
            Dict{String, Union{Nothing, String}}()), AbstractLineDefinitionPlan[], AbstractLineWrapperPlan[],
        ModuleDefinitionPlan[], GridLayout(), ProbeChannel[], used)
    context = (; netlist, settings, name, line_options = overrides, dc_labels,
        buses = Dict(bus.key => bus for bus in netlist.buses))
    if any(e -> e.model isa Union{PowerImpedance.TLC, PowerImpedance.MMC}, netlist.elements)
        abc = abc_to_dq_module(pscad_name("ABC_DQ"; used))
        dq = dq_to_abc_module(pscad_name("DQ_ABC"; used))
        append!(state.modules, [abc, dq])
        context = merge(context,
            (;
                converter_transforms =
            (; abc = name * ":" * abc.name, dq = name * ":" * dq.name)))
    end
    elements = sort(netlist.elements;
        by = e -> e.role == :source ? 1 :
                  e.role in (:shunt, :load) ? 3 : 2,
        alg = Base.Sort.MergeSort)
    for e in elements
        emit!(state, e, context)
    end
    precharge_buses = _dc_precharge_buses(netlist)
    for bus in precharge_buses
        dc_precharge!(state, bus, context)
    end
    for bus in netlist.buses
        labels = bus.kind == :dc ? dc_labels[bus.key] : (bus.name,)
        if bus.kind == :dc && dc_reference == :midpoint_resistors
            grounded = any(netlist.elements) do e
                any(t -> t.bus == bus.key, e.terminals) &&
                    (e.model isa PowerImpedance.Source ||
                     (e.model isa PowerImpedance.Impedance &&
                      any(t -> t.grounded, e.terminals)))
            end
            grounded || dc_reference!(state, bus, labels)
        end
        voltage_probe!(state, bus, labels;
            at_conducting_node = any(b -> b.key == bus.key, precharge_buses))
    end
    reference_key = netlist.operating_point.slack_bus
    if reference_key === nothing
        # Linear builder networks use the first AC source for the angle reference
        # because a solved operating point is unavailable.
        source = findfirst(
            e -> e.model isa PowerImpedance.Source &&
                 any(t -> t.bus !== nothing && t.bus.domain == 1, e.terminals),
            elements)
        if source !== nothing
            reference_key = first(filter(t -> t.bus !== nothing && t.bus.domain == 1,
                elements[source].terminals)).bus
        end
    end
    reference = reference_key === nothing ? nothing : context.buses[reference_key].name
    manifest = ProbeManifest(state.channels, reference)
    plan = ProjectPlan(String(name), String(description),
        _project_settings(settings, String(description)), state.main,
        state.lines, state.wrappers, state.modules, manifest)
    check_connectivity(plan)
    return plan
end

function _export_keywords(path, name, line_options, dc_reference)
    dc_reference in (:midpoint_resistors, :none) ||
        throw(ArgumentError("dc_reference must be :midpoint_resistors or :none"))
    _line_options(line_options)
    path isa AbstractString && endswith(path, ".pscx") ||
        throw(ArgumentError("PSCAD export path must end in .pscx"))
    isdir(dirname(abspath(path))) ||
        throw(ArgumentError("PSCAD export parent directory must exist: $path"))
    !ispath(path) && !islink(path) ||
        throw(ArgumentError("PSCAD export target already exists: $path"))
    name isa AbstractString && name == pscad_name(name) ||
        throw(ArgumentError("name must be an ASCII PSCAD identifier of at most 30 characters"))
    name == splitext(basename(path))[1] ||
        throw(ArgumentError("PSCAD project name must equal the path stem"))
    return nothing
end

function _export_project(
        netlist, path, name, settings, resolved_powerflow, line_options, dc_reference)
    if settings.time_step > 1e-6
        converters = [string(e.name) for e in netlist.elements
                      if e.model isa PowerImpedance.MMC &&
                         e.model.modulation isa PowerImpedance.CompensatedModulation]
        if !isempty(converters)
            @warn "MMC with CompensatedModulation ($(join(converters, ", "))): time_step=$(settings.time_step) s exceeds the validated step of 1 us; 10 us grows unstable."
        end
    end
    plan = build_plan(netlist; settings, name, line_options, dc_reference,
        description = "PowerImpedance.jl: $name")
    written = _write_project(plan, abspath(path))
    provenance = (source = :export,
        powerimpedance_version = string(Base.pkgversion(PowerImpedance)),
        mhi_xml_version = written.mhi_xml_version, created = string(now(UTC)),
        resolved_powerflow = resolved_powerflow)
    return PSCADModel(written.path, String(name), netlist, plan.probes, settings,
        netlist.operating_point, provenance)
end

"""
$(TYPEDSIGNATURES)

Export an AC/DC network as a portable `.pscx` project with one subsystem.
Use `PythonCall` to enable the `mhi-xml` writer. Check the keywords and extension
availability before the power-flow solve or project write.

# Arguments

- `net`: Classic network or a materialized `NetworkBuilder.NetworkState`.
- `path`: New `.pscx` filename in an existing directory.
- `name`: Project identifier, equal to the path stem. Default: the path stem.
- `powerflow`: Classic four-tuple returned by `power_flow(net)`, or `nothing`
  (default). Builder states accept only `nothing` and use `NetworkBuilder.solve`.
- `settings`: Simulation settings. Default: `SimulationSettings()`.
- `line_options`: Named tuple of PSCAD ground and frequency/phase overrides.
  Default: empty. An example is `(; FS = 0.5, FE = 1e6, Numf = 200, CPASS = 0)`.
  Numbers use PSCAD field units. Strings retain explicit units.
- `dc_reference`: `:midpoint_resistors` (default) adds two resistors of
  `1e7` \\[Ω\\] to ground per DC bus without a local source midpoint or grounded
  shunt. `:none` omits those resistors.

# Returns

- A `PSCADModel` with project path, netlist, probes, settings, operating point,
  package versions and export timestamp. `resolved_powerflow` records whether
  this call solved power flow.

# Notes

For a classic network, `powerflow = nothing` calls `power_flow(net)`, retaining
its changes to active-element setpoints and its solver logs. Supply a solved
tuple to reuse that solution. For a builder state, `NetworkBuilder.solve` skips
power flow for linear networks, which use source setpoints and have no solved
comparison data. Export never contacts the station.

DC source and converter `Setpoint.Vdc` are pole-to-pole voltages \\[kV\\].
Without a solved result, each pole source uses `Setpoint.Vdc / 2`.
With a solved result, each pole source uses `vm_pu * base_kV` \\[kV\\]
relative to ground.

# Errors

- Throws `ArgumentError` for unknown line fields before solving power flow.
"""
function export_pscad(net::PowerImpedance.Network; path,
        name = splitext(basename(path))[1], powerflow = nothing,
        settings::SimulationSettings = SimulationSettings(), line_options = (;),
        dc_reference = :midpoint_resistors)
    _export_keywords(path, name, line_options, dc_reference)
    _require_extension()
    pf = powerflow === nothing ? PowerImpedance.power_flow(net) : powerflow
    return _export_project(netlist(net, pf), path, name, settings,
        powerflow === nothing, line_options, dc_reference)
end

function export_pscad(state::PowerImpedance.NetworkBuilder.NetworkState; path,
        name = splitext(basename(path))[1], powerflow = nothing,
        settings::SimulationSettings = SimulationSettings(), line_options = (;),
        dc_reference = :midpoint_resistors)
    _export_keywords(path, name, line_options, dc_reference)
    _require_extension()
    powerflow === nothing ||
        throw(ArgumentError("builder export obtains power flow from NetworkBuilder.solve; powerflow must be nothing"))
    solved = PowerImpedance.NetworkBuilder.solve(state)
    elements = NamedTuple{keys(state.elements)}(
        Tuple(solved.network.elements[name] for name in keys(state.elements)))
    return _export_project(netlist(state, solved.powerflow, elements), path, name, settings,
        solved.powerflow !== nothing, line_options, dc_reference)
end
