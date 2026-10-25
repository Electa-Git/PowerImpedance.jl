
Vm=380/sqrt(3)

source_ac = ac_source(v = Vm*sqrt(2))
source_dc = dc_source(v = 2Vm)

ABCD_analytical_AC=Diagonal(fill(ComplexF64(1), 6))
ABCD_analytical_DC=Diagonal(fill(ComplexF64(1), 2))

@test ABCD_analytical_AC≈PowerImpedance.eval_abcd(source_ac, 1im) rtol=1e-9 atol=1e-9
@test ABCD_analytical_DC≈PowerImpedance.eval_abcd(source_dc, 1im) rtol=1e-9 atol=1e-9

@testset "DC source pole-to-pole voltage" begin
    source = dc_source(v = 640.0)
    state = NetworkBuilder.define((; source),
        (NetworkBuilder.Bus(:DC; ports = ((:source, :dc),)),);
        options = (; voltageBase = 320.0))
    for poles in (1, 2)
        data, bases, _ = convert(state, PowerImpedance.PMACDC)
        data["dcpol"] = poles
        PowerImpedance.convert!(data, source, PowerImpedance.PMACDC,
            (; name = :source, index = 1, pmtype = "gendc"),
            (dc = 1,), bases)
        @test data["gendc"]["1"]["vgdc"] === 640.0 / (poles * 320.0)
    end
end
