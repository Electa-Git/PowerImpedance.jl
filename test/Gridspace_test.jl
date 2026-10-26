using Random

const NB = PowerImpedance.NetworkBuilder
using PowerImpedance.NetworkBuilder: @gridspace, @relax

struct GridspacePoint
    x::Any
    y::Any
end

@gridspace struct GridspaceMacroExample{T <: Real}
    x::T
    y::T = 2
end

@relax struct RelaxMacroExample{T <: Real}
    x::T
    y::T
end

@testset "Canonical Grid and Gridspace grammar" begin
    @test Grid === PowerImpedance.Grammar.Grid === NB.Grid
    @test Gridspace === PowerImpedance.Grammar.Gridspace === NB.Gridspace
    @test configurations === PowerImpedance.Grammar.configurations === NB.configurations
    @test materialize === PowerImpedance.Grammar.materialize === NB.materialize
    @test collect(Grid(1)) == [1]
    @test collect(Grid((1, "two", 3 + 4im))) == [1, "two", 3 + 4im]
    @test size(Grid(1:3)) == (3,)

    product = Gridspace{GridspacePoint}(
        GridspacePoint,
        (Grid([1, 2]), Grid([10, 20])),
        (:x, :y)
    )
    @test [(value.x, value.y) for value in product] ==
          [(1, 10), (2, 10), (1, 20), (2, 20)]
    @test configuration_manifest.(collect(configurations(product))) == [
        (x = 1, y = 10),
        (x = 2, y = 10),
        (x = 1, y = 20),
        (x = 2, y = 20)
    ]

    zipped = Gridspace{GridspacePoint}(
        GridspacePoint,
        (Grid([1, 2]), Grid([10, 20])),
        (:x, :y);
        combine = :zip
    )
    @test [(value.x, value.y) for value in zipped] == [(1, 10), (2, 20)]

    broadcast_zip = Gridspace{GridspacePoint}(
        GridspacePoint,
        (Grid([1, 2]), Grid(10)),
        (:x, :y);
        combine = :zip
    )
    @test [(value.x, value.y) for value in broadcast_zip] == [(1, 10), (2, 10)]
    @test_throws DimensionMismatch collect(Gridspace{GridspacePoint}(
        GridspacePoint,
        (Grid([1, 2]), Grid([10, 20, 30])),
        (:x, :y);
        combine = :zip
    ))

    shared = Grid([1, 2])
    identity_coupled = Gridspace{GridspacePoint}(
        GridspacePoint,
        (shared, shared),
        (:x, :y)
    )
    @test [(value.x, value.y) for value in identity_coupled] == [(1, 1), (2, 2)]

    named_coupled = Gridspace{GridspacePoint}(
        GridspacePoint,
        (Grid([1, 2]; key = :shared), Grid([10, 20]; key = :shared)),
        (:x, :y)
    )
    @test [(value.x, value.y) for value in named_coupled] == [(1, 10), (2, 20)]

    inner = Gridspace{Tuple}((x, y) -> (x, y), (Grid([1, 2]), 3), (:x, :y))
    nested = Gridspace{Tuple}((pair, z) -> (pair..., z), (inner, Grid([4, 5])),
        (:pair, :z))
    @test collect(nested) == [(1, 3, 4), (2, 3, 4), (1, 3, 5), (2, 3, 5)]

    matrix = [1.0 2.0; 3.0 4.0]
    atomic = @inferred impedance(Grid; z = matrix, conductors = 2)
    @test length(atomic) == 1
    @test only(atomic).value == matrix
    @test eltype(atomic) === PowerImpedance.Impedance
    @test !isdefined(NB, :impedance)

    varying = @inferred impedance(Grid; z = Grid((1.0, 2.0)), conductors = 1)
    fixed = impedance(z = 3.0, conductors = 1)
    mixed_connections = (
        NB.Bus(:bus; ports = ((:varying, :side1), (:fixed, :side1))),
        NB.Bus(:gnd; ports = ((:varying, :side2), (:fixed, :side2)))
    )
    networks = @inferred NB.define((; varying, fixed), mixed_connections)
    @test networks isa Gridspace{NB.NetworkState}
    @test length(networks) == 2
    @test all(network -> network.elements.fixed === fixed, networks)
    @test @inferred(PowerFlowProblem(networks)) isa
          Gridspace{PowerFlowProblem{NB.NetworkState}}

    converters = @inferred mmc(Grid; Sbase = Grid([500.0, 1000.0]),
        sync = PLLSynchronization(),
        delta_control = ΔdqControlGFL(outer_active = OuterActivePowerControl(),
            outer_reactive = OuterReactiveQControl(), occ = InnerCurrentPIControl()),
        sigma_control = ΣdqzControlTEC())
    @test converters isa Gridspace{MMC}
    @test all(model -> model isa MMC, converters)
    @test [bases(model).S for model in converters] == [500.0, 1000.0]

    for (constructor, keyword) in ((tlc, :Sbase),
        (synchronousmachine, :S_base), (inductionmachine, :S_base))
        models = constructor(Grid; NamedTuple{(keyword,)}((Grid([500.0, 1000.0]),))...)
        @test [bases(model).S for model in models] == [500.0, 1000.0]
    end

    macro_grid = GridspaceMacroExample(x = Grid([1, 2]))
    @test [(case.x, case.y) for case in macro_grid] == [(1, 2), (2, 2)]
    @test RelaxMacroExample(1, 2.5) == RelaxMacroExample{Float64}(1, 2.5)

    uncertain = Gridspace{GridspacePoint}(
        GridspacePoint,
        (Grid(10.0, 5.0; key = :shared), Grid(20.0, 5.0; key = :shared)),
        (:x, :y)
    )
    @test has_uncertainty(uncertain)
    configuration = only(configurations(uncertain))
    first_draw = rand(Xoshiro(42), configuration; distribution = :normal)
    second_draw = rand(Xoshiro(42), configuration; distribution = :normal)
    @test first_draw == second_draw
    @test (first_draw.x - 10) / 0.5 == (first_draw.y - 20) / 1.0
    @test_throws ArgumentError rand(Xoshiro(1), configuration; distribution = :cauchy)
    @test_throws ArgumentError Grid(1.0, -1.0)
    @test_throws ArgumentError Grid(1.0, AbsoluteError(-1.0))
end

@testset "NetworkBuilder grammar identity and retired names" begin
    grammar_names = (
        :AbstractProblemDefinition,
        :AbstractFormulation,
        :AbstractProblemResult,
        :AbstractParametricResult,
        :AbstractUncertaintyResult,
        :compute,
        :primitives,
        :preprocess,
        :ParametricProblem,
        :Combinatorial,
        :LinearError,
        :MonteCarlo,
        :ParametricResult,
        :LinearErrorResult,
        :MonteCarloResult
    )
    @test all(name -> getfield(NB, name) === getfield(PowerImpedance.Grammar, name),
        grammar_names)
    retired = (
        :ImpedanceCase,
        :ParametricImpedance,
        :SolveCase,
        :ParametricSolve,
        :FrequencyResponseCase,
        :ParametricFrequencyResponse,
        :StabilityCase,
        :ParametricStability,
        :UQuantProblem,
        :sampled_frequency_response
    )
    @test all(name -> name ∉ names(NB; all = true), retired)
end
