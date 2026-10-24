module PSCADDCEquivalenceTests
import ..PSCADFixtures
using Test, PowerImpedance, LinearAlgebra
using ..PSCADFixtures: dc_network
const P = PowerImpedance

@testset "DC differential series and shunt pole circuits" begin
    # Independent two-conductor ABCD circuits, reduced with the package's
    # physical differential transformation, never the exporter's scale helper.
    for z in (s -> 2.0 + s * 0.05, s -> 400.0,
            s -> inv(inv(400.0) + s * 1e-6)),
        omega in (1e-6, 2π * 50)

        s = ComplexF64(im * omega)
        differential = P.eval_abcd(impedance(; z, pins = 1).element_model, s)
        poles = P.eval_abcd(impedance(; z = t -> z(t) / 2, pins = 2).element_model, s)
        @test P.transformation_dc(poles)≈differential rtol=1e-12 atol=1e-12
        identity = Matrix{ComplexF64}(I, 2, 2)
        shunt_poles = [identity zeros(ComplexF64, 2, 2);
                       Diagonal(fill(2 / z(s), 2)) identity]
        @test P.transformation_dc(shunt_poles)≈ComplexF64[1 0; inv(z(s)) 1] rtol=1e-12 atol=1e-12
    end
end

@testset "DC fixture solved power and pole circuit" begin
    classic = dc_network()
    pf = PSCADFixtures.solved_powerflow(classic)
    result, data, elem2comp = pf.result, pf.data, pf.elem2comp
    @test string(result["termination_status"]) == "LOCALLY_SOLVED"
    _, index = elem2comp[:line]
    branch = data["branchdc"][string(index)]
    flow = result["solution"]["branchdc"][string(index)]
    from = result["solution"]["busdc"][string(branch["fbusdc"])]["vm"] * 320
    to = result["solution"]["busdc"][string(branch["tbusdc"])]["vm"] * 320
    current = (from - to) / 1.0 # one ohm per pole, kV / ohm = kA
    @test from ≈ 320.0 rtol = 1e-9
    @test to ≈ 318.0 rtol = 1e-9
    @test current ≈ 2.0 rtol = 1e-9
    @test (flow["pf"] + flow["pt"]) * 1000 ≈ 2 * current^2 rtol = 1e-6
    @test abs(flow["pf"]) * 1000 / (2from) ≈ current rtol = 1e-6
    @test abs(flow["pt"]) * 1000 / (2to) ≈ current rtol = 1e-6
end
end
