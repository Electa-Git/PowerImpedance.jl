module PowerFlowFallbackTests
using PowerImpedance, Test

@testset "NetworkBuilder power-flow fallback" begin
    script = raw"""
    using PowerImpedance, Test, Logging
    const PI = PowerImpedance
    const NB = PI.NetworkBuilder
    Logging.global_logger(ConsoleLogger(stderr, Logging.Error))
    PI._PMACDC.silence()
    include(joinpath(pkgdir(PI), "test/pscad/fixtures.jl"))
    const force_status = Ref(true)
    const solve_calls = Ref(0)
    # Change only the reported label of real solved models, so acceptance and
    # the absence of retries/fallback do not depend on Ipopt's version.
    @eval PI._IM function build_result(pm::Main.PI._PM.ACPPowerModel, solve_time;
            solution_processors = [])
        result = invoke(build_result, Tuple{AbstractInfrastructureModel, Any},
            pm, solve_time; solution_processors)
        Main.solve_calls[] += 1
        if Main.force_status[]
            result["termination_status"] = Main.PI.MOI.ITERATION_LIMIT
        end
        return result
    end
    @testset "Feasible points retain their status and skip fallback" begin
        state = PSCADFixtures.small_ac_network()
        data = first(convert(state, PI.PMACDC))
        original = deepcopy(data)
        options = (; power_flow = (; optimizer = (; constr_viol_tol = 1e-7)))
        NB = PI.NetworkBuilder
        result = @test_logs(
            (:warn, r"termination status ITERATION_LIMIT.*constr_viol_tol = 1.0e-7"),
            min_level=Logging.Warn,
            NB.solve_acdcpf(data, PI._PM.ACPPowerModel, NB.powerflow_optimizer(options),
                NB.is_bounded_options(options); setting = NB.powerflow_setting(options)))
        @test result["termination_status"] == PI.MOI.ITERATION_LIMIT
        @test result["primal_feasible"]
        @test isequal(data, original)
        @test solve_calls[] == 1
    end
    @testset "Primal feasibility uses the configured inclusive threshold" begin
        model = PI.JuMP.Model(PI.JuMP.optimizer_with_attributes(PI.Ipopt.Optimizer,
            "print_level" => 0, "max_iter" => 0, "constr_viol_tol" => 0.5))
        PI.JuMP.@variable(model, x, start = 0.0)
        PI.JuMP.@constraint(model, x == 1.0)
        result = Dict{String, Any}("termination_status" => PI.MOI.ITERATION_LIMIT)
        @test !NB.accept_feasible_power_flow!(result, model) # No returned point.
        PI.JuMP.optimize!(model)
        @test maximum(values(PI.JuMP.primal_feasibility_report(model))) == 1.0
        @test_logs min_level=Logging.Warn @test !NB.accept_feasible_power_flow!(
            result, model)
        @test !haskey(result, "primal_feasible")
        PI.JuMP.set_optimizer_attribute(model, "constr_viol_tol", 1.0)
        PI.JuMP.optimize!(model)
        @test_logs(
            (:warn, r"termination status ITERATION_LIMIT.*violation 1.0"),
            min_level=Logging.Warn,
            @test NB.accept_feasible_power_flow!(result, model))
        @test result["termination_status"] == PI.MOI.ITERATION_LIMIT
        @test result["primal_feasible"]
    end
    force_status[] = false
    const fallback_calls = Ref(0)
    @eval NB function solve_acdcpf_relax(data::Dict{String, Any},
            model_type::Type{Main.PI._PM.ACPPowerModel},
            optimizer::Main.PI.JuMP.MOI.OptimizerWithAttributes,
            variables::NamedTuple; kwargs...)
        Main.fallback_calls[] += 1
        return invoke(solve_acdcpf_relax,
            Tuple{Dict{String, Any}, Type, Any, NamedTuple},
            data, model_type, optimizer, variables; kwargs...)
    end

    @testset "Native relaxation reports violated constraints" begin
        state = PSCADFixtures.small_ac_network()
        # An isolated PV generator prescribes nonzero active power, while its
        # bus balance requires zero: relaxation cannot make this case feasible.
        machine = synchronousmachine(Vᵃᶜ_base = 380.0, elec = ElectricalSM())
        b = bases(machine)
        machine = component(machine;
            powerflow = (p = 100.0 / b.S, v = (380sqrt(2 / 3)) / b.v_ac))
        declarations = (PSCADFixtures._small_ac_circuit().rows...,
            NB.Bus(:isolated; ports = ((:isolated, :ac),)))
        state = NB.define(merge(state.elements, (; isolated = machine)), declarations;
            options = state.options)
        declared = map(inputvalues, state.elements)
        logger = Test.TestLogger(; min_level = Logging.Warn)
        solved = with_logger(logger) do
            compute(PowerFlowProblem(state), ACDCPowerFlow())
        end
        @test fallback_calls[] == 1
        @test any(log -> occursin("Relaxing constraints", string(log.message)), logger.logs)
        @test any(log -> occursin("is violated by", string(log.message)), logger.logs)
        @test declared == map(inputvalues, state.elements)
    end
    """
    command = `$(Base.julia_cmd()) --startup-file=no
        --project=$(dirname(Base.active_project())) -e $script`
    @test success(pipeline(command; stdout = stdout, stderr = stderr))
end
end
