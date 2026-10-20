

Vm=380/sqrt(3)

grid = Network()

add!(
	grid,
	:labanimal_AC,
	ac_source(pins = 3, setpoint=Setpoint(Vac = Vm*sqrt(2)), transformation = true)
)

add!(
	grid,
	:labanimal_DC,
	dc_source(pins = 1, setpoint = Setpoint(Vdc = 2Vm))
)


ABCD_analytical_AC=Diagonal(fill(ComplexF64(1), 6))
ABCD_analytical_DC=Diagonal(fill(ComplexF64(1), 2))


@test ABCD_analytical_AC ≈ PowerImpedance.eval_abcd(grid.elements[:labanimal_AC].element_model, 1im) rtol = 1e-9 atol = 1e-9
@test ABCD_analytical_DC ≈ PowerImpedance.eval_abcd(grid.elements[:labanimal_DC].element_model, 1im) rtol = 1e-9 atol = 1e-9

@testset "DC source pole-to-pole voltage" begin
    bases = PowerImpedance.PowerModelsACDC._get_pu_bases(1000, 320.0)
    for poles in (1, 2)
        data = PowerImpedance.data_init!(Dict{String, Any}(), bases)
        data["dcpol"] = poles
        data["busdc"]["1"] = Dict{String, Any}("busdc_i" => 1, "bus_type" => 1)
        source = dc_source(setpoint = Setpoint(Vdc = 640.0), V = 636.0)
        PowerImpedance.convert!(data, source, PowerImpedance.PMACDC, 1, (1,), bases)
        @test data["gendc"]["1"]["vgdc"] === 640.0 / (poles * 320.0)
        @test data["busdc"]["1"]["Vdc"] === 636.0 / (poles * 320.0)
        @test data["busdc"]["1"]["Vdcmax"] === 1.1 * (636.0 / (poles * 320.0))
        @test data["busdc"]["1"]["Vdcmin"] === 0.9 * (636.0 / (poles * 320.0))
    end
end
