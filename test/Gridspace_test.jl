using Random
using Distributions
using PowerImpedance.NetworkBuilder: @gridspace, @relax

struct GridspacePokemon
    name::Symbol
end

module ErgonomicBuilderAPI
using PowerImpedance
using PowerImpedance.NetworkBuilder: Grid, define

function impedance_study()
    elements = (branch = impedance(Grid; z = Grid([1.0, 2.0]), pins = 1),)
    connections = (
        (node = :bus, element = :branch, side = 1, terminal = 1),
        (node = :gnd, element = :branch, side = 2, terminal = 1),
    )
    builders = define(elements, connections)
    return determine_impedance(
        builders;
        nets = [:bus],
        freq_range = (1.0, 10.0, 2)
    )
end
end

module WildcardBuilderAPI
using PowerImpedance
using PowerImpedance.NetworkBuilder

const shared_impedance_generic = determine_impedance === NetworkBuilder.determine_impedance
const shared_loopgain_generic = make_loopgain === NetworkBuilder.make_loopgain
end

module ReverseWildcardBuilderAPI
using PowerImpedance.NetworkBuilder
using PowerImpedance

const shared_impedance_generic = determine_impedance === NetworkBuilder.determine_impedance
const shared_loopgain_generic = make_loopgain === NetworkBuilder.make_loopgain
end

@gridspace struct GridspaceMacroExample{T <: Real}
    x::T
    y::T = 2
end

@relax struct RelaxMacroExample{T <: Real}
    x::T
    y::T
end

@testset "Grid and Gridspace" begin
    @test collect(NB.Grid(1)) == [1]
    @test collect(NB.Grid((1, "two", 3 + 4im))) == [1, "two", 3 + 4im]
    @test only(NB.Grid(GridspacePokemon(:pikachu))).name == :pikachu
    @test size(NB.Grid(1:3)) == (3,)
    @test Base.IteratorSize(typeof(NB.Grid(1:3))) isa Base.HasShape{1}
    @test NB.Grid([1, 2])[2] == 2
    @test length(NB.Grid(Int[])) == 0

    matrix = [1.0 2.0; 3.0 4.0]
    @test length(NB.impedance(z = matrix, pins = 2)) == 1
    @test only(NB.impedance(z = matrix, pins = 2)).element_model.value == matrix
    @test length(NB.impedance(z = NB.Grid([1.0, 2.0]), pins = 1)) == 2

    nested = NB.tlc(elec = NB.ElectricalTLC(Lᵣ = NB.Grid([0.1, 0.2])))
    @test length(nested) == 2
    @test [case.element_model.elec.Lᵣ for case in nested] ==
          [PowerImpedance.ElectricalTLC(Lᵣ = value).Lᵣ for value in (0.1, 0.2)]

    macro_grid = GridspaceMacroExample(x = NB.Grid([1, 2]))
    @test [(case.x, case.y) for case in macro_grid] == [(1, 2), (2, 2)]
    @test RelaxMacroExample(1, 2.5) == RelaxMacroExample{Float64}(1, 2.5)
    @test convert(RelaxMacroExample{Float32}, RelaxMacroExample(1, 2)) ==
          RelaxMacroExample{Float32}(1, 2)

    rng1 = Xoshiro(42)
    rng2 = Xoshiro(42)
    relative = NB.Grid(10.0, 5.0)
    @test rand(rng1, relative, Normal) == rand(rng2, relative, Normal)
    @test_throws ArgumentError rand(Xoshiro(1), relative; distribution = :cauchy)
    @test_throws ArgumentError NB.Grid(1.0, -1.0)
    @test_throws ArgumentError NB.Grid(1.0, NB.AbsoluteError(-1.0))
    @test_throws ArgumentError collect(relative)
end

