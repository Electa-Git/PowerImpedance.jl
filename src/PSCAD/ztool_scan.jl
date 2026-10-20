function _ztool_real(name, value; positive = true)
    value isa Real && !(value isa Bool) && isfinite(value) &&
        (positive ? value > 0 : value >= 0) ||
        throw(ArgumentError("$name must be $(positive ? "positive" : "nonnegative") and finite"))
    result = Float64(value)
    isfinite(result) && (positive ? result > 0 : result >= 0) ||
        throw(ArgumentError("$name must be representable as a finite Float64"))
    return result
end

function _ztool_integer(name, value)
    value isa Integer && !(value isa Bool) && 0 < value <= typemax(Int) ||
        throw(ArgumentError("$name must be a positive integer"))
    return Int(value)
end

function _ztool_topology(path)
    path isa AbstractString && isfile(path) ||
        throw(ArgumentError("topology must name an existing Z-tool topology file"))
    lines = filter(line -> !isempty(strip(line)), readlines(path))
    isempty(lines) && throw(ArgumentError("Z-tool topology file is empty: $path"))
    names = split(first(lines))
    iseven(length(names)) || throw(ArgumentError("Z-tool topology needs pairs of block sides"))
    for index in 1:2:length(names)
        first_side = match(r"^(.+)-1$", names[index])
        first_side !== nothing && names[index + 1] == first_side[1] * "-2" ||
            throw(ArgumentError("Z-tool topology headers must pair each block as Name-1 Name-2"))
    end
    length(unique(names)) == length(names) ||
        throw(ArgumentError("Z-tool topology has duplicate block sides"))
    matrix_lines = [strip(first(split(line, r"[#%!]"; limit = 2))) for line in lines[2:end]]
    rows = [split(line) for line in matrix_lines if !isempty(line)]
    length(rows) == length(names) && all(row -> length(row) == length(names), rows) ||
        throw(ArgumentError("Z-tool topology must have one square matrix row per block side"))
    matrix = [tryparse(Float64, field) for row in rows for field in row]
    all(value -> value in (0.0, 1.0), matrix) ||
        throw(ArgumentError("Z-tool topology entries must be 0 or 1"))
    n = length(names)
    all(matrix[(i - 1) * n + j] == matrix[(j - 1) * n + i] for i in 1:n, j in 1:n) ||
        throw(ArgumentError("Z-tool topology matrix must be symmetric"))
    return abspath(path)
end

