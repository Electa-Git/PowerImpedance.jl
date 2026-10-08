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

Build a pure Julia plan for passive AC export. Emit sources, branches, shunts,
then bus probes into separate layout cells, using node labels to join buses.
No files are written and no power flow is solved.

# Arguments

- `netlist`: Materialized connectivity and optional operating-point evidence.
- `settings`: Simulation settings; frequency must match the netlist \\[Hz\\].
- `name`: ASCII project identifier.
- `description`: Project description, defaulting to `name`.

# Returns

- A `ProjectPlan` containing the Main schematic, file settings and probes.
"""
function build_plan(netlist::Netlist; settings::SimulationSettings = SimulationSettings(),
        name::AbstractString = "network", description::AbstractString = name)
    settings.frequency == netlist.frequency ||
        throw(ArgumentError("PSCAD settings frequency must match the network's $(netlist.frequency) Hz frame"))
    name == pscad_name(name) ||
        throw(ArgumentError("name must be an ASCII PSCAD identifier of at most 30 characters"))
    used = Set(vcat([bus.name for bus in netlist.buses], [e.pscad for e in netlist.elements]))
    state = PlanState(CanvasPlan(), GridLayout(), ProbeChannel[], used)
    context = (; netlist, settings, buses = Dict(bus.key => bus for bus in netlist.buses))
    elements = sort(netlist.elements;
        by = e -> e.role == :source ? 1 :
                  e.role in (:shunt, :load) ? 3 : 2,
        alg = Base.Sort.MergeSort)
    for e in elements
        emit!(state, e, context)
    end
    for bus in netlist.buses
        voltage_probe!(state, bus)
    end
    reference_key = netlist.operating_point.slack_bus
    if reference_key === nothing
        # Linear NB networks still have an angle-reference channel, even though
        # no solved operating point is available for comparison.
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
    return ProjectPlan(String(name), String(description),
        _project_settings(settings, String(description)), state.main, manifest)
end

function _export_keywords(path, name, line_options, dc_reference)
    dc_reference in (:midpoint_resistors, :none) ||
        throw(ArgumentError("dc_reference must be :midpoint_resistors or :none"))
    line_options isa NamedTuple || throw(ArgumentError("line_options must be a NamedTuple"))
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

function _export_project(netlist, path, name, settings, resolved_powerflow)
    plan = build_plan(netlist; settings, name, description = "PowerImpedance.jl: $name")
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

Export a passive AC network to a portable, single-subsystem `.pscx` project.
Load `PythonCall` to enable the mhi-xml writer. Validate keywords and require
the extension before solving power flow or writing the project.

# Arguments

- `net`: Classic network, or a materialized `NetworkBuilder.NetworkState`.
- `path`: New output `.pscx` path whose parent directory already exists.
- `name`: Project identifier, defaulting to and required to equal the path stem.
- `powerflow`: Optional classic four-tuple from `power_flow(net)`. A builder
  state uses `NetworkBuilder.solve` and accepts only `nothing` here.
- `settings`: Detached-run settings, default `SimulationSettings()`.
- `line_options`: Named tuple reserved for the line-export step.
- `dc_reference`: `:midpoint_resistors` (default) or `:none`, reserved for DC export.

# Returns

- A `PSCADModel` retaining the project path, netlist, probes, settings,
  operating point and version/time provenance. `resolved_powerflow` records
  whether this export ran a power-flow solve.

# Notes

Without `powerflow`, the classic method calls `power_flow(net)`, which mutates
active-element setpoints and emits solver logs. These mutations are retained.
Pass a previously solved tuple to avoid re-solving. The builder method calls
`NetworkBuilder.solve`; linear networks skip power flow, use source setpoints,
and retain no solved comparison data. This function never contacts PSCAD.
"""
function export_pscad(net::PowerImpedance.Network; path,
        name = splitext(basename(path))[1], powerflow = nothing,
        settings::SimulationSettings = SimulationSettings(), line_options = (;),
        dc_reference = :midpoint_resistors)
    _export_keywords(path, name, line_options, dc_reference)
    _require_extension()
    pf = powerflow === nothing ? PowerImpedance.power_flow(net) : powerflow
    return _export_project(netlist(net, pf), path, name, settings, powerflow === nothing)
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
    return _export_project(netlist(state, solved.powerflow), path, name, settings,
        solved.powerflow !== nothing)
end