@testset "NetworkBuilder public import boundary" begin
    safe_exports = (
        :NetworkState,
        :NetworkTopology,
        :AdmittanceLookup,
        :NetworkLookup,
        :NetworkModel,
        :define,
        :update!,
        :solve,
        :Grid,
        :Gridspace,
        :DeterministicGrid,
        :RelativeGrid,
        :AbsoluteGrid,
        :AbsoluteError,
        Symbol("@gridspace"),
        Symbol("@relax"),
        :ImpedanceCase,
        :ParametricImpedance,
        :SolveCase,
        :ParametricSolve,
        :FrequencyResponseCase,
        :ParametricFrequencyResponse,
        :ParametricNodeSchema,
        :StabilityCase,
        :ParametricStability,
        :determine_impedance,
        :make_loopgain,
        :sampled_frequency_response
    )
    @test all(name -> name in names(NB), safe_exports)
    @test all(
        name -> name ∉ names(NB),
        (:BuilderState, :Pin, :ConnectionDef, :pin, Symbol("⟷"), Symbol("↔")),
    )
    @test all(name -> name ∉ names(NB), (:impedance, :cable, :overhead_line, :mmc, :tlc))
    @test WildcardBuilderAPI.shared_impedance_generic
    @test WildcardBuilderAPI.shared_loopgain_generic
    @test ReverseWildcardBuilderAPI.shared_impedance_generic
    @test ReverseWildcardBuilderAPI.shared_loopgain_generic

    result = ErgonomicBuilderAPI.impedance_study()
    @test result isa NB.ParametricImpedance
    @test length(result) == 2
    @test all(case -> size(case.impedance) == (1, 1, 2), result)
end

@testset "large impedance sample stacking" begin
    samples = Any[fill(complex(Float64(index)), 1, 1, 2) for index in 1:15_000]
    stacked = NB._stack_impedance_samples(samples)
    @test size(stacked) == (1, 1, 2, 15_000)
    @test stacked[:, :, :, 1] == first(samples)
    @test stacked[:, :, :, end] == last(samples)
end

@testset "Qualified component shadows" begin
    parent = PowerImpedance.impedance(z = 3.0, pins = 1)
    shadow = only(NB.impedance(z = 3.0, pins = 1))
    dispatched = only(PowerImpedance.impedance(NB.Grid; z = 3.0, pins = 1))
    @test shadow.element_model.value == parent.element_model.value
    @test shadow.input_pins == parent.input_pins
    @test shadow.output_pins == parent.output_pins
    @test shadow.transformation == parent.transformation
    @test shadow.connection == parent.connection
    @test dispatched.element_model.value == parent.element_model.value

    @test only(NB.PIControl(Kp = 2.0, Ki = 3.0)) ==
          PowerImpedance.PIControl(Kp = 2.0, Ki = 3.0)
    @test only(PowerImpedance.PIControl(NB.Grid; Kp = 2.0, Ki = 3.0)) ==
          PowerImpedance.PIControl(Kp = 2.0, Ki = 3.0)
    @test only(NB.ElectricalTLC(Lᵣ = 0.1, Rᵣ = 0.2)) ==
          PowerImpedance.ElectricalTLC(Lᵣ = 0.1, Rᵣ = 0.2)
    @test length(NB.SHADOW_CONSTRUCTOR_MANIFEST) >= 70
    @test length(unique(first, NB.SHADOW_CONSTRUCTOR_MANIFEST)) ==
          length(NB.SHADOW_CONSTRUCTOR_MANIFEST)
    @test all(entry -> isdefined(NB, first(entry)), NB.SHADOW_CONSTRUCTOR_MANIFEST)
    @test all(entry -> isdefined(PowerImpedance, first(entry)), NB.SHADOW_CONSTRUCTOR_MANIFEST)
    @test all(
        entry -> hasmethod(
            getfield(PowerImpedance, first(entry)),
            Tuple{typeof(NB.Grid)}
        ),
        NB.SHADOW_CONSTRUCTOR_MANIFEST
    )

    old_pi = PowerImpedance.PI_control(Kₚ = 1.0, Kᵢ = 2.0)
    @test only(NB.tlc(P = 1.0, pll = old_pi)) isa PowerImpedance.Element
    @test only(NB.mmc(P = 1.0, pll = old_pi)) isa PowerImpedance.Element
    @test_throws ArgumentError NB.tlc(P = 1.0, outerActive = NB.NoOuterActiveControl())
    @test_throws ArgumentError NB.mmc(P = 1.0, delta_control = NB.ΔdqControlGFL())
