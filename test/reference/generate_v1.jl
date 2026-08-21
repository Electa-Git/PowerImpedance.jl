using DelimitedFiles
using Ipopt
using LinearAlgebra
using Measurements
using PowerImpedance
using PowerModels
using PowerModelsACDC
using Printf
using Random
using SHA

const NB = PowerImpedance.NetworkBuilder
const SOURCE_COMMIT = "e8bf10bdc330d8edf46a02d1aff8be4598081f1f"
const ReferenceRow = Tuple{String,Int,Int,Int,Float64,Float64}

function record!(rows::Vector{ReferenceRow}, name::AbstractString, value::Number)
    push!(rows, (String(name), 1, 1, 1, Float64(real(value)), Float64(imag(value))))
    return rows
end

function record!(rows::Vector{ReferenceRow}, name::AbstractString, values::AbstractArray)
    ndims(values) <= 3 || throw(ArgumentError("reference arrays support at most three dimensions"))
    for index in CartesianIndices(values)
        coordinates = (Tuple(index)..., ntuple(_ -> 1, 3 - ndims(values))...)
        value = values[index]
        value isa Number || throw(ArgumentError("reference arrays must contain numbers"))
        push!(rows, (
            String(name),
            coordinates[1],
            coordinates[2],
            coordinates[3],
            Float64(real(value)),
            Float64(imag(value)),
        ))
    end
    return rows
end

function write_rows(path, rows)
    open(path, "w") do io
        println(io, "dataset,i,j,k,real,imag")
        for row in rows
            @printf(io, "%s,%d,%d,%d,%.17g,%.17g\n", row...)
        end
    end
    return path
end

function passive_state(; branch_impedance=2.0)
    elements = (
        branch=impedance(z=branch_impedance, pins=1),
        shunt=impedance(z=4.0, pins=1),
    )
    connections = (
        (node=:bus, element=:branch, side=1, terminal=1),
        (node=:bus, element=:shunt, side=1, terminal=1),
        (node=:gnd, element=:branch, side=2, terminal=1),
        (node=:gnd, element=:shunt, side=2, terminal=1),
    )
    return NB.define(elements, connections)
end

function impedance_space(axis)
    elements = (
        z1=impedance(Grid; z=axis, pins=1),
        z2=impedance(z=20.0, pins=1),
    )
    connections = (
        (node=:n1, element=:z1, side=1, terminal=1),
        (node=:n1, element=:z2, side=1, terminal=1),
        (node=:gnd, element=:z1, side=2, terminal=1),
        (node=:gnd, element=:z2, side=2, terminal=1),
    )
    return NB.define(elements, connections)
end

function powerflow_state(axis=1.0)
    voltage = 220.0
    uncertain = axis isa NB.AbstractGrid
    machine = uncertain ?
        synchronousmachine(
            NB.Grid;
            elec=ElectricalSM(rt=1e-10, lt=1e-10),
            setpoint=Setpoint(Pac=50.0, Qac=10.0, Vac=voltage / sqrt(3)),
        ) :
        synchronousmachine(
            elec=ElectricalSM(rt=1e-10, lt=1e-10),
            setpoint=Setpoint(Pac=50.0, Qac=10.0, Vac=voltage / sqrt(3)),
        )
    shunt = uncertain ? impedance(NB.Grid; z=axis, pins=3, transformation=true) :
        impedance(z=axis, pins=3, transformation=true)
    elements = (
        sm1=machine,
        z1=shunt,
    )
    connections = (
        (node=:machine_d, element=:z1, side=1, terminal=1),
        (node=:machine_d, element=:sm1, side=1, terminal=1),
        (node=:machine_q, element=:z1, side=1, terminal=2),
        (node=:machine_q, element=:sm1, side=1, terminal=2),
        (node=:gnd_d, element=:z1, side=2, terminal=1),
        (node=:gnd_q, element=:z1, side=2, terminal=2),
    )
    return NB.define(elements, connections)
end

function record_powerflow!(rows, prefix, powerflow)
    solution = powerflow.result["solution"]
    record!(rows, "$prefix.baseMVA", solution["baseMVA"])
    for group in ("bus", "gen", "branch")
        for identifier in sort!(collect(keys(solution[group])))
            values = solution[group][identifier]
            for field in sort!(collect(keys(values)))
                value = values[field]
                value isa Number || continue
                record!(rows, "$prefix.$group.$identifier.$field", value)
            end
        end
    end
    for field in fieldnames(Setpoint)
        value = getfield(powerflow.operating_point[:sm1], field)
        value isa Number || continue
        record!(rows, "$prefix.operating_point.sm1.$field", value)
    end
    return rows
