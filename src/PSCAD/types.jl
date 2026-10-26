"""
$(TYPEDEF)

Specify duration, integration step, output interval and optional snapshot time
for a fresh PSCAD run. Duration, steps and frequency must be positive and
finite. The source ramp must be finite and nonnegative.
Require `sample_step >= time_step` and, for a snapshot,
`0 < snapshot_time <= simulation_time`.

$(TYPEDFIELDS)
"""
struct SimulationSettings
    "Simulation duration \\[s\\]."
    simulation_time::Float64
    "Integration time step \\[s\\]."
    time_step::Float64
    "Output sampling interval \\[s\\]."
    sample_step::Float64
    "Optional snapshot time \\[s\\]."
    snapshot_time::Union{Nothing, Float64}
    "Output filename stem of 1–20 ASCII characters, beginning with a letter."
    output_stem::String
    "Nominal network frequency \\[Hz\\]."
    frequency::Float64
    "Source ramp duration \\[s\\]. Zero applies the specified voltage immediately."
    source_ramp::Float64

    function SimulationSettings(; simulation_time = 2.0, time_step = 10e-6,
            sample_step = 100e-6, snapshot_time = nothing, output_stem = "pi",
            frequency = 50.0, source_ramp = 0.05)
        values = (simulation_time, time_step, sample_step, frequency)
        for (name, value) in zip(
            (:simulation_time, :time_step, :sample_step,
                :frequency), values)
            value isa Real && !(value isa Bool) && isfinite(value) && value > 0 ||
                throw(ArgumentError("$name must be positive and finite"))
        end
        source_ramp isa Real && !(source_ramp isa Bool) && isfinite(source_ramp) &&
        source_ramp >= 0 ||
            throw(ArgumentError("source_ramp must be nonnegative and finite"))
        duration, step, sample, freq = Float64.(values)
        ramp = Float64(source_ramp)
        all(isfinite, (duration, step, sample, freq, ramp)) &&
        all(>(0), (duration, step, sample, freq)) ||
            throw(ArgumentError("simulation settings must be representable as positive finite Float64 values"))
        sample >= step || throw(ArgumentError("sample_step must be at least time_step"))
        snapshot = if snapshot_time === nothing
            nothing
        else
            snapshot_time isa Real && !(snapshot_time isa Bool) &&
            isfinite(snapshot_time) && 0 < snapshot_time <= duration ||
                throw(ArgumentError("snapshot_time must satisfy 0 < snapshot_time <= simulation_time"))
            value = Float64(snapshot_time)
            0 < value <= duration ||
                throw(ArgumentError("snapshot_time is not representable in seconds"))
            value
        end
        output_stem isa AbstractString &&
        occursin(r"^[A-Za-z][A-Za-z0-9_]{0,19}$", output_stem) ||
            throw(ArgumentError("output_stem must match ^[A-Za-z][A-Za-z0-9_]{0,19}\$"))
        return new(duration, step, sample, snapshot, String(output_stem), freq, ramp)
    end
end

"""
$(TYPEDEF)

Describe a measured PSCAD channel and its bus or element.
Exported terminal current probes measure current into the component.

$(TYPEDFIELDS)
"""
struct ProbeChannel
    "Output channel name."
    name::String
    "Measured quantity kind."
    kind::Symbol
    "Bus name, when applicable."
    bus::Union{Nothing, String}
    "Component name, when applicable."
    element::Union{Nothing, String}
    "Electrical port name for element channels, when applicable."
    port::Union{Nothing, Symbol}
    "P/N pole for DC voltage channels, when applicable."
    pole::Union{Nothing, String}
    "Number of measured components."
    dim::Int
    "Physical unit recorded for the channel."
    unit::String
    "Positive current direction (`:into` or `:out`), or `nothing` for other quantities."
    orientation::Union{Nothing, Symbol}
    function ProbeChannel(name, kind, bus, element, port, dim, unit,
            orientation = nothing; pole = nothing)
        if kind in (:current, :injection_current)
            orientation in (:into, :out) ||
                throw(ArgumentError("terminal current probe requires :into or :out orientation"))
        else
            orientation === nothing ||
                throw(ArgumentError("only terminal current probes have orientation"))
        end
        return new(name, kind, bus, element, port, pole, dim, unit, orientation)
    end