end

@testset "NetworkState Cartesian studies" begin
    elements = (
        z1 = NB.impedance(z = NB.Grid([1.0, 2.0]), pins = 1),
        z2 = NB.impedance(z = 3.0, pins = 1)
    )
    connections = (
        (node = :n1, element = :z1, side = 1, terminal = 1),
        (node = :n1, element = :z2, side = 1, terminal = 1),
        (node = :gnd, element = :z1, side = 2, terminal = 1),
        (node = :gnd, element = :z2, side = 2, terminal = 1),
    )
    builders = NB.define(elements, connections)
    @test builders isa NB.Gridspace{NB.NetworkState}
    @test length(builders) == 2
    @test [case.elements.z1.element_model.value[1] for case in builders] == [1, 2]

    result = PowerImpedance.determine_impedance(
        builders; nets = [:n1], freq_range = (1.0, 10.0, 3), seed = 11
    )
    @test result isa NB.ParametricImpedance
    @test length(result) == 2
    @test size(result[1].impedance) == (1, 1, 3)
    @test length(result[1].frequencies) == 3
    @test only(result[1].coordinates).first == (:elements, :z1, :z)

    solved = NB.solve(builders; seed = 11)
    @test solved isa NB.ParametricSolve
    @test length(solved) == 2
    @test all(case -> case.powerflow === nothing, solved)
end

@testset "Gridspace linearization cache dispatch" begin
    connections = (
        (node = :dc, element = :converter, side = 1, terminal = 1),
        (node = :dc, element = :zdc, side = 1, terminal = 1),
        (node = :gnd, element = :zdc, side = 2, terminal = 1),
        (node = :ac_d, element = :converter, side = 2, terminal = 1),
        (node = :ac_q, element = :converter, side = 2, terminal = 2),
    )

    passive_space = NB.define(
        (;
            converter = NB.tlc(elec = NB.ElectricalTLC(Lᵣ = 0.05)),
            zdc = NB.impedance(z = NB.Grid([1.0, 2.0]), pins = 1)
        ),
        connections
    )
    passive_a, passive_b = collect(passive_space)
    cache = NB._LinearizationCache(
        NB._operating_point_context(passive_a), nothing, Dict{Symbol, Any}()
    )
    @test NB._linearization_decision(passive_b, cache) isa NB._ReuseLinearization

    active_space = NB.define(
        (;
            converter = NB.tlc(
                elec = NB.ElectricalTLC(Lᵣ = NB.Grid([0.05, 0.06])),
            ),
            zdc = NB.impedance(z = 1.0, pins = 1)
        ),
        connections
    )
    active_a, active_b = collect(active_space)
    cache = NB._LinearizationCache(
        NB._operating_point_context(active_a), nothing, Dict{Symbol, Any}()
    )
    @test NB._linearization_decision(active_b, cache) isa NB._RefreshLinearization

    changed_topology = only(NB.define(
        (;
            converter = NB.tlc(elec = NB.ElectricalTLC(Lᵣ = 0.05)),
            zdc = NB.impedance(z = 1.0, pins = 1)
        ),
        (
            (node = :dc_changed, element = :converter, side = 1, terminal = 1),
            (node = :dc_changed, element = :zdc, side = 1, terminal = 1),
            (node = :gnd, element = :zdc, side = 2, terminal = 1),
            (node = :ac_d, element = :converter, side = 2, terminal = 1),
            (node = :ac_q, element = :converter, side = 2, terminal = 2),
        )
    ))
    @test NB._linearization_decision(changed_topology, cache) isa NB._RefreshLinearization
end
