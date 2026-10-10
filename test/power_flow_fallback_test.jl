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