"""
$(TYPEDEF)

Select a Z-tool admittance sweep of a staged PSCAD project.
The station uses `ztoolacdc==0.1.52` and the application's selected compiler.
Times use seconds and frequencies use Hz.

$(TYPEDFIELDS)
"""
struct ZToolScan{B} <: AbstractFormulation
    "Selected execution backend."
    backend::Type{B}
    "Explicit increasing frequencies \\[Hz\\], or `nothing` for a logarithmic list."
    frequencies::Union{Nothing, Vector{Float64}}
    "Minimum value for the frequency, in \\[Hz\\], or `nothing`."
    f_min::Union{Nothing, Float64}
    "Maximum value for the frequency, in \\[Hz\\], or `nothing`."
    f_max::Union{Nothing, Float64}
    "Requested point count for a logarithmic list, or `nothing`."
    f_points::Union{Nothing, Int}
    "Frequency spacing \\[Hz\\], whose reciprocal gives the base period."
    f_base::Float64
    "Startup time before decoupling \\[s\\], or `nothing` for the model setting."
    snapshot_time::Union{Nothing, Float64}
    "Settling interval before the FFT, in \\[s\\]."
    start_fft::Float64
    "Number of base periods in the FFT window."
    fft_periods::Int
    "Delay between decoupling and injection \\[s\\]."
    injection_interval::Float64
    "Injection voltage relative to the scan's nominal voltage \\[dimensionless\\]."
    perturbation::Float64
    "Whether Z-tool injects up to eight frequencies together."
    multi_frequency::Bool
    "Integration step, in \\[s\\], or `nothing` for the model setting."
    time_step::Union{Nothing, Float64}
    "Sampling interval \\[s\\], or `nothing` for the model setting."
    sample_step::Union{Nothing, Float64}
    "Maximum number of concurrent EMTDC simulations."
    num_parallel_sim::Int
    "Optional local file describing connections among scan block sides."
    topology::Union{Nothing, String}

    @doc """
    $(TYPEDSIGNATURES)

    Construct a sweep with explicit frequencies or a logarithmic frequency list.

    # Keywords

    - `frequencies`: Increasing positive vector \\[Hz\\]. Default: `nothing`.
      Explicit values replace `f_min`, `f_max` and `f_points`.
    - `f_min`, `f_max`, `f_points`: Defaults: `1.0` \\[Hz\\], `1000.0` \\[Hz\\]
      and `80`. These match Z-tool's `create_freq.loglist` defaults.
      The station calls that function to round and fill the logarithmic list.
    - `f_base`: Default: `1.0` \\[Hz\\], for a one-second base period.
      Frequencies and range endpoints must be multiples of this value.
    - `snapshot_time`: Default: the model's snapshot time, or its duration
      when no snapshot time exists. This uses the model's startup allowance.
    - `start_fft`: Default: `1.0` \\[s\\], allowing one second for injection settling.
    - `fft_periods`: Default: `1`. The FFT window spans `fft_periods/f_base` \\[s\\].
    - `injection_interval`: Default: `start_fft` \\[s\\], as in Z-tool.
      It maps to `dt_injections`, the delay after decoupling.
    - `perturbation`: Default: `0.01` \\[dimensionless\\], matching the scan library.
    - `multi_frequency`: Default: `false`, for separate single-tone injections.
    - `time_step`, `sample_step`: Default: `nothing`, using the model settings
      \\[s\\]. The station receives microseconds for these two arguments.
    - `num_parallel_sim`: Default: `1`, for the educational licence.
    - `topology`: Default: `nothing`, for one scan block. Multiple blocks need
      a Z-tool topology file with paired `Name-1 Name-2` headers and a binary matrix.
    - `backend`: Default: `PSCADBackend`.

    # Returns

    - A `ZToolScan` for [`compute`](@ref).

    # Errors

    Invalid fields raise `ArgumentError`. Resolved steps must support the FFT
    period with an integer sample count and satisfy the Nyquist limit.
    Both sweep modes need a point count divisible by eight to avoid padding.
    Multi-frequency sweeps need at least sixteen points for PSCAD to write run indices.
    Z-tool expects those indices in perturbation output filenames.
    The runner checks the length of a generated list before simulation.
    """
    function ZToolScan(; frequencies = nothing, f_min = nothing, f_max = nothing,
            f_points = nothing, f_base = 1.0, snapshot_time = nothing, start_fft = 1.0,
            fft_periods = 1, injection_interval = nothing, perturbation = 0.01,
            multi_frequency = false, time_step = nothing, sample_step = nothing,
            num_parallel_sim = 1, topology = nothing,
            backend::Type{B} = PSCADBackend) where {B}
        base = _ztool_real(:f_base, f_base)
        if frequencies === nothing
            low = _ztool_real(:f_min, something(f_min, 1.0))
            high = _ztool_real(:f_max, something(f_max, 1000.0))
            low <= high || throw(ArgumentError("f_min must not exceed f_max"))
            points = _ztool_integer(:f_points, something(f_points, 80))
            values = [low, high]
            frequency_list = nothing
        else
            all(isnothing, (f_min, f_max, f_points)) ||
                throw(ArgumentError("frequencies cannot be combined with f_min, f_max or f_points"))
            frequencies isa AbstractVector && !isempty(frequencies) ||
                throw(ArgumentError("frequencies must be a nonempty vector"))
            frequency_list = [_ztool_real(:frequencies, value) for value in frequencies]
            all(>(0), diff(frequency_list)) ||
                throw(ArgumentError("frequencies must be strictly increasing"))
            values = frequency_list
            low, high, points = nothing, nothing, nothing
        end
        all(value -> isfinite(value / base) && value / base >= 1 &&
            isapprox(value / base, round(value / base); rtol = 1e-9, atol = 0), values) ||
            throw(ArgumentError("frequencies and range endpoints must be multiples of f_base"))
        multi_frequency isa Bool || throw(ArgumentError("multi_frequency must be Bool"))
        count = frequency_list === nothing ? points : length(frequency_list)
        if count % 8 != 0 || (multi_frequency && count < 16)
            reason = multi_frequency ?
                "multi-frequency sweeps need a frequency count divisible by 8 and at least 16: padding repeats the maximum frequency, and PSCAD omits the run index that Z-tool expects when each axis runs only one simulation" :
                "single-frequency sweeps need a frequency count divisible by 8: Z-tool pads other counts with repeated maximum frequencies but does not run the extra simulations"
            throw(ArgumentError("Z-tool 0.1.52 $reason"))
        end
        snapshot = snapshot_time === nothing ? nothing : _ztool_real(:snapshot_time, snapshot_time)
        settling = _ztool_real(:start_fft, start_fft; positive = false)
        interval = injection_interval === nothing ? settling :
            _ztool_real(:injection_interval, injection_interval; positive = false)
        step = time_step === nothing ? nothing : _ztool_real(:time_step, time_step)
        sample = sample_step === nothing ? nothing : _ztool_real(:sample_step, sample_step)
        step === nothing || sample === nothing || sample >= step ||
            throw(ArgumentError("sample_step must be at least time_step"))
        return new{B}(backend, frequency_list, low, high, points, base, snapshot,
            settling, _ztool_integer(:fft_periods, fft_periods), interval,
            _ztool_real(:perturbation, perturbation), multi_frequency, step, sample,
            _ztool_integer(:num_parallel_sim, num_parallel_sim),
            topology === nothing ? nothing : _ztool_topology(topology))
    end