end

function primitive_references!(rows)
    problem = PowerImpedanceProblem(
        passive_state();
        nodes=[:bus],
        frequency_range=(1.0, 100.0, 5),
    )
    formulations = (
        nodal_impedance=NodalImpedance(),
        node_admittance=NodeAdmittance(),
        edge_admittance=EdgeAdmittance(),
        loopgain=LoopGain(),
    )
    for (name, formulation) in pairs(formulations)
        result = compute(problem, formulation)
        record!(rows, "primitive.$name.response", result.response)
        record!(rows, "primitive.$name.frequencies", result.frequencies)
    end
    return rows
end

function stability_references!(rows)
    frequencies = 2pi .* 10.0 .^ range(0, 2; length=24)
    response = Array{ComplexF64}(undef, 2, 2, length(frequencies))
    second = similar(response)
    for index in eachindex(frequencies)
        frequency = frequencies[index]
        response[:, :, index] = ComplexF64[
            0.45 / (1 + im * frequency / 70) 0.02im
            -0.01im 0.25 / (1 + im * frequency / 110)
        ]
        second[:, :, index] = ComplexF64[2.0 0.1; 0.2 1.5]
    end
    record!(rows, "stability.frequencies", frequencies)
    record!(rows, "stability.response", response)
    record!(rows, "stability.second_response", second)

    bode_magnitude, bode_phase = PowerImpedance._aligned_bode_samples([response])
    record!(rows, "stability.bode.magnitude_db", only(bode_magnitude))
    record!(rows, "stability.bode.phase_deg", only(bode_phase))

    passivity_index = [
        minimum(real.(eigvals(response[:, :, index] + adjoint(response[:, :, index]))))
        for index in axes(response, 3)
    ]
    record!(rows, "stability.passivity.index", passivity_index)

    gains = PowerImpedance._small_gain_trial(response, second)
    record!(rows, "stability.small_gain.first", gains.first_gain)
    record!(rows, "stability.small_gain.second", gains.second_gain)
    record!(rows, "stability.small_gain.product", gains.product_gain)

    evd = PowerImpedance._evd_trial(response, frequencies, 1.0, 100.0)
    record!(rows, "stability.evd.eigenvalues", evd.eigenvalues)
    record!(rows, "stability.evd.observability", evd.observability)
    record!(rows, "stability.evd.controllability", evd.controllability)
    record!(rows, "stability.evd.participation", evd.participation)
    record!(rows, "stability.evd.determinant_index", evd.determinant_index)
    record!(rows, "stability.evd.dominant_mode", evd.dominant_mode)
    record!(rows, "stability.evd.critical_frequency", evd.critical_frequency)
    record!(rows, "stability.evd.pmd_unstable", Int(evd.pmd_unstable))
    record!(rows, "stability.evd.pnd_unstable", Int(evd.pnd_unstable))
    for mode in eachindex(evd.pmd_modes)
        record!(rows, "stability.evd.pmd_modes.$mode", evd.pmd_modes[mode])
        record!(rows, "stability.evd.pnd_modes.$mode", evd.pnd_modes[mode])
    end

    unstable_frequencies = 2pi .* 10.0 .^ range(-2, 2; length=400)
    unstable_locus = 8.5 ./ (1 .+ im .* unstable_frequencies) .^ 3
    unstable_response = reshape(ComplexF64.(unstable_locus), 1, 1, :)
    loci, _, _ = PowerImpedance._matched_eigenloci([unstable_response])
    metrics = PowerImpedance._nyquist_trial(only(loci), unstable_frequencies)
    record!(rows, "stability.nyquist.frequencies", unstable_frequencies)
    record!(rows, "stability.nyquist.eigenloci", only(loci))
    record!(rows, "stability.nyquist.clockwise", metrics.clockwise)
    record!(rows, "stability.nyquist.counterclockwise", metrics.counterclockwise)
    record!(rows, "stability.nyquist.net", metrics.net)
    record!(rows, "stability.nyquist.unstable_frequencies", metrics.unstable_frequencies)
    for (mode, margins) in enumerate(metrics.margins)
        record!(rows, "stability.nyquist.margin.$mode.vector", [
            margins.vector.margin,
            margins.vector.frequency,
        ])
        for (kind, records) in (("phase", margins.phase), ("gain", margins.gain))
            values = isempty(records) ? zeros(0, 2) : reduce(vcat, (
                reshape([record.margin, record.frequency], 1, 2) for record in records
            ))
            record!(rows, "stability.nyquist.margin.$mode.$kind", values)
        end
    end

    complementary = 1 ./ (ones(ComplexF64, length(unstable_locus)) .+ unstable_locus)
    record!(rows, "stability.unstable.complementary_sensitivity", complementary)
    record!(rows, "stability.unstable.magnitude_db", 20 .* log10.(abs.(complementary)))
    record!(rows, "stability.unstable.phase_deg", rad2deg.(angle.(complementary)))
    record!(rows, "stability.unstable.detected_frequencies", unstable_frequency(
        unstable_locus,
        unstable_frequencies;
        make_plot=false,
    ))

    wrapped_frequencies = 2pi .* [1.0, 2.0, 3.0, 4.0, 5.0]
    wrapped_phase = deg2rad.([170.0, 179.0, -179.0, -170.0, -160.0])
    wrapped_response = reshape(ComplexF64.(cis.(wrapped_phase)), 1, 1, :)
    wrapped_magnitude, unwrapped_phase = PowerImpedance._aligned_bode_samples([
        wrapped_response,
    ])
    record!(rows, "stability.bode_wrapped.frequencies", wrapped_frequencies)
    record!(rows, "stability.bode_wrapped.magnitude_db", only(wrapped_magnitude))
    record!(rows, "stability.bode_wrapped.phase_deg", only(unwrapped_phase))
    return rows
