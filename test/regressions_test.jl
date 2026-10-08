@testset "Three-phase classification of untransformed six-pin elements" begin
    abc_branch = impedance(z = s -> 1.0 + 0.01s, pins = 3)
    @test PI.is_three_phase(abc_branch)
    @test PI.pmtype(abc_branch) == "branch"
    @test all(port -> port.domain == 1, NB._port_descriptions(abc_branch))

    abc_source = ac_source(pins = 3)
    @test PI.is_three_phase(abc_source)
    @test PI.pmtype(abc_source) == "gen"

    dq_branch = impedance(z = s -> 1.0, pins = 3, transformation = true)
    @test PI.is_three_phase(dq_branch)

    dc_branch = impedance(z = s -> 1.0, pins = 1)
    @test !PI.is_three_phase(dc_branch)
    @test PI.pmtype(dc_branch) == "branchdc"
end