end
_register_backend!(ZToolScan, PSCADBackend)

function _ztool_arguments(scan::ZToolScan, settings::SimulationSettings)
    step = something(scan.time_step, settings.time_step)
    sample = something(scan.sample_step, settings.sample_step)
    sample >= step || throw(ArgumentError("sample_step must be at least time_step"))
    for (name, ratio) in (("sample_step/time_step", sample / step),
            ("FFT window/sample_step", scan.fft_periods / scan.f_base / sample))
        isfinite(ratio) && isapprox(ratio, round(ratio); rtol = 1e-9, atol = 0) ||
            throw(ArgumentError("$name must be an integer for a Z-tool sweep"))
    end
    maximum_frequency = scan.frequencies === nothing ? scan.f_max : last(scan.frequencies)
    maximum_frequency < inv(2sample) ||
        throw(ArgumentError("sample_step must resolve the highest scan frequency below Nyquist"))
    snapshot = something(scan.snapshot_time, settings.snapshot_time, settings.simulation_time)
    isfinite(snapshot + scan.injection_interval + scan.start_fft + scan.fft_periods / scan.f_base) ||
        throw(ArgumentError("Z-tool simulation times must have a finite total"))
    all(isfinite, (step * 1e6, sample * 1e6,
        (snapshot + scan.injection_interval) / sample,
        (scan.start_fft + scan.fft_periods / scan.f_base) / sample)) ||
        throw(ArgumentError("Z-tool times must be representable in microseconds and samples"))
    arguments = Dict{String, Any}("t_snap" => snapshot, "t_step" => step * 1e6,
        "sample_step" => sample * 1e6, "f_base" => scan.f_base,
        "start_fft" => scan.start_fft, "fft_periods" => scan.fft_periods,
        "dt_injections" => scan.injection_interval, "v_perturb_mag" => scan.perturbation,
        "multi_freq_scan" => scan.multi_frequency, "num_parallel_sim" => scan.num_parallel_sim,
        "t_sim" => scan.start_fft + scan.fft_periods / scan.f_base)
    if scan.frequencies === nothing
        arguments["f_min"], arguments["f_max"], arguments["f_points"] =
            scan.f_min, scan.f_max, scan.f_points
    else
        arguments["freq"] = copy(scan.frequencies)
    end
    return arguments
end

function _computation_input(model::PSCADModel, scan::ZToolScan, settings)
    model.ztool_library === nothing &&
        throw(ArgumentError("ZToolScan requires a model with a Z-tool library"))
    input = _computation_input(model, PSCADRun(), settings)
    arguments = _ztool_arguments(scan, settings)
    input["ztool"] = Dict("version" => "0.1.52", "arguments" => arguments)
    if scan.topology !== nothing
        path = _ztool_topology(scan.topology)
        input["resources"]["ztool_topology.txt"] = _file_digest(path)
        arguments["topology"] = "ztool_topology.txt"
    end
    return input
end
