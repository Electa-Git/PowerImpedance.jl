module PSCADFixtures
using PowerImpedance

"""
    small_ac_network()

Return `(classic, state)` representations of the same balanced 50 Hz circuit:
a 380 kV line-to-line RMS source, a 0.19 Ω / 0.0122 H series branch and a
400 Ω per-phase shunt load. Both use a phase RMS voltage base of `380/sqrt(3)`
kV. Source setpoints are phase peak kV with zero cosine-reference angle.
"""
function small_ac_network()
    voltage = 380 / sqrt(3)
    elements = (;
        source = ac_source(; pins = 3, transformation = true,
            setpoint = Setpoint(Vac = voltage * sqrt(2), θac = 0.0)),
        line = impedance(; z = s -> 0.19 + s * 0.0122, pins = 3, transformation = true),
        load = impedance(; z = s -> 400.0, pins = 3, transformation = true))
    rows = [(node = Symbol(bus * suffix), element = name, side = side, terminal = terminal)
            for (name, side, bus) in ((:source, 1, "B1"), (:line, 1, "B1"),
        (:line, 2, "B2"), (:load, 1, "B2"))
            for (terminal, suffix) in enumerate(("d", "q"))]
    append!(rows, [(node = :gnd, element = :load, side = 2, terminal = terminal)
                   for terminal in 1:2])
    state = NetworkBuilder.define(deepcopy(elements), rows; options = (;
        voltageBase = voltage))
    classic = Network()
    classic.voltageBase[1] = voltage
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for terminal in 1:2
        connect!(classic, (:source, Symbol("2.$terminal")), :gnd)
    end
    connect!(classic)
    return (; classic, state)
end

"""
    passive_ohl_network()

Return `(classic, state)` representations of the small AC fixture with the
25 km `tl1` overhead line from `examples/P2P_HVDC_ALT.jl` replacing the series
impedance. Both declare `voltageBase = 380/sqrt(3)` kV phase RMS.
"""
function passive_ohl_network()
    classic, state = small_ac_network()
    tl1 = overhead_line(length = 25e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1,
            Rᵈᶜ = 0.063,
            rᶜ = 0.015, yᵇᶜ = 30,
            Δyᵇᶜ = 0, Δxᵇᶜ = 10, Δ̃xᵇᶜ = 0, dˢᵇ = 0, dˢᵃᵍ = 10),
        groundwires = Groundwires(
            nᵍ = 2,
            Rᵍᵈᶜ = 0.92,
            rᵍ = 0.0062,
            Δxᵍ = 6.5,
            Δyᵍ = 7.5,
            dᵍˢᵃᵍ = 10
        ),
        earth_parameters = (1, 1, 100), transformation = true)
    # Retain the fixture's designator and connectivity in both representations.
    # Each representation owns its element; solving classic may mutate setpoints.
    tl1.symbol = :line
    tl1.pins = copy(classic.elements[:line].pins)
    classic.elements[:line] = tl1
    elements = merge(state.elements, (; line = deepcopy(tl1)))
    rows = [(; row.node, row.element, row.side, row.terminal)
            for row in state.topology.connections]
    builder = NetworkBuilder.define(elements, rows;
        options = (; voltageBase = 380 / sqrt(3)))
    return (; classic, state = builder)
end

"""
    transformer_network(; organization = :YY, Rₘ = 1e6, Lₘ = 1000.0)

Return classic and builder circuits with a 380/150 kV LL transformer and a
400 Ω per-phase secondary load. Use the winding values from Transformer_test:
Rₚ = 10 Ω, Lₚ = 0.1 H, Rₛ = 1 Ω, Lₛ = 0.05 H. The default magnetizing branch
draws about 1 % of the load current; `Rₘ = 1e4, Lₘ = 10.0` reproduces the
Transformer_test stress values, whose large magnetizing current exposes the
power-flow pi-model approximation of the T-model.
Both representations declare 380/sqrt(3) kV phase RMS as the common base.
"""
function transformer_network(; organization = :YY, Rₘ = 1e6, Lₘ = 1000.0)
    classic, state = small_ac_network()
    winding = transformer(; pins = 3, transformation = true, organization,
        n = 380 / 150, Rₚ = 10.0, Lₚ = 0.1, Rₛ = 1.0, Lₛ = 0.05,
        Rₘ, Lₘ, Cₜ = 0.0, Cₛ = 0.0)
    winding.symbol = :line
    winding.pins = copy(classic.elements[:line].pins)
    classic.elements[:line] = winding
    elements = merge(state.elements, (; line = deepcopy(winding)))
    rows = [(; row.node, row.element, row.side, row.terminal)
            for row in state.topology.connections]
    builder = NetworkBuilder.define(elements, rows;
        options = (; voltageBase = 380 / sqrt(3)))
    return (; classic, state = builder)