end

"""
$(TYPEDEF)

Store the requested channels and optional voltage-angle reference bus.
`ProbeManifest()` constructs an empty manifest for a hand-built project.

$(TYPEDFIELDS)
"""
struct ProbeManifest
    "Channels in the requested physical order."
    channels::Vector{ProbeChannel}
    "Optional bus used as the voltage-angle reference."
    reference_bus::Union{Nothing, String}
end
ProbeManifest() = ProbeManifest(ProbeChannel[], nothing)

"""
$(TYPEDEF)

Store a PSCAD project, measurement manifest, simulation settings, and optional
network and operating-point records. Construction stores these records locally.

$(TYPEDFIELDS)
"""
struct PSCADModel{N, O}
    "Path to the PSCAD project file."
    project_path::String
    "Project name, equal to the project file stem."
    project_name::String
    "Optional network representation used to generate the project."
    netlist::N
    "Requested measurement channels."
    probes::ProbeManifest
    "Simulation settings."
    settings::SimulationSettings
    "Optional operating point used to generate the project."
    operating_point::O
    "Project source, package versions and export timestamp."
    provenance::NamedTuple
    "Optional Z-tool library path and SHA-256."
    ztool_library::Union{Nothing, NamedTuple{(:path, :sha256), Tuple{String, String}}}
    "Optional workspace listing the Z-tool library before the project."
    workspace_path::Union{Nothing, String}
end

PSCADModel(path, name, netlist, probes, settings, operating_point, provenance) =
    PSCADModel(path, name, netlist, probes, settings, operating_point, provenance,
        nothing, nothing)

"""
$(TYPEDSIGNATURES)

Wrap an existing PSCAD project for simulation.

# Arguments

- `path`: Existing `.pscx` file.
- `probes`: Requested channels. Default: `ProbeManifest()`.
- `settings`: Simulation settings. Default: `SimulationSettings()`.
- `ztool_library`: Optional local Z-tool library used by this project. Its
  path and SHA-256 are stored for simulation staging. Default: `nothing`.

# Returns

- A `PSCADModel` with an absolute project path, `nothing` for the network and
  operating point, and `(source = :file,)` as the project source record.

# Errors

- Throws `ArgumentError` if the file is absent or its extension is not `.pscx`.
"""
function PSCADModel(path::AbstractString; probes::ProbeManifest = ProbeManifest(),
        settings::SimulationSettings = SimulationSettings(), ztool_library = nothing)
    isfile(path) || throw(ArgumentError("PSCAD project file does not exist: $path"))
    endswith(lowercase(path), ".pscx") ||
        throw(ArgumentError("PSCAD project must end in .pscx: $path"))
    library = ztool_library === nothing ? nothing : _ztool_library(ztool_library)
    workspace = splitext(abspath(path))[1] * ".pswx"
    return PSCADModel(abspath(path), _remote_project_name(path), nothing,
        probes, settings, nothing, (source = :file,), library,
        library !== nothing && isfile(workspace) ? workspace : nothing)
end

"""
$(TYPEDEF)

Select a fresh PSCAD execution of an existing project, or verified reuse when
requested through the computation options.

$(TYPEDFIELDS)
"""
struct PSCADRun{B} <: AbstractFormulation
    "Selected execution backend."
    backend::Type{B}
end
PSCADRun(; backend::Type{B} = PSCADBackend) where {B} = PSCADRun{B}(backend)
_register_backend!(PSCADRun, PSCADBackend)

"""
$(TYPEDEF)

Store finite, ordered time-domain output and the simulation execution records.

$(TYPEDFIELDS)
"""
struct PSCADResult{F} <: AbstractProblemResult
    "Formulation used for this result."
    formulation::F
    "Strictly increasing output times \\[s\\]."
    time::Vector{Float64}
    "Channel values, in INF channel order and their recorded physical units."
    channels::OrderedDict{String, Vector{Float64}}
    "Requested measurement manifest."
    probes::ProbeManifest
    "Resolved simulation settings."
    settings::SimulationSettings
    "Elapsed time \\[s\\], reuse status, solver identity, settings readback and build warnings."
    diagnostics::NamedTuple
    "Run directory, output directory, console, build-message and INF paths."
    paths::NamedTuple
end
