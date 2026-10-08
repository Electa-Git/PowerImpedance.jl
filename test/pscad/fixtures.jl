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
end