end

function monte_carlo_replay_references!(rows)
    study = NB.determine_impedance(
        impedance_space(NB.Grid(10.0, NB.AbsoluteError(1.0)));
        nets=[:n1],
        freq_range=(1.0, 10.0, 4),
        trials=32,
        distribution=:normal,
        seed=123,
        return_samples=true,
    )
    samples = only(study).samples
    response_samples = dropdims(samples; dims=(1, 2))
    equivalent = real.(response_samples[1, :])
    axis_values = 20 .* equivalent ./ (20 .- equivalent)
    record!(rows, "monte_carlo.axis_values", axis_values)
    record!(rows, "monte_carlo.nodal_impedance", response_samples)
    return rows
end

function powerflow_references!(rows)
    deterministic = compute(NB.PowerFlowProblem(powerflow_state()), NB.ACDCPowerFlow())
    record_powerflow!(rows, "powerflow.deterministic", deterministic)

    rng = Random.Xoshiro(NB._case_seed(UInt64(17), 1))
    axis_values = [1.0 + 0.05randn(rng) for _ in 1:4]
    for (trial, axis_value) in enumerate(axis_values)
        powerflow = compute(
            NB.PowerFlowProblem(powerflow_state(axis_value)),
            NB.ACDCPowerFlow(),
        )
        record_powerflow!(rows, "powerflow.replay.trial.$trial", powerflow)
    end
    record!(rows, "powerflow.replay.axis_values", axis_values)
    return rows
end

function main(output_directory)
    package_root = dirname(dirname(pathof(PowerImpedance)))
    actual_commit = readchomp(Cmd(["git", "-C", package_root, "rev-parse", "HEAD"]))
    actual_commit == SOURCE_COMMIT || error(
        "reference data must be generated from $SOURCE_COMMIT, got $actual_commit",
    )
    mkpath(output_directory)
    rows = ReferenceRow[]
    primitive_references!(rows)
    stability_references!(rows)
    monte_carlo_replay_references!(rows)
    powerflow_references!(rows)
    sort!(rows; by=row -> (row[1], row[2], row[3], row[4]))
    write_rows(joinpath(output_directory, "numeric.csv"), rows)
    open(joinpath(output_directory, "metadata.txt"), "w") do io
        println(io, "format_version=1")
        println(io, "source_commit=$SOURCE_COMMIT")
        println(io, "julia_version=$(VERSION)")
        println(io, "powermodels_version=$(Base.pkgversion(PowerModels))")
        println(io, "powermodelsacdc_version=$(Base.pkgversion(PowerModelsACDC))")
        println(io, "ipopt_version=$(Base.pkgversion(Ipopt))")
        manifest_path = joinpath(dirname(Base.active_project()), "Manifest.toml")
        println(io, "dependency_manifest_sha256=$(bytes2hex(sha256(read(manifest_path))))")
        println(io, "frequency_unit=rad_per_second")
        println(io, "complex_storage=real_imaginary_columns")
    end
    return nothing
end

length(ARGS) == 1 || error("usage: julia generate_v1.jl OUTPUT_DIRECTORY")
main(only(ARGS))
