using DelimitedFiles
using LinearAlgebra
using Test

isdefined(Main, :NumericReference) || include(joinpath(@__DIR__, "reference", "reference_io.jl"))
using .NumericReference

const PARITY_REFERENCE_DIRECTORY = joinpath(@__DIR__, "reference", "v1")
const PARITY_REFERENCE = load_reference(joinpath(PARITY_REFERENCE_DIRECTORY, "numeric.csv"))
const PARITY_METADATA = load_metadata(joinpath(PARITY_REFERENCE_DIRECTORY, "metadata.txt"))
const PARITY_SOURCE_COMMIT = "e8bf10bdc330d8edf46a02d1aff8be4598081f1f"
const PARITY_NB = PowerImpedance.NetworkBuilder

parity_real(name, dimensions) = real.(reference_array(PARITY_REFERENCE, name, dimensions))
parity_real_vector(name) = real.(reference_vector(PARITY_REFERENCE, name))
parity_complex(name, dimensions) = reference_array(PARITY_REFERENCE, name, dimensions)
parity_scalar(name) = real(reference_scalar(PARITY_REFERENCE, name))

function parity_passive_state(; branch_impedance=2.0)
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
    return PARITY_NB.define(elements, connections)
end

function parity_impedance_state(branch_impedance)
    elements = (
        z1=impedance(z=branch_impedance, pins=1),
        z2=impedance(z=20.0, pins=1),
    )
    connections = (
        (node=:n1, element=:z1, side=1, terminal=1),
        (node=:n1, element=:z2, side=1, terminal=1),
        (node=:gnd, element=:z1, side=2, terminal=1),
        (node=:gnd, element=:z2, side=2, terminal=1),
    )
    return PARITY_NB.define(elements, connections)
end

function parity_powerflow_state(shunt_impedance=1.0)
    voltage = 220.0
    elements = (
        sm1=synchronousmachine(
            elec=ElectricalSM(rt=1e-10, lt=1e-10),
            setpoint=Setpoint(Pac=50.0, Qac=10.0, Vac=voltage / sqrt(3)),
        ),
        z1=impedance(z=shunt_impedance, pins=3, transformation=true),
    )
    connections = (
        (node=:machine_d, element=:z1, side=1, terminal=1),
        (node=:machine_d, element=:sm1, side=1, terminal=1),
        (node=:machine_q, element=:z1, side=1, terminal=2),
        (node=:machine_q, element=:sm1, side=1, terminal=2),
        (node=:gnd_d, element=:z1, side=2, terminal=1),
        (node=:gnd_q, element=:z1, side=2, terminal=2),
    )
    return PARITY_NB.define(elements, connections)
end

function parity_powerflow_space(shunt_impedances)
    voltage = 220.0
    elements = (
        sm1=synchronousmachine(
            elec=ElectricalSM(rt=1e-10, lt=1e-10),
            setpoint=Setpoint(Pac=50.0, Qac=10.0, Vac=voltage / sqrt(3)),
        ),
        z1=impedance(
            Grid;
            z=Grid(shunt_impedances),
            pins=3,
            transformation=true,
        ),
    )
    connections = (
        (node=:machine_d, element=:z1, side=1, terminal=1),
        (node=:machine_d, element=:sm1, side=1, terminal=1),
        (node=:machine_q, element=:z1, side=1, terminal=2),
        (node=:machine_q, element=:sm1, side=1, terminal=2),
        (node=:gnd_d, element=:z1, side=2, terminal=1),
        (node=:gnd_q, element=:z1, side=2, terminal=2),
    )
    return PARITY_NB.define(elements, connections)
end

function parity_powerflow_numbers(powerflow, prefix)
    numbers = Dict{String,Float64}()
    solution = powerflow.result["solution"]
    numbers["$prefix.baseMVA"] = solution["baseMVA"]
    for group in ("bus", "gen", "branch")
        for (identifier, fields) in solution[group]
            for (field, value) in fields
                value isa Number || continue
                numbers["$prefix.$group.$identifier.$field"] = value
            end
        end
    end
    for field in fieldnames(Setpoint)
        value = getfield(powerflow.operating_point[:sm1], field)
        value isa Number || continue
        numbers["$prefix.operating_point.sm1.$field"] = value
    end
    return numbers
end

