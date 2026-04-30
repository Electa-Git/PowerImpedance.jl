using PowerImpedanceACDC.NetworkBuilder: pin, ⟷

@testset "NetworkBuilder" begin
	legacy = @network begin
		z1 = impedance(z = 1, pins = 1)
		z2 = impedance(z = 2, pins = 1)

		z1[1.1] ⟷ z2[1.1] ⟷ n1
		z1[2.1] ⟷ z2[2.1] ⟷ gnd
	end

	elements = (; z1 = impedance(z = 1, pins = 1), z2 = impedance(z = 2, pins = 1))
	connections = (
		pin(:z1, 1.1) ⟷ pin(:z2, 1.1) ⟷ :n1,
		pin(:z1, 2.1) ⟷ pin(:z2, 2.1) ⟷ :gnd,
	)

	builder = NetworkBuilder.define(elements, connections)

	@test collect(keys(builder.network.elements)) == collect(keys(legacy.elements))
	@test Set(builder.network.nets[:n1]) == Set(legacy.nets[:n1])
	@test Set(builder.network.nets[:gnd]) == Set(legacy.nets[:gnd])
	@test builder.network.elements[:z1].pins == legacy.elements[:z1].pins
	@test builder.network.elements[:z2].pins == legacy.elements[:z2].pins

	@test NetworkBuilder.solve(builder).powerflow === nothing

	updated_elements = (; z1 = impedance(z = 3, pins = 1), z2 = impedance(z = 4, pins = 1))
	updated = NetworkBuilder.update!(builder; elements = updated_elements)

	@test updated.powerflow === nothing
	@test builder.network.elements[:z1].element_value.value == ComplexF64[3;;]
	@test Set(builder.network.nets[:n1]) == Set(legacy.nets[:n1])
end
