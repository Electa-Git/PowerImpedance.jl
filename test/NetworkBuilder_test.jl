using PowerImpedance.NetworkBuilder: powerflow_optimizer, is_bounded_options,
powerflow_setting, solve_acdcpf, get_y, NetworkModel
using LinearAlgebra
using PowerImpedance
using Test

if !isdefined(@__MODULE__, :PI)
	const PI = PowerImpedance
end
if !isdefined(@__MODULE__, :NB)
	const NB = PowerImpedance.NetworkBuilder
end

@testset "NetworkBuilder unit tests" begin

	elements = (; z1 = impedance(z = 1, conductors = 1),
        z2 = impedance(z = 2, conductors = 1))
	connections = (
        NB.Bus(:n1; ports = ((:z1, :side1), (:z2, :side1))),
        NB.Bus(:gnd; ports = ((:z1, :side2), (:z2, :side2))),
	)

	builder = NetworkBuilder.define(elements, connections)
	# A power flow needs a source, and this network has none.
	@test_throws Exception NetworkBuilder.solve(builder)

	updated_elements = (; z1 = impedance(z = 3, conductors = 1),
        z2 = impedance(z = 4, conductors = 1))
	updated = NetworkBuilder.update!(builder; elements = updated_elements)

	@test !hasproperty(updated, :operating_point)
	@test builder.elements[:z1].value == ComplexF64[3;;]

end


if !isdefined(@__MODULE__, :ieee39bus_elements)
    include("fixtures/ieee39bus.jl")
end

function build_ieee39bus_with_networkbuilder()

	builder_options = (;
		voltageBase = Vm1,
		power_flow = (;
			is_bounded = (;
				bus_voltage = true,
			),
		),
	)

	builder = NetworkBuilder.define(
		ieee39bus_elements(),
		ieee39bus_connections();
		options = builder_options,
        exclude = (:T8_9,),
	)
	solved = NetworkBuilder.solve(builder)
	return (; builder, solved)
end

function ieee39bus_with_nwbuilder_powerflow()
	builder_options = (;
		voltageBase = Vm1,
		power_flow = (;
			is_bounded = (;
				bus_voltage = true,
			),
		),
	)

	builder = NetworkBuilder.define(
		ieee39bus_elements(),
		ieee39bus_connections();
		options = builder_options,
        exclude = (:T8_9,),
	)

	data, _, elempitopm = convert(builder, PI.PMACDC)

    options = builder.options

    result = solve_acdcpf(
        data,
        PI._PM.ACPPowerModel,
        powerflow_optimizer(options),
        is_bounded_options(options);
        setting = powerflow_setting(options),
    )

	return (; builder, solved=(;data, result, elempitopm))
end

function determine_ieee39bus_impedance(network; freq_range = IEEE39_FREQ_RANGE)
    return NB.determine_impedance(
        network;
        nets = IEEE39_INPUT_PINS,
		elim_elements = IEEE39_ELIM_ELEMENTS,
		freq_range = freq_range,
	)
end

@testset "IEEE39bus NetworkBuilder power flow" begin
    sharedpf = build_ieee39bus_with_networkbuilder().solved
    direct_case = ieee39bus_with_nwbuilder_powerflow()
    newpf = direct_case.solved
    function dicts_approx_equal(dict1, dict2; atol = 1e-8)
        keys(dict1) == keys(dict2) || return false
        for key in keys(dict1)
            val1, val2 = dict1[key], dict2[key]
            if val1 isa AbstractDict && val2 isa AbstractDict
                dicts_approx_equal(val1, val2; atol) || return false
            elseif val1 isa Number && val2 isa Number
                isapprox(val1, val2; atol) || return false
            elseif !isequal(val1, val2)
                return false
            end
        end
        return true
    end
    @test sharedpf.result["termination_status"] == newpf.result["termination_status"]
    @test dicts_approx_equal(sharedpf.result["solution"], newpf.result["solution"])
    @test Set(keys(sharedpf.nodes2bus)) ==
        Set(direct_case.builder.topology.connections.net)
    @test sharedpf.operating_point isa OperatingPoint
end


@testset "NetworkBuilder drops endpoints of declared disconnected elements" begin
	elements = (;
		a = impedance(z = 1.0, conductors = 1),
		b = impedance(z = 2.0, conductors = 1),
		open_line = overhead_line(
			length = 1e3,
			conductors = Conductors(
				organization = :flat,
				nᵇ = 3,
				nˢᵇ = 1,
				Rᵈᶜ = 0.063,
				rᶜ = 0.015,
				yᵇᶜ = 30,
				Δyᵇᶜ = 0,
				Δxᵇᶜ = 10,
				Δ̃xᵇᶜ = 0,
				dˢᵇ = 0,
				dˢᵃᵍ = 10,
			),
			groundwires = Groundwires(
				nᵍ = 2,
				Rᵍᵈᶜ = 0.92,
				rᵍ = 0.0062,
				Δxᵍ = 6.5,
				Δyᵍ = 7.5,
				dᵍˢᵃᵍ = 10,
			),
			earth_parameters = (1, 1, 100),

		),
	)

	connections = (
        NB.Bus(:B; ports = ((:a, :side1), (:b, :side1))),
        NB.Bus(:Open; ports = ((:open_line, :side1),)),
        NB.Bus(:gnd; ports = ((:a, :side2), (:b, :side2))),
	)

	builder = NetworkBuilder.define(elements, connections; exclude = (:open_line,))
	@test !haskey(builder.elements, :open_line)
    rows = builder.topology.connections
    for name in (:a, :b)
        @test only(filter(r -> r.component == name && r.port == :side1, rows)).net == :B
        @test only(filter(r -> r.component == name && r.port == :side2, rows)).net == :gnd
    end
end