function test_powerflow_reference(powerflow, prefix)
    actual = parity_powerflow_numbers(powerflow, prefix)
    names = reference_names(PARITY_REFERENCE, prefix)
    @test Set(keys(actual)) == Set(names)
    for name in names
        @test isapprox(actual[name], parity_scalar(name); rtol=5e-7, atol=5e-8)
    end
    return nothing
end

function parity_stability_inputs()
    frequencies = parity_real_vector("stability.frequencies")
    response = parity_complex("stability.response", (2, 2, length(frequencies)))
    second = parity_complex("stability.second_response", (2, 2, length(frequencies)))
    first_result = FrequencyResponseResult(
        NodeAdmittance(),
        :node_admittance,
        response,
        frequencies,
        [:d, :q],
        nothing,
        (;),
    )
    second_result = FrequencyResponseResult(
        EdgeAdmittance(),
        :edge_admittance,
        second,
        frequencies,
        [:d, :q],
        nothing,
        (;),
    )
    return first_result, second_result
end

function labeled_series(render, label; view=1)
    series = only(render.figures).views[view].series
    return only(filter(item -> item.label == label, series))
end

function grouped_line(render, group; view=1)
    series = only(render.figures).views[view].series
    return only(filter(
        item -> item.kind === :line && item.group === group && item.label !== nothing,
        series,
    ))
end

function grouped_line(page::PlotBuilder.PageDefinition, group; view=1)
    series = page.views[view].series
    return only(filter(
        item -> item.kind === :line && item.group === group && item.label !== nothing,
        series,
    ))
end

@testset "Frozen numerical reference provenance" begin
    @test PARITY_METADATA["format_version"] == "1"
    @test PARITY_METADATA["source_commit"] == PARITY_SOURCE_COMMIT
    @test PARITY_METADATA["frequency_unit"] == "rad_per_second"
    @test length(PARITY_METADATA["dependency_manifest_sha256"]) == 64
    @test all(haskey(PARITY_METADATA, name) for name in (
        "powermodels_version",
        "powermodelsacdc_version",
        "ipopt_version",
    ))
    @test !isempty(reference_names(PARITY_REFERENCE))
end

