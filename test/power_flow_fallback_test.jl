module PowerFlowFallbackTests
using PowerImpedance, Test

@testset "Classic power-flow fallback" begin
    # Isolate solver-stage dispatch used to force this otherwise solver-dependent
    # branch. The child calls the production power_flow body and native relaxation.
    script = raw"""
    using PowerImpedance, Test, Logging
    const PI = PowerImpedance
    Logging.global_logger(ConsoleLogger(stderr, Logging.Error))
    PI._PMACDC.silence()
    include(joinpath(pkgdir(PI), "test/pscad/fixtures.jl"))
    witness = PSCADFixtures.small_ac_network().classic
    witness_result = first(power_flow(witness))
    witness_setpoints = Dict(n => e.setpoint for (n, e) in witness.elements)
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
        net = PSCADFixtures.small_ac_network().classic
        result = first(@test_logs (:warn, r"termination status ITERATION_LIMIT.*maximum primal constraint violation") min_level=Logging.Warn power_flow(net))
        @test result["termination_status"] == PI.MOI.ITERATION_LIMIT
        @test result["primal_feasible"]
        @test result["solution"] == witness_result["solution"]
        @test solve_calls[] == 1

        state = PSCADFixtures.small_ac_network().state
        data = first(convert(state, PI.PMACDC))
        original = deepcopy(data)
        options = (; power_flow = (; optimizer = (; constr_viol_tol = 1e-7)))
        NB = PI.NetworkBuilder
        result = @test_logs (:warn, r"termination status ITERATION_LIMIT.*constr_viol_tol = 1.0e-7") min_level=Logging.Warn NB.solve_acdcpf(
            data, PI._PM.ACPPowerModel, NB.powerflow_optimizer(options),
            NB.is_bounded_options(options); setting = NB.powerflow_setting(options))
        @test result["termination_status"] == PI.MOI.ITERATION_LIMIT
        @test result["primal_feasible"]
        @test isequal(data, original)
        @test solve_calls[] == 2
    end
    @testset "Primal feasibility uses the configured inclusive threshold" begin
        model = PI.JuMP.Model(PI.JuMP.optimizer_with_attributes(PI.Ipopt.Optimizer,
            "print_level" => 0, "max_iter" => 0, "constr_viol_tol" => 0.5))
        PI.JuMP.@variable(model, x, start = 0.0)
        PI.JuMP.@constraint(model, x == 1.0)
        result = Dict{String, Any}("termination_status" => PI.MOI.ITERATION_LIMIT)
        @test !PI.accept_feasible_power_flow!(result, model) # No returned point.
        PI.JuMP.optimize!(model)
        @test maximum(values(PI.JuMP.primal_feasibility_report(model))) == 1.0
        @test_logs min_level=Logging.Warn @test !PI.accept_feasible_power_flow!(result, model)
        @test !haskey(result, "primal_feasible")
        PI.JuMP.set_optimizer_attribute(model, "constr_viol_tol", 1.0)
        PI.JuMP.optimize!(model)
        @test_logs (:warn, r"termination status ITERATION_LIMIT.*violation 1.0") min_level=Logging.Warn @test PI.accept_feasible_power_flow!(result, model)
        @test result["termination_status"] == PI.MOI.ITERATION_LIMIT
        @test result["primal_feasible"]
    end
    force_status[] = false
    const initial_calls = Ref(0)
    const fallback_calls = Ref(0)
    const fallback_mode = Ref(:native)

    @eval PI function solve_acdcpf(data::Dict{String, Any},
            ::Type{_PM.ACPPowerModel}, optimizer::JuMP.MOI.OptimizerWithAttributes;
            kwargs...)
        Main.initial_calls[] += 1
        return Dict("termination_status" => MOI.ITERATION_LIMIT)
    end
    @eval PI function solve_acdcpf_relax(data::Dict{String, Any},
            model_type::Type{_PM.ACPPowerModel},
            optimizer::JuMP.MOI.OptimizerWithAttributes; kwargs...)
        Main.fallback_calls[] += 1
        if Main.fallback_mode[] === :native
            return invoke(solve_acdcpf_relax, Tuple{Dict{String, Any}, Type, Any},
                data, model_type, optimizer; kwargs...)
        elseif Main.fallback_mode[] === :accepted
            return Main.witness_result
        end
        return Dict("termination_status" => MOI.ITERATION_LIMIT)
    end

    @testset "Native relaxation rejects violated constraints" begin
        net = PSCADFixtures.small_ac_network().classic
        # An isolated PV generator prescribes nonzero active power, while its
        # bus balance requires zero: relaxation cannot make this case feasible.
        add!(net, :isolated, synchronousmachine(;
            setpoint = Setpoint(Vac = 380sqrt(2 / 3), Pac = 100.0),
            elec = ElectricalSM(Vᵃᶜ_base = 380.0)))
        for terminal in 1:2
            connect!(net, (:isolated, Symbol("1.$terminal")), Symbol("isolated$terminal"))
            connect!(net, (:isolated, Symbol("2.$terminal")), :gnd)
        end
        connect!(net)
        declared = Dict(n => e.setpoint for (n, e) in net.elements)
        error = try
            power_flow(net)
            nothing
        catch exception
            exception
        end
        @test error isa ErrorException
        @test sprint(showerror, error) == "Power flow constraints are violated."
        @test (initial_calls[], fallback_calls[]) == (1, 1)
        @test isequal(declared, Dict(n => e.setpoint for (n, e) in net.elements))
    end
    @testset "Accepted fallback updates setpoints" begin
        fallback_mode[] = :accepted
        net = PSCADFixtures.small_ac_network().classic
        result = first(power_flow(net))
        @test result === witness_result
        @test result["termination_status"] == PI.MOI.LOCALLY_SOLVED
        @test (initial_calls[], fallback_calls[]) == (2, 2)
        @test isequal(witness_setpoints, Dict(n => e.setpoint for (n, e) in net.elements))
    end
    @testset "Unsuccessful fallback preserves setpoints" begin
        fallback_mode[] = :failed
        net = PSCADFixtures.small_ac_network().classic
        declared = Dict(n => e.setpoint for (n, e) in net.elements)
        error = try
            power_flow(net)
            nothing
        catch exception
            exception
        end
        @test error isa ErrorException
        @test sprint(showerror, error) == "Second iteration not succesful. Check your formulation"
        @test (initial_calls[], fallback_calls[]) == (3, 3)
        @test isequal(declared, Dict(n => e.setpoint for (n, e) in net.elements))
    end
    """
    command = `$(Base.julia_cmd()) --startup-file=no --project=$(dirname(Base.active_project())) -e $script`
    @test success(pipeline(command; stdout = stdout, stderr = stderr))
end
end