end

"""
    dc_network()

Return classic and builder representations of two DC voltage sources at 320
and 318 kV pole-to-ground, joined by the differential series impedance
2 + s*0.05 Ω. The common base is 320 kV. An independent AC slack island
supports the classic power-flow solve; a 400 Ω AC shunt also makes that island
materializable by NetworkBuilder. Grounded DC shunts currently become
ordinary nonzero-voltage buses in that solver, so this fixture omits them.
"""
function dc_network()
    elements = (;
        ac = ac_source(; pins = 3, transformation = true,
            setpoint = Setpoint(Vac = 320sqrt(2), θac = 0.0)),
        from = dc_source(; setpoint = Setpoint(Vdc = 640.0)),
        to = dc_source(; setpoint = Setpoint(Vdc = 636.0)),
        line = impedance(; z = s -> 2.0 + s * 0.05, pins = 1),
        ac_load = impedance(; z = s -> 400.0, pins = 3, transformation = true))
    rows = [(node = Symbol("AC$k"), element, side = 1, terminal = k)
            for element in (:ac, :ac_load) for k in 1:2]
    append!(rows, [(node = :gnd, element = :ac_load, side = 2, terminal = k) for k in 1:2])
    for (element, side, node) in ((:from, 1, :D1), (:to, 1, :D2),
        (:line, 1, :D1), (:line, 2, :D2))
        push!(rows, (; node, element, side, terminal = 1))
    end
    state = NetworkBuilder.define(deepcopy(elements), rows; options = (;
        voltageBase = 320.0))
    classic = Network()
    classic.voltageBase[1] = 320.0
    for (name, element) in pairs(elements)
        add!(classic, name, element)
    end
    for row in rows
        connect!(classic, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for (name, count) in ((:ac, 2), (:from, 1), (:to, 1)), k in 1:count

        connect!(classic, (name, Symbol("2.$k")), :gnd)
    end
    connect!(classic)
    return (; classic, state)
end

"""
    dc_cable_network()

Return the M2 DC circuit with the two-position `ugc` cable from
`examples/P2P_HVDC_ALT.jl` as its 50 km DC branch. Layer and earth parameters
are copied from the example (rho = 100 Ω·m); both ends retain the transformed
differential terminal and grounded internal-conductor elimination.
"""
function dc_cable_network()
    classic, state = dc_network()
    ugc = cable(
        length = 50e3,
        positions = [(-0.5, 1), (0.5, 1)],
        C1 = Conductor(rₒ = 0.02622, ρ = 2.354e-8, μᵣ = 1.035),
        I1 = Insulator(rᵢ = 0.02622, rₒ = 0.06006, ϵᵣ = 2.67, μᵣ = 1.469),
        C2 = Conductor(rᵢ = 0.06006, rₒ = 0.06336, ρ = 2.14e-7, μᵣ = 1.0),
        I2 = Insulator(rᵢ = 0.06336, rₒ = 0.06636, ϵᵣ = 2.3, μᵣ = 1.0),
        C3 = Conductor(rᵢ = 0.06636, rₒ = 0.06651, ρ = 2.826e-8, μᵣ = 1.0),
        I3 = Insulator(rᵢ = 0.06651, rₒ = 0.07256, ϵᵣ = 2.3, μᵣ = 1.0),
        earth_parameters = (1, 1, 100.0),
        transformation = true
    )
    ugc.symbol = :line
    ugc.pins = copy(classic.elements[:line].pins)
    classic.elements[:line] = ugc
    elements = merge(state.elements, (; line = deepcopy(ugc)))
    rows = [(; row.node, row.element, row.side, row.terminal)
            for row in state.topology.connections]
    builder = NetworkBuilder.define(elements, rows; options = state.options)
    return (; classic, state = builder)
end

end