@testset "Pre-refactor primitive numerical parity" begin
    problem = PowerImpedanceProblem(
        parity_passive_state();
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
        prefix = "primitive.$name"
        @test result.frequencies ≈ parity_real_vector("$prefix.frequencies") rtol = 5e-13
        @test result.response ≈ parity_complex(
            "$prefix.response",
            size(result.response),
        ) rtol = 5e-13 atol = 5e-13
    end

    impedance = compute(problem, NodalImpedance())
    render = PlotBuilder.make_render(HarmonicImpedancePlotDefinition, impedance)
    curve = only(filter(
        item -> item.kind === :line && item.label !== nothing,
        only(render.figures).views[1].series,
    ))
    expected = parity_complex("primitive.nodal_impedance.response", size(impedance.response))
    @test curve.xdata ≈ parity_real_vector("primitive.nodal_impedance.frequencies") ./ 2pi
    @test curve.ydata ≈ 20 .* log10.(abs.(vec(expected[1, 1, :])))
end

@testset "Pre-refactor stability numerical parity" begin
    first_result, second_result = parity_stability_inputs()
    frequencies = first_result.frequencies

    bode = compute(StabilityProblem(first_result), BodeAnalysis())
    @test bode.output.magnitude_db ≈ parity_real(
        "stability.bode.magnitude_db",
        size(bode.output.magnitude_db),
    ) rtol = 5e-12 atol = 5e-12
    @test bode.output.phase_deg ≈ parity_real(
        "stability.bode.phase_deg",
        size(bode.output.phase_deg),
    ) rtol = 5e-12 atol = 5e-12
    bode_render = PlotBuilder.make_render(BodePlotDefinition, bode; channels=(1, 1))
    bode_curve = labeled_series(bode_render, "Channel [1, 1]")
    @test bode_curve.xdata ≈ frequencies ./ 2pi
    @test bode_curve.ydata ≈ vec(parity_real(
        "stability.bode.magnitude_db",
        size(bode.output.magnitude_db),
    )[1, 1, :])

    wrapped_frequencies = parity_real_vector("stability.bode_wrapped.frequencies")
    wrapped_phase = deg2rad.([170.0, 179.0, -179.0, -170.0, -160.0])
    wrapped_response = FrequencyResponseResult(
        LoopGain(),
        :loopgain,
        reshape(ComplexF64.(cis.(wrapped_phase)), 1, 1, :),
        wrapped_frequencies,
        [:channel],
        nothing,
        (;),
    )
    wrapped_bode = compute(StabilityProblem(wrapped_response), BodeAnalysis())
    @test wrapped_bode.output.magnitude_db ≈ parity_real(
        "stability.bode_wrapped.magnitude_db",
        size(wrapped_bode.output.magnitude_db),
    ) rtol = 5e-12 atol = 5e-12
    @test wrapped_bode.output.phase_deg ≈ parity_real(
        "stability.bode_wrapped.phase_deg",
        size(wrapped_bode.output.phase_deg),
    ) rtol = 5e-12 atol = 5e-12

    passivity_result = compute(StabilityProblem(first_result), PassivityAnalysis())
    @test passivity_result.output.index ≈ parity_real_vector(
        "stability.passivity.index",
    ) rtol = 5e-12 atol = 5e-12
    passivity_render = PlotBuilder.make_render(PassivityPlotDefinition, passivity_result)
    @test grouped_line(passivity_render, :passivity).ydata ≈ parity_real_vector(
        "stability.passivity.index",
    )

    small_gain_result = compute(
        StabilityProblem((first_result, second_result)),
        SmallGainAnalysis(),
    )
    @test small_gain_result.output.first_gain ≈ parity_real_vector(
        "stability.small_gain.first",
    ) rtol = 5e-12 atol = 5e-12
    @test small_gain_result.output.second_gain ≈ parity_real_vector(
        "stability.small_gain.second",
    ) rtol = 5e-12 atol = 5e-12
    @test small_gain_result.output.product_gain ≈ parity_real_vector(
        "stability.small_gain.product",
    ) rtol = 5e-12 atol = 5e-12
    gain_render = PlotBuilder.make_render(SmallGainPlotDefinition, small_gain_result)
    @test grouped_line(gain_render, :product_gain).ydata ≈ parity_real_vector(
        "stability.small_gain.product",
    )

    evd = compute(
        StabilityProblem(first_result),
        EigenvalueAnalysis(fmin=1.0, fmax=100.0, determinant=true),
    )
    @test evd.output.eigenvalues ≈ parity_complex(
        "stability.evd.eigenvalues",
        size(evd.output.eigenvalues),
    ) rtol = 5e-11 atol = 5e-12
    for field in (:observability, :controllability, :participation)
        @test getproperty(evd.output, field) ≈ parity_real(
            "stability.evd.$field",
            size(getproperty(evd.output, field)),
        ) rtol = 5e-11 atol = 5e-12
    end
    @test evd.output.determinant_index ≈ parity_real_vector(
        "stability.evd.determinant_index",
    ) rtol = 5e-11 atol = 5e-12
    @test evd.output.dominant_mode == round(Int, parity_scalar("stability.evd.dominant_mode"))
    @test evd.output.critical_frequency ≈ parity_scalar("stability.evd.critical_frequency")
    @test evd.output.pmd_unstable == Bool(round(Int, parity_scalar("stability.evd.pmd_unstable")))
    @test evd.output.pnd_unstable == Bool(round(Int, parity_scalar("stability.evd.pnd_unstable")))
    evd_render = PlotBuilder.make_render(EigenvaluePlotDefinition, evd)
    evd_curve = grouped_line(first(evd_render.figures), :mode_1)
    expected_eigenvalues = parity_complex("stability.evd.eigenvalues", size(evd.output.eigenvalues))
    @test evd_curve.ydata ≈ 20 .* log10.(abs.(expected_eigenvalues[:, 1]))
    @test grouped_line(last(evd_render.figures), :determinant).ydata ≈ parity_real_vector(
        "stability.evd.determinant_index",
    )

    nyquist_frequencies = parity_real_vector("stability.nyquist.frequencies")
    nyquist_locus = vec(parity_complex(
        "stability.nyquist.eigenloci",
        (length(nyquist_frequencies), 1),
    ))
    loop_result = FrequencyResponseResult(
        LoopGain(),
        :loopgain,
        reshape(nyquist_locus, 1, 1, :),
        nyquist_frequencies,
        [:loop],
        nothing,
        (;),
    )
    nyquist = compute(StabilityProblem(loop_result), GeneralizedNyquist())
    @test nyquist.output.eigenloci ≈ reshape(nyquist_locus, :, 1) rtol = 5e-12 atol = 5e-12
    @test nyquist.output.encirclements.clockwise == round.(
        Int,
        parity_real_vector("stability.nyquist.clockwise"),
    )
    @test nyquist.output.encirclements.counterclockwise == round.(
        Int,
        parity_real_vector("stability.nyquist.counterclockwise"),
    )
    @test nyquist.output.encirclements.net == round(Int, parity_scalar("stability.nyquist.net"))
    @test nyquist.output.assessment === :unstable_system
    @test nyquist.output.unstable_frequencies ≈ parity_real_vector(
        "stability.nyquist.unstable_frequencies",
    ) rtol = 5e-10
    margins = only(nyquist.output.margins)
    @test [margins.vector.margin, margins.vector.frequency] ≈ parity_real_vector(
        "stability.nyquist.margin.1.vector",
    ) rtol = 5e-12 atol = 5e-12
    for kind in (:phase, :gain)
        records = getproperty(margins, kind)
        actual = reduce(vcat, (
            reshape([record.margin, record.frequency], 1, 2) for record in records
        ))
        @test actual ≈ parity_real(
            "stability.nyquist.margin.1.$kind",
            size(actual),
        ) rtol = 5e-12 atol = 5e-12
    end
    nyquist_render = PlotBuilder.make_render(NyquistPlotDefinition, nyquist)
    nyquist_curve = labeled_series(nyquist_render, "Mode 1")
    @test nyquist_curve.xdata ≈ real.(nyquist_locus)
    @test nyquist_curve.ydata ≈ imag.(nyquist_locus)

    unstable = compute(
        StabilityProblem(loop_result),
        UnstableFrequencyAnalysis(order_maxima=5),
    )
    @test only(unstable.output.complementary_sensitivity) ≈ reference_vector(
        PARITY_REFERENCE,
        "stability.unstable.complementary_sensitivity",
    ) rtol = 5e-12 atol = 5e-12
    @test only(unstable.output.magnitude_db) ≈ parity_real_vector(
        "stability.unstable.magnitude_db",
    ) rtol = 5e-12 atol = 5e-12
    @test only(unstable.output.phase_deg) ≈ parity_real_vector(
        "stability.unstable.phase_deg",
    ) rtol = 5e-12 atol = 5e-12
    @test unstable.output.detected_frequencies ≈ parity_real_vector(
        "stability.unstable.detected_frequencies",
    ) rtol = 5e-10
    unstable_render = PlotBuilder.make_render(UnstableFrequencyPlotDefinition, unstable)
    @test grouped_line(unstable_render, :mode_1).ydata ≈ parity_real_vector(
        "stability.unstable.magnitude_db",
    )
end

@testset "Stored Monte Carlo realization replay" begin
    axis_values = parity_real_vector("monte_carlo.axis_values")
    expected = parity_complex(
        "monte_carlo.nodal_impedance",
        (4, length(axis_values)),
    )
    actual = Matrix{ComplexF64}(undef, size(expected))
    for (trial, axis_value) in enumerate(axis_values)
        result = compute(
            PowerImpedanceProblem(
                parity_impedance_state(axis_value);
                nodes=[:n1],
                frequency_range=(1.0, 10.0, 4),
            ),
            NodalImpedance(),
        )
        actual[:, trial] = vec(result.response)
    end
    @test actual ≈ expected rtol = 5e-12 atol = 5e-12
end

@testset "Pre-refactor power-flow numerical parity" begin
    deterministic = compute(PowerFlowProblem(parity_powerflow_state()), ACDCPowerFlow())
    test_powerflow_reference(deterministic, "powerflow.deterministic")

    axis_values = parity_real_vector("powerflow.replay.axis_values")
    study = compute(
        ParametricProblem(PowerFlowProblem(parity_powerflow_space(axis_values))),
        Combinatorial(ACDCPowerFlow()),
    )
    @test study isa ParametricResult{<:PowerFlowResult}
    for (trial, powerflow) in enumerate(study.values)
        test_powerflow_reference(powerflow, "powerflow.replay.trial.$trial")
    end
end
