

Vm=380/sqrt(3)

grid = Network()

add!(
	grid,
	:labanimal_AC,
	ac_source(pins = 3, setpoint=Setpoint(Vac = Vm), transformation = true)
)

add!(
	grid,
	:labanimal_DC,
	dc_source(pins = 1, setpoint=Setpoint(Vdc = Vm))
)


ABCD_analytical_AC=Diagonal(fill(ComplexF64(1), 6))
ABCD_analytical_DC=Diagonal(fill(ComplexF64(1), 2))


@test ABCD_analytical_AC ≈ PowerImpedance.eval_abcd(grid.elements[:labanimal_AC].element_model, 1im) rtol = 1e-9 atol = 1e-9
@test ABCD_analytical_DC ≈ PowerImpedance.eval_abcd(grid.elements[:labanimal_DC].element_model, 1im) rtol = 1e-9 atol = 1e-9