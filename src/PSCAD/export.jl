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
- `ztool_probes`: Export-only scan requests. Default: an empty vector.
  An unsolved bus requires an explicit `ZToolProbe` voltage in \\[kV\\].

# Returns

- A `ProjectPlan` with the Main schematic, line rows, modules, settings and probes.
"""
function build_plan(netlist::Netlist; settings::SimulationSettings = SimulationSettings(),
        name::AbstractString = "network", description::AbstractString = name,
        line_options = (;), dc_reference = :midpoint_resistors, ztool_probes = ZToolProbe[])
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
    scans = _resolve_ztool_probes(netlist, ztool_probes)
    # Keep generated terminal labels distinct from every requested scan name.
    # Existing component names remain reserved for the duplicate-name check.
    reserved = String[]
    for scan in scans
        scan.probe.name in used && continue
        push!(used, scan.probe.name)
        push!(reserved, scan.probe.name)
    end
    ztool_terminals = Dict{Tuple{Symbol, Symbol}, Tuple{Vararg{String}}}()
    for scan in scans
        (; probe, bus, terminal) = scan
        terminal === nothing && continue
        inner = pscad_name(probe.name * "_terminal"; used)
        ztool_terminals[(probe.element, probe.port)] = probe.kind == :dc ?
            (inner, last(dc_labels[bus.key])) : (inner,)
    end
    for scan_name in reserved
        delete!(used, scan_name)
    end
    state = PlanState(
        CanvasPlan(AbstractComponentPlan[], WirePlan[], used,
            Dict{String, Union{Nothing, String}}()), AbstractLineDefinitionPlan[], AbstractLineWrapperPlan[],
        ModuleDefinitionPlan[], GridLayout(), ProbeChannel[], used)
    context = (; netlist, settings, name, line_options = overrides, dc_labels, ztool_terminals,
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
    for scan in scans
        _emit_ztool_probe!(state, scan, context)
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
        netlist, path, name, settings, resolved_powerflow, line_options, dc_reference,
        ztool_probes, ztool_library)
    if settings.time_step > 1e-6
        converters = [string(e.name) for e in netlist.elements
                      if e.model isa PowerImpedance.MMC &&
                         e.model.modulation isa PowerImpedance.CompensatedModulation]
        if !isempty(converters)
            @warn "MMC with CompensatedModulation ($(join(converters, ", "))): time_step=$(settings.time_step) s exceeds the validated step of 1 us; 10 us grows unstable."
        end
    end
    plan = build_plan(netlist; settings, name, line_options, dc_reference, ztool_probes,
        description = "PowerImpedance.jl: $name")
    library, workspace = nothing, nothing
    if !isempty(ztool_probes)
        lowercase(name) == "z_tool" && throw(ArgumentError("Z-tool project name must differ from the library name Z_tool"))
        library_path = joinpath(dirname(abspath(path)), "Z_tool.pslx")
        workspace = splitext(abspath(path))[1] * ".pswx"
        !ispath(workspace) && !islink(workspace) ||
            throw(ArgumentError("Z-tool workspace target already exists: $workspace"))
        source = _ztool_library(ztool_library)
        if ispath(library_path) || islink(library_path)
            isfile(library_path) && bytes2hex(open(sha256, library_path)) == source.sha256 ||
                throw(ArgumentError("Z-tool export library differs from $library_path"))
        end
        library = (; path = library_path, sha256 = source.sha256)
    end
    written = _write_project(plan, abspath(path))
    if library !== nothing
        isfile(library.path) || cp(source.path, library.path)
        write(workspace, _ztool_workspace(String(name), basename(path)))
        _write_ztool_frequency_tables(dirname(written.path),
            _ztool_frequency_tables(settings.frequency))
    end
    provenance = (source = :export,
        powerimpedance_version = string(Base.pkgversion(PowerImpedance)),
        mhi_xml_version = written.mhi_xml_version, created = string(now(UTC)),
        resolved_powerflow = resolved_powerflow)
    return PSCADModel(written.path, String(name), netlist, plan.probes, settings,
        netlist.operating_point, provenance, library, workspace)
end

"""
$(TYPEDSIGNATURES)

Export an AC/DC network as a portable `.pscx` project with one subsystem.
Use `PythonCall` to enable the `mhi-xml` writer. Check the keywords and extension
availability before the power-flow solve or project write.

# Arguments

- `state`: Materialized `NetworkBuilder.NetworkState`.
- `path`: New `.pscx` filename in an existing directory.
- `name`: Project identifier, equal to the path stem. Default: the path stem.
- `powerflow`: `PowerFlowResult`, or `nothing` (default) to calculate it.
- `settings`: Simulation settings. Default: `SimulationSettings()`.
- `line_options`: Named tuple of PSCAD ground and frequency/phase overrides.
  Default: empty. An example is `(; FS = 0.5, FE = 1e6, Numf = 200, CPASS = 0)`.
  Numbers use PSCAD field units. Strings retain explicit units.
- `dc_reference`: `:midpoint_resistors` (default) adds two resistors of
  `1e7` \\[Ω\\] to ground per DC bus without a local source midpoint or grounded
  shunt. `:none` omits those resistors.
- `ztool_probes`: Export-only `ZToolProbe` requests. Default: empty.
- `ztool_library`: Local `.pslx` file, or `nothing` (default) to download and
  cache the SHA-256-checked Z-tool v0.1.52 library on first use. Exports with
  scan probes include `Z_tool.pslx` and a relative-path `.pswx` workspace.

# Returns

- A `PSCADModel` with project path, netlist, probes, settings, operating point,
  package versions and export timestamp. `resolved_powerflow` records whether
  this call solved power flow.

# Notes

With `powerflow = nothing`, calculate the operating point with
`compute(PowerFlowProblem(state), ACDCPowerFlow())` for every network. Bus voltages
and transformer ratings use that solution. Export never contacts the station.

DC source inputs and converter port values use pole-to-pole voltages \\[kV\\].
Without a solved result, each pole source uses half the declared voltage.
With a solved result, each pole source uses `vm_pu * base_kV` \\[kV\\]
relative to ground.

# Errors

- Throws `ArgumentError` for unknown line fields before solving power flow.
"""
function export_pscad(state::PowerImpedance.NetworkBuilder.NetworkState; path,
        name = splitext(basename(path))[1],
        powerflow::Union{Nothing, PowerImpedance.PowerFlowResult} = nothing,
        settings::SimulationSettings = SimulationSettings(), line_options = (;),
        dc_reference = :midpoint_resistors, ztool_probes = ZToolProbe[], ztool_library = nothing)
    _export_keywords(path, name, line_options, dc_reference)
    _require_extension()
    pf = powerflow === nothing ? PowerImpedance.compute(
        PowerImpedance.NetworkBuilder.PowerFlowProblem(state),
        PowerImpedance.NetworkBuilder.ACDCPowerFlow()) : powerflow
    return _export_project(netlist(state, pf), path, name, settings,
        powerflow === nothing && pf.result !== nothing, line_options, dc_reference,
        ztool_probes, ztool_library)
end
