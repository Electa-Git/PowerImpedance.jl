using Random
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
    atomic = NB.impedance(z = matrix, pins = 2)
    @test length(atomic) == 1
    @test only(atomic).element_model.value == matrix

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
