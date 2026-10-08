"""
$(TYPEDEF)

Specify simulation duration, integration and output sampling, and optional
snapshot saving for one fresh PSCAD run. Construct with keyword arguments;
all physical values must be positive and finite, `sample_step >= time_step`,
and a snapshot must satisfy `0 < snapshot_time <= simulation_time`.

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
    "Output filename stem: 1–20 ASCII characters, starting with a letter."
    output_stem::String
    "Nominal network frequency \\[Hz\\]."
    frequency::Float64
    "Source ramp duration \\[s\\]."
    source_ramp::Float64

    function SimulationSettings(; simulation_time = 2.0, time_step = 10e-6,
            sample_step = 100e-6, snapshot_time = nothing, output_stem = "pi",
            frequency = 50.0, source_ramp = 0.05)
        values = (simulation_time, time_step, sample_step, frequency, source_ramp)
        for (name, value) in zip(
            (:simulation_time, :time_step, :sample_step,
                :frequency, :source_ramp), values)
            value isa Real && !(value isa Bool) && isfinite(value) && value > 0 ||
                throw(ArgumentError("$name must be positive and finite"))
        end
        duration, step, sample, freq, ramp = Float64.(values)
        all(isfinite, (duration, step, sample, freq, ramp)) &&
        all(>(0), (duration, step, sample, freq, ramp)) ||
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

Describe a measured PSCAD channel and its network ownership.

$(TYPEDFIELDS)
"""
struct ProbeChannel
    "Output channel name."
    name::String
    "Measured quantity kind."
    kind::Symbol
    "Bus name, when applicable."
    bus::Union{Nothing, String}
    "Element name, when applicable."
    element::Union{Nothing, String}
    "Element side, when applicable."
    side::Union{Nothing, String}
    "Number of measured components."
    dim::Int
    "Physical unit recorded for the channel."
    unit::String
end

"""
$(TYPEDEF)

Retain the requested channels and optional voltage-angle reference bus.
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

Retain a PSCAD project, measurement manifest, simulation settings, and optional
network and operating-point records. Construction does not contact the station.

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
    "Project provenance."
    provenance::NamedTuple
end

"""
    PSCADModel(path; probes = ProbeManifest(), settings = SimulationSettings())

Wrap an existing `.pscx` project. The file must exist. Network and operating-point
records are `nothing`, and provenance is `(source = :file,)`.
"""
function PSCADModel(path::AbstractString; probes::ProbeManifest = ProbeManifest(),
        settings::SimulationSettings = SimulationSettings())
    isfile(path) || throw(ArgumentError("PSCAD project file does not exist: $path"))
    endswith(lowercase(path), ".pscx") ||
        throw(ArgumentError("PSCAD project must end in .pscx: $path"))
    return PSCADModel(abspath(path), _remote_project_name(path), nothing,
        probes, settings, nothing, (source = :file,))
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

Retain finite, ordered time-domain output and the simulation execution records.

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
    "Elapsed seconds, reuse status, solver identity, settings readback and build warnings."
    diagnostics::NamedTuple
    "Run directory, output directory, console, build-message and INF paths."
    paths::NamedTuple
end
